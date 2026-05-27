extends SceneTree

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_pass_corridor_tour.tscn"
const TerrainPassCorridorTourSceneScript := preload("res://worldgen_terrain/runtime/terrain_pass_corridor_tour_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("packed_scene_load_failed")
	else:
		await _check_saved_scene_startup(packed, errors)
	_check_reduced_script_contract(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-pass-corridor-tour] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-pass-corridor-tour] status=pass")
	return 0


func _check_saved_scene_startup(packed: PackedScene, errors: Array[String]) -> void:
	var packed_instance: Node = packed.instantiate()
	if packed_instance == null:
		errors.append("packed_scene_instantiate_failed")
		return
	if packed_instance.get("corridor_shaping_enabled") != true:
		errors.append("packed_corridor_shaping_disabled")
	if packed_instance.get("use_far_clipmap") != true:
		errors.append("packed_far_clipmap_disabled")
	if packed_instance.get("build_when_idle") == true:
		errors.append("packed_build_when_idle_enabled")
	if int(packed_instance.get("vertices_per_side")) > 33:
		errors.append("packed_corridor_vertices_too_high:%d" % int(packed_instance.get("vertices_per_side")))
	if int(packed_instance.get("visible_radius_chunks")) < 2:
		errors.append("packed_corridor_radius_too_low:%d" % int(packed_instance.get("visible_radius_chunks")))
	if str(packed_instance.get("debug_mode")) != "height_bands":
		errors.append("packed_corridor_debug_mode:%s" % str(packed_instance.get("debug_mode")))
	get_root().add_child(packed_instance)
	await process_frame
	await process_frame
	var report: Dictionary = packed_instance.call("corridor_tour_report") as Dictionary
	if report.get("schema", "") != "worldgen9.pass_corridor_tour.v1":
		errors.append("packed_schema:%s" % str(report.get("schema", "")))
	if int(report.get("site_count", 0)) < 3:
		errors.append("packed_site_count:%d" % int(report.get("site_count", 0)))
	if int(packed_instance.call("built_chunk_count")) <= 0:
		errors.append("packed_no_built_chunks")
	var profile_report: Dictionary = report.get("landform_profile", {}) as Dictionary
	if not bool(profile_report.get("native_prepared_grid_enabled", false)):
		errors.append("packed_shaped_native_should_be_enabled:%s" % str(profile_report))
	var terrain: Node = packed_instance.get("terrain") as Node
	if terrain == null:
		errors.append("packed_missing_terrain")
	elif terrain.get("use_native_chunk_payloads") != true or terrain.get("use_native_chunk_workers") != true:
		errors.append("packed_corridor_native_path_inactive")
	packed_instance.queue_free()
	await process_frame


func _check_reduced_script_contract(errors: Array[String]) -> void:
	var scene: Node3D = TerrainPassCorridorTourSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.auto_tour_enabled = false
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 9
	scene.preload_active_chunks_before_start = true
	scene.use_far_clipmap = true
	scene.far_clipmap_level_count = 2
	scene.far_clipmap_rebuild_levels_per_update = 2
	scene.use_far_clipmap_native_workers = true
	scene.corridor_site_target_count = 4
	scene.corridor_scan_radius_regions = 8
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = scene.corridor_tour_report()
	if report.get("schema", "") != "worldgen9.pass_corridor_tour.v1":
		errors.append("schema:%s" % str(report.get("schema", "")))
	if int(report.get("site_count", 0)) < 3:
		errors.append("site_count:%d" % int(report.get("site_count", 0)))
	if not bool(report.get("corridor_shaping_enabled", false)):
		errors.append("initial_shaping_disabled")
	var profile_report: Dictionary = report.get("landform_profile", {}) as Dictionary
	if not bool(profile_report.get("native_prepared_grid_enabled", false)):
		errors.append("shaped_native_should_be_enabled:%s" % str(profile_report))
	var current_site: Dictionary = report.get("current_site", {}) as Dictionary
	if float(current_site.get("expected_cut_m", 0.0)) < 8.0:
		errors.append("expected_cut_too_low:%s" % str(current_site))
	if scene.built_chunk_count() <= 0:
		errors.append("no_built_chunks")
	var first_site: String = str(current_site.get("id", ""))
	scene.jump_review_site(1)
	var next_report: Dictionary = scene.corridor_tour_report()
	var next_site: String = str((next_report.get("current_site", {}) as Dictionary).get("id", ""))
	if next_site == first_site:
		errors.append("site_did_not_advance:%s" % first_site)
	scene.toggle_corridor_shaping()
	var neutral_report: Dictionary = scene.corridor_tour_report()
	if bool(neutral_report.get("corridor_shaping_enabled", true)):
		errors.append("toggle_did_not_disable")
	var neutral_profile: Dictionary = neutral_report.get("landform_profile", {}) as Dictionary
	if not bool(neutral_profile.get("native_prepared_grid_enabled", false)):
		errors.append("neutral_native_should_be_enabled:%s" % str(neutral_profile))
	scene.toggle_corridor_shaping()
	var shaped_again: Dictionary = scene.corridor_tour_report()
	if not bool(shaped_again.get("corridor_shaping_enabled", false)):
		errors.append("toggle_did_not_reenable")
	scene.queue_free()
