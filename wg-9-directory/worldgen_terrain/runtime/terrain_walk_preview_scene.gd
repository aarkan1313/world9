class_name TerrainWalkPreviewScene
extends TerrainStreamingPreviewScene

@export var eye_height_m: float = 2.0
@export var look_pitch_deg: float = -8.0
@export var mouse_sensitivity: float = 0.0024
@export var capture_mouse_on_ready: bool = true
@export var free_fly_enabled: bool = true
@export var fly_start_height_m: float = 48.0
@export var fly_min_ground_clearance_m: float = 4.0
@export var auto_select_diverse_review_sites: bool = true
@export_range(6, 18, 1) var review_site_target_count: int = 12
@export_range(2, 12, 1) var review_site_scan_radius_regions: int = 6

var review_regions: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(2, -1),
	Vector2i(-2, -1),
]
var review_site_index: int = 0
var look_pitch_rad: float = 0.0
var camera_world_y: float = 0.0
var _camera_height_initialized: bool = false


func _init() -> void:
	quality_profile_id = TerrainQualityProfileScript.WALK_REVIEW
	TerrainQualityProfileScript.apply_to_node(self, TerrainQualityProfileScript.profile(quality_profile_id))
	viewer_position_xz = Vector2(chunk_size_m * 0.5, chunk_size_m * 0.5)
	camera_yaw_deg = 42.0
	camera_height_m = eye_height_m
	camera_distance_m = 0.0
	build_when_idle = false
	distance_fog_color = Color(0.18, 0.18, 0.18)


func _ready() -> void:
	look_pitch_rad = deg_to_rad(look_pitch_deg)
	if capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	super._ready()


func setup() -> bool:
	_apply_walk_review_runtime_minimums()
	var ok: bool = super.setup()
	if ok and auto_select_diverse_review_sites:
		_select_diverse_review_sites()
	return ok


func _apply_walk_review_runtime_minimums() -> void:
	preload_active_chunk_limit = 0
	if vertices_per_side <= 129:
		build_budget_per_frame = max(build_budget_per_frame, 8)
		warmup_build_steps = max(warmup_build_steps, 4)
		preload_active_chunks_before_start = true
		max_native_chunk_workers = max(max_native_chunk_workers, 6)
		review_sync_hole_fill_radius_chunks = max(review_sync_hole_fill_radius_chunks, 1)
		review_sync_hole_fill_max_chunks_per_frame = max(review_sync_hole_fill_max_chunks_per_frame, 2)
	else:
		build_budget_per_frame = min(build_budget_per_frame, 2)
		warmup_build_steps = min(warmup_build_steps, 1)
		preload_active_chunks_before_start = false
		max_native_chunk_workers = max(max_native_chunk_workers, 4)
		review_sync_hole_fill_radius_chunks = max(review_sync_hole_fill_radius_chunks, 1)
		review_sync_hole_fill_max_chunks_per_frame = max(review_sync_hole_fill_max_chunks_per_frame, 1)


func _exit_tree() -> void:
	if capture_mouse_on_ready and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var movement := Vector2.ZERO
	var vertical_input := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y -= 1.0
	if free_fly_enabled:
		if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
			vertical_input += 1.0
		if Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_Q):
			vertical_input -= 1.0
	var speed_scale: float = _current_speed_scale()
	_apply_debug_key_input()
	_apply_local_detail_review_key_input()
	if movement.length_squared() > 0.000001 or absf(vertical_input) > 0.000001 or build_when_idle or _has_pending_visual_work():
		step_viewer(delta * speed_scale, movement, 0.0, vertical_input)
	else:
		_update_camera()
	_update_diagnostics()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			jump_review_site(1)
		elif event.keycode == KEY_B:
			jump_review_site(-1)
		elif event.keycode == KEY_G:
			toggle_free_fly_mode()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)


func apply_mouse_look(relative: Vector2) -> void:
	camera_yaw_rad -= relative.x * mouse_sensitivity
	look_pitch_rad = clampf(
		look_pitch_rad - relative.y * mouse_sensitivity,
		deg_to_rad(-70.0),
		deg_to_rad(40.0)
	)
	_update_camera()


func jump_review_site(direction: int) -> void:
	if terrain == null or terrain.world == null:
		return
	if review_regions.is_empty():
		_select_diverse_review_sites()
	if review_regions.is_empty():
		return
	review_site_index = posmod(review_site_index + direction, review_regions.size())
	var region: Vector2i = review_regions[review_site_index]
	var region_size: float = terrain.world.region_size_m
	var target_xz := Vector2(
		(float(region.x) + 0.5) * region_size,
		(float(region.y) + 0.5) * region_size
	)
	viewer_position_xz = _chunk_center_for_point(target_xz)
	_camera_height_initialized = false
	_update_streamer()
	_update_camera()
	_update_diagnostics()


func set_free_fly_enabled(enabled: bool) -> void:
	if free_fly_enabled == enabled:
		return
	free_fly_enabled = enabled
	if free_fly_enabled:
		var ground_y: float = terrain.world.sample_height(viewer_position_xz.x, viewer_position_xz.y) if terrain != null and terrain.world != null else 0.0
		var current_y: float = camera.global_position.y if camera != null else ground_y + fly_start_height_m
		camera_world_y = max(current_y, ground_y + fly_min_ground_clearance_m)
		_camera_height_initialized = true
	else:
		_camera_height_initialized = false
	_update_camera()
	_update_diagnostics()


func toggle_free_fly_mode() -> void:
	set_free_fly_enabled(not free_fly_enabled)


func step_viewer(delta: float, movement: Vector2, yaw_delta: float = 0.0, vertical_input: float = 0.0) -> Dictionary:
	if terrain == null:
		return {"status": "fail", "errors": ["terrain_not_setup"]}
	camera_yaw_rad += yaw_delta
	if free_fly_enabled:
		_ensure_camera_height_initialized()
		camera_world_y += vertical_input * move_speed_mps * delta
	if movement.length_squared() > 0.000001:
		var normalized := movement.normalized()
		var forward := _camera_forward_xz()
		var right := _camera_right_xz()
		var world_direction: Vector2 = (right * normalized.x + forward * normalized.y).normalized()
		_stream_priority_direction = world_direction
		viewer_position_xz += world_direction * move_speed_mps * delta
	var report := _update_streamer()
	_update_camera()
	return report


func diagnostics_text() -> String:
	var active_count: int = int(last_stream_report.get("active_count", 0))
	var queued_count: int = int(last_stream_report.get("queued_build_count", 0))
	var viewer_chunk: Array = last_stream_report.get("viewer_chunk", [0, 0]) as Array
	var fps: float = Engine.get_frames_per_second()
	var stats: Dictionary = terrain.build_stats() if terrain != null else {}
	var clipmap_stats: Dictionary = far_clipmap.stats() if far_clipmap != null else {}
	var detail_stats: Dictionary = local_detail.build_stats() if local_detail != null else {}
	var spacing_m: float = chunk_size_m / float(max(1, vertices_per_side - 1))
	var ground_y: float = terrain.world.sample_height(viewer_position_xz.x, viewer_position_xz.y) if terrain != null and terrain.world != null else 0.0
	var clearance_m: float = camera.global_position.y - ground_y if camera != null else 0.0
	var region_summary: Dictionary = _current_region_summary()
	return "fps %.0f | fly %s | speed %.0fm/s x%.1f | chunks %d/%d | queue %d+%d | workers %d | fill %d preload %d | build %.0fms avg %.0fms native %.0fms | far %dL %.0fms t%.0fms %s p%d w%d | detail %d b%.0f/a%.0f/t%.0fms mat %s disp %s %.2f/%.1fm | vtx %d step %.1fm | site %d/%d region %s %s kernels %s/%s | pos %.0f,%.0f | alt %.0fm | chunk %d,%d | mode %s" % [
		fps,
		"on" if free_fly_enabled else "ground",
		_effective_move_speed_mps(),
		_current_speed_scale(),
		built_chunk_count(),
		active_count,
		queued_count,
		int(stats.get("queued_native_worker_builds", 0)),
		int(stats.get("active_native_workers", 0)),
		last_review_sync_fill_count,
		last_preload_chunk_count,
		float(stats.get("last_chunk_build_ms", 0.0)),
		float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		float(stats.get("last_native_chunk_payload_ms", stats.get("last_native_mesh_payload_ms", 0.0))),
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
		vertices_per_side,
		spacing_m,
		review_site_index + 1,
		review_regions.size(),
		str(region_summary.get("region", "")),
		str(region_summary.get("palette", "")),
		str(region_summary.get("kernel_a", "")),
		str(region_summary.get("kernel_b", "")),
		viewer_position_xz.x,
		viewer_position_xz.y,
		clearance_m,
		int(viewer_chunk[0]),
		int(viewer_chunk[1]),
		debug_mode,
	]


func _update_camera() -> void:
	if camera == null or terrain == null or terrain.world == null:
		return
	var ground_y: float = terrain.world.sample_height(viewer_position_xz.x, viewer_position_xz.y)
	var camera_y: float = ground_y + eye_height_m
	if free_fly_enabled:
		_ensure_camera_height_initialized(ground_y)
		camera_world_y = max(camera_world_y, ground_y + fly_min_ground_clearance_m)
		camera_y = camera_world_y
	var forward := Vector3(
		sin(camera_yaw_rad) * cos(look_pitch_rad),
		sin(look_pitch_rad),
		cos(camera_yaw_rad) * cos(look_pitch_rad)
	).normalized()
	var position := Vector3(viewer_position_xz.x, camera_y, viewer_position_xz.y)
	camera.look_at_from_position(position, position + forward * 20.0, Vector3.UP)


func _current_region_summary() -> Dictionary:
	if terrain == null or terrain.world == null or terrain.world.provider == null:
		return {}
	var region_size: float = terrain.world.region_size_m
	var rx: int = int(floor(viewer_position_xz.x / region_size))
	var rz: int = int(floor(viewer_position_xz.y / region_size))
	var palette: Dictionary = terrain.world.provider.decisions.region_info(rx, rz, terrain.world.seed)
	var families: Array = palette.get("families", []) as Array
	var sample: Dictionary = terrain.world.sample(viewer_position_xz.x, viewer_position_xz.y)
	return {
		"region": "%d,%d" % [rx, rz],
		"palette": "%s:%s" % [str(palette.get("id", "")), "/".join(families)],
		"kernel_a": str(sample.get("kernel_a", "")),
		"kernel_b": str(sample.get("kernel_b", "")),
	}


func review_site_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if terrain == null or terrain.world == null or terrain.world.provider == null:
		return summaries
	var region_size: float = terrain.world.region_size_m
	for index in range(review_regions.size()):
		var region: Vector2i = review_regions[index]
		var center := Vector2((float(region.x) + 0.5) * region_size, (float(region.y) + 0.5) * region_size)
		var sample: Dictionary = terrain.world.sample(center.x, center.y)
		var palette: Dictionary = terrain.world.provider.decisions.region_info(region.x, region.y, terrain.world.seed)
		summaries.append({
			"index": index,
			"region": "%d,%d" % [region.x, region.y],
			"palette": str(palette.get("id", "")),
			"families": (palette.get("families", []) as Array).duplicate(),
			"primary_family": str(sample.get("primary_family", "unknown")),
			"secondary_family": str(sample.get("secondary_family", "unknown")),
			"kernel_a": str(sample.get("kernel_a", "")),
			"kernel_b": str(sample.get("kernel_b", "")),
		})
	return summaries


func _select_diverse_review_sites() -> void:
	if terrain == null or terrain.world == null or terrain.world.provider == null:
		return
	var decisions: RefCounted = terrain.world.provider.decisions
	var seed_value: int = terrain.world.seed
	var wanted_count: int = max(1, review_site_target_count)
	var scan_radius: int = max(1, review_site_scan_radius_regions)
	var candidates: Array[Dictionary] = []
	for rz in range(-scan_radius, scan_radius + 1):
		for rx in range(-scan_radius, scan_radius + 1):
			var palette: Dictionary = decisions.region_info(rx, rz, seed_value)
			if palette.is_empty():
				continue
			var families: Array = palette.get("families", []) as Array
			var primary_family: String = str(families[0]) if not families.is_empty() else "unknown"
			var kernel: Dictionary = decisions.kernel_for_family(primary_family, rx, rz, seed_value)
			var kernel_id: String = str(kernel.get("id", "")) if not kernel.is_empty() else ""
			candidates.append({
				"coord": Vector2i(rx, rz),
				"palette": str(palette.get("id", "")),
				"primary_family": primary_family,
				"kernel_id": kernel_id,
				"distance": abs(rx) + abs(rz),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		var ac: Vector2i = a["coord"] as Vector2i
		var bc: Vector2i = b["coord"] as Vector2i
		if ac.y != bc.y:
			return ac.y < bc.y
		return ac.x < bc.x
	)

	var selected: Array[Vector2i] = []
	var used_palettes: Dictionary = {}
	var used_families: Dictionary = {}
	var used_kernels: Dictionary = {}
	for candidate in candidates:
		if selected.size() >= wanted_count:
			break
		var palette_id: String = str(candidate["palette"])
		if used_palettes.has(palette_id):
			continue
		_add_review_candidate(candidate, selected, used_palettes, used_families, used_kernels)
	for candidate in candidates:
		if selected.size() >= wanted_count:
			break
		var family_id: String = str(candidate["primary_family"])
		if used_families.has(family_id):
			continue
		_add_review_candidate(candidate, selected, used_palettes, used_families, used_kernels)
	for candidate in candidates:
		if selected.size() >= wanted_count:
			break
		var kernel_id: String = str(candidate["kernel_id"])
		if kernel_id.is_empty() or used_kernels.has(kernel_id):
			continue
		_add_review_candidate(candidate, selected, used_palettes, used_families, used_kernels)
	if selected.size() >= 2:
		review_regions = selected
		review_site_index = min(review_site_index, review_regions.size() - 1)


func _add_review_candidate(
	candidate: Dictionary,
	selected: Array[Vector2i],
	used_palettes: Dictionary,
	used_families: Dictionary,
	used_kernels: Dictionary
) -> void:
	var coord: Vector2i = candidate["coord"] as Vector2i
	if selected.has(coord):
		return
	selected.append(coord)
	used_palettes[str(candidate["palette"])] = true
	used_families[str(candidate["primary_family"])] = true
	var kernel_id: String = str(candidate["kernel_id"])
	if not kernel_id.is_empty():
		used_kernels[kernel_id] = true


func _ensure_camera_height_initialized(ground_y: float = NAN) -> void:
	if _camera_height_initialized:
		return
	if is_nan(ground_y):
		ground_y = terrain.world.sample_height(viewer_position_xz.x, viewer_position_xz.y) if terrain != null and terrain.world != null else 0.0
	camera_world_y = ground_y + fly_start_height_m
	_camera_height_initialized = true


func _camera_forward_xz() -> Vector2:
	if camera != null:
		var camera_forward_3d: Vector3 = -camera.global_transform.basis.z
		var camera_forward := Vector2(camera_forward_3d.x, camera_forward_3d.z)
		if camera_forward.length_squared() > 0.000001:
			return camera_forward.normalized()
	var yaw_forward := Vector2(sin(camera_yaw_rad), cos(camera_yaw_rad))
	return yaw_forward.normalized()


func _camera_right_xz() -> Vector2:
	if camera != null:
		var camera_right_3d: Vector3 = camera.global_transform.basis.x
		var camera_right := Vector2(camera_right_3d.x, camera_right_3d.z)
		if camera_right.length_squared() > 0.000001:
			return camera_right.normalized()
	var forward := _camera_forward_xz()
	return Vector2(forward.y, -forward.x)


func _chunk_center_for_point(point: Vector2) -> Vector2:
	var chunk: Vector2i = TerrainStreamerScript.viewer_chunk(point, chunk_size_m)
	return Vector2(
		(float(chunk.x) + 0.5) * chunk_size_m,
		(float(chunk.y) + 0.5) * chunk_size_m
	)
