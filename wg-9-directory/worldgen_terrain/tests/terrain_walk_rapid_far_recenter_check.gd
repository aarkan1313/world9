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
	scene.viewer_position_xz = Vector2(scene.chunk_size_m + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	var boundary_stats: Dictionary = scene.far_clipmap.stats()
	var counts_after_boundary: Array = _far_counts(scene)
	var expected_level_count: int = _expected_level_count(scene)
	var expected_latest_recenter: int = expected_level_count
	var page_mode: bool = bool(boundary_stats.get("use_persistent_page_mesh", false))
	if _count_delta(counts_before, counts_after_boundary) != 0:
		errors.append("boundary_recenter_rebuilt:%s before:%s" % [str(counts_after_boundary), str(counts_before)])
	if not (boundary_stats.get("last_scheduled_levels", []) as Array).is_empty():
		errors.append("boundary_recenter_scheduled:%s" % str(boundary_stats))
	scene.viewer_position_xz = Vector2(scene.chunk_size_m * 2.0 + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	var first_stats: Dictionary = scene.far_clipmap.stats()
	var counts_after_first: Array = _far_counts(scene)
	scene.viewer_position_xz = Vector2(scene.chunk_size_m * 4.0 + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	var expected_latest_origin: Vector2 = scene._far_clipmap_center_xz()
	var second_stats: Dictionary = scene.far_clipmap.stats()
	var counts_after_second: Array = _far_counts(scene)
	if page_mode:
		expected_latest_recenter = expected_level_count * 2
		if _count_delta(counts_before, counts_after_first) != expected_level_count:
			errors.append("first_page_recenter_not_committed:%s before:%s" % [str(counts_after_first), str(counts_before)])
		if _count_delta(counts_before, counts_after_second) != expected_latest_recenter:
			errors.append("second_page_recenter_not_committed:%s before:%s" % [str(counts_after_second), str(counts_before)])
		if (first_stats.get("last_rebuilt_levels", []) as Array) != _expected_levels(scene):
			errors.append("first_page_rebuilt_levels:%s" % str(first_stats))
		if (second_stats.get("last_rebuilt_levels", []) as Array) != _expected_levels(scene):
			errors.append("second_page_rebuilt_levels:%s" % str(second_stats))
		if int(second_stats.get("pending_rebuild_count", 0)) != 0:
			errors.append("second_page_pending:%s" % str(second_stats))
	else:
		if _count_delta(counts_before, counts_after_first) != 0:
			errors.append("first_rapid_recenter_partially_committed:%s before:%s" % [str(counts_after_first), str(counts_before)])
		if _count_delta(counts_before, counts_after_second) != 0:
			errors.append("second_rapid_recenter_partially_committed:%s before:%s" % [str(counts_after_second), str(counts_before)])
		if not (first_stats.get("last_rebuilt_levels", []) as Array).is_empty():
			errors.append("first_rebuilt_synchronously:%s" % str(first_stats))
		if (first_stats.get("last_scheduled_levels", []) as Array).is_empty():
			errors.append("first_scheduled_empty:%s" % str(first_stats))
		if int(second_stats.get("active_worker_count", 0)) <= 0 and int(second_stats.get("pending_rebuild_count", 0)) <= 0:
			errors.append("second_no_async_work:%s" % str(second_stats))
	_drain_queue(scene, errors)
	var counts_after_drain: Array = _far_counts(scene)
	var origins_after_drain: Array = _far_origins(scene)
	if _count_delta(counts_before, counts_after_drain) != expected_latest_recenter:
		errors.append("rapid_recenter_did_not_finish:%s before:%s" % [str(counts_after_drain), str(counts_before)])
	for origin_value in origins_after_drain:
		var origin: Vector2 = origin_value as Vector2
		if origin.distance_to(expected_latest_origin) > 0.001:
			errors.append("rapid_recenter_origin:%s expected:%s" % [str(origin), str(expected_latest_origin)])
	var report := {
		"counts_before": counts_before,
		"counts_after_boundary": counts_after_boundary,
		"counts_after_first": counts_after_first,
		"counts_after_second": counts_after_second,
		"counts_after_drain": counts_after_drain,
		"expected_latest_origin": [expected_latest_origin.x, expected_latest_origin.y],
		"origins_after_drain": origins_after_drain,
		"boundary_stats": boundary_stats,
		"first_scheduled": first_stats.get("last_scheduled_levels", []),
		"second_deferred": second_stats.get("last_deferred_levels", []),
		"second_workers": int(second_stats.get("active_worker_count", 0)),
	}
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-rapid-far-recenter] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-rapid-far-recenter] status=pass report=%s" % JSON.stringify(report))
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(260):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		var far_pending: int = int(scene.far_clipmap.stats().get("pending_rebuild_count", 0)) if scene.far_clipmap != null else 0
		var far_workers: int = int(scene.far_clipmap.stats().get("active_worker_count", 0)) if scene.far_clipmap != null else 0
		if queued == 0 and native_queued == 0 and native_workers == 0 and far_pending == 0 and far_workers == 0 and int(scene.built_chunk_count()) >= active:
			return
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))


func _far_counts(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	return (scene.far_clipmap.stats().get("build_counts", []) as Array).duplicate()


func _far_origins(scene: Node3D) -> Array:
	if scene.far_clipmap == null:
		return []
	return scene.far_clipmap.level_origins.duplicate()


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
