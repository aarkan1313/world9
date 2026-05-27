extends SceneTree

const TerrainGpuPageResidencyScript := preload("res://worldgen_terrain/core/terrain_gpu_page_residency.gd")
const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not _rendering_device_available():
		print("[wg9-gpu-rd-page-residency] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	_check_direct_rd_residency(errors)
	_check_direct_rd_compute_normal_residency(errors)
	_check_far_clipmap_rd_opt_in(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-rd-page-residency] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-rd-page-residency] status=pass")
	quit(0)


func _rendering_device_available() -> bool:
	return ClassDB.class_exists("Texture2DRD") and RenderingServer.has_method("get_rendering_device") and RenderingServer.call("get_rendering_device") != null


func _check_direct_rd_residency(errors: Array[String]) -> void:
	var residency = TerrainGpuPageResidencyScript.new()
	residency.configure(2, true)
	var entry: Dictionary = residency.get_or_create_textures("rd_a", _descriptor(16, 3.0))
	if entry.get("status", "fail") != "pass":
		errors.append("rd_entry_failed:%s" % str(entry))
		return
	if str(entry.get("texture_backend", "")) != "rd":
		errors.append("rd_entry_backend:%s" % str(entry))
	var state: Dictionary = residency.debug_state()
	if int(state.get("rd_uploads", 0)) != 1:
		errors.append("rd_uploads:%s" % str(state))
	if int(state.get("image_uploads", 0)) != 0:
		errors.append("image_uploads:%s" % str(state))
	residency.clear()


func _check_direct_rd_compute_normal_residency(errors: Array[String]) -> void:
	var residency = TerrainGpuPageResidencyScript.new()
	residency.configure(2, true, true)
	var entry: Dictionary = residency.get_or_create_textures("rd_compute_a", _descriptor(16, 3.0))
	if entry.get("status", "fail") != "pass":
		errors.append("rd_compute_entry_failed:%s" % str(entry))
		return
	if str(entry.get("texture_backend", "")) != "rd":
		errors.append("rd_compute_entry_backend:%s" % str(entry))
	if str(entry.get("normal_texture_mode", "")) != "rd_compute":
		errors.append("rd_compute_normal_mode:%s" % str(entry))
	var state: Dictionary = residency.debug_state()
	if int(state.get("rd_compute_normal_uploads", 0)) != 1:
		errors.append("rd_compute_normal_uploads:%s" % str(state))
	if int(state.get("rd_compute_normal_failures", 0)) != 0:
		errors.append("rd_compute_normal_failures:%s" % str(state))
	if int(state.get("image_uploads", 0)) != 0:
		errors.append("rd_compute_image_uploads:%s" % str(state))
	residency.clear()


func _check_far_clipmap_rd_opt_in(errors: Array[String]) -> void:
	var world = TerrainWorldScript.new()
	if not world.setup_procedural(2551):
		errors.append("world_setup_failed:%s" % str(world.errors))
		return
	var node = TerrainFarClipmapNodeScript.new()
	node.level_count = 2
	node.use_persistent_page_mesh = true
	node.use_native_workers = false
	node.use_gpu_page_normal_backend = true
	node.use_gpu_rd_page_textures = true
	node.use_gpu_rd_compute_normals = true
	node.gpu_page_residency_max_pages = 8
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("clipmap_setup_failed")
		node.clear_levels(true)
		node.queue_free()
		return
	node.update_viewer(Vector2.ZERO)
	var stats: Dictionary = node.stats()
	var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
	if int(gpu_state.get("rd_uploads", 0)) < node.level_count:
		errors.append("clipmap_rd_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("clipmap_image_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("rd_compute_normal_uploads", 0)) < node.level_count:
		errors.append("clipmap_rd_compute_normal_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("rd_compute_normal_failures", 0)) != 0:
		errors.append("clipmap_rd_compute_normal_failures:%s" % str(gpu_state))
	if int(stats.get("last_gpu_page_normal_dispatches", 0)) < node.level_count:
		errors.append("clipmap_gpu_normal_dispatches:%s" % str(stats))
	node.clear_levels(true)
	node.queue_free()


func _descriptor(count: int, base_height: float) -> Dictionary:
	var height_data := PackedByteArray()
	var normal_data := PackedByteArray()
	height_data.resize(count * count * 4)
	normal_data.resize(count * count * 12)
	for index in range(count * count):
		height_data.encode_float(index * 4, base_height + float(index) * 0.125)
		var normal_offset: int = index * 12
		normal_data.encode_float(normal_offset, 0.5)
		normal_data.encode_float(normal_offset + 4, 1.0)
		normal_data.encode_float(normal_offset + 8, 0.5)
	return {
		"status": "pass",
		"vertices_per_side": count,
		"spacing_m": 4.0,
		"height_image_data": height_data,
		"normal_image_data": normal_data,
		"height_image": Image.create_from_data(count, count, false, Image.FORMAT_RF, height_data),
		"normal_image": Image.create_from_data(count, count, false, Image.FORMAT_RGBF, normal_data),
	}
