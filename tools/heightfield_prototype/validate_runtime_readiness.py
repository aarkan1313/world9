#!/usr/bin/env python3
"""Validate that runtime reference fixtures are mutually consistent."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "factory" / "runtime" / "runtime_readiness_report.json"
FLOAT_EPSILON = 1e-6

RUNTIME = ROOT / "factory" / "runtime"
PROTOTYPE_VISUAL = ROOT / "prototypes" / "seed_compare_runtime_v7_balanced" / "seed_comparison_summary.json"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def check(condition: bool, errors: list[str], code: str) -> None:
    if not condition:
        errors.append(code)


def near_zero(value: Any, tolerance: float = FLOAT_EPSILON) -> bool:
    return abs(float(value)) <= tolerance


def close_float(actual: Any, expected: float, tolerance: float = FLOAT_EPSILON) -> bool:
    return abs(float(actual) - expected) <= tolerance


def all_edge_zero(reports: list[dict[str, Any]], field: str) -> bool:
    return all(near_zero(report.get(field, -1.0)) for report in reports)


def validate() -> dict[str, Any]:
    paths = {
        "kernel_pack": RUNTIME / "kernel_pack_v1.json",
        "hash_reference": RUNTIME / "hash_reference" / "hash_reference.json",
        "provider_decisions": RUNTIME / "provider_decisions" / "provider_decisions_reference.json",
        "terrain_sample": RUNTIME / "terrain_sample_reference.json",
        "kernel_pack_verification": RUNTIME / "kernel_pack_verification.json",
        "chunk_reference": RUNTIME / "chunk_reference" / "chunk_reference_manifest.json",
        "mesh_reference": RUNTIME / "mesh_reference" / "mesh_reference_manifest.json",
        "streamer_reference": RUNTIME / "streamer_reference" / "streamer_reference.json",
        "streamer_fifo": RUNTIME / "streamer_reference_fifo" / "streamer_reference.json",
        "runtime_budget": RUNTIME / "runtime_budget" / "runtime_budget.json",
        "godot_review_index_manifest": RUNTIME / "godot_review_index" / "review_index_manifest.json",
        "landform_quality_report": RUNTIME / "godot_landform_quality" / "landform_quality_report.json",
        "landform_profile_report": RUNTIME / "godot_landform_profiles" / "landform_profile_report.json",
        "hydrology_hint_report": RUNTIME / "godot_hydrology_hints" / "hydrology_hint_report.json",
        "hydrology_consistency_report": RUNTIME / "godot_hydrology_hints" / "hydrology_consistency_report.json",
        "hydrology_tile_cache_report": RUNTIME / "godot_hydrology_tiles" / "hydrology_tile_cache_report.json",
        "debug_mode_perf_report": RUNTIME / "godot_performance" / "debug_mode_perf_report.json",
        "streaming_far_overview_manifest": RUNTIME / "godot_streaming_far_overview" / "streaming_far_overview_manifest.json",
        "walk_density_manifest": RUNTIME / "godot_walk_density_review" / "walk_density_manifest.json",
        "local_detail_displacement_manifest": RUNTIME / "godot_local_detail_displacement" / "local_detail_displacement_manifest.json",
        "walk_local_detail_manifest": RUNTIME / "godot_walk_local_detail_review" / "walk_local_detail_manifest.json",
        "region_grammar": RUNTIME / "region_grammar" / "region_grammar_report.json",
        "infinite_travel": RUNTIME / "infinite_travel" / "infinite_travel_report.json",
        "visual_summary": PROTOTYPE_VISUAL,
    }
    errors: list[str] = []
    missing = [name for name, path in paths.items() if not path.exists()]
    errors.extend(f"missing:{name}:{paths[name]}" for name in missing)
    if missing:
        return {
            "version": 1,
            "schema": "worldgen9.runtime_readiness.v1",
            "paths": {name: str(path).replace("\\", "/") for name, path in paths.items()},
            "errors": errors,
            "status": "fail",
        }

    kernel_pack = read_json(paths["kernel_pack"])
    hash_reference = read_json(paths["hash_reference"])
    provider_decisions = read_json(paths["provider_decisions"])
    terrain_sample = read_json(paths["terrain_sample"])
    kernel_pack_verification = read_json(paths["kernel_pack_verification"])
    chunk_reference = read_json(paths["chunk_reference"])
    mesh_reference = read_json(paths["mesh_reference"])
    streamer_reference = read_json(paths["streamer_reference"])
    streamer_fifo = read_json(paths["streamer_fifo"])
    runtime_budget = read_json(paths["runtime_budget"])
    godot_review_index_manifest = read_json(paths["godot_review_index_manifest"])
    landform_quality_report = read_json(paths["landform_quality_report"])
    landform_profile_report = read_json(paths["landform_profile_report"])
    hydrology_hint_report = read_json(paths["hydrology_hint_report"])
    hydrology_consistency_report = read_json(paths["hydrology_consistency_report"])
    hydrology_tile_cache_report = read_json(paths["hydrology_tile_cache_report"])
    debug_mode_perf_report = read_json(paths["debug_mode_perf_report"])
    streaming_far_overview_manifest = read_json(paths["streaming_far_overview_manifest"])
    walk_density_manifest = read_json(paths["walk_density_manifest"])
    local_detail_displacement_manifest = read_json(paths["local_detail_displacement_manifest"])
    walk_local_detail_manifest = read_json(paths["walk_local_detail_manifest"])
    region_grammar = read_json(paths["region_grammar"])
    infinite_travel = read_json(paths["infinite_travel"])
    visual_summary = read_json(paths["visual_summary"])

    defaults = kernel_pack.get("runtime_defaults", {})
    chunk_size = float(defaults.get("chunk_size_m", -1.0))
    lod0_vps = int(defaults.get("lod0_vertices_per_side", -1))
    province_size = int(defaults.get("province_size_regions", -1))
    region_size = float(defaults.get("region_size_m", -1.0))
    scale_min = float(defaults.get("kernel_world_scale_min_region_multiplier", -1.0))
    scale_max = float(defaults.get("kernel_world_scale_max_region_multiplier", -1.0))
    declared_kernel_count = int(kernel_pack.get("kernel_count", -1))
    actual_kernel_count = len(kernel_pack.get("kernels", []))
    actual_family_count = len(kernel_pack.get("families", {}))

    check(kernel_pack.get("schema") == "worldgen9.runtime_kernel_pack.v1", errors, "kernel_pack_schema")
    check(declared_kernel_count == actual_kernel_count and actual_kernel_count > 0, errors, "kernel_pack_count")
    check(actual_family_count > 0, errors, "kernel_pack_family_count")
    check(lod0_vps == 129, errors, "runtime_default_lod0_not_129")
    check(close_float(chunk_size, 2048.0), errors, "runtime_default_chunk_size")
    check(province_size == 4, errors, "runtime_default_province_size")
    check(close_float(region_size, 32768.0), errors, "runtime_default_region_size")
    check(close_float(scale_min, 2.2) and close_float(scale_max, 3.2), errors, "runtime_default_kernel_scale")

    for name, report in [
        ("hash_reference", hash_reference),
        ("provider_decisions", provider_decisions),
        ("terrain_sample", terrain_sample),
        ("kernel_pack_verification", kernel_pack_verification),
        ("chunk_reference", chunk_reference),
        ("mesh_reference", mesh_reference),
        ("region_grammar", region_grammar),
        ("infinite_travel", infinite_travel),
    ]:
        check(report.get("status") == "pass", errors, f"{name}_not_pass")

    check(hash_reference.get("schema") == "worldgen9.hash_reference.v1", errors, "hash_schema")
    check(len(hash_reference.get("stable_hash_cases", [])) >= 10, errors, "hash_cases_missing")
    check(len(hash_reference.get("hash_grid_cases", [])) >= 5, errors, "hash_grid_cases_missing")
    check(len(hash_reference.get("noise_cases", [])) >= 4, errors, "noise_cases_missing")

    check(provider_decisions.get("province_size_regions") == province_size, errors, "provider_province_mismatch")
    check(close_float(provider_decisions.get("kernel_world_scale_min_region_multiplier", -1.0), scale_min), errors, "provider_scale_min_mismatch")
    check(close_float(provider_decisions.get("kernel_world_scale_max_region_multiplier", -1.0), scale_max), errors, "provider_scale_max_mismatch")
    for index, decision in enumerate(provider_decisions.get("decisions", [])):
        check(abs(float(decision.get("corner_weight_sum", -1.0)) - 1.0) < 1e-9, errors, f"provider_corner_weight:{index}")
        check(bool(decision.get("corners")), errors, f"provider_missing_corners:{index}")

    check(near_zero(terrain_sample.get("max_height_repeat_delta_m", -1.0)), errors, "terrain_sample_repeat_delta")
    check(len(terrain_sample.get("samples", [])) >= 5, errors, "terrain_sample_count")

    for index, report in enumerate(kernel_pack_verification.get("reports", [])):
        check(near_zero(report.get("determinism", {}).get("max_abs_delta_m", -1.0)), errors, f"verify_determinism:{index}")
        check(near_zero(report.get("shared_coordinate_edges", {}).get("max_abs_delta_m", -1.0)), errors, f"verify_shared_edge:{index}")
        check(near_zero(report.get("full_neighbor_chunk_edges", {}).get("max_abs_delta_m", -1.0)), errors, f"verify_full_edge:{index}")

    check(chunk_reference.get("vertices_per_side") == lod0_vps, errors, "chunk_vps_mismatch")
    check(close_float(chunk_reference.get("chunk_size_m", -1.0), chunk_size), errors, "chunk_size_mismatch")
    check(close_float(chunk_reference.get("step_m", -1.0), 16.0), errors, "chunk_step_mismatch")
    check(all_edge_zero(chunk_reference.get("edge_reports", []), "max_abs_delta_m"), errors, "chunk_edge_nonzero")

    check(mesh_reference.get("vertices_per_side") == lod0_vps, errors, "mesh_vps_mismatch")
    check(close_float(mesh_reference.get("chunk_size_m", -1.0), chunk_size), errors, "mesh_chunk_size_mismatch")
    check(mesh_reference.get("triangle_count") == 32768, errors, "mesh_triangle_count")
    check(all_edge_zero(mesh_reference.get("edge_reports", []), "max_abs_height_delta_m"), errors, "mesh_edge_nonzero")

    streamer_settings = streamer_reference.get("settings", {})
    streamer_summary = streamer_reference.get("summary", {})
    check(streamer_settings.get("queue_policy") == "priority_cancel", errors, "streamer_queue_policy")
    check(streamer_settings.get("expected_active_count") == 81, errors, "streamer_expected_active")
    check(streamer_summary.get("max_active_count") == 81, errors, "streamer_max_active")
    check(streamer_summary.get("max_built_ring") <= 1, errors, "streamer_priority_max_ring")
    check(streamer_fifo.get("settings", {}).get("queue_policy") == "fifo", errors, "fifo_policy_missing")

    budget_streamer = runtime_budget.get("streamer", {})
    recommendation = runtime_budget.get("recommendation", {})
    _check_runtime_budget(runtime_budget, lod0_vps, errors)
    check(
        streaming_far_overview_manifest.get("schema") == "worldgen9.streaming_far_overview_manifest.v1",
        errors,
        "streaming_far_overview_schema",
    )
    _check_godot_review_index(godot_review_index_manifest, errors)
    _check_landform_quality_report(landform_quality_report, errors)
    _check_landform_profile_report(landform_profile_report, errors)
    _check_hydrology_reports(hydrology_hint_report, hydrology_consistency_report, hydrology_tile_cache_report, errors)
    _check_debug_mode_perf_report(debug_mode_perf_report, errors)
    _check_streaming_far_overview_budget(runtime_budget, streaming_far_overview_manifest, errors)
    _check_walk_density_manifest(walk_density_manifest, errors)
    _check_local_detail_review_manifests(local_detail_displacement_manifest, walk_local_detail_manifest, errors)

    check(region_grammar.get("province_size_regions") == province_size, errors, "region_grammar_province_size")
    check(close_float(region_grammar.get("unique_region_signature_fraction", -1.0), 1.0), errors, "region_unique_fraction")
    check(near_zero(region_grammar.get("same_signature_adjacent_fraction", -1.0)), errors, "region_adjacent_signature")
    check(len(region_grammar.get("palette_counts", {})) == 6, errors, "region_palette_count")

    check(infinite_travel.get("schema") == "worldgen9.infinite_travel_probe.v1", errors, "travel_schema")
    check(infinite_travel.get("window_count") >= 12, errors, "travel_window_count")
    check(float(infinite_travel.get("max_abs_height_window_correlation", 999.0)) < 0.995, errors, "travel_window_correlation")
    check(not infinite_travel.get("duplicate_visual_hashes"), errors, "travel_duplicate_hashes")
    check(float(infinite_travel.get("max_slope_p95_deg", 999.0)) <= 58.0, errors, "travel_slope_p95")
    check(float(infinite_travel.get("max_height_range_m", 999999.0)) <= 1800.0, errors, "travel_height_range_high")
    check(float(infinite_travel.get("min_height_range_m", -999.0)) >= 120.0, errors, "travel_height_range_low")
    travel_contact_sheet = paths["infinite_travel"].parent / str(infinite_travel.get("contact_sheet", ""))
    check(travel_contact_sheet.exists(), errors, "travel_contact_sheet_missing")

    visual_results = visual_summary.get("results", [])
    max_p95 = max((float(item.get("slope_p95_deg", 999.0)) for item in visual_results), default=999.0)
    max_range = max((float(item.get("height_range_m", 999999.0)) for item in visual_results), default=999999.0)
    check(len(visual_results) >= 4, errors, "visual_seed_count")
    check(max_p95 <= 50.0, errors, "visual_p95_slope_above_50")
    check(max_range <= 1400.0, errors, "visual_height_range_above_1400")
    contact_sheet = Path(str(visual_summary.get("contact_sheet", "")))
    check(contact_sheet.exists(), errors, "visual_contact_sheet_missing")

    return {
        "version": 1,
        "schema": "worldgen9.runtime_readiness.v1",
        "paths": {name: str(path).replace("\\", "/") for name, path in paths.items()},
        "summary": {
            "kernel_count": kernel_pack.get("kernel_count"),
            "family_count": len(kernel_pack.get("families", {})),
            "chunk_size_m": chunk_size,
            "lod0_vertices_per_side": lod0_vps,
            "province_size_regions": province_size,
            "kernel_world_scale_range": [scale_min, scale_max],
            "max_visual_slope_p95_deg": max_p95,
            "max_visual_height_range_m": max_range,
            "max_travel_window_correlation": infinite_travel.get("max_abs_height_window_correlation"),
            "travel_window_count": infinite_travel.get("window_count"),
            "streamer_active_count": streamer_summary.get("max_active_count"),
            "budget_active_triangles_129": recommendation.get("active_total_triangle_count"),
        },
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def _find_by_int(items: list[dict[str, Any]], key: str, value: int) -> dict[str, Any] | None:
    for item in items:
        if int(item.get(key, -1)) == value:
            return item
    return None


def _check_float_close(actual: Any, expected: float, errors: list[str], code: str, tolerance: float = 0.001) -> None:
    check(abs(float(actual) - expected) <= tolerance, errors, code)


def _check_active_totals(
    report: dict[str, Any],
    expected_vertices: int,
    expected_triangles: int,
    expected_indices: int,
    expected_mib: float,
    prefix: str,
    errors: list[str],
) -> None:
    totals = report.get("active_totals", {})
    check(int(totals.get("vertex_count", -1)) == expected_vertices, errors, f"{prefix}_vertex_count")
    check(int(totals.get("triangle_count", -1)) == expected_triangles, errors, f"{prefix}_triangle_count")
    check(int(totals.get("index_count", -1)) == expected_indices, errors, f"{prefix}_index_count")
    _check_float_close(totals.get("memory_mib", {}).get("total_mib", -1.0), expected_mib, errors, f"{prefix}_memory")


def _check_clipmap_budget_case(
    estimates: list[dict[str, Any]],
    level_count: int,
    near_hole_extent_m: float,
    expected_triangles: int,
    expected_indices: int,
    expected_mib: float,
    prefix: str,
    errors: list[str],
    expected_scenario: str | None = None,
    expected_chunk_size_m: float | None = None,
    expected_radius: int | None = None,
) -> None:
    estimate = _find_by_int(estimates, "level_count", level_count)
    if estimate is None:
        errors.append(f"{prefix}_missing:{level_count}")
        return
    check(close_float(estimate.get("base_spacing_m", -1.0), 64.0), errors, f"{prefix}_base_spacing:{level_count}")
    check(close_float(estimate.get("base_outer_extent_m", -1.0), 4096.0), errors, f"{prefix}_base_extent:{level_count}")
    check(close_float(estimate.get("near_hole_extent_m", -1.0), near_hole_extent_m), errors, f"{prefix}_near_hole:{level_count}")
    levels = estimate.get("levels", [])
    check(len(levels) == level_count, errors, f"{prefix}_level_count:{level_count}")
    for index, level in enumerate(levels):
        check(int(level.get("level", -1)) == index, errors, f"{prefix}_level_index:{level_count}:{index}")
        check(int(level.get("vertices_per_side", -1)) == 129, errors, f"{prefix}_level_vps:{level_count}:{index}")
    totals = estimate.get("totals", {})
    check(int(totals.get("triangle_count", -1)) == expected_triangles, errors, f"{prefix}_triangles:{level_count}")
    check(int(totals.get("index_count", -1)) == expected_indices, errors, f"{prefix}_indices:{level_count}")
    _check_float_close(totals.get("mesh_plus_height_mib", -1.0), expected_mib, errors, f"{prefix}_memory:{level_count}")
    if expected_scenario is not None:
        check(estimate.get("scenario") == expected_scenario, errors, f"{prefix}_scenario:{level_count}")
    if expected_chunk_size_m is not None:
        check(close_float(estimate.get("chunk_size_m", -1.0), expected_chunk_size_m), errors, f"{prefix}_chunk_size:{level_count}")
    if expected_radius is not None:
        check(int(estimate.get("visible_radius_chunks", -1)) == expected_radius, errors, f"{prefix}_radius:{level_count}")


def _check_runtime_budget(budget: dict[str, Any], lod0_vps: int, errors: list[str]) -> None:
    check(budget.get("schema") == "worldgen9.runtime_budget.v1", errors, "budget_schema")
    check(budget.get("status") == "pass", errors, "budget_status")
    assumptions = budget.get("assumptions", {})
    check(int(assumptions.get("mesh_vertex_stride_bytes", 0)) == 32, errors, "budget_vertex_stride")
    check(int(assumptions.get("index_bytes", 0)) == 4, errors, "budget_index_bytes")
    check(int(assumptions.get("cpu_height_bytes_per_vertex", 0)) == 4, errors, "budget_height_bytes")

    budget_streamer = budget.get("streamer", {})
    recommendation = budget.get("recommendation", {})
    check(budget_streamer.get("active_count") == 81, errors, "budget_active_count")
    check(budget_streamer.get("lod_counts") == {"0": 9, "1": 16, "2": 24, "3": 32}, errors, "budget_lod_counts")
    check(recommendation.get("start_base_vertices_per_side") == lod0_vps, errors, "budget_recommendation_vps")
    check(recommendation.get("active_total_triangle_count") == 491520, errors, "budget_triangle_count")
    _check_float_close(recommendation.get("active_total_memory_mib", -1.0), 14.303, errors, "budget_recommendation_memory")

    estimates = budget.get("estimates", [])
    expected_baseline = {
        65: (64977, 122880, 368640, 3.637),
        129: (252753, 491520, 1474560, 14.303),
        257: (996945, 1966080, 5898240, 56.727),
    }
    for vertices_per_side, expected in expected_baseline.items():
        estimate = _find_by_int(estimates, "base_vertices_per_side", vertices_per_side)
        if estimate is None:
            errors.append(f"budget_estimate_missing:{vertices_per_side}")
            continue
        _check_active_totals(estimate, expected[0], expected[1], expected[2], expected[3], f"budget_estimate_{vertices_per_side}", errors)

    walk_estimates = budget.get("walk_review_density_estimates", [])
    walk_129 = _find_by_int(walk_estimates, "base_vertices_per_side", 129)
    walk_257 = _find_by_int(walk_estimates, "base_vertices_per_side", 257)
    if walk_129 is None:
        errors.append("budget_walk_density_missing:129")
    else:
        check(close_float(walk_129.get("chunk_size_m", -1.0), 512.0), errors, "budget_walk_129_chunk_size")
        check(int(walk_129.get("visible_radius_chunks", -1)) == 4, errors, "budget_walk_129_radius")
        check(int(walk_129.get("max_lod", -1)) == 2, errors, "budget_walk_129_max_lod")
        check(bool(walk_129.get("lod_density", False)), errors, "budget_walk_129_lod_density")
        check(bool(walk_129.get("mesh_skirts", False)), errors, "budget_walk_129_skirts")
        check(close_float(walk_129.get("spacing_m", -1.0), 4.0), errors, "budget_walk_129_spacing")
        _check_active_totals(walk_129, 294225, 572416, 1717248, 16.652, "budget_walk_129", errors)
    if walk_257 is None:
        errors.append("budget_walk_density_missing:257")
    else:
        check(close_float(walk_257.get("chunk_size_m", -1.0), 512.0), errors, "budget_walk_257_chunk_size")
        check(int(walk_257.get("visible_radius_chunks", -1)) == 3, errors, "budget_walk_257_radius")
        check(int(walk_257.get("max_lod", -1)) == 2, errors, "budget_walk_257_max_lod")
        check(bool(walk_257.get("lod_density", False)), errors, "budget_walk_257_lod_density")
        check(bool(walk_257.get("mesh_skirts", False)), errors, "budget_walk_257_skirts")
        check(close_float(walk_257.get("spacing_m", -1.0), 2.0), errors, "budget_walk_257_spacing")
        _check_active_totals(walk_257, 985649, 1947648, 5842944, 56.129, "budget_walk_257", errors)
    if walk_129 is not None and walk_257 is not None:
        low_totals = walk_129.get("active_totals", {})
        high_totals = walk_257.get("active_totals", {})
        low_triangles = int(low_totals.get("triangle_count", 0))
        high_triangles = int(high_totals.get("triangle_count", 0))
        low_mib = float(low_totals.get("memory_mib", {}).get("total_mib", 0.0))
        high_mib = float(high_totals.get("memory_mib", {}).get("total_mib", 0.0))
        check(high_triangles > low_triangles * 3.0, errors, "budget_walk_257_triangle_cost_not_opt_in")
        check(high_mib > low_mib * 3.0, errors, "budget_walk_257_memory_cost_not_opt_in")

    _check_clipmap_budget_case(budget.get("far_clipmap_estimates", []), 3, 2048.0, 74736, 224208, 2.569, "budget_far_clipmap", errors)
    _check_clipmap_budget_case(budget.get("far_clipmap_estimates", []), 4, 2048.0, 99816, 299448, 3.428, "budget_far_clipmap", errors)
    _check_clipmap_budget_case(
        budget.get("walk_far_clipmap_review_estimates", []),
        3,
        960.0,
        81128,
        243384,
        2.642,
        "budget_walk_far_clipmap",
        errors,
        expected_scenario="walk_preview_7x7",
        expected_chunk_size_m=512.0,
        expected_radius=3,
    )
    _check_clipmap_budget_case(
        budget.get("walk_far_clipmap_review_estimates", []),
        4,
        960.0,
        106208,
        318624,
        3.501,
        "budget_walk_far_clipmap",
        errors,
        expected_scenario="walk_preview_7x7",
        expected_chunk_size_m=512.0,
        expected_radius=3,
    )


def _review_index_files(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for section in manifest.get("sections", []):
        for record in section.get("files", []):
            records[str(record.get("path", ""))] = record
    return records


def _check_godot_review_index(manifest: dict[str, Any], errors: list[str]) -> None:
    check(manifest.get("schema") == "worldgen9.godot_review_index.v1", errors, "godot_review_index_schema")
    check(manifest.get("status") == "pass", errors, "godot_review_index_status")
    sections = manifest.get("sections", [])
    expected_titles = [
        "Plain Gray Landform Readability",
        "Scale And Mesh Density",
        "Hydrology Debug Readability",
        "Far Clipmap Review",
        "Local Detail And Displacement Review",
    ]
    actual_titles = [str(section.get("title", "")) for section in sections]
    check(actual_titles == expected_titles, errors, "godot_review_index_sections")
    files = _review_index_files(manifest)
    required_paths = [
        "factory/runtime/godot_streaming_review/streaming_review_contact_sheet.png",
        "factory/runtime/godot_streaming_scale_review/streaming_scale_review_manifest.json",
        "factory/runtime/godot_walk_density_review/walk_density_manifest.json",
        "factory/runtime/godot_hydrology_hints/hydrology_consistency_report.json",
        "factory/runtime/godot_streaming_far_overview/streaming_far_overview_manifest.json",
        "factory/runtime/godot_local_detail_displacement/local_detail_displacement_manifest.json",
        "factory/runtime/godot_walk_local_detail_review/walk_local_detail_manifest.json",
    ]
    for path in required_paths:
        record = files.get(path)
        if record is None:
            errors.append(f"godot_review_index_missing:{path}")
            continue
        check(bool(record.get("exists", False)), errors, f"godot_review_index_not_exists:{path}")
        check(int(record.get("bytes", 0)) > 0, errors, f"godot_review_index_empty:{path}")
    for path, record in files.items():
        check(bool(record.get("exists", False)), errors, f"godot_review_index_file_missing:{path}")
        if path.endswith(".png"):
            check(int(record.get("width", 0)) > 0, errors, f"godot_review_index_png_width:{path}")
            check(int(record.get("height", 0)) > 0, errors, f"godot_review_index_png_height:{path}")


def _check_landform_quality_report(report: dict[str, Any], errors: list[str]) -> None:
    check(report.get("schema") == "worldgen9.landform_quality_report.v1", errors, "landform_quality_schema")
    check(int(report.get("grid_size", 0)) == 97, errors, "landform_quality_grid_size")
    check(not report.get("warnings", []), errors, "landform_quality_warnings")
    cases = report.get("cases", [])
    check(len(cases) == 6, errors, "landform_quality_case_count")
    strong_count = 0
    families: set[str] = set()
    for index, case in enumerate(cases):
        check(int(case.get("index", -1)) == index, errors, f"landform_quality_index:{index}")
        check(int(case.get("grid_size", 0)) == 97, errors, f"landform_quality_case_grid:{index}")
        check(close_float(case.get("span_m", -1.0), 12288.0), errors, f"landform_quality_span:{index}")
        check(close_float(case.get("step_m", -1.0), 128.0), errors, f"landform_quality_step:{index}")
        check(float(case.get("height_range_m", 0.0)) >= 300.0, errors, f"landform_quality_height_range:{index}")
        check(float(case.get("relief_p05_p95_m", 0.0)) >= 200.0, errors, f"landform_quality_relief:{index}")
        check(float(case.get("mean_local_relief_m", 0.0)) >= 10.0, errors, f"landform_quality_local_relief:{index}")
        check(float(case.get("source_confidence", 0.0)) >= 0.5, errors, f"landform_quality_confidence:{index}")
        if str(case.get("landform_signal", "")) == "strong":
            strong_count += 1
        families.add(str(case.get("primary_family", "")))
    check(strong_count >= 3, errors, "landform_quality_strong_count")
    check(len(families - {""}) >= 4, errors, "landform_quality_family_variety")


def _check_landform_profile_report(report: dict[str, Any], errors: list[str]) -> None:
    check(report.get("schema") == "worldgen9.landform_profile_report.v1", errors, "landform_profile_schema")
    check(int(report.get("grid_size", 0)) == 81, errors, "landform_profile_grid_size")
    expected_profiles = ["balanced_current", "strong_mountains", "medium_scale", "compressed_scale"]
    check(report.get("profile_ids", []) == expected_profiles, errors, "landform_profile_ids")
    sites = report.get("sites", [])
    check(len(sites) >= 3, errors, "landform_profile_site_count")
    strong_improved = False
    compressed_changed = False
    for site in sites:
        by_profile = {str(item.get("profile", "")): item for item in site.get("profiles", [])}
        for profile_id in expected_profiles:
            check(profile_id in by_profile, errors, f"landform_profile_missing:{profile_id}")
        if not all(profile_id in by_profile for profile_id in expected_profiles):
            continue
        balanced = by_profile["balanced_current"]
        strong = by_profile["strong_mountains"]
        compressed = by_profile["compressed_scale"]
        for profile_id, item in by_profile.items():
            check(float(item.get("seam_max_delta_m", 1.0)) <= 0.01, errors, f"landform_profile_seam:{profile_id}")
            check(float(item.get("height_range_m", 0.0)) >= 100.0, errors, f"landform_profile_height_range:{profile_id}")
            check(bool(item.get("native_prepared_grid_enabled", False)), errors, f"landform_profile_native:{profile_id}")
        if float(strong.get("relief_p05_p95_m", 0.0)) >= float(balanced.get("relief_p05_p95_m", 0.0)) * 1.03:
            strong_improved = True
        if abs(float(compressed.get("mean_local_relief_m", 0.0)) - float(balanced.get("mean_local_relief_m", 0.0))) >= 1.0:
            compressed_changed = True
    check(strong_improved, errors, "landform_profile_strong_effect")
    check(compressed_changed, errors, "landform_profile_compressed_effect")


def _check_hydrology_hint_report(report: dict[str, Any], errors: list[str]) -> None:
    check(report.get("schema") == "worldgen9.hydrology_hint_report.v1", errors, "hydrology_hint_schema")
    check(int(report.get("grid_size", 0)) == 97, errors, "hydrology_hint_grid_size")
    check(int(report.get("padding_cells", 0)) == 24, errors, "hydrology_hint_padding")
    check(not report.get("warnings", []), errors, "hydrology_hint_warnings")
    check(report.get("columns", []) == ["flow_accumulation", "wetness", "channel_likelihood"], errors, "hydrology_hint_columns")
    cases = report.get("cases", [])
    check(len(cases) == 6, errors, "hydrology_hint_case_count")
    strong_channel_cases = 0
    wet_cases = 0
    for index, case in enumerate(cases):
        check(int(case.get("index", -1)) == index, errors, f"hydrology_hint_index:{index}")
        check(int(case.get("grid_size", 0)) == 97, errors, f"hydrology_hint_case_grid:{index}")
        check(int(case.get("padding_cells", 0)) == 24, errors, f"hydrology_hint_case_padding:{index}")
        check(case.get("stable_fields", []) == ["height", "slope_deg", "flow_dir"], errors, f"hydrology_hint_stable_fields:{index}")
        check(
            case.get("window_limited_fields", []) == ["flow_accumulation", "wetness", "channel_likelihood"],
            errors,
            f"hydrology_hint_window_limited_fields:{index}",
        )
        check(float(case.get("max_flow_accumulation", 0.0)) > 0.0, errors, f"hydrology_hint_flow:{index}")
        check(0.0 <= float(case.get("mean_wetness", -1.0)) <= 1.0, errors, f"hydrology_hint_mean_wetness:{index}")
        check(0.0 <= float(case.get("max_wetness", -1.0)) <= 1.0, errors, f"hydrology_hint_max_wetness:{index}")
        check(0.0 <= float(case.get("mean_channel_likelihood", -1.0)) <= 1.0, errors, f"hydrology_hint_mean_channel:{index}")
        check(0.0 <= float(case.get("max_channel_likelihood", -1.0)) <= 1.0, errors, f"hydrology_hint_max_channel:{index}")
        if float(case.get("strong_channel_fraction", 0.0)) > 0.0:
            strong_channel_cases += 1
        if float(case.get("wet_cell_fraction", 0.0)) > 0.0:
            wet_cases += 1
    check(strong_channel_cases >= 4, errors, "hydrology_hint_strong_channel_cases")
    check(wet_cases >= 4, errors, "hydrology_hint_wet_cases")


def _check_hydrology_reports(
    hint_report: dict[str, Any],
    consistency_report: dict[str, Any],
    tile_cache_report: dict[str, Any],
    errors: list[str],
) -> None:
    _check_hydrology_hint_report(hint_report, errors)
    check(consistency_report.get("schema") == "worldgen9.hydrology_consistency_report.v1", errors, "hydrology_consistency_schema")
    check(consistency_report.get("stable_fields", []) == ["height", "slope_deg", "flow_dir"], errors, "hydrology_consistency_stable_fields")
    check(
        consistency_report.get("window_limited_fields", []) == ["flow_accumulation", "wetness", "channel_likelihood"],
        errors,
        "hydrology_consistency_window_limited_fields",
    )
    overlaps = consistency_report.get("overlaps", [])
    check(len(overlaps) == 2, errors, "hydrology_consistency_overlap_count")
    for overlap in overlaps:
        stable_metrics = overlap.get("stable_field_metrics", {})
        check(int(stable_metrics.get("flow_dir_mismatch_count", -1)) == 0, errors, f"hydrology_consistency_flow_dir:{overlap.get('label')}")
        check(near_zero(stable_metrics.get("max_slope_delta_deg", -1.0)), errors, f"hydrology_consistency_slope:{overlap.get('label')}")
    check(tile_cache_report.get("schema") == "worldgen9.hydrology_tile_cache_report.v1", errors, "hydrology_tile_schema")
    check(int(tile_cache_report.get("built_tile_count", 0)) >= 4, errors, "hydrology_tile_count")
    check(close_float(tile_cache_report.get("tile_size_m", -1.0), 32768.0), errors, "hydrology_tile_size")
    check(tile_cache_report.get("fields", []) == ["flow_accumulation", "wetness", "channel_likelihood", "slope_deg"], errors, "hydrology_tile_fields")
    for check_record in tile_cache_report.get("checks", []):
        if check_record.get("check") == "repeatability":
            check(near_zero(check_record.get("max_delta", -1.0)), errors, "hydrology_tile_repeatability")
            continue
        for field_record in check_record.get("fields", []):
            field = field_record.get("field", "unknown")
            check(near_zero(field_record.get("max_edge_delta", -1.0)), errors, f"hydrology_tile_edge:{check_record.get('check')}:{field}")


def _check_debug_mode_perf_report(report: dict[str, Any], errors: list[str]) -> None:
    check(report.get("schema") == "worldgen9.debug_mode_perf_report.v1", errors, "debug_perf_schema")
    check(int(report.get("seed", 0)) == 1337, errors, "debug_perf_seed")
    check(int(report.get("vertices_per_side", 0)) == 33, errors, "debug_perf_vertices")
    check(int(report.get("visible_radius_chunks", -1)) == 1, errors, "debug_perf_radius")
    check(int(report.get("built_chunks", 0)) == 9, errors, "debug_perf_built_chunks")
    check(int(report.get("hydrology_tiles_built", 0)) == 4, errors, "debug_perf_hydrology_tiles")
    check(int(report.get("hydrology_overlay_tile_grid_size", 0)) == 65, errors, "debug_perf_hydrology_grid")
    check(int(report.get("hydrology_overlay_padding_cells", 0)) == 16, errors, "debug_perf_hydrology_padding")
    offset = report.get("hydrology_overlay_tile_origin_offset_m", [])
    check(offset == [16384.0, 16384.0], errors, "debug_perf_hydrology_origin_offset")
    timing_checks = report.get("timing_checks", {})
    limits = timing_checks.get("limits_ms", {})
    check(bool(timing_checks.get("hydrology_switch_within_limit", False)), errors, "debug_perf_hydrology_switch_limit")
    check(bool(timing_checks.get("gray_switch_within_limit", False)), errors, "debug_perf_gray_switch_limit")
    check(int(limits.get("hydrology_switch", 0)) == 25000, errors, "debug_perf_hydrology_limit")
    check(int(limits.get("gray_switch", 0)) == 10000, errors, "debug_perf_gray_limit")


def _check_streaming_far_overview_budget(
    runtime_budget: dict[str, Any],
    streaming_far_overview_manifest: dict[str, Any],
    errors: list[str],
) -> None:
    estimates = runtime_budget.get("streaming_far_clipmap_review_estimates", [])
    cases = streaming_far_overview_manifest.get("cases", [])
    check(len(estimates) >= 2, errors, "streaming_far_budget_estimates_missing")
    check(len(cases) >= 2, errors, "streaming_far_manifest_cases_missing")
    for level_count in [3, 4]:
        estimate = _find_by_int(estimates, "level_count", level_count)
        case = _find_by_int(cases, "level_count", level_count)
        if estimate is None:
            errors.append(f"streaming_far_budget_estimate_missing:{level_count}")
            continue
        if case is None:
            errors.append(f"streaming_far_manifest_case_missing:{level_count}")
            continue
        totals = estimate.get("totals", {})
        check(close_float(estimate.get("near_hole_extent_m", -1.0), 1984.0), errors, f"streaming_far_near_hole:{level_count}")
        check(int(case.get("far_vertex_count", -1)) == int(totals.get("vertex_count", -2)), errors, f"streaming_far_vertices:{level_count}")
        check(int(case.get("far_index_count", -1)) == int(totals.get("index_count", -2)), errors, f"streaming_far_indices:{level_count}")
        check(int(case.get("far_triangle_count", -1)) == int(totals.get("triangle_count", -2)), errors, f"streaming_far_triangles:{level_count}")
        check(
            abs(float(case.get("mesh_plus_height_mib", -1.0)) - float(totals.get("mesh_plus_height_mib", -2.0))) < 0.001,
            errors,
            f"streaming_far_memory:{level_count}",
        )


def _check_walk_density_manifest(manifest: dict[str, Any], errors: list[str]) -> None:
    check(manifest.get("schema") == "worldgen9.walk_density_review_manifest.v1", errors, "walk_density_manifest_schema")
    check(manifest.get("status") == "pass", errors, "walk_density_manifest_status")
    check(manifest.get("capture_size") == [1280, 720], errors, "walk_density_capture_size")
    cases = manifest.get("cases", [])
    check(len(cases) == 2, errors, "walk_density_case_count")
    expected = {
        "walk_density_129_4m": (129, 4.0),
        "walk_density_257_2m": (257, 2.0),
    }
    for case in cases:
        label = str(case.get("label", ""))
        if label not in expected:
            errors.append(f"walk_density_case_unexpected:{label}")
            continue
        vertices_per_side, spacing_m = expected[label]
        check(int(case.get("vertices_per_side", -1)) == vertices_per_side, errors, f"walk_density_vps:{label}")
        check(float(case.get("spacing_m", -1.0)) == spacing_m, errors, f"walk_density_spacing:{label}")
        stats = case.get("stats", {})
        check(float(stats.get("luma_range", 0.0)) >= 0.04, errors, f"walk_density_luma_range:{label}")
        check(float(stats.get("max_luma", 1.0)) <= 0.82, errors, f"walk_density_max_luma:{label}")
        check(float(stats.get("bright_pixel_fraction", 1.0)) <= 0.03, errors, f"walk_density_bright_fraction:{label}")
        check(float(stats.get("mean_luma", 1.0)) <= 0.62, errors, f"walk_density_mean_luma:{label}")
        check(int(stats.get("unique_colors", 0)) >= 6, errors, f"walk_density_unique_colors:{label}")
    check(
        float(manifest.get("mean_abs_luma_delta_129_to_257", 0.0)) > 0.0,
        errors,
        "walk_density_luma_delta_zero",
    )


def _case_by_label(cases: list[dict[str, Any]], label: str) -> dict[str, Any] | None:
    for item in cases:
        if str(item.get("label", "")) == label:
            return item
    return None


def _check_local_detail_budget(budget: dict[str, Any], prefix: str, errors: list[str]) -> None:
    check(int(budget.get("vertices_per_side", -1)) == 257, errors, f"{prefix}_vertices_per_side")
    check(close_float(budget.get("spacing_m", -1.0), 1.0), errors, f"{prefix}_spacing")
    check(int(budget.get("vertex_count_per_patch", -1)) == 66049, errors, f"{prefix}_vertex_count")
    check(int(budget.get("index_count_per_patch", -1)) == 393216, errors, f"{prefix}_index_count")
    check(int(budget.get("heightfield_bytes_per_patch", -1)) == 264196, errors, f"{prefix}_heightfield_bytes")


def _check_local_detail_cases(cases: list[dict[str, Any]], prefix: str, errors: list[str]) -> None:
    check(len(cases) == 3, errors, f"{prefix}_case_count")
    for label in ["base", "texture", "displacement"]:
        case = _case_by_label(cases, label)
        if case is None:
            errors.append(f"{prefix}_case_missing:{label}")
            continue
        min_luma_range = 0.012 if prefix == "walk_local_detail_manifest" and label == "base" else 0.04
        check(float(case.get("luma_range", 0.0)) >= min_luma_range, errors, f"{prefix}_{label}_luma_range")
        min_colors = 6 if label == "base" else 12
        check(int(case.get("unique_colors", 0)) >= min_colors, errors, f"{prefix}_{label}_unique_colors")
    texture_case = _case_by_label(cases, "texture")
    displacement_case = _case_by_label(cases, "displacement")
    if texture_case is not None:
        settings = texture_case.get("settings", {})
        check(bool(settings.get("surface_material", False)), errors, f"{prefix}_texture_surface_material")
        check(not bool(settings.get("visual_displacement", True)), errors, f"{prefix}_texture_visual_displacement")
    if displacement_case is not None:
        settings = displacement_case.get("settings", {})
        check(bool(settings.get("surface_material", False)), errors, f"{prefix}_displacement_surface_material")
        check(bool(settings.get("visual_displacement", False)), errors, f"{prefix}_displacement_visual_displacement")
        check(close_float(settings.get("displacement_limit_m", -1.0), 4.0), errors, f"{prefix}_displacement_limit")


def _check_local_detail_review_manifests(
    local_detail_manifest: dict[str, Any],
    walk_manifest: dict[str, Any],
    errors: list[str],
) -> None:
    check(local_detail_manifest.get("schema") == "worldgen9.local_detail_displacement_manifest.v1", errors, "local_detail_manifest_schema")
    check(walk_manifest.get("schema") == "worldgen9.walk_local_detail_review_manifest.v1", errors, "walk_local_detail_manifest_schema")
    _check_local_detail_budget(local_detail_manifest.get("patch", {}), "local_detail_manifest", errors)
    _check_local_detail_budget(walk_manifest.get("detail_budget", {}), "walk_local_detail_manifest", errors)
    check(not bool(walk_manifest.get("detail_budget", {}).get("collision_enabled", True)), errors, "walk_local_detail_collision_enabled")
    local_cases = local_detail_manifest.get("cases", [])
    walk_cases = walk_manifest.get("cases", [])
    _check_local_detail_cases(local_cases, "local_detail_manifest", errors)
    _check_local_detail_cases(walk_cases, "walk_local_detail_manifest", errors)
    check(
        float(local_detail_manifest.get("texture_to_displacement_mean_abs_luma_delta", 0.0)) > 0.0,
        errors,
        "local_detail_displacement_delta_zero",
    )
    check(
        float(walk_manifest.get("texture_to_displacement_mean_abs_luma_delta", 0.0)) > 0.0,
        errors,
        "walk_local_detail_displacement_delta_zero",
    )
    check(
        "subtle_displacement_luma_delta" in local_detail_manifest.get("review_flags", []),
        errors,
        "local_detail_subtle_flag_missing",
    )
    check(
        "subtle_displacement_luma_delta" in walk_manifest.get("review_flags", []),
        errors,
        "walk_local_detail_subtle_flag_missing",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = validate()
    if not args.dry_run:
        write_json(Path(args.out), report)
    print("[runtime-readiness] status=%s errors=%d" % (report["status"], len(report["errors"])))
    if not args.dry_run:
        print("[runtime-readiness] out=%s" % args.out)
    if report["errors"]:
        for error in report["errors"]:
            print("[runtime-readiness] error: %s" % error)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
