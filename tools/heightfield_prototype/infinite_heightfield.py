#!/usr/bin/env python3
"""Generate deterministic infinite-heightfield previews from DEM kernels.

The prototype is deliberately offline and engine-independent. It produces
preview images and seam metrics so we can evaluate kernel blending before
building Godot runtime code.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
USER_CATALOG = ROOT / "factory" / "reviews" / "user_shortlist_kernel_catalog.json"
PROMOTED_CATALOG = ROOT / "factory" / "catalog" / "promoted_kernel_catalog.json"
OUT_ROOT = ROOT / "prototypes" / "infinite_heightfield"
KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER = 2.20
KERNEL_WORLD_SCALE_SPAN_REGION_MULTIPLIER = 1.00
PROVINCE_SIZE_REGIONS = 4

FAMILY_WEIGHTS = {
    "mountain": {"relief": 640.0, "detail": 44.0},
    "glacial": {"relief": 560.0, "detail": 38.0},
    "badlands": {"relief": 500.0, "detail": 62.0},
    "desert": {"relief": 390.0, "detail": 38.0},
    "karst": {"relief": 450.0, "detail": 52.0},
    "coast": {"relief": 280.0, "detail": 30.0},
    "grassland": {"relief": 190.0, "detail": 22.0},
    "rainforest": {"relief": 380.0, "detail": 36.0},
    "volcanic": {"relief": 460.0, "detail": 40.0},
    "temperate": {"relief": 300.0, "detail": 45.0},
    "tundra": {"relief": 260.0, "detail": 35.0},
    "uncategorized": {"relief": 320.0, "detail": 35.0},
}

DEFAULT_FAMILIES = ["mountain", "glacial", "badlands", "desert", "karst", "coast", "grassland", "rainforest", "volcanic"]
REGION_PALETTES = [
    ("alpine", ("mountain", "glacial", "grassland")),
    ("drylands", ("badlands", "desert", "karst")),
    ("humid_hills", ("rainforest", "mountain", "grassland")),
    ("volcanic_coast", ("volcanic", "coast", "rainforest")),
    ("coastal_ridges", ("coast", "mountain", "glacial")),
    ("open_steppe", ("grassland", "badlands", "desert")),
]
PALETTE_COMPATIBILITY = {
    "alpine": ("coastal_ridges", "humid_hills", "open_steppe"),
    "drylands": ("open_steppe", "volcanic_coast", "coastal_ridges"),
    "humid_hills": ("alpine", "volcanic_coast", "coastal_ridges"),
    "volcanic_coast": ("coastal_ridges", "humid_hills", "drylands"),
    "coastal_ridges": ("alpine", "volcanic_coast", "humid_hills"),
    "open_steppe": ("drylands", "alpine", "coastal_ridges"),
}


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def stable_hash(*values: Any) -> int:
    h = 0x811C9DC5
    text = "|".join(str(v) for v in values)
    for ch in text:
        h ^= ord(ch)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def smoothstep(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fade(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def hash_grid(ix: np.ndarray, iz: np.ndarray, seed: int, salt: int = 0) -> np.ndarray:
    n = (ix.astype(np.int64) * 374761393 + iz.astype(np.int64) * 668265263 + seed * 1442695041 + salt * 69069) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return (n & 0xFFFFFFFF).astype(np.float64) / 4294967295.0


def value_noise(x: np.ndarray, z: np.ndarray, scale_m: float, seed: int, salt: int = 0) -> np.ndarray:
    fx = x / scale_m
    fz = z / scale_m
    ix = np.floor(fx).astype(np.int64)
    iz = np.floor(fz).astype(np.int64)
    tx = fade(fx - ix)
    tz = fade(fz - iz)
    a = hash_grid(ix, iz, seed, salt)
    b = hash_grid(ix + 1, iz, seed, salt)
    c = hash_grid(ix, iz + 1, seed, salt)
    d = hash_grid(ix + 1, iz + 1, seed, salt)
    ab = a * (1.0 - tx) + b * tx
    cd = c * (1.0 - tx) + d * tx
    return (ab * (1.0 - tz) + cd * tz) * 2.0 - 1.0


def fbm(x: np.ndarray, z: np.ndarray, scale_m: float, seed: int, octaves: int = 4) -> np.ndarray:
    total = np.zeros_like(x, dtype=np.float64)
    amp = 1.0
    norm = 0.0
    for octave in range(octaves):
        total += value_noise(x, z, scale_m / (2 ** octave), seed, octave) * amp
        norm += amp
        amp *= 0.5
    return total / max(1e-6, norm)


def ridged_noise(x: np.ndarray, z: np.ndarray, scale_m: float, seed: int, octaves: int = 4) -> np.ndarray:
    value = fbm(x, z, scale_m, seed, octaves)
    ridged = 1.0 - np.abs(value)
    return ridged * ridged * 2.0 - 1.0


def valley_mask(x: np.ndarray, z: np.ndarray, seed: int) -> np.ndarray:
    broad = ridged_noise(x + 5000.0, z - 3100.0, 18000.0, seed + 101, 4)
    tributary = ridged_noise(x * 1.15 - z * 0.10, z * 0.9 + x * 0.08, 6200.0, seed + 211, 3)
    combined = broad * 0.72 + tributary * 0.28
    mask = smoothstep((combined - 0.16) / 0.52)
    return mask.astype(np.float64)


def load_catalog(override: str = "") -> tuple[Path, list[dict[str, Any]]]:
    if override:
        path = Path(override)
        data = read_json(path, {})
        if data.get("schema") == "worldgen9.runtime_kernel_pack.v1":
            return path, adapt_runtime_pack(data, path)
        kernels = data.get("kernels")
        if not isinstance(kernels, list) or not kernels:
            raise RuntimeError("override catalog has no kernels: %s" % path)
        return path, kernels
    user = read_json(USER_CATALOG, {})
    user_kernels = user.get("kernels") if isinstance(user, dict) else None
    if isinstance(user_kernels, list) and len(user_kernels) >= 24:
        return USER_CATALOG, user_kernels
    promoted = read_json(PROMOTED_CATALOG, {})
    kernels = promoted.get("kernels")
    if not isinstance(kernels, list) or not kernels:
        raise RuntimeError("no usable kernel catalog found")
    return PROMOTED_CATALOG, kernels


def resolve_pack_path(value: str, pack_path: Path) -> str:
    path = Path(value)
    if path.is_absolute():
        return str(path)
    root_path = ROOT / path
    if root_path.exists():
        return str(root_path)
    return str((pack_path.parent / path).resolve())


def adapt_runtime_pack(pack: dict[str, Any], pack_path: Path) -> list[dict[str, Any]]:
    kernels = pack.get("kernels")
    if not isinstance(kernels, list) or not kernels:
        raise RuntimeError("runtime pack has no kernels: %s" % pack_path)
    family_params = pack.get("families", {})
    if not isinstance(family_params, dict):
        family_params = {}
    adapted = []
    for kernel in kernels:
        stats = kernel.get("stats", {})
        sample = kernel.get("sample", {})
        source = kernel.get("source", {})
        artifacts = kernel.get("artifacts", {})
        if not isinstance(stats, dict) or not isinstance(sample, dict) or not isinstance(artifacts, dict):
            raise RuntimeError("runtime pack kernel is malformed: %s" % kernel.get("id", "unknown"))
        adapted_artifacts = {
            key: resolve_pack_path(str(value), pack_path)
            for key, value in artifacts.items()
            if isinstance(value, str)
        }
        source_dem_path = source.get("dem_path") if isinstance(source, dict) else ""
        family = str(kernel.get("family", "uncategorized"))
        fallback_params = FAMILY_WEIGHTS.get(family, FAMILY_WEIGHTS["uncategorized"])
        runtime_params = family_params.get(family, {})
        if not isinstance(runtime_params, dict):
            runtime_params = {}
        adapted.append(
            {
                "kernel_id": kernel.get("id"),
                "terrain_family": family,
                "runtime_family": {
                    "relief": float(runtime_params.get("relief_scale_m", fallback_params["relief"])),
                    "detail": float(runtime_params.get("detail_scale_m", fallback_params["detail"])),
                    "weight": float(runtime_params.get("runtime_weight", 1.0)),
                },
                "demtype": kernel.get("demtype", "unknown"),
                "source_dem_path": resolve_pack_path(str(source_dem_path), pack_path) if source_dem_path else "",
                "source_bounds": source.get("bounds") if isinstance(source, dict) else None,
                "sample_px": int(sample.get("source_sample_px", 0) or 0),
                "approx_sample_spacing_m": float(sample.get("approx_sample_spacing_m", 1.0) or 1.0),
                "coverage_fraction": float(stats.get("coverage_fraction", 0.0) or 0.0),
                "height_range_m": float(stats.get("height_range_m", 0.0) or 0.0),
                "height_std_m": float(stats.get("height_std_m", 0.0) or 0.0),
                "mean_slope_deg": float(stats.get("mean_slope_deg", 0.0) or 0.0),
                "slope_p95_deg": float(stats.get("slope_p95_deg", 0.0) or 0.0),
                "roughness_residual_std_m": float(stats.get("roughness_residual_std_m", 0.0) or 0.0),
                "anisotropy_score": float(stats.get("anisotropy_score", 0.0) or 0.0),
                "quality_score": float(stats.get("quality_score", 0.0) or 0.0),
                "promotion_status": kernel.get("promotion_status", "runtime_pack"),
                "promotion_weight": float(kernel.get("promotion_weight", 1.0) or 1.0),
                "artifacts": adapted_artifacts,
            }
        )
    return adapted


def choose_kernel_pool(kernels: list[dict[str, Any]], max_per_family: int) -> dict[str, list[dict[str, Any]]]:
    by_family: dict[str, list[dict[str, Any]]] = {}
    for kernel in kernels:
        family = str(kernel.get("terrain_family", "uncategorized"))
        if family == "wetland":
            continue
        by_family.setdefault(family, []).append(kernel)
    pool: dict[str, list[dict[str, Any]]] = {}
    for family, items in by_family.items():
        ranked = sorted(
            items,
            key=lambda k: (
                float(k.get("quality_score", 0.0)),
                float(k.get("height_range_m", 0.0)),
                float(k.get("slope_p95_deg", 0.0)),
            ),
            reverse=True,
        )
        cap = 4 if family == "uncategorized" else max_per_family
        pool[family] = ranked[:cap]
    for family in DEFAULT_FAMILIES:
        if family not in pool:
            pool[family] = []
    return pool


def load_kernel_arrays(pool: dict[str, list[dict[str, Any]]]) -> dict[str, list[dict[str, Any]]]:
    loaded: dict[str, list[dict[str, Any]]] = {}
    for family, kernels in pool.items():
        loaded[family] = []
        for kernel in kernels:
            artifacts = kernel.get("artifacts", {})
            normalized_path = artifacts.get("normalized_height_npy")
            residual_path = artifacts.get("residual_m_npy")
            if not normalized_path or not residual_path:
                continue
            norm = np.load(normalized_path).astype(np.float32)
            residual = np.load(residual_path).astype(np.float32)
            if norm.ndim != 2 or residual.ndim != 2:
                continue
            loaded[family].append({**kernel, "_norm": norm, "_residual": residual})
    return loaded


def bilinear_sample(arr: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    h, w = arr.shape
    # DEM-derived kernels are not naturally tileable. Mirrored repeat avoids the
    # hard jump caused by wrapping the right edge directly to the left edge.
    u = 1.0 - np.abs(np.mod(u, 2.0) - 1.0)
    v = 1.0 - np.abs(np.mod(v, 2.0) - 1.0)
    u = u * (w - 1)
    v = v * (h - 1)
    x0 = np.floor(u).astype(np.int64)
    y0 = np.floor(v).astype(np.int64)
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    tx = u - x0
    ty = v - y0
    a = arr[y0, x0]
    b = arr[y0, x1]
    c = arr[y1, x0]
    d = arr[y1, x1]
    return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty


def palette_by_name(name: str) -> tuple[str, tuple[str, ...]]:
    for palette in REGION_PALETTES:
        if palette[0] == name:
            return palette
    raise KeyError(name)


def province_palette_name(prx: int, prz: int, seed: int) -> str:
    idx = stable_hash("province_palette", prx, prz, seed) % len(REGION_PALETTES)
    return REGION_PALETTES[idx][0]


def region_info(rx: int, rz: int, seed: int) -> tuple[str, tuple[str, ...]]:
    prx = rx // PROVINCE_SIZE_REGIONS
    prz = rz // PROVINCE_SIZE_REGIONS
    primary = province_palette_name(prx, prz, seed)
    roll = stable_hash("palette_local", rx, rz, prx, prz, seed) % 100
    if roll < 72:
        return palette_by_name(primary)
    if roll < 94:
        compatible = PALETTE_COMPATIBILITY[primary]
        idx = stable_hash("palette_compatible", rx, rz, seed) % len(compatible)
        return palette_by_name(compatible[idx])
    idx = stable_hash("palette_rare", rx, rz, seed) % len(REGION_PALETTES)
    return REGION_PALETTES[idx]


def palette_weights(x: np.ndarray, z: np.ndarray, seed: int, region_size_m: float) -> tuple[dict[str, np.ndarray], np.ndarray]:
    gx = x / region_size_m
    gz = z / region_size_m
    rx = np.floor(gx).astype(np.int64)
    rz = np.floor(gz).astype(np.int64)
    tx = smoothstep(gx - rx)
    tz = smoothstep(gz - rz)
    family_weights: dict[str, np.ndarray] = {}
    palette_id = np.zeros_like(x, dtype=np.float32)

    corners = [
        (rx, rz, (1.0 - tx) * (1.0 - tz)),
        (rx + 1, rz, tx * (1.0 - tz)),
        (rx, rz + 1, (1.0 - tx) * tz),
        (rx + 1, rz + 1, tx * tz),
    ]

    # Loop over unique region coords instead of per-pixel Python loops.
    for crx_arr, crz_arr, weight_arr in corners:
        pairs = np.stack([crx_arr.ravel(), crz_arr.ravel()], axis=1)
        unique_pairs = np.unique(pairs, axis=0)
        for urx, urz in unique_pairs:
            mask = (crx_arr == urx) & (crz_arr == urz)
            name, families = region_info(int(urx), int(urz), seed)
            local = weight_arr * mask
            palette_index = float([p[0] for p in REGION_PALETTES].index(name))
            palette_id += local.astype(np.float32) * palette_index
            family_bias = np.array(
                [0.55, 0.30, 0.15],
                dtype=np.float64,
            )
            roll = stable_hash("family_roll", int(urx), int(urz), seed) % 3
            family_bias = np.roll(family_bias, roll)
            for family, bias in zip(families, family_bias):
                family_weights.setdefault(family, np.zeros_like(x, dtype=np.float64))
                family_weights[family] += local * bias

    total = np.zeros_like(x, dtype=np.float64)
    for values in family_weights.values():
        total += values
    total = np.maximum(total, 1e-6)
    for family in list(family_weights):
        family_weights[family] = family_weights[family] / total
    return family_weights, palette_id


def kernel_for_family(loaded: dict[str, list[dict[str, Any]]], family: str, seed: int, rx: int, rz: int) -> dict[str, Any] | None:
    kernels = loaded.get(family) or loaded.get("uncategorized") or []
    if not kernels:
        return None
    idx = stable_hash("kernel", family, rx, rz, seed) % len(kernels)
    return kernels[idx]


def kernel_runtime_moderation(kernel: dict[str, Any]) -> float:
    slope_p95 = float(kernel.get("slope_p95_deg", 0.0) or 0.0)
    if slope_p95 <= 42.0:
        return 1.0
    return float(np.clip(42.0 / slope_p95, 0.58, 1.0))


def sample_kernel_field(
    kernel: dict[str, Any],
    x: np.ndarray,
    z: np.ndarray,
    seed: int,
    rx: int,
    rz: int,
    region_size_m: float,
) -> np.ndarray:
    arr = kernel["_norm"]
    scale_jitter = (
        stable_hash("scale", kernel["kernel_id"], rx, rz, seed) % int(KERNEL_WORLD_SCALE_SPAN_REGION_MULTIPLIER * 1000)
    ) / 1000.0
    scale = region_size_m * (KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER + scale_jitter)
    angle_i = stable_hash("rot", kernel["kernel_id"], rx, rz, seed) % 4
    u = x / scale
    v = z / scale
    if angle_i == 1:
        u, v = v, -u
    elif angle_i == 2:
        u, v = -u, -v
    elif angle_i == 3:
        u, v = -v, u
    off_u = (stable_hash("offu", kernel["kernel_id"], rx, rz, seed) % 10000) / 10000.0
    off_v = (stable_hash("offv", kernel["kernel_id"], rx, rz, seed) % 10000) / 10000.0
    return bilinear_sample(arr, u + off_u, v + off_v)


def sample_height_grid(
    x: np.ndarray,
    z: np.ndarray,
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> tuple[np.ndarray, np.ndarray]:
    layers = sample_height_layers(x, z, loaded, seed, region_size_m)
    return layers["height"], layers["region"]


def sample_height_layers(
    x: np.ndarray,
    z: np.ndarray,
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> dict[str, np.ndarray]:
    continent = fbm(x, z, 52000.0, seed + 3, 4)
    upland = smoothstep((continent + 0.2) / 0.75)
    basin = 1.0 - smoothstep((continent + 0.05) / 0.55)
    macro = (
        continent * 560.0
        + fbm(x, z, 26000.0, seed, 4) * 430.0
        + fbm(x + 2300.0, z - 1100.0, 12000.0, seed + 11, 3) * 140.0
    )
    ridge = ridged_noise(x * 0.8 + z * 0.15, z * 0.65 - x * 0.1, 18000.0, seed + 37, 3)
    macro += ridge * (190.0 + upland * 230.0)
    macro -= basin * 170.0

    _family_weights, palette_id = palette_weights(x, z, seed, region_size_m)
    detail = np.zeros_like(x, dtype=np.float64)
    relief = np.zeros_like(x, dtype=np.float64)

    gx = x / region_size_m
    gz = z / region_size_m
    rx = np.floor(x / region_size_m).astype(np.int64)
    rz = np.floor(z / region_size_m).astype(np.int64)
    tx = smoothstep(gx - rx)
    tz = smoothstep(gz - rz)
    corners = [
        (rx, rz, (1.0 - tx) * (1.0 - tz)),
        (rx + 1, rz, tx * (1.0 - tz)),
        (rx, rz + 1, (1.0 - tx) * tz),
        (rx + 1, rz + 1, tx * tz),
    ]

    # Blend both family choice and the actual kernel source across neighboring
    # regions. If only the family weights blend but the sampled kernel changes
    # by current region, square region boundaries become visible.
    for crx_arr, crz_arr, corner_weight in corners:
        pairs = np.unique(np.stack([crx_arr.ravel(), crz_arr.ravel()], axis=1), axis=0)
        for urx, urz in pairs:
            mask = (crx_arr == urx) & (crz_arr == urz)
            local_weight = corner_weight * mask
            if float(np.max(local_weight)) <= 1e-8:
                continue
            _name, families = region_info(int(urx), int(urz), seed)
            family_bias = np.array([0.55, 0.30, 0.15], dtype=np.float64)
            roll = stable_hash("family_roll", int(urx), int(urz), seed) % 3
            family_bias = np.roll(family_bias, roll)
            for family, bias in zip(families, family_bias):
                if family not in loaded or not loaded[family]:
                    continue
                kernel = kernel_for_family(loaded, family, seed, int(urx), int(urz))
                if not kernel:
                    continue
                sampled = sample_kernel_field(kernel, x, z, seed, int(urx), int(urz), region_size_m)
                params = kernel.get("runtime_family", FAMILY_WEIGHTS.get(family, FAMILY_WEIGHTS["uncategorized"]))
                runtime_weight = float(params.get("weight", 1.0))
                kernel_weight = kernel_runtime_moderation(kernel)
                weight = local_weight * bias
                relief += sampled * weight * runtime_weight * kernel_weight * params["relief"] * (0.58 + upland * 0.38)
                detail += (
                    fbm(x, z, 3000.0, seed + stable_hash(family) % 1000, 2)
                    * weight
                    * runtime_weight
                    * kernel_weight
                    * params["detail"]
                    * 0.82
                )

    valleys = valley_mask(x, z, seed)
    valley_cut = valleys * (110.0 + upland * 130.0)
    valley_floor_noise = fbm(x, z, 4200.0, seed + 401, 2) * 24.0 * valleys
    height = macro + relief + detail - valley_cut + valley_floor_noise
    valley_layer = (-valley_cut + valley_floor_noise)
    return {
        "height": height.astype(np.float32),
        "macro": macro.astype(np.float32),
        "relief": relief.astype(np.float32),
        "detail": detail.astype(np.float32),
        "valley": valley_layer.astype(np.float32),
        "region": palette_id.astype(np.float32),
    }


def save_gray(arr: np.ndarray, path: Path, lo: float | None = None, hi: float | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    low = float(np.percentile(arr, 1.0)) if lo is None else lo
    high = float(np.percentile(arr, 99.0)) if hi is None else hi
    span = max(1e-6, high - low)
    image = np.clip((arr - low) / span * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(image, mode="L").save(path)


def save_region(arr: np.ndarray, path: Path) -> None:
    palette = np.array(
        [
            [70, 100, 160],
            [190, 135, 70],
            [70, 150, 95],
            [150, 80, 120],
            [75, 145, 170],
            [165, 165, 95],
        ],
        dtype=np.float32,
    )
    idx0 = np.floor(arr).astype(np.int64) % len(palette)
    idx1 = (idx0 + 1) % len(palette)
    t = arr - np.floor(arr)
    rgb = palette[idx0] * (1.0 - t[..., None]) + palette[idx1] * t[..., None]
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB").save(path)


def hillshade(height: np.ndarray, spacing_m: float, azimuth_deg: float = 315.0, altitude_deg: float = 45.0) -> np.ndarray:
    gy, gx = np.gradient(height, spacing_m, spacing_m)
    slope = np.arctan(np.sqrt(gx * gx + gy * gy))
    aspect = np.arctan2(-gx, gy)
    az = math.radians(azimuth_deg)
    alt = math.radians(altitude_deg)
    shaded = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.clip((shaded + 0.15) / 1.15, 0.0, 1.0).astype(np.float32)


def save_hillshade(height: np.ndarray, spacing_m: float, path: Path) -> None:
    shade = hillshade(height, spacing_m)
    image = np.clip(shade * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(image, mode="L").save(path)


def save_color_relief(height: np.ndarray, spacing_m: float, path: Path) -> None:
    low = float(np.percentile(height, 1.0))
    high = float(np.percentile(height, 99.0))
    t = np.clip((height - low) / max(1e-6, high - low), 0.0, 1.0)
    stops = np.array(
        [
            [42, 62, 76],
            [72, 104, 94],
            [122, 137, 98],
            [155, 139, 103],
            [180, 180, 170],
            [235, 238, 232],
        ],
        dtype=np.float32,
    )
    pos = t * (len(stops) - 1)
    i0 = np.floor(pos).astype(np.int64)
    i1 = np.clip(i0 + 1, 0, len(stops) - 1)
    f = pos - i0
    rgb = stops[i0] * (1.0 - f[..., None]) + stops[i1] * f[..., None]
    shade = hillshade(height, spacing_m)
    rgb = rgb * (0.45 + shade[..., None] * 0.75)
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB").save(path)


def save_oblique_preview(height: np.ndarray, path: Path, max_width: int = 1200) -> None:
    # Lightweight pseudo-oblique terrain view for human review. This is not a
    # renderer; it shears scanlines and shades height so landforms read faster.
    src = height
    step = max(1, int(math.ceil(src.shape[1] / max_width)))
    src = src[::step, ::step]
    low = float(np.percentile(src, 1.0))
    high = float(np.percentile(src, 99.0))
    norm = np.clip((src - low) / max(1e-6, high - low), 0.0, 1.0)
    shade = hillshade(src, 1.0)
    rows, cols = src.shape
    row_scale = 0.55
    lift = 90
    out_w = cols + rows // 3
    out_h = int(rows * row_scale) + lift + 4
    image = Image.new("RGB", (out_w, out_h), (18, 22, 24))
    pixels = image.load()
    for y in range(rows - 1, -1, -1):
        yy = int(y * row_scale)
        shear = (rows - y) // 3
        for x in range(cols):
            elevation = int(norm[y, x] * lift)
            ox = x + shear
            oy = yy + lift - elevation
            if 0 <= ox < out_w and 0 <= oy < out_h:
                val = int(np.clip((0.25 + 0.75 * shade[y, x]) * (95 + 140 * norm[y, x]), 0, 255))
                pixels[ox, oy] = (val, val, val)
                if oy + 1 < out_h:
                    pixels[ox, oy + 1] = (max(0, val - 35), max(0, val - 35), max(0, val - 35))
    image.save(path)


def slope_degrees(height: np.ndarray, spacing_m: float) -> np.ndarray:
    gy, gx = np.gradient(height, spacing_m, spacing_m)
    return np.degrees(np.arctan(np.sqrt(gx * gx + gy * gy))).astype(np.float32)


def generate_tile(
    out_dir: Path,
    name: str,
    origin_x: float,
    origin_z: float,
    size_m: float,
    resolution_m: float,
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
) -> dict[str, Any]:
    samples = int(round(size_m / resolution_m)) + 1
    xs = origin_x + np.arange(samples, dtype=np.float64) * resolution_m
    zs = origin_z + np.arange(samples, dtype=np.float64) * resolution_m
    xg, zg = np.meshgrid(xs, zs)
    layers = sample_height_layers(xg, zg, loaded, seed, region_size_m)
    height = layers["height"]
    region = layers["region"]
    slope = slope_degrees(height, resolution_m)
    np.save(out_dir / f"{name}_height_m.npy", height)
    np.save(out_dir / f"{name}_macro_m.npy", layers["macro"])
    np.save(out_dir / f"{name}_kernel_relief_m.npy", layers["relief"])
    np.save(out_dir / f"{name}_detail_m.npy", layers["detail"])
    np.save(out_dir / f"{name}_valley_m.npy", layers["valley"])
    save_gray(height, out_dir / f"{name}_height.png")
    save_gray(layers["macro"], out_dir / f"{name}_macro.png")
    save_gray(layers["relief"], out_dir / f"{name}_kernel_relief.png")
    save_gray(layers["detail"], out_dir / f"{name}_detail.png")
    save_gray(layers["valley"], out_dir / f"{name}_valley.png")
    save_gray(slope, out_dir / f"{name}_slope.png", lo=0.0, hi=max(5.0, float(np.percentile(slope, 99.0))))
    save_hillshade(height, resolution_m, out_dir / f"{name}_hillshade.png")
    save_color_relief(height, resolution_m, out_dir / f"{name}_color_relief.png")
    save_oblique_preview(height, out_dir / f"{name}_oblique.png")
    save_region(region, out_dir / f"{name}_region_style.png")
    return {
        "name": name,
        "origin": [origin_x, origin_z],
        "size_m": size_m,
        "resolution_m": resolution_m,
        "samples": samples,
        "height_min_m": float(np.min(height)),
        "height_max_m": float(np.max(height)),
        "height_range_m": float(np.max(height) - np.min(height)),
        "height_std_m": float(np.std(height)),
        "macro_std_m": float(np.std(layers["macro"])),
        "kernel_relief_std_m": float(np.std(layers["relief"])),
        "detail_std_m": float(np.std(layers["detail"])),
        "valley_std_m": float(np.std(layers["valley"])),
        "slope_mean_deg": float(np.mean(slope)),
        "slope_p95_deg": float(np.percentile(slope, 95.0)),
        "height_png": str(out_dir / f"{name}_height.png").replace("\\", "/"),
        "slope_png": str(out_dir / f"{name}_slope.png").replace("\\", "/"),
        "hillshade_png": str(out_dir / f"{name}_hillshade.png").replace("\\", "/"),
        "color_relief_png": str(out_dir / f"{name}_color_relief.png").replace("\\", "/"),
        "oblique_png": str(out_dir / f"{name}_oblique.png").replace("\\", "/"),
        "macro_png": str(out_dir / f"{name}_macro.png").replace("\\", "/"),
        "kernel_relief_png": str(out_dir / f"{name}_kernel_relief.png").replace("\\", "/"),
        "detail_png": str(out_dir / f"{name}_detail.png").replace("\\", "/"),
        "valley_png": str(out_dir / f"{name}_valley.png").replace("\\", "/"),
        "region_png": str(out_dir / f"{name}_region_style.png").replace("\\", "/"),
    }


def seam_report(
    loaded: dict[str, list[dict[str, Any]]],
    seed: int,
    region_size_m: float,
    tile_size_m: float,
    resolution_m: float,
) -> dict[str, Any]:
    samples = int(round(tile_size_m / resolution_m)) + 1
    axis = np.arange(samples, dtype=np.float64) * resolution_m
    x0 = axis.reshape(1, -1)
    z0 = axis.reshape(-1, 1)

    left_h, _ = sample_height_grid(x0, z0, loaded, seed, region_size_m)
    right_h, _ = sample_height_grid(x0 + tile_size_m, z0, loaded, seed, region_size_m)
    delta = np.abs(left_h[:, -1] - right_h[:, 0])

    top_h, _ = sample_height_grid(x0, z0, loaded, seed, region_size_m)
    bottom_h, _ = sample_height_grid(x0, z0 + tile_size_m, loaded, seed, region_size_m)
    delta_z = np.abs(top_h[-1, :] - bottom_h[0, :])
    all_delta = np.concatenate([delta.ravel(), delta_z.ravel()])
    return {
        "tile_size_m": tile_size_m,
        "resolution_m": resolution_m,
        "edge_samples": int(all_delta.size),
        "mean_abs_delta_m": float(np.mean(all_delta)),
        "p95_abs_delta_m": float(np.percentile(all_delta, 95.0)),
        "max_abs_delta_m": float(np.max(all_delta)),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    parser.add_argument("--catalog", default="", help="Optional kernel catalog override")
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--resolution-m", type=float, default=32.0)
    parser.add_argument("--region-size-m", type=float, default=16384.0)
    parser.add_argument("--max-per-family", type=int, default=12)
    parser.add_argument("--small-size-m", type=float, default=8192.0)
    parser.add_argument("--large-size-m", type=float, default=16384.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog_path, kernels = load_catalog(str(args.catalog))
    pool = choose_kernel_pool(kernels, int(args.max_per_family))
    loaded = load_kernel_arrays(pool)
    loaded_counts = {family: len(items) for family, items in sorted(loaded.items()) if items}
    if not loaded_counts:
        raise RuntimeError("no kernel arrays loaded")

    outputs = []
    outputs.append(
        generate_tile(
            out_dir,
            "height_preview_8192",
            0.0,
            0.0,
            float(args.small_size_m),
            float(args.resolution_m),
            loaded,
            int(args.seed),
            float(args.region_size_m),
        )
    )
    outputs.append(
        generate_tile(
            out_dir,
            "height_preview_16384",
            0.0,
            0.0,
            float(args.large_size_m),
            float(args.resolution_m),
            loaded,
            int(args.seed),
            float(args.region_size_m),
        )
    )
    outputs.append(
        generate_tile(
            out_dir,
            "zoom_crop_offset",
            float(args.large_size_m) * 0.37,
            float(args.large_size_m) * 0.22,
            float(args.small_size_m),
            float(args.resolution_m),
            loaded,
            int(args.seed),
            float(args.region_size_m),
        )
    )
    seam = seam_report(loaded, int(args.seed), float(args.region_size_m), float(args.small_size_m), float(args.resolution_m))
    config = {
        "version": 1,
        "catalog": str(catalog_path).replace("\\", "/"),
        "seed": int(args.seed),
        "resolution_m": float(args.resolution_m),
        "region_size_m": float(args.region_size_m),
        "loaded_family_counts": loaded_counts,
        "outputs": outputs,
        "seam_report": seam,
    }
    write_json(out_dir / "prototype_config.json", config)
    write_json(out_dir / "seam_report.json", seam)
    print("[heightfield] catalog=%s kernels=%d" % (catalog_path, len(kernels)))
    print("[heightfield] loaded=%s" % loaded_counts)
    print("[heightfield] out=%s" % out_dir)
    print("[heightfield] seam max=%.9f mean=%.9f" % (seam["max_abs_delta_m"], seam["mean_abs_delta_m"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
