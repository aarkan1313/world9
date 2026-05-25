extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")

const MAX_DRAIN_STEPS := 260
const MAX_SETUP_MS := 800
const MAX_AVG_BUILD_MS := 90.0
const MAX_NATIVE_PAYLOAD_MS := 140.0
const MAX_MOVE_STEP_MS := 20


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.vertices_per_side = 257
	scene.visible_radius_chunks = 3
	scene.build_budget_per_frame = 2
	scene.max_native_chunk_workers = 2
	get_root().add_child(scene)

	var start_ms: int = Time.get_ticks_msec()
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var setup_ms: int = Time.get_ticks_msec() - start_ms
	var warmup_steps: int = _drain_queue(scene, errors)
	var clipmap_counts_before: Array = _far_clipmap_build_counts(scene)
	var move_ms: Array[int] = []
	for _step in range(4):
		start_ms = Time.get_ticks_msec()
		scene.step_viewer(0.16, Vector2(1.0, 0.5).normalized(), 0.0)
		move_ms.append(Time.get_ticks_msec() - start_ms)
		_drain_queue(scene, errors)
	var clipmap_counts_after: Array = _far_clipmap_build_counts(scene)
	if clipmap_counts_after != clipmap_counts_before:
		errors.append("far_clipmap_rebuilt_on_small_move:%s before:%s" % [str(clipmap_counts_after), str(clipmap_counts_before)])

	var stats: Dictionary = scene.terrain.build_stats()
	var spacing_m: float = scene.chunk_size_m / float(scene.vertices_per_side - 1)
	var built_chunks: int = scene.built_chunk_count()
	if built_chunks != scene.expected_active_count():
		errors.append("built_chunks:%d expected:%d" % [built_chunks, scene.expected_active_count()])
	var avg_build_ms: float = float(stats.get("avg_recent_chunk_build_ms", 0.0))
	var max_build_ms: int = int(stats.get("max_recent_chunk_build_ms", 0))
	var native_payload_ms: float = float(stats.get("last_native_chunk_payload_ms", 0.0))
	var max_move_ms: int = _max_int(move_ms)
	if setup_ms > MAX_SETUP_MS:
		errors.append("setup_ms:%d limit:%d" % [setup_ms, MAX_SETUP_MS])
	if avg_build_ms > MAX_AVG_BUILD_MS:
		errors.append("avg_build_ms:%.1f limit:%.1f" % [avg_build_ms, MAX_AVG_BUILD_MS])
	if native_payload_ms > MAX_NATIVE_PAYLOAD_MS:
		errors.append("native_payload_ms:%.1f limit:%.1f" % [native_payload_ms, MAX_NATIVE_PAYLOAD_MS])
	if max_move_ms > MAX_MOVE_STEP_MS:
		errors.append("max_move_ms:%d limit:%d" % [max_move_ms, MAX_MOVE_STEP_MS])

	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-walk-257-probe] status=fail errors=%d setup_ms=%d warmup_steps=%d chunks=%d spacing=%.1fm avg_build_ms=%.1f max_build_ms=%d native_ms=%.0f move_ms=%s" % [
			errors.size(),
			setup_ms,
			warmup_steps,
			built_chunks,
			spacing_m,
			avg_build_ms,
			max_build_ms,
			native_payload_ms,
			str(move_ms),
		])
		quit(1)
		return

	print("[wg9-terrain-walk-257-probe] status=pass setup_ms=%d warmup_steps=%d chunks=%d vtx=%d spacing=%.1fm avg_build_ms=%.1f max_build_ms=%d native_ms=%.0f move_ms=%s far_build_counts=%s" % [
		setup_ms,
		warmup_steps,
		built_chunks,
		scene.vertices_per_side,
		spacing_m,
		avg_build_ms,
		max_build_ms,
		native_payload_ms,
		str(move_ms),
		str(clipmap_counts_after),
	])
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> int:
	for index in range(MAX_DRAIN_STEPS):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and native_queued == 0 and native_workers == 0 and int(scene.built_chunk_count()) >= active:
			return index + 1
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))
	return MAX_DRAIN_STEPS


func _far_clipmap_build_counts(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	var stats: Dictionary = scene.far_clipmap.stats()
	return (stats.get("build_counts", []) as Array).duplicate()


func _max_int(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = max(result, value)
	return result
