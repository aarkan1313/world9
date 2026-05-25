extends SceneTree

const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const MAX_INITIAL_UPDATE_MS := 90
const MAX_PATCH_MOVE_UPDATE_MS := 25
const MAX_DRAIN_FRAMES := 120


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return

	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 1
	scene.warmup_build_steps = 1
	scene.use_fast_gray_material = true
	scene.use_local_detail = true
	scene.local_detail_radius_patches = 0
	scene.local_detail_max_active_patches = 1
	scene.use_local_detail_workers = true
	scene.enable_local_collision_bodies = true
	get_root().add_child(scene)

	var setup_start_ms: int = Time.get_ticks_msec()
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
		_report_and_quit(errors)
		return
	var setup_ms: int = Time.get_ticks_msec() - setup_start_ms
	var initial_report: Dictionary = scene.local_detail.last_report
	if int(initial_report.get("built_now", -1)) != 0:
		errors.append("initial_detail_built_sync:%d" % int(initial_report.get("built_now", -1)))
	if int(initial_report.get("active_native_workers", 0)) + int(initial_report.get("queued_worker_builds", 0)) <= 0:
		errors.append("initial_worker_not_started:%s" % str(initial_report))
	var initial_update_ms: int = int(scene.local_detail.build_stats().get("last_build_ms", 0))
	if setup_ms > 1000:
		errors.append("setup_ms:%d" % setup_ms)
	if initial_update_ms > MAX_INITIAL_UPDATE_MS:
		errors.append("initial_update_ms:%d limit:%d" % [initial_update_ms, MAX_INITIAL_UPDATE_MS])

	var warmup_frames: int = _drain_detail_patch(scene, "0,0", errors)
	if not scene.local_detail.patch_nodes.has("0,0"):
		errors.append("initial_patch_not_ready")
	if not scene.local_detail.collision_bodies.has("0,0"):
		errors.append("initial_collision_not_ready")

	var move_ms: Array[int] = []
	var targets: Array[Vector2] = [
		Vector2(300.0, 80.0),
		Vector2(556.0, 80.0),
		Vector2(812.0, 80.0),
	]
	var expected_keys: Array[String] = ["1,0", "2,0", "3,0"]
	var drain_frames: Array[int] = []
	for index in range(targets.size()):
		scene.viewer_position_xz = targets[index]
		var start_ms: int = Time.get_ticks_msec()
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var elapsed_ms: int = Time.get_ticks_msec() - start_ms
		move_ms.append(elapsed_ms)
		if report.get("status", "fail") != "pass":
			errors.append("move_report_failed:%d:%s" % [index, str(report)])
		if elapsed_ms > MAX_PATCH_MOVE_UPDATE_MS:
			errors.append("move_ms_%d:%d limit:%d" % [index, elapsed_ms, MAX_PATCH_MOVE_UPDATE_MS])
		var key: String = expected_keys[index]
		drain_frames.append(_drain_detail_patch(scene, key, errors))
		if not scene.local_detail.patch_nodes.has(key):
			errors.append("patch_missing:%s" % key)
		if not scene.local_detail.collision_bodies.has(key):
			errors.append("collision_missing:%s" % key)

	var stats: Dictionary = scene.local_detail.build_stats()
	stats["setup_ms"] = setup_ms
	stats["move_ms"] = move_ms
	stats["warmup_frames"] = warmup_frames
	stats["drain_frames"] = drain_frames
	scene.queue_free()
	_report_and_quit(errors, stats)


func _drain_detail_patch(scene: Node3D, key: String, errors: Array[String]) -> int:
	for index in range(MAX_DRAIN_FRAMES):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		if report.get("status", "fail") != "pass":
			errors.append("drain_report_failed:%s:%s" % [key, str(report)])
			return index + 1
		var stats: Dictionary = scene.local_detail.build_stats()
		if (
			scene.local_detail.patch_nodes.has(key)
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("queued_worker_builds", 0)) == 0
		):
			return index + 1
		OS.delay_msec(5)
	errors.append("drain_timeout:%s:%s" % [key, JSON.stringify(scene.local_detail.build_stats())])
	return MAX_DRAIN_FRAMES


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-local-detail-worker-perf] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-streaming-local-detail-worker-perf] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
