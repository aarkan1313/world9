extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var startup_report: Dictionary = scene.last_stream_report.duplicate(true)
	scene.camera_yaw_rad = 0.0
	scene.look_pitch_rad = 0.0
	scene._update_camera()
	var returned_report: Dictionary = scene.step_viewer(0.0, Vector2(0.0, 1.0), 0.0)
	_drain_queue(scene, errors)
	var prefetch_report: Dictionary = returned_report.duplicate(true)
	var expected_prefetch_count: int = (scene.visible_radius_chunks * 2 + 1) * (scene.visible_radius_chunks * 2 + 2)
	if int(scene.prefetch_forward_chunks) != 1:
		errors.append("prefetch_setting:%d" % int(scene.prefetch_forward_chunks))
	if int(prefetch_report.get("active_count", 0)) != expected_prefetch_count:
		errors.append("prefetch_active_count:%d expected:%d report:%s" % [
			int(prefetch_report.get("active_count", 0)),
			expected_prefetch_count,
			str(prefetch_report),
		])
	if int(prefetch_report.get("base_active_count", 0)) != 49:
		errors.append("prefetch_base_active:%d" % int(prefetch_report.get("base_active_count", 0)))
	if prefetch_report.get("prefetch_step", []) != [0, 1]:
		errors.append("prefetch_step:%s" % str(prefetch_report.get("prefetch_step", [])))
	if scene.built_chunk_count() < int(prefetch_report.get("active_count", 0)):
		errors.append("prefetch_not_built:%d/%d startup:%s" % [
			scene.built_chunk_count(),
			int(prefetch_report.get("active_count", 0)),
			str(startup_report),
		])
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-prefetch-residency] startup=%s prefetch=%s terrain_errors=%s world_errors=%s" % [
			JSON.stringify(startup_report),
			JSON.stringify(prefetch_report),
			str(scene.terrain.errors if scene.terrain != null else []),
			str(scene.terrain.world.errors if scene.terrain != null and scene.terrain.world != null else []),
		])
		print("[wg9-walk-prefetch-residency] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-walk-prefetch-residency] status=pass active=%d built=%d" % [
		int(prefetch_report.get("active_count", 0)),
		scene.built_chunk_count(),
	])
	quit(0)


func _drain_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(180):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and native_queued == 0 and native_workers == 0 and scene.built_chunk_count() >= active:
			return
		OS.delay_msec(5)
	errors.append("prefetch_drain_timeout:%s" % scene.diagnostics_text())
