extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


class FailedWorker:
	extends RefCounted

	var request_id: String = ""

	func _init(p_request_id: String = "") -> void:
		request_id = p_request_id

	func is_done() -> bool:
		return true

	func take_result() -> Dictionary:
		return {
			"status": "fail",
			"error": "forced_test_failure",
			"request_id": request_id,
		}


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	clipmap.level_count = 3
	clipmap.vertices_per_side = 129
	clipmap.base_spacing_m = 64.0
	clipmap.base_outer_extent_m = 4096.0
	clipmap.near_hole_extent_m = 2048.0
	get_root().add_child(clipmap)
	if not clipmap.setup(world):
		errors.append("clipmap_setup_failed")
	var first: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	if first.get("status", "fail") != "pass":
		errors.append("first_update:%s" % str(first))
	if int(first.get("levels", 0)) != 3:
		errors.append("levels:%d" % int(first.get("levels", 0)))
	if int(first.get("vertices", 0)) != 3 * 129 * 129:
		errors.append("vertices:%d" % int(first.get("vertices", 0)))
	if int(first.get("indices", 0)) <= 0:
		errors.append("indices:%d" % int(first.get("indices", 0)))
	_check_worker_request_signature(clipmap, errors)
	_check_geometric_transition_band(clipmap, errors)
	_check_worker_failure_fallback(clipmap, errors)
	var restored: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	var initial_counts: Array = restored.get("build_counts", []) as Array
	var second: Dictionary = clipmap.update_viewer(Vector2(31.0, 31.0))
	if str(second.get("build_counts", [])) != str(initial_counts):
		errors.append("small_move_rebuilt:%s" % str(second.get("build_counts", [])))
	var third: Dictionary = clipmap.update_viewer(Vector2(65.0, 0.0))
	var third_counts: Array = third.get("build_counts", []) as Array
	for level in range(third_counts.size()):
		if int(third_counts[level]) <= int(initial_counts[level]):
			errors.append("shared_origin_level_did_not_rebuild:%d:%s" % [level, str(third_counts)])
	var fourth: Dictionary = clipmap.update_viewer(Vector2(130.0, 0.0))
	var fourth_counts: Array = fourth.get("build_counts", []) as Array
	for level in range(fourth_counts.size()):
		if int(fourth_counts[level]) <= int(third_counts[level]):
			errors.append("shared_origin_level_did_not_rebuild_again:%d:%s" % [level, str(fourth_counts)])
	clipmap.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-far-clipmap] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-terrain-far-clipmap] status=pass vertices=%d indices=%d build_counts=%s" % [
		int(fourth.get("vertices", 0)),
		int(fourth.get("indices", 0)),
		str(fourth_counts),
	])
	quit(0)


func _check_worker_request_signature(clipmap: Node3D, errors: Array[String]) -> void:
	var origin: Vector2 = clipmap._pending_origin
	var request: Dictionary = clipmap._prepare_worker_request(0, origin)
	if request.get("status", "fail") != "pass":
		errors.append("worker_request_prepare:%s" % str(request))
		return
	if not clipmap._worker_request_matches_pending(0, request):
		errors.append("worker_request_rejected_valid:%s" % str(request))
	var request_id: String = str(request.get("request_id", ""))
	var wrong_side: Dictionary = request.duplicate(true)
	wrong_side["side"] = int(wrong_side["side"]) + 2
	if clipmap._worker_request_matches_pending(0, wrong_side):
		errors.append("worker_request_accepted_wrong_side")
	var wrong_origin: Dictionary = request.duplicate(true)
	wrong_origin["origin_x"] = float(wrong_origin["origin_x"]) + clipmap.base_spacing_m
	if clipmap._worker_request_matches_pending(0, wrong_origin):
		errors.append("worker_request_accepted_wrong_origin")
	var changed_id: String = clipmap._worker_request_id(wrong_side)
	if changed_id == request_id:
		errors.append("worker_request_id_not_geometry_specific:%s" % request_id)


func _check_geometric_transition_band(clipmap: Node3D, errors: Array[String]) -> void:
	if int(clipmap.geometric_transition_band_cells) <= 0:
		errors.append("transition_band_disabled")
		return
	var heightfield: Dictionary = clipmap.level_heightfields[0] as Dictionary
	if heightfield.is_empty():
		errors.append("transition_heightfield_missing")
		return
	var side: int = int(heightfield["vertices_per_side"])
	var height: PackedFloat32Array = heightfield["height"] as PackedFloat32Array
	var origin := Vector2(float(heightfield["origin_x"]), float(heightfield["origin_z"]))
	var outer_extent: float = float(heightfield["outer_extent_m"])
	var spacing: float = float(heightfield["spacing_m"])
	var edge_x: int = side - 1
	var edge_z: int = int(side / 2) + 1
	var local_x: float = -outer_extent + float(edge_x) * spacing
	var local_z: float = -outer_extent + float(edge_z) * spacing
	var expected: float = clipmap._coarse_surface_height(origin, local_x, local_z, clipmap._level_spacing(1))
	var actual: float = float(height[edge_z * side + edge_x])
	if absf(actual - expected) > 0.0001:
		errors.append("transition_outer_not_coarse:%.6f expected:%.6f" % [actual, expected])
	var inner_offset: int = int(clipmap.geometric_transition_band_cells) + 2
	var inner_x: int = side - 1 - inner_offset
	var inner_local_x: float = -outer_extent + float(inner_x) * spacing
	var raw: float = clipmap.world.sample_height(origin.x + inner_local_x, origin.y + local_z)
	var inner_actual: float = float(height[edge_z * side + inner_x])
	if absf(inner_actual - raw) > 0.0001:
		errors.append("transition_inner_changed:%.6f raw:%.6f" % [inner_actual, raw])


func _check_worker_failure_fallback(clipmap: Node3D, errors: Array[String]) -> void:
	var new_origin := Vector2(clipmap.base_spacing_m, 0.0)
	clipmap._pending_origin = new_origin
	var request: Dictionary = clipmap._prepare_worker_request(0, new_origin)
	if request.get("status", "fail") != "pass":
		errors.append("failure_request_prepare:%s" % str(request))
		return
	var before_count: int = int((clipmap.level_build_counts as Array)[0])
	clipmap._native_workers[0] = FailedWorker.new(str(request.get("request_id", "")))
	clipmap._native_worker_requests[0] = request
	clipmap._poll_native_workers()
	if str(clipmap.last_worker_error).is_empty():
		errors.append("worker_failure_not_reported")
	if int((clipmap.level_build_counts as Array)[0]) <= before_count:
		errors.append("worker_failure_did_not_rebuild:%s" % str(clipmap.level_build_counts))
	var level_origin: Vector2 = clipmap.level_origins[0] as Vector2
	if level_origin.distance_to(new_origin) > 0.001:
		errors.append("worker_failure_origin:%s expected:%s" % [str(level_origin), str(new_origin)])
