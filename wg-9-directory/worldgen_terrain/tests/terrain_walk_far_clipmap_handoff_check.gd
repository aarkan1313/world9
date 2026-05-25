extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")

const HEIGHT_EPSILON := 0.0001
const XZ_KEY_SCALE := 1000.0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	_report_if_missing(scene, errors)
	_drain_queue(scene, errors)
	var report: Dictionary = _check_handoff(scene, errors)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-far-clipmap-handoff] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-far-clipmap-handoff] status=pass report=%s" % JSON.stringify(report))
	quit(0)


func _report_if_missing(scene: Node3D, errors: Array[String]) -> void:
	if scene.terrain == null:
		errors.append("terrain_missing")
	if scene.far_clipmap == null:
		errors.append("far_clipmap_missing")


func _drain_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(220):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var stats: Dictionary = scene.terrain.build_stats()
		var queued: int = int(report.get("queued_build_count", 0))
		var native_queued: int = int(stats.get("queued_native_worker_builds", 0))
		var native_workers: int = int(stats.get("active_native_workers", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and native_queued == 0 and native_workers == 0 and int(scene.built_chunk_count()) >= active:
			return
		OS.delay_msec(5)
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))


func _check_handoff(scene: Node3D, errors: Array[String]) -> Dictionary:
	if scene.far_clipmap == null or scene.terrain == null:
		return {}
	var center: Vector2 = scene._far_clipmap_center_xz()
	var visual_half_extent: float = scene._far_clipmap_near_hole_extent_m()
	var authoritative_half_extent: float = scene._near_chunk_window_half_extent_m()
	var level_origin: Vector2 = scene.far_clipmap.level_origins[0] as Vector2
	if level_origin.distance_to(center) > 0.001:
		errors.append("clipmap_origin:%s expected:%s" % [str(level_origin), str(center)])
	if absf(float(scene.far_clipmap.near_hole_extent_m) - visual_half_extent) > 0.001:
		errors.append("near_hole_extent:%.3f expected:%.3f" % [float(scene.far_clipmap.near_hole_extent_m), visual_half_extent])
	var near_vertices: Dictionary = _near_chunk_vertex_map(scene)
	var far: Dictionary = scene.far_clipmap.level_heightfields[0] as Dictionary
	var spacing: float = float(far["spacing_m"])
	var level0_underlay: bool = bool(scene.far_clipmap.level0_full_underlay_enabled)
	if level0_underlay:
		errors.append("level0_full_underlay_enabled")
	var underlap: float = authoritative_half_extent - visual_half_extent
	if underlap < spacing - 0.001:
		errors.append("handoff_underlap_too_small:%.3f spacing:%.3f" % [underlap, spacing])
	var anchor_drift_margin: float = max(scene.chunk_size_m * 0.5, scene.far_clipmap_recenter_distance_m)
	if visual_half_extent + anchor_drift_margin > authoritative_half_extent - spacing + 0.001:
		errors.append("handoff_not_covered_during_anchor_drift:visual=%.3f drift=%.3f near=%.3f spacing=%.3f" % [
			visual_half_extent,
			anchor_drift_margin,
			authoritative_half_extent,
			spacing,
		])
	var y_bias: float = float(scene.far_clipmap.visual_y_bias_per_level_m)
	if y_bias > -1.0:
		errors.append("handoff_y_bias_too_small:%.3f" % y_bias)
	var nearest_far_cell_inner_edge: float = _nearest_far_cell_inner_edge(far)
	if nearest_far_cell_inner_edge > authoritative_half_extent + 0.001:
		errors.append("far_starts_outside_near_window:%.3f near:%.3f" % [nearest_far_cell_inner_edge, authoritative_half_extent])
	var max_delta := 0.0
	var missing := 0
	var samples := 0
	var x := center.x - authoritative_half_extent
	while x <= center.x + authoritative_half_extent + spacing * 0.25:
		var north: Dictionary = _compare_sample(near_vertices, far, x, center.y - authoritative_half_extent)
		var south: Dictionary = _compare_sample(near_vertices, far, x, center.y + authoritative_half_extent)
		max_delta = max(max_delta, float(north["delta"]), float(south["delta"]))
		missing += int(north["missing"]) + int(south["missing"])
		samples += 2
		x += spacing
	var z := center.y - authoritative_half_extent + spacing
	while z <= center.y + authoritative_half_extent - spacing * 0.25:
		var west: Dictionary = _compare_sample(near_vertices, far, center.x - authoritative_half_extent, z)
		var east: Dictionary = _compare_sample(near_vertices, far, center.x + authoritative_half_extent, z)
		max_delta = max(max_delta, float(west["delta"]), float(east["delta"]))
		missing += int(west["missing"]) + int(east["missing"])
		samples += 2
		z += spacing
	if missing > 0:
		errors.append("missing_near_edge_samples:%d" % missing)
	if max_delta > HEIGHT_EPSILON:
		errors.append("handoff_height_delta:%.9f" % max_delta)
	return {
		"center": [center.x, center.y],
		"near_hole_extent_m": visual_half_extent,
		"authoritative_half_extent_m": authoritative_half_extent,
		"visual_underlap_m": underlap,
		"anchor_drift_margin_m": anchor_drift_margin,
		"visual_y_bias_per_level_m": y_bias,
		"level0_full_underlay_enabled": level0_underlay,
		"nearest_far_cell_inner_edge_m": nearest_far_cell_inner_edge,
		"samples": samples,
		"missing": missing,
		"max_delta": max_delta,
	}


func _near_chunk_vertex_map(scene: Node3D) -> Dictionary:
	var vertices_by_xz: Dictionary = {}
	for mesh_instance_value in scene.terrain.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		var lod: int = int(mesh_instance.get_meta("lod"))
		var count: int = scene.terrain._vertices_for_lod(lod)
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if mesh == null:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for index in range(count * count):
			var world_vertex: Vector3 = mesh_instance.position + vertices[index]
			vertices_by_xz[_xz_key(world_vertex.x, world_vertex.z)] = world_vertex.y
	return vertices_by_xz


func _compare_sample(near_vertices: Dictionary, far: Dictionary, world_x: float, world_z: float) -> Dictionary:
	var key: String = _xz_key(world_x, world_z)
	if not near_vertices.has(key):
		return {"missing": 1, "delta": 0.0}
	return {
		"missing": 0,
		"delta": absf(float(near_vertices[key]) - _heightfield_at_world(far, world_x, world_z)),
	}


func _heightfield_at_world(heightfield: Dictionary, world_x: float, world_z: float) -> float:
	var origin_x: float = float(heightfield["origin_x"])
	var origin_z: float = float(heightfield["origin_z"])
	var outer_extent: float = float(heightfield["outer_extent_m"])
	var spacing: float = float(heightfield["spacing_m"])
	var side: int = int(heightfield["vertices_per_side"])
	var x: int = int(round((world_x - (origin_x - outer_extent)) / spacing))
	var z: int = int(round((world_z - (origin_z - outer_extent)) / spacing))
	x = clampi(x, 0, side - 1)
	z = clampi(z, 0, side - 1)
	var height: PackedFloat32Array = heightfield["height"] as PackedFloat32Array
	return float(height[z * side + x])


func _nearest_far_cell_inner_edge(heightfield: Dictionary) -> float:
	var inner_extent: float = float(heightfield["inner_extent_m"])
	var spacing: float = float(heightfield["spacing_m"])
	return inner_extent - spacing * 0.5


func _xz_key(x: float, z: float) -> String:
	return "%d,%d" % [int(round(x * XZ_KEY_SCALE)), int(round(z * XZ_KEY_SCALE))]
