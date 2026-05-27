class_name TerrainGpuProviderPageTextureBackend
extends RefCounted

const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")

var _shader_rid: RID
var _pipeline_rid: RID
var _compile_count: int = 0
var _dispatch_count: int = 0
var _last_error: String = ""


func clear(rd: RenderingDevice) -> void:
	if rd == null:
		_shader_rid = RID()
		_pipeline_rid = RID()
		return
	if _pipeline_rid.is_valid():
		rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		rd.free_rid(_shader_rid)
	_shader_rid = RID()
	_pipeline_rid = RID()


func create_height_texture(rd: RenderingDevice, descriptor: Dictionary) -> Dictionary:
	var validation: String = _validate_descriptor(rd, descriptor)
	if not validation.is_empty():
		_last_error = validation
		return {"status": "fail", "error": validation}
	var pipeline_result: Dictionary = _ensure_pipeline(rd)
	if pipeline_result.get("status", "fail") != "pass":
		return pipeline_result

	var side: int = int(descriptor.get("count_x", 0))
	var params: PackedByteArray = descriptor["params_bytes"] as PackedByteArray
	var entries_bytes: PackedByteArray = descriptor["entry_bytes"] as PackedByteArray
	var kernel_bytes: PackedByteArray = descriptor["kernel_bytes"] as PackedByteArray
	var zero_height := PackedByteArray()
	zero_height.resize(side * side * 4)

	var params_buffer: RID = rd.storage_buffer_create(params.size(), params)
	var entries_buffer: RID = rd.storage_buffer_create(entries_bytes.size(), entries_bytes)
	var kernel_buffer: RID = rd.storage_buffer_create(kernel_bytes.size(), kernel_bytes)
	var height_rid: RID = _create_height_texture_rid(rd, side, zero_height)
	if not params_buffer.is_valid() or not entries_buffer.is_valid() or not kernel_buffer.is_valid() or not height_rid.is_valid():
		_free_rids(rd, [height_rid, kernel_buffer, entries_buffer, params_buffer])
		_last_error = "gpu_provider_texture_resource_create_failed"
		return {"status": "fail", "error": _last_error}

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
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	height_uniform.binding = 3
	height_uniform.add_id(height_rid)
	var uniform_set: RID = rd.uniform_set_create([params_uniform, entries_uniform, kernel_uniform, height_uniform], _shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids(rd, [height_rid, kernel_buffer, entries_buffer, params_buffer])
		_last_error = "gpu_provider_texture_uniform_set_failed"
		return {"status": "fail", "error": _last_error}

	var compute_list: int = rd.compute_list_begin()
	if compute_list < 0:
		_free_rids(rd, [uniform_set, height_rid, kernel_buffer, entries_buffer, params_buffer])
		_last_error = "gpu_provider_texture_compute_begin_failed"
		return {"status": "fail", "error": _last_error}
	rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(float(side) / 8.0)), int(ceil(float(side) / 8.0)), 1)
	rd.compute_list_end()
	_dispatch_count += 1

	return {
		"status": "pass",
		"schema": "worldgen9.gpu_provider_page_texture.v1",
		"vertices_per_side": side,
		"spacing_m": float(descriptor.get("step_m", 0.0)),
		"height_texture_rid": height_rid,
		"height_texture_owned_by_residency": true,
		"height_bytes": side * side * 4,
		"height_image_only": true,
		"height_texture_mode": "gpu_provider_rd",
		"texture_payload_mode": "gpu_provider_rd_height_texture",
		"rd_owned_rids": [uniform_set, params_buffer, entries_buffer, kernel_buffer],
		"entry_count": int(descriptor.get("entry_count", 0)),
		"kernel_value_count": int(descriptor.get("kernel_value_count", 0)),
	}


func debug_state() -> Dictionary:
	return {
		"compile_count": _compile_count,
		"dispatch_count": _dispatch_count,
		"last_error": _last_error,
	}


func _validate_descriptor(rd: RenderingDevice, descriptor: Dictionary) -> String:
	if rd == null:
		return "rendering_device_unavailable"
	if descriptor.get("status", "fail") != "pass":
		return "descriptor_status:%s" % str(descriptor.get("status", "missing"))
	if str(descriptor.get("schema", "")) != "worldgen9.gpu_provider_page_descriptor.v1":
		return "descriptor_schema:%s" % str(descriptor.get("schema", ""))
	var count_x: int = int(descriptor.get("count_x", 0))
	var count_z: int = int(descriptor.get("count_z", 0))
	if count_x < 1 or count_z < 1 or count_x != count_z:
		return "count:%d,%d" % [count_x, count_z]
	var step_m: float = float(descriptor.get("step_m", 0.0))
	if not is_finite(step_m) or step_m <= 0.0:
		return "step_m:%f" % step_m
	var params: PackedByteArray = descriptor.get("params_bytes", PackedByteArray()) as PackedByteArray
	var entries_bytes: PackedByteArray = descriptor.get("entry_bytes", PackedByteArray()) as PackedByteArray
	var kernel_bytes: PackedByteArray = descriptor.get("kernel_bytes", PackedByteArray()) as PackedByteArray
	if params.size() != 64:
		return "params_bytes:%d" % params.size()
	if entries_bytes.size() <= 0 or entries_bytes.size() % (16 * 4) != 0:
		return "entry_bytes:%d" % entries_bytes.size()
	if kernel_bytes.size() <= 0 or kernel_bytes.size() % 4 != 0:
		return "kernel_bytes:%d" % kernel_bytes.size()
	return ""


func _ensure_pipeline(rd: RenderingDevice) -> Dictionary:
	if _shader_rid.is_valid() and _pipeline_rid.is_valid():
		return {"status": "pass"}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _provider_height_texture_shader()
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		_last_error = "gpu_provider_texture_shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null")
		return {"status": "fail", "error": _last_error}
	_shader_rid = rd.shader_create_from_spirv(shader_spirv)
	if not _shader_rid.is_valid():
		_last_error = "gpu_provider_texture_shader_create_failed"
		return {"status": "fail", "error": _last_error}
	_pipeline_rid = rd.compute_pipeline_create(_shader_rid)
	if not _pipeline_rid.is_valid():
		rd.free_rid(_shader_rid)
		_shader_rid = RID()
		_last_error = "gpu_provider_texture_pipeline_create_failed"
		return {"status": "fail", "error": _last_error}
	_compile_count += 1
	return {"status": "pass"}


func _provider_height_texture_shader() -> String:
	var helper = TerrainGpuHeightPageBackendScript.new()
	var source: String = helper._provider_height_shader()
	source = source.replace(
		"layout(set = 0, binding = 3, std430) writeonly restrict buffer HeightOutput {\n\tfloat height[];\n} output_buffer;",
		"layout(r32f, set = 0, binding = 3) uniform writeonly image2D height_image;"
	)
	source = source.replace(
		"output_buffer.height[z * count_x + x] = provider_height(world_x, world_z);",
		"imageStore(height_image, ivec2(int(x), int(z)), vec4(provider_height(world_x, world_z), 0.0, 0.0, 1.0));"
	)
	return source


func _create_height_texture_rid(rd: RenderingDevice, side: int, data: PackedByteArray) -> RID:
	var format := RDTextureFormat.new()
	format.width = side
	format.height = side
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	return rd.texture_create(format, RDTextureView.new(), [data])


func _free_rids(rd: RenderingDevice, rids: Array) -> void:
	if rd == null:
		return
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			rd.free_rid(rid)
