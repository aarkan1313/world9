class_name TerrainFarClipmapNode
extends Node3D

const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainSurfaceTextureBuilderScript := preload("res://worldgen_terrain/runtime/terrain_surface_texture_builder.gd")
const TerrainFarClipmapPayloadWorkerScript := preload("res://worldgen_terrain/mesh/terrain_far_clipmap_payload_worker.gd")
const TerrainPageRequestScript := preload("res://worldgen_terrain/core/terrain_page_request.gd")
const TerrainPageCacheScript := preload("res://worldgen_terrain/core/terrain_page_cache.gd")
const TerrainGpuPageResidencyScript := preload("res://worldgen_terrain/core/terrain_gpu_page_residency.gd")

@export var level_count: int = 3
@export var vertices_per_side: int = 129
@export var base_spacing_m: float = 64.0
@export var base_outer_extent_m: float = 4096.0
@export var near_hole_extent_m: float = 2048.0
@export var level0_full_underlay_enabled: bool = false
@export var debug_level_colors: bool = false
@export var use_surface_texture_material: bool = false
@export var use_elevation_color_material: bool = false
@export var visual_y_bias_per_level_m: float = -0.08
@export_range(0.0, 3.0, 0.05) var transition_fade_seconds: float = 0.45
@export_range(1, 16, 1) var max_rebuild_levels_per_update: int = 16
@export var use_native_workers: bool = false
@export var use_persistent_page_mesh: bool = false
@export_range(0, 256, 1) var page_cache_max_pages: int = 48
@export_range(0, 256, 1) var gpu_page_residency_max_pages: int = 48
@export_range(0.0, 4.0, 0.05) var surface_texture_normal_strength: float = 1.0
@export_range(0, 16, 1) var geometric_transition_band_cells: int = 4
@export var use_edge_fog: bool = false
@export var edge_fog_begin_m: float = 24000.0
@export var edge_fog_end_m: float = 33000.0
@export var edge_fog_color: Color = Color(0.18, 0.18, 0.18)

var world: RefCounted
var level_nodes: Array[MeshInstance3D] = []
var level_origins: Array[Vector2] = []
var level_build_counts: Array[int] = []
var level_vertex_counts: Array[int] = []
var level_index_counts: Array[int] = []
var level_heightfields: Array[Dictionary] = []
var level_surface_descriptors: Array[Dictionary] = []
var level_material_descriptors: Array[Dictionary] = []
var level_transition_nodes: Array = []
var level_transition_start_ms: Array[int] = []
var level_page_blend_start_ms: Array[int] = []
var last_build_ms: int = 0
var last_surface_texture_ms: int = 0
var total_vertex_count: int = 0
var total_index_count: int = 0
var pending_rebuild_count: int = 0
var active_transition_count: int = 0
var active_page_blend_count: int = 0
var last_rebuilt_levels: Array[int] = []
var last_scheduled_levels: Array[int] = []
var last_deferred_levels: Array[int] = []
var active_worker_count: int = 0
var last_worker_elapsed_ms: int = 0
var last_worker_error: String = ""
var last_page_error: String = ""
var last_surface_material_reused: bool = false
var last_page_material_reused: bool = false
var last_page_descriptor_image_builds: int = 0
var last_page_descriptor_texture_hits: int = 0
var edge_fog_center_xz := Vector2.ZERO
var _pending_origin := Vector2(INF, INF)
var _native_backend: Object
var _native_workers: Dictionary = {}
var _native_worker_requests: Dictionary = {}
var _staged_native_payloads: Dictionary = {}
var _staged_native_origin := Vector2(INF, INF)
var _gray_shader_opaque: Shader
var _gray_shader_fade: Shader
var _surface_texture_shader_opaque: Shader
var _surface_texture_shader_fade: Shader
var _page_height_shader: Shader
var _page_cache: RefCounted
var _gpu_page_residency: RefCounted


func setup(p_world: RefCounted) -> bool:
	clear_levels()
	world = p_world
	if world == null:
		return false
	for level in range(level_count):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "far_clipmap_level_%d" % level
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = _material_for_level(level)
		add_child(mesh_instance)
		level_nodes.append(mesh_instance)
		level_origins.append(Vector2(INF, INF))
		level_build_counts.append(0)
		level_vertex_counts.append(0)
		level_index_counts.append(0)
		level_heightfields.append({})
		level_surface_descriptors.append({})
		level_material_descriptors.append({})
		level_transition_nodes.append(null)
		level_transition_start_ms.append(0)
		level_page_blend_start_ms.append(0)
	_ensure_page_cache()
	_ensure_gpu_page_residency()
	return true


func clear_levels() -> void:
	_clear_native_workers()
	for child in get_children():
		child.queue_free()
	level_nodes.clear()
	level_origins.clear()
	level_build_counts.clear()
	level_vertex_counts.clear()
	level_index_counts.clear()
	level_heightfields.clear()
	level_surface_descriptors.clear()
	level_material_descriptors.clear()
	level_transition_nodes.clear()
	level_transition_start_ms.clear()
	level_page_blend_start_ms.clear()
	last_build_ms = 0
	last_surface_texture_ms = 0
	total_vertex_count = 0
	total_index_count = 0
	pending_rebuild_count = 0
	active_transition_count = 0
	active_page_blend_count = 0
	last_rebuilt_levels.clear()
	last_scheduled_levels.clear()
	last_deferred_levels.clear()
	active_worker_count = 0
	last_worker_elapsed_ms = 0
	last_worker_error = ""
	last_page_error = ""
	last_surface_material_reused = false
	last_page_material_reused = false
	last_page_descriptor_image_builds = 0
	last_page_descriptor_texture_hits = 0
	_pending_origin = Vector2(INF, INF)
	_staged_native_payloads.clear()
	_staged_native_origin = Vector2(INF, INF)
	if _page_cache != null:
		_page_cache.clear()
	if _gpu_page_residency != null:
		_gpu_page_residency.clear()


func configure_geometry(p_level_count: int, p_base_spacing_m: float, p_base_outer_extent_m: float) -> bool:
	var next_level_count: int = max(1, p_level_count)
	var next_base_spacing_m: float = max(0.000001, p_base_spacing_m)
	var next_base_outer_extent_m: float = max(next_base_spacing_m, p_base_outer_extent_m)
	var changed := (
		next_level_count != level_count
		or not is_equal_approx(next_base_spacing_m, base_spacing_m)
		or not is_equal_approx(next_base_outer_extent_m, base_outer_extent_m)
	)
	var node_count_mismatch := world != null and level_nodes.size() != next_level_count
	level_count = next_level_count
	base_spacing_m = next_base_spacing_m
	base_outer_extent_m = next_base_outer_extent_m
	if world != null and (changed or node_count_mismatch):
		var current_world: RefCounted = world
		return setup(current_world)
	return true


func set_debug_level_colors(enabled: bool) -> void:
	debug_level_colors = enabled
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level]
		mesh_instance.material_override = _material_for_level(level)


func set_elevation_color_material(enabled: bool) -> void:
	use_elevation_color_material = enabled
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level]
		mesh_instance.material_override = _material_for_level(level)


func apply_surface_material_settings(enabled: bool, normal_strength: float, refresh_existing: bool = true) -> void:
	use_surface_texture_material = enabled
	surface_texture_normal_strength = max(0.0, normal_strength)
	if not refresh_existing:
		return
	var texture_start_ms: int = Time.get_ticks_msec()
	var reused_count := 0
	for level in range(level_nodes.size()):
		var heightfield: Dictionary = level_heightfields[level] as Dictionary
		if use_surface_texture_material and not heightfield.is_empty():
			var descriptor: Dictionary = level_material_descriptors[level] as Dictionary
			if descriptor.get("status", "fail") != "pass":
				level_material_descriptors[level] = _material_descriptor_from_heightfield(heightfield)
		var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
		if use_surface_texture_material and _refresh_surface_material_parameters(mesh_instance, level):
			reused_count += 1
		else:
			mesh_instance.material_override = _material_for_level(level)
	last_surface_texture_ms = Time.get_ticks_msec() - texture_start_ms
	last_surface_material_reused = use_surface_texture_material and reused_count == level_nodes.size() and reused_count > 0


func apply_edge_fog(enabled: bool, begin_m: float, end_m: float, color: Color, refresh_existing: bool = true) -> void:
	use_edge_fog = enabled
	edge_fog_begin_m = max(0.0, begin_m)
	edge_fog_end_m = max(edge_fog_begin_m + 1.0, end_m)
	edge_fog_color = color
	if not refresh_existing:
		return
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
		if mesh_instance == null:
			continue
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if material == null:
			mesh_instance.material_override = _material_for_level(level)
		else:
			_apply_level_edge_fog_shader_parameters(level, material)


func set_edge_fog_center_xz(center_xz: Vector2) -> void:
	edge_fog_center_xz = center_xz
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
		if mesh_instance == null:
			continue
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if material != null:
			_apply_level_edge_fog_shader_parameters(level, material)


func update_viewer(viewer_xz: Vector2) -> Dictionary:
	if world == null:
		return {"status": "fail", "error": "world_not_setup"}
	TerrainFarClipmapPayloadWorkerScript.cleanup_detached_workers()
	var start_ms: int = Time.get_ticks_msec()
	total_vertex_count = 0
	total_index_count = 0
	last_rebuilt_levels.clear()
	last_scheduled_levels.clear()
	last_deferred_levels.clear()
	last_page_descriptor_image_builds = 0
	last_page_descriptor_texture_hits = 0
	var shared_origin := _shared_origin(viewer_xz)
	if shared_origin != _pending_origin:
		_pending_origin = shared_origin
		_clear_staged_payloads_for_other_origin(_pending_origin)
	_poll_native_workers()
	_commit_staged_payloads_if_ready()
	_update_transition_fades()
	_update_page_blends()
	var rebuild_budget: int = max(1, max_rebuild_levels_per_update)
	var rebuilt_count := 0
	for level in range(level_nodes.size()):
		if _pending_origin != level_origins[level] and rebuilt_count < rebuild_budget:
			if _staged_payload_matches_pending(level):
				last_deferred_levels.append(level)
				rebuilt_count += 1
				continue
			if use_persistent_page_mesh and _page_cache_has_level(level, _pending_origin):
				_rebuild_level(level, _pending_origin)
				last_rebuilt_levels.append(level)
				rebuilt_count += 1
				continue
			if _can_use_native_workers():
				var schedule_status: String = _schedule_native_worker(level, _pending_origin)
				if schedule_status == "scheduled":
					last_scheduled_levels.append(level)
				elif schedule_status == "inflight":
					last_deferred_levels.append(level)
				else:
					_rebuild_level(level, _pending_origin)
					last_rebuilt_levels.append(level)
			else:
				_rebuild_level(level, _pending_origin)
				last_rebuilt_levels.append(level)
			rebuilt_count += 1
	total_vertex_count = _sum_int_array(level_vertex_counts)
	total_index_count = _sum_int_array(level_index_counts)
	pending_rebuild_count = _count_pending_rebuilds()
	active_worker_count = _native_workers.size()
	last_build_ms = Time.get_ticks_msec() - start_ms
	return {
		"status": "pass",
		"levels": level_nodes.size(),
		"vertices": total_vertex_count,
		"indices": total_index_count,
		"last_build_ms": last_build_ms,
		"last_surface_texture_ms": last_surface_texture_ms,
		"use_surface_texture_material": use_surface_texture_material,
		"use_elevation_color_material": use_elevation_color_material,
		"build_counts": level_build_counts.duplicate(),
		"pending_rebuild_count": pending_rebuild_count,
		"active_transition_count": active_transition_count,
		"active_page_blend_count": active_page_blend_count,
		"staged_native_payload_count": _staged_native_payloads.size(),
		"use_persistent_page_mesh": use_persistent_page_mesh,
		"page_cache": _page_cache.debug_state() if _page_cache != null else {},
		"gpu_page_residency": _gpu_page_residency.debug_state() if _gpu_page_residency != null else {},
		"last_rebuilt_levels": last_rebuilt_levels.duplicate(),
		"last_scheduled_levels": last_scheduled_levels.duplicate(),
		"last_deferred_levels": last_deferred_levels.duplicate(),
		"active_worker_count": active_worker_count,
		"last_worker_elapsed_ms": last_worker_elapsed_ms,
		"last_worker_error": last_worker_error,
		"last_page_error": last_page_error,
		"last_surface_material_reused": last_surface_material_reused,
		"last_page_material_reused": last_page_material_reused,
		"last_page_descriptor_image_builds": last_page_descriptor_image_builds,
		"last_page_descriptor_texture_hits": last_page_descriptor_texture_hits,
	}


func stats() -> Dictionary:
	return {
		"levels": level_nodes.size(),
		"vertices": total_vertex_count,
		"indices": total_index_count,
		"last_build_ms": last_build_ms,
		"last_surface_texture_ms": last_surface_texture_ms,
		"use_surface_texture_material": use_surface_texture_material,
		"build_counts": level_build_counts.duplicate(),
		"pending_rebuild_count": pending_rebuild_count,
		"active_transition_count": active_transition_count,
		"active_page_blend_count": active_page_blend_count,
		"staged_native_payload_count": _staged_native_payloads.size(),
		"use_persistent_page_mesh": use_persistent_page_mesh,
		"page_cache": _page_cache.debug_state() if _page_cache != null else {},
		"gpu_page_residency": _gpu_page_residency.debug_state() if _gpu_page_residency != null else {},
		"last_rebuilt_levels": last_rebuilt_levels.duplicate(),
		"last_scheduled_levels": last_scheduled_levels.duplicate(),
		"last_deferred_levels": last_deferred_levels.duplicate(),
		"active_worker_count": active_worker_count,
		"last_worker_elapsed_ms": last_worker_elapsed_ms,
		"last_worker_error": last_worker_error,
		"last_page_error": last_page_error,
		"last_surface_material_reused": last_surface_material_reused,
		"last_page_material_reused": last_page_material_reused,
		"last_page_descriptor_image_builds": last_page_descriptor_image_builds,
		"last_page_descriptor_texture_hits": last_page_descriptor_texture_hits,
	}


func has_pending_rebuilds() -> bool:
	return pending_rebuild_count > 0 or active_transition_count > 0 or active_page_blend_count > 0 or not _native_workers.is_empty() or not _staged_native_payloads.is_empty()


func _set_level_geometry_counts(level: int, vertex_count: int, index_count: int) -> void:
	if level < 0:
		return
	while level_vertex_counts.size() <= level:
		level_vertex_counts.append(0)
	while level_index_counts.size() <= level:
		level_index_counts.append(0)
	level_vertex_counts[level] = max(0, vertex_count)
	level_index_counts[level] = max(0, index_count)


func _sum_int_array(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func budget_report() -> Dictionary:
	var levels: Array[Dictionary] = []
	var total_vertices := 0
	var total_indices := 0
	var total_triangles := 0
	var total_mesh_bytes := 0
	var total_height_bytes := 0
	for level in range(max(0, level_count)):
		var spacing: float = _level_spacing(level)
		var outer_extent: float = _level_outer_extent(level)
		var inner_extent: float = _inner_extent_for_level(level)
		var side: int = _side_for_extent(outer_extent, spacing)
		var vertex_count: int = side * side
		var index_count: int = _clipmap_index_count(side, spacing, outer_extent, inner_extent)
		var triangle_count: int = int(index_count / 3)
		var mesh_bytes: int = vertex_count * 32 + index_count * 4
		var height_bytes: int = vertex_count * 4
		levels.append({
			"level": level,
			"vertices_per_side": side,
			"spacing_m": spacing,
			"outer_extent_m": outer_extent,
			"diameter_m": outer_extent * 2.0,
			"inner_extent_m": inner_extent,
			"vertex_count": vertex_count,
			"triangle_count": triangle_count,
			"index_count": index_count,
			"mesh_mib": _mib(mesh_bytes),
			"cpu_height_mib": _mib(height_bytes),
		})
		total_vertices += vertex_count
		total_indices += index_count
		total_triangles += triangle_count
		total_mesh_bytes += mesh_bytes
		total_height_bytes += height_bytes
	return {
		"level_count": max(0, level_count),
		"base_spacing_m": base_spacing_m,
		"base_outer_extent_m": base_outer_extent_m,
		"near_hole_extent_m": near_hole_extent_m,
		"level0_full_underlay_enabled": level0_full_underlay_enabled,
		"levels": levels,
		"totals": {
			"vertex_count": total_vertices,
			"triangle_count": total_triangles,
			"index_count": total_indices,
			"mesh_mib": _mib(total_mesh_bytes),
			"cpu_height_mib": _mib(total_height_bytes),
			"mesh_plus_height_mib": _mib(total_mesh_bytes + total_height_bytes),
		},
	}


func active_surface_texture_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for level in range(level_heightfields.size()):
		var descriptor: Dictionary = level_surface_descriptors[level] as Dictionary
		if descriptor.is_empty():
			var heightfield: Dictionary = level_heightfields[level] as Dictionary
			if not heightfield.is_empty():
				descriptor = _surface_descriptor_from_heightfield(heightfield)
				level_surface_descriptors[level] = descriptor
		if descriptor.is_empty():
			continue
		descriptors.append(descriptor.duplicate())
	return descriptors


func _rebuild_level_page(level: int, origin: Vector2, use_transition: bool = true) -> void:
	var spacing: float = _level_spacing(level)
	var outer_extent: float = _level_outer_extent(level)
	var inner_extent: float = _inner_extent_for_level(level)
	var side: int = _side_for_extent(outer_extent, spacing)
	var result = _height_page_result_for_level(level, origin, outer_extent, spacing, side)
	if typeof(result) != TYPE_DICTIONARY or str(result.get("status", "fail")) != "pass":
		last_page_error = "level_%d:page_result_failed:%s" % [level, str(result.get("error", "null") if typeof(result) == TYPE_DICTIONARY else "null")]
		last_worker_error = last_page_error
		return
	last_page_error = ""
	var height: PackedFloat32Array = result["height_samples"] as PackedFloat32Array
	var previous_heightfield: Dictionary = level_heightfields[level] as Dictionary
	var normals := PackedVector3Array()
	normals.resize(side * side)
	for z in range(side):
		for x in range(side):
			normals[z * side + x] = _normal_at(height, side, x, z, spacing)
	var heightfield: Dictionary = _heightfield_for_level(level, origin, outer_extent, spacing, side, height, normals)
	level_heightfields[level] = heightfield
	level_surface_descriptors[level] = {}
	var descriptor: Dictionary = _page_material_descriptor_from_heightfield(heightfield)
	level_material_descriptors[level] = descriptor
	var mesh_instance: MeshInstance3D = level_nodes[level]
	_ensure_persistent_page_mesh(level, side, spacing, outer_extent, inner_extent)
	var previous_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	var previous_height_texture: Texture2D = null
	var previous_normal_texture: Texture2D = null
	var previous_page_origin := origin
	var previous_page_extent := outer_extent
	if use_transition and previous_material != null:
		previous_height_texture = previous_material.get_shader_parameter("height_texture") as Texture2D
		previous_normal_texture = previous_material.get_shader_parameter("normal_texture") as Texture2D
		previous_page_origin = _shader_vec2_param(previous_material, "page_origin_m", origin)
		previous_page_extent = _shader_float_param(previous_material, "page_extent_m", outer_extent)
	mesh_instance.material_override = _page_height_material_for_descriptor(
		descriptor,
		level,
		previous_height_texture,
		previous_normal_texture,
		0.0 if previous_height_texture != null and transition_fade_seconds > 0.0 else 1.0,
		previous_page_origin,
		previous_page_extent,
		previous_material
	)
	mesh_instance.position = Vector3(origin.x, visual_y_bias_per_level_m * float(level + 1), origin.y)
	_apply_persistent_page_custom_aabb(level, heightfield, previous_heightfield)
	level_origins[level] = origin
	level_build_counts[level] = int(level_build_counts[level]) + 1
	_set_level_geometry_counts(level, side * side, _clipmap_index_count(side, spacing, outer_extent, inner_extent))
	_start_page_blend(level, previous_height_texture != null and use_transition)
	_refresh_page_morph_sources()
	_protect_active_page_keys()


func _assign_level_page_payload(payload: Dictionary, use_transition: bool = true) -> void:
	var level: int = int(payload.get("level", -1))
	if level < 0 or level >= level_nodes.size():
		return
	var origin := Vector2(float(payload["origin_x"]), float(payload["origin_z"]))
	var side: int = int(payload["side"])
	var outer_extent: float = float(payload["outer_extent_m"])
	var spacing: float = float(payload["spacing_m"])
	var height: PackedFloat32Array = payload["height"] as PackedFloat32Array
	_cache_page_payload(level, origin, outer_extent, spacing, side, height)
	var previous_heightfield: Dictionary = level_heightfields[level] as Dictionary
	var normals := PackedVector3Array()
	normals.resize(side * side)
	for z in range(side):
		for x in range(side):
			normals[z * side + x] = _normal_at(height, side, x, z, spacing)
	var heightfield: Dictionary = _heightfield_for_level(level, origin, outer_extent, spacing, side, height, normals)
	level_heightfields[level] = heightfield
	level_surface_descriptors[level] = {}
	var descriptor: Dictionary = _page_material_descriptor_from_heightfield(heightfield)
	level_material_descriptors[level] = descriptor
	var mesh_instance: MeshInstance3D = level_nodes[level]
	var previous_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	var previous_height_texture: Texture2D = null
	var previous_normal_texture: Texture2D = null
	var previous_page_origin := origin
	var previous_page_extent := outer_extent
	if use_transition and previous_material != null:
		previous_height_texture = previous_material.get_shader_parameter("height_texture") as Texture2D
		previous_normal_texture = previous_material.get_shader_parameter("normal_texture") as Texture2D
		previous_page_origin = _shader_vec2_param(previous_material, "page_origin_m", origin)
		previous_page_extent = _shader_float_param(previous_material, "page_extent_m", outer_extent)
	_ensure_persistent_page_mesh(level, side, spacing, outer_extent, float(payload["inner_extent_m"]))
	mesh_instance.material_override = _page_height_material_for_descriptor(
		descriptor,
		level,
		previous_height_texture,
		previous_normal_texture,
		0.0 if previous_height_texture != null and transition_fade_seconds > 0.0 else 1.0,
		previous_page_origin,
		previous_page_extent,
		previous_material
	)
	mesh_instance.position = Vector3(origin.x, visual_y_bias_per_level_m * float(level + 1), origin.y)
	_apply_persistent_page_custom_aabb(level, heightfield, previous_heightfield)
	level_origins[level] = origin
	level_build_counts[level] = int(level_build_counts[level]) + 1
	_set_level_geometry_counts(level, side * side, (payload["indices"] as PackedInt32Array).size())
	_start_page_blend(level, previous_height_texture != null and use_transition)
	_refresh_page_morph_sources()
	_protect_active_page_keys()
	last_rebuilt_levels.append(level)


func _height_page_result_for_level(level: int, origin: Vector2, outer_extent: float, spacing: float, side: int):
	_ensure_page_cache()
	var request = _make_far_clipmap_page_request(level, origin, outer_extent, spacing, side)
	var validation: String = request.validate()
	if not validation.is_empty():
		return _failed_page_dictionary(request, validation)
	var cached = _page_cache.get_page(request.cache_key())
	if cached != null:
		return cached
	var start_ms: int = Time.get_ticks_msec()
	var height_samples: PackedFloat32Array = _sample_height_grid_split_by_region(origin, outer_extent, spacing, side)
	var result := {
		"status": "pass",
		"error": "",
		"request_key": request.deterministic_key(),
		"cache_key": request.cache_key(),
		"version_stamp": request.version_stamp(),
		"origin_xz": request.origin_xz,
		"count_x": request.count_x,
		"count_z": request.count_z,
		"step_m": request.step_m,
		"world_seed": request.world_seed,
		"purpose": request.purpose,
		"quality_profile": request.quality_profile,
		"provider_revision": request.provider_revision,
		"runtime_pack_hash": request.runtime_pack_hash,
		"height_samples": height_samples,
		"timings_ms": {"sample_height_ms": Time.get_ticks_msec() - start_ms},
		"metadata": request.metadata.duplicate(true),
	}
	var shape_error: String = _validate_page_dictionary_shape(result)
	if not shape_error.is_empty():
		result["status"] = "fail"
		result["error"] = shape_error
		return result
	_page_cache.put_page(result)
	return result


func _page_cache_has_level(level: int, origin: Vector2) -> bool:
	_ensure_page_cache()
	var spacing: float = _level_spacing(level)
	var outer_extent: float = _level_outer_extent(level)
	var side: int = _side_for_extent(outer_extent, spacing)
	var request = _make_far_clipmap_page_request(level, origin, outer_extent, spacing, side)
	if not request.validate().is_empty():
		return false
	return _page_cache.has_page(request.cache_key())


func _cache_page_payload(level: int, origin: Vector2, outer_extent: float, spacing: float, side: int, height: PackedFloat32Array) -> void:
	if not use_persistent_page_mesh:
		return
	_ensure_page_cache()
	var request = _make_far_clipmap_page_request(level, origin, outer_extent, spacing, side)
	var validation: String = request.validate()
	if not validation.is_empty():
		last_page_error = "level_%d:cache_request:%s" % [level, validation]
		return
	var result := {
		"status": "pass",
		"error": "",
		"request_key": request.deterministic_key(),
		"cache_key": request.cache_key(),
		"version_stamp": request.version_stamp(),
		"origin_xz": request.origin_xz,
		"count_x": request.count_x,
		"count_z": request.count_z,
		"step_m": request.step_m,
		"world_seed": request.world_seed,
		"purpose": request.purpose,
		"quality_profile": request.quality_profile,
		"provider_revision": request.provider_revision,
		"runtime_pack_hash": request.runtime_pack_hash,
		"height_samples": PackedFloat32Array(height),
		"timings_ms": {"source": "native_worker"},
		"metadata": request.metadata.duplicate(true),
	}
	var shape_error: String = _validate_page_dictionary_shape(result)
	if not shape_error.is_empty():
		last_page_error = "level_%d:cache_payload:%s" % [level, shape_error]
		return
	_page_cache.put_page(result)


func _failed_page_dictionary(request, error: String) -> Dictionary:
	return {
		"status": "fail",
		"error": error,
		"request_key": request.deterministic_key(),
		"cache_key": request.cache_key(),
		"version_stamp": request.version_stamp(),
		"origin_xz": request.origin_xz,
		"count_x": request.count_x,
		"count_z": request.count_z,
		"step_m": request.step_m,
		"world_seed": request.world_seed,
		"purpose": request.purpose,
		"quality_profile": request.quality_profile,
		"provider_revision": request.provider_revision,
		"runtime_pack_hash": request.runtime_pack_hash,
		"height_samples": PackedFloat32Array(),
		"timings_ms": {},
		"metadata": request.metadata.duplicate(true),
	}


func _validate_page_dictionary_shape(result: Dictionary) -> String:
	var count_x: int = int(result.get("count_x", 0))
	var count_z: int = int(result.get("count_z", 0))
	var expected: int = max(0, count_x) * max(0, count_z)
	if expected <= 0:
		return "expected_sample_count:%d" % expected
	var height_samples: PackedFloat32Array = result.get("height_samples", PackedFloat32Array()) as PackedFloat32Array
	if height_samples.size() != expected:
		return "height_samples:%d expected:%d" % [height_samples.size(), expected]
	return ""


func _ensure_page_cache() -> void:
	if _page_cache == null:
		_page_cache = TerrainPageCacheScript.new()
	_page_cache.configure(page_cache_max_pages)


func _ensure_gpu_page_residency() -> void:
	if _gpu_page_residency == null:
		_gpu_page_residency = TerrainGpuPageResidencyScript.new()
	_gpu_page_residency.configure(gpu_page_residency_max_pages)


func _protect_active_page_keys() -> void:
	if _page_cache == null:
		return
	var protected: Array[String] = []
	for descriptor_value in level_heightfields:
		var heightfield: Dictionary = descriptor_value as Dictionary
		if heightfield.is_empty():
			continue
		var level: int = int(heightfield.get("level", -1))
		var outer_extent: float = float(heightfield.get("outer_extent_m", 0.0))
		var spacing: float = float(heightfield.get("spacing_m", 0.0))
		var side: int = int(heightfield.get("vertices_per_side", 0))
		var origin := Vector2(float(heightfield.get("origin_x", 0.0)), float(heightfield.get("origin_z", 0.0)))
		var request = _make_far_clipmap_page_request(level, origin, outer_extent, spacing, side)
		protected.append(request.cache_key())
	_page_cache.set_protected_keys(protected)
	if _gpu_page_residency != null:
		_gpu_page_residency.set_protected_keys(protected)


func _make_far_clipmap_page_request(level: int, origin: Vector2, outer_extent: float, spacing: float, side: int):
	var request = TerrainPageRequestScript.new()
	request.origin_xz = Vector2(origin.x - outer_extent, origin.y - outer_extent)
	request.count_x = side
	request.count_z = side
	request.step_m = spacing
	request.world_seed = world.seed
	request.purpose = "far_clipmap_height"
	request.quality_profile = "level_%d" % level
	request.feature_flags = {
		"level": level,
		"outer_extent_m": outer_extent,
		"inner_extent_m": _inner_extent_for_level(level),
		"persistent_page_mesh": use_persistent_page_mesh,
	}
	request.metadata = {
		"clipmap_origin_x": origin.x,
		"clipmap_origin_z": origin.y,
	}
	return request


func _rebuild_level(level: int, origin: Vector2, use_transition: bool = true) -> void:
	if use_persistent_page_mesh:
		_rebuild_level_page(level, origin, use_transition)
		return
	var spacing: float = _level_spacing(level)
	var outer_extent: float = _level_outer_extent(level)
	var inner_extent: float = _inner_extent_for_level(level)
	var side: int = _side_for_extent(outer_extent, spacing)
	var height: PackedFloat32Array = _sample_height_grid_split_by_region(origin, outer_extent, spacing, side)
	height = _morph_outer_transition_band(level, origin, outer_extent, spacing, side, height)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var native_mesh: Dictionary = _native_clipmap_mesh_payload_from_height(height, side, spacing, outer_extent, inner_extent)
	if native_mesh.get("status", "fail") == "pass":
		vertices = native_mesh["vertices"] as PackedVector3Array
		normals = native_mesh["normals"] as PackedVector3Array
		uvs = native_mesh["uvs"] as PackedVector2Array
		indices = native_mesh["indices"] as PackedInt32Array
	else:
		vertices.resize(side * side)
		normals.resize(side * side)
		uvs.resize(side * side)
		var denom: float = float(side - 1)
		for z in range(side):
			var local_z: float = -outer_extent + float(z) * spacing
			for x in range(side):
				var local_x: float = -outer_extent + float(x) * spacing
				var index: int = z * side + x
				vertices[index] = Vector3(local_x, float(height[index]), local_z)
				normals[index] = _normal_at(height, side, x, z, spacing)
				uvs[index] = Vector2(float(x) / denom, float(z) / denom)
		indices = _clipmap_indices(side, spacing, outer_extent, inner_extent)
	level_heightfields[level] = _heightfield_for_level(level, origin, outer_extent, spacing, side, height, normals)
	level_surface_descriptors[level] = {}
	if use_surface_texture_material:
		level_material_descriptors[level] = _material_descriptor_from_heightfield(level_heightfields[level] as Dictionary)
	else:
		level_material_descriptors[level] = {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance: MeshInstance3D = level_nodes[level]
	if use_transition:
		_begin_level_transition(level)
	else:
		_remove_transition_node(level)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_level(level)
	mesh_instance.position = Vector3(origin.x, visual_y_bias_per_level_m * float(level + 1), origin.y)
	mesh_instance.custom_aabb = AABB()
	if use_transition:
		_start_level_fade(level)
	else:
		_set_material_alpha(mesh_instance.material_override, 1.0)
	level_origins[level] = origin
	level_build_counts[level] = int(level_build_counts[level]) + 1
	_set_level_geometry_counts(level, vertices.size(), indices.size())
	_apply_level_edge_fog_shader_parameters(level, mesh_instance.material_override as ShaderMaterial)


func _assign_level_payload(payload: Dictionary, use_transition: bool = true) -> void:
	if payload.get("status", "fail") != "pass":
		return
	if use_persistent_page_mesh:
		_assign_level_page_payload(payload, use_transition)
		return
	var level: int = int(payload["level"])
	if level < 0 or level >= level_nodes.size():
		return
	var origin := Vector2(float(payload["origin_x"]), float(payload["origin_z"]))
	var side: int = int(payload["side"])
	var outer_extent: float = float(payload["outer_extent_m"])
	var spacing: float = float(payload["spacing_m"])
	var height: PackedFloat32Array = payload["height"] as PackedFloat32Array
	height = _morph_outer_transition_band(level, origin, outer_extent, spacing, side, height)
	var normals := PackedVector3Array()
	normals.resize(side * side)
	for z in range(side):
		for x in range(side):
			normals[z * side + x] = _normal_at(height, side, x, z, spacing)
	level_heightfields[level] = _heightfield_for_level(level, origin, outer_extent, spacing, side, height, normals)
	level_surface_descriptors[level] = {}
	if use_surface_texture_material:
		level_material_descriptors[level] = _material_descriptor_from_heightfield(level_heightfields[level] as Dictionary)
	else:
		level_material_descriptors[level] = {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _centered_vertices_from_height(height, side, spacing, outer_extent)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = payload["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = payload["indices"] as PackedInt32Array
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance: MeshInstance3D = level_nodes[level]
	if use_transition:
		_begin_level_transition(level)
	else:
		_remove_transition_node(level)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_level(level)
	mesh_instance.position = Vector3(origin.x, visual_y_bias_per_level_m * float(level + 1), origin.y)
	mesh_instance.custom_aabb = AABB()
	if use_transition:
		_start_level_fade(level)
	else:
		_set_material_alpha(mesh_instance.material_override, 1.0)
	level_origins[level] = origin
	level_build_counts[level] = int(level_build_counts[level]) + 1
	_set_level_geometry_counts(level, side * side, (payload["indices"] as PackedInt32Array).size())
	_apply_level_edge_fog_shader_parameters(level, mesh_instance.material_override as ShaderMaterial)
	last_rebuilt_levels.append(level)


func _begin_level_transition(level: int) -> void:
	if level < 0 or level >= level_nodes.size():
		return
	_remove_transition_node(level)
	var fade_ms: int = int(max(0.0, transition_fade_seconds) * 1000.0)
	if fade_ms <= 0:
		return
	var current: MeshInstance3D = level_nodes[level] as MeshInstance3D
	var current_mesh: Mesh = current.mesh
	if current_mesh == null or current_mesh.get_surface_count() <= 0:
		return
	var ghost := MeshInstance3D.new()
	ghost.name = "far_clipmap_level_%d_transition" % level
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.mesh = current_mesh
	ghost.position = current.position
	ghost.custom_aabb = current.custom_aabb
	ghost.material_override = _material_copy_with_alpha(current.material_override, 1.0)
	add_child(ghost)
	level_transition_nodes[level] = ghost
	level_transition_start_ms[level] = Time.get_ticks_msec()
	active_transition_count = _count_active_transitions()


func _start_level_fade(level: int) -> void:
	if level < 0 or level >= level_nodes.size():
		return
	var current: MeshInstance3D = level_nodes[level] as MeshInstance3D
	if level_transition_nodes[level] == null:
		_set_material_alpha(current.material_override, 1.0)
		level_transition_start_ms[level] = 0
		active_transition_count = _count_active_transitions()
		return
	current.material_override = _material_copy_with_alpha(current.material_override, 0.0)
	_set_material_alpha(current.material_override, 0.0)


func _update_transition_fades() -> void:
	var fade_ms: float = max(0.0, transition_fade_seconds) * 1000.0
	if fade_ms <= 0.0:
		for level in range(level_transition_nodes.size()):
			_remove_transition_node(level)
			if level < level_nodes.size():
				_set_material_alpha((level_nodes[level] as MeshInstance3D).material_override, 1.0)
		active_transition_count = 0
		return
	var now_ms: int = Time.get_ticks_msec()
	for level in range(level_transition_nodes.size()):
		var ghost: MeshInstance3D = level_transition_nodes[level] as MeshInstance3D
		if ghost == null:
			continue
		var elapsed: float = float(now_ms - int(level_transition_start_ms[level]))
		var t: float = clampf(elapsed / fade_ms, 0.0, 1.0)
		if level < level_nodes.size():
			_set_material_alpha((level_nodes[level] as MeshInstance3D).material_override, t)
		_set_material_alpha(ghost.material_override, 1.0 - t)
		if t >= 1.0:
			_remove_transition_node(level)
			if level < level_nodes.size():
				var current: MeshInstance3D = level_nodes[level] as MeshInstance3D
				current.material_override = _material_for_level(level, 1.0)
	active_transition_count = _count_active_transitions()


func _start_page_blend(level: int, has_previous_page: bool) -> void:
	if level < 0 or level >= level_page_blend_start_ms.size():
		return
	if not use_persistent_page_mesh or not has_previous_page or transition_fade_seconds <= 0.0:
		level_page_blend_start_ms[level] = 0
		_set_page_material_blend_alpha(level, 1.0)
	else:
		level_page_blend_start_ms[level] = Time.get_ticks_msec()
		_set_page_material_blend_alpha(level, 0.0)
	active_page_blend_count = _count_active_page_blends()


func _update_page_blends() -> void:
	if not use_persistent_page_mesh:
		active_page_blend_count = 0
		return
	var fade_ms: float = max(0.0, transition_fade_seconds) * 1000.0
	if fade_ms <= 0.0:
		for level in range(level_page_blend_start_ms.size()):
			level_page_blend_start_ms[level] = 0
			_set_page_material_blend_alpha(level, 1.0)
		active_page_blend_count = 0
		return
	var now_ms: int = Time.get_ticks_msec()
	for level in range(level_page_blend_start_ms.size()):
		var start_ms: int = int(level_page_blend_start_ms[level])
		if start_ms <= 0:
			continue
		var t: float = clampf(float(now_ms - start_ms) / fade_ms, 0.0, 1.0)
		_set_page_material_blend_alpha(level, t)
		if t >= 1.0:
			level_page_blend_start_ms[level] = 0
	active_page_blend_count = _count_active_page_blends()


func _set_page_material_blend_alpha(level: int, alpha: float) -> void:
	if level < 0 or level >= level_nodes.size():
		return
	var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
	if mesh_instance == null:
		return
	var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("height_blend_alpha", clampf(alpha, 0.0, 1.0))


func _count_active_page_blends() -> int:
	var count := 0
	for start_ms in level_page_blend_start_ms:
		if int(start_ms) > 0:
			count += 1
	return count


func _remove_transition_node(level: int) -> void:
	if level < 0 or level >= level_transition_nodes.size():
		return
	var ghost: MeshInstance3D = level_transition_nodes[level] as MeshInstance3D
	if ghost != null:
		if ghost.get_parent() != null:
			ghost.get_parent().remove_child(ghost)
		ghost.queue_free()
	level_transition_nodes[level] = null
	level_transition_start_ms[level] = 0


func _count_active_transitions() -> int:
	var count := 0
	for node in level_transition_nodes:
		if node != null:
			count += 1
	return count


func _material_copy_with_alpha(source: Material, alpha: float) -> Material:
	if source == null:
		return _material_for_level(0, alpha)
	var copy: Material = source.duplicate() as Material
	var shader_copy: ShaderMaterial = copy as ShaderMaterial
	if shader_copy != null and alpha < 0.999:
		var has_surface_textures: bool = shader_copy.get_shader_parameter("height_texture") != null
		shader_copy.shader = _surface_texture_material_shader(true) if has_surface_textures else _gray_material_shader(true)
	_set_material_alpha(copy, alpha)
	return copy


func _set_material_alpha(material: Material, alpha: float) -> void:
	var clamped_alpha: float = clampf(alpha, 0.0, 1.0)
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("fade_alpha", clamped_alpha)
		return
	var standard_material: StandardMaterial3D = material as StandardMaterial3D
	if standard_material != null:
		var color: Color = standard_material.albedo_color
		color.a = clamped_alpha
		standard_material.albedo_color = color
		standard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if clamped_alpha < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED


func _level_spacing(level: int) -> float:
	return base_spacing_m * float(1 << level)


func _native_clipmap_mesh_payload_from_height(
	height: PackedFloat32Array,
	side: int,
	spacing: float,
	outer_extent: float,
	inner_extent: float
) -> Dictionary:
	if not _native_backend_available():
		return {"status": "fail", "error": "native_backend_unavailable"}
	return _native_backend.call(
		"build_clipmap_mesh_payload_from_height",
		height,
		side,
		spacing,
		outer_extent,
		inner_extent
	) as Dictionary


func _native_backend_available() -> bool:
	if _native_backend != null:
		return true
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return false
	_native_backend = ClassDB.instantiate("Wg9TerrainNativeBackend")
	return _native_backend != null


func _can_use_native_workers() -> bool:
	if not use_native_workers:
		return false
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return false
	if world == null or world.provider == null:
		return false
	if not world.provider.has_method("native_prepared_height_grid_request"):
		return false
	if world.provider.has_method("landform_profile_report"):
		var profile_report: Dictionary = world.provider.call("landform_profile_report") as Dictionary
		if not bool(profile_report.get("native_prepared_grid_enabled", true)):
			return false
	return true


func _schedule_native_worker(level: int, origin: Vector2) -> String:
	if _native_workers.has(level):
		var existing_request: Dictionary = _native_worker_requests.get(level, {}) as Dictionary
		if _worker_request_matches_origin(level, existing_request, origin):
			return "inflight"
		var stale_worker: RefCounted = _native_workers[level] as RefCounted
		if stale_worker.call("is_done"):
			stale_worker.call("take_result")
		else:
			stale_worker.call("detach_until_done")
		_native_workers.erase(level)
		_native_worker_requests.erase(level)
	var request: Dictionary = _prepare_worker_request(level, origin)
	if request.get("status", "fail") != "pass":
		return "failed"
	var worker: RefCounted = TerrainFarClipmapPayloadWorkerScript.new()
	if not worker.start(request):
		return "failed"
	_native_workers[level] = worker
	_native_worker_requests[level] = request
	return "scheduled"


func _poll_native_workers() -> void:
	var keys: Array = _native_workers.keys()
	for key_value in keys:
		var level: int = int(key_value)
		var worker: RefCounted = _native_workers[level] as RefCounted
		if not worker.is_done():
			continue
		var payload: Dictionary = worker.take_result()
		var request: Dictionary = _native_worker_requests.get(level, {}) as Dictionary
		_native_workers.erase(level)
		_native_worker_requests.erase(level)
		if payload.get("status", "fail") != "pass":
			last_worker_error = "level_%d:%s" % [level, str(payload.get("error", "unknown"))]
			if level >= 0 and level < level_origins.size() and _pending_origin != level_origins[level]:
				_rebuild_level(level, _pending_origin, false)
				last_rebuilt_levels.append(level)
			continue
		if request.is_empty():
			last_worker_error = "level_%d:missing_request" % level
			continue
		if str(payload.get("request_id", "")) != str(request.get("request_id", "")):
			last_worker_error = "level_%d:request_id_mismatch" % level
			continue
		if not _worker_request_matches_pending(level, request):
			last_worker_error = "level_%d:stale_request" % level
			continue
		last_worker_error = ""
		last_worker_elapsed_ms = int(payload.get("worker_elapsed_ms", 0))
		_stage_native_payload(level, payload)
	active_worker_count = _native_workers.size()


func _clear_native_workers() -> void:
	for worker_value in _native_workers.values():
		var worker: RefCounted = worker_value as RefCounted
		if worker.call("is_done"):
			worker.call("take_result")
		else:
			worker.call("detach_until_done")
	_native_workers.clear()
	_native_worker_requests.clear()
	_staged_native_payloads.clear()
	_staged_native_origin = Vector2(INF, INF)
	active_worker_count = 0


func _prepare_worker_request(level: int, origin: Vector2) -> Dictionary:
	var spacing: float = _level_spacing(level)
	var outer_extent: float = _level_outer_extent(level)
	var inner_extent: float = _inner_extent_for_level(level)
	var side: int = _side_for_extent(outer_extent, spacing)
	var blocks: Array[Dictionary] = []
	var x_ranges: Array[Dictionary] = _axis_ranges_by_region(origin.x, outer_extent, spacing, side)
	var z_ranges: Array[Dictionary] = _axis_ranges_by_region(origin.y, outer_extent, spacing, side)
	for z_range_value in z_ranges:
		var z_range: Dictionary = z_range_value as Dictionary
		for x_range_value in x_ranges:
			var x_range: Dictionary = x_range_value as Dictionary
			var x0: int = int(x_range["start"])
			var x1: int = int(x_range["end"])
			var z0: int = int(z_range["start"])
			var z1: int = int(z_range["end"])
			var count_x: int = x1 - x0 + 1
			var count_z: int = z1 - z0 + 1
			var world_x0: float = origin.x - outer_extent + float(x0) * spacing
			var world_z0: float = origin.y - outer_extent + float(z0) * spacing
			var prepared: Dictionary = world.provider.native_prepared_height_grid_request(
				world_x0,
				world_z0,
				spacing,
				count_x,
				count_z,
				world.seed,
				world.region_size_m
			)
			if prepared.get("status", "fail") != "pass":
				return prepared
			blocks.append({
				"x0": x0,
				"z0": z0,
				"count_x": count_x,
				"count_z": count_z,
				"origin_x": world_x0,
				"origin_z": world_z0,
				"base_rx": int(prepared["base_rx"]),
				"base_rz": int(prepared["base_rz"]),
				"corner_entries": prepared["corner_entries"] as Array,
			})
	var request: Dictionary = {
		"status": "pass",
		"level": level,
		"origin_x": origin.x,
		"origin_z": origin.y,
		"outer_extent_m": outer_extent,
		"inner_extent_m": inner_extent,
		"spacing_m": spacing,
		"side": side,
		"world_seed": world.seed,
		"region_size_m": world.region_size_m,
		"blocks": blocks,
	}
	request["request_id"] = _worker_request_id(request)
	return request


func _worker_request_id(request: Dictionary) -> String:
	return "%d:%s:%s:%d:%s:%s:%s" % [
		int(request.get("level", -1)),
		_float_request_id(float(request.get("origin_x", INF))),
		_float_request_id(float(request.get("origin_z", INF))),
		int(request.get("side", -1)),
		_float_request_id(float(request.get("spacing_m", 0.0))),
		_float_request_id(float(request.get("outer_extent_m", 0.0))),
		_float_request_id(float(request.get("inner_extent_m", 0.0))),
	]


func _float_request_id(value: float) -> String:
	return "%.9f" % value


func _worker_request_matches_pending(level: int, request: Dictionary) -> bool:
	return _worker_request_matches_origin(level, request, _pending_origin)


func _worker_request_matches_origin(level: int, request: Dictionary, origin: Vector2) -> bool:
	if request.is_empty():
		return false
	if int(request.get("level", -1)) != level:
		return false
	var spacing: float = _level_spacing(level)
	var outer_extent: float = _level_outer_extent(level)
	var inner_extent: float = _inner_extent_for_level(level)
	var side: int = _side_for_extent(outer_extent, spacing)
	if int(request.get("side", -1)) != side:
		return false
	if not is_equal_approx(float(request.get("spacing_m", -1.0)), spacing):
		return false
	if not is_equal_approx(float(request.get("outer_extent_m", -1.0)), outer_extent):
		return false
	if not is_equal_approx(float(request.get("inner_extent_m", -1.0)), inner_extent):
		return false
	if int(request.get("world_seed", -1)) != int(world.seed):
		return false
	if not is_equal_approx(float(request.get("region_size_m", -1.0)), float(world.region_size_m)):
		return false
	var request_origin := Vector2(float(request.get("origin_x", INF)), float(request.get("origin_z", INF)))
	return request_origin == origin


func _stage_native_payload(level: int, payload: Dictionary) -> void:
	var origin := Vector2(float(payload.get("origin_x", INF)), float(payload.get("origin_z", INF)))
	if origin != _pending_origin:
		last_worker_error = "level_%d:stale_payload_origin" % level
		return
	_clear_staged_payloads_for_other_origin(origin)
	_staged_native_origin = origin
	_staged_native_payloads[level] = payload


func _clear_staged_payloads_for_other_origin(origin: Vector2) -> void:
	if _staged_native_payloads.is_empty():
		_staged_native_origin = origin
		return
	if _staged_native_origin == origin:
		return
	_staged_native_payloads.clear()
	_staged_native_origin = origin


func _staged_payload_matches_pending(level: int) -> bool:
	if _staged_native_origin != _pending_origin:
		return false
	return _staged_native_payloads.has(level)


func _commit_staged_payloads_if_ready() -> void:
	if _staged_native_origin != _pending_origin:
		return
	if _staged_native_payloads.size() < level_nodes.size():
		return
	for level in range(level_nodes.size()):
		if not _staged_native_payloads.has(level):
			return
	for level in range(level_nodes.size()):
		_assign_level_payload(_staged_native_payloads[level] as Dictionary, use_persistent_page_mesh)
	_staged_native_payloads.clear()
	_staged_native_origin = _pending_origin


func _clipmap_indices(side: int, spacing: float, outer_extent: float, inner_extent: float) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for z in range(side - 1):
		var z_center: float = -outer_extent + (float(z) + 0.5) * spacing
		for x in range(side - 1):
			var x_center: float = -outer_extent + (float(x) + 0.5) * spacing
			if absf(x_center) < inner_extent and absf(z_center) < inner_extent:
				continue
			var row: int = z * side
			var next_row: int = (z + 1) * side
			var a: int = row + x
			var b: int = row + x + 1
			var c: int = next_row + x
			var d: int = next_row + x + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	return indices


func _clipmap_index_count(side: int, spacing: float, outer_extent: float, inner_extent: float) -> int:
	var cell_count := 0
	for z in range(side - 1):
		var z_center: float = -outer_extent + (float(z) + 0.5) * spacing
		for x in range(side - 1):
			var x_center: float = -outer_extent + (float(x) + 0.5) * spacing
			if absf(x_center) < inner_extent and absf(z_center) < inner_extent:
				continue
			cell_count += 1
	return cell_count * 6


func _count_pending_rebuilds() -> int:
	var count := 0
	for origin in level_origins:
		if origin != _pending_origin:
			count += 1
	return count


func _shared_origin(viewer_xz: Vector2) -> Vector2:
	var spacing: float = max(0.000001, base_spacing_m)
	return Vector2(
		round(viewer_xz.x / spacing) * spacing,
		round(viewer_xz.y / spacing) * spacing
	)


func _level_outer_extent(level: int) -> float:
	return base_outer_extent_m * float(1 << level)


func _inner_extent_for_level(level: int) -> float:
	if level == 0:
		if level0_full_underlay_enabled:
			return 0.0
		return near_hole_extent_m
	return max(0.0, _level_outer_extent(level - 1) - _level_spacing(level))


func _side_for_extent(outer_extent: float, spacing: float) -> int:
	return int(round((outer_extent * 2.0) / spacing)) + 1


func _mib(byte_count: int) -> float:
	return snapped(float(byte_count) / (1024.0 * 1024.0), 0.001)


func _sample_height_grid_split_by_region(origin: Vector2, outer_extent: float, spacing: float, side: int) -> PackedFloat32Array:
	var height := PackedFloat32Array()
	height.resize(side * side)
	var x_ranges: Array[Dictionary] = _axis_ranges_by_region(origin.x, outer_extent, spacing, side)
	var z_ranges: Array[Dictionary] = _axis_ranges_by_region(origin.y, outer_extent, spacing, side)
	for z_range_value in z_ranges:
		var z_range: Dictionary = z_range_value as Dictionary
		for x_range_value in x_ranges:
			var x_range: Dictionary = x_range_value as Dictionary
			var x0: int = int(x_range["start"])
			var x1: int = int(x_range["end"])
			var z0: int = int(z_range["start"])
			var z1: int = int(z_range["end"])
			var count_x: int = x1 - x0 + 1
			var count_z: int = z1 - z0 + 1
			var world_x0: float = origin.x - outer_extent + float(x0) * spacing
			var world_z0: float = origin.y - outer_extent + float(z0) * spacing
			var block: PackedFloat32Array = world.sample_height_grid(world_x0, world_z0, spacing, count_x, count_z)
			for local_z in range(count_z):
				var src_row: int = local_z * count_x
				var dst_row: int = (z0 + local_z) * side
				for local_x in range(count_x):
					height[dst_row + x0 + local_x] = block[src_row + local_x]
	return height


func _morph_outer_transition_band(
	level: int,
	origin: Vector2,
	outer_extent: float,
	spacing: float,
	side: int,
	height: PackedFloat32Array
) -> PackedFloat32Array:
	if geometric_transition_band_cells <= 0 or level >= level_count - 1:
		return height
	if height.size() != side * side:
		return height
	var band_width_m: float = max(0.0, spacing * float(geometric_transition_band_cells))
	if band_width_m <= 0.000001:
		return height
	var next_spacing: float = _level_spacing(level + 1)
	if next_spacing <= spacing + 0.000001:
		return height
	var coarse_side: int = _side_for_extent(outer_extent, next_spacing)
	var coarse_height: PackedFloat32Array = _sample_height_grid_split_by_region(origin, outer_extent, next_spacing, coarse_side)
	var morphed := PackedFloat32Array(height)
	for z in range(side):
		var local_z: float = -outer_extent + float(z) * spacing
		for x in range(side):
			var local_x: float = -outer_extent + float(x) * spacing
			var distance_to_outer: float = outer_extent - max(absf(local_x), absf(local_z))
			if distance_to_outer >= band_width_m:
				continue
			var t: float = clampf(1.0 - distance_to_outer / band_width_m, 0.0, 1.0)
			var smooth_t: float = t * t * (3.0 - 2.0 * t)
			var index: int = z * side + x
			var target_height: float = _coarse_surface_height_from_grid(
				coarse_height,
				coarse_side,
				outer_extent,
				next_spacing,
				local_x,
				local_z
			)
			morphed[index] = lerpf(float(height[index]), target_height, smooth_t)
	return morphed


func _coarse_surface_height(origin: Vector2, local_x: float, local_z: float, coarse_spacing: float) -> float:
	var step: float = max(0.000001, coarse_spacing)
	var x0: float = floor(local_x / step) * step
	var z0: float = floor(local_z / step) * step
	var x1: float = x0 + step
	var z1: float = z0 + step
	var tx: float = clampf((local_x - x0) / step, 0.0, 1.0)
	var tz: float = clampf((local_z - z0) / step, 0.0, 1.0)
	var h00: float = world.sample_height(origin.x + x0, origin.y + z0)
	var h10: float = world.sample_height(origin.x + x1, origin.y + z0)
	var h01: float = world.sample_height(origin.x + x0, origin.y + z1)
	var h11: float = world.sample_height(origin.x + x1, origin.y + z1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _coarse_surface_height_from_grid(
	height: PackedFloat32Array,
	side: int,
	outer_extent: float,
	spacing: float,
	local_x: float,
	local_z: float
) -> float:
	if height.size() != side * side:
		return 0.0
	var grid_x: float = (local_x + outer_extent) / max(0.000001, spacing)
	var grid_z: float = (local_z + outer_extent) / max(0.000001, spacing)
	var x0: int = clampi(int(floor(grid_x)), 0, side - 1)
	var z0: int = clampi(int(floor(grid_z)), 0, side - 1)
	var x1: int = clampi(x0 + 1, 0, side - 1)
	var z1: int = clampi(z0 + 1, 0, side - 1)
	var tx: float = clampf(grid_x - float(x0), 0.0, 1.0)
	var tz: float = clampf(grid_z - float(z0), 0.0, 1.0)
	var h00: float = float(height[z0 * side + x0])
	var h10: float = float(height[z0 * side + x1])
	var h01: float = float(height[z1 * side + x0])
	var h11: float = float(height[z1 * side + x1])
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _centered_vertices_from_height(
	height: PackedFloat32Array,
	side: int,
	spacing: float,
	outer_extent: float
) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	vertices.resize(side * side)
	for z in range(side):
		var local_z: float = -outer_extent + float(z) * spacing
		for x in range(side):
			var local_x: float = -outer_extent + float(x) * spacing
			var index: int = z * side + x
			vertices[index] = Vector3(local_x, float(height[index]), local_z)
	return vertices


func _axis_ranges_by_region(origin_axis: float, outer_extent: float, spacing: float, side: int) -> Array[Dictionary]:
	var ranges: Array[Dictionary] = []
	var start := 0
	var current_region: int = _region_for_axis(origin_axis - outer_extent)
	for index in range(1, side):
		var coord: float = origin_axis - outer_extent + float(index) * spacing
		var region: int = _region_for_axis(coord)
		if region == current_region:
			continue
		ranges.append({"start": start, "end": index - 1, "region": current_region})
		start = index
		current_region = region
	ranges.append({"start": start, "end": side - 1, "region": current_region})
	return ranges


func _region_for_axis(coord: float) -> int:
	return int(floor(coord / world.region_size_m))


func _normal_at(height: PackedFloat32Array, side: int, x: int, z: int, spacing: float) -> Vector3:
	var x0: int = max(0, x - 1)
	var x1: int = min(side - 1, x + 1)
	var z0: int = max(0, z - 1)
	var z1: int = min(side - 1, z + 1)
	var dx: float = (float(height[z * side + x1]) - float(height[z * side + x0])) / max(0.000001, float(x1 - x0) * spacing)
	var dz: float = (float(height[z1 * side + x]) - float(height[z0 * side + x])) / max(0.000001, float(z1 - z0) * spacing)
	return Vector3(-dx, 1.0, -dz).normalized()


func _heightfield_for_level(
	level: int,
	origin: Vector2,
	outer_extent: float,
	spacing: float,
	side: int,
	height: PackedFloat32Array,
	normals: PackedVector3Array = PackedVector3Array()
) -> Dictionary:
	var range: Dictionary = TerrainSurfaceTextureBuilderScript.height_range(height)
	return {
		"level": level,
		"origin_x": origin.x,
		"origin_z": origin.y,
		"outer_extent_m": outer_extent,
		"inner_extent_m": _inner_extent_for_level(level),
		"spacing_m": spacing,
		"vertices_per_side": side,
		"height": height,
		"normals": normals,
		"cache_key": _page_cache_key_for_level(level, origin, outer_extent, spacing, side),
		"height_min_m": float(range["min"]),
		"height_max_m": float(range["max"]),
	}


func _page_cache_key_for_level(level: int, origin: Vector2, outer_extent: float, spacing: float, side: int) -> String:
	if world == null:
		return ""
	var request = _make_far_clipmap_page_request(level, origin, outer_extent, spacing, side)
	if not request.validate().is_empty():
		return ""
	return request.cache_key()


func _surface_descriptor_from_heightfield(
	heightfield: Dictionary,
	include_debug_maps: bool = true,
	include_visual_displacement: bool = true
) -> Dictionary:
	var texture_start_ms: int = Time.get_ticks_msec()
	var normals: PackedVector3Array = heightfield.get("normals", PackedVector3Array()) as PackedVector3Array
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(
		heightfield["height"] as PackedFloat32Array,
		int(heightfield["vertices_per_side"]),
		float(heightfield["spacing_m"]),
		include_debug_maps,
		include_visual_displacement,
		normals
	)
	last_surface_texture_ms = Time.get_ticks_msec() - texture_start_ms
	descriptor["level"] = int(heightfield["level"])
	descriptor["origin_x"] = float(heightfield["origin_x"])
	descriptor["origin_z"] = float(heightfield["origin_z"])
	descriptor["outer_extent_m"] = float(heightfield["outer_extent_m"])
	descriptor["cache_key"] = str(heightfield.get("cache_key", ""))
	if descriptor.get("status", "fail") != "pass":
		return descriptor
	var level: int = int(heightfield["level"])
	descriptor["inner_extent_m"] = _inner_extent_for_level(level)
	return descriptor


func _material_descriptor_from_heightfield(heightfield: Dictionary) -> Dictionary:
	return _surface_descriptor_from_heightfield(heightfield, false, false)


func _page_material_descriptor_from_heightfield(heightfield: Dictionary) -> Dictionary:
	var cache_key: String = str(heightfield.get("cache_key", ""))
	if use_persistent_page_mesh and _gpu_page_residency != null and _gpu_page_residency.has_page(cache_key):
		last_page_descriptor_texture_hits += 1
		var height_min: float = float(heightfield.get("height_min_m", 0.0))
		var height_max: float = float(heightfield.get("height_max_m", height_min))
		var level: int = int(heightfield.get("level", 0))
		return {
			"status": "pass",
			"level": level,
			"origin_x": float(heightfield.get("origin_x", 0.0)),
			"origin_z": float(heightfield.get("origin_z", 0.0)),
			"outer_extent_m": float(heightfield.get("outer_extent_m", 0.0)),
			"inner_extent_m": _inner_extent_for_level(level),
			"vertices_per_side": int(heightfield.get("vertices_per_side", vertices_per_side)),
			"spacing_m": float(heightfield.get("spacing_m", _level_spacing(level))),
			"height_min_m": height_min,
			"height_max_m": height_max,
			"height_range_m": max(0.0, height_max - height_min),
			"cache_key": cache_key,
		}
	last_page_descriptor_image_builds += 1
	return _material_descriptor_from_heightfield(heightfield)


func _ensure_persistent_page_mesh(level: int, side: int, spacing: float, outer_extent: float, inner_extent: float) -> void:
	if level < 0 or level >= level_nodes.size():
		return
	var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
	var mesh_key: String = "%d:%.9f:%.9f:%.9f" % [side, spacing, outer_extent, inner_extent]
	if mesh_instance.mesh != null and str(mesh_instance.get_meta("persistent_page_mesh_key", "")) == mesh_key:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	uvs.resize(side * side)
	var denom: float = float(max(1, side - 1))
	for z in range(side):
		var local_z: float = -outer_extent + float(z) * spacing
		for x in range(side):
			var local_x: float = -outer_extent + float(x) * spacing
			var index: int = z * side + x
			vertices[index] = Vector3(local_x, 0.0, local_z)
			normals[index] = Vector3.UP
			uvs[index] = Vector2(float(x) / denom, float(z) / denom)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _clipmap_indices(side, spacing, outer_extent, inner_extent)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh
	mesh_instance.set_meta("persistent_page_mesh_key", mesh_key)


func _apply_persistent_page_custom_aabb(
	level: int,
	heightfield: Dictionary,
	previous_heightfield: Dictionary = {}
) -> void:
	if level < 0 or level >= level_nodes.size() or not use_persistent_page_mesh:
		return
	if heightfield.is_empty():
		return
	var outer_extent: float = max(1.0, float(heightfield.get("outer_extent_m", _level_outer_extent(level))))
	var min_y: float = float(heightfield.get("height_min_m", 0.0))
	var max_y: float = float(heightfield.get("height_max_m", 0.0))
	if not previous_heightfield.is_empty():
		min_y = minf(min_y, float(previous_heightfield.get("height_min_m", min_y)))
		max_y = maxf(max_y, float(previous_heightfield.get("height_max_m", max_y)))
	if not is_finite(min_y) or not is_finite(max_y):
		min_y = -1024.0
		max_y = 1024.0
	if max_y < min_y:
		var swap := min_y
		min_y = max_y
		max_y = swap
	var height_range: float = max(1.0, max_y - min_y)
	var padding_y: float = maxf(32.0, maxf(_level_spacing(level) * 2.0, height_range * 0.08))
	var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
	mesh_instance.custom_aabb = AABB(
		Vector3(-outer_extent, min_y - padding_y, -outer_extent),
		Vector3(outer_extent * 2.0, height_range + padding_y * 2.0, outer_extent * 2.0)
	)


func _page_height_material_for_descriptor(
	descriptor: Dictionary,
	level: int,
	previous_height_texture: Texture2D = null,
	previous_normal_texture: Texture2D = null,
	blend_alpha: float = 1.0,
	previous_page_origin_m: Vector2 = Vector2(INF, INF),
	previous_page_extent_m: float = 0.0,
	reusable_material: ShaderMaterial = null
) -> ShaderMaterial:
	var texture_entry: Dictionary = _gpu_page_textures_for_descriptor(descriptor)
	var height_texture: Texture2D = texture_entry["height_texture"] as Texture2D
	var normal_texture: Texture2D = texture_entry["normal_texture"] as Texture2D
	var page_origin := Vector2(float(descriptor.get("origin_x", 0.0)), float(descriptor.get("origin_z", 0.0)))
	var page_extent: float = float(descriptor.get("outer_extent_m", 0.0))
	if not is_finite(previous_page_origin_m.x) or not is_finite(previous_page_origin_m.y):
		previous_page_origin_m = page_origin
	if previous_page_extent_m <= 0.0:
		previous_page_extent_m = page_extent
	var page_shader: Shader = _page_height_material_shader()
	var material: ShaderMaterial = null
	if reusable_material != null and reusable_material.shader == page_shader:
		material = reusable_material
	if material == null:
		material = ShaderMaterial.new()
		material.shader = page_shader
	last_page_material_reused = material == reusable_material and reusable_material != null
	material.set_shader_parameter("height_texture", height_texture)
	material.set_shader_parameter("normal_texture", normal_texture)
	material.set_shader_parameter("previous_height_texture", previous_height_texture if previous_height_texture != null else height_texture)
	material.set_shader_parameter("previous_normal_texture", previous_normal_texture if previous_normal_texture != null else normal_texture)
	material.set_shader_parameter("height_blend_alpha", clampf(blend_alpha, 0.0, 1.0))
	material.set_shader_parameter("normal_strength", surface_texture_normal_strength)
	material.set_shader_parameter("clipmap_level", level)
	material.set_shader_parameter("page_origin_m", page_origin)
	material.set_shader_parameter("page_extent_m", page_extent)
	material.set_shader_parameter("previous_page_origin_m", previous_page_origin_m)
	material.set_shader_parameter("previous_page_extent_m", previous_page_extent_m)
	material.set_shader_parameter("coarse_height_texture", height_texture)
	material.set_shader_parameter("coarse_page_origin_m", page_origin)
	material.set_shader_parameter("coarse_page_extent_m", page_extent)
	material.set_shader_parameter("morph_enabled", false)
	material.set_shader_parameter("morph_band_m", 0.0)
	material.set_shader_parameter("inner_extent_m", float(descriptor.get("inner_extent_m", 0.0)))
	material.set_shader_parameter("outer_extent_m", float(descriptor.get("outer_extent_m", 0.0)))
	material.set_shader_parameter("boundary_blend_width_m", max(512.0, float(descriptor.get("outer_extent_m", 0.0)) * 0.035))
	material.set_shader_parameter("elevation_color_enabled", use_elevation_color_material)
	_apply_level_edge_fog_shader_parameters(level, material)
	return material


func _gpu_page_textures_for_descriptor(descriptor: Dictionary) -> Dictionary:
	var cache_key: String = str(descriptor.get("cache_key", ""))
	if use_persistent_page_mesh:
		_ensure_gpu_page_residency()
		var resident: Dictionary = _gpu_page_residency.get_or_create_textures(cache_key, descriptor) as Dictionary
		if resident.get("status", "fail") == "pass":
			return resident
	return {
		"status": "pass",
		"cache_key": cache_key,
		"height_texture": ImageTexture.create_from_image(descriptor["height_image"] as Image),
		"normal_texture": ImageTexture.create_from_image(descriptor["normal_image"] as Image),
	}


func _refresh_page_morph_sources() -> void:
	for level in range(level_nodes.size()):
		var mesh_instance: MeshInstance3D = level_nodes[level] as MeshInstance3D
		if mesh_instance == null:
			continue
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if material == null:
			continue
		var height_texture: Texture2D = material.get_shader_parameter("height_texture") as Texture2D
		if height_texture == null:
			continue
		var page_origin := _shader_vec2_param(material, "page_origin_m", Vector2.ZERO)
		var page_extent: float = _shader_float_param(material, "page_extent_m", _level_outer_extent(level))
		var enabled := false
		var coarse_texture: Texture2D = height_texture
		var coarse_origin := page_origin
		var coarse_extent := page_extent
		if geometric_transition_band_cells > 0 and level + 1 < level_nodes.size():
			var coarse_instance: MeshInstance3D = level_nodes[level + 1] as MeshInstance3D
			var coarse_material: ShaderMaterial = coarse_instance.material_override as ShaderMaterial if coarse_instance != null else null
			if coarse_material != null:
				var candidate: Texture2D = coarse_material.get_shader_parameter("height_texture") as Texture2D
				if candidate != null:
					enabled = true
					coarse_texture = candidate
					coarse_origin = _shader_vec2_param(coarse_material, "page_origin_m", page_origin)
					coarse_extent = _shader_float_param(coarse_material, "page_extent_m", page_extent)
		material.set_shader_parameter("coarse_height_texture", coarse_texture)
		material.set_shader_parameter("coarse_page_origin_m", coarse_origin)
		material.set_shader_parameter("coarse_page_extent_m", coarse_extent)
		material.set_shader_parameter("morph_enabled", enabled)
		material.set_shader_parameter("morph_band_m", max(_level_spacing(level) * float(geometric_transition_band_cells), 1.0))


func _shader_vec2_param(material: ShaderMaterial, name: String, fallback: Vector2) -> Vector2:
	if material == null:
		return fallback
	var value: Variant = material.get_shader_parameter(name)
	if value is Vector2:
		return value as Vector2
	return fallback


func _shader_float_param(material: ShaderMaterial, name: String, fallback: float) -> float:
	if material == null:
		return fallback
	var value: Variant = material.get_shader_parameter(name)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


func _material_for_level(level: int, alpha: float = 1.0) -> Material:
	if debug_level_colors:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var colors: Array[Color] = [
			Color(0.28, 0.54, 0.86),
			Color(0.35, 0.72, 0.44),
			Color(0.92, 0.70, 0.26),
			Color(0.80, 0.44, 0.78),
		]
		material.albedo_color = colors[clampi(level, 0, colors.size() - 1)]
		_set_material_alpha(material, alpha)
		return material
	if use_surface_texture_material and level < level_material_descriptors.size():
		var descriptor: Dictionary = level_material_descriptors[level] as Dictionary
		if descriptor.get("status", "fail") == "pass":
			return _surface_texture_material_for_descriptor(descriptor, alpha)
	var material := ShaderMaterial.new()
	material.shader = _gray_material_shader(alpha < 0.999)
	material.set_shader_parameter("fade_alpha", alpha)
	material.set_shader_parameter("elevation_color_enabled", use_elevation_color_material)
	_apply_level_edge_fog_shader_parameters(level, material)
	return material


func _surface_texture_material_for_descriptor(descriptor: Dictionary, alpha: float = 1.0) -> ShaderMaterial:
	var height_texture: ImageTexture = ImageTexture.create_from_image(descriptor["height_image"] as Image)
	var normal_texture: ImageTexture = ImageTexture.create_from_image(descriptor["normal_image"] as Image)
	var material := ShaderMaterial.new()
	var level: int = int(descriptor.get("level", 0))
	material.shader = _surface_texture_material_shader(alpha < 0.999)
	material.set_shader_parameter("height_texture", height_texture)
	material.set_shader_parameter("normal_texture", normal_texture)
	material.set_shader_parameter("height_min_m", float(descriptor["height_min_m"]))
	material.set_shader_parameter("height_range_m", max(0.000001, float(descriptor["height_range_m"])))
	material.set_shader_parameter("normal_strength", surface_texture_normal_strength)
	material.set_shader_parameter("fade_alpha", alpha)
	material.set_shader_parameter("elevation_color_enabled", use_elevation_color_material)
	_apply_level_edge_fog_shader_parameters(level, material)
	return material


func _refresh_surface_material_parameters(mesh_instance: MeshInstance3D, level: int) -> bool:
	var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material == null:
		return false
	var height_texture: Texture2D = material.get_shader_parameter("height_texture") as Texture2D
	var normal_texture: Texture2D = material.get_shader_parameter("normal_texture") as Texture2D
	if height_texture == null or normal_texture == null:
		return false
	material.set_shader_parameter("normal_strength", surface_texture_normal_strength)
	material.set_shader_parameter("elevation_color_enabled", use_elevation_color_material)
	_apply_level_edge_fog_shader_parameters(level, material)
	return true


func _level_uses_edge_fade(level: int) -> bool:
	return use_edge_fog and level == level_nodes.size() - 1


func _gray_material_shader(fade_enabled: bool = false) -> Shader:
	if fade_enabled and _gray_shader_fade != null:
		return _gray_shader_fade
	if not fade_enabled and _gray_shader_opaque != null:
		return _gray_shader_opaque
	var shader := Shader.new()
	var render_mode: String = "unshaded, cull_disabled, blend_mix" if fade_enabled else "unshaded, cull_disabled"
	shader.code = """
shader_type spatial;
render_mode %s;

uniform float fade_alpha = 1.0;
uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);
uniform bool edge_fog_square_enabled = true;
uniform vec2 edge_fog_center_xz = vec2(0.0, 0.0);
uniform bool elevation_color_enabled = false;

varying float height_m;
varying vec3 terrain_normal;
varying vec3 world_position;

vec3 elevation_palette(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.16) {
		return mix(vec3(0.005, 0.006, 0.012), vec3(0.02, 0.05, 0.22), t / 0.16);
	}
	if (t < 0.32) {
		return mix(vec3(0.02, 0.05, 0.22), vec3(0.02, 0.35, 0.70), (t - 0.16) / 0.16);
	}
	if (t < 0.48) {
		return mix(vec3(0.02, 0.35, 0.70), vec3(0.05, 0.58, 0.24), (t - 0.32) / 0.16);
	}
	if (t < 0.64) {
		return mix(vec3(0.05, 0.58, 0.24), vec3(0.95, 0.86, 0.20), (t - 0.48) / 0.16);
	}
	if (t < 0.80) {
		return mix(vec3(0.95, 0.86, 0.20), vec3(0.90, 0.20, 0.08), (t - 0.64) / 0.16);
	}
	if (t < 0.92) {
		return mix(vec3(0.90, 0.20, 0.08), vec3(0.70, 0.24, 0.86), (t - 0.80) / 0.12);
	}
	return mix(vec3(0.70, 0.24, 0.86), vec3(1.0, 1.0, 1.0), (t - 0.92) / 0.08);
}

void vertex() {
	height_m = VERTEX.y;
	terrain_normal = normalize(NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(terrain_normal);
	if (n.y < 0.0) {
		n = -n;
	}
	if (n.y < 0.25) {
		n = vec3(0.0, 1.0, 0.0);
	}
	vec3 review_n = normalize(vec3(n.x * 0.65, n.y, n.z * 0.65));
	vec3 light_dir = normalize(vec3(-0.42, 0.74, -0.52));
	float lambert = dot(review_n, light_dir) * 0.5 + 0.5;
	float compressed_height = 0.5 + atan(height_m / 1800.0) / 3.14159265;
	float slope_shadow = clamp((1.0 - review_n.y) * 0.04, 0.0, 0.025);
	float shade = clamp(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70);
	shade = (shade - 0.5) * 1.42 + 0.5;
	shade = clamp(shade * 0.42, 0.035, 0.58);
	float height_t = clamp(compressed_height, 0.0, 1.0);
	vec3 elevation_tint = mix(vec3(0.56, 0.62, 0.58), vec3(0.80, 0.74, 0.62), height_t);
	vec3 color = vec3(shade) * mix(vec3(1.0), elevation_tint * 1.24, 0.28);
	if (elevation_color_enabled) {
		color = elevation_palette(height_t) * clamp(0.62 + lambert * 0.32 - (1.0 - review_n.y) * 0.08, 0.45, 1.0);
	}
	float camera_distance_m = distance(world_position.xz, CAMERA_POSITION_WORLD.xz);
	float square_distance_m = max(abs(world_position.x - edge_fog_center_xz.x), abs(world_position.z - edge_fog_center_xz.y));
	float fog_distance_m = edge_fog_square_enabled ? square_distance_m : camera_distance_m;
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, fog_distance_m) : 0.0;
	ALBEDO = mix(color, edge_fog_color, fog_t);
	ALPHA = fade_alpha;
}
""" % render_mode
	if fade_enabled:
		_gray_shader_fade = shader
	else:
		_gray_shader_opaque = shader
	return shader


func _surface_texture_material_shader(fade_enabled: bool = false) -> Shader:
	if fade_enabled and _surface_texture_shader_fade != null:
		return _surface_texture_shader_fade
	if not fade_enabled and _surface_texture_shader_opaque != null:
		return _surface_texture_shader_opaque
	var shader := Shader.new()
	var render_mode: String = "unshaded, cull_disabled, blend_mix" if fade_enabled else "unshaded, cull_disabled"
	shader.code = """
shader_type spatial;
render_mode %s;

uniform sampler2D height_texture : filter_linear;
uniform sampler2D normal_texture : filter_linear;
uniform float height_min_m = 0.0;
uniform float height_range_m = 1.0;
uniform float normal_strength = 1.0;
uniform float fade_alpha = 1.0;
uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);
uniform bool edge_fog_square_enabled = true;
uniform vec2 edge_fog_center_xz = vec2(0.0, 0.0);
uniform bool elevation_color_enabled = false;

varying vec2 local_uv;
varying vec3 terrain_normal;
varying vec3 world_position;

vec3 elevation_palette(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.16) {
		return mix(vec3(0.005, 0.006, 0.012), vec3(0.02, 0.05, 0.22), t / 0.16);
	}
	if (t < 0.32) {
		return mix(vec3(0.02, 0.05, 0.22), vec3(0.02, 0.35, 0.70), (t - 0.16) / 0.16);
	}
	if (t < 0.48) {
		return mix(vec3(0.02, 0.35, 0.70), vec3(0.05, 0.58, 0.24), (t - 0.32) / 0.16);
	}
	if (t < 0.64) {
		return mix(vec3(0.05, 0.58, 0.24), vec3(0.95, 0.86, 0.20), (t - 0.48) / 0.16);
	}
	if (t < 0.80) {
		return mix(vec3(0.95, 0.86, 0.20), vec3(0.90, 0.20, 0.08), (t - 0.64) / 0.16);
	}
	if (t < 0.92) {
		return mix(vec3(0.90, 0.20, 0.08), vec3(0.70, 0.24, 0.86), (t - 0.80) / 0.12);
	}
	return mix(vec3(0.70, 0.24, 0.86), vec3(1.0, 1.0, 1.0), (t - 0.92) / 0.08);
}

void vertex() {
	local_uv = UV;
	terrain_normal = normalize(NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float height_m = texture(height_texture, local_uv).r;
	float compressed_height = 0.5 + atan(height_m / 1800.0) / 3.14159265;
	vec3 geometry_n = normalize(terrain_normal);
	if (geometry_n.y < 0.0) {
		geometry_n = -geometry_n;
	}
	if (geometry_n.y < 0.25) {
		geometry_n = vec3(0.0, 1.0, 0.0);
	}
	vec3 normal_sample = normalize(texture(normal_texture, local_uv).rgb * 2.0 - 1.0);
	vec3 n = normalize(mix(geometry_n, normal_sample, clamp(normal_strength * 0.18, 0.0, 0.35)));
	vec3 review_n = normalize(vec3(n.x * 0.65, n.y, n.z * 0.65));
	vec3 light_dir = normalize(vec3(-0.42, 0.74, -0.52));
	float lambert = dot(review_n, light_dir) * 0.5 + 0.5;
	float slope_shadow = clamp((1.0 - review_n.y) * 0.04, 0.0, 0.025);
	float shade = clamp(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70);
	shade = (shade - 0.5) * 1.42 + 0.5;
	shade = clamp(shade * 0.42, 0.035, 0.58);
	float height_t = clamp(compressed_height, 0.0, 1.0);
	vec3 elevation_tint = mix(vec3(0.56, 0.62, 0.58), vec3(0.80, 0.74, 0.62), height_t);
	vec3 color = vec3(shade) * mix(vec3(1.0), elevation_tint * 1.24, 0.28);
	if (elevation_color_enabled) {
		color = elevation_palette(height_t) * clamp(0.62 + lambert * 0.32 - (1.0 - review_n.y) * 0.08, 0.45, 1.0);
	}
	float camera_distance_m = distance(world_position.xz, CAMERA_POSITION_WORLD.xz);
	float square_distance_m = max(abs(world_position.x - edge_fog_center_xz.x), abs(world_position.z - edge_fog_center_xz.y));
	float fog_distance_m = edge_fog_square_enabled ? square_distance_m : camera_distance_m;
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, fog_distance_m) : 0.0;
	ALBEDO = mix(color, edge_fog_color, fog_t);
	ALPHA = fade_alpha;
}
""" % render_mode
	if fade_enabled:
		_surface_texture_shader_fade = shader
	else:
		_surface_texture_shader_opaque = shader
	return shader


func _page_height_material_shader() -> Shader:
	if _page_height_shader != null:
		return _page_height_shader
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D height_texture : filter_linear, repeat_disable;
uniform sampler2D normal_texture : filter_linear, repeat_disable;
uniform sampler2D previous_height_texture : filter_linear, repeat_disable;
uniform sampler2D previous_normal_texture : filter_linear, repeat_disable;
uniform sampler2D coarse_height_texture : filter_linear, repeat_disable;
uniform float height_blend_alpha = 1.0;
uniform float normal_strength = 1.0;
uniform int clipmap_level = 0;
uniform vec2 page_origin_m = vec2(0.0, 0.0);
uniform float page_extent_m = 1.0;
uniform vec2 previous_page_origin_m = vec2(0.0, 0.0);
uniform float previous_page_extent_m = 1.0;
uniform vec2 coarse_page_origin_m = vec2(0.0, 0.0);
uniform float coarse_page_extent_m = 1.0;
uniform bool morph_enabled = false;
uniform float morph_band_m = 0.0;
uniform float inner_extent_m = 0.0;
uniform float outer_extent_m = 0.0;
uniform float boundary_blend_width_m = 512.0;
uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);
uniform bool edge_fog_square_enabled = true;
uniform vec2 edge_fog_center_xz = vec2(0.0, 0.0);
uniform bool elevation_color_enabled = false;

varying vec2 local_uv;
varying vec2 current_uv;
varying vec2 previous_uv;
varying float previous_uv_valid;
varying vec2 local_xz;
varying float height_m;
varying vec3 terrain_normal;
varying vec3 world_position;

vec3 elevation_palette(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.16) {
		return mix(vec3(0.005, 0.006, 0.012), vec3(0.02, 0.05, 0.22), t / 0.16);
	}
	if (t < 0.32) {
		return mix(vec3(0.02, 0.05, 0.22), vec3(0.02, 0.35, 0.70), (t - 0.16) / 0.16);
	}
	if (t < 0.48) {
		return mix(vec3(0.02, 0.35, 0.70), vec3(0.05, 0.58, 0.24), (t - 0.32) / 0.16);
	}
	if (t < 0.64) {
		return mix(vec3(0.05, 0.58, 0.24), vec3(0.95, 0.86, 0.20), (t - 0.48) / 0.16);
	}
	if (t < 0.80) {
		return mix(vec3(0.95, 0.86, 0.20), vec3(0.90, 0.20, 0.08), (t - 0.64) / 0.16);
	}
	if (t < 0.92) {
		return mix(vec3(0.90, 0.20, 0.08), vec3(0.70, 0.24, 0.86), (t - 0.80) / 0.12);
	}
	return mix(vec3(0.70, 0.24, 0.86), vec3(1.0, 1.0, 1.0), (t - 0.92) / 0.08);
}

vec2 page_uv_for_world(vec2 world_xz, vec2 origin_m, float extent_m) {
	float diameter_m = max(extent_m * 2.0, 1e-6);
	return (world_xz - (origin_m - vec2(extent_m))) / diameter_m;
}

float uv_valid_factor(vec2 uv) {
	vec2 inside_min = step(vec2(0.0), uv);
	vec2 inside_max = step(uv, vec2(1.0));
	return inside_min.x * inside_min.y * inside_max.x * inside_max.y;
}

float sample_height_world(sampler2D tex, vec2 world_xz, vec2 origin_m, float extent_m) {
	vec2 uv = clamp(page_uv_for_world(world_xz, origin_m, extent_m), vec2(0.0), vec2(1.0));
	return texture(tex, uv).r;
}

void vertex() {
	local_xz = VERTEX.xz;
	vec3 flat_world_position = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	vec2 world_xz = flat_world_position.xz;
	current_uv = clamp(page_uv_for_world(world_xz, page_origin_m, page_extent_m), vec2(0.0), vec2(1.0));
	previous_uv = clamp(page_uv_for_world(world_xz, previous_page_origin_m, previous_page_extent_m), vec2(0.0), vec2(1.0));
	previous_uv_valid = uv_valid_factor(page_uv_for_world(world_xz, previous_page_origin_m, previous_page_extent_m));
	local_uv = current_uv;
	float current_height_m = texture(height_texture, current_uv).r;
	float previous_height_m = texture(previous_height_texture, previous_uv).r;
	previous_height_m = mix(current_height_m, previous_height_m, previous_uv_valid);
	height_m = mix(previous_height_m, current_height_m, clamp(height_blend_alpha, 0.0, 1.0));
	if (morph_enabled) {
		vec2 coarse_uv_unclamped = page_uv_for_world(world_xz, coarse_page_origin_m, coarse_page_extent_m);
		float coarse_valid = uv_valid_factor(coarse_uv_unclamped);
		float coarse_height_m = texture(coarse_height_texture, clamp(coarse_uv_unclamped, vec2(0.0), vec2(1.0))).r;
		float square_radius_m = max(abs(world_xz.x - page_origin_m.x), abs(world_xz.y - page_origin_m.y));
		float distance_to_outer_m = max(0.0, page_extent_m - square_radius_m);
		float morph_t = 1.0 - smoothstep(0.0, max(1.0, morph_band_m), distance_to_outer_m);
		height_m = mix(height_m, coarse_height_m, morph_t * coarse_valid);
	}
	VERTEX.y = height_m;
	terrain_normal = NORMAL;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 previous_n = normalize(texture(previous_normal_texture, previous_uv).rgb * 2.0 - 1.0);
	vec3 current_n = normalize(texture(normal_texture, current_uv).rgb * 2.0 - 1.0);
	previous_n = normalize(mix(current_n, previous_n, previous_uv_valid));
	vec3 n = normalize(mix(previous_n, current_n, clamp(height_blend_alpha, 0.0, 1.0)));
	if (n.y < 0.0) {
		n = -n;
	}
	if (n.y < 0.25) {
		n = vec3(0.0, 1.0, 0.0);
	}
	float square_radius = max(abs(local_xz.x), abs(local_xz.y));
	float inner_distance = inner_extent_m > 0.0 ? abs(square_radius - inner_extent_m) : boundary_blend_width_m;
	float outer_distance = outer_extent_m > 0.0 ? max(0.0, outer_extent_m - square_radius) : boundary_blend_width_m;
	float boundary_distance = min(inner_distance, outer_distance);
	float boundary_strength = smoothstep(0.0, max(1.0, boundary_blend_width_m), boundary_distance);
	float level_strength = 1.0 / (1.0 + max(float(clipmap_level), 0.0) * 0.55);
	float detail_strength = clamp(normal_strength, 0.0, 4.0) * boundary_strength * level_strength;
	vec3 stable_n = normalize(mix(vec3(0.0, 1.0, 0.0), n, detail_strength));
	vec3 review_n = normalize(vec3(stable_n.x * 0.65, stable_n.y, stable_n.z * 0.65));
	vec3 light_dir = normalize(vec3(-0.42, 0.74, -0.52));
	float lambert = dot(review_n, light_dir) * 0.5 + 0.5;
	float compressed_height = 0.5 + atan(height_m / 1800.0) / 3.14159265;
	float slope_shadow = clamp((1.0 - review_n.y) * 0.04, 0.0, 0.025);
	float shade = clamp(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70);
	shade = (shade - 0.5) * 1.42 + 0.5;
	shade = clamp(shade * 0.42, 0.035, 0.58);
	float height_t = clamp(compressed_height, 0.0, 1.0);
	vec3 elevation_tint = mix(vec3(0.56, 0.62, 0.58), vec3(0.80, 0.74, 0.62), height_t);
	vec3 color = vec3(shade) * mix(vec3(1.0), elevation_tint * 1.24, 0.28);
	if (elevation_color_enabled) {
		color = elevation_palette(height_t) * clamp(0.62 + lambert * 0.32 - (1.0 - review_n.y) * 0.08, 0.45, 1.0);
	}
	float camera_distance_m = distance(world_position.xz, CAMERA_POSITION_WORLD.xz);
	float square_distance_m = max(abs(world_position.x - edge_fog_center_xz.x), abs(world_position.z - edge_fog_center_xz.y));
	float fog_distance_m = edge_fog_square_enabled ? square_distance_m : camera_distance_m;
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, fog_distance_m) : 0.0;
	ALBEDO = mix(color, edge_fog_color, fog_t);
}
"""
	_page_height_shader = shader
	return shader


func _apply_level_edge_fog_shader_parameters(level: int, material: ShaderMaterial) -> void:
	if material == null:
		return
	if level != level_nodes.size() - 1:
		_apply_edge_fog_shader_parameters(material, false, Vector2.ZERO)
		return
	var center := edge_fog_center_xz
	if not is_finite(center.x) or not is_finite(center.y):
		center = Vector2.ZERO
	var outer_extent: float = _level_outer_extent(level)
	var effective_begin: float = edge_fog_begin_m
	var effective_end: float = edge_fog_end_m
	if outer_extent > 1.0:
		if effective_begin >= outer_extent:
			effective_begin = outer_extent * 0.82
			effective_end = outer_extent * 0.985
		else:
			effective_end = min(effective_end, outer_extent * 0.995)
			effective_begin = min(effective_begin, effective_end - 1.0)
	_apply_edge_fog_shader_parameters(material, true, center, effective_begin, effective_end)


func _apply_edge_fog_shader_parameters(
	material: ShaderMaterial,
	square_enabled: bool = false,
	center_xz: Vector2 = Vector2.ZERO,
	begin_m: float = -1.0,
	end_m: float = -1.0
) -> void:
	var fog_begin: float = edge_fog_begin_m if begin_m < 0.0 else max(0.0, begin_m)
	var fog_end: float = edge_fog_end_m if end_m < 0.0 else max(fog_begin + 1.0, end_m)
	material.set_shader_parameter("edge_fog_enabled", use_edge_fog)
	material.set_shader_parameter("edge_fog_begin_m", fog_begin)
	material.set_shader_parameter("edge_fog_end_m", max(fog_begin + 1.0, fog_end))
	material.set_shader_parameter("edge_fog_color", Vector3(edge_fog_color.r, edge_fog_color.g, edge_fog_color.b))
	material.set_shader_parameter("edge_fog_square_enabled", square_enabled)
	material.set_shader_parameter("edge_fog_center_xz", center_xz)
