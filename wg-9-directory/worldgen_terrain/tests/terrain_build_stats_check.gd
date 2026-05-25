extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_node_stats(errors)
	_check_streaming_diagnostics(errors)
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-build-stats] status=pass")
	return 0


func _check_node_stats(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.use_fast_gray_material = true
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("node_setup")
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": TerrainSettingsScript.CHUNK_SIZE_M,
		"visible_radius_chunks": 1,
		"max_lod": 4,
		"build_budget_per_frame": 2,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	node.update_viewer(Vector2.ZERO)
	node.update_viewer(Vector2.ZERO)
	var stats: Dictionary = node.build_stats()
	if int(stats.get("total_chunk_builds", 0)) < 2:
		errors.append("total_builds:%d" % int(stats.get("total_chunk_builds", 0)))
	if int(stats.get("recent_build_count", 0)) <= 0:
		errors.append("recent_count")
	if float(stats.get("avg_recent_chunk_build_ms", -1.0)) < 0.0:
		errors.append("avg_build_negative")
	if int(stats.get("active_chunks", -1)) != node.built_chunk_count():
		errors.append("active_stat")
	node.queue_free()


func _check_streaming_diagnostics(errors: Array[String]) -> void:
	var scene: Node = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 1
	scene.warmup_build_steps = 1
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("streaming_setup")
		scene.queue_free()
		return
	var text: String = str(scene.diagnostics_text())
	if not text.contains("build") or not text.contains("avg") or not text.contains("pool"):
		errors.append("diagnostics_missing_stats:%s" % text)
	scene.queue_free()


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-build-stats] status=fail errors=%d" % errors.size())
