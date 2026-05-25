extends SceneTree

const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_local_detail_displacement"
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
		print("[wg9-local-detail-displacement-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
		_report(errors, out_dir)
		return 1
	var viewport := SubViewport.new()
	viewport.name = "LocalDetailDisplacementCaptureViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var detail: Node3D = TerrainLocalDetailNodeScript.new()
	detail.enabled = true
	detail.patch_size_m = 256.0
	detail.vertices_per_side = 257
	detail.radius_patches = 0
	detail.max_active_patches = 1
	detail.use_native_payloads = true
	detail.use_native_workers = false
	root.add_child(detail)
	if not detail.setup(world):
		errors.append("detail_setup:%s" % str(detail.errors))
	var update: Dictionary = detail.update_viewer(Vector2(96.0, 96.0))
	if update.get("status", "fail") != "pass":
		errors.append("detail_update:%s" % str(update))
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 45.0
	camera.look_at_from_position(Vector3(128.0, 255.0, 455.0), Vector3(128.0, 20.0, 128.0), Vector3.UP)
	root.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-54.0, -30.0, 0.0)
	light.light_energy = 1.8
	root.add_child(light)
	await process_frame
	await process_frame
	await process_frame
	var base_path: String = out_dir.path_join("local_detail_base.png")
	var base_image: Image = _capture_image(viewport, base_path, errors)
	var base_stats: Dictionary = _image_stats(base_image)
	_check_stats("base", base_stats, errors)
	detail.apply_surface_material_settings(true, 1.0, false, 0.0, 2.0, true)
	await process_frame
	await process_frame
	var texture_path: String = out_dir.path_join("local_detail_texture_material.png")
	var texture_image: Image = _capture_image(viewport, texture_path, errors)
	var texture_stats: Dictionary = _image_stats(texture_image)
	_check_stats("texture", texture_stats, errors)
	detail.apply_surface_material_settings(true, 1.0, true, 1.0, 4.0, true)
	await process_frame
	await process_frame
	var displacement_path: String = out_dir.path_join("local_detail_displacement.png")
	var displacement_image: Image = _capture_image(viewport, displacement_path, errors)
	var displacement_stats: Dictionary = _image_stats(displacement_image)
	_check_stats("displacement", displacement_stats, errors)
	var texture_delta: float = _mean_abs_luma_delta(texture_image, displacement_image)
	if texture_delta < 0.000001:
		errors.append("displacement_too_similar:%.6f" % texture_delta)
	_save_manifest(
		out_dir.path_join("local_detail_displacement_manifest.json"),
		detail,
		[
			_case_record("base", base_path, base_stats, {"surface_material": false, "visual_displacement": false}),
			_case_record("texture", texture_path, texture_stats, {"surface_material": true, "normal_strength": 1.0, "visual_displacement": false}),
			_case_record("displacement", displacement_path, displacement_stats, {"surface_material": true, "normal_strength": 1.0, "visual_displacement": true, "displacement_strength": 1.0, "displacement_limit_m": 4.0}),
		],
		texture_delta,
		errors
	)
	viewport.queue_free()
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-local-detail-displacement-render] status=pass base_range=%.3f texture_range=%.3f displacement_delta=%.5f out=%s" % [
		float(base_stats["luma_range"]),
		float(texture_stats["luma_range"]),
		texture_delta,
		out_dir,
	])
	return 0


func _capture_image(viewport: SubViewport, path: String, errors: Array[String]) -> Image:
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
	if int(stats["unique_colors"]) < 12:
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


func _case_record(label: String, path: String, image_stats: Dictionary, settings: Dictionary) -> Dictionary:
	return {
		"label": label,
		"image": path.get_file(),
		"settings": settings,
		"luma_range": float(image_stats.get("luma_range", 0.0)),
		"unique_colors": int(image_stats.get("unique_colors", 0)),
	}


func _save_manifest(
	path: String,
	detail: Node3D,
	cases: Array,
	texture_to_displacement_delta: float,
	errors: Array[String]
) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%s" % path)
		return
	var detail_stats: Dictionary = detail.build_stats()
	var manifest := {
		"schema": "worldgen9.local_detail_displacement_manifest.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"patch": {
			"patch_size_m": detail.patch_size_m,
			"vertices_per_side": int(detail_stats.get("vertices_per_side", 0)),
			"spacing_m": float(detail_stats.get("spacing_m", 0.0)),
			"vertex_count_per_patch": int(detail_stats.get("vertex_count_per_patch", 0)),
			"index_count_per_patch": int(detail_stats.get("index_count_per_patch", 0)),
			"bytes_estimate_per_patch": int(detail_stats.get("bytes_estimate_per_patch", 0)),
			"heightfield_bytes_per_patch": int(detail_stats.get("heightfield_bytes_per_patch", 0)),
		},
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
	print("[wg9-local-detail-displacement-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
