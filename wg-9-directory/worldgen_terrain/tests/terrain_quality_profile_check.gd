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
	var visibility: Dictionary = TerrainQualityProfileScript.visibility_contract(profile)
	if float(visibility.get("hidden_buffer_m", 0.0)) <= 0.0:
		errors.append("visibility_hidden_buffer:%.3f" % float(visibility.get("hidden_buffer_m", 0.0)))
