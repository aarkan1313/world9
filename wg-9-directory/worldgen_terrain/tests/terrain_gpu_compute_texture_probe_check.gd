extends SceneTree


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_compute_to_texture(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-compute-texture-probe] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-compute-texture-probe] status=pass")
	quit(0)


func _check_compute_to_texture(errors: Array[String]) -> void:
	if not ClassDB.class_exists("Texture2DRD"):
		errors.append("texture2drd_class_missing")
		return
	if not RenderingServer.has_method("get_rendering_device"):
		errors.append("rendering_server_get_rendering_device_missing")
		return
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd == null:
		print("[wg9-gpu-compute-texture-probe] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	var side := 8
	var initial_data := PackedByteArray()
	initial_data.resize(side * side * 4)
	var texture_rid: RID = _create_storage_texture(rd, side, initial_data)
	if not texture_rid.is_valid():
		errors.append("storage_texture_create_failed")
		return
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _compute_texture_shader()
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		rd.free_rid(texture_rid)
		errors.append("shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null"))
		return
	var shader_rid: RID = rd.shader_create_from_spirv(shader_spirv)
	var pipeline_rid: RID = rd.compute_pipeline_create(shader_rid)
	if not shader_rid.is_valid() or not pipeline_rid.is_valid():
		_free_rids(rd, [pipeline_rid, shader_rid, texture_rid])
		errors.append("pipeline_create_failed")
		return
	var texture_uniform := RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 0
	texture_uniform.add_id(texture_rid)
	var uniform_set: RID = rd.uniform_set_create([texture_uniform], shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids(rd, [uniform_set, pipeline_rid, shader_rid, texture_rid])
		errors.append("uniform_set_create_failed")
		return
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	var readback: PackedByteArray = rd.texture_get_data(texture_rid, 0)
	var max_delta := 0.0
	for z in range(side):
		for x in range(side):
			var expected: float = float(x) * 0.25 + float(z) * 0.5
			var actual: float = readback.decode_float((z * side + x) * 4)
			max_delta = maxf(max_delta, absf(expected - actual))
	_free_rids(rd, [uniform_set, pipeline_rid, shader_rid, texture_rid])
	if max_delta > 0.00001:
		errors.append("max_delta:%f" % max_delta)


func _create_storage_texture(rd: RenderingDevice, side: int, data: PackedByteArray) -> RID:
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
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	return rd.texture_create(format, RDTextureView.new(), [data])


func _compute_texture_shader() -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform writeonly image2D out_tex;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	float value = float(pixel.x) * 0.25 + float(pixel.y) * 0.5;
	imageStore(out_tex, pixel, vec4(value, 0.0, 0.0, 1.0));
}
"""


func _free_rids(rd: RenderingDevice, rids: Array) -> void:
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			rd.free_rid(rid)
