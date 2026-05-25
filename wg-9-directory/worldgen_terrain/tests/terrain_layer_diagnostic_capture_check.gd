extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_visual_layers"
const SIZE := 160
const SPAN_CHUNKS := 6.0


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
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var layers: Array[String] = ["height", "macro", "relief", "detail", "valley"]
	var summaries: Array[String] = []
	for layer in layers:
		var result: Dictionary = _capture_layer(world, layer, out_dir.path_join("layer_%s.png" % layer))
		if result.get("status") != "pass":
			errors.append("%s:%s" % [layer, str(result.get("error", "unknown"))])
			continue
		if float(result["range"]) <= 0.01:
			errors.append("%s_blank" % layer)
		summaries.append("%s_range=%.3f" % [layer, float(result["range"])])
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-terrain-layers] status=pass size=%d %s out=%s" % [SIZE, " ".join(summaries), out_dir])
	return 0


func _capture_layer(world: RefCounted, layer: String, path: String) -> Dictionary:
	var values := PackedFloat32Array()
	values.resize(SIZE * SIZE)
	var min_value := INF
	var max_value := -INF
	var span_m: float = TerrainSettingsScript.CHUNK_SIZE_M * SPAN_CHUNKS
	var origin: float = -span_m * 0.5
	for y in range(SIZE):
		var world_z: float = origin + (float(y) / float(SIZE - 1)) * span_m
		for x in range(SIZE):
			var world_x: float = origin + (float(x) / float(SIZE - 1)) * span_m
			var layers: Dictionary = world.provider.sample_layers(world_x, world_z, world.seed, world.region_size_m)
			var value: float = float(layers[layer])
			var index: int = y * SIZE + x
			values[index] = value
			min_value = min(min_value, value)
			max_value = max(max_value, value)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var denom: float = max(0.0001, max_value - min_value)
	for y in range(SIZE):
		for x in range(SIZE):
			var value: float = float(values[y * SIZE + x])
			var normalized: float = clampf((value - min_value) / denom, 0.0, 1.0)
			image.set_pixel(x, y, Color(normalized, normalized, normalized))
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		return {"status": "fail", "error": "save:%d" % int(save_result)}
	return {
		"status": "pass",
		"range": max_value - min_value,
		"min": min_value,
		"max": max_value,
	}


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-layers] status=fail errors=%d" % errors.size())
