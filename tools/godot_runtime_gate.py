#!/usr/bin/env python3
"""Run Godot runtime checks for WorldGen9."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "wg-9-directory"
def godot_candidates() -> list[Path]:
    names = [
        "godot",
        "godot4",
        "Godot_v4.6.2-stable_mono_win64_console.exe",
        "Godot_v4.6.2-stable_mono_win64.exe",
    ]
    candidates: list[Path] = []
    if os.environ.get("GODOT_BIN"):
        candidates.append(Path(os.environ["GODOT_BIN"]))
    for name in names:
        resolved = shutil.which(name)
        if resolved:
            candidates.append(Path(resolved))
    candidates.extend(
        [
            Path(
                r"C:\tmp\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64"
                r"\Godot_v4.6.2-stable_mono_win64_console.exe"
            ),
            Path.home()
            / "Downloads"
            / "Godot_v4.6.2-stable_mono_win64"
            / "Godot_v4.6.2-stable_mono_win64_console.exe",
            Path.home()
            / "Downloads"
            / "Godot_v4.6.2-stable_mono_win64"
            / "Godot_v4.6.2-stable_mono_win64.exe",
        ]
    )
    return candidates

FAST_HEADLESS_CHECKS = [
    "native_backend_registration_check.gd",
    "terrain_quality_profile_check.gd",
    "terrain_visibility_contract_check.gd",
    "terrain_elevation_color_material_check.gd",
    "terrain_gpu_page_residency_check.gd",
    "native_clipmap_mesh_payload_from_height_check.gd",
    "terrain_far_clipmap_budget_check.gd",
    "terrain_far_clipmap_smoke_check.gd",
    "terrain_far_clipmap_transition_check.gd",
    "terrain_far_gray_shader_alignment_check.gd",
    "terrain_walk_far_clipmap_handoff_check.gd",
    "terrain_walk_chunk_boundary_recenter_check.gd",
    "terrain_walk_rapid_far_recenter_check.gd",
    "terrain_walk_far_surface_recenter_check.gd",
    "terrain_walk_hole_fill_priority_check.gd",
    "terrain_walk_preview_perf_check.gd",
    "terrain_walk_motion_profile_check.gd",
    "terrain_walk_prefetch_residency_check.gd",
    "terrain_walk_preview_smoke_check.gd",
]

EXTENDED_HEADLESS_CHECKS = FAST_HEADLESS_CHECKS + [
    "terrain_page_contract_check.gd",
    "streamer_reference_parity_check.gd",
    "terrain_chunk_renderer_check.gd",
    "terrain_runtime_modularity_check.gd",
    "native_prepared_height_grid_check.gd",
    "native_mesh_payload_from_height_check.gd",
    "native_chunk_payload_prepared_check.gd",
    "native_chunk_payload_worker_check.gd",
    "terrain_world_node_native_worker_check.gd",
    "terrain_lod_mixed_density_edge_check.gd",
    "terrain_far_clipmap_surface_material_check.gd",
    "terrain_streaming_far_clipmap_review_controls_check.gd",
    "terrain_local_detail_worker_stale_check.gd",
    "terrain_streaming_local_detail_review_controls_check.gd",
    "terrain_streaming_local_detail_surface_perf_check.gd",
]

QUALITY_HEADLESS_CHECKS = [
    "terrain_worldgen_capability_check.gd",
    "terrain_kernel_gallery_scene_check.gd",
    "terrain_mountain_kernel_gallery_scene_check.gd",
    "terrain_kernel_gallery_contact_sheet_check.gd",
    "terrain_kernel_tour_scene_check.gd",
    "terrain_landform_quality_probe_check.gd",
    "terrain_landform_profile_compare_check.gd",
    "terrain_landform_profile_tour_scene_check.gd",
    "terrain_landform_profile_tour_live_key_check.gd",
    "terrain_world_facts_pass_corridor_check.gd",
    "terrain_pass_corridor_visual_probe_check.gd",
    "terrain_hydrology_consistency_check.gd",
    "terrain_hydrology_tile_cache_check.gd",
    "terrain_hydrology_hint_probe_check.gd",
    "terrain_debug_mode_perf_check.gd",
    "terrain_streaming_perf_breakdown_check.gd",
    "terrain_walk_preview_257_perf_probe_check.gd",
]

GPU_CHECKS = [
    "terrain_gpu_compute_probe_check.gd",
    "terrain_gpu_page_normal_backend_check.gd",
    "terrain_gpu_texture_rd_probe_check.gd",
    "terrain_gpu_rd_page_residency_check.gd",
    "terrain_gpu_page_review_profile_check.gd",
    "terrain_gpu_page_review_scene_check.gd",
]

RENDER_CHECKS = [
    "terrain_preview_render_capture_check.gd",
    "terrain_streaming_render_capture_check.gd",
    "terrain_lod_skirt_render_capture_check.gd",
    "terrain_far_clipmap_render_capture_check.gd",
    "terrain_local_detail_displacement_render_capture_check.gd",
    "terrain_walk_local_detail_review_capture_check.gd",
]

REVIEW_CHECKS = [
    "terrain_streaming_review_contact_sheet_check.gd",
    "terrain_streaming_scale_review_contact_sheet_check.gd",
    "terrain_streaming_far_overview_review_capture_check.gd",
    "terrain_walk_density_review_capture_check.gd",
]

SUITES = {
    "fast": FAST_HEADLESS_CHECKS,
    "extended": EXTENDED_HEADLESS_CHECKS,
    "quality": QUALITY_HEADLESS_CHECKS,
    "gpu": GPU_CHECKS,
    "render": RENDER_CHECKS,
    "review": REVIEW_CHECKS,
}

DEFAULT_TIMEOUT_BY_SUITE = {
    "fast": 30,
    "extended": 30,
    "quality": 90,
    "gpu": 60,
    "render": 120,
    "review": 180,
}

HEADLESS_BY_SUITE = {
    "fast": True,
    "extended": True,
    "quality": True,
    "gpu": False,
    "render": False,
    "review": False,
}


def default_godot() -> Path | None:
    for candidate in godot_candidates():
        if candidate.exists():
            return candidate
    return None


def run_check(godot: Path, project: Path, check: str, timeout_s: int, headless: bool) -> dict[str, Any]:
    script = "res://worldgen_terrain/tests/%s" % check
    command = [
        str(godot),
        "--path",
        str(project),
        "--script",
        script,
    ]
    if headless:
        command.insert(1, "--headless")
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            text=True,
            capture_output=True,
            timeout=timeout_s,
        )
        elapsed_ms = int((time.monotonic() - started) * 1000)
        return {
            "check": check,
            "script": script,
            "headless": headless,
            "elapsed_ms": elapsed_ms,
            "returncode": completed.returncode,
            "stdout_tail": tail_lines(completed.stdout),
            "stderr_tail": tail_lines(completed.stderr),
            "status": "pass" if completed.returncode == 0 else "fail",
        }
    except subprocess.TimeoutExpired as error:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        return {
            "check": check,
            "script": script,
            "headless": headless,
            "elapsed_ms": elapsed_ms,
            "returncode": None,
            "stdout_tail": tail_lines(error.stdout or ""),
            "stderr_tail": tail_lines(error.stderr or ""),
            "status": "fail",
            "error": "timeout:%ds" % timeout_s,
        }


def tail_lines(text: str, max_lines: int = 8) -> list[str]:
    lines = [line for line in text.splitlines() if line.strip()]
    return lines[-max_lines:]


def run_gate(
    godot: Path,
    project: Path,
    suite: str,
    checks: list[str],
    timeout_s: int,
    headless: bool,
) -> dict[str, Any]:
    results = [run_check(godot, project, check, timeout_s, headless) for check in checks]
    errors = []
    for result in results:
        if result["status"] != "pass":
            errors.append("%s:%s" % (result["check"], result.get("error", result["returncode"])))
    return {
        "version": 1,
        "schema": "worldgen9.godot_runtime_gate.v1",
        "suite": suite,
        "headless": headless,
        "godot": str(godot),
        "project": str(project),
        "checks": checks,
        "results": results,
        "summary": {
            "check_count": len(results),
            "pass_count": sum(1 for result in results if result["status"] == "pass"),
            "fail_count": sum(1 for result in results if result["status"] != "pass"),
            "elapsed_ms": sum(int(result["elapsed_ms"]) for result in results),
        },
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(default_godot() or ""))
    parser.add_argument("--project", default=str(PROJECT))
    parser.add_argument("--timeout", type=int, default=None)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--suite", choices=sorted(SUITES), default="fast")
    parser.add_argument(
        "--no-headless",
        action="store_true",
        help="Run selected checks with the renderer enabled. The render and review suites do this by default.",
    )
    parser.add_argument(
        "--check",
        action="append",
        default=[],
        help="Run one check by filename. May be passed multiple times.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    godot = Path(args.godot) if args.godot else None
    if godot is None or not godot.exists():
        print("[godot-runtime] status=fail errors=1")
        print("[godot-runtime] error: godot_not_found")
        return 1
    project = Path(args.project)
    checks = args.check if args.check else SUITES[args.suite]
    suite = "custom" if args.check else args.suite
    timeout_s = args.timeout if args.timeout is not None else DEFAULT_TIMEOUT_BY_SUITE.get(args.suite, 30)
    headless = (not args.no_headless) and HEADLESS_BY_SUITE.get(args.suite, True)
    report = run_gate(godot, project, suite, checks, timeout_s, headless)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        summary = report["summary"]
        print(
            "[godot-runtime] status=%s suite=%s headless=%s checks=%d pass=%d fail=%d elapsed_ms=%d"
            % (
                report["status"],
                report["suite"],
                str(report["headless"]).lower(),
                summary["check_count"],
                summary["pass_count"],
                summary["fail_count"],
                summary["elapsed_ms"],
            )
        )
        for result in report["results"]:
            print(
                "[godot-runtime] check=%s status=%s elapsed_ms=%d"
                % (result["check"], result["status"], result["elapsed_ms"])
            )
            if result["status"] != "pass":
                for line in result["stdout_tail"] + result["stderr_tail"]:
                    print("[godot-runtime] detail: %s" % line)
        for error in report["errors"]:
            print("[godot-runtime] error: %s" % error)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
