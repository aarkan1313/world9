extends SceneTree

const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	await _check_streaming_scene(errors)
	await _check_walk_scene(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-stationary-prefetch-direction] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-stationary-prefetch-direction] status=pass")
	quit(0)


func _check_streaming_scene(errors: Array[String]) -> void:
	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.visible_radius_chunks = 2
	scene.prefetch_forward_chunks = 2
	scene.residency_halo_chunks = 0
	scene.max_lod = 1
	scene.vertices_per_side = 33
	scene.build_budget_per_frame = 2
	scene.warmup_build_steps = 1
	scene.preload_active_chunks_before_start = false
	scene.use_far_clipmap = false
	scene.move_speed_mps = scene.chunk_size_m
	get_root().add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("streaming_setup_failed:%s" % str(scene.get("errors")))
		scene.queue_free()
		return
	var moved: Dictionary = scene.call("step_viewer", 1.0, Vector2(0.0, -1.0), 0.0) as Dictionary
	var idle: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0) as Dictionary
	_assert_stationary_report("streaming", moved, idle, scene, errors)
	scene.queue_free()


func _check_walk_scene(errors: Array[String]) -> void:
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.visible_radius_chunks = 2
	scene.prefetch_forward_chunks = 2
	scene.residency_halo_chunks = 0
	scene.max_lod = 1
	scene.vertices_per_side = 33
	scene.build_budget_per_frame = 2
	scene.warmup_build_steps = 1
	scene.preload_active_chunks_before_start = false
	scene.use_far_clipmap = false
	scene.use_gpu_page_chunks = false
	scene.use_gpu_provider_page_chunk_textures = false
	scene.use_gpu_provider_page_chunk_descriptor_staging = false
	scene.move_speed_mps = scene.chunk_size_m
	get_root().add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("walk_setup_failed:%s" % str(scene.get("errors")))
		scene.queue_free()
		return
	var moved: Dictionary = scene.call("step_viewer", 1.0, Vector2(0.0, -1.0), 0.0, 0.0) as Dictionary
	var idle: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
	_assert_stationary_report("walk", moved, idle, scene, errors)
	scene.queue_free()


func _assert_stationary_report(label: String, moved: Dictionary, idle: Dictionary, scene: Node3D, errors: Array[String]) -> void:
	if str(moved.get("status", "fail")) != "pass":
		errors.append("%s_move_report:%s" % [label, str(moved)])
	if str(idle.get("status", "fail")) != "pass":
		errors.append("%s_idle_report:%s" % [label, str(idle)])
	if int(idle.get("created_count", 0)) != 0:
		errors.append("%s_idle_created:%s" % [label, str(idle)])
	if int(idle.get("retired_count", 0)) != 0:
		errors.append("%s_idle_retired:%s" % [label, str(idle)])
	if int(idle.get("lod_changed_count", 0)) != 0:
		errors.append("%s_idle_lod_changed:%s" % [label, str(idle)])
	var moved_prefetch: Array = moved.get("prefetch_step", []) as Array
	var idle_prefetch: Array = idle.get("prefetch_step", []) as Array
	if moved_prefetch != idle_prefetch:
		errors.append("%s_prefetch_step_changed:%s -> %s" % [label, str(moved_prefetch), str(idle_prefetch)])
