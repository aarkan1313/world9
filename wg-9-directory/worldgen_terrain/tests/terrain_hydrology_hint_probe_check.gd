extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const HydrologySamplerScript := preload("res://worldgen_terrain/hydrology/hydrology_sampler.gd")

const OUT_DIR := "factory/runtime/godot_hydrology_hints"
const GRID_SIZE := 97
const SPAN_CHUNKS := 6.0
const PADDING_CELLS := 24
const SHEET_COLUMNS := 3
const SHEET_GUTTER_PX := 4
const STRONG_CHANNEL_THRESHOLD := 0.42
const WET_CELL_THRESHOLD := 0.55


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("setup:%s" % str(error))
		_report(errors)
		return 1
	var sampler: RefCounted = HydrologySamplerScript.new()
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cases: Array[Dictionary] = _review_cases()
	var sheet_images: Array[Image] = []
	var reports: Array[Dictionary] = []
	for index in range(cases.size()):
		var item: Dictionary = cases[index]
		var center: Vector2 = item["center"] as Vector2
		var result: Dictionary = sampler.sample_window(
			world,
			center,
			TerrainSettingsScript.CHUNK_SIZE_M * SPAN_CHUNKS,
			GRID_SIZE,
			PADDING_CELLS
		)
		if result.get("status", "fail") != "pass":
			errors.append("%s:%s" % [str(item["label"]), str(result.get("error", "unknown"))])
			continue
		var images: Dictionary = _save_case_images(index, str(item["label"]), result, out_dir, errors)
		sheet_images.append(images["flow"] as Image)
		sheet_images.append(images["wetness"] as Image)
		sheet_images.append(images["channel"] as Image)
		var report: Dictionary = _case_report(index, str(item["label"]), center, result)
		_add_warnings(report, warnings)
		reports.append(report)
	if sheet_images.size() == cases.size() * SHEET_COLUMNS:
		_save_contact_sheet(sheet_images, out_dir.path_join("hydrology_hint_contact_sheet.png"), errors)
	_save_report(out_dir.path_join("hydrology_hint_report.json"), reports, warnings, errors)
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-hydrology-hints] status=pass cases=%d warnings=%d out=%s" % [
		reports.size(),
		warnings.size(),
		out_dir,
	])
	return 0


func _review_cases() -> Array[Dictionary]:
	var region: float = TerrainSettingsScript.REGION_SIZE_M
	return [
		{"label": "origin", "center": Vector2(0.0, 0.0)},
		{"label": "east_region", "center": Vector2(region * 1.25, region * 0.15)},
		{"label": "northwest_region", "center": Vector2(region * -0.75, region * 1.35)},
		{"label": "far_southwest", "center": Vector2(region * -2.1, region * -1.6)},
		{"label": "far_northeast", "center": Vector2(region * 2.4, region * 2.0)},
		{"label": "long_travel", "center": Vector2(region * 5.5, region * -3.25)},
	]


func _save_case_images(index: int, label: String, result: Dictionary, out_dir: String, errors: Array[String]) -> Dictionary:
	var flow: Image = _heat_image(result["flow_accumulation"] as PackedFloat32Array, true)
	var wetness: Image = _heat_image(result["wetness"] as PackedFloat32Array, false)
	var channel: Image = _heat_image(result["channel_likelihood"] as PackedFloat32Array, false)
	_save_image(flow, out_dir.path_join("hydrology_%02d_%s_flow.png" % [index, label]), errors)
	_save_image(wetness, out_dir.path_join("hydrology_%02d_%s_wetness.png" % [index, label]), errors)
	_save_image(channel, out_dir.path_join("hydrology_%02d_%s_channel.png" % [index, label]), errors)
	return {
		"flow": flow,
		"wetness": wetness,
		"channel": channel,
	}


func _case_report(index: int, label: String, center: Vector2, result: Dictionary) -> Dictionary:
	var flow: PackedFloat32Array = result["flow_accumulation"] as PackedFloat32Array
	var wetness: PackedFloat32Array = result["wetness"] as PackedFloat32Array
	var channel: PackedFloat32Array = result["channel_likelihood"] as PackedFloat32Array
	var slope: PackedFloat32Array = result["slope_deg"] as PackedFloat32Array
	var strong_channel_cells := 0
	var wet_cells := 0
	var channel_total := 0.0
	var wetness_total := 0.0
	var slope_total := 0.0
	var max_channel := 0.0
	var max_wetness := 0.0
	for cell_index in range(channel.size()):
		var channel_value: float = float(channel[cell_index])
		var wetness_value: float = float(wetness[cell_index])
		channel_total += channel_value
		wetness_total += wetness_value
		slope_total += float(slope[cell_index])
		max_channel = max(max_channel, channel_value)
		max_wetness = max(max_wetness, wetness_value)
		if channel_value >= STRONG_CHANNEL_THRESHOLD:
			strong_channel_cells += 1
		if wetness_value >= WET_CELL_THRESHOLD:
			wet_cells += 1
	return {
		"index": index,
		"label": label,
		"center_m": [center.x, center.y],
		"span_m": float(result["span_m"]),
		"grid_size": int(result["grid_size"]),
		"padding_cells": int(result["padding_cells"]),
		"stable_fields": result.get("stable_fields", []),
		"window_limited_fields": result.get("window_limited_fields", []),
		"step_m": float(result["step_m"]),
		"height_min_m": float(result["height_min_m"]),
		"height_max_m": float(result["height_max_m"]),
		"max_flow_accumulation": float(result["max_flow_accumulation"]),
		"mean_channel_likelihood": channel_total / max(1, channel.size()),
		"mean_wetness": wetness_total / max(1, wetness.size()),
		"mean_slope_deg": slope_total / max(1, slope.size()),
		"max_channel_likelihood": max_channel,
		"max_wetness": max_wetness,
		"strong_channel_threshold": STRONG_CHANNEL_THRESHOLD,
		"wet_cell_threshold": WET_CELL_THRESHOLD,
		"strong_channel_fraction": float(strong_channel_cells) / float(max(1, channel.size())),
		"wet_cell_fraction": float(wet_cells) / float(max(1, wetness.size())),
		"flow_image": "hydrology_%02d_%s_flow.png" % [index, label],
		"wetness_image": "hydrology_%02d_%s_wetness.png" % [index, label],
		"channel_image": "hydrology_%02d_%s_channel.png" % [index, label],
	}


func _add_warnings(report: Dictionary, warnings: Array[String]) -> void:
	var label: String = str(report["label"])
	if float(report["max_flow_accumulation"]) < 24.0:
		warnings.append("%s_low_accumulation" % label)
	if float(report["max_channel_likelihood"]) < STRONG_CHANNEL_THRESHOLD:
		warnings.append("%s_low_channel_peak" % label)
	if float(report["max_wetness"]) < WET_CELL_THRESHOLD:
		warnings.append("%s_low_wetness_peak" % label)


func _heat_image(values: PackedFloat32Array, log_scale: bool) -> Image:
	var max_value := 0.000001
	for value in values:
		var v: float = float(value)
		if log_scale:
			v = log(1.0 + v)
		max_value = max(max_value, v)
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var raw: float = float(values[y * GRID_SIZE + x])
			var scaled: float = log(1.0 + raw) if log_scale else raw
			var normalized: float = clampf(scaled / max_value, 0.0, 1.0)
			image.set_pixel(x, y, _heat_color(normalized))
	return image


func _heat_color(value: float) -> Color:
	var v: float = clampf(value, 0.0, 1.0)
	if v < 0.35:
		var t: float = v / 0.35
		return Color(0.04 + 0.10 * t, 0.05 + 0.18 * t, 0.10 + 0.35 * t)
	if v < 0.72:
		var t2: float = (v - 0.35) / 0.37
		return Color(0.14 + 0.18 * t2, 0.23 + 0.50 * t2, 0.45 - 0.20 * t2)
	var t3: float = (v - 0.72) / 0.28
	return Color(0.32 + 0.66 * t3, 0.73 - 0.08 * t3, 0.25 - 0.17 * t3)


func _save_image(image: Image, path: String, errors: Array[String]) -> void:
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save:%s:%d" % [path, int(save_result)])


func _save_contact_sheet(images: Array[Image], path: String, errors: Array[String]) -> void:
	var rows: int = int(ceil(float(images.size()) / float(SHEET_COLUMNS)))
	var sheet_width: int = GRID_SIZE * SHEET_COLUMNS + SHEET_GUTTER_PX * (SHEET_COLUMNS - 1)
	var sheet_height: int = GRID_SIZE * rows + SHEET_GUTTER_PX * (rows - 1)
	var sheet := Image.create(sheet_width, sheet_height, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in range(images.size()):
		var column: int = index % SHEET_COLUMNS
		var row: int = index / SHEET_COLUMNS
		var dest := Vector2i(
			column * (GRID_SIZE + SHEET_GUTTER_PX),
			row * (GRID_SIZE + SHEET_GUTTER_PX)
		)
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), dest)
	_save_image(sheet, path, errors)


func _save_report(path: String, cases: Array[Dictionary], warnings: Array[String], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	var report := {
		"schema": "worldgen9.hydrology_hint_report.v1",
		"seed": 1337,
		"span_chunks": SPAN_CHUNKS,
		"grid_size": GRID_SIZE,
		"padding_cells": PADDING_CELLS,
		"seam_policy": "height, slope, and local flow direction are world-coordinate stable; accumulation, wetness, and channel likelihood are window-limited diagnostics until a persistent basin/tile hydrology layer exists",
		"columns": ["flow_accumulation", "wetness", "channel_likelihood"],
		"warnings": warnings,
		"cases": cases,
	}
	file.store_string(JSON.stringify(report, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-hydrology-hints] status=fail errors=%d" % errors.size())
