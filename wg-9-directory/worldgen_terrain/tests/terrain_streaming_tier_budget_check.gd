extends SceneTree

const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const TIERS: Array[Dictionary] = [
	{
		"label": "review_33_r1",
		"vertices_per_side": 33,
		"visible_radius_chunks": 1,
		"build_budget_per_frame": 1,
		"warmup_build_steps": 1,
		"max_elapsed_ms": 30000,
	},
	{
		"label": "review_65_r1",
		"vertices_per_side": 65,
		"visible_radius_chunks": 1,
		"build_budget_per_frame": 1,
		"warmup_build_steps": 1,
		"max_elapsed_ms": 90000,
	},
]


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var summaries: Array[String] = []
	for tier in TIERS:
		var result: Dictionary = _run_tier(tier)
		summaries.append("%s:%dms:%dchunks" % [
			str(tier["label"]),
			int(result.get("elapsed_ms", -1)),
			int(result.get("built_chunks", -1)),
		])
		for error in result.get("errors", []) as Array:
			errors.append("%s:%s" % [str(tier["label"]), str(error)])
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-streaming-tier-budget] status=fail errors=%d summary=%s" % [errors.size(), ", ".join(summaries)])
		return 1
	print("[wg9-terrain-streaming-tier-budget] status=pass tiers=%d summary=%s" % [TIERS.size(), ", ".join(summaries)])
	return 0


func _run_tier(tier: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var scene: Node = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = int(tier["vertices_per_side"])
	scene.visible_radius_chunks = int(tier["visible_radius_chunks"])
	scene.build_budget_per_frame = int(tier["build_budget_per_frame"])
	scene.warmup_build_steps = int(tier["warmup_build_steps"])
	get_root().add_child(scene)
	var start_ms: int = Time.get_ticks_msec()
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var initial_position: Vector2 = scene.viewer_position_xz
	var expected_active_count: int = scene.expected_active_count()
	var saw_stream_change := false
	for _index in range(10):
		var report: Dictionary = scene.step_viewer(0.25, Vector2(0.0, 1.0), 0.0)
		if int(report.get("created_count", 0)) > 0 or int(report.get("retired_count", 0)) > 0:
			saw_stream_change = true
	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	var final_report: Dictionary = scene.last_stream_report
	var moved_m: float = scene.viewer_position_xz.distance_to(initial_position)
	var built_chunks: int = scene.built_chunk_count()
	if elapsed_ms > int(tier["max_elapsed_ms"]):
		errors.append("elapsed_ms:%d limit:%d" % [elapsed_ms, int(tier["max_elapsed_ms"])])
	if moved_m < 2048.0:
		errors.append("viewer_did_not_cross_chunk:%.1f" % moved_m)
	if final_report.get("status", "fail") != "pass":
		errors.append("stream_report_not_pass")
	if int(final_report.get("active_count", -1)) != expected_active_count:
		errors.append("active_count:%d expected:%d" % [int(final_report.get("active_count", -1)), expected_active_count])
	if not saw_stream_change:
		errors.append("chunks_did_not_stream")
	if built_chunks <= 0:
		errors.append("no_built_chunks")
	if built_chunks > expected_active_count:
		errors.append("built_exceeds_active:%d:%d" % [built_chunks, expected_active_count])
	scene.queue_free()
	return {
		"errors": errors,
		"elapsed_ms": elapsed_ms,
		"built_chunks": built_chunks,
		"moved_m": moved_m,
	}
