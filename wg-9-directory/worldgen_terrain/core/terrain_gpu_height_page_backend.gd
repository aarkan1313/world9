class_name TerrainGpuHeightPageBackend
extends RefCounted

const TerrainHashScript := preload("res://worldgen_terrain/height/terrain_hash.gd")

const U32_MASK: int = 0xffffffff
const U32_DENOMINATOR: float = 4294967295.0
const MAX_SAMPLE_COUNT: int = 1048576

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _kernel_shader_rid: RID
var _kernel_pipeline_rid: RID
var _provider_shader_rid: RID
var _provider_pipeline_rid: RID
var _compile_count: int = 0
var _kernel_compile_count: int = 0
var _provider_compile_count: int = 0
var _dispatch_count: int = 0
var _kernel_dispatch_count: int = 0
var _provider_dispatch_count: int = 0
var _last_error: String = ""


func setup() -> Dictionary:
	if _rd != null:
		return {"status": "pass"}
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		_last_error = "rendering_device_unavailable"
		return {
			"status": "unsupported",
			"error": _last_error,
			"headless_runtime_note": "Godot headless checks can run without a RenderingDevice; use non-headless GPU probes for actual compute validation.",
		}
	return _ensure_pipeline()


func shutdown() -> void:
	if _rd == null:
		return
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
	if _kernel_pipeline_rid.is_valid():
		_rd.free_rid(_kernel_pipeline_rid)
	if _kernel_shader_rid.is_valid():
		_rd.free_rid(_kernel_shader_rid)
	if _provider_pipeline_rid.is_valid():
		_rd.free_rid(_provider_pipeline_rid)
	if _provider_shader_rid.is_valid():
		_rd.free_rid(_provider_shader_rid)
	_pipeline_rid = RID()
	_shader_rid = RID()
	_kernel_pipeline_rid = RID()
	_kernel_shader_rid = RID()
	_provider_pipeline_rid = RID()
	_provider_shader_rid = RID()
	_rd.free()
	_rd = null


func compute_macro_height_page(
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int = 1337,
	macro_relief_scale: float = 1.0,
	regional_scale_multiplier: float = 1.0
) -> Dictionary:
	var validation: String = _validate_request(origin_x, origin_z, step_m, count_x, count_z, macro_relief_scale, regional_scale_multiplier)
	if not validation.is_empty():
		return {"status": "fail", "error": validation}
	var setup_result: Dictionary = setup()
	if setup_result.get("status", "fail") != "pass":
		return setup_result

	var sample_count: int = count_x * count_z
	var params := PackedByteArray()
	params.resize(32)
	params.encode_float(0, origin_x)
	params.encode_float(4, origin_z)
	params.encode_float(8, step_m)
	params.encode_u32(12, count_x)
	params.encode_u32(16, count_z)
	params.encode_s32(20, world_seed)
	params.encode_float(24, macro_relief_scale)
	params.encode_float(28, regional_scale_multiplier)
	var output := PackedByteArray()
	output.resize(sample_count * 4)

	var params_buffer: RID = _rd.storage_buffer_create(params.size(), params)
	var output_buffer: RID = _rd.storage_buffer_create(output.size(), output)
	if not params_buffer.is_valid() or not output_buffer.is_valid():
		_free_rids([output_buffer, params_buffer])
		return {"status": "fail", "error": "storage_buffer_create_failed"}

	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)
	var uniform_set: RID = _rd.uniform_set_create([params_uniform, output_uniform], _shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids([uniform_set, output_buffer, params_buffer])
		return {"status": "fail", "error": "uniform_set_create_failed"}

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, int(ceil(float(count_x) / 8.0)), int(ceil(float(count_z) / 8.0)), 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	_dispatch_count += 1

	var readback: PackedByteArray = _rd.buffer_get_data(output_buffer)
	_free_rids([uniform_set, output_buffer, params_buffer])
	var values := PackedFloat32Array()
	values.resize(sample_count)
	for index in range(sample_count):
		values[index] = readback.decode_float(index * 4)
	return {
		"status": "pass",
		"values": values,
		"height_image_data": readback,
		"height_image_format": "rf",
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count_x": count_x,
		"count_z": count_z,
		"world_seed": world_seed,
		"macro_relief_scale": macro_relief_scale,
		"regional_scale_multiplier": regional_scale_multiplier,
		"workgroups_x": int(ceil(float(count_x) / 8.0)),
		"workgroups_y": int(ceil(float(count_z) / 8.0)),
	}


func reference_macro_height_page(
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int = 1337,
	macro_relief_scale: float = 1.0,
	regional_scale_multiplier: float = 1.0
) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if not _validate_request(origin_x, origin_z, step_m, count_x, count_z, macro_relief_scale, regional_scale_multiplier).is_empty():
		return values
	values.resize(count_x * count_z)
	var index := 0
	for z in range(count_z):
		for x in range(count_x):
			var world_x: float = origin_x + float(x) * step_m
			var world_z: float = origin_z + float(z) * step_m
			values[index] = _f32(_macro_height(world_x, world_z, world_seed, macro_relief_scale, regional_scale_multiplier))
			index += 1
	return values


func compute_kernel_sample_page(
	kernel_values: PackedFloat32Array,
	rows: int,
	cols: int,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	scale_m: float,
	angle_i: int,
	offset_u: float,
	offset_v: float
) -> Dictionary:
	var validation: String = _validate_kernel_request(kernel_values, rows, cols, origin_x, origin_z, step_m, count_x, count_z, scale_m, angle_i, offset_u, offset_v)
	if not validation.is_empty():
		return {"status": "fail", "error": validation}
	var setup_result: Dictionary = setup()
	if setup_result.get("status", "fail") != "pass":
		return setup_result
	var pipeline_result: Dictionary = _ensure_kernel_pipeline()
	if pipeline_result.get("status", "fail") != "pass":
		return pipeline_result

	var sample_count: int = count_x * count_z
	var params := PackedByteArray()
	params.resize(48)
	params.encode_float(0, origin_x)
	params.encode_float(4, origin_z)
	params.encode_float(8, step_m)
	params.encode_float(12, scale_m)
	params.encode_float(16, offset_u)
	params.encode_float(20, offset_v)
	params.encode_u32(24, count_x)
	params.encode_u32(28, count_z)
	params.encode_u32(32, rows)
	params.encode_u32(36, cols)
	params.encode_s32(40, angle_i)
	var kernel_bytes := PackedByteArray()
	kernel_bytes.resize(kernel_values.size() * 4)
	for index in range(kernel_values.size()):
		kernel_bytes.encode_float(index * 4, float(kernel_values[index]))
	var output := PackedByteArray()
	output.resize(sample_count * 4)

	var params_buffer: RID = _rd.storage_buffer_create(params.size(), params)
	var kernel_buffer: RID = _rd.storage_buffer_create(kernel_bytes.size(), kernel_bytes)
	var output_buffer: RID = _rd.storage_buffer_create(output.size(), output)
	if not params_buffer.is_valid() or not kernel_buffer.is_valid() or not output_buffer.is_valid():
		_free_rids([output_buffer, kernel_buffer, params_buffer])
		return {"status": "fail", "error": "storage_buffer_create_failed"}

	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer)
	var kernel_uniform := RDUniform.new()
	kernel_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	kernel_uniform.binding = 1
	kernel_uniform.add_id(kernel_buffer)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 2
	output_uniform.add_id(output_buffer)
	var uniform_set: RID = _rd.uniform_set_create([params_uniform, kernel_uniform, output_uniform], _kernel_shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids([uniform_set, output_buffer, kernel_buffer, params_buffer])
		return {"status": "fail", "error": "uniform_set_create_failed"}

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _kernel_pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, int(ceil(float(count_x) / 8.0)), int(ceil(float(count_z) / 8.0)), 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	_kernel_dispatch_count += 1

	var readback: PackedByteArray = _rd.buffer_get_data(output_buffer)
	_free_rids([uniform_set, output_buffer, kernel_buffer, params_buffer])
	var values := PackedFloat32Array()
	values.resize(sample_count)
	for index in range(sample_count):
		values[index] = readback.decode_float(index * 4)
	return {
		"status": "pass",
		"values": values,
		"kernel_sample_data": readback,
		"kernel_sample_format": "rf",
		"rows": rows,
		"cols": cols,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count_x": count_x,
		"count_z": count_z,
		"scale_m": scale_m,
		"angle_i": angle_i,
		"offset_u": offset_u,
		"offset_v": offset_v,
	}


func reference_kernel_sample_page(
	kernel_values: PackedFloat32Array,
	rows: int,
	cols: int,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	scale_m: float,
	angle_i: int,
	offset_u: float,
	offset_v: float
) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if not _validate_kernel_request(kernel_values, rows, cols, origin_x, origin_z, step_m, count_x, count_z, scale_m, angle_i, offset_u, offset_v).is_empty():
		return values
	values.resize(count_x * count_z)
	var index := 0
	for z in range(count_z):
		for x in range(count_x):
			var world_x: float = origin_x + float(x) * step_m
			var world_z: float = origin_z + float(z) * step_m
			var u: float = world_x / scale_m
			var v: float = world_z / scale_m
			if angle_i == 1:
				var old_u: float = u
				u = v
				v = -old_u
			elif angle_i == 2:
				u = -u
				v = -v
			elif angle_i == 3:
				var old_u3: float = u
				u = -v
				v = old_u3
			u += offset_u
			v += offset_v
			values[index] = _f32(_bilinear_sample_values(kernel_values, rows, cols, u, v))
			index += 1
	return values


func compare_kernel_to_reference(result: Dictionary, kernel_values: PackedFloat32Array) -> Dictionary:
	if result.get("status", "fail") != "pass":
		return result
	var expected: PackedFloat32Array = reference_kernel_sample_page(
		kernel_values,
		int(result.get("rows", 0)),
		int(result.get("cols", 0)),
		float(result.get("origin_x", 0.0)),
		float(result.get("origin_z", 0.0)),
		float(result.get("step_m", 0.0)),
		int(result.get("count_x", 0)),
		int(result.get("count_z", 0)),
		float(result.get("scale_m", 0.0)),
		int(result.get("angle_i", 0)),
		float(result.get("offset_u", 0.0)),
		float(result.get("offset_v", 0.0))
	)
	var actual: PackedFloat32Array = result.get("values", PackedFloat32Array()) as PackedFloat32Array
	if expected.size() != actual.size():
		return {"status": "fail", "error": "size:%d expected:%d" % [actual.size(), expected.size()]}
	var max_delta := 0.0
	var sum_delta := 0.0
	for index in range(actual.size()):
		var delta: float = absf(float(actual[index]) - float(expected[index]))
		max_delta = maxf(max_delta, delta)
		sum_delta += delta
	return {
		"status": "pass",
		"sample_count": actual.size(),
		"max_delta": max_delta,
		"mean_delta": sum_delta / float(max(1, actual.size())),
	}


func compute_prepared_provider_height_page(
	prepared_request: Dictionary,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int,
	region_size_m: float
) -> Dictionary:
	var setup_result: Dictionary = setup()
	if setup_result.get("status", "fail") != "pass":
		return setup_result
	var pipeline_result: Dictionary = _ensure_provider_pipeline()
	if pipeline_result.get("status", "fail") != "pass":
		return pipeline_result
	var descriptor: Dictionary = build_prepared_provider_page_descriptor(
		prepared_request,
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m
	)
	if descriptor.get("status", "fail") != "pass":
		return descriptor
	var sample_count: int = count_x * count_z
	var params: PackedByteArray = descriptor["params_bytes"] as PackedByteArray
	var entries_bytes: PackedByteArray = descriptor["entry_bytes"] as PackedByteArray
	var kernel_bytes: PackedByteArray = descriptor["kernel_bytes"] as PackedByteArray
	var output := PackedByteArray()
	output.resize(sample_count * 4)

	var params_buffer: RID = _rd.storage_buffer_create(params.size(), params)
	var entries_buffer: RID = _rd.storage_buffer_create(entries_bytes.size(), entries_bytes)
	var kernel_buffer: RID = _rd.storage_buffer_create(kernel_bytes.size(), kernel_bytes)
	var output_buffer: RID = _rd.storage_buffer_create(output.size(), output)
	if not params_buffer.is_valid() or not entries_buffer.is_valid() or not kernel_buffer.is_valid() or not output_buffer.is_valid():
		_free_rids([output_buffer, kernel_buffer, entries_buffer, params_buffer])
		return {"status": "fail", "error": "storage_buffer_create_failed"}

	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer)
	var entries_uniform := RDUniform.new()
	entries_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	entries_uniform.binding = 1
	entries_uniform.add_id(entries_buffer)
	var kernel_uniform := RDUniform.new()
	kernel_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	kernel_uniform.binding = 2
	kernel_uniform.add_id(kernel_buffer)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 3
	output_uniform.add_id(output_buffer)
	var uniform_set: RID = _rd.uniform_set_create([params_uniform, entries_uniform, kernel_uniform, output_uniform], _provider_shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids([uniform_set, output_buffer, kernel_buffer, entries_buffer, params_buffer])
		return {"status": "fail", "error": "uniform_set_create_failed"}

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _provider_pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, int(ceil(float(count_x) / 8.0)), int(ceil(float(count_z) / 8.0)), 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	_provider_dispatch_count += 1

	var readback: PackedByteArray = _rd.buffer_get_data(output_buffer)
	_free_rids([uniform_set, output_buffer, kernel_buffer, entries_buffer, params_buffer])
	var values := PackedFloat32Array()
	values.resize(sample_count)
	for index in range(sample_count):
		values[index] = readback.decode_float(index * 4)
	return {
		"status": "pass",
		"values": values,
		"height_image_data": readback,
		"height_image_format": "rf",
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count_x": count_x,
		"count_z": count_z,
		"world_seed": world_seed,
		"region_size_m": region_size_m,
		"entry_count": int(descriptor.get("entry_count", 0)),
		"kernel_value_count": int(descriptor.get("kernel_value_count", 0)),
	}


func build_prepared_provider_page_descriptor(
	prepared_request: Dictionary,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int,
	region_size_m: float
) -> Dictionary:
	var validation: String = _validate_provider_request(prepared_request, origin_x, origin_z, step_m, count_x, count_z, region_size_m)
	if not validation.is_empty():
		return {"status": "fail", "error": validation}
	var flattened: Dictionary = _flatten_provider_entries(prepared_request)
	if flattened.get("status", "fail") != "pass":
		return flattened
	var profile: Dictionary = flattened["profile"] as Dictionary
	var params := PackedByteArray()
	params.resize(64)
	var param_values: Array[float] = [
		origin_x,
		origin_z,
		step_m,
		region_size_m,
		float(count_x),
		float(count_z),
		float(world_seed),
		float(prepared_request.get("base_rx", 0)),
		float(prepared_request.get("base_rz", 0)),
		float(flattened.get("entry_count", 0)),
		float(profile.get("macro_relief_scale", 1.0)),
		float(profile.get("regional_scale_multiplier", 1.0)),
		float(profile.get("valley_bias_strength", 1.0)),
		0.0,
		0.0,
		0.0,
	]
	for index in range(param_values.size()):
		params.encode_float(index * 4, param_values[index])
	return {
		"status": "pass",
		"schema": "worldgen9.gpu_provider_page_descriptor.v1",
		"params_bytes": params,
		"entry_bytes": flattened["entry_bytes"] as PackedByteArray,
		"kernel_bytes": flattened["kernel_bytes"] as PackedByteArray,
		"entry_count": int(flattened.get("entry_count", 0)),
		"kernel_value_count": int(flattened.get("kernel_value_count", 0)),
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count_x": count_x,
		"count_z": count_z,
		"world_seed": world_seed,
		"region_size_m": region_size_m,
	}


func compare_values_to_reference(result: Dictionary, expected: PackedFloat32Array) -> Dictionary:
	if result.get("status", "fail") != "pass":
		return result
	var actual: PackedFloat32Array = result.get("values", PackedFloat32Array()) as PackedFloat32Array
	if actual.size() != expected.size():
		return {"status": "fail", "error": "size:%d expected:%d" % [actual.size(), expected.size()]}
	var max_delta := 0.0
	var sum_delta := 0.0
	for index in range(actual.size()):
		var delta: float = absf(float(actual[index]) - float(expected[index]))
		max_delta = maxf(max_delta, delta)
		sum_delta += delta
	return {
		"status": "pass",
		"sample_count": actual.size(),
		"max_delta_m": max_delta,
		"mean_delta_m": sum_delta / float(max(1, actual.size())),
	}


func compare_to_reference(result: Dictionary) -> Dictionary:
	if result.get("status", "fail") != "pass":
		return result
	var expected: PackedFloat32Array = reference_macro_height_page(
		float(result.get("origin_x", 0.0)),
		float(result.get("origin_z", 0.0)),
		float(result.get("step_m", 0.0)),
		int(result.get("count_x", 0)),
		int(result.get("count_z", 0)),
		int(result.get("world_seed", 0)),
		float(result.get("macro_relief_scale", 1.0)),
		float(result.get("regional_scale_multiplier", 1.0))
	)
	var actual: PackedFloat32Array = result.get("values", PackedFloat32Array()) as PackedFloat32Array
	if expected.size() != actual.size():
		return {"status": "fail", "error": "size:%d expected:%d" % [actual.size(), expected.size()]}
	var max_delta := 0.0
	var sum_delta := 0.0
	for index in range(actual.size()):
		var delta: float = absf(float(actual[index]) - float(expected[index]))
		max_delta = maxf(max_delta, delta)
		sum_delta += delta
	return {
		"status": "pass",
		"sample_count": actual.size(),
		"max_delta_m": max_delta,
		"mean_delta_m": sum_delta / float(max(1, actual.size())),
	}


func debug_state() -> Dictionary:
	return {
		"available": _rd != null,
		"compile_count": _compile_count,
		"kernel_compile_count": _kernel_compile_count,
		"provider_compile_count": _provider_compile_count,
		"dispatch_count": _dispatch_count,
		"kernel_dispatch_count": _kernel_dispatch_count,
		"provider_dispatch_count": _provider_dispatch_count,
		"last_error": _last_error,
	}


func _ensure_pipeline() -> Dictionary:
	if _shader_rid.is_valid() and _pipeline_rid.is_valid():
		return {"status": "pass"}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _macro_height_shader()
	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		_last_error = "shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null")
		return {"status": "fail", "error": _last_error}
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader_rid.is_valid():
		_last_error = "shader_create_failed"
		return {"status": "fail", "error": _last_error}
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	if not _pipeline_rid.is_valid():
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()
		_last_error = "pipeline_create_failed"
		return {"status": "fail", "error": _last_error}
	_compile_count += 1
	return {"status": "pass"}


func _ensure_kernel_pipeline() -> Dictionary:
	if _kernel_shader_rid.is_valid() and _kernel_pipeline_rid.is_valid():
		return {"status": "pass"}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _kernel_sample_shader()
	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		_last_error = "kernel_shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null")
		return {"status": "fail", "error": _last_error}
	_kernel_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if not _kernel_shader_rid.is_valid():
		_last_error = "kernel_shader_create_failed"
		return {"status": "fail", "error": _last_error}
	_kernel_pipeline_rid = _rd.compute_pipeline_create(_kernel_shader_rid)
	if not _kernel_pipeline_rid.is_valid():
		_rd.free_rid(_kernel_shader_rid)
		_kernel_shader_rid = RID()
		_last_error = "kernel_pipeline_create_failed"
		return {"status": "fail", "error": _last_error}
	_kernel_compile_count += 1
	return {"status": "pass"}


func _ensure_provider_pipeline() -> Dictionary:
	if _provider_shader_rid.is_valid() and _provider_pipeline_rid.is_valid():
		return {"status": "pass"}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _provider_height_shader()
	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		_last_error = "provider_shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null")
		return {"status": "fail", "error": _last_error}
	_provider_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if not _provider_shader_rid.is_valid():
		_last_error = "provider_shader_create_failed"
		return {"status": "fail", "error": _last_error}
	_provider_pipeline_rid = _rd.compute_pipeline_create(_provider_shader_rid)
	if not _provider_pipeline_rid.is_valid():
		_rd.free_rid(_provider_shader_rid)
		_provider_shader_rid = RID()
		_last_error = "provider_pipeline_create_failed"
		return {"status": "fail", "error": _last_error}
	_provider_compile_count += 1
	return {"status": "pass"}


func _validate_request(
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	macro_relief_scale: float,
	regional_scale_multiplier: float
) -> String:
	if not is_finite(origin_x) or not is_finite(origin_z):
		return "origin_nonfinite"
	if not is_finite(step_m) or step_m <= 0.0:
		return "step_m:%f" % step_m
	if count_x < 1 or count_z < 1:
		return "count:%d,%d" % [count_x, count_z]
	if count_x * count_z > MAX_SAMPLE_COUNT:
		return "sample_count:%d" % (count_x * count_z)
	if not is_finite(macro_relief_scale) or macro_relief_scale <= 0.0:
		return "macro_relief_scale:%f" % macro_relief_scale
	if not is_finite(regional_scale_multiplier) or regional_scale_multiplier <= 0.0:
		return "regional_scale_multiplier:%f" % regional_scale_multiplier
	return ""


func _validate_kernel_request(
	kernel_values: PackedFloat32Array,
	rows: int,
	cols: int,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	scale_m: float,
	angle_i: int,
	offset_u: float,
	offset_v: float
) -> String:
	if rows < 2 or cols < 2:
		return "kernel_shape:%d,%d" % [rows, cols]
	if kernel_values.size() != rows * cols:
		return "kernel_values:%d expected:%d" % [kernel_values.size(), rows * cols]
	if not is_finite(origin_x) or not is_finite(origin_z):
		return "origin_nonfinite"
	if not is_finite(step_m) or step_m <= 0.0:
		return "step_m:%f" % step_m
	if count_x < 1 or count_z < 1:
		return "count:%d,%d" % [count_x, count_z]
	if count_x * count_z > MAX_SAMPLE_COUNT:
		return "sample_count:%d" % (count_x * count_z)
	if not is_finite(scale_m) or scale_m <= 0.0:
		return "scale_m:%f" % scale_m
	if angle_i < 0 or angle_i > 3:
		return "angle_i:%d" % angle_i
	if not is_finite(offset_u) or not is_finite(offset_v):
		return "offset_nonfinite"
	return ""


func _validate_provider_request(
	prepared_request: Dictionary,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	region_size_m: float
) -> String:
	if prepared_request.get("status", "fail") != "pass":
		return "prepared_status:%s" % str(prepared_request.get("status", "missing"))
	if not prepared_request.has("corner_entries"):
		return "missing_corner_entries"
	if not is_finite(origin_x) or not is_finite(origin_z):
		return "origin_nonfinite"
	if not is_finite(step_m) or step_m <= 0.0:
		return "step_m:%f" % step_m
	if count_x < 1 or count_z < 1:
		return "count:%d,%d" % [count_x, count_z]
	if count_x * count_z > MAX_SAMPLE_COUNT:
		return "sample_count:%d" % (count_x * count_z)
	if not is_finite(region_size_m) or region_size_m <= 0.0:
		return "region_size_m:%f" % region_size_m
	return ""


func _flatten_provider_entries(prepared_request: Dictionary) -> Dictionary:
	var corners: Array = prepared_request.get("corner_entries", []) as Array
	if corners.size() != 4:
		return {"status": "fail", "error": "corner_count:%d" % corners.size()}
	var entry_values: Array[float] = []
	var kernel_values := PackedFloat32Array()
	var entry_count := 0
	var profile := {
		"macro_relief_scale": 1.0,
		"regional_scale_multiplier": 1.0,
		"valley_bias_strength": 1.0,
	}
	for corner_index in range(corners.size()):
		var corner: Dictionary = corners[corner_index] as Dictionary
		var entries: Array = corner.get("entries", []) as Array
		for entry_value in entries:
			var entry: Dictionary = entry_value as Dictionary
			var values: PackedFloat32Array = entry.get("values", PackedFloat32Array()) as PackedFloat32Array
			var rows: int = int(entry.get("rows", 0))
			var cols: int = int(entry.get("cols", 0))
			if rows < 2 or cols < 2 or values.size() != rows * cols:
				return {"status": "fail", "error": "entry_shape:%d:%d:%d" % [entry_count, rows, cols]}
			var pass_strength: float = float(entry.get("profile_pass_corridor_strength", 0.0))
			if absf(pass_strength) > 0.000001:
				return {"status": "fail", "error": "pass_corridor_not_supported:%f" % pass_strength}
			var scale_m: float = float(entry.get("scale", 0.0))
			var regional_scale: float = float(entry.get("profile_regional_scale_multiplier", 1.0))
			if absf(regional_scale - 1.0) > 0.000001:
				scale_m = max(0.000001, scale_m / max(0.000001, float(entry.get("scale_multiplier", 1.0))) * regional_scale)
			if scale_m <= 0.0:
				return {"status": "fail", "error": "entry_scale:%d" % entry_count}
			if entry_count == 0:
				profile["macro_relief_scale"] = float(entry.get("profile_macro_relief_scale", 1.0))
				profile["regional_scale_multiplier"] = regional_scale
				profile["valley_bias_strength"] = float(entry.get("profile_valley_bias_strength", 1.0))
			var kernel_offset: int = kernel_values.size()
			kernel_values.resize(kernel_values.size() + values.size())
			for value_index in range(values.size()):
				kernel_values[kernel_offset + value_index] = values[value_index]
			var relief_boost: float = _entry_family_relief_boost(str(entry.get("family", "")), float(entry.get("profile_mountain_boost", 1.0)))
			entry_values.append_array([
				float(corner_index),
				float(entry.get("bias", 0.0)),
				float(entry.get("runtime_weight", 1.0)),
				float(entry.get("moderation", 1.0)),
				float(entry.get("relief_scale_m", 0.0)),
				float(entry.get("detail_scale_m", 0.0)),
				scale_m,
				float(int(entry.get("angle_i", 0))),
				float(entry.get("offset_u", 0.0)),
				float(entry.get("offset_v", 0.0)),
				relief_boost,
				float(int(entry.get("detail_seed", 0))),
				float(rows),
				float(cols),
				float(kernel_offset),
				float(entry.get("profile_kernel_relief_strength", 1.0)),
			])
			entry_count += 1
	if entry_count <= 0:
		return {"status": "fail", "error": "entry_count_empty"}
	var entry_bytes := PackedByteArray()
	entry_bytes.resize(entry_values.size() * 4)
	for index in range(entry_values.size()):
		entry_bytes.encode_float(index * 4, entry_values[index])
	var kernel_bytes := PackedByteArray()
	kernel_bytes.resize(kernel_values.size() * 4)
	for index in range(kernel_values.size()):
		kernel_bytes.encode_float(index * 4, float(kernel_values[index]))
	return {
		"status": "pass",
		"entry_count": entry_count,
		"entry_bytes": entry_bytes,
		"kernel_bytes": kernel_bytes,
		"kernel_value_count": kernel_values.size(),
		"profile": profile,
	}


func _entry_family_relief_boost(family: String, mountain_boost: float) -> float:
	if absf(mountain_boost - 1.0) <= 0.000001:
		return 1.0
	if family == "mountain" or family == "glacial" or family == "volcanic":
		return mountain_boost
	return 1.0


func _macro_height(x: float, z: float, world_seed: int, macro_relief_scale: float, regional_scale_multiplier: float) -> float:
	var sample_x: float = x / regional_scale_multiplier
	var sample_z: float = z / regional_scale_multiplier
	var continent: float = TerrainHashScript.fbm(sample_x, sample_z, 52000.0, world_seed + 3, 4)
	var upland: float = TerrainHashScript.smoothstep_unit((continent + 0.2) / 0.75)
	var basin: float = 1.0 - TerrainHashScript.smoothstep_unit((continent + 0.05) / 0.55)
	var macro: float = (
		continent * 560.0
		+ TerrainHashScript.fbm(sample_x, sample_z, 26000.0, world_seed, 4) * 430.0
		+ TerrainHashScript.fbm(sample_x + 2300.0, sample_z - 1100.0, 12000.0, world_seed + 11, 3) * 140.0
	)
	var ridge: float = _ridged_noise(sample_x * 0.8 + sample_z * 0.15, sample_z * 0.65 - sample_x * 0.1, 18000.0, world_seed + 37, 3)
	macro += ridge * (190.0 + upland * 230.0)
	macro -= basin * 170.0
	return macro * macro_relief_scale


func _ridged_noise(x: float, z: float, scale_m: float, world_seed: int, octaves: int = 4) -> float:
	var value: float = TerrainHashScript.fbm(x, z, scale_m, world_seed, octaves)
	var ridged: float = 1.0 - absf(value)
	return ridged * ridged * 2.0 - 1.0


func _f32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)


func _bilinear_sample_values(values: PackedFloat32Array, rows: int, cols: int, u: float, v: float) -> float:
	var mu: float = 1.0 - absf(fposmod(u, 2.0) - 1.0)
	var mv: float = 1.0 - absf(fposmod(v, 2.0) - 1.0)
	var px: float = mu * float(cols - 1)
	var py: float = mv * float(rows - 1)
	var x0: int = clampi(int(floor(px)), 0, cols - 1)
	var y0: int = clampi(int(floor(py)), 0, rows - 1)
	var x1: int = min(x0 + 1, cols - 1)
	var y1: int = min(y0 + 1, rows - 1)
	var tx: float = px - float(x0)
	var ty: float = py - float(y0)
	var a: float = float(values[y0 * cols + x0])
	var b: float = float(values[y0 * cols + x1])
	var c: float = float(values[y1 * cols + x0])
	var d: float = float(values[y1 * cols + x1])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _macro_height_shader() -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer Params {
	float origin_x;
	float origin_z;
	float step_m;
	uint count_x;
	uint count_z;
	int world_seed;
	float macro_relief_scale;
	float regional_scale_multiplier;
} params;

layout(set = 0, binding = 1, std430) writeonly restrict buffer HeightOutput {
	float height[];
} output_buffer;

float fade(float t) {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float smoothstep_unit(float t) {
	float v = clamp(t, 0.0, 1.0);
	return v * v * (3.0 - 2.0 * v);
}

uint hash_grid_u32(int ix, int iz, int world_seed, int salt) {
	uint n = (
		uint(ix) * 374761393u
		+ uint(iz) * 668265263u
		+ uint(world_seed) * 1442695041u
		+ uint(salt) * 69069u
	);
	uint mixed = n ^ (n >> 13u);
	uint product_hi;
	uint product_lo;
	umulExtended(mixed, 1274126177u, product_hi, product_lo);
	uint shifted_low = (product_lo >> 16u) | (product_hi << 16u);
	return product_lo ^ shifted_low;
}

float hash_grid(int ix, int iz, int world_seed, int salt) {
	return float(hash_grid_u32(ix, iz, world_seed, salt)) / 4294967295.0;
}

float value_noise(float x, float z, float scale_m, int world_seed, int salt) {
	float fx = x / scale_m;
	float fz = z / scale_m;
	int ix = int(floor(fx));
	int iz = int(floor(fz));
	float tx = fade(fx - float(ix));
	float tz = fade(fz - float(iz));
	float a = hash_grid(ix, iz, world_seed, salt);
	float b = hash_grid(ix + 1, iz, world_seed, salt);
	float c = hash_grid(ix, iz + 1, world_seed, salt);
	float d = hash_grid(ix + 1, iz + 1, world_seed, salt);
	float ab = mix(a, b, tx);
	float cd = mix(c, d, tx);
	return mix(ab, cd, tz) * 2.0 - 1.0;
}

float fbm(float x, float z, float scale_m, int world_seed, int octaves) {
	float total = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		total += value_noise(x, z, scale_m / float(1 << octave), world_seed, octave) * amp;
		norm += amp;
		amp *= 0.5;
	}
	return total / max(0.000001, norm);
}

float ridged_noise(float x, float z, float scale_m, int world_seed, int octaves) {
	float value = fbm(x, z, scale_m, world_seed, octaves);
	float ridged = 1.0 - abs(value);
	return ridged * ridged * 2.0 - 1.0;
}

float macro_height(float x, float z) {
	float sample_x = x / params.regional_scale_multiplier;
	float sample_z = z / params.regional_scale_multiplier;
	int seed = params.world_seed;
	float continent = fbm(sample_x, sample_z, 52000.0, seed + 3, 4);
	float upland = smoothstep_unit((continent + 0.2) / 0.75);
	float basin = 1.0 - smoothstep_unit((continent + 0.05) / 0.55);
	float macro = (
		continent * 560.0
		+ fbm(sample_x, sample_z, 26000.0, seed, 4) * 430.0
		+ fbm(sample_x + 2300.0, sample_z - 1100.0, 12000.0, seed + 11, 3) * 140.0
	);
	float ridge = ridged_noise(sample_x * 0.8 + sample_z * 0.15, sample_z * 0.65 - sample_x * 0.1, 18000.0, seed + 37, 3);
	macro += ridge * (190.0 + upland * 230.0);
	macro -= basin * 170.0;
	return macro * params.macro_relief_scale;
}

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint z = gl_GlobalInvocationID.y;
	if (x >= params.count_x || z >= params.count_z) {
		return;
	}
	uint index = z * params.count_x + x;
	float world_x = params.origin_x + float(x) * params.step_m;
	float world_z = params.origin_z + float(z) * params.step_m;
	output_buffer.height[index] = macro_height(world_x, world_z);
}
"""


func _kernel_sample_shader() -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer Params {
	float origin_x;
	float origin_z;
	float step_m;
	float scale_m;
	float offset_u;
	float offset_v;
	uint count_x;
	uint count_z;
	uint rows;
	uint cols;
	int angle_i;
} params;

layout(set = 0, binding = 1, std430) readonly restrict buffer KernelValues {
	float values[];
} kernel_buffer;

layout(set = 0, binding = 2, std430) writeonly restrict buffer SampleOutput {
	float values[];
} output_buffer;

float fposmod_scalar(float value, float modulo_value) {
	return mod(mod(value, modulo_value) + modulo_value, modulo_value);
}

float bilinear_sample(float u, float v) {
	float mu = 1.0 - abs(fposmod_scalar(u, 2.0) - 1.0);
	float mv = 1.0 - abs(fposmod_scalar(v, 2.0) - 1.0);
	float px = mu * float(params.cols - 1u);
	float py = mv * float(params.rows - 1u);
	uint x0 = min(uint(floor(px)), params.cols - 1u);
	uint y0 = min(uint(floor(py)), params.rows - 1u);
	uint x1 = min(x0 + 1u, params.cols - 1u);
	uint y1 = min(y0 + 1u, params.rows - 1u);
	float tx = px - float(x0);
	float ty = py - float(y0);
	float a = kernel_buffer.values[y0 * params.cols + x0];
	float b = kernel_buffer.values[y0 * params.cols + x1];
	float c = kernel_buffer.values[y1 * params.cols + x0];
	float d = kernel_buffer.values[y1 * params.cols + x1];
	return mix(mix(a, b, tx), mix(c, d, tx), ty);
}

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint z = gl_GlobalInvocationID.y;
	if (x >= params.count_x || z >= params.count_z) {
		return;
	}
	float world_x = params.origin_x + float(x) * params.step_m;
	float world_z = params.origin_z + float(z) * params.step_m;
	float u = world_x / params.scale_m;
	float v = world_z / params.scale_m;
	if (params.angle_i == 1) {
		float old_u = u;
		u = v;
		v = -old_u;
	} else if (params.angle_i == 2) {
		u = -u;
		v = -v;
	} else if (params.angle_i == 3) {
		float old_u3 = u;
		u = -v;
		v = old_u3;
	}
	u += params.offset_u;
	v += params.offset_v;
	output_buffer.values[z * params.count_x + x] = bilinear_sample(u, v);
}
"""


func _provider_height_shader() -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

const int ENTRY_STRIDE = 16;

layout(set = 0, binding = 0, std430) readonly restrict buffer Params {
	float p[];
} params;

layout(set = 0, binding = 1, std430) readonly restrict buffer Entries {
	float e[];
} entries;

layout(set = 0, binding = 2, std430) readonly restrict buffer KernelValues {
	float values[];
} kernel_buffer;

layout(set = 0, binding = 3, std430) writeonly restrict buffer HeightOutput {
	float height[];
} output_buffer;

float param(int index) {
	return params.p[index];
}

float entry_at(int entry_index, int field_index) {
	return entries.e[entry_index * ENTRY_STRIDE + field_index];
}

float fade(float t) {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float smoothstep_unit(float t) {
	float v = clamp(t, 0.0, 1.0);
	return v * v * (3.0 - 2.0 * v);
}

float fposmod_scalar(float value, float modulo_value) {
	return mod(mod(value, modulo_value) + modulo_value, modulo_value);
}

uint hash_grid_u32(int ix, int iz, int world_seed, int salt) {
	uint n = (
		uint(ix) * 374761393u
		+ uint(iz) * 668265263u
		+ uint(world_seed) * 1442695041u
		+ uint(salt) * 69069u
	);
	uint mixed = n ^ (n >> 13u);
	uint product_hi;
	uint product_lo;
	umulExtended(mixed, 1274126177u, product_hi, product_lo);
	uint shifted_low = (product_lo >> 16u) | (product_hi << 16u);
	return product_lo ^ shifted_low;
}

float hash_grid(int ix, int iz, int world_seed, int salt) {
	return float(hash_grid_u32(ix, iz, world_seed, salt)) / 4294967295.0;
}

float value_noise(float x, float z, float scale_m, int world_seed, int salt) {
	float fx = x / scale_m;
	float fz = z / scale_m;
	int ix = int(floor(fx));
	int iz = int(floor(fz));
	float tx = fade(fx - float(ix));
	float tz = fade(fz - float(iz));
	float a = hash_grid(ix, iz, world_seed, salt);
	float b = hash_grid(ix + 1, iz, world_seed, salt);
	float c = hash_grid(ix, iz + 1, world_seed, salt);
	float d = hash_grid(ix + 1, iz + 1, world_seed, salt);
	return mix(mix(a, b, tx), mix(c, d, tx), tz) * 2.0 - 1.0;
}

float fbm(float x, float z, float scale_m, int world_seed, int octaves) {
	float total = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		total += value_noise(x, z, scale_m / float(1 << octave), world_seed, octave) * amp;
		norm += amp;
		amp *= 0.5;
	}
	return total / max(0.000001, norm);
}

float ridged_noise(float x, float z, float scale_m, int world_seed, int octaves) {
	float value = fbm(x, z, scale_m, world_seed, octaves);
	float ridged = 1.0 - abs(value);
	return ridged * ridged * 2.0 - 1.0;
}

float valley_mask(float x, float z, int world_seed) {
	float broad = ridged_noise(x + 5000.0, z - 3100.0, 18000.0, world_seed + 101, 4);
	float tributary = ridged_noise(x * 1.15 - z * 0.10, z * 0.9 + x * 0.08, 6200.0, world_seed + 211, 3);
	float combined = broad * 0.72 + tributary * 0.28;
	return smoothstep_unit((combined - 0.16) / 0.52);
}

float corner_weight_for(int corner_index, float tx, float tz) {
	if (corner_index == 0) {
		return (1.0 - tx) * (1.0 - tz);
	}
	if (corner_index == 1) {
		return tx * (1.0 - tz);
	}
	if (corner_index == 2) {
		return (1.0 - tx) * tz;
	}
	return tx * tz;
}

float sample_kernel_entry(int entry_index, float world_x, float world_z) {
	float scale_m = entry_at(entry_index, 6);
	int angle_i = int(entry_at(entry_index, 7) + 0.5);
	float u = world_x / scale_m;
	float v = world_z / scale_m;
	if (angle_i == 1) {
		float old_u = u;
		u = v;
		v = -old_u;
	} else if (angle_i == 2) {
		u = -u;
		v = -v;
	} else if (angle_i == 3) {
		float old_u3 = u;
		u = -v;
		v = old_u3;
	}
	u += entry_at(entry_index, 8);
	v += entry_at(entry_index, 9);
	uint rows = uint(entry_at(entry_index, 12) + 0.5);
	uint cols = uint(entry_at(entry_index, 13) + 0.5);
	uint value_offset = uint(entry_at(entry_index, 14) + 0.5);
	float mu = 1.0 - abs(fposmod_scalar(u, 2.0) - 1.0);
	float mv = 1.0 - abs(fposmod_scalar(v, 2.0) - 1.0);
	float px = mu * float(cols - 1u);
	float py = mv * float(rows - 1u);
	uint x0 = min(uint(floor(px)), cols - 1u);
	uint y0 = min(uint(floor(py)), rows - 1u);
	uint x1 = min(x0 + 1u, cols - 1u);
	uint y1 = min(y0 + 1u, rows - 1u);
	float tx = px - float(x0);
	float ty = py - float(y0);
	float a = kernel_buffer.values[value_offset + y0 * cols + x0];
	float b = kernel_buffer.values[value_offset + y0 * cols + x1];
	float c = kernel_buffer.values[value_offset + y1 * cols + x0];
	float d = kernel_buffer.values[value_offset + y1 * cols + x1];
	return mix(mix(a, b, tx), mix(c, d, tx), ty);
}

float provider_height(float world_x, float world_z) {
	int world_seed = int(param(6) + 0.5);
	float region_size_m = param(3);
	float base_rx = param(7);
	float base_rz = param(8);
	int entry_count = int(param(9) + 0.5);
	float macro_relief_scale = param(10);
	float regional_scale_multiplier = param(11);
	float valley_bias_strength = param(12);
	float sample_x = world_x / regional_scale_multiplier;
	float sample_z = world_z / regional_scale_multiplier;
	float continent = fbm(sample_x, sample_z, 52000.0, world_seed + 3, 4);
	float upland = smoothstep_unit((continent + 0.2) / 0.75);
	float basin = 1.0 - smoothstep_unit((continent + 0.05) / 0.55);
	float macro = (
		continent * 560.0
		+ fbm(sample_x, sample_z, 26000.0, world_seed, 4) * 430.0
		+ fbm(sample_x + 2300.0, sample_z - 1100.0, 12000.0, world_seed + 11, 3) * 140.0
	);
	float ridge = ridged_noise(sample_x * 0.8 + sample_z * 0.15, sample_z * 0.65 - sample_x * 0.1, 18000.0, world_seed + 37, 3);
	macro += ridge * (190.0 + upland * 230.0);
	macro -= basin * 170.0;
	macro *= macro_relief_scale;

	float gx = world_x / region_size_m;
	float gz = world_z / region_size_m;
	float tx = smoothstep_unit(gx - base_rx);
	float tz = smoothstep_unit(gz - base_rz);
	float relief = 0.0;
	float detail = 0.0;
	for (int entry_index = 0; entry_index < entry_count; entry_index++) {
		int corner_index = int(entry_at(entry_index, 0) + 0.5);
		float weight = corner_weight_for(corner_index, tx, tz) * entry_at(entry_index, 1);
		if (weight <= 0.00000001) {
			continue;
		}
		float runtime_weight = entry_at(entry_index, 2);
		float moderation = entry_at(entry_index, 3);
		float sampled = sample_kernel_entry(entry_index, world_x, world_z);
		relief += sampled * weight * runtime_weight * moderation * entry_at(entry_index, 4) * (0.58 + upland * 0.38) * entry_at(entry_index, 15) * entry_at(entry_index, 10);
		detail += (
			fbm(sample_x, sample_z, 3000.0, int(entry_at(entry_index, 11) + 0.5), 2)
			* weight
			* runtime_weight
			* moderation
			* entry_at(entry_index, 5)
			* 0.82
		);
	}
	float valleys = valley_mask(sample_x, sample_z, world_seed);
	float valley_cut = valleys * (110.0 + upland * 130.0) * valley_bias_strength;
	float valley_floor_noise = fbm(sample_x, sample_z, 4200.0, world_seed + 401, 2) * 24.0 * valleys;
	return macro + relief + detail - valley_cut + valley_floor_noise;
}

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint z = gl_GlobalInvocationID.y;
	uint count_x = uint(param(4) + 0.5);
	uint count_z = uint(param(5) + 0.5);
	if (x >= count_x || z >= count_z) {
		return;
	}
	float world_x = param(0) + float(x) * param(2);
	float world_z = param(1) + float(z) * param(2);
	output_buffer.height[z * count_x + x] = provider_height(world_x, world_z);
}
"""


func _free_rids(rids: Array) -> void:
	if _rd == null:
		return
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			_rd.free_rid(rid)
