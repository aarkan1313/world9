extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_finish(errors, {})
		return

	var regions: Array[Vector2i] = _select_regions(world)
	var fact_ids: Dictionary = {}
	var rugged_count := 0
	var max_mid_strength := 0.0
	var best_mid := Vector2.ZERO
	for region in regions:
		var facts: Dictionary = world.pass_corridor_facts_for_region(region.x, region.y)
		var repeat: Dictionary = world.pass_corridor_facts_for_region(region.x, region.y)
		if JSON.stringify(facts) != JSON.stringify(repeat):
			errors.append("nondeterministic_region:%d,%d" % [region.x, region.y])
		_validate_fact_set(facts, region, errors)
		for fact_value in facts.get("facts", []) as Array:
			var fact: Dictionary = fact_value as Dictionary
			fact_ids[str(fact.get("id", ""))] = true
			if float(fact.get("ruggedness", 0.0)) >= 0.55:
				rugged_count += 1
			var start_values: Array = fact["start_m"] as Array
			var end_values: Array = fact["end_m"] as Array
			var mid := Vector2(
				(float(start_values[0]) + float(end_values[0])) * 0.5,
				(float(start_values[1]) + float(end_values[1])) * 0.5
			)
			var hint: Dictionary = world.sample_pass_corridor_hint(mid.x, mid.y)
			if hint.get("status", "fail") != "pass":
				errors.append("hint_failed:%s" % str(hint))
			var mid_strength: float = float(hint.get("corridor_strength", 0.0))
			if mid_strength > max_mid_strength:
				max_mid_strength = mid_strength
				best_mid = mid
			var sample: Dictionary = world.sample(mid.x, mid.y)
			if absf(float(sample.get("pass_corridor_hint", 0.0)) - float(hint.get("corridor_strength", 0.0))) > 0.0001:
				errors.append("sample_hint_mismatch:%s:%s" % [str(sample), str(hint)])

	var neutral_probe_height: float = world.sample_height(8192.0, -4096.0)
	var neutral_corridor_height: float = world.sample_height(best_mid.x, best_mid.y)
	var custom_profile := {
		"id": "pass_shaping_probe",
		"settings": {
			"macro_relief_scale": 1.0,
			"kernel_relief_strength": 1.0,
			"mountain_boost": 1.0,
			"regional_scale_multiplier": 1.0,
			"valley_bias_strength": 1.0,
			"pass_corridor_strength": 1.0,
		},
	}
	if not world.apply_landform_profile(custom_profile):
		errors.append("custom_profile_apply_failed")
	var shaped_probe_height: float = world.sample_height(8192.0, -4096.0)
	var shaped_corridor_height: float = world.sample_height(best_mid.x, best_mid.y)
	var neutral_probe_delta: float = absf(neutral_probe_height - shaped_probe_height)
	var corridor_delta: float = neutral_corridor_height - shaped_corridor_height
	if neutral_probe_delta > 0.0001:
		errors.append("pass_shape_changed_off_corridor_probe:%.6f" % neutral_probe_delta)
	if corridor_delta < 8.0:
		errors.append("pass_shape_too_weak:%.6f neutral:%.3f shaped:%.3f mid:%s" % [
			corridor_delta,
			neutral_corridor_height,
			shaped_corridor_height,
			str(best_mid),
		])
	var profile_report: Dictionary = world.landform_profile_report()
	if not bool(profile_report.get("native_prepared_grid_enabled", false)):
		errors.append("pass_shape_native_should_be_enabled:%s" % str(profile_report))
	var shaped_sample: Dictionary = world.sample(best_mid.x, best_mid.y)
	if float(shaped_sample.get("pass_corridor_adjust_m", 0.0)) >= -0.0001:
		errors.append("pass_adjust_missing:%s" % str(shaped_sample))
	_check_native_pass_corridor_grid(world, best_mid, shaped_corridor_height, errors)

	if fact_ids.size() < regions.size():
		errors.append("duplicate_fact_ids:%d regions:%d" % [fact_ids.size(), regions.size()])
	if rugged_count <= 0:
		errors.append("no_rugged_pass_candidates")
	if max_mid_strength < 0.95:
		errors.append("low_mid_corridor_strength:%.6f" % max_mid_strength)

	_finish(errors, {
		"schema": "worldgen9.pass_corridor_world_facts_check.v1",
		"regions": regions.size(),
		"unique_fact_ids": fact_ids.size(),
		"rugged_candidates": rugged_count,
		"max_mid_corridor_strength": max_mid_strength,
		"best_mid": [best_mid.x, best_mid.y],
		"corridor_height_delta_m": corridor_delta,
		"affects_height": true,
		"native_prepared_grid_enabled": bool(profile_report.get("native_prepared_grid_enabled", false)),
	})


func _check_native_pass_corridor_grid(world: RefCounted, best_mid: Vector2, shaped_corridor_height: float, errors: Array[String]) -> void:
	var provider: RefCounted = world.provider
	if provider == null:
		errors.append("native_pass_provider_missing")
		return
	if not provider.has_method("sample_height_grid_native_prepared"):
		errors.append("native_pass_method_missing")
		return
	var native: Dictionary = provider.call(
		"sample_height_grid_native_prepared",
		best_mid.x,
		best_mid.y,
		32.0,
		1,
		1,
		world.seed,
		world.region_size_m
	) as Dictionary
	if native.get("status", "fail") != "pass":
		errors.append("native_pass_grid_failed:%s" % str(native))
		return
	var values: PackedFloat32Array = native.get("values", PackedFloat32Array()) as PackedFloat32Array
	if values.size() != 1:
		errors.append("native_pass_grid_size:%d" % values.size())
		return
	var delta: float = absf(float(values[0]) - shaped_corridor_height)
	if delta > 0.05:
		errors.append("native_pass_grid_delta:%.6f native:%.3f scalar:%.3f" % [delta, values[0], shaped_corridor_height])


func _select_regions(world: RefCounted) -> Array[Vector2i]:
	var rugged: Array[Vector2i] = []
	var other: Array[Vector2i] = []
	for rz in range(-8, 9):
		for rx in range(-8, 9):
			var facts: Dictionary = world.pass_corridor_facts_for_region(rx, rz)
			if facts.get("status", "fail") != "pass":
				continue
			var ruggedness: float = float(facts.get("ruggedness", 0.0))
			if ruggedness >= 0.55:
				rugged.append(Vector2i(rx, rz))
			else:
				other.append(Vector2i(rx, rz))
	var selected: Array[Vector2i] = []
	for region in rugged:
		if selected.size() >= 3:
			break
		selected.append(region)
	for region in other:
		if selected.size() >= 6:
			break
		selected.append(region)
	return selected


func _validate_fact_set(facts: Dictionary, region: Vector2i, errors: Array[String]) -> void:
	if facts.get("status", "fail") != "pass":
		errors.append("facts_failed:%d,%d:%s" % [region.x, region.y, str(facts)])
		return
	if facts.get("schema", "") != "worldgen9.terrain_world_facts.v1":
		errors.append("schema:%s" % str(facts.get("schema", "")))
	if bool(facts.get("affects_height", true)):
		errors.append("fact_set_affects_height")
	var items: Array = facts.get("facts", []) as Array
	if items.is_empty():
		errors.append("facts_empty:%d,%d" % [region.x, region.y])
	for fact_value in items:
		var fact: Dictionary = fact_value as Dictionary
		if bool(fact.get("affects_height", true)):
			errors.append("fact_affects_height:%s" % str(fact))
		var width_m: float = float(fact.get("width_m", 0.0))
		var priority: float = float(fact.get("priority", 0.0))
		var ruggedness: float = float(fact.get("ruggedness", -1.0))
		if not is_finite(width_m) or width_m <= 0.0:
			errors.append("invalid_width:%s" % str(fact))
		if not is_finite(priority) or priority < 0.0 or priority > 1.0:
			errors.append("invalid_priority:%s" % str(fact))
		if not is_finite(ruggedness) or ruggedness < 0.0 or ruggedness > 1.0:
			errors.append("invalid_ruggedness:%s" % str(fact))
		_validate_point_array("start", fact.get("start_m", []), errors)
		_validate_point_array("end", fact.get("end_m", []), errors)


func _validate_point_array(label: String, value: Variant, errors: Array[String]) -> void:
	var point: Array = value as Array
	if point.size() != 2:
		errors.append("%s_point_size:%s" % [label, str(value)])
		return
	if not is_finite(float(point[0])) or not is_finite(float(point[1])):
		errors.append("%s_point_nonfinite:%s" % [label, str(value)])


func _finish(errors: Array[String], report: Dictionary) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-pass-corridor-world-facts] status=fail errors=%d report=%s" % [errors.size(), str(report)])
		quit(1)
		return
	print("[wg9-pass-corridor-world-facts] status=pass report=%s" % str(report))
	quit(0)
