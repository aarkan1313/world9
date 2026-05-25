#!/usr/bin/env python3
"""Analyze deterministic terrain-region grammar for variety and continuity."""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT_DIR = ROOT / "factory" / "runtime" / "region_grammar"

PALETTE_COLORS = {
    "alpine": (104, 132, 178),
    "drylands": (191, 139, 74),
    "humid_hills": (80, 149, 98),
    "volcanic_coast": (150, 84, 126),
    "coastal_ridges": (82, 148, 170),
    "open_steppe": (164, 164, 98),
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_kernel_ids_by_family(catalog: Path, max_per_family: int) -> dict[str, list[str]]:
    catalog_path, kernels = hf.load_catalog(str(catalog))
    pool = hf.choose_kernel_pool(kernels, max_per_family)
    result: dict[str, list[str]] = {}
    for family, items in pool.items():
        ids = [str(item.get("kernel_id", "")) for item in items if item.get("kernel_id")]
        if ids:
            result[family] = ids
    if not result:
        raise RuntimeError(f"no kernel ids available from {catalog_path}")
    return result


def family_bias_order(rx: int, rz: int, seed: int) -> list[float]:
    values = [0.55, 0.30, 0.15]
    roll = hf.stable_hash("family_roll", rx, rz, seed, 0) % 3
    return values[-roll:] + values[:-roll] if roll else values


def selected_kernel_id(family: str, rx: int, rz: int, seed: int, ids_by_family: dict[str, list[str]]) -> str:
    ids = ids_by_family.get(family) or []
    if not ids:
        return ""
    idx = hf.stable_hash("kernel", family, rx, rz, seed) % len(ids)
    return ids[idx]


def kernel_transform_signature(kernel_id: str, rx: int, rz: int, seed: int) -> dict[str, int]:
    scale_span = int(hf.KERNEL_WORLD_SCALE_SPAN_REGION_MULTIPLIER * 1000)
    scale_jitter = hf.stable_hash("scale", kernel_id, rx, rz, seed) % scale_span
    return {
        "scale_multiplier_milli": int(hf.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER * 1000) + scale_jitter,
        "rotation_quadrants": hf.stable_hash("rot", kernel_id, rx, rz, seed) % 4,
        "offset_u_10000": hf.stable_hash("offu", kernel_id, rx, rz, seed) % 10000,
        "offset_v_10000": hf.stable_hash("offv", kernel_id, rx, rz, seed) % 10000,
    }


def region_record(rx: int, rz: int, seed: int, ids_by_family: dict[str, list[str]]) -> dict[str, Any]:
    palette, families = hf.region_info(rx, rz, seed)
    biases = family_bias_order(rx, rz, seed)
    family_entries = []
    for family, bias in zip(families, biases):
        kernel_id = selected_kernel_id(family, rx, rz, seed, ids_by_family)
        family_entries.append(
            {
                "family": family,
                "weight": bias,
                "kernel_id": kernel_id,
                "transform": kernel_transform_signature(kernel_id, rx, rz, seed) if kernel_id else {},
            }
        )
    signature_parts = [palette]
    for entry in family_entries:
        transform = entry["transform"]
        signature_parts.append(
            "%s:%s:%.2f:%s:%s:%s:%s"
            % (
                entry["family"],
                entry["kernel_id"],
                entry["weight"],
                transform.get("scale_multiplier_milli", ""),
                transform.get("rotation_quadrants", ""),
                transform.get("offset_u_10000", ""),
                transform.get("offset_v_10000", ""),
            )
        )
    signature = "|".join(signature_parts)
    return {
        "rx": rx,
        "rz": rz,
        "province": [rx // hf.PROVINCE_SIZE_REGIONS, rz // hf.PROVINCE_SIZE_REGIONS],
        "palette": palette,
        "families": family_entries,
        "signature": signature,
    }


def max_run_length(grid: list[list[str]]) -> int:
    best = 0
    for row in grid:
        current = 0
        previous = None
        for value in row:
            current = current + 1 if value == previous else 1
            previous = value
            best = max(best, current)
    cols = len(grid[0])
    for col in range(cols):
        current = 0
        previous = None
        for row in grid:
            value = row[col]
            current = current + 1 if value == previous else 1
            previous = value
            best = max(best, current)
    return best


def adjacency_fraction(grid: list[list[str]]) -> float:
    same = 0
    total = 0
    for z, row in enumerate(grid):
        for x, value in enumerate(row):
            if x + 1 < len(row):
                total += 1
                same += int(value == row[x + 1])
            if z + 1 < len(grid):
                total += 1
                same += int(value == grid[z + 1][x])
    return same / max(1, total)


def save_map(records: list[dict[str, Any]], extent: int, out_path: Path) -> None:
    size = extent * 2 + 1
    cell = 18
    legend_w = 220
    image = Image.new("RGB", (size * cell + legend_w, size * cell), (18, 20, 22))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("arial.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    for record in records:
        x = (int(record["rx"]) + extent) * cell
        z = (int(record["rz"]) + extent) * cell
        color = PALETTE_COLORS.get(str(record["palette"]), (128, 128, 128))
        draw.rectangle((x, z, x + cell - 1, z + cell - 1), fill=color)
        if record["rx"] % hf.PROVINCE_SIZE_REGIONS == 0:
            draw.line((x, z, x, z + cell - 1), fill=(28, 30, 32))
        if record["rz"] % hf.PROVINCE_SIZE_REGIONS == 0:
            draw.line((x, z, x + cell - 1, z), fill=(28, 30, 32))
    lx = size * cell + 12
    ly = 14
    for name, color in PALETTE_COLORS.items():
        draw.rectangle((lx, ly, lx + 14, ly + 14), fill=color)
        draw.text((lx + 22, ly), name, fill=(224, 226, 228), font=font)
        ly += 24
    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--extent-regions", type=int, default=24)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    extent = int(args.extent_regions)
    ids_by_family = load_kernel_ids_by_family(Path(args.catalog), int(args.max_per_family))
    records = [
        region_record(rx, rz, int(args.seed), ids_by_family)
        for rz in range(-extent, extent + 1)
        for rx in range(-extent, extent + 1)
    ]
    size = extent * 2 + 1
    palette_grid = [
        [records[z * size + x]["palette"] for x in range(size)]
        for z in range(size)
    ]
    signature_grid = [
        [records[z * size + x]["signature"] for x in range(size)]
        for z in range(size)
    ]
    palette_counts = Counter(str(record["palette"]) for record in records)
    family_counts = Counter(entry["family"] for record in records for entry in record["families"])
    kernel_counts = Counter(entry["kernel_id"] for record in records for entry in record["families"] if entry["kernel_id"])
    unique_signatures = len({record["signature"] for record in records})
    total_regions = len(records)
    palette_adjacent = adjacency_fraction(palette_grid)
    signature_adjacent = adjacency_fraction(signature_grid)
    report = {
        "version": 1,
        "schema": "worldgen9.region_grammar.v1",
        "seed": int(args.seed),
        "extent_regions": extent,
        "province_size_regions": hf.PROVINCE_SIZE_REGIONS,
        "total_regions": total_regions,
        "palette_counts": dict(sorted(palette_counts.items())),
        "family_presence_counts": dict(sorted(family_counts.items())),
        "unique_region_signatures": unique_signatures,
        "unique_region_signature_fraction": round(unique_signatures / total_regions, 6),
        "same_palette_adjacent_fraction": round(palette_adjacent, 6),
        "same_signature_adjacent_fraction": round(signature_adjacent, 6),
        "max_palette_fraction": round(max(palette_counts.values()) / total_regions, 6),
        "max_palette_run_regions": max_run_length(palette_grid),
        "kernel_usage_min": min(kernel_counts.values()) if kernel_counts else 0,
        "kernel_usage_max": max(kernel_counts.values()) if kernel_counts else 0,
        "kernel_usage_unique": len(kernel_counts),
        "visual_map": "region_palette_map.png",
        "sample_records": records[:20],
    }
    errors = []
    if len(palette_counts) != len(hf.REGION_PALETTES):
        errors.append("not_all_palettes_used")
    if not (0.35 <= palette_adjacent <= 0.80):
        errors.append("palette_adjacency_out_of_range")
    if signature_adjacent > 0.12:
        errors.append("too_many_adjacent_identical_signatures")
    if report["unique_region_signature_fraction"] < 0.95:
        errors.append("low_unique_region_signature_fraction")
    if report["max_palette_fraction"] > 0.35:
        errors.append("palette_distribution_too_dominant")
    report["errors"] = errors
    report["status"] = "pass" if not errors else "review"

    out_dir = Path(args.out_dir)
    if not args.dry_run:
        write_json(out_dir / "region_grammar_report.json", report)
        save_map(records, extent, out_dir / "region_palette_map.png")
    print(
        "[region-grammar] regions=%d palettes=%d same_palette=%.3f unique=%.3f status=%s"
        % (
            total_regions,
            len(palette_counts),
            palette_adjacent,
            report["unique_region_signature_fraction"],
            report["status"],
        )
    )
    if not args.dry_run:
        print("[region-grammar] out=%s" % out_dir)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
