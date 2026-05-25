extends SceneTree

const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 1
	scene.warmup_build_steps = 1
	scene.use_local_detail = true
	scene.local_detail_radius_patches = 0
	scene.local_detail_max_active_patches = 1
	scene.use_local_detail_workers = false
	scene.use_local_detail_surface_material = true
	scene.local_detail_surface_normal_strength = 0.70
	scene.use_local_detail_visual_displacement = true
	scene.local_detail_visual_displacement_strength = 0.40
	scene.local_detail_visual_displacement_limit_m = 2.75
	scene.enable_local_collision_bodies = true
	get_root().add_child(scene)

	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	else:
		_check_initial_detail(scene, errors)
		_check_patch_transition(scene, errors)
		_check_disabled_clear(scene, errors)
	var stats: Dictionary = scene.local_detail.build_stats() if scene.local_detail != null else {}
	scene.queue_free()
	_report_and_quit(errors, stats)


func _check_initial_detail(scene: Node3D, errors: Array[String]) -> void:
	if scene.local_detail == null:
		errors.append("local_detail_null")
		return
	if int(scene.local_detail.patch_nodes.size()) != 1:
		errors.append("initial_patch_count:%d" % int(scene.local_detail.patch_nodes.size()))
	if not scene.local_detail.patch_nodes.has("0,0"):
		errors.append("initial_missing_0_0")
	var stats: Dictionary = scene.local_detail.build_stats()
	if absf(float(stats.get("spacing_m", 0.0)) - 1.0) > 0.000001:
		errors.append("spacing:%.6f" % float(stats.get("spacing_m", 0.0)))
	if int(stats.get("vertex_count_per_patch", 0)) != 257 * 257:
		errors.append("vertex_count:%d" % int(stats.get("vertex_count_per_patch", 0)))
	if not bool(stats.get("use_surface_texture_material", false)):
		errors.append("surface_material_not_enabled")
	if not bool(stats.get("use_visual_displacement", false)):
		errors.append("visual_displacement_not_enabled")
	if absf(float(stats.get("visual_displacement_strength", -1.0)) - 0.40) > 0.000001:
		errors.append("visual_displacement_strength:%.6f" % float(stats.get("visual_displacement_strength", -1.0)))
	if absf(float(stats.get("visual_displacement_limit_m", -1.0)) - 2.75) > 0.000001:
		errors.append("visual_displacement_limit:%.6f" % float(stats.get("visual_displacement_limit_m", -1.0)))
	var patch: MeshInstance3D = scene.local_detail.patch_nodes.get("0,0", null) as MeshInstance3D
	if patch == null:
		return
	var material: ShaderMaterial = patch.material_override as ShaderMaterial
	if material == null:
		errors.append("patch_material_null")
		return
	var displacement_texture: Texture2D = material.get_shader_parameter("visual_displacement_texture") as Texture2D
	if displacement_texture == null:
		errors.append("displacement_texture_null")
	elif displacement_texture.get_width() != 257 or displacement_texture.get_height() != 257:
		errors.append("displacement_texture_size:%dx%d" % [displacement_texture.get_width(), displacement_texture.get_height()])
	var displacement_limit: float = float(material.get_shader_parameter("visual_displacement_limit_m"))
	if absf(displacement_limit - 2.75) > 0.000001:
		errors.append("material_displacement_limit:%.6f" % displacement_limit)


func _check_patch_transition(scene: Node3D, errors: Array[String]) -> void:
	scene.viewer_position_xz = Vector2(300.0, 80.0)
	var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
	if report.get("status", "fail") != "pass":
		errors.append("transition_stream_failed:%s" % str(report))
	if scene.local_detail.patch_nodes.has("0,0"):
		errors.append("old_detail_patch_not_retired")
	if not scene.local_detail.patch_nodes.has("1,0"):
		errors.append("new_detail_patch_missing")
	if scene.local_detail.collision_bodies.has("0,0"):
		errors.append("old_collision_not_retired")
	if not scene.local_detail.collision_bodies.has("1,0"):
		errors.append("new_collision_missing")
	var detail_report: Dictionary = scene.local_detail.last_report
	if int(detail_report.get("built_now", -1)) != 1:
		errors.append("transition_built:%d" % int(detail_report.get("built_now", -1)))
	if int(detail_report.get("retired_now", -1)) != 1:
		errors.append("transition_retired:%d" % int(detail_report.get("retired_now", -1)))


func _check_disabled_clear(scene: Node3D, errors: Array[String]) -> void:
	scene.local_detail.enabled = false
	var report: Dictionary = scene.local_detail.update_viewer(Vector2(300.0, 80.0))
	if report.get("status", "fail") != "pass":
		errors.append("disabled_report:%s" % str(report))
	if int(report.get("active_count", -1)) != 0:
		errors.append("disabled_active:%d" % int(report.get("active_count", -1)))
	if int(scene.local_detail.patch_nodes.size()) != 0:
		errors.append("disabled_nodes:%d" % int(scene.local_detail.patch_nodes.size()))
	if int(scene.local_detail.collision_bodies.size()) != 0:
		errors.append("disabled_collision:%d" % int(scene.local_detail.collision_bodies.size()))


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-local-detail] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-streaming-local-detail] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
