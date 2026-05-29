extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_profile.tscn"
const OUT_DIR := "factory/runtime/godot_gpu_page_profile"
const REPORT_NAME := "gpu_page_hitch_profile_report.json"
const FRAME_COUNT := 132
const FRAME_DELTA_S := 1.0 / 30.0
const SPEED_MULTIPLIER := 90.0
const MAX_HARD_STEP_MS := 220
const MAX_GPU_PROVIDER_PAGE_MS := 180
const MAX_GPU_TEXTURE_RESIDENCY_MS := 180
const MAX_METADATA_COMMITS_PER_FRAME := 1
const MAX_STAGED_PAYLOAD_COMMITS_PER_FRAME := 4
const MAX_STAGED_PAYLOAD_COMMIT_MS := 45
const MAX_TRANSIENT_MISSING_BASE_CHUNKS := 6


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not _rendering_device_available():
		print("[wg9-gpu-page-hitch-profile] status=unsupported rendering_device_unavailable out=%s" % out_dir)
		return 0

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		_write_report(out_dir, {}, errors)
		_report(errors, out_dir)
		return 1

	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		_write_report(out_dir, {}, errors)
		_report(errors, out_dir)
		return 1
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	get_root().add_child(scene)

	var profile_report: Dictionary = {}
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
	else:
		await _drain_initial_work(scene, errors)
		profile_report = await _profile_motion(scene, errors)
		_write_report(out_dir, profile_report, errors)

	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap != null and far_clipmap.has_method("clear_levels"):
		far_clipmap.call("clear_levels", true)
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	await process_frame

	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	var summary: Dictionary = profile_report.get("summary", {}) as Dictionary
	print("[wg9-gpu-page-hitch-profile] status=pass max_step_ms=%d p95_step_ms=%d max_provider_ms=%d max_residency_ms=%d out=%s" % [
		int((summary.get("step_ms", {}) as Dictionary).get("max", 0)),
		int((summary.get("step_ms", {}) as Dictionary).get("p95", 0)),
		int(summary.get("max_gpu_provider_page_ms", 0)),
		int(summary.get("max_gpu_texture_residency_ms", 0)),
		out_dir,
	])
	return 0


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _drain_initial_work(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(260):
		var report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		var terrain_node: Node = scene.get("terrain") as Node
		var terrain_stats: Dictionary = terrain_node.call("build_stats") as Dictionary if terrain_node != null else {}
		var far_stats: Dictionary = _far_stats(scene)
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(terrain_stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(terrain_stats.get("active_native_workers", 0))
		var descriptor_workers: int = int(terrain_stats.get("active_gpu_provider_chunk_descriptor_workers", 0))
		var missing_active: int = int(terrain_stats.get("active_missing_chunk_count", 0))
		var active: int = int(report.get("active_count", 0))
		if (
			active > 0
			and queued == 0
			and native_queued == 0
			and native_workers == 0
			and descriptor_workers == 0
			and missing_active == 0
			and int(far_stats.get("pending_rebuild_count", 0)) == 0
			and int(far_stats.get("active_worker_count", 0)) == 0
		):
			return
		await process_frame
	errors.append("initial_work_not_drained:%s" % str(scene.call("diagnostics_text")))


func _profile_motion(scene: Node3D, errors: Array[String]) -> Dictionary:
	scene.set("camera_yaw_rad", 0.0)
	scene.set("look_pitch_rad", deg_to_rad(-8.0))
	if scene.has_method("_update_camera"):
		scene.call("_update_camera")
	await _drain_initial_work(scene, errors)
	var frames: Array[Dictionary] = []
	var step_ms_values: Array[int] = []
	var frame_ms_values: Array[int] = []
	var max_provider_page_ms := 0
	var max_texture_residency_ms := 0
	var max_metadata_commits_per_frame := 0
	var max_staged_payload_commits_per_frame := 0
	var max_staged_payload_commit_ms := 0
	var total_staged_payload_commits := 0
	var max_terrain_last_chunk_build_ms := 0
	var max_terrain_native_worker_elapsed_ms := 0
	var max_terrain_active_native_workers := 0
	var max_terrain_queued_native_worker_builds := 0
	var max_terrain_build_delta := 0
	var max_terrain_native_worker_results_applied := 0
	var max_terrain_missing_active_chunks := 0
	var max_terrain_missing_base_chunks := 0
	var max_stream_queue := 0
	var total_metadata_commits := 0
	var total_provider_dispatches := 0
	var total_terrain_build_delta := 0
	var recenter_frames := 0
	var commit_frames := 0
	var previous_build_counts: Array = _far_build_counts(scene)
	var previous_anchor: Vector2 = _far_anchor(scene)
	var previous_terrain_builds: int = _terrain_total_builds(scene)
	for frame_index in range(FRAME_COUNT):
		var direction: Vector2 = _direction_for_frame(frame_index)
		var frame_start_us: int = Time.get_ticks_usec()
		var step_start_us: int = Time.get_ticks_usec()
		var stream_report: Dictionary = scene.call(
			"step_viewer",
			FRAME_DELTA_S * SPEED_MULTIPLIER,
			direction,
			0.0,
			0.0
		) as Dictionary
		var step_ms: int = int((Time.get_ticks_usec() - step_start_us + 500) / 1000)
		await process_frame
		var frame_ms: int = int((Time.get_ticks_usec() - frame_start_us + 500) / 1000)
		var far_stats: Dictionary = _far_stats(scene)
		var terrain_stats: Dictionary = _terrain_stats(scene)
		var gpu_state: Dictionary = far_stats.get("gpu_page_residency", {}) as Dictionary
		var build_counts: Array = _far_build_counts(scene)
		var build_delta: int = _count_delta(previous_build_counts, build_counts)
		var anchor: Vector2 = _far_anchor(scene)
		var anchor_moved: bool = anchor.distance_to(previous_anchor) > 0.001
		var terrain_total_builds: int = int(terrain_stats.get("total_chunk_builds", 0))
		var terrain_build_delta: int = max(0, terrain_total_builds - previous_terrain_builds)
		var metadata_commits: int = int(far_stats.get("last_gpu_provider_metadata_only_commits", 0))
		var staged_payload_commits: int = int(far_stats.get("last_staged_payload_commits", 0))
		var provider_ms: int = int(far_stats.get("last_gpu_provider_page_ms", 0))
		var residency_ms: int = int(far_stats.get("last_gpu_page_texture_residency_ms", 0))
		var staged_commit_ms: int = int(far_stats.get("last_staged_payload_commit_ms", 0))
		var terrain_last_chunk_build_ms: int = int(terrain_stats.get("last_chunk_build_ms", 0))
		var terrain_native_worker_elapsed_ms: int = int(terrain_stats.get("last_native_worker_elapsed_ms", 0))
		var terrain_active_native_workers: int = int(terrain_stats.get("active_native_workers", 0))
		var terrain_queued_native_worker_builds: int = int(terrain_stats.get("queued_native_worker_builds", 0))
		var terrain_native_worker_results_applied: int = int(terrain_stats.get("last_native_worker_results_applied", 0))
		var terrain_built_chunks: int = int(scene.call("built_chunk_count"))
		var stream_active_chunks: int = int(stream_report.get("active_count", 0))
		var stream_queued_chunks: int = int(stream_report.get("queued_build_count", 0))
		var terrain_missing_active_chunks: int = int(terrain_stats.get("active_missing_chunk_count", 0))
		var terrain_missing_base_chunks: int = _missing_base_chunk_count(scene, stream_report)
		step_ms_values.append(step_ms)
		frame_ms_values.append(frame_ms)
		max_provider_page_ms = max(max_provider_page_ms, provider_ms)
		max_texture_residency_ms = max(max_texture_residency_ms, residency_ms)
		max_metadata_commits_per_frame = max(max_metadata_commits_per_frame, metadata_commits)
		max_staged_payload_commits_per_frame = max(max_staged_payload_commits_per_frame, staged_payload_commits)
		max_staged_payload_commit_ms = max(max_staged_payload_commit_ms, staged_commit_ms)
		max_terrain_last_chunk_build_ms = max(max_terrain_last_chunk_build_ms, terrain_last_chunk_build_ms)
		max_terrain_native_worker_elapsed_ms = max(max_terrain_native_worker_elapsed_ms, terrain_native_worker_elapsed_ms)
		max_terrain_active_native_workers = max(max_terrain_active_native_workers, terrain_active_native_workers)
		max_terrain_queued_native_worker_builds = max(max_terrain_queued_native_worker_builds, terrain_queued_native_worker_builds)
		max_terrain_build_delta = max(max_terrain_build_delta, terrain_build_delta)
		max_terrain_native_worker_results_applied = max(max_terrain_native_worker_results_applied, terrain_native_worker_results_applied)
		max_terrain_missing_active_chunks = max(max_terrain_missing_active_chunks, terrain_missing_active_chunks)
		max_terrain_missing_base_chunks = max(max_terrain_missing_base_chunks, terrain_missing_base_chunks)
		max_stream_queue = max(max_stream_queue, stream_queued_chunks)
		total_metadata_commits += metadata_commits
		total_staged_payload_commits += staged_payload_commits
		total_provider_dispatches += int(far_stats.get("last_gpu_provider_page_dispatches", 0))
		total_terrain_build_delta += terrain_build_delta
		if anchor_moved or build_delta > 0:
			recenter_frames += 1
		if metadata_commits > 0:
			commit_frames += 1
		frames.append({
			"frame": frame_index,
			"step_ms": step_ms,
			"frame_ms": frame_ms,
			"stream_created": int(stream_report.get("created_count", 0)),
			"stream_retired": int(stream_report.get("retired_count", 0)),
			"stream_active_chunks": stream_active_chunks,
			"stream_expected_active_chunks": int(stream_report.get("expected_active_count", stream_active_chunks)),
			"stream_queued_chunks": stream_queued_chunks,
			"prefetch_forward_chunks": int(stream_report.get("prefetch_forward_chunks", 0)),
			"far_pending": int(far_stats.get("pending_rebuild_count", 0)),
			"far_rebuild_delta": build_delta,
			"anchor_moved": anchor_moved,
			"metadata_only_commits": metadata_commits,
			"staged_payload_commits": staged_payload_commits,
			"staged_payload_commit_ms": staged_commit_ms,
			"staged_payload_commit_ready": bool(far_stats.get("staged_native_commit_ready", false)),
			"provider_dispatches": int(far_stats.get("last_gpu_provider_page_dispatches", 0)),
			"gpu_provider_page_ms": provider_ms,
			"gpu_provider_texture_ms": int(far_stats.get("last_gpu_provider_texture_ms", 0)),
			"gpu_texture_residency_ms": residency_ms,
			"gpu_provider_material_ms": int(far_stats.get("last_gpu_provider_material_ms", 0)),
			"gpu_provider_mesh_ms": int(far_stats.get("last_gpu_provider_mesh_ms", 0)),
			"rd_uploads": int(gpu_state.get("rd_uploads", 0)),
			"image_uploads": int(gpu_state.get("image_uploads", 0)),
			"rd_normal_uploads": int(gpu_state.get("rd_compute_normal_uploads", 0)),
			"page_count": int(gpu_state.get("count", 0)),
			"terrain_build_delta": terrain_build_delta,
			"terrain_built_chunks": terrain_built_chunks,
			"terrain_missing_active_chunks": terrain_missing_active_chunks,
			"terrain_missing_base_chunks": terrain_missing_base_chunks,
			"terrain_last_chunk_build_ms": terrain_last_chunk_build_ms,
			"terrain_last_native_worker_elapsed_ms": terrain_native_worker_elapsed_ms,
			"terrain_active_native_workers": terrain_active_native_workers,
			"terrain_queued_native_worker_builds": terrain_queued_native_worker_builds,
			"terrain_native_worker_results_applied": terrain_native_worker_results_applied,
			"terrain_native_worker_result_budget": int(terrain_stats.get("max_native_chunk_worker_results_per_update", 0)),
			"terrain_active_gpu_provider_chunk_descriptor_workers": int(terrain_stats.get("active_gpu_provider_chunk_descriptor_workers", 0)),
			"terrain_gpu_provider_chunk_descriptor_cache_count": int(terrain_stats.get("gpu_provider_chunk_descriptor_cache_count", 0)),
			"terrain_recent_build_count": int(terrain_stats.get("recent_build_count", 0)),
			"terrain_max_recent_chunk_build_ms": int(terrain_stats.get("max_recent_chunk_build_ms", 0)),
		})
		previous_build_counts = build_counts
		previous_anchor = anchor
		previous_terrain_builds = terrain_total_builds

	var idle_drain_report: Dictionary = await _drain_idle_pending_visual_work(scene, 90)
	var final_far_stats: Dictionary = _far_stats(scene)
	var final_terrain_stats: Dictionary = _terrain_stats(scene)
	var final_gpu_state: Dictionary = final_far_stats.get("gpu_page_residency", {}) as Dictionary
	var summary := {
		"step_ms": _timing_summary(step_ms_values),
		"frame_ms": _timing_summary(frame_ms_values),
		"recenter_frames": recenter_frames,
		"commit_frames": commit_frames,
		"total_metadata_only_commits": total_metadata_commits,
		"total_staged_payload_commits": total_staged_payload_commits,
		"total_provider_dispatches": total_provider_dispatches,
		"max_metadata_commits_per_frame": max_metadata_commits_per_frame,
		"max_staged_payload_commits_per_frame": max_staged_payload_commits_per_frame,
		"max_staged_payload_commit_ms": max_staged_payload_commit_ms,
		"total_terrain_build_delta": total_terrain_build_delta,
		"max_terrain_build_delta": max_terrain_build_delta,
		"max_terrain_missing_active_chunks": max_terrain_missing_active_chunks,
		"max_terrain_missing_base_chunks": max_terrain_missing_base_chunks,
		"max_stream_queue": max_stream_queue,
		"max_terrain_last_chunk_build_ms": max_terrain_last_chunk_build_ms,
		"max_terrain_native_worker_elapsed_ms": max_terrain_native_worker_elapsed_ms,
		"max_terrain_active_native_workers": max_terrain_active_native_workers,
		"max_terrain_queued_native_worker_builds": max_terrain_queued_native_worker_builds,
		"max_terrain_native_worker_results_applied": max_terrain_native_worker_results_applied,
		"max_gpu_provider_page_ms": max_provider_page_ms,
		"max_gpu_texture_residency_ms": max_texture_residency_ms,
		"idle_drain": idle_drain_report,
		"final_gpu_page_residency": final_gpu_state,
		"final_far_stats": final_far_stats,
		"final_terrain_stats": final_terrain_stats,
	}
	_validate_profile(summary, errors)
	return {
		"schema": "worldgen9.gpu_page_hitch_profile.v2",
		"scene": SCENE_PATH,
		"profile": {
			"frame_count": FRAME_COUNT,
			"frame_delta_s": FRAME_DELTA_S,
			"speed_multiplier": SPEED_MULTIPLIER,
			"nominal_speed_mps": float(scene.get("move_speed_mps")) * SPEED_MULTIPLIER,
		},
		"thresholds": {
			"max_hard_step_ms": MAX_HARD_STEP_MS,
			"max_gpu_provider_page_ms": MAX_GPU_PROVIDER_PAGE_MS,
			"max_gpu_texture_residency_ms": MAX_GPU_TEXTURE_RESIDENCY_MS,
			"max_metadata_commits_per_frame": MAX_METADATA_COMMITS_PER_FRAME,
			"max_staged_payload_commits_per_frame": MAX_STAGED_PAYLOAD_COMMITS_PER_FRAME,
			"max_staged_payload_commit_ms": MAX_STAGED_PAYLOAD_COMMIT_MS,
			"max_transient_missing_base_chunks": MAX_TRANSIENT_MISSING_BASE_CHUNKS,
		},
		"summary": summary,
		"frames": frames,
	}


func _direction_for_frame(frame_index: int) -> Vector2:
	var segment: int = int(frame_index / 36)
	match segment % 4:
		0:
			return Vector2(0.0, 1.0)
		1:
			return Vector2(1.0, 0.0)
		2:
			return Vector2(0.0, -1.0)
		_:
			return Vector2(-1.0, 0.0)


func _validate_profile(summary: Dictionary, errors: Array[String]) -> void:
	var step_summary: Dictionary = summary.get("step_ms", {}) as Dictionary
	var final_gpu_state: Dictionary = summary.get("final_gpu_page_residency", {}) as Dictionary
	var final_terrain_stats: Dictionary = summary.get("final_terrain_stats", {}) as Dictionary
	var idle_drain: Dictionary = summary.get("idle_drain", {}) as Dictionary
	if int(step_summary.get("max", 0)) > MAX_HARD_STEP_MS:
		errors.append("gpu_page_step_ms:%d limit:%d" % [int(step_summary.get("max", 0)), MAX_HARD_STEP_MS])
	if int(summary.get("max_gpu_provider_page_ms", 0)) > MAX_GPU_PROVIDER_PAGE_MS:
		errors.append("gpu_provider_page_ms:%d limit:%d" % [int(summary.get("max_gpu_provider_page_ms", 0)), MAX_GPU_PROVIDER_PAGE_MS])
	if int(summary.get("max_gpu_texture_residency_ms", 0)) > MAX_GPU_TEXTURE_RESIDENCY_MS:
		errors.append("gpu_texture_residency_ms:%d limit:%d" % [int(summary.get("max_gpu_texture_residency_ms", 0)), MAX_GPU_TEXTURE_RESIDENCY_MS])
	if int(summary.get("max_metadata_commits_per_frame", 0)) > MAX_METADATA_COMMITS_PER_FRAME:
		errors.append("metadata_commits_per_frame:%d limit:%d" % [int(summary.get("max_metadata_commits_per_frame", 0)), MAX_METADATA_COMMITS_PER_FRAME])
	if int(summary.get("max_staged_payload_commits_per_frame", 0)) > MAX_STAGED_PAYLOAD_COMMITS_PER_FRAME:
		errors.append("staged_payload_commits_per_frame:%d limit:%d" % [int(summary.get("max_staged_payload_commits_per_frame", 0)), MAX_STAGED_PAYLOAD_COMMITS_PER_FRAME])
	if int(summary.get("max_staged_payload_commit_ms", 0)) > MAX_STAGED_PAYLOAD_COMMIT_MS:
		errors.append("staged_payload_commit_ms:%d limit:%d" % [int(summary.get("max_staged_payload_commit_ms", 0)), MAX_STAGED_PAYLOAD_COMMIT_MS])
	if int(summary.get("max_terrain_missing_base_chunks", 0)) > MAX_TRANSIENT_MISSING_BASE_CHUNKS:
		errors.append(
			"missing_base_chunks:%d limit:%d"
			% [int(summary.get("max_terrain_missing_base_chunks", 0)), MAX_TRANSIENT_MISSING_BASE_CHUNKS]
		)
	if int(summary.get("recenter_frames", 0)) <= 0:
		errors.append("no_recenter_frames")
	if bool(idle_drain.get("pending_after_drain", false)):
		errors.append("idle_pending_not_drained:%s" % str(idle_drain))
	if int(final_gpu_state.get("image_uploads", 0)) != 0:
		errors.append("unexpected_image_uploads:%s" % str(final_gpu_state))
	if int(final_gpu_state.get("evictions", 0)) != 0:
		errors.append("unexpected_gpu_page_evictions:%s" % str(final_gpu_state))
	if not bool(final_terrain_stats.get("use_gpu_page_chunks", false)):
		errors.append("near_gpu_page_chunks_disabled:%s" % str(final_terrain_stats))
	if int(final_terrain_stats.get("gpu_page_chunk_count", 0)) <= 0:
		errors.append("near_gpu_page_chunks_not_committed:%s" % str(final_terrain_stats))
	if int(final_terrain_stats.get("cpu_chunk_payload_count", 0)) != 0:
		errors.append("near_sync_cpu_chunks_committed:%s" % str(final_terrain_stats))
	if int(final_terrain_stats.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("near_gpu_page_chunk_fallbacks:%s" % str(final_terrain_stats))
	if not str(final_terrain_stats.get("last_gpu_page_chunk_error", "")).is_empty():
		errors.append("near_gpu_page_chunk_error:%s" % str(final_terrain_stats.get("last_gpu_page_chunk_error", "")))


func _far_stats(scene: Node3D) -> Dictionary:
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null or not far_clipmap.has_method("stats"):
		return {}
	return far_clipmap.call("stats") as Dictionary


func _terrain_stats(scene: Node3D) -> Dictionary:
	var terrain_node: Node = scene.get("terrain") as Node
	if terrain_node == null or not terrain_node.has_method("build_stats"):
		return {}
	return terrain_node.call("build_stats") as Dictionary


func _terrain_total_builds(scene: Node3D) -> int:
	return int(_terrain_stats(scene).get("total_chunk_builds", 0))


func _missing_base_chunk_count(scene: Node3D, stream_report: Dictionary) -> int:
	var terrain_node: Node = scene.get("terrain") as Node
	if terrain_node == null:
		return 0
	var chunk_nodes: Dictionary = terrain_node.get("chunk_nodes") as Dictionary
	var center: Array = stream_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var visible_radius: int = int(scene.get("visible_radius_chunks"))
	var missing := 0
	for item_value in stream_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item.get("chunk_x", 0))
		var chunk_z: int = int(item.get("chunk_z", 0))
		if max(abs(chunk_x - center_x), abs(chunk_z - center_z)) > visible_radius:
			continue
		var key := "%d,%d" % [chunk_x, chunk_z]
		if not chunk_nodes.has(key):
			missing += 1
	return missing


func _drain_idle_pending_visual_work(scene: Node3D, max_frames: int) -> Dictionary:
	var frames := 0
	var last_report: Dictionary = scene.get("last_stream_report") as Dictionary
	while frames < max_frames:
		if not bool(scene.call("_has_pending_visual_work")):
			break
		last_report = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		frames += 1
		await process_frame
	var active_count: int = int(last_report.get("active_count", 0))
	var built_count: int = int(scene.call("built_chunk_count"))
	var terrain_stats: Dictionary = _terrain_stats(scene)
	var far_stats: Dictionary = _far_stats(scene)
	return {
		"frames": frames,
		"pending_after_drain": bool(scene.call("_has_pending_visual_work")),
		"active_chunks": active_count,
		"built_chunks": built_count,
		"missing_active_chunks": max(0, active_count - built_count),
		"queued_chunks": int(last_report.get("queued_build_count", 0)),
		"queued_native_worker_builds": int(terrain_stats.get("queued_native_worker_builds", 0)),
		"active_native_workers": int(terrain_stats.get("active_native_workers", 0)),
		"far_pending": int(far_stats.get("pending_rebuild_count", 0)),
		"far_workers": int(far_stats.get("active_worker_count", 0)),
	}


func _far_build_counts(scene: Node3D) -> Array:
	return (_far_stats(scene).get("build_counts", []) as Array).duplicate()


func _far_anchor(scene: Node3D) -> Vector2:
	var value: Variant = scene.call("_far_clipmap_center_xz")
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO


func _count_delta(before: Array, after: Array) -> int:
	var total := 0
	for index in range(min(before.size(), after.size())):
		total += int(after[index]) - int(before[index])
	return total


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


func _write_report(out_dir: String, profile_report: Dictionary, errors: Array[String]) -> void:
	var report: Dictionary = profile_report.duplicate(true)
	report["status"] = "pass" if errors.is_empty() else "fail"
	report["errors"] = errors.duplicate()
	var file := FileAccess.open(out_dir.path_join(REPORT_NAME), FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%d" % int(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-gpu-page-hitch-profile] status=fail errors=%d out=%s" % [errors.size(), out_dir])
