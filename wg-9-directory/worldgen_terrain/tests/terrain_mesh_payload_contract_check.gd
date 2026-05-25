extends SceneTree

const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")

const VERTICES_PER_SIDE := 33
const STEP_M := 64.0
const FLOAT_EPSILON := 0.000001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var height := PackedFloat32Array()
	height.resize(VERTICES_PER_SIDE * VERTICES_PER_SIDE)
	for z in range(VERTICES_PER_SIDE):
		for x in range(VERTICES_PER_SIDE):
			var index: int = z * VERTICES_PER_SIDE + x
			height[index] = sin(float(x) * 0.17) * 20.0 + cos(float(z) * 0.11) * 12.0
	var direct_vertices: PackedVector3Array = TerrainMeshBuilderScript.build_vertices(height, VERTICES_PER_SIDE, STEP_M)
	var layout: PackedVector2Array = TerrainMeshBuilderScript.build_layout_xz(VERTICES_PER_SIDE, STEP_M)
	var layout_again: PackedVector2Array = TerrainMeshBuilderScript.build_layout_xz(VERTICES_PER_SIDE, STEP_M)
	var layout_vertices: PackedVector3Array = TerrainMeshBuilderScript.build_vertices_from_layout(height, layout)
	var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(height, VERTICES_PER_SIDE, STEP_M)
	var mesh: ArrayMesh = TerrainMeshBuilderScript.build_array_mesh(arrays)
	var max_vertex_delta := _compare_vertices(direct_vertices, layout_vertices)
	if max_vertex_delta > FLOAT_EPSILON:
		errors.append("layout_vertex_delta:%.9f" % max_vertex_delta)
	if layout.size() != layout_again.size():
		errors.append("layout_cache_size")
	if layout[layout.size() - 1] != layout_again[layout_again.size() - 1]:
		errors.append("layout_cache_value")
	TerrainMeshBuilderScript.build_layout_xz(VERTICES_PER_SIDE, 1.0)
	var near_step_layout: PackedVector2Array = TerrainMeshBuilderScript.build_layout_xz(VERTICES_PER_SIDE, 1.0000004)
	var near_step_edge: float = near_step_layout[near_step_layout.size() - 1].x
	if near_step_edge <= float(VERTICES_PER_SIDE - 1) + FLOAT_EPSILON:
		errors.append("layout_cache_step_alias:%.9f" % near_step_edge)
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != height.size():
		errors.append("array_vertex_size")
	if (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() != height.size():
		errors.append("array_normal_size")
	if (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() != height.size():
		errors.append("array_uv_size")
	if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() != (VERTICES_PER_SIDE - 1) * (VERTICES_PER_SIDE - 1) * 6:
		errors.append("array_index_size")
	if mesh == null or mesh.get_surface_count() != 1:
		errors.append("mesh_surface_count")
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-mesh-payload] status=pass vertices=%d indices=%d max_vertex_delta=%.9f" % [
		height.size(),
		(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
		max_vertex_delta,
	])
	return 0


func _compare_vertices(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var max_delta := 0.0
	for index in range(a.size()):
		max_delta = max(max_delta, abs(a[index].x - b[index].x))
		max_delta = max(max_delta, abs(a[index].y - b[index].y))
		max_delta = max(max_delta, abs(a[index].z - b[index].z))
	return max_delta


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-mesh-payload] status=fail errors=%d" % errors.size())
