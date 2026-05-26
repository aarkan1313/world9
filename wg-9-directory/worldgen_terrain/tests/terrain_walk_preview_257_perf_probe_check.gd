extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")
const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")

var max_drain_steps: int = 260
var max_setup_ms: int = 800
var max_avg_build_ms: float = 90.0
var max_native_payload_ms: float = 140.0
var max_move_step_ms: int = 20


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var profile: Dictionary = TerrainQualityProfileScript.profile(TerrainQualityProfileScript.HIGH_DENSITY_257_REVIEW)
	_apply_profile_budgets(profile)
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.quality_profile_id = TerrainQualityProfileScript.HIGH_DENSITY_257_REVIEW
	TerrainQualityProfileScript.apply_to_node(scene, profile)
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
	var profile_report: Dictionary = scene.quality_profile_report()
	if profile_report.get("status", "fail") != "pass":
		errors.append("profile_report:%s" % str(profile_report))
	if setup_ms > max_setup_ms:
		errors.append("setup_ms:%d limit:%d" % [setup_ms, max_setup_ms])
	if avg_build_ms > max_avg_build_ms:
		errors.append("avg_build_ms:%.1f limit:%.1f" % [avg_build_ms, max_avg_build_ms])
	if native_payload_ms > max_native_payload_ms:
		errors.append("native_payload_ms:%.1f limit:%.1f" % [native_payload_ms, max_native_payload_ms])
	if max_move_ms > max_move_step_ms:
		errors.append("max_move_ms:%d limit:%d" % [max_move_ms, max_move_step_ms])

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
	for index in range(max_drain_steps):
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
	return max_drain_steps


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


func _apply_profile_budgets(profile: Dictionary) -> void:
	var budgets: Dictionary = profile.get("budgets", {}) as Dictionary
	max_drain_steps = int(budgets.get("high_density_max_drain_steps", max_drain_steps))
	max_setup_ms = int(budgets.get("high_density_max_setup_ms", max_setup_ms))
	max_avg_build_ms = float(budgets.get("high_density_max_avg_build_ms", max_avg_build_ms))
	max_native_payload_ms = float(budgets.get("high_density_max_native_payload_ms", max_native_payload_ms))
	max_move_step_ms = int(budgets.get("high_density_max_move_step_ms", max_move_step_ms))
