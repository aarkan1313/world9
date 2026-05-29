extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")

const MAX_SURFACE_TEXTURE_MS := 30


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
		_report_and_quit(scene, errors, {})
		return
	_drain_queue(scene, errors)

	scene.apply_far_clipmap_surface_review(true, 0.75)
	scene._update_streamer()
	scene._update_camera()
	_drain_queue(scene, errors)
	var expected_level_count: int = _expected_level_count(scene)
	var counts_before_surface_move: Array = _far_counts(scene)
	scene.viewer_position_xz = Vector2(scene.chunk_size_m - 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	_drain_queue(scene, errors)
	var counts_before_cross: Array = _far_counts(scene)
	if _count_delta(counts_before_surface_move, counts_before_cross) != 0:
		errors.append("surface_position_prep_rebuilt:%s before:%s" % [str(counts_before_cross), str(counts_before_surface_move)])

	scene.viewer_position_xz = Vector2(scene.chunk_size_m + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	var stats_after_boundary: Dictionary = scene.far_clipmap.stats()
	var counts_after_boundary: Array = _far_counts(scene)
	if _count_delta(counts_before_cross, counts_after_boundary) != 0:
		errors.append("surface_boundary_rebuilt:%s before:%s" % [str(counts_after_boundary), str(counts_before_cross)])
	if not (stats_after_boundary.get("last_scheduled_levels", []) as Array).is_empty():
		errors.append("surface_boundary_scheduled:%s" % str(stats_after_boundary))
	if int(stats_after_boundary.get("pending_rebuild_count", 0)) != 0:
		errors.append("surface_boundary_pending:%d" % int(stats_after_boundary.get("pending_rebuild_count", 0)))

	var start_ms: int = Time.get_ticks_msec()
	scene.viewer_position_xz = Vector2(scene.chunk_size_m * 2.0 + 4.0, scene.chunk_size_m * 0.5)
	scene._update_streamer()
	scene._update_camera()
	var first_cross_ms: int = Time.get_ticks_msec() - start_ms
	var stats_after_first: Dictionary = scene.far_clipmap.stats()
	var counts_after_first: Array = _far_counts(scene)
	var page_mode: bool = bool(stats_after_first.get("use_persistent_page_mesh", false))
	var page_async: bool = page_mode and scene.use_far_clipmap_native_workers
	var rebuilt_after_first: Array = stats_after_first.get("last_rebuilt_levels", []) as Array
	var scheduled_after_first: Array = stats_after_first.get("last_scheduled_levels", []) as Array
	var pending_after_first: int = int(stats_after_first.get("pending_rebuild_count", 0))
	var workers_after_first: int = int(stats_after_first.get("active_worker_count", 0))
	if page_mode and not page_async:
		if _count_delta(counts_before_cross, counts_after_first) != expected_level_count:
			errors.append("surface_page_recenter_not_committed:%s before:%s" % [str(counts_after_first), str(counts_before_cross)])
		if rebuilt_after_first != _expected_levels(scene):
			errors.append("surface_page_rebuilt_levels:%s" % str(rebuilt_after_first))
		if pending_after_first != 0:
			errors.append("surface_page_pending:%d" % pending_after_first)
	else:
		if _count_delta(counts_before_cross, counts_after_first) != 0:
			errors.append("surface_first_cross_partially_committed:%s before:%s" % [str(counts_after_first), str(counts_before_cross)])
		if not rebuilt_after_first.is_empty():
			errors.append("surface_first_rebuilt_synchronously:%s" % str(rebuilt_after_first))
		if scheduled_after_first.is_empty():
			errors.append("surface_first_scheduled_empty:%s" % str(stats_after_first))
		if pending_after_first <= 0:
			errors.append("surface_pending_after_first_missing:%d" % pending_after_first)
		if workers_after_first <= 0:
			errors.append("surface_workers_after_first_missing:%d" % workers_after_first)

	_drain_queue(scene, errors)
	var stats_after_drain: Dictionary = scene.far_clipmap.stats()
	var counts_after_drain: Array = _far_counts(scene)
	var descriptors: Array = scene.far_clipmap.active_surface_texture_descriptors()
	var surface_texture_ms: int = int(stats_after_drain.get("last_surface_texture_ms", 0))
	if page_async and str(stats_after_drain.get("last_worker_payload_mode", "")) != "height_page":
		errors.append("surface_page_worker_payload_mode:%s" % str(stats_after_drain))
	if page_async and not _has_valid_page_texture_descriptor(scene):
		errors.append("surface_page_descriptor_texture_missing:%s" % str(scene.far_clipmap.level_material_descriptors))
	if int(stats_after_drain.get("pending_rebuild_count", 0)) != 0:
		errors.append("surface_pending_after_drain:%d" % int(stats_after_drain.get("pending_rebuild_count", 0)))
	if _count_delta(counts_before_cross, counts_after_drain) != expected_level_count:
		errors.append("surface_clipmap_did_not_finish:%s before:%s" % [str(counts_after_drain), str(counts_before_cross)])
	if descriptors.size() != expected_level_count:
		errors.append("surface_descriptor_count:%d" % descriptors.size())
	if surface_texture_ms > MAX_SURFACE_TEXTURE_MS:
		errors.append("surface_texture_ms:%d limit:%d" % [surface_texture_ms, MAX_SURFACE_TEXTURE_MS])
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		if descriptor.get("status", "fail") != "pass":
			errors.append("surface_descriptor_failed:%s" % str(descriptor))
	var report := {
		"first_cross_ms": first_cross_ms,
		"counts_before": counts_before_cross,
		"counts_after_boundary": counts_after_boundary,
		"counts_after_first": counts_after_first,
		"counts_after_drain": counts_after_drain,
		"boundary_stats": stats_after_boundary,
		"first_rebuilt_levels": rebuilt_after_first,
		"first_scheduled_levels": scheduled_after_first,
		"pending_after_first": pending_after_first,
		"workers_after_first": workers_after_first,
		"last_worker_payload_mode": str(stats_after_drain.get("last_worker_payload_mode", "")),
		"last_page_descriptor_preencoded_hits": int(stats_after_drain.get("last_page_descriptor_preencoded_hits", 0)),
		"descriptor_modes": _descriptor_modes(scene),
		"errors": errors.duplicate(),
		"surface_texture_ms": surface_texture_ms,
	}
	_report_and_quit(scene, errors, report)


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


func _expected_level_count(scene: Node3D) -> int:
	if scene.far_clipmap == null:
		return 0
	return int(scene.far_clipmap.stats().get("levels", 0))


func _expected_levels(scene: Node3D) -> Array[int]:
	var levels: Array[int] = []
	for index in range(_expected_level_count(scene)):
		levels.append(index)
	return levels


func _has_valid_page_texture_descriptor(scene: Node3D) -> bool:
	if scene.far_clipmap == null:
		return false
	for descriptor_value in scene.far_clipmap.level_material_descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		if descriptor.get("status", "fail") != "pass":
			continue
		if descriptor.has("height_texture_rid"):
			return true
		if (descriptor.get("height_image_data", PackedByteArray()) as PackedByteArray).size() > 0:
			return true
	return false


func _descriptor_modes(scene: Node3D) -> Array[String]:
	var modes: Array[String] = []
	if scene.far_clipmap == null:
		return modes
	for descriptor_value in scene.far_clipmap.level_material_descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		modes.append("%s:rid=%s:height_bytes=%d:image_bytes=%d" % [
			str(descriptor.get("texture_payload_mode", "")),
			str(descriptor.has("height_texture_rid")),
			int(descriptor.get("height_bytes", 0)),
			(descriptor.get("height_image_data", PackedByteArray()) as PackedByteArray).size(),
		])
	return modes


func _count_delta(before: Array, after: Array) -> int:
	var total := 0
	for index in range(min(before.size(), after.size())):
		total += int(after[index]) - int(before[index])
	return total


func _report_and_quit(scene: Node3D, errors: Array[String], report: Dictionary) -> void:
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-far-surface-recenter] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-far-surface-recenter] status=pass report=%s" % JSON.stringify(report))
	quit(0)
