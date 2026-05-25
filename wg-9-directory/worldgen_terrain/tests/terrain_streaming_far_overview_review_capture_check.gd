extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_streaming_far_overview"
const CAPTURE_SIZE := Vector2i(960, 540)


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var manifest_cases: Array[Dictionary] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if DisplayServer.get_name() == "headless":
		print("[wg9-streaming-far-overview-review] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	var viewport := SubViewport.new()
	viewport.name = "StreamingFarOverviewReviewViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.use_fast_gray_material = true
	scene.fast_gray_exposure = 0.62
	scene.fast_gray_contrast = 1.28
	scene.use_far_clipmap = true
	scene.far_clipmap_rebuild_levels_per_update = 4
	scene.use_far_clipmap_native_workers = false
	scene.build_when_idle = false
	viewport.add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var image_3: Image = await _capture_overview(viewport, scene, 3, out_dir.path_join("streaming_far_overview_3ring.png"), manifest_cases, errors)
	var image_4: Image = await _capture_overview(viewport, scene, 4, out_dir.path_join("streaming_far_overview_4ring.png"), manifest_cases, errors)
	if image_3 != null and image_4 != null:
		_save_contact_sheet([image_3, image_4], out_dir.path_join("streaming_far_overview_contact_sheet.png"), errors)
	_save_manifest(out_dir.path_join("streaming_far_overview_manifest.json"), manifest_cases, errors)
	viewport.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-far-overview-review] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		return 1
	print("[wg9-streaming-far-overview-review] status=pass out=%s" % out_dir)
	return 0


func _capture_overview(
	viewport: SubViewport,
	scene: Node3D,
	level_count: int,
	path: String,
	manifest_cases: Array[Dictionary],
	errors: Array[String]
) -> Image:
	scene.apply_far_clipmap_geometry_review(level_count)
	_drain_far_clipmap(scene)
	scene.frame_far_clipmap_overview()
	await process_frame
	await process_frame
	await process_frame
	var image: Image = _viewport_image(viewport, errors)
	if image == null:
		return null
	var stats: Dictionary = _image_stats(image)
	_check_stats("%dring" % level_count, stats, errors)
	var diagnostics: String = str(scene.diagnostics_text())
	if not diagnostics.contains("far %dL" % level_count):
		errors.append("diagnostics_missing_%dL:%s" % [level_count, diagnostics])
	_record_manifest_case(scene, level_count, path, stats, manifest_cases)
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save_%dring:%d" % [level_count, int(save_result)])
	return image


func _drain_far_clipmap(scene: Node3D) -> void:
	for _index in range(16):
		if scene.far_clipmap == null or not scene.far_clipmap.has_pending_rebuilds():
			return
		scene.step_viewer(0.0, Vector2.ZERO, 0.0)


func _viewport_image(viewport: SubViewport, errors: Array[String]) -> Image:
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		errors.append("viewport_texture_null")
		return null
	var image: Image = texture.get_image()
	if image == null:
		errors.append("viewport_image_null")
		return null
	image.convert(Image.FORMAT_RGB8)
	return image


func _check_stats(label: String, stats: Dictionary, errors: Array[String]) -> void:
	if stats.is_empty():
		return
	if float(stats["luma_range"]) < 0.05:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	if int(stats["unique_colors"]) < 12:
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


func _save_contact_sheet(images: Array[Image], path: String, errors: Array[String]) -> void:
	var sheet := Image.create(CAPTURE_SIZE.x * images.size(), CAPTURE_SIZE.y, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.03, 0.03, 0.03))
	for index in range(images.size()):
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, CAPTURE_SIZE), Vector2i(index * CAPTURE_SIZE.x, 0))
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _record_manifest_case(
	scene: Node3D,
	level_count: int,
	path: String,
	image_stats: Dictionary,
	manifest_cases: Array[Dictionary]
) -> void:
	var far_stats: Dictionary = scene.far_clipmap.stats() if scene.far_clipmap != null else {}
	var budget: Dictionary = scene.far_clipmap.budget_report() if scene.far_clipmap != null else {}
	var levels: Array = budget.get("levels", [])
	var totals: Dictionary = budget.get("totals", {})
	var outer_level: Dictionary = levels[levels.size() - 1] if not levels.is_empty() else {}
	manifest_cases.append({
		"label": "%dring" % level_count,
		"level_count": level_count,
		"image": path.get_file(),
		"diagnostic_far_label": "far %dL" % level_count,
		"camera_distance_m": scene.camera_distance_m,
		"camera_height_m": scene.camera_height_m,
		"far_vertex_count": int(far_stats.get("vertices", 0)),
		"far_index_count": int(far_stats.get("indices", 0)),
		"far_triangle_count": int(totals.get("triangle_count", 0)),
		"far_diameter_m": float(outer_level.get("diameter_m", 0.0)),
		"mesh_plus_height_mib": float(totals.get("mesh_plus_height_mib", 0.0)),
		"luma_range": float(image_stats.get("luma_range", 0.0)),
		"unique_colors": int(image_stats.get("unique_colors", 0)),
	})


func _save_manifest(path: String, cases: Array[Dictionary], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % path)
		return
	var manifest := {
		"schema": "worldgen9.streaming_far_overview_manifest.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"cases": cases,
	}
	file.store_string(JSON.stringify(manifest, "\t"))
