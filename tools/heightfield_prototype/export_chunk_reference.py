#!/usr/bin/env python3
"""Export reference chunk height grids for runtime parity tests."""
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
DEFAULT_OUT_DIR = ROOT / "factory" / "runtime" / "chunk_reference"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def sha256_array(arr: np.ndarray) -> str:
    contiguous = np.ascontiguousarray(arr)
    return hashlib.sha256(contiguous.tobytes()).hexdigest()


def load_provider(catalog: Path, max_per_family: int) -> tuple[Path, dict[str, list[dict[str, Any]]]]:
    catalog_path, kernels = hf.load_catalog(str(catalog))
    pool = hf.choose_kernel_pool(kernels, max_per_family)
    loaded = hf.load_kernel_arrays(pool)
    if not any(loaded.values()):
        raise RuntimeError("no kernel arrays loaded")
    return catalog_path, loaded


def sample_chunk(
    chunk_x: int,
    chunk_z: int,
    chunk_size_m: float,
    vertices_per_side: int,
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> dict[str, Any]:
    step_m = chunk_size_m / float(vertices_per_side - 1)
    origin_x = float(chunk_x) * chunk_size_m
    origin_z = float(chunk_z) * chunk_size_m
    values = np.arange(vertices_per_side, dtype=np.float64) * step_m
    xg, zg = np.meshgrid(origin_x + values, origin_z + values)
    layers = hf.sample_height_layers(xg, zg, loaded, seed, region_size_m)
    height = layers["height"].astype(np.float32)
    return {
        "chunk_x": chunk_x,
        "chunk_z": chunk_z,
        "origin": [origin_x, origin_z],
        "step_m": step_m,
        "height": height,
        "height_min_m": float(np.min(height)),
        "height_max_m": float(np.max(height)),
        "height_mean_m": float(np.mean(height)),
        "height_std_m": float(np.std(height)),
        "height_sha256": sha256_array(height),
    }


def edge_delta(a: np.ndarray, b: np.ndarray, side: str) -> dict[str, Any]:
    if side == "east_west":
        delta = np.abs(a[:, -1] - b[:, 0])
    elif side == "north_south":
        delta = np.abs(a[-1, :] - b[0, :])
    else:
        raise ValueError(side)
    return {
        "side": side,
        "samples": int(delta.size),
        "mean_abs_delta_m": float(np.mean(delta)),
        "p95_abs_delta_m": float(np.percentile(delta, 95.0)),
        "max_abs_delta_m": float(np.max(delta)),
        "delta_sha256": sha256_array(delta.astype(np.float32)),
    }


def height_rgb(arr: np.ndarray, low: float, high: float) -> Image.Image:
    span = max(1e-6, high - low)
    gray = np.clip((arr - low) / span * 255.0, 0.0, 255.0).astype(np.uint8)
    return Image.fromarray(gray, mode="L").convert("RGB")


def save_contact_sheet(chunks: list[dict[str, Any]], path: Path) -> None:
    low = min(float(np.min(chunk["height"])) for chunk in chunks)
    high = max(float(np.max(chunk["height"])) for chunk in chunks)
    tile = 220
    label_h = 34
    sheet = Image.new("RGB", (tile * 2, (tile + label_h) * 2), (22, 24, 24))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
    except Exception:
        font = ImageFont.load_default()
    for chunk in chunks:
        cx = int(chunk["chunk_x"])
        cz = int(chunk["chunk_z"])
        x = cx * tile
        y = cz * (tile + label_h)
        img = height_rgb(chunk["height"], low, high).resize((tile, tile), Image.Resampling.BILINEAR)
        sheet.paste(img, (x, y))
        draw.rectangle((x, y + tile, x + tile, y + tile + label_h), fill=(18, 18, 18))
        label = "chunk %+d,%+d  %.1f..%.1fm" % (cx, cz, chunk["height_min_m"], chunk["height_max_m"])
        draw.text((x + 6, y + tile + 9), label, fill=(232, 232, 232), font=font)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--region-size-m", type=float, default=32768.0)
    parser.add_argument("--chunk-size-m", type=float, default=2048.0)
    parser.add_argument("--vertices-per-side", type=int, default=129)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if int(args.vertices_per_side) < 2:
        raise RuntimeError("--vertices-per-side must be at least 2")
    catalog_path, loaded = load_provider(Path(args.catalog), int(args.max_per_family))
    out_dir = Path(args.out_dir)
    chunk_coords = [(0, 0), (1, 0), (0, 1), (1, 1)]
    chunks = [
        sample_chunk(cx, cz, float(args.chunk_size_m), int(args.vertices_per_side), loaded, int(args.seed), float(args.region_size_m))
        for cx, cz in chunk_coords
    ]
    by_coord = {(chunk["chunk_x"], chunk["chunk_z"]): chunk for chunk in chunks}
    edge_reports = [
        {
            "chunk_a": [0, 0],
            "chunk_b": [1, 0],
            **edge_delta(by_coord[(0, 0)]["height"], by_coord[(1, 0)]["height"], "east_west"),
        },
        {
            "chunk_a": [0, 0],
            "chunk_b": [0, 1],
            **edge_delta(by_coord[(0, 0)]["height"], by_coord[(0, 1)]["height"], "north_south"),
        },
        {
            "chunk_a": [0, 1],
            "chunk_b": [1, 1],
            **edge_delta(by_coord[(0, 1)]["height"], by_coord[(1, 1)]["height"], "east_west"),
        },
        {
            "chunk_a": [1, 0],
            "chunk_b": [1, 1],
            **edge_delta(by_coord[(1, 0)]["height"], by_coord[(1, 1)]["height"], "north_south"),
        },
    ]
    failed = any(report["max_abs_delta_m"] != 0.0 for report in edge_reports)

    manifest_chunks = []
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
    for chunk in chunks:
        file_name = "chunk_%+d_%+d_height_m.npy" % (chunk["chunk_x"], chunk["chunk_z"])
        out_path = out_dir / file_name
        if not args.dry_run:
            np.save(out_path, chunk["height"])
        manifest_chunks.append(
            {
                "chunk": [chunk["chunk_x"], chunk["chunk_z"]],
                "origin": chunk["origin"],
                "height_npy": file_name,
                "height_min_m": chunk["height_min_m"],
                "height_max_m": chunk["height_max_m"],
                "height_mean_m": chunk["height_mean_m"],
                "height_std_m": chunk["height_std_m"],
                "height_sha256": chunk["height_sha256"],
            }
        )

    manifest = {
        "version": 1,
        "schema": "worldgen9.chunk_reference.v1",
        "catalog": str(catalog_path).replace("\\", "/"),
        "seed": int(args.seed),
        "region_size_m": float(args.region_size_m),
        "chunk_size_m": float(args.chunk_size_m),
        "vertices_per_side": int(args.vertices_per_side),
        "step_m": float(args.chunk_size_m) / float(int(args.vertices_per_side) - 1),
        "chunks": manifest_chunks,
        "edge_reports": edge_reports,
        "visual_contact_sheet": "chunk_reference_contact_sheet.png",
        "status": "fail" if failed else "pass",
    }
    if not args.dry_run:
        write_json(out_dir / "chunk_reference_manifest.json", manifest)
        save_contact_sheet(chunks, out_dir / "chunk_reference_contact_sheet.png")
    print("[chunk-reference] chunks=%d vertices=%d status=%s" % (len(chunks), int(args.vertices_per_side), manifest["status"]))
    for report in edge_reports:
        print(
            "[chunk-reference] %s %s->%s max=%.9f"
            % (report["side"], report["chunk_a"], report["chunk_b"], report["max_abs_delta_m"])
        )
    if not args.dry_run:
        print("[chunk-reference] out=%s" % out_dir)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
