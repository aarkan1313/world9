#!/usr/bin/env python3
"""Verify deterministic height sampling against a runtime kernel pack."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "runtime" / "kernel_pack_v1.json"
DEFAULT_OUT = ROOT / "factory" / "runtime" / "kernel_pack_verification.json"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_provider(catalog: Path, max_per_family: int) -> dict[str, list[dict[str, Any]]]:
    _catalog_path, kernels = hf.load_catalog(str(catalog))
    pool = hf.choose_kernel_pool(kernels, max_per_family)
    loaded = hf.load_kernel_arrays(pool)
    if not any(loaded.values()):
        raise RuntimeError("no kernel arrays loaded")
    return loaded


def deterministic_report(
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> dict[str, Any]:
    coords = np.array(
        [
            [0.0, 0.0],
            [1.0, 1.0],
            [2048.0, 0.0],
            [2048.0, 2048.0],
            [-2048.0, 2048.0],
            [12345.0, -6789.0],
            [32768.0, 32768.0],
            [65536.0, -32768.0],
        ],
        dtype=np.float64,
    )
    x = coords[:, 0].reshape(-1, 1)
    z = coords[:, 1].reshape(-1, 1)
    h1, _ = hf.sample_height_grid(x, z, loaded, seed, region_size_m)
    h2, _ = hf.sample_height_grid(x, z, loaded, seed, region_size_m)
    delta = np.abs(h1 - h2)
    return {
        "sample_count": int(coords.shape[0]),
        "max_abs_delta_m": float(np.max(delta)),
        "mean_abs_delta_m": float(np.mean(delta)),
    }


def edge_report(
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
    chunk_size_m: float,
    edge_samples: int,
) -> dict[str, Any]:
    values = np.linspace(0.0, chunk_size_m, edge_samples, dtype=np.float64)

    z = values.reshape(-1, 1)
    east_x = np.full_like(z, chunk_size_m)
    west_x = np.full_like(z, chunk_size_m)
    east_h, _ = hf.sample_height_grid(east_x, z, loaded, seed, region_size_m)
    west_h, _ = hf.sample_height_grid(west_x, z, loaded, seed, region_size_m)

    x = values.reshape(1, -1)
    north_z = np.full_like(x, chunk_size_m)
    south_z = np.full_like(x, chunk_size_m)
    north_h, _ = hf.sample_height_grid(x, north_z, loaded, seed, region_size_m)
    south_h, _ = hf.sample_height_grid(x, south_z, loaded, seed, region_size_m)

    delta = np.concatenate([np.abs(east_h - west_h).ravel(), np.abs(north_h - south_h).ravel()])
    return {
        "chunk_size_m": float(chunk_size_m),
        "edge_samples_per_side": int(edge_samples),
        "mean_abs_delta_m": float(np.mean(delta)),
        "p95_abs_delta_m": float(np.percentile(delta, 95.0)),
        "max_abs_delta_m": float(np.max(delta)),
    }


def full_chunk_edge_report(
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
    chunk_size_m: float,
    edge_samples: int,
) -> dict[str, Any]:
    values = np.linspace(0.0, chunk_size_m, edge_samples, dtype=np.float64)
    x0, z0 = np.meshgrid(values, values)
    east_chunk_x, east_chunk_z = np.meshgrid(values + chunk_size_m, values)
    north_chunk_x, north_chunk_z = np.meshgrid(values, values + chunk_size_m)

    base_h, _ = hf.sample_height_grid(x0, z0, loaded, seed, region_size_m)
    east_h, _ = hf.sample_height_grid(east_chunk_x, east_chunk_z, loaded, seed, region_size_m)
    north_h, _ = hf.sample_height_grid(north_chunk_x, north_chunk_z, loaded, seed, region_size_m)

    east_delta = np.abs(base_h[:, -1] - east_h[:, 0])
    north_delta = np.abs(base_h[-1, :] - north_h[0, :])
    delta = np.concatenate([east_delta.ravel(), north_delta.ravel()])
    return {
        "chunk_size_m": float(chunk_size_m),
        "edge_samples_per_side": int(edge_samples),
        "mean_abs_delta_m": float(np.mean(delta)),
        "p95_abs_delta_m": float(np.percentile(delta, 95.0)),
        "max_abs_delta_m": float(np.max(delta)),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--seeds", default="1337,2049,4099,8191")
    parser.add_argument("--region-size-m", type=float, default=32768.0)
    parser.add_argument("--chunk-size-m", type=float, default=2048.0)
    parser.add_argument("--edge-samples", type=int, default=65)
    parser.add_argument("--max-per-family", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    seeds = [int(part.strip()) for part in str(args.seeds).split(",") if part.strip()]
    loaded = load_provider(Path(args.catalog), int(args.max_per_family))
    family_counts = {family: len(items) for family, items in sorted(loaded.items()) if items}
    reports = []
    failed = False
    for seed in seeds:
        deterministic = deterministic_report(loaded, seed, float(args.region_size_m))
        edge = edge_report(
            loaded,
            seed,
            float(args.region_size_m),
            float(args.chunk_size_m),
            int(args.edge_samples),
        )
        full_chunk_edge = full_chunk_edge_report(
            loaded,
            seed,
            float(args.region_size_m),
            float(args.chunk_size_m),
            int(args.edge_samples),
        )
        if deterministic["max_abs_delta_m"] != 0.0 or edge["max_abs_delta_m"] != 0.0 or full_chunk_edge["max_abs_delta_m"] != 0.0:
            failed = True
        reports.append(
            {
                "seed": seed,
                "determinism": deterministic,
                "shared_coordinate_edges": edge,
                "full_neighbor_chunk_edges": full_chunk_edge,
            }
        )

    result = {
        "version": 1,
        "catalog": str(args.catalog).replace("\\", "/"),
        "family_counts": family_counts,
        "region_size_m": float(args.region_size_m),
        "reports": reports,
        "status": "pass" if not failed else "fail",
    }
    if not args.dry_run:
        write_json(Path(args.out), result)
    print("[verify-runtime-pack] catalog=%s" % args.catalog)
    print("[verify-runtime-pack] families=%s" % family_counts)
    print("[verify-runtime-pack] seeds=%s status=%s" % (seeds, result["status"]))
    if not args.dry_run:
        print("[verify-runtime-pack] out=%s" % args.out)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
