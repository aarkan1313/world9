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
			max_mid_strength = max(max_mid_strength, float(hint.get("corridor_strength", 0.0)))
			var sample: Dictionary = world.sample(mid.x, mid.y)
			if absf(float(sample.get("pass_corridor_hint", 0.0)) - float(hint.get("corridor_strength", 0.0))) > 0.0001:
				errors.append("sample_hint_mismatch:%s:%s" % [str(sample), str(hint)])

	var before_height: float = world.sample_height(8192.0, -4096.0)
	var custom_profile := {
		"id": "pass_placeholder_probe",
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
	var after_height: float = world.sample_height(8192.0, -4096.0)
	if absf(before_height - after_height) > 0.0001:
		errors.append("pass_placeholder_changed_height:%.6f" % absf(before_height - after_height))

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
		"affects_height": false,
	})


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
