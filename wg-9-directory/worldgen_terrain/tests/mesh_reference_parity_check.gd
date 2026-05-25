extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const NpyFloat32ArrayScript := preload("res://worldgen_terrain/io/npy_float32_array.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")

const FLOAT_EPSILON := 0.0001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var chunk_manifest_path: String = TerrainSettingsScript.workspace_path("factory/runtime/chunk_reference/chunk_reference_manifest.json")
	var mesh_manifest_path: String = TerrainSettingsScript.workspace_path("factory/runtime/mesh_reference/mesh_reference_manifest.json")
	var chunk_manifest := _read_json(chunk_manifest_path)
	var mesh_manifest := _read_json(mesh_manifest_path)
	if chunk_manifest.is_empty() or mesh_manifest.is_empty():
		return 1

	var vertices_per_side: int = int(mesh_manifest["vertices_per_side"])
	var step_m: float = float(mesh_manifest["step_m"])
	var errors: Array[String] = []
	_check_indices(mesh_manifest, vertices_per_side, errors)
	_check_uvs(mesh_manifest, vertices_per_side, errors)

	var generated_by_coord: Dictionary = {}
	var max_vertex_delta: float = 0.0
	var max_normal_delta: float = 0.0
	for mesh_chunk_value in mesh_manifest.get("chunks", []) as Array:
		var mesh_chunk: Dictionary = mesh_chunk_value as Dictionary
		var coord: Array = mesh_chunk["chunk"] as Array
		var chunk_record: Dictionary = _chunk_record(chunk_manifest, coord)
		if chunk_record.is_empty():
			errors.append("missing_chunk_record:%s" % str(coord))
			continue
		var height_path: String = chunk_manifest_path.get_base_dir().path_join(str(chunk_record["height_npy"]))
		var height_info: Dictionary = NpyFloat32ArrayScript.load_2d(height_path)
		if height_info.get("status") != "pass":
			errors.append("height_load:%s" % height_info.get("error", "unknown"))
			continue
		var height: PackedFloat32Array = height_info["values"] as PackedFloat32Array
		var vertices: PackedVector3Array = TerrainMeshBuilderScript.build_vertices(height, vertices_per_side, step_m)
		var normals: PackedVector3Array = TerrainMeshBuilderScript.build_normals(height, vertices_per_side, step_m)
		var ref_vertices: Dictionary = NpyFloat32ArrayScript.load_2d(mesh_manifest_path.get_base_dir().path_join(str(mesh_chunk["vertices_npy"])))
		var ref_normals: Dictionary = NpyFloat32ArrayScript.load_2d(mesh_manifest_path.get_base_dir().path_join(str(mesh_chunk["normals_npy"])))
		if ref_vertices.get("status") != "pass" or ref_normals.get("status") != "pass":
			errors.append("mesh_ref_load:%s" % str(coord))
			continue
		var vertex_delta: float = _compare_vec3_array(vertices, ref_vertices["values"] as PackedFloat32Array)
		var normal_delta: float = _compare_vec3_array(normals, ref_normals["values"] as PackedFloat32Array)
		max_vertex_delta = max(max_vertex_delta, vertex_delta)
		max_normal_delta = max(max_normal_delta, normal_delta)
		if vertex_delta > FLOAT_EPSILON:
			errors.append("vertex_delta:%s max=%.9f" % [str(coord), vertex_delta])
		if normal_delta > FLOAT_EPSILON:
			errors.append("normal_delta:%s max=%.9f" % [str(coord), normal_delta])
		generated_by_coord["%d,%d" % [int(coord[0]), int(coord[1])]] = {
			"vertices": vertices,
			"origin": mesh_chunk["origin"],
		}

	_check_edges(generated_by_coord, vertices_per_side, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-mesh-reference] status=fail errors=%d max_vertex_delta=%.9f max_normal_delta=%.9f" % [errors.size(), max_vertex_delta, max_normal_delta])
		return 1

	print("[wg9-mesh-reference] status=pass chunks=%d vertices=%d triangles=%d max_vertex_delta=%.9f max_normal_delta=%.9f" % [
		(mesh_manifest.get("chunks", []) as Array).size(),
		vertices_per_side * vertices_per_side,
		int(mesh_manifest["triangle_count"]),
		max_vertex_delta,
		max_normal_delta,
	])
	return 0


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON: %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open JSON: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON is not an object: %s" % path)
		return {}
	return parsed as Dictionary


func _check_indices(mesh_manifest: Dictionary, vertices_per_side: int, errors: Array[String]) -> void:
	var generated: PackedInt32Array = TerrainMeshBuilderScript.build_indices(vertices_per_side)
	var ref: Dictionary = NpyFloat32ArrayScript.load_u32_1d(TerrainSettingsScript.workspace_path("factory/runtime/mesh_reference").path_join(str(mesh_manifest["shared_indices_npy"])))
	if ref.get("status") != "pass":
		errors.append("indices_load:%s" % ref.get("error", "unknown"))
		return
	var values: PackedInt32Array = ref["values"] as PackedInt32Array
	if values.size() != generated.size():
		errors.append("indices_size expected %d got %d" % [values.size(), generated.size()])
		return
	for index in range(values.size()):
		if values[index] != generated[index]:
			errors.append("index_mismatch:%d expected %d got %d" % [index, values[index], generated[index]])
			return


func _check_uvs(mesh_manifest: Dictionary, vertices_per_side: int, errors: Array[String]) -> void:
	var generated: PackedVector2Array = TerrainMeshBuilderScript.build_uvs(vertices_per_side)
	var ref: Dictionary = NpyFloat32ArrayScript.load_2d(TerrainSettingsScript.workspace_path("factory/runtime/mesh_reference").path_join(str(mesh_manifest["shared_uvs_npy"])))
	if ref.get("status") != "pass":
		errors.append("uvs_load:%s" % ref.get("error", "unknown"))
		return
	var values: PackedFloat32Array = ref["values"] as PackedFloat32Array
	if values.size() != generated.size() * 2:
		errors.append("uv_size")
		return
	var max_delta: float = 0.0
	for index in range(generated.size()):
		max_delta = max(max_delta, abs(float(generated[index].x) - float(values[index * 2])))
		max_delta = max(max_delta, abs(float(generated[index].y) - float(values[index * 2 + 1])))
	if max_delta > FLOAT_EPSILON:
		errors.append("uv_delta max=%.9f" % max_delta)


func _chunk_record(chunk_manifest: Dictionary, coord: Array) -> Dictionary:
	for item in chunk_manifest.get("chunks", []) as Array:
		var record: Dictionary = item as Dictionary
		var chunk_coord: Array = record["chunk"] as Array
		if int(chunk_coord[0]) == int(coord[0]) and int(chunk_coord[1]) == int(coord[1]):
			return record
	return {}


func _compare_vec3_array(actual: PackedVector3Array, expected_flat: PackedFloat32Array) -> float:
	if expected_flat.size() != actual.size() * 3:
		return INF
	var max_delta: float = 0.0
	for index in range(actual.size()):
		max_delta = max(max_delta, abs(float(actual[index].x) - float(expected_flat[index * 3])))
		max_delta = max(max_delta, abs(float(actual[index].y) - float(expected_flat[index * 3 + 1])))
		max_delta = max(max_delta, abs(float(actual[index].z) - float(expected_flat[index * 3 + 2])))
	return max_delta


func _check_edges(meshes: Dictionary, vertices_per_side: int, errors: Array[String]) -> void:
	_check_east_west(meshes, "0,0", "1,0", vertices_per_side, errors)
	_check_north_south(meshes, "0,0", "0,1", vertices_per_side, errors)
	_check_east_west(meshes, "0,1", "1,1", vertices_per_side, errors)
	_check_north_south(meshes, "1,0", "1,1", vertices_per_side, errors)


func _check_east_west(meshes: Dictionary, a_key: String, b_key: String, vertices_per_side: int, errors: Array[String]) -> void:
	if not meshes.has(a_key) or not meshes.has(b_key):
		return
	var a: Dictionary = meshes[a_key] as Dictionary
	var b: Dictionary = meshes[b_key] as Dictionary
	var av: PackedVector3Array = a["vertices"] as PackedVector3Array
	var bv: PackedVector3Array = b["vertices"] as PackedVector3Array
	var ao: Array = a["origin"] as Array
	var bo: Array = b["origin"] as Array
	var max_delta: float = 0.0
	for row in range(vertices_per_side):
		var va: Vector3 = av[row * vertices_per_side + vertices_per_side - 1] + Vector3(float(ao[0]), 0.0, float(ao[1]))
		var vb: Vector3 = bv[row * vertices_per_side] + Vector3(float(bo[0]), 0.0, float(bo[1]))
		max_delta = max(max_delta, abs(va.x - vb.x), abs(va.y - vb.y), abs(va.z - vb.z))
	if max_delta != 0.0:
		errors.append("edge_east_west:%s:%s max=%.9f" % [a_key, b_key, max_delta])


func _check_north_south(meshes: Dictionary, a_key: String, b_key: String, vertices_per_side: int, errors: Array[String]) -> void:
	if not meshes.has(a_key) or not meshes.has(b_key):
		return
	var a: Dictionary = meshes[a_key] as Dictionary
	var b: Dictionary = meshes[b_key] as Dictionary
	var av: PackedVector3Array = a["vertices"] as PackedVector3Array
	var bv: PackedVector3Array = b["vertices"] as PackedVector3Array
	var ao: Array = a["origin"] as Array
	var bo: Array = b["origin"] as Array
	var max_delta: float = 0.0
	var a_start: int = (vertices_per_side - 1) * vertices_per_side
	for col in range(vertices_per_side):
		var va: Vector3 = av[a_start + col] + Vector3(float(ao[0]), 0.0, float(ao[1]))
		var vb: Vector3 = bv[col] + Vector3(float(bo[0]), 0.0, float(bo[1]))
		max_delta = max(max_delta, abs(va.x - vb.x), abs(va.y - vb.y), abs(va.z - vb.z))
	if max_delta != 0.0:
		errors.append("edge_north_south:%s:%s max=%.9f" % [a_key, b_key, max_delta])
