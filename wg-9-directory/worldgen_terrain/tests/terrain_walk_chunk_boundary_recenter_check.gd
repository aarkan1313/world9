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
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	_drain_queue(scene, errors)
	scene.viewer_position_xz = Vector2(scene.chunk_size_m - 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	_drain_queue(scene, errors)
	var counts_before: Array = _far_counts(scene)
	var expected_level_count: int = _expected_level_count(scene)
	var start_ms: int = Time.get_ticks_msec()
	scene.viewer_position_xz = Vector2(scene.chunk_size_m + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	var boundary_cross_ms: int = Time.get_ticks_msec() - start_ms
	var stats_after_boundary: Dictionary = scene.far_clipmap.stats()
	var counts_after_boundary: Array = _far_counts(scene)
	if _count_delta(counts_before, counts_after_boundary) != 0:
		errors.append("clipmap_rebuilt_on_boundary:%s before:%s" % [str(counts_after_boundary), str(counts_before)])
	if not (stats_after_boundary.get("last_rebuilt_levels", []) as Array).is_empty():
		errors.append("boundary_rebuilt_levels:%s" % str(stats_after_boundary))
	if not (stats_after_boundary.get("last_scheduled_levels", []) as Array).is_empty():
		errors.append("boundary_scheduled_levels:%s" % str(stats_after_boundary))
	if int(stats_after_boundary.get("pending_rebuild_count", 0)) != 0:
		errors.append("boundary_pending:%d" % int(stats_after_boundary.get("pending_rebuild_count", 0)))

	start_ms = Time.get_ticks_msec()
	scene.viewer_position_xz = Vector2(scene.chunk_size_m * 2.0 + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	var first_cross_ms: int = Time.get_ticks_msec() - start_ms
	var stats_after_first: Dictionary = scene.far_clipmap.stats()
	var counts_after_first: Array = _far_counts(scene)
	var page_mode: bool = bool(stats_after_first.get("use_persistent_page_mesh", false))
	var rebuilt_after_first: Array = stats_after_first.get("last_rebuilt_levels", []) as Array
	var scheduled_after_first: Array = stats_after_first.get("last_scheduled_levels", []) as Array
	var pending_after_first: int = int(stats_after_first.get("pending_rebuild_count", 0))
	var workers_after_first: int = int(stats_after_first.get("active_worker_count", 0))
	if page_mode:
		if _count_delta(counts_before, counts_after_first) != expected_level_count:
			errors.append("first_page_recenter_not_committed:%s before:%s" % [str(counts_after_first), str(counts_before)])
		if rebuilt_after_first != _expected_levels(scene):
			errors.append("first_page_rebuilt_levels:%s" % str(rebuilt_after_first))
		if pending_after_first != 0:
			errors.append("first_page_pending:%d" % pending_after_first)
	else:
		if _count_delta(counts_before, counts_after_first) != 0:
			errors.append("first_cross_partially_committed:%s before:%s" % [str(counts_after_first), str(counts_before)])
		if not rebuilt_after_first.is_empty():
			errors.append("first_rebuilt_levels_should_be_async:%s" % str(rebuilt_after_first))
		if scheduled_after_first.is_empty():
			errors.append("first_scheduled_levels_empty:%s" % str(stats_after_first))
		if workers_after_first <= 0:
			errors.append("workers_after_first_missing:%d" % workers_after_first)
	_drain_queue(scene, errors)
	var counts_after_drain: Array = _far_counts(scene)
	var pending_after_drain: int = int(scene.far_clipmap.stats().get("pending_rebuild_count", 0))
	if pending_after_drain != 0:
		errors.append("pending_after_drain:%d" % pending_after_drain)
	if _count_delta(counts_before, counts_after_drain) != expected_level_count:
		errors.append("clipmap_did_not_finish_budgeted_recenter:%s before:%s" % [str(counts_after_drain), str(counts_before)])
	var report := {
		"boundary_cross_ms": boundary_cross_ms,
		"first_cross_ms": first_cross_ms,
		"counts_before": counts_before,
		"counts_after_boundary": counts_after_boundary,
		"counts_after_first": counts_after_first,
		"counts_after_drain": counts_after_drain,
		"boundary_stats": stats_after_boundary,
		"first_rebuilt_levels": rebuilt_after_first,
		"first_scheduled_levels": scheduled_after_first,
		"pending_after_first": pending_after_first,
		"workers_after_first": workers_after_first,
	}
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-chunk-boundary-recenter] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-chunk-boundary-recenter] status=pass report=%s" % JSON.stringify(report))
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(220):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		var far_pending: int = int(scene.far_clipmap.stats().get("pending_rebuild_count", 0)) if scene.far_clipmap != null else 0
		if queued == 0 and native_queued == 0 and native_workers == 0 and far_pending == 0 and int(scene.built_chunk_count()) >= active:
			return
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))


func _far_counts(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	return (scene.far_clipmap.stats().get("build_counts", []) as Array).duplicate()


func _expected_level_count(scene: Node3D) -> int:
	if scene.far_clipmap == null:
		return 0
	return int(scene.far_clipmap.stats().get("levels", 0))


func _expected_levels(scene: Node3D) -> Array[int]:
	var levels: Array[int] = []
	for index in range(_expected_level_count(scene)):
		levels.append(index)
	return levels


func _count_delta(before: Array, after: Array) -> int:
	var total := 0
	for index in range(min(before.size(), after.size())):
		total += int(after[index]) - int(before[index])
	return total
