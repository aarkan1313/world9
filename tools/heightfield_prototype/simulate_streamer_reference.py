#!/usr/bin/env python3
"""Simulate chunk streaming and LOD-ring decisions without an engine."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = ROOT / "factory" / "runtime" / "streamer_reference"

LOD_COLORS = {
    0: (78, 168, 222),
    1: (94, 190, 120),
    2: (222, 188, 82),
    3: (224, 132, 80),
    4: (170, 110, 190),
}


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def parse_path(value: str) -> list[tuple[float, float]]:
    points = []
    for part in value.split(";"):
        if not part.strip():
            continue
        x_text, z_text = part.split(",", 1)
        points.append((float(x_text.strip()), float(z_text.strip())))
    if not points:
        raise RuntimeError("viewer path is empty")
    return points


def viewer_chunk(point: tuple[float, float], chunk_size_m: float) -> tuple[int, int]:
    return (math.floor(point[0] / chunk_size_m), math.floor(point[1] / chunk_size_m))


def lod_for_ring(ring: int, max_lod: int) -> int:
    if ring <= 1:
        return 0
    return min(max_lod, ring - 1)


def wanted_chunks(center: tuple[int, int], visible_radius: int, max_lod: int) -> dict[tuple[int, int], dict[str, int]]:
    result: dict[tuple[int, int], dict[str, int]] = {}
    cx, cz = center
    for dz in range(-visible_radius, visible_radius + 1):
        for dx in range(-visible_radius, visible_radius + 1):
            coord = (cx + dx, cz + dz)
            ring = max(abs(dx), abs(dz))
            result[coord] = {"ring": ring, "lod": lod_for_ring(ring, max_lod)}
    return result


def lod_counts(chunks: dict[tuple[int, int], dict[str, int]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in chunks.values():
        key = str(item["lod"])
        counts[key] = counts.get(key, 0) + 1
    return dict(sorted(counts.items(), key=lambda pair: int(pair[0])))


def chunk_list(chunks: dict[tuple[int, int], dict[str, int]]) -> list[dict[str, int]]:
    return [
        {"chunk_x": coord[0], "chunk_z": coord[1], "ring": data["ring"], "lod": data["lod"]}
        for coord, data in sorted(chunks.items())
    ]


def prioritize_queue(queue: list[tuple[int, int]], wanted: dict[tuple[int, int], dict[str, int]], center: tuple[int, int]) -> list[tuple[int, int]]:
    def key(coord: tuple[int, int]) -> tuple[int, int, int, int, int]:
        data = wanted.get(coord, {"ring": 999, "lod": 999})
        dx = abs(coord[0] - center[0])
        dz = abs(coord[1] - center[1])
        return (int(data["ring"]), int(data["lod"]), dx + dz, coord[1], coord[0])

    return sorted(queue, key=key)


def enqueue_unique(queue: list[tuple[int, int]], coord: tuple[int, int]) -> None:
    if coord not in queue:
        queue.append(coord)


def simulate(
    path: list[tuple[float, float]],
    chunk_size_m: float,
    visible_radius: int,
    max_lod: int,
    build_budget_per_frame: int,
    queue_policy: str,
) -> dict[str, Any]:
    expected_count = (visible_radius * 2 + 1) ** 2
    active: dict[tuple[int, int], dict[str, int]] = {}
    queued_builds: list[tuple[int, int]] = []
    steps = []
    max_active_count = 0
    total_created = 0
    total_retired = 0
    total_lod_changed = 0
    build_ring_values: list[int] = []

    for step_index, point in enumerate(path):
        center = viewer_chunk(point, chunk_size_m)
        wanted = wanted_chunks(center, visible_radius, max_lod)
        active_keys = set(active)
        wanted_keys = set(wanted)
        created = sorted(wanted_keys - active_keys)
        retired = sorted(active_keys - wanted_keys)
        kept = sorted(wanted_keys & active_keys)
        lod_changed = sorted(coord for coord in kept if active[coord]["lod"] != wanted[coord]["lod"])

        cancelled = 0
        for coord in retired:
            active.pop(coord, None)
            if coord in queued_builds:
                queued_builds.remove(coord)
                cancelled += 1
        for coord in created:
            active[coord] = wanted[coord]
            enqueue_unique(queued_builds, coord)
        for coord in lod_changed:
            active[coord] = wanted[coord]
            enqueue_unique(queued_builds, coord)

        if queue_policy == "priority_cancel":
            before = len(queued_builds)
            queued_builds = [coord for coord in queued_builds if coord in wanted]
            cancelled += before - len(queued_builds)
            queued_builds = prioritize_queue(queued_builds, wanted, center)
        elif queue_policy != "fifo":
            raise RuntimeError("unknown queue policy: %s" % queue_policy)

        build_now = queued_builds[:build_budget_per_frame]
        queued_builds = queued_builds[build_budget_per_frame:]
        build_now_rings = [int(wanted.get(coord, {"ring": -1})["ring"]) for coord in build_now]
        build_ring_values.extend(ring for ring in build_now_rings if ring >= 0)
        max_active_count = max(max_active_count, len(active))
        total_created += len(created)
        total_retired += len(retired)
        total_lod_changed += len(lod_changed)

        steps.append(
            {
                "step": step_index,
                "viewer_world": [point[0], point[1]],
                "viewer_chunk": [center[0], center[1]],
                "active_count": len(active),
                "expected_active_count": expected_count,
                "created_count": len(created),
                "retired_count": len(retired),
                "lod_changed_count": len(lod_changed),
                "cancelled_count": cancelled,
                "build_now_count": len(build_now),
                "build_now_rings": build_now_rings,
                "queued_build_count": len(queued_builds),
                "lod_counts": lod_counts(wanted),
                "active_chunks": chunk_list(wanted),
                "created": [[x, z] for x, z in created],
                "retired": [[x, z] for x, z in retired],
                "lod_changed": [[x, z] for x, z in lod_changed],
                "build_now": [[x, z] for x, z in build_now],
            }
        )

    errors = []
    if max_active_count > expected_count:
        errors.append("active_count_exceeded_expected")
    for step in steps:
        if step["active_count"] != expected_count:
            errors.append("active_count_not_expected_at_step_%d" % step["step"])
    return {
        "version": 1,
        "schema": "worldgen9.streamer_reference.v1",
        "settings": {
            "chunk_size_m": chunk_size_m,
            "visible_radius_chunks": visible_radius,
            "max_lod": max_lod,
            "build_budget_per_frame": build_budget_per_frame,
            "queue_policy": queue_policy,
            "expected_active_count": expected_count,
        },
        "summary": {
            "steps": len(steps),
            "max_active_count": max_active_count,
            "total_created": total_created,
            "total_retired": total_retired,
            "total_lod_changed": total_lod_changed,
            "final_queued_build_count": len(queued_builds),
            "built_count": len(build_ring_values),
            "mean_built_ring": (sum(build_ring_values) / float(len(build_ring_values))) if build_ring_values else 0.0,
            "max_built_ring": max(build_ring_values) if build_ring_values else 0,
        },
        "steps": steps,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def draw_step(
    draw: ImageDraw.ImageDraw,
    step: dict[str, Any],
    x0: int,
    y0: int,
    cell: int,
    radius: int,
    max_lod: int,
    font: ImageFont.ImageFont,
) -> None:
    lod_counts_data = step["lod_counts"]
    center_x = x0 + radius * cell
    center_y = y0 + radius * cell
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            ring = max(abs(dx), abs(dz))
            lod = lod_for_ring(ring, max_lod)
            color = LOD_COLORS.get(lod, (120, 120, 120))
            px = x0 + (dx + radius) * cell
            py = y0 + (dz + radius) * cell
            draw.rectangle((px, py, px + cell - 1, py + cell - 1), fill=color, outline=(24, 24, 24))
    draw.rectangle((center_x + 3, center_y + 3, center_x + cell - 4, center_y + cell - 4), outline=(255, 255, 255), width=2)
    label = "step %d chunk %s active %d q %d" % (
        step["step"],
        step["viewer_chunk"],
        step["active_count"],
        step["queued_build_count"],
    )
    draw.text((x0, y0 + (radius * 2 + 1) * cell + 5), label, fill=(235, 235, 235), font=font)
    counts_label = "lod " + ", ".join("%s:%s" % (k, v) for k, v in lod_counts_data.items())
    draw.text((x0, y0 + (radius * 2 + 1) * cell + 22), counts_label, fill=(205, 205, 205), font=font)


def save_contact_sheet(report: dict[str, Any], path: Path) -> None:
    steps = report["steps"]
    radius = int(report["settings"]["visible_radius_chunks"])
    max_lod = int(report["settings"]["max_lod"])
    cell = 18
    panel_w = (radius * 2 + 1) * cell
    panel_h = panel_w + 42
    cols = min(3, len(steps))
    rows = math.ceil(len(steps) / cols)
    sheet = Image.new("RGB", (cols * panel_w, rows * panel_h), (18, 18, 18))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 11)
    except Exception:
        font = ImageFont.load_default()
    for index, step in enumerate(steps):
        x0 = (index % cols) * panel_w
        y0 = (index // cols) * panel_h
        draw_step(draw, step, x0, y0, cell, radius, max_lod, font)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--chunk-size-m", type=float, default=2048.0)
    parser.add_argument("--visible-radius-chunks", type=int, default=4)
    parser.add_argument("--max-lod", type=int, default=4)
    parser.add_argument("--build-budget-per-frame", type=int, default=2)
    parser.add_argument("--queue-policy", choices=("fifo", "priority_cancel"), default="priority_cancel")
    parser.add_argument(
        "--viewer-path",
        default="0,0;1800,0;2300,0;4300,1800;-1000,3800;9000,-3000",
        help="Semicolon-separated world x,z viewer positions",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = simulate(
        parse_path(str(args.viewer_path)),
        float(args.chunk_size_m),
        int(args.visible_radius_chunks),
        int(args.max_lod),
        int(args.build_budget_per_frame),
        str(args.queue_policy),
    )
    out_dir = Path(args.out_dir)
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
        write_json(out_dir / "streamer_reference.json", report)
        save_contact_sheet(report, out_dir / "streamer_lod_contact_sheet.png")
    print(
        "[streamer-reference] steps=%d active=%d status=%s"
        % (report["summary"]["steps"], report["summary"]["max_active_count"], report["status"])
    )
    print("[streamer-reference] created=%d retired=%d lod_changed=%d final_queue=%d" % (
        report["summary"]["total_created"],
        report["summary"]["total_retired"],
        report["summary"]["total_lod_changed"],
        report["summary"]["final_queued_build_count"],
    ))
    print(
        "[streamer-reference] built=%d mean_ring=%.3f max_ring=%d policy=%s"
        % (
            report["summary"]["built_count"],
            report["summary"]["mean_built_ring"],
            report["summary"]["max_built_ring"],
            report["settings"]["queue_policy"],
        )
    )
    if not args.dry_run:
        print("[streamer-reference] out=%s" % out_dir)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
