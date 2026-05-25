extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainChunkBuildJobScript := preload("res://worldgen_terrain/mesh/terrain_chunk_build_job.gd")

const VERTICES_PER_SIDE := 33


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("setup:%s" % str(error))
		_report(errors)
		return 1
	var request: Dictionary = TerrainChunkBuildJobScript.make_request(
		1,
		-2,
		VERTICES_PER_SIDE,
		TerrainSettingsScript.CHUNK_SIZE_M,
		1,
		0,
		TerrainWorldScript.DEBUG_GRAY
	)
	var payload: Dictionary = TerrainChunkBuildJobScript.build_payload(world, request)
	_check_payload(payload, false, errors)
	var colors := PackedColorArray()
	colors.resize(VERTICES_PER_SIDE * VERTICES_PER_SIDE)
	for index in range(colors.size()):
		colors[index] = Color(0.25, 0.50, 0.75)
	var colored_payload: Dictionary = TerrainChunkBuildJobScript.build_payload(world, request, colors)
	_check_payload(colored_payload, true, errors)
	var mesh: ArrayMesh = TerrainChunkBuildJobScript.mesh_from_payload(payload)
	if mesh == null or mesh.get_surface_count() != 1:
		errors.append("mesh_from_payload")
	var bad_colors := PackedColorArray()
	bad_colors.resize(1)
	var bad_payload: Dictionary = TerrainChunkBuildJobScript.build_payload(world, request, bad_colors)
	if bad_payload.get("status", "pass") == "pass":
		errors.append("bad_color_payload_passed")
	if not errors.is_empty():
		_report(errors)
		return 1
	var summary: Dictionary = TerrainChunkBuildJobScript.payload_summary(payload)
	print("[wg9-chunk-build-job] status=pass vertices=%d indices=%d" % [
		int(summary["vertex_count"]),
		int(summary["index_count"]),
	])
	return 0


func _check_payload(payload: Dictionary, expect_colors: bool, errors: Array[String]) -> void:
	if payload.get("status", "fail") != "pass":
		errors.append("payload_failed:%s" % str(payload.get("error", "unknown")))
		return
	var arrays: Array = payload["arrays"] as Array
	var expected_count: int = VERTICES_PER_SIDE * VERTICES_PER_SIDE
	var expected_indices: int = (VERTICES_PER_SIDE - 1) * (VERTICES_PER_SIDE - 1) * 6
	if (payload["height"] as PackedFloat32Array).size() != expected_count:
		errors.append("height_size")
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != expected_count:
		errors.append("vertex_size")
	if (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() != expected_count:
		errors.append("normal_size")
	if (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() != expected_count:
		errors.append("uv_size")
	if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() != expected_indices:
		errors.append("index_size")
	var color_value: Variant = arrays[Mesh.ARRAY_COLOR]
	var has_colors: bool = color_value is PackedColorArray and not (color_value as PackedColorArray).is_empty()
	if has_colors != expect_colors:
		errors.append("color_presence:%s expected:%s" % [str(has_colors), str(expect_colors)])


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-chunk-build-job] status=fail errors=%d" % errors.size())
