extends SceneTree

const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 129
	node.use_fast_gray_material = true
	node.use_native_chunk_payloads = true
	node.use_lod_mesh_density = true
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 4,
		"build_budget_per_frame": 8,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	for _index in range(8):
		node.update_viewer(Vector2.ZERO)
	var counts_by_lod: Dictionary = {}
	for mesh_instance_value in node.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		var lod: int = int(mesh_instance.get_meta("lod"))
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		counts_by_lod[lod] = max(int(counts_by_lod.get(lod, 0)), vertex_count)
	if int(counts_by_lod.get(0, 0)) != 129 * 129:
		errors.append("lod0_vertex_count:%d" % int(counts_by_lod.get(0, 0)))
	if int(counts_by_lod.get(1, 0)) != 65 * 65:
		errors.append("lod1_vertex_count:%d" % int(counts_by_lod.get(1, 0)))
	node.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-lod-density] status=fail errors=%d counts=%s" % [errors.size(), str(counts_by_lod)])
		quit(1)
		return
	print("[wg9-terrain-lod-density] status=pass counts=%s" % str(counts_by_lod))
	quit(0)
