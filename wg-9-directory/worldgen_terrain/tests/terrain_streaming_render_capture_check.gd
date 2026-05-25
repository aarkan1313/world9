extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_streaming_preview"
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
	var viewport := SubViewport.new()
	viewport.name = "StreamingCaptureViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	viewport.add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	for _index in range(8):
		scene.step_viewer(0.25, Vector2(0.0, 1.0), 0.0)
	await process_frame
	await process_frame
	await process_frame
	var motion_path: String = out_dir.path_join("streaming_in_motion.png")
	var motion_stats: Dictionary = _capture(viewport, motion_path, errors)
	_check_stats("motion", motion_stats, errors)
	_drain_streaming_queue(scene, errors)
	await process_frame
	await process_frame
	await process_frame
	var settled_path: String = out_dir.path_join("streaming_settled_gray.png")
	var settled_stats: Dictionary = _capture(viewport, settled_path, errors)
	_check_stats("settled", settled_stats, errors)
	var compatibility_path: String = out_dir.path_join("streaming_gray.png")
	var compatibility_stats: Dictionary = _capture(viewport, compatibility_path, errors)
	_check_stats("compatibility", compatibility_stats, errors)
	viewport.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-streaming-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		return 1
	print("[wg9-terrain-streaming-render] status=pass size=%dx%d out=%s" % [CAPTURE_SIZE.x, CAPTURE_SIZE.y, out_dir])
	return 0


func _drain_streaming_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(24):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var queued: int = int(report.get("queued_build_count", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and int(scene.built_chunk_count()) >= active:
			return
	errors.append("settled_queue_not_drained:%s" % str(scene.diagnostics_text()))


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
	if float(stats["luma_range"]) < 0.06:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	if int(stats["unique_colors"]) < 2:
		errors.append("%s_low_color_variety:%d" % [label, int(stats["unique_colors"])])


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
			colors["%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]] = true
	return {
		"luma_range": max_luma - min_luma,
		"unique_colors": colors.size(),
	}
