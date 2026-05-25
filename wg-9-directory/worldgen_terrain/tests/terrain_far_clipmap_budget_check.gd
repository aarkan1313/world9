extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	clipmap.level_count = 3
	clipmap.base_spacing_m = 64.0
	clipmap.base_outer_extent_m = 4096.0
	clipmap.near_hole_extent_m = 2048.0
	var default_budget: Dictionary = clipmap.budget_report()
	_check_budget("default", default_budget, 3, 49923, 74736, 224208, 32768.0, errors)
	clipmap.level_count = 4
	var expanded_budget: Dictionary = clipmap.budget_report()
	_check_budget("expanded", expanded_budget, 4, 66564, 99816, 299448, 65536.0, errors)
	var default_totals: Dictionary = default_budget["totals"] as Dictionary
	var expanded_totals: Dictionary = expanded_budget["totals"] as Dictionary
	if float(expanded_totals["mesh_plus_height_mib"]) > 4.0:
		errors.append("expanded_budget_too_heavy:%.3f" % float(expanded_totals["mesh_plus_height_mib"]))
	if float(expanded_totals["mesh_plus_height_mib"]) <= float(default_totals["mesh_plus_height_mib"]):
		errors.append("expanded_budget_did_not_increase")
	_check_live_reconfigure(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-far-clipmap-budget] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-far-clipmap-budget] status=pass default_mib=%.3f expanded_mib=%.3f" % [
		float(default_totals["mesh_plus_height_mib"]),
		float(expanded_totals["mesh_plus_height_mib"]),
	])
	quit(0)


func _check_live_reconfigure(errors: Array[String]) -> void:
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
		return
	var live_clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	live_clipmap.level_count = 3
	live_clipmap.base_spacing_m = 64.0
	live_clipmap.base_outer_extent_m = 4096.0
	live_clipmap.near_hole_extent_m = 2048.0
	get_root().add_child(live_clipmap)
	if not live_clipmap.setup(world):
		errors.append("live_setup_failed")
		return
	var first: Dictionary = live_clipmap.update_viewer(Vector2.ZERO)
	if int(first.get("levels", 0)) != 3:
		errors.append("live_initial_levels:%d" % int(first.get("levels", 0)))
	if not live_clipmap.configure_geometry(4, 64.0, 4096.0):
		errors.append("live_reconfigure_failed")
	var second: Dictionary = live_clipmap.update_viewer(Vector2.ZERO)
	if int(second.get("levels", 0)) != 4:
		errors.append("live_reconfigured_levels:%d" % int(second.get("levels", 0)))
	if int(second.get("vertices", 0)) != 66564:
		errors.append("live_reconfigured_vertices:%d" % int(second.get("vertices", 0)))
	var counts: Array = second.get("build_counts", []) as Array
	if counts.size() != 4:
		errors.append("live_reconfigured_counts:%s" % str(counts))
	live_clipmap.queue_free()


func _check_budget(
	label: String,
	budget: Dictionary,
	expected_levels: int,
	expected_vertices: int,
	expected_triangles: int,
	expected_indices: int,
	expected_max_diameter_m: float,
	errors: Array[String]
) -> void:
	if int(budget.get("level_count", 0)) != expected_levels:
		errors.append("%s_levels:%d" % [label, int(budget.get("level_count", 0))])
	var levels: Array = budget.get("levels", []) as Array
	if levels.size() != expected_levels:
		errors.append("%s_level_entries:%d" % [label, levels.size()])
	var totals: Dictionary = budget.get("totals", {}) as Dictionary
	if int(totals.get("vertex_count", 0)) != expected_vertices:
		errors.append("%s_vertices:%d" % [label, int(totals.get("vertex_count", 0))])
	if int(totals.get("triangle_count", 0)) != expected_triangles:
		errors.append("%s_triangles:%d" % [label, int(totals.get("triangle_count", 0))])
	if int(totals.get("index_count", 0)) != expected_indices:
		errors.append("%s_indices:%d" % [label, int(totals.get("index_count", 0))])
	if levels.size() > 0:
		var last_level: Dictionary = levels[levels.size() - 1] as Dictionary
		if absf(float(last_level["diameter_m"]) - expected_max_diameter_m) > 0.001:
			errors.append("%s_max_diameter:%.3f" % [label, float(last_level["diameter_m"])])
