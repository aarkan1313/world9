extends SceneTree

const TerrainGpuPageNormalBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_page_normal_backend.gd")
const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var backend = TerrainGpuPageNormalBackendScript.new()
	var setup_result: Dictionary = backend.setup()
	if setup_result.get("status", "fail") == "unsupported":
		print("[wg9-gpu-page-normal-backend] status=unsupported result=%s" % str(setup_result))
		quit(0)
		return
	if setup_result.get("status", "fail") != "pass":
		errors.append("setup_failed:%s" % str(setup_result))
	else:
		_check_reused_pipeline(backend, errors)
	backend.shutdown()
	if errors.is_empty():
		_check_far_clipmap_opt_in(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-normal-backend] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-page-normal-backend] status=pass")
	quit(0)


func _check_reused_pipeline(backend: RefCounted, errors: Array[String]) -> void:
	var side := 16
	var step_m := 2.0
	var height_data: PackedByteArray = _height_bytes(side)
	var first: Dictionary = backend.compute_normal_image_data_from_height_bytes(height_data, side, step_m)
	var second: Dictionary = backend.compute_normal_image_data_from_height_bytes(height_data, side, step_m)
	if first.get("status", "fail") != "pass":
		errors.append("first_compute_failed:%s" % str(first))
		return
	if second.get("status", "fail") != "pass":
		errors.append("second_compute_failed:%s" % str(second))
		return
	var normal_data: PackedByteArray = second.get("normal_image_data", PackedByteArray()) as PackedByteArray
	if normal_data.size() != side * side * 12:
		errors.append("normal_data_size:%d" % normal_data.size())
	var state: Dictionary = backend.debug_state()
	if int(state.get("compile_count", 0)) != 1:
		errors.append("compile_count:%s" % str(state))
	if int(state.get("dispatch_count", 0)) != 2:
		errors.append("dispatch_count:%s" % str(state))
	if int(state.get("pipeline_count", 0)) != 1:
		errors.append("pipeline_count:%s" % str(state))
	var max_delta: float = _max_cpu_delta(height_data, normal_data, side, step_m)
	if max_delta > 0.0001:
		errors.append("normal_delta:%f" % max_delta)


func _check_far_clipmap_opt_in(errors: Array[String]) -> void:
	var world = TerrainWorldScript.new()
	if not world.setup_procedural(1777):
		errors.append("world_setup_failed:%s" % str(world.errors))
		return
	var node = TerrainFarClipmapNodeScript.new()
	node.level_count = 2
	node.use_persistent_page_mesh = true
	node.use_native_workers = false
	node.use_gpu_page_normal_backend = true
	node.gpu_page_residency_max_pages = 8
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("clipmap_setup_failed")
		node.queue_free()
		return
	node.update_viewer(Vector2.ZERO)
	var stats: Dictionary = node.stats()
	if int(stats.get("last_gpu_page_normal_dispatches", 0)) < node.level_count:
		errors.append("clipmap_gpu_normal_dispatches:%s" % str(stats))
	if not str(stats.get("last_gpu_page_normal_error", "")).is_empty():
		errors.append("clipmap_gpu_normal_error:%s" % str(stats))
	for descriptor_value in node.level_material_descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		if descriptor.get("status", "fail") != "pass":
			errors.append("clipmap_descriptor_failed:%s" % str(descriptor))
		elif str(descriptor.get("texture_payload_mode", "")) != "gpu_normal_backend":
			errors.append("clipmap_descriptor_payload_mode:%s" % str(descriptor))
	node.queue_free()


func _height_bytes(side: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(side * side * 4)
	for z in range(side):
		for x in range(side):
			var index: int = z * side + x
			var height: float = sin(float(x) * 0.27) * 13.0 + cos(float(z) * 0.19) * 9.0 + float(x + z) * 0.5
			data.encode_float(index * 4, height)
	return data


func _max_cpu_delta(height_data: PackedByteArray, normal_data: PackedByteArray, side: int, step_m: float) -> float:
	var max_delta := 0.0
	for z in range(side):
		for x in range(side):
			var expected := _encoded_normal(height_data, side, x, z, step_m)
			var offset: int = (z * side + x) * 12
			var actual := Vector3(
				normal_data.decode_float(offset),
				normal_data.decode_float(offset + 4),
				normal_data.decode_float(offset + 8)
			)
			max_delta = maxf(max_delta, absf(expected.x - actual.x))
			max_delta = maxf(max_delta, absf(expected.y - actual.y))
			max_delta = maxf(max_delta, absf(expected.z - actual.z))
	return max_delta


func _encoded_normal(height_data: PackedByteArray, side: int, x: int, z: int, step_m: float) -> Vector3:
	var left: float = _height_at(height_data, side, maxi(0, x - 1), z)
	var right: float = _height_at(height_data, side, mini(side - 1, x + 1), z)
	var up: float = _height_at(height_data, side, x, maxi(0, z - 1))
	var down: float = _height_at(height_data, side, x, mini(side - 1, z + 1))
	return Vector3(left - right, step_m * 2.0, up - down).normalized() * 0.5 + Vector3(0.5, 0.5, 0.5)


func _height_at(height_data: PackedByteArray, side: int, x: int, z: int) -> float:
	return height_data.decode_float((z * side + x) * 4)
