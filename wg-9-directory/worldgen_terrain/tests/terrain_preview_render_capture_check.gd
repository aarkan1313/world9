extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_rendered_preview"
const CAPTURE_SIZE := Vector2i(1024, 768)
const PREVIEW_VERTICES := 33
const PREVIEW_RADIUS := 1


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var modes: Array[String] = [
		TerrainWorldScript.DEBUG_GRAY,
		TerrainWorldScript.DEBUG_LOD_RING,
		TerrainWorldScript.DEBUG_HEIGHT_BANDS,
		TerrainWorldScript.DEBUG_SEAM,
		TerrainWorldScript.DEBUG_FAMILY_PALETTE,
		TerrainWorldScript.DEBUG_HYDROLOGY,
	]
	var viewport := SubViewport.new()
	viewport.name = "CaptureViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var scene: Node3D = TerrainPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.use_fast_gray_material = true
	scene.use_native_chunk_payloads = true
	viewport.add_child(scene)
	if not scene.setup(TerrainWorldScript.DEBUG_GRAY, PREVIEW_VERTICES, PREVIEW_RADIUS, 1337):
		errors.append("preview_setup")
		viewport.queue_free()
		for error in errors:
			push_error(error)
		print("[wg9-terrain-preview-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		return 1
	for mode in modes:
		var path: String = out_dir.path_join("preview_%s.png" % mode)
		scene.apply_debug_mode(mode)
		var stats: Dictionary = await _capture_mode(viewport, path, errors)
		if not stats.is_empty():
			if float(stats["luma_range"]) <= 0.02:
				errors.append("%s_blank_luma" % mode)
			if mode == TerrainWorldScript.DEBUG_GRAY and float(stats["luma_range"]) < 0.18:
				errors.append("gray_low_luma_range:%.3f" % float(stats["luma_range"]))
			var minimum_colors: int = _minimum_unique_colors(mode)
			if int(stats["unique_colors"]) < minimum_colors:
				errors.append("%s_low_color_variety:%d" % [mode, int(stats["unique_colors"])])
	viewport.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-preview-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		return 1
	print("[wg9-terrain-preview-render] status=pass modes=%d size=%dx%d out=%s" % [modes.size(), CAPTURE_SIZE.x, CAPTURE_SIZE.y, out_dir])
	return 0


func _capture_mode(viewport: SubViewport, path: String, errors: Array[String]) -> Dictionary:
	await process_frame
	await process_frame
	await process_frame
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


func _image_stats(image: Image) -> Dictionary:
	var min_luma := INF
	var max_luma := -INF
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.get_luminance()
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			var key: String = "%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]
			colors[key] = true
	return {
		"luma_range": max_luma - min_luma,
		"unique_colors": colors.size(),
	}


func _minimum_unique_colors(mode: String) -> int:
	if mode == TerrainWorldScript.DEBUG_GRAY:
		return 12
	if mode == TerrainWorldScript.DEBUG_LOD_RING:
		return 3
	if mode == TerrainWorldScript.DEBUG_HEIGHT_BANDS:
		return 4
	if mode == TerrainWorldScript.DEBUG_SEAM:
		return 3
	if mode == TerrainWorldScript.DEBUG_FAMILY_PALETTE:
		return 2
	if mode == TerrainWorldScript.DEBUG_HYDROLOGY:
		return 8
	return 2
