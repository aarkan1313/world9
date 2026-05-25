#!/usr/bin/env python3
"""Estimate runtime terrain mesh budgets from the streamer reference."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STREAMER = ROOT / "factory" / "runtime" / "streamer_reference" / "streamer_reference.json"
DEFAULT_OUT = ROOT / "factory" / "runtime" / "runtime_budget" / "runtime_budget.json"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def vertices_per_side_for_lod(base_vertices_per_side: int, lod: int) -> int:
    quads = base_vertices_per_side - 1
    reduced_quads = max(1, quads // (2**lod))
    return reduced_quads + 1


def mesh_counts(vertices_per_side: int, include_skirts: bool = False) -> dict[str, int]:
    top_vertex_count = vertices_per_side * vertices_per_side
    skirt_vertex_count = vertices_per_side * 4 - 4 if include_skirts else 0
    vertex_count = top_vertex_count + skirt_vertex_count
    top_triangle_count = (vertices_per_side - 1) * (vertices_per_side - 1) * 2
    skirt_triangle_count = skirt_vertex_count * 2 if include_skirts else 0
    triangle_count = top_triangle_count + skirt_triangle_count
    index_count = triangle_count * 3
    return {
        "vertices_per_side": vertices_per_side,
        "include_skirts": include_skirts,
        "top_vertex_count": top_vertex_count,
        "skirt_vertex_count": skirt_vertex_count,
        "vertex_count": vertex_count,
        "top_triangle_count": top_triangle_count,
        "skirt_triangle_count": skirt_triangle_count,
        "triangle_count": triangle_count,
        "index_count": index_count,
    }


def memory_bytes_for_counts(counts: dict[str, int]) -> dict[str, int]:
    vertex_count = counts["vertex_count"]
    index_count = counts["index_count"]
    vertex_gpu_bytes = vertex_count * 32  # position vec3 + normal vec3 + uv vec2, float32.
    index_gpu_bytes = index_count * 4
    cpu_height_bytes = vertex_count * 4
    return {
        "vertex_gpu_bytes": vertex_gpu_bytes,
        "index_gpu_bytes": index_gpu_bytes,
        "cpu_height_bytes": cpu_height_bytes,
        "total_bytes": vertex_gpu_bytes + index_gpu_bytes + cpu_height_bytes,
    }


def mib(value: int | float) -> float:
    return round(float(value) / (1024.0 * 1024.0), 3)


def estimate_for_base(base_vertices_per_side: int, lod_counts: dict[str, int]) -> dict[str, Any]:
    return estimate_for_base_with_options(
        base_vertices_per_side,
        lod_counts,
        include_skirts=False,
    )


def walk_review_lod_counts(radius_chunks: int = 3, max_lod: int = 4) -> dict[str, int]:
    # Matches TerrainStreamer.lod_for_ring: rings 0-1 stay LOD0, then each ring steps down.
    counts: dict[str, int] = {}
    for z in range(-radius_chunks, radius_chunks + 1):
        for x in range(-radius_chunks, radius_chunks + 1):
            ring = max(abs(x), abs(z))
            lod = 0 if ring <= 1 else min(max_lod, ring - 1)
            key = str(lod)
            counts[key] = counts.get(key, 0) + 1
    return counts


def estimate_walk_review_density(base_vertices_per_side: int, radius_chunks: int = 4, max_lod: int = 2) -> dict[str, Any]:
    lod_counts = walk_review_lod_counts(radius_chunks, max_lod)
    estimate = estimate_for_base_with_options(
        base_vertices_per_side,
        lod_counts,
        include_skirts=True,
    )
    estimate["chunk_size_m"] = 512.0
    estimate["visible_radius_chunks"] = radius_chunks
    estimate["max_lod"] = max_lod
    estimate["lod_density"] = True
    estimate["mesh_skirts"] = True
    estimate["spacing_m"] = round(512.0 / float(base_vertices_per_side - 1), 3)
    return estimate


def clipmap_index_count(side: int, spacing_m: float, outer_extent_m: float, inner_extent_m: float) -> int:
    cell_count = 0
    for z in range(side - 1):
        z_center = -outer_extent_m + (float(z) + 0.5) * spacing_m
        for x in range(side - 1):
            x_center = -outer_extent_m + (float(x) + 0.5) * spacing_m
            if abs(x_center) < inner_extent_m and abs(z_center) < inner_extent_m:
                continue
            cell_count += 1
    return cell_count * 6


def estimate_far_clipmap(
    level_count: int,
    base_spacing_m: float = 64.0,
    base_outer_extent_m: float = 4096.0,
    near_hole_extent_m: float = 2048.0,
) -> dict[str, Any]:
    levels = []
    total_vertices = 0
    total_triangles = 0
    total_indices = 0
    total_mesh_bytes = 0
    total_height_bytes = 0
    for level in range(level_count):
        spacing_m = base_spacing_m * float(1 << level)
        outer_extent_m = base_outer_extent_m * float(1 << level)
        inner_extent_m = near_hole_extent_m
        if level > 0:
            previous_outer_extent_m = base_outer_extent_m * float(1 << (level - 1))
            inner_extent_m = max(0.0, previous_outer_extent_m - spacing_m)
        side = int(round((outer_extent_m * 2.0) / spacing_m)) + 1
        vertex_count = side * side
        index_count = clipmap_index_count(side, spacing_m, outer_extent_m, inner_extent_m)
        triangle_count = index_count // 3
        mesh_bytes = vertex_count * 32 + index_count * 4
        height_bytes = vertex_count * 4
        levels.append(
            {
                "level": level,
                "vertices_per_side": side,
                "spacing_m": spacing_m,
                "outer_extent_m": outer_extent_m,
                "diameter_m": outer_extent_m * 2.0,
                "inner_extent_m": inner_extent_m,
                "vertex_count": vertex_count,
                "triangle_count": triangle_count,
                "index_count": index_count,
                "mesh_mib": mib(mesh_bytes),
                "cpu_height_mib": mib(height_bytes),
            }
        )
        total_vertices += vertex_count
        total_triangles += triangle_count
        total_indices += index_count
        total_mesh_bytes += mesh_bytes
        total_height_bytes += height_bytes
    return {
        "level_count": level_count,
        "base_spacing_m": base_spacing_m,
        "base_outer_extent_m": base_outer_extent_m,
        "near_hole_extent_m": near_hole_extent_m,
        "levels": levels,
        "totals": {
            "vertex_count": total_vertices,
            "triangle_count": total_triangles,
            "index_count": total_indices,
            "mesh_mib": mib(total_mesh_bytes),
            "cpu_height_mib": mib(total_height_bytes),
            "mesh_plus_height_mib": mib(total_mesh_bytes + total_height_bytes),
        },
    }


def estimate_far_clipmap_for_retained_window(
    scenario: str,
    level_count: int,
    chunk_size_m: float,
    visible_radius_chunks: int,
    base_spacing_m: float = 64.0,
    base_outer_extent_m: float = 4096.0,
    handoff_overlap_m: float = 64.0,
    recenter_distance_m: float = 768.0,
) -> dict[str, Any]:
    authoritative_half_extent_m = float(visible_radius_chunks * 2 + 1) * chunk_size_m * 0.5
    handoff_margin_m = max(max(0.0, handoff_overlap_m), base_spacing_m)
    anchor_drift_margin_m = max(chunk_size_m * 0.5, recenter_distance_m)
    near_hole_extent_m = max(0.0, authoritative_half_extent_m - handoff_margin_m - anchor_drift_margin_m)
    estimate = estimate_far_clipmap(
        level_count,
        base_spacing_m=base_spacing_m,
        base_outer_extent_m=base_outer_extent_m,
        near_hole_extent_m=near_hole_extent_m,
    )
    estimate["scenario"] = scenario
    estimate["chunk_size_m"] = chunk_size_m
    estimate["visible_radius_chunks"] = visible_radius_chunks
    estimate["authoritative_half_extent_m"] = authoritative_half_extent_m
    estimate["handoff_overlap_m"] = handoff_overlap_m
    estimate["recenter_distance_m"] = recenter_distance_m
    estimate["handoff_margin_m"] = handoff_margin_m
    estimate["anchor_drift_margin_m"] = anchor_drift_margin_m
    estimate["near_hole_source"] = "authoritative_half_extent_m - max(handoff_overlap_m, base_spacing_m) - max(chunk_size_m * 0.5, recenter_distance_m)"
    return estimate


def estimate_for_base_with_options(
    base_vertices_per_side: int,
    lod_counts: dict[str, int],
    include_skirts: bool,
) -> dict[str, Any]:
    per_lod = {}
    active_vertices = 0
    active_triangles = 0
    active_indices = 0
    active_memory = {
        "vertex_gpu_bytes": 0,
        "index_gpu_bytes": 0,
        "cpu_height_bytes": 0,
        "total_bytes": 0,
    }

    for lod_key in sorted(lod_counts, key=lambda k: int(k)):
        lod = int(lod_key)
        chunk_count = int(lod_counts[lod_key])
        counts = mesh_counts(vertices_per_side_for_lod(base_vertices_per_side, lod), include_skirts)
        memory = memory_bytes_for_counts(counts)
        total_for_lod = {k: v * chunk_count for k, v in memory.items()}
        per_lod[lod_key] = {
            "chunk_count": chunk_count,
            **counts,
            "per_chunk_mib": {k.replace("_bytes", "_mib"): mib(v) for k, v in memory.items()},
            "active_total_mib": {k.replace("_bytes", "_mib"): mib(v) for k, v in total_for_lod.items()},
        }
        active_vertices += counts["vertex_count"] * chunk_count
        active_triangles += counts["triangle_count"] * chunk_count
        active_indices += counts["index_count"] * chunk_count
        for key in active_memory:
            active_memory[key] += total_for_lod[key]

    return {
        "base_vertices_per_side": base_vertices_per_side,
        "lod_counts": lod_counts,
        "per_lod": per_lod,
        "active_totals": {
            "vertex_count": active_vertices,
            "triangle_count": active_triangles,
            "index_count": active_indices,
            "memory_mib": {k.replace("_bytes", "_mib"): mib(v) for k, v in active_memory.items()},
        },
    }

def summarize_streamer(streamer: dict[str, Any]) -> dict[str, Any]:
    steps = streamer.get("steps", [])
    if not steps:
        raise ValueError("streamer reference has no steps")
    first_lod_counts = steps[0]["lod_counts"]
    lod_count_values = [step["lod_counts"] for step in steps]
    if any(counts != first_lod_counts for counts in lod_count_values):
        lod_count_status = "varies"
    else:
        lod_count_status = "stable"
    queued_counts = [int(step["queued_build_count"]) for step in steps]
    built_counts = [int(step["build_now_count"]) for step in steps]
    return {
        "chunk_size_m": streamer["settings"]["chunk_size_m"],
        "visible_radius_chunks": streamer["settings"]["visible_radius_chunks"],
        "queue_policy": streamer["settings"].get("queue_policy"),
        "active_count": steps[0]["active_count"],
        "lod_counts_status": lod_count_status,
        "lod_counts": first_lod_counts,
        "build_budget_per_frame": streamer["settings"]["build_budget_per_frame"],
        "steps": len(steps),
        "queued_build_count_min": min(queued_counts),
        "queued_build_count_max": max(queued_counts),
        "queued_build_count_final": queued_counts[-1],
        "built_count_total": sum(built_counts),
        "mean_built_per_frame": round(sum(built_counts) / len(built_counts), 3),
        "mean_built_ring": streamer["summary"].get("mean_built_ring"),
        "max_built_ring": streamer["summary"].get("max_built_ring"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--streamer", default=str(DEFAULT_STREAMER))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--base-vertices", nargs="+", type=int, default=[65, 129, 257])
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    streamer = read_json(Path(args.streamer))
    summary = summarize_streamer(streamer)
    estimates = [
        estimate_for_base(base_vertices_per_side=vps, lod_counts=summary["lod_counts"])
        for vps in args.base_vertices
    ]
    recommended = next((item for item in estimates if item["base_vertices_per_side"] == 129), estimates[0])
    report = {
        "version": 1,
        "schema": "worldgen9.runtime_budget.v1",
        "source_streamer_reference": str(Path(args.streamer).resolve()),
        "assumptions": {
            "mesh_vertex_stride_bytes": 32,
            "index_bytes": 4,
            "cpu_height_bytes_per_vertex": 4,
            "lod_reduction": "halve quads per LOD, keeping shared edge endpoint vertices",
            "skirts": "baseline streamer estimates exclude skirts; walk_review_density_estimates include skirts",
            "materials_textures_collision": "not included",
        },
        "streamer": summary,
        "estimates": estimates,
        "walk_review_density_estimates": [
            estimate_walk_review_density(129, 4),
            estimate_walk_review_density(257, 3),
        ],
        "far_clipmap_estimates": [
            estimate_far_clipmap(3),
            estimate_far_clipmap(4),
        ],
        "streaming_far_clipmap_review_estimates": [
            estimate_far_clipmap_for_retained_window("streaming_preview_3x3", 3, 2048.0, 1),
            estimate_far_clipmap_for_retained_window("streaming_preview_3x3", 4, 2048.0, 1),
        ],
        "walk_far_clipmap_review_estimates": [
            estimate_far_clipmap_for_retained_window("walk_preview_7x7", 3, 512.0, 3),
            estimate_far_clipmap_for_retained_window("walk_preview_7x7", 4, 512.0, 3),
        ],
        "recommendation": {
            "start_base_vertices_per_side": recommended["base_vertices_per_side"],
            "reason": (
                "129x129 LOD0 is a conservative first target for visible quality and CPU/GPU cost. "
                "257x257 remains plausible if threaded/native mesh building is ready."
            ),
            "active_total_triangle_count": recommended["active_totals"]["triangle_count"],
            "active_total_memory_mib": recommended["active_totals"]["memory_mib"]["total_mib"],
        },
        "status": "pass",
    }
    if not args.dry_run:
        write_json(Path(args.out), report)
    print(
        f"runtime budget: {summary['active_count']} active chunks, "
        f"{recommended['active_totals']['triangle_count']} triangles at "
        f"{recommended['base_vertices_per_side']}x{recommended['base_vertices_per_side']} LOD0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
