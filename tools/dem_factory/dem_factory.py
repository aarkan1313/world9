#!/usr/bin/env python3
"""Standalone DEM catalog and terrain-kernel factory for WorldGen9.

This tool deliberately stays outside Godot. It reads raw GeoTIFF DEMs from the
operator cache and writes compact JSON/NPY/PNG artifacts that a later runtime
terrain module can consume.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np
from PIL import Image
import rasterio
from rasterio.enums import Resampling


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DEM_ROOT = ROOT / "dems"
DEFAULT_FACTORY_ROOT = ROOT / "factory"
CATALOG_DIR = DEFAULT_FACTORY_ROOT / "catalog"
KERNEL_DIR = DEFAULT_FACTORY_ROOT / "kernels"

FAMILY_KEYWORDS = (
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
    "fjord",
    "delta",
    "tundra",
    "temperate",
)

PREFERRED_KERNEL_HINTS = (
    "mountain_alps_mont_blanc",
    "glacial_nz_southern_alps",
    "volcanic_fuji",
    "badlands_death_valley",
    "karst_ha_long",
    "desert_namib_sossusvlei",
    "grassland_nebraska_sandhills",
    "wetland_okavango_delta",
    "rainforest_borneo_sabah",
    "coast_oregon",
    "badlands_grand_canyon",
    "coast_musandam",
)


@dataclass(frozen=True)
class DemRecord:
    path: Path
    rel_path: str
    stem: str
    family: str
    demtype: str
    bytes: int
    width: int
    height: int
    crs: str | None
    bounds: list[float]
    nodata: float | None
    dtype: str
    approx_spacing_m: float | None
    sidecar: str | None
    error: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "path": str(self.path).replace("\\", "/"),
            "relative_path": self.rel_path,
            "stem": self.stem,
            "family": self.family,
            "demtype": self.demtype,
            "bytes": self.bytes,
            "width": self.width,
            "height": self.height,
            "crs": self.crs,
            "bounds": self.bounds,
            "nodata": self.nodata,
            "dtype": self.dtype,
            "approx_spacing_m": self.approx_spacing_m,
            "sidecar": self.sidecar,
            "error": self.error,
        }


def safe_id(value: str) -> str:
    text = re.sub(r"[^A-Za-z0-9]+", "_", value.strip().lower()).strip("_")
    return text or "unknown"


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def find_sidecar(path: Path) -> tuple[Path | None, dict[str, Any]]:
    candidates = [path.with_suffix(path.suffix + ".json"), path.with_suffix(".json")]
    for candidate in candidates:
        if candidate.exists():
            return candidate, read_json(candidate)
    return None, {}


def classify_family(path: Path, sidecar: dict[str, Any]) -> str:
    stem = path.stem.lower()
    match = re.search(r"bulk\d+_([a-z]+)_", stem)
    if match:
        return match.group(1)
    target = sidecar.get("target") or sidecar.get("terrain_family")
    if isinstance(target, str) and target:
        return safe_id(target)
    for keyword in FAMILY_KEYWORDS:
        if keyword in stem:
            if keyword == "fjord":
                return "coast"
            if keyword == "delta":
                return "wetland"
            return keyword
    return "uncategorized"


def classify_demtype(path: Path, sidecar: dict[str, Any]) -> str:
    demtype = sidecar.get("demtype")
    if isinstance(demtype, str) and demtype:
        return demtype
    first = path.stem.split("_", 1)[0]
    return first or "unknown"


def approximate_spacing_m(src: rasterio.io.DatasetReader) -> float | None:
    if src.width <= 0 or src.height <= 0:
        return None
    try:
        if src.crs and src.crs.is_geographic:
            left, bottom, right, top = src.bounds
            center_lat = (bottom + top) * 0.5
            meters_per_degree_lat = 111_320.0
            meters_per_degree_lon = 111_320.0 * max(0.01, math.cos(math.radians(center_lat)))
            sx = abs(right - left) * meters_per_degree_lon / float(src.width)
            sy = abs(top - bottom) * meters_per_degree_lat / float(src.height)
            return float((sx + sy) * 0.5)
        sx = abs(float(src.transform.a))
        sy = abs(float(src.transform.e))
        if sx > 0.0 and sy > 0.0:
            return float((sx + sy) * 0.5)
    except Exception:
        return None
    return None


def scan_dem(path: Path, dem_root: Path) -> DemRecord:
    sidecar_path, sidecar = find_sidecar(path)
    try:
        with rasterio.open(path) as src:
            return DemRecord(
                path=path,
                rel_path=str(path.relative_to(dem_root)).replace("\\", "/"),
                stem=path.stem,
                family=classify_family(path, sidecar),
                demtype=classify_demtype(path, sidecar),
                bytes=path.stat().st_size,
                width=int(src.width),
                height=int(src.height),
                crs=str(src.crs) if src.crs else None,
                bounds=[float(v) for v in src.bounds],
                nodata=None if src.nodata is None else float(src.nodata),
                dtype=str(src.dtypes[0]) if src.dtypes else "unknown",
                approx_spacing_m=approximate_spacing_m(src),
                sidecar=str(sidecar_path).replace("\\", "/") if sidecar_path else None,
            )
    except Exception as exc:
        return DemRecord(
            path=path,
            rel_path=str(path.relative_to(dem_root)).replace("\\", "/"),
            stem=path.stem,
            family=classify_family(path, sidecar),
            demtype=classify_demtype(path, sidecar),
            bytes=path.stat().st_size if path.exists() else 0,
            width=0,
            height=0,
            crs=None,
            bounds=[],
            nodata=None,
            dtype="unknown",
            approx_spacing_m=None,
            sidecar=str(sidecar_path).replace("\\", "/") if sidecar_path else None,
            error=f"{type(exc).__name__}: {exc}",
        )


def summarize(records: list[DemRecord]) -> dict[str, Any]:
    by_family: dict[str, dict[str, Any]] = {}
    by_demtype: dict[str, dict[str, Any]] = {}
    total_bytes = 0
    errors = 0
    for record in records:
        total_bytes += record.bytes
        if record.error:
            errors += 1
        fam = by_family.setdefault(record.family, {"count": 0, "bytes": 0})
        fam["count"] += 1
        fam["bytes"] += record.bytes
        dem = by_demtype.setdefault(record.demtype, {"count": 0, "bytes": 0})
        dem["count"] += 1
        dem["bytes"] += record.bytes
    for bucket in list(by_family.values()) + list(by_demtype.values()):
        bucket["gib"] = bucket["bytes"] / float(1024**3)
    return {
        "dem_root": str(DEFAULT_DEM_ROOT).replace("\\", "/"),
        "count": len(records),
        "errors": errors,
        "bytes": total_bytes,
        "gib": total_bytes / float(1024**3),
        "by_family": dict(sorted(by_family.items())),
        "by_demtype": dict(sorted(by_demtype.items())),
    }


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def read_kernel_metadata(path: Path) -> dict[str, Any]:
    data = read_json(path)
    if not isinstance(data, dict) or not data.get("kernel_id"):
        raise RuntimeError("invalid kernel metadata: %s" % path)
    return data


def command_catalog(args: argparse.Namespace) -> int:
    dem_root = Path(args.dem_root)
    paths = sorted(dem_root.rglob("*.tif"))
    records = [scan_dem(path, dem_root) for path in paths]
    catalog = {
        "version": 1,
        "dem_root": str(dem_root).replace("\\", "/"),
        "records": [record.to_json() for record in records],
    }
    summary = summarize(records)
    out_dir = Path(args.out_dir)
    write_json(out_dir / "dem_catalog.json", catalog)
    write_json(out_dir / "dem_catalog_summary.json", summary)
    print("[catalog] records=%d errors=%d gib=%.3f" % (summary["count"], summary["errors"], summary["gib"]))
    print("[catalog] wrote=%s" % (out_dir / "dem_catalog.json"))
    print("[catalog] wrote=%s" % (out_dir / "dem_catalog_summary.json"))
    return 0


def load_catalog(path: Path) -> list[dict[str, Any]]:
    data = read_json(path)
    records = data.get("records")
    if not isinstance(records, list):
        raise RuntimeError("catalog has no records list: %s" % path)
    return [record for record in records if not record.get("error")]


def select_kernel_records(records: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    by_stem = {safe_id(record["stem"]): record for record in records}
    selected: list[dict[str, Any]] = []
    used_paths: set[str] = set()

    for hint in PREFERRED_KERNEL_HINTS:
        for key, record in by_stem.items():
            if hint in key and record["path"] not in used_paths:
                selected.append(record)
                used_paths.add(record["path"])
                break
        if len(selected) >= limit:
            return selected

    family_seen = {record["family"] for record in selected}
    candidates = sorted(
        records,
        key=lambda r: (
            0 if "bulk20260524" in str(r.get("stem", "")).lower() else 1,
            -int(r.get("bytes", 0)),
        ),
    )
    for record in candidates:
        if record["path"] in used_paths:
            continue
        if record.get("family") in family_seen and len(family_seen) < limit:
            continue
        selected.append(record)
        used_paths.add(record["path"])
        family_seen.add(record.get("family", "unknown"))
        if len(selected) >= limit:
            return selected

    for record in candidates:
        if record["path"] not in used_paths:
            selected.append(record)
            used_paths.add(record["path"])
            if len(selected) >= limit:
                break
    return selected


def finite_percentile(arr: np.ndarray, percentile: float, fallback: float = 0.0) -> float:
    finite = arr[np.isfinite(arr)]
    if finite.size == 0:
        return fallback
    return float(np.percentile(finite, percentile))


def save_gray_png(arr: np.ndarray, path: Path, lo: float | None = None, hi: float | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    finite = np.isfinite(arr)
    if not finite.any():
        image = np.zeros(arr.shape, dtype=np.uint8)
    else:
        low = finite_percentile(arr, 1.0) if lo is None else lo
        high = finite_percentile(arr, 99.0, low + 1.0) if hi is None else hi
        span = max(1e-6, high - low)
        image = np.clip((np.where(finite, arr, low) - low) / span * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(image, mode="L").save(path)


def lowpass_resize(arr: np.ndarray, small_size: int) -> np.ndarray:
    lo = float(np.nanmin(arr))
    hi = float(np.nanmax(arr))
    span = max(1e-6, hi - lo)
    img = np.clip((arr - lo) / span * 65535.0, 0.0, 65535.0).astype(np.uint16)
    pil = Image.fromarray(img)
    small = pil.resize((small_size, small_size), Image.Resampling.BILINEAR)
    large = small.resize((arr.shape[1], arr.shape[0]), Image.Resampling.BILINEAR)
    return np.asarray(large).astype(np.float32) / 65535.0 * span + lo


def orientation_stats(gx: np.ndarray, gy: np.ndarray) -> tuple[float, float]:
    finite = np.isfinite(gx) & np.isfinite(gy)
    if not finite.any():
        return 0.0, 0.0
    x = gx[finite].astype(np.float64)
    y = gy[finite].astype(np.float64)
    cov = np.array([[float(np.mean(x * x)), float(np.mean(x * y))], [float(np.mean(x * y)), float(np.mean(y * y))]])
    vals, vecs = np.linalg.eigh(cov)
    order = np.argsort(vals)
    major = float(vals[order[-1]])
    minor = float(vals[order[0]])
    vec = vecs[:, order[-1]]
    angle = math.degrees(math.atan2(float(vec[1]), float(vec[0])))
    anisotropy = 0.0 if major <= 1e-12 else max(0.0, min(1.0, 1.0 - minor / major))
    return angle, anisotropy


def analyze_record(record: dict[str, Any], out_root: Path, sample_px: int, residual_px: int) -> dict[str, Any]:
    path = Path(record["path"])
    kernel_id = "%s__%s" % (safe_id(record.get("family", "unknown")), safe_id(path.stem))
    out_dir = out_root / kernel_id
    out_dir.mkdir(parents=True, exist_ok=True)

    with rasterio.open(path) as src:
        data = src.read(
            1,
            out_shape=(sample_px, sample_px),
            masked=True,
            resampling=Resampling.bilinear,
        ).astype(np.float32)
        arr = data.filled(np.nan)
        spacing = approximate_spacing_m(src)
        if spacing is not None:
            spacing *= max(src.width / sample_px, src.height / sample_px)

    finite = np.isfinite(arr)
    coverage = float(np.count_nonzero(finite) / arr.size)
    if not finite.any():
        raise RuntimeError("no finite samples in %s" % path)
    fill_value = float(np.nanmean(arr))
    height = np.where(finite, arr, fill_value).astype(np.float32)
    low = lowpass_resize(height, max(8, residual_px))
    residual = (height - low).astype(np.float32)
    residual_std = float(np.std(residual))
    normalized = ((height - float(np.mean(height))) / max(1e-6, float(np.std(height)))).astype(np.float32)

    spacing_m = float(spacing or 1.0)
    gy, gx = np.gradient(height, spacing_m, spacing_m)
    slope = np.degrees(np.arctan(np.sqrt(gx * gx + gy * gy))).astype(np.float32)
    lap = (
        np.roll(height, 1, axis=0)
        + np.roll(height, -1, axis=0)
        + np.roll(height, 1, axis=1)
        + np.roll(height, -1, axis=1)
        - 4.0 * height
    ).astype(np.float32)
    abs_lap = np.abs(lap)
    ridge_threshold = finite_percentile(lap, 90.0)
    valley_threshold = finite_percentile(lap, 10.0)
    dominant_orientation_deg, anisotropy = orientation_stats(gx, gy)

    height_range = float(np.max(height) - np.min(height))
    mean_slope = float(np.mean(slope))
    roughness = float(np.std(residual))
    quality_score = coverage
    if height_range < 20.0:
        quality_score *= 0.4
    if mean_slope < 0.2:
        quality_score *= 0.7
    if coverage < 0.95:
        quality_score *= coverage

    np.save(out_dir / "height_m.npy", height)
    np.save(out_dir / "normalized_height.npy", normalized)
    np.save(out_dir / "residual_m.npy", residual)
    save_gray_png(height, out_dir / "preview_height.png")
    save_gray_png(slope, out_dir / "preview_slope.png", lo=0.0, hi=max(5.0, finite_percentile(slope, 99.0)))
    save_gray_png(residual, out_dir / "preview_residual.png")

    metadata = {
        "kernel_id": kernel_id,
        "source_dem_path": str(path).replace("\\", "/"),
        "terrain_family": record.get("family", "unknown"),
        "demtype": record.get("demtype", "unknown"),
        "source_bounds": record.get("bounds"),
        "sample_px": sample_px,
        "approx_sample_spacing_m": spacing_m,
        "coverage_fraction": coverage,
        "height_min_m": float(np.min(height)),
        "height_max_m": float(np.max(height)),
        "height_range_m": height_range,
        "height_mean_m": float(np.mean(height)),
        "height_std_m": float(np.std(height)),
        "mean_slope_deg": mean_slope,
        "slope_p50_deg": finite_percentile(slope, 50.0),
        "slope_p95_deg": finite_percentile(slope, 95.0),
        "curvature_abs_mean": float(np.mean(abs_lap)),
        "roughness_residual_std_m": roughness,
        "residual_std_m": residual_std,
        "ridge_density": float(np.mean(lap >= ridge_threshold)),
        "valley_density": float(np.mean(lap <= valley_threshold)),
        "dominant_orientation_deg": dominant_orientation_deg,
        "anisotropy_score": anisotropy,
        "quality_score": float(quality_score),
        "review_status": "candidate",
        "artifacts": {
            "height_m_npy": str(out_dir / "height_m.npy").replace("\\", "/"),
            "normalized_height_npy": str(out_dir / "normalized_height.npy").replace("\\", "/"),
            "residual_m_npy": str(out_dir / "residual_m.npy").replace("\\", "/"),
            "preview_height_png": str(out_dir / "preview_height.png").replace("\\", "/"),
            "preview_slope_png": str(out_dir / "preview_slope.png").replace("\\", "/"),
            "preview_residual_png": str(out_dir / "preview_residual.png").replace("\\", "/"),
        },
    }
    write_json(out_dir / "kernel.json", metadata)
    return metadata


def command_kernels(args: argparse.Namespace) -> int:
    catalog_path = Path(args.catalog)
    if not catalog_path.exists():
        command_catalog(
            argparse.Namespace(
                dem_root=args.dem_root,
                out_dir=str(catalog_path.parent),
            )
        )
    records = load_catalog(catalog_path)
    selected = records if bool(args.all) else select_kernel_records(records, int(args.limit))
    out_root = Path(args.out_dir)
    kernels = []
    for index, record in enumerate(selected, 1):
        kernel_id = "%s__%s" % (safe_id(record.get("family", "unknown")), safe_id(Path(record["path"]).stem))
        kernel_json = out_root / kernel_id / "kernel.json"
        if bool(args.skip_existing) and kernel_json.exists():
            kernels.append(read_kernel_metadata(kernel_json))
            continue
        print("[kernels] %d/%d %s" % (index, len(selected), record["relative_path"]))
        try:
            kernels.append(analyze_record(record, out_root, int(args.sample_px), int(args.residual_px)))
        except Exception as exc:
            print("[kernels] skipped %s: %s: %s" % (record["relative_path"], type(exc).__name__, exc))
    catalog = {
        "version": 1,
        "kernel_count": len(kernels),
        "kernels": kernels,
    }
    write_json(CATALOG_DIR / "kernel_catalog.json", catalog)
    print("[kernels] wrote=%s" % (CATALOG_DIR / "kernel_catalog.json"))
    return 0


def validate_kernel(kernel: dict[str, Any]) -> dict[str, Any]:
    artifacts = kernel.get("artifacts", {})
    problems: list[str] = []
    for key in (
        "height_m_npy",
        "normalized_height_npy",
        "residual_m_npy",
        "preview_height_png",
        "preview_slope_png",
        "preview_residual_png",
    ):
        value = artifacts.get(key)
        if not value or not Path(value).exists():
            problems.append("missing_%s" % key)
    for key in ("height_m_npy", "normalized_height_npy", "residual_m_npy"):
        value = artifacts.get(key)
        if value and Path(value).exists():
            arr = np.load(value)
            if arr.ndim != 2:
                problems.append("%s_not_2d" % key)
            if arr.shape[0] < 64 or arr.shape[1] < 64:
                problems.append("%s_too_small" % key)
            finite = np.isfinite(arr)
            if not finite.all():
                problems.append("%s_nonfinite" % key)
            if float(np.std(arr)) <= 1e-6:
                problems.append("%s_flat" % key)
    coverage = float(kernel.get("coverage_fraction", 0.0))
    quality = float(kernel.get("quality_score", 0.0))
    height_range = float(kernel.get("height_range_m", 0.0))
    family = str(kernel.get("terrain_family", "unknown"))
    if coverage < 0.95:
        problems.append("low_coverage")
    if quality < 0.5:
        problems.append("low_quality")
    if height_range < 20.0 and family not in ("wetland", "grassland", "coast"):
        problems.append("low_height_range")
    return {
        "kernel_id": kernel.get("kernel_id"),
        "terrain_family": family,
        "quality_score": quality,
        "coverage_fraction": coverage,
        "height_range_m": height_range,
        "mean_slope_deg": kernel.get("mean_slope_deg"),
        "slope_p95_deg": kernel.get("slope_p95_deg"),
        "problems": problems,
        "status": "pass" if not problems else "review",
    }


def make_contact_sheet(kernels: list[dict[str, Any]], output_path: Path) -> None:
    thumbs: list[tuple[str, Image.Image]] = []
    for kernel in kernels:
        preview = kernel.get("artifacts", {}).get("preview_height_png")
        if not preview or not Path(preview).exists():
            continue
        image = Image.open(preview).convert("L").resize((160, 160), Image.Resampling.BILINEAR).convert("RGB")
        thumbs.append((str(kernel.get("kernel_id", "unknown")), image))
    if not thumbs:
        return
    cols = 4
    rows = int(math.ceil(len(thumbs) / cols))
    label_h = 36
    sheet = Image.new("RGB", (cols * 160, rows * (160 + label_h)), (24, 24, 24))
    for index, (label, image) in enumerate(thumbs):
        x = (index % cols) * 160
        y = (index // cols) * (160 + label_h)
        sheet.paste(image, (x, y))
        # Avoid a font dependency; write labels into metadata sidecar instead.
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)


def command_validate(args: argparse.Namespace) -> int:
    catalog_path = Path(args.catalog)
    data = read_json(catalog_path)
    kernels = data.get("kernels")
    if not isinstance(kernels, list):
        raise RuntimeError("kernel catalog has no kernels list: %s" % catalog_path)
    results = [validate_kernel(kernel) for kernel in kernels]
    result_by_id = {result["kernel_id"]: result for result in results}
    accepted_kernels = [kernel for kernel in kernels if result_by_id.get(kernel.get("kernel_id"), {}).get("status") == "pass"]
    review_kernels = [kernel for kernel in kernels if result_by_id.get(kernel.get("kernel_id"), {}).get("status") != "pass"]
    pass_count = sum(1 for result in results if result["status"] == "pass")
    review_count = len(results) - pass_count
    report = {
        "version": 1,
        "kernel_count": len(results),
        "pass_count": pass_count,
        "review_count": review_count,
        "results": results,
    }
    out_path = Path(args.out)
    write_json(out_path, report)
    accepted_path = out_path.with_name("accepted_kernel_catalog.json")
    review_path = out_path.with_name("review_kernel_catalog.json")
    write_json(accepted_path, {"version": 1, "kernel_count": len(accepted_kernels), "kernels": accepted_kernels})
    write_json(review_path, {"version": 1, "kernel_count": len(review_kernels), "kernels": review_kernels})
    if args.contact_sheet and not args.no_contact_sheet:
        make_contact_sheet(kernels, Path(args.contact_sheet))
    print("[validate] kernels=%d pass=%d review=%d" % (len(results), pass_count, review_count))
    print("[validate] wrote=%s" % out_path)
    print("[validate] accepted=%s" % accepted_path)
    print("[validate] review=%s" % review_path)
    if args.contact_sheet and not args.no_contact_sheet:
        print("[validate] contact_sheet=%s" % args.contact_sheet)
    return 0


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    catalog = sub.add_parser("catalog", help="Scan DEM GeoTIFF headers and write catalog JSON")
    catalog.add_argument("--dem-root", default=str(DEFAULT_DEM_ROOT))
    catalog.add_argument("--out-dir", default=str(CATALOG_DIR))
    catalog.set_defaults(func=command_catalog)

    kernels = sub.add_parser("kernels", help="Generate reduced DEM terrain-kernel candidates")
    kernels.add_argument("--dem-root", default=str(DEFAULT_DEM_ROOT))
    kernels.add_argument("--catalog", default=str(CATALOG_DIR / "dem_catalog.json"))
    kernels.add_argument("--out-dir", default=str(KERNEL_DIR))
    kernels.add_argument("--limit", type=int, default=12)
    kernels.add_argument("--all", action="store_true", help="Generate kernels for every valid DEM in the catalog")
    kernels.add_argument("--skip-existing", action="store_true", help="Reuse existing kernel.json artifacts")
    kernels.add_argument("--sample-px", type=int, default=512)
    kernels.add_argument("--residual-px", type=int, default=64)
    kernels.set_defaults(func=command_kernels)

    validate = sub.add_parser("validate", help="Validate generated kernel artifacts")
    validate.add_argument("--catalog", default=str(CATALOG_DIR / "kernel_catalog.json"))
    validate.add_argument("--out", default=str(CATALOG_DIR / "kernel_validation_report.json"))
    validate.add_argument("--contact-sheet", default=str(CATALOG_DIR / "kernel_contact_sheet.png"))
    validate.add_argument("--no-contact-sheet", action="store_true")
    validate.set_defaults(func=command_validate)
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
