extends SceneTree

const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")

const MAX_DELTA_M: float = 0.08
const MAX_MEAN_DELTA_M: float = 0.015


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var backend = TerrainGpuHeightPageBackendScript.new()
	var setup_result: Dictionary = backend.setup()
	if setup_result.get("status", "fail") == "unsupported":
		print("[wg9-gpu-height-page] status=unsupported result=%s" % str(setup_result))
		quit(0)
		return
	if setup_result.get("status", "fail") != "pass":
		errors.append("setup:%s" % str(setup_result))
	else:
		_check_case(
			backend,
			"origin_positive",
			1024.0,
			2048.0,
			64.0,
			33,
			17,
			1337,
			1.0,
			1.0,
			errors
		)
		_check_case(
			backend,
			"origin_offset_macro_scale",
			8192.0,
			4096.0,
			128.0,
			25,
			25,
			1441,
			1.35,
			1.0,
			errors
		)
		_check_case(
			backend,
			"negative_origin_regional_scale",
			-8192.0,
			4096.0,
			128.0,
			25,
			25,
			1441,
			0.85,
			1.2,
			errors
		)
		_check_invalid_requests(backend, errors)
	var state: Dictionary = backend.debug_state()
	if int(state.get("compile_count", 0)) != 1:
		errors.append("compile_count:%s" % str(state))
	if int(state.get("dispatch_count", 0)) < 3:
		errors.append("dispatch_count:%s" % str(state))
	backend.shutdown()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-height-page] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-height-page] status=pass state=%s" % str(state))
	quit(0)


func _check_case(
	backend: RefCounted,
	label: String,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int,
	macro_relief_scale: float,
	regional_scale_multiplier: float,
	errors: Array[String]
) -> void:
	var result: Dictionary = backend.compute_macro_height_page(
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		macro_relief_scale,
		regional_scale_multiplier
	)
	if result.get("status", "fail") != "pass":
		errors.append("%s:compute:%s" % [label, str(result)])
		return
	var values: PackedFloat32Array = result.get("values", PackedFloat32Array()) as PackedFloat32Array
	if values.size() != count_x * count_z:
		errors.append("%s:value_count:%d" % [label, values.size()])
	if (result.get("height_image_data", PackedByteArray()) as PackedByteArray).size() != count_x * count_z * 4:
		errors.append("%s:height_bytes:%d" % [label, (result.get("height_image_data", PackedByteArray()) as PackedByteArray).size()])
	var comparison: Dictionary = backend.compare_to_reference(result)
	if comparison.get("status", "fail") != "pass":
		errors.append("%s:compare:%s" % [label, str(comparison)])
		return
	if float(comparison.get("max_delta_m", 999.0)) > MAX_DELTA_M:
		errors.append("%s:max_delta:%s" % [label, str(comparison)])
	if float(comparison.get("mean_delta_m", 999.0)) > MAX_MEAN_DELTA_M:
		errors.append("%s:mean_delta:%s" % [label, str(comparison)])


func _check_invalid_requests(backend: RefCounted, errors: Array[String]) -> void:
	var bad_step: Dictionary = backend.compute_macro_height_page(0.0, 0.0, 0.0, 4, 4)
	if bad_step.get("status", "pass") == "pass":
		errors.append("bad_step_passed")
	var bad_count: Dictionary = backend.compute_macro_height_page(0.0, 0.0, 16.0, 0, 4)
	if bad_count.get("status", "pass") == "pass":
		errors.append("bad_count_passed")
	var bad_scale: Dictionary = backend.compute_macro_height_page(0.0, 0.0, 16.0, 4, 4, 1337, 1.0, 0.0)
	if bad_scale.get("status", "pass") == "pass":
		errors.append("bad_scale_passed")
	var bad_macro_scale: Dictionary = backend.compute_macro_height_page(0.0, 0.0, 16.0, 4, 4, 1337, 0.0, 1.0)
	if bad_macro_scale.get("status", "pass") == "pass":
		errors.append("bad_macro_scale_passed")
