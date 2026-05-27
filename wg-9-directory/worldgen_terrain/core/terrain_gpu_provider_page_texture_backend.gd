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

	var width: int = int(descriptor.get("count_x", 0))
	var height: int = int(descriptor.get("count_z", 0))
	var zero_height := PackedByteArray()
	zero_height.resize(width * height * 4)
	var height_rid: RID = _create_height_texture_rid(rd, width, height, zero_height)
	if not height_rid.is_valid():
		_last_error = "gpu_provider_texture_resource_create_failed"
		return {"status": "fail", "error": _last_error}
	var dispatch: Dictionary = _dispatch_descriptor_to_height_texture(rd, descriptor, height_rid, 0, 0)
	if dispatch.get("status", "fail") != "pass":
		_free_rids(rd, [height_rid])
		return dispatch

	return {
		"status": "pass",
		"schema": "worldgen9.gpu_provider_page_texture.v1",
		"vertices_per_side": width,
		"spacing_m": float(descriptor.get("step_m", 0.0)),
		"height_texture_rid": height_rid,
		"height_texture_owned_by_residency": true,
		"height_bytes": width * height * 4,
		"height_image_only": true,
		"height_texture_mode": "gpu_provider_rd",
		"texture_payload_mode": "gpu_provider_rd_height_texture",
		"rd_owned_rids": dispatch.get("rd_owned_rids", []) as Array,
		"entry_count": int(descriptor.get("entry_count", 0)),
		"kernel_value_count": int(descriptor.get("kernel_value_count", 0)),
		"block_count": 1,
	}


func create_height_texture_from_prepared_request(
	rd: RenderingDevice,
	prepared_request: Dictionary,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	world_seed: int,
	region_size_m: float
) -> Dictionary:
	var descriptor_builder = TerrainGpuHeightPageBackendScript.new()
	var descriptor: Dictionary = descriptor_builder.build_prepared_provider_page_descriptor(
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
	return create_height_texture(rd, descriptor)


func create_height_texture_from_prepared_blocks(
	rd: RenderingDevice,
	blocks: Array,
	width: int,
	height: int,
	step_m: float,
	world_seed: int,
	region_size_m: float
) -> Dictionary:
	if rd == null:
		return {"status": "fail", "error": "rendering_device_unavailable"}
	if width < 1 or height < 1:
		return {"status": "fail", "error": "texture_size:%d,%d" % [width, height]}
	if blocks.is_empty():
		return {"status": "fail", "error": "blocks_empty"}
	var pipeline_result: Dictionary = _ensure_pipeline(rd)
	if pipeline_result.get("status", "fail") != "pass":
		return pipeline_result
	var zero_height := PackedByteArray()
	zero_height.resize(width * height * 4)
	var height_rid: RID = _create_height_texture_rid(rd, width, height, zero_height)
	if not height_rid.is_valid():
		_last_error = "gpu_provider_texture_resource_create_failed"
		return {"status": "fail", "error": _last_error}
	var descriptor_builder = TerrainGpuHeightPageBackendScript.new()
	var owned_rids: Array = []
	var total_entries := 0
	var total_kernel_values := 0
	for block_value in blocks:
		var block: Dictionary = block_value as Dictionary
		var descriptor: Dictionary = descriptor_builder.build_prepared_provider_page_descriptor(
			block.get("prepared_request", {}) as Dictionary,
			float(block.get("origin_x", 0.0)),
			float(block.get("origin_z", 0.0)),
			step_m,
			int(block.get("count_x", 0)),
			int(block.get("count_z", 0)),
			world_seed,
			region_size_m
		)
		if descriptor.get("status", "fail") != "pass":
			_free_rids(rd, owned_rids)
			_free_rids(rd, [height_rid])
			return descriptor
		var dispatch: Dictionary = _dispatch_descriptor_to_height_texture(
			rd,
			descriptor,
			height_rid,
			int(block.get("offset_x", 0)),
			int(block.get("offset_z", 0))
		)
		if dispatch.get("status", "fail") != "pass":
			_free_rids(rd, owned_rids)
			_free_rids(rd, [height_rid])
			return dispatch
		for rid_value in dispatch.get("rd_owned_rids", []) as Array:
			owned_rids.append(rid_value)
		total_entries += int(descriptor.get("entry_count", 0))
		total_kernel_values += int(descriptor.get("kernel_value_count", 0))
	return {
		"status": "pass",
		"schema": "worldgen9.gpu_provider_page_texture.v1",
		"vertices_per_side": width,
		"spacing_m": step_m,
		"height_texture_rid": height_rid,
		"height_texture_owned_by_residency": true,
		"height_bytes": width * height * 4,
		"height_image_only": true,
		"height_texture_mode": "gpu_provider_rd",
		"texture_payload_mode": "gpu_provider_rd_height_texture",
		"rd_owned_rids": owned_rids,
		"entry_count": total_entries,
		"kernel_value_count": total_kernel_values,
		"block_count": blocks.size(),
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
	if count_x < 1 or count_z < 1:
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


func _dispatch_descriptor_to_height_texture(
	rd: RenderingDevice,
	descriptor: Dictionary,
	height_rid: RID,
	offset_x: int,
	offset_z: int
) -> Dictionary:
	var validation: String = _validate_descriptor(rd, descriptor)
	if not validation.is_empty():
		_last_error = validation
		return {"status": "fail", "error": validation}
	if not height_rid.is_valid():
		_last_error = "height_texture_invalid"
		return {"status": "fail", "error": _last_error}
	var params: PackedByteArray = _params_with_write_offset(descriptor["params_bytes"] as PackedByteArray, offset_x, offset_z)
	var entries_bytes: PackedByteArray = descriptor["entry_bytes"] as PackedByteArray
	var kernel_bytes: PackedByteArray = descriptor["kernel_bytes"] as PackedByteArray
	var params_buffer: RID = rd.storage_buffer_create(params.size(), params)
	var entries_buffer: RID = rd.storage_buffer_create(entries_bytes.size(), entries_bytes)
	var kernel_buffer: RID = rd.storage_buffer_create(kernel_bytes.size(), kernel_bytes)
	if not params_buffer.is_valid() or not entries_buffer.is_valid() or not kernel_buffer.is_valid():
		_free_rids(rd, [kernel_buffer, entries_buffer, params_buffer])
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
		_free_rids(rd, [kernel_buffer, entries_buffer, params_buffer])
		_last_error = "gpu_provider_texture_uniform_set_failed"
		return {"status": "fail", "error": _last_error}
	var count_x: int = int(descriptor.get("count_x", 0))
	var count_z: int = int(descriptor.get("count_z", 0))
	var compute_list: int = rd.compute_list_begin()
	if compute_list < 0:
		_free_rids(rd, [uniform_set, kernel_buffer, entries_buffer, params_buffer])
		_last_error = "gpu_provider_texture_compute_begin_failed"
		return {"status": "fail", "error": _last_error}
	rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(float(count_x) / 8.0)), int(ceil(float(count_z) / 8.0)), 1)
	rd.compute_list_end()
	_dispatch_count += 1
	return {
		"status": "pass",
		"rd_owned_rids": [uniform_set, params_buffer, entries_buffer, kernel_buffer],
	}


func _params_with_write_offset(params: PackedByteArray, offset_x: int, offset_z: int) -> PackedByteArray:
	var copy := PackedByteArray()
	copy.resize(params.size())
	for index in range(params.size()):
		copy[index] = params[index]
	if copy.size() >= 60:
		copy.encode_float(52, float(offset_x))
		copy.encode_float(56, float(offset_z))
	return copy


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
		"imageStore(height_image, ivec2(int(x) + int(param(13) + 0.5), int(z) + int(param(14) + 0.5)), vec4(provider_height(world_x, world_z), 0.0, 0.0, 1.0));"
	)
	return source


func _create_height_texture_rid(rd: RenderingDevice, width: int, height: int, data: PackedByteArray) -> RID:
	var format := RDTextureFormat.new()
	format.width = width
	format.height = height
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
