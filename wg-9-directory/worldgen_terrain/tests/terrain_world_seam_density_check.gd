extends SceneTree

const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")

const FLOAT_EPSILON := 0.0001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var world: RefCounted = TerrainWorldScript.new()
	var errors: Array[String] = []
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("setup:%s" % str(error))
		_report(errors)
		return 1
	for density in [17, 33, 65, 129]:
		_check_density(world, density, errors)
	_check_preview_window(world, 33, 1, errors)
	_check_preview_window(world, 65, 1, errors)
	_check_gray_color_preview_window(33, 1, errors)
	_check_gray_color_preview_window(65, 1, errors)
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-terrain-world-seams] status=pass densities=4 epsilon=%.6f" % FLOAT_EPSILON)
	return 0


func _check_density(world: RefCounted, density: int, errors: Array[String]) -> void:
	var center: PackedFloat32Array = world.sample_height_grid_for_chunk(0, 0, density)
	var east: PackedFloat32Array = world.sample_height_grid_for_chunk(1, 0, density)
	var south: PackedFloat32Array = world.sample_height_grid_for_chunk(0, 1, density)
	var max_east_delta := 0.0
	var max_south_delta := 0.0
	for row in range(density):
		max_east_delta = max(max_east_delta, abs(float(center[row * density + density - 1]) - float(east[row * density])))
	for col in range(density):
		max_south_delta = max(max_south_delta, abs(float(center[(density - 1) * density + col]) - float(south[col])))
	if max_east_delta > FLOAT_EPSILON:
		errors.append("density_%d_east_delta:%.9f" % [density, max_east_delta])
	if max_south_delta > FLOAT_EPSILON:
		errors.append("density_%d_south_delta:%.9f" % [density, max_south_delta])
	var h0: float = world.sample_height(2048.0, 2048.0)
	var h1: float = world.sample_height(2048.0, 2048.0)
	if abs(h0 - h1) > FLOAT_EPSILON:
		errors.append("density_%d_repeat_delta:%.9f" % [density, abs(h0 - h1)])


func _check_preview_window(world: RefCounted, density: int, radius: int, errors: Array[String]) -> void:
	var grids: Dictionary = {}
	for chunk_z in range(-radius, radius + 1):
		for chunk_x in range(-radius, radius + 1):
			grids["%d,%d" % [chunk_x, chunk_z]] = world.sample_height_grid_for_chunk(chunk_x, chunk_z, density)
	for chunk_z in range(-radius, radius + 1):
		for chunk_x in range(-radius, radius + 1):
			var key: String = "%d,%d" % [chunk_x, chunk_z]
			var grid: PackedFloat32Array = grids[key] as PackedFloat32Array
			if chunk_x < radius:
				var east_key: String = "%d,%d" % [chunk_x + 1, chunk_z]
				_check_east_west("preview_%d:%s:%s" % [density, key, east_key], grid, grids[east_key] as PackedFloat32Array, density, errors)
			if chunk_z < radius:
				var south_key: String = "%d,%d" % [chunk_x, chunk_z + 1]
				_check_north_south("preview_%d:%s:%s" % [density, key, south_key], grid, grids[south_key] as PackedFloat32Array, density, errors)


func _check_east_west(label: String, west: PackedFloat32Array, east: PackedFloat32Array, density: int, errors: Array[String]) -> void:
	var max_delta := 0.0
	for row in range(density):
		max_delta = max(max_delta, abs(float(west[row * density + density - 1]) - float(east[row * density])))
	if max_delta > FLOAT_EPSILON:
		errors.append("%s_east_west_delta:%.9f" % [label, max_delta])


func _check_north_south(label: String, north: PackedFloat32Array, south: PackedFloat32Array, density: int, errors: Array[String]) -> void:
	var max_delta := 0.0
	for col in range(density):
		max_delta = max(max_delta, abs(float(north[(density - 1) * density + col]) - float(south[col])))
	if max_delta > FLOAT_EPSILON:
		errors.append("%s_north_south_delta:%.9f" % [label, max_delta])


func _check_gray_color_preview_window(density: int, radius: int, errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	get_root().add_child(node)
	node.vertices_per_side = density
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("gray_color_setup")
		node.queue_free()
		return
	node.update_viewer(Vector2.ZERO)
	var step_m: float = node.world.chunk_size_m / float(density - 1)
	var colors: Dictionary = {}
	for chunk_z in range(-radius, radius + 1):
		for chunk_x in range(-radius, radius + 1):
			colors["%d,%d" % [chunk_x, chunk_z]] = node._build_gray_colors_for_chunk(chunk_x, chunk_z, density, step_m)
	for chunk_z in range(-radius, radius + 1):
		for chunk_x in range(-radius, radius + 1):
			var key: String = "%d,%d" % [chunk_x, chunk_z]
			var grid: PackedColorArray = colors[key] as PackedColorArray
			if chunk_x < radius:
				var east_key: String = "%d,%d" % [chunk_x + 1, chunk_z]
				_check_color_east_west("gray_%d:%s:%s" % [density, key, east_key], grid, colors[east_key] as PackedColorArray, density, errors)
			if chunk_z < radius:
				var south_key: String = "%d,%d" % [chunk_x, chunk_z + 1]
				_check_color_north_south("gray_%d:%s:%s" % [density, key, south_key], grid, colors[south_key] as PackedColorArray, density, errors)
	node.queue_free()


func _check_color_east_west(label: String, west: PackedColorArray, east: PackedColorArray, density: int, errors: Array[String]) -> void:
	var max_delta := 0.0
	for row in range(density):
		max_delta = max(max_delta, abs(west[row * density + density - 1].r - east[row * density].r))
	if max_delta > 0.003:
		errors.append("%s_color_east_west_delta:%.9f" % [label, max_delta])


func _check_color_north_south(label: String, north: PackedColorArray, south: PackedColorArray, density: int, errors: Array[String]) -> void:
	var max_delta := 0.0
	for col in range(density):
		max_delta = max(max_delta, abs(north[(density - 1) * density + col].r - south[col].r))
	if max_delta > 0.003:
		errors.append("%s_color_north_south_delta:%.9f" % [label, max_delta])


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-world-seams] status=fail errors=%d" % errors.size())
