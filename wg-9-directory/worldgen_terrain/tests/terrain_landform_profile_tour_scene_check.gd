extends SceneTree

const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")
const TerrainLandformProfileTourSceneScript := preload("res://worldgen_terrain/runtime/terrain_landform_profile_tour_scene.gd")


func _init() -> void:
	var errors: Array[String] = []
	var packed: PackedScene = load("res://worldgen_terrain/scenes/terrain_landform_profile_tour.tscn") as PackedScene
	if packed == null:
		errors.append("packed_scene_load_failed")
	else:
		var packed_instance: Node = packed.instantiate()
		if packed_instance == null:
			errors.append("packed_scene_instantiate_failed")
		else:
			if bool(packed_instance.get("auto_profile_cycle_enabled")):
				errors.append("packed_auto_profile_cycle_enabled")
			if bool(packed_instance.get("use_far_clipmap")):
				errors.append("packed_far_clipmap_enabled")
			packed_instance.queue_free()
	var scene: Node3D = TerrainLandformProfileTourSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.auto_profile_cycle_enabled = false
	scene.advance_site_after_profile_cycle = false
	scene.seconds_per_profile = 2.0
	scene.vertices_per_side = 33
	scene.visible_radius_chunks = 1
	scene.build_budget_per_frame = 9
	scene.preload_active_chunks_before_start = true
	scene.use_far_clipmap = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = scene.profile_tour_report()
	if report.get("schema", "") != "worldgen9.landform_profile_tour.v1":
		errors.append("schema:%s" % str(report.get("schema", "")))
	if report.get("profile_ids", []) != TerrainLandformProfileScript.profile_ids():
		errors.append("profile_ids:%s" % str(report.get("profile_ids", [])))
	if int(report.get("review_site_count", 0)) < 6:
		errors.append("site_count:%d" % int(report.get("review_site_count", 0)))
	if str(report.get("active_profile", "")) != TerrainLandformProfileScript.BALANCED_CURRENT:
		errors.append("initial_profile:%s" % str(report.get("active_profile", "")))
	scene.cycle_landform_profile(1)
	var strong_report: Dictionary = scene.profile_tour_report()
	if str(strong_report.get("active_profile", "")) != TerrainLandformProfileScript.STRONG_MOUNTAINS:
		errors.append("strong_profile:%s" % str(strong_report.get("active_profile", "")))
	var strong_provider: Dictionary = strong_report.get("landform_profile", {}) as Dictionary
	if bool(strong_provider.get("native_prepared_grid_enabled", true)):
		errors.append("strong_native_should_be_disabled")
	scene.cycle_landform_profile(1)
	var compressed_report: Dictionary = scene.profile_tour_report()
	if str(compressed_report.get("active_profile", "")) != TerrainLandformProfileScript.COMPRESSED_SCALE:
		errors.append("compressed_profile:%s" % str(compressed_report.get("active_profile", "")))
	scene.cycle_landform_profile(1)
	var balanced_report: Dictionary = scene.profile_tour_report()
	if str(balanced_report.get("active_profile", "")) != TerrainLandformProfileScript.BALANCED_CURRENT:
		errors.append("balanced_profile:%s" % str(balanced_report.get("active_profile", "")))
	var balanced_provider: Dictionary = balanced_report.get("landform_profile", {}) as Dictionary
	if not bool(balanced_provider.get("native_prepared_grid_enabled", false)):
		errors.append("balanced_native_should_be_enabled")
	if scene.built_chunk_count() <= 0:
		errors.append("no_built_chunks")
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-landform-profile-tour] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-landform-profile-tour] status=pass sites=%d profiles=%d" % [
		int(report.get("review_site_count", 0)),
		TerrainLandformProfileScript.profile_ids().size(),
	])
	quit(0)
