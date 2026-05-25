extends SceneTree

const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainHeightProviderScript := preload("res://worldgen_terrain/height/terrain_height_provider.gd")
const FlatHeightProviderScript := preload("res://worldgen_terrain/height/flat_height_provider.gd")
const ProceduralHeightProviderScript := preload("res://worldgen_terrain/height/procedural_height_provider.gd")

const FLOAT_EPSILON := 0.00001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_flat_provider(errors)
	_check_procedural_provider(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-height-provider-contract] status=fail errors=%d" % errors.size())
		return 1

	print("[wg9-height-provider-contract] status=pass flat=true procedural=true")
	return 0


func _check_flat_provider(errors: Array[String]) -> void:
	var provider: RefCounted = FlatHeightProviderScript.new()
	provider.setup(42.5)
	var points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(2048.0, 0.0),
		Vector2(-8192.25, 32768.75),
		Vector2(900000.0, -1200000.0),
	]
	for point in points:
		var sample: Dictionary = provider.sample(point.x, point.y)
		if abs(float(sample["height_m"]) - 42.5) > FLOAT_EPSILON:
			errors.append("flat_sample_height:%s" % str(point))
		if float(provider.sample_height(point.x, point.y)) != 42.5:
			errors.append("flat_height:%s" % str(point))
		if str(sample["primary_family"]) != "flat":
			errors.append("flat_family:%s" % str(point))
		if float(sample.get("source_confidence", -1.0)) != 0.0:
			errors.append("flat_source_confidence:%s" % str(point))
		if float(sample.get("source_resolution_m", -1.0)) != 0.0:
			errors.append("flat_source_resolution:%s" % str(point))

	var grid: PackedFloat32Array = provider.sample_height_grid(0.0, 0.0, 512.0, 5, 4)
	if grid.size() != 20:
		errors.append("flat_grid_size:%d" % grid.size())
	for value in grid:
		if abs(float(value) - 42.5) > FLOAT_EPSILON:
			errors.append("flat_grid_value")
			return
	_check_invalid_grid_requests("flat", provider, errors)


func _check_procedural_provider(errors: Array[String]) -> void:
	var pack: RefCounted = RuntimeKernelPackScript.new()
	if not pack.load_default():
		for error in pack.errors:
			errors.append("pack:%s" % str(error))
		return

	var baseline: RefCounted = TerrainHeightProviderScript.new()
	baseline.setup(pack)
	var provider: RefCounted = ProceduralHeightProviderScript.new()
	provider.setup(pack)
	var points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(512.0, 4096.0),
		Vector2(32768.0, -2048.0),
		Vector2(90000.0, -30000.0),
	]
	for point in points:
		var expected: Dictionary = baseline.sample(point.x, point.y)
		var actual: Dictionary = provider.sample(point.x, point.y)
		if abs(float(expected["height_m"]) - float(actual["height_m"])) > FLOAT_EPSILON:
			errors.append("procedural_height:%s" % str(point))
		if str(expected["primary_family"]) != str(actual["primary_family"]):
			errors.append("procedural_family:%s" % str(point))
		if str(expected["kernel_a"]) != str(actual["kernel_a"]):
			errors.append("procedural_kernel:%s" % str(point))
		if not actual.has("source_confidence") or float(actual["source_confidence"]) <= 0.0:
			errors.append("procedural_source_confidence:%s" % str(point))
		if not actual.has("source_resolution_m") or float(actual["source_resolution_m"]) <= 0.0:
			errors.append("procedural_source_resolution:%s" % str(point))
		if not actual.has("primary_source_resolution_m") or float(actual["primary_source_resolution_m"]) <= 0.0:
			errors.append("procedural_primary_source_resolution:%s" % str(point))

	var expected_grid: PackedFloat32Array = baseline.sample_height_grid(0.0, 0.0, 256.0, 4, 3)
	var actual_grid: PackedFloat32Array = provider.sample_height_grid(0.0, 0.0, 256.0, 4, 3)
	if expected_grid.size() != actual_grid.size():
		errors.append("procedural_grid_size")
		return
	for index in range(expected_grid.size()):
		if abs(float(expected_grid[index]) - float(actual_grid[index])) > FLOAT_EPSILON:
			errors.append("procedural_grid_value:%d" % index)
			return
	_check_grid_matches_scalar(provider, 32768.0 - 512.0, -512.0, 256.0, 6, 5, errors)
	_check_grid_matches_scalar(provider, -32768.0 - 512.0, 32768.0 - 256.0, 256.0, 6, 5, errors)
	_check_invalid_grid_requests("procedural", provider, errors)


func _check_grid_matches_scalar(
	provider: RefCounted,
	origin_x: float,
	origin_z: float,
	step_m: float,
	count_x: int,
	count_z: int,
	errors: Array[String]
) -> void:
	var grid: PackedFloat32Array = provider.sample_height_grid(origin_x, origin_z, step_m, count_x, count_z)
	if grid.size() != count_x * count_z:
		errors.append("cross_region_grid_size:%d expected:%d" % [grid.size(), count_x * count_z])
		return
	for z in range(count_z):
		for x in range(count_x):
			var world_x: float = origin_x + float(x) * step_m
			var world_z: float = origin_z + float(z) * step_m
			var expected: float = float(provider.sample_height(world_x, world_z))
			var actual: float = float(grid[z * count_x + x])
			if abs(expected - actual) > FLOAT_EPSILON:
				errors.append("cross_region_grid_value:%d,%d delta:%.9f" % [x, z, abs(expected - actual)])
				return


func _check_invalid_grid_requests(label: String, provider: RefCounted, errors: Array[String]) -> void:
	var invalid_grids: Array[PackedFloat32Array] = [
		provider.sample_height_grid(0.0, 0.0, 0.0, 4, 4),
		provider.sample_height_grid(0.0, 0.0, -1.0, 4, 4),
		provider.sample_height_grid(0.0, 0.0, 256.0, 0, 4),
		provider.sample_height_grid(0.0, 0.0, 256.0, 4, 0),
		provider.sample_height_grid(0.0, 0.0, 256.0, 4, 4, 1337, 0.0),
	]
	for index in range(invalid_grids.size()):
		if not invalid_grids[index].is_empty():
			errors.append("%s_invalid_grid_not_empty:%d:%d" % [label, index, invalid_grids[index].size()])
