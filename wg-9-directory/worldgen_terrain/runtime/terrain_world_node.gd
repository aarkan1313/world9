class_name TerrainWorldNode
extends Node3D

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")
const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")
const TerrainNativeChunkPayloadWorkerScript := preload("res://worldgen_terrain/mesh/terrain_native_chunk_payload_worker.gd")
const TerrainGpuProviderChunkDescriptorWorkerScript := preload("res://worldgen_terrain/mesh/terrain_gpu_provider_chunk_descriptor_worker.gd")
const TerrainPageRequestScript := preload("res://worldgen_terrain/core/terrain_page_request.gd")
const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")
const TerrainGpuProviderPageTextureBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_provider_page_texture_backend.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainChunkRendererScript := preload("res://worldgen_terrain/runtime/terrain_chunk_renderer.gd")
const TerrainChunkPageRendererScript := preload("res://worldgen_terrain/runtime/terrain_chunk_page_renderer.gd")
const HydrologyTileCacheScript := preload("res://worldgen_terrain/hydrology/hydrology_tile_cache.gd")

@export_enum("procedural", "flat") var provider_mode: String = TerrainWorldScript.PROVIDER_PROCEDURAL
@export_enum("gray", "elevation_color", "chunk_id", "lod_ring", "height_bands", "seam", "family_palette", "hydrology", "surface_owner") var debug_mode: String = TerrainWorldScript.DEBUG_GRAY
@export var seed: int = 1337
@export var flat_height_m: float = 0.0
@export_range(17, 257, 16) var vertices_per_side: int = TerrainSettingsScript.LOD0_VERTICES_PER_SIDE
@export var auto_setup_on_ready: bool = true
@export var viewer_position_xz: Vector2 = Vector2.ZERO
@export var use_fast_gray_material: bool = false
@export var fast_gray_exposure: float = 1.0
@export var fast_gray_contrast: float = 1.0
@export var use_native_chunk_payloads: bool = false
@export var use_native_chunk_workers: bool = false
@export_range(1, 8, 1) var max_native_chunk_workers: int = 2
@export_range(1, 16, 1) var max_native_chunk_worker_results_per_update: int = 1
@export var use_gpu_page_chunks: bool = false
@export var use_gpu_provider_page_chunk_textures: bool = false
@export var use_gpu_provider_page_chunk_descriptor_staging: bool = false
@export var use_gpu_rd_chunk_page_textures: bool = false
@export var use_gpu_rd_chunk_compute_normals: bool = true
@export_range(1, 16, 1) var max_gpu_page_chunk_builds_per_update: int = 1
@export_range(1, 16, 1) var max_gpu_page_prefetch_chunk_builds_per_update: int = 2
@export_range(0, 1000, 1) var max_gpu_page_chunk_build_ms_per_update: int = 0
@export_range(0, 16, 1) var max_gpu_provider_chunk_descriptor_stages_per_update: int = 1
@export_range(1, 16, 1) var max_gpu_provider_chunk_descriptor_workers: int = 2
@export_range(0, 512, 1) var chunk_page_cache_max_pages: int = 96
@export_range(0, 512, 1) var chunk_gpu_page_residency_max_pages: int = 96
@export_range(0, 512, 1) var gpu_provider_chunk_descriptor_cache_max_entries: int = 96
@export var defer_inactive_chunk_retire_until_active_ready: bool = false
@export_range(0, 256, 1) var max_retained_inactive_chunk_nodes: int = 0
@export var use_lod_mesh_density: bool = false
@export var use_mesh_skirts: bool = false
@export var mesh_skirt_depth_m: float = 50.0
@export var use_lod_transition_morph: bool = true
@export_range(0, 16, 1) var lod_transition_band_cells: int = 4
@export var use_native_mesh_payloads: bool = false
@export var reuse_chunk_nodes: bool = true
@export_range(0, 256, 1) var max_pooled_chunk_nodes: int = 64
@export var use_edge_fog: bool = false
@export var edge_fog_begin_m: float = 24000.0
@export var edge_fog_end_m: float = 33000.0
@export var edge_fog_color: Color = Color(0.18, 0.18, 0.18)
@export var allow_profile_fallback_sync_rebuilds: bool = false

var world: RefCounted
var chunk_nodes: Dictionary = {}
var last_report: Dictionary = {}
var errors: Array[String] = []
var _active_info_by_key: Dictionary = {}
var _gray_material: ShaderMaterial
var _elevation_color_material: ShaderMaterial
var _hydrology_cache: RefCounted
var _chunk_renderer: RefCounted
var _native_backend: Object
var _recent_chunk_build_ms: Array[int] = []
var _total_chunk_builds: int = 0
var _last_chunk_build_ms: int = 0
var _last_height_grid_ms: int = 0
var _last_native_chunk_payload_ms: int = 0
var _last_native_mesh_payload_ms: int = 0
var _last_native_worker_elapsed_ms: int = 0
var _last_cpu_chunk_payload_ms: int = 0
var _last_mesh_normals_ms: int = 0
var _native_chunk_payload_count: int = 0
var _native_worker_payload_count: int = 0
var _cpu_chunk_payload_count: int = 0
var _max_recent_build_samples: int = 64
var _native_chunk_workers: Dictionary = {}
var _native_worker_requests: Dictionary = {}
var _native_worker_queue: Array[Dictionary] = []
var _native_worker_results_applied_this_update: int = 0
var _last_native_worker_results_applied: int = 0
var _chunk_page_renderer: RefCounted
var _chunk_gpu_provider_page_texture_backend: RefCounted
var _last_gpu_page_chunk_ms: int = 0
var _last_gpu_page_chunk_texture_ms: int = 0
var _gpu_page_chunk_count: int = 0
var _gpu_page_chunk_fallback_count: int = 0
var _last_gpu_page_chunk_error: String = ""
var _gpu_page_chunks_built_this_update: int = 0
var _gpu_page_prefetch_chunks_built_this_update: int = 0
var _gpu_page_chunk_ms_this_update: int = 0
var _gpu_provider_chunk_descriptor_cache: Dictionary = {}
var _gpu_provider_chunk_descriptor_lru: Array[String] = []
var _last_gpu_provider_chunk_descriptor_stages: int = 0
var _total_gpu_provider_chunk_descriptor_stages: int = 0
var _last_gpu_provider_chunk_descriptor_stage_ms: int = 0
var _last_gpu_provider_chunk_descriptor_worker_elapsed_ms: int = 0
var _last_gpu_provider_chunk_descriptor_error: String = ""
var _gpu_provider_chunk_descriptor_workers: Dictionary = {}
var _gpu_provider_chunk_descriptor_worker_requests: Dictionary = {}


func _ready() -> void:
	_ensure_chunk_renderer()
	if auto_setup_on_ready:
		setup_world(provider_mode, seed)
		update_viewer(viewer_position_xz)


func _exit_tree() -> void:
	_clear_native_chunk_workers(true)
	if _chunk_page_renderer != null:
		_chunk_page_renderer.call("clear")
	if _chunk_renderer != null:
		_chunk_renderer.call("clear_all")
	_clear_chunk_gpu_provider_texture_backend()
	_clear_gpu_provider_chunk_descriptor_workers(true)
	TerrainGpuProviderChunkDescriptorWorkerScript.cleanup_detached_workers(0, true, 5000)
	TerrainNativeChunkPayloadWorkerScript.cleanup_detached_workers(0, true, 5000)


func setup_world(mode: String = TerrainWorldScript.PROVIDER_PROCEDURAL, p_seed: int = 1337) -> bool:
	_ensure_chunk_renderer()
	clear_chunks()
	errors.clear()
	seed = p_seed
	provider_mode = mode
	world = TerrainWorldScript.new()
	if provider_mode == TerrainWorldScript.PROVIDER_FLAT:
		world.setup_flat(flat_height_m, seed)
	else:
		if not world.setup_procedural(seed):
			for error in world.errors:
				errors.append(str(error))
			return false
	_hydrology_cache = null
	world.set_debug_mode(debug_mode)
	return true


func update_viewer(position_xz: Vector2) -> Dictionary:
	TerrainNativeChunkPayloadWorkerScript.cleanup_detached_workers()
	TerrainGpuProviderChunkDescriptorWorkerScript.cleanup_detached_workers()
	_native_worker_results_applied_this_update = 0
	_last_native_worker_results_applied = 0
	_gpu_page_chunks_built_this_update = 0
	_gpu_page_prefetch_chunks_built_this_update = 0
	_gpu_page_chunk_ms_this_update = 0
	_last_gpu_provider_chunk_descriptor_stages = 0
	_last_gpu_provider_chunk_descriptor_stage_ms = 0
	_last_gpu_provider_chunk_descriptor_worker_elapsed_ms = 0
	if world == null:
		if not setup_world(provider_mode, seed):
			return {"status": "fail", "errors": errors}
	viewer_position_xz = position_xz
	last_report = world.update_viewer(position_xz)
	if last_report.get("status", "pass") != "pass":
		return last_report
	_refresh_active_info_index()
	_stage_gpu_provider_chunk_page_descriptors()
	_retag_full_density_chunk_nodes()
	_retire_inactive_chunk_nodes()
	_prune_streamer_queue_for_built_chunks()
	_prune_native_worker_queue()
	_poll_native_chunk_workers()
	_build_queued_chunks(last_report.get("build_now", []) as Array)
	_poll_native_chunk_workers()
	_prune_streamer_queue_for_built_chunks()
	_sync_chunk_visibility_for_runtime_window()
	_update_chunk_page_protected_keys()
	return last_report


func apply_debug_mode(mode: String) -> void:
	var previous_mode: String = debug_mode
	debug_mode = mode
	if world != null:
		world.set_debug_mode(mode)
	if not _can_use_native_chunk_workers():
		_clear_native_chunk_workers(true)
	if _mode_requires_vertex_rebuild(previous_mode) or _mode_requires_vertex_rebuild(mode):
		_rebuild_existing_chunk_meshes()
	refresh_debug_materials()


func set_stream_priority_direction(direction: Vector2) -> void:
	if world != null and world.has_method("set_stream_priority_direction"):
		world.call("set_stream_priority_direction", direction)


func apply_landform_profile(profile: Variant, rebuild_existing: bool = true) -> bool:
	if world == null or not world.has_method("apply_landform_profile"):
		return false
	var ok: bool = bool(world.call("apply_landform_profile", profile))
	if ok:
		_clear_native_chunk_workers(true)
		if rebuild_existing:
			if _profile_disables_native_grid() and not allow_profile_fallback_sync_rebuilds:
				_queue_active_chunks_for_rebuild()
			else:
				_rebuild_existing_chunk_meshes()
		else:
			_queue_active_chunks_for_rebuild()
	return ok


func clear_native_worker_backlog_for_preview() -> void:
	_clear_native_chunk_workers(true)


func rebuild_all_active_for_preview(max_chunks: int = 0) -> int:
	if world == null or last_report.is_empty():
		update_viewer(viewer_position_xz)
	var built := 0
	for item_value in last_report.get("active_chunks", []) as Array:
		if max_chunks > 0 and built >= max_chunks:
			break
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var key: String = _chunk_key(chunk_x, chunk_z)
		_remove_streamer_queued_build_for_key(key)
		_remove_queued_native_worker_for_key(key)
		var allow_sync_staged_provider: bool = _can_use_staged_gpu_provider_chunk_pages()
		if allow_sync_staged_provider:
			_finish_staged_gpu_provider_chunk_descriptor(chunk_x, chunk_z, int(item["ring"]), int(item["lod"]))
		if _build_or_update_chunk_node(key, chunk_x, chunk_z, int(item["ring"]), int(item["lod"]), allow_sync_staged_provider):
			built += 1
	_sync_chunk_visibility_for_runtime_window()
	return built


func rebuild_nearby_for_preview(radius_chunks: int = 2) -> int:
	if world == null or last_report.is_empty():
		update_viewer(viewer_position_xz)
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var items: Array[Dictionary] = []
	for item_value in last_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var dx: int = abs(int(item["chunk_x"]) - center_x)
		var dz: int = abs(int(item["chunk_z"]) - center_z)
		if max(dx, dz) <= radius_chunks:
			items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax: int = abs(int(a["chunk_x"]) - center_x)
		var az: int = abs(int(a["chunk_z"]) - center_z)
		var bx: int = abs(int(b["chunk_x"]) - center_x)
		var bz: int = abs(int(b["chunk_z"]) - center_z)
		var ar: int = max(ax, az)
		var br: int = max(bx, bz)
		if ar != br:
			return ar < br
		var ad: int = ax + az
		var bd: int = bx + bz
		if ad != bd:
			return ad < bd
		if int(a["chunk_z"]) != int(b["chunk_z"]):
			return int(a["chunk_z"]) < int(b["chunk_z"])
		return int(a["chunk_x"]) < int(b["chunk_x"])
	)
	var built := 0
	for item in items:
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var key: String = _chunk_key(chunk_x, chunk_z)
		_remove_streamer_queued_build_for_key(key)
		_remove_queued_native_worker_for_key(key)
		if _build_or_update_chunk_node(key, chunk_x, chunk_z, int(item["ring"]), int(item["lod"])):
			built += 1
	_sync_chunk_visibility_for_runtime_window()
	return built


func build_missing_nearby_for_preview(radius_chunks: int = 2, max_chunks: int = 0) -> int:
	if world == null or last_report.is_empty():
		update_viewer(viewer_position_xz)
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var missing_items: Array[Dictionary] = []
	var stale_items: Array[Dictionary] = []
	for item_value in last_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var dx: int = abs(int(item["chunk_x"]) - center_x)
		var dz: int = abs(int(item["chunk_z"]) - center_z)
		if max(dx, dz) <= radius_chunks:
			var key: String = _chunk_key(int(item["chunk_x"]), int(item["chunk_z"]))
			if not chunk_nodes.has(key):
				missing_items.append(item)
			elif not _chunk_node_matches_active_info(key, item):
				stale_items.append(item)
	_sort_preview_fill_items(missing_items, center_x, center_z)
	_sort_preview_fill_items(stale_items, center_x, center_z)
	var items: Array[Dictionary] = []
	items.append_array(missing_items)
	items.append_array(stale_items)
	var built := 0
	for item in items:
		if max_chunks > 0 and built >= max_chunks:
			break
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var ring: int = int(item["ring"])
		var lod: int = int(item["lod"])
		var key: String = _chunk_key(chunk_x, chunk_z)
		if _chunk_node_matches_active_info(key, item):
			continue
		_remove_streamer_queued_build_for_key(key)
		_remove_queued_native_worker_for_key(key)
		var allow_sync_staged_provider := false
		if _build_or_update_chunk_node(key, chunk_x, chunk_z, ring, lod, allow_sync_staged_provider):
			built += 1
	_sync_chunk_visibility_for_runtime_window()
	return built


func _sort_preview_fill_items(items: Array[Dictionary], center_x: int, center_z: int) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax: int = abs(int(a["chunk_x"]) - center_x)
		var az: int = abs(int(a["chunk_z"]) - center_z)
		var bx: int = abs(int(b["chunk_x"]) - center_x)
		var bz: int = abs(int(b["chunk_z"]) - center_z)
		var ar: int = max(ax, az)
		var br: int = max(bx, bz)
		if ar != br:
			return ar < br
		var ad: int = ax + az
		var bd: int = bx + bz
		if ad != bd:
			return ad < bd
		if int(a["chunk_z"]) != int(b["chunk_z"]):
			return int(a["chunk_z"]) < int(b["chunk_z"])
		return int(a["chunk_x"]) < int(b["chunk_x"])
	)


func clear_chunks() -> void:
	_ensure_chunk_renderer()
	_clear_native_chunk_workers()
	_chunk_renderer.call("clear_all")
	if _chunk_page_renderer != null:
		_chunk_page_renderer.call("clear")
	_clear_chunk_gpu_provider_texture_backend()
	_recent_chunk_build_ms.clear()
	_active_info_by_key.clear()
	_total_chunk_builds = 0
	_last_chunk_build_ms = 0
	_last_height_grid_ms = 0
	_last_native_chunk_payload_ms = 0
	_last_native_mesh_payload_ms = 0
	_last_native_worker_elapsed_ms = 0
	_last_cpu_chunk_payload_ms = 0
	_last_mesh_normals_ms = 0
	_native_chunk_payload_count = 0
	_native_worker_payload_count = 0
	_cpu_chunk_payload_count = 0
	_last_gpu_page_chunk_ms = 0
	_last_gpu_page_chunk_texture_ms = 0
	_gpu_page_chunk_count = 0
	_gpu_page_chunk_fallback_count = 0
	_last_gpu_page_chunk_error = ""
	_gpu_page_chunks_built_this_update = 0
	_gpu_page_prefetch_chunks_built_this_update = 0
	_gpu_page_chunk_ms_this_update = 0
	_gpu_provider_chunk_descriptor_cache.clear()
	_gpu_provider_chunk_descriptor_lru.clear()
	_clear_gpu_provider_chunk_descriptor_workers(true)
	_last_gpu_provider_chunk_descriptor_stages = 0
	_total_gpu_provider_chunk_descriptor_stages = 0
	_last_gpu_provider_chunk_descriptor_stage_ms = 0
	_last_gpu_provider_chunk_descriptor_worker_elapsed_ms = 0
	_last_gpu_provider_chunk_descriptor_error = ""


func _clear_chunk_gpu_provider_texture_backend() -> void:
	if _chunk_gpu_provider_page_texture_backend == null:
		return
	if RenderingServer.has_method("get_rendering_device"):
		var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
		_chunk_gpu_provider_page_texture_backend.call("clear", rd)


func built_chunk_count() -> int:
	_ensure_chunk_renderer()
	return int(_chunk_renderer.call("built_chunk_count"))


func pooled_chunk_count() -> int:
	_ensure_chunk_renderer()
	return int(_chunk_renderer.call("pooled_chunk_count"))


func build_stats() -> Dictionary:
	var total_recent := 0
	var max_recent := 0
	for value in _recent_chunk_build_ms:
		total_recent += value
		max_recent = max(max_recent, value)
	var recent_count: int = _recent_chunk_build_ms.size()
	return {
		"active_chunks": chunk_nodes.size(),
		"visible_chunk_count": _visible_chunk_count(),
		"standby_chunk_count": _standby_chunk_count(),
		"active_missing_chunk_count": _active_missing_chunk_count(),
		"retained_inactive_chunk_count": _retained_inactive_chunk_count(),
		"pooled_chunks": pooled_chunk_count(),
		"child_nodes": get_child_count(),
		"total_chunk_builds": _total_chunk_builds,
		"recent_build_count": recent_count,
		"last_chunk_build_ms": _last_chunk_build_ms,
		"last_height_grid_ms": _last_height_grid_ms,
		"last_native_chunk_payload_ms": _last_native_chunk_payload_ms,
		"last_native_mesh_payload_ms": _last_native_mesh_payload_ms,
		"last_native_worker_elapsed_ms": _last_native_worker_elapsed_ms,
		"last_cpu_chunk_payload_ms": _last_cpu_chunk_payload_ms,
		"last_mesh_normals_ms": _last_mesh_normals_ms,
		"native_chunk_payload_count": _native_chunk_payload_count,
		"native_worker_payload_count": _native_worker_payload_count,
		"cpu_chunk_payload_count": _cpu_chunk_payload_count,
		"active_native_workers": _native_chunk_workers.size(),
		"queued_native_worker_builds": _native_worker_queue.size(),
		"last_native_worker_results_applied": _last_native_worker_results_applied,
		"max_native_chunk_worker_results_per_update": max_native_chunk_worker_results_per_update,
		"use_gpu_page_chunks": use_gpu_page_chunks,
		"gpu_page_chunk_count": _gpu_page_chunk_count,
		"gpu_page_chunk_fallback_count": _gpu_page_chunk_fallback_count,
		"last_gpu_page_chunk_ms": _last_gpu_page_chunk_ms,
		"last_gpu_page_chunk_texture_ms": _last_gpu_page_chunk_texture_ms,
		"last_gpu_page_chunk_error": _last_gpu_page_chunk_error,
		"last_gpu_page_chunks_built": _gpu_page_chunks_built_this_update,
		"last_gpu_page_prefetch_chunks_built": _gpu_page_prefetch_chunks_built_this_update,
		"gpu_page_chunk_ms_this_update": _gpu_page_chunk_ms_this_update,
		"max_gpu_page_chunk_builds_per_update": max_gpu_page_chunk_builds_per_update,
		"max_gpu_page_prefetch_chunk_builds_per_update": max_gpu_page_prefetch_chunk_builds_per_update,
		"max_gpu_page_chunk_build_ms_per_update": max_gpu_page_chunk_build_ms_per_update,
		"use_gpu_provider_page_chunk_descriptor_staging": use_gpu_provider_page_chunk_descriptor_staging,
		"gpu_provider_chunk_descriptor_cache_count": _gpu_provider_chunk_descriptor_cache.size(),
		"last_gpu_provider_chunk_descriptor_stages": _last_gpu_provider_chunk_descriptor_stages,
		"total_gpu_provider_chunk_descriptor_stages": _total_gpu_provider_chunk_descriptor_stages,
		"last_gpu_provider_chunk_descriptor_stage_ms": _last_gpu_provider_chunk_descriptor_stage_ms,
		"last_gpu_provider_chunk_descriptor_worker_elapsed_ms": _last_gpu_provider_chunk_descriptor_worker_elapsed_ms,
		"active_gpu_provider_chunk_descriptor_workers": _gpu_provider_chunk_descriptor_workers.size(),
		"max_gpu_provider_chunk_descriptor_workers": max_gpu_provider_chunk_descriptor_workers,
		"last_gpu_provider_chunk_descriptor_error": _last_gpu_provider_chunk_descriptor_error,
		"chunk_gpu_page_residency": _chunk_gpu_page_residency_state(),
		"chunk_gpu_provider_page_texture_backend": _chunk_gpu_provider_texture_backend_state(),
		"avg_recent_chunk_build_ms": float(total_recent) / float(max(1, recent_count)),
		"max_recent_chunk_build_ms": max_recent,
	}


func active_missing_chunk_count(radius_chunks: int = -1) -> int:
	return _active_missing_chunk_count(radius_chunks)


func surface_provenance() -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	var keys: Array[String] = []
	for key_value in chunk_nodes.keys():
		keys.append(str(key_value))
	keys.sort()
	for key in keys:
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		if mesh_instance == null:
			continue
		var chunk_x: int = int(mesh_instance.get_meta("chunk_x", 0))
		var chunk_z: int = int(mesh_instance.get_meta("chunk_z", 0))
		var ring: int = int(mesh_instance.get_meta("ring", -1))
		var lod: int = int(mesh_instance.get_meta("lod", -1))
		var material: Material = mesh_instance.material_override
		surfaces.append({
			"owner": "near_chunk",
			"node": mesh_instance.name,
			"key": key,
			"chunk_x": chunk_x,
			"chunk_z": chunk_z,
			"ring": ring,
			"lod": lod,
			"payload_mode": "gpu_page_chunk" if bool(mesh_instance.get_meta("gpu_page_chunk", false)) else _near_chunk_payload_mode(),
			"debug_mode": debug_mode,
			"material_mode": _material_mode(material),
			"height_texture_valid": _shader_texture_valid(material, "height_texture"),
			"normal_texture_valid": _shader_texture_valid(material, "normal_texture"),
			"custom_aabb": _aabb_dictionary(mesh_instance.custom_aabb),
			"global_position": _vec3_array(mesh_instance.global_position),
			"visible": mesh_instance.visible,
			"loaded": mesh_instance.mesh != null,
			"resident": chunk_nodes.has(key),
			"mesh": _mesh_summary(mesh_instance.mesh),
		})
	return surfaces


func refresh_debug_materials() -> void:
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		var chunk_x: int = int(mesh_instance.get_meta("chunk_x"))
		var chunk_z: int = int(mesh_instance.get_meta("chunk_z"))
		var ring: int = int(mesh_instance.get_meta("ring"))
		var lod: int = int(mesh_instance.get_meta("lod"))
		if bool(mesh_instance.get_meta("gpu_page_chunk", false)) and _can_use_gpu_page_chunks():
			_build_or_update_chunk_node(key, chunk_x, chunk_z, ring, lod)
			continue
		mesh_instance.material_override = _material_for_chunk(chunk_x, chunk_z, ring, lod)


func apply_edge_fog(enabled: bool, begin_m: float, end_m: float, color: Color) -> void:
	use_edge_fog = enabled
	edge_fog_begin_m = max(0.0, begin_m)
	edge_fog_end_m = max(edge_fog_begin_m + 1.0, end_m)
	edge_fog_color = color
	if _gray_material != null:
		_apply_edge_fog_shader_parameters(_gray_material)


func _build_queued_chunks(build_now: Array) -> void:
	var items_to_build: Array = build_now
	if _can_use_staged_gpu_provider_chunk_pages():
		items_to_build = _ready_staged_gpu_provider_build_items(build_now)
	for coord_value in items_to_build:
		var coord: Array = coord_value as Array
		var chunk_x: int = int(coord[0])
		var chunk_z: int = int(coord[1])
		var key: String = _chunk_key(chunk_x, chunk_z)
		var active_info: Dictionary = _active_info_for_key(key)
		if active_info.is_empty():
			continue
		if _chunk_node_matches_active_info(key, active_info):
			continue
		var is_visible_runtime_chunk: bool = _active_info_in_visible_runtime_window(active_info)
		if not is_visible_runtime_chunk and _gpu_page_prefetch_update_budget_exhausted():
			_requeue_streamer_build_key(key)
			continue
		if _can_use_staged_gpu_provider_chunk_pages() and _staged_gpu_provider_chunk_descriptor_ready(chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"])):
			if _gpu_page_chunk_update_budget_exhausted():
				_requeue_streamer_build_key(key)
				continue
			_build_or_update_chunk_node(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
			if not is_visible_runtime_chunk:
				_gpu_page_prefetch_chunks_built_this_update += 1
			continue
		if _can_use_staged_gpu_provider_chunk_pages():
			_defer_staged_gpu_provider_chunk_build(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
			continue
		if _can_use_gpu_page_chunks() and _can_use_native_chunk_workers():
			_enqueue_native_worker_build(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
			continue
		if _can_use_gpu_page_chunks():
			if _gpu_page_chunk_update_budget_exhausted():
				_requeue_streamer_build_key(key)
				continue
			_build_or_update_chunk_node(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
			if not is_visible_runtime_chunk:
				_gpu_page_prefetch_chunks_built_this_update += 1
			continue
		if _can_use_native_chunk_workers():
			_enqueue_native_worker_build(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
			continue
		_build_or_update_chunk_node(key, chunk_x, chunk_z, int(active_info["ring"]), int(active_info["lod"]))
	_pump_native_worker_queue()


func _ready_staged_gpu_provider_build_items(build_now: Array) -> Array:
	if world == null or world.streamer == null:
		return build_now
	var target_count: int = max(1, build_now.size())
	var queue: Array[String] = []
	for key_value in world.streamer.queued_builds:
		var queued_key: String = str(key_value)
		if not queued_key.is_empty() and not queue.has(queued_key):
			queue.append(queued_key)
	for coord_value in build_now:
		var coord: Array = coord_value as Array
		if coord.size() < 2:
			continue
		var key: String = _chunk_key(int(coord[0]), int(coord[1]))
		if not queue.has(key):
			queue.append(key)
	_sort_streamer_build_keys_by_runtime_priority(queue)
	var selected: Array = []
	var retained: Array[String] = []
	for key in queue:
		var active_info: Dictionary = _active_info_for_key(key)
		if active_info.is_empty():
			continue
		var ready := _staged_gpu_provider_chunk_descriptor_ready(
			int(active_info["chunk_x"]),
			int(active_info["chunk_z"]),
			int(active_info["ring"]),
			int(active_info["lod"])
		)
		if ready and selected.size() < target_count:
			selected.append([int(active_info["chunk_x"]), int(active_info["chunk_z"])])
		else:
			retained.append(key)
	world.streamer.queued_builds = retained
	return selected


func _sort_streamer_build_keys_by_runtime_priority(keys: Array[String]) -> void:
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var direction := Vector2.ZERO
	if world != null and world.streamer != null:
		direction = world.streamer.priority_direction
	keys.sort_custom(func(a: String, b: String) -> bool:
		var a_info: Dictionary = _active_info_for_key(a)
		var b_info: Dictionary = _active_info_for_key(b)
		if a_info.is_empty() != b_info.is_empty():
			return not a_info.is_empty()
		var ar: int = int(a_info.get("ring", 9999))
		var br: int = int(b_info.get("ring", 9999))
		var a_ready := false
		var b_ready := false
		if not a_info.is_empty():
			a_ready = _staged_gpu_provider_chunk_descriptor_ready(
				int(a_info["chunk_x"]),
				int(a_info["chunk_z"]),
				int(a_info["ring"]),
				int(a_info["lod"])
			)
		if not b_info.is_empty():
			b_ready = _staged_gpu_provider_chunk_descriptor_ready(
				int(b_info["chunk_x"]),
				int(b_info["chunk_z"]),
				int(b_info["ring"]),
				int(b_info["lod"])
			)
		if a_ready != b_ready:
			return a_ready
		if ar != br:
			return ar < br
		var alod: int = int(a_info.get("lod", 9999))
		var blod: int = int(b_info.get("lod", 9999))
		if alod != blod:
			return alod < blod
		var ax: int = int(a_info.get("chunk_x", _key_x(a)))
		var az: int = int(a_info.get("chunk_z", _key_z(a)))
		var bx: int = int(b_info.get("chunk_x", _key_x(b)))
		var bz: int = int(b_info.get("chunk_z", _key_z(b)))
		var aahead := 0.0
		var bahead := 0.0
		if direction.length_squared() > 0.000001:
			aahead = Vector2(float(ax - center_x), float(az - center_z)).dot(direction)
			bahead = Vector2(float(bx - center_x), float(bz - center_z)).dot(direction)
		if not is_equal_approx(aahead, bahead):
			return aahead > bahead
		var ad: int = abs(ax - center_x) + abs(az - center_z)
		var bd: int = abs(bx - center_x) + abs(bz - center_z)
		if ad != bd:
			return ad < bd
		if az != bz:
			return az < bz
		return ax < bx
	)


func _build_or_update_chunk_node(
	key: String,
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	allow_sync_staged_provider: bool = false
) -> bool:
	_ensure_chunk_renderer()
	if (
		_can_use_staged_gpu_provider_chunk_pages()
		and not allow_sync_staged_provider
		and not _staged_gpu_provider_chunk_descriptor_ready(chunk_x, chunk_z, ring, lod)
	):
		_defer_staged_gpu_provider_chunk_build(key, chunk_x, chunk_z, ring, lod)
		return false
	var build_start_ms: int = Time.get_ticks_msec()
	if _can_use_gpu_page_chunks() and _try_apply_gpu_page_chunk(key, chunk_x, chunk_z, ring, lod, allow_sync_staged_provider):
		_record_chunk_build_time(Time.get_ticks_msec() - build_start_ms)
		_gpu_page_chunk_count += 1
		_gpu_page_chunks_built_this_update += 1
		_gpu_page_chunk_ms_this_update += _last_gpu_page_chunk_ms
		return true
	var mesh: ArrayMesh = _build_chunk_mesh(chunk_x, chunk_z, ring, lod)
	_record_chunk_build_time(Time.get_ticks_msec() - build_start_ms)
	var mesh_instance: MeshInstance3D = _chunk_renderer.call(
		"apply_chunk",
		key,
		chunk_x,
		chunk_z,
		ring,
		lod,
		world.chunk_size_m,
		mesh,
		_material_for_chunk(chunk_x, chunk_z, ring, lod)
	) as MeshInstance3D
	if mesh_instance != null:
		mesh_instance.set_meta("gpu_page_chunk", false)
	return mesh_instance != null


func _gpu_page_chunk_update_budget_exhausted() -> bool:
	if _gpu_page_chunks_built_this_update >= max(1, max_gpu_page_chunk_builds_per_update):
		return true
	if max_gpu_page_chunk_build_ms_per_update <= 0:
		return false
	return (
		_gpu_page_chunks_built_this_update > 0
		and _gpu_page_chunk_ms_this_update >= max_gpu_page_chunk_build_ms_per_update
	)


func _gpu_page_prefetch_update_budget_exhausted() -> bool:
	return _gpu_page_prefetch_chunks_built_this_update >= max(1, max_gpu_page_prefetch_chunk_builds_per_update)


func _defer_staged_gpu_provider_chunk_build(key: String, chunk_x: int, chunk_z: int, ring: int, lod: int) -> void:
	_requeue_streamer_build_key(key)


func _try_apply_gpu_page_chunk(
	key: String,
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	allow_sync_staged_provider: bool = false
) -> bool:
	var descriptor: Dictionary = _gpu_page_chunk_descriptor(chunk_x, chunk_z, ring, lod, allow_sync_staged_provider)
	if descriptor.get("status", "fail") != "pass":
		_gpu_page_chunk_fallback_count += 1
		_last_gpu_page_chunk_error = str(descriptor.get("error", "descriptor_failed"))
		return false
	var applied: Dictionary = _ensure_chunk_page_renderer().call(
		"apply_descriptor",
		_chunk_renderer,
		key,
		chunk_x,
		chunk_z,
		ring,
		lod,
		world.chunk_size_m,
		descriptor
	) as Dictionary
	_last_gpu_page_chunk_texture_ms = int(applied.get("texture_ms", 0))
	if applied.get("status", "fail") != "pass":
		_gpu_page_chunk_fallback_count += 1
		_last_gpu_page_chunk_error = str(applied.get("error", "apply_failed"))
		return false
	_last_gpu_page_chunk_error = ""
	_last_gpu_page_chunk_ms = int(descriptor.get("build_ms", 0)) + _last_gpu_page_chunk_texture_ms
	return true


func _chunk_page_request(chunk_x: int, chunk_z: int, ring: int, lod: int, count: int, chunk_size: float) -> RefCounted:
	return TerrainPageRequestScript.from_chunk(
		chunk_x,
		chunk_z,
		chunk_size,
		count,
		int(world.seed),
		"near_chunk_height",
		_chunk_page_quality_profile(lod),
		_chunk_page_feature_flags(ring, lod),
		{
			"ring": ring,
			"lod": lod,
			"debug_mode": debug_mode,
		}
	)


func _stage_gpu_provider_chunk_page_descriptors() -> void:
	if not _can_use_staged_gpu_provider_chunk_pages() or last_report.is_empty():
		return
	var started_ms: int = Time.get_ticks_msec()
	var completed: int = _poll_gpu_provider_chunk_descriptor_workers()
	var budget: int = max(0, max_gpu_provider_chunk_descriptor_stages_per_update)
	if budget <= 0:
		_last_gpu_provider_chunk_descriptor_stages = completed
		if completed > 0:
			_total_gpu_provider_chunk_descriptor_stages += completed
			_last_gpu_provider_chunk_descriptor_stage_ms = Time.get_ticks_msec() - started_ms
		return
	var queued := 0
	var queued_prefetch := 0
	var items: Array = (last_report.get("active_chunks", []) as Array).duplicate(true)
	_sort_stream_items_by_runtime_priority(items)
	for item_value in items:
		if queued >= budget:
			break
		if _gpu_provider_chunk_descriptor_workers.size() >= max(1, max_gpu_provider_chunk_descriptor_workers):
			break
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item.get("chunk_x", 0))
		var chunk_z: int = int(item.get("chunk_z", 0))
		var ring: int = int(item.get("ring", 0))
		var lod: int = int(item.get("lod", 0))
		var key: String = _chunk_key(chunk_x, chunk_z)
		if _chunk_node_matches_active_info(key, item):
			continue
		var is_visible_runtime_chunk: bool = _active_info_in_visible_runtime_window(item)
		if not is_visible_runtime_chunk and queued_prefetch >= max(1, max_gpu_page_prefetch_chunk_builds_per_update):
			continue
		if _stage_gpu_provider_chunk_page_descriptor(chunk_x, chunk_z, ring, lod):
			queued += 1
			if not is_visible_runtime_chunk:
				queued_prefetch += 1
	_last_gpu_provider_chunk_descriptor_stages = completed
	if completed > 0:
		_total_gpu_provider_chunk_descriptor_stages += completed
		_last_gpu_provider_chunk_descriptor_stage_ms = Time.get_ticks_msec() - started_ms


func _sort_stream_items_by_runtime_priority(items: Array) -> void:
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var direction := Vector2.ZERO
	if world != null and world.streamer != null:
		direction = world.streamer.priority_direction
	items.sort_custom(func(a_value: Variant, b_value: Variant) -> bool:
		var a: Dictionary = a_value as Dictionary
		var b: Dictionary = b_value as Dictionary
		var ax: int = int(a.get("chunk_x", 0))
		var az: int = int(a.get("chunk_z", 0))
		var bx: int = int(b.get("chunk_x", 0))
		var bz: int = int(b.get("chunk_z", 0))
		var ar: int = max(abs(ax - center_x), abs(az - center_z))
		var br: int = max(abs(bx - center_x), abs(bz - center_z))
		if ar != br:
			return ar < br
		var alod: int = int(a.get("lod", 0))
		var blod: int = int(b.get("lod", 0))
		if alod != blod:
			return alod < blod
		var a_stream_ring: int = int(a.get("ring", ar))
		var b_stream_ring: int = int(b.get("ring", br))
		if a_stream_ring != b_stream_ring:
			return a_stream_ring < b_stream_ring
		var aahead := 0.0
		var bahead := 0.0
		if direction.length_squared() > 0.000001:
			aahead = Vector2(float(ax - center_x), float(az - center_z)).dot(direction)
			bahead = Vector2(float(bx - center_x), float(bz - center_z)).dot(direction)
		if not is_equal_approx(aahead, bahead):
			return aahead > bahead
		var ad: int = abs(ax - center_x) + abs(az - center_z)
		var bd: int = abs(bx - center_x) + abs(bz - center_z)
		if ad != bd:
			return ad < bd
		if az != bz:
			return az < bz
		return ax < bx
	)


func _stage_gpu_provider_chunk_page_descriptor(chunk_x: int, chunk_z: int, ring: int, lod: int) -> bool:
	var count: int = _vertices_for_lod(lod)
	if count < 2:
		_last_gpu_provider_chunk_descriptor_error = "vertices_per_side:%d" % count
		return false
	var chunk_size: float = float(world.chunk_size_m)
	var step_m: float = chunk_size / float(count - 1)
	if not is_finite(step_m) or step_m <= 0.0:
		_last_gpu_provider_chunk_descriptor_error = "step_m:%f" % step_m
		return false
	var request = _chunk_page_request(chunk_x, chunk_z, ring, lod, count, chunk_size)
	var validation: String = request.validate()
	if not validation.is_empty():
		_last_gpu_provider_chunk_descriptor_error = "request:%s" % validation
		return false
	var cache_key: String = request.cache_key()
	if _gpu_provider_chunk_descriptor_cache.has(cache_key):
		_touch_gpu_provider_chunk_descriptor(cache_key)
		return false
	if _gpu_provider_chunk_descriptor_workers.has(cache_key):
		return false
	var origin := Vector2(float(chunk_x) * chunk_size, float(chunk_z) * chunk_size)
	var blocks: Array = _gpu_provider_chunk_page_blocks(origin, step_m, count)
	if blocks.is_empty():
		_last_gpu_provider_chunk_descriptor_error = "prepared_blocks_empty"
		return false
	var first_block: Dictionary = blocks[0] as Dictionary
	if first_block.get("status", "pass") != "pass":
		_last_gpu_provider_chunk_descriptor_error = "prepared:%s" % str(first_block.get("error", "fail"))
		return false
	var worker_request := {
		"cache_key": cache_key,
		"blocks": blocks,
		"step_m": step_m,
		"count": count,
		"world_seed": int(world.seed),
		"region_size_m": float(world.region_size_m),
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": ring,
		"lod": lod,
		"vertices_per_side": count,
	}
	var worker: RefCounted = TerrainGpuProviderChunkDescriptorWorkerScript.new()
	if not bool(worker.call("start", worker_request)):
		_last_gpu_provider_chunk_descriptor_error = "worker_start_failed"
		return false
	_gpu_provider_chunk_descriptor_workers[cache_key] = worker
	_gpu_provider_chunk_descriptor_worker_requests[cache_key] = worker_request
	_last_gpu_provider_chunk_descriptor_error = ""
	return true


func _poll_gpu_provider_chunk_descriptor_workers() -> int:
	var completed := 0
	var keys: Array = _gpu_provider_chunk_descriptor_workers.keys()
	for key_value in keys:
		var cache_key: String = str(key_value)
		var worker: RefCounted = _gpu_provider_chunk_descriptor_workers.get(cache_key) as RefCounted
		if worker == null:
			_gpu_provider_chunk_descriptor_workers.erase(cache_key)
			_gpu_provider_chunk_descriptor_worker_requests.erase(cache_key)
			continue
		if not bool(worker.call("is_done")):
			continue
		var result: Dictionary = worker.call("take_result") as Dictionary
		var request: Dictionary = _gpu_provider_chunk_descriptor_worker_requests.get(cache_key, {}) as Dictionary
		_gpu_provider_chunk_descriptor_workers.erase(cache_key)
		_gpu_provider_chunk_descriptor_worker_requests.erase(cache_key)
		if not _store_gpu_provider_chunk_descriptor_result(cache_key, request, result):
			continue
		completed += 1
	return completed


func _finish_staged_gpu_provider_chunk_descriptor(chunk_x: int, chunk_z: int, ring: int, lod: int) -> bool:
	if not _can_use_staged_gpu_provider_chunk_pages():
		return false
	var count: int = _vertices_for_lod(lod)
	if count < 2:
		return false
	var request = _chunk_page_request(chunk_x, chunk_z, ring, lod, count, float(world.chunk_size_m))
	if not request.validate().is_empty():
		return false
	var cache_key: String = request.cache_key()
	if _gpu_provider_chunk_descriptor_cache.has(cache_key):
		return true
	var worker: RefCounted = _gpu_provider_chunk_descriptor_workers.get(cache_key) as RefCounted
	if worker == null:
		return false
	var worker_request: Dictionary = _gpu_provider_chunk_descriptor_worker_requests.get(cache_key, {}) as Dictionary
	var result: Dictionary = {}
	if bool(worker.call("is_done")):
		result = worker.call("take_result") as Dictionary
	else:
		result = worker.call("wait_for_result", 5000) as Dictionary
	_gpu_provider_chunk_descriptor_workers.erase(cache_key)
	_gpu_provider_chunk_descriptor_worker_requests.erase(cache_key)
	return _store_gpu_provider_chunk_descriptor_result(cache_key, worker_request, result)


func _store_gpu_provider_chunk_descriptor_result(cache_key: String, request: Dictionary, result: Dictionary) -> bool:
	_last_gpu_provider_chunk_descriptor_worker_elapsed_ms = int(result.get("worker_elapsed_ms", 0))
	if result.get("status", "fail") != "pass":
		_last_gpu_provider_chunk_descriptor_error = "worker:%s" % str(result.get("error", "fail"))
		return false
	var descriptor_blocks: Array = result.get("descriptor_blocks", []) as Array
	if descriptor_blocks.is_empty():
		_last_gpu_provider_chunk_descriptor_error = "worker_descriptor_blocks_empty"
		return false
	_gpu_provider_chunk_descriptor_cache[cache_key] = {
		"blocks": request.get("blocks", []) as Array,
		"descriptor_blocks": descriptor_blocks,
		"chunk_x": int(request.get("chunk_x", 0)),
		"chunk_z": int(request.get("chunk_z", 0)),
		"ring": int(request.get("ring", 0)),
		"lod": int(request.get("lod", 0)),
		"vertices_per_side": int(request.get("vertices_per_side", 0)),
	}
	_touch_gpu_provider_chunk_descriptor(cache_key)
	_trim_gpu_provider_chunk_descriptor_cache()
	_last_gpu_provider_chunk_descriptor_error = ""
	return true


func _staged_gpu_provider_chunk_descriptor_ready(chunk_x: int, chunk_z: int, ring: int, lod: int) -> bool:
	if not _can_use_staged_gpu_provider_chunk_pages():
		return false
	var count: int = _vertices_for_lod(lod)
	if count < 2:
		return false
	var request = _chunk_page_request(chunk_x, chunk_z, ring, lod, count, float(world.chunk_size_m))
	if not request.validate().is_empty():
		return false
	return _gpu_provider_chunk_descriptor_cache.has(request.cache_key())


func _touch_gpu_provider_chunk_descriptor(cache_key: String) -> void:
	var existing: int = _gpu_provider_chunk_descriptor_lru.find(cache_key)
	if existing >= 0:
		_gpu_provider_chunk_descriptor_lru.remove_at(existing)
	_gpu_provider_chunk_descriptor_lru.append(cache_key)


func _trim_gpu_provider_chunk_descriptor_cache() -> void:
	var max_entries: int = max(1, gpu_provider_chunk_descriptor_cache_max_entries)
	while _gpu_provider_chunk_descriptor_cache.size() > max_entries and not _gpu_provider_chunk_descriptor_lru.is_empty():
		var oldest: String = _gpu_provider_chunk_descriptor_lru.pop_front()
		_gpu_provider_chunk_descriptor_cache.erase(oldest)


func _gpu_page_chunk_descriptor(
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	allow_sync_staged_provider: bool = false
) -> Dictionary:
	if world == null or world.provider == null:
		return {"status": "fail", "error": "world_not_ready"}
	var count: int = _vertices_for_lod(lod)
	if count < 2:
		return {"status": "fail", "error": "vertices_per_side:%d" % count}
	var chunk_size: float = float(world.chunk_size_m)
	var step_m: float = chunk_size / float(count - 1)
	if not is_finite(step_m) or step_m <= 0.0:
		return {"status": "fail", "error": "step_m:%f" % step_m}
	var origin := Vector2(float(chunk_x) * chunk_size, float(chunk_z) * chunk_size)
	var request = _chunk_page_request(chunk_x, chunk_z, ring, lod, count, chunk_size)
	var validation: String = request.validate()
	if not validation.is_empty():
		return {"status": "fail", "error": "request:%s" % validation}
	var cache_key: String = request.cache_key()
	var build_start_ms: int = Time.get_ticks_msec()
	var result: Dictionary = {}
	if use_gpu_provider_page_chunk_textures:
		if _chunk_page_renderer_has_page(cache_key):
			var bounds: Dictionary = _conservative_chunk_page_height_bounds()
			result = {
				"status": "pass",
				"height_min_m": float(bounds["min"]),
				"height_max_m": float(bounds["max"]),
				"height_image_only": true,
				"texture_payload_mode": "gpu_provider_rd_height_texture_resident",
			}
		else:
			result = _attach_gpu_provider_chunk_texture(origin, step_m, count, cache_key, allow_sync_staged_provider)
	else:
		result = _cpu_encoded_chunk_page(origin, step_m, count)
	if result.get("status", "fail") != "pass":
		return result
	var height_min: float = float(result.get("height_min_m", -8192.0))
	var height_max: float = float(result.get("height_max_m", 8192.0))
	var descriptor := {
		"status": "pass",
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": ring,
		"lod": lod,
		"origin_x": origin.x,
		"origin_z": origin.y,
		"chunk_size_m": chunk_size,
		"vertices_per_side": count,
		"spacing_m": step_m,
		"height_min_m": height_min,
		"height_max_m": height_max,
		"height_range_m": max(0.0, height_max - height_min),
		"cache_key": cache_key,
		"texture_payload_mode": str(result.get("texture_payload_mode", "")),
		"build_ms": Time.get_ticks_msec() - build_start_ms,
	}
	for field in [
		"height_texture_rid",
		"height_texture_owned_by_residency",
		"height_bytes",
		"height_image_only",
		"rd_owned_rids",
		"height_image_data",
		"normal_image_data",
		"height_image",
		"normal_image",
	]:
		if result.has(field):
			descriptor[field] = result[field]
	if not use_gpu_rd_chunk_compute_normals and not descriptor.has("normal_image_data"):
		descriptor["normal_image_data"] = _chunk_page_flat_normal_image_data(count)
	return descriptor


func _assign_gpu_page_chunk_from_native(key: String, request: Dictionary, native: Dictionary, build_ms: int) -> bool:
	var active_info: Dictionary = _active_info_for_key(key)
	if active_info.is_empty():
		return false
	var count: int = int(request.get("vertices_per_side", 0))
	var height: PackedFloat32Array = native.get("height", PackedFloat32Array()) as PackedFloat32Array
	if count < 2 or height.size() != count * count:
		_last_gpu_page_chunk_error = "native_height_size:%d expected:%d" % [height.size(), count * count]
		return false
	var descriptor: Dictionary = _gpu_page_chunk_descriptor_from_height(
		int(request.get("chunk_x", active_info.get("chunk_x", 0))),
		int(request.get("chunk_z", active_info.get("chunk_z", 0))),
		int(request.get("ring", active_info.get("ring", 0))),
		int(request.get("lod", active_info.get("lod", 0))),
		height,
		build_ms,
		"native_worker_height_page"
	)
	if descriptor.get("status", "fail") != "pass":
		_last_gpu_page_chunk_error = str(descriptor.get("error", "native_descriptor_failed"))
		return false
	var applied: Dictionary = _ensure_chunk_page_renderer().call(
		"apply_descriptor",
		_chunk_renderer,
		key,
		int(descriptor["chunk_x"]),
		int(descriptor["chunk_z"]),
		int(descriptor["ring"]),
		int(descriptor["lod"]),
		world.chunk_size_m,
		descriptor
	) as Dictionary
	_last_gpu_page_chunk_texture_ms = int(applied.get("texture_ms", 0))
	if applied.get("status", "fail") != "pass":
		_last_gpu_page_chunk_error = "native_%s" % str(applied.get("error", "apply_failed"))
		return false
	_record_chunk_build_time(_last_gpu_page_chunk_texture_ms)
	_gpu_page_chunk_count += 1
	_gpu_page_chunks_built_this_update += 1
	_last_gpu_page_chunk_ms = _last_gpu_page_chunk_texture_ms
	_gpu_page_chunk_ms_this_update += _last_gpu_page_chunk_ms
	_last_gpu_page_chunk_error = ""
	return true


func _gpu_page_chunk_descriptor_from_height(
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	height: PackedFloat32Array,
	build_ms: int,
	payload_mode: String
) -> Dictionary:
	var count: int = _vertices_for_lod(lod)
	if count < 2 or height.size() != count * count:
		return {"status": "fail", "error": "height_size:%d expected:%d" % [height.size(), count * count]}
	var chunk_size: float = float(world.chunk_size_m)
	var step_m: float = chunk_size / float(count - 1)
	var request = _chunk_page_request(chunk_x, chunk_z, ring, lod, count, chunk_size)
	var validation: String = request.validate()
	if not validation.is_empty():
		return {"status": "fail", "error": "request:%s" % validation}
	var height_data := PackedByteArray()
	height_data.resize(count * count * 4)
	var min_height := INF
	var max_height := -INF
	for index in range(height.size()):
		var value: float = float(height[index])
		if not is_finite(value):
			return {"status": "fail", "error": "height_nonfinite:%d" % index}
		min_height = minf(min_height, value)
		max_height = maxf(max_height, value)
		height_data.encode_float(index * 4, value)
	return {
		"status": "pass",
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": ring,
		"lod": lod,
		"origin_x": float(chunk_x) * chunk_size,
		"origin_z": float(chunk_z) * chunk_size,
		"chunk_size_m": chunk_size,
		"vertices_per_side": count,
		"spacing_m": step_m,
		"height_min_m": min_height,
		"height_max_m": max_height,
		"height_range_m": max(0.0, max_height - min_height),
		"cache_key": request.cache_key(),
		"height_image_data": height_data,
		"normal_image_data": _chunk_page_flat_normal_image_data(count) if not use_gpu_rd_chunk_compute_normals else PackedByteArray(),
		"height_image_only": use_gpu_rd_chunk_compute_normals,
		"texture_payload_mode": payload_mode,
		"build_ms": build_ms,
	}


func _attach_gpu_provider_chunk_texture(
	origin: Vector2,
	step_m: float,
	count: int,
	cache_key: String,
	allow_sync_staged_provider: bool = false
) -> Dictionary:
	if not _can_use_direct_rd_chunk_page_textures():
		return {"status": "fail", "error": "direct_rd_unavailable"}
	var blocks: Array = []
	if use_gpu_provider_page_chunk_descriptor_staging:
		if not _gpu_provider_chunk_descriptor_cache.has(cache_key) and not allow_sync_staged_provider:
			return {"status": "fail", "error": "provider_descriptor_not_staged"}
		if _gpu_provider_chunk_descriptor_cache.has(cache_key):
			var cached_descriptor: Dictionary = _gpu_provider_chunk_descriptor_cache[cache_key] as Dictionary
			var descriptor_blocks: Array = cached_descriptor.get("descriptor_blocks", []) as Array
			_touch_gpu_provider_chunk_descriptor(cache_key)
			if not descriptor_blocks.is_empty():
				var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
				var backend: RefCounted = _ensure_chunk_gpu_provider_page_texture_backend()
				var staged_result: Dictionary = backend.call(
					"create_height_texture_from_prepared_descriptors",
					rd,
					descriptor_blocks,
					count,
					count,
					step_m
				) as Dictionary
				if staged_result.get("status", "fail") == "pass":
					var staged_bounds: Dictionary = _conservative_chunk_page_height_bounds()
					staged_result["height_min_m"] = float(staged_bounds["min"])
					staged_result["height_max_m"] = float(staged_bounds["max"])
				return staged_result
			blocks = cached_descriptor.get("blocks", []) as Array
		elif allow_sync_staged_provider:
			blocks = _gpu_provider_chunk_page_blocks(origin, step_m, count)
	else:
		blocks = _gpu_provider_chunk_page_blocks(origin, step_m, count)
	if blocks.is_empty():
		return {"status": "fail", "error": "prepared_blocks_empty"}
	var first_block: Dictionary = blocks[0] as Dictionary
	if first_block.get("status", "pass") != "pass":
		return {"status": "fail", "error": "prepared:%s" % str(first_block.get("error", "fail"))}
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	var backend: RefCounted = _ensure_chunk_gpu_provider_page_texture_backend()
	var result: Dictionary = backend.call(
		"create_height_texture_from_prepared_blocks",
		rd,
		blocks,
		count,
		count,
		step_m,
		int(world.seed),
		float(world.region_size_m)
	) as Dictionary
	if result.get("status", "fail") != "pass":
		return result
	var bounds: Dictionary = _conservative_chunk_page_height_bounds()
	result["height_min_m"] = float(bounds["min"])
	result["height_max_m"] = float(bounds["max"])
	return result


func _cpu_encoded_chunk_page(origin: Vector2, step_m: float, count: int) -> Dictionary:
	var height: PackedFloat32Array = world.provider.sample_height_grid(
		origin.x,
		origin.y,
		step_m,
		count,
		count,
		int(world.seed),
		float(world.region_size_m)
	)
	if height.size() != count * count:
		return {"status": "fail", "error": "height_size:%d expected:%d" % [height.size(), count * count]}
	var height_range := {"min": INF, "max": -INF}
	var height_data := PackedByteArray()
	height_data.resize(count * count * 4)
	for index in range(height.size()):
		var value: float = float(height[index])
		if not is_finite(value):
			return {"status": "fail", "error": "height_nonfinite:%d" % index}
		height_range["min"] = minf(float(height_range["min"]), value)
		height_range["max"] = maxf(float(height_range["max"]), value)
		height_data.encode_float(index * 4, value)
	return {
		"status": "pass",
		"height_image_data": height_data,
		"height_image_only": true,
		"height_min_m": float(height_range["min"]),
		"height_max_m": float(height_range["max"]),
		"texture_payload_mode": "cpu_preencoded_height",
	}


func _gpu_provider_chunk_page_blocks(origin: Vector2, step_m: float, count: int) -> Array:
	var blocks: Array = []
	var x_ranges: Array[Dictionary] = _axis_ranges_by_region_for_span(origin.x, step_m, count)
	var z_ranges: Array[Dictionary] = _axis_ranges_by_region_for_span(origin.y, step_m, count)
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
			var world_x0: float = origin.x + float(x0) * step_m
			var world_z0: float = origin.y + float(z0) * step_m
			var prepared: Dictionary = world.provider.call(
				"native_prepared_height_grid_request",
				world_x0,
				world_z0,
				step_m,
				count_x,
				count_z,
				int(world.seed),
				float(world.region_size_m)
			) as Dictionary
			if prepared.get("status", "fail") != "pass":
				return [{"status": "fail", "error": prepared.get("error", prepared.get("status", "fail"))}]
			blocks.append({
				"status": "pass",
				"prepared_request": prepared,
				"origin_x": world_x0,
				"origin_z": world_z0,
				"count_x": count_x,
				"count_z": count_z,
				"offset_x": x0,
				"offset_z": z0,
			})
	return blocks


func _axis_ranges_by_region_for_span(origin_axis: float, step_m: float, count: int) -> Array[Dictionary]:
	var ranges: Array[Dictionary] = []
	if count <= 0:
		return ranges
	var start := 0
	var current_region: int = _region_for_axis(origin_axis)
	for index in range(1, count):
		var coord: float = origin_axis + float(index) * step_m
		var region: int = _region_for_axis(coord)
		if region == current_region:
			continue
		ranges.append({"start": start, "end": index - 1, "region": current_region})
		start = index
		current_region = region
	ranges.append({"start": start, "end": count - 1, "region": current_region})
	return ranges


func _region_for_axis(coord: float) -> int:
	return int(floor(coord / float(world.region_size_m)))


func _chunk_page_feature_flags(ring: int, lod: int) -> Dictionary:
	var flags := {
		"debug_mode": debug_mode,
		"fast_gray": use_fast_gray_material,
		"provider_gpu_texture": use_gpu_provider_page_chunk_textures,
		"profile": _landform_profile_cache_key(),
	}
	if use_lod_mesh_density:
		flags["ring"] = ring
		flags["lod"] = lod
	return flags


func _chunk_page_quality_profile(lod: int) -> String:
	if not use_lod_mesh_density:
		return "full_density"
	return "lod_%d" % lod


func _landform_profile_cache_key() -> String:
	if world == null or world.provider == null or not world.provider.has_method("landform_profile_report"):
		return ""
	var report: Dictionary = world.provider.call("landform_profile_report") as Dictionary
	var settings: Dictionary = report.get("settings", {}) as Dictionary
	if not settings.is_empty():
		return str(settings)
	return str(report.get("profile_id", report.get("profile", "")))


func _chunk_page_flat_normal_image_data(count: int) -> PackedByteArray:
	return _ensure_chunk_page_renderer().call("flat_normal_image_data", count) as PackedByteArray


func _assign_chunk_payload(key: String, payload: Dictionary, build_ms: int) -> void:
	if payload.get("status", "fail") != "pass":
		return
	var chunk_x: int = int(payload["chunk_x"])
	var chunk_z: int = int(payload["chunk_z"])
	var active_info: Dictionary = _active_info_for_key(key)
	if active_info.is_empty():
		return
	_ensure_chunk_renderer()
	_record_chunk_build_time(build_ms)
	var ring: int = int(payload.get("ring", active_info.get("ring", 0)))
	var lod: int = int(payload.get("lod", active_info.get("lod", 0)))
	var mesh_instance: MeshInstance3D = _chunk_renderer.call(
		"apply_chunk",
		key,
		chunk_x,
		chunk_z,
		ring,
		lod,
		world.chunk_size_m,
		TerrainChunkBuildJobScript.mesh_from_payload(payload),
		_material_for_chunk(chunk_x, chunk_z, ring, lod)
	) as MeshInstance3D
	if mesh_instance != null:
		mesh_instance.set_meta("gpu_page_chunk", false)


func _build_chunk_mesh(chunk_x: int, chunk_z: int, ring: int = 0, lod: int = 0) -> ArrayMesh:
	var payload: Dictionary = _build_chunk_payload(chunk_x, chunk_z, ring, lod)
	return TerrainChunkBuildJobScript.mesh_from_payload(payload)


func _build_chunk_payload(chunk_x: int, chunk_z: int, ring: int = 0, lod: int = 0) -> Dictionary:
	var count: int = _vertices_for_lod(lod)
	var step_m: float = world.chunk_size_m / float(count - 1)
	var colors := PackedColorArray()
	if debug_mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		colors = _build_hydrology_colors_for_chunk(chunk_x, chunk_z, count, step_m)
	elif not use_fast_gray_material:
		colors = _build_gray_colors_for_chunk(chunk_x, chunk_z, count, step_m)
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		chunk_x,
		chunk_z,
		count,
		world.chunk_size_m,
		ring,
		lod,
		debug_mode
	)
	if use_native_chunk_payloads and colors.is_empty() and _native_backend_available() and _provider_supports_native_prepared_grid():
		var native_payload: Dictionary = _build_native_chunk_payload(request)
		if native_payload.get("status", "fail") == "pass":
			_native_chunk_payload_count += 1
			return _finalize_chunk_payload(native_payload, count)
	if use_native_mesh_payloads and colors.is_empty() and _native_backend_available():
		var native_mesh_payload: Dictionary = _build_native_mesh_payload(request)
		if native_mesh_payload.get("status", "fail") == "pass":
			_native_chunk_payload_count += 1
			return _finalize_chunk_payload(native_mesh_payload, count)
	var cpu_start_ms: int = Time.get_ticks_msec()
	var payload: Dictionary = TerrainChunkBuildJobScript.build_payload(
		world,
		request,
		colors,
		_chunk_payload_needs_normals()
	)
	_last_cpu_chunk_payload_ms = Time.get_ticks_msec() - cpu_start_ms
	_last_mesh_normals_ms = TerrainMeshBuilderScript.last_normals_build_ms
	_cpu_chunk_payload_count += 1
	return _finalize_chunk_payload(payload, count)


func _can_use_gpu_page_chunks() -> bool:
	if not use_gpu_page_chunks:
		return false
	if world == null or world.provider == null:
		return false
	if debug_mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		return false
	if debug_mode == TerrainWorldScript.DEBUG_GRAY and not use_fast_gray_material:
		return false
	if debug_mode != TerrainWorldScript.DEBUG_GRAY and debug_mode != TerrainWorldScript.DEBUG_ELEVATION_COLOR:
		return false
	if use_mesh_skirts or use_lod_mesh_density:
		return false
	if use_gpu_provider_page_chunk_textures and not _provider_supports_native_prepared_grid():
		return false
	if use_gpu_provider_page_chunk_textures and not _can_use_direct_rd_chunk_page_textures():
		return false
	return true


func _can_use_staged_gpu_provider_chunk_pages() -> bool:
	return (
		_can_use_gpu_page_chunks()
		and use_gpu_provider_page_chunk_textures
		and use_gpu_provider_page_chunk_descriptor_staging
		and _provider_supports_native_prepared_grid()
		and _can_use_direct_rd_chunk_page_textures()
	)


func _can_use_native_chunk_workers() -> bool:
	if not use_native_chunk_workers or not use_native_chunk_payloads:
		return false
	if not _native_backend_available():
		return false
	if not _provider_supports_native_prepared_grid():
		return false
	if debug_mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		return false
	if debug_mode == TerrainWorldScript.DEBUG_GRAY and not use_fast_gray_material:
		return false
	return true


func _enqueue_native_worker_build(key: String, chunk_x: int, chunk_z: int, ring: int, lod: int) -> void:
	if _native_chunk_workers.has(key):
		return
	var queued_item: Dictionary = {
		"key": key,
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": ring,
		"lod": lod,
	}
	var item_index := 0
	for item_value in _native_worker_queue:
		var item: Dictionary = item_value as Dictionary
		if str(item["key"]) == key:
			_native_worker_queue[item_index] = queued_item
			return
		item_index += 1
	_native_worker_queue.append(queued_item)


func _pump_native_worker_queue() -> void:
	if not _can_use_native_chunk_workers():
		_native_worker_queue.clear()
		return
	while _native_chunk_workers.size() < max(1, max_native_chunk_workers) and not _native_worker_queue.is_empty():
		var item: Dictionary = _native_worker_queue.pop_front() as Dictionary
		var key: String = str(item["key"])
		var active_info: Dictionary = _active_info_for_key(key)
		if active_info.is_empty():
			continue
		var lod: int = int(active_info["lod"])
		var count: int = _vertices_for_lod(lod)
		var request: Dictionary = TerrainChunkBuildJobScript.make_request(
			int(active_info["chunk_x"]),
			int(active_info["chunk_z"]),
			count,
			world.chunk_size_m,
			int(active_info["ring"]),
			lod,
			debug_mode
		)
		request["request_id"] = _native_chunk_request_id(key, request)
		request["target_step"] = int(last_report.get("step", -1))
		var prepared_request: Dictionary = _prepare_native_chunk_payload_request(request)
		if prepared_request.get("status", "fail") != "pass":
			_build_or_update_chunk_node(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), lod)
			continue
		prepared_request["request_id"] = str(request["request_id"])
		var worker: RefCounted = TerrainNativeChunkPayloadWorkerScript.new()
		if not worker.start(prepared_request):
			_build_or_update_chunk_node(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), lod)
			continue
		_native_chunk_workers[key] = worker
		_native_worker_requests[key] = request


func _poll_native_chunk_workers() -> void:
	var result_budget: int = max(1, max_native_chunk_worker_results_per_update)
	var keys: Array = _native_chunk_workers.keys()
	for key_value in keys:
		if _native_worker_results_applied_this_update >= result_budget:
			break
		var key: String = str(key_value)
		var worker: RefCounted = _native_chunk_workers[key] as RefCounted
		if not worker.is_done():
			continue
		var native: Dictionary = worker.take_result()
		var request: Dictionary = _native_worker_requests.get(key, {}) as Dictionary
		_native_chunk_workers.erase(key)
		_native_worker_requests.erase(key)
		var active_info: Dictionary = _active_info_for_key(key)
		if request.is_empty() or active_info.is_empty():
			continue
		if not _can_use_native_chunk_workers():
			_build_or_update_chunk_node(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), int(active_info["lod"]))
			continue
		if str(native.get("worker_request_id", "")) != str(request.get("request_id", "")):
			if _can_use_native_chunk_workers():
				_enqueue_native_worker_build(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), int(active_info["lod"]))
			else:
				_build_or_update_chunk_node(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), int(active_info["lod"]))
			continue
		if not _native_request_matches_active_target(request, active_info):
			if _can_use_native_chunk_workers():
				_enqueue_native_worker_build(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), int(active_info["lod"]))
			else:
				_build_or_update_chunk_node(key, int(active_info["chunk_x"]), int(active_info["chunk_z"]), int(active_info["ring"]), int(active_info["lod"]))
			continue
		_last_native_worker_elapsed_ms = int(native.get("worker_elapsed_ms", 0))
		_last_native_chunk_payload_ms = _last_native_worker_elapsed_ms
		_last_height_grid_ms = 0
		_last_native_mesh_payload_ms = _last_native_worker_elapsed_ms
		var build_ms: int = _last_native_worker_elapsed_ms
		if native.get("status", "fail") == "pass" and _can_use_gpu_page_chunks():
			if _assign_gpu_page_chunk_from_native(key, request, native, build_ms):
				_native_worker_payload_count += 1
				_native_worker_results_applied_this_update += 1
				_last_native_worker_results_applied = _native_worker_results_applied_this_update
				continue
		var payload: Dictionary = _native_chunk_payload_to_job_payload(request, native)
		if payload.get("status", "fail") == "pass":
			payload = _finalize_chunk_payload(payload, int(request["vertices_per_side"]))
			_native_worker_payload_count += 1
		else:
			var fallback_start_ms: int = Time.get_ticks_msec()
			payload = _build_cpu_chunk_payload_from_request(request)
			build_ms = Time.get_ticks_msec() - fallback_start_ms
		_assign_chunk_payload(key, payload, build_ms)
		_native_worker_results_applied_this_update += 1
		_last_native_worker_results_applied = _native_worker_results_applied_this_update
	_prune_native_worker_queue()
	_pump_native_worker_queue()


func _prune_native_worker_queue() -> void:
	if _native_worker_queue.is_empty() or last_report.is_empty():
		return
	var filtered: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	for item_value in _native_worker_queue:
		var item: Dictionary = item_value as Dictionary
		var key: String = str(item.get("key", ""))
		if key.is_empty() or seen_keys.has(key):
			continue
		if _native_chunk_workers.has(key):
			continue
		if _active_info_for_key(key).is_empty():
			continue
		seen_keys[key] = true
		filtered.append(item)
	_native_worker_queue = filtered


func _remove_queued_native_worker_for_key(key: String) -> void:
	if _native_worker_queue.is_empty():
		return
	var filtered: Array[Dictionary] = []
	for item_value in _native_worker_queue:
		var item: Dictionary = item_value as Dictionary
		if str(item.get("key", "")) == key:
			continue
		filtered.append(item)
	_native_worker_queue = filtered


func _remove_streamer_queued_build_for_key(key: String) -> void:
	if world == null or world.streamer == null:
		return
	var queue: Array = world.streamer.queued_builds
	if queue.is_empty():
		return
	var index: int = queue.find(key)
	while index >= 0:
		queue.remove_at(index)
		index = queue.find(key)


func _prune_streamer_queue_for_built_chunks() -> void:
	if world == null or world.streamer == null:
		return
	var queue: Array = world.streamer.queued_builds
	if queue.is_empty():
		return
	var filtered: Array[String] = []
	for key_value in queue:
		var key: String = str(key_value)
		var active_info: Dictionary = _active_info_for_key(key)
		if active_info.is_empty():
			continue
		if _chunk_node_matches_active_info(key, active_info):
			continue
		filtered.append(key)
	world.streamer.queued_builds = filtered
	if not last_report.is_empty():
		last_report["queued_build_count"] = filtered.size()


func _native_chunk_request_id(key: String, request: Dictionary) -> String:
	return "%s:%d:%d:%d:%s" % [
		key,
		int(request.get("ring", -1)),
		int(request.get("lod", -1)),
		int(request.get("vertices_per_side", -1)),
		str(request.get("debug_mode", "")),
	]


func _native_request_matches_active_target(request: Dictionary, active_info: Dictionary) -> bool:
	if int(request.get("chunk_x", 0)) != int(active_info.get("chunk_x", 1)):
		return false
	if int(request.get("chunk_z", 0)) != int(active_info.get("chunk_z", 1)):
		return false
	var active_lod: int = int(active_info.get("lod", -1))
	if int(request.get("lod", -2)) != active_lod:
		return false
	if int(request.get("ring", -2)) != int(active_info.get("ring", -1)):
		return false
	if int(request.get("vertices_per_side", -1)) != _vertices_for_lod(active_lod):
		return false
	if float(request.get("chunk_size_m", -1.0)) != world.chunk_size_m:
		return false
	if str(request.get("debug_mode", "")) != debug_mode:
		return false
	return true


func _clear_native_chunk_workers(wait_for_running: bool = false) -> void:
	for worker_value in _native_chunk_workers.values():
		var worker: RefCounted = worker_value as RefCounted
		if worker.call("is_done"):
			worker.call("take_result")
		elif wait_for_running:
			worker.call("wait_for_result", 5000)
		else:
			worker.call("detach_until_done")
	_native_chunk_workers.clear()
	_native_worker_requests.clear()
	_native_worker_queue.clear()


func _clear_gpu_provider_chunk_descriptor_workers(wait_for_running: bool = false) -> void:
	for worker_value in _gpu_provider_chunk_descriptor_workers.values():
		var worker: RefCounted = worker_value as RefCounted
		if worker == null:
			continue
		if bool(worker.call("is_done")):
			worker.call("take_result")
		elif wait_for_running:
			worker.call("wait_for_result", 5000)
		else:
			worker.call("detach_until_done")
	_gpu_provider_chunk_descriptor_workers.clear()
	_gpu_provider_chunk_descriptor_worker_requests.clear()


func _provider_supports_native_prepared_grid() -> bool:
	if world == null or world.provider == null or not world.provider.has_method("native_prepared_height_grid_request"):
		return false
	if world.provider.has_method("landform_profile_report"):
		var report: Dictionary = world.provider.call("landform_profile_report") as Dictionary
		if not bool(report.get("native_prepared_grid_enabled", true)):
			return false
	return true


func _chunk_node_matches_active_info(key: String, active_info: Dictionary) -> bool:
	if not chunk_nodes.has(key):
		return false
	var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	if int(mesh_instance.get_meta("chunk_x")) != int(active_info.get("chunk_x", 0)):
		return false
	if int(mesh_instance.get_meta("chunk_z")) != int(active_info.get("chunk_z", 0)):
		return false
	if not use_lod_mesh_density:
		return true
	if int(mesh_instance.get_meta("ring")) != int(active_info.get("ring", -1)):
		return false
	if int(mesh_instance.get_meta("lod")) != int(active_info.get("lod", -1)):
		return false
	return true


func _retag_full_density_chunk_nodes() -> void:
	if use_lod_mesh_density:
		return
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		var active_info: Dictionary = _active_info_for_key(key)
		if active_info.is_empty():
			continue
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var chunk_x: int = int(active_info.get("chunk_x", 0))
		var chunk_z: int = int(active_info.get("chunk_z", 0))
		if int(mesh_instance.get_meta("chunk_x")) != chunk_x:
			continue
		if int(mesh_instance.get_meta("chunk_z")) != chunk_z:
			continue
		var ring: int = int(active_info.get("ring", 0))
		var lod: int = int(active_info.get("lod", 0))
		if int(mesh_instance.get_meta("ring")) == ring and int(mesh_instance.get_meta("lod")) == lod:
			continue
		mesh_instance.set_meta("ring", ring)
		mesh_instance.set_meta("lod", lod)
		mesh_instance.material_override = _material_for_chunk(chunk_x, chunk_z, ring, lod)


func _vertices_for_lod(lod: int) -> int:
	var base_count: int = max(17, vertices_per_side)
	if not use_lod_mesh_density:
		return base_count
	var divisor: int = 1 << max(0, lod)
	var quads: int = max(16, int((base_count - 1) / divisor))
	return quads + 1


func _build_native_chunk_payload(request: Dictionary) -> Dictionary:
	var prepared_request: Dictionary = _prepare_native_chunk_payload_request(request)
	if prepared_request.get("status", "fail") != "pass":
		return prepared_request
	var native_start_ms: int = Time.get_ticks_msec()
	var native: Dictionary = _run_native_chunk_payload(prepared_request)
	_last_native_chunk_payload_ms = Time.get_ticks_msec() - native_start_ms
	_last_height_grid_ms = 0
	_last_native_mesh_payload_ms = _last_native_chunk_payload_ms
	return _native_chunk_payload_to_job_payload(request, native)


func _finalize_chunk_payload(payload: Dictionary, vertices_per_side_for_top: int) -> Dictionary:
	payload = _maybe_apply_lod_transition_morph(payload, vertices_per_side_for_top)
	return _maybe_append_mesh_skirts(payload, vertices_per_side_for_top)


func _maybe_apply_lod_transition_morph(payload: Dictionary, vertices_per_side_for_top: int) -> Dictionary:
	if not use_lod_mesh_density or not use_lod_transition_morph or lod_transition_band_cells <= 0:
		return payload
	if payload.get("status", "fail") != "pass":
		return payload
	if bool(payload.get("has_colors", false)):
		return payload
	var lod: int = int(payload.get("lod", 0))
	var chunk_x: int = int(payload.get("chunk_x", 0))
	var chunk_z: int = int(payload.get("chunk_z", 0))
	var neighbor_lods: Dictionary = _coarser_neighbor_lods(chunk_x, chunk_z, lod)
	if neighbor_lods.is_empty():
		return payload
	var height: PackedFloat32Array = payload.get("height", PackedFloat32Array()) as PackedFloat32Array
	var count: int = vertices_per_side_for_top
	if height.size() != count * count:
		return payload
	var step_m: float = float(payload.get("step_m", world.chunk_size_m / float(max(1, count - 1))))
	var morphed_height: PackedFloat32Array = _morph_chunk_height_to_coarser_neighbors(
		height,
		count,
		step_m,
		chunk_x,
		chunk_z,
		neighbor_lods
	)
	var arrays: Array = payload["arrays"] as Array
	var morphed_arrays: Array = arrays.duplicate()
	morphed_arrays[Mesh.ARRAY_VERTEX] = TerrainMeshBuilderScript.build_vertices(morphed_height, count, step_m)
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var normals_start_ms: int = Time.get_ticks_msec()
		morphed_arrays[Mesh.ARRAY_NORMAL] = TerrainMeshBuilderScript.build_normals(morphed_height, count, step_m)
		_last_mesh_normals_ms = Time.get_ticks_msec() - normals_start_ms
	var morphed_payload: Dictionary = payload.duplicate()
	morphed_payload["height"] = morphed_height
	morphed_payload["arrays"] = morphed_arrays
	morphed_payload["lod_transition_morph"] = true
	morphed_payload["lod_transition_band_cells"] = lod_transition_band_cells
	morphed_payload["lod_transition_neighbors"] = neighbor_lods.duplicate()
	return morphed_payload


func _coarser_neighbor_lods(chunk_x: int, chunk_z: int, lod: int) -> Dictionary:
	var result: Dictionary = {}
	var directions: Array[Dictionary] = [
		{"name": "west", "dx": -1, "dz": 0},
		{"name": "east", "dx": 1, "dz": 0},
		{"name": "north", "dx": 0, "dz": -1},
		{"name": "south", "dx": 0, "dz": 1},
	]
	for direction_value in directions:
		var direction: Dictionary = direction_value as Dictionary
		var neighbor_lod: int = _active_lod_for_chunk(chunk_x + int(direction["dx"]), chunk_z + int(direction["dz"]))
		if neighbor_lod > lod:
			result[str(direction["name"])] = neighbor_lod
	return result


func _active_lod_for_chunk(chunk_x: int, chunk_z: int) -> int:
	var key: String = _chunk_key(chunk_x, chunk_z)
	var active_info: Dictionary = _active_info_for_key(key)
	if active_info.is_empty():
		return -1
	return int(active_info.get("lod", -1))


func _morph_chunk_height_to_coarser_neighbors(
	height: PackedFloat32Array,
	count: int,
	step_m: float,
	chunk_x: int,
	chunk_z: int,
	neighbor_lods: Dictionary
) -> PackedFloat32Array:
	var band: int = min(max(1, lod_transition_band_cells), max(1, count - 1))
	var morphed := PackedFloat32Array(height)
	var best_blend := PackedFloat32Array()
	best_blend.resize(count * count)
	var best_lod := PackedInt32Array()
	best_lod.resize(count * count)
	var modified_indices: Array[int] = []
	var origin_x: float = float(chunk_x) * world.chunk_size_m
	var origin_z: float = float(chunk_z) * world.chunk_size_m
	if neighbor_lods.has("west"):
		var lod_west: int = int(neighbor_lods["west"])
		for x in range(band):
			var blend_west: float = _lod_transition_blend_for_distance(x, band)
			for z in range(count):
				_mark_lod_transition_candidate(z * count + x, blend_west, lod_west, best_blend, best_lod, modified_indices)
	if neighbor_lods.has("east"):
		var lod_east: int = int(neighbor_lods["east"])
		for offset in range(band):
			var x_east: int = count - 1 - offset
			var blend_east: float = _lod_transition_blend_for_distance(offset, band)
			for z in range(count):
				_mark_lod_transition_candidate(z * count + x_east, blend_east, lod_east, best_blend, best_lod, modified_indices)
	if neighbor_lods.has("north"):
		var lod_north: int = int(neighbor_lods["north"])
		for z in range(band):
			var blend_north: float = _lod_transition_blend_for_distance(z, band)
			for x in range(count):
				_mark_lod_transition_candidate(z * count + x, blend_north, lod_north, best_blend, best_lod, modified_indices)
	if neighbor_lods.has("south"):
		var lod_south: int = int(neighbor_lods["south"])
		for offset in range(band):
			var z_south: int = count - 1 - offset
			var blend_south: float = _lod_transition_blend_for_distance(offset, band)
			for x in range(count):
				_mark_lod_transition_candidate(z_south * count + x, blend_south, lod_south, best_blend, best_lod, modified_indices)
	for index in modified_indices:
		var x: int = index % count
		var z: int = index / count
		var world_x: float = origin_x + float(x) * step_m
		var world_z: float = origin_z + float(z) * step_m
		var coarse_step: float = _step_for_lod(int(best_lod[index]))
		var target_height: float = _coarse_chunk_surface_height(world_x, world_z, coarse_step)
		morphed[index] = lerpf(float(height[index]), target_height, float(best_blend[index]))
	return morphed


func _lod_transition_blend_for_distance(distance: int, band: int) -> float:
	var t: float = clampf(1.0 - float(distance) / float(max(1, band)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _mark_lod_transition_candidate(
	index: int,
	blend: float,
	lod: int,
	best_blend: PackedFloat32Array,
	best_lod: PackedInt32Array,
	modified_indices: Array[int]
) -> void:
	if blend <= 0.0:
		return
	if float(best_blend[index]) <= 0.0:
		modified_indices.append(index)
	if blend > float(best_blend[index]) or (is_equal_approx(blend, float(best_blend[index])) and lod > int(best_lod[index])):
		best_blend[index] = blend
		best_lod[index] = lod


func _step_for_lod(lod: int) -> float:
	return world.chunk_size_m / float(max(1, _vertices_for_lod(lod) - 1))


func _coarse_chunk_surface_height(world_x: float, world_z: float, coarse_step: float) -> float:
	var step: float = max(0.000001, coarse_step)
	var x0: float = floor(world_x / step) * step
	var z0: float = floor(world_z / step) * step
	var x1: float = x0 + step
	var z1: float = z0 + step
	var tx: float = clampf((world_x - x0) / step, 0.0, 1.0)
	var tz: float = clampf((world_z - z0) / step, 0.0, 1.0)
	var h00: float = world.sample_height(x0, z0)
	var h10: float = world.sample_height(x1, z0)
	var h01: float = world.sample_height(x0, z1)
	var h11: float = world.sample_height(x1, z1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _maybe_append_mesh_skirts(payload: Dictionary, vertices_per_side_for_top: int) -> Dictionary:
	if not use_mesh_skirts or mesh_skirt_depth_m <= 0.0:
		return payload
	if payload.get("status", "fail") != "pass":
		return payload
	var arrays: Array = payload["arrays"] as Array
	payload = payload.duplicate()
	payload["arrays"] = TerrainMeshBuilderScript.append_skirts_to_surface_arrays(
		arrays,
		vertices_per_side_for_top,
		mesh_skirt_depth_m
	)
	payload["has_mesh_skirts"] = true
	payload["mesh_skirt_depth_m"] = mesh_skirt_depth_m
	return payload


func _prepare_native_chunk_payload_request(request: Dictionary) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var step_m: float = float(request["step_m"])
	if count < 2:
		return _native_request_fail("vertices_per_side:%d" % count, request)
	if step_m <= 0.0:
		return _native_request_fail("step_m:%f" % step_m, request)
	var origin_x: float = float(chunk_x) * float(request["chunk_size_m"])
	var origin_z: float = float(chunk_z) * float(request["chunk_size_m"])
	var prepared: Dictionary = world.provider.native_prepared_height_grid_request(
		origin_x,
		origin_z,
		step_m,
		count,
		count,
		world.seed,
		world.region_size_m
	)
	if prepared.get("status", "fail") != "pass":
		return prepared
	var validation: Dictionary = _validate_native_prepared_chunk_payload(prepared, request)
	if validation.get("status", "fail") != "pass":
		return validation
	return {
		"status": "pass",
		"request": request,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count": count,
		"world_seed": world.seed,
		"region_size_m": world.region_size_m,
		"base_rx": int(prepared["base_rx"]),
		"base_rz": int(prepared["base_rz"]),
		"corner_entries": prepared["corner_entries"] as Array,
	}


func _native_request_fail(error: String, request: Dictionary = {}) -> Dictionary:
	return {
		"status": "fail",
		"error": "native_request:%s" % error,
		"request": request,
	}


func _validate_native_prepared_chunk_payload(prepared: Dictionary, request: Dictionary = {}) -> Dictionary:
	if not prepared.has("base_rx") or not prepared.has("base_rz"):
		return _native_request_fail("missing_base_region", request)
	if not prepared.has("corner_entries"):
		return _native_request_fail("missing_corner_entries", request)
	var corner_entries_variant: Variant = prepared["corner_entries"]
	if not (corner_entries_variant is Array):
		return _native_request_fail("corner_entries_not_array", request)
	var corner_entries: Array = corner_entries_variant as Array
	if corner_entries.size() != 4:
		return _native_request_fail("corner_count:%d expected:4" % corner_entries.size(), request)
	for corner_index in range(corner_entries.size()):
		var corner_variant: Variant = corner_entries[corner_index]
		if not (corner_variant is Dictionary):
			return _native_request_fail("corner_not_dictionary:%d" % corner_index, request)
		var corner: Dictionary = corner_variant as Dictionary
		var entries_variant: Variant = corner.get("entries", [])
		if not (entries_variant is Array):
			return _native_request_fail("entries_not_array:%d" % corner_index, request)
		var entries: Array = entries_variant as Array
		if entries.is_empty():
			return _native_request_fail("entries_empty:%d" % corner_index, request)
		for entry_index in range(entries.size()):
			var entry_variant: Variant = entries[entry_index]
			if not (entry_variant is Dictionary):
				return _native_request_fail("entry_not_dictionary:%d:%d" % [corner_index, entry_index], request)
			var entry: Dictionary = entry_variant as Dictionary
			var rows: int = int(entry.get("rows", 0))
			var cols: int = int(entry.get("cols", 0))
			if rows < 2 or cols < 2:
				return _native_request_fail("entry_shape:%d:%d rows:%d cols:%d" % [corner_index, entry_index, rows, cols], request)
			var values_variant: Variant = entry.get("values", PackedFloat32Array())
			if not (values_variant is PackedFloat32Array):
				return _native_request_fail("entry_values_not_float32:%d:%d" % [corner_index, entry_index], request)
			var values: PackedFloat32Array = values_variant as PackedFloat32Array
			var expected_values: int = rows * cols
			if values.size() != expected_values:
				return _native_request_fail("entry_values_size:%d:%d size:%d expected:%d" % [corner_index, entry_index, values.size(), expected_values], request)
			var scale: float = float(entry.get("scale", 0.0))
			if scale <= 0.0:
				return _native_request_fail("entry_scale:%d:%d value:%f" % [corner_index, entry_index, scale], request)
	return {"status": "pass"}


func _run_native_chunk_payload(prepared_request: Dictionary) -> Dictionary:
	return _native_backend.call(
		"build_chunk_payload_prepared",
		float(prepared_request["origin_x"]),
		float(prepared_request["origin_z"]),
		float(prepared_request["step_m"]),
		int(prepared_request["count"]),
		int(prepared_request["world_seed"]),
		float(prepared_request["region_size_m"]),
		int(prepared_request["base_rx"]),
		int(prepared_request["base_rz"]),
		prepared_request["corner_entries"] as Array
	) as Dictionary


func _native_chunk_payload_to_job_payload(request: Dictionary, native: Dictionary) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var step_m: float = float(request["step_m"])
	var origin_x: float = float(chunk_x) * float(request["chunk_size_m"])
	var origin_z: float = float(chunk_z) * float(request["chunk_size_m"])
	if native.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": "native_chunk_payload:%s" % str(native.get("error", "unknown")),
			"request": request,
		}
	var height: PackedFloat32Array = native["height"] as PackedFloat32Array
	if height.size() != count * count:
		return {
			"status": "fail",
			"error": "height_size:%d expected:%d" % [height.size(), count * count],
			"request": request,
		}
	var vertices: PackedVector3Array = native.get("vertices", PackedVector3Array()) as PackedVector3Array
	var normals: PackedVector3Array = native.get("normals", PackedVector3Array()) as PackedVector3Array
	var uvs: PackedVector2Array = native.get("uvs", PackedVector2Array()) as PackedVector2Array
	var indices: PackedInt32Array = native.get("indices", PackedInt32Array()) as PackedInt32Array
	var expected_vertices: int = count * count
	var expected_indices: int = (count - 1) * (count - 1) * 6
	if vertices.size() != expected_vertices or normals.size() != expected_vertices or uvs.size() != expected_vertices or indices.size() != expected_indices:
		return {
			"status": "fail",
			"error": "native_array_shape vertices:%d normals:%d uvs:%d indices:%d expected_vertices:%d expected_indices:%d" % [
				vertices.size(),
				normals.size(),
				uvs.size(),
				indices.size(),
				expected_vertices,
				expected_indices,
			],
			"request": request,
		}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return {
		"status": "pass",
		"request": request,
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": int(request.get("ring", 0)),
		"lod": int(request.get("lod", 0)),
		"origin_m": [origin_x, origin_z],
		"vertices_per_side": count,
		"step_m": step_m,
		"height": height,
		"arrays": arrays,
		"has_colors": false,
		"native_chunk_payload": true,
	}


func _build_cpu_chunk_payload_from_request(request: Dictionary) -> Dictionary:
	var cpu_start_ms: int = Time.get_ticks_msec()
	var payload: Dictionary = TerrainChunkBuildJobScript.build_payload(
		world,
		request,
		PackedColorArray(),
		_chunk_payload_needs_normals()
	)
	_last_cpu_chunk_payload_ms = Time.get_ticks_msec() - cpu_start_ms
	_last_mesh_normals_ms = TerrainMeshBuilderScript.last_normals_build_ms
	_cpu_chunk_payload_count += 1
	return _finalize_chunk_payload(payload, int(request["vertices_per_side"]))


func _build_native_mesh_payload(request: Dictionary) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var step_m: float = float(request["step_m"])
	var height_start_ms: int = Time.get_ticks_msec()
	var height: PackedFloat32Array = world.sample_height_grid_for_chunk(chunk_x, chunk_z, count)
	_last_height_grid_ms = Time.get_ticks_msec() - height_start_ms
	if height.size() != count * count:
		return {
			"status": "fail",
			"error": "height_size:%d expected:%d" % [height.size(), count * count],
			"request": request,
		}
	var mesh_start_ms: int = Time.get_ticks_msec()
	var native: Dictionary = _native_backend.call(
		"build_mesh_payload_from_height",
		height,
		count,
		step_m
	) as Dictionary
	_last_native_mesh_payload_ms = Time.get_ticks_msec() - mesh_start_ms
	if native.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": "native_mesh_payload:%s" % str(native.get("error", "unknown")),
			"request": request,
		}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = native["vertices"] as PackedVector3Array
	arrays[Mesh.ARRAY_NORMAL] = native["normals"] as PackedVector3Array
	arrays[Mesh.ARRAY_TEX_UV] = native["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = native["indices"] as PackedInt32Array
	return {
		"status": "pass",
		"request": request,
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": int(request.get("ring", 0)),
		"lod": int(request.get("lod", 0)),
		"origin_m": [float(chunk_x) * float(request["chunk_size_m"]), float(chunk_z) * float(request["chunk_size_m"])],
		"vertices_per_side": count,
		"step_m": step_m,
		"height": height,
		"arrays": arrays,
		"has_colors": false,
		"native_mesh_payload": true,
	}


func _native_backend_available() -> bool:
	if _native_backend != null:
		return true
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return false
	_native_backend = ClassDB.instantiate("Wg9TerrainNativeBackend")
	return _native_backend != null


func _can_use_direct_rd_chunk_page_textures() -> bool:
	return (
		use_gpu_rd_chunk_page_textures
		and ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _ensure_chunk_page_renderer() -> RefCounted:
	if _chunk_page_renderer == null:
		_chunk_page_renderer = TerrainChunkPageRendererScript.new()
	_chunk_page_renderer.call("configure", {
		"cache_max_pages": chunk_page_cache_max_pages,
		"residency_max_pages": chunk_gpu_page_residency_max_pages,
		"use_rd_page_textures": use_gpu_rd_chunk_page_textures,
		"use_rd_compute_normals": use_gpu_rd_chunk_compute_normals,
		"fast_gray_exposure": fast_gray_exposure,
		"fast_gray_contrast": fast_gray_contrast,
		"elevation_color_enabled": debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR,
		"edge_fog_enabled": use_edge_fog,
		"edge_fog_begin_m": edge_fog_begin_m,
		"edge_fog_end_m": edge_fog_end_m,
		"edge_fog_color": edge_fog_color,
	})
	return _chunk_page_renderer


func _ensure_chunk_gpu_provider_page_texture_backend() -> RefCounted:
	if _chunk_gpu_provider_page_texture_backend == null:
		_chunk_gpu_provider_page_texture_backend = TerrainGpuProviderPageTextureBackendScript.new()
	return _chunk_gpu_provider_page_texture_backend


func _chunk_gpu_page_residency_state() -> Dictionary:
	if _chunk_page_renderer == null:
		return {
			"max_pages": chunk_gpu_page_residency_max_pages,
			"count": 0,
			"uploads": 0,
			"rd_uploads": 0,
			"image_uploads": 0,
			"total_mib": 0.0,
		}
	return _chunk_page_renderer.call("gpu_page_residency_state") as Dictionary


func _chunk_gpu_provider_texture_backend_state() -> Dictionary:
	if _chunk_gpu_provider_page_texture_backend == null:
		return {
			"compile_count": 0,
			"dispatch_count": 0,
			"last_create_texture_ms": 0,
			"max_create_texture_ms": 0,
			"last_block_count": 0,
			"last_error": "",
		}
	return _chunk_gpu_provider_page_texture_backend.call("debug_state") as Dictionary


func _chunk_page_renderer_has_page(cache_key: String) -> bool:
	if _chunk_page_renderer == null or cache_key.is_empty():
		return false
	return bool(_chunk_page_renderer.call("has_page", cache_key))


func _update_chunk_page_protected_keys() -> void:
	if _chunk_page_renderer == null or world == null:
		return
	var keys: Array[String] = []
	for key_value in chunk_nodes.keys():
		var mesh_instance: MeshInstance3D = chunk_nodes[key_value] as MeshInstance3D
		if mesh_instance == null or not bool(mesh_instance.get_meta("gpu_page_chunk", false)):
			continue
		var chunk_x: int = int(mesh_instance.get_meta("chunk_x", 0))
		var chunk_z: int = int(mesh_instance.get_meta("chunk_z", 0))
		var lod: int = int(mesh_instance.get_meta("lod", 0))
		var ring: int = int(mesh_instance.get_meta("ring", 0))
		var count: int = _vertices_for_lod(lod)
		var request = TerrainPageRequestScript.from_chunk(
			chunk_x,
			chunk_z,
			float(world.chunk_size_m),
			count,
			int(world.seed),
			"near_chunk_height",
			_chunk_page_quality_profile(lod),
			_chunk_page_feature_flags(ring, lod)
		)
		if request.validate().is_empty():
			keys.append(request.cache_key())
	_chunk_page_renderer.call("set_protected_keys", keys)


func _conservative_chunk_page_height_bounds() -> Dictionary:
	var scale := 1.0
	if world != null and world.provider != null and world.provider.has_method("landform_profile_report"):
		var profile: Dictionary = world.provider.call("landform_profile_report") as Dictionary
		var settings: Dictionary = profile.get("settings", {}) as Dictionary
		if not settings.is_empty():
			scale = maxf(scale, float(settings.get("macro_relief_scale", 1.0)))
			scale = maxf(scale, float(settings.get("kernel_relief_strength", 1.0)))
			scale = maxf(scale, float(settings.get("mountain_boost", 1.0)))
	var extent: float = 8192.0 * clampf(scale, 1.0, 3.0)
	return {"min": -extent, "max": extent}


func _build_gray_colors_for_chunk(chunk_x: int, chunk_z: int, count: int, step_m: float) -> PackedColorArray:
	var extended_count: int = count + 2
	var origin_x: float = float(chunk_x) * world.chunk_size_m - step_m
	var origin_z: float = float(chunk_z) * world.chunk_size_m - step_m
	var extended: PackedFloat32Array = world.provider.sample_height_grid(
		origin_x,
		origin_z,
		step_m,
		extended_count,
		extended_count,
		world.seed,
		world.region_size_m
	)
	var colors := PackedColorArray()
	colors.resize(count * count)
	var light_dir := Vector3(-0.42, 0.74, -0.52).normalized()
	for z in range(count):
		for x in range(count):
			var ext_x: int = x + 1
			var ext_z: int = z + 1
			var center_height: float = float(extended[ext_z * extended_count + ext_x])
			var dx: float = (
				float(extended[ext_z * extended_count + ext_x + 1])
				- float(extended[ext_z * extended_count + ext_x - 1])
			) / (step_m * 2.0)
			var dz: float = (
				float(extended[(ext_z + 1) * extended_count + ext_x])
				- float(extended[(ext_z - 1) * extended_count + ext_x])
			) / (step_m * 2.0)
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			var compressed_height: float = 0.5 + atan(center_height / 1800.0) / PI
			var review_normal := Vector3(normal.x * 0.65, normal.y, normal.z * 0.65).normalized()
			var lambert: float = review_normal.dot(light_dir) * 0.5 + 0.5
			var slope_shadow: float = clampf((1.0 - review_normal.y) * 0.04, 0.0, 0.025)
			var shade: float = clampf(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70)
			colors[z * count + x] = Color(shade, shade, shade)
	return colors


func _material_for_chunk(chunk_x: int, chunk_z: int, ring: int, lod: int) -> Material:
	if debug_mode == TerrainWorldScript.DEBUG_HEIGHT_BANDS:
		return _height_band_material()
	if debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR:
		return _elevation_color_material_for_chunks()
	if debug_mode == TerrainWorldScript.DEBUG_GRAY and use_fast_gray_material:
		return _fast_gray_material()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if debug_mode == TerrainWorldScript.DEBUG_GRAY or debug_mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
	else:
		material.albedo_color = _debug_color(chunk_x, chunk_z, ring, lod)
	material.roughness = 1.0
	return material


func _build_hydrology_colors_for_chunk(chunk_x: int, chunk_z: int, count: int, step_m: float) -> PackedColorArray:
	var cache: RefCounted = _get_hydrology_cache()
	var colors := PackedColorArray()
	colors.resize(count * count)
	var origin_x: float = float(chunk_x) * world.chunk_size_m
	var origin_z: float = float(chunk_z) * world.chunk_size_m
	for z in range(count):
		var sample_z: float = origin_z + float(z) * step_m
		for x in range(count):
			var sample_x: float = origin_x + float(x) * step_m
			var sample: Dictionary = cache.sample(sample_x, sample_z)
			var wetness: float = float(sample.get(HydrologyTileCacheScript.FIELD_WETNESS, 0.0))
			var channel: float = float(sample.get(HydrologyTileCacheScript.FIELD_CHANNEL_LIKELIHOOD, 0.0))
			var slope: float = float(sample.get(HydrologyTileCacheScript.FIELD_SLOPE_DEG, 0.0))
			var flow: float = float(sample.get(HydrologyTileCacheScript.FIELD_FLOW_ACCUMULATION, 0.0))
			colors[z * count + x] = _hydrology_color(wetness, channel, slope, flow)
	return colors


func _hydrology_color(wetness: float, channel: float, slope_deg: float, flow_accumulation: float) -> Color:
	var wet: float = _smooth01(0.14, 0.62, wetness)
	var channel_line: float = _smooth01(0.22, 0.52, channel)
	var flow_signal: float = log(1.0 + max(0.0, flow_accumulation)) / log(4097.0)
	var flow_line: float = _smooth01(0.34, 0.78, flow_signal)
	var line: float = max(channel_line, flow_line)
	var slope: float = clampf(slope_deg / 36.0, 0.0, 1.0)
	var base := Color(0.020 + slope * 0.07, 0.034 + slope * 0.10, 0.074 + slope * 0.16)
	var wet_color := Color(0.04, 0.24, 0.58)
	var channel_color := Color(0.66, 0.78, 0.16)
	var color: Color = base.lerp(wet_color, clampf(wet * 0.68, 0.0, 0.68))
	color = color.lerp(channel_color, clampf(line * 0.78, 0.0, 0.78))
	return color


func _smooth01(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / max(0.000001, edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_hydrology_cache() -> RefCounted:
	if _hydrology_cache != null:
		return _hydrology_cache
	_hydrology_cache = HydrologyTileCacheScript.new()
	var tile_offset := Vector2(
		TerrainSettingsScript.REGION_SIZE_M * 0.5,
		TerrainSettingsScript.REGION_SIZE_M * 0.5
	)
	_hydrology_cache.setup(world, TerrainSettingsScript.REGION_SIZE_M, 65, 16, tile_offset)
	return _hydrology_cache


func _mode_requires_vertex_rebuild(mode: String) -> bool:
	if mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		return true
	if mode == TerrainWorldScript.DEBUG_GRAY and not use_fast_gray_material:
		return true
	return false


func _chunk_payload_needs_normals() -> bool:
	if use_mesh_skirts:
		return true
	if use_lod_mesh_density and use_lod_transition_morph:
		return true
	return (
		(debug_mode == TerrainWorldScript.DEBUG_GRAY and use_fast_gray_material)
		or debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR
	)


func _rebuild_existing_chunk_meshes() -> void:
	if world == null:
		return
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		var chunk_x: int = int(mesh_instance.get_meta("chunk_x"))
		var chunk_z: int = int(mesh_instance.get_meta("chunk_z"))
		var ring: int = int(mesh_instance.get_meta("ring"))
		var lod: int = int(mesh_instance.get_meta("lod"))
		mesh_instance.mesh = _build_chunk_mesh(chunk_x, chunk_z, ring, lod)


func _profile_disables_native_grid() -> bool:
	if world == null or world.provider == null or not world.provider.has_method("landform_profile_report"):
		return false
	var report: Dictionary = world.provider.call("landform_profile_report") as Dictionary
	return not bool(report.get("native_prepared_grid_enabled", true))


func _queue_active_chunks_for_rebuild() -> void:
	if world == null or world.streamer == null or last_report.is_empty():
		return
	for item_value in last_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var key: String = _chunk_key(int(item.get("chunk_x", 0)), int(item.get("chunk_z", 0)))
		_remove_queued_native_worker_for_key(key)
		if not world.streamer.queued_builds.has(key):
			world.streamer.queued_builds.append(key)


func _requeue_streamer_build_key(key: String) -> void:
	if world == null or world.streamer == null or key.is_empty():
		return
	if not world.streamer.queued_builds.has(key):
		world.streamer.queued_builds.push_front(key)


func _fast_gray_material() -> ShaderMaterial:
	if _gray_material != null:
		_gray_material.set_shader_parameter("gray_exposure", fast_gray_exposure)
		_gray_material.set_shader_parameter("gray_contrast", fast_gray_contrast)
		_apply_edge_fog_shader_parameters(_gray_material)
		return _gray_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float gray_exposure = 1.0;
uniform float gray_contrast = 1.0;
uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);

varying float height_m;
varying vec3 terrain_normal;
varying vec3 world_position;

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
	shade = (shade - 0.5) * gray_contrast + 0.5;
	shade = clamp(shade * gray_exposure, 0.035, 0.58);
	float height_t = clamp(compressed_height, 0.0, 1.0);
	vec3 elevation_tint = mix(vec3(0.56, 0.62, 0.58), vec3(0.80, 0.74, 0.62), height_t);
	vec3 color = vec3(shade) * mix(vec3(1.0), elevation_tint * 1.24, 0.28);
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, distance(world_position.xz, CAMERA_POSITION_WORLD.xz)) : 0.0;
	ALBEDO = mix(color, edge_fog_color, fog_t);
}
"""
	_gray_material = ShaderMaterial.new()
	_gray_material.shader = shader
	_gray_material.set_shader_parameter("gray_exposure", fast_gray_exposure)
	_gray_material.set_shader_parameter("gray_contrast", fast_gray_contrast)
	_apply_edge_fog_shader_parameters(_gray_material)
	return _gray_material


func _elevation_color_material_for_chunks() -> ShaderMaterial:
	if _elevation_color_material != null:
		_apply_edge_fog_shader_parameters(_elevation_color_material)
		return _elevation_color_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);

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
	vec3 review_n = normalize(vec3(n.x * 0.75, n.y, n.z * 0.75));
	vec3 light_dir = normalize(vec3(-0.42, 0.74, -0.52));
	float lambert = dot(review_n, light_dir) * 0.5 + 0.5;
	float height_t = clamp(0.5 + atan(height_m / 1800.0) / 3.14159265, 0.0, 1.0);
	vec3 color = elevation_palette(height_t);
	float shade = clamp(0.62 + lambert * 0.32 - (1.0 - review_n.y) * 0.08, 0.45, 1.0);
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, distance(world_position.xz, CAMERA_POSITION_WORLD.xz)) : 0.0;
	ALBEDO = mix(color * shade, edge_fog_color, fog_t);
}
"""
	_elevation_color_material = ShaderMaterial.new()
	_elevation_color_material.shader = shader
	_apply_edge_fog_shader_parameters(_elevation_color_material)
	return _elevation_color_material


func _apply_edge_fog_shader_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("edge_fog_enabled", use_edge_fog)
	material.set_shader_parameter("edge_fog_begin_m", edge_fog_begin_m)
	material.set_shader_parameter("edge_fog_end_m", max(edge_fog_begin_m + 1.0, edge_fog_end_m))
	material.set_shader_parameter("edge_fog_color", Vector3(edge_fog_color.r, edge_fog_color.g, edge_fog_color.b))


func _height_band_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying float height_m;

void vertex() {
	height_m = VERTEX.y;
}

void fragment() {
	float band = floor(clamp((height_m + 900.0) / 80.0, 0.0, 15.0));
	vec3 color = vec3(0.18, 0.28, 0.38);
	if (band < 2.0) {
		color = vec3(0.16, 0.30, 0.48);
	} else if (band < 4.0) {
		color = vec3(0.27, 0.48, 0.42);
	} else if (band < 6.0) {
		color = vec3(0.45, 0.57, 0.34);
	} else if (band < 8.0) {
		color = vec3(0.62, 0.55, 0.34);
	} else if (band < 10.0) {
		color = vec3(0.65, 0.43, 0.31);
	} else if (band < 12.0) {
		color = vec3(0.53, 0.45, 0.43);
	} else {
		color = vec3(0.78, 0.80, 0.82);
	}
	float line = step(0.92, fract((height_m + 900.0) / 80.0));
	ALBEDO = mix(color, vec3(0.04, 0.04, 0.04), line * 0.35);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _debug_color(chunk_x: int, chunk_z: int, ring: int, _lod: int) -> Color:
	if debug_mode == TerrainWorldScript.DEBUG_SURFACE_OWNER:
		return Color(0.06, 0.72, 0.95)
	if debug_mode == TerrainWorldScript.DEBUG_CHUNK_ID:
		var r: float = float(abs((chunk_x * 73 + chunk_z * 19) % 255)) / 255.0
		var g: float = float(abs((chunk_x * 37 - chunk_z * 97) % 255)) / 255.0
		var b: float = float(abs((chunk_x * 13 + chunk_z * 149) % 255)) / 255.0
		return Color(0.25 + r * 0.65, 0.25 + g * 0.65, 0.25 + b * 0.65)
	if debug_mode == TerrainWorldScript.DEBUG_LOD_RING:
		var colors: Array[Color] = [
			Color(0.26, 0.62, 0.93),
			Color(0.35, 0.78, 0.43),
			Color(0.95, 0.76, 0.28),
			Color(0.90, 0.45, 0.25),
			Color(0.66, 0.38, 0.85),
		]
		return colors[clampi(ring, 0, colors.size() - 1)]
	if debug_mode == TerrainWorldScript.DEBUG_SEAM:
		return Color(0.12, 0.12, 0.12) if ((chunk_x + chunk_z) & 1) == 0 else Color(0.78, 0.78, 0.78)
	if debug_mode == TerrainWorldScript.DEBUG_FAMILY_PALETTE:
		var sample: Dictionary = world.provider.sample(
			(float(chunk_x) + 0.5) * world.chunk_size_m,
			(float(chunk_z) + 0.5) * world.chunk_size_m,
			world.seed,
			world.region_size_m
		)
		return _family_color(str(sample.get("primary_family", "unknown")))
	return Color(0.52, 0.52, 0.50)


func _near_chunk_payload_mode() -> String:
	if use_native_chunk_workers:
		return "native_worker_mesh"
	if use_native_chunk_payloads:
		return "native_payload_mesh"
	return "cpu_mesh"


func _material_mode(material: Material) -> String:
	if material == null:
		return "missing"
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material != null:
		if _shader_texture_valid(shader_material, "height_texture"):
			return "height_texture_shader"
		if debug_mode == TerrainWorldScript.DEBUG_ELEVATION_COLOR:
			return "elevation_color_shader"
		if debug_mode == TerrainWorldScript.DEBUG_GRAY and use_fast_gray_material:
			return "fast_gray_shader"
		return "shader"
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard != null:
		if debug_mode == TerrainWorldScript.DEBUG_SURFACE_OWNER:
			return "surface_owner_color"
		return "standard"
	return material.get_class()


func _shader_texture_valid(material: Material, parameter_name: String) -> bool:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null:
		return false
	var texture: Texture2D = shader_material.get_shader_parameter(parameter_name) as Texture2D
	return texture != null


func _aabb_dictionary(aabb: AABB) -> Dictionary:
	return {
		"position": _vec3_array(aabb.position),
		"size": _vec3_array(aabb.size),
	}


func _vec3_array(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]


func _mesh_summary(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {"surface_count": 0, "vertex_count": 0, "index_count": 0}
	var vertex_count := 0
	var index_count := 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		vertex_count += vertices.size()
		index_count += indices.size()
	return {
		"surface_count": mesh.get_surface_count(),
		"vertex_count": vertex_count,
		"index_count": index_count,
	}


func _family_color(family: String) -> Color:
	match family:
		"mountain":
			return Color(0.54, 0.55, 0.58)
		"glacial":
			return Color(0.68, 0.78, 0.86)
		"badlands":
			return Color(0.76, 0.42, 0.26)
		"desert":
			return Color(0.78, 0.68, 0.40)
		"karst":
			return Color(0.50, 0.62, 0.50)
		"coast":
			return Color(0.38, 0.58, 0.67)
		"grassland":
			return Color(0.42, 0.62, 0.32)
		"rainforest":
			return Color(0.20, 0.48, 0.32)
		"volcanic":
			return Color(0.36, 0.30, 0.30)
		_:
			return Color(0.50, 0.50, 0.50)


func _retire_inactive_chunk_nodes() -> void:
	_ensure_chunk_renderer()
	var keep_keys: Dictionary = {}
	var missing_active: int = _active_missing_chunk_count()
	if defer_inactive_chunk_retire_until_active_ready and missing_active > 0:
		var retention_limit: int = mini(max_retained_inactive_chunk_nodes, missing_active * 2)
		keep_keys = _inactive_chunk_retention_keys(retention_limit)
	_chunk_renderer.call("retire_inactive", _active_info_by_key, keep_keys)


func _active_chunk_window_has_pending_visual_work() -> bool:
	if last_report.is_empty():
		return false
	if int(last_report.get("queued_build_count", 0)) > 0:
		return true
	if not _native_chunk_workers.is_empty() or not _native_worker_queue.is_empty():
		return true
	if not _gpu_provider_chunk_descriptor_workers.is_empty():
		return true
	for key_value in _active_info_by_key.keys():
		var key: String = str(key_value)
		if not chunk_nodes.has(key):
			return true
		var active_info: Dictionary = _active_info_by_key[key] as Dictionary
		if not _chunk_node_matches_active_info(key, active_info):
			return true
	return false


func _active_missing_chunk_count(radius_chunks: int = -1) -> int:
	if last_report.is_empty():
		return 0
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var missing := 0
	for key_value in _active_info_by_key.keys():
		var key: String = str(key_value)
		var active_info: Dictionary = _active_info_by_key[key] as Dictionary
		if radius_chunks >= 0:
			var dx: int = abs(int(active_info.get("chunk_x", 0)) - center_x)
			var dz: int = abs(int(active_info.get("chunk_z", 0)) - center_z)
			if max(dx, dz) > radius_chunks:
				continue
		if not chunk_nodes.has(key) or not _chunk_node_matches_active_info(key, active_info):
			missing += 1
	return missing


func _retained_inactive_chunk_count() -> int:
	var retained := 0
	for key_value in chunk_nodes.keys():
		if not _active_info_by_key.has(str(key_value)):
			retained += 1
	return retained


func _visible_chunk_count() -> int:
	var count := 0
	for node_value in chunk_nodes.values():
		var mesh_instance: MeshInstance3D = node_value as MeshInstance3D
		if mesh_instance != null and mesh_instance.visible:
			count += 1
	return count


func _standby_chunk_count() -> int:
	var count := 0
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		if not _active_info_by_key.has(key):
			continue
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		if mesh_instance != null and not mesh_instance.visible:
			count += 1
	return count


func _sync_chunk_visibility_for_runtime_window() -> void:
	if last_report.is_empty():
		return
	var visible_radius: int = _runtime_visible_radius_chunks()
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		var mesh_instance: MeshInstance3D = chunk_nodes[key] as MeshInstance3D
		if mesh_instance == null:
			continue
		var active_info: Dictionary = _active_info_by_key.get(key, {}) as Dictionary
		if active_info.is_empty():
			mesh_instance.visible = false
			continue
		var dx: int = abs(int(active_info.get("chunk_x", 0)) - center_x)
		var dz: int = abs(int(active_info.get("chunk_z", 0)) - center_z)
		mesh_instance.visible = max(dx, dz) <= visible_radius


func _active_info_in_visible_runtime_window(active_info: Dictionary) -> bool:
	if last_report.is_empty():
		return true
	var visible_radius: int = _runtime_visible_radius_chunks()
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var dx: int = abs(int(active_info.get("chunk_x", 0)) - center_x)
	var dz: int = abs(int(active_info.get("chunk_z", 0)) - center_z)
	return max(dx, dz) <= visible_radius


func _runtime_visible_radius_chunks() -> int:
	if last_report.is_empty():
		return 2147483647
	return int(last_report.get("visible_radius_chunks", last_report.get("max_visible_radius_chunks", 2147483647)))


func _inactive_chunk_retention_keys(retention_limit: int = -1) -> Dictionary:
	var retained: Dictionary = {}
	var inactive: Array[String] = []
	for key_value in chunk_nodes.keys():
		var key: String = str(key_value)
		if not _active_info_by_key.has(key):
			inactive.append(key)
	if inactive.is_empty():
		return retained
	var max_retained: int = max(0, max_retained_inactive_chunk_nodes if retention_limit < 0 else retention_limit)
	if max_retained <= 0:
		return retained
	var center: Array = last_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	inactive.sort_custom(func(a: String, b: String) -> bool:
		var ax: int = _key_x(a)
		var az: int = _key_z(a)
		var bx: int = _key_x(b)
		var bz: int = _key_z(b)
		var ar: int = max(abs(ax - center_x), abs(az - center_z))
		var br: int = max(abs(bx - center_x), abs(bz - center_z))
		if ar != br:
			return ar < br
		var ad: int = abs(ax - center_x) + abs(az - center_z)
		var bd: int = abs(bx - center_x) + abs(bz - center_z)
		if ad != bd:
			return ad < bd
		if az != bz:
			return az < bz
		return ax < bx
	)
	for index in range(min(max_retained, inactive.size())):
		retained[inactive[index]] = true
	return retained


func _ensure_chunk_renderer() -> void:
	if _chunk_renderer == null:
		_chunk_renderer = TerrainChunkRendererScript.new()
		_chunk_renderer.call("setup", self, reuse_chunk_nodes, max_pooled_chunk_nodes)
		chunk_nodes = _chunk_renderer.get("chunk_nodes") as Dictionary
	else:
		_chunk_renderer.call("sync_settings", reuse_chunk_nodes, max_pooled_chunk_nodes)
		if chunk_nodes.is_empty() and int(_chunk_renderer.call("built_chunk_count")) > 0:
			chunk_nodes = _chunk_renderer.get("chunk_nodes") as Dictionary


func _record_chunk_build_time(elapsed_ms: int) -> void:
	_last_chunk_build_ms = elapsed_ms
	_total_chunk_builds += 1
	_recent_chunk_build_ms.append(elapsed_ms)
	while _recent_chunk_build_ms.size() > _max_recent_build_samples:
		_recent_chunk_build_ms.pop_front()


func _active_info_for_key(key: String) -> Dictionary:
	if not _active_info_by_key.has(key) and not last_report.is_empty():
		_refresh_active_info_index()
	return _active_info_by_key.get(key, {}) as Dictionary


func _refresh_active_info_index() -> void:
	_active_info_by_key.clear()
	for item_value in last_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		_active_info_by_key[_chunk_key(int(item["chunk_x"]), int(item["chunk_z"]))] = item


func _chunk_key(chunk_x: int, chunk_z: int) -> String:
	return "%d,%d" % [chunk_x, chunk_z]


func _key_x(key: String) -> int:
	var parts := key.split(",", false)
	return int(parts[0]) if parts.size() > 0 else 0


func _key_z(key: String) -> int:
	var parts := key.split(",", false)
	return int(parts[1]) if parts.size() > 1 else 0
