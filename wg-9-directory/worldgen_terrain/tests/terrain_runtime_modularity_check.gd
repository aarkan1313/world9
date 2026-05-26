extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")
const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var world: RefCounted = _check_world_contract(errors)
	_check_world_node_contract(errors)
	if world != null:
		_check_far_clipmap_contract(world, errors)
		_check_local_detail_contract(world, errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-runtime-modularity] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-runtime-modularity] status=pass")
	quit(0)


func _check_world_contract(errors: Array[String]) -> RefCounted:
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
		return null
	if not world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 1,
		"max_lod": 2,
		"build_budget_per_frame": 9,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	}):
		errors.append("world_streamer_config:%s" % str(world.errors))
		return world
	var step: Dictionary = world.update_viewer(Vector2(1024.0, -512.0))
	if step.get("status", "fail") != "pass":
		errors.append("world_update:%s" % str(step))
	if int(step.get("active_count", 0)) != 9:
		errors.append("world_active_count:%d" % int(step.get("active_count", 0)))
	var heights: PackedFloat32Array = world.sample_height_grid(0.0, 0.0, 32.0, 5, 5)
	if heights.size() != 25:
		errors.append("world_grid_count:%d" % heights.size())
	var facts: Dictionary = world.pass_corridor_facts_for_region(0, 0)
	if facts.get("status", "fail") != "pass":
		errors.append("world_facts:%s" % str(facts))
	if not world.apply_landform_profile(TerrainLandformProfileScript.STRONG_MOUNTAINS):
		errors.append("world_landform_apply")
	var profile: Dictionary = world.landform_profile_report()
	if str(profile.get("id", "")) != TerrainLandformProfileScript.STRONG_MOUNTAINS:
		errors.append("world_landform_profile:%s" % str(profile))
	if not bool(profile.get("native_prepared_grid_enabled", false)):
		errors.append("world_landform_native_disabled")
	return world


func _check_world_node_contract(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	get_root().add_child(node)
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.debug_mode = TerrainWorldScript.DEBUG_ELEVATION_COLOR
	node.use_fast_gray_material = true
	node.use_native_chunk_payloads = true
	node.use_native_chunk_workers = false
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("node_setup:%s" % str(node.errors))
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 1,
		"max_lod": 2,
		"build_budget_per_frame": 9,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	var report: Dictionary = node.update_viewer(Vector2.ZERO)
	if report.get("status", "fail") != "pass":
		errors.append("node_update:%s" % str(report))
	if node.built_chunk_count() != 9:
		errors.append("node_built_count:%d" % node.built_chunk_count())
	for child in node.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			errors.append("node_non_mesh_child:%s" % child.name)
			continue
		if mesh_instance.mesh == null:
			errors.append("node_missing_mesh:%s" % child.name)
	if not node.apply_landform_profile(TerrainLandformProfileScript.COMPRESSED_SCALE, false):
		errors.append("node_profile_apply")
	var stats: Dictionary = node.build_stats()
	if int(stats.get("active_chunks", 0)) != node.built_chunk_count():
		errors.append("node_stats_active:%s" % str(stats))
	node.queue_free()


func _check_far_clipmap_contract(world: RefCounted, errors: Array[String]) -> void:
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	get_root().add_child(clipmap)
	clipmap.level_count = 2
	clipmap.vertices_per_side = 33
	clipmap.base_spacing_m = 64.0
	clipmap.base_outer_extent_m = 1024.0
	clipmap.near_hole_extent_m = 512.0
	clipmap.max_rebuild_levels_per_update = 2
	clipmap.use_native_workers = false
	clipmap.use_persistent_page_mesh = true
	clipmap.page_cache_max_pages = 8
	if not clipmap.setup(world):
		errors.append("clipmap_setup")
		clipmap.queue_free()
		return
	var report: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	if report.get("status", "fail") != "pass":
		errors.append("clipmap_update:%s" % str(report))
	if int(report.get("levels", 0)) != 2:
		errors.append("clipmap_levels:%d" % int(report.get("levels", 0)))
	if int(report.get("vertices", 0)) != 2 * 33 * 33:
		errors.append("clipmap_vertices:%d" % int(report.get("vertices", 0)))
	var stats: Dictionary = clipmap.stats()
	if (stats.get("page_cache", {}) as Dictionary).is_empty():
		errors.append("clipmap_page_cache_missing:%s" % str(stats))
	clipmap.queue_free()


func _check_local_detail_contract(world: RefCounted, errors: Array[String]) -> void:
	var detail: Node3D = TerrainLocalDetailNodeScript.new()
	get_root().add_child(detail)
	detail.enabled = true
	detail.patch_size_m = 64.0
	detail.vertices_per_side = 33
	detail.radius_patches = 0
	detail.max_active_patches = 1
	detail.use_native_payloads = false
	detail.use_native_workers = false
	detail.use_surface_texture_material = false
	detail.use_visual_displacement = false
	detail.enable_collision_bodies = false
	if not detail.setup(world):
		errors.append("detail_setup:%s" % str(detail.errors))
		detail.queue_free()
		return
	var report: Dictionary = detail.update_viewer(Vector2.ZERO)
	if report.get("status", "fail") != "pass":
		errors.append("detail_update:%s" % str(report))
	if int(report.get("active_count", 0)) != 1:
		errors.append("detail_active_count:%d" % int(report.get("active_count", 0)))
	var stats: Dictionary = detail.build_stats()
	if int(stats.get("active_patches", 0)) != 1:
		errors.append("detail_stats:%s" % str(stats))
	detail.queue_free()
