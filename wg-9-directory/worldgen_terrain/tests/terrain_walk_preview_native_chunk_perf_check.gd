extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.use_native_chunk_payloads = true
	get_root().add_child(scene)
	var start_ms: int = Time.get_ticks_msec()
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var setup_ms: int = Time.get_ticks_msec() - start_ms
	var warmup_ms: Array[int] = _drain_queue(scene, errors)
	var stats: Dictionary = scene.terrain.build_stats()
	var spacing_m: float = scene.chunk_size_m / float(scene.vertices_per_side - 1)
	var built_chunks: int = scene.built_chunk_count()
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-walk-native-chunk-perf] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-terrain-walk-native-chunk-perf] status=pass setup_ms=%d warmup_ms=%s chunks=%d vtx=%d spacing=%.1fm avg_build_ms=%.1f max_build_ms=%d native_ms=%d" % [
		setup_ms,
		str(warmup_ms),
		built_chunks,
		scene.vertices_per_side,
		spacing_m,
		float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		int(stats.get("max_recent_chunk_build_ms", 0)),
		int(stats.get("last_native_chunk_payload_ms", 0)),
	])
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> Array[int]:
	var timings: Array[int] = []
	for _index in range(40):
		var start_ms: int = Time.get_ticks_msec()
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		timings.append(Time.get_ticks_msec() - start_ms)
		var queued: int = int(report.get("queued_build_count", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and int(scene.built_chunk_count()) >= active:
			return timings
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))
	return timings
