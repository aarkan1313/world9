class_name TerrainGpuComputeProbe
extends RefCounted

const TerrainGpuPageNormalBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_page_normal_backend.gd")


func run_float_buffer_probe(count: int = 64) -> Dictionary:
	count = clampi(count, 1, 4096)
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd == null:
		return {
			"status": "unsupported",
			"error": "rendering_device_unavailable",
			"headless_runtime_note": "Godot headless checks can run without a RenderingDevice; use non-headless GPU probes for actual compute validation.",
		}

	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _float_buffer_probe_shader()
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		rd.free()
		return {
			"status": "fail",
			"error": "shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null"),
		}
	var shader_rid: RID = rd.shader_create_from_spirv(shader_spirv)
	if not shader_rid.is_valid():
		rd.free()
		return {"status": "fail", "error": "shader_create_failed"}

	var input_bytes := PackedByteArray()
	var output_bytes := PackedByteArray()
	input_bytes.resize(count * 4)
	output_bytes.resize(count * 4)
	for index in range(count):
		input_bytes.encode_float(index * 4, float(index) * 0.25 - 8.0)
		output_bytes.encode_float(index * 4, 0.0)

	var input_buffer: RID = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	var output_buffer: RID = rd.storage_buffer_create(output_bytes.size(), output_bytes)
	if not input_buffer.is_valid() or not output_buffer.is_valid():
		_free_rids(rd, [output_buffer, input_buffer, shader_rid])
		rd.free()
		return {"status": "fail", "error": "storage_buffer_create_failed"}

	var input_uniform := RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_uniform.binding = 0
	input_uniform.add_id(input_buffer)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)
	var uniform_set: RID = rd.uniform_set_create([input_uniform, output_uniform], shader_rid, 0)
	var pipeline: RID = rd.compute_pipeline_create(shader_rid)
	if not uniform_set.is_valid() or not pipeline.is_valid():
		_free_rids(rd, [pipeline, uniform_set, output_buffer, input_buffer, shader_rid])
		rd.free()
		return {"status": "fail", "error": "pipeline_create_failed"}

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(float(count) / 64.0)), 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	var readback: PackedByteArray = rd.buffer_get_data(output_buffer)
	var max_delta := 0.0
	for index in range(count):
		var expected: float = input_bytes.decode_float(index * 4) * 2.0 + 1.0
		var actual: float = readback.decode_float(index * 4)
		max_delta = maxf(max_delta, absf(expected - actual))
	_free_rids(rd, [pipeline, uniform_set, output_buffer, input_buffer, shader_rid])
	rd.free()
	if max_delta > 0.00001:
		return {"status": "fail", "error": "max_delta:%f" % max_delta, "max_delta": max_delta}
	return {
		"status": "pass",
		"count": count,
		"workgroups_x": int(ceil(float(count) / 64.0)),
		"max_delta": max_delta,
	}


func run_height_normal_probe(side: int = 16, step_m: float = 2.0) -> Dictionary:
	side = clampi(side, 4, 128)
	step_m = max(0.000001, step_m)
	var height_bytes := PackedByteArray()
	height_bytes.resize(side * side * 4)
	for z in range(side):
		for x in range(side):
			var index: int = z * side + x
			var height: float = sin(float(x) * 0.31) * 17.0 + cos(float(z) * 0.23) * 11.0 + float(x - z) * 0.75
			height_bytes.encode_float(index * 4, height)
	var compute_result: Dictionary = compute_normal_image_data_from_height_bytes(height_bytes, side, step_m)
	if compute_result.get("status", "fail") != "pass":
		return compute_result
	var readback: PackedByteArray = compute_result.get("normal_image_data", PackedByteArray()) as PackedByteArray
	var max_delta := 0.0
	for z in range(side):
		for x in range(side):
			var index: int = z * side + x
			var expected := _encoded_normal_from_height_bytes(height_bytes, side, x, z, step_m)
			var offset: int = index * 12
			var actual := Vector3(
				readback.decode_float(offset),
				readback.decode_float(offset + 4),
				readback.decode_float(offset + 8)
			)
			max_delta = maxf(max_delta, absf(expected.x - actual.x))
			max_delta = maxf(max_delta, absf(expected.y - actual.y))
			max_delta = maxf(max_delta, absf(expected.z - actual.z))
	if max_delta > 0.0001:
		return {"status": "fail", "error": "normal_max_delta:%f" % max_delta, "max_delta": max_delta}
	return {
		"status": "pass",
		"side": side,
		"step_m": step_m,
		"workgroups_x": int(ceil(float(side) / 8.0)),
		"workgroups_y": int(ceil(float(side) / 8.0)),
		"max_delta": max_delta,
		"normal_image_data_bytes": readback.size(),
		"normal_image_format": str(compute_result.get("normal_image_format", "")),
	}


func compute_normal_image_data_from_height_bytes(height_data: PackedByteArray, side: int, step_m: float) -> Dictionary:
	var backend = TerrainGpuPageNormalBackendScript.new()
	var result: Dictionary = backend.compute_normal_image_data_from_height_bytes(height_data, side, step_m)
	backend.shutdown()
	return result


func _float_buffer_probe_shader() -> String:
	return """
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer InputBuffer {
	float data[];
} input_buffer;

layout(set = 0, binding = 1, std430) writeonly restrict buffer OutputBuffer {
	float data[];
} output_buffer;

void main() {
	uint index = gl_GlobalInvocationID.x;
	output_buffer.data[index] = input_buffer.data[index] * 2.0 + 1.0;
}
"""


func _encoded_normal_from_height_bytes(height_bytes: PackedByteArray, side: int, x: int, z: int, step_m: float) -> Vector3:
	var left: float = _height_at(height_bytes, side, maxi(0, x - 1), z)
	var right: float = _height_at(height_bytes, side, mini(side - 1, x + 1), z)
	var up: float = _height_at(height_bytes, side, x, maxi(0, z - 1))
	var down: float = _height_at(height_bytes, side, x, mini(side - 1, z + 1))
	var normal := Vector3(left - right, step_m * 2.0, up - down).normalized()
	return normal * 0.5 + Vector3(0.5, 0.5, 0.5)


func _height_at(height_bytes: PackedByteArray, side: int, x: int, z: int) -> float:
	return height_bytes.decode_float((z * side + x) * 4)


func _free_rids(rd: RenderingDevice, rids: Array) -> void:
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			rd.free_rid(rid)
