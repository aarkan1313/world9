extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_CASES := [
	{
		"name": "gpu_page_review",
		"path": "res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn",
	},
	{
		"name": "walk_preview",
		"path": "res://worldgen_terrain/scenes/terrain_walk_preview.tscn",
	},
]
const OUT_DIR := "factory/runtime/godot_gpu_page_review"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MANIFEST_NAME := "gpu_page_black_slab_manifest.json"
const BLACK_LUMA_THRESHOLD := 0.045
const BLACK_RGB_THRESHOLD := 0.08
const MAX_BLACK_COMPONENT_FRACTION := 0.035
const DARK_LUMA_THRESHOLD := 0.13
const DARK_RGB_THRESHOLD := 0.16
const MAX_DARK_COMPONENT_FRACTION := 0.08
const BACKGROUND_VOID_LUMA_MIN := 0.14
const BACKGROUND_VOID_LUMA_MAX := 0.20
const BACKGROUND_VOID_RGB_SPREAD_MAX := 0.025
const MAX_BACKGROUND_VOID_COMPONENT_FRACTION := 0.055
const BACKTRAIL_FRAME_COUNT := 240
const SAMPLE_STEP := 2


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var samples: Array[Dictionary] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if DisplayServer.get_name() == "headless":
		print("[wg9-gpu-page-black-slab] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	if not _rendering_device_available():
		print("[wg9-gpu-page-black-slab] status=unsupported rendering_device_unavailable out=%s" % out_dir)
		return 0

	var viewport := SubViewport.new()
	viewport.name = "GpuPageBlackSlabViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var final_state: Dictionary = {}
	for scene_case in SCENE_CASES:
		var case_state: Dictionary = await _run_scene_case(viewport, scene_case, out_dir, samples, errors)
		final_state[str(scene_case.get("name", ""))] = case_state
	_check_samples(samples, errors)
	_write_manifest(out_dir, samples, final_state, errors)
	viewport.queue_free()
	await process_frame
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-gpu-page-black-slab] status=pass samples=%d max_black_fraction=%.4f max_dark_fraction=%.4f out=%s" % [
		samples.size(),
		_max_component_fraction(samples, "black_component"),
		_max_component_fraction(samples, "dark_component"),
		out_dir,
	])
	return 0


func _run_scene_case(
	viewport: SubViewport,
	scene_case: Dictionary,
	out_dir: String,
	samples: Array[Dictionary],
	errors: Array[String]
) -> Dictionary:
	var case_name: String = str(scene_case.get("name", "scene"))
	var scene_path: String = str(scene_case.get("path", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		errors.append("scene_load_failed:%s" % scene_path)
		return {}

	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed:%s" % scene_path)
		return {}
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	viewport.add_child(scene)

	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s:%s" % [case_name, str(scene.get("errors"))])
	else:
		await _drain_scene(scene, errors)
		samples.append(await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "initial", errors))
		await _run_trail_sequence(viewport, scene, out_dir, case_name, scene_path, samples, errors, "backtrail", Vector2(0.0, -1.0), 0.0)
		await _run_trail_sequence(viewport, scene, out_dir, case_name, scene_path, samples, errors, "lookback_trail", Vector2(0.0, -1.0), PI)
		var directions: Array[Vector2] = [
			Vector2(0.0, 1.0),
			Vector2(1.0, 0.0),
			Vector2(0.0, 1.0),
			Vector2(-1.0, 0.0),
			Vector2(0.0, -1.0),
			Vector2(1.0, 0.0),
		]
		for index in range(directions.size()):
			var report: Dictionary = scene.call("step_viewer", 80.0, directions[index], 0.0, 0.0) as Dictionary
			if report.get("status", "fail") != "pass":
				errors.append("step_failed:%s:move_%d:%s" % [case_name, index, str(report)])
				break
			await process_frame
			samples.append(await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "move_%d_live" % index, errors))
			await _drain_scene(scene, errors)
			samples.append(await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "move_%d_settled" % index, errors))

	var case_state: Dictionary = _scene_state(scene)
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap != null and far_clipmap.has_method("clear_levels"):
		far_clipmap.call("clear_levels", true)
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	await process_frame
	return case_state


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _drain_scene(scene: Node3D, errors: Array[String]) -> void:
	for _index in range(90):
		var far_stats: Dictionary = _far_stats(scene)
		if _scene_settled(scene, far_stats):
			return
		var report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("drain_step_failed:%s" % str(report))
			return
		await process_frame
	errors.append("drain_timeout:%s" % str(scene.call("diagnostics_text")))


func _scene_settled(scene: Node3D, far_stats: Dictionary) -> bool:
	var terrain_stats: Dictionary = _terrain_stats(scene)
	return (
		int(scene.call("built_chunk_count")) >= int(scene.call("expected_active_count"))
		and int(terrain_stats.get("active_native_workers", 0)) == 0
		and int(terrain_stats.get("queued_native_worker_builds", 0)) == 0
		and int(far_stats.get("pending_rebuild_count", 0)) == 0
		and int(far_stats.get("active_worker_count", 0)) == 0
		and int(far_stats.get("staged_native_payload_count", 0)) == 0
	)


func _capture_sample(
	viewport: SubViewport,
	scene: Node3D,
	out_dir: String,
	case_name: String,
	scene_path: String,
	label: String,
	errors: Array[String]
) -> Dictionary:
	for _index in range(2):
		await process_frame
	var capture_name := "%s_%s.png" % [case_name, label]
	var image: Image = _capture_image(viewport, out_dir.path_join(capture_name), errors)
	var black_stats: Dictionary = _black_component_stats(image)
	var dark_stats: Dictionary = _dark_component_stats(image)
	var void_stats: Dictionary = _background_void_component_stats(image)
	return {
		"label": label,
		"scene_case": case_name,
		"scene_path": scene_path,
		"capture": capture_name,
		"viewer_position_xz": _vec2_array(scene.get("viewer_position_xz")),
		"diagnostics": str(scene.call("diagnostics_text")),
		"black_component": black_stats,
		"dark_component": dark_stats,
		"background_void_component": void_stats,
		"scene_state": _scene_state(scene),
		"surface_provenance": scene.call("surface_provenance") if scene.has_method("surface_provenance") else {},
	}


func _run_trail_sequence(
	viewport: SubViewport,
	scene: Node3D,
	out_dir: String,
	case_name: String,
	scene_path: String,
	samples: Array[Dictionary],
	errors: Array[String],
	label_prefix: String,
	movement: Vector2,
	setup_yaw_delta: float
) -> void:
	if absf(setup_yaw_delta) > 0.00001:
		var yaw_report: Dictionary = scene.call("step_viewer", 0.0, Vector2.ZERO, setup_yaw_delta, 0.0) as Dictionary
		if yaw_report.get("status", "fail") != "pass":
			errors.append("%s_yaw_step_failed:%s" % [label_prefix, str(yaw_report)])
			return
		await process_frame
		samples.append(await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "%s_yaw" % label_prefix, errors))
	var previous_fraction := 0.0
	for frame_index in range(BACKTRAIL_FRAME_COUNT):
		var report: Dictionary = scene.call("step_viewer", 1.4, movement, 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("%s_step_failed:%d:%s" % [label_prefix, frame_index, str(report)])
			return
		await process_frame
		if frame_index % 5 != 0:
			continue
		var sample: Dictionary = await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "%s_%03d" % [label_prefix, frame_index], errors)
		var fraction: float = maxf(
			float((sample.get("black_component", {}) as Dictionary).get("largest_component_fraction", 0.0)),
			maxf(
				float((sample.get("dark_component", {}) as Dictionary).get("largest_component_fraction", 0.0)),
				float((sample.get("background_void_component", {}) as Dictionary).get("largest_component_fraction", 0.0))
			)
		)
		sample["backtrail_frame"] = frame_index
		sample["artifact_fraction_delta"] = fraction - previous_fraction
		previous_fraction = fraction
		samples.append(sample)
		if fraction > MAX_BACKGROUND_VOID_COMPONENT_FRACTION:
			for extra in range(3):
				var extra_report: Dictionary = scene.call("step_viewer", 0.7, movement, 0.0, 0.0) as Dictionary
				if extra_report.get("status", "fail") != "pass":
					errors.append("%s_extra_step_failed:%d:%s" % [label_prefix, extra, str(extra_report)])
					return
				await process_frame
				samples.append(await _capture_sample(viewport, scene, out_dir, case_name, scene_path, "%s_fail_follow_%d" % [label_prefix, extra], errors))
			return


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


func _black_component_stats(image: Image) -> Dictionary:
	return _component_stats(image, "black", BLACK_LUMA_THRESHOLD, BLACK_RGB_THRESHOLD, 0.35, 0.96)


func _dark_component_stats(image: Image) -> Dictionary:
	return _component_stats(image, "dark", DARK_LUMA_THRESHOLD, DARK_RGB_THRESHOLD, 0.25, 0.98)


func _background_void_component_stats(image: Image) -> Dictionary:
	return _component_stats(image, "background_void", 0.0, 0.0, 0.52, 0.98)


func _component_stats(
	image: Image,
	mode: String,
	luma_threshold: float,
	rgb_threshold: float,
	roi_y_min_fraction: float,
	roi_y_max_fraction: float
) -> Dictionary:
	if image == null:
		return {}
	var width: int = image.get_width()
	var height: int = image.get_height()
	var grid_w: int = int(ceil(float(width) / float(SAMPLE_STEP)))
	var grid_h: int = int(ceil(float(height) / float(SAMPLE_STEP)))
	var min_x: int = int(floor(float(grid_w) * 0.10))
	var max_x: int = int(ceil(float(grid_w) * 0.90))
	var min_y: int = int(floor(float(grid_h) * roi_y_min_fraction))
	var max_y: int = int(ceil(float(grid_h) * roi_y_max_fraction))
	var roi_cells: int = max(1, (max_x - min_x) * (max_y - min_y))
	var visited := PackedByteArray()
	visited.resize(grid_w * grid_h)
	var largest_cells := 0
	var largest_bbox := Rect2i()
	var component_count := 0
	for gy in range(min_y, max_y):
		for gx in range(min_x, max_x):
			var index: int = gy * grid_w + gx
			if visited[index] != 0:
				continue
			visited[index] = 1
			if not _is_artifact_cell(image, gx, gy, mode, luma_threshold, rgb_threshold):
				continue
			component_count += 1
			var component: Dictionary = _flood_component(image, visited, grid_w, grid_h, min_x, max_x, min_y, max_y, gx, gy, mode, luma_threshold, rgb_threshold)
			var cells: int = int(component.get("cells", 0))
			if cells > largest_cells:
				largest_cells = cells
				largest_bbox = component.get("bbox", Rect2i()) as Rect2i
	var fraction: float = float(largest_cells) / float(roi_cells)
	return {
		"sample_step": SAMPLE_STEP,
		"mode": mode,
		"roi": [min_x * SAMPLE_STEP, min_y * SAMPLE_STEP, (max_x - min_x) * SAMPLE_STEP, (max_y - min_y) * SAMPLE_STEP],
		"component_count": component_count,
		"largest_component_cells": largest_cells,
		"largest_component_pixels_est": largest_cells * SAMPLE_STEP * SAMPLE_STEP,
		"largest_component_fraction": fraction,
		"largest_component_bbox": [largest_bbox.position.x * SAMPLE_STEP, largest_bbox.position.y * SAMPLE_STEP, largest_bbox.size.x * SAMPLE_STEP, largest_bbox.size.y * SAMPLE_STEP],
		"threshold_luma": luma_threshold,
		"threshold_rgb": rgb_threshold,
	}


func _flood_component(
	image: Image,
	visited: PackedByteArray,
	grid_w: int,
	grid_h: int,
	min_x: int,
	max_x: int,
	min_y: int,
	max_y: int,
	start_x: int,
	start_y: int,
	mode: String,
	luma_threshold: float,
	rgb_threshold: float
) -> Dictionary:
	var stack := PackedInt32Array()
	stack.append(start_y * grid_w + start_x)
	var cells := 0
	var bbox_min_x: int = start_x
	var bbox_max_x: int = start_x
	var bbox_min_y: int = start_y
	var bbox_max_y: int = start_y
	while not stack.is_empty():
		var index: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var gx: int = index % grid_w
		var gy: int = int(index / grid_w)
		cells += 1
		bbox_min_x = min(bbox_min_x, gx)
		bbox_max_x = max(bbox_max_x, gx)
		bbox_min_y = min(bbox_min_y, gy)
		bbox_max_y = max(bbox_max_y, gy)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = gx + offset.x
			var ny: int = gy + offset.y
			if nx < min_x or nx >= max_x or ny < min_y or ny >= max_y or nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
				continue
			var next_index: int = ny * grid_w + nx
			if visited[next_index] != 0:
				continue
			visited[next_index] = 1
			if _is_artifact_cell(image, nx, ny, mode, luma_threshold, rgb_threshold):
				stack.append(next_index)
	return {
		"cells": cells,
		"bbox": Rect2i(bbox_min_x, bbox_min_y, bbox_max_x - bbox_min_x + 1, bbox_max_y - bbox_min_y + 1),
	}


func _is_artifact_cell(image: Image, gx: int, gy: int, mode: String, luma_threshold: float, rgb_threshold: float) -> bool:
	var px: int = mini(image.get_width() - 1, gx * SAMPLE_STEP)
	var py: int = mini(image.get_height() - 1, gy * SAMPLE_STEP)
	var color: Color = image.get_pixel(px, py)
	if color.a <= 0.5:
		return false
	if mode == "background_void":
		var min_rgb: float = minf(color.r, minf(color.g, color.b))
		var max_rgb: float = maxf(color.r, maxf(color.g, color.b))
		var luma: float = color.get_luminance()
		return (
			luma >= BACKGROUND_VOID_LUMA_MIN
			and luma <= BACKGROUND_VOID_LUMA_MAX
			and max_rgb - min_rgb <= BACKGROUND_VOID_RGB_SPREAD_MAX
		)
	return (
		color.get_luminance() < luma_threshold
		and maxf(color.r, maxf(color.g, color.b)) < rgb_threshold
	)


func _check_samples(samples: Array[Dictionary], errors: Array[String]) -> void:
	for sample in samples:
		var black_stats: Dictionary = sample.get("black_component", {}) as Dictionary
		var black_fraction: float = float(black_stats.get("largest_component_fraction", 0.0))
		if black_fraction > MAX_BLACK_COMPONENT_FRACTION:
			errors.append("large_black_component:%s fraction=%.4f stats=%s" % [
				_sample_id(sample),
				black_fraction,
				str(black_stats),
			])
		var dark_stats: Dictionary = sample.get("dark_component", {}) as Dictionary
		var dark_fraction: float = float(dark_stats.get("largest_component_fraction", 0.0))
		if dark_fraction > MAX_DARK_COMPONENT_FRACTION:
			errors.append("large_dark_component:%s fraction=%.4f stats=%s" % [
				_sample_id(sample),
				dark_fraction,
				str(dark_stats),
			])
		var void_stats: Dictionary = sample.get("background_void_component", {}) as Dictionary
		var void_fraction: float = float(void_stats.get("largest_component_fraction", 0.0))
		if void_fraction > MAX_BACKGROUND_VOID_COMPONENT_FRACTION:
			errors.append("large_background_void_component:%s fraction=%.4f stats=%s" % [
				_sample_id(sample),
				void_fraction,
				str(void_stats),
			])


func _scene_state(scene: Node3D) -> Dictionary:
	return {
		"diagnostics": str(scene.call("diagnostics_text")) if scene.has_method("diagnostics_text") else "",
		"stream_report": scene.get("last_stream_report"),
		"terrain_stats": _terrain_stats(scene),
		"far_stats": _far_stats(scene),
	}


func _terrain_stats(scene: Node3D) -> Dictionary:
	var terrain: Node = scene.get("terrain") as Node
	if terrain == null or not terrain.has_method("build_stats"):
		return {}
	return terrain.call("build_stats") as Dictionary


func _far_stats(scene: Node3D) -> Dictionary:
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null or not far_clipmap.has_method("stats"):
		return {}
	return far_clipmap.call("stats") as Dictionary


func _max_component_fraction(samples: Array[Dictionary], key: String) -> float:
	var max_fraction := 0.0
	for sample in samples:
		var stats: Dictionary = sample.get(key, {}) as Dictionary
		max_fraction = maxf(max_fraction, float(stats.get("largest_component_fraction", 0.0)))
	return max_fraction


func _sample_id(sample: Dictionary) -> String:
	return "%s:%s" % [str(sample.get("scene_case", "")), str(sample.get("label", ""))]


func _write_manifest(out_dir: String, samples: Array[Dictionary], final_state: Dictionary, errors: Array[String]) -> void:
	var manifest := {
		"version": 1,
		"schema": "worldgen9.gpu_page_black_slab_manifest.v1",
		"scene_cases": SCENE_CASES,
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"black_component_limit_fraction": MAX_BLACK_COMPONENT_FRACTION,
		"dark_component_limit_fraction": MAX_DARK_COMPONENT_FRACTION,
		"background_void_component_limit_fraction": MAX_BACKGROUND_VOID_COMPONENT_FRACTION,
		"backtrail_frame_count": BACKTRAIL_FRAME_COUNT,
		"samples": samples,
		"final_state": final_state,
		"errors": errors.duplicate(),
		"status": "pass" if errors.is_empty() else "fail",
	}
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%d" % int(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _vec2_array(value: Variant) -> Array[float]:
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]
	return [0.0, 0.0]


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-gpu-page-black-slab] status=fail errors=%d out=%s" % [errors.size(), out_dir])
