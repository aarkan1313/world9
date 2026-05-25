extends SceneTree

const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const HEIGHT_EPSILON := 0.0001
const MAX_NATIVE_MS := 1500
const MAX_MESH_MS := 1500


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return

	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_report_and_quit(errors)
		return

	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	var configs: Array[Dictionary] = [
		{"label": "baseline_512m_129v_4m", "chunk_size_m": 512.0, "vertices_per_side": 129},
		{"label": "detail_512m_257v_2m", "chunk_size_m": 512.0, "vertices_per_side": 257},
		{"label": "local_256m_257v_1m", "chunk_size_m": 256.0, "vertices_per_side": 257},
	]
	var results: Array[Dictionary] = []
	for config in configs:
		results.append(_run_config(world, backend, config, errors))
	_report_and_quit(errors, results)


func _run_config(world: RefCounted, backend: Object, config: Dictionary, errors: Array[String]) -> Dictionary:
	var label: String = str(config["label"])
	var chunk_size_m: float = float(config["chunk_size_m"])
	var count: int = int(config["vertices_per_side"])
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		0,
		0,
		count,
		chunk_size_m,
		0,
		0,
		TerrainWorldScript.DEBUG_GRAY
	)
	var prepare_start_ms: int = Time.get_ticks_msec()
	var prepared: Dictionary = _prepare_native_request(world, request)
	var prepare_ms: int = Time.get_ticks_msec() - prepare_start_ms
	if prepared.get("status", "fail") != "pass":
		errors.append("%s:prepare_failed:%s" % [label, str(prepared)])
		return {"label": label, "status": "fail", "prepare_ms": prepare_ms}

	var native_start_ms: int = Time.get_ticks_msec()
	var native: Dictionary = _run_native_payload(backend, prepared)
	var native_ms: int = Time.get_ticks_msec() - native_start_ms
	if native.get("status", "fail") != "pass":
		errors.append("%s:native_failed:%s" % [label, str(native)])
		return {"label": label, "status": "fail", "prepare_ms": prepare_ms, "native_ms": native_ms}

	var mesh_start_ms: int = Time.get_ticks_msec()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = native["vertices"] as PackedVector3Array
	arrays[Mesh.ARRAY_NORMAL] = native["normals"] as PackedVector3Array
	arrays[Mesh.ARRAY_TEX_UV] = native["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = native["indices"] as PackedInt32Array
	var mesh: ArrayMesh = TerrainMeshBuilderScript.build_array_mesh(arrays)
	var mesh_ms: int = Time.get_ticks_msec() - mesh_start_ms
	if mesh == null:
		errors.append("%s:mesh_null" % label)

	var east_native: Dictionary = _run_adjacent_east(world, backend, request, errors, label)
	var edge_delta: float = INF
	var east_native_ms: int = -1
	if east_native.get("status", "fail") == "pass":
		east_native_ms = int(east_native["native_ms"])
		edge_delta = _east_west_edge_delta(native["height"] as PackedFloat32Array, east_native["height"] as PackedFloat32Array, count)
		if edge_delta > HEIGHT_EPSILON:
			errors.append("%s:edge_delta:%.9f" % [label, edge_delta])

	var vertex_count: int = (native["vertices"] as PackedVector3Array).size()
	var normal_count: int = (native["normals"] as PackedVector3Array).size()
	var uv_count: int = (native["uvs"] as PackedVector2Array).size()
	var index_count: int = (native["indices"] as PackedInt32Array).size()
	var expected_vertices: int = count * count
	var expected_indices: int = (count - 1) * (count - 1) * 6
	if vertex_count != expected_vertices:
		errors.append("%s:vertex_count:%d expected:%d" % [label, vertex_count, expected_vertices])
	if normal_count != expected_vertices:
		errors.append("%s:normal_count:%d expected:%d" % [label, normal_count, expected_vertices])
	if uv_count != expected_vertices:
		errors.append("%s:uv_count:%d expected:%d" % [label, uv_count, expected_vertices])
	if index_count != expected_indices:
		errors.append("%s:index_count:%d expected:%d" % [label, index_count, expected_indices])
	if native_ms > MAX_NATIVE_MS:
		errors.append("%s:native_ms:%d limit:%d" % [label, native_ms, MAX_NATIVE_MS])
	if mesh_ms > MAX_MESH_MS:
		errors.append("%s:mesh_ms:%d limit:%d" % [label, mesh_ms, MAX_MESH_MS])

	var bytes_estimate: int = expected_vertices * (4 + 12 + 12 + 8) + expected_indices * 4
	return {
		"label": label,
		"status": "pass",
		"chunk_size_m": chunk_size_m,
		"vertices_per_side": count,
		"spacing_m": chunk_size_m / float(count - 1),
		"prepare_ms": prepare_ms,
		"native_ms": native_ms,
		"mesh_ms": mesh_ms,
		"east_native_ms": east_native_ms,
		"edge_delta": edge_delta,
		"vertex_count": vertex_count,
		"index_count": index_count,
		"bytes_estimate": bytes_estimate,
	}


func _run_adjacent_east(world: RefCounted, backend: Object, request: Dictionary, errors: Array[String], label: String) -> Dictionary:
	var east_request: Dictionary = request.duplicate()
	east_request["chunk_x"] = int(request["chunk_x"]) + 1
	var prepared: Dictionary = _prepare_native_request(world, east_request)
	if prepared.get("status", "fail") != "pass":
		errors.append("%s:east_prepare_failed:%s" % [label, str(prepared)])
		return {"status": "fail"}
	var native_start_ms: int = Time.get_ticks_msec()
	var native: Dictionary = _run_native_payload(backend, prepared)
	var native_ms: int = Time.get_ticks_msec() - native_start_ms
	if native.get("status", "fail") != "pass":
		errors.append("%s:east_native_failed:%s" % [label, str(native)])
		return {"status": "fail"}
	return {
		"status": "pass",
		"native_ms": native_ms,
		"height": native["height"] as PackedFloat32Array,
	}


func _prepare_native_request(world: RefCounted, request: Dictionary) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var chunk_size_m: float = float(request["chunk_size_m"])
	var step_m: float = float(request["step_m"])
	var origin_x: float = float(chunk_x) * chunk_size_m
	var origin_z: float = float(chunk_z) * chunk_size_m
	var prepared: Dictionary = world.provider.native_prepared_height_grid_request(
		origin_x,
		origin_z,
		step_m,
		count,
		count,
		world.seed,
		world.region_size_m
	)
	if prepared.get("status", "fail") != "pass":
		return prepared
	return {
		"status": "pass",
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count": count,
		"world_seed": world.seed,
		"region_size_m": world.region_size_m,
		"base_rx": int(prepared["base_rx"]),
		"base_rz": int(prepared["base_rz"]),
		"corner_entries": prepared["corner_entries"] as Array,
	}


func _run_native_payload(backend: Object, prepared: Dictionary) -> Dictionary:
	return backend.call(
		"build_chunk_payload_prepared",
		float(prepared["origin_x"]),
		float(prepared["origin_z"]),
		float(prepared["step_m"]),
		int(prepared["count"]),
		int(prepared["world_seed"]),
		float(prepared["region_size_m"]),
		int(prepared["base_rx"]),
		int(prepared["base_rz"]),
		prepared["corner_entries"] as Array
	) as Dictionary


func _east_west_edge_delta(west: PackedFloat32Array, east: PackedFloat32Array, count: int) -> float:
	if west.size() != count * count or east.size() != count * count:
		return INF
	var max_delta := 0.0
	for row in range(count):
		max_delta = max(max_delta, abs(float(west[row * count + count - 1]) - float(east[row * count])))
	return max_delta


func _report_and_quit(errors: Array[String], results: Array[Dictionary] = []) -> void:
	for result in results:
		print("[wg9-257-local-detail] result=%s" % JSON.stringify(result))
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-257-local-detail] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-257-local-detail] status=pass configs=%d" % results.size())
	quit(0)
