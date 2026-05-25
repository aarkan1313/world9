extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const HydrologySamplerScript := preload("res://worldgen_terrain/hydrology/hydrology_sampler.gd")
const HydrologyTileCacheScript := preload("res://worldgen_terrain/hydrology/hydrology_tile_cache.gd")

const OUT_DIR := "factory/runtime/godot_hydrology_tiles"
const TILE_GRID_SIZE := 97
const TILE_PADDING_CELLS := 24
const CHUNK_DENSITY := 33
const FLOAT_EPSILON := 0.000001
const SHEET_COLUMNS := 3
const SHEET_GUTTER_PX := 4


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
	var cache: RefCounted = HydrologyTileCacheScript.new()
	cache.setup(
		world,
		TerrainSettingsScript.REGION_SIZE_M,
		TILE_GRID_SIZE,
		TILE_PADDING_CELLS
	)
	var reports: Array[Dictionary] = []
	_check_invalid_inputs(world, cache, errors, reports)
	_check_repeatability(cache, errors, reports)
	_check_eviction_policy(cache, errors, reports)
	_check_chunk_edge("origin_chunks", cache, 0, 0, errors, reports)
	_check_chunk_edge("tile_boundary_chunks", cache, 15, 0, errors, reports)
	_save_boundary_contact_sheet(cache, errors)
	_save_report(cache, reports, errors)
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-hydrology-tiles] status=pass tiles=%d checks=%d" % [
		int(cache.built_tile_count()),
		reports.size(),
	])
	return 0


func _check_repeatability(cache: RefCounted, errors: Array[String], reports: Array[Dictionary]) -> void:
	var points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(TerrainSettingsScript.REGION_SIZE_M - 1.0, 512.0),
		Vector2(TerrainSettingsScript.REGION_SIZE_M, 512.0),
	]
	var max_delta := 0.0
	for point in points:
		var a: Dictionary = cache.sample(point.x, point.y)
		var b: Dictionary = cache.sample(point.x, point.y)
		for field in _scalar_fields():
			max_delta = max(max_delta, abs(float(a[field]) - float(b[field])))
			max_delta = max(max_delta, abs(float(a[field]) - float(cache.sample_field(point.x, point.y, field))))
	if max_delta > FLOAT_EPSILON:
		errors.append("repeatability_delta:%.9f" % max_delta)
	reports.append({
		"check": "repeatability",
		"points": points.size(),
		"max_delta": max_delta,
	})


func _check_invalid_inputs(
	world: RefCounted,
	cache: RefCounted,
	errors: Array[String],
	reports: Array[Dictionary]
) -> void:
	var sampler: RefCounted = HydrologySamplerScript.new()
	var invalid_reports: Array[Dictionary] = [
		sampler.sample_window(null, Vector2.ZERO, TerrainSettingsScript.REGION_SIZE_M, TILE_GRID_SIZE, TILE_PADDING_CELLS),
		sampler.sample_window(RefCounted.new(), Vector2.ZERO, TerrainSettingsScript.REGION_SIZE_M, TILE_GRID_SIZE, TILE_PADDING_CELLS),
		sampler.sample_window(world, Vector2.ZERO, 0.0, TILE_GRID_SIZE, TILE_PADDING_CELLS),
		sampler.sample_window(world, Vector2.ZERO, TerrainSettingsScript.REGION_SIZE_M, 1, TILE_PADDING_CELLS),
		sampler.sample_window(world, Vector2.ZERO, TerrainSettingsScript.REGION_SIZE_M, TILE_GRID_SIZE, -1),
	]
	for index in range(invalid_reports.size()):
		if str(invalid_reports[index].get("status", "fail")) != "fail":
			errors.append("invalid_sampler_input_passed:%d" % index)
	var bad_grid: PackedFloat32Array = cache.sample_grid(0.0, 0.0, 32.0, 4, 4, "bad_field")
	if not bad_grid.is_empty():
		errors.append("invalid_field_grid_not_empty:%d" % bad_grid.size())
	var bad_field: float = cache.sample_field(0.0, 0.0, "bad_field")
	if not _is_nan(bad_field):
		errors.append("invalid_field_not_nan:%.6f" % bad_field)
	var fail_tile: Dictionary = {
		"status": "fail",
		"error": "forced_failure",
	}
	var failed_tile_value: float = cache.sample_tile_field(fail_tile, 0.0, 0.0, HydrologyTileCacheScript.FIELD_WETNESS)
	if not _is_nan(failed_tile_value):
		errors.append("failed_tile_field_not_nan:%.6f" % failed_tile_value)
	reports.append({
		"check": "invalid_inputs",
		"sampler_failures": invalid_reports.size(),
		"cache_error_count": int(cache.errors.size()),
	})


func _check_eviction_policy(cache: RefCounted, errors: Array[String], reports: Array[Dictionary]) -> void:
	cache.set_max_cached_tiles(2)
	var points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(TerrainSettingsScript.REGION_SIZE_M, 0.0),
		Vector2(TerrainSettingsScript.REGION_SIZE_M * 2.0, 0.0),
	]
	for point in points:
		cache.sample(point.x, point.y)
	var count: int = int(cache.built_tile_count())
	if count > 2:
		errors.append("eviction_tile_count:%d" % count)
	cache.set_max_cached_tiles(32)
	reports.append({
		"check": "eviction_policy",
		"max_cached_tiles": 2,
		"tile_count": count,
	})


func _check_chunk_edge(
	label: String,
	cache: RefCounted,
	west_chunk_x: int,
	chunk_z: int,
	errors: Array[String],
	reports: Array[Dictionary]
) -> void:
	var density := CHUNK_DENSITY
	var step_m: float = TerrainSettingsScript.CHUNK_SIZE_M / float(density - 1)
	var west_origin_x: float = float(west_chunk_x) * TerrainSettingsScript.CHUNK_SIZE_M
	var east_origin_x: float = float(west_chunk_x + 1) * TerrainSettingsScript.CHUNK_SIZE_M
	var origin_z: float = float(chunk_z) * TerrainSettingsScript.CHUNK_SIZE_M
	var field_reports: Array[Dictionary] = []
	for field in _scalar_fields():
		var west: PackedFloat32Array = cache.sample_grid(west_origin_x, origin_z, step_m, density, density, field)
		var east: PackedFloat32Array = cache.sample_grid(east_origin_x, origin_z, step_m, density, density, field)
		var max_delta := 0.0
		for row in range(density):
			max_delta = max(max_delta, abs(float(west[row * density + density - 1]) - float(east[row * density])))
		if max_delta > FLOAT_EPSILON:
			errors.append("%s_%s_delta:%.9f" % [label, field, max_delta])
		field_reports.append({
			"field": field,
			"max_edge_delta": max_delta,
		})
	reports.append({
		"check": label,
		"west_chunk_x": west_chunk_x,
		"east_chunk_x": west_chunk_x + 1,
		"chunk_z": chunk_z,
		"density": density,
		"fields": field_reports,
	})


func _save_boundary_contact_sheet(cache: RefCounted, errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var size := 97
	var span_m: float = TerrainSettingsScript.CHUNK_SIZE_M * 4.0
	var step_m: float = span_m / float(size - 1)
	var origin_x: float = TerrainSettingsScript.REGION_SIZE_M - span_m * 0.5
	var origin_z: float = -span_m * 0.5
	var images: Array[Image] = []
	for field in _scalar_fields():
		var values: PackedFloat32Array = cache.sample_grid(origin_x, origin_z, step_m, size, size, field)
		images.append(_heat_image(values, size, field == HydrologyTileCacheScript.FIELD_FLOW_ACCUMULATION))
	var path: String = out_dir.path_join("hydrology_tile_boundary_contact_sheet.png")
	var sheet_width: int = size * SHEET_COLUMNS + SHEET_GUTTER_PX * (SHEET_COLUMNS - 1)
	var sheet := Image.create(sheet_width, size, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in range(images.size()):
		var dest := Vector2i(index * (size + SHEET_GUTTER_PX), 0)
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, Vector2i(size, size)), dest)
	_save_image(sheet, path, errors)


func _heat_image(values: PackedFloat32Array, size: int, log_scale: bool) -> Image:
	var max_value := 0.000001
	for value in values:
		var v: float = float(value)
		if log_scale:
			v = log(1.0 + v)
		max_value = max(max_value, v)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var raw: float = float(values[y * size + x])
			var scaled: float = log(1.0 + raw) if log_scale else raw
			image.set_pixel(x, y, _heat_color(clampf(scaled / max_value, 0.0, 1.0)))
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


func _save_report(cache: RefCounted, reports: Array[Dictionary], errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join("hydrology_tile_cache_report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	var report := {
		"schema": "worldgen9.hydrology_tile_cache_report.v1",
		"seed": 1337,
		"tile_size_m": TerrainSettingsScript.REGION_SIZE_M,
		"tile_grid_size": TILE_GRID_SIZE,
		"tile_padding_cells": TILE_PADDING_CELLS,
		"chunk_density": CHUNK_DENSITY,
		"epsilon": FLOAT_EPSILON,
		"fields": _scalar_fields(),
		"built_tile_count": int(cache.built_tile_count()),
		"policy": "Chunks and debug overlays sample hydrology by world coordinate through an owning hydrology tile cache; they do not solve accumulation independently per visible chunk.",
		"checks": reports,
	}
	file.store_string(JSON.stringify(report, "\t"))


func _save_image(image: Image, path: String, errors: Array[String]) -> void:
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save:%s:%d" % [path, int(save_result)])


func _scalar_fields() -> Array[String]:
	return [
		HydrologyTileCacheScript.FIELD_FLOW_ACCUMULATION,
		HydrologyTileCacheScript.FIELD_WETNESS,
		HydrologyTileCacheScript.FIELD_CHANNEL_LIKELIHOOD,
		HydrologyTileCacheScript.FIELD_SLOPE_DEG,
	]


func _is_nan(value: float) -> bool:
	return value != value


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-hydrology-tiles] status=fail errors=%d" % errors.size())
