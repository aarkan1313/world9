#!/usr/bin/env python3
"""Emit TerrainSample V1 reference values from the Python height provider."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT = ROOT / "factory" / "runtime" / "terrain_sample_reference.json"

SOURCE_PROCEDURAL_MACRO = 1
SOURCE_DEM_KERNEL_RELIEF = 2
SOURCE_RESIDUAL_DETAIL = 4
SOURCE_VALLEY_HINT = 8
SOURCE_MASK_CURRENT = SOURCE_PROCEDURAL_MACRO | SOURCE_DEM_KERNEL_RELIEF | SOURCE_RESIDUAL_DETAIL | SOURCE_VALLEY_HINT

FAMILY_IDS = {
    "unknown": 0,
    "mountain": 1,
    "glacial": 2,
    "badlands": 3,
    "desert": 4,
    "karst": 5,
    "coast": 6,
    "grassland": 7,
    "rainforest": 8,
    "volcanic": 9,
}


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_provider(catalog: Path, max_per_family: int) -> tuple[Path, dict[str, list[dict[str, Any]]], dict[str, int]]:
    catalog_path, kernels = hf.load_catalog(str(catalog))
    pool = hf.choose_kernel_pool(kernels, max_per_family)
    loaded = hf.load_kernel_arrays(pool)
    if not any(loaded.values()):
        raise RuntimeError("no kernel arrays loaded")
    kernel_ids = sorted(kernel["kernel_id"] for items in loaded.values() for kernel in items)
    kernel_index = {kernel_id: index + 1 for index, kernel_id in enumerate(kernel_ids)}
    return catalog_path, loaded, kernel_index


def scalar_layers(x: float, z: float, loaded: dict[str, list[dict[str, Any]]], seed: int, region_size_m: float) -> dict[str, float]:
    xa = np.array([[x]], dtype=np.float64)
    za = np.array([[z]], dtype=np.float64)
    layers = hf.sample_height_layers(xa, za, loaded, seed, region_size_m)
    return {key: float(value[0, 0]) for key, value in layers.items()}


def primary_families(x: float, z: float, seed: int, region_size_m: float) -> tuple[str, str, float, int]:
    xa = np.array([[x]], dtype=np.float64)
    za = np.array([[z]], dtype=np.float64)
    weights, palette_id = hf.palette_weights(xa, za, seed, region_size_m)
    ranked = sorted(((family, float(values[0, 0])) for family, values in weights.items()), key=lambda item: item[1], reverse=True)
    primary = ranked[0] if ranked else ("unknown", 1.0)
    secondary = ranked[1] if len(ranked) > 1 else ("unknown", 0.0)
    return primary[0], secondary[0], primary[1], int(round(float(palette_id[0, 0])))


def kernel_id_for_point(loaded: dict[str, list[dict[str, Any]]], family: str, x: float, z: float, seed: int, region_size_m: float) -> str:
    rx = int(np.floor(x / region_size_m))
    rz = int(np.floor(z / region_size_m))
    kernel = hf.kernel_for_family(loaded, family, seed, rx, rz)
    if not kernel:
        return ""
    return str(kernel["kernel_id"])


def slope_hint(x: float, z: float, loaded: dict[str, list[dict[str, Any]]], seed: int, region_size_m: float, step_m: float) -> float:
    h_x0 = scalar_layers(x - step_m, z, loaded, seed, region_size_m)["height"]
    h_x1 = scalar_layers(x + step_m, z, loaded, seed, region_size_m)["height"]
    h_z0 = scalar_layers(x, z - step_m, loaded, seed, region_size_m)["height"]
    h_z1 = scalar_layers(x, z + step_m, loaded, seed, region_size_m)["height"]
    gx = (h_x1 - h_x0) / max(1e-6, step_m * 2.0)
    gz = (h_z1 - h_z0) / max(1e-6, step_m * 2.0)
    return float(np.degrees(np.arctan(np.sqrt(gx * gx + gz * gz))))


def terrain_sample(
    x: float,
    z: float,
    loaded: dict[str, list[dict[str, Any]]],
    kernel_index: dict[str, int],
    seed: int,
    region_size_m: float,
    slope_step_m: float,
) -> dict[str, Any]:
    layers = scalar_layers(x, z, loaded, seed, region_size_m)
    primary, secondary, primary_weight, region_id = primary_families(x, z, seed, region_size_m)
    kernel_a = kernel_id_for_point(loaded, primary, x, z, seed, region_size_m)
    kernel_b = kernel_id_for_point(loaded, secondary, x, z, seed, region_size_m)
    return {
        "world_x": float(x),
        "world_z": float(z),
        "height_m": layers["height"],
        "valid": True,
        "source_mask": SOURCE_MASK_CURRENT,
        "region_id": region_id,
        "primary_family_id": FAMILY_IDS.get(primary, 0),
        "primary_family": primary,
        "secondary_family_id": FAMILY_IDS.get(secondary, 0),
        "secondary_family": secondary,
        "kernel_a_id": kernel_index.get(kernel_a, 0),
        "kernel_a": kernel_a,
        "kernel_b_id": kernel_index.get(kernel_b, 0),
        "kernel_b": kernel_b,
        "blend_weight": primary_weight,
        "macro_height_m": layers["macro"],
        "kernel_relief_m": layers["relief"],
        "detail_height_m": layers["detail"],
        "valley_adjust_m": layers["valley"],
        "slope_hint": slope_hint(x, z, loaded, seed, region_size_m, slope_step_m),
        "roughness_hint": abs(layers["detail"]),
        "confidence": max(0.0, min(1.0, primary_weight)),
    }


def parse_points(value: str) -> list[tuple[float, float]]:
    points = []
    for part in value.split(";"):
        if not part.strip():
            continue
        x_text, z_text = part.split(",", 1)
        points.append((float(x_text.strip()), float(z_text.strip())))
    return points


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--region-size-m", type=float, default=32768.0)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument("--slope-step-m", type=float, default=32.0)
    parser.add_argument("--points", default="0,0;2048,0;2048,2048;12345,-6789;32768,32768")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog_path, loaded, kernel_index = load_provider(Path(args.catalog), int(args.max_per_family))
    samples = [
        terrain_sample(x, z, loaded, kernel_index, int(args.seed), float(args.region_size_m), float(args.slope_step_m))
        for x, z in parse_points(str(args.points))
    ]
    repeat_samples = [
        terrain_sample(x, z, loaded, kernel_index, int(args.seed), float(args.region_size_m), float(args.slope_step_m))
        for x, z in parse_points(str(args.points))
    ]
    max_height_repeat_delta = max(abs(a["height_m"] - b["height_m"]) for a, b in zip(samples, repeat_samples)) if samples else 0.0
    result = {
        "version": 1,
        "schema": "worldgen9.terrain_sample_reference.v1",
        "catalog": str(catalog_path).replace("\\", "/"),
        "seed": int(args.seed),
        "region_size_m": float(args.region_size_m),
        "source_mask_bits": {
            "procedural_macro": SOURCE_PROCEDURAL_MACRO,
            "dem_kernel_relief": SOURCE_DEM_KERNEL_RELIEF,
            "residual_detail": SOURCE_RESIDUAL_DETAIL,
            "valley_hint": SOURCE_VALLEY_HINT,
        },
        "family_ids": FAMILY_IDS,
        "kernel_ids": {str(value): key for key, value in kernel_index.items()},
        "max_height_repeat_delta_m": max_height_repeat_delta,
        "samples": samples,
        "status": "pass" if max_height_repeat_delta == 0.0 else "fail",
    }
    if not args.dry_run:
        write_json(Path(args.out), result)
    print("[terrain-sample-reference] samples=%d status=%s max_repeat_delta=%.9f" % (len(samples), result["status"], max_height_repeat_delta))
    if not args.dry_run:
        print("[terrain-sample-reference] out=%s" % args.out)
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

