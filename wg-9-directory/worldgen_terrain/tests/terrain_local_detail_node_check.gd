extends SceneTree

const TerrainDetailTierPolicyScript := preload("res://worldgen_terrain/core/terrain_detail_tier_policy.gd")
const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const HEIGHT_EPSILON := 0.0001


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
	node.use_native_workers = false
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("node_setup_failed:%s" % str(node.errors))
		_report_and_quit(errors)
		return

	_check_alignment(errors)
	_check_build_and_retire(node, errors)
	_check_payload_seams(node, errors)
	_check_height_queries_and_collision_contract(node, world, errors)
	_check_collision_body_lifecycle(node, errors)
	var stats: Dictionary = node.build_stats()
	node.queue_free()
	_report_and_quit(errors, stats)


func _check_alignment(errors: Array[String]) -> void:
	var alignment: Dictionary = TerrainDetailTierPolicyScript.validate_alignment(256.0, 257, 512.0, 129)
	if alignment.get("status", "fail") != "pass":
		errors.append("alignment_failed:%s" % str(alignment))
	if absf(float(alignment["detail_spacing_m"]) - 1.0) > 0.000001:
		errors.append("spacing:%.6f" % float(alignment["detail_spacing_m"]))
	if int(alignment["detail_samples_per_base_step"]) != 4:
		errors.append("detail_samples_per_base_step:%d" % int(alignment["detail_samples_per_base_step"]))


func _check_build_and_retire(node: Node3D, errors: Array[String]) -> void:
	var first: Dictionary = node.update_viewer(Vector2(12.0, 80.0))
	if first.get("status", "fail") != "pass":
		errors.append("first_update_failed:%s" % str(first))
	if int(first.get("active_count", -1)) != 1:
		errors.append("first_active:%d" % int(first.get("active_count", -1)))
	if int(first.get("built_now", -1)) != 1:
		errors.append("first_built:%d" % int(first.get("built_now", -1)))
	if int(first.get("retired_now", -1)) != 0:
		errors.append("first_retired:%d" % int(first.get("retired_now", -1)))
	if not node.patch_nodes.has("0,0"):
		errors.append("missing_patch_0_0")
	else:
		var patch: MeshInstance3D = node.patch_nodes["0,0"] as MeshInstance3D
		_check_patch_node(patch, "0,0", Vector3(0.0, node.vertical_offset_m, 0.0), errors)

	var repeat: Dictionary = node.update_viewer(Vector2(128.0, 128.0))
	if int(repeat.get("built_now", -1)) != 0 or int(repeat.get("retired_now", -1)) != 0:
		errors.append("repeat_changed:%s" % str(repeat))

	var moved: Dictionary = node.update_viewer(Vector2(300.0, 80.0))
	if moved.get("status", "fail") != "pass":
		errors.append("moved_update_failed:%s" % str(moved))
	if int(moved.get("active_count", -1)) != 1:
		errors.append("moved_active:%d" % int(moved.get("active_count", -1)))
	if int(moved.get("built_now", -1)) != 1:
		errors.append("moved_built:%d" % int(moved.get("built_now", -1)))
	if int(moved.get("retired_now", -1)) != 1:
		errors.append("moved_retired:%d" % int(moved.get("retired_now", -1)))
	if node.patch_nodes.has("0,0"):
		errors.append("patch_0_0_not_retired")
	if not node.patch_nodes.has("1,0"):
		errors.append("missing_patch_1_0")
	else:
		var patch_moved: MeshInstance3D = node.patch_nodes["1,0"] as MeshInstance3D
		_check_patch_node(patch_moved, "1,0", Vector3(256.0, node.vertical_offset_m, 0.0), errors)
	if not node.patch_heightfields.has("1,0"):
		errors.append("missing_heightfield_1_0")


func _check_patch_node(patch: MeshInstance3D, expected_key: String, expected_position: Vector3, errors: Array[String]) -> void:
	if patch == null:
		errors.append("patch_null:%s" % expected_key)
		return
	if patch.mesh == null:
		errors.append("patch_mesh_null:%s" % expected_key)
	if str(patch.get_meta("detail_key")) != expected_key:
		errors.append("patch_key:%s expected:%s" % [str(patch.get_meta("detail_key")), expected_key])
	if patch.position.distance_to(expected_position) > 0.000001:
		errors.append("patch_position:%s expected:%s" % [str(patch.position), str(expected_position)])
	if absf(float(patch.get_meta("spacing_m")) - 1.0) > 0.000001:
		errors.append("patch_spacing:%.6f" % float(patch.get_meta("spacing_m")))


func _check_payload_seams(node: Node3D, errors: Array[String]) -> void:
	var settings: Dictionary = node.settings()
	var west_patch: Dictionary = TerrainDetailTierPolicyScript.active_patches(Vector2(12.0, 80.0), settings)[0]
	var east_patch: Dictionary = TerrainDetailTierPolicyScript.active_patches(Vector2(300.0, 80.0), settings)[0]
	var west_payload: Dictionary = node.build_patch_payload(west_patch)
	var east_payload: Dictionary = node.build_patch_payload(east_patch)
	if west_payload.get("status", "fail") != "pass":
		errors.append("west_payload_failed:%s" % str(west_payload))
		return
	if east_payload.get("status", "fail") != "pass":
		errors.append("east_payload_failed:%s" % str(east_payload))
		return
	var count: int = int(west_payload["vertices_per_side"])
	var delta: float = _east_west_edge_delta(west_payload["height"] as PackedFloat32Array, east_payload["height"] as PackedFloat32Array, count)
	if delta > HEIGHT_EPSILON:
		errors.append("edge_delta:%.9f" % delta)


func _check_height_queries_and_collision_contract(node: Node3D, world: RefCounted, errors: Array[String]) -> void:
	node.update_viewer(Vector2(300.0, 80.0))
	var query_points: Array[Vector2] = [
		Vector2(256.0, 0.0),
		Vector2(300.0, 80.0),
		Vector2(511.0, 255.0),
	]
	for point in query_points:
		var query: Dictionary = node.sample_height(point.x, point.y)
		if query.get("status", "fail") != "pass":
			errors.append("query_failed:%s:%s" % [str(point), str(query)])
			continue
		if str(query.get("source", "")) != "local_detail":
			errors.append("query_source:%s:%s" % [str(point), str(query.get("source", ""))])
		var expected: float = world.sample_height(point.x, point.y)
		var delta: float = abs(float(query["height_m"]) - expected)
		if delta > HEIGHT_EPSILON:
			errors.append("query_delta:%s:%.9f" % [str(point), delta])

	var fallback: Dictionary = node.sample_height(12.0, 80.0)
	if fallback.get("status", "fail") != "pass":
		errors.append("fallback_failed:%s" % str(fallback))
	elif str(fallback.get("source", "")) != "world_fallback":
		errors.append("fallback_source:%s" % str(fallback.get("source", "")))

	var fields: Array[Dictionary] = node.active_collision_heightfields()
	if fields.size() != 1:
		errors.append("heightfield_count:%d" % fields.size())
		return
	var field: Dictionary = fields[0]
	if str(field.get("key", "")) != "1,0":
		errors.append("heightfield_key:%s" % str(field.get("key", "")))
	if int(field.get("vertices_per_side", 0)) != 257:
		errors.append("heightfield_vertices:%d" % int(field.get("vertices_per_side", 0)))
	if absf(float(field.get("spacing_m", 0.0)) - 1.0) > 0.000001:
		errors.append("heightfield_spacing:%.6f" % float(field.get("spacing_m", 0.0)))
	var height: PackedFloat32Array = field["height"] as PackedFloat32Array
	if height.size() != 257 * 257:
		errors.append("heightfield_size:%d" % height.size())
	if float(field.get("height_max_m", -INF)) < float(field.get("height_min_m", INF)):
		errors.append("heightfield_range:%s:%s" % [str(field.get("height_min_m")), str(field.get("height_max_m"))])
	var shape_result: Dictionary = node.collision_shape_for_key("1,0")
	if shape_result.get("status", "fail") != "pass":
		errors.append("shape_result:%s" % str(shape_result))
	else:
		var shape: HeightMapShape3D = shape_result["shape"] as HeightMapShape3D
		if shape == null:
			errors.append("shape_null")
		else:
			if shape.map_width != 257:
				errors.append("shape_width:%d" % shape.map_width)
			if shape.map_depth != 257:
				errors.append("shape_depth:%d" % shape.map_depth)
			if shape.map_data.size() != 257 * 257:
				errors.append("shape_data:%d" % shape.map_data.size())
	var missing_shape: Dictionary = node.collision_shape_for_key("0,0")
	if missing_shape.get("status", "pass") == "pass":
		errors.append("missing_shape_passed")


func _check_collision_body_lifecycle(node: Node3D, errors: Array[String]) -> void:
	node.set_collision_bodies_enabled(false)
	if int(node.collision_bodies.size()) != 0:
		errors.append("collision_default_count:%d" % int(node.collision_bodies.size()))
	node.set_collision_bodies_enabled(true)
	if int(node.collision_bodies.size()) != 1:
		errors.append("collision_enabled_count:%d" % int(node.collision_bodies.size()))
		return
	if not node.collision_bodies.has("1,0"):
		errors.append("collision_missing_1_0")
		return
	var body: StaticBody3D = node.collision_bodies["1,0"] as StaticBody3D
	if body == null:
		errors.append("collision_body_null")
		return
	if body.position.distance_to(Vector3(384.0, node.collision_vertical_offset_m, 128.0)) > 0.000001:
		errors.append("collision_body_position:%s" % str(body.position))
	if body.collision_layer != node.collision_layer:
		errors.append("collision_layer:%d" % body.collision_layer)
	if body.collision_mask != node.collision_mask:
		errors.append("collision_mask:%d" % body.collision_mask)
	if body.get_child_count() != 1:
		errors.append("collision_child_count:%d" % body.get_child_count())
	else:
		var shape_node: CollisionShape3D = body.get_child(0) as CollisionShape3D
		if shape_node == null:
			errors.append("collision_shape_node_null")
		else:
			if shape_node.scale.distance_to(Vector3(1.0, 1.0, 1.0)) > 0.000001:
				errors.append("collision_shape_scale:%s" % str(shape_node.scale))
			var shape: HeightMapShape3D = shape_node.shape as HeightMapShape3D
			if shape == null:
				errors.append("collision_shape_null")
			else:
				if shape.map_width != 257:
					errors.append("collision_shape_width:%d" % shape.map_width)
				if shape.map_depth != 257:
					errors.append("collision_shape_depth:%d" % shape.map_depth)
				if shape.map_data.size() != 257 * 257:
					errors.append("collision_shape_data:%d" % shape.map_data.size())

	node.update_viewer(Vector2(12.0, 80.0))
	if node.collision_bodies.has("1,0"):
		errors.append("collision_old_not_retired")
	if not node.collision_bodies.has("0,0"):
		errors.append("collision_new_missing")
	node.set_collision_bodies_enabled(false)
	if int(node.collision_bodies.size()) != 0:
		errors.append("collision_disabled_count:%d" % int(node.collision_bodies.size()))


func _east_west_edge_delta(west: PackedFloat32Array, east: PackedFloat32Array, count: int) -> float:
	if west.size() != count * count or east.size() != count * count:
		return INF
	var max_delta := 0.0
	for row in range(count):
		max_delta = max(max_delta, abs(float(west[row * count + count - 1]) - float(east[row * count])))
	return max_delta


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-local-detail-node] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-local-detail-node] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
