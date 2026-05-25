extends SceneTree

const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainSurfaceTextureBuilderScript := preload("res://worldgen_terrain/runtime/terrain_surface_texture_builder.gd")
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

	var first_start_ms: int = Time.get_ticks_msec()
	var first: Dictionary = node.update_viewer(Vector2(12.0, 80.0))
	var first_update_ms: int = Time.get_ticks_msec() - first_start_ms
	if first.get("status", "fail") != "pass":
		errors.append("first_update_failed:%s" % str(first))
	if int(first.get("built_now", -1)) != 0:
		errors.append("first_built_sync:%d" % int(first.get("built_now", -1)))
	if int(first.get("active_native_workers", 0)) + int(first.get("queued_worker_builds", 0)) <= 0:
		errors.append("worker_not_started:%s" % str(first))

	var warmup_frames: int = _drain_until_patch(node, "0,0", errors)
	if not node.patch_nodes.has("0,0"):
		errors.append("patch_0_0_not_built")
	if not node.collision_bodies.has("0,0"):
		errors.append("collision_0_0_not_built")

	var move_start_ms: int = Time.get_ticks_msec()
	var moved: Dictionary = node.update_viewer(Vector2(300.0, 80.0))
	var move_update_ms: int = Time.get_ticks_msec() - move_start_ms
	if moved.get("status", "fail") != "pass":
		errors.append("move_update_failed:%s" % str(moved))
	if node.patch_nodes.has("0,0"):
		errors.append("old_patch_not_retired")
	if node.collision_bodies.has("0,0"):
		errors.append("old_collision_not_retired")
	var move_frames: int = _drain_until_patch(node, "1,0", errors)
	if not node.patch_nodes.has("1,0"):
		errors.append("patch_1_0_not_built")
	if not node.collision_bodies.has("1,0"):
		errors.append("collision_1_0_not_built")
	_check_surface_descriptors(node, errors)

	var stats: Dictionary = node.build_stats()
	stats["first_update_ms"] = first_update_ms
	stats["move_update_ms"] = move_update_ms
	stats["warmup_frames"] = warmup_frames
	stats["move_frames"] = move_frames
	node.queue_free()
	_report_and_quit(errors, stats)


func _drain_until_patch(node: Node3D, key: String, errors: Array[String]) -> int:
	for index in range(80):
		var report: Dictionary = node.update_viewer(_position_for_key(key))
		if report.get("status", "fail") != "pass":
			errors.append("drain_failed:%s:%s" % [key, str(report)])
			return index + 1
		if node.patch_nodes.has(key) and int(node.build_stats().get("active_native_workers", 0)) == 0:
			return index + 1
		OS.delay_msec(5)
	errors.append("worker_not_drained:%s:%s" % [key, JSON.stringify(node.build_stats())])
	return 80


func _position_for_key(key: String) -> Vector2:
	var parts: PackedStringArray = key.split(",")
	return Vector2(float(int(parts[0]) * 256 + 12), float(int(parts[1]) * 256 + 80))


func _check_surface_descriptors(node: Node3D, errors: Array[String]) -> void:
	var descriptors: Array[Dictionary] = node.active_surface_texture_descriptors()
	if descriptors.size() != 1:
		errors.append("descriptor_count:%d" % descriptors.size())
		return
	var descriptor: Dictionary = descriptors[0]
	if descriptor.get("status", "fail") != "pass":
		errors.append("descriptor_failed:%s" % str(descriptor))
		return
	if str(descriptor.get("key", "")) != "1,0":
		errors.append("descriptor_key:%s" % str(descriptor.get("key", "")))
	if int(descriptor.get("vertices_per_side", 0)) != 257:
		errors.append("descriptor_vertices:%d" % int(descriptor.get("vertices_per_side", 0)))
	if absf(float(descriptor.get("spacing_m", 0.0)) - 1.0) > 0.000001:
		errors.append("descriptor_spacing:%.6f" % float(descriptor.get("spacing_m", 0.0)))
	var height_image: Image = descriptor["height_image"] as Image
	var normal_image: Image = descriptor["normal_image"] as Image
	var slope_image: Image = descriptor["slope_deg_image"] as Image
	var curvature_image: Image = descriptor["curvature_image"] as Image
	var heatmap_image: Image = descriptor["debug_heatmap_image"] as Image
	var displacement_image: Image = descriptor["visual_displacement_image"] as Image
	if height_image.get_width() != 257 or height_image.get_height() != 257:
		errors.append("descriptor_height_image:%dx%d" % [height_image.get_width(), height_image.get_height()])
	if normal_image.get_width() != 257 or normal_image.get_height() != 257:
		errors.append("descriptor_normal_image:%dx%d" % [normal_image.get_width(), normal_image.get_height()])
	if slope_image.get_width() != 257 or slope_image.get_height() != 257:
		errors.append("descriptor_slope_image:%dx%d" % [slope_image.get_width(), slope_image.get_height()])
	if curvature_image.get_width() != 257 or curvature_image.get_height() != 257:
		errors.append("descriptor_curvature_image:%dx%d" % [curvature_image.get_width(), curvature_image.get_height()])
	if heatmap_image.get_width() != 257 or heatmap_image.get_height() != 257:
		errors.append("descriptor_heatmap_image:%dx%d" % [heatmap_image.get_width(), heatmap_image.get_height()])
	if displacement_image.get_width() != 257 or displacement_image.get_height() != 257:
		errors.append("descriptor_displacement_image:%dx%d" % [displacement_image.get_width(), displacement_image.get_height()])
	var normal_values: PackedVector3Array = descriptor["normal_values"] as PackedVector3Array
	if normal_values.size() != 257 * 257:
		errors.append("descriptor_normals:%d" % normal_values.size())
	var slope_values: PackedFloat32Array = descriptor["slope_deg_values"] as PackedFloat32Array
	var curvature_values: PackedFloat32Array = descriptor["curvature_values"] as PackedFloat32Array
	var displacement_values: PackedFloat32Array = descriptor["visual_displacement_values"] as PackedFloat32Array
	if slope_values.size() != 257 * 257:
		errors.append("descriptor_slopes:%d" % slope_values.size())
	if curvature_values.size() != 257 * 257:
		errors.append("descriptor_curvatures:%d" % curvature_values.size())
	if displacement_values.size() != 257 * 257:
		errors.append("descriptor_displacements:%d" % displacement_values.size())
	if absf(float(displacement_values[0])) > 0.000001:
		errors.append("descriptor_edge_displacement:%.6f" % float(displacement_values[0]))
	var decoded_center := TerrainSurfaceTextureBuilderScript.decode_normal_color(normal_image.get_pixel(128, 128))
	if absf(decoded_center.length() - 1.0) > 0.001:
		errors.append("descriptor_normal_length:%.6f" % decoded_center.length())


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-local-detail-worker] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-local-detail-worker] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
