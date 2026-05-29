extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_profile.tscn"
const OUT_DIR := "factory/runtime/godot_gpu_page_profile"
const REPORT_NAME := "gpu_provider_chunk_staged_hitch_report.json"
const FRAME_COUNT := 54
const FRAME_DELTA_S := 1.0 / 30.0
const SPEED_MULTIPLIER := 60.0
const MAX_STEP_MS := 260
const MAX_P95_STEP_MS := 120
const NEAR_GPU_CACHE_PAGES := 192


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not _rendering_device_available():
		print("[wg9-gpu-provider-chunk-staged-hitch] status=unsupported rendering_device_unavailable out=%s" % out_dir)
		quit(0)
		return
	var scene: Node3D = _profile_scene(errors)
	var report: Dictionary = {}
	if scene != null:
		get_root().add_child(scene)
		if not bool(scene.call("setup")):
			errors.append("setup_failed:%s" % str(scene.get("errors")))
		else:
			await _drain_scene(scene, errors, 0, 220)
			report = await _profile_motion(scene, errors)
		await _cleanup_scene(scene)
	_write_report(out_dir, report, errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-provider-chunk-staged-hitch] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		quit(1)
		return
	var summary: Dictionary = report.get("summary", {}) as Dictionary
	print("[wg9-gpu-provider-chunk-staged-hitch] status=pass max_step_ms=%d p95_step_ms=%d stages=%d chunks=%d out=%s" % [
		int((summary.get("step_ms", {}) as Dictionary).get("max", 0)),
		int((summary.get("step_ms", {}) as Dictionary).get("p95", 0)),
		int(summary.get("total_descriptor_stages", 0)),
		int(summary.get("gpu_page_chunk_count", 0)),
		out_dir,
	])
	quit(0)


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _cleanup_scene(scene: Node3D) -> void:
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap != null and far_clipmap.has_method("clear_levels"):
		far_clipmap.call("clear_levels", true)
	var terrain_node: Node = scene.get("terrain") as Node
	if terrain_node != null and terrain_node.has_method("clear_chunks"):
		terrain_node.call("clear_chunks")
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	for _index in range(4):
		await process_frame


func _profile_scene(errors: Array[String]) -> Node3D:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		return null
	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		return null
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	scene.set("use_native_chunk_payloads", false)
	scene.set("use_native_chunk_workers", false)
	scene.set("use_gpu_page_chunks", true)
	scene.set("use_gpu_provider_page_chunk_textures", true)
	scene.set("use_gpu_provider_page_chunk_descriptor_staging", true)
	scene.set("use_gpu_rd_chunk_page_textures", true)
	scene.set("use_gpu_rd_chunk_compute_normals", false)
	scene.set("max_gpu_provider_chunk_descriptor_stages_per_update", 8)
	scene.set("max_gpu_provider_chunk_descriptor_workers", 8)
	scene.set("max_gpu_page_chunk_builds_per_update", 4)
	scene.set("max_gpu_page_chunk_build_ms_per_update", 150)
	scene.set("gpu_provider_chunk_descriptor_cache_max_entries", NEAR_GPU_CACHE_PAGES)
	scene.set("chunk_gpu_page_residency_max_pages", NEAR_GPU_CACHE_PAGES)
	scene.set("chunk_page_cache_max_pages", NEAR_GPU_CACHE_PAGES)
	scene.set("warmup_build_steps", 1)
	scene.set("preload_active_chunks_before_start", false)
	scene.set("review_sync_hole_fill_radius_chunks", 0)
	scene.set("review_sync_hole_fill_max_chunks_per_frame", 0)
	return scene


func _drain_scene(scene: Node3D, errors: Array[String], target_chunks: int, max_frames: int) -> void:
	for _index in range(max_frames):
		var stream_report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		var terrain_stats: Dictionary = _terrain_stats(scene)
		var active_count: int = int(stream_report.get("active_count", target_chunks))
		if target_chunks <= 0:
			target_chunks = active_count
		var queued: int = int(stream_report.get("queued_build_count", 0))
		if (
			int(scene.call("built_chunk_count")) >= min(target_chunks, active_count)
			and queued == 0
			and int(terrain_stats.get("queued_native_worker_builds", 0)) == 0
			and int(terrain_stats.get("active_native_workers", 0)) == 0
		):
			return
		await process_frame
	errors.append("initial_staged_provider_drain_failed:%s" % str(_terrain_stats(scene)))


func _profile_motion(scene: Node3D, errors: Array[String]) -> Dictionary:
	scene.set("camera_yaw_rad", 0.0)
	if scene.has_method("_update_camera"):
		scene.call("_update_camera")
	var step_values: Array[int] = []
	var frame_values: Array[int] = []
	var max_stage_count := 0
	var max_stage_ms := 0
	var max_page_chunks_built := 0
	var max_fallback_count := 0
	var max_page_chunk_ms := 0
	var max_page_texture_ms := 0
	var max_backend_create_texture_ms := 0
	var max_rd_upload_delta := 0
	var max_dispatch_delta := 0
	var frame_rows: Array[Dictionary] = []
	var final_stats: Dictionary = {}
	var previous_stats: Dictionary = _terrain_stats(scene)
	var previous_gpu_state: Dictionary = previous_stats.get("chunk_gpu_page_residency", {}) as Dictionary
	var previous_backend_state: Dictionary = previous_stats.get("chunk_gpu_provider_page_texture_backend", {}) as Dictionary
	for frame_index in range(FRAME_COUNT):
		var frame_start_us: int = Time.get_ticks_usec()
		var step_start_us: int = Time.get_ticks_usec()
		scene.call("step_viewer", FRAME_DELTA_S * SPEED_MULTIPLIER, _direction_for_frame(frame_index), 0.0, 0.0)
		var step_ms: int = int((Time.get_ticks_usec() - step_start_us + 500) / 1000)
		await process_frame
		var frame_ms: int = int((Time.get_ticks_usec() - frame_start_us + 500) / 1000)
		var terrain_stats: Dictionary = _terrain_stats(scene)
		step_values.append(step_ms)
		frame_values.append(frame_ms)
		max_stage_count = max(max_stage_count, int(terrain_stats.get("last_gpu_provider_chunk_descriptor_stages", 0)))
		max_stage_ms = max(max_stage_ms, int(terrain_stats.get("last_gpu_provider_chunk_descriptor_stage_ms", 0)))
		max_page_chunks_built = max(max_page_chunks_built, int(terrain_stats.get("last_gpu_page_chunks_built", 0)))
		max_fallback_count = max(max_fallback_count, int(terrain_stats.get("gpu_page_chunk_fallback_count", 0)))
		max_page_chunk_ms = max(max_page_chunk_ms, int(terrain_stats.get("last_gpu_page_chunk_ms", 0)))
		max_page_texture_ms = max(max_page_texture_ms, int(terrain_stats.get("last_gpu_page_chunk_texture_ms", 0)))
		var gpu_state: Dictionary = terrain_stats.get("chunk_gpu_page_residency", {}) as Dictionary
		var backend_state: Dictionary = terrain_stats.get("chunk_gpu_provider_page_texture_backend", {}) as Dictionary
		var rd_upload_delta: int = int(gpu_state.get("rd_uploads", 0)) - int(previous_gpu_state.get("rd_uploads", 0))
		var dispatch_delta: int = int(backend_state.get("dispatch_count", 0)) - int(previous_backend_state.get("dispatch_count", 0))
		max_rd_upload_delta = max(max_rd_upload_delta, rd_upload_delta)
		max_dispatch_delta = max(max_dispatch_delta, dispatch_delta)
		max_backend_create_texture_ms = max(max_backend_create_texture_ms, int(backend_state.get("last_create_texture_ms", 0)))
		frame_rows.append({
			"frame": frame_index,
			"step_ms": step_ms,
			"frame_ms": frame_ms,
			"page_chunk_ms": int(terrain_stats.get("last_gpu_page_chunk_ms", 0)),
			"page_chunk_ms_this_update": int(terrain_stats.get("gpu_page_chunk_ms_this_update", 0)),
			"page_texture_ms": int(terrain_stats.get("last_gpu_page_chunk_texture_ms", 0)),
			"page_chunks_built": int(terrain_stats.get("last_gpu_page_chunks_built", 0)),
			"descriptor_stages": int(terrain_stats.get("last_gpu_provider_chunk_descriptor_stages", 0)),
			"descriptor_stage_ms": int(terrain_stats.get("last_gpu_provider_chunk_descriptor_stage_ms", 0)),
			"rd_upload_delta": rd_upload_delta,
			"dispatch_delta": dispatch_delta,
			"backend_create_texture_ms": int(backend_state.get("last_create_texture_ms", 0)),
			"backend_dispatch_count": int(backend_state.get("dispatch_count", 0)),
			"residency_hits": int(gpu_state.get("hits", 0)),
			"residency_rd_uploads": int(gpu_state.get("rd_uploads", 0)),
			"residency_count": int(gpu_state.get("count", 0)),
			"queued_build_count": int(terrain_stats.get("queued_native_worker_builds", 0)),
		})
		previous_gpu_state = gpu_state
		previous_backend_state = backend_state
		final_stats = terrain_stats
	await _drain_scene(scene, errors, 0, 160)
	final_stats = _terrain_stats(scene)
	var gpu_state: Dictionary = final_stats.get("chunk_gpu_page_residency", {}) as Dictionary
	var summary := {
		"step_ms": _timing_summary(step_values),
		"frame_ms": _timing_summary(frame_values),
		"max_descriptor_stages_per_frame": max_stage_count,
		"max_descriptor_stage_ms": max_stage_ms,
		"max_page_chunks_built_per_frame": max_page_chunks_built,
		"max_page_chunk_ms": max_page_chunk_ms,
		"max_page_texture_ms": max_page_texture_ms,
		"max_backend_create_texture_ms": max_backend_create_texture_ms,
		"max_rd_upload_delta_per_frame": max_rd_upload_delta,
		"max_dispatch_delta_per_frame": max_dispatch_delta,
		"total_descriptor_stages": int(final_stats.get("total_gpu_provider_chunk_descriptor_stages", 0)),
		"gpu_page_chunk_count": int(final_stats.get("gpu_page_chunk_count", 0)),
		"gpu_page_chunk_fallback_count": int(final_stats.get("gpu_page_chunk_fallback_count", 0)),
		"final_gpu_state": gpu_state,
		"final_provider_texture_backend_state": final_stats.get("chunk_gpu_provider_page_texture_backend", {}) as Dictionary,
		"final_terrain_stats": final_stats,
	}
	_validate_summary(summary, errors)
	return {
		"schema": "worldgen9.gpu_provider_chunk_staged_hitch.v2",
		"scene": SCENE_PATH,
		"profile": {
			"frame_count": FRAME_COUNT,
			"frame_delta_s": FRAME_DELTA_S,
			"speed_multiplier": SPEED_MULTIPLIER,
		},
		"thresholds": {
			"max_step_ms": MAX_STEP_MS,
			"max_p95_step_ms": MAX_P95_STEP_MS,
		},
		"summary": summary,
		"frames": frame_rows,
	}


func _direction_for_frame(frame_index: int) -> Vector2:
	var segment: int = int(frame_index / 18)
	match segment % 3:
		0:
			return Vector2(0.0, 1.0)
		1:
			return Vector2(1.0, 0.0)
		_:
			return Vector2(0.0, -1.0)


func _validate_summary(summary: Dictionary, errors: Array[String]) -> void:
	var step_summary: Dictionary = summary.get("step_ms", {}) as Dictionary
	var final_stats: Dictionary = summary.get("final_terrain_stats", {}) as Dictionary
	var gpu_state: Dictionary = summary.get("final_gpu_state", {}) as Dictionary
	var expected_active: int = int(final_stats.get("active_chunks", 0))
	if int(step_summary.get("max", 0)) > MAX_STEP_MS:
		errors.append("staged_provider_step_ms:%d limit:%d" % [int(step_summary.get("max", 0)), MAX_STEP_MS])
	if int(step_summary.get("p95", 0)) > MAX_P95_STEP_MS:
		errors.append("staged_provider_p95_step_ms:%d limit:%d" % [int(step_summary.get("p95", 0)), MAX_P95_STEP_MS])
	if not bool(final_stats.get("use_gpu_provider_page_chunk_descriptor_staging", false)):
		errors.append("staged_provider_not_enabled:%s" % str(final_stats))
	if expected_active <= 0:
		errors.append("staged_provider_no_active_chunks:%s" % str(summary))
	if int(summary.get("total_descriptor_stages", 0)) < min(expected_active, 32):
		errors.append("staged_provider_stage_count:%s" % str(summary))
	if int(summary.get("gpu_page_chunk_count", 0)) < expected_active:
		errors.append("staged_provider_chunk_count:%s" % str(summary))
	if int(summary.get("gpu_page_chunk_fallback_count", 0)) != 0:
		errors.append("staged_provider_fallbacks:%s" % str(summary))
	if int(final_stats.get("cpu_chunk_payload_count", 0)) != 0:
		errors.append("staged_provider_cpu_payloads:%s" % str(final_stats))
	if not str(final_stats.get("last_gpu_page_chunk_error", "")).is_empty():
		errors.append("staged_provider_page_error:%s" % str(final_stats.get("last_gpu_page_chunk_error", "")))
	if not str(final_stats.get("last_gpu_provider_chunk_descriptor_error", "")).is_empty():
		errors.append("staged_provider_descriptor_error:%s" % str(final_stats.get("last_gpu_provider_chunk_descriptor_error", "")))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("staged_provider_image_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("evictions", 0)) != 0:
		errors.append("staged_provider_evictions:%s" % str(gpu_state))


func _terrain_stats(scene: Node3D) -> Dictionary:
	var terrain_node: Node = scene.get("terrain") as Node
	if terrain_node == null or not terrain_node.has_method("build_stats"):
		return {}
	return terrain_node.call("build_stats") as Dictionary


func _timing_summary(values: Array[int]) -> Dictionary:
	var sorted_values: Array[int] = values.duplicate()
	sorted_values.sort()
	var total := 0
	for value in sorted_values:
		total += value
	return {
		"count": sorted_values.size(),
		"avg": float(total) / float(max(1, sorted_values.size())),
		"p95": _percentile(sorted_values, 0.95),
		"max": sorted_values[sorted_values.size() - 1] if not sorted_values.is_empty() else 0,
	}


func _percentile(sorted_values: Array[int], fraction: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index: int = clampi(int(ceil(float(sorted_values.size()) * fraction)) - 1, 0, sorted_values.size() - 1)
	return int(sorted_values[index])


func _write_report(out_dir: String, profile_report: Dictionary, errors: Array[String]) -> void:
	var report: Dictionary = profile_report.duplicate(true)
	report["errors"] = errors.duplicate()
	var file := FileAccess.open(out_dir.path_join(REPORT_NAME), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
