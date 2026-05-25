#!/usr/bin/env python3
"""Build a runtime-facing DEM kernel pack manifest.

This is intentionally lightweight. It validates catalog shape and kernel array
headers, then writes a manifest with only the fields a future terrain runtime
should depend on.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "catalog" / "promoted_kernel_catalog.json"
DEFAULT_OUT = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"

FAMILY_RUNTIME_DEFAULTS = {
    "mountain": {"relief_scale_m": 640.0, "detail_scale_m": 44.0, "runtime_weight": 1.0},
    "glacial": {"relief_scale_m": 560.0, "detail_scale_m": 38.0, "runtime_weight": 1.0},
    "badlands": {"relief_scale_m": 500.0, "detail_scale_m": 62.0, "runtime_weight": 1.0},
    "desert": {"relief_scale_m": 390.0, "detail_scale_m": 38.0, "runtime_weight": 1.0},
    "karst": {"relief_scale_m": 450.0, "detail_scale_m": 52.0, "runtime_weight": 1.0},
    "coast": {"relief_scale_m": 280.0, "detail_scale_m": 30.0, "runtime_weight": 1.0},
    "grassland": {"relief_scale_m": 190.0, "detail_scale_m": 22.0, "runtime_weight": 1.0},
    "rainforest": {"relief_scale_m": 380.0, "detail_scale_m": 36.0, "runtime_weight": 1.0},
    "volcanic": {"relief_scale_m": 460.0, "detail_scale_m": 40.0, "runtime_weight": 1.0},
}

REGION_PALETTES = [
    {"id": "alpine", "families": ["mountain", "glacial", "grassland"]},
    {"id": "drylands", "families": ["badlands", "desert", "karst"]},
    {"id": "humid_hills", "families": ["rainforest", "mountain", "grassland"]},
    {"id": "volcanic_coast", "families": ["volcanic", "coast", "rainforest"]},
    {"id": "coastal_ridges", "families": ["coast", "mountain", "glacial"]},
    {"id": "open_steppe", "families": ["grassland", "badlands", "desert"]},
]

REQUIRED_ARTIFACTS = ("normalized_height_npy", "residual_m_npy", "preview_height_png")
OPTIONAL_ARTIFACTS = ("height_m_npy", "preview_slope_png", "preview_residual_png")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def as_posix(path: Path) -> str:
    return str(path).replace("\\", "/")


def path_string(value: str, root: Path, relative: bool) -> str:
    path = Path(value)
    if relative:
        try:
            return as_posix(path.resolve().relative_to(root.resolve()))
        except ValueError:
            return as_posix(path)
    return as_posix(path)


def array_header(path: Path) -> dict[str, Any]:
    arr = np.load(path, mmap_mode="r")
    if arr.ndim != 2:
        raise RuntimeError(f"kernel array is not 2D: {path}")
    if arr.shape[0] != arr.shape[1]:
        raise RuntimeError(f"kernel array is not square: {path}")
    return {
        "shape": [int(arr.shape[0]), int(arr.shape[1])],
        "dtype": str(arr.dtype),
    }


def require_number(kernel: dict[str, Any], field: str) -> float:
    value = kernel.get(field)
    if not isinstance(value, (int, float)):
        raise RuntimeError(f"{kernel.get('kernel_id', 'unknown')} missing numeric field {field}")
    return float(value)


def build_kernel_entry(kernel: dict[str, Any], root: Path, relative_paths: bool) -> dict[str, Any]:
    kernel_id = kernel.get("kernel_id")
    family = kernel.get("terrain_family")
    if not isinstance(kernel_id, str) or not kernel_id:
        raise RuntimeError("kernel has no kernel_id")
    if not isinstance(family, str) or not family:
        raise RuntimeError(f"{kernel_id} has no terrain_family")

    artifacts = kernel.get("artifacts")
    if not isinstance(artifacts, dict):
        raise RuntimeError(f"{kernel_id} has no artifacts block")

    missing = [key for key in REQUIRED_ARTIFACTS if not artifacts.get(key)]
    if missing:
        raise RuntimeError(f"{kernel_id} missing artifacts: {', '.join(missing)}")

    for key in REQUIRED_ARTIFACTS:
        if not Path(str(artifacts[key])).exists():
            raise RuntimeError(f"{kernel_id} artifact does not exist: {artifacts[key]}")

    normalized = array_header(Path(str(artifacts["normalized_height_npy"])))
    residual = array_header(Path(str(artifacts["residual_m_npy"])))
    if normalized["shape"] != residual["shape"]:
        raise RuntimeError(f"{kernel_id} normalized/residual shapes differ")

    runtime_artifacts = {
        "normalized_height_npy": path_string(str(artifacts["normalized_height_npy"]), root, relative_paths),
        "residual_m_npy": path_string(str(artifacts["residual_m_npy"]), root, relative_paths),
        "preview_height_png": path_string(str(artifacts["preview_height_png"]), root, relative_paths),
    }
    for key in OPTIONAL_ARTIFACTS:
        value = artifacts.get(key)
        if value and Path(str(value)).exists():
            runtime_artifacts[key] = path_string(str(value), root, relative_paths)

    return {
        "id": kernel_id,
        "family": family,
        "demtype": str(kernel.get("demtype", "unknown")),
        "promotion_status": str(kernel.get("promotion_status", kernel.get("review_status", "unknown"))),
        "promotion_weight": float(kernel.get("promotion_weight", 1.0)),
        "sample": {
            "shape": normalized["shape"],
            "dtype": normalized["dtype"],
            "source_sample_px": int(kernel.get("sample_px", normalized["shape"][0])),
            "approx_sample_spacing_m": require_number(kernel, "approx_sample_spacing_m"),
        },
        "stats": {
            "coverage_fraction": require_number(kernel, "coverage_fraction"),
            "height_range_m": require_number(kernel, "height_range_m"),
            "height_std_m": require_number(kernel, "height_std_m"),
            "mean_slope_deg": require_number(kernel, "mean_slope_deg"),
            "slope_p95_deg": require_number(kernel, "slope_p95_deg"),
            "roughness_residual_std_m": require_number(kernel, "roughness_residual_std_m"),
            "anisotropy_score": require_number(kernel, "anisotropy_score"),
            "quality_score": require_number(kernel, "quality_score"),
        },
        "source": {
            "dem_path": path_string(str(kernel.get("source_dem_path", "")), root, relative_paths),
            "bounds": kernel.get("source_bounds"),
        },
        "artifacts": runtime_artifacts,
    }


def build_pack(catalog_path: Path, relative_paths: bool) -> dict[str, Any]:
    catalog = read_json(catalog_path)
    kernels = catalog.get("kernels")
    if not isinstance(kernels, list) or not kernels:
        raise RuntimeError(f"catalog has no kernels: {catalog_path}")

    entries = [build_kernel_entry(kernel, ROOT, relative_paths) for kernel in kernels]
    families: dict[str, dict[str, Any]] = {}
    for entry in entries:
        family = entry["family"]
        bucket = families.setdefault(
            family,
            {
                **FAMILY_RUNTIME_DEFAULTS.get(
                    family,
                    {"relief_scale_m": 320.0, "detail_scale_m": 35.0, "runtime_weight": 1.0},
                ),
                "kernel_count": 0,
                "kernel_ids": [],
            },
        )
        bucket["kernel_count"] += 1
        bucket["kernel_ids"].append(entry["id"])

    missing_palette_families = sorted(
        {
            family
            for palette in REGION_PALETTES
            for family in palette["families"]
            if family not in families
        }
    )
    if missing_palette_families:
        raise RuntimeError("palette references families with no kernels: " + ", ".join(missing_palette_families))

    return {
        "version": 1,
        "schema": "worldgen9.runtime_kernel_pack.v1",
        "source_catalog": path_string(str(catalog_path), ROOT, relative_paths),
        "description": "Reviewed DEM-derived terrain kernel pack for infinite heightfield experiments.",
        "coordinate_contract": {
            "units": "meters",
            "sampling": "deterministic_world_space",
            "normalization": "no_per_chunk_normalization",
            "kernel_edge_mode": "mirrored_repeat",
            "chunk_seam_rule": "same_world_coordinate_returns_same_height_from_any_chunk",
        },
        "runtime_defaults": {
            "chunk_size_m": 2048.0,
            "lod0_vertices_per_side": 129,
            "high_detail_lod0_vertices_per_side": 257,
            "region_size_m": 32768.0,
            "province_size_regions": 4,
            "height_resolution_m": 32.0,
            "kernel_world_scale_min_region_multiplier": 2.20,
            "kernel_world_scale_max_region_multiplier": 3.20,
        },
        "region_palettes": REGION_PALETTES,
        "families": dict(sorted(families.items())),
        "kernel_count": len(entries),
        "kernels": entries,
    }


def validate_pack(pack: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    ids: set[str] = set()
    for kernel in pack.get("kernels", []):
        kernel_id = kernel.get("id")
        if kernel_id in ids:
            errors.append(f"duplicate kernel id: {kernel_id}")
        ids.add(kernel_id)
        if kernel.get("family") not in pack.get("families", {}):
            errors.append(f"kernel family not declared: {kernel_id}")
    for family, data in pack.get("families", {}).items():
        if int(data.get("kernel_count", 0)) <= 0:
            errors.append(f"family has no kernels: {family}")
        if len(data.get("kernel_ids", [])) != int(data.get("kernel_count", 0)):
            errors.append(f"family count mismatch: {family}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--absolute-paths", action="store_true", help="Write absolute artifact paths instead of paths relative to worldgen9 root")
    parser.add_argument("--dry-run", action="store_true", help="Validate without writing output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pack = build_pack(Path(args.catalog), relative_paths=not bool(args.absolute_paths))
    errors = validate_pack(pack)
    if errors:
        for error in errors:
            print(f"[kernel-pack] error: {error}")
        return 1
    family_counts = {family: data["kernel_count"] for family, data in pack["families"].items()}
    if not args.dry_run:
        write_json(Path(args.out), pack)
    print("[kernel-pack] source=%s" % args.catalog)
    print("[kernel-pack] kernels=%d families=%s" % (pack["kernel_count"], family_counts))
    print("[kernel-pack] dry_run=%s out=%s" % (bool(args.dry_run), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
