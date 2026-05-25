#!/usr/bin/env python3
"""Infer conservative terrain tags for accepted DEM kernels.

The goal is not to magically classify every coordinate-named DEM into a biome.
This produces conservative geomorphic tags and a runtime-family hint with a
confidence score so future promotion tools can avoid one giant uncategorized
bucket without overwriting the reviewed source catalog.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "catalog" / "accepted_kernel_catalog.json"
DEFAULT_OUT = ROOT / "factory" / "catalog" / "kernel_inferred_tags.json"
DEFAULT_ENRICHED = ROOT / "factory" / "catalog" / "accepted_kernel_catalog_tagged.json"

KNOWN_FAMILIES = {
    "badlands",
    "coast",
    "desert",
    "glacial",
    "grassland",
    "karst",
    "mountain",
    "rainforest",
    "volcanic",
    "wetland",
    "temperate",
    "tundra",
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def center_lat(bounds: list[float]) -> float | None:
    if len(bounds) != 4:
        return None
    return (float(bounds[1]) + float(bounds[3])) * 0.5


def center_lon(bounds: list[float]) -> float | None:
    if len(bounds) != 4:
        return None
    return (float(bounds[0]) + float(bounds[2])) * 0.5


def geographic_bounds_center(bounds: list[float]) -> tuple[float | None, float | None, str | None]:
    if len(bounds) != 4:
        return None, None, None
    left, bottom, right, top = [float(value) for value in bounds]
    if -180.0 <= left <= 180.0 and -180.0 <= right <= 180.0 and -90.0 <= bottom <= 90.0 and -90.0 <= top <= 90.0:
        return center_lat(bounds), center_lon(bounds), "source_bounds"
    return None, None, None


def path_coordinate_center(source_path: str) -> tuple[float | None, float | None, str | None]:
    values = [float(value) for value in re.findall(r"(?<!\d)([+-]\d+(?:\.\d+)?)", source_path)]
    if len(values) < 4:
        return None, None, None
    lon1, lat1, lon2, lat2 = values[-4:]
    if -180.0 <= lon1 <= 180.0 and -180.0 <= lon2 <= 180.0 and -90.0 <= lat1 <= 90.0 and -90.0 <= lat2 <= 90.0:
        return (lat1 + lat2) * 0.5, (lon1 + lon2) * 0.5, "source_path_coordinates"
    return None, None, None


def geographic_center(kernel: dict[str, Any], bounds: list[float]) -> tuple[float | None, float | None, str | None]:
    lat, lon, source = path_coordinate_center(str(kernel.get("source_dem_path", "")))
    if source:
        return lat, lon, source
    return geographic_bounds_center(bounds)


def contains_any(text: str, words: tuple[str, ...]) -> bool:
    return any(word in text for word in words)


def add_tag(tags: list[str], tag: str) -> None:
    if tag not in tags:
        tags.append(tag)


def infer_one(kernel: dict[str, Any]) -> dict[str, Any]:
    kernel_id = str(kernel.get("kernel_id", "unknown"))
    current_family = str(kernel.get("terrain_family", "uncategorized"))
    demtype = str(kernel.get("demtype", "unknown"))
    text = " ".join(
        str(value).lower()
        for value in (
            kernel_id,
            kernel.get("source_dem_path", ""),
            demtype,
        )
    )
    bounds = kernel.get("source_bounds") or []
    lat, lon, center_source = geographic_center(kernel, bounds)

    height_range = float(kernel.get("height_range_m", 0.0) or 0.0)
    height_std = float(kernel.get("height_std_m", 0.0) or 0.0)
    slope_p95 = float(kernel.get("slope_p95_deg", 0.0) or 0.0)
    mean_slope = float(kernel.get("mean_slope_deg", 0.0) or 0.0)
    roughness = float(kernel.get("roughness_residual_std_m", 0.0) or 0.0)
    anisotropy = float(kernel.get("anisotropy_score", 0.0) or 0.0)

    tags: list[str] = []
    rationale: list[str] = []
    inferred_family = current_family if current_family in KNOWN_FAMILIES and current_family != "uncategorized" else "uncategorized"
    confidence = 0.0 if inferred_family == "uncategorized" else 0.95

    if lat is not None:
        abs_lat = abs(lat)
        if abs_lat >= 66.0:
            add_tag(tags, "polar")
            rationale.append("center latitude is polar")
        elif abs_lat >= 50.0:
            add_tag(tags, "high_latitude")
        elif abs_lat <= 23.5:
            add_tag(tags, "tropical_latitude")
    elif bounds:
        add_tag(tags, "projected_or_unknown_coordinates")

    if contains_any(text, ("arcticdem", "rema", "gebcoicetopo")):
        add_tag(tags, "polar_dem_product")
        rationale.append("DEM product is polar/ice/topography oriented")
    if contains_any(text, ("gebco", "srtm15plus")):
        add_tag(tags, "bathymetry_or_ocean_context")
        rationale.append("DEM product may include ocean/bathymetry context")

    if height_range >= 2500.0 or (height_range >= 1500.0 and slope_p95 >= 30.0):
        add_tag(tags, "major_relief")
        rationale.append("height range and slope indicate major relief")
    elif height_range >= 700.0 or slope_p95 >= 22.0:
        add_tag(tags, "moderate_relief")
    elif height_range < 180.0 and slope_p95 < 7.0:
        add_tag(tags, "low_relief")
        rationale.append("height range and slope are low")

    if slope_p95 >= 42.0:
        add_tag(tags, "very_steep")
    elif slope_p95 >= 30.0:
        add_tag(tags, "steep")
    elif slope_p95 <= 8.0:
        add_tag(tags, "flat_to_gentle")

    if roughness >= 180.0:
        add_tag(tags, "rough")
    elif roughness <= 30.0:
        add_tag(tags, "smooth")

    if anisotropy >= 0.55:
        add_tag(tags, "strong_orientation")
    elif anisotropy >= 0.35:
        add_tag(tags, "oriented")

    if current_family != "uncategorized":
        add_tag(tags, f"reviewed_{current_family}")
        rationale.append("existing reviewed family retained")
    else:
        polar_or_ice = "polar" in tags or "polar_dem_product" in tags
        ocean_context = "bathymetry_or_ocean_context" in tags
        if polar_or_ice and (height_range >= 500.0 or slope_p95 >= 15.0):
            inferred_family = "glacial"
            confidence = 0.68
            add_tag(tags, "glacial_candidate")
            rationale.append("polar DEM with meaningful relief")
        elif ocean_context and slope_p95 <= 12.0:
            inferred_family = "coast"
            confidence = 0.55
            add_tag(tags, "coast_or_ocean_context_candidate")
            rationale.append("ocean-context DEM with gentle relief")
        elif height_range >= 2500.0 or (height_range >= 1500.0 and slope_p95 >= 28.0):
            inferred_family = "mountain"
            confidence = 0.62
            add_tag(tags, "mountain_candidate")
            rationale.append("large relief and steep slopes")
        elif height_range <= 250.0 and slope_p95 <= 8.0:
            inferred_family = "grassland"
            confidence = 0.45
            add_tag(tags, "plain_candidate")
            rationale.append("low relief and gentle slopes")
        elif slope_p95 >= 38.0 and roughness >= 100.0:
            inferred_family = "mountain"
            confidence = 0.48
            add_tag(tags, "rugged_candidate")
            rationale.append("rugged high-slope terrain without semantic family evidence")
        else:
            add_tag(tags, "needs_visual_family_review")
            rationale.append("metadata is insufficient for safe family assignment")

    if current_family == "uncategorized" and inferred_family != "uncategorized":
        status = "suggested"
    elif current_family == "uncategorized":
        status = "unresolved"
    else:
        status = "retained"

    return {
        "kernel_id": kernel_id,
        "current_family": current_family,
        "inferred_family": inferred_family,
        "family_confidence": confidence,
        "tag_status": status,
        "tags": tags,
        "rationale": rationale,
        "center": {
            "lat": lat,
            "lon": lon,
            "source": center_source,
        },
        "metrics": {
            "height_range_m": height_range,
            "height_std_m": height_std,
            "mean_slope_deg": mean_slope,
            "slope_p95_deg": slope_p95,
            "roughness_residual_std_m": roughness,
            "anisotropy_score": anisotropy,
        },
    }


def summarize(inferences: list[dict[str, Any]]) -> dict[str, Any]:
    by_status: dict[str, int] = {}
    by_inferred_family: dict[str, int] = {}
    by_tag: dict[str, int] = {}
    for item in inferences:
        status = str(item["tag_status"])
        family = str(item["inferred_family"])
        by_status[status] = by_status.get(status, 0) + 1
        by_inferred_family[family] = by_inferred_family.get(family, 0) + 1
        for tag in item.get("tags", []):
            by_tag[tag] = by_tag.get(tag, 0) + 1
    return {
        "by_status": dict(sorted(by_status.items())),
        "by_inferred_family": dict(sorted(by_inferred_family.items())),
        "by_tag": dict(sorted(by_tag.items())),
    }


def enriched_catalog(catalog: dict[str, Any], inferences: list[dict[str, Any]]) -> dict[str, Any]:
    by_id = {item["kernel_id"]: item for item in inferences}
    kernels = []
    for kernel in catalog.get("kernels", []):
        item = by_id.get(kernel.get("kernel_id"))
        if not item:
            kernels.append(kernel)
            continue
        kernels.append(
            {
                **kernel,
                "inferred_family": item["inferred_family"],
                "family_confidence": item["family_confidence"],
                "terrain_tags": item["tags"],
                "tag_status": item["tag_status"],
                "tag_rationale": item["rationale"],
            }
        )
    return {
        **catalog,
        "tagging": {
            "schema": "worldgen9.kernel_inferred_tags.v1",
            "source": "metadata_only_conservative_inference",
        },
        "kernels": kernels,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--enriched-out", default=str(DEFAULT_ENRICHED))
    parser.add_argument("--no-enriched", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog = read_json(Path(args.catalog))
    kernels = catalog.get("kernels")
    if not isinstance(kernels, list):
        raise RuntimeError("catalog has no kernels list: %s" % args.catalog)
    inferences = [infer_one(kernel) for kernel in kernels]
    summary = summarize(inferences)
    report = {
        "version": 1,
        "schema": "worldgen9.kernel_inferred_tags.v1",
        "source_catalog": str(args.catalog).replace("\\", "/"),
        "kernel_count": len(inferences),
        "summary": summary,
        "inferences": inferences,
    }
    if not args.dry_run:
        write_json(Path(args.out), report)
        if not args.no_enriched:
            write_json(Path(args.enriched_out), enriched_catalog(catalog, inferences))
    print("[infer-tags] catalog=%s kernels=%d" % (args.catalog, len(inferences)))
    print("[infer-tags] by_status=%s" % summary["by_status"])
    print("[infer-tags] by_inferred_family=%s" % summary["by_inferred_family"])
    if not args.dry_run:
        print("[infer-tags] out=%s" % args.out)
        if not args.no_enriched:
            print("[infer-tags] enriched=%s" % args.enriched_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
