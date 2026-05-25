extends SceneTree

const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")

const HEIGHT_EPSILON := 0.0001
const XZ_EPSILON := 0.001


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var reports: Array[Dictionary] = []
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 129
	node.use_fast_gray_material = true
	node.use_native_chunk_payloads = true
	node.use_lod_mesh_density = true
	node.use_mesh_skirts = false
	node.mesh_skirt_depth_m = 48.0
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 3,
		"max_lod": 4,
		"build_budget_per_frame": 16,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	_drain_node(node, errors)
	if node.built_chunk_count() != 49:
		errors.append("built_chunk_count:%d" % node.built_chunk_count())
	_check_edges(node, reports, errors)
	_check_lod_transition_morph(node, errors)
	node.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-lod-mixed-density-edges] status=fail errors=%d reports=%s" % [errors.size(), JSON.stringify(reports)])
		quit(1)
		return
	print("[wg9-lod-mixed-density-edges] status=pass summary=%s" % JSON.stringify(reports[reports.size() - 1]))
	quit(0)


func _drain_node(node: Node3D, errors: Array[String]) -> void:
	for _index in range(12):
		var report: Dictionary = node.update_viewer(Vector2.ZERO)
		if report.get("status", "fail") != "pass":
			errors.append("update_failed:%s" % str(report))
			return
		if int(report.get("queued_build_count", 0)) == 0 and node.built_chunk_count() >= int(report.get("active_count", 0)):
			return
	errors.append("queue_not_drained:%s" % str(node.last_report))


func _check_edges(node: Node3D, reports: Array[Dictionary], errors: Array[String]) -> void:
	var mixed_pairs := 0
	var same_pairs := 0
	var max_height_delta := 0.0
	var max_xz_delta := 0.0
	for key_value in node.chunk_nodes.keys():
		var key: String = str(key_value)
		var mesh_instance: MeshInstance3D = node.chunk_nodes[key] as MeshInstance3D
		var cx: int = int(mesh_instance.get_meta("chunk_x"))
		var cz: int = int(mesh_instance.get_meta("chunk_z"))
		var east_key: String = "%d,%d" % [cx + 1, cz]
		if node.chunk_nodes.has(east_key):
			var report: Dictionary = _check_east_west(node, mesh_instance, node.chunk_nodes[east_key] as MeshInstance3D, errors)
			reports.append(report)
			if bool(report["mixed_density"]):
				mixed_pairs += 1
			else:
				same_pairs += 1
			max_height_delta = max(max_height_delta, float(report["max_height_delta"]))
			max_xz_delta = max(max_xz_delta, float(report["max_xz_delta"]))
		var south_key: String = "%d,%d" % [cx, cz + 1]
		if node.chunk_nodes.has(south_key):
			var report_south: Dictionary = _check_north_south(node, mesh_instance, node.chunk_nodes[south_key] as MeshInstance3D, errors)
			reports.append(report_south)
			if bool(report_south["mixed_density"]):
				mixed_pairs += 1
			else:
				same_pairs += 1
			max_height_delta = max(max_height_delta, float(report_south["max_height_delta"]))
			max_xz_delta = max(max_xz_delta, float(report_south["max_xz_delta"]))
	if mixed_pairs <= 0:
		errors.append("mixed_pairs_missing")
	reports.append({
		"summary": true,
		"mixed_pairs": mixed_pairs,
		"same_pairs": same_pairs,
		"max_height_delta": max_height_delta,
		"max_xz_delta": max_xz_delta,
	})


func _check_east_west(node: Node3D, west: MeshInstance3D, east: MeshInstance3D, errors: Array[String]) -> Dictionary:
	var west_info: Dictionary = _mesh_info(node, west)
	var east_info: Dictionary = _mesh_info(node, east)
	var west_count: int = int(west_info["count"])
	var east_count: int = int(east_info["count"])
	var max_height_delta := 0.0
	var max_xz_delta := 0.0
	var samples := 0
	var sample_count: int = min(west_count, east_count)
	var west_ratio: int = int((west_count - 1) / max(1, sample_count - 1))
	var east_ratio: int = int((east_count - 1) / max(1, sample_count - 1))
	for row in range(sample_count):
		var west_row: int = row * west_ratio
		var east_row: int = row * east_ratio
		var west_vertex: Vector3 = _world_vertex(west, west_info, west_row * west_count + west_count - 1)
		var east_vertex: Vector3 = _world_vertex(east, east_info, east_row * east_count)
		max_height_delta = max(max_height_delta, absf(west_vertex.y - east_vertex.y))
		max_xz_delta = max(max_xz_delta, Vector2(west_vertex.x, west_vertex.z).distance_to(Vector2(east_vertex.x, east_vertex.z)))
		samples += 1
	var report: Dictionary = _edge_report("east_west", west, east, west_count, east_count, samples, max_height_delta, max_xz_delta)
	_validate_edge_report(report, errors)
	return report


func _check_north_south(node: Node3D, north: MeshInstance3D, south: MeshInstance3D, errors: Array[String]) -> Dictionary:
	var north_info: Dictionary = _mesh_info(node, north)
	var south_info: Dictionary = _mesh_info(node, south)
	var north_count: int = int(north_info["count"])
	var south_count: int = int(south_info["count"])
	var max_height_delta := 0.0
	var max_xz_delta := 0.0
	var samples := 0
	var sample_count: int = min(north_count, south_count)
	var north_ratio: int = int((north_count - 1) / max(1, sample_count - 1))
	var south_ratio: int = int((south_count - 1) / max(1, sample_count - 1))
	for col in range(sample_count):
		var north_col: int = col * north_ratio
		var south_col: int = col * south_ratio
		var north_vertex: Vector3 = _world_vertex(north, north_info, (north_count - 1) * north_count + north_col)
		var south_vertex: Vector3 = _world_vertex(south, south_info, south_col)
		max_height_delta = max(max_height_delta, absf(north_vertex.y - south_vertex.y))
		max_xz_delta = max(max_xz_delta, Vector2(north_vertex.x, north_vertex.z).distance_to(Vector2(south_vertex.x, south_vertex.z)))
		samples += 1
	var report: Dictionary = _edge_report("north_south", north, south, north_count, south_count, samples, max_height_delta, max_xz_delta)
	_validate_edge_report(report, errors)
	return report


func _mesh_info(node: Node3D, mesh_instance: MeshInstance3D) -> Dictionary:
	var lod: int = int(mesh_instance.get_meta("lod"))
	var count: int = node._vertices_for_lod(lod)
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	return {
		"lod": lod,
		"count": count,
		"vertices": arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array,
	}


func _world_vertex(mesh_instance: MeshInstance3D, info: Dictionary, vertex_index: int) -> Vector3:
	var vertices: PackedVector3Array = info["vertices"] as PackedVector3Array
	return mesh_instance.position + vertices[vertex_index]


func _edge_report(
	direction: String,
	a: MeshInstance3D,
	b: MeshInstance3D,
	a_count: int,
	b_count: int,
	samples: int,
	max_height_delta: float,
	max_xz_delta: float
) -> Dictionary:
	return {
		"direction": direction,
		"a": "%d,%d" % [int(a.get_meta("chunk_x")), int(a.get_meta("chunk_z"))],
		"b": "%d,%d" % [int(b.get_meta("chunk_x")), int(b.get_meta("chunk_z"))],
		"a_lod": int(a.get_meta("lod")),
		"b_lod": int(b.get_meta("lod")),
		"a_count": a_count,
		"b_count": b_count,
		"mixed_density": a_count != b_count,
		"samples": samples,
		"max_height_delta": max_height_delta,
		"max_xz_delta": max_xz_delta,
	}


func _validate_edge_report(report: Dictionary, errors: Array[String]) -> void:
	if float(report["max_height_delta"]) > HEIGHT_EPSILON:
		errors.append("height_delta:%s" % JSON.stringify(report))
	if float(report["max_xz_delta"]) > XZ_EPSILON:
		errors.append("xz_delta:%s" % JSON.stringify(report))


func _check_lod_transition_morph(node: Node3D, errors: Array[String]) -> void:
	if not node.use_lod_transition_morph:
		errors.append("lod_transition_morph_disabled")
		return
	var fine: MeshInstance3D = node.chunk_nodes.get("1,0", null) as MeshInstance3D
	var coarse: MeshInstance3D = node.chunk_nodes.get("2,0", null) as MeshInstance3D
	if fine == null or coarse == null:
		errors.append("lod_transition_pair_missing")
		return
	if int(fine.get_meta("lod")) >= int(coarse.get_meta("lod")):
		errors.append("lod_transition_pair_not_mixed:%d:%d" % [int(fine.get_meta("lod")), int(coarse.get_meta("lod"))])
		return
	var info: Dictionary = _mesh_info(node, fine)
	var count: int = int(info["count"])
	var vertices: PackedVector3Array = info["vertices"] as PackedVector3Array
	var edge_row := 1
	var edge_index: int = edge_row * count + count - 1
	var edge_vertex: Vector3 = _world_vertex(fine, info, edge_index)
	var coarse_step: float = node._step_for_lod(int(coarse.get_meta("lod")))
	var expected_edge_y: float = node._coarse_chunk_surface_height(edge_vertex.x, edge_vertex.z, coarse_step)
	if absf(edge_vertex.y - expected_edge_y) > HEIGHT_EPSILON:
		errors.append("lod_transition_edge_not_morphed:%.6f expected:%.6f" % [edge_vertex.y, expected_edge_y])
	var inner_x: int = count - 1 - int(node.lod_transition_band_cells) - 2
	var inner_index: int = edge_row * count + inner_x
	var inner_vertex: Vector3 = _world_vertex(fine, info, inner_index)
	var raw_y: float = node.world.sample_height(inner_vertex.x, inner_vertex.z)
	if absf(inner_vertex.y - raw_y) > HEIGHT_EPSILON:
		errors.append("lod_transition_inner_changed:%.6f raw:%.6f" % [inner_vertex.y, raw_y])
