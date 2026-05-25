extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const FLOAT_EPSILON := 0.00001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_flat_world(errors)
	_check_procedural_world(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-world] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-terrain-world] status=pass flat=true procedural=true active=%d" % _expected_active_count())
	return 0


func _check_flat_world(errors: Array[String]) -> void:
	var world: RefCounted = TerrainWorldScript.new()
	world.setup_flat(12.25, 1337)
	world.set_debug_mode(TerrainWorldScript.DEBUG_LOD_RING)
	if world.debug_mode != TerrainWorldScript.DEBUG_LOD_RING:
		errors.append("flat_debug_mode")
	var steps: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1800.0, 0.0),
		Vector2(4300.0, 1800.0),
		Vector2(9000.0, -3000.0),
	]
	for point in steps:
		var report: Dictionary = world.update_viewer(point)
		_check_stream_report("flat", report, errors)
		if world.active_count() != _expected_active_count():
			errors.append("flat_active:%s" % str(point))
	if abs(world.sample_height(500000.0, -900000.0) - 12.25) > FLOAT_EPSILON:
		errors.append("flat_sample_height")
	var flat_sample: Dictionary = world.sample(500000.0, -900000.0)
	if abs(float(flat_sample["height_m"]) - 12.25) > FLOAT_EPSILON:
		errors.append("flat_sample_fact_height")
	if str(flat_sample["primary_family"]) != "flat":
		errors.append("flat_sample_fact_family")
	var grid: PackedFloat32Array = world.sample_height_grid_for_chunk(0, 0, 5)
	if grid.size() != 25:
		errors.append("flat_chunk_grid_size")
	for value in grid:
		if abs(float(value) - 12.25) > FLOAT_EPSILON:
			errors.append("flat_chunk_grid_value")
			return


func _check_procedural_world(errors: Array[String]) -> void:
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("procedural_setup:%s" % str(error))
		return
	var first_report: Dictionary = world.update_viewer(Vector2(0.0, 0.0))
	var second_report: Dictionary = world.update_viewer(Vector2(9000.0, -3000.0))
	_check_stream_report("procedural.first", first_report, errors)
	_check_stream_report("procedural.second", second_report, errors)
	if world.provider_mode != TerrainWorldScript.PROVIDER_PROCEDURAL:
		errors.append("procedural_mode")
	var h0: float = world.sample_height(1234.5, -6789.0)
	var h1: float = world.sample_height(1234.5, -6789.0)
	if abs(h0 - h1) > FLOAT_EPSILON:
		errors.append("procedural_determinism")
	var sample: Dictionary = world.sample(1234.5, -6789.0)
	if abs(float(sample["height_m"]) - h0) > 0.05:
		errors.append("procedural_sample_fact_height")
	if float(sample.get("source_confidence", 0.0)) <= 0.0:
		errors.append("procedural_source_confidence")
	if float(sample.get("source_resolution_m", 0.0)) <= 0.0:
		errors.append("procedural_source_resolution")
	var grid: PackedFloat32Array = world.sample_height_grid_for_chunk(0, 0, TerrainSettingsScript.LOD0_VERTICES_PER_SIDE)
	if grid.size() != TerrainSettingsScript.LOD0_VERTICES_PER_SIDE * TerrainSettingsScript.LOD0_VERTICES_PER_SIDE:
		errors.append("procedural_chunk_grid_size")
	var direct_grid: PackedFloat32Array = world.sample_height_grid(0.0, 0.0, 256.0, 4, 3)
	if direct_grid.size() != 12:
		errors.append("procedural_direct_grid_size")


func _check_stream_report(label: String, report: Dictionary, errors: Array[String]) -> void:
	if report.get("status", "pass") != "pass":
		errors.append("%s_status:%s" % [label, str(report.get("errors", []))])
	if int(report["active_count"]) != _expected_active_count():
		errors.append("%s_active_count:%d" % [label, int(report["active_count"])])
	if int(report["expected_active_count"]) != _expected_active_count():
		errors.append("%s_expected_active_count:%d" % [label, int(report["expected_active_count"])])
	if int(report["build_now_count"]) > 2:
		errors.append("%s_build_budget:%d" % [label, int(report["build_now_count"])])


func _expected_active_count() -> int:
	var radius: int = TerrainSettingsScript.VISIBLE_RADIUS_CHUNKS
	return (radius * 2 + 1) * (radius * 2 + 1)
