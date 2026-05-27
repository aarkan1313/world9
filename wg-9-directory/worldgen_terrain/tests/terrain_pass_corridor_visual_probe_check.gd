extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_pass_corridor"
const GRID_SIZE := 97


func _init() -> void:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_finish(errors, {})
		return

	var site: Dictionary = _select_corridor_site(world)
	if site.is_empty():
		errors.append("corridor_site_not_found")
		_finish(errors, {})
		return

	var center: Vector2 = site["mid_m"] as Vector2
	var width_m: float = float(site["width_m"])
	var span_m: float = clampf(width_m * 6.0, world.region_size_m * 0.18, world.region_size_m * 0.55)
	var neutral_height: PackedFloat32Array = _sample_grid(world, center, span_m)
	var strength_grid: PackedFloat32Array = _sample_strength_grid(world, center, span_m)
	var neutral_mid_height: float = world.sample_height(center.x, center.y)
	var neutral_off_height: float = world.sample_height(center.x + span_m * 0.45, center.y + span_m * 0.45)

	var profile := {
		"id": "pass_corridor_visual_probe",
		"settings": {
			"macro_relief_scale": 1.0,
			"kernel_relief_strength": 1.0,
			"mountain_boost": 1.0,
			"regional_scale_multiplier": 1.0,
			"valley_bias_strength": 1.0,
			"pass_corridor_strength": 1.0,
		},
	}
	if not world.apply_landform_profile(profile):
		errors.append("pass_profile_apply_failed")
		_finish(errors, {})
		return
	var shaped_height: PackedFloat32Array = _sample_grid(world, center, span_m)
	var shaped_mid_height: float = world.sample_height(center.x, center.y)
	var shaped_off_height: float = world.sample_height(center.x + span_m * 0.45, center.y + span_m * 0.45)

	var metrics: Dictionary = _cut_metrics(neutral_height, shaped_height, strength_grid)
	var mid_cut_m: float = neutral_mid_height - shaped_mid_height
	var off_delta_m: float = absf(neutral_off_height - shaped_off_height)
	if neutral_height.size() != GRID_SIZE * GRID_SIZE or shaped_height.size() != GRID_SIZE * GRID_SIZE:
		errors.append("grid_size:%d/%d" % [neutral_height.size(), shaped_height.size()])
	if mid_cut_m < 8.0:
		errors.append("mid_cut_too_weak:%.3f" % mid_cut_m)
	if float(metrics.get("corridor_mean_cut_m", 0.0)) < 4.0:
		errors.append("corridor_mean_cut_too_weak:%.3f" % float(metrics.get("corridor_mean_cut_m", 0.0)))
	if off_delta_m > 0.0001:
		errors.append("off_corridor_anchor_changed:%.6f" % off_delta_m)
	var profile_report: Dictionary = world.landform_profile_report()
	if bool(profile_report.get("native_prepared_grid_enabled", true)):
		errors.append("pass_profile_native_should_be_disabled:%s" % str(profile_report))

	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var contact_sheet_path: String = out_dir.path_join("pass_corridor_visual_probe_contact_sheet.png")
	var report_path: String = out_dir.path_join("pass_corridor_visual_probe_report.json")
	_save_contact_sheet(neutral_height, shaped_height, strength_grid, contact_sheet_path, errors)
	var report := {
		"schema": "worldgen9.pass_corridor_visual_probe.v1",
		"seed": 1337,
		"grid_size": GRID_SIZE,
		"center_m": [center.x, center.y],
		"span_m": span_m,
		"site": site,
		"mid_cut_m": mid_cut_m,
		"off_corridor_anchor_delta_m": off_delta_m,
		"metrics": metrics,
		"native_prepared_grid_enabled": bool(profile_report.get("native_prepared_grid_enabled", true)),
		"contact_sheet": "pass_corridor_visual_probe_contact_sheet.png",
	}
	_save_report(report_path, report, errors)
	_finish(errors, report)


func _select_corridor_site(world: RefCounted) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for rz in range(-10, 11):
		for rx in range(-10, 11):
			var facts: Dictionary = world.pass_corridor_facts_for_region(rx, rz)
			if facts.get("status", "fail") != "pass":
				continue
			for fact_value in facts.get("facts", []) as Array:
				var fact: Dictionary = fact_value as Dictionary
				var start_values: Array = fact.get("start_m", []) as Array
				var end_values: Array = fact.get("end_m", []) as Array
				if start_values.size() < 2 or end_values.size() < 2:
					continue
				var ruggedness: float = float(fact.get("ruggedness", 0.0))
				var priority: float = float(fact.get("priority", 0.0))
				var start := Vector2(float(start_values[0]), float(start_values[1]))
				var end := Vector2(float(end_values[0]), float(end_values[1]))
				for sample_index in range(1, 10):
					var t: float = float(sample_index) / 10.0
					var point: Vector2 = start.lerp(end, t)
					var hint: Dictionary = world.sample_pass_corridor_hint(point.x, point.y)
					var strength: float = float(hint.get("corridor_strength", 0.0))
					var neutral_height: float = world.sample_height(point.x, point.y)
					var high_factor: float = _smoothstep_unit((neutral_height + 90.0) / 560.0)
					var score: float = strength * strength * high_factor * 8.0 + ruggedness * 2.0 + priority
					if score > best_score:
						best_score = score
						best = {
							"id": str(fact.get("id", "")),
							"kind": str(fact.get("kind", "")),
							"region": fact.get("region", []),
							"families": fact.get("families", []),
							"start_m": start_values,
							"end_m": end_values,
							"mid_m": point,
							"width_m": float(fact.get("width_m", 0.0)),
							"priority": priority,
							"ruggedness": ruggedness,
							"mid_strength": strength,
							"neutral_height_m": neutral_height,
							"expected_height_factor": high_factor,
						}
	return best


func _smoothstep_unit(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _sample_grid(world: RefCounted, center: Vector2, span_m: float) -> PackedFloat32Array:
	var step_m: float = span_m / float(GRID_SIZE - 1)
	return world.sample_height_grid(center.x - span_m * 0.5, center.y - span_m * 0.5, step_m, GRID_SIZE, GRID_SIZE)


func _sample_strength_grid(world: RefCounted, center: Vector2, span_m: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(GRID_SIZE * GRID_SIZE)
	var step_m: float = span_m / float(GRID_SIZE - 1)
	var origin := Vector2(center.x - span_m * 0.5, center.y - span_m * 0.5)
	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var world_x: float = origin.x + float(x) * step_m
			var world_z: float = origin.y + float(z) * step_m
			values[z * GRID_SIZE + x] = float(world.sample_pass_corridor_hint(world_x, world_z).get("corridor_strength", 0.0))
	return values


func _cut_metrics(neutral_height: PackedFloat32Array, shaped_height: PackedFloat32Array, strength_grid: PackedFloat32Array) -> Dictionary:
	var max_cut := 0.0
	var corridor_cut_total := 0.0
	var corridor_count := 0
	var outside_max_delta := 0.0
	for index in range(min(neutral_height.size(), shaped_height.size(), strength_grid.size())):
		var cut_m: float = float(neutral_height[index]) - float(shaped_height[index])
		var strength: float = float(strength_grid[index])
		max_cut = max(max_cut, cut_m)
		if strength >= 0.45:
			corridor_cut_total += max(0.0, cut_m)
			corridor_count += 1
		elif strength <= 0.001:
			outside_max_delta = max(outside_max_delta, absf(cut_m))
	return {
		"max_cut_m": max_cut,
		"corridor_mean_cut_m": corridor_cut_total / float(max(1, corridor_count)),
		"corridor_sample_count": corridor_count,
		"outside_max_delta_m": outside_max_delta,
	}


func _save_contact_sheet(
	neutral_height: PackedFloat32Array,
	shaped_height: PackedFloat32Array,
	strength_grid: PackedFloat32Array,
	path: String,
	errors: Array[String]
) -> void:
	var sheet := Image.create(GRID_SIZE * 4, GRID_SIZE, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	var neutral_image: Image = _height_image(neutral_height, neutral_height, shaped_height)
	var shaped_image: Image = _height_image(shaped_height, neutral_height, shaped_height)
	var cut_image: Image = _cut_image(neutral_height, shaped_height)
	var strength_image: Image = _strength_image(strength_grid)
	sheet.blit_rect(neutral_image, Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), Vector2i.ZERO)
	sheet.blit_rect(shaped_image, Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), Vector2i(GRID_SIZE, 0))
	sheet.blit_rect(cut_image, Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), Vector2i(GRID_SIZE * 2, 0))
	sheet.blit_rect(strength_image, Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), Vector2i(GRID_SIZE * 3, 0))
	var result: Error = sheet.save_png(path)
	if result != OK:
		errors.append("contact_sheet_save:%d" % int(result))


func _height_image(height: PackedFloat32Array, neutral_height: PackedFloat32Array, shaped_height: PackedFloat32Array) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	var min_height := INF
	var max_height := -INF
	for value in neutral_height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	for value in shaped_height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var denom: float = max(0.0001, max_height - min_height)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var value: float = float(height[y * GRID_SIZE + x])
			var n: float = clampf((value - min_height) / denom, 0.0, 1.0)
			image.set_pixel(x, y, Color(n, n, n))
	return image


func _cut_image(neutral_height: PackedFloat32Array, shaped_height: PackedFloat32Array) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	var max_cut := 0.0001
	for index in range(min(neutral_height.size(), shaped_height.size())):
		max_cut = max(max_cut, float(neutral_height[index]) - float(shaped_height[index]))
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var index: int = y * GRID_SIZE + x
			var cut_n: float = clampf((float(neutral_height[index]) - float(shaped_height[index])) / max_cut, 0.0, 1.0)
			image.set_pixel(x, y, Color(cut_n, cut_n * 0.32, 0.05))
	return image


func _strength_image(strength_grid: PackedFloat32Array) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var strength: float = clampf(float(strength_grid[y * GRID_SIZE + x]), 0.0, 1.0)
			image.set_pixel(x, y, Color(0.04, strength, strength * 0.35))
	return image


func _save_report(path: String, report: Dictionary, errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open:%s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))


func _finish(errors: Array[String], report: Dictionary) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-pass-corridor-visual-probe] status=fail errors=%d report=%s" % [errors.size(), str(report)])
		quit(1)
		return
	print("[wg9-pass-corridor-visual-probe] status=pass report=%s" % str(report))
	quit(0)
