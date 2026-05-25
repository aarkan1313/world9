extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")

const OUT_DIR := "factory/runtime/godot_lod_skirts"
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
		print("[wg9-terrain-lod-skirt-render] status=skip reason=headless_renderer out=%s" % out_dir)
		return 0
	var viewport := SubViewport.new()
	viewport.name = "LodSkirtCaptureViewport"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var terrain: Node3D = TerrainWorldNodeScript.new()
	terrain.auto_setup_on_ready = false
	terrain.vertices_per_side = 129
	terrain.debug_mode = TerrainWorldScript.DEBUG_GRAY
	terrain.use_fast_gray_material = true
	terrain.fast_gray_exposure = 0.88
	terrain.fast_gray_contrast = 0.90
	terrain.use_native_chunk_payloads = true
	terrain.use_lod_mesh_density = true
	terrain.use_mesh_skirts = true
	terrain.mesh_skirt_depth_m = 48.0
	root.add_child(terrain)
	if not terrain.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(terrain.errors))
		viewport.queue_free()
		_report(errors, out_dir)
		return 1
	terrain.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 2,
		"max_lod": 4,
		"build_budget_per_frame": 8,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	for _index in range(8):
		terrain.update_viewer(Vector2.ZERO)
	var active_count: int = int(terrain.built_chunk_count())
	if active_count < 25:
		errors.append("active_count:%d" % active_count)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 54.0
	camera.look_at_from_position(Vector3(256.0, 900.0, 1720.0), Vector3(256.0, 40.0, 256.0), Vector3.UP)
	root.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.4
	root.add_child(light)
	await process_frame
	await process_frame
	await process_frame
	var gray_stats: Dictionary = _capture(viewport, out_dir.path_join("lod_skirt_gray.png"), errors)
	_check_stats("gray", gray_stats, errors)
	terrain.apply_debug_mode(TerrainWorldScript.DEBUG_LOD_RING)
	await process_frame
	await process_frame
	var ring_stats: Dictionary = _capture(viewport, out_dir.path_join("lod_skirt_rings.png"), errors)
	_check_stats("rings", ring_stats, errors)
	viewport.queue_free()
	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	print("[wg9-terrain-lod-skirt-render] status=pass chunks=%d gray_range=%.3f ring_colors=%d out=%s" % [
		active_count,
		float(gray_stats["luma_range"]),
		int(ring_stats["unique_colors"]),
		out_dir,
	])
	return 0


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
	if float(stats["luma_range"]) < 0.05:
		errors.append("%s_low_luma_range:%.3f" % [label, float(stats["luma_range"])])
	var min_colors := 3 if label == "rings" else 12
	var effective_min_colors: int = 2 if label == "gray" else min_colors
	if int(stats["unique_colors"]) < effective_min_colors:
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


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-lod-skirt-render] status=fail errors=%d out=%s" % [errors.size(), out_dir])
