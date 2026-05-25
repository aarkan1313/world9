extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const HEIGHT_EPSILON := 0.00001


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var reports: Array[Dictionary] = []
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
	for viewer in [
		Vector2.ZERO,
		Vector2(65.0, 0.0),
		Vector2(130.0, -192.0),
		Vector2(8192.0 + 96.0, -4096.0 - 128.0),
	]:
		var update: Dictionary = clipmap.update_viewer(viewer)
		if update.get("status", "fail") != "pass":
			errors.append("update_failed:%s:%s" % [str(viewer), str(update)])
			continue
		_check_transitions(clipmap, viewer, reports, errors)
	clipmap.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-far-clipmap-transitions] status=fail errors=%d reports=%s" % [errors.size(), JSON.stringify(reports)])
		quit(1)
		return
	print("[wg9-far-clipmap-transitions] status=pass reports=%s" % JSON.stringify(reports))
	quit(0)


func _check_transitions(clipmap: Node3D, viewer: Vector2, reports: Array[Dictionary], errors: Array[String]) -> void:
	for level in range(1, clipmap.level_heightfields.size()):
		var fine: Dictionary = clipmap.level_heightfields[level - 1] as Dictionary
		var coarse: Dictionary = clipmap.level_heightfields[level] as Dictionary
		if fine.is_empty() or coarse.is_empty():
			errors.append("missing_heightfield:%d:%s" % [level, str(viewer)])
			continue
		var inner_extent: float = float(coarse["outer_extent_m"]) / 2.0
		var spacing: float = float(coarse["spacing_m"])
		var max_delta := 0.0
		var samples := 0
		var x := -inner_extent
		while x <= inner_extent + spacing * 0.25:
			max_delta = max(max_delta, _compare_world_height(fine, coarse, x, -inner_extent))
			max_delta = max(max_delta, _compare_world_height(fine, coarse, x, inner_extent))
			samples += 2
			x += spacing
		var z := -inner_extent + spacing
		while z <= inner_extent - spacing * 0.25:
			max_delta = max(max_delta, _compare_world_height(fine, coarse, -inner_extent, z))
			max_delta = max(max_delta, _compare_world_height(fine, coarse, inner_extent, z))
			samples += 2
			z += spacing
		reports.append({
			"viewer": [viewer.x, viewer.y],
			"fine_level": level - 1,
			"coarse_level": level,
			"samples": samples,
			"max_delta": max_delta,
		})
		if max_delta > HEIGHT_EPSILON:
			errors.append("transition_delta:%d:%s:%.9f" % [level, str(viewer), max_delta])


func _compare_world_height(fine: Dictionary, coarse: Dictionary, local_x: float, local_z: float) -> float:
	var world_x: float = float(coarse["origin_x"]) + local_x
	var world_z: float = float(coarse["origin_z"]) + local_z
	return absf(_heightfield_at_world(fine, world_x, world_z) - _heightfield_at_world(coarse, world_x, world_z))


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
