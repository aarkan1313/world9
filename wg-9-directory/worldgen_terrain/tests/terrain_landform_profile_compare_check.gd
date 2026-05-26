extends SceneTree

const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_landform_profiles"
const GRID_SIZE := 81
const SPAN_REGION_FRACTION := 0.42
const SHEET_COLUMNS := 3


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

	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_validate_neutral_profile(world, errors)
	var sites: Array[Dictionary] = _select_sites(world)
	var reports: Array[Dictionary] = []
	var images: Array[Image] = []
	for site in sites:
		var site_report: Dictionary = _probe_site_profiles(world, site, out_dir, images, errors)
		if not site_report.is_empty():
			reports.append(site_report)

	_validate_profile_effects(reports, errors)
	if not images.is_empty():
		_save_contact_sheet(images, out_dir.path_join("landform_profile_contact_sheet.png"), errors)
	_save_report(out_dir.path_join("landform_profile_report.json"), reports, errors)

	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-landform-profile] status=pass sites=%d profiles=%d out=%s" % [
		reports.size(),
		TerrainLandformProfileScript.profile_ids().size(),
		out_dir,
	])
	return 0


func _validate_neutral_profile(world: RefCounted, errors: Array[String]) -> void:
	var center := Vector2(0.25 * world.region_size_m, -0.35 * world.region_size_m)
	var span_m: float = world.region_size_m * SPAN_REGION_FRACTION
	var before: PackedFloat32Array = _sample_grid(world, center, span_m)
	if not world.apply_landform_profile(TerrainLandformProfileScript.BALANCED_CURRENT):
		errors.append("balanced_profile_apply_failed")
		return
	var after: PackedFloat32Array = _sample_grid(world, center, span_m)
	if before.size() != after.size() or before.is_empty():
		errors.append("balanced_profile_grid_size")
		return
	var max_delta := 0.0
	for index in range(before.size()):
		max_delta = max(max_delta, absf(float(before[index]) - float(after[index])))
	if max_delta > 0.0001:
		errors.append("balanced_profile_changed_default:%.6f" % max_delta)


func _select_sites(world: RefCounted) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var wanted_families: Array[String] = ["mountain", "glacial", "volcanic"]
	var region_size: float = world.region_size_m
	for rz in range(-6, 7):
		for rx in range(-6, 7):
			var center := Vector2((float(rx) + 0.5) * region_size, (float(rz) + 0.5) * region_size)
			var sample: Dictionary = world.sample(center.x, center.y)
			var primary: String = str(sample.get("primary_family", ""))
			var secondary: String = str(sample.get("secondary_family", ""))
			if wanted_families.has(primary) or wanted_families.has(secondary):
				selected.append({
					"label": "%s_%d_%d" % [primary, rx, rz],
					"region": Vector2i(rx, rz),
					"center_m": center,
					"primary_family": primary,
					"secondary_family": secondary,
				})
			if selected.size() >= 3:
				return selected
	return [
		{"label": "origin", "region": Vector2i.ZERO, "center_m": Vector2.ZERO, "primary_family": "unknown", "secondary_family": "unknown"},
	]


func _probe_site_profiles(
	world: RefCounted,
	site: Dictionary,
	out_dir: String,
	images: Array[Image],
	errors: Array[String]
) -> Dictionary:
	var center: Vector2 = site["center_m"] as Vector2
	var span_m: float = world.region_size_m * SPAN_REGION_FRACTION
	var profile_reports: Array[Dictionary] = []
	for profile_id in TerrainLandformProfileScript.profile_ids():
		if not world.apply_landform_profile(profile_id):
			errors.append("%s_apply_failed" % profile_id)
			continue
		var heights: PackedFloat32Array = _sample_grid(world, center, span_m)
		if heights.size() != GRID_SIZE * GRID_SIZE:
			errors.append("%s_%s_grid:%d" % [str(site["label"]), profile_id, heights.size()])
			continue
		var metrics: Dictionary = _height_metrics(heights, span_m / float(GRID_SIZE - 1))
		var seam: Dictionary = _seam_report(world, center, span_m)
		var image: Image = _height_image(heights, metrics)
		var image_name := "landform_profile_%s_%s.png" % [profile_id, str(site["label"])]
		var save_result: Error = image.save_png(out_dir.path_join(image_name))
		if save_result != OK:
			errors.append("%s_save:%d" % [image_name, int(save_result)])
		images.append(image)
		profile_reports.append({
			"profile": profile_id,
			"image": image_name,
			"height_range_m": float(metrics["height_range_m"]),
			"relief_p05_p95_m": float(metrics["relief_p05_p95_m"]),
			"mean_abs_slope_deg": float(metrics["mean_abs_slope_deg"]),
			"mean_local_relief_m": float(metrics["mean_local_relief_m"]),
			"kernel_relief_mean_abs_m": _kernel_relief_mean_abs(world, center, span_m),
			"seam_max_delta_m": float(seam["max_delta_m"]),
			"native_prepared_grid_enabled": bool(world.landform_profile_report().get("native_prepared_grid_enabled", false)),
		})
	return {
		"label": str(site["label"]),
		"region": "%d,%d" % [(site["region"] as Vector2i).x, (site["region"] as Vector2i).y],
		"center_m": [center.x, center.y],
		"primary_family": str(site["primary_family"]),
		"secondary_family": str(site["secondary_family"]),
		"profiles": profile_reports,
	}


func _sample_grid(world: RefCounted, center: Vector2, span_m: float) -> PackedFloat32Array:
	var step_m: float = span_m / float(GRID_SIZE - 1)
	return world.sample_height_grid(center.x - span_m * 0.5, center.y - span_m * 0.5, step_m, GRID_SIZE, GRID_SIZE)


func _validate_profile_effects(reports: Array[Dictionary], errors: Array[String]) -> void:
	if reports.is_empty():
		errors.append("profile_report_empty")
		return
	var strong_improved := false
	var compressed_changed := false
	for report in reports:
		var by_profile: Dictionary = {}
		for profile_value in report.get("profiles", []) as Array:
			var item: Dictionary = profile_value as Dictionary
			by_profile[str(item["profile"])] = item
			if float(item.get("seam_max_delta_m", 1.0)) > 0.01:
				errors.append("%s_%s_seam:%.6f" % [str(report["label"]), str(item["profile"]), float(item["seam_max_delta_m"])])
		if not (by_profile.has(TerrainLandformProfileScript.BALANCED_CURRENT) and by_profile.has(TerrainLandformProfileScript.STRONG_MOUNTAINS) and by_profile.has(TerrainLandformProfileScript.COMPRESSED_SCALE)):
			errors.append("%s_missing_profiles" % str(report["label"]))
			continue
		var balanced: Dictionary = by_profile[TerrainLandformProfileScript.BALANCED_CURRENT] as Dictionary
		var strong: Dictionary = by_profile[TerrainLandformProfileScript.STRONG_MOUNTAINS] as Dictionary
		var compressed: Dictionary = by_profile[TerrainLandformProfileScript.COMPRESSED_SCALE] as Dictionary
		if float(strong["relief_p05_p95_m"]) >= float(balanced["relief_p05_p95_m"]) * 1.03:
			strong_improved = true
		if absf(float(compressed["mean_local_relief_m"]) - float(balanced["mean_local_relief_m"])) >= 1.0:
			compressed_changed = true
		if not bool(strong.get("native_prepared_grid_enabled", false)):
			errors.append("strong_profile_native_disabled")
		if not bool(compressed.get("native_prepared_grid_enabled", false)):
			errors.append("compressed_profile_native_disabled")
	if not strong_improved:
		errors.append("strong_mountains_no_relief_increase")
	if not compressed_changed:
		errors.append("compressed_scale_no_local_change")


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
			local_relief_total += max(left, right, north, south) - min(left, right, north, south)
			count += 1
	return {
		"height_range_m": max_height - min_height,
		"relief_p05_p95_m": p95 - p05,
		"mean_abs_slope_deg": slope_total / max(1, count),
		"mean_local_relief_m": local_relief_total / max(1, count),
	}


func _kernel_relief_mean_abs(world: RefCounted, center: Vector2, span_m: float) -> float:
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(-0.25, 0.0), Vector2(0.25, 0.0), Vector2(0.0, -0.25), Vector2(0.0, 0.25)]
	var total := 0.0
	for offset in offsets:
		var point: Vector2 = center + offset * span_m
		var layers: Dictionary = world.provider.sample_layers(point.x, point.y, world.seed, world.region_size_m)
		total += absf(float(layers.get("relief", 0.0)))
	return total / float(offsets.size())


func _seam_report(world: RefCounted, center: Vector2, span_m: float) -> Dictionary:
	var step_m: float = span_m / float(GRID_SIZE - 1)
	var left_origin := Vector2(center.x - span_m, center.y - span_m * 0.5)
	var right_origin := Vector2(center.x, center.y - span_m * 0.5)
	var bottom_origin := Vector2(center.x - span_m * 0.5, center.y - span_m)
	var top_origin := Vector2(center.x - span_m * 0.5, center.y)
	var left_grid: PackedFloat32Array = world.sample_height_grid(left_origin.x, left_origin.y, step_m, GRID_SIZE, GRID_SIZE)
	var right_grid: PackedFloat32Array = world.sample_height_grid(right_origin.x, right_origin.y, step_m, GRID_SIZE, GRID_SIZE)
	var bottom_grid: PackedFloat32Array = world.sample_height_grid(bottom_origin.x, bottom_origin.y, step_m, GRID_SIZE, GRID_SIZE)
	var top_grid: PackedFloat32Array = world.sample_height_grid(top_origin.x, top_origin.y, step_m, GRID_SIZE, GRID_SIZE)
	if left_grid.size() != GRID_SIZE * GRID_SIZE or right_grid.size() != GRID_SIZE * GRID_SIZE or bottom_grid.size() != GRID_SIZE * GRID_SIZE or top_grid.size() != GRID_SIZE * GRID_SIZE:
		return {"max_delta_m": INF}
	var max_delta := 0.0
	for index in range(GRID_SIZE):
		var x_delta: float = absf(float(left_grid[index * GRID_SIZE + GRID_SIZE - 1]) - float(right_grid[index * GRID_SIZE]))
		var z_delta: float = absf(float(bottom_grid[(GRID_SIZE - 1) * GRID_SIZE + index]) - float(top_grid[index]))
		max_delta = max(max_delta, max(x_delta, z_delta))
	return {"max_delta_m": max_delta}


func _height_image(height: PackedFloat32Array, metrics: Dictionary) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	var min_height: float = float(metrics["height_range_m"])
	var max_height := -INF
	min_height = INF
	for value in height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var denom: float = max(0.0001, max_height - min_height)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var normalized: float = clampf((float(height[y * GRID_SIZE + x]) - min_height) / denom, 0.0, 1.0)
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
		errors.append("contact_sheet_save:%d" % int(save_result))


func _save_report(path: String, reports: Array[Dictionary], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open:%s" % path)
		return
	file.store_string(JSON.stringify({
		"schema": "worldgen9.landform_profile_report.v1",
		"seed": 1337,
		"grid_size": GRID_SIZE,
		"site_count": reports.size(),
		"profile_ids": TerrainLandformProfileScript.profile_ids(),
		"sites": reports,
	}, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-landform-profile] status=fail errors=%d" % errors.size())
