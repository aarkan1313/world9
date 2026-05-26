extends SceneTree

const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")

var max_drain_frames: int = 140
var max_patch_assign_ms: int = 120
var max_surface_texture_ms: int = 90
var max_param_refresh_ms: int = 20
var max_toggle_displacement_texture_ms: int = 45
var max_patch_move_update_ms: int = 35


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.LOCAL_DETAIL_REVIEW)
	_apply_profile_budgets(profile)
	var local_settings: Dictionary = profile.get("settings", {}) as Dictionary

	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 1
	scene.warmup_build_steps = 1
	scene.use_fast_gray_material = true
	_apply_local_detail_profile_settings(scene, local_settings)
	get_root().add_child(scene)

	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
		_report_and_quit(errors)
		return

	var warmup_frames: int = _drain_detail_patch(scene, "0,0", errors)
	_check_surface_perf_stats("initial", scene.local_detail.build_stats(), errors)
	_check_parameter_refresh(scene, errors)

	scene.viewer_position_xz = Vector2(300.0, 40.0)
	var move_start_ms: int = Time.get_ticks_msec()
	var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
	var move_ms: int = Time.get_ticks_msec() - move_start_ms
	if report.get("status", "fail") != "pass":
		errors.append("move_report_failed:%s" % str(report))
	if move_ms > max_patch_move_update_ms:
		errors.append("move_update_ms:%d limit:%d" % [move_ms, max_patch_move_update_ms])
	var move_drain_frames: int = _drain_detail_patch(scene, "1,0", errors)
	var final_stats: Dictionary = scene.local_detail.build_stats()
	_check_surface_perf_stats("move", final_stats, errors)
	final_stats["warmup_frames"] = warmup_frames
	final_stats["move_drain_frames"] = move_drain_frames
	final_stats["move_update_ms"] = move_ms
	scene.queue_free()
	_check_texture_then_displacement_toggle(errors, final_stats)
	_report_and_quit(errors, final_stats)


func _drain_detail_patch(scene: Node3D, key: String, errors: Array[String]) -> int:
	for index in range(max_drain_frames):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		if report.get("status", "fail") != "pass":
			errors.append("drain_report_failed:%s:%s" % [key, str(report)])
			return index + 1
		var stats: Dictionary = scene.local_detail.build_stats()
		if (
			scene.local_detail.patch_nodes.has(key)
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("queued_worker_builds", 0)) == 0
		):
			return index + 1
		OS.delay_msec(5)
	errors.append("drain_timeout:%s:%s" % [key, JSON.stringify(scene.local_detail.build_stats())])
	return max_drain_frames


func _check_surface_perf_stats(label: String, stats: Dictionary, errors: Array[String]) -> void:
	if int(stats.get("active_patches", 0)) != 1:
		errors.append("%s_active_patches:%d" % [label, int(stats.get("active_patches", 0))])
	if not bool(stats.get("use_surface_texture_material", false)):
		errors.append("%s_surface_material_disabled" % label)
	if not bool(stats.get("use_visual_displacement", false)):
		errors.append("%s_visual_displacement_disabled" % label)
	var assign_ms: int = int(stats.get("last_patch_assign_ms", 0))
	if assign_ms <= 0 or assign_ms > max_patch_assign_ms:
		errors.append("%s_assign_ms:%d limit:%d" % [label, assign_ms, max_patch_assign_ms])
	var texture_ms: int = int(stats.get("last_surface_texture_ms", 0))
	if texture_ms <= 0 or texture_ms > max_surface_texture_ms:
		errors.append("%s_surface_texture_ms:%d limit:%d" % [label, texture_ms, max_surface_texture_ms])
	var max_assign_ms: int = int(stats.get("max_recent_patch_assign_ms", 0))
	if max_assign_ms > max_patch_assign_ms:
		errors.append("%s_max_assign_ms:%d limit:%d" % [label, max_assign_ms, max_patch_assign_ms])


func _check_parameter_refresh(scene: Node3D, errors: Array[String]) -> void:
	scene.apply_local_detail_surface_review(true, 0.50, true, 0.20, 1.25)
	var stats: Dictionary = scene.local_detail.build_stats()
	if not bool(stats.get("last_surface_material_reused", false)):
		errors.append("parameter_refresh_not_reused:%s" % JSON.stringify(stats))
	var refresh_ms: int = int(stats.get("last_surface_texture_ms", 0))
	if refresh_ms > max_param_refresh_ms:
		errors.append("parameter_refresh_ms:%d limit:%d" % [refresh_ms, max_param_refresh_ms])


func _check_texture_then_displacement_toggle(errors: Array[String], stats_out: Dictionary) -> void:
	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 1
	scene.warmup_build_steps = 1
	scene.use_fast_gray_material = true
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.LOCAL_DETAIL_REVIEW)
	var local_settings: Dictionary = profile.get("settings", {}) as Dictionary
	_apply_local_detail_profile_settings(scene, local_settings)
	scene.use_local_detail_visual_displacement = false
	scene.local_detail_visual_displacement_strength = 0.0
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("toggle_setup_failed:%s" % str(scene.errors))
		scene.queue_free()
		return
	_drain_detail_patch(scene, "0,0", errors)
	var patch: MeshInstance3D = scene.local_detail.patch_nodes.get("0,0", null) as MeshInstance3D
	if patch == null:
		errors.append("toggle_patch_missing")
		scene.queue_free()
		return
	var material_before: ShaderMaterial = patch.material_override as ShaderMaterial
	if material_before == null:
		errors.append("toggle_material_before_null")
		scene.queue_free()
		return
	var displacement_before: Texture2D = material_before.get_shader_parameter("visual_displacement_texture") as Texture2D
	if displacement_before == null or displacement_before.get_width() != 1 or displacement_before.get_height() != 1:
		errors.append("toggle_before_displacement_texture:%s" % str(displacement_before))
	scene.apply_local_detail_surface_review(true, 0.75, true, 0.35, 2.0)
	var stats: Dictionary = scene.local_detail.build_stats()
	var toggle_texture_ms: int = int(stats.get("last_surface_texture_ms", 0))
	stats_out["toggle_displacement_texture_ms"] = toggle_texture_ms
	if toggle_texture_ms <= 0 or toggle_texture_ms > max_toggle_displacement_texture_ms:
		errors.append("toggle_displacement_texture_ms:%d limit:%d stats:%s" % [
			toggle_texture_ms,
			max_toggle_displacement_texture_ms,
			JSON.stringify(stats),
		])
	var material_after: ShaderMaterial = patch.material_override as ShaderMaterial
	if material_after == null:
		errors.append("toggle_material_after_null")
		scene.queue_free()
		return
	var displacement_after: Texture2D = material_after.get_shader_parameter("visual_displacement_texture") as Texture2D
	if displacement_after == null:
		errors.append("toggle_displacement_after_null")
	elif displacement_after.get_width() != 257 or displacement_after.get_height() != 257:
		errors.append("toggle_displacement_after_size:%dx%d" % [displacement_after.get_width(), displacement_after.get_height()])
	if not bool(stats.get("use_visual_displacement", false)):
		errors.append("toggle_displacement_not_enabled")
	scene.queue_free()


func _apply_profile_budgets(profile: Dictionary) -> void:
	var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
	max_drain_frames = int(budgets.get("local_detail_max_drain_frames", max_drain_frames))
	max_patch_assign_ms = int(budgets.get("local_detail_max_patch_assign_ms", max_patch_assign_ms))
	max_surface_texture_ms = int(budgets.get("local_detail_max_surface_texture_ms", max_surface_texture_ms))
	max_param_refresh_ms = int(budgets.get("local_detail_max_param_refresh_ms", max_param_refresh_ms))
	max_toggle_displacement_texture_ms = int(budgets.get("local_detail_max_toggle_displacement_texture_ms", max_toggle_displacement_texture_ms))
	max_patch_move_update_ms = int(budgets.get("local_detail_max_patch_move_update_ms", max_patch_move_update_ms))


func _apply_local_detail_profile_settings(scene: Node3D, settings: Dictionary) -> void:
	scene.use_local_detail = bool(settings.get("use_local_detail", true))
	scene.local_detail_radius_patches = int(settings.get("local_detail_radius_patches", 0))
	scene.local_detail_max_active_patches = int(settings.get("local_detail_max_active_patches", 1))
	scene.use_local_detail_workers = bool(settings.get("use_local_detail_workers", true))
	scene.use_local_detail_surface_material = bool(settings.get("use_local_detail_surface_material", true))
	scene.local_detail_surface_normal_strength = float(settings.get("local_detail_surface_normal_strength", 0.85))
	scene.use_local_detail_visual_displacement = bool(settings.get("use_local_detail_visual_displacement", true))
	scene.local_detail_visual_displacement_strength = float(settings.get("local_detail_visual_displacement_strength", 0.45))
	scene.local_detail_visual_displacement_limit_m = float(settings.get("local_detail_visual_displacement_limit_m", 2.5))
	scene.enable_local_collision_bodies = bool(settings.get("enable_local_collision_bodies", false))


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-local-detail-surface-perf] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-streaming-local-detail-surface-perf] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
