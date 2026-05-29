extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn"
const REPORT_PATH := "factory/runtime/godot_gpu_page_profile/gpu_page_high_speed_fly_report.json"
const STEP_COUNT := 112
const REVIEW_SPEED_SCALE := 90.0
const TARGET_DELTA := 1.0 / 60.0
const MAX_FRAME_MS := 120
const MAX_P95_FRAME_MS := 70
const MAX_FINAL_BASE_MISSING := 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var report: Dictionary = await _run_case(errors)
	_write_report(report, errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-high-speed-fly] status=fail errors=%d report=%s" % [errors.size(), TerrainSettingsScript.workspace_path(REPORT_PATH)])
		quit(1)
		return
	print("[wg9-gpu-page-high-speed-fly] status=pass max_frame_ms=%d p95_frame_ms=%d max_base_missing=%d final_queue=%d report=%s" % [
		int((report.get("summary", {}) as Dictionary).get("max_frame_ms", 0)),
		int((report.get("summary", {}) as Dictionary).get("p95_frame_ms", 0)),
		int((report.get("summary", {}) as Dictionary).get("max_base_missing", 0)),
		int((report.get("summary", {}) as Dictionary).get("final_queue", 0)),
		TerrainSettingsScript.workspace_path(REPORT_PATH),
	])
	quit(0)


func _run_case(errors: Array[String]) -> Dictionary:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		return {}
	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		return {}
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	get_root().add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
		scene.queue_free()
		await process_frame
		return {}
	await _drain(scene, 180)
	var samples: Array[Dictionary] = []
	var frame_times: Array[int] = []
	var max_base_missing := 0
	var max_active_missing := 0
	var max_queue := 0
	var max_descriptor_workers := 0
	var start_position: Vector2 = scene.get("viewer_position_xz") as Vector2
	for step in range(STEP_COUNT):
		var frame_start: int = Time.get_ticks_msec()
		var report: Dictionary = scene.call("step_viewer", TARGET_DELTA * REVIEW_SPEED_SCALE, Vector2(0.0, 1.0), 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("step_failed:%d:%s" % [step, str(report)])
			break
		await process_frame
		var frame_ms: int = Time.get_ticks_msec() - frame_start
		frame_times.append(frame_ms)
		var terrain_stats: Dictionary = _terrain_stats(scene)
		var base_missing: int = int((scene.get("terrain") as Node).call("active_missing_chunk_count", int(scene.get("visible_radius_chunks"))))
		var active_missing: int = int(terrain_stats.get("active_missing_chunk_count", 0))
		var queue_count: int = int(report.get("queued_build_count", 0))
		var descriptor_workers: int = int(terrain_stats.get("active_gpu_provider_chunk_descriptor_workers", 0))
		max_base_missing = maxi(max_base_missing, base_missing)
		max_active_missing = maxi(max_active_missing, active_missing)
		max_queue = maxi(max_queue, queue_count)
		max_descriptor_workers = maxi(max_descriptor_workers, descriptor_workers)
		if step % 8 == 0 or frame_ms > MAX_P95_FRAME_MS:
			samples.append({
				"step": step,
				"frame_ms": frame_ms,
				"viewer_position_xz": _vec2_array(scene.get("viewer_position_xz")),
				"stream_report": _compact_stream_report(report),
				"terrain_stats": _compact_terrain_stats(terrain_stats),
				"diagnostics": str(scene.call("diagnostics_text")),
			})
	await _drain(scene, 240)
	var final_report: Dictionary = scene.get("last_stream_report") as Dictionary
	var final_stats: Dictionary = _terrain_stats(scene)
	var final_base_missing: int = int((scene.get("terrain") as Node).call("active_missing_chunk_count", int(scene.get("visible_radius_chunks"))))
	var summary := {
		"steps": frame_times.size(),
		"distance_m": ((scene.get("viewer_position_xz") as Vector2) - start_position).length(),
		"max_frame_ms": _max_int(frame_times),
		"p95_frame_ms": _percentile_int(frame_times, 0.95),
		"max_base_missing": max_base_missing,
		"max_active_missing": max_active_missing,
		"max_queue": max_queue,
		"max_descriptor_workers": max_descriptor_workers,
		"final_queue": int(final_report.get("queued_build_count", 0)),
		"final_base_missing": final_base_missing,
		"final_active_missing": int(final_stats.get("active_missing_chunk_count", 0)),
		"final_terrain_stats": _compact_terrain_stats(final_stats),
	}
	if int(summary["max_frame_ms"]) > MAX_FRAME_MS:
		errors.append("max_frame_ms:%d limit:%d" % [int(summary["max_frame_ms"]), MAX_FRAME_MS])
	if int(summary["p95_frame_ms"]) > MAX_P95_FRAME_MS:
		errors.append("p95_frame_ms:%d limit:%d" % [int(summary["p95_frame_ms"]), MAX_P95_FRAME_MS])
	if final_base_missing > MAX_FINAL_BASE_MISSING:
		errors.append("final_base_missing:%d" % final_base_missing)
	var result := {
		"schema": "worldgen9.gpu_page_high_speed_fly.v1",
		"scene": SCENE_PATH,
		"speed_scale": REVIEW_SPEED_SCALE,
		"target_delta": TARGET_DELTA,
		"summary": summary,
		"samples": samples,
	}
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	await process_frame
	return result


func _drain(scene: Node3D, max_frames: int) -> void:
	for _index in range(max_frames):
		if not bool(scene.call("_has_pending_visual_work")):
			return
		scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0)
		await process_frame


func _terrain_stats(scene: Node3D) -> Dictionary:
	var terrain: Node = scene.get("terrain") as Node
	if terrain == null or not terrain.has_method("build_stats"):
		return {}
	return terrain.call("build_stats") as Dictionary


func _compact_stream_report(report: Dictionary) -> Dictionary:
	return {
		"active_count": int(report.get("active_count", 0)),
		"queued_build_count": int(report.get("queued_build_count", 0)),
		"created_count": int(report.get("created_count", 0)),
		"retired_count": int(report.get("retired_count", 0)),
		"build_now_count": int(report.get("build_now_count", 0)),
		"viewer_chunk": report.get("viewer_chunk", []),
	}


func _compact_terrain_stats(stats: Dictionary) -> Dictionary:
	return {
		"active_chunks": int(stats.get("active_chunks", 0)),
		"visible_chunk_count": int(stats.get("visible_chunk_count", 0)),
		"active_missing_chunk_count": int(stats.get("active_missing_chunk_count", 0)),
		"queued_native_worker_builds": int(stats.get("queued_native_worker_builds", 0)),
		"active_native_workers": int(stats.get("active_native_workers", 0)),
		"active_gpu_provider_chunk_descriptor_workers": int(stats.get("active_gpu_provider_chunk_descriptor_workers", 0)),
		"gpu_provider_chunk_descriptor_cache_count": int(stats.get("gpu_provider_chunk_descriptor_cache_count", 0)),
		"gpu_page_chunk_count": int(stats.get("gpu_page_chunk_count", 0)),
		"last_gpu_page_chunk_ms": int(stats.get("last_gpu_page_chunk_ms", 0)),
		"gpu_page_chunk_ms_this_update": int(stats.get("gpu_page_chunk_ms_this_update", 0)),
		"last_gpu_provider_chunk_descriptor_stages": int(stats.get("last_gpu_provider_chunk_descriptor_stages", 0)),
		"last_gpu_provider_chunk_descriptor_worker_elapsed_ms": int(stats.get("last_gpu_provider_chunk_descriptor_worker_elapsed_ms", 0)),
		"last_gpu_provider_chunk_descriptor_error": str(stats.get("last_gpu_provider_chunk_descriptor_error", "")),
		"avg_recent_chunk_build_ms": float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		"max_recent_chunk_build_ms": int(stats.get("max_recent_chunk_build_ms", 0)),
	}


func _write_report(report: Dictionary, errors: Array[String]) -> void:
	var path: String = TerrainSettingsScript.workspace_path(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var payload: Dictionary = report.duplicate(true)
	payload["errors"] = errors.duplicate()
	payload["status"] = "pass" if errors.is_empty() else "fail"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%d" % int(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _max_int(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func _percentile_int(values: Array[int], percentile: float) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var index: int = clampi(int(ceil(percentile * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _vec2_array(value: Variant) -> Array[float]:
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]
	return [0.0, 0.0]
