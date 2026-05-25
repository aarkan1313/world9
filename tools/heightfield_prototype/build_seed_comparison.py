#!/usr/bin/env python3
"""Build a compact multi-seed visual comparison from the runtime kernel pack."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT_DIR = ROOT / "prototypes" / "seed_compare_runtime_v1"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def open_panel(path: str, size: tuple[int, int]) -> Image.Image:
    img = Image.open(path).convert("RGB")
    img.thumbnail(size, Image.Resampling.LANCZOS)
    panel = Image.new("RGB", size, (24, 26, 28))
    x = (size[0] - img.width) // 2
    y = (size[1] - img.height) // 2
    panel.paste(img, (x, y))
    return panel


def save_contact_sheet(results: list[dict[str, Any]], out_path: Path) -> None:
    cols = [
        ("height_png", "height"),
        ("hillshade_png", "hillshade"),
        ("color_relief_png", "relief"),
        ("region_png", "regions"),
    ]
    cell = (260, 260)
    label_h = 42
    header_h = 34
    sheet_w = cell[0] * len(cols)
    sheet_h = header_h + len(results) * (cell[1] + label_h)
    sheet = Image.new("RGB", (sheet_w, sheet_h), (18, 20, 22))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
        small = ImageFont.truetype("arial.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
        small = font

    for col, (_key, label) in enumerate(cols):
        draw.text((col * cell[0] + 10, 9), label, fill=(220, 222, 224), font=font)

    for row, result in enumerate(results):
        y0 = header_h + row * (cell[1] + label_h)
        for col, (key, _label) in enumerate(cols):
            panel = open_panel(result[key], cell)
            sheet.paste(panel, (col * cell[0], y0))
        label = (
            f"seed {result['seed']}  range {result['height_range_m']:.0f}m  "
            f"p95 slope {result['slope_p95_deg']:.1f}  detail std {result['detail_std_m']:.1f}"
        )
        draw.text((10, y0 + cell[1] + 11), label, fill=(220, 222, 224), font=small)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--seeds", nargs="+", type=int, default=[1337, 2049, 4099, 8191])
    parser.add_argument("--size-m", type=float, default=8192.0)
    parser.add_argument("--resolution-m", type=float, default=32.0)
    parser.add_argument("--region-size-m", type=float, default=16384.0)
    parser.add_argument("--max-per-family", type=int, default=12)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    catalog_path, kernels = hf.load_catalog(str(args.catalog))
    pool = hf.choose_kernel_pool(kernels, int(args.max_per_family))
    loaded = hf.load_kernel_arrays(pool)
    loaded_counts = {family: len(items) for family, items in sorted(loaded.items()) if items}
    if not loaded_counts:
        raise RuntimeError("no kernel arrays loaded")

    results = []
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
    for seed in args.seeds:
        seed_dir = out_dir / f"seed_{seed}"
        if not args.dry_run:
            seed_dir.mkdir(parents=True, exist_ok=True)
        result = hf.generate_tile(
            seed_dir,
            "preview",
            0.0,
            0.0,
            float(args.size_m),
            float(args.resolution_m),
            loaded,
            int(seed),
            float(args.region_size_m),
        )
        result["seed"] = int(seed)
        result["out_dir"] = str(seed_dir).replace("\\", "/")
        results.append(result)

    summary = {
        "version": 1,
        "schema": "worldgen9.seed_comparison.v1",
        "catalog": str(catalog_path).replace("\\", "/"),
        "seeds": [int(seed) for seed in args.seeds],
        "size_m": float(args.size_m),
        "resolution_m": float(args.resolution_m),
        "region_size_m": float(args.region_size_m),
        "loaded_family_counts": loaded_counts,
        "results": results,
        "contact_sheet": str(out_dir / "seed_comparison_contact_sheet.png").replace("\\", "/"),
    }
    if not args.dry_run:
        write_json(out_dir / "seed_comparison_summary.json", summary)
        save_contact_sheet(results, out_dir / "seed_comparison_contact_sheet.png")
    print("[seed-compare] catalog=%s kernels=%d" % (catalog_path, len(kernels)))
    print("[seed-compare] seeds=%s out=%s" % (list(args.seeds), out_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
