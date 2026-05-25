extends SceneTree

const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainDetailTierPolicyScript := preload("res://worldgen_terrain/core/terrain_detail_tier_policy.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return

	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_report_and_quit(errors)
		return

	var node: Node3D = TerrainLocalDetailNodeScript.new()
	node.enabled = true
	node.patch_size_m = 256.0
	node.vertices_per_side = 257
	node.radius_patches = 0
	node.max_active_patches = 1
	node.use_native_payloads = true
	node.use_native_workers = true
	node.max_native_workers = 1
	node.enable_collision_bodies = true
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("node_setup_failed:%s" % str(node.errors))
		_report_and_quit(errors)
		return
	_check_semantic_queue_signature(node, errors)

	var first: Dictionary = node.update_viewer(Vector2(12.0, 80.0))
	if first.get("status", "fail") != "pass":
		errors.append("first_update_failed:%s" % str(first))
	if int(first.get("active_native_workers", 0)) + int(first.get("queued_worker_builds", 0)) <= 0:
		errors.append("first_worker_not_started:%s" % str(first))
	if node.patch_nodes.has("0,0"):
		errors.append("stale_patch_built_synchronously")

	var move_start_ms: int = Time.get_ticks_msec()
	var moved: Dictionary = node.update_viewer(Vector2(300.0, 80.0))
	var move_update_ms: int = Time.get_ticks_msec() - move_start_ms
	if moved.get("status", "fail") != "pass":
		errors.append("move_update_failed:%s" % str(moved))
	if node.patch_nodes.has("0,0"):
		errors.append("stale_patch_attached_immediately")
	if node.collision_bodies.has("0,0"):
		errors.append("stale_collision_attached_immediately")

	var frames: int = _drain_until_current_patch(node, errors)
	if node.patch_nodes.has("0,0"):
		errors.append("stale_patch_attached_after_worker")
	if node.collision_bodies.has("0,0"):
		errors.append("stale_collision_attached_after_worker")
	if not node.patch_nodes.has("1,0"):
		errors.append("current_patch_not_built")
	if not node.collision_bodies.has("1,0"):
		errors.append("current_collision_not_built")
	_check_active_patch_rebuilds_on_density_change(node, errors)
	var stats: Dictionary = node.build_stats()
	stats["move_update_ms"] = move_update_ms
	stats["drain_frames"] = frames
	node.queue_free()
	_report_and_quit(errors, stats)


func _drain_until_current_patch(node: Node3D, errors: Array[String]) -> int:
	for index in range(120):
		var report: Dictionary = node.update_viewer(Vector2(300.0, 80.0))
		if report.get("status", "fail") != "pass":
			errors.append("drain_update_failed:%s" % str(report))
			return index + 1
		if node.patch_nodes.has("1,0") and int(node.build_stats().get("active_native_workers", 0)) == 0:
			return index + 1
		OS.delay_msec(5)
	errors.append("current_worker_not_drained:%s" % JSON.stringify(node.build_stats()))
	return 120


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-local-detail-worker-stale] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-local-detail-worker-stale] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)


func _check_semantic_queue_signature(node: Node3D, errors: Array[String]) -> void:
	var original_vertices: int = node.vertices_per_side
	var original_queue: Array = node._native_worker_queue.duplicate(true)
	var original_desired: Dictionary = node._desired_patch_keys.duplicate(true)
	node._native_worker_queue.clear()
	node._desired_patch_keys.clear()
	node.vertices_per_side = 257
	var patch_257: Dictionary = TerrainDetailTierPolicyScript.active_patches(Vector2(12.0, 80.0), node.settings())[0]
	node._desired_patch_keys[str(patch_257["key"])] = patch_257
	if not node._enqueue_native_worker_build(patch_257):
		errors.append("semantic_enqueue_257_failed")
		node.vertices_per_side = original_vertices
		node._native_worker_queue = original_queue
		node._desired_patch_keys = original_desired
		return
	if not node._queued_worker_has_key(str(patch_257["key"])):
		errors.append("semantic_queue_missing_initial")
	node.vertices_per_side = 129
	var patch_129: Dictionary = TerrainDetailTierPolicyScript.active_patches(Vector2(12.0, 80.0), node.settings())[0]
	node._desired_patch_keys[str(patch_129["key"])] = patch_129
	if node._queued_worker_has_key(str(patch_129["key"])):
		errors.append("semantic_queue_accepted_stale_density")
	node._cancel_retired_worker_work(node._desired_patch_keys)
	if not node._native_worker_queue.is_empty():
		errors.append("semantic_queue_not_pruned:%s" % str(node._native_worker_queue))
	node.vertices_per_side = original_vertices
	node._native_worker_queue = original_queue
	node._desired_patch_keys = original_desired


func _check_active_patch_rebuilds_on_density_change(node: Node3D, errors: Array[String]) -> void:
	node.use_native_workers = false
	node.vertices_per_side = 129
	var report: Dictionary = node.update_viewer(Vector2(300.0, 80.0))
	if report.get("status", "fail") != "pass":
		errors.append("density_change_update_failed:%s" % str(report))
		return
	if not node.patch_nodes.has("1,0"):
		errors.append("density_change_patch_missing")
		return
	var heightfield: Dictionary = node.patch_heightfields.get("1,0", {}) as Dictionary
	if int(heightfield.get("vertices_per_side", 0)) != 129:
		errors.append("density_change_stale_vertices:%d" % int(heightfield.get("vertices_per_side", 0)))
	var mesh_instance: MeshInstance3D = node.patch_nodes["1,0"] as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		errors.append("density_change_mesh_missing")
		return
	var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if vertices.size() != 129 * 129:
		errors.append("density_change_mesh_vertices:%d" % vertices.size())
