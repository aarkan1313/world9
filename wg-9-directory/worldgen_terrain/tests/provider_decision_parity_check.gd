extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainProviderDecisionsScript := preload("res://worldgen_terrain/height/terrain_provider_decisions.gd")

const FLOAT_EPSILON := 0.000001
const HEIGHT_FIELDS := {
	"height_m": true,
	"macro_height_m": true,
	"kernel_relief_m": true,
	"detail_height_m": true,
	"valley_adjust_m": true,
	"region_debug_value": true,
}


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var reference_path := TerrainSettingsScript.provider_decisions_path()
	if not FileAccess.file_exists(reference_path):
		push_error("Missing provider reference: %s" % reference_path)
		return 1
	var file := FileAccess.open(reference_path, FileAccess.READ)
	if file == null:
		push_error("Could not open provider reference: %s" % reference_path)
		return 1
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Provider reference is not a JSON object: %s" % reference_path)
		return 1
	var reference := parsed as Dictionary

	var pack := RuntimeKernelPackScript.new()
	if not pack.load_default():
		for error in pack.errors:
			push_error(error)
		return 1
	var provider := TerrainProviderDecisionsScript.new()
	provider.setup(pack)
	var errors: Array[String] = []
	var reference_seed: int = int(reference["seed"])
	var region_size_m: float = float(reference["region_size_m"])
	var decisions: Array = reference.get("decisions", []) as Array
	for index in range(decisions.size()):
		var expected := decisions[index] as Dictionary
		var actual := provider.decision(float(expected["world_x"]), float(expected["world_z"]), reference_seed, region_size_m)
		_compare_value("decision[%d]" % index, actual, expected, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-provider-decisions] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-provider-decisions] status=pass decisions=%d height_fields_ignored=true" % decisions.size())
	return 0


func _compare_value(path: String, actual: Variant, expected: Variant, errors: Array[String]) -> void:
	if HEIGHT_FIELDS.has(path.get_slice(".", path.get_slice_count(".") - 1)):
		return
	if _is_height_key_path(path):
		return
	var expected_type := typeof(expected)
	if expected_type == TYPE_DICTIONARY:
		if typeof(actual) != TYPE_DICTIONARY:
			errors.append("%s type mismatch" % path)
			return
		var expected_dict := expected as Dictionary
		var actual_dict := actual as Dictionary
		for key in expected_dict.keys():
			var key_text := str(key)
			if HEIGHT_FIELDS.has(key_text):
				continue
			if not actual_dict.has(key):
				errors.append("%s.%s missing" % [path, key_text])
				continue
			_compare_value("%s.%s" % [path, key_text], actual_dict[key], expected_dict[key], errors)
	elif expected_type == TYPE_ARRAY:
		if typeof(actual) != TYPE_ARRAY:
			errors.append("%s type mismatch" % path)
			return
		var expected_array := expected as Array
		var actual_array := actual as Array
		if actual_array.size() != expected_array.size():
			errors.append("%s size expected %d got %d" % [path, expected_array.size(), actual_array.size()])
			return
		for index in range(expected_array.size()):
			_compare_value("%s[%d]" % [path, index], actual_array[index], expected_array[index], errors)
	elif expected_type == TYPE_FLOAT:
		if abs(float(actual) - float(expected)) > FLOAT_EPSILON:
			errors.append("%s expected %.9f got %.9f" % [path, float(expected), float(actual)])
	elif expected_type == TYPE_INT:
		if int(actual) != int(expected):
			errors.append("%s expected %d got %d" % [path, int(expected), int(actual)])
	else:
		if actual != expected:
			errors.append("%s expected %s got %s" % [path, str(expected), str(actual)])


func _is_height_key_path(path: String) -> bool:
	for key in HEIGHT_FIELDS.keys():
		if path.ends_with("." + str(key)):
			return true
	return false
