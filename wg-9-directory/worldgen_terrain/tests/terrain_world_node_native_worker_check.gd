extends SceneTree

const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
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
	node.use_native_chunk_workers = true
	node.max_native_chunk_workers = 3
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
		node.queue_free()
		for error in errors:
			push_error(error)
		print("[wg9-terrain-node-native-worker] status=fail errors=%d stats={}" % errors.size())
		quit(1)
		return
	_check_native_request_validation(node, errors)
	_check_native_failure_cpu_fallback(node, errors)
	_check_native_queue_dedupe(node, errors)
	_check_native_target_signature(node, errors)
	_check_debug_mode_clears_native_work(node, errors)
	_check_fast_gray_material_refresh(node, errors)
	_check_flat_provider_native_fallback(errors)
	_check_pass_corridor_profile_rebuilds_with_cpu_fallback(errors)
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 1,
		"max_lod": 4,
		"build_budget_per_frame": 3,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	for _index in range(40):
		node.update_viewer(Vector2.ZERO)
		var stats: Dictionary = node.build_stats()
		if int(node.built_chunk_count()) >= 9 and int(stats["active_native_workers"]) == 0 and int(stats["queued_native_worker_builds"]) == 0:
			break
		OS.delay_msec(5)
	var stats: Dictionary = node.build_stats()
	if int(node.built_chunk_count()) != 9:
		errors.append("built_chunk_count:%d" % int(node.built_chunk_count()))
	if int(stats["active_native_workers"]) != 0:
		errors.append("active_native_workers:%d" % int(stats["active_native_workers"]))
	if int(stats["queued_native_worker_builds"]) != 0:
		errors.append("queued_native_worker_builds:%d" % int(stats["queued_native_worker_builds"]))
	if int(stats["total_chunk_builds"]) != 9:
		errors.append("total_chunk_builds:%d" % int(stats["total_chunk_builds"]))
	if int(stats["last_native_worker_elapsed_ms"]) <= 0:
		errors.append("last_native_worker_elapsed_ms:%d" % int(stats["last_native_worker_elapsed_ms"]))
	for mesh_instance_value in node.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_instance_value as MeshInstance3D
		var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if mesh == null:
			errors.append("mesh_null:%s" % mesh_instance.name)
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vertex_count != 129 * 129:
			errors.append("vertex_count:%s:%d" % [mesh_instance.name, vertex_count])
			break
	node.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-node-native-worker] status=fail errors=%d stats=%s" % [errors.size(), str(stats)])
		quit(1)
		return
	print("[wg9-terrain-node-native-worker] status=pass chunks=%d stats=%s" % [int(node.built_chunk_count()), str(stats)])
	quit(0)


func _check_native_request_validation(node: Node3D, errors: Array[String]) -> void:
	var prepared: Dictionary = node.world.provider.native_prepared_height_grid_request(
		0.0,
		0.0,
		TerrainSettingsScript.CHUNK_SIZE_M / 32.0,
		33,
		33,
		node.world.seed,
		node.world.region_size_m
	)
	var valid_result: Dictionary = node._validate_native_prepared_chunk_payload(prepared, {})
	if valid_result.get("status", "fail") != "pass":
		errors.append("valid_native_request_rejected:%s" % str(valid_result))
		return
	var bad_prepared: Dictionary = prepared.duplicate(true)
	var corners: Array = (bad_prepared["corner_entries"] as Array).duplicate(true)
	var corner: Dictionary = (corners[0] as Dictionary).duplicate(true)
	var entries: Array = (corner["entries"] as Array).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["rows"] = 3
	entry["cols"] = 3
	entry["values"] = PackedFloat32Array([0.0, 1.0, 2.0])
	entries[0] = entry
	corner["entries"] = entries
	corners[0] = corner
	bad_prepared["corner_entries"] = corners
	var bad_result: Dictionary = node._validate_native_prepared_chunk_payload(bad_prepared, {})
	if bad_result.get("status", "pass") != "fail":
		errors.append("invalid_native_request_accepted:%s" % str(bad_result))


func _check_native_failure_cpu_fallback(node: Node3D, errors: Array[String]) -> void:
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		0,
		0,
		33,
		TerrainSettingsScript.CHUNK_SIZE_M,
		0,
		0,
		TerrainWorldScript.DEBUG_GRAY
	)
	var converted: Dictionary = node._native_chunk_payload_to_job_payload(request, {
		"status": "fail",
		"error": "forced_test_failure",
	})
	if converted.get("status", "pass") != "fail":
		errors.append("native_failure_payload_not_rejected:%s" % str(converted))
	var fallback: Dictionary = node._build_cpu_chunk_payload_from_request(request)
	if fallback.get("status", "fail") != "pass":
		errors.append("cpu_fallback_failed:%s" % str(fallback))
		return
	var arrays: Array = fallback["arrays"] as Array
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	if vertices.size() != 33 * 33:
		errors.append("cpu_fallback_vertices:%d" % vertices.size())
	if indices.size() != 32 * 32 * 6:
		errors.append("cpu_fallback_indices:%d" % indices.size())


func _check_native_queue_dedupe(node: Node3D, errors: Array[String]) -> void:
	node.last_report = {
		"active_chunks": [
			{"chunk_x": 0, "chunk_z": 0, "ring": 0, "lod": 0},
		],
	}
	node._enqueue_native_worker_build("0,0", 0, 0, 0, 0)
	node._enqueue_native_worker_build("0,0", 0, 0, 2, 2)
	if node._native_worker_queue.size() != 1:
		errors.append("native_queue_duplicate_count:%d" % node._native_worker_queue.size())
	elif int(node._native_worker_queue[0].get("lod", -1)) != 2:
		errors.append("native_queue_dedupe_did_not_replace:%s" % str(node._native_worker_queue[0]))
	node.last_report = {"active_chunks": []}
	node._prune_native_worker_queue()
	if not node._native_worker_queue.is_empty():
		errors.append("native_queue_stale_not_pruned:%s" % str(node._native_worker_queue))


func _check_native_target_signature(node: Node3D, errors: Array[String]) -> void:
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.world.set_debug_mode(TerrainWorldScript.DEBUG_GRAY)
	node.world.chunk_size_m = TerrainSettingsScript.CHUNK_SIZE_M
	var active: Dictionary = {"chunk_x": 0, "chunk_z": 0, "ring": 0, "lod": 0}
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		0,
		0,
		129,
		TerrainSettingsScript.CHUNK_SIZE_M,
		0,
		0,
		TerrainWorldScript.DEBUG_GRAY
	)
	var request_id: String = node._native_chunk_request_id("0,0", request)
	if request_id != "0,0:0:0:129:gray":
		errors.append("native_request_id:%s" % request_id)
	if not node._native_request_matches_active_target(request, active):
		errors.append("native_target_signature_rejected_valid")
	var wrong_lod: Dictionary = request.duplicate()
	wrong_lod["lod"] = 1
	if node._native_request_matches_active_target(wrong_lod, active):
		errors.append("native_target_signature_accepted_wrong_lod")
	var wrong_count: Dictionary = request.duplicate()
	wrong_count["vertices_per_side"] = 65
	if node._native_request_matches_active_target(wrong_count, active):
		errors.append("native_target_signature_accepted_wrong_count")
	var wrong_debug: Dictionary = request.duplicate()
	wrong_debug["debug_mode"] = TerrainWorldScript.DEBUG_SEAM
	if node._native_request_matches_active_target(wrong_debug, active):
		errors.append("native_target_signature_accepted_wrong_debug")


func _check_debug_mode_clears_native_work(node: Node3D, errors: Array[String]) -> void:
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.use_fast_gray_material = true
	node.use_native_chunk_workers = true
	node.use_native_chunk_payloads = true
	node.last_report = {
		"active_chunks": [
			{"chunk_x": 0, "chunk_z": 0, "ring": 0, "lod": 0},
		],
	}
	node._enqueue_native_worker_build("0,0", 0, 0, 0, 0)
	if node._native_worker_queue.is_empty():
		errors.append("native_queue_not_seeded_for_debug_switch")
	node.apply_debug_mode(TerrainWorldScript.DEBUG_HYDROLOGY)
	if not node._native_worker_queue.is_empty():
		errors.append("native_queue_not_cleared_on_hydrology:%s" % str(node._native_worker_queue))
	if not node._native_chunk_workers.is_empty():
		errors.append("native_workers_not_cleared_on_hydrology:%d" % node._native_chunk_workers.size())
	node.apply_debug_mode(TerrainWorldScript.DEBUG_GRAY)


func _check_fast_gray_material_refresh(node: Node3D, errors: Array[String]) -> void:
	node.fast_gray_exposure = 0.25
	node.fast_gray_contrast = 1.25
	var material: ShaderMaterial = node._fast_gray_material()
	node.fast_gray_exposure = 0.55
	node.fast_gray_contrast = 1.55
	var same_material: ShaderMaterial = node._fast_gray_material()
	if same_material != material:
		errors.append("fast_gray_material_not_cached")
	if absf(float(same_material.get_shader_parameter("gray_exposure")) - 0.55) > 0.000001:
		errors.append("fast_gray_exposure_not_refreshed:%s" % str(same_material.get_shader_parameter("gray_exposure")))
	if absf(float(same_material.get_shader_parameter("gray_contrast")) - 1.55) > 0.000001:
		errors.append("fast_gray_contrast_not_refreshed:%s" % str(same_material.get_shader_parameter("gray_contrast")))


func _check_flat_provider_native_fallback(errors: Array[String]) -> void:
	var flat_node: Node3D = TerrainWorldNodeScript.new()
	flat_node.auto_setup_on_ready = false
	flat_node.vertices_per_side = 33
	flat_node.use_fast_gray_material = true
	flat_node.use_native_chunk_payloads = true
	flat_node.use_native_chunk_workers = true
	flat_node.max_native_chunk_workers = 2
	get_root().add_child(flat_node)
	if not flat_node.setup_world(TerrainWorldScript.PROVIDER_FLAT, 1337):
		errors.append("flat_setup_failed:%s" % str(flat_node.errors))
		flat_node.queue_free()
		return
	flat_node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 0,
		"max_lod": 0,
		"build_budget_per_frame": 1,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	for _index in range(8):
		flat_node.update_viewer(Vector2.ZERO)
	if flat_node.built_chunk_count() != 1:
		errors.append("flat_native_fallback_chunk_count:%d" % flat_node.built_chunk_count())
	if int(flat_node.build_stats().get("active_native_workers", 0)) != 0:
		errors.append("flat_native_workers_started:%s" % str(flat_node.build_stats()))
	if int(flat_node.build_stats().get("queued_native_worker_builds", 0)) != 0:
		errors.append("flat_native_queue_started:%s" % str(flat_node.build_stats()))
	flat_node.queue_free()


func _check_pass_corridor_profile_rebuilds_with_cpu_fallback(errors: Array[String]) -> void:
	var corridor_node: Node3D = TerrainWorldNodeScript.new()
	corridor_node.auto_setup_on_ready = false
	corridor_node.vertices_per_side = 65
	corridor_node.debug_mode = TerrainWorldScript.DEBUG_HEIGHT_BANDS
	corridor_node.use_fast_gray_material = false
	corridor_node.use_native_chunk_payloads = true
	corridor_node.use_native_chunk_workers = true
	corridor_node.max_native_chunk_workers = 2
	corridor_node.allow_profile_fallback_sync_rebuilds = true
	get_root().add_child(corridor_node)
	if not corridor_node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("corridor_node_setup_failed:%s" % str(corridor_node.errors))
		corridor_node.queue_free()
		return
	var best_mid: Vector2 = _best_pass_corridor_mid(corridor_node.world)
	corridor_node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 0,
		"max_lod": 0,
		"build_budget_per_frame": 1,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	for _index in range(4):
		corridor_node.update_viewer(best_mid)
	corridor_node.rebuild_all_active_for_preview(0)
	if corridor_node.built_chunk_count() != 1:
		errors.append("corridor_initial_chunk_count:%d" % corridor_node.built_chunk_count())
		corridor_node.queue_free()
		return
	var before_cpu_count: int = int(corridor_node.build_stats().get("cpu_chunk_payload_count", 0))
	var profile := {
		"id": "pass_shaping_node_probe",
		"settings": {
			"macro_relief_scale": 1.0,
			"kernel_relief_strength": 1.0,
			"mountain_boost": 1.0,
			"regional_scale_multiplier": 1.0,
			"valley_bias_strength": 1.0,
			"pass_corridor_strength": 1.0,
		},
	}
	if not corridor_node.apply_landform_profile(profile, true):
		errors.append("corridor_profile_apply_failed")
	var report: Dictionary = corridor_node.world.landform_profile_report()
	if bool(report.get("native_prepared_grid_enabled", true)):
		errors.append("corridor_profile_native_still_enabled:%s" % str(report))
	var after_stats: Dictionary = corridor_node.build_stats()
	if int(after_stats.get("active_native_workers", 0)) != 0 or int(after_stats.get("queued_native_worker_builds", 0)) != 0:
		errors.append("corridor_profile_left_native_work:%s" % str(after_stats))
	if int(after_stats.get("cpu_chunk_payload_count", 0)) <= before_cpu_count:
		errors.append("corridor_profile_no_cpu_rebuild:%s before:%d" % [str(after_stats), before_cpu_count])
	corridor_node.queue_free()


func _best_pass_corridor_mid(world: RefCounted) -> Vector2:
	var best_mid := Vector2.ZERO
	var best_strength := -1.0
	for rz in range(-8, 9):
		for rx in range(-8, 9):
			var facts: Dictionary = world.pass_corridor_facts_for_region(rx, rz)
			if facts.get("status", "fail") != "pass":
				continue
			for fact_value in facts.get("facts", []) as Array:
				var fact: Dictionary = fact_value as Dictionary
				var start_values: Array = fact.get("start_m", []) as Array
				var end_values: Array = fact.get("end_m", []) as Array
				if start_values.size() < 2 or end_values.size() < 2:
					continue
				var mid := Vector2(
					(float(start_values[0]) + float(end_values[0])) * 0.5,
					(float(start_values[1]) + float(end_values[1])) * 0.5
				)
				var hint: Dictionary = world.sample_pass_corridor_hint(mid.x, mid.y)
				var strength: float = float(hint.get("corridor_strength", 0.0))
				if strength > best_strength:
					best_strength = strength
					best_mid = mid
	return best_mid
