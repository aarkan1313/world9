extends SceneTree

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_streaming_preview.tscn"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		errors.append("scene_load")
		_report(errors)
		return 1
	var scene: Node = packed.instantiate()
	if scene == null:
		errors.append("scene_instantiate")
		_report(errors)
		return 1
	get_root().add_child(scene)
	await process_frame
	await process_frame
	if scene.get("terrain") == null:
		errors.append("missing_terrain")
	if scene.get("camera") == null:
		errors.append("missing_camera")
	var diagnostics: Node = scene.get_node_or_null("StreamingDiagnostics/DiagnosticsPanel/DiagnosticsLabel")
	if diagnostics == null:
		errors.append("missing_diagnostics")
	var initial_position: Vector2 = scene.get("viewer_position_xz")
	var initial_chunk_count: int = int(scene.call("built_chunk_count"))
	var expected_active_count: int = int(scene.call("expected_active_count"))
	var saw_stream_change := false
	for _index in range(12):
		var step_report: Dictionary = scene.call("step_viewer", 0.25, Vector2(0.0, 1.0), 0.0) as Dictionary
		if int(step_report.get("created_count", 0)) > 0 or int(step_report.get("retired_count", 0)) > 0:
			saw_stream_change = true
	var moved_position: Vector2 = scene.get("viewer_position_xz")
	var report: Dictionary = scene.get("last_stream_report") as Dictionary
	var built_count: int = int(scene.call("built_chunk_count"))
	var diagnostics_text: String = str(scene.call("diagnostics_text"))
	if moved_position.distance_to(initial_position) < 2048.0:
		errors.append("viewer_did_not_cross_chunk")
	if report.get("status", "fail") != "pass":
		errors.append("stream_report_not_pass")
	if int(report.get("active_count", -1)) != expected_active_count:
		errors.append("active_count:%d expected:%d" % [int(report.get("active_count", -1)), expected_active_count])
	if not saw_stream_change:
		errors.append("chunks_did_not_stream")
	if built_count <= 0:
		errors.append("no_built_chunks")
	if built_count > expected_active_count:
		errors.append("built_exceeds_active:%d:%d" % [built_count, expected_active_count])
	if not diagnostics_text.contains("chunks") or not diagnostics_text.contains("queue"):
		errors.append("diagnostics_text:%s" % diagnostics_text)
	scene.queue_free()
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-terrain-streaming-preview] status=pass initial_chunks=%d built_chunks=%d active=%d moved_m=%.1f" % [
		initial_chunk_count,
		built_count,
		expected_active_count,
		moved_position.distance_to(initial_position),
	])
	return 0


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-streaming-preview] status=fail errors=%d" % errors.size())
