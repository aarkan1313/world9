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
	scene.use_far_clipmap = true
	scene.far_clipmap_rebuild_levels_per_update = 3
	scene.use_far_clipmap_native_workers = false
	get_root().add_child(scene)

	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	else:
		_check_far_surface_review(scene, errors)
		_check_parameter_only_refresh(scene, errors)
		_check_far_surface_toggle(scene, errors)
		_check_far_geometry_review(scene, errors)
		_check_far_overview_camera(scene, errors)
	scene.queue_free()
	_report_and_quit(errors)


func _check_far_surface_review(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		errors.append("far_clipmap_missing")
		return
	var stats_before: Dictionary = scene.far_clipmap.stats()
	if int(stats_before.get("levels", 0)) != 3:
		errors.append("far_levels:%d" % int(stats_before.get("levels", 0)))
	if bool(stats_before.get("use_surface_texture_material", true)):
		errors.append("far_surface_enabled_before")
	scene.apply_far_clipmap_surface_review(true, 0.7)
	var stats_after: Dictionary = scene.far_clipmap.stats()
	if not bool(stats_after.get("use_surface_texture_material", false)):
		errors.append("far_surface_disabled_after")
	if int(stats_after.get("last_surface_texture_ms", -1)) < 0:
		errors.append("far_surface_texture_ms:%d" % int(stats_after.get("last_surface_texture_ms", -1)))
	var descriptors: Array = scene.far_clipmap.active_surface_texture_descriptors()
	if descriptors.size() != 3:
		errors.append("far_descriptor_count:%d" % descriptors.size())
	for level in range(min(3, descriptors.size())):
		var descriptor: Dictionary = descriptors[level] as Dictionary
		if descriptor.get("status", "fail") != "pass":
			errors.append("far_descriptor_failed:%d:%s" % [level, str(descriptor)])
		if int(descriptor.get("level", -1)) != level:
			errors.append("far_descriptor_level:%d expected:%d" % [int(descriptor.get("level", -1)), level])
	var mesh_instance: MeshInstance3D = scene.far_clipmap.level_nodes[0] as MeshInstance3D
	var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material == null:
		errors.append("far_material_null")
		return
	var height_texture: Texture2D = material.get_shader_parameter("height_texture") as Texture2D
	var normal_texture: Texture2D = material.get_shader_parameter("normal_texture") as Texture2D
	if height_texture == null:
		errors.append("far_height_texture_null")
	if normal_texture == null:
		errors.append("far_normal_texture_null")
	if absf(float(material.get_shader_parameter("normal_strength")) - 0.7) > 0.000001:
		errors.append("far_normal_strength:%.6f" % float(material.get_shader_parameter("normal_strength")))
	var diagnostics: String = str(scene.diagnostics_text())
	if not diagnostics.contains("far 3L") or not diagnostics.contains("tex"):
		errors.append("diagnostics_missing_far_surface:%s" % diagnostics)


func _check_parameter_only_refresh(scene: Node3D, errors: Array[String]) -> void:
	var mesh_instance: MeshInstance3D = scene.far_clipmap.level_nodes[0] as MeshInstance3D
	var material_before: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material_before == null:
		errors.append("far_refresh_material_before_null")
		return
	var height_texture_before: Texture2D = material_before.get_shader_parameter("height_texture") as Texture2D
	var normal_texture_before: Texture2D = material_before.get_shader_parameter("normal_texture") as Texture2D
	scene.apply_far_clipmap_surface_review(true, 0.45)
	var material_after: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material_after != material_before:
		errors.append("far_refresh_rebuilt_material")
	var height_texture_after: Texture2D = material_after.get_shader_parameter("height_texture") as Texture2D
	var normal_texture_after: Texture2D = material_after.get_shader_parameter("normal_texture") as Texture2D
	if height_texture_after != height_texture_before:
		errors.append("far_refresh_rebuilt_height_texture")
	if normal_texture_after != normal_texture_before:
		errors.append("far_refresh_rebuilt_normal_texture")
	var stats: Dictionary = scene.far_clipmap.stats()
	if not bool(stats.get("last_surface_material_reused", false)):
		errors.append("far_refresh_not_marked_reused:%s" % str(stats))
	if int(stats.get("last_surface_texture_ms", 999)) > 1:
		errors.append("far_refresh_texture_ms:%d" % int(stats.get("last_surface_texture_ms", 999)))
	if absf(float(material_after.get_shader_parameter("normal_strength")) - 0.45) > 0.000001:
		errors.append("far_refresh_normal_strength:%.6f" % float(material_after.get_shader_parameter("normal_strength")))


func _check_far_surface_toggle(scene: Node3D, errors: Array[String]) -> void:
	scene.toggle_far_clipmap_surface_material()
	var stats: Dictionary = scene.far_clipmap.stats()
	if bool(stats.get("use_surface_texture_material", true)):
		errors.append("far_toggle_still_enabled")
	var mesh_instance: MeshInstance3D = scene.far_clipmap.level_nodes[0] as MeshInstance3D
	if mesh_instance.material_override == null:
		errors.append("far_toggle_material_null")
	if mesh_instance.material_override is ShaderMaterial:
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		var has_height_texture: Variant = material.get_shader_parameter("height_texture")
		if has_height_texture != null:
			errors.append("far_toggle_kept_height_texture")


func _check_far_geometry_review(scene: Node3D, errors: Array[String]) -> void:
	scene.far_clipmap_rebuild_levels_per_update = 4
	scene.apply_far_clipmap_geometry_review(4)
	_drain_far_clipmap(scene)
	var wide_stats: Dictionary = scene.far_clipmap.stats()
	if int(wide_stats.get("levels", 0)) != 4:
		errors.append("far_geometry_wide_levels:%d" % int(wide_stats.get("levels", 0)))
	if int(wide_stats.get("vertices", 0)) != 66564:
		errors.append("far_geometry_wide_vertices:%d" % int(wide_stats.get("vertices", 0)))
	if int(wide_stats.get("pending_rebuild_count", -1)) != 0:
		errors.append("far_geometry_wide_pending:%d" % int(wide_stats.get("pending_rebuild_count", -1)))
	var diagnostics: String = str(scene.diagnostics_text())
	if not diagnostics.contains("far 4L"):
		errors.append("diagnostics_missing_far_4L:%s" % diagnostics)
	scene.toggle_far_clipmap_wide_review()
	_drain_far_clipmap(scene)
	var default_stats: Dictionary = scene.far_clipmap.stats()
	if int(default_stats.get("levels", 0)) != 3:
		errors.append("far_geometry_default_levels:%d" % int(default_stats.get("levels", 0)))
	if int(default_stats.get("vertices", 0)) != 49923:
		errors.append("far_geometry_default_vertices:%d" % int(default_stats.get("vertices", 0)))
	diagnostics = str(scene.diagnostics_text())
	if not diagnostics.contains("far 3L"):
		errors.append("diagnostics_missing_far_3L:%s" % diagnostics)


func _drain_far_clipmap(scene: Node3D) -> void:
	for _index in range(12):
		if scene.far_clipmap == null or not scene.far_clipmap.has_pending_rebuilds():
			return
		scene.step_viewer(0.0, Vector2.ZERO, 0.0)


func _check_far_overview_camera(scene: Node3D, errors: Array[String]) -> void:
	scene.apply_far_clipmap_geometry_review(4)
	_drain_far_clipmap(scene)
	scene.frame_far_clipmap_overview()
	var expected_distance: float = 65536.0 * scene.far_clipmap_overview_distance_scale
	var expected_height: float = 65536.0 * scene.far_clipmap_overview_height_scale
	if absf(scene.camera_distance_m - expected_distance) > 0.01:
		errors.append("far_overview_distance:%.3f expected:%.3f" % [scene.camera_distance_m, expected_distance])
	if absf(scene.camera_height_m - expected_height) > 0.01:
		errors.append("far_overview_height:%.3f expected:%.3f" % [scene.camera_height_m, expected_height])
	if scene.max_camera_distance_m < expected_distance:
		errors.append("far_overview_max_distance:%.3f expected:%.3f" % [scene.max_camera_distance_m, expected_distance])
	if scene.max_camera_height_m < expected_height:
		errors.append("far_overview_max_height:%.3f expected:%.3f" % [scene.max_camera_height_m, expected_height])
	var diagnostics: String = str(scene.diagnostics_text())
	if not diagnostics.contains("far 4L"):
		errors.append("far_overview_diagnostics:%s" % diagnostics)


func _report_and_quit(errors: Array[String]) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-far-clipmap-review-controls] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-streaming-far-clipmap-review-controls] status=pass")
	quit(0)
