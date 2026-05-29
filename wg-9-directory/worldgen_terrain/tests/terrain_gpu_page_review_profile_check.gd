extends SceneTree

const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not _rendering_device_available():
		print("[wg9-gpu-page-review-profile] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	_check_gpu_page_review_profile(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-review-profile] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-page-review-profile] status=pass")
	quit(0)


func _rendering_device_available() -> bool:
	return ClassDB.class_exists("Texture2DRD") and RenderingServer.has_method("get_rendering_device") and RenderingServer.call("get_rendering_device") != null


func _check_gpu_page_review_profile(errors: Array[String]) -> void:
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.GPU_PAGE_REVIEW)
	if profile.is_empty():
		errors.append("profile_missing")
		return
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.quality_profile_id = TerrainQualityProfileScript.GPU_PAGE_REVIEW
	TerrainQualityProfileScript.apply_to_node(scene, profile)
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
		_clear_scene_now(scene)
		scene.queue_free()
		return
	if scene.far_clipmap == null:
		errors.append("far_clipmap_missing")
	else:
		var stats: Dictionary = scene.far_clipmap.stats()
		var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
		var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
		if not bool(gpu_state.get("use_rd_textures", false)):
			errors.append("rd_textures_not_enabled:%s" % str(gpu_state))
		if not bool(gpu_state.get("use_rd_compute_normals", false)):
			errors.append("rd_compute_normals_not_enabled:%s" % str(gpu_state))
		if int(gpu_state.get("rd_uploads", 0)) < int(budgets.get("gpu_page_review_min_rd_uploads", 0)):
			errors.append("rd_uploads:%s" % str(gpu_state))
		if int(gpu_state.get("rd_compute_normal_uploads", 0)) < int(budgets.get("gpu_page_review_min_rd_compute_normal_uploads", 0)):
			errors.append("rd_compute_normal_uploads:%s" % str(gpu_state))
		if int(gpu_state.get("rd_compute_normal_failures", 0)) != 0:
			errors.append("rd_compute_normal_failures:%s" % str(gpu_state))
		if int(gpu_state.get("image_uploads", 0)) > int(budgets.get("gpu_page_review_max_image_uploads", 0)):
			errors.append("image_uploads:%s" % str(gpu_state))
		if int(stats.get("last_gpu_page_normal_dispatches", 0)) < int(budgets.get("gpu_page_review_min_normal_dispatches", 0)):
			errors.append("normal_dispatches:%s" % str(stats))
		if not str(stats.get("last_gpu_page_normal_error", "")).is_empty():
			errors.append("normal_error:%s" % str(stats))
		var min_provider_dispatches: int = int(budgets.get("gpu_page_review_min_provider_page_dispatches", 0))
		if int(stats.get("total_gpu_provider_page_dispatches", 0)) < min_provider_dispatches:
			errors.append("provider_page_dispatches:%s" % str(stats))
		if int(stats.get("total_gpu_provider_metadata_only_commits", 0)) < min_provider_dispatches:
			errors.append("provider_metadata_only_commits:%s" % str(stats))
		if not str(stats.get("last_gpu_provider_page_error", "")).is_empty():
			errors.append("provider_page_error:%s" % str(stats))
	var terrain_stats: Dictionary = scene.terrain.build_stats() if scene.terrain != null else {}
	# Near GPU page chunks stay OFF in the accepted saved review profile per
	# roadmap 61zg; saved review proves direct-RD far pages over native-worker
	# near chunks. The experimental near-page path is measured by the separate
	# hitch-profile scene/gate. Keep this consistent with the scene and motion
	# checks against the same gpu_page_review profile.
	if bool(terrain_stats.get("use_gpu_page_chunks", false)):
		errors.append("near_gpu_page_chunks_active:%s" % str(terrain_stats))
	if int(terrain_stats.get("gpu_page_chunk_count", 0)) != int((profile.get("budgets", {}) as Dictionary).get("gpu_page_review_expected_near_page_chunks", 0)):
		errors.append("near_gpu_page_chunks:%s" % str(terrain_stats))
	if not str(terrain_stats.get("last_gpu_page_chunk_error", "")).is_empty():
		errors.append("near_gpu_page_chunk_error:%s" % str(terrain_stats))
	_clear_scene_now(scene)
	scene.queue_free()


func _clear_scene_now(scene: Node3D) -> void:
	if scene.far_clipmap != null and scene.far_clipmap.has_method("clear_levels"):
		scene.far_clipmap.call("clear_levels", true)
	scene.clear_preview()
