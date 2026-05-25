extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_landform_quality"
const GRID_SIZE := 97
const SPAN_CHUNKS := 6.0
const SHEET_COLUMNS := 2


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

	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cases: Array[Dictionary] = _review_cases()
	var images: Array[Image] = []
	var reports: Array[Dictionary] = []
	for index in range(cases.size()):
		var item: Dictionary = cases[index]
		var result: Dictionary = _probe_case(world, item, out_dir, index, errors, warnings)
		if result.has("image"):
			images.append(result["image"] as Image)
		if result.has("report"):
			reports.append(result["report"] as Dictionary)

	if images.size() == cases.size():
		_save_contact_sheet(images, out_dir.path_join("landform_quality_contact_sheet.png"), errors)
	_save_report(out_dir.path_join("landform_quality_report.json"), reports, warnings, errors)

	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-landform-quality] status=pass cases=%d warnings=%d out=%s" % [
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


func _probe_case(
	world: RefCounted,
	item: Dictionary,
	out_dir: String,
	index: int,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var center: Vector2 = item["center"] as Vector2
	var span_m: float = TerrainSettingsScript.CHUNK_SIZE_M * SPAN_CHUNKS
	var step_m: float = span_m / float(GRID_SIZE - 1)
	var origin_x: float = center.x - span_m * 0.5
	var origin_z: float = center.y - span_m * 0.5
	var height: PackedFloat32Array = world.sample_height_grid(origin_x, origin_z, step_m, GRID_SIZE, GRID_SIZE)
	if height.size() != GRID_SIZE * GRID_SIZE:
		errors.append("%s_grid_size:%d" % [str(item["label"]), height.size()])
		return {}
	var metrics: Dictionary = _height_metrics(height, step_m)
	_add_case_warnings(str(item["label"]), metrics, warnings)
	if float(metrics["height_range_m"]) <= 1.0:
		errors.append("%s_blank_height_range:%.3f" % [str(item["label"]), float(metrics["height_range_m"])])

	var center_sample: Dictionary = world.sample(center.x, center.y)
	var image: Image = _height_image(height, metrics)
	var image_name: String = "landform_%02d_%s.png" % [index, str(item["label"])]
	var save_result: Error = image.save_png(out_dir.path_join(image_name))
	if save_result != OK:
		errors.append("%s_save:%d" % [str(item["label"]), int(save_result)])

	var report := {
		"index": index,
		"label": str(item["label"]),
		"center_m": [center.x, center.y],
		"span_m": span_m,
		"grid_size": GRID_SIZE,
		"step_m": step_m,
		"image": image_name,
		"primary_family": str(center_sample.get("primary_family", "unknown")),
		"secondary_family": str(center_sample.get("secondary_family", "unknown")),
		"source_confidence": float(center_sample.get("source_confidence", 0.0)),
		"source_resolution_m": float(center_sample.get("source_resolution_m", 0.0)),
		"height_min_m": float(metrics["height_min_m"]),
		"height_max_m": float(metrics["height_max_m"]),
		"height_range_m": float(metrics["height_range_m"]),
		"relief_p05_p95_m": float(metrics["relief_p05_p95_m"]),
		"mean_abs_slope_deg": float(metrics["mean_abs_slope_deg"]),
		"mean_local_relief_m": float(metrics["mean_local_relief_m"]),
		"landform_signal": _landform_signal(metrics),
	}
	return {
		"image": image,
		"report": report,
	}


func _height_metrics(height: PackedFloat32Array, step_m: float) -> Dictionary:
	var min_height := INF
	var max_height := -INF
	var values: Array[float] = []
	values.resize(height.size())
	for index in range(height.size()):
		var value: float = float(height[index])
		values[index] = value
		min_height = min(min_height, value)
		max_height = max(max_height, value)
	values.sort()
	var p05: float = values[int(floor(float(values.size() - 1) * 0.05))]
	var p95: float = values[int(floor(float(values.size() - 1) * 0.95))]

	var slope_total := 0.0
	var local_relief_total := 0.0
	var count := 0
	for z in range(1, GRID_SIZE - 1):
		for x in range(1, GRID_SIZE - 1):
			var left: float = float(height[z * GRID_SIZE + x - 1])
			var right: float = float(height[z * GRID_SIZE + x + 1])
			var north: float = float(height[(z - 1) * GRID_SIZE + x])
			var south: float = float(height[(z + 1) * GRID_SIZE + x])
			var dx: float = (right - left) / (step_m * 2.0)
			var dz: float = (south - north) / (step_m * 2.0)
			slope_total += rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
			var local_min: float = min(left, right, north, south)
			var local_max: float = max(left, right, north, south)
			local_relief_total += local_max - local_min
			count += 1

	return {
		"height_min_m": min_height,
		"height_max_m": max_height,
		"height_range_m": max_height - min_height,
		"relief_p05_p95_m": p95 - p05,
		"mean_abs_slope_deg": slope_total / max(1, count),
		"mean_local_relief_m": local_relief_total / max(1, count),
	}


func _add_case_warnings(label: String, metrics: Dictionary, warnings: Array[String]) -> void:
	if float(metrics["relief_p05_p95_m"]) < 80.0:
		warnings.append("%s_low_relief_p05_p95" % label)
	if float(metrics["mean_abs_slope_deg"]) < 0.45:
		warnings.append("%s_low_mean_slope" % label)
	if float(metrics["mean_local_relief_m"]) < 8.0:
		warnings.append("%s_low_local_relief" % label)


func _landform_signal(metrics: Dictionary) -> String:
	var relief: float = float(metrics["relief_p05_p95_m"])
	var slope: float = float(metrics["mean_abs_slope_deg"])
	var local_relief: float = float(metrics["mean_local_relief_m"])
	if relief >= 350.0 and slope >= 2.0:
		return "strong"
	if relief >= 160.0 and slope >= 1.0:
		return "moderate"
	if relief >= 80.0 or local_relief >= 8.0:
		return "subtle"
	return "weak"


func _height_image(height: PackedFloat32Array, metrics: Dictionary) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	var min_height: float = float(metrics["height_min_m"])
	var max_height: float = float(metrics["height_max_m"])
	var denom: float = max(0.0001, max_height - min_height)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var value: float = float(height[y * GRID_SIZE + x])
			var normalized: float = clampf((value - min_height) / denom, 0.0, 1.0)
			var shaded: float = pow(normalized, 0.82)
			image.set_pixel(x, y, Color(shaded, shaded, shaded))
	return image


func _save_contact_sheet(images: Array[Image], path: String, errors: Array[String]) -> void:
	var rows: int = int(ceil(float(images.size()) / float(SHEET_COLUMNS)))
	var sheet := Image.create(GRID_SIZE * SHEET_COLUMNS, GRID_SIZE * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in range(images.size()):
		var column: int = index % SHEET_COLUMNS
		var row: int = index / SHEET_COLUMNS
		var dest := Vector2i(column * GRID_SIZE, row * GRID_SIZE)
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), dest)
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _save_report(path: String, cases: Array[Dictionary], warnings: Array[String], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	var report := {
		"schema": "worldgen9.landform_quality_report.v1",
		"seed": 1337,
		"span_chunks": SPAN_CHUNKS,
		"grid_size": GRID_SIZE,
		"warnings": warnings,
		"cases": cases,
	}
	file.store_string(JSON.stringify(report, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-landform-quality] status=fail errors=%d" % errors.size())
