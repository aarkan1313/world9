class_name TerrainGpuPageNormalBackend
extends RefCounted

var _rd: RenderingDevice
var _shader_rids: Dictionary = {}
var _pipeline_rids: Dictionary = {}
var _compile_count: int = 0
var _dispatch_count: int = 0
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
	return {"status": "pass"}


func shutdown() -> void:
	if _rd == null:
		return
	for value in _pipeline_rids.values():
		var rid: RID = value as RID
		if rid.is_valid():
			_rd.free_rid(rid)
	_pipeline_rids.clear()
	for value in _shader_rids.values():
		var rid: RID = value as RID
		if rid.is_valid():
			_rd.free_rid(rid)
	_shader_rids.clear()
	_rd.free()
	_rd = null


func compute_normal_image_data_from_height_bytes(height_data: PackedByteArray, side: int, step_m: float) -> Dictionary:
	side = clampi(side, 2, 4096)
	step_m = max(0.000001, step_m)
	var expected_height_bytes: int = side * side * 4
	if height_data.size() != expected_height_bytes:
		return {"status": "fail", "error": "height_bytes:%d expected:%d" % [height_data.size(), expected_height_bytes]}
	var setup_result: Dictionary = setup()
	if setup_result.get("status", "fail") != "pass":
		return setup_result
	var pipeline_result: Dictionary = _pipeline_for(side, step_m)
	if pipeline_result.get("status", "fail") != "pass":
		return pipeline_result
	var shader_rid: RID = pipeline_result["shader_rid"] as RID
	var pipeline_rid: RID = pipeline_result["pipeline_rid"] as RID

	var normal_data := PackedByteArray()
	normal_data.resize(side * side * 12)
	var height_buffer: RID = _rd.storage_buffer_create(height_data.size(), height_data)
	var normal_buffer: RID = _rd.storage_buffer_create(normal_data.size(), normal_data)
	if not height_buffer.is_valid() or not normal_buffer.is_valid():
		_free_rids([normal_buffer, height_buffer])
		return {"status": "fail", "error": "storage_buffer_create_failed"}

	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	height_uniform.binding = 0
	height_uniform.add_id(height_buffer)
	var normal_uniform := RDUniform.new()
	normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	normal_uniform.binding = 1
	normal_uniform.add_id(normal_buffer)
	var uniform_set: RID = _rd.uniform_set_create([height_uniform, normal_uniform], shader_rid, 0)
	if not uniform_set.is_valid():
		_free_rids([uniform_set, normal_buffer, height_buffer])
		return {"status": "fail", "error": "uniform_set_create_failed"}

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, int(ceil(float(side) / 8.0)), int(ceil(float(side) / 8.0)), 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	_dispatch_count += 1

	var readback: PackedByteArray = _rd.buffer_get_data(normal_buffer)
	_free_rids([uniform_set, normal_buffer, height_buffer])
	return {
		"status": "pass",
		"normal_image_data": readback,
		"normal_image_format": "rgbf",
		"vertices_per_side": side,
		"step_m": step_m,
		"workgroups_x": int(ceil(float(side) / 8.0)),
		"workgroups_y": int(ceil(float(side) / 8.0)),
	}


func debug_state() -> Dictionary:
	return {
		"available": _rd != null,
		"compile_count": _compile_count,
		"dispatch_count": _dispatch_count,
		"shader_count": _shader_rids.size(),
		"pipeline_count": _pipeline_rids.size(),
		"last_error": _last_error,
	}


func _pipeline_for(side: int, step_m: float) -> Dictionary:
	var key: String = "%d:%.9f" % [side, step_m]
	if _shader_rids.has(key) and _pipeline_rids.has(key):
		return {
			"status": "pass",
			"shader_rid": _shader_rids[key] as RID,
			"pipeline_rid": _pipeline_rids[key] as RID,
		}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _height_normal_shader(side, step_m)
	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		_last_error = "shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null")
		return {"status": "fail", "error": _last_error}
	var shader_rid: RID = _rd.shader_create_from_spirv(shader_spirv)
	if not shader_rid.is_valid():
		_last_error = "shader_create_failed"
		return {"status": "fail", "error": _last_error}
	var pipeline_rid: RID = _rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		_rd.free_rid(shader_rid)
		_last_error = "pipeline_create_failed"
		return {"status": "fail", "error": _last_error}
	_shader_rids[key] = shader_rid
	_pipeline_rids[key] = pipeline_rid
	_compile_count += 1
	return {"status": "pass", "shader_rid": shader_rid, "pipeline_rid": pipeline_rid}


func _height_normal_shader(side: int, step_m: float) -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

const uint SIDE = %du;
const float STEP_M = %.9f;

layout(set = 0, binding = 0, std430) readonly restrict buffer HeightBuffer {
	float height[];
} height_buffer;

layout(set = 0, binding = 1, std430) writeonly restrict buffer NormalBuffer {
	float normal[];
} normal_buffer;

float sample_height(uint x, uint z) {
	x = clamp(x, 0u, SIDE - 1u);
	z = clamp(z, 0u, SIDE - 1u);
	return height_buffer.height[z * SIDE + x];
}

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint z = gl_GlobalInvocationID.y;
	if (x >= SIDE || z >= SIDE) {
		return;
	}
	float left = sample_height(x > 0u ? x - 1u : 0u, z);
	float right = sample_height(min(x + 1u, SIDE - 1u), z);
	float up = sample_height(x, z > 0u ? z - 1u : 0u);
	float down = sample_height(x, min(z + 1u, SIDE - 1u));
	vec3 n = normalize(vec3(left - right, STEP_M * 2.0, up - down));
	vec3 encoded = n * 0.5 + vec3(0.5);
	uint base = (z * SIDE + x) * 3u;
	normal_buffer.normal[base] = encoded.x;
	normal_buffer.normal[base + 1u] = encoded.y;
	normal_buffer.normal[base + 2u] = encoded.z;
}
""" % [side, step_m]


func _free_rids(rids: Array) -> void:
	if _rd == null:
		return
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			_rd.free_rid(rid)
