extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_visual"
const SIZE := 384
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
	var report: Dictionary = world.update_viewer(Vector2.ZERO)
	if report.get("status", "pass") != "pass":
		errors.append("world_update:%s" % str(report.get("errors", [])))
		_report(errors)
		return 1

	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var height_image: Image = _height_image(world)
	var lod_image: Image = _lod_image(report)
	var height_path: String = out_dir.path_join("terrain_world_gray_height.png")
	var lod_path: String = out_dir.path_join("terrain_world_lod_rings.png")
	var height_result: Error = height_image.save_png(height_path)
	var lod_result: Error = lod_image.save_png(lod_path)
	if height_result != OK:
		errors.append("save_height:%d" % int(height_result))
	if lod_result != OK:
		errors.append("save_lod:%d" % int(lod_result))
	var height_stats: Dictionary = _image_stats(height_image)
	var lod_stats: Dictionary = _image_stats(lod_image)
	if float(height_stats["range"]) <= 0.01:
		errors.append("height_image_blank")
	if int(lod_stats["unique_colors"]) < 3:
		errors.append("lod_image_low_variety:%d" % int(lod_stats["unique_colors"]))

	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-terrain-world-visual] status=pass size=%d height_range=%.3f lod_colors=%d out=%s" % [
		SIZE,
		float(height_stats["range"]),
		int(lod_stats["unique_colors"]),
		out_dir,
	])
	return 0


func _height_image(world: RefCounted) -> Image:
	var values := PackedFloat32Array()
	values.resize(SIZE * SIZE)
	var min_height := INF
	var max_height := -INF
	var span_m: float = TerrainSettingsScript.CHUNK_SIZE_M * SPAN_CHUNKS
	var origin: float = -span_m * 0.5
	for y in range(SIZE):
		var world_z: float = origin + (float(y) / float(SIZE - 1)) * span_m
		for x in range(SIZE):
			var world_x: float = origin + (float(x) / float(SIZE - 1)) * span_m
			var height: float = world.sample_height(world_x, world_z)
			var index: int = y * SIZE + x
			values[index] = height
			min_height = min(min_height, height)
			max_height = max(max_height, height)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var denom: float = max(0.0001, max_height - min_height)
	for y in range(SIZE):
		for x in range(SIZE):
			var h: float = float(values[y * SIZE + x])
			var normalized: float = clampf((h - min_height) / denom, 0.0, 1.0)
			var shaded: float = pow(normalized, 0.82)
			image.set_pixel(x, y, Color(shaded, shaded, shaded))
	return image


func _lod_image(report: Dictionary) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	image.fill(Color(0.02, 0.02, 0.02))
	var chunk_size: float = TerrainSettingsScript.CHUNK_SIZE_M
	var span_m: float = chunk_size * SPAN_CHUNKS
	var origin: float = -span_m * 0.5
	var cell: float = float(SIZE) / SPAN_CHUNKS
	for item_value in report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var px0: int = int(floor(((float(chunk_x) * chunk_size) - origin) / span_m * float(SIZE)))
		var py0: int = int(floor(((float(chunk_z) * chunk_size) - origin) / span_m * float(SIZE)))
		var px1: int = int(ceil(float(px0) + cell))
		var py1: int = int(ceil(float(py0) + cell))
		var color: Color = _lod_color(int(item["lod"]))
		for y in range(max(0, py0), min(SIZE, py1)):
			for x in range(max(0, px0), min(SIZE, px1)):
				var border: bool = x == px0 or y == py0 or x == px1 - 1 or y == py1 - 1
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0) if border else color)
	return image


func _lod_color(lod: int) -> Color:
	match lod:
		0:
			return Color(0.26, 0.62, 0.93)
		1:
			return Color(0.35, 0.78, 0.43)
		2:
			return Color(0.95, 0.76, 0.28)
		3:
			return Color(0.90, 0.45, 0.25)
		_:
			return Color(0.66, 0.38, 0.85)


func _image_stats(image: Image) -> Dictionary:
	var min_luma := INF
	var max_luma := -INF
	var colors: Dictionary = {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.get_luminance()
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			var key: String = "%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]
			colors[key] = true
	return {
		"range": max_luma - min_luma,
		"unique_colors": colors.size(),
	}


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-world-visual] status=fail errors=%d" % errors.size())
