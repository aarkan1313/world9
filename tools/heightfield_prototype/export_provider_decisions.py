#!/usr/bin/env python3
"""Export low-level height-provider decisions for future runtime parity tests."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT = ROOT / "factory" / "runtime" / "provider_decisions" / "provider_decisions_reference.json"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_provider(catalog: Path, max_per_family: int) -> tuple[Path, dict[str, list[dict[str, Any]]]]:
    catalog_path, kernels = hf.load_catalog(str(catalog))
    pool = hf.choose_kernel_pool(kernels, max_per_family)
    loaded = hf.load_kernel_arrays(pool)
    if not any(loaded.values()):
        raise RuntimeError("no kernel arrays loaded")
    return catalog_path, loaded


def parse_points(value: str) -> list[tuple[float, float]]:
    points = []
    for part in value.split(";"):
        if not part.strip():
            continue
        x_text, z_text = part.split(",", 1)
        points.append((float(x_text.strip()), float(z_text.strip())))
    return points


def smooth_scalar(value: float) -> float:
    return float(value * value * (3.0 - 2.0 * value))


def family_biases(rx: int, rz: int, seed: int) -> list[float]:
    biases = [0.55, 0.30, 0.15]
    roll = hf.stable_hash("family_roll", rx, rz, seed) % 3
    return biases[-roll:] + biases[:-roll] if roll else biases


def kernel_transform(kernel_id: str, rx: int, rz: int, seed: int, region_size_m: float) -> dict[str, Any]:
    scale_span = int(hf.KERNEL_WORLD_SCALE_SPAN_REGION_MULTIPLIER * 1000)
    scale_jitter = (hf.stable_hash("scale", kernel_id, rx, rz, seed) % scale_span) / 1000.0
    scale_multiplier = hf.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER + scale_jitter
    return {
        "scale_multiplier": round(float(scale_multiplier), 6),
        "world_scale_m": round(float(region_size_m * scale_multiplier), 6),
        "rotation_quadrants": int(hf.stable_hash("rot", kernel_id, rx, rz, seed) % 4),
        "offset_u": round((hf.stable_hash("offu", kernel_id, rx, rz, seed) % 10000) / 10000.0, 6),
        "offset_v": round((hf.stable_hash("offv", kernel_id, rx, rz, seed) % 10000) / 10000.0, 6),
    }


def scalar_layers(x: float, z: float, loaded: dict[str, list[dict[str, Any]]], seed: int, region_size_m: float) -> dict[str, float]:
    xa = np.array([[x]], dtype=np.float64)
    za = np.array([[z]], dtype=np.float64)
    layers = hf.sample_height_layers(xa, za, loaded, seed, region_size_m)
    return {key: float(value[0, 0]) for key, value in layers.items()}


def provider_decision(
    x: float,
    z: float,
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> dict[str, Any]:
    gx = x / region_size_m
    gz = z / region_size_m
    rx = int(np.floor(gx))
    rz = int(np.floor(gz))
    tx = smooth_scalar(gx - rx)
    tz = smooth_scalar(gz - rz)
    corner_defs = [
        (rx, rz, (1.0 - tx) * (1.0 - tz)),
        (rx + 1, rz, tx * (1.0 - tz)),
        (rx, rz + 1, (1.0 - tx) * tz),
        (rx + 1, rz + 1, tx * tz),
    ]

    corners = []
    for crx, crz, corner_weight in corner_defs:
        palette, families = hf.region_info(crx, crz, seed)
        biases = family_biases(crx, crz, seed)
        entries = []
        for family, bias in zip(families, biases):
            kernel = hf.kernel_for_family(loaded, family, seed, crx, crz)
            if not kernel:
                continue
            kernel_id = str(kernel["kernel_id"])
            params = kernel.get("runtime_family", hf.FAMILY_WEIGHTS.get(family, hf.FAMILY_WEIGHTS["uncategorized"]))
            moderation = hf.kernel_runtime_moderation(kernel)
            entries.append(
                {
                    "family": family,
                    "family_bias": float(bias),
                    "corner_family_weight": float(corner_weight * bias),
                    "kernel_id": kernel_id,
                    "kernel_slope_p95_deg": float(kernel.get("slope_p95_deg", 0.0) or 0.0),
                    "kernel_moderation": float(moderation),
                    "relief_scale_m": float(params["relief"]),
                    "detail_scale_m": float(params["detail"]),
                    "effective_relief_scale_m": float(params["relief"] * moderation),
                    "effective_detail_scale_m": float(params["detail"] * moderation),
                    "transform": kernel_transform(kernel_id, crx, crz, seed, region_size_m),
                }
            )
        corners.append(
            {
                "region": [crx, crz],
                "province": [crx // hf.PROVINCE_SIZE_REGIONS, crz // hf.PROVINCE_SIZE_REGIONS],
                "corner_salt": 0,
                "corner_weight": float(corner_weight),
                "palette": palette,
                "families": entries,
            }
        )

    layers = scalar_layers(x, z, loaded, seed, region_size_m)
    return {
        "world_x": float(x),
        "world_z": float(z),
        "base_region": [rx, rz],
        "region_fraction": [float(gx - rx), float(gz - rz)],
        "smooth_fraction": [tx, tz],
        "corner_weight_sum": float(sum(corner["corner_weight"] for corner in corners)),
        "corners": corners,
        "height_m": layers["height"],
        "macro_height_m": layers["macro"],
        "kernel_relief_m": layers["relief"],
        "detail_height_m": layers["detail"],
        "valley_adjust_m": layers["valley"],
        "region_debug_value": layers["region"],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--region-size-m", type=float, default=32768.0)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument(
        "--points",
        default="0,0;2048,0;2048,2048;12345,-6789;32768,32768;49152,16384;-32768,65536",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog_path, loaded = load_provider(Path(args.catalog), int(args.max_per_family))
    points = parse_points(str(args.points))
    decisions = [
        provider_decision(x, z, loaded, int(args.seed), float(args.region_size_m))
        for x, z in points
    ]
    repeat = [
        provider_decision(x, z, loaded, int(args.seed), float(args.region_size_m))
        for x, z in points
    ]
    errors = []
    for index, decision in enumerate(decisions):
        if abs(decision["corner_weight_sum"] - 1.0) > 1e-9:
            errors.append(f"corner_weight_sum:{index}")
        if decision != repeat[index]:
            errors.append(f"nondeterministic_decision:{index}")
        if not all(corner["families"] for corner in decision["corners"]):
            errors.append(f"missing_corner_family:{index}")
    result = {
        "version": 1,
        "schema": "worldgen9.provider_decisions.v1",
        "catalog": str(catalog_path).replace("\\", "/"),
        "seed": int(args.seed),
        "region_size_m": float(args.region_size_m),
        "province_size_regions": hf.PROVINCE_SIZE_REGIONS,
        "kernel_world_scale_min_region_multiplier": hf.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER,
        "kernel_world_scale_max_region_multiplier": hf.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER
        + hf.KERNEL_WORLD_SCALE_SPAN_REGION_MULTIPLIER,
        "decisions": decisions,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    if not args.dry_run:
        write_json(Path(args.out), result)
    print("[provider-decisions] points=%d status=%s" % (len(points), result["status"]))
    if not args.dry_run:
        print("[provider-decisions] out=%s" % args.out)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
