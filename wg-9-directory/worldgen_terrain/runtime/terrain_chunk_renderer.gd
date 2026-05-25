class_name TerrainChunkRenderer
extends RefCounted

var parent: Node3D
var chunk_nodes: Dictionary = {}
var reuse_chunk_nodes: bool = true
var max_pooled_chunk_nodes: int = 64
var _chunk_node_pool: Array[MeshInstance3D] = []


func setup(p_parent: Node3D, p_reuse_chunk_nodes: bool = true, p_max_pooled_chunk_nodes: int = 64) -> void:
	parent = p_parent
	reuse_chunk_nodes = p_reuse_chunk_nodes
	max_pooled_chunk_nodes = max(0, p_max_pooled_chunk_nodes)


func sync_settings(p_reuse_chunk_nodes: bool, p_max_pooled_chunk_nodes: int) -> void:
	reuse_chunk_nodes = p_reuse_chunk_nodes
	max_pooled_chunk_nodes = max(0, p_max_pooled_chunk_nodes)
	_trim_pool_to_limit()


func clear_all() -> void:
	for node_value in chunk_nodes.values():
		var mesh_instance: MeshInstance3D = node_value as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.queue_free()
	for pooled in _chunk_node_pool:
		if pooled != null:
			pooled.queue_free()
	chunk_nodes.clear()
	_chunk_node_pool.clear()


func apply_chunk(
	key: String,
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	chunk_size_m: float,
	mesh: Mesh,
	material: Material
) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = _node_for_key(key)
	mesh_instance.name = "chunk_%d_%d" % [chunk_x, chunk_z]
	mesh_instance.visible = true
	mesh_instance.position = Vector3(float(chunk_x) * chunk_size_m, 0.0, float(chunk_z) * chunk_size_m)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.set_meta("chunk_x", chunk_x)
	mesh_instance.set_meta("chunk_z", chunk_z)
	mesh_instance.set_meta("ring", ring)
	mesh_instance.set_meta("lod", lod)
	return mesh_instance


func retire_inactive(active_keys: Dictionary) -> int:
	var retired := 0
	var existing_keys: Array = chunk_nodes.keys()
	for key_value in existing_keys:
		var key: String = str(key_value)
		if active_keys.has(key):
			continue
		var node: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		chunk_nodes.erase(key)
		_release_node(node)
		retired += 1
	return retired


func built_chunk_count() -> int:
	return chunk_nodes.size()


func pooled_chunk_count() -> int:
	return _chunk_node_pool.size()


func _node_for_key(key: String) -> MeshInstance3D:
	if chunk_nodes.has(key):
		return chunk_nodes[key] as MeshInstance3D
	var mesh_instance: MeshInstance3D = _acquire_node()
	chunk_nodes[key] = mesh_instance
	return mesh_instance


func _acquire_node() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D
	if reuse_chunk_nodes and not _chunk_node_pool.is_empty():
		mesh_instance = _chunk_node_pool.pop_back()
	else:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if parent != null:
			parent.add_child(mesh_instance)
	mesh_instance.visible = true
	return mesh_instance


func _release_node(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null:
		return
	if reuse_chunk_nodes and _chunk_node_pool.size() < max_pooled_chunk_nodes:
		mesh_instance.visible = false
		mesh_instance.mesh = null
		mesh_instance.material_override = null
		mesh_instance.name = "pooled_chunk_%d" % _chunk_node_pool.size()
		mesh_instance.set_meta("chunk_x", 0)
		mesh_instance.set_meta("chunk_z", 0)
		mesh_instance.set_meta("ring", -1)
		mesh_instance.set_meta("lod", -1)
		_chunk_node_pool.append(mesh_instance)
	else:
		mesh_instance.queue_free()


func _trim_pool_to_limit() -> void:
	while _chunk_node_pool.size() > max_pooled_chunk_nodes:
		var mesh_instance: MeshInstance3D = _chunk_node_pool.pop_back()
		if mesh_instance != null:
			mesh_instance.queue_free()
