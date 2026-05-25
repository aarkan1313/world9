#!/usr/bin/env python3
"""Export deterministic hash/noise reference values for runtime ports."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np

import infinite_heightfield as hf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "factory" / "runtime" / "hash_reference" / "hash_reference.json"


STABLE_HASH_CASES: list[tuple[Any, ...]] = [
    ("province_palette", 0, 0, 1337),
    ("province_palette", -6, 12, 1337),
    ("palette_local", -24, -24, -6, -6, 1337),
    ("palette_compatible", 17, -9, 1337),
    ("family_roll", 1, 0, 1337, 1),
    ("kernel", "mountain", -3, 7, 2049),
    ("scale", "volcanic__cop30_bulk20260524_volcanic_fuji_138_7_35_4", 0, 0, 1337),
    ("rot", "coast__cop30_fjord_coast_milford_sound_167_8_44_65", 1, 0, 1337),
    ("offu", "rainforest__cop30_bulk20260524_rainforest_congo_ituri_28_6_1_6", 0, 0, 1337),
    ("offv", "badlands__cop30_bulk20260524_badlands_tibetan_gorge_95_0_29_8", -5, 3, 8191),
]


HASH_GRID_CASES = [
    {"ix": 0, "iz": 0, "seed": 1337, "salt": 0},
    {"ix": 1, "iz": 0, "seed": 1337, "salt": 0},
    {"ix": 0, "iz": 1, "seed": 1337, "salt": 1},
    {"ix": -1, "iz": 2, "seed": 2049, "salt": 3},
    {"ix": 12345, "iz": -6789, "seed": 8191, "salt": 7},
]


NOISE_CASES = [
    {"x": 0.0, "z": 0.0, "scale_m": 32768.0, "seed": 1337, "salt": 0},
    {"x": 2048.0, "z": 0.0, "scale_m": 32768.0, "seed": 1337, "salt": 0},
    {"x": 12345.0, "z": -6789.0, "scale_m": 12000.0, "seed": 1348, "salt": 2},
    {"x": -32768.0, "z": 65536.0, "scale_m": 52000.0, "seed": 4099, "salt": 4},
]


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def hash_grid_scalar(ix: int, iz: int, seed: int, salt: int) -> float:
    ix_arr = np.array([[ix]], dtype=np.int64)
    iz_arr = np.array([[iz]], dtype=np.int64)
    return float(hf.hash_grid(ix_arr, iz_arr, seed, salt)[0, 0])


def value_noise_scalar(x: float, z: float, scale_m: float, seed: int, salt: int) -> float:
    x_arr = np.array([[x]], dtype=np.float64)
    z_arr = np.array([[z]], dtype=np.float64)
    return float(hf.value_noise(x_arr, z_arr, scale_m, seed, salt)[0, 0])


def fbm_scalar(x: float, z: float, scale_m: float, seed: int, octaves: int) -> float:
    x_arr = np.array([[x]], dtype=np.float64)
    z_arr = np.array([[z]], dtype=np.float64)
    return float(hf.fbm(x_arr, z_arr, scale_m, seed, octaves)[0, 0])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    stable_hash = [
        {
            "values": list(case),
            "joined_text": "|".join(str(value) for value in case),
            "hash_u32": hf.stable_hash(*case),
        }
        for case in STABLE_HASH_CASES
    ]
    hash_grid = [
        {
            **case,
            "value_0_to_1": hash_grid_scalar(case["ix"], case["iz"], case["seed"], case["salt"]),
        }
        for case in HASH_GRID_CASES
    ]
    noise = [
        {
            **case,
            "value_noise": value_noise_scalar(case["x"], case["z"], case["scale_m"], case["seed"], case["salt"]),
            "fbm_4": fbm_scalar(case["x"], case["z"], case["scale_m"], case["seed"], 4),
        }
        for case in NOISE_CASES
    ]
    result = {
        "version": 1,
        "schema": "worldgen9.hash_reference.v1",
        "stable_hash_contract": {
            "algorithm": "fnv1a_32",
            "initial_u32_hex": "0x811C9DC5",
            "multiply_u32_hex": "0x01000193",
            "join_values_with": "|",
            "integer_format": "base10_with_minus_for_negative",
            "string_encoding": "unicode_codepoint_ord_values",
            "mask_after_multiply": "0xFFFFFFFF",
        },
        "hash_grid_contract": {
            "integer_math": "signed int64 intermediates masked to u32",
            "normalization": "u32 / 4294967295.0",
        },
        "stable_hash_cases": stable_hash,
        "hash_grid_cases": hash_grid,
        "noise_cases": noise,
        "status": "pass",
    }
    if not args.dry_run:
        write_json(Path(args.out), result)
    print("[hash-reference] stable=%d grid=%d noise=%d status=pass" % (len(stable_hash), len(hash_grid), len(noise)))
    if not args.dry_run:
        print("[hash-reference] out=%s" % args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
