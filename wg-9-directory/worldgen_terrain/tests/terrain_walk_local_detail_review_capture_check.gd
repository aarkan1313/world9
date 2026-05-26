extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_walk_local_detail_review"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MAX_DRAIN_FRAMES := 260
const CAPTURE_CENTER_XZ := Vector2(128.0, 96.0)


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
		print("[wg9-walk-local-detail-review-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0

	var viewport := SubViewport.new()
	viewport.name = "WalkLocalDetailReviewViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	scene.debug_mode = TerrainWorldScript.DEBUG_ELEVATION_COLOR
	scene.use_local_detail = false
	viewport.add_child(scene)

	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
		_report(errors, out_dir)
		return 1
	scene.viewer_position_xz = CAPTURE_CENTER_XZ
	scene.camera_yaw_rad = 0.0
	scene.look_pitch_rad = deg_to_rad(-34.0)
	var ground_y: float = scene.terrain.world.sample_height(scene.viewer_position_xz.x, scene.viewer_position_xz.y)
	scene.camera_world_y = ground_y + 140.0
	scene.camera_height_m = 140.0
	scene._camera_height_initialized = true
	scene._update_streamer()
	scene._update_camera()
	var base_frames: int = await _drain_base_terrain(scene, errors)
	await _render_frames(3)
	var base_path: String = out_dir.path_join("walk_base.png")
	var base_image: Image = _capture(viewport, base_path, errors)
	var base_stats: Dictionary = _image_stats(base_image)
	_check_stats("base", base_stats, errors)

	scene.apply_local_detail_surface_review(true, 0.85, false, 0.0, 2.0)
	var texture_frames: int = await _drain_local_detail(scene, errors)
	await _render_frames(3)
	var texture_path: String = out_dir.path_join("walk_local_texture.png")
	var texture_image: Image = _capture(viewport, texture_path, errors)
	var texture_stats: Dictionary = _image_stats(texture_image)
	_check_stats("texture", texture_stats, errors)

	scene.apply_local_detail_surface_review(true, 0.85, true, 1.0, 4.0)
	var displacement_frames: int = await _drain_local_detail(scene, errors)
	await _render_frames(3)
	var displacement_path: String = out_dir.path_join("walk_local_displacement.png")
	var displacement_image: Image = _capture(viewport, displacement_path, errors)
	var displacement_stats: Dictionary = _image_stats(displacement_image)
	_check_stats("displacement", displacement_stats, errors)

	var texture_delta: float = _mean_abs_luma_delta(texture_image, displacement_image)
	_save_contact_sheet([base_image, texture_image, displacement_image], out_dir.path_join("walk_local_detail_contact_sheet.png"), errors)

	var detail_stats: Dictionary = scene.local_detail.build_stats() if scene.local_detail != null else {}
	_save_manifest(
		out_dir.path_join("walk_local_detail_manifest.json"),
		scene,
		[
			_case_record("base", base_path, base_stats, {"surface_material": false, "visual_displacement": false}),
			_case_record("texture", texture_path, texture_stats, {"surface_material": true, "normal_strength": 0.85, "visual_displacement": false}),
			_case_record("displacement", displacement_path, displacement_stats, {"surface_material": true, "normal_strength": 0.85, "visual_displacement": true, "displacement_strength": 1.0, "displacement_limit_m": 4.0}),
		],
		texture_delta,
		detail_stats,
		errors
	)
	viewport.queue_free()
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-walk-local-detail-review-render] status=pass base_range=%.3f texture_range=%.3f displacement_delta=%.5f frames=%d/%d/%d detail_assign=%.0fms texture=%.0fms out=%s" % [
		float(base_stats["luma_range"]),
		float(texture_stats["luma_range"]),
		texture_delta,
		base_frames,
		texture_frames,
		displacement_frames,
		float(detail_stats.get("last_patch_assign_ms", 0.0)),
		float(detail_stats.get("last_surface_texture_ms", 0.0)),
		out_dir,
	])
	return 0


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
		):
			return index + 1
		await process_frame
	errors.append("base_drain_timeout:%s" % JSON.stringify(scene.terrain.build_stats()))
	return MAX_DRAIN_FRAMES


func _drain_local_detail(scene: Node3D, errors: Array[String]) -> int:
	if scene.local_detail == null:
		errors.append("local_detail_null")
		return 0
	for index in range(MAX_DRAIN_FRAMES):
		var report: Dictionary = scene.step_viewer(0.0, Vector2.ZERO, 0.0, 0.0)
		if report.get("status", "fail") != "pass":
			errors.append("detail_report_failed:%s" % str(report))
			return index + 1
		var stats: Dictionary = scene.local_detail.build_stats()
		if (
			int(stats.get("active_patches", 0)) >= 1
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("queued_worker_builds", 0)) == 0
		):
			return index + 1
		await process_frame
	errors.append("detail_drain_timeout:%s" % JSON.stringify(scene.local_detail.build_stats()))
	return MAX_DRAIN_FRAMES


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
	var min_luma_range := 0.005 if label == "base" else 0.04
	if float(stats["luma_range"]) < min_luma_range:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	var min_colors := 6 if label == "base" else 12
	if int(stats["unique_colors"]) < min_colors:
		errors.append("%s_low_color_variety:%d" % [label, int(stats["unique_colors"])])


func _image_stats(image: Image) -> Dictionary:
	if image == null:
		return {}
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


func _case_record(label: String, path: String, image_stats: Dictionary, settings: Dictionary) -> Dictionary:
	return {
		"label": label,
		"image": path.get_file(),
		"settings": settings,
		"luma_range": float(image_stats.get("luma_range", 0.0)),
		"unique_colors": int(image_stats.get("unique_colors", 0)),
	}


func _stable_detail_budget(detail_stats: Dictionary) -> Dictionary:
	return {
		"active_patches": int(detail_stats.get("active_patches", 0)),
		"active_heightfields": int(detail_stats.get("active_heightfields", 0)),
		"collision_enabled": bool(detail_stats.get("collision_enabled", false)),
		"vertices_per_side": int(detail_stats.get("vertices_per_side", 0)),
		"spacing_m": float(detail_stats.get("spacing_m", 0.0)),
		"vertex_count_per_patch": int(detail_stats.get("vertex_count_per_patch", 0)),
		"index_count_per_patch": int(detail_stats.get("index_count_per_patch", 0)),
		"bytes_estimate_per_patch": int(detail_stats.get("bytes_estimate_per_patch", 0)),
		"heightfield_bytes_per_patch": int(detail_stats.get("heightfield_bytes_per_patch", 0)),
	}


func _save_manifest(
	path: String,
	scene: Node3D,
	cases: Array,
	texture_to_displacement_delta: float,
	detail_stats: Dictionary,
	errors: Array[String]
) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % path)
		return
	var manifest := {
		"schema": "worldgen9.walk_local_detail_review_manifest.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"viewer_position_xz": [scene.viewer_position_xz.x, scene.viewer_position_xz.y],
		"camera": {
			"height_m": scene.camera_height_m,
			"yaw_deg": rad_to_deg(scene.camera_yaw_rad),
			"pitch_deg": rad_to_deg(scene.look_pitch_rad),
		},
		"detail_budget": _stable_detail_budget(detail_stats),
		"texture_to_displacement_mean_abs_luma_delta": texture_to_displacement_delta,
		"review_flags": _review_flags(cases, texture_to_displacement_delta),
		"cases": cases,
	}
	file.store_string(JSON.stringify(manifest, "\t"))


func _review_flags(cases: Array, texture_to_displacement_delta: float) -> Array[String]:
	var flags: Array[String] = []
	if texture_to_displacement_delta < 0.001:
		flags.append("subtle_displacement_luma_delta")
	for case in cases:
		var record: Dictionary = case as Dictionary
		if float(record.get("luma_range", 0.0)) < 0.06:
			flags.append("%s_low_luma_margin" % str(record.get("label", "unknown")))
	return flags


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-walk-local-detail-review-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
