class_name RuntimeKernelPack
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const NpyFloat32ArrayScript := preload("res://worldgen_terrain/io/npy_float32_array.gd")

var source_path: String = ""
var data: Dictionary = {}
var kernels: Array = []
var families: Dictionary = {}
var runtime_defaults: Dictionary = {}
var errors: Array[String] = []
var _array_cache: Dictionary = {}
var _normalized_cache: Dictionary = {}
var _kernel_id_to_index: Dictionary = {}


func load_from_path(path: String) -> bool:
	source_path = path
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("missing_pack:%s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("open_failed:%s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("pack_not_json_object:%s" % path)
		return false
	data = parsed as Dictionary
	kernels = data.get("kernels", []) as Array
	families = data.get("families", {}) as Dictionary
	runtime_defaults = data.get("runtime_defaults", {}) as Dictionary
	_rebuild_kernel_index()
	_validate_metadata()
	return errors.is_empty()


func load_default() -> bool:
	return load_from_path(TerrainSettingsScript.runtime_pack_path())


func kernel_runtime_paths(kernel: Dictionary) -> Dictionary:
	var artifacts := kernel.get("artifacts", {}) as Dictionary
	return {
		"normalized_height_npy": TerrainSettingsScript.workspace_path(str(artifacts.get("normalized_height_npy", ""))),
		"residual_m_npy": TerrainSettingsScript.workspace_path(str(artifacts.get("residual_m_npy", ""))),
	}


func load_kernel_arrays(kernel_index: int) -> Dictionary:
	if kernel_index < 0 or kernel_index >= kernels.size():
		return _fail("kernel_index_out_of_range:%d" % kernel_index)
	var kernel := kernels[kernel_index] as Dictionary
	var paths := kernel_runtime_paths(kernel)
	var normalized := NpyFloat32ArrayScript.load_2d(paths["normalized_height_npy"])
	if normalized.get("status") != "pass":
		return _fail("normalized:%s" % normalized.get("error", "unknown"))
	var residual := NpyFloat32ArrayScript.load_2d(paths["residual_m_npy"])
	if residual.get("status") != "pass":
		return _fail("residual:%s" % residual.get("error", "unknown"))
	return {
		"status": "pass",
		"kernel_id": str(kernel.get("id", "")),
		"family": str(kernel.get("family", "")),
		"normalized": normalized,
		"residual": residual,
	}


func load_kernel_arrays_by_id(kernel_id: String) -> Dictionary:
	if _array_cache.has(kernel_id):
		return _array_cache[kernel_id] as Dictionary
	if not _kernel_id_to_index.has(kernel_id):
		return _fail("kernel_id_not_found:%s" % kernel_id)
	var loaded := load_kernel_arrays(int(_kernel_id_to_index[kernel_id]))
	if loaded.get("status") == "pass":
		_array_cache[kernel_id] = loaded
		_normalized_cache[kernel_id] = {
			"status": "pass",
			"kernel_id": str(loaded.get("kernel_id", "")),
			"family": str(loaded.get("family", "")),
			"normalized": loaded["normalized"],
		}
	return loaded


func kernel_metadata_by_id(kernel_id: String) -> Dictionary:
	if not _kernel_id_to_index.has(kernel_id):
		return {}
	return kernels[int(_kernel_id_to_index[kernel_id])] as Dictionary


func load_kernel_normalized(kernel_index: int) -> Dictionary:
	if kernel_index < 0 or kernel_index >= kernels.size():
		return _fail("kernel_index_out_of_range:%d" % kernel_index)
	var kernel := kernels[kernel_index] as Dictionary
	var paths := kernel_runtime_paths(kernel)
	var normalized := NpyFloat32ArrayScript.load_2d(paths["normalized_height_npy"])
	if normalized.get("status") != "pass":
		return _fail("normalized:%s" % normalized.get("error", "unknown"))
	return {
		"status": "pass",
		"kernel_id": str(kernel.get("id", "")),
		"family": str(kernel.get("family", "")),
		"normalized": normalized,
	}


func load_kernel_normalized_by_id(kernel_id: String) -> Dictionary:
	if _normalized_cache.has(kernel_id):
		return _normalized_cache[kernel_id] as Dictionary
	if not _kernel_id_to_index.has(kernel_id):
		return _fail("kernel_id_not_found:%s" % kernel_id)
	var loaded := load_kernel_normalized(int(_kernel_id_to_index[kernel_id]))
	if loaded.get("status") == "pass":
		_normalized_cache[kernel_id] = loaded
	return loaded


func validate_runtime_sources(load_first_arrays: bool = false) -> Dictionary:
	var report_errors: Array[String] = []
	if data.get("schema", "") != "worldgen9.runtime_kernel_pack.v1":
		report_errors.append("schema_mismatch")
	if int(data.get("kernel_count", 0)) != kernels.size():
		report_errors.append("kernel_count_mismatch")
	_check_default("chunk_size_m", TerrainSettingsScript.CHUNK_SIZE_M, report_errors)
	_check_default("lod0_vertices_per_side", TerrainSettingsScript.LOD0_VERTICES_PER_SIDE, report_errors)
	_check_default("region_size_m", TerrainSettingsScript.REGION_SIZE_M, report_errors)
	_check_default("province_size_regions", TerrainSettingsScript.PROVINCE_SIZE_REGIONS, report_errors)

	var missing_arrays := 0
	for kernel in kernels:
		var paths := kernel_runtime_paths(kernel as Dictionary)
		for key in ["normalized_height_npy", "residual_m_npy"]:
			if not FileAccess.file_exists(paths[key]):
				missing_arrays += 1
				report_errors.append("missing_%s:%s" % [key, paths[key]])

	var loaded_kernel_id := ""
	var loaded_shape: Array = []
	if load_first_arrays and not kernels.is_empty():
		var loaded := load_kernel_arrays(0)
		if loaded.get("status") != "pass":
			report_errors.append(str(loaded.get("error", "array_load_failed")))
		else:
			loaded_kernel_id = str(loaded.get("kernel_id", ""))
			loaded_shape = (loaded["normalized"] as Dictionary).get("shape", []) as Array

	return {
		"status": "pass" if report_errors.is_empty() else "fail",
		"errors": report_errors,
		"kernel_count": kernels.size(),
		"family_count": families.size(),
		"missing_arrays": missing_arrays,
		"loaded_kernel_id": loaded_kernel_id,
		"loaded_shape": loaded_shape,
	}


func _validate_metadata() -> void:
	if data.get("schema", "") != "worldgen9.runtime_kernel_pack.v1":
		errors.append("schema_mismatch")
	if not data.has("kernels") or typeof(data["kernels"]) != TYPE_ARRAY:
		errors.append("missing_kernels")
	if not data.has("runtime_defaults") or typeof(data["runtime_defaults"]) != TYPE_DICTIONARY:
		errors.append("missing_runtime_defaults")
	if not data.has("families") or typeof(data["families"]) != TYPE_DICTIONARY:
		errors.append("missing_families")


func _rebuild_kernel_index() -> void:
	_array_cache.clear()
	_normalized_cache.clear()
	_kernel_id_to_index.clear()
	for index in range(kernels.size()):
		var kernel := kernels[index] as Dictionary
		var kernel_id := str(kernel.get("id", ""))
		if kernel_id.is_empty():
			errors.append("empty_kernel_id:%d" % index)
			continue
		if _kernel_id_to_index.has(kernel_id):
			errors.append("duplicate_kernel_id:%s:%d:%d" % [kernel_id, int(_kernel_id_to_index[kernel_id]), index])
			continue
		_kernel_id_to_index[kernel_id] = index


func _check_default(key: String, expected: Variant, report_errors: Array[String]) -> void:
	if not runtime_defaults.has(key):
		report_errors.append("missing_default:%s" % key)
		return
	if typeof(expected) == TYPE_FLOAT:
		if abs(float(runtime_defaults[key]) - float(expected)) > 0.000001:
			report_errors.append("default_mismatch:%s" % key)
	else:
		if int(runtime_defaults[key]) != int(expected):
			report_errors.append("default_mismatch:%s" % key)


func _fail(error: String) -> Dictionary:
	return {
		"status": "fail",
		"error": error,
	}
