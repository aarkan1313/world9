extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamingPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_streaming_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_streaming_review"
const CAPTURE_SIZE := Vector2i(640, 360)
const GRID_COLUMNS := 2


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
	viewport.name = "StreamingReviewViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var scene: Node3D = TerrainStreamingPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.use_fast_gray_material = false
	scene.camera_height_m = 3600.0
	scene.camera_distance_m = 6500.0
	scene.build_when_idle = false
	viewport.add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))

	var cases: Array[Dictionary] = _review_cases()
	var captures: Array[Image] = []
	var manifest_cases: Array[Dictionary] = []
	for index in range(cases.size()):
		var item: Dictionary = cases[index]
		var image: Image = await _capture_case(viewport, scene, item, out_dir, index, errors)
		if image != null:
			captures.append(image)
			manifest_cases.append(_manifest_case(index, item))

	if captures.size() == cases.size():
		_save_contact_sheet(captures, out_dir.path_join("streaming_review_contact_sheet.png"), errors)
	_save_manifest(out_dir.path_join("streaming_review_manifest.json"), manifest_cases, errors)

	viewport.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-streaming-review] status=fail errors=%d out=%s" % [errors.size(), out_dir])
		return 1
	print("[wg9-terrain-streaming-review] status=pass cases=%d size=%dx%d out=%s" % [
		cases.size(),
		CAPTURE_SIZE.x,
		CAPTURE_SIZE.y,
		out_dir,
	])
	return 0


func _review_cases() -> Array[Dictionary]:
	var region: float = TerrainSettingsScript.REGION_SIZE_M
	return [
		{"label": "origin", "position": Vector2(0.0, 0.0), "yaw_deg": 42.0},
		{"label": "east_region", "position": Vector2(region * 1.25, region * 0.15), "yaw_deg": 35.0},
		{"label": "northwest_region", "position": Vector2(region * -0.75, region * 1.35), "yaw_deg": 62.0},
		{"label": "far_southwest", "position": Vector2(region * -2.1, region * -1.6), "yaw_deg": 20.0},
		{"label": "far_northeast", "position": Vector2(region * 2.4, region * 2.0), "yaw_deg": 55.0},
		{"label": "long_travel", "position": Vector2(region * 5.5, region * -3.25), "yaw_deg": 47.0},
	]


func _capture_case(
	viewport: SubViewport,
	scene: Node3D,
	item: Dictionary,
	out_dir: String,
	index: int,
	errors: Array[String]
) -> Image:
	scene.viewer_position_xz = item["position"] as Vector2
	scene.camera_yaw_rad = deg_to_rad(float(item["yaw_deg"]))
	_drain_streaming_queue(scene, errors)
	await process_frame
	await process_frame
	await process_frame
	var image: Image = _viewport_image(viewport, errors)
	if image == null:
		return null
	var stats: Dictionary = _image_stats(image)
	_check_stats(str(item["label"]), stats, errors)
	var path: String = out_dir.path_join("review_%02d_%s.png" % [index, str(item["label"])])
	var save_result: Error = image.save_png(path)
	if save_result != OK:
		errors.append("save_%s:%d" % [str(item["label"]), int(save_result)])
	return image


func _drain_streaming_queue(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(30):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0)
		var queued: int = int(report.get("queued_build_count", 0))
		var active: int = int(report.get("active_count", 0))
		if queued == 0 and int(scene.built_chunk_count()) >= active:
			return
	errors.append("queue_not_drained:%s" % str(scene.diagnostics_text()))


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


func _save_contact_sheet(captures: Array[Image], path: String, errors: Array[String]) -> void:
	var rows: int = int(ceil(float(captures.size()) / float(GRID_COLUMNS)))
	var sheet := Image.create(
		CAPTURE_SIZE.x * GRID_COLUMNS,
		CAPTURE_SIZE.y * rows,
		false,
		Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.03, 0.03, 0.03))
	for index in range(captures.size()):
		var column: int = index % GRID_COLUMNS
		var row: int = index / GRID_COLUMNS
		var dest := Vector2i(column * CAPTURE_SIZE.x, row * CAPTURE_SIZE.y)
		sheet.blit_rect(captures[index], Rect2i(Vector2i.ZERO, CAPTURE_SIZE), dest)
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _save_manifest(path: String, cases: Array[Dictionary], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % path)
		return
	var manifest := {
		"schema": "worldgen9.streaming_review_manifest.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"grid_columns": GRID_COLUMNS,
		"cases": cases,
	}
	file.store_string(JSON.stringify(manifest, "\t"))


func _manifest_case(index: int, item: Dictionary) -> Dictionary:
	var position: Vector2 = item["position"] as Vector2
	return {
		"index": index,
		"label": str(item["label"]),
		"position_m": [position.x, position.y],
		"yaw_deg": float(item["yaw_deg"]),
		"image": "review_%02d_%s.png" % [index, str(item["label"])],
	}


func _check_stats(label: String, stats: Dictionary, errors: Array[String]) -> void:
	if stats.is_empty():
		return
	if float(stats["luma_range"]) < 0.06:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	if int(stats["unique_colors"]) < 16:
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
