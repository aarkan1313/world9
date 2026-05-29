extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_profile.tscn"
const OUT_DIR := "factory/runtime/godot_gpu_page_profile"
const REPORT_NAME := "gpu_page_profile_reload_probe_report.json"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var report: Dictionary = await _run_probe(errors)
	var path: String = out_dir.path_join(REPORT_NAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-profile-reload-probe] status=fail errors=%d out=%s" % [errors.size(), path])
		quit(1)
		return
	print("[wg9-gpu-page-profile-reload-probe] status=pass out=%s summary=%s" % [path, JSON.stringify(report.get("summary", {}))])
	quit(0)


func _run_probe(errors: Array[String]) -> Dictionary:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		return {}
	var scene: Node3D = packed.instantiate() as Node3D
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	get_root().add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
		scene.queue_free()
		return {}
	var samples: Array[Dictionary] = []
	samples.append(_sample(scene, "after_setup", {}))
	var initial_drain: Dictionary = await _drain(scene, "initial_drain", 360)
	samples.append(initial_drain)
	var idle_report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
	samples.append(_sample(scene, "idle_after_drain", idle_report))
	var move_delta: float = 2048.0 / max(0.001, float(scene.get("move_speed_mps")))
	var move_report: Dictionary = scene.call("step_viewer", move_delta, Vector2(0.0, 1.0), 0.0, 0.0) as Dictionary
	samples.append(_sample(scene, "after_2km_move", move_report))
	var move_drain: Dictionary = await _drain(scene, "move_drain", 360)
	samples.append(move_drain)
	var summary := _summary(samples)
	if int(summary.get("idle_created", 0)) != 0 or int(summary.get("idle_retired", 0)) != 0:
		errors.append("idle_reloaded_after_drain:%s" % str(summary))
	if int(summary.get("move_created", 0)) > 60:
		errors.append("move_created_too_high:%s" % str(summary))
	if int(summary.get("move_base_missing", 0)) != 0:
		errors.append("move_base_missing:%s" % str(summary))
	if bool(summary.get("move_drain_pending", false)):
		errors.append("move_drain_pending:%s" % str(summary))
	scene.call("clear_preview")
	scene.queue_free()
	await process_frame
	return {
		"schema": "worldgen9.gpu_page_profile_reload_probe.v1",
		"summary": summary,
		"samples": samples,
	}


func _drain(scene: Node3D, label: String, max_frames: int) -> Dictionary:
	var frames := 0
	var last_report: Dictionary = scene.get("last_stream_report") as Dictionary
	while frames < max_frames and bool(scene.call("_has_pending_visual_work")):
		last_report = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		frames += 1
		await process_frame
	var sample: Dictionary = _sample(scene, label, last_report)
	sample["drain_frames"] = frames
	sample["pending_after_drain"] = bool(scene.call("_has_pending_visual_work"))
	return sample


func _sample(scene: Node3D, label: String, stream_report: Dictionary) -> Dictionary:
	var terrain_node: Node = scene.get("terrain") as Node
	var terrain_stats: Dictionary = terrain_node.call("build_stats") as Dictionary if terrain_node != null else {}
	var visible_radius: int = int(scene.get("visible_radius_chunks"))
	var base_missing: int = int(terrain_node.call("active_missing_chunk_count", visible_radius)) if terrain_node != null and terrain_node.has_method("active_missing_chunk_count") else 0
	var far_node: Node = scene.get("far_clipmap") as Node
	var far_stats: Dictionary = far_node.call("stats") as Dictionary if far_node != null and far_node.has_method("stats") else {}
	return {
		"label": label,
		"viewer": _vec2_array(scene.get("viewer_position_xz") as Vector2),
		"stream": {
			"active": int(stream_report.get("active_count", 0)),
			"created": int(stream_report.get("created_count", 0)),
			"retired": int(stream_report.get("retired_count", 0)),
			"lod_changed": int(stream_report.get("lod_changed_count", 0)),
			"queued": int(stream_report.get("queued_build_count", 0)),
			"build_now": int(stream_report.get("build_now_count", 0)),
			"viewer_chunk": stream_report.get("viewer_chunk", []),
			"prefetch_step": stream_report.get("prefetch_step", []),
		},
		"terrain": {
			"built": int(scene.call("built_chunk_count")),
			"visible": int(terrain_stats.get("visible_chunk_count", 0)),
			"standby": int(terrain_stats.get("standby_chunk_count", 0)),
			"active_missing": int(terrain_stats.get("active_missing_chunk_count", 0)),
			"base_missing": base_missing,
			"retained_inactive": int(terrain_stats.get("retained_inactive_chunk_count", 0)),
			"total_builds": int(terrain_stats.get("total_chunk_builds", 0)),
			"last_built": int(terrain_stats.get("last_gpu_page_chunks_built", 0)),
			"descriptor_workers": int(terrain_stats.get("active_gpu_provider_chunk_descriptor_workers", 0)),
			"descriptor_cache": int(terrain_stats.get("gpu_provider_chunk_descriptor_cache_count", 0)),
			"page_chunks": int(terrain_stats.get("gpu_page_chunk_count", 0)),
		},
		"far": {
			"pending": int(far_stats.get("pending_rebuild_count", 0)),
			"workers": int(far_stats.get("active_worker_count", 0)),
			"last_build_ms": int(far_stats.get("last_build_ms", 0)),
		},
	}


func _summary(samples: Array[Dictionary]) -> Dictionary:
	var by_label: Dictionary = {}
	for sample in samples:
		by_label[str(sample.get("label", ""))] = sample
	var setup_sample: Dictionary = by_label.get("after_setup", {}) as Dictionary
	var initial_drain: Dictionary = by_label.get("initial_drain", {}) as Dictionary
	var idle: Dictionary = by_label.get("idle_after_drain", {}) as Dictionary
	var move: Dictionary = by_label.get("after_2km_move", {}) as Dictionary
	var move_drain: Dictionary = by_label.get("move_drain", {}) as Dictionary
	return {
		"setup_pending_queue": int((setup_sample.get("stream", {}) as Dictionary).get("queued", 0)),
		"setup_built": int((setup_sample.get("terrain", {}) as Dictionary).get("built", 0)),
		"initial_drain_frames": int(initial_drain.get("drain_frames", 0)),
		"initial_drain_pending": bool(initial_drain.get("pending_after_drain", false)),
		"idle_created": int((idle.get("stream", {}) as Dictionary).get("created", 0)),
		"idle_retired": int((idle.get("stream", {}) as Dictionary).get("retired", 0)),
		"idle_queued": int((idle.get("stream", {}) as Dictionary).get("queued", 0)),
		"move_created": int((move.get("stream", {}) as Dictionary).get("created", 0)),
		"move_retired": int((move.get("stream", {}) as Dictionary).get("retired", 0)),
		"move_lod_changed": int((move.get("stream", {}) as Dictionary).get("lod_changed", 0)),
		"move_queued": int((move.get("stream", {}) as Dictionary).get("queued", 0)),
		"move_built": int((move.get("terrain", {}) as Dictionary).get("built", 0)),
		"move_missing": int((move.get("terrain", {}) as Dictionary).get("active_missing", 0)),
		"move_base_missing": int((move.get("terrain", {}) as Dictionary).get("base_missing", 0)),
		"move_drain_frames": int(move_drain.get("drain_frames", 0)),
		"move_drain_pending": bool(move_drain.get("pending_after_drain", false)),
		"move_drain_built": int((move_drain.get("terrain", {}) as Dictionary).get("built", 0)),
	}


func _vec2_array(value: Vector2) -> Array[float]:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001)]
