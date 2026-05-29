extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainHeightProviderScript := preload("res://worldgen_terrain/height/terrain_height_provider.gd")
const NpyFloat32ArrayScript := preload("res://worldgen_terrain/io/npy_float32_array.gd")

const FLOAT_EPSILON := 0.001


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var manifest_path: String = TerrainSettingsScript.workspace_path("factory/runtime/chunk_reference/chunk_reference_manifest.json")
	if not FileAccess.file_exists(manifest_path):
		push_error("Missing chunk reference manifest: %s" % manifest_path)
		return 1
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("Could not open chunk reference manifest: %s" % manifest_path)
		return 1
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Chunk reference manifest is not a JSON object: %s" % manifest_path)
		return 1
	var manifest: Dictionary = parsed as Dictionary

	var pack: RefCounted = RuntimeKernelPackScript.new()
	if not pack.load_default():
		for error in pack.errors:
			push_error(error)
		return 1
	var provider: RefCounted = TerrainHeightProviderScript.new()
	provider.setup(pack)

	var reference_seed: int = int(manifest["seed"])
	var region_size_m: float = float(manifest["region_size_m"])
	var step_m: float = float(manifest["step_m"])
	var vertices_per_side: int = int(manifest["vertices_per_side"])
	var errors: Array[String] = []
	var generated_by_coord: Dictionary = {}
	var max_height_delta: float = 0.0
	var chunks: Array = manifest.get("chunks", []) as Array
	for chunk_record_value in chunks:
		var chunk_record: Dictionary = chunk_record_value as Dictionary
		var origin: Array = chunk_record["origin"] as Array
		var generated: PackedFloat32Array = provider.sample_height_grid(
			float(origin[0]),
			float(origin[1]),
			step_m,
			vertices_per_side,
			vertices_per_side,
			reference_seed,
			region_size_m
		)
		var reference_path: String = manifest_path.get_base_dir().path_join(str(chunk_record["height_npy"]))
		var reference: Dictionary = NpyFloat32ArrayScript.load_2d(reference_path)
		if reference.get("status") != "pass":
			errors.append("reference_load:%s" % reference.get("error", "unknown"))
			continue
		var reference_values: PackedFloat32Array = reference["values"] as PackedFloat32Array
		if reference_values.size() != generated.size():
			errors.append("size_mismatch:%s" % str(chunk_record["chunk"]))
			continue
		var chunk_max_delta: float = 0.0
		for index in range(reference_values.size()):
			var delta: float = abs(float(generated[index]) - float(reference_values[index]))
			chunk_max_delta = max(chunk_max_delta, delta)
		max_height_delta = max(max_height_delta, chunk_max_delta)
		if chunk_max_delta > FLOAT_EPSILON:
			errors.append("chunk_height_delta:%s max=%.6f" % [str(chunk_record["chunk"]), chunk_max_delta])
		var coord: Array = chunk_record["chunk"] as Array
		generated_by_coord["%d,%d" % [int(coord[0]), int(coord[1])]] = generated

	_check_edges(generated_by_coord, vertices_per_side, errors)
	_check_axis_crossing_seams(provider, reference_seed, region_size_m, step_m, vertices_per_side, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-chunk-reference] status=fail errors=%d max_height_delta=%.6f" % [errors.size(), max_height_delta])
		return 1

	print("[wg9-chunk-reference] status=pass chunks=%d vertices=%d max_height_delta=%.6f epsilon=%.3f" % [
		chunks.size(),
		vertices_per_side,
		max_height_delta,
		FLOAT_EPSILON,
	])
	return 0


func _check_edges(generated_by_coord: Dictionary, vertices_per_side: int, errors: Array[String]) -> void:
	_check_east_west(generated_by_coord, "0,0", "1,0", vertices_per_side, errors)
	_check_north_south(generated_by_coord, "0,0", "0,1", vertices_per_side, errors)
	_check_east_west(generated_by_coord, "0,1", "1,1", vertices_per_side, errors)
	_check_north_south(generated_by_coord, "1,0", "1,1", vertices_per_side, errors)


# The manifest-driven edge checks above only cover positive-coordinate
# neighbors. Seams that cross the x=0 / z=0 axes are the classic floor-vs-
# truncate failure mode for procedural terrain, so sample those neighbor pairs
# directly from the provider (independent of the reference fixtures, which do
# not include negative chunks) and require exact zero shared-edge deltas.
func _check_axis_crossing_seams(
	provider: RefCounted,
	seed: int,
	region_size_m: float,
	step_m: float,
	vertices_per_side: int,
	errors: Array[String]
) -> void:
	var chunk_span_m: float = step_m * float(vertices_per_side - 1)
	var samples: Dictionary = {}
	for coord in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		samples["%d,%d" % [coord.x, coord.y]] = provider.sample_height_grid(
			float(coord.x) * chunk_span_m,
			float(coord.y) * chunk_span_m,
			step_m,
			vertices_per_side,
			vertices_per_side,
			seed,
			region_size_m
		)
	# x=0 crossing: east edge of (-1,0) must equal west edge of (0,0).
	_check_east_west(samples, "-1,0", "0,0", vertices_per_side, errors)
	# z=0 crossing: south edge of (0,-1) must equal north edge of (0,0).
	_check_north_south(samples, "0,-1", "0,0", vertices_per_side, errors)
	# corner approach along the negative quadrant for completeness.
	_check_east_west(samples, "-1,-1", "0,-1", vertices_per_side, errors)
	_check_north_south(samples, "-1,-1", "-1,0", vertices_per_side, errors)


func _check_east_west(generated_by_coord: Dictionary, a_key: String, b_key: String, vertices_per_side: int, errors: Array[String]) -> void:
	if not generated_by_coord.has(a_key) or not generated_by_coord.has(b_key):
		return
	var a: PackedFloat32Array = generated_by_coord[a_key] as PackedFloat32Array
	var b: PackedFloat32Array = generated_by_coord[b_key] as PackedFloat32Array
	var max_delta: float = 0.0
	for row in range(vertices_per_side):
		var delta: float = abs(float(a[row * vertices_per_side + vertices_per_side - 1]) - float(b[row * vertices_per_side]))
		max_delta = max(max_delta, delta)
	if max_delta != 0.0:
		errors.append("edge_east_west:%s:%s max=%.9f" % [a_key, b_key, max_delta])


func _check_north_south(generated_by_coord: Dictionary, a_key: String, b_key: String, vertices_per_side: int, errors: Array[String]) -> void:
	if not generated_by_coord.has(a_key) or not generated_by_coord.has(b_key):
		return
	var a: PackedFloat32Array = generated_by_coord[a_key] as PackedFloat32Array
	var b: PackedFloat32Array = generated_by_coord[b_key] as PackedFloat32Array
	var max_delta: float = 0.0
	var a_start: int = (vertices_per_side - 1) * vertices_per_side
	for col in range(vertices_per_side):
		var delta: float = abs(float(a[a_start + col]) - float(b[col]))
		max_delta = max(max_delta, delta)
	if max_delta != 0.0:
		errors.append("edge_north_south:%s:%s max=%.9f" % [a_key, b_key, max_delta])
