extends SceneTree

const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_flat_visible_node(errors)
	_check_procedural_visible_node(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-world-node] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-terrain-world-node] status=pass flat_meshes=9 procedural_meshes=2")
	return 0


func _check_flat_visible_node(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	get_root().add_child(node)
	node.vertices_per_side = 17
	node.flat_height_m = 5.0
	node.debug_mode = TerrainWorldScript.DEBUG_LOD_RING
	if not node.setup_world(TerrainWorldScript.PROVIDER_FLAT, 1337):
		errors.append("flat_setup")
		node.queue_free()
		return
	var report: Dictionary = node.update_viewer(Vector2.ZERO)
	if report.get("status", "pass") != "pass":
		errors.append("flat_update")
	if node.built_chunk_count() != 2:
		errors.append("flat_build_budget:%d" % node.built_chunk_count())
	var preview_built: int = node.rebuild_all_active_for_preview(9)
	if preview_built != 9 or node.built_chunk_count() < 9:
		errors.append("flat_preview_built:%d count=%d" % [preview_built, node.built_chunk_count()])
	_check_mesh_instances("flat", node, errors)
	node.queue_free()


func _check_procedural_visible_node(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	get_root().add_child(node)
	node.vertices_per_side = 17
	node.debug_mode = TerrainWorldScript.DEBUG_FAMILY_PALETTE
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("procedural_setup:%s" % str(node.errors))
		node.queue_free()
		return
	var report: Dictionary = node.update_viewer(Vector2(9000.0, -3000.0))
	if report.get("status", "pass") != "pass":
		errors.append("procedural_update")
	if node.built_chunk_count() != 2:
		errors.append("procedural_build_budget:%d" % node.built_chunk_count())
	_check_mesh_instances("procedural", node, errors)
	var moved_report: Dictionary = node.update_viewer(Vector2(50000.0, 50000.0))
	if moved_report.get("status", "pass") != "pass":
		errors.append("procedural_move_update")
	if node.built_chunk_count() != 2:
		errors.append("procedural_move_retire_count:%d" % node.built_chunk_count())
	_check_mesh_instances("procedural_moved", node, errors)
	node.queue_free()


func _check_mesh_instances(label: String, node: Node3D, errors: Array[String]) -> void:
	for child in node.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			errors.append("%s_non_mesh_child" % label)
			continue
		if mesh_instance.mesh == null:
			errors.append("%s_missing_mesh:%s" % [label, mesh_instance.name])
			continue
		if mesh_instance.mesh.get_surface_count() != 1:
			errors.append("%s_surface_count:%s" % [label, mesh_instance.name])
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if vertices.is_empty():
			errors.append("%s_empty_vertices:%s" % [label, mesh_instance.name])
		if indices.is_empty():
			errors.append("%s_empty_indices:%s" % [label, mesh_instance.name])
