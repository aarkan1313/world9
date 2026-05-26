extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")
const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_walk_preview.tscn"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_saved_scene_defaults(errors)
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	if not scene.preload_active_chunks_before_start:
		errors.append("walk_review_preload_disabled")
	if scene.built_chunk_count() < scene.expected_active_count():
		errors.append("walk_review_initial_preload_incomplete:built=%d expected=%d diag=%s" % [
			scene.built_chunk_count(),
			scene.expected_active_count(),
			scene.diagnostics_text(),
		])
	if scene.review_sync_hole_fill_radius_chunks != 0:
		errors.append("walk_review_sync_fill_should_be_disabled:%d" % scene.review_sync_hole_fill_radius_chunks)
	if scene.review_sync_hole_fill_max_chunks_per_frame != 0:
		errors.append("walk_review_sync_fill_cap_should_be_zero:%d" % scene.review_sync_hole_fill_max_chunks_per_frame)
	_drain_queue(scene, errors)
	scene.camera_yaw_rad = 0.0
	scene.look_pitch_rad = 0.0
	scene._update_camera()
	var initial_ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
	var initial_camera_y: float = scene.camera.global_position.y
	if initial_camera_y < initial_ground_y + scene.fly_start_height_m - 0.01:
		errors.append("camera_not_in_free_fly:%.4f" % (initial_camera_y - initial_ground_y))
	var initial_position: Vector2 = scene.viewer_position_xz
	var base_speed: float = scene._effective_move_speed_mps()
	scene._fast_modifier_active = true
	var fast_speed: float = scene._effective_move_speed_mps()
	scene._fast_modifier_active = false
	if fast_speed < base_speed * 10.0:
		errors.append("fast_speed_multiplier:base=%.3f fast=%.3f" % [base_speed, fast_speed])
	scene.step_viewer(1.0, Vector2(0.0, 1.0), 0.0)
	_drain_queue(scene, errors)
	var forward_delta: Vector2 = scene.viewer_position_xz - initial_position
	var camera_forward_3d: Vector3 = -scene.camera.global_transform.basis.z
	var camera_forward := Vector2(camera_forward_3d.x, camera_forward_3d.z).normalized()
	if forward_delta.length() < 7.5:
		errors.append("viewer_did_not_move")
	elif forward_delta.normalized().dot(camera_forward) < 0.98:
		errors.append("forward_movement_mismatch:%.4f" % forward_delta.normalized().dot(camera_forward))
	var before_right: Vector2 = scene.viewer_position_xz
	var camera_right_3d: Vector3 = scene.camera.global_transform.basis.x
	var camera_right := Vector2(camera_right_3d.x, camera_right_3d.z).normalized()
	scene.step_viewer(1.0, Vector2(1.0, 0.0), 0.0)
	_drain_queue(scene, errors)
	var right_delta: Vector2 = scene.viewer_position_xz - before_right
	if right_delta.length() < 7.5:
		errors.append("viewer_did_not_strafe")
	elif right_delta.normalized().dot(camera_right) < 0.98:
		errors.append("right_movement_mismatch:%.4f" % right_delta.normalized().dot(camera_right))
	var yaw_before: float = scene.camera_yaw_rad
	scene.apply_mouse_look(Vector2(10.0, 0.0))
	if scene.camera_yaw_rad >= yaw_before:
		errors.append("mouse_right_did_not_match_walk_preview_yaw")
	if scene.camera == null:
		errors.append("missing_camera")
	else:
		var ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
		if scene.camera.global_position.y < ground_y + scene.fly_min_ground_clearance_m - 0.01:
			errors.append("camera_below_min_clearance:%.4f" % (scene.camera.global_position.y - ground_y))
		var before_up_y: float = scene.camera.global_position.y
		scene.step_viewer(1.0, Vector2.ZERO, 0.0, 1.0)
		if scene.camera.global_position.y <= before_up_y + scene.move_speed_mps - 0.01:
			errors.append("camera_vertical_input_failed:%.4f" % (scene.camera.global_position.y - before_up_y))
		scene.set_free_fly_enabled(false)
		var ground_camera_y: float = scene.camera.global_position.y
		var ground_y_after_toggle: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
		if scene.free_fly_enabled:
			errors.append("ground_toggle_did_not_disable_fly")
		if absf(ground_camera_y - (ground_y_after_toggle + scene.eye_height_m)) > 0.01:
			errors.append("ground_toggle_height:%.4f" % (ground_camera_y - ground_y_after_toggle))
		scene.step_viewer(1.0, Vector2.ZERO, 0.0, 1.0)
		var ground_y_after_vertical: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
		if absf(scene.camera.global_position.y - (ground_y_after_vertical + scene.eye_height_m)) > 0.01:
			errors.append("ground_vertical_input_changed_height:%.4f" % (scene.camera.global_position.y - ground_y_after_vertical))
		scene.toggle_free_fly_mode()
		if not scene.free_fly_enabled:
			errors.append("fly_toggle_did_not_enable_fly")
		var fly_ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
		if scene.camera.global_position.y < fly_ground_y + scene.fly_min_ground_clearance_m - 0.01:
			errors.append("fly_toggle_below_min_clearance:%.4f" % (scene.camera.global_position.y - fly_ground_y))
	var before_jump_position: Vector2 = scene.viewer_position_xz
	scene.jump_review_site(1)
	_drain_queue(scene, errors)
	if scene.viewer_position_xz.distance_to(before_jump_position) < scene.terrain.world.region_size_m * 0.5:
		errors.append("review_jump_too_small:%.3f" % scene.viewer_position_xz.distance_to(before_jump_position))
	var summary: Dictionary = scene._current_region_summary()
	if str(summary.get("palette", "")).is_empty():
		errors.append("missing_region_summary")
	_check_review_site_diversity(scene, errors)
	var expected_spacing: float = scene.chunk_size_m / float(scene.vertices_per_side - 1)
	if absf(expected_spacing - 4.0) > 0.001:
		errors.append("unexpected_spacing:%.3f" % expected_spacing)
	if scene.expected_active_count() != 49:
		errors.append("expected_active_count:%d" % scene.expected_active_count())
	if scene.use_lod_mesh_density:
		errors.append("walk_review_should_not_use_mixed_density_chunks")
	if scene.far_clipmap_rebuild_levels_per_update < scene.far_clipmap_level_count:
		errors.append("walk_review_far_async_budget_too_low:%d" % scene.far_clipmap_rebuild_levels_per_update)
	if not scene.use_persistent_page_clipmap:
		errors.append("walk_review_page_clipmap_disabled")
	if scene.far_clipmap_transition_fade_seconds < 0.2:
		errors.append("walk_review_page_blend_too_short:%.3f" % scene.far_clipmap_transition_fade_seconds)
	if scene.distance_fog_depth_begin_m < 29000.0:
		errors.append("walk_review_fog_too_near:%.3f" % scene.distance_fog_depth_begin_m)
	if scene.use_far_clipmap_native_workers:
		errors.append("walk_review_page_clipmap_should_not_use_mesh_workers")
	_check_far_fog_center_tracks_viewer(scene, errors)
	_check_page_clipmap_shader_contract(scene, errors)
	_check_lod_mesh_counts(scene, errors)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-walk-preview] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-terrain-walk-preview] status=pass chunks=%d spacing=%.1fm pos=%.1f,%.1f" % [
		scene.built_chunk_count(),
		expected_spacing,
		scene.viewer_position_xz.x,
		scene.viewer_position_xz.y,
	])
	quit(0)


func _check_saved_scene_defaults(errors: Array[String]) -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		errors.append("walk_scene_load_failed")
		return
	var scene: Node = packed.instantiate()
	if scene == null:
		errors.append("walk_scene_instantiate_failed")
		return
	if int(scene.get("build_budget_per_frame")) < 8:
		errors.append("walk_scene_build_budget:%d" % int(scene.get("build_budget_per_frame")))
	if int(scene.get("warmup_build_steps")) < 4:
		errors.append("walk_scene_warmup_steps:%d" % int(scene.get("warmup_build_steps")))
	if not bool(scene.get("preload_active_chunks_before_start")):
		errors.append("walk_scene_preload_disabled")
	if int(scene.get("max_native_chunk_workers")) < 6:
		errors.append("walk_scene_native_workers:%d" % int(scene.get("max_native_chunk_workers")))
	if int(scene.get("review_sync_hole_fill_radius_chunks")) != 0:
		errors.append("walk_scene_hole_fill_radius:%d" % int(scene.get("review_sync_hole_fill_radius_chunks")))
	if bool(scene.get("use_mesh_skirts")):
		errors.append("walk_scene_skirts_enabled")
	if int(scene.get("review_sync_hole_fill_max_chunks_per_frame")) != 0:
		errors.append("walk_scene_hole_fill_cap:%d" % int(scene.get("review_sync_hole_fill_max_chunks_per_frame")))
	if not bool(scene.get("use_persistent_page_clipmap")):
		errors.append("walk_scene_page_clipmap_disabled")
	if bool(scene.get("use_far_clipmap_native_workers")):
		errors.append("walk_scene_page_clipmap_workers_enabled")
	if float(scene.get("far_clipmap_transition_fade_seconds")) < 0.2:
		errors.append("walk_scene_page_blend_too_short:%.3f" % float(scene.get("far_clipmap_transition_fade_seconds")))
	if int(scene.get("far_clipmap_page_cache_max_pages")) < 64:
		errors.append("walk_scene_page_cache:%d" % int(scene.get("far_clipmap_page_cache_max_pages")))
	scene.free()


func _check_lod_mesh_counts(scene: Node3D, errors: Array[String]) -> void:
	var counts_by_lod: Dictionary = {}
	var expected_full_density_count: int = 129 * 129
	if scene.use_mesh_skirts:
		expected_full_density_count += 129 * 4 - 4
	for mesh_instance_value in scene.terrain.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		var lod: int = int(mesh_instance.get_meta("lod"))
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if mesh == null:
			errors.append("mesh_null:%s" % mesh_instance.name)
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		counts_by_lod[lod] = max(int(counts_by_lod.get(lod, 0)), vertex_count)
	for lod_value in counts_by_lod.keys():
		var expected: int = expected_full_density_count
		var actual: int = int(counts_by_lod.get(lod_value, 0))
		if actual != expected:
			errors.append("lod_%d_vertex_count:%d expected:%d counts=%s" % [int(lod_value), actual, expected, str(counts_by_lod)])


func _check_far_fog_center_tracks_viewer(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		errors.append("far_clipmap_missing_for_fog_center")
		return
	var anchor_before: Vector2 = scene._far_clipmap_center_xz()
	var fog_center_before: Vector2 = scene.far_clipmap.edge_fog_center_xz
	var viewer_before: Vector2 = scene.viewer_position_xz
	scene.step_viewer(1.0, Vector2(0.0, 1.0), 0.0)
	var anchor_after: Vector2 = scene._far_clipmap_center_xz()
	var fog_center_after: Vector2 = scene.far_clipmap.edge_fog_center_xz
	if anchor_after.distance_to(anchor_before) > 0.001:
		errors.append("far_fog_test_recentered_anchor:before=%s after=%s" % [str(anchor_before), str(anchor_after)])
	if fog_center_before.distance_to(viewer_before) > 0.001:
		errors.append("far_fog_center_not_initialized:%.3f" % fog_center_before.distance_to(viewer_before))
	if fog_center_after.distance_to(scene.viewer_position_xz) > 0.001:
		errors.append("far_fog_center_not_tracking_viewer:%.3f" % fog_center_after.distance_to(scene.viewer_position_xz))
	if fog_center_after.distance_to(fog_center_before) < 1.0:
		errors.append("far_fog_center_did_not_move_smoothly:%.3f" % fog_center_after.distance_to(fog_center_before))


func _check_page_clipmap_shader_contract(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		errors.append("page_shader_far_clipmap_missing")
		return
	if scene.far_clipmap.level_nodes.size() < 2:
		errors.append("page_shader_not_enough_levels:%d" % scene.far_clipmap.level_nodes.size())
		return
	var level0: MeshInstance3D = scene.far_clipmap.level_nodes[0] as MeshInstance3D
	var level1: MeshInstance3D = scene.far_clipmap.level_nodes[1] as MeshInstance3D
	var material0: ShaderMaterial = level0.material_override as ShaderMaterial
	var material1: ShaderMaterial = level1.material_override as ShaderMaterial
	if material0 == null or material1 == null:
		errors.append("page_shader_material_missing")
		return
	var height_texture0: Texture2D = material0.get_shader_parameter("height_texture") as Texture2D
	var height_texture1: Texture2D = material1.get_shader_parameter("height_texture") as Texture2D
	var coarse_texture: Texture2D = material0.get_shader_parameter("coarse_height_texture") as Texture2D
	if height_texture0 == null or height_texture1 == null:
		errors.append("page_shader_height_texture_missing")
	if coarse_texture == null:
		errors.append("page_shader_coarse_texture_missing")
	elif coarse_texture != height_texture1:
		errors.append("page_shader_coarse_texture_not_next_level")
	if not bool(material0.get_shader_parameter("morph_enabled")):
		errors.append("page_shader_morph_disabled")
	var page_origin: Vector2 = material0.get_shader_parameter("page_origin_m") as Vector2
	var previous_origin: Vector2 = material0.get_shader_parameter("previous_page_origin_m") as Vector2
	if page_origin.distance_to(scene.far_clipmap.level_origins[0] as Vector2) > 0.001:
		errors.append("page_shader_origin_mismatch:%s" % str(page_origin))
	if not is_finite(previous_origin.x) or not is_finite(previous_origin.y):
		errors.append("page_shader_previous_origin_invalid:%s" % str(previous_origin))
	if float(material0.get_shader_parameter("page_extent_m")) <= 0.0:
		errors.append("page_shader_extent_invalid")
	if float(material0.get_shader_parameter("previous_page_extent_m")) <= 0.0:
		errors.append("page_shader_previous_extent_invalid")
	if float(material0.get_shader_parameter("morph_band_m")) <= 0.0:
		errors.append("page_shader_morph_band_invalid")


func _check_review_site_diversity(scene: Node3D, errors: Array[String]) -> void:
	var summaries: Array = scene.review_site_summaries()
	if summaries.size() < 6:
		errors.append("review_site_count:%d" % summaries.size())
		return
	var palettes: Dictionary = {}
	var families: Dictionary = {}
	var kernels: Dictionary = {}
	for summary_value in summaries:
		var site: Dictionary = summary_value as Dictionary
		palettes[str(site.get("palette", ""))] = true
		families[str(site.get("primary_family", ""))] = true
		var kernel_a: String = str(site.get("kernel_a", ""))
		if not kernel_a.is_empty():
			kernels[kernel_a] = true
	if palettes.size() < 4:
		errors.append("review_site_palette_diversity:%d summaries:%s" % [palettes.size(), str(summaries)])
	if families.size() < 4:
		errors.append("review_site_family_diversity:%d summaries:%s" % [families.size(), str(summaries)])
	if kernels.size() < 6:
		errors.append("review_site_kernel_diversity:%d summaries:%s" % [kernels.size(), str(summaries)])


func _drain_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(180):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and native_queued == 0 and native_workers == 0 and int(scene.built_chunk_count()) >= active:
			return
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))
