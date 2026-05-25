extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const HydrologySamplerScript := preload("res://worldgen_terrain/hydrology/hydrology_sampler.gd")

const OUT_DIR := "factory/runtime/godot_hydrology_hints"
const GRID_SIZE := 97
const SPAN_CHUNKS := 6.0
const PADDING_CELLS := 24
const SHIFT_CELLS := 16
const EDGE_MARGIN_CELLS := 3
const SLOPE_EPSILON_DEG := 0.0001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("setup:%s" % str(error))
		_report(errors)
		return 1
	var sampler: RefCounted = HydrologySamplerScript.new()
	var span_m: float = TerrainSettingsScript.CHUNK_SIZE_M * SPAN_CHUNKS
	var step_m: float = span_m / float(GRID_SIZE - 1)
	var base_center := Vector2.ZERO
	var east_center := Vector2(float(SHIFT_CELLS) * step_m, 0.0)
	var north_center := Vector2(0.0, float(SHIFT_CELLS) * step_m)
	var base: Dictionary = sampler.sample_window(world, base_center, span_m, GRID_SIZE, PADDING_CELLS)
	var east: Dictionary = sampler.sample_window(world, east_center, span_m, GRID_SIZE, PADDING_CELLS)
	var north: Dictionary = sampler.sample_window(world, north_center, span_m, GRID_SIZE, PADDING_CELLS)
	_check_result("base", base, errors)
	_check_result("east", east, errors)
	_check_result("north", north, errors)
	if errors.is_empty():
		var reports: Array[Dictionary] = []
		reports.append(_check_overlap("east", base, east, SHIFT_CELLS, 0, errors))
		reports.append(_check_overlap("north", base, north, 0, SHIFT_CELLS, errors))
		_save_report(reports, errors)
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-hydrology-consistency] status=pass grid=%d shift_cells=%d margin=%d" % [
		GRID_SIZE,
		SHIFT_CELLS,
		EDGE_MARGIN_CELLS,
	])
	return 0


func _check_result(label: String, result: Dictionary, errors: Array[String]) -> void:
	if result.get("status", "fail") != "pass":
		errors.append("%s:%s" % [label, str(result.get("error", "unknown"))])


func _check_overlap(label: String, base: Dictionary, shifted: Dictionary, dx_cells: int, dz_cells: int, errors: Array[String]) -> Dictionary:
	var base_slope: PackedFloat32Array = base["slope_deg"] as PackedFloat32Array
	var shifted_slope: PackedFloat32Array = shifted["slope_deg"] as PackedFloat32Array
	var base_dir: PackedVector2Array = base["flow_dir"] as PackedVector2Array
	var shifted_dir: PackedVector2Array = shifted["flow_dir"] as PackedVector2Array
	var compared := 0
	var dir_mismatch := 0
	var max_slope_delta := 0.0
	var window_metrics: Array[Dictionary] = []
	var window_fields: Array[String] = [
		"flow_accumulation",
		"wetness",
		"channel_likelihood",
	]
	var x_start: int = EDGE_MARGIN_CELLS + max(dx_cells, 0)
	var x_end: int = GRID_SIZE - EDGE_MARGIN_CELLS + min(dx_cells, 0)
	var z_start: int = EDGE_MARGIN_CELLS + max(dz_cells, 0)
	var z_end: int = GRID_SIZE - EDGE_MARGIN_CELLS + min(dz_cells, 0)
	for field in window_fields:
		window_metrics.append({
			"field": field,
			"max_delta": 0.0,
			"mean_delta": 0.0,
		})
	for z in range(z_start, z_end):
		for x in range(x_start, x_end):
			var shifted_x: int = x - dx_cells
			var shifted_z: int = z - dz_cells
			var base_index: int = z * GRID_SIZE + x
			var shifted_index: int = shifted_z * GRID_SIZE + shifted_x
			var slope_delta: float = abs(float(base_slope[base_index]) - float(shifted_slope[shifted_index]))
			max_slope_delta = max(max_slope_delta, slope_delta)
			var base_vector: Vector2 = base_dir[base_index]
			var shifted_vector: Vector2 = shifted_dir[shifted_index]
			if base_vector.length_squared() > 0.0001 or shifted_vector.length_squared() > 0.0001:
				if base_vector.dot(shifted_vector) < 0.999:
					dir_mismatch += 1
			for metric_index in range(window_fields.size()):
				var field: String = window_fields[metric_index]
				var base_values: PackedFloat32Array = base[field] as PackedFloat32Array
				var shifted_values: PackedFloat32Array = shifted[field] as PackedFloat32Array
				var delta: float = abs(float(base_values[base_index]) - float(shifted_values[shifted_index]))
				var metric: Dictionary = window_metrics[metric_index]
				metric["max_delta"] = max(float(metric["max_delta"]), delta)
				metric["mean_delta"] = float(metric["mean_delta"]) + delta
			compared += 1
	if compared <= 0:
		errors.append("%s_no_overlap" % label)
	if max_slope_delta > SLOPE_EPSILON_DEG:
		errors.append("%s_slope_delta:%.8f" % [label, max_slope_delta])
	if dir_mismatch > 0:
		errors.append("%s_dir_mismatch:%d/%d" % [label, dir_mismatch, compared])
	for metric in window_metrics:
		metric["mean_delta"] = float(metric["mean_delta"]) / float(max(1, compared))
	return {
		"label": label,
		"compared_cells": compared,
		"stable_field_metrics": {
			"max_slope_delta_deg": max_slope_delta,
			"flow_dir_mismatch_count": dir_mismatch,
		},
		"window_limited_field_metrics": window_metrics,
	}


func _save_report(overlaps: Array[Dictionary], errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(out_dir.path_join("hydrology_consistency_report.json"), FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:hydrology_consistency_report.json")
		return
	var report := {
		"schema": "worldgen9.hydrology_consistency_report.v1",
		"seed": 1337,
		"grid_size": GRID_SIZE,
		"span_chunks": SPAN_CHUNKS,
		"padding_cells": PADDING_CELLS,
		"shift_cells": SHIFT_CELLS,
		"edge_margin_cells": EDGE_MARGIN_CELLS,
		"stable_fields": ["height", "slope_deg", "flow_dir"],
		"window_limited_fields": ["flow_accumulation", "wetness", "channel_likelihood"],
		"policy": "Only stable fields are allowed to gate seam correctness at this phase. Window-limited fields need a persistent basin/tile hydrology layer before runtime use.",
		"overlaps": overlaps,
	}
	file.store_string(JSON.stringify(report, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-hydrology-consistency] status=fail errors=%d" % errors.size())
