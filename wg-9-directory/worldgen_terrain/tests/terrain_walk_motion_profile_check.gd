extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_walk_motion_profile"
const FRAME_COUNT := 72
const FRAME_DELTA_S := 1.0 / 30.0
const PROFILE_SPEED_MULTIPLIER := 60.0
const MAX_HARD_STEP_MS := 220
const WARN_NOT_FULL_FRAMES := 6
const WARN_QUEUE_BACKLOG := 90
const MAX_GPU_PAGE_UPLOAD_LEVEL_SETS := 6
const MAX_GPU_PAGE_EVICTIONS := 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.camera_yaw_deg = 0.0
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	_check_startup_defaults(scene, errors)
	_drain_initial_work(scene, errors)
	var report: Dictionary = _profile_forward_motion(scene, errors)
	_save_report(report, errors)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-motion-profile] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-motion-profile] status=pass report=%s" % JSON.stringify(_summary_for_stdout(report)))
	quit(0)


func _check_startup_defaults(scene: Node3D, errors: Array[String]) -> void:
	if not scene.use_persistent_page_clipmap:
		errors.append("page_clipmap_disabled")
	if not scene.use_far_clipmap_native_workers:
		errors.append("page_clipmap_workers_disabled")
	if scene.far_clipmap_rebuild_levels_per_update < scene.far_clipmap_level_count:
		errors.append("page_clipmap_rebuild_budget_too_low:%d" % scene.far_clipmap_rebuild_levels_per_update)
	if scene.built_chunk_count() < scene.expected_active_count():
		errors.append("startup_chunks_not_ready:%d/%d" % [scene.built_chunk_count(), scene.expected_active_count()])


func _profile_forward_motion(scene: Node3D, errors: Array[String]) -> Dictionary:
	scene.camera_yaw_rad = 0.0
	scene.look_pitch_rad = deg_to_rad(-8.0)
	scene._fast_modifier_active = false
	scene._update_camera()
	var previous_counts: Array = _far_counts(scene)
	var previous_anchor: Vector2 = scene._far_clipmap_center_xz()
	var step_ms_values: Array[int] = []
	var frame_reports: Array[Dictionary] = []
	var warnings: Array[String] = []
	var base_not_full_frames := 0
	var prefetch_not_full_frames := 0
	var recenter_frames := 0
	var chunk_churn_frames := 0
	var queue_backlog_frames := 0
	var max_queue := 0
	var max_native_workers := 0
	var max_far_pending := 0
	var max_page_blends := 0
	var max_gpu_pages := 0
	var max_gpu_page_mib := 0.0
	var max_gpu_uploads := 0
	var max_gpu_evictions := 0
	var page_material_reuse_frames := 0
	var page_descriptor_texture_hit_frames := 0
	var total_page_descriptor_texture_hits := 0
	var total_page_descriptor_image_builds := 0
	var max_step_ms := 0
	var total_chunk_created := 0
	var total_chunk_retired := 0
	var total_far_rebuild_delta := 0
	var final_far_stats: Dictionary = {}
	for frame_index in range(FRAME_COUNT):
		var start_ms: int = Time.get_ticks_msec()
		var stream_report: Dictionary = scene.step_viewer(FRAME_DELTA_S * PROFILE_SPEED_MULTIPLIER, Vector2(0.0, 1.0), 0.0)
		var step_ms: int = Time.get_ticks_msec() - start_ms
		step_ms_values.append(step_ms)
		max_step_ms = max(max_step_ms, step_ms)
		var terrain_stats: Dictionary = scene.terrain.build_stats()
		var far_stats: Dictionary = scene.far_clipmap.stats() if scene.far_clipmap != null else {}
		final_far_stats = far_stats
		var gpu_state: Dictionary = far_stats.get("gpu_page_residency", {}) as Dictionary
		var active_count: int = int(stream_report.get("active_count", 0))
		var base_active_count: int = int(stream_report.get("base_active_count", active_count))
		var built_count: int = scene.built_chunk_count()
		var queued: int = int(stream_report.get("queued_build_count", 0))
		var native_queued: int = int(terrain_stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(terrain_stats.get("active_native_workers", 0))
		var far_pending: int = int(far_stats.get("pending_rebuild_count", 0))
		var page_blends: int = int(far_stats.get("active_page_blend_count", 0))
		var far_counts: Array = _far_counts(scene)
		var far_delta: int = _count_delta(previous_counts, far_counts)
		var anchor: Vector2 = scene._far_clipmap_center_xz()
		var anchor_moved: bool = anchor.distance_to(previous_anchor) > 0.001
		var created: int = int(stream_report.get("created_count", 0))
		var retired: int = int(stream_report.get("retired_count", 0))
		total_chunk_created += created
		total_chunk_retired += retired
		total_far_rebuild_delta += far_delta
		if built_count < base_active_count:
			base_not_full_frames += 1
		elif built_count < active_count:
			prefetch_not_full_frames += 1
		if far_delta > 0 or anchor_moved:
			recenter_frames += 1
		if created > 0 or retired > 0:
			chunk_churn_frames += 1
		max_queue = max(max_queue, queued + native_queued)
		max_native_workers = max(max_native_workers, native_workers)
		max_far_pending = max(max_far_pending, far_pending)
		max_page_blends = max(max_page_blends, page_blends)
		max_gpu_pages = max(max_gpu_pages, int(gpu_state.get("count", 0)))
		max_gpu_page_mib = maxf(max_gpu_page_mib, float(gpu_state.get("total_mib", 0.0)))
		max_gpu_uploads = max(max_gpu_uploads, int(gpu_state.get("uploads", 0)))
		max_gpu_evictions = max(max_gpu_evictions, int(gpu_state.get("evictions", 0)))
		if bool(far_stats.get("last_page_material_reused", false)):
			page_material_reuse_frames += 1
		var descriptor_texture_hits: int = int(far_stats.get("last_page_descriptor_texture_hits", 0))
		var descriptor_image_builds: int = int(far_stats.get("last_page_descriptor_image_builds", 0))
		if descriptor_texture_hits > 0:
			page_descriptor_texture_hit_frames += 1
		total_page_descriptor_texture_hits += descriptor_texture_hits
		total_page_descriptor_image_builds += descriptor_image_builds
		if queued + native_queued > WARN_QUEUE_BACKLOG:
			queue_backlog_frames += 1
		frame_reports.append({
			"frame": frame_index,
			"step_ms": step_ms,
			"pos": [scene.viewer_position_xz.x, scene.viewer_position_xz.y],
			"built_chunks": built_count,
			"active_chunks": active_count,
			"base_active_chunks": base_active_count,
			"queued_chunks": queued,
			"native_queue": native_queued,
			"native_workers": native_workers,
			"created": created,
			"retired": retired,
			"far_pending": far_pending,
			"far_workers": int(far_stats.get("active_worker_count", 0)),
			"page_blends": page_blends,
			"gpu_pages": int(gpu_state.get("count", 0)),
			"gpu_page_uploads": int(gpu_state.get("uploads", 0)),
			"gpu_page_evictions": int(gpu_state.get("evictions", 0)),
			"page_material_reused": bool(far_stats.get("last_page_material_reused", false)),
			"page_descriptor_texture_hits": descriptor_texture_hits,
			"page_descriptor_image_builds": descriptor_image_builds,
			"far_rebuild_delta": far_delta,
			"anchor_moved": anchor_moved,
			"far_rebuilt_levels": (far_stats.get("last_rebuilt_levels", []) as Array).duplicate(),
		})
		previous_counts = far_counts
		previous_anchor = anchor
		OS.delay_msec(2)
	if max_step_ms > MAX_HARD_STEP_MS:
		errors.append("motion_step_ms:%d limit:%d" % [max_step_ms, MAX_HARD_STEP_MS])
	if queue_backlog_frames > 0:
		warnings.append("queue_backlog_frames:%d max_queue:%d" % [queue_backlog_frames, max_queue])
	if base_not_full_frames > WARN_NOT_FULL_FRAMES:
		warnings.append("base_not_full_frames:%d warning_limit:%d" % [base_not_full_frames, WARN_NOT_FULL_FRAMES])
	if prefetch_not_full_frames > WARN_NOT_FULL_FRAMES:
		warnings.append("prefetch_not_full_frames:%d warning_limit:%d" % [prefetch_not_full_frames, WARN_NOT_FULL_FRAMES])
	if recenter_frames <= 0:
		errors.append("no_recenter_frames_observed")
	if max_page_blends <= 0:
		errors.append("no_page_blend_activity_observed")
	var max_allowed_gpu_uploads: int = _max_allowed_gpu_page_uploads(scene)
	if max_gpu_uploads > max_allowed_gpu_uploads:
		errors.append("gpu_page_uploads:%d limit:%d" % [max_gpu_uploads, max_allowed_gpu_uploads])
	if max_gpu_evictions > MAX_GPU_PAGE_EVICTIONS:
		errors.append("gpu_page_evictions:%d limit:%d" % [max_gpu_evictions, MAX_GPU_PAGE_EVICTIONS])
	return {
		"schema": "worldgen9.walk_motion_profile.v1",
		"quality_profile": scene.quality_profile_report(),
		"profile": {
			"frame_count": FRAME_COUNT,
			"frame_delta_s": FRAME_DELTA_S,
			"speed_multiplier": PROFILE_SPEED_MULTIPLIER,
			"nominal_speed_mps": scene.move_speed_mps * PROFILE_SPEED_MULTIPLIER,
			"motion": "straight_forward",
		},
		"thresholds": {
			"max_hard_step_ms": MAX_HARD_STEP_MS,
			"warn_not_full_frames": WARN_NOT_FULL_FRAMES,
			"warn_queue_backlog": WARN_QUEUE_BACKLOG,
			"max_gpu_page_upload_level_sets": MAX_GPU_PAGE_UPLOAD_LEVEL_SETS,
			"max_gpu_page_uploads": max_allowed_gpu_uploads,
			"max_gpu_page_evictions": MAX_GPU_PAGE_EVICTIONS,
		},
		"warnings": warnings,
		"summary": {
			"step_ms": _timing_summary(step_ms_values),
			"render_budget": _render_budget_summary(scene),
			"base_not_full_frames": base_not_full_frames,
			"prefetch_not_full_frames": prefetch_not_full_frames,
			"recenter_frames": recenter_frames,
			"chunk_churn_frames": chunk_churn_frames,
			"max_queue": max_queue,
			"max_native_workers": max_native_workers,
			"max_far_pending": max_far_pending,
			"max_page_blends": max_page_blends,
			"max_gpu_pages": max_gpu_pages,
			"max_gpu_page_mib": max_gpu_page_mib,
			"max_gpu_uploads": max_gpu_uploads,
			"max_gpu_evictions": max_gpu_evictions,
			"page_material_reuse_frames": page_material_reuse_frames,
			"page_descriptor_texture_hit_frames": page_descriptor_texture_hit_frames,
			"total_page_descriptor_texture_hits": total_page_descriptor_texture_hits,
			"total_page_descriptor_image_builds": total_page_descriptor_image_builds,
			"total_chunk_created": total_chunk_created,
			"total_chunk_retired": total_chunk_retired,
			"total_far_rebuild_delta": total_far_rebuild_delta,
			"final_position": [scene.viewer_position_xz.x, scene.viewer_position_xz.y],
			"final_diagnostics": scene.diagnostics_text(),
			"final_gpu_page_residency": final_far_stats.get("gpu_page_residency", {}),
		},
		"frames": frame_reports,
	}


func _drain_initial_work(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(260):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		var far_pending: int = int(scene.far_clipmap.stats().get("pending_rebuild_count", 0)) if scene.far_clipmap != null else 0
		var far_workers: int = int(scene.far_clipmap.stats().get("active_worker_count", 0)) if scene.far_clipmap != null else 0
		if queued == 0 and native_queued == 0 and native_workers == 0 and far_pending == 0 and far_workers == 0 and scene.built_chunk_count() >= active:
			return
		OS.delay_msec(5)
	errors.append("initial_work_not_drained:%s" % scene.diagnostics_text())


func _max_allowed_gpu_page_uploads(scene: Node3D) -> int:
	var level_count: int = 1
	if scene.far_clipmap != null:
		level_count = max(1, int(scene.far_clipmap.level_count))
	return level_count * MAX_GPU_PAGE_UPLOAD_LEVEL_SETS


func _timing_summary(values: Array[int]) -> Dictionary:
	var sorted_values: Array[int] = values.duplicate()
	sorted_values.sort()
	var total := 0
	for value in sorted_values:
		total += int(value)
	return {
		"count": sorted_values.size(),
		"avg": float(total) / float(max(1, sorted_values.size())),
		"p50": _percentile(sorted_values, 0.50),
		"p95": _percentile(sorted_values, 0.95),
		"p99": _percentile(sorted_values, 0.99),
		"max": sorted_values[sorted_values.size() - 1] if not sorted_values.is_empty() else 0,
	}


func _percentile(sorted_values: Array[int], fraction: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index: int = clampi(int(ceil(float(sorted_values.size()) * fraction)) - 1, 0, sorted_values.size() - 1)
	return int(sorted_values[index])


func _far_counts(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	return (scene.far_clipmap.stats().get("build_counts", []) as Array).duplicate()


func _count_delta(before: Array, after: Array) -> int:
	var total := 0
	for index in range(min(before.size(), after.size())):
		total += int(after[index]) - int(before[index])
	return total


func _summary_for_stdout(report: Dictionary) -> Dictionary:
	return {
		"summary": report.get("summary", {}),
		"thresholds": report.get("thresholds", {}),
	}


func _render_budget_summary(scene: Node3D) -> Dictionary:
	var active_chunks: int = scene.expected_active_count()
	var near_vertices_per_chunk: int = scene.vertices_per_side * scene.vertices_per_side
	var near_triangles_per_chunk: int = (scene.vertices_per_side - 1) * (scene.vertices_per_side - 1) * 2
	var far_budget: Dictionary = scene.far_clipmap.budget_report() if scene.far_clipmap != null else {}
	var far_totals: Dictionary = far_budget.get("totals", {}) as Dictionary
	return {
		"near_active_chunks": active_chunks,
		"near_vertex_count": active_chunks * near_vertices_per_chunk,
		"near_triangle_count": active_chunks * near_triangles_per_chunk,
		"far_vertex_count": int(far_totals.get("vertex_count", 0)),
		"far_triangle_count": int(far_totals.get("triangle_count", 0)),
		"far_mesh_plus_height_mib": float(far_totals.get("mesh_plus_height_mib", 0.0)),
	}


func _save_report(report: Dictionary, errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join("walk_motion_profile_report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
