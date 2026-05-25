#!/usr/bin/env python3
"""Sample far-apart terrain windows to check infinite-world variety."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT_DIR = ROOT / "factory" / "runtime" / "infinite_travel"

DEFAULT_ORIGINS = [
    (0.0, 0.0),
    (32768.0, 0.0),
    (0.0, 32768.0),
    (65536.0, 32768.0),
    (-32768.0, 65536.0),
    (131072.0, -65536.0),
    (-196608.0, 98304.0),
    (262144.0, 196608.0),
    (-393216.0, -131072.0),
    (524288.0, 327680.0),
    (-786432.0, 458752.0),
    (1048576.0, -524288.0),
]


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def normalize_u8(arr: np.ndarray) -> np.ndarray:
    low = float(np.percentile(arr, 1.0))
    high = float(np.percentile(arr, 99.0))
    span = max(1e-6, high - low)
    return np.clip((arr - low) / span * 255.0, 0.0, 255.0).astype(np.uint8)


def visual_hash(arr: np.ndarray) -> str:
    image = Image.fromarray(normalize_u8(arr), mode="L").resize((32, 32), Image.Resampling.LANCZOS)
    return hashlib.sha256(image.tobytes()).hexdigest()


def correlation(a: np.ndarray, b: np.ndarray) -> float:
    av = a.astype(np.float64).ravel()
    bv = b.astype(np.float64).ravel()
    av -= float(np.mean(av))
    bv -= float(np.mean(bv))
    denom = float(np.linalg.norm(av) * np.linalg.norm(bv))
    if denom <= 1e-9:
        return 0.0
    return float(np.dot(av, bv) / denom)


def save_panel_images(out_dir: Path, name: str, height: np.ndarray, region: np.ndarray, spacing_m: float) -> dict[str, str]:
    height_png = out_dir / f"{name}_height.png"
    hillshade_png = out_dir / f"{name}_hillshade.png"
    region_png = out_dir / f"{name}_regions.png"
    hf.save_gray(height, height_png)
    hf.save_hillshade(height, spacing_m, hillshade_png)
    hf.save_region(region, region_png)
    return {
        "height_png": height_png.name,
        "hillshade_png": hillshade_png.name,
        "region_png": region_png.name,
    }


def open_panel(path: Path, size: tuple[int, int]) -> Image.Image:
    img = Image.open(path).convert("RGB")
    img.thumbnail(size, Image.Resampling.LANCZOS)
    panel = Image.new("RGB", size, (22, 24, 26))
    panel.paste(img, ((size[0] - img.width) // 2, (size[1] - img.height) // 2))
    return panel


def save_contact_sheet(records: list[dict[str, Any]], out_dir: Path, out_path: Path) -> None:
    cols = [("height_png", "height"), ("hillshade_png", "hillshade"), ("region_png", "regions")]
    cell = (220, 220)
    label_h = 52
    header_h = 34
    sheet = Image.new("RGB", (cell[0] * len(cols), header_h + len(records) * (cell[1] + label_h)), (18, 20, 22))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 13)
        small = ImageFont.truetype("arial.ttf", 11)
    except OSError:
        font = ImageFont.load_default()
        small = font

    for col, (_key, label) in enumerate(cols):
        draw.text((col * cell[0] + 10, 9), label, fill=(224, 226, 228), font=font)

    for row, record in enumerate(records):
        y0 = header_h + row * (cell[1] + label_h)
        for col, (key, _label) in enumerate(cols):
            sheet.paste(open_panel(out_dir / str(record[key]), cell), (col * cell[0], y0))
        origin = record["origin"]
        label = (
            f"{record['name']}  x {origin[0]:.0f} z {origin[1]:.0f}  "
            f"range {record['height_range_m']:.0f}m  p95 slope {record['slope_p95_deg']:.1f}"
        )
        draw.text((10, y0 + cell[1] + 8), label, fill=(224, 226, 228), font=small)
        draw.text((10, y0 + cell[1] + 27), f"hash {record['visual_hash'][:12]}", fill=(170, 174, 178), font=small)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def parse_origins(values: list[str] | None) -> list[tuple[float, float]]:
    if not values:
        return DEFAULT_ORIGINS
    origins = []
    for value in values:
        parts = value.split(",")
        if len(parts) != 2:
            raise ValueError("origin must be x,z: %s" % value)
        origins.append((float(parts[0]), float(parts[1])))
    return origins


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--size-m", type=float, default=8192.0)
    parser.add_argument("--resolution-m", type=float, default=64.0)
    parser.add_argument("--region-size-m", type=float, default=32768.0)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument("--origin", action="append", help="Add an x,z origin in meters. May be repeated.")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    origins = parse_origins(args.origin)
    _catalog_path, kernels = hf.load_catalog(str(args.catalog))
    pool = hf.choose_kernel_pool(kernels, int(args.max_per_family))
    loaded = hf.load_kernel_arrays(pool)
    if not any(loaded.values()):
        raise RuntimeError("no kernel arrays loaded")

    samples = int(round(float(args.size_m) / float(args.resolution_m))) + 1
    records: list[dict[str, Any]] = []
    normalized_height_windows: list[np.ndarray] = []
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    for index, (origin_x, origin_z) in enumerate(origins):
        xs = origin_x + np.arange(samples, dtype=np.float64) * float(args.resolution_m)
        zs = origin_z + np.arange(samples, dtype=np.float64) * float(args.resolution_m)
        xg, zg = np.meshgrid(xs, zs)
        layers = hf.sample_height_layers(xg, zg, loaded, int(args.seed), float(args.region_size_m))
        height = layers["height"]
        region = layers["region"]
        slope = hf.slope_degrees(height, float(args.resolution_m))
        norm = normalize_u8(height)
        normalized_height_windows.append(norm)
        name = f"window_{index:02d}"
        image_paths = save_panel_images(out_dir, name, height, region, float(args.resolution_m)) if not args.dry_run else {}
        records.append(
            {
                "name": name,
                "origin": [float(origin_x), float(origin_z)],
                "size_m": float(args.size_m),
                "resolution_m": float(args.resolution_m),
                "samples": samples,
                "height_min_m": float(np.min(height)),
                "height_max_m": float(np.max(height)),
                "height_range_m": float(np.max(height) - np.min(height)),
                "height_std_m": float(np.std(height)),
                "slope_mean_deg": float(np.mean(slope)),
                "slope_p95_deg": float(np.percentile(slope, 95.0)),
                "visual_hash": visual_hash(height),
                **image_paths,
            }
        )

    pair_reports = []
    max_abs_corr = 0.0
    for i in range(len(records)):
        for j in range(i + 1, len(records)):
            corr = correlation(normalized_height_windows[i], normalized_height_windows[j])
            max_abs_corr = max(max_abs_corr, abs(corr))
            if abs(corr) >= 0.94:
                pair_reports.append(
                    {
                        "a": records[i]["name"],
                        "b": records[j]["name"],
                        "height_corr": corr,
                    }
                )

    hashes = [record["visual_hash"] for record in records]
    duplicate_hashes = sorted({value for value in hashes if hashes.count(value) > 1})
    max_slope_p95 = max(float(record["slope_p95_deg"]) for record in records)
    max_height_range = max(float(record["height_range_m"]) for record in records)
    min_height_range = min(float(record["height_range_m"]) for record in records)
    errors = []
    if duplicate_hashes:
        errors.append("duplicate_visual_hash")
    if max_abs_corr >= 0.995:
        errors.append("near_duplicate_window_correlation")
    if max_slope_p95 > 58.0:
        errors.append("slope_p95_above_58")
    if max_height_range > 1800.0:
        errors.append("height_range_above_1800")
    if min_height_range < 120.0:
        errors.append("height_range_below_120")

    summary = {
        "version": 1,
        "schema": "worldgen9.infinite_travel_probe.v1",
        "seed": int(args.seed),
        "window_count": len(records),
        "size_m": float(args.size_m),
        "resolution_m": float(args.resolution_m),
        "region_size_m": float(args.region_size_m),
        "samples_per_side": samples,
        "max_abs_height_window_correlation": max_abs_corr,
        "high_correlation_pairs": pair_reports,
        "duplicate_visual_hashes": duplicate_hashes,
        "max_slope_p95_deg": max_slope_p95,
        "max_height_range_m": max_height_range,
        "min_height_range_m": min_height_range,
        "records": records,
        "contact_sheet": "infinite_travel_contact_sheet.png",
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }

    if not args.dry_run:
        write_json(out_dir / "infinite_travel_report.json", summary)
        save_contact_sheet(records, out_dir, out_dir / "infinite_travel_contact_sheet.png")
    print("[infinite-travel] status=%s windows=%d max_corr=%.4f max_p95_slope=%.1f" % (
        summary["status"],
        len(records),
        max_abs_corr,
        max_slope_p95,
    ))
    if errors:
        for error in errors:
            print("[infinite-travel] error: %s" % error)
    return 0 if summary["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
