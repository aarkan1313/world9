extends SceneTree

const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")
const TerrainNativeChunkPayloadWorkerScript := preload("res://worldgen_terrain/mesh/terrain_native_chunk_payload_worker.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const FLOAT_EPSILON := 0.000001
const HEIGHT_EPSILON := 0.0001


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
	var timings: Array[String] = []
	for count in [33, 129]:
		_run_count(world, count, errors, timings)
	_report_and_quit(errors, timings)


func _run_count(world: RefCounted, count: int, errors: Array[String], timings: Array[String]) -> void:
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		1,
		2,
		count,
		TerrainSettingsScript.CHUNK_SIZE_M,
		0,
		0,
		TerrainWorldScript.DEBUG_GRAY
	)
	var reference: Dictionary = TerrainChunkBuildJobScript.build_payload(world, request)
	if reference.get("status", "fail") != "pass":
		errors.append("reference_failed_%d:%s" % [count, str(reference)])
		return
	var prepared: Dictionary = _prepare_native_request(world, request)
	if prepared.get("status", "fail") != "pass":
		errors.append("prepared_failed_%d:%s" % [count, str(prepared)])
		return
	prepared["request_id"] = "%d:%d:%d" % [int(request["chunk_x"]), int(request["chunk_z"]), count]
	var worker: RefCounted = TerrainNativeChunkPayloadWorkerScript.new()
	if not worker.start(prepared):
		errors.append("worker_start_failed_%d" % count)
		return
	var native: Dictionary = worker.wait_for_result(5000)
	timings.append("%d:%dms" % [count, int(native.get("worker_elapsed_ms", -1))])
	if native.get("status", "fail") != "pass":
		errors.append("worker_failed_%d:%s" % [count, str(native)])
		return
	if str(native.get("worker_request_id", "")) != str(prepared["request_id"]):
		errors.append("worker_request_id_%d:%s" % [count, str(native.get("worker_request_id", ""))])
	_check_native_payload(count, native, reference, errors)


func _prepare_native_request(world: RefCounted, request: Dictionary) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var step_m: float = float(request["step_m"])
	var origin_x: float = float(chunk_x) * float(request["chunk_size_m"])
	var origin_z: float = float(chunk_z) * float(request["chunk_size_m"])
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


func _check_native_payload(count: int, native: Dictionary, reference: Dictionary, errors: Array[String]) -> void:
	var native_height: PackedFloat32Array = native["height"] as PackedFloat32Array
	var reference_height: PackedFloat32Array = reference["height"] as PackedFloat32Array
	var height_delta: float = _compare_float32(native_height, reference_height)
	if height_delta > HEIGHT_EPSILON:
		errors.append("height_delta_%d:%.9f" % [count, height_delta])
	var native_vertices: PackedVector3Array = native["vertices"] as PackedVector3Array
	var native_normals: PackedVector3Array = native["normals"] as PackedVector3Array
	var native_uvs: PackedVector2Array = native["uvs"] as PackedVector2Array
	var native_indices: PackedInt32Array = native["indices"] as PackedInt32Array
	var reference_arrays: Array = reference["arrays"] as Array
	var vertex_delta: float = _compare_vec3(native_vertices, reference_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var normal_delta: float = _compare_vec3(native_normals, reference_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
	var uv_delta: float = _compare_vec2(native_uvs, reference_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array)
	if vertex_delta > HEIGHT_EPSILON:
		errors.append("vertex_delta_%d:%.9f" % [count, vertex_delta])
	if normal_delta > FLOAT_EPSILON:
		errors.append("normal_delta_%d:%.9f" % [count, normal_delta])
	if uv_delta > FLOAT_EPSILON:
		errors.append("uv_delta_%d:%.9f" % [count, uv_delta])
	if native_indices != (reference_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		errors.append("index_mismatch_%d" % count)


func _compare_float32(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var max_delta := 0.0
	for index in range(a.size()):
		max_delta = max(max_delta, abs(float(a[index]) - float(b[index])))
	return max_delta


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


func _report_and_quit(errors: Array[String], timings: Array[String] = []) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-native-chunk-worker] status=fail errors=%d timings=%s" % [errors.size(), str(timings)])
		quit(1)
		return
	print("[wg9-native-chunk-worker] status=pass timings=%s" % str(timings))
	quit(0)
