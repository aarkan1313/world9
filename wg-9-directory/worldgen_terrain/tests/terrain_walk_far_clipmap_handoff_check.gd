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
	_check_active_page_materials(scene, errors)
	_check_invalid_page_material_rejected(scene, errors)
	_check_stale_context_payload_rejection(scene, errors)
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
	var side: int = int(far["vertices_per_side"])
	var level0_underlay: bool = bool(scene.far_clipmap.level0_full_underlay_enabled)
	if not level0_underlay:
		errors.append("level0_full_underlay_disabled")
	if visual_half_extent > 0.001:
		errors.append("level0_underlay_hole_extent:%.3f" % visual_half_extent)
	if level0_underlay:
		var expected_full_index_count: int = (side - 1) * (side - 1) * 6
		var actual_index_count: int = int(scene.far_clipmap.level_index_counts[0])
		if actual_index_count != expected_full_index_count:
			errors.append("level0_mesh_still_hole_filtered:%d expected_full:%d" % [actual_index_count, expected_full_index_count])
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
	if y_bias >= -0.001 or y_bias < -0.5:
		errors.append("handoff_y_bias_out_of_range:%.3f" % y_bias)
	var nearest_far_cell_inner_edge: float = _nearest_far_cell_inner_edge(far)
	if nearest_far_cell_inner_edge > authoritative_half_extent + 0.001:
		errors.append("far_starts_outside_near_window:%.3f near:%.3f" % [nearest_far_cell_inner_edge, authoritative_half_extent])
	var max_delta := 0.0
	var max_delta_sample: Dictionary = {}
	var missing := 0
	var samples := 0
	var x := center.x - authoritative_half_extent
	while x <= center.x + authoritative_half_extent + spacing * 0.25:
		var north: Dictionary = _compare_sample(scene, near_vertices, far, x, center.y - authoritative_half_extent)
		var south: Dictionary = _compare_sample(scene, near_vertices, far, x, center.y + authoritative_half_extent)
		if float(north["delta"]) > max_delta:
			max_delta = float(north["delta"])
			max_delta_sample = north
		if float(south["delta"]) > max_delta:
			max_delta = float(south["delta"])
			max_delta_sample = south
		missing += int(north["missing"]) + int(south["missing"])
		samples += 2
		x += spacing
	var z := center.y - authoritative_half_extent + spacing
	while z <= center.y + authoritative_half_extent - spacing * 0.25:
		var west: Dictionary = _compare_sample(scene, near_vertices, far, center.x - authoritative_half_extent, z)
		var east: Dictionary = _compare_sample(scene, near_vertices, far, center.x + authoritative_half_extent, z)
		if float(west["delta"]) > max_delta:
			max_delta = float(west["delta"])
			max_delta_sample = west
		if float(east["delta"]) > max_delta:
			max_delta = float(east["delta"])
			max_delta_sample = east
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
		"max_delta_sample": max_delta_sample,
	}


func _check_active_page_materials(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		return
	var level_nodes: Array = scene.far_clipmap.get("level_nodes") as Array
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if not bool(scene.far_clipmap.call("_page_height_material_has_valid_textures", material)):
			errors.append("invalid_far_page_material:%d" % level)


func _check_invalid_page_material_rejected(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		return
	var invalid_descriptor := {
		"status": "pass",
		"cache_key": "invalid_missing_texture_payload",
		"level": 999,
		"origin_x": 0.0,
		"origin_z": 0.0,
		"outer_extent_m": 1024.0,
		"inner_extent_m": 0.0,
		"vertices_per_side": 17,
		"spacing_m": 128.0,
		"height_min_m": 0.0,
		"height_max_m": 0.0,
		"height_range_m": 1.0,
	}
	var material = scene.far_clipmap.call(
		"_page_height_material_for_descriptor",
		invalid_descriptor,
		999,
		null,
		null,
		1.0,
		Vector2.ZERO,
		1.0,
		null
	)
	if material != null:
		errors.append("invalid_page_material_not_rejected")


func _check_stale_context_payload_rejection(scene: Node3D, errors: Array[String]) -> void:
	if scene.far_clipmap == null:
		return
	var clipmap: Node = scene.far_clipmap
	var center: Vector2 = scene._far_clipmap_center_xz()
	var before_drop_count: int = int((clipmap.call("stats") as Dictionary).get("stale_payload_drop_count", 0))
	var stale_payload: Dictionary = _fake_stale_page_payload(clipmap, 0, center)
	clipmap.set("_staged_native_origin", center)
	clipmap.set("_staged_native_commit_ready", true)
	var staged: Dictionary = clipmap.get("_staged_native_payloads") as Dictionary
	staged[0] = stale_payload
	clipmap.set("_staged_native_payloads", staged)
	clipmap.call("_commit_staged_payloads_if_ready")
	var after_staged: Dictionary = clipmap.get("_staged_native_payloads") as Dictionary
	var after_drop_count: int = int((clipmap.call("stats") as Dictionary).get("stale_payload_drop_count", 0))
	if after_staged.has(0):
		errors.append("stale_context_payload_not_dropped")
	if after_drop_count <= before_drop_count:
		errors.append("stale_context_drop_counter_not_incremented:%d->%d" % [before_drop_count, after_drop_count])


func _fake_stale_page_payload(clipmap: Node, level: int, origin: Vector2) -> Dictionary:
	var spacing: float = float(clipmap.call("_level_spacing", level))
	var outer_extent: float = float(clipmap.call("_level_outer_extent", level))
	var side: int = int(clipmap.call("_side_for_extent", outer_extent, spacing))
	var height := PackedFloat32Array()
	height.resize(side * side)
	return {
		"status": "pass",
		"payload_mode": "height_page",
		"height": height,
		"height_image_data": PackedByteArray(),
		"height_image_only": true,
		"level": level,
		"origin_x": origin.x,
		"origin_z": origin.y,
		"outer_extent_m": outer_extent,
		"inner_extent_m": 512.0,
		"spacing_m": spacing,
		"side": side,
		"request_id": "stale",
		"render_context_key": "stale",
		"render_context_version": -1,
	}


func _near_chunk_vertex_map(scene: Node3D) -> Dictionary:
	var vertices_by_xz: Dictionary = {}
	for mesh_instance_value in scene.terrain.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		if mesh_instance == null or not mesh_instance.visible:
			continue
		var lod: int = int(mesh_instance.get_meta("lod"))
		var count: int = scene.terrain._vertices_for_lod(lod)
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if mesh == null:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var gpu_page_chunk: bool = bool(mesh_instance.get_meta("gpu_page_chunk", false))
		for index in range(count * count):
			var world_vertex: Vector3 = mesh_instance.position + vertices[index]
			var height: float = world_vertex.y
			var key: String = _xz_key(world_vertex.x, world_vertex.z)
			if not vertices_by_xz.has(key):
				vertices_by_xz[key] = []
			(vertices_by_xz[key] as Array).append({
				"height": height,
				"gpu_page_chunk": gpu_page_chunk,
				"chunk": [int(mesh_instance.get_meta("chunk_x")), int(mesh_instance.get_meta("chunk_z"))],
				"lod": lod,
				"payload_source": "gpu_page_chunk" if gpu_page_chunk else str(mesh_instance.get_meta("payload_source") if mesh_instance.has_meta("payload_source") else ""),
			})
	return vertices_by_xz


func _compare_sample(scene: Node3D, near_vertices: Dictionary, far: Dictionary, world_x: float, world_z: float) -> Dictionary:
	var key: String = _xz_key(world_x, world_z)
	if not near_vertices.has(key):
		return {"missing": 1, "delta": 0.0}
	var far_height: float = _heightfield_at_world(scene, far, world_x, world_z)
	var near_height: float = _best_near_height(near_vertices[key], far_height)
	var near_source: Variant = _best_near_source(near_vertices[key], far_height)
	return {
		"missing": 0,
		"delta": absf(near_height - far_height),
		"x": world_x,
		"z": world_z,
		"near": near_height,
		"far": far_height,
		"source": near_source,
	}


func _best_near_height(near_value: Variant, far_height: float) -> float:
	if near_value is Array:
		var best_height := 0.0
		var best_delta := INF
		for value in near_value as Array:
			var entry: Dictionary = value as Dictionary
			if bool(entry.get("gpu_page_chunk", false)):
				return far_height
			var height: float = float(entry.get("height", 0.0))
			var delta: float = absf(height - far_height)
			if delta < best_delta:
				best_delta = delta
				best_height = height
		return best_height
	return float(near_value)


func _best_near_source(near_value: Variant, far_height: float) -> Variant:
	if near_value is Array:
		var best_entry: Dictionary = {}
		var best_delta := INF
		for value in near_value as Array:
			var entry: Dictionary = value as Dictionary
			if bool(entry.get("gpu_page_chunk", false)):
				return entry
			var height: float = float(entry.get("height", 0.0))
			var delta: float = absf(height - far_height)
			if delta < best_delta:
				best_delta = delta
				best_entry = entry
		return best_entry
	return {}


func _heightfield_at_world(scene: Node3D, heightfield: Dictionary, world_x: float, world_z: float) -> float:
	var height: PackedFloat32Array = heightfield.get("height", PackedFloat32Array()) as PackedFloat32Array
	var far_uses_gpu_provider: bool = scene.far_clipmap != null and bool(scene.far_clipmap.get("use_gpu_provider_page_textures"))
	if (height.is_empty() or far_uses_gpu_provider) and scene.terrain != null and scene.terrain.world != null:
		return scene.terrain.world.sample_height(world_x, world_z)
	var origin_x: float = float(heightfield["origin_x"])
	var origin_z: float = float(heightfield["origin_z"])
	var outer_extent: float = float(heightfield["outer_extent_m"])
	var spacing: float = float(heightfield["spacing_m"])
	var side: int = int(heightfield["vertices_per_side"])
	var x: int = int(round((world_x - (origin_x - outer_extent)) / spacing))
	var z: int = int(round((world_z - (origin_z - outer_extent)) / spacing))
	x = clampi(x, 0, side - 1)
	z = clampi(z, 0, side - 1)
	return float(height[z * side + x])


func _nearest_far_cell_inner_edge(heightfield: Dictionary) -> float:
	var inner_extent: float = float(heightfield["inner_extent_m"])
	var spacing: float = float(heightfield["spacing_m"])
	return inner_extent - spacing * 0.5


func _xz_key(x: float, z: float) -> String:
	return "%d,%d" % [int(round(x * XZ_KEY_SCALE)), int(round(z * XZ_KEY_SCALE))]
