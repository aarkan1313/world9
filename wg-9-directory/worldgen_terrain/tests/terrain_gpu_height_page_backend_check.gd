extends SceneTree

const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainHeightProviderScript := preload("res://worldgen_terrain/height/terrain_height_provider.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const MAX_DELTA_M: float = 0.08
const MAX_MEAN_DELTA_M: float = 0.015
const MAX_KERNEL_DELTA: float = 0.0001
const MAX_PROVIDER_DELTA_M: float = 0.12
const MAX_PROVIDER_MEAN_DELTA_M: float = 0.03


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
		_check_kernel_sample_case(backend, errors)
		_check_prepared_provider_case(backend, errors)
	var state: Dictionary = backend.debug_state()
	if int(state.get("compile_count", 0)) != 1:
		errors.append("compile_count:%s" % str(state))
	if int(state.get("kernel_compile_count", 0)) != 1:
		errors.append("kernel_compile_count:%s" % str(state))
	if int(state.get("provider_compile_count", 0)) != 1:
		errors.append("provider_compile_count:%s" % str(state))
	if int(state.get("dispatch_count", 0)) < 3:
		errors.append("dispatch_count:%s" % str(state))
	if int(state.get("kernel_dispatch_count", 0)) < 1:
		errors.append("kernel_dispatch_count:%s" % str(state))
	if int(state.get("provider_dispatch_count", 0)) < 1:
		errors.append("provider_dispatch_count:%s" % str(state))
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
	var bad_kernel_shape: Dictionary = backend.compute_kernel_sample_page(PackedFloat32Array(), 0, 0, 0.0, 0.0, 16.0, 4, 4, 1024.0, 0, 0.0, 0.0)
	if bad_kernel_shape.get("status", "pass") == "pass":
		errors.append("bad_kernel_shape_passed")


func _check_kernel_sample_case(backend: RefCounted, errors: Array[String]) -> void:
	var pack = RuntimeKernelPackScript.new()
	if not pack.load_default():
		errors.append("kernel_pack:%s" % str(pack.errors))
		return
	var loaded: Dictionary = pack.load_kernel_normalized(0)
	if loaded.get("status", "fail") != "pass":
		errors.append("kernel_load:%s" % str(loaded))
		return
	var normalized: Dictionary = loaded["normalized"] as Dictionary
	var shape: Array = normalized["shape"] as Array
	var rows: int = int(shape[0])
	var cols: int = int(shape[1])
	var values: PackedFloat32Array = normalized["values"] as PackedFloat32Array
	var result: Dictionary = backend.compute_kernel_sample_page(
		values,
		rows,
		cols,
		-4096.0,
		2048.0,
		96.0,
		31,
		23,
		9000.0,
		3,
		0.271,
		-0.613
	)
	if result.get("status", "fail") != "pass":
		errors.append("kernel_compute:%s" % str(result))
		return
	var comparison: Dictionary = backend.compare_kernel_to_reference(result, values)
	if comparison.get("status", "fail") != "pass":
		errors.append("kernel_compare:%s" % str(comparison))
		return
	if float(comparison.get("max_delta", 999.0)) > MAX_KERNEL_DELTA:
		errors.append("kernel_max_delta:%s" % str(comparison))
	if float(comparison.get("mean_delta", 999.0)) > MAX_KERNEL_DELTA:
		errors.append("kernel_mean_delta:%s" % str(comparison))


func _check_prepared_provider_case(backend: RefCounted, errors: Array[String]) -> void:
	var pack = RuntimeKernelPackScript.new()
	if not pack.load_default():
		errors.append("provider_pack:%s" % str(pack.errors))
		return
	var provider = TerrainHeightProviderScript.new()
	provider.setup(pack)
	var origin_x := 1024.0
	var origin_z := 2048.0
	var step_m := 128.0
	var count_x := 17
	var count_z := 13
	var world_seed := 1337
	var region_size_m: float = TerrainSettingsScript.REGION_SIZE_M
	var prepared: Dictionary = provider.native_prepared_height_grid_request(
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	if prepared.get("status", "fail") != "pass":
		errors.append("provider_prepared:%s" % str(prepared))
		return
	var descriptor: Dictionary = backend.build_prepared_provider_page_descriptor(
		prepared,
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	if descriptor.get("status", "fail") != "pass":
		errors.append("provider_descriptor:%s" % str(descriptor))
		return
	if str(descriptor.get("schema", "")) != "worldgen9.gpu_provider_page_descriptor.v1":
		errors.append("provider_descriptor_schema:%s" % str(descriptor))
	if (descriptor.get("params_bytes", PackedByteArray()) as PackedByteArray).size() != 64:
		errors.append("provider_params_bytes:%d" % (descriptor.get("params_bytes", PackedByteArray()) as PackedByteArray).size())
	if int(descriptor.get("entry_count", 0)) <= 0:
		errors.append("provider_entry_count:%s" % str(descriptor))
	if int(descriptor.get("kernel_value_count", 0)) <= 0:
		errors.append("provider_kernel_value_count:%s" % str(descriptor))
	_check_provider_corridor_rejection(backend, prepared, origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m, errors)
	var result: Dictionary = backend.compute_prepared_provider_height_page(
		prepared,
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	if result.get("status", "fail") != "pass":
		errors.append("provider_compute:%s" % str(result))
		return
	var expected: PackedFloat32Array = provider.sample_height_grid(
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	var comparison: Dictionary = backend.compare_values_to_reference(result, expected)
	if comparison.get("status", "fail") != "pass":
		errors.append("provider_compare:%s" % str(comparison))
		return
	if float(comparison.get("max_delta_m", 999.0)) > MAX_PROVIDER_DELTA_M:
		errors.append("provider_max_delta:%s" % str(comparison))
	if float(comparison.get("mean_delta_m", 999.0)) > MAX_PROVIDER_MEAN_DELTA_M:
		errors.append("provider_mean_delta:%s" % str(comparison))


func _check_provider_corridor_rejection(
	backend: RefCounted,
	prepared: Dictionary,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int,
	region_size_m: float,
	errors: Array[String]
) -> void:
	var corridor_prepared: Dictionary = prepared.duplicate(true)
	var corners: Array = corridor_prepared["corner_entries"] as Array
	for corner_value in corners:
		var corner: Dictionary = corner_value as Dictionary
		var entries: Array = corner.get("entries", []) as Array
		if not entries.is_empty():
			var entry: Dictionary = entries[0] as Dictionary
			entry["profile_pass_corridor_strength"] = 1.0
			break
	var descriptor: Dictionary = backend.build_prepared_provider_page_descriptor(
		corridor_prepared,
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	if descriptor.get("status", "pass") == "pass":
		errors.append("provider_corridor_descriptor_passed")
