class_name TerrainStreamingPreviewScene
extends Node3D

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")
const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")

@export_enum("gray", "elevation_color", "chunk_id", "lod_ring", "height_bands", "seam", "family_palette", "hydrology") var debug_mode: String = TerrainWorldScript.DEBUG_GRAY
@export_range(17, 257, 16) var vertices_per_side: int = 33
@export_range(1, 5, 1) var visible_radius_chunks: int = 1
@export_range(1, 16, 1) var build_budget_per_frame: int = 1
@export_range(0, 3, 1) var prefetch_forward_chunks: int = 0
@export_range(1, 6, 1) var max_lod: int = 4
@export_range(0, 24, 1) var warmup_build_steps: int = 3
@export var preload_active_chunks_before_start: bool = false
@export_range(0, 256, 1) var preload_active_chunk_limit: int = 0
@export var auto_setup_on_ready: bool = true
@export var seed: int = 1337
@export var chunk_size_m: float = TerrainSettingsScript.CHUNK_SIZE_M
@export var move_speed_mps: float = 1800.0
@export var fast_multiplier: float = 3.0
@export var slow_multiplier: float = 0.25
@export var camera_height_m: float = 1900.0
@export var camera_distance_m: float = 3300.0
@export var camera_yaw_deg: float = 42.0
@export var camera_zoom_step: float = 1.12
@export var min_camera_distance_m: float = 700.0
@export var max_camera_distance_m: float = 18000.0
@export var min_camera_height_m: float = 450.0
@export var max_camera_height_m: float = 12000.0
@export var camera_height_distance_ratio: float = 0.58
@export var camera_far_m: float = 120000.0
@export var far_clipmap_overview_distance_scale: float = 0.62
@export var far_clipmap_overview_height_scale: float = 0.38
@export var use_distance_fog: bool = true
@export_range(0.0, 0.002, 0.00001) var distance_fog_density: float = 0.0
@export var distance_fog_depth_begin_m: float = 24000.0
@export var distance_fog_depth_end_m: float = 33000.0
@export var distance_fog_color: Color = Color(0.18, 0.18, 0.18)
@export var build_when_idle: bool = false
@export var warm_load_start_region_kernels: bool = false
@export var show_diagnostics_overlay: bool = true
@export var use_fast_gray_material: bool = true
@export var fast_gray_exposure: float = 1.0
@export var fast_gray_contrast: float = 1.0
@export var use_native_chunk_payloads: bool = false
@export var use_native_chunk_workers: bool = false
@export_range(1, 8, 1) var max_native_chunk_workers: int = 2
@export_range(0, 4, 1) var review_sync_hole_fill_radius_chunks: int = 0
@export_range(0, 256, 1) var review_sync_hole_fill_max_chunks_per_frame: int = 0
@export var use_lod_mesh_density: bool = false
@export var use_mesh_skirts: bool = false
@export var mesh_skirt_depth_m: float = 50.0
@export var use_far_clipmap: bool = false
@export var far_clipmap_debug_levels: bool = false
@export_range(1, 6, 1) var far_clipmap_level_count: int = 3
@export var far_clipmap_base_spacing_m: float = 64.0
@export var far_clipmap_base_outer_extent_m: float = 4096.0
@export var far_clipmap_handoff_overlap_m: float = 64.0
@export var far_clipmap_visual_y_bias_per_level_m: float = -4.0
@export var far_clipmap_full_underlay_level0: bool = false
@export var far_clipmap_recenter_distance_m: float = 768.0
@export_range(1, 16, 1) var far_clipmap_rebuild_levels_per_update: int = 1
@export_range(0.0, 3.0, 0.05) var far_clipmap_transition_fade_seconds: float = 0.45
@export var use_far_clipmap_native_workers: bool = true
@export var use_persistent_page_clipmap: bool = false
@export_range(0, 256, 1) var far_clipmap_page_cache_max_pages: int = 48
@export_range(0, 256, 1) var far_clipmap_gpu_page_residency_max_pages: int = 48
@export var use_far_clipmap_surface_material: bool = false
@export_range(0.0, 4.0, 0.05) var far_clipmap_surface_normal_strength: float = 1.0
@export var use_local_detail: bool = false
@export_range(0, 2, 1) var local_detail_radius_patches: int = 0
@export_range(1, 25, 1) var local_detail_max_active_patches: int = 1
@export var use_local_detail_workers: bool = true
@export var use_local_detail_surface_material: bool = false
@export_range(0.0, 4.0, 0.05) var local_detail_surface_normal_strength: float = 1.0
@export var use_local_detail_visual_displacement: bool = false
@export_range(0.0, 1.0, 0.01) var local_detail_visual_displacement_strength: float = 0.0
@export_range(0.0, 16.0, 0.25) var local_detail_visual_displacement_limit_m: float = 2.0
@export var enable_local_collision_bodies: bool = false
@export_enum("balanced_current", "strong_mountains", "compressed_scale") var landform_profile_id: String = TerrainLandformProfileScript.BALANCED_CURRENT

var terrain: Node3D
var far_clipmap: Node3D
var local_detail: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var diagnostics_layer: CanvasLayer
var diagnostics_label: Label
var viewer_position_xz := Vector2.ZERO
var camera_yaw_rad: float = 0.0
var last_stream_report: Dictionary = {}
var errors: Array[String] = []
var last_review_sync_fill_count: int = 0
var last_preload_chunk_count: int = 0
var _stream_priority_direction := Vector2.ZERO
var _surface_toggle_down: bool = false
var _displacement_toggle_down: bool = false
var _far_surface_toggle_down: bool = false
var _far_geometry_toggle_down: bool = false
var _far_camera_toggle_down: bool = false
var _far_clipmap_anchor_xz := Vector2(INF, INF)
var _fast_modifier_active: bool = false
var _slow_modifier_active: bool = false
var _far_clipmap_config_key: String = ""
var quality_profile_id: String = ""


func _ready() -> void:
	if auto_setup_on_ready:
		setup()


func _process(delta: float) -> void:
	var yaw_delta := 0.0
	if Input.is_key_pressed(KEY_Q):
		yaw_delta -= 1.0
	if Input.is_key_pressed(KEY_E):
		yaw_delta += 1.0
	if Input.is_key_pressed(KEY_Z):
		_zoom_camera(1.0 / pow(camera_zoom_step, delta * 8.0))
	if Input.is_key_pressed(KEY_X):
		_zoom_camera(pow(camera_zoom_step, delta * 8.0))
	if Input.is_key_pressed(KEY_R):
		_raise_camera(delta)
	if Input.is_key_pressed(KEY_F):
		_lower_camera(delta)
	var movement := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y -= 1.0
	var speed_scale: float = _current_speed_scale()
	_apply_debug_key_input()
	_apply_local_detail_review_key_input()
	if movement.length_squared() > 0.000001 or absf(yaw_delta) > 0.000001 or build_when_idle or _has_pending_visual_work():
		step_viewer(delta * speed_scale, movement, yaw_delta * delta * 1.8)
	_update_diagnostics()


func _input(event: InputEvent) -> void:
	_update_speed_modifier_state(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.0 / camera_zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(camera_zoom_step)


func setup() -> bool:
	clear_preview()
	errors.clear()
	camera_yaw_rad = deg_to_rad(camera_yaw_deg)
	if prefetch_forward_chunks > 0:
		_stream_priority_direction = Vector2(sin(camera_yaw_rad), cos(camera_yaw_rad)).normalized()
	terrain = TerrainWorldNodeScript.new()
	terrain.name = "StreamingTerrainWorldNode"
	terrain.auto_setup_on_ready = false
	terrain.vertices_per_side = vertices_per_side
	terrain.debug_mode = debug_mode
	terrain.use_fast_gray_material = use_fast_gray_material
	terrain.fast_gray_exposure = fast_gray_exposure
	terrain.fast_gray_contrast = fast_gray_contrast
	terrain.use_native_chunk_payloads = use_native_chunk_payloads
	terrain.use_native_chunk_workers = use_native_chunk_workers
	terrain.max_native_chunk_workers = max_native_chunk_workers
	terrain.use_lod_mesh_density = use_lod_mesh_density
	terrain.use_mesh_skirts = use_mesh_skirts
	terrain.mesh_skirt_depth_m = mesh_skirt_depth_m
	terrain.apply_edge_fog(use_distance_fog, distance_fog_depth_begin_m, distance_fog_depth_end_m, distance_fog_color)
	add_child(terrain)
	if not terrain.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, seed):
		for error in terrain.errors:
			errors.append(str(error))
		return false
	if not apply_landform_profile(landform_profile_id, false):
		errors.append("landform_profile_setup_failed:%s" % landform_profile_id)
		return false
	if warm_load_start_region_kernels:
		_warm_load_visible_region_kernels()
	if use_far_clipmap:
		far_clipmap = TerrainFarClipmapNodeScript.new()
		far_clipmap.name = "FarClipmapVisual"
		_configure_far_clipmap_node()
		add_child(far_clipmap)
		if not far_clipmap.setup(terrain.world):
			errors.append("far_clipmap_setup_failed")
			return false
	if use_local_detail:
		if not _ensure_local_detail_node():
			return false
	terrain.world.configure_streamer({
		"chunk_size_m": chunk_size_m,
		"visible_radius_chunks": visible_radius_chunks,
		"max_lod": max_lod,
		"build_budget_per_frame": build_budget_per_frame,
		"prefetch_forward_chunks": prefetch_forward_chunks,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	_add_light()
	_add_environment()
	_add_camera()
	if show_diagnostics_overlay:
		_add_diagnostics_overlay()
	for _index in range(max(1, warmup_build_steps)):
		_update_streamer()
	_preload_chunks_before_start()
	_preload_far_clipmap_before_start()
	_update_camera()
	_update_diagnostics()
	return true


func clear_preview() -> void:
	for child in get_children():
		child.queue_free()
	terrain = null
	far_clipmap = null
	local_detail = null
	camera = null
	sun = null
	environment = null
	diagnostics_layer = null
	diagnostics_label = null
	last_stream_report.clear()
	last_review_sync_fill_count = 0
	last_preload_chunk_count = 0
	_stream_priority_direction = Vector2.ZERO
	_far_clipmap_anchor_xz = Vector2(INF, INF)
	_far_clipmap_config_key = ""


func step_viewer(delta: float, movement: Vector2, yaw_delta: float = 0.0) -> Dictionary:
	if terrain == null:
		return {"status": "fail", "errors": ["terrain_not_setup"]}
	camera_yaw_rad += yaw_delta
	if movement.length_squared() > 0.000001:
		var normalized := movement.normalized()
		var forward := Vector2(sin(camera_yaw_rad), cos(camera_yaw_rad))
		var right := Vector2(forward.y, -forward.x)
		var world_direction: Vector2 = (right * normalized.x + forward * normalized.y).normalized()
		_stream_priority_direction = world_direction
		viewer_position_xz += world_direction * move_speed_mps * delta
	var report := _update_streamer()
	_update_camera()
	return report


func apply_debug_mode(mode: String) -> void:
	debug_mode = mode
	if terrain != null:
		terrain.apply_debug_mode(mode)
	if far_clipmap != null:
		_configure_far_clipmap_node()


func apply_landform_profile(profile_id: String, rebuild_existing: bool = true) -> bool:
	landform_profile_id = profile_id
	if terrain == null or terrain.world == null:
		return true
	var applied := false
	if terrain.has_method("apply_landform_profile"):
		applied = bool(terrain.call("apply_landform_profile", profile_id))
	elif terrain.world.has_method("apply_landform_profile"):
		applied = bool(terrain.world.call("apply_landform_profile", profile_id))
	if not applied:
		return false
	if rebuild_existing:
		if terrain.has_method("clear_native_worker_backlog_for_preview"):
			terrain.call("clear_native_worker_backlog_for_preview")
		if terrain.has_method("rebuild_all_active_for_preview"):
			terrain.call("rebuild_all_active_for_preview", 0)
		if far_clipmap != null:
			if not far_clipmap.setup(terrain.world):
				errors.append("far_clipmap_profile_rebuild_failed:%s" % profile_id)
				return false
			_preload_far_clipmap_before_start()
		if local_detail != null:
			local_detail.clear_patches()
		_update_camera()
		_update_diagnostics()
	return true


func landform_profile_report() -> Dictionary:
	if terrain == null or terrain.world == null or not terrain.world.has_method("landform_profile_report"):
		return {}
	return terrain.world.call("landform_profile_report") as Dictionary


func expected_active_count() -> int:
	if not last_stream_report.is_empty():
		return int(last_stream_report.get("expected_active_count", last_stream_report.get("active_count", 0)))
	return (visible_radius_chunks * 2 + 1) * (visible_radius_chunks * 2 + 1)


func built_chunk_count() -> int:
	return terrain.built_chunk_count() if terrain != null else 0


func apply_local_detail_surface_review(
	surface_material_enabled: bool,
	normal_strength: float,
	visual_displacement_enabled: bool,
	displacement_strength: float,
	displacement_limit_m: float
) -> void:
	use_local_detail_surface_material = surface_material_enabled
	local_detail_surface_normal_strength = max(0.0, normal_strength)
	use_local_detail_visual_displacement = visual_displacement_enabled
	local_detail_visual_displacement_strength = clampf(displacement_strength, 0.0, 1.0)
	local_detail_visual_displacement_limit_m = max(0.0, displacement_limit_m)
	if local_detail == null and (surface_material_enabled or visual_displacement_enabled):
		use_local_detail = true
		if not _ensure_local_detail_node():
			return
	if local_detail != null:
		local_detail.apply_surface_material_settings(
			use_local_detail_surface_material,
			local_detail_surface_normal_strength,
			use_local_detail_visual_displacement,
			local_detail_visual_displacement_strength,
			local_detail_visual_displacement_limit_m,
			true
		)
		local_detail.update_viewer(viewer_position_xz)


func toggle_local_detail_surface_material() -> void:
	apply_local_detail_surface_review(
		not use_local_detail_surface_material,
		local_detail_surface_normal_strength,
		use_local_detail_visual_displacement,
		local_detail_visual_displacement_strength,
		local_detail_visual_displacement_limit_m
	)


func toggle_local_detail_visual_displacement() -> void:
	var enable_displacement: bool = not use_local_detail_visual_displacement
	apply_local_detail_surface_review(
		true if enable_displacement else use_local_detail_surface_material,
		local_detail_surface_normal_strength,
		enable_displacement,
		max(local_detail_visual_displacement_strength, 0.35) if enable_displacement else local_detail_visual_displacement_strength,
		local_detail_visual_displacement_limit_m
	)


func apply_far_clipmap_surface_review(surface_material_enabled: bool, normal_strength: float) -> void:
	use_far_clipmap_surface_material = surface_material_enabled
	far_clipmap_surface_normal_strength = max(0.0, normal_strength)
	if far_clipmap == null:
		return
	far_clipmap.apply_surface_material_settings(
		use_far_clipmap_surface_material,
		far_clipmap_surface_normal_strength,
		true
	)


func toggle_far_clipmap_surface_material() -> void:
	apply_far_clipmap_surface_review(
		not use_far_clipmap_surface_material,
		far_clipmap_surface_normal_strength
	)


func apply_far_clipmap_geometry_review(levels: int, base_spacing_m: float = 64.0, base_outer_extent_m: float = 4096.0) -> void:
	far_clipmap_level_count = clampi(levels, 1, 6)
	far_clipmap_base_spacing_m = max(0.000001, base_spacing_m)
	far_clipmap_base_outer_extent_m = max(far_clipmap_base_spacing_m, base_outer_extent_m)
	if far_clipmap == null:
		return
	_configure_far_clipmap_node()
	far_clipmap.near_hole_extent_m = _far_clipmap_near_hole_extent_m()
	far_clipmap.update_viewer(_far_clipmap_center_xz())
	_update_diagnostics()


func toggle_far_clipmap_wide_review() -> void:
	var next_level_count := 4 if far_clipmap_level_count <= 3 else 3
	apply_far_clipmap_geometry_review(
		next_level_count,
		far_clipmap_base_spacing_m,
		far_clipmap_base_outer_extent_m
	)


func frame_far_clipmap_overview() -> void:
	if far_clipmap == null:
		return
	var budget: Dictionary = far_clipmap.budget_report()
	var levels: Array = budget.get("levels", []) as Array
	if levels.is_empty():
		return
	var last_level: Dictionary = levels[levels.size() - 1] as Dictionary
	var diameter_m: float = float(last_level.get("diameter_m", 0.0))
	var wanted_distance: float = diameter_m * max(0.01, far_clipmap_overview_distance_scale)
	var wanted_height: float = diameter_m * max(0.01, far_clipmap_overview_height_scale)
	max_camera_distance_m = max(max_camera_distance_m, wanted_distance)
	max_camera_height_m = max(max_camera_height_m, wanted_height)
	camera_distance_m = clampf(wanted_distance, min_camera_distance_m, max_camera_distance_m)
	camera_height_m = clampf(wanted_height, min_camera_height_m, max_camera_height_m)
	_update_camera()
	_update_diagnostics()


func diagnostics_text() -> String:
	var active_count: int = int(last_stream_report.get("active_count", 0))
	var queued_count: int = int(last_stream_report.get("queued_build_count", 0))
	var created_count: int = int(last_stream_report.get("created_count", 0))
	var retired_count: int = int(last_stream_report.get("retired_count", 0))
	var viewer_chunk: Array = last_stream_report.get("viewer_chunk", [0, 0]) as Array
	var fps: float = Engine.get_frames_per_second()
	var stats: Dictionary = terrain.build_stats() if terrain != null else {}
	var spacing_m: float = chunk_size_m / float(max(1, vertices_per_side - 1))
	var clipmap_stats: Dictionary = far_clipmap.stats() if far_clipmap != null else {}
	var detail_stats: Dictionary = local_detail.build_stats() if local_detail != null else {}
	return "fps %.0f | chunks %d/%d | queue %d+%d | workers %d | fill %d preload %d | build %.0fms avg %.0fms h %.0fms mesh %.0fms | far %dL %.0fms t%.0fms %s p%d w%d | detail %d b%.0f/a%.0f/t%.0fms mat %s disp %s %.2f/%.1fm | pool %d | vtx %d step %.0fm | cam %.0fm/%.0fm | mode %s | viewer %d,%d | delta +%d -%d" % [
		fps,
		built_chunk_count(),
		active_count,
		queued_count,
		int(stats.get("queued_native_worker_builds", 0)),
		int(stats.get("active_native_workers", 0)),
		last_review_sync_fill_count,
		last_preload_chunk_count,
		float(stats.get("last_chunk_build_ms", 0.0)),
		float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		float(stats.get("last_height_grid_ms", 0.0)),
		float(stats.get("last_native_mesh_payload_ms", 0.0)),
		int(clipmap_stats.get("levels", 0)),
		float(clipmap_stats.get("last_build_ms", 0.0)),
		float(clipmap_stats.get("last_surface_texture_ms", 0.0)),
		"tex" if bool(clipmap_stats.get("use_surface_texture_material", false)) else "base",
		int(clipmap_stats.get("pending_rebuild_count", 0)),
		int(clipmap_stats.get("active_worker_count", 0)),
		int(detail_stats.get("active_patches", 0)),
		float(detail_stats.get("last_build_ms", 0.0)),
		float(detail_stats.get("last_patch_assign_ms", 0.0)),
		float(detail_stats.get("last_surface_texture_ms", 0.0)),
		"tex" if bool(detail_stats.get("use_surface_texture_material", false)) else "base",
		"on" if bool(detail_stats.get("use_visual_displacement", false)) else "off",
		float(detail_stats.get("visual_displacement_strength", 0.0)),
		float(detail_stats.get("visual_displacement_limit_m", 0.0)),
		int(stats.get("pooled_chunks", 0)),
		vertices_per_side,
		spacing_m,
		camera_distance_m,
		camera_height_m,
		debug_mode,
		int(viewer_chunk[0]),
		int(viewer_chunk[1]),
		created_count,
		retired_count,
	]


func _current_speed_scale() -> float:
	var speed_scale := 1.0
	if _is_fast_modifier_down():
		speed_scale *= fast_multiplier
	if _is_slow_modifier_down():
		speed_scale *= slow_multiplier
	return speed_scale


func _effective_move_speed_mps() -> float:
	return move_speed_mps * _current_speed_scale()


func _is_fast_modifier_down() -> bool:
	return _fast_modifier_active or Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)


func _is_slow_modifier_down() -> bool:
	return _slow_modifier_active or Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_CTRL)


func _update_speed_modifier_state(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null:
		_fast_modifier_active = key_event.shift_pressed
		_slow_modifier_active = key_event.ctrl_pressed
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		_fast_modifier_active = mouse_button.shift_pressed
		_slow_modifier_active = mouse_button.ctrl_pressed
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		_fast_modifier_active = mouse_motion.shift_pressed
		_slow_modifier_active = mouse_motion.ctrl_pressed


func _update_streamer() -> Dictionary:
	if terrain != null and terrain.has_method("set_stream_priority_direction"):
		terrain.call("set_stream_priority_direction", _stream_priority_direction)
	last_stream_report = terrain.update_viewer(viewer_position_xz)
	_fill_near_chunk_holes_for_review()
	if far_clipmap != null:
		_configure_far_clipmap_node()
		far_clipmap.near_hole_extent_m = _far_clipmap_near_hole_extent_m()
		if far_clipmap.has_method("set_edge_fog_center_xz"):
			far_clipmap.call("set_edge_fog_center_xz", viewer_position_xz)
		far_clipmap.update_viewer(_far_clipmap_center_xz())
	if use_local_detail and local_detail == null:
		_ensure_local_detail_node()
	if local_detail != null:
		local_detail.update_viewer(viewer_position_xz)
	return last_stream_report


func _preload_chunks_before_start() -> void:
	last_preload_chunk_count = 0
	if not preload_active_chunks_before_start or terrain == null:
		return
	if last_stream_report.is_empty():
		last_stream_report = terrain.update_viewer(viewer_position_xz)
	if terrain.has_method("clear_native_worker_backlog_for_preview"):
		terrain.call("clear_native_worker_backlog_for_preview")
	if terrain.has_method("rebuild_all_active_for_preview"):
		last_preload_chunk_count = int(terrain.call("rebuild_all_active_for_preview", preload_active_chunk_limit))


func _preload_far_clipmap_before_start() -> void:
	if far_clipmap == null:
		return
	var previous_workers: bool = far_clipmap.use_native_workers
	var previous_budget: int = far_clipmap.max_rebuild_levels_per_update
	far_clipmap.use_native_workers = false
	far_clipmap.max_rebuild_levels_per_update = max(previous_budget, far_clipmap_level_count)
	far_clipmap.update_viewer(_far_clipmap_center_xz())
	far_clipmap.use_native_workers = previous_workers
	far_clipmap.max_rebuild_levels_per_update = previous_budget


func _fill_near_chunk_holes_for_review() -> void:
	last_review_sync_fill_count = 0
	if review_sync_hole_fill_radius_chunks <= 0 or terrain == null or last_stream_report.is_empty():
		return
	var active_count: int = int(last_stream_report.get("active_count", 0))
	if active_count <= 0 or terrain.built_chunk_count() >= active_count:
		return
	if not terrain.has_method("build_missing_nearby_for_preview"):
		return
	last_review_sync_fill_count = int(terrain.call(
		"build_missing_nearby_for_preview",
		review_sync_hole_fill_radius_chunks,
		review_sync_hole_fill_max_chunks_per_frame
	))
	last_stream_report["review_sync_fill_count"] = last_review_sync_fill_count


func _far_clipmap_center_xz() -> Vector2:
	var viewer_chunk: Vector2i = TerrainStreamerScript.viewer_chunk(viewer_position_xz, chunk_size_m)
	var desired_center := Vector2(
		(float(viewer_chunk.x) + 0.5) * chunk_size_m,
		(float(viewer_chunk.y) + 0.5) * chunk_size_m
	)
	if not is_finite(_far_clipmap_anchor_xz.x) or not is_finite(_far_clipmap_anchor_xz.y):
		_far_clipmap_anchor_xz = desired_center
	var recenter_distance: float = max(chunk_size_m * 0.5, far_clipmap_recenter_distance_m)
	if viewer_position_xz.distance_to(_far_clipmap_anchor_xz) > recenter_distance:
		_far_clipmap_anchor_xz = desired_center
	return _far_clipmap_anchor_xz


func _far_clipmap_near_hole_extent_m() -> float:
	var spacing_margin: float = max(0.0, far_clipmap_base_spacing_m)
	var underlap_margin: float = max(spacing_margin, max(0.0, far_clipmap_handoff_overlap_m))
	var anchor_drift_margin: float = max(chunk_size_m * 0.5, far_clipmap_recenter_distance_m)
	return max(0.0, _near_chunk_window_half_extent_m() - underlap_margin - anchor_drift_margin)


func _near_chunk_window_half_extent_m() -> float:
	return float(visible_radius_chunks * 2 + 1) * chunk_size_m * 0.5


func _has_pending_visual_work() -> bool:
	if far_clipmap != null and far_clipmap.has_pending_rebuilds():
		return true
	if use_local_detail and local_detail == null and terrain != null:
		return true
	return local_detail != null and local_detail.has_pending_rebuilds()


func _update_camera() -> void:
	if camera == null or terrain == null or terrain.world == null:
		return
	var target_y: float = terrain.world.sample_height(viewer_position_xz.x, viewer_position_xz.y)
	var target := Vector3(viewer_position_xz.x, target_y, viewer_position_xz.y)
	var forward := Vector2(sin(camera_yaw_rad), cos(camera_yaw_rad))
	var camera_position := target + Vector3(-forward.x * camera_distance_m, camera_height_m, -forward.y * camera_distance_m)
	camera.look_at_from_position(camera_position, target, Vector3.UP)


func _zoom_camera(scale: float) -> void:
	camera_distance_m = clampf(camera_distance_m * scale, min_camera_distance_m, max_camera_distance_m)
	var wanted_height: float = camera_distance_m * camera_height_distance_ratio
	camera_height_m = clampf(wanted_height, min_camera_height_m, max_camera_height_m)
	_update_camera()


func _raise_camera(delta: float) -> void:
	camera_height_m = clampf(camera_height_m + max(200.0, camera_distance_m * 0.45) * delta, min_camera_height_m, max_camera_height_m)
	_update_camera()


func _lower_camera(delta: float) -> void:
	camera_height_m = clampf(camera_height_m - max(200.0, camera_distance_m * 0.45) * delta, min_camera_height_m, max_camera_height_m)
	_update_camera()


func _add_light() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "StreamingSun"
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(sun)


func _add_environment() -> void:
	environment = WorldEnvironment.new()
	environment.name = "StreamingEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.18, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.22, 0.22)
	env.ambient_light_energy = 0.35
	env.fog_enabled = use_distance_fog
	env.fog_density = distance_fog_density
	env.fog_light_color = distance_fog_color
	env.fog_light_energy = 0.85
	env.fog_sun_scatter = 0.0
	_set_environment_property_if_present(env, "fog_depth_enabled", use_distance_fog)
	_set_environment_property_if_present(env, "fog_depth_begin", max(0.0, distance_fog_depth_begin_m))
	_set_environment_property_if_present(env, "fog_depth_end", max(distance_fog_depth_begin_m + 1.0, distance_fog_depth_end_m))
	_set_environment_property_if_present(env, "fog_depth_curve", 1.0)
	environment.environment = env
	add_child(environment)


func _set_environment_property_if_present(env: Environment, property_name: String, value: Variant) -> void:
	for property in env.get_property_list():
		if String(property.get("name", "")) == property_name:
			env.set(property_name, value)
			return


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "StreamingCamera"
	camera.current = true
	camera.fov = 48.0
	camera.near = 1.0
	camera.far = camera_far_m
	add_child(camera)


func quality_profile_report() -> Dictionary:
	if quality_profile_id.is_empty():
		return {
			"profile_id": "",
			"status": "manual",
			"errors": [],
		}
	var profile_data: Dictionary = TerrainQualityProfileScript.profile(quality_profile_id)
	var profile_errors: Array[String] = TerrainQualityProfileScript.validation_errors(self, profile_data)
	return {
		"profile_id": quality_profile_id,
		"schema": str(profile_data.get("schema", "")),
		"status": "pass" if profile_errors.is_empty() else "fail",
		"errors": profile_errors,
		"visibility": TerrainQualityProfileScript.visibility_contract(profile_data),
	}


func _add_diagnostics_overlay() -> void:
	diagnostics_layer = CanvasLayer.new()
	diagnostics_layer.name = "StreamingDiagnostics"
	add_child(diagnostics_layer)
	var panel := PanelContainer.new()
	panel.name = "DiagnosticsPanel"
	panel.position = Vector2(12.0, 12.0)
	diagnostics_layer.add_child(panel)
	diagnostics_label = Label.new()
	diagnostics_label.name = "DiagnosticsLabel"
	diagnostics_label.add_theme_font_size_override("font_size", 18)
	diagnostics_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.90))
	diagnostics_label.text = ""
	panel.add_child(diagnostics_label)


func _update_diagnostics() -> void:
	if diagnostics_label == null:
		return
	diagnostics_label.text = diagnostics_text()


func _ensure_local_detail_node() -> bool:
	if local_detail != null:
		_configure_local_detail_node()
		return true
	if terrain == null or terrain.world == null:
		errors.append("local_detail_world_not_ready")
		return false
	local_detail = TerrainLocalDetailNodeScript.new()
	local_detail.name = "LocalDetailTerrain"
	add_child(local_detail)
	_configure_local_detail_node()
	if not local_detail.setup(terrain.world):
		errors.append("local_detail_setup_failed:%s" % str(local_detail.errors))
		return false
	return true


func _configure_far_clipmap_node() -> void:
	var config_key: String = _far_clipmap_config_key_for_current_settings()
	if config_key == _far_clipmap_config_key:
		return
	_far_clipmap_config_key = config_key
	if not far_clipmap.configure_geometry(
		far_clipmap_level_count,
		far_clipmap_base_spacing_m,
		far_clipmap_base_outer_extent_m
	):
		errors.append("far_clipmap_reconfigure_failed")
	far_clipmap.set_debug_level_colors(far_clipmap_debug_levels)
	far_clipmap.max_rebuild_levels_per_update = far_clipmap_rebuild_levels_per_update
	far_clipmap.transition_fade_seconds = far_clipmap_transition_fade_seconds
	far_clipmap.use_native_workers = use_far_clipmap_native_workers
	far_clipmap.use_persistent_page_mesh = use_persistent_page_clipmap
	far_clipmap.page_cache_max_pages = far_clipmap_page_cache_max_pages
	far_clipmap.gpu_page_residency_max_pages = far_clipmap_gpu_page_residency_max_pages
	far_clipmap.use_surface_texture_material = use_far_clipmap_surface_material
	far_clipmap.set_elevation_color_material(debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR)
	far_clipmap.surface_texture_normal_strength = far_clipmap_surface_normal_strength
	far_clipmap.visual_y_bias_per_level_m = far_clipmap_visual_y_bias_per_level_m
	far_clipmap.level0_full_underlay_enabled = far_clipmap_full_underlay_level0
	far_clipmap.apply_edge_fog(use_distance_fog, distance_fog_depth_begin_m, distance_fog_depth_end_m, distance_fog_color)


func _far_clipmap_config_key_for_current_settings() -> String:
	return "%d:%.6f:%.6f:%d:%d:%.6f:%d:%d:%d:%d:%d:%.6f:%.6f:%d:%d:%.6f:%.6f:%.6f:%.6f:%.6f:%d" % [
		far_clipmap_level_count,
		far_clipmap_base_spacing_m,
		far_clipmap_base_outer_extent_m,
		1 if far_clipmap_debug_levels else 0,
		far_clipmap_rebuild_levels_per_update,
		far_clipmap_transition_fade_seconds,
		1 if use_far_clipmap_native_workers else 0,
		1 if use_persistent_page_clipmap else 0,
		far_clipmap_page_cache_max_pages,
		far_clipmap_gpu_page_residency_max_pages,
		1 if use_far_clipmap_surface_material else 0,
		far_clipmap_surface_normal_strength,
		far_clipmap_visual_y_bias_per_level_m,
		1 if far_clipmap_full_underlay_level0 else 0,
		1 if use_distance_fog else 0,
		distance_fog_depth_begin_m,
		distance_fog_depth_end_m,
		distance_fog_color.r,
		distance_fog_color.g,
		distance_fog_color.b,
		1 if debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR else 0,
	]


func _configure_local_detail_node() -> void:
	local_detail.enabled = true
	local_detail.radius_patches = local_detail_radius_patches
	local_detail.max_active_patches = local_detail_max_active_patches
	local_detail.use_native_workers = use_local_detail_workers
	local_detail.use_surface_texture_material = use_local_detail_surface_material
	local_detail.surface_texture_normal_strength = local_detail_surface_normal_strength
	local_detail.use_visual_displacement = use_local_detail_visual_displacement
	local_detail.visual_displacement_strength = local_detail_visual_displacement_strength
	local_detail.visual_displacement_limit_m = local_detail_visual_displacement_limit_m
	local_detail.enable_collision_bodies = enable_local_collision_bodies


func _apply_debug_key_input() -> void:
	if Input.is_key_pressed(KEY_1):
		apply_debug_mode(TerrainWorldScript.DEBUG_GRAY)
	elif Input.is_key_pressed(KEY_2):
		apply_debug_mode(TerrainWorldScript.DEBUG_LOD_RING)
	elif Input.is_key_pressed(KEY_3):
		apply_debug_mode(TerrainWorldScript.DEBUG_HEIGHT_BANDS)
	elif Input.is_key_pressed(KEY_4):
		apply_debug_mode(TerrainWorldScript.DEBUG_SEAM)
	elif Input.is_key_pressed(KEY_5):
		apply_debug_mode(TerrainWorldScript.DEBUG_FAMILY_PALETTE)
	elif Input.is_key_pressed(KEY_6):
		apply_debug_mode(TerrainWorldScript.DEBUG_CHUNK_ID)
	elif Input.is_key_pressed(KEY_7):
		apply_debug_mode(TerrainWorldScript.DEBUG_HYDROLOGY)
	elif Input.is_key_pressed(KEY_8):
		apply_debug_mode(TerrainWorldScript.DEBUG_ELEVATION_COLOR)


func _apply_local_detail_review_key_input() -> void:
	var surface_down: bool = Input.is_key_pressed(KEY_T)
	if surface_down and not _surface_toggle_down:
		toggle_local_detail_surface_material()
	_surface_toggle_down = surface_down
	var displacement_down: bool = Input.is_key_pressed(KEY_Y)
	if displacement_down and not _displacement_toggle_down:
		toggle_local_detail_visual_displacement()
	_displacement_toggle_down = displacement_down
	var far_surface_down: bool = Input.is_key_pressed(KEY_U)
	if far_surface_down and not _far_surface_toggle_down:
		toggle_far_clipmap_surface_material()
	_far_surface_toggle_down = far_surface_down
	var far_geometry_down: bool = Input.is_key_pressed(KEY_H)
	if far_geometry_down and not _far_geometry_toggle_down:
		toggle_far_clipmap_wide_review()
	_far_geometry_toggle_down = far_geometry_down
	var far_camera_down: bool = Input.is_key_pressed(KEY_J)
	if far_camera_down and not _far_camera_toggle_down:
		frame_far_clipmap_overview()
	_far_camera_toggle_down = far_camera_down


func _warm_load_visible_region_kernels() -> void:
	if terrain == null or terrain.world == null or terrain.world.provider == null:
		return
	var provider: RefCounted = terrain.world.provider
	var region_size_m: float = terrain.world.region_size_m
	var chunk_size_m: float = terrain.world.chunk_size_m
	var seen: Dictionary = {}
	for cz in range(-visible_radius_chunks, visible_radius_chunks + 1):
		for cx in range(-visible_radius_chunks, visible_radius_chunks + 1):
			var origin_x: float = float(cx) * chunk_size_m
			var origin_z: float = float(cz) * chunk_size_m
			var rx: int = int(floor(origin_x / region_size_m))
			var rz: int = int(floor(origin_z / region_size_m))
			for dz in range(2):
				for dx in range(2):
					var crx: int = rx + dx
					var crz: int = rz + dz
					var key := "%d,%d" % [crx, crz]
					if seen.has(key):
						continue
					seen[key] = true
					var palette: Dictionary = provider.decisions.region_info(crx, crz, terrain.world.seed)
					var families: Array = palette["families"] as Array
					for family_value in families:
						var family: String = str(family_value)
						var kernel: Dictionary = provider.decisions.kernel_for_family(family, crx, crz, terrain.world.seed)
						if kernel.is_empty():
							continue
						terrain.world.runtime_pack.load_kernel_normalized_by_id(str(kernel.get("id", "")))
