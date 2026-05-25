#!/usr/bin/env python3
"""Find likely duplicate or overrepresented DEM terrain kernels.

This detector is intentionally metadata-only. It does not load DEM rasters or
kernel arrays, so it is safe to run while visual review or other work is open.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "catalog" / "accepted_kernel_catalog.json"
DEFAULT_OUT = ROOT / "factory" / "catalog" / "kernel_duplicate_candidates.json"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def bounds_area(bounds: list[float]) -> float:
    if len(bounds) != 4:
        return 0.0
    left, bottom, right, top = bounds
    return max(0.0, right - left) * max(0.0, top - bottom)


def bounds_overlap_ratio(a: list[float], b: list[float]) -> float:
    if len(a) != 4 or len(b) != 4:
        return 0.0
    left = max(a[0], b[0])
    bottom = max(a[1], b[1])
    right = min(a[2], b[2])
    top = min(a[3], b[3])
    inter = bounds_area([left, bottom, right, top])
    if inter <= 0.0:
        return 0.0
    smaller = min(bounds_area(a), bounds_area(b))
    return 0.0 if smaller <= 0.0 else inter / smaller


def bounds_center_distance(a: list[float], b: list[float]) -> float:
    if len(a) != 4 or len(b) != 4:
        return math.inf
    ax = (a[0] + a[2]) * 0.5
    ay = (a[1] + a[3]) * 0.5
    bx = (b[0] + b[2]) * 0.5
    by = (b[1] + b[3]) * 0.5
    return math.hypot(ax - bx, ay - by)


def rel_delta(a: float, b: float) -> float:
    denom = max(1e-6, abs(a), abs(b))
    return abs(a - b) / denom


def stats_similarity(a: dict[str, Any], b: dict[str, Any]) -> float:
    fields = (
        "height_range_m",
        "height_std_m",
        "mean_slope_deg",
        "slope_p95_deg",
        "roughness_residual_std_m",
        "anisotropy_score",
    )
    deltas = []
    for field in fields:
        av = a.get(field)
        bv = b.get(field)
        if isinstance(av, (int, float)) and isinstance(bv, (int, float)):
            deltas.append(rel_delta(float(av), float(bv)))
    if not deltas:
        return 0.0
    score = 1.0 - min(1.0, sum(deltas) / len(deltas))
    return max(0.0, score)


def pair_reason(a: dict[str, Any], b: dict[str, Any], overlap_threshold: float, center_threshold: float, stats_threshold: float) -> dict[str, Any] | None:
    same_source = a.get("source_dem_path") == b.get("source_dem_path")
    same_family = a.get("terrain_family") == b.get("terrain_family")
    overlap = bounds_overlap_ratio(a.get("source_bounds") or [], b.get("source_bounds") or [])
    center_distance = bounds_center_distance(a.get("source_bounds") or [], b.get("source_bounds") or [])
    similarity = stats_similarity(a, b)

    reasons = []
    if same_source:
        reasons.append("same_source_dem")
    if overlap >= overlap_threshold:
        reasons.append("overlapping_source_bounds")
    if same_family and center_distance <= center_threshold and similarity >= stats_threshold:
        reasons.append("nearby_same_family_similar_stats")

    if not reasons:
        return None
    return {
        "kernel_a": a.get("kernel_id"),
        "kernel_b": b.get("kernel_id"),
        "family_a": a.get("terrain_family"),
        "family_b": b.get("terrain_family"),
        "reasons": reasons,
        "source_overlap_ratio": overlap,
        "center_distance_degrees": None if math.isinf(center_distance) else center_distance,
        "stats_similarity": similarity,
        "height_range_m": [a.get("height_range_m"), b.get("height_range_m")],
        "slope_p95_deg": [a.get("slope_p95_deg"), b.get("slope_p95_deg")],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--overlap-threshold", type=float, default=0.35)
    parser.add_argument("--center-threshold-deg", type=float, default=0.20)
    parser.add_argument("--stats-threshold", type=float, default=0.88)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog = read_json(Path(args.catalog))
    kernels = catalog.get("kernels")
    if not isinstance(kernels, list):
        raise RuntimeError("catalog has no kernels list: %s" % args.catalog)

    candidates = []
    for i, a in enumerate(kernels):
        for b in kernels[i + 1 :]:
            reason = pair_reason(
                a,
                b,
                float(args.overlap_threshold),
                float(args.center_threshold_deg),
                float(args.stats_threshold),
            )
            if reason:
                candidates.append(reason)

    by_family: dict[str, int] = {}
    by_reason: dict[str, int] = {}
    for candidate in candidates:
        family = str(candidate.get("family_a"))
        by_family[family] = by_family.get(family, 0) + 1
        for reason in candidate.get("reasons", []):
            by_reason[reason] = by_reason.get(reason, 0) + 1

    report = {
        "version": 1,
        "source_catalog": str(args.catalog).replace("\\", "/"),
        "kernel_count": len(kernels),
        "candidate_pair_count": len(candidates),
        "thresholds": {
            "overlap_threshold": float(args.overlap_threshold),
            "center_threshold_degrees": float(args.center_threshold_deg),
            "stats_threshold": float(args.stats_threshold),
        },
        "by_family": dict(sorted(by_family.items())),
        "by_reason": dict(sorted(by_reason.items())),
        "candidates": candidates,
    }
    if not args.dry_run:
        write_json(Path(args.out), report)
    print("[duplicates] catalog=%s kernels=%d candidates=%d" % (args.catalog, len(kernels), len(candidates)))
    print("[duplicates] by_reason=%s" % report["by_reason"])
    if not args.dry_run:
        print("[duplicates] out=%s" % args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

