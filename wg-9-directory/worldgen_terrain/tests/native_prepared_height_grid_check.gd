extends SceneTree

const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const ORIGIN_X := 2048.0
const ORIGIN_Z := 4096.0
const STEP_M := 64.0
const COUNT := 33
const EPSILON := 0.075


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_report_and_quit(errors)
		return
	var provider: RefCounted = world.provider
	provider.use_native_prepared_height_grid = false
	var gdscript_values: PackedFloat32Array = provider.sample_height_grid(
		ORIGIN_X,
		ORIGIN_Z,
		STEP_M,
		COUNT,
		COUNT,
		world.seed,
		TerrainSettingsScript.REGION_SIZE_M
	)
	var native: Dictionary = provider.sample_height_grid_native_prepared(
		ORIGIN_X,
		ORIGIN_Z,
		STEP_M,
		COUNT,
		COUNT,
		world.seed,
		TerrainSettingsScript.REGION_SIZE_M
	)
	if native.get("status", "fail") != "pass":
		errors.append("native_height_grid_failed:%s" % str(native))
		_report_and_quit(errors)
		return
	var native_values: PackedFloat32Array = native["values"] as PackedFloat32Array
	if native_values.size() != gdscript_values.size():
		errors.append("size_mismatch:%d:%d" % [native_values.size(), gdscript_values.size()])
		_report_and_quit(errors)
		return
	var max_delta := 0.0
	var total_delta := 0.0
	for index in range(native_values.size()):
		var delta: float = abs(float(native_values[index]) - float(gdscript_values[index]))
		max_delta = max(max_delta, delta)
		total_delta += delta
	if max_delta > EPSILON:
		errors.append("max_delta:%.6f epsilon:%.6f" % [max_delta, EPSILON])
	_check_provider_prepared_validation(provider, errors)
	_report_and_quit(errors, max_delta, total_delta / float(max(1, native_values.size())))


func _check_provider_prepared_validation(provider: RefCounted, errors: Array[String]) -> void:
	var invalid_step: Dictionary = provider.native_prepared_height_grid_request(
		ORIGIN_X,
		ORIGIN_Z,
		0.0,
		COUNT,
		COUNT,
		1337,
		TerrainSettingsScript.REGION_SIZE_M
	)
	if invalid_step.get("status", "pass") != "fail":
		errors.append("invalid_step_prepared_passed:%s" % str(invalid_step))
	var prepared: Dictionary = provider.native_prepared_height_grid_request(
		ORIGIN_X,
		ORIGIN_Z,
		STEP_M,
		COUNT,
		COUNT,
		1337,
		TerrainSettingsScript.REGION_SIZE_M
	)
	if prepared.get("status", "fail") != "pass":
		errors.append("valid_prepared_rejected:%s" % str(prepared))
		return
	var bad_corners: Array = (prepared["corner_entries"] as Array).duplicate(true)
	var corner: Dictionary = (bad_corners[0] as Dictionary).duplicate(true)
	var entries: Array = (corner["entries"] as Array).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["rows"] = 4
	entry["cols"] = 4
	entry["values"] = PackedFloat32Array([0.0, 1.0])
	entries[0] = entry
	corner["entries"] = entries
	bad_corners[0] = corner
	var validation: Dictionary = provider._validate_native_prepared_corner_entries(bad_corners)
	if validation.get("status", "pass") != "fail":
		errors.append("invalid_prepared_entries_passed:%s" % str(validation))


func _report_and_quit(errors: Array[String], max_delta: float = 0.0, mean_delta: float = 0.0) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-native-height-grid] status=fail errors=%d max_delta=%.6f mean_delta=%.6f" % [errors.size(), max_delta, mean_delta])
		quit(1)
		return
	print("[wg9-native-height-grid] status=pass values=%d max_delta=%.6f mean_delta=%.6f" % [
		COUNT * COUNT,
		max_delta,
		mean_delta,
	])
	quit(0)
