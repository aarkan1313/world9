extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainHeightProviderScript := preload("res://worldgen_terrain/height/terrain_height_provider.gd")

const FLOAT_EPSILON := 0.05


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var reference_path := TerrainSettingsScript.terrain_sample_reference_path()
	if not FileAccess.file_exists(reference_path):
		push_error("Missing terrain sample reference: %s" % reference_path)
		return 1
	var file := FileAccess.open(reference_path, FileAccess.READ)
	if file == null:
		push_error("Could not open terrain sample reference: %s" % reference_path)
		return 1
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Terrain sample reference is not a JSON object: %s" % reference_path)
		return 1
	var reference := parsed as Dictionary

	var pack := RuntimeKernelPackScript.new()
	if not pack.load_default():
		for error in pack.errors:
			push_error(error)
		return 1
	var provider := TerrainHeightProviderScript.new()
	provider.setup(pack)

	var reference_seed: int = int(reference["seed"])
	var region_size_m: float = float(reference["region_size_m"])
	var errors: Array[String] = []
	var samples: Array = reference.get("samples", []) as Array
	for index in range(samples.size()):
		var expected := samples[index] as Dictionary
		var actual := provider.sample(float(expected["world_x"]), float(expected["world_z"]), reference_seed, region_size_m, 32.0)
		_compare_sample(index, actual, expected, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-sample] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-terrain-sample] status=pass samples=%d epsilon=%.3f" % [samples.size(), FLOAT_EPSILON])
	return 0


func _compare_sample(index: int, actual: Dictionary, expected: Dictionary, errors: Array[String]) -> void:
	for key in expected.keys():
		if not actual.has(key):
			errors.append("sample[%d].%s missing" % [index, str(key)])
			continue
		var expected_value: Variant = expected[key]
		var actual_value: Variant = actual[key]
		match typeof(expected_value):
			TYPE_FLOAT:
				if abs(float(actual_value) - float(expected_value)) > FLOAT_EPSILON:
					errors.append("sample[%d].%s expected %.6f got %.6f" % [index, str(key), float(expected_value), float(actual_value)])
			TYPE_INT:
				if int(actual_value) != int(expected_value):
					errors.append("sample[%d].%s expected %d got %d" % [index, str(key), int(expected_value), int(actual_value)])
			TYPE_BOOL:
				if bool(actual_value) != bool(expected_value):
					errors.append("sample[%d].%s expected %s got %s" % [index, str(key), str(expected_value), str(actual_value)])
			_:
				if actual_value != expected_value:
					errors.append("sample[%d].%s expected %s got %s" % [index, str(key), str(expected_value), str(actual_value)])
