extends SceneTree

const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")

const VERTICES_PER_SIDE := 33
const STEP_M := 64.0
const FLOAT_EPSILON := 0.000001


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return
	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	var height := _fixture_height()
	var native: Dictionary = backend.call(
		"build_mesh_payload_from_height",
		height,
		VERTICES_PER_SIDE,
		STEP_M
	) as Dictionary
	if native.get("status", "fail") != "pass":
		errors.append("native_payload_failed:%s" % str(native))
		_report_and_quit(errors)
		return
	var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(height, VERTICES_PER_SIDE, STEP_M)
	var native_vertices: PackedVector3Array = native["vertices"] as PackedVector3Array
	var native_normals: PackedVector3Array = native["normals"] as PackedVector3Array
	var native_uvs: PackedVector2Array = native["uvs"] as PackedVector2Array
	var native_indices: PackedInt32Array = native["indices"] as PackedInt32Array
	var vertex_delta: float = _compare_vec3(native_vertices, arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var normal_delta: float = _compare_vec3(native_normals, arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
	var uv_delta: float = _compare_vec2(native_uvs, arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array)
	if vertex_delta > FLOAT_EPSILON:
		errors.append("vertex_delta:%.9f" % vertex_delta)
	if normal_delta > FLOAT_EPSILON:
		errors.append("normal_delta:%.9f" % normal_delta)
	if uv_delta > FLOAT_EPSILON:
		errors.append("uv_delta:%.9f" % uv_delta)
	if native_indices != (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		errors.append("index_mismatch")
	if native_vertices.size() != height.size():
		errors.append("vertex_size:%d" % native_vertices.size())
	if native_indices.size() != (VERTICES_PER_SIDE - 1) * (VERTICES_PER_SIDE - 1) * 6:
		errors.append("index_size:%d" % native_indices.size())
	_check_invalid_native_inputs(backend, height, errors)
	if not errors.is_empty():
		_report_and_quit(errors)
		return
	print("[wg9-native-mesh-payload] status=pass vertices=%d indices=%d vertex_delta=%.9f normal_delta=%.9f" % [
		native_vertices.size(),
		native_indices.size(),
		vertex_delta,
		normal_delta,
	])
	quit(0)


func _fixture_height() -> PackedFloat32Array:
	var height := PackedFloat32Array()
	height.resize(VERTICES_PER_SIDE * VERTICES_PER_SIDE)
	for z in range(VERTICES_PER_SIDE):
		for x in range(VERTICES_PER_SIDE):
			var index: int = z * VERTICES_PER_SIDE + x
			height[index] = sin(float(x) * 0.17) * 20.0 + cos(float(z) * 0.11) * 12.0
	return height


func _check_invalid_native_inputs(backend: Object, height: PackedFloat32Array, errors: Array[String]) -> void:
	var zero_step: Dictionary = backend.call("build_mesh_payload_from_height", height, VERTICES_PER_SIDE, 0.0) as Dictionary
	if zero_step.get("status", "pass") != "fail":
		errors.append("zero_step_passed:%s" % str(zero_step))
	var bad_height := height.duplicate()
	bad_height[0] = INF
	var non_finite: Dictionary = backend.call("build_mesh_payload_from_height", bad_height, VERTICES_PER_SIDE, STEP_M) as Dictionary
	if non_finite.get("status", "pass") != "fail":
		errors.append("non_finite_height_passed:%s" % str(non_finite))


func _compare_vec3(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var max_delta := 0.0
	for index in range(a.size()):
		max_delta = max(max_delta, abs(a[index].x - b[index].x))
		max_delta = max(max_delta, abs(a[index].y - b[index].y))
		max_delta = max(max_delta, abs(a[index].z - b[index].z))
	return max_delta


func _compare_vec2(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var max_delta := 0.0
	for index in range(a.size()):
		max_delta = max(max_delta, abs(a[index].x - b[index].x))
		max_delta = max(max_delta, abs(a[index].y - b[index].y))
	return max_delta


func _report_and_quit(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-native-mesh-payload] status=fail errors=%d" % errors.size())
	quit(1)
