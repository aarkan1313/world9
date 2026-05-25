extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	get_root().add_child(scene)
	var start_ms: int = Time.get_ticks_msec()
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var setup_ms: int = Time.get_ticks_msec() - start_ms
	var warmup_ms: Array[int] = _drain_queue(scene, errors)
	var move_ms: Array[int] = []
	var clipmap_counts_before: Array = _far_clipmap_build_counts(scene)
	for _step in range(8):
		start_ms = Time.get_ticks_msec()
		scene.step_viewer(0.25, Vector2(1.0, 1.0).normalized(), 0.0)
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
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-walk-perf] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-terrain-walk-perf] status=pass setup_ms=%d warmup_ms=%s move_ms=%s chunks=%d vtx=%d spacing=%.1fm avg_build_ms=%.1f max_build_ms=%d far_build_counts=%s" % [
		setup_ms,
		str(warmup_ms),
		str(move_ms),
		built_chunks,
		scene.vertices_per_side,
		spacing_m,
		float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		int(stats.get("max_recent_chunk_build_ms", 0)),
		str(clipmap_counts_after),
	])
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> Array[int]:
	var timings: Array[int] = []
	for _index in range(180):
		var start_ms: int = Time.get_ticks_msec()
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		timings.append(Time.get_ticks_msec() - start_ms)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		var far_pending: int = int(scene.far_clipmap.stats().get("pending_rebuild_count", 0)) if scene.far_clipmap != null else 0
		var far_workers: int = int(scene.far_clipmap.stats().get("active_worker_count", 0)) if scene.far_clipmap != null else 0
		if queued == 0 and native_queued == 0 and native_workers == 0 and far_pending == 0 and far_workers == 0 and int(scene.built_chunk_count()) >= active:
			return timings
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))
	return timings


func _far_clipmap_build_counts(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	var stats: Dictionary = scene.far_clipmap.stats()
	return (stats.get("build_counts", []) as Array).duplicate()
