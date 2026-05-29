extends SceneTree

const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")
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
	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	var timings: Array[String] = []
	for count in [33, 129]:
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
			continue
		var step_m: float = float(request["step_m"])
		var origin_x: float = float(request["chunk_x"]) * float(request["chunk_size_m"])
		var origin_z: float = float(request["chunk_z"]) * float(request["chunk_size_m"])
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
			errors.append("prepared_failed_%d:%s" % [count, str(prepared)])
			continue
		var start_ms: int = Time.get_ticks_msec()
		var native: Dictionary = backend.call(
			"build_chunk_payload_prepared",
			origin_x,
			origin_z,
			step_m,
			count,
			world.seed,
			world.region_size_m,
			int(prepared["base_rx"]),
			int(prepared["base_rz"]),
			prepared["corner_entries"] as Array
		) as Dictionary
		var native_ms: int = Time.get_ticks_msec() - start_ms
		timings.append("%d:%dms" % [count, native_ms])
		if native.get("status", "fail") != "pass":
			errors.append("native_failed_%d:%s" % [count, str(native)])
			continue
		_check_native_payload(count, native, reference, errors)
	_check_custom_chunk_size_payload(backend, world, errors)
	_check_native_prepared_validation(backend, world, errors)
	_report_and_quit(errors, timings)


func _check_custom_chunk_size_payload(backend: Object, world: RefCounted, errors: Array[String]) -> void:
	var count := 129
	var chunk_size_m := 512.0
	var chunk_x := -2
	var chunk_z := 3
	var step_m: float = chunk_size_m / float(count - 1)
	var origin_x: float = float(chunk_x) * chunk_size_m
	var origin_z: float = float(chunk_z) * chunk_size_m
	var reference_height: PackedFloat32Array = world.sample_height_grid(origin_x, origin_z, step_m, count, count)
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
		errors.append("custom_prepare_failed:%s" % str(prepared))
		return
	var native: Dictionary = backend.call(
		"build_chunk_payload_prepared",
		origin_x,
		origin_z,
		step_m,
		count,
		world.seed,
		world.region_size_m,
		int(prepared["base_rx"]),
		int(prepared["base_rz"]),
		prepared["corner_entries"] as Array
	) as Dictionary
	if native.get("status", "fail") != "pass":
		errors.append("custom_native_failed:%s" % str(native))
		return
	var native_height: PackedFloat32Array = native["height"] as PackedFloat32Array
	var height_delta: float = _compare_float32(native_height, reference_height)
	if height_delta > HEIGHT_EPSILON:
		errors.append("custom_height_delta:%.9f" % height_delta)
	var native_vertices: PackedVector3Array = native["vertices"] as PackedVector3Array
	var probe_index: int = 128 * count + 112
	var expected_height: float = float(reference_height[probe_index])
	var actual_height: float = native_vertices[probe_index].y if probe_index < native_vertices.size() else INF
	if absf(actual_height - expected_height) > HEIGHT_EPSILON:
		errors.append("custom_probe_vertex:%.9f expected:%.9f" % [actual_height, expected_height])


func _check_native_prepared_validation(backend: Object, world: RefCounted, errors: Array[String]) -> void:
	var count := 33
	var step_m: float = TerrainSettingsScript.CHUNK_SIZE_M / float(count - 1)
	var prepared: Dictionary = world.provider.native_prepared_height_grid_request(
		0.0,
		0.0,
		step_m,
		count,
		count,
		world.seed,
		world.region_size_m
	)
	if prepared.get("status", "fail") != "pass":
		errors.append("validation_prepare_failed:%s" % str(prepared))
		return
	var bad_prepared: Dictionary = prepared.duplicate(true)
	var corners: Array = (bad_prepared["corner_entries"] as Array).duplicate(true)
	var corner: Dictionary = (corners[0] as Dictionary).duplicate(true)
	var entries: Array = (corner["entries"] as Array).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["rows"] = 4
	entry["cols"] = 4
	entry["values"] = PackedFloat32Array([0.0, 1.0, 2.0])
	entries[0] = entry
	corner["entries"] = entries
	corners[0] = corner
	bad_prepared["corner_entries"] = corners
	var native: Dictionary = backend.call(
		"build_chunk_payload_prepared",
		0.0,
		0.0,
		step_m,
		count,
		world.seed,
		world.region_size_m,
		int(bad_prepared["base_rx"]),
		int(bad_prepared["base_rz"]),
		bad_prepared["corner_entries"] as Array
	) as Dictionary
	if native.get("status", "pass") != "fail":
		errors.append("native_invalid_prepared_accepted:%s" % str(native))


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
		print("[wg9-native-chunk-payload] status=fail errors=%d timings=%s" % [errors.size(), str(timings)])
		quit(1)
		return
	print("[wg9-native-chunk-payload] status=pass timings=%s" % str(timings))
	quit(0)
