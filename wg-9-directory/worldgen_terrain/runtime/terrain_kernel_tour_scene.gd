class_name TerrainKernelTourScene
extends TerrainWalkPreviewScene

@export var auto_tour_enabled: bool = true
@export_range(2.0, 30.0, 0.5) var seconds_per_site: float = 6.0
@export var restart_at_first_site_on_setup: bool = true
@export var stabilize_review_jumps: bool = true

var _tour_elapsed_s: float = 0.0


func _init() -> void:
	super._init()
	capture_mouse_on_ready = false
	free_fly_enabled = true
	fly_start_height_m = 820.0
	fly_min_ground_clearance_m = 80.0
	look_pitch_deg = -32.0
	camera_yaw_deg = 38.0
	review_site_target_count = 18
	review_site_scan_radius_regions = 18
	build_when_idle = true
	show_diagnostics_overlay = true


func setup() -> bool:
	var ok: bool = super.setup()
	if ok and restart_at_first_site_on_setup and not review_regions.is_empty():
		review_site_index = -1
		jump_review_site(1)
	return ok


func _process(delta: float) -> void:
	super._process(delta)
	if not auto_tour_enabled or review_regions.size() < 2:
		return
	if _has_pending_visual_work():
		return
	_tour_elapsed_s += delta
	if _tour_elapsed_s >= seconds_per_site:
		_tour_elapsed_s = 0.0
		jump_review_site(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			auto_tour_enabled = not auto_tour_enabled
			return
	_tour_elapsed_s = 0.0
	super._unhandled_input(event)


func jump_review_site(direction: int) -> void:
	super.jump_review_site(direction)
	_tour_elapsed_s = 0.0
	if stabilize_review_jumps:
		_stabilize_review_residency()


func _stabilize_review_residency() -> void:
	if terrain == null:
		return
	if terrain.has_method("clear_native_worker_backlog_for_preview"):
		terrain.call("clear_native_worker_backlog_for_preview")
	if last_stream_report.is_empty():
		last_stream_report = terrain.update_viewer(viewer_position_xz)
	if terrain.has_method("rebuild_all_active_for_preview"):
		last_preload_chunk_count = int(terrain.call("rebuild_all_active_for_preview", preload_active_chunk_limit))
	_preload_far_clipmap_before_start()
	_update_camera()
	_update_diagnostics()
