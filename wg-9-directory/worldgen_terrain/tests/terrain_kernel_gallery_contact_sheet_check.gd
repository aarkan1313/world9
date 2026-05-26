extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainKernelGallerySceneScript := preload("res://worldgen_terrain/runtime/terrain_kernel_gallery_scene.gd")

const OUT_DIR := "factory/runtime/godot_kernel_gallery"
const TILE_IMAGE_SIZE := 128
const SHEET_COLUMNS := 6


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: Node3D = TerrainKernelGallerySceneScript.new()
	scene.auto_setup_on_ready = false
	scene.target_tile_count = 36
	scene.scan_radius_regions = 18
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = scene.gallery_report()
	if int(report.get("unique_kernel_count", 0)) < 36:
		errors.append("kernel_count:%d" % int(report.get("unique_kernel_count", 0)))
	var tiles: Array[Image] = []
	for site_value in scene.selected_sites:
		var site: Dictionary = site_value as Dictionary
		var image: Image = _site_image(scene, site, errors)
		if image != null:
			tiles.append(image)
	if tiles.size() == scene.selected_sites.size() and not tiles.is_empty():
		_save_contact_sheet(tiles, out_dir.path_join("kernel_gallery_contact_sheet.png"), errors)
	_save_manifest(out_dir.path_join("kernel_gallery_manifest.json"), report, scene.selected_sites, errors)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-kernel-gallery-contact-sheet] status=fail errors=%d out=%s report=%s" % [errors.size(), out_dir, str(report)])
		return 1
	print("[wg9-kernel-gallery-contact-sheet] status=pass tiles=%d kernels=%d out=%s" % [
		int(report.get("tile_count", 0)),
		int(report.get("unique_kernel_count", 0)),
		out_dir,
	])
	return 0


func _site_image(scene: Node3D, site: Dictionary, errors: Array[String]) -> Image:
	var center: Vector2 = site["center_m"] as Vector2
	var step_m: float = scene.sample_span_m / float(TILE_IMAGE_SIZE - 1)
	var origin_x: float = center.x - scene.sample_span_m * 0.5
	var origin_z: float = center.y - scene.sample_span_m * 0.5
	var heights: PackedFloat32Array = scene.world.sample_height_grid(origin_x, origin_z, step_m, TILE_IMAGE_SIZE, TILE_IMAGE_SIZE)
	if heights.size() != TILE_IMAGE_SIZE * TILE_IMAGE_SIZE:
		errors.append("height_size:%s:%d" % [str(site.get("kernel_id", "")), heights.size()])
		return null
	var min_height := INF
	var max_height := -INF
	for value in heights:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var denom: float = max(0.0001, max_height - min_height)
	var image := Image.create(TILE_IMAGE_SIZE, TILE_IMAGE_SIZE, false, Image.FORMAT_RGB8)
	for y in range(TILE_IMAGE_SIZE):
		for x in range(TILE_IMAGE_SIZE):
			var t: float = clampf((float(heights[y * TILE_IMAGE_SIZE + x]) - min_height) / denom, 0.0, 1.0)
			image.set_pixel(x, y, scene._elevation_ramp(t))
	return image


func _save_contact_sheet(tiles: Array[Image], path: String, errors: Array[String]) -> void:
	var rows: int = int(ceil(float(tiles.size()) / float(SHEET_COLUMNS)))
	var sheet := Image.create(TILE_IMAGE_SIZE * SHEET_COLUMNS, TILE_IMAGE_SIZE * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in range(tiles.size()):
		var column: int = index % SHEET_COLUMNS
		var row: int = index / SHEET_COLUMNS
		var dest := Vector2i(column * TILE_IMAGE_SIZE, row * TILE_IMAGE_SIZE)
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, Vector2i(TILE_IMAGE_SIZE, TILE_IMAGE_SIZE)), dest)
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _save_manifest(path: String, report: Dictionary, sites: Array[Dictionary], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % path)
		return
	var manifest_sites: Array[Dictionary] = []
	for index in range(sites.size()):
		var site: Dictionary = sites[index] as Dictionary
		var region: Vector2i = site["region"] as Vector2i
		manifest_sites.append({
			"index": index,
			"kernel_id": str(site.get("kernel_id", "")),
			"kernel_slot": str(site.get("kernel_slot", "")),
			"primary_family": str(site.get("primary_family", "")),
			"secondary_family": str(site.get("secondary_family", "")),
			"palette": str(site.get("palette", "")),
			"region": [region.x, region.y],
		})
	file.store_string(JSON.stringify({
		"schema": "worldgen9.kernel_gallery_manifest.v1",
		"contact_sheet": "kernel_gallery_contact_sheet.png",
		"tile_image_size": TILE_IMAGE_SIZE,
		"sheet_columns": SHEET_COLUMNS,
		"report": report,
		"sites": manifest_sites,
	}, "\t"))
