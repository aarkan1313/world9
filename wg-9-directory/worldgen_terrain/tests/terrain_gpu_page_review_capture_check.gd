extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn"
const OUT_DIR := "factory/runtime/godot_gpu_page_review"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MANIFEST_NAME := "gpu_page_review_manifest.json"


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
		print("[wg9-gpu-page-review-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	if not _rendering_device_available():
		print("[wg9-gpu-page-review-render] status=unsupported rendering_device_unavailable out=%s" % out_dir)
		return 0

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		_report(errors, out_dir)
		return 1

	var viewport := SubViewport.new()
	viewport.name = "GpuPageReviewViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		viewport.queue_free()
		_report(errors, out_dir)
		return 1
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	viewport.add_child(scene)
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
	else:
		var drain_summary: Dictionary = _far_page_counter_summary(scene)
		drain_summary = await _drain_scene(scene, errors, drain_summary)
		for _index in range(4):
			await process_frame
		var capture_path: String = out_dir.path_join("gpu_page_review.png")
		var image: Image = _capture(viewport, capture_path, errors)
		var image_stats: Dictionary = _image_stats(image)
		_check_image_stats(image_stats, errors)
		var gpu_stats: Dictionary = _gpu_stats(scene)
		_check_gpu_stats(gpu_stats, scene, errors)
		var descriptor_summary: Dictionary = _descriptor_summary(scene)
		_check_descriptor_summary(descriptor_summary, scene, errors)
		_check_drain_summary(drain_summary, errors)
		_write_manifest(out_dir, image_stats, gpu_stats, drain_summary, descriptor_summary, errors)

	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap != null and far_clipmap.has_method("clear_levels"):
		far_clipmap.call("clear_levels", true)
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	viewport.queue_free()
	await process_frame
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-gpu-page-review-render] status=pass luma_range=%.3f unique_colors=%d rd_uploads=%d rd_normal_uploads=%d out=%s" % [
		float(_read_manifest_stats(out_dir).get("luma_range", 0.0)),
		int(_read_manifest_stats(out_dir).get("unique_colors", 0)),
		int(_read_manifest_gpu(out_dir).get("rd_uploads", 0)),
		int(_read_manifest_gpu(out_dir).get("rd_compute_normal_uploads", 0)),
		out_dir,
	])
	return 0


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _far_page_counter_summary(scene: Node3D) -> Dictionary:
	var summary := {
		"frames": 0,
		"total_page_descriptor_image_builds": 0,
		"total_page_descriptor_texture_hits": 0,
		"total_page_descriptor_preencoded_hits": 0,
		"total_gpu_page_normal_dispatches": 0,
		"max_pending_levels": 0,
	}
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null or not far_clipmap.has_method("stats"):
		return summary
	return _accumulate_far_page_stats(summary, far_clipmap.call("stats") as Dictionary)


func _drain_scene(scene: Node3D, errors: Array[String], summary: Dictionary) -> Dictionary:
	for _index in range(90):
		var report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("step_failed:%s" % str(report))
			return summary
		var far_clipmap: Node = scene.get("far_clipmap") as Node
		var stats: Dictionary = {}
		if far_clipmap != null and far_clipmap.has_method("stats"):
			stats = far_clipmap.call("stats") as Dictionary
		summary = _accumulate_far_page_stats(summary, stats)
		var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
		if (
			int(scene.call("built_chunk_count")) >= int(scene.call("expected_active_count"))
			and int(stats.get("pending_levels", 0)) == 0
			and int(stats.get("active_native_workers", 0)) == 0
			and int(stats.get("queued_native_worker_builds", 0)) == 0
			and int(gpu_state.get("rd_uploads", 0)) >= int(scene.get("far_clipmap_level_count"))
			and int(gpu_state.get("rd_compute_normal_uploads", 0)) >= int(scene.get("far_clipmap_level_count"))
		):
			return summary
		await process_frame
	errors.append("drain_timeout:%s" % str(scene.call("diagnostics_text")))
	return summary


func _accumulate_far_page_stats(summary: Dictionary, stats: Dictionary) -> Dictionary:
	summary["frames"] = int(summary["frames"]) + 1
	summary["total_page_descriptor_image_builds"] = int(summary["total_page_descriptor_image_builds"]) + int(stats.get("last_page_descriptor_image_builds", 0))
	summary["total_page_descriptor_texture_hits"] = int(summary["total_page_descriptor_texture_hits"]) + int(stats.get("last_page_descriptor_texture_hits", 0))
	summary["total_page_descriptor_preencoded_hits"] = int(summary["total_page_descriptor_preencoded_hits"]) + int(stats.get("last_page_descriptor_preencoded_hits", 0))
	summary["total_gpu_page_normal_dispatches"] = int(summary["total_gpu_page_normal_dispatches"]) + int(stats.get("last_gpu_page_normal_dispatches", 0))
	summary["max_pending_levels"] = max(int(summary["max_pending_levels"]), int(stats.get("pending_rebuild_count", 0)))
	return summary


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


func _image_stats(image: Image) -> Dictionary:
	if image == null:
		return {}
	var min_luma := INF
	var max_luma := -INF
	var total_luma := 0.0
	var samples := 0
	var colors: Dictionary = {}
	var bright_count := 0
	var dark_count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.get_luminance()
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			total_luma += luma
			samples += 1
			if luma > 0.82:
				bright_count += 1
			if luma < 0.12:
				dark_count += 1
			colors["%d,%d,%d" % [int(color.r8), int(color.g8), int(color.b8)]] = true
	return {
		"luma_range": max_luma - min_luma,
		"mean_luma": total_luma / float(max(1, samples)),
		"bright_pixel_fraction": float(bright_count) / float(max(1, samples)),
		"dark_pixel_fraction": float(dark_count) / float(max(1, samples)),
		"unique_colors": colors.size(),
	}


func _check_image_stats(stats: Dictionary, errors: Array[String]) -> void:
	if stats.is_empty():
		errors.append("image_stats_empty")
		return
	if float(stats["luma_range"]) < 0.05:
		errors.append("low_luma_range:%.3f" % float(stats["luma_range"]))
	if int(stats["unique_colors"]) < 8:
		errors.append("low_color_variety:%d" % int(stats["unique_colors"]))
	if float(stats["dark_pixel_fraction"]) > 0.65:
		errors.append("too_much_background:%.3f" % float(stats["dark_pixel_fraction"]))


func _gpu_stats(scene: Node3D) -> Dictionary:
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null or not far_clipmap.has_method("stats"):
		return {}
	var stats: Dictionary = far_clipmap.call("stats") as Dictionary
	return stats.get("gpu_page_residency", {}) as Dictionary


func _check_gpu_stats(stats: Dictionary, scene: Node3D, errors: Array[String]) -> void:
	if stats.is_empty():
		errors.append("gpu_stats_empty")
		return
	var expected_levels: int = int(scene.get("far_clipmap_level_count"))
	if int(stats.get("rd_uploads", 0)) < expected_levels:
		errors.append("rd_uploads:%s" % str(stats))
	if int(stats.get("rd_compute_normal_uploads", 0)) < expected_levels:
		errors.append("rd_compute_normal_uploads:%s" % str(stats))
	if int(stats.get("rd_compute_normal_failures", 0)) != 0:
		errors.append("rd_compute_normal_failures:%s" % str(stats))
	if int(stats.get("image_uploads", 0)) != 0:
		errors.append("image_uploads:%s" % str(stats))


func _descriptor_summary(scene: Node3D) -> Dictionary:
	var summary := {
		"count": 0,
		"pass_count": 0,
		"height_image_data_count": 0,
		"normal_image_data_count": 0,
		"height_image_only_count": 0,
		"height_image_wrapper_count": 0,
		"normal_image_wrapper_count": 0,
		"payload_modes": [],
	}
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null:
		return summary
	var descriptors: Array = far_clipmap.get("level_material_descriptors") as Array
	var modes: Dictionary = {}
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		if descriptor.is_empty():
			continue
		summary["count"] = int(summary["count"]) + 1
		if descriptor.get("status", "fail") == "pass":
			summary["pass_count"] = int(summary["pass_count"]) + 1
		if (descriptor.get("height_image_data", PackedByteArray()) as PackedByteArray).size() > 0:
			summary["height_image_data_count"] = int(summary["height_image_data_count"]) + 1
		if (descriptor.get("normal_image_data", PackedByteArray()) as PackedByteArray).size() > 0:
			summary["normal_image_data_count"] = int(summary["normal_image_data_count"]) + 1
		if bool(descriptor.get("height_image_only", false)):
			summary["height_image_only_count"] = int(summary["height_image_only_count"]) + 1
		if descriptor.has("height_image"):
			summary["height_image_wrapper_count"] = int(summary["height_image_wrapper_count"]) + 1
		if descriptor.has("normal_image"):
			summary["normal_image_wrapper_count"] = int(summary["normal_image_wrapper_count"]) + 1
		var mode: String = str(descriptor.get("texture_payload_mode", ""))
		if not mode.is_empty():
			modes[mode] = true
	summary["payload_modes"] = _sorted_keys(modes)
	return summary


func _check_descriptor_summary(summary: Dictionary, scene: Node3D, errors: Array[String]) -> void:
	var expected_levels: int = int(scene.get("far_clipmap_level_count"))
	if int(summary.get("count", 0)) < expected_levels:
		errors.append("descriptor_count:%s" % str(summary))
	if int(summary.get("pass_count", 0)) < expected_levels:
		errors.append("descriptor_pass_count:%s" % str(summary))
	if int(summary.get("height_image_data_count", 0)) < expected_levels:
		errors.append("descriptor_height_data:%s" % str(summary))
	if int(summary.get("height_image_only_count", 0)) < expected_levels:
		errors.append("descriptor_height_only:%s" % str(summary))
	if int(summary.get("height_image_wrapper_count", 0)) != 0 or int(summary.get("normal_image_wrapper_count", 0)) != 0:
		errors.append("descriptor_image_wrappers:%s" % str(summary))


func _check_drain_summary(summary: Dictionary, errors: Array[String]) -> void:
	if int(summary.get("total_page_descriptor_image_builds", 0)) != 0:
		errors.append("page_descriptor_image_builds:%s" % str(summary))


func _write_manifest(
	out_dir: String,
	image_stats: Dictionary,
	gpu_stats: Dictionary,
	drain_summary: Dictionary,
	descriptor_summary: Dictionary,
	errors: Array[String]
) -> void:
	var manifest := {
		"version": 1,
		"schema": "worldgen9.gpu_page_review_manifest.v1",
		"scene": SCENE_PATH,
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"capture": "gpu_page_review.png",
		"image_stats": image_stats,
		"gpu_page_residency": gpu_stats,
		"far_page_drain": drain_summary,
		"far_page_descriptors": descriptor_summary,
		"errors": errors.duplicate(),
		"status": "pass" if errors.is_empty() else "fail",
	}
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%d" % int(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _read_manifest_stats(out_dir: String) -> Dictionary:
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.READ)
	if file == null:
		return {}
	var manifest: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	return manifest.get("image_stats", {}) as Dictionary


func _read_manifest_gpu(out_dir: String) -> Dictionary:
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.READ)
	if file == null:
		return {}
	var manifest: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	return manifest.get("gpu_page_residency", {}) as Dictionary


func _sorted_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key_value in dict.keys():
		out.append(str(key_value))
	out.sort()
	return out


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-gpu-page-review-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
