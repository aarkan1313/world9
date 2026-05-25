extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 17
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.use_fast_gray_material = true
	node.reuse_chunk_nodes = true
	node.max_pooled_chunk_nodes = 16
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
	else:
		node.world.configure_streamer({
			"chunk_size_m": TerrainSettingsScript.CHUNK_SIZE_M,
			"visible_radius_chunks": 1,
			"max_lod": 4,
			"build_budget_per_frame": 9,
			"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
		})
		_drain_at(node, Vector2.ZERO, 3)
		var first_child_count: int = node.get_child_count()
		var first_active: int = int(node.built_chunk_count())
		_drain_at(node, Vector2(TerrainSettingsScript.CHUNK_SIZE_M * 5.0, 0.0), 4)
		var second_child_count: int = node.get_child_count()
		var second_active: int = int(node.built_chunk_count())
		var pool_count: int = int(node.pooled_chunk_count())
		if first_active != 9:
			errors.append("first_active:%d" % first_active)
		if second_active != 9:
			errors.append("second_active:%d" % second_active)
		if pool_count > 16:
			errors.append("pool_limit:%d" % pool_count)
		if second_child_count > first_child_count + 9:
			errors.append("pool_not_reusing_children:%d:%d" % [first_child_count, second_child_count])
	node.queue_free()
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-chunk-node-pool] status=pass active=9 pooled=%d children=%d" % [
		int(node.pooled_chunk_count()),
		node.get_child_count(),
	])
	return 0


func _drain_at(node: Node3D, position: Vector2, steps: int) -> void:
	for _index in range(steps):
		node.update_viewer(position)


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-chunk-node-pool] status=fail errors=%d" % errors.size())
