extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainHashScript := preload("res://worldgen_terrain/height/terrain_hash.gd")

const FLOAT_EPSILON := 0.000000001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var reference_path := TerrainSettingsScript.hash_reference_path()
	if not FileAccess.file_exists(reference_path):
		push_error("Missing hash reference: %s" % reference_path)
		return 1

	var file := FileAccess.open(reference_path, FileAccess.READ)
	if file == null:
		push_error("Could not open hash reference: %s" % reference_path)
		return 1

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Hash reference is not a JSON object: %s" % reference_path)
		return 1

	var errors: Array[String] = []
	_check_stable_hash_cases(parsed, errors)
	_check_hash_grid_cases(parsed, errors)
	_check_noise_cases(parsed, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-hash-parity] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-hash-parity] status=pass stable=%d grid=%d noise=%d" % [
		(parsed.get("stable_hash_cases", []) as Array).size(),
		(parsed.get("hash_grid_cases", []) as Array).size(),
		(parsed.get("noise_cases", []) as Array).size(),
	])
	return 0


func _check_stable_hash_cases(reference: Dictionary, errors: Array[String]) -> void:
	for index in range((reference.get("stable_hash_cases", []) as Array).size()):
		var test_case := (reference["stable_hash_cases"] as Array)[index] as Dictionary
		var actual := TerrainHashScript.stable_hash(test_case["values"] as Array)
		var expected := int(test_case["hash_u32"])
		if actual != expected:
			errors.append("stable_hash[%d] expected %d got %d" % [index, expected, actual])


func _check_hash_grid_cases(reference: Dictionary, errors: Array[String]) -> void:
	for index in range((reference.get("hash_grid_cases", []) as Array).size()):
		var test_case := (reference["hash_grid_cases"] as Array)[index] as Dictionary
		var actual := TerrainHashScript.hash_grid(
			int(test_case["ix"]),
			int(test_case["iz"]),
			int(test_case["seed"]),
			int(test_case["salt"])
		)
		var expected := float(test_case["value_0_to_1"])
		if abs(actual - expected) > FLOAT_EPSILON:
			errors.append("hash_grid[%d] expected %.12f got %.12f" % [index, expected, actual])


func _check_noise_cases(reference: Dictionary, errors: Array[String]) -> void:
	for index in range((reference.get("noise_cases", []) as Array).size()):
		var test_case := (reference["noise_cases"] as Array)[index] as Dictionary
		var x := float(test_case["x"])
		var z := float(test_case["z"])
		var scale_m := float(test_case["scale_m"])
		var reference_seed := int(test_case["seed"])
		var salt := int(test_case["salt"])
		var actual_value := TerrainHashScript.value_noise(x, z, scale_m, reference_seed, salt)
		var expected_value := float(test_case["value_noise"])
		if abs(actual_value - expected_value) > FLOAT_EPSILON:
			errors.append("value_noise[%d] expected %.12f got %.12f" % [index, expected_value, actual_value])

		var actual_fbm := TerrainHashScript.fbm(x, z, scale_m, reference_seed, 4)
		var expected_fbm := float(test_case["fbm_4"])
		if abs(actual_fbm - expected_fbm) > FLOAT_EPSILON:
			errors.append("fbm[%d] expected %.12f got %.12f" % [index, expected_fbm, actual_fbm])
