extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const WALK_SCENE := "res://worldgen_terrain/scenes/terrain_walk_preview.tscn"
const REPORT_PATH := "factory/runtime/godot_gpu_page_profile/walk_backward_streaming_pressure_report.json"
const STEP_COUNT := 90


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var report: Dictionary = await _run_pressure_case(errors)
	_write_report(report, errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-backward-pressure] status=fail errors=%d report=%s" % [errors.size(), TerrainSettingsScript.workspace_path(REPORT_PATH)])
		quit(1)
		return
	print("[wg9-walk-backward-pressure] status=pass steps=%d max_missing=%d max_center_missing=%d max_retained=%d report=%s" % [
		STEP_COUNT,
		int(report.get("max_active_missing", 0)),
		int(report.get("max_center_missing", 0)),
		int(report.get("max_retained_inactive", 0)),
		TerrainSettingsScript.workspace_path(REPORT_PATH),
	])
	quit(0)


func _run_pressure_case(errors: Array[String]) -> Dictionary:
	var packed: PackedScene = load(WALK_SCENE) as PackedScene
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
	scene.set("viewer_position_xz", Vector2(28000.0, 0.0))
	get_root().add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
		scene.queue_free()
		await process_frame
		return {}
	await _drain(scene, errors, 160)
	var samples: Array[Dictionary] = []
	var max_active_missing := 0
	var max_center_missing := 0
	var max_retained_inactive := 0
	var max_step_ms := 0
	for step in range(STEP_COUNT):
		var started_ms: int = Time.get_ticks_msec()
		var move_report: Dictionary = scene.call("step_viewer", 2.0, Vector2(0.0, -1.0), 0.0, 0.0) as Dictionary
		max_step_ms = maxi(max_step_ms, Time.get_ticks_msec() - started_ms)
		if move_report.get("status", "fail") != "pass":
			errors.append("step_failed:%d:%s" % [step, str(move_report)])
			break
		await process_frame
		var stats: Dictionary = _terrain_stats(scene)
		var active_missing: int = int(stats.get("active_missing_chunk_count", 0))
		var center_missing: int = int((scene.get("terrain") as Node).call("active_missing_chunk_count", 1))
		var retained: int = int(stats.get("retained_inactive_chunk_count", 0))
		max_active_missing = maxi(max_active_missing, active_missing)
		max_center_missing = maxi(max_center_missing, center_missing)
		max_retained_inactive = maxi(max_retained_inactive, retained)
		if step % 5 == 0:
			samples.append({
				"step": step,
				"viewer_position_xz": _vec2_array(scene.get("viewer_position_xz")),
				"stream_report": move_report,
				"terrain_stats": stats,
				"diagnostics": str(scene.call("diagnostics_text")),
			})
		if center_missing > 0:
			errors.append("center_missing:%d step:%d diagnostics:%s" % [center_missing, step, str(scene.call("diagnostics_text"))])
			break
		if retained > 128:
			errors.append("retained_inactive_exceeded:%d step:%d" % [retained, step])
			break
	await _drain(scene, errors, 180)
	var final_stats: Dictionary = _terrain_stats(scene)
	var final_missing: int = int(final_stats.get("active_missing_chunk_count", 0))
	if final_missing > 0:
		errors.append("final_active_missing:%d" % final_missing)
	var result := {
		"schema": "worldgen9.walk_backward_streaming_pressure.v1",
		"steps": STEP_COUNT,
		"max_active_missing": max_active_missing,
		"max_center_missing": max_center_missing,
		"max_retained_inactive": max_retained_inactive,
		"max_step_ms": max_step_ms,
		"final_stats": final_stats,
		"samples": samples,
	}
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	await process_frame
	return result


func _drain(scene: Node3D, errors: Array[String], max_frames: int) -> void:
	for _index in range(max_frames):
		var stats: Dictionary = _terrain_stats(scene)
		if (
			int(stats.get("active_missing_chunk_count", 0)) == 0
			and int(stats.get("queued_native_worker_builds", 0)) == 0
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("active_gpu_provider_chunk_descriptor_workers", 0)) == 0
		):
			return
		var report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("drain_step_failed:%s" % str(report))
			return
		await process_frame
	errors.append("drain_timeout:%s" % str(scene.call("diagnostics_text")))


func _terrain_stats(scene: Node3D) -> Dictionary:
	var terrain: Node = scene.get("terrain") as Node
	if terrain == null or not terrain.has_method("build_stats"):
		return {}
	return terrain.call("build_stats") as Dictionary


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


func _vec2_array(value: Variant) -> Array[float]:
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]
	return [0.0, 0.0]
