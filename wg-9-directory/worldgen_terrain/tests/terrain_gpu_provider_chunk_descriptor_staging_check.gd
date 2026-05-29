extends SceneTree

const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not _rendering_device_available():
		print("[wg9-gpu-provider-chunk-staging] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	await _check_staged_near_chunk_provider_path(errors)
	await _check_staged_near_chunk_motion_window(errors)
	await _check_staged_near_chunk_full_window_backlog(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-provider-chunk-staging] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-provider-chunk-staging] status=pass")
	quit(0)


func _rendering_device_available() -> bool:
	return ClassDB.class_exists("Texture2DRD") and RenderingServer.has_method("get_rendering_device") and RenderingServer.call("get_rendering_device") != null


func _check_staged_near_chunk_provider_path(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.use_fast_gray_material = true
	node.use_gpu_page_chunks = true
	node.use_gpu_provider_page_chunk_textures = true
	node.use_gpu_provider_page_chunk_descriptor_staging = true
	node.use_gpu_rd_chunk_page_textures = true
	node.use_gpu_rd_chunk_compute_normals = true
	node.use_native_chunk_payloads = false
	node.use_native_chunk_workers = false
	node.max_gpu_provider_chunk_descriptor_stages_per_update = 1
	node.max_gpu_provider_chunk_descriptor_workers = 1
	node.max_gpu_page_chunk_builds_per_update = 1
	node.gpu_provider_chunk_descriptor_cache_max_entries = 8
	node.chunk_gpu_page_residency_max_pages = 8
	node.chunk_page_cache_max_pages = 8
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 7331):
		errors.append("setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 0,
		"max_lod": 0,
		"build_budget_per_frame": 1,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	node.update_viewer(Vector2.ZERO)
	await _drain_staged_gpu_node(node, 1, 1, 120)
	var stats: Dictionary = node.build_stats()
	var gpu_state: Dictionary = stats.get("chunk_gpu_page_residency", {}) as Dictionary
	if int(node.built_chunk_count()) != 1:
		errors.append("built_chunk_count:%d stats:%s" % [int(node.built_chunk_count()), str(stats)])
	if int(stats.get("last_gpu_provider_chunk_descriptor_stages", 0)) != 1:
		errors.append("descriptor_stage_count:%s" % str(stats))
	if int(stats.get("total_gpu_provider_chunk_descriptor_stages", 0)) < 1:
		errors.append("descriptor_stage_total:%s" % str(stats))
	if int(stats.get("gpu_provider_chunk_descriptor_cache_count", 0)) < 1:
		errors.append("descriptor_cache_empty:%s" % str(stats))
	if int(stats.get("gpu_page_chunk_count", 0)) < 1:
		errors.append("gpu_page_chunk_not_committed:%s" % str(stats))
	if str(stats.get("last_gpu_page_chunk_error", "")) != "":
		errors.append("gpu_page_chunk_error:%s" % str(stats.get("last_gpu_page_chunk_error", "")))
	if str(stats.get("last_gpu_provider_chunk_descriptor_error", "")) != "":
		errors.append("descriptor_error:%s" % str(stats.get("last_gpu_provider_chunk_descriptor_error", "")))
	if int(gpu_state.get("rd_uploads", 0)) < 1:
		errors.append("chunk_rd_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("chunk_image_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("rd_compute_normal_failures", 0)) != 0:
		errors.append("chunk_compute_normal_failures:%s" % str(gpu_state))
	for mesh_instance_value in node.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		if not bool(mesh_instance.get_meta("gpu_page_chunk", false)):
			errors.append("chunk_not_marked_gpu_page:%s" % mesh_instance.name)
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if mesh == null:
			errors.append("chunk_mesh_null:%s" % mesh_instance.name)
	node.clear_chunks()
	node.queue_free()


func _check_staged_near_chunk_motion_window(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.use_fast_gray_material = true
	node.use_gpu_page_chunks = true
	node.use_gpu_provider_page_chunk_textures = true
	node.use_gpu_provider_page_chunk_descriptor_staging = true
	node.use_gpu_rd_chunk_page_textures = true
	node.use_gpu_rd_chunk_compute_normals = true
	node.use_native_chunk_payloads = false
	node.use_native_chunk_workers = false
	node.max_gpu_provider_chunk_descriptor_stages_per_update = 9
	node.max_gpu_provider_chunk_descriptor_workers = 8
	node.max_gpu_page_chunk_builds_per_update = 9
	node.gpu_provider_chunk_descriptor_cache_max_entries = 24
	node.chunk_gpu_page_residency_max_pages = 24
	node.chunk_page_cache_max_pages = 24
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 8111):
		errors.append("motion_setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 1,
		"max_lod": 0,
		"build_budget_per_frame": 9,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	node.update_viewer(Vector2.ZERO)
	await _drain_staged_gpu_node(node, 9, 9, 64)
	node.update_viewer(Vector2(512.0, 0.0))
	await _drain_staged_gpu_node(node, 9, 10, 96)
	var stats: Dictionary = node.build_stats()
	var gpu_state: Dictionary = stats.get("chunk_gpu_page_residency", {}) as Dictionary
	if int(node.built_chunk_count()) < 9:
		errors.append("motion_built_chunk_count:%d stats:%s" % [int(node.built_chunk_count()), str(stats)])
	if int(stats.get("active_missing_chunk_count", 0)) != 0:
		errors.append("motion_active_missing:%s" % str(stats))
	if int(stats.get("gpu_page_chunk_count", 0)) < 10:
		errors.append("motion_gpu_page_chunk_count:%s" % str(stats))
	if int(stats.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("motion_gpu_page_fallbacks:%s" % str(stats))
	if int(stats.get("total_gpu_provider_chunk_descriptor_stages", 0)) < 10:
		errors.append("motion_descriptor_stages:%s" % str(stats))
	if int(stats.get("gpu_provider_chunk_descriptor_cache_count", 0)) < 10:
		errors.append("motion_descriptor_cache:%s" % str(stats))
	if str(stats.get("last_gpu_page_chunk_error", "")) != "":
		errors.append("motion_gpu_page_chunk_error:%s" % str(stats.get("last_gpu_page_chunk_error", "")))
	if str(stats.get("last_gpu_provider_chunk_descriptor_error", "")) != "":
		errors.append("motion_descriptor_error:%s" % str(stats.get("last_gpu_provider_chunk_descriptor_error", "")))
	if int(gpu_state.get("rd_uploads", 0)) < 10:
		errors.append("motion_rd_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("motion_image_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("evictions", 0)) != 0:
		errors.append("motion_evictions:%s" % str(gpu_state))
	node.clear_chunks()
	node.queue_free()


func _check_staged_near_chunk_full_window_backlog(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.use_fast_gray_material = true
	node.use_gpu_page_chunks = true
	node.use_gpu_provider_page_chunk_textures = true
	node.use_gpu_provider_page_chunk_descriptor_staging = true
	node.use_gpu_rd_chunk_page_textures = true
	node.use_gpu_rd_chunk_compute_normals = true
	node.use_native_chunk_payloads = false
	node.use_native_chunk_workers = false
	node.max_gpu_provider_chunk_descriptor_stages_per_update = 8
	node.max_gpu_provider_chunk_descriptor_workers = 8
	node.max_gpu_page_chunk_builds_per_update = 16
	node.gpu_provider_chunk_descriptor_cache_max_entries = 96
	node.chunk_gpu_page_residency_max_pages = 96
	node.chunk_page_cache_max_pages = 96
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 9121):
		errors.append("full_window_setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 3,
		"max_lod": 0,
		"build_budget_per_frame": 16,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	node.update_viewer(Vector2.ZERO)
	var first_stats: Dictionary = node.build_stats()
	if int(first_stats.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("full_window_first_fallbacks:%s" % str(first_stats))
	if int(node.built_chunk_count()) > 8:
		errors.append("full_window_first_overbuilt:%d stats:%s" % [int(node.built_chunk_count()), str(first_stats)])
	await _drain_staged_gpu_node(node, 49, 49, 600)
	var stats: Dictionary = node.build_stats()
	var gpu_state: Dictionary = stats.get("chunk_gpu_page_residency", {}) as Dictionary
	if int(node.built_chunk_count()) < 49:
		errors.append("full_window_built_chunk_count:%d stats:%s" % [int(node.built_chunk_count()), str(stats)])
	if int(stats.get("active_missing_chunk_count", 0)) != 0:
		errors.append("full_window_active_missing:%s" % str(stats))
	if int(stats.get("gpu_page_chunk_count", 0)) < 49:
		errors.append("full_window_gpu_page_chunk_count:%s" % str(stats))
	if int(stats.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("full_window_gpu_page_fallbacks:%s" % str(stats))
	if int(stats.get("total_gpu_provider_chunk_descriptor_stages", 0)) < 49:
		errors.append("full_window_descriptor_stages:%s" % str(stats))
	if str(stats.get("last_gpu_page_chunk_error", "")) != "":
		errors.append("full_window_gpu_page_chunk_error:%s" % str(stats.get("last_gpu_page_chunk_error", "")))
	if str(stats.get("last_gpu_provider_chunk_descriptor_error", "")) != "":
		errors.append("full_window_descriptor_error:%s" % str(stats.get("last_gpu_provider_chunk_descriptor_error", "")))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("full_window_image_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("evictions", 0)) != 0:
		errors.append("full_window_evictions:%s" % str(gpu_state))
	node.update_viewer(Vector2(512.0, 0.0))
	await _drain_staged_gpu_node(node, 49, 56, 600)
	var motion_stats: Dictionary = node.build_stats()
	var motion_gpu_state: Dictionary = motion_stats.get("chunk_gpu_page_residency", {}) as Dictionary
	if int(node.built_chunk_count()) < 49:
		errors.append("full_window_motion_built_chunk_count:%d stats:%s" % [int(node.built_chunk_count()), str(motion_stats)])
	if int(motion_stats.get("active_missing_chunk_count", 0)) != 0:
		errors.append("full_window_motion_active_missing:%s" % str(motion_stats))
	if int(motion_stats.get("gpu_page_chunk_count", 0)) < 56:
		errors.append("full_window_motion_gpu_page_chunk_count:%s" % str(motion_stats))
	if int(motion_stats.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("full_window_motion_gpu_page_fallbacks:%s" % str(motion_stats))
	if int(motion_stats.get("total_gpu_provider_chunk_descriptor_stages", 0)) < 56:
		errors.append("full_window_motion_descriptor_stages:%s" % str(motion_stats))
	if str(motion_stats.get("last_gpu_page_chunk_error", "")) != "":
		errors.append("full_window_motion_gpu_page_chunk_error:%s" % str(motion_stats.get("last_gpu_page_chunk_error", "")))
	if str(motion_stats.get("last_gpu_provider_chunk_descriptor_error", "")) != "":
		errors.append("full_window_motion_descriptor_error:%s" % str(motion_stats.get("last_gpu_provider_chunk_descriptor_error", "")))
	if int(motion_gpu_state.get("image_uploads", 0)) != 0:
		errors.append("full_window_motion_image_uploads:%s" % str(motion_gpu_state))
	if int(motion_gpu_state.get("evictions", 0)) != 0:
		errors.append("full_window_motion_evictions:%s" % str(motion_gpu_state))
	node.clear_chunks()
	node.queue_free()


func _drain_staged_gpu_node(node: Node3D, target_count: int, target_gpu_count: int, max_iterations: int) -> void:
	for _i in range(max_iterations):
		var stats: Dictionary = node.build_stats()
		var active_missing: int = int(stats.get("active_missing_chunk_count", 0))
		var active_descriptor_workers: int = int(stats.get("active_gpu_provider_chunk_descriptor_workers", 0))
		var queued_native_workers: int = int(stats.get("queued_native_worker_builds", 0))
		var active_native_workers: int = int(stats.get("active_native_workers", 0))
		if (
			int(node.built_chunk_count()) >= target_count
			and int(stats.get("gpu_page_chunk_count", 0)) >= target_gpu_count
			and active_missing == 0
			and active_descriptor_workers == 0
			and queued_native_workers == 0
			and active_native_workers == 0
		):
			return
		node.update_viewer(node.viewer_position_xz)
		await process_frame
