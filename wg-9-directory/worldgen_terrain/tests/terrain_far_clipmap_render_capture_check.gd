extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_far_clipmap"
const CAPTURE_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if DisplayServer.get_name() == "headless":
		print("[wg9-terrain-far-clipmap-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
		_report(errors, out_dir)
		return 1
	var viewport := SubViewport.new()
	viewport.name = "FarClipmapCaptureViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	root.add_child(clipmap)
	if not clipmap.setup(world):
		errors.append("clipmap_setup_failed")
	var update: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	if update.get("status", "fail") != "pass":
		errors.append("clipmap_update:%s" % str(update))
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	camera.far = 80000.0
	camera.look_at_from_position(Vector3(-7400.0, 5200.0, -9800.0), Vector3(0.0, 150.0, 0.0), Vector3.UP)
	root.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -36.0, 0.0)
	light.light_energy = 1.6
	root.add_child(light)
	await process_frame
	await process_frame
	await process_frame
	var gray_stats: Dictionary = _capture(viewport, out_dir.path_join("far_clipmap_gray.png"), errors)
	_check_stats("gray", gray_stats, errors)
	clipmap.apply_surface_material_settings(true, 0.8, true)
	await process_frame
	await process_frame
	var surface_stats: Dictionary = _capture(viewport, out_dir.path_join("far_clipmap_surface_material.png"), errors)
	_check_stats("surface", surface_stats, errors)
	_check_capture_luma_alignment("gray_surface", gray_stats, surface_stats, errors)
	clipmap.set_debug_level_colors(true)
	await process_frame
	await process_frame
	var level_stats: Dictionary = _capture(viewport, out_dir.path_join("far_clipmap_levels.png"), errors)
	_check_stats("levels", level_stats, errors)
	root.remove_child(clipmap)
	clipmap.queue_free()
	var wide_clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	wide_clipmap.level_count = 4
	root.add_child(wide_clipmap)
	if not wide_clipmap.setup(world):
		errors.append("wide_clipmap_setup_failed")
	var wide_update: Dictionary = wide_clipmap.update_viewer(Vector2.ZERO)
	if wide_update.get("status", "fail") != "pass":
		errors.append("wide_clipmap_update:%s" % str(wide_update))
	camera.far = 160000.0
	camera.fov = 42.0
	camera.look_at_from_position(Vector3(-23000.0, 15000.0, -27000.0), Vector3(0.0, 220.0, 0.0), Vector3.UP)
	await process_frame
	await process_frame
	var wide_stats: Dictionary = _capture(viewport, out_dir.path_join("far_clipmap_4ring_wide.png"), errors)
	_check_stats("wide", wide_stats, errors)
	viewport.queue_free()
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-terrain-far-clipmap-render] status=pass gray_range=%.3f surface_range=%.3f level_colors=%d wide_range=%.3f out=%s" % [
		float(gray_stats["luma_range"]),
		float(surface_stats["luma_range"]),
		int(level_stats["unique_colors"]),
		float(wide_stats["luma_range"]),
		out_dir,
	])
	return 0


func _capture(viewport: SubViewport, path: String, errors: Array[String]) -> Dictionary:
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		errors.append("viewport_texture_null")
		return {}
	var image: Image = texture.get_image()
	if image == null:
		errors.append("viewport_image_null")
		return {}
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save:%d" % int(save_result))
		return {}
	return _image_stats(image)


func _check_stats(label: String, stats: Dictionary, errors: Array[String]) -> void:
	if stats.is_empty():
		return
	if float(stats["luma_range"]) < 0.05:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	var min_colors := 3 if label == "levels" else 2
	if int(stats["unique_colors"]) < min_colors:
		errors.append("%s_low_color_variety:%d" % [label, int(stats["unique_colors"])])


func _check_capture_luma_alignment(label: String, a: Dictionary, b: Dictionary, errors: Array[String]) -> void:
	if a.is_empty() or b.is_empty():
		return
	var luma_delta: float = absf(float(a["mean_luma"]) - float(b["mean_luma"]))
	var range_delta: float = absf(float(a["luma_range"]) - float(b["luma_range"]))
	if luma_delta > 0.055:
		errors.append("%s_luma_mismatch:%.4f" % [label, luma_delta])
	if range_delta > 0.080:
		errors.append("%s_range_mismatch:%.4f" % [label, range_delta])


func _image_stats(image: Image) -> Dictionary:
	var min_luma := INF
	var max_luma := -INF
	var total_luma := 0.0
	var samples := 0
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.get_luminance()
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			total_luma += luma
			samples += 1
			colors["%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]] = true
	return {
		"luma_range": max_luma - min_luma,
		"mean_luma": total_luma / float(max(1, samples)),
		"unique_colors": colors.size(),
	}


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-far-clipmap-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
