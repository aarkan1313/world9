extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")

const FLOAT_EPSILON := 0.000001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var priority_report: Dictionary = _read_json(TerrainSettingsScript.streamer_reference_path())
	var fifo_report: Dictionary = _read_json(TerrainSettingsScript.streamer_fifo_reference_path())
	if priority_report.is_empty() or fifo_report.is_empty():
		return 1

	_check_reference("priority_cancel", priority_report, errors)
	_check_reference("fifo", fifo_report, errors)
	_check_invalid_settings(errors)
	_check_directional_priority(errors)
	_check_directional_simulate(errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streamer-reference] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-streamer-reference] status=pass policies=2 active=%d priority_mean_ring=%.2f fifo_mean_ring=%.2f" % [
		int(priority_report["settings"]["expected_active_count"]),
		float(priority_report["summary"]["mean_built_ring"]),
		float(fifo_report["summary"]["mean_built_ring"]),
	])
	return 0


func _check_directional_priority(errors: Array[String]) -> void:
	var streamer: RefCounted = TerrainStreamerScript.new()
	streamer.setup({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 2,
		"build_budget_per_frame": 4,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	streamer.set_priority_direction(Vector2(1.0, 0.0))
	var step: Dictionary = streamer.update_viewer(Vector2.ZERO)
	var build_now: Array = step.get("build_now", []) as Array
	if build_now.size() < 4:
		errors.append("directional_priority_build_count:%d" % build_now.size())
		return
	var first_ahead: Array = build_now[1] as Array
	if int(first_ahead[0]) <= 0:
		errors.append("directional_priority_first_ahead:%s build_now:%s" % [str(first_ahead), str(build_now)])
	var second_ahead: Array = build_now[2] as Array
	if int(second_ahead[0]) <= 0:
		errors.append("directional_priority_second_ahead:%s build_now:%s" % [str(second_ahead), str(build_now)])


func _check_invalid_settings(errors: Array[String]) -> void:
	var streamer: RefCounted = TerrainStreamerScript.new()
	var ok: bool = streamer.setup({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 2,
		"build_budget_per_frame": 4,
	})
	if ok:
		errors.append("invalid_settings_setup_passed")
	if (streamer.errors as Array).is_empty():
		errors.append("invalid_settings_no_errors")
	var simulated: Dictionary = TerrainStreamerScript.simulate(PackedVector2Array([Vector2.ZERO]), {
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 2,
		"build_budget_per_frame": 4,
	})
	if simulated.get("status", "pass") != "fail":
		errors.append("invalid_settings_simulate_passed:%s" % str(simulated))


func _check_directional_simulate(errors: Array[String]) -> void:
	var settings := {
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 2,
		"build_budget_per_frame": 4,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
		"priority_direction": [1.0, 0.0],
	}
	var report: Dictionary = TerrainStreamerScript.simulate(PackedVector2Array([Vector2.ZERO]), settings)
	var steps: Array = report.get("steps", []) as Array
	if steps.is_empty():
		errors.append("directional_simulate_no_steps:%s" % str(report))
		return
	var first_step: Dictionary = steps[0] as Dictionary
	var build_now: Array = first_step.get("build_now", []) as Array
	if build_now.size() < 4:
		errors.append("directional_simulate_build_count:%d" % build_now.size())
		return
	var first_ahead: Array = build_now[1] as Array
	var second_ahead: Array = build_now[2] as Array
	if int(first_ahead[0]) <= 0 or int(second_ahead[0]) <= 0:
		errors.append("directional_simulate_not_ahead:%s" % str(build_now))


func _check_reference(label: String, expected: Dictionary, errors: Array[String]) -> void:
	var path: PackedVector2Array = TerrainStreamerScript.path_from_reference(expected)
	var actual: Dictionary = TerrainStreamerScript.simulate(path, expected["settings"] as Dictionary)
	_compare_value(label, expected, actual, errors)
	var stateful: Dictionary = _simulate_stateful(path, expected["settings"] as Dictionary)
	_compare_value("%s.stateful" % label, expected, stateful, errors)


func _simulate_stateful(path: PackedVector2Array, settings: Dictionary) -> Dictionary:
	var streamer: RefCounted = TerrainStreamerScript.new()
	streamer.setup(settings)
	var steps: Array[Dictionary] = []
	var max_active_count := 0
	var total_created := 0
	var total_retired := 0
	var total_lod_changed := 0
	var build_ring_values: Array[int] = []
	for point in path:
		var step: Dictionary = streamer.update_viewer(point)
		steps.append(step)
		max_active_count = max(max_active_count, int(step["active_count"]))
		total_created += int(step["created_count"])
		total_retired += int(step["retired_count"])
		total_lod_changed += int(step["lod_changed_count"])
		for ring_value in step["build_now_rings"] as Array:
			var ring: int = int(ring_value)
			if ring >= 0:
				build_ring_values.append(ring)
	var errors: Array[String] = []
	for step in steps:
		if int(step["active_count"]) != int(step["expected_active_count"]):
			errors.append("active_count_not_expected_at_step_%d" % int(step["step"]))
	return {
		"version": 1,
		"schema": "worldgen9.streamer_reference.v1",
		"settings": {
			"chunk_size_m": float(settings["chunk_size_m"]),
			"visible_radius_chunks": int(settings["visible_radius_chunks"]),
			"max_lod": int(settings["max_lod"]),
			"build_budget_per_frame": int(settings["build_budget_per_frame"]),
			"queue_policy": str(settings["queue_policy"]),
			"expected_active_count": int(settings["expected_active_count"]),
		},
		"summary": {
			"steps": steps.size(),
			"max_active_count": max_active_count,
			"total_created": total_created,
			"total_retired": total_retired,
			"total_lod_changed": total_lod_changed,
			"final_queued_build_count": int(streamer.queued_builds.size()),
			"built_count": build_ring_values.size(),
			"mean_built_ring": _mean_int(build_ring_values),
			"max_built_ring": _max_int(build_ring_values),
		},
		"steps": _strip_runtime_step_fields(steps),
		"errors": errors,
		"status": "pass" if errors.is_empty() else "fail",
	}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON: %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open JSON: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON is not an object: %s" % path)
		return {}
	return parsed as Dictionary


func _compare_value(path: String, expected: Variant, actual: Variant, errors: Array[String]) -> void:
	if _is_number(expected) and _is_number(actual):
		if abs(float(expected) - float(actual)) > FLOAT_EPSILON:
			errors.append("%s expected %s got %s" % [path, str(expected), str(actual)])
		return
	if typeof(expected) != typeof(actual):
		errors.append("%s type expected %s got %s" % [path, type_string(typeof(expected)), type_string(typeof(actual))])
		return
	if typeof(expected) == TYPE_DICTIONARY:
		_compare_dictionary(path, expected as Dictionary, actual as Dictionary, errors)
		return
	if typeof(expected) == TYPE_ARRAY:
		_compare_array(path, expected as Array, actual as Array, errors)
		return
	if expected != actual:
		errors.append("%s expected %s got %s" % [path, str(expected), str(actual)])


func _compare_dictionary(path: String, expected: Dictionary, actual: Dictionary, errors: Array[String]) -> void:
	var expected_keys: Array = expected.keys()
	expected_keys.sort()
	var actual_keys: Array = actual.keys()
	actual_keys.sort()
	if expected_keys != actual_keys:
		errors.append("%s keys expected %s got %s" % [path, str(expected_keys), str(actual_keys)])
		return
	for key_value in expected_keys:
		var key: String = str(key_value)
		_compare_value("%s.%s" % [path, key], expected[key], actual[key], errors)
		if errors.size() > 40:
			return


func _compare_array(path: String, expected: Array, actual: Array, errors: Array[String]) -> void:
	if expected.size() != actual.size():
		errors.append("%s size expected %d got %d" % [path, expected.size(), actual.size()])
		return
	for index in range(expected.size()):
		_compare_value("%s[%d]" % [path, index], expected[index], actual[index], errors)
		if errors.size() > 40:
			return


func _is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


func _strip_runtime_step_fields(steps: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step in steps:
		var copy: Dictionary = step.duplicate(true)
		copy.erase("status")
		result.append(copy)
	return result


func _mean_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / float(values.size())


func _max_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var result: int = values[0]
	for value in values:
		result = max(result, value)
	return result
