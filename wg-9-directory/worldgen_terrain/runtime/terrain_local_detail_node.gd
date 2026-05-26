class_name TerrainLocalDetailNode
extends Node3D

const TerrainDetailTierPolicyScript := preload("res://worldgen_terrain/core/terrain_detail_tier_policy.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")
const TerrainNativeChunkPayloadWorkerScript := preload("res://worldgen_terrain/mesh/terrain_native_chunk_payload_worker.gd")
const TerrainSurfaceTextureBuilderScript := preload("res://worldgen_terrain/runtime/terrain_surface_texture_builder.gd")

@export var enabled: bool = false
@export var patch_size_m: float = TerrainDetailTierPolicyScript.DEFAULT_PATCH_SIZE_M
@export_range(17, 257, 16) var vertices_per_side: int = TerrainDetailTierPolicyScript.DEFAULT_VERTICES_PER_SIDE
@export_range(0, 2, 1) var radius_patches: int = TerrainDetailTierPolicyScript.DEFAULT_RADIUS_PATCHES
@export_range(1, 25, 1) var max_active_patches: int = 1
@export var use_native_payloads: bool = true
@export var use_native_workers: bool = true
@export_range(1, 4, 1) var max_native_workers: int = 1
@export var vertical_offset_m: float = 0.18
@export var collision_vertical_offset_m: float = 0.18
@export var use_surface_texture_material: bool = false
@export_range(0.0, 4.0, 0.05) var surface_texture_normal_strength: float = 1.0
@export var use_visual_displacement: bool = false
@export_range(0.0, 1.0, 0.01) var visual_displacement_strength: float = 0.0
@export_range(0.0, 16.0, 0.25) var visual_displacement_limit_m: float = 2.0
@export var enable_collision_bodies: bool = false
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

var world: RefCounted
var patch_nodes: Dictionary = {}
var patch_heightfields: Dictionary = {}
var collision_bodies: Dictionary = {}
var last_report: Dictionary = {}
var errors: Array[String] = []
var _native_backend: Object
var _material: ShaderMaterial
var _surface_texture_shader: Shader
var _zero_float_texture: ImageTexture
var _recent_build_ms: Array[int] = []
var _total_builds: int = 0
var _last_build_ms: int = 0
var _last_native_payload_ms: int = 0
var _last_native_worker_elapsed_ms: int = 0
var _last_mesh_assign_ms: int = 0
var _last_patch_assign_ms: int = 0
var _last_surface_texture_ms: int = 0
var _last_surface_material_reused: bool = false
var _max_recent_build_samples: int = 32
var _recent_patch_assign_ms: Array[int] = []
var _native_workers: Dictionary = {}
var _native_worker_patches: Dictionary = {}
var _native_worker_queue: Array[Dictionary] = []
var _desired_patch_keys: Dictionary = {}
var _last_material_state_key: String = ""


func _exit_tree() -> void:
	_clear_native_workers(true)
	TerrainNativeChunkPayloadWorkerScript.cleanup_detached_workers(0, true, 5000)
	clear_patches()


func setup(p_world: RefCounted) -> bool:
	clear_patches()
	errors.clear()
	world = p_world
	if world == null:
		errors.append("world_null")
		return false
	return true


func update_viewer(viewer_xz: Vector2) -> Dictionary:
	TerrainNativeChunkPayloadWorkerScript.cleanup_detached_workers()
	errors.clear()
	if not enabled:
		clear_patches()
		last_report = {
			"status": "pass",
			"enabled": false,
			"active_count": 0,
			"built_now": 0,
			"retired_now": 0,
		}
		return last_report
	if world == null:
		last_report = {"status": "fail", "error": "world_null"}
		return last_report

	var patches: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(viewer_xz, settings())
	var desired_keys: Dictionary = {}
	for patch in patches:
		desired_keys[str(patch["key"])] = patch
	_desired_patch_keys = desired_keys.duplicate()
	var retired_now: int = _retire_unwanted_patches(desired_keys)
	retired_now += _retire_stale_patches(desired_keys)
	_cancel_retired_worker_work(desired_keys)
	var built_now: int = _poll_native_workers()
	for patch in patches:
		var key: String = str(patch["key"])
		if patch_nodes.has(key) or _native_workers.has(key) or _queued_worker_has_key(key):
			continue
		if _can_use_native_workers():
			if _enqueue_native_worker_build(patch):
				continue
		var payload: Dictionary = build_patch_payload(patch)
		if payload.get("status", "fail") != "pass":
			errors.append("payload_failed:%s:%s" % [key, str(payload.get("error", "unknown"))])
			continue
		_assign_patch_payload(key, payload)
		built_now += 1
	_pump_native_worker_queue()
	built_now += _poll_native_workers()
	_sync_collision_bodies()
	_refresh_active_materials_if_needed()
	last_report = {
		"status": "pass" if errors.is_empty() else "fail",
		"enabled": true,
		"active_count": patch_nodes.size(),
		"collision_body_count": collision_bodies.size(),
		"queued_worker_builds": _native_worker_queue.size(),
		"active_native_workers": _native_workers.size(),
		"requested_count": patches.size(),
		"built_now": built_now,
		"retired_now": retired_now,
		"patch_size_m": patch_size_m,
		"vertices_per_side": vertices_per_side,
		"spacing_m": patch_size_m / float(max(1, vertices_per_side - 1)),
		"errors": errors.duplicate(),
	}
	return last_report


func settings() -> Dictionary:
	return TerrainDetailTierPolicyScript.make_settings(
		patch_size_m,
		vertices_per_side,
		radius_patches,
		max_active_patches
	)


func clear_patches() -> void:
	for node_value in patch_nodes.values():
		var mesh_instance: MeshInstance3D = node_value as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.queue_free()
	patch_nodes.clear()
	patch_heightfields.clear()
	_clear_collision_bodies()
	_clear_native_workers()
	_recent_build_ms.clear()
	_recent_patch_assign_ms.clear()
	_total_builds = 0
	_last_build_ms = 0
	_last_native_payload_ms = 0
	_last_native_worker_elapsed_ms = 0
	_last_mesh_assign_ms = 0
	_last_patch_assign_ms = 0
	_last_surface_texture_ms = 0
	_last_surface_material_reused = false


func build_patch_payload(patch: Dictionary) -> Dictionary:
	if world == null:
		return {"status": "fail", "error": "world_null"}
	var started_ms: int = Time.get_ticks_msec()
	var payload: Dictionary
	if use_native_payloads and _native_backend_available() and world.provider.has_method("native_prepared_height_grid_request"):
		payload = _build_native_patch_payload(patch)
		if payload.get("status", "fail") == "pass":
			_record_build_time(Time.get_ticks_msec() - started_ms)
			return payload
	payload = _build_gdscript_patch_payload(patch)
	_record_build_time(Time.get_ticks_msec() - started_ms)
	return payload


func build_stats() -> Dictionary:
	var total_recent := 0
	var max_recent := 0
	for value in _recent_build_ms:
		total_recent += value
		max_recent = max(max_recent, value)
	var total_recent_assign := 0
	var max_recent_assign := 0
	for value in _recent_patch_assign_ms:
		total_recent_assign += value
		max_recent_assign = max(max_recent_assign, value)
	var recent_count: int = _recent_build_ms.size()
	var recent_assign_count: int = _recent_patch_assign_ms.size()
	var count: int = max(2, vertices_per_side)
	var vertex_count: int = count * count
	var index_count: int = (count - 1) * (count - 1) * 6
	return {
		"active_patches": patch_nodes.size(),
		"active_heightfields": patch_heightfields.size(),
		"collision_bodies": collision_bodies.size(),
		"collision_enabled": enable_collision_bodies,
		"total_builds": _total_builds,
		"recent_build_count": recent_count,
		"last_build_ms": _last_build_ms,
		"avg_recent_build_ms": float(total_recent) / float(max(1, recent_count)),
		"max_recent_build_ms": max_recent,
		"last_native_payload_ms": _last_native_payload_ms,
		"last_native_worker_elapsed_ms": _last_native_worker_elapsed_ms,
		"last_mesh_assign_ms": _last_mesh_assign_ms,
		"last_patch_assign_ms": _last_patch_assign_ms,
		"avg_recent_patch_assign_ms": float(total_recent_assign) / float(max(1, recent_assign_count)),
		"max_recent_patch_assign_ms": max_recent_assign,
		"last_surface_texture_ms": _last_surface_texture_ms,
		"last_surface_material_reused": _last_surface_material_reused,
		"use_surface_texture_material": use_surface_texture_material,
		"use_visual_displacement": use_visual_displacement,
		"visual_displacement_strength": visual_displacement_strength,
		"visual_displacement_limit_m": visual_displacement_limit_m,
		"active_native_workers": _native_workers.size(),
		"queued_worker_builds": _native_worker_queue.size(),
		"vertices_per_side": count,
		"spacing_m": patch_size_m / float(count - 1),
		"vertex_count_per_patch": vertex_count,
		"index_count_per_patch": index_count,
		"bytes_estimate_per_patch": vertex_count * (4 + 12 + 12 + 8) + index_count * 4,
		"heightfield_bytes_per_patch": vertex_count * 4,
	}


func has_pending_rebuilds() -> bool:
	return not _native_workers.is_empty() or not _native_worker_queue.is_empty()


func sample_height(world_x: float, world_z: float) -> Dictionary:
	var key: String = _patch_key_for_world_position(world_x, world_z)
	if patch_heightfields.has(key):
		var heightfield: Dictionary = patch_heightfields[key] as Dictionary
		if _heightfield_contains(heightfield, world_x, world_z):
			return {
				"status": "pass",
				"source": "local_detail",
				"key": key,
				"height_m": _sample_heightfield(heightfield, world_x, world_z),
				"spacing_m": float(heightfield["spacing_m"]),
			}
	if world != null:
		return {
			"status": "pass",
			"source": "world_fallback",
			"key": "",
			"height_m": world.sample_height(world_x, world_z),
			"spacing_m": 0.0,
		}
	return {
		"status": "fail",
		"error": "world_null",
	}


func active_collision_heightfields() -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var keys: Array = patch_heightfields.keys()
	keys.sort()
	for key_value in keys:
		var key: String = str(key_value)
		var heightfield: Dictionary = patch_heightfields[key] as Dictionary
		fields.append({
			"key": key,
			"origin_x": float(heightfield["origin_x"]),
			"origin_z": float(heightfield["origin_z"]),
			"patch_size_m": float(heightfield["patch_size_m"]),
			"vertices_per_side": int(heightfield["vertices_per_side"]),
			"spacing_m": float(heightfield["spacing_m"]),
			"height": heightfield["height"] as PackedFloat32Array,
			"height_min_m": float(heightfield["height_min_m"]),
			"height_max_m": float(heightfield["height_max_m"]),
		})
	return fields


func active_surface_texture_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	var keys: Array = patch_heightfields.keys()
	keys.sort()
	for key_value in keys:
		var key: String = str(key_value)
		var heightfield: Dictionary = patch_heightfields[key] as Dictionary
		var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(
			heightfield["height"] as PackedFloat32Array,
			int(heightfield["vertices_per_side"]),
			float(heightfield["spacing_m"])
		)
		if descriptor.get("status", "fail") != "pass":
			descriptor["key"] = key
			descriptors.append(descriptor)
			continue
		descriptor["key"] = key
		descriptor["origin_x"] = float(heightfield["origin_x"])
		descriptor["origin_z"] = float(heightfield["origin_z"])
		descriptor["patch_size_m"] = float(heightfield["patch_size_m"])
		descriptors.append(descriptor)
	return descriptors


func collision_shape_for_key(key: String) -> Dictionary:
	if not patch_heightfields.has(key):
		return {
			"status": "fail",
			"error": "heightfield_not_active:%s" % key,
		}
	var heightfield: Dictionary = patch_heightfields[key] as Dictionary
	var shape := HeightMapShape3D.new()
	shape.map_width = int(heightfield["vertices_per_side"])
	shape.map_depth = int(heightfield["vertices_per_side"])
	shape.map_data = heightfield["height"] as PackedFloat32Array
	return {
		"status": "pass",
		"key": key,
		"shape": shape,
		"origin_x": float(heightfield["origin_x"]),
		"origin_z": float(heightfield["origin_z"]),
		"spacing_m": float(heightfield["spacing_m"]),
		"patch_size_m": float(heightfield["patch_size_m"]),
		"vertices_per_side": int(heightfield["vertices_per_side"]),
	}


func set_collision_bodies_enabled(value: bool) -> void:
	enable_collision_bodies = value
	_sync_collision_bodies()


func apply_surface_material_settings(
	surface_material_enabled: bool,
	normal_strength: float,
	visual_displacement_enabled: bool,
	displacement_strength: float,
	displacement_limit_m: float,
	refresh_existing: bool = true
) -> void:
	use_surface_texture_material = surface_material_enabled
	surface_texture_normal_strength = max(0.0, normal_strength)
	use_visual_displacement = visual_displacement_enabled
	visual_displacement_strength = clampf(displacement_strength, 0.0, 1.0)
	visual_displacement_limit_m = max(0.0, displacement_limit_m)
	if refresh_existing:
		refresh_active_materials()
		_last_material_state_key = _material_state_key()


func refresh_active_materials() -> void:
	var refresh_start_ms: int = Time.get_ticks_msec()
	var rebuilt_any := false
	var keys: Array = patch_nodes.keys()
	for key_value in keys:
		var key: String = str(key_value)
		var mesh_instance: MeshInstance3D = patch_nodes.get(key, null) as MeshInstance3D
		if mesh_instance == null:
			continue
		if use_surface_texture_material and patch_heightfields.has(key):
			var existing_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
			if _can_update_surface_material_in_place(existing_material):
				_update_surface_material_parameters(existing_material)
				continue
			mesh_instance.material_override = _local_detail_surface_texture_material_from_heightfield(patch_heightfields[key] as Dictionary)
			rebuilt_any = true
		else:
			if mesh_instance.material_override != _local_detail_material():
				mesh_instance.material_override = _local_detail_material()
				rebuilt_any = true
	if not rebuilt_any:
		_last_surface_texture_ms = Time.get_ticks_msec() - refresh_start_ms
		_last_surface_material_reused = true


func _can_use_native_workers() -> bool:
	return (
		use_native_workers
		and use_native_payloads
		and _native_backend_available()
		and world != null
		and world.provider != null
		and world.provider.has_method("native_prepared_height_grid_request")
	)


func _enqueue_native_worker_build(patch: Dictionary) -> bool:
	var key: String = str(patch["key"])
	var prepared: Dictionary = _prepare_native_patch_payload_request(patch)
	if prepared.get("status", "fail") != "pass":
		return false
	var queued_item: Dictionary = {
		"key": key,
		"patch": patch.duplicate(true),
		"prepared": prepared,
		"request_id": str(prepared["request_id"]),
	}
	for index in range(_native_worker_queue.size()):
		var item: Dictionary = _native_worker_queue[index] as Dictionary
		if str(item.get("key", "")) == key:
			_native_worker_queue[index] = queued_item
			return true
	_native_worker_queue.append(queued_item)
	return true


func _pump_native_worker_queue() -> void:
	while _native_workers.size() < max(1, max_native_workers) and not _native_worker_queue.is_empty():
		var item: Dictionary = _native_worker_queue.pop_front() as Dictionary
		var key: String = str(item["key"])
		if patch_nodes.has(key):
			continue
		if not _queued_patch_matches_desired(item):
			continue
		var worker: RefCounted = TerrainNativeChunkPayloadWorkerScript.new()
		if not worker.start(item["prepared"] as Dictionary):
			var payload: Dictionary = build_patch_payload(item["patch"] as Dictionary)
			if payload.get("status", "fail") == "pass":
				_assign_patch_payload(key, payload)
			else:
				errors.append("worker_start_payload_failed:%s:%s" % [key, str(payload.get("error", "unknown"))])
			continue
		_native_workers[key] = worker
		_native_worker_patches[key] = item["patch"] as Dictionary


func _poll_native_workers() -> int:
	var built_now := 0
	var keys: Array = _native_workers.keys()
	for key_value in keys:
		var key: String = str(key_value)
		var worker: RefCounted = _native_workers[key] as RefCounted
		if not worker.is_done():
			continue
		var native: Dictionary = worker.take_result()
		var patch: Dictionary = _native_worker_patches.get(key, {}) as Dictionary
		_native_workers.erase(key)
		_native_worker_patches.erase(key)
		if patch.is_empty() or patch_nodes.has(key) or not _desired_patch_keys.has(key):
			continue
		var expected_request_id: String = _patch_request_id(patch)
		if str(native.get("worker_request_id", "")) != expected_request_id:
			_enqueue_desired_patch_if_needed(key)
			continue
		if not _patch_matches_desired(patch):
			_enqueue_desired_patch_if_needed(key)
			continue
		var payload: Dictionary = _native_patch_payload_to_payload(patch, native, true)
		if payload.get("status", "fail") != "pass":
			errors.append("worker_payload_failed:%s:%s" % [key, str(payload.get("error", "unknown"))])
			continue
		_last_native_worker_elapsed_ms = int(native.get("worker_elapsed_ms", 0))
		_last_native_payload_ms = _last_native_worker_elapsed_ms
		_assign_patch_payload(key, payload)
		_record_chunk_worker_time(_last_native_worker_elapsed_ms)
		built_now += 1
	_pump_native_worker_queue()
	return built_now


func _queued_worker_has_key(key: String) -> bool:
	for item_value in _native_worker_queue:
		var item: Dictionary = item_value as Dictionary
		if str(item["key"]) == key and _queued_patch_matches_desired(item):
			return true
	return false


func _cancel_retired_worker_work(desired_keys: Dictionary) -> void:
	var filtered: Array[Dictionary] = []
	for item_value in _native_worker_queue:
		var item: Dictionary = item_value as Dictionary
		var key: String = str(item["key"])
		if desired_keys.has(key) and _queued_patch_matches_desired(item):
			filtered.append(item)
	_native_worker_queue = filtered


func _clear_native_workers(wait_for_running: bool = false) -> void:
	for worker_value in _native_workers.values():
		var worker: RefCounted = worker_value as RefCounted
		if worker.call("is_done"):
			worker.call("take_result")
		elif wait_for_running:
			worker.call("wait_for_result", 5000)
		else:
			worker.call("detach_until_done")
	_native_workers.clear()
	_native_worker_patches.clear()
	_native_worker_queue.clear()
	_desired_patch_keys.clear()
	_last_material_state_key = ""


func _build_native_patch_payload(patch: Dictionary) -> Dictionary:
	var prepared: Dictionary = _prepare_native_patch_payload_request(patch)
	if prepared.get("status", "fail") != "pass":
		return prepared
	var native_start_ms: int = Time.get_ticks_msec()
	var native: Dictionary = _run_native_patch_payload(prepared)
	_last_native_payload_ms = Time.get_ticks_msec() - native_start_ms
	return _native_patch_payload_to_payload(patch, native, true)


func _prepare_native_patch_payload_request(patch: Dictionary) -> Dictionary:
	var count: int = int(patch["vertices_per_side"])
	var step_m: float = float(patch["spacing_m"])
	var origin_x: float = float(patch["origin_x"])
	var origin_z: float = float(patch["origin_z"])
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
	return {
		"status": "pass",
		"request_id": _patch_request_id(patch),
		"origin_x": origin_x,
		"origin_z": origin_z,
		"step_m": step_m,
		"count": count,
		"include_visual_displacement": use_surface_texture_material and use_visual_displacement,
		"world_seed": world.seed,
		"region_size_m": world.region_size_m,
		"base_rx": int(prepared["base_rx"]),
		"base_rz": int(prepared["base_rz"]),
		"corner_entries": prepared["corner_entries"] as Array,
	}


func _patch_request_id(patch: Dictionary) -> String:
	return "%s:%s:%s:%s:%d:%s:%d:%s:%d:%d" % [
		str(patch.get("key", "")),
		_float_request_id(float(patch.get("origin_x", INF))),
		_float_request_id(float(patch.get("origin_z", INF))),
		_float_request_id(float(patch.get("patch_size_m", 0.0))),
		int(patch.get("vertices_per_side", -1)),
		_float_request_id(float(patch.get("spacing_m", 0.0))),
		int(world.seed) if world != null else -1,
		_float_request_id(float(world.region_size_m)) if world != null else "nan",
		1 if use_surface_texture_material else 0,
		1 if use_visual_displacement else 0,
	]


func _float_request_id(value: float) -> String:
	return "%.9f" % value


func _patch_matches_desired(patch: Dictionary) -> bool:
	var key: String = str(patch.get("key", ""))
	if key.is_empty() or not _desired_patch_keys.has(key):
		return false
	var desired: Dictionary = _desired_patch_keys[key] as Dictionary
	if int(patch.get("patch_x", 0)) != int(desired.get("patch_x", 1)):
		return false
	if int(patch.get("patch_z", 0)) != int(desired.get("patch_z", 1)):
		return false
	if int(patch.get("ring", -1)) != int(desired.get("ring", -2)):
		return false
	if int(patch.get("vertices_per_side", -1)) != int(desired.get("vertices_per_side", -2)):
		return false
	if not is_equal_approx(float(patch.get("origin_x", INF)), float(desired.get("origin_x", -INF))):
		return false
	if not is_equal_approx(float(patch.get("origin_z", INF)), float(desired.get("origin_z", -INF))):
		return false
	if not is_equal_approx(float(patch.get("patch_size_m", -1.0)), float(desired.get("patch_size_m", -2.0))):
		return false
	if not is_equal_approx(float(patch.get("spacing_m", -1.0)), float(desired.get("spacing_m", -2.0))):
		return false
	return true


func _queued_patch_matches_desired(item: Dictionary) -> bool:
	var patch: Dictionary = item.get("patch", {}) as Dictionary
	if not _patch_matches_desired(patch):
		return false
	return str(item.get("request_id", "")) == _patch_request_id(patch)


func _enqueue_desired_patch_if_needed(key: String) -> void:
	if not _desired_patch_keys.has(key) or patch_nodes.has(key) or _queued_worker_has_key(key):
		return
	if _can_use_native_workers():
		_enqueue_native_worker_build(_desired_patch_keys[key] as Dictionary)


func _run_native_patch_payload(prepared: Dictionary) -> Dictionary:
	var native: Dictionary = _native_backend.call(
		"build_chunk_payload_prepared",
		float(prepared["origin_x"]),
		float(prepared["origin_z"]),
		float(prepared["step_m"]),
		int(prepared["count"]),
		int(prepared["world_seed"]),
		float(prepared["region_size_m"]),
		int(prepared["base_rx"]),
		int(prepared["base_rz"]),
		prepared["corner_entries"] as Array
	) as Dictionary
	if native.get("status", "fail") == "pass" and bool(prepared.get("include_visual_displacement", false)):
		var displacement: Dictionary = _native_backend.call(
			"build_visual_displacement_from_height",
			native["height"] as PackedFloat32Array,
			int(prepared["count"]),
			1
		) as Dictionary
		if displacement.get("status", "fail") == "pass":
			native["visual_displacement_values"] = displacement["values"] as PackedFloat32Array
			native["visual_displacement_max_abs_m"] = float(displacement["max_abs_m"])
		else:
			native["status"] = "fail"
			native["error"] = "visual_displacement:%s" % str(displacement.get("error", "unknown"))
	return native


func _native_patch_payload_to_payload(patch: Dictionary, native: Dictionary, native_payload: bool) -> Dictionary:
	if native.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": "native_payload:%s" % str(native.get("error", "unknown")),
		}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = native["vertices"] as PackedVector3Array
	arrays[Mesh.ARRAY_NORMAL] = native["normals"] as PackedVector3Array
	arrays[Mesh.ARRAY_TEX_UV] = native["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = native["indices"] as PackedInt32Array
	var payload: Dictionary = _make_payload(patch, native["height"] as PackedFloat32Array, arrays, native_payload)
	if native.has("visual_displacement_values"):
		payload["visual_displacement_values"] = native["visual_displacement_values"] as PackedFloat32Array
		payload["visual_displacement_max_abs_m"] = float(native.get("visual_displacement_max_abs_m", 0.0))
	return payload


func _build_gdscript_patch_payload(patch: Dictionary) -> Dictionary:
	var count: int = int(patch["vertices_per_side"])
	var step_m: float = float(patch["spacing_m"])
	var height: PackedFloat32Array = world.sample_height_grid(
		float(patch["origin_x"]),
		float(patch["origin_z"]),
		step_m,
		count,
		count
	)
	if height.size() != count * count:
		return {
			"status": "fail",
			"error": "height_size:%d expected:%d" % [height.size(), count * count],
		}
	var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(height, count, step_m, PackedColorArray())
	return _make_payload(patch, height, arrays, false)


func _make_payload(patch: Dictionary, height: PackedFloat32Array, arrays: Array, native_payload: bool) -> Dictionary:
	return {
		"status": "pass",
		"key": str(patch["key"]),
		"patch_x": int(patch["patch_x"]),
		"patch_z": int(patch["patch_z"]),
		"origin_x": float(patch["origin_x"]),
		"origin_z": float(patch["origin_z"]),
		"patch_size_m": float(patch["patch_size_m"]),
		"vertices_per_side": int(patch["vertices_per_side"]),
		"spacing_m": float(patch["spacing_m"]),
		"ring": int(patch["ring"]),
		"height": height,
		"normals": arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array,
		"arrays": arrays,
		"native_payload": native_payload,
	}


func _assign_patch_payload(key: String, payload: Dictionary) -> void:
	var assign_start_ms: int = Time.get_ticks_msec()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "local_detail_%s" % key.replace(",", "_")
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(float(payload["origin_x"]), vertical_offset_m, float(payload["origin_z"]))
	var mesh_start_ms: int = Time.get_ticks_msec()
	mesh_instance.mesh = TerrainMeshBuilderScript.build_array_mesh(payload["arrays"] as Array)
	_last_mesh_assign_ms = Time.get_ticks_msec() - mesh_start_ms
	mesh_instance.material_override = _material_for_payload(payload)
	mesh_instance.set_meta("detail_key", key)
	mesh_instance.set_meta("patch_x", int(payload["patch_x"]))
	mesh_instance.set_meta("patch_z", int(payload["patch_z"]))
	mesh_instance.set_meta("spacing_m", float(payload["spacing_m"]))
	add_child(mesh_instance)
	patch_nodes[key] = mesh_instance
	patch_heightfields[key] = _heightfield_from_payload(payload)
	_record_patch_assign_time(Time.get_ticks_msec() - assign_start_ms)


func _retire_unwanted_patches(desired_keys: Dictionary) -> int:
	var retired := 0
	var existing: Array = patch_nodes.keys()
	for key_value in existing:
		var key: String = str(key_value)
		if desired_keys.has(key):
			continue
		var mesh_instance: MeshInstance3D = patch_nodes[key] as MeshInstance3D
		patch_nodes.erase(key)
		patch_heightfields.erase(key)
		_release_collision_body(key)
		if mesh_instance != null:
			mesh_instance.queue_free()
		retired += 1
	return retired


func _retire_stale_patches(desired_keys: Dictionary) -> int:
	var retired := 0
	var existing: Array = patch_nodes.keys()
	for key_value in existing:
		var key: String = str(key_value)
		if not desired_keys.has(key):
			continue
		if _active_patch_matches_desired(key, desired_keys[key] as Dictionary):
			continue
		var mesh_instance: MeshInstance3D = patch_nodes[key] as MeshInstance3D
		patch_nodes.erase(key)
		patch_heightfields.erase(key)
		_release_collision_body(key)
		if mesh_instance != null:
			mesh_instance.queue_free()
		retired += 1
	return retired


func _active_patch_matches_desired(key: String, desired: Dictionary) -> bool:
	if not patch_heightfields.has(key):
		return false
	var heightfield: Dictionary = patch_heightfields[key] as Dictionary
	if int(heightfield.get("vertices_per_side", -1)) != int(desired.get("vertices_per_side", -2)):
		return false
	if not is_equal_approx(float(heightfield.get("origin_x", INF)), float(desired.get("origin_x", -INF))):
		return false
	if not is_equal_approx(float(heightfield.get("origin_z", INF)), float(desired.get("origin_z", -INF))):
		return false
	if not is_equal_approx(float(heightfield.get("patch_size_m", -1.0)), float(desired.get("patch_size_m", -2.0))):
		return false
	if not is_equal_approx(float(heightfield.get("spacing_m", -1.0)), float(desired.get("spacing_m", -2.0))):
		return false
	return true


func _native_backend_available() -> bool:
	if _native_backend != null:
		return true
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return false
	_native_backend = ClassDB.instantiate("Wg9TerrainNativeBackend")
	return _native_backend != null


func _record_build_time(elapsed_ms: int) -> void:
	_last_build_ms = elapsed_ms
	_total_builds += 1
	_recent_build_ms.append(elapsed_ms)
	while _recent_build_ms.size() > _max_recent_build_samples:
		_recent_build_ms.pop_front()


func _record_chunk_worker_time(elapsed_ms: int) -> void:
	_record_build_time(elapsed_ms)


func _record_patch_assign_time(elapsed_ms: int) -> void:
	_last_patch_assign_ms = elapsed_ms
	_recent_patch_assign_ms.append(elapsed_ms)
	while _recent_patch_assign_ms.size() > _max_recent_build_samples:
		_recent_patch_assign_ms.pop_front()


func _heightfield_from_payload(payload: Dictionary) -> Dictionary:
	var height: PackedFloat32Array = payload["height"] as PackedFloat32Array
	var height_min := INF
	var height_max := -INF
	for value in height:
		var height_m: float = float(value)
		height_min = min(height_min, height_m)
		height_max = max(height_max, height_m)
	return {
		"key": str(payload["key"]),
		"origin_x": float(payload["origin_x"]),
		"origin_z": float(payload["origin_z"]),
		"patch_size_m": float(payload["patch_size_m"]),
		"vertices_per_side": int(payload["vertices_per_side"]),
		"spacing_m": float(payload["spacing_m"]),
		"height": height,
		"normals": payload["normals"] as PackedVector3Array,
		"visual_displacement_values": payload.get("visual_displacement_values", PackedFloat32Array()) as PackedFloat32Array,
		"height_min_m": height_min,
		"height_max_m": height_max,
	}


func _patch_key_for_world_position(world_x: float, world_z: float) -> String:
	var coord: Vector2i = TerrainDetailTierPolicyScript.patch_coord_for_position(Vector2(world_x, world_z), patch_size_m)
	return "%d,%d" % [coord.x, coord.y]


func _refresh_active_materials_if_needed() -> void:
	var key: String = _material_state_key()
	if key == _last_material_state_key:
		return
	_last_material_state_key = key
	refresh_active_materials()


func _material_state_key() -> String:
	return "%d:%.6f:%d:%.6f:%.6f" % [
		1 if use_surface_texture_material else 0,
		surface_texture_normal_strength,
		1 if use_visual_displacement else 0,
		visual_displacement_strength,
		visual_displacement_limit_m,
	]


func _heightfield_contains(heightfield: Dictionary, world_x: float, world_z: float) -> bool:
	var origin_x: float = float(heightfield["origin_x"])
	var origin_z: float = float(heightfield["origin_z"])
	var size_m: float = float(heightfield["patch_size_m"])
	return (
		world_x >= origin_x
		and world_z >= origin_z
		and world_x <= origin_x + size_m
		and world_z <= origin_z + size_m
	)


func _sample_heightfield(heightfield: Dictionary, world_x: float, world_z: float) -> float:
	var height: PackedFloat32Array = heightfield["height"] as PackedFloat32Array
	var count: int = int(heightfield["vertices_per_side"])
	var spacing_m: float = float(heightfield["spacing_m"])
	var fx: float = clampf((world_x - float(heightfield["origin_x"])) / spacing_m, 0.0, float(count - 1))
	var fz: float = clampf((world_z - float(heightfield["origin_z"])) / spacing_m, 0.0, float(count - 1))
	var x0: int = int(floor(fx))
	var z0: int = int(floor(fz))
	var x1: int = min(count - 1, x0 + 1)
	var z1: int = min(count - 1, z0 + 1)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var a: float = float(height[z0 * count + x0])
	var b: float = float(height[z0 * count + x1])
	var c: float = float(height[z1 * count + x0])
	var d: float = float(height[z1 * count + x1])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _sync_collision_bodies() -> void:
	if not enable_collision_bodies:
		_clear_collision_bodies()
		return
	var active_keys: Dictionary = {}
	for key_value in patch_heightfields.keys():
		var key: String = str(key_value)
		active_keys[key] = true
		if collision_bodies.has(key):
			continue
		var shape_result: Dictionary = collision_shape_for_key(key)
		if shape_result.get("status", "fail") != "pass":
			errors.append("collision_shape_failed:%s:%s" % [key, str(shape_result.get("error", "unknown"))])
			continue
		collision_bodies[key] = _create_collision_body(key, shape_result)
	var existing: Array = collision_bodies.keys()
	for key_value in existing:
		var key: String = str(key_value)
		if active_keys.has(key):
			continue
		_release_collision_body(key)


func _create_collision_body(key: String, shape_result: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "local_detail_collision_%s" % key.replace(",", "_")
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	var spacing_m: float = float(shape_result["spacing_m"])
	var patch_size: float = float(shape_result["patch_size_m"])
	body.position = Vector3(
		float(shape_result["origin_x"]) + patch_size * 0.5,
		collision_vertical_offset_m,
		float(shape_result["origin_z"]) + patch_size * 0.5
	)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "HeightMapShape"
	collision_shape.shape = shape_result["shape"] as Shape3D
	collision_shape.scale = Vector3(spacing_m, 1.0, spacing_m)
	body.add_child(collision_shape)
	body.set_meta("detail_key", key)
	body.set_meta("spacing_m", spacing_m)
	body.set_meta("patch_size_m", patch_size)
	add_child(body)
	return body


func _release_collision_body(key: String) -> void:
	if not collision_bodies.has(key):
		return
	var body: StaticBody3D = collision_bodies[key] as StaticBody3D
	collision_bodies.erase(key)
	if body != null:
		body.queue_free()


func _clear_collision_bodies() -> void:
	var keys: Array = collision_bodies.keys()
	for key_value in keys:
		_release_collision_body(str(key_value))


func _local_detail_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying float height_m;
varying vec3 normal_local;

void vertex() {
	height_m = VERTEX.y;
	normal_local = NORMAL;
}

void fragment() {
	vec3 n = normalize(normal_local);
	vec3 light_dir = normalize(vec3(-0.35, 0.80, -0.48));
	float lambert = dot(n, light_dir) * 0.5 + 0.5;
	float height_tone = 0.5 + atan(height_m / 1600.0) / 3.14159265;
	float shade = clamp(0.18 + lambert * 0.58 + height_tone * 0.18, 0.10, 0.88);
	ALBEDO = mix(vec3(shade), vec3(0.18, 0.34, 0.36), 0.18);
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	return _material


func _material_for_payload(payload: Dictionary) -> ShaderMaterial:
	if use_surface_texture_material:
		var material: ShaderMaterial = _local_detail_surface_texture_material(payload)
		if material != null:
			return material
	return _local_detail_material()


func _local_detail_surface_texture_material(payload: Dictionary) -> ShaderMaterial:
	return _local_detail_surface_texture_material_from_heightfield({
		"key": str(payload.get("key", "")),
		"height": payload["height"] as PackedFloat32Array,
		"normals": payload["normals"] as PackedVector3Array,
		"vertices_per_side": int(payload["vertices_per_side"]),
		"spacing_m": float(payload["spacing_m"]),
		"visual_displacement_values": payload.get("visual_displacement_values", PackedFloat32Array()) as PackedFloat32Array,
	})


func _local_detail_surface_texture_material_from_heightfield(heightfield: Dictionary) -> ShaderMaterial:
	var texture_start_ms: int = Time.get_ticks_msec()
	_last_surface_material_reused = false
	if use_visual_displacement:
		_ensure_native_visual_displacement(heightfield)
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(
		heightfield["height"] as PackedFloat32Array,
		int(heightfield["vertices_per_side"]),
		float(heightfield["spacing_m"]),
		false,
		use_visual_displacement,
		heightfield.get("normals", PackedVector3Array()) as PackedVector3Array,
		heightfield.get("visual_displacement_values", PackedFloat32Array()) as PackedFloat32Array
	)
	_last_surface_texture_ms = Time.get_ticks_msec() - texture_start_ms
	if descriptor.get("status", "fail") != "pass":
		errors.append("surface_texture_descriptor_failed:%s:%s" % [str(heightfield.get("key", "")), str(descriptor.get("error", "unknown"))])
		return _local_detail_material()

	var height_texture: ImageTexture = ImageTexture.create_from_image(descriptor["height_image"] as Image)
	var normal_texture: ImageTexture = ImageTexture.create_from_image(descriptor["normal_image"] as Image)
	var displacement_texture: ImageTexture = (
		ImageTexture.create_from_image(descriptor["visual_displacement_image"] as Image)
		if use_visual_displacement
		else _zero_float_texture_1x1()
	)
	var displacement_max_abs: float = float(descriptor.get("visual_displacement_max_abs_m", 0.0))
	var material := ShaderMaterial.new()
	material.shader = _local_detail_surface_texture_shader()
	material.set_shader_parameter("height_texture", height_texture)
	material.set_shader_parameter("normal_texture", normal_texture)
	material.set_shader_parameter("visual_displacement_texture", displacement_texture)
	material.set_shader_parameter("height_min_m", float(descriptor["height_min_m"]))
	material.set_shader_parameter("height_range_m", max(0.000001, float(descriptor["height_range_m"])))
	material.set_shader_parameter("visual_displacement_max_abs_m", displacement_max_abs)
	material.set_meta("local_detail_surface_material", true)
	material.set_meta("has_visual_displacement_texture", use_visual_displacement)
	_update_surface_material_parameters(material)
	return material


func _ensure_native_visual_displacement(heightfield: Dictionary) -> void:
	var count: int = int(heightfield["vertices_per_side"])
	var existing: PackedFloat32Array = heightfield.get("visual_displacement_values", PackedFloat32Array()) as PackedFloat32Array
	if existing.size() == count * count:
		return
	if not _native_backend_available():
		return
	var displacement: Dictionary = _native_backend.call(
		"build_visual_displacement_from_height",
		heightfield["height"] as PackedFloat32Array,
		count,
		1
	) as Dictionary
	if displacement.get("status", "fail") != "pass":
		errors.append("native_visual_displacement_failed:%s:%s" % [str(heightfield.get("key", "")), str(displacement.get("error", "unknown"))])
		return
	heightfield["visual_displacement_values"] = displacement["values"] as PackedFloat32Array
	heightfield["visual_displacement_max_abs_m"] = float(displacement.get("max_abs_m", 0.0))


func _can_update_surface_material_in_place(material: ShaderMaterial) -> bool:
	if material == null:
		return false
	if not bool(material.get_meta("local_detail_surface_material", false)):
		return false
	if use_visual_displacement and not bool(material.get_meta("has_visual_displacement_texture", false)):
		return false
	return true


func _update_surface_material_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("normal_strength", surface_texture_normal_strength)
	material.set_shader_parameter("visual_displacement_strength", visual_displacement_strength if use_visual_displacement else 0.0)
	material.set_shader_parameter("visual_displacement_limit_m", max(0.0, visual_displacement_limit_m))


func _local_detail_surface_texture_shader() -> Shader:
	if _surface_texture_shader != null:
		return _surface_texture_shader
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D height_texture : filter_linear;
uniform sampler2D normal_texture : filter_linear;
uniform sampler2D visual_displacement_texture : filter_linear;
uniform float height_min_m = 0.0;
uniform float height_range_m = 1.0;
uniform float normal_strength = 1.0;
uniform float visual_displacement_strength = 0.0;
uniform float visual_displacement_limit_m = 2.0;
uniform float visual_displacement_max_abs_m = 0.0;

varying vec2 local_uv;

void vertex() {
	local_uv = UV;
	if (visual_displacement_strength > 0.0) {
		float visual_displacement_m = clamp(texture(visual_displacement_texture, local_uv).r, -visual_displacement_limit_m, visual_displacement_limit_m);
		VERTEX += NORMAL * visual_displacement_m * visual_displacement_strength;
	}
}

void fragment() {
	float height_m = texture(height_texture, local_uv).r;
	float height_tone = clamp((height_m - height_min_m) / max(height_range_m, 0.000001), 0.0, 1.0);
	vec3 normal_sample = normalize(texture(normal_texture, local_uv).rgb * 2.0 - 1.0);
	vec3 mesh_normal = normalize(NORMAL);
	vec3 n = normalize(mesh_normal + normal_sample * clamp(normal_strength, 0.0, 4.0));
	vec3 light_dir = normalize(vec3(-0.35, 0.80, -0.48));
	float lambert = dot(n, light_dir) * 0.5 + 0.5;
	float displacement_t = 0.0;
	if (visual_displacement_strength > 0.0) {
		displacement_t = clamp(abs(texture(visual_displacement_texture, local_uv).r) / max(visual_displacement_max_abs_m, 0.000001), 0.0, 1.0);
	}
	float shade = clamp(0.20 + lambert * 0.55 + height_tone * 0.20 + displacement_t * visual_displacement_strength * 0.04, 0.12, 0.86);
	ALBEDO = mix(vec3(shade), vec3(0.16, 0.32, 0.34), 0.16);
}
"""
	_surface_texture_shader = shader
	return _surface_texture_shader


func _zero_float_texture_1x1() -> ImageTexture:
	if _zero_float_texture != null:
		return _zero_float_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RF)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	_zero_float_texture = ImageTexture.create_from_image(image)
	return _zero_float_texture
