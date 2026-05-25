extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_walk_density_review"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MAX_DRAIN_FRAMES := 260
const MANIFEST_NAME := "walk_density_manifest.json"


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
		print("[wg9-walk-density-review-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0

	var viewport := SubViewport.new()
	viewport.name = "WalkDensityReviewViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var capture_129: Image = await _capture_density(viewport, 129, out_dir.path_join("walk_density_129_4m.png"), errors)
	var stats_129: Dictionary = _image_stats(capture_129)
	_check_stats("density_129", stats_129, errors)
	var capture_257: Image = await _capture_density(viewport, 257, out_dir.path_join("walk_density_257_2m.png"), errors)
	var stats_257: Dictionary = _image_stats(capture_257)
	_check_stats("density_257", stats_257, errors)
	_save_contact_sheet([capture_129, capture_257], out_dir.path_join("walk_density_contact_sheet.png"), errors)
	var luma_delta: float = _mean_abs_luma_delta(capture_129, capture_257)
	_write_manifest(out_dir, stats_129, stats_257, luma_delta, errors)

	viewport.queue_free()
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-walk-density-review-render] status=pass range_129=%.3f range_257=%.3f luma_delta=%.5f out=%s" % [
		float(stats_129["luma_range"]),
		float(stats_257["luma_range"]),
		luma_delta,
		out_dir,
	])
	return 0


func _capture_density(viewport: SubViewport, vertices_per_side: int, path: String, errors: Array[String]) -> Image:
	for child in viewport.get_children():
		child.queue_free()
	await process_frame
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_GRAY
	scene.vertices_per_side = vertices_per_side
	scene.visible_radius_chunks = 3
	scene.use_far_clipmap = false
	scene.viewer_position_xz = Vector2(256.0, 256.0)
	scene.camera_yaw_rad = deg_to_rad(32.0)
	scene.look_pitch_rad = deg_to_rad(-70.0)
	viewport.add_child(scene)
	if not scene.setup():
		errors.append("setup_%d_failed:%s" % [vertices_per_side, str(scene.errors)])
		return null
	scene.viewer_position_xz = Vector2(256.0, 256.0)
	scene.camera_yaw_rad = deg_to_rad(32.0)
	scene.look_pitch_rad = deg_to_rad(-70.0)
	var ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
	scene.camera_world_y = ground_y + 1400.0
	scene.camera_height_m = 1400.0
	scene._camera_height_initialized = true
	scene._update_streamer()
	if scene.terrain.has_method("clear_native_worker_backlog_for_preview"):
		scene.terrain.call("clear_native_worker_backlog_for_preview")
	if scene.terrain.has_method("rebuild_all_active_for_preview"):
		scene.terrain.call("rebuild_all_active_for_preview", 0)
	scene._update_camera()
	_drain_base_terrain(scene, errors)
	_frame_density_review_camera(scene)
	await _render_frames(3)
	var image: Image = _capture(viewport, path, errors)
	scene.queue_free()
	await process_frame
	return image


func _drain_base_terrain(scene: Node3D, errors: Array[String]) -> int:
	for index in range(MAX_DRAIN_FRAMES):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0, 0.0)
		if report.get("status", "fail") != "pass":
			errors.append("base_report_failed:%s" % str(report))
			return index + 1
		var stats: Dictionary = scene.terrain.build_stats()
		if (
			scene.built_chunk_count() >= scene.expected_active_count()
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("queued_native_worker_builds", 0)) == 0
			and not scene._has_pending_visual_work()
		):
			return index + 1
		await process_frame
	errors.append("base_drain_timeout:%s" % JSON.stringify(scene.terrain.build_stats()))
	return MAX_DRAIN_FRAMES


func _frame_density_review_camera(scene: Node3D) -> void:
	var ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
	var camera: Camera3D = scene.camera as Camera3D
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1800.0
	camera.global_position = Vector3(scene.viewer_position_xz.x, ground_y + 5000.0, scene.viewer_position_xz.y)
	camera.look_at(Vector3(scene.viewer_position_xz.x, ground_y, scene.viewer_position_xz.y), Vector3(0.0, 0.0, -1.0))


func _render_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _capture(viewport: SubViewport, path: String, errors: Array[String]) -> Image:
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		errors.append("viewport_texture_null")
		return null
	var image: Image = texture.get_image()
	if image == null:
		errors.append("viewport_image_null")
		return null
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save:%d:%s" % [int(save_result), path])
	return image


func _check_stats(label: String, stats: Dictionary, errors: Array[String]) -> void:
	if stats.is_empty():
		errors.append("%s_stats_empty" % label)
		return
	if float(stats["luma_range"]) < 0.04:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	if float(stats["max_luma"]) > 0.82:
		errors.append("%s_high_luma:%.3f" % [label, float(stats["max_luma"])])
	if float(stats["bright_pixel_fraction"]) > 0.03:
		errors.append("%s_too_many_bright_pixels:%.3f" % [label, float(stats["bright_pixel_fraction"])])
	if float(stats["dark_pixel_fraction"]) > 0.05:
		errors.append("%s_too_many_background_pixels:%.3f" % [label, float(stats["dark_pixel_fraction"])])
	if float(stats["mean_luma"]) > 0.62:
		errors.append("%s_mean_luma_high:%.3f" % [label, float(stats["mean_luma"])])
	if int(stats["unique_colors"]) < 6:
		errors.append("%s_low_color_variety:%d" % [label, int(stats["unique_colors"])])


func _image_stats(image: Image) -> Dictionary:
	if image == null:
		return {}
	var min_luma := INF
	var max_luma := -INF
	var luma_total := 0.0
	var sample_count := 0
	var bright_count := 0
	var dark_count := 0
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.get_luminance()
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			luma_total += luma
			sample_count += 1
			if luma >= 0.80:
				bright_count += 1
			if luma <= 0.19:
				dark_count += 1
			colors["%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]] = true
	return {
		"luma_range": max_luma - min_luma,
		"min_luma": min_luma,
		"max_luma": max_luma,
		"mean_luma": luma_total / float(max(1, sample_count)),
		"bright_pixel_fraction": float(bright_count) / float(max(1, sample_count)),
		"dark_pixel_fraction": float(dark_count) / float(max(1, sample_count)),
		"unique_colors": colors.size(),
	}


func _mean_abs_luma_delta(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 0.0
	var width: int = min(a.get_width(), b.get_width())
	var height: int = min(a.get_height(), b.get_height())
	var total := 0.0
	var samples := 0
	for y in range(0, height, 8):
		for x in range(0, width, 8):
			total += absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			samples += 1
	return total / float(max(1, samples))


func _save_contact_sheet(images: Array[Image], path: String, errors: Array[String]) -> void:
	var sheet := Image.create(CAPTURE_SIZE.x * images.size(), CAPTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.02, 1.0))
	for index in range(images.size()):
		if images[index] == null:
			continue
		var source: Image = images[index].duplicate()
		if source.get_format() != Image.FORMAT_RGBA8:
			source.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(source, Rect2i(Vector2i.ZERO, CAPTURE_SIZE), Vector2i(index * CAPTURE_SIZE.x, 0))
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _write_manifest(out_dir: String, stats_129: Dictionary, stats_257: Dictionary, luma_delta: float, errors: Array[String]) -> void:
	var manifest := {
		"version": 1,
		"schema": "worldgen9.walk_density_review_manifest.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"cases": [
			{
				"label": "walk_density_129_4m",
				"path": "walk_density_129_4m.png",
				"vertices_per_side": 129,
				"spacing_m": 4.0,
				"stats": stats_129,
			},
			{
				"label": "walk_density_257_2m",
				"path": "walk_density_257_2m.png",
				"vertices_per_side": 257,
				"spacing_m": 2.0,
				"stats": stats_257,
			},
		],
		"mean_abs_luma_delta_129_to_257": luma_delta,
		"readability_policy": {
			"max_luma_limit": 0.82,
			"bright_pixel_luma_threshold": 0.80,
			"bright_pixel_fraction_limit": 0.03,
			"dark_pixel_luma_threshold": 0.19,
			"dark_pixel_fraction_limit": 0.05,
			"mean_luma_limit": 0.62,
		},
		"status": "pass" if errors.is_empty() else "fail",
	}
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % out_dir.path_join(MANIFEST_NAME))
		return
	file.store_string(JSON.stringify(manifest, "\t"))


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-walk-density-review-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
