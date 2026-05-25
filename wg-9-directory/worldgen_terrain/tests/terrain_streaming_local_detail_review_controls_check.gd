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
	scene.use_local_detail = false
	scene.use_local_detail_workers = false
	get_root().add_child(scene)

	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	else:
		_check_review_mount(scene, errors)
		_check_parameter_only_refresh(scene, errors)
		_check_review_toggle(scene, errors)
	scene.queue_free()
	_report_and_quit(errors)


func _check_review_mount(scene: Node3D, errors: Array[String]) -> void:
	if scene.local_detail != null:
		errors.append("local_detail_pre_mounted")
	scene.apply_local_detail_surface_review(true, 0.85, true, 0.45, 2.5)
	if scene.local_detail == null:
		errors.append("local_detail_not_mounted")
		return
	if not scene.local_detail.patch_nodes.has("0,0"):
		errors.append("review_patch_missing")
		return
	var stats: Dictionary = scene.local_detail.build_stats()
	if not bool(stats.get("use_surface_texture_material", false)):
		errors.append("review_surface_disabled")
	if not bool(stats.get("use_visual_displacement", false)):
		errors.append("review_displacement_disabled")
	if absf(float(stats.get("visual_displacement_strength", -1.0)) - 0.45) > 0.000001:
		errors.append("review_displacement_strength:%.6f" % float(stats.get("visual_displacement_strength", -1.0)))
	if absf(float(stats.get("visual_displacement_limit_m", -1.0)) - 2.5) > 0.000001:
		errors.append("review_displacement_limit:%.6f" % float(stats.get("visual_displacement_limit_m", -1.0)))
	var patch: MeshInstance3D = scene.local_detail.patch_nodes["0,0"] as MeshInstance3D
	var material: ShaderMaterial = patch.material_override as ShaderMaterial
	if material == null:
		errors.append("review_material_null")
		return
	if absf(float(material.get_shader_parameter("normal_strength")) - 0.85) > 0.000001:
		errors.append("review_normal_strength:%.6f" % float(material.get_shader_parameter("normal_strength")))
	if absf(float(material.get_shader_parameter("visual_displacement_limit_m")) - 2.5) > 0.000001:
		errors.append("review_material_limit:%.6f" % float(material.get_shader_parameter("visual_displacement_limit_m")))
	var diagnostics: String = str(scene.diagnostics_text())
	if not diagnostics.contains("mat tex") or not diagnostics.contains("disp on"):
		errors.append("diagnostics_missing_review:%s" % diagnostics)


func _check_parameter_only_refresh(scene: Node3D, errors: Array[String]) -> void:
	var patch: MeshInstance3D = scene.local_detail.patch_nodes.get("0,0", null) as MeshInstance3D
	if patch == null:
		errors.append("refresh_patch_missing")
		return
	var material_before: ShaderMaterial = patch.material_override as ShaderMaterial
	if material_before == null:
		errors.append("refresh_material_before_null")
		return
	var displacement_texture_before: Texture2D = material_before.get_shader_parameter("visual_displacement_texture") as Texture2D
	scene.apply_local_detail_surface_review(true, 0.55, true, 0.25, 1.25)
	var material_after: ShaderMaterial = patch.material_override as ShaderMaterial
	if material_after != material_before:
		errors.append("refresh_rebuilt_material")
	var displacement_texture_after: Texture2D = material_after.get_shader_parameter("visual_displacement_texture") as Texture2D
	if displacement_texture_after != displacement_texture_before:
		errors.append("refresh_rebuilt_displacement_texture")
	var stats: Dictionary = scene.local_detail.build_stats()
	if not bool(stats.get("last_surface_material_reused", false)):
		errors.append("refresh_not_marked_reused:%s" % str(stats))
	if absf(float(material_after.get_shader_parameter("normal_strength")) - 0.55) > 0.000001:
		errors.append("refresh_normal_strength:%.6f" % float(material_after.get_shader_parameter("normal_strength")))
	if absf(float(material_after.get_shader_parameter("visual_displacement_strength")) - 0.25) > 0.000001:
		errors.append("refresh_displacement_strength:%.6f" % float(material_after.get_shader_parameter("visual_displacement_strength")))
	if absf(float(material_after.get_shader_parameter("visual_displacement_limit_m")) - 1.25) > 0.000001:
		errors.append("refresh_displacement_limit:%.6f" % float(material_after.get_shader_parameter("visual_displacement_limit_m")))


func _check_review_toggle(scene: Node3D, errors: Array[String]) -> void:
	scene.toggle_local_detail_visual_displacement()
	if bool(scene.local_detail.build_stats().get("use_visual_displacement", true)):
		errors.append("toggle_displacement_still_on")
	scene.toggle_local_detail_surface_material()
	if bool(scene.local_detail.build_stats().get("use_surface_texture_material", true)):
		errors.append("toggle_surface_still_on")
	var patch: MeshInstance3D = scene.local_detail.patch_nodes.get("0,0", null) as MeshInstance3D
	if patch == null:
		errors.append("toggle_patch_missing")
		return
	if not (patch.material_override is ShaderMaterial):
		errors.append("toggle_material_not_shader")


func _report_and_quit(errors: Array[String]) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-local-detail-review-controls] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-streaming-local-detail-review-controls] status=pass")
	quit(0)
