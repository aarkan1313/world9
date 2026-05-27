extends SceneTree

const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.WALK_REVIEW)
	if profile.is_empty():
		errors.append("walk_profile_missing")
	if not TerrainQualityProfileScript.profile_ids().has(TerrainQualityProfileScript.WALK_REVIEW):
		errors.append("walk_profile_not_listed")
	_check_profile_contract(profile, errors)
	_check_local_detail_profile_contract(errors)
	_check_high_density_profile_contract(errors)
	_check_gpu_page_profile_contract(errors)
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	get_root().add_child(scene)
	var pre_setup_report: Dictionary = scene.quality_profile_report()
	if pre_setup_report.get("status", "fail") != "pass":
		errors.append("walk_profile_pre_setup:%s" % str(pre_setup_report))
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var live_report: Dictionary = scene.quality_profile_report()
	if live_report.get("status", "fail") != "pass":
		errors.append("walk_profile_live:%s" % str(live_report))
	if scene.camera == null:
		errors.append("camera_missing")
	elif absf(scene.camera.far - float(TerrainQualityProfileScript.setting(profile, "camera_far_m", 0.0))) > 0.001:
		errors.append("camera_far:%.3f" % scene.camera.far)
	if scene.far_clipmap == null:
		errors.append("far_clipmap_missing")
	else:
		var visibility: Dictionary = live_report.get("visibility", {}) as Dictionary
		var budget: Dictionary = scene.far_clipmap.budget_report()
		var levels: Array = budget.get("levels", []) as Array
		if levels.is_empty():
			errors.append("far_budget_empty")
		else:
			var last_level: Dictionary = levels[levels.size() - 1] as Dictionary
			var expected_radius: float = float(last_level.get("diameter_m", 0.0)) * 0.5
			if absf(float(visibility.get("loaded_radius_m", 0.0)) - expected_radius) > 0.001:
				errors.append("visibility_loaded_radius:%.3f expected:%.3f" % [float(visibility.get("loaded_radius_m", 0.0)), expected_radius])
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-quality-profile] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-terrain-quality-profile] status=pass profile=%s visibility=%s" % [
		str(profile.get("id", "")),
		JSON.stringify(TerrainQualityProfileScript.visibility_contract(profile)),
	])
	quit(0)


func _check_profile_contract(profile: Dictionary, errors: Array[String]) -> void:
	var settings: Dictionary = profile.get("settings", {}) as Dictionary
	var required_keys: Array[String] = [
		"chunk_size_m",
		"debug_mode",
		"vertices_per_side",
		"visible_radius_chunks",
		"build_budget_per_frame",
		"prefetch_forward_chunks",
		"max_native_chunk_workers",
		"use_far_clipmap",
		"far_clipmap_level_count",
		"far_clipmap_base_outer_extent_m",
		"far_clipmap_rebuild_levels_per_update",
		"use_persistent_page_clipmap",
		"far_clipmap_gpu_page_residency_max_pages",
		"use_far_clipmap_gpu_page_normal_backend",
		"use_far_clipmap_gpu_rd_page_textures",
		"use_far_clipmap_gpu_rd_compute_normals",
		"use_far_clipmap_gpu_provider_page_textures",
		"distance_fog_depth_begin_m",
		"distance_fog_depth_end_m",
		"camera_far_m",
	]
	for key in required_keys:
		if not settings.has(key):
			errors.append("missing_setting:%s" % key)
	if int(settings.get("far_clipmap_rebuild_levels_per_update", 0)) < int(settings.get("far_clipmap_level_count", 0)):
		errors.append("rebuild_budget_below_level_count")
	if not bool(settings.get("use_persistent_page_clipmap", false)):
		errors.append("profile_page_clipmap_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_page_normal_backend", false)):
		errors.append("walk_profile_gpu_normal_backend_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_rd_page_textures", false)):
		errors.append("walk_profile_rd_textures_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_rd_compute_normals", false)):
		errors.append("walk_profile_rd_compute_normals_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_provider_page_textures", false)):
		errors.append("walk_profile_gpu_provider_page_textures_disabled")
	var visibility: Dictionary = TerrainQualityProfileScript.visibility_contract(profile)
	if float(visibility.get("hidden_buffer_m", 0.0)) <= 0.0:
		errors.append("visibility_hidden_buffer:%.3f" % float(visibility.get("hidden_buffer_m", 0.0)))


func _check_local_detail_profile_contract(errors: Array[String]) -> void:
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.LOCAL_DETAIL_REVIEW)
	if profile.is_empty():
		errors.append("local_detail_profile_missing")
		return
	if not TerrainQualityProfileScript.profile_ids().has(TerrainQualityProfileScript.LOCAL_DETAIL_REVIEW):
		errors.append("local_detail_profile_not_listed")
	var settings: Dictionary = profile.get("settings", {}) as Dictionary
	var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
	var required_keys: Array[String] = [
		"use_local_detail",
		"local_detail_radius_patches",
		"local_detail_max_active_patches",
		"use_local_detail_workers",
		"use_local_detail_surface_material",
		"local_detail_surface_normal_strength",
		"use_local_detail_visual_displacement",
		"local_detail_visual_displacement_strength",
		"local_detail_visual_displacement_limit_m",
		"enable_local_collision_bodies",
	]
	for key in required_keys:
		if not settings.has(key):
			errors.append("local_detail_missing_setting:%s" % key)
	if not bool(profile.get("review_only", false)):
		errors.append("local_detail_profile_not_review_only")
	if not bool(settings.get("use_local_detail", false)):
		errors.append("local_detail_profile_disabled")
	if int(settings.get("local_detail_max_active_patches", 0)) != 1:
		errors.append("local_detail_profile_patch_budget:%d" % int(settings.get("local_detail_max_active_patches", 0)))
	if not bool(settings.get("use_local_detail_surface_material", false)):
		errors.append("local_detail_profile_surface_disabled")
	if not bool(settings.get("use_local_detail_visual_displacement", false)):
		errors.append("local_detail_profile_displacement_disabled")
	if bool(settings.get("enable_local_collision_bodies", true)):
		errors.append("local_detail_profile_collision_enabled")
	var required_budgets: Array[String] = [
		"local_detail_max_drain_frames",
		"local_detail_max_patch_assign_ms",
		"local_detail_max_surface_texture_ms",
		"local_detail_max_param_refresh_ms",
		"local_detail_max_toggle_displacement_texture_ms",
		"local_detail_max_patch_move_update_ms",
	]
	for key in required_budgets:
		if int(budgets.get(key, 0)) <= 0:
			errors.append("local_detail_missing_budget:%s" % key)
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.quality_profile_id = TerrainQualityProfileScript.LOCAL_DETAIL_REVIEW
	TerrainQualityProfileScript.apply_to_node(scene, profile)
	get_root().add_child(scene)
	var pre_setup_report: Dictionary = scene.quality_profile_report()
	if pre_setup_report.get("status", "fail") != "pass":
		errors.append("local_detail_profile_pre_setup:%s" % str(pre_setup_report))
	if not scene.setup():
		errors.append("local_detail_profile_setup_failed:%s" % str(scene.errors))
	else:
		var live_report: Dictionary = scene.quality_profile_report()
		if live_report.get("status", "fail") != "pass":
			errors.append("local_detail_profile_live:%s" % str(live_report))
		if scene.local_detail == null:
			errors.append("local_detail_profile_node_missing")
		else:
			var stats: Dictionary = scene.local_detail.build_stats()
			if not bool(stats.get("use_surface_texture_material", false)):
				errors.append("local_detail_profile_node_surface_disabled")
			if not bool(stats.get("use_visual_displacement", false)):
				errors.append("local_detail_profile_node_displacement_disabled")
			if bool(stats.get("collision_enabled", true)):
				errors.append("local_detail_profile_node_collision_enabled")
	scene.queue_free()


func _check_gpu_page_profile_contract(errors: Array[String]) -> void:
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.GPU_PAGE_REVIEW)
	if profile.is_empty():
		errors.append("gpu_page_profile_missing")
		return
	if not TerrainQualityProfileScript.profile_ids().has(TerrainQualityProfileScript.GPU_PAGE_REVIEW):
		errors.append("gpu_page_profile_not_listed")
	if not bool(profile.get("review_only", false)):
		errors.append("gpu_page_profile_not_review_only")
	var settings: Dictionary = profile.get("settings", {}) as Dictionary
	if not bool(settings.get("use_far_clipmap_gpu_page_normal_backend", false)):
		errors.append("gpu_page_profile_normal_backend_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_rd_page_textures", false)):
		errors.append("gpu_page_profile_rd_textures_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_rd_compute_normals", false)):
		errors.append("gpu_page_profile_rd_compute_normals_disabled")
	if not bool(settings.get("use_far_clipmap_gpu_provider_page_textures", false)):
		errors.append("gpu_page_profile_provider_page_textures_disabled")
	var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
	if int(budgets.get("gpu_page_review_max_image_uploads", -1)) != 0:
		errors.append("gpu_page_profile_image_budget:%s" % str(budgets))
	if int(budgets.get("gpu_page_review_min_rd_uploads", 0)) <= 0:
		errors.append("gpu_page_profile_rd_budget:%s" % str(budgets))
	if int(budgets.get("gpu_page_review_min_normal_dispatches", -1)) < 0:
		errors.append("gpu_page_profile_normal_budget:%s" % str(budgets))
	if int(budgets.get("gpu_page_review_min_rd_compute_normal_uploads", 0)) <= 0:
		errors.append("gpu_page_profile_rd_compute_normal_budget:%s" % str(budgets))
	if int(budgets.get("gpu_page_review_min_provider_page_dispatches", -1)) < 0:
		errors.append("gpu_page_profile_provider_dispatch_budget:%s" % str(budgets))
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.quality_profile_id = TerrainQualityProfileScript.GPU_PAGE_REVIEW
	TerrainQualityProfileScript.apply_to_node(scene, profile)
	get_root().add_child(scene)
	var pre_setup_report: Dictionary = scene.quality_profile_report()
	if pre_setup_report.get("status", "fail") != "pass":
		errors.append("gpu_page_profile_pre_setup:%s" % str(pre_setup_report))
	if not scene.setup():
		errors.append("gpu_page_profile_setup_failed:%s" % str(scene.errors))
	else:
		var live_report: Dictionary = scene.quality_profile_report()
		if live_report.get("status", "fail") != "pass":
			errors.append("gpu_page_profile_live:%s" % str(live_report))
		if scene.far_clipmap == null:
			errors.append("gpu_page_profile_far_missing")
		else:
			var stats: Dictionary = scene.far_clipmap.stats()
			var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
			if not bool(gpu_state.get("use_rd_textures", false)):
				errors.append("gpu_page_profile_rd_not_configured:%s" % str(gpu_state))
			if not bool(gpu_state.get("use_rd_compute_normals", false)):
				errors.append("gpu_page_profile_rd_compute_not_configured:%s" % str(gpu_state))
			if _rendering_device_available():
				var min_provider_dispatches: int = int(budgets.get("gpu_page_review_min_provider_page_dispatches", 0))
				if int(stats.get("total_gpu_provider_page_dispatches", 0)) < min_provider_dispatches:
					errors.append("gpu_page_profile_provider_dispatches:%s" % str(stats))
				if str(stats.get("last_gpu_provider_page_error", "")) != "":
					errors.append("gpu_page_profile_provider_error:%s" % str(stats))
	scene.queue_free()


func _check_high_density_profile_contract(errors: Array[String]) -> void:
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.HIGH_DENSITY_257_REVIEW)
	if profile.is_empty():
		errors.append("high_density_profile_missing")
		return
	if not TerrainQualityProfileScript.profile_ids().has(TerrainQualityProfileScript.HIGH_DENSITY_257_REVIEW):
		errors.append("high_density_profile_not_listed")
	var settings: Dictionary = profile.get("settings", {}) as Dictionary
	var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
	if not bool(profile.get("review_only", false)):
		errors.append("high_density_profile_not_review_only")
	if int(settings.get("vertices_per_side", 0)) != 257:
		errors.append("high_density_vertices:%d" % int(settings.get("vertices_per_side", 0)))
	if int(settings.get("visible_radius_chunks", 0)) != 3:
		errors.append("high_density_radius:%d" % int(settings.get("visible_radius_chunks", 0)))
	if int(settings.get("build_budget_per_frame", 0)) > 2:
		errors.append("high_density_build_budget:%d" % int(settings.get("build_budget_per_frame", 0)))
	if bool(settings.get("preload_active_chunks_before_start", true)):
		errors.append("high_density_preload_enabled")
	var required_budgets: Array[String] = [
		"high_density_max_drain_steps",
		"high_density_max_setup_ms",
		"high_density_max_avg_build_ms",
		"high_density_max_native_payload_ms",
		"high_density_max_move_step_ms",
	]
	for key in required_budgets:
		if float(budgets.get(key, 0.0)) <= 0.0:
			errors.append("high_density_missing_budget:%s" % key)
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.quality_profile_id = TerrainQualityProfileScript.HIGH_DENSITY_257_REVIEW
	TerrainQualityProfileScript.apply_to_node(scene, profile)
	get_root().add_child(scene)
	var pre_setup_report: Dictionary = scene.quality_profile_report()
	if pre_setup_report.get("status", "fail") != "pass":
		errors.append("high_density_profile_pre_setup:%s" % str(pre_setup_report))
	if not scene.setup():
		errors.append("high_density_profile_setup_failed:%s" % str(scene.errors))
	else:
		var live_report: Dictionary = scene.quality_profile_report()
		if live_report.get("status", "fail") != "pass":
			errors.append("high_density_profile_live:%s" % str(live_report))
		if scene.vertices_per_side != 257:
			errors.append("high_density_scene_vertices:%d" % scene.vertices_per_side)
		var spacing_m: float = scene.chunk_size_m / float(max(1, scene.vertices_per_side - 1))
		if absf(spacing_m - 2.0) > 0.0001:
			errors.append("high_density_spacing:%.6f" % spacing_m)
	scene.queue_free()


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)
