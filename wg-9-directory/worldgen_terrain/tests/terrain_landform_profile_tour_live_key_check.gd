extends SceneTree

const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")


func _init() -> void:
	var errors: Array[String] = []
	var packed: PackedScene = load("res://worldgen_terrain/scenes/terrain_landform_profile_tour.tscn") as PackedScene
	if packed == null:
		errors.append("packed_scene_load_failed")
		_finish(errors, {})
		return
	var scene: Node3D = packed.instantiate()
	if scene == null:
		errors.append("packed_scene_instantiate_failed")
		_finish(errors, {})
		return
	scene.auto_setup_on_ready = false
	scene.auto_profile_cycle_enabled = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var before_ms: int = Time.get_ticks_msec()
	var v_event := InputEventKey.new()
	v_event.keycode = KEY_V
	v_event.pressed = true
	scene._unhandled_input(v_event)
	var elapsed_ms: int = Time.get_ticks_msec() - before_ms
	var report: Dictionary = scene.profile_tour_report()
	if str(report.get("active_profile", "")) != TerrainLandformProfileScript.STRONG_MOUNTAINS:
		errors.append("v_profile:%s" % str(report.get("active_profile", "")))
	if elapsed_ms > 1000:
		errors.append("v_key_elapsed_ms:%d" % elapsed_ms)
	if scene.far_clipmap != null:
		var stats: Dictionary = scene.far_clipmap.stats()
		if int(stats.get("levels", 0)) != int(scene.far_clipmap_level_count):
			errors.append("far_levels_after_v:%s" % str(stats))
	scene.queue_free()
	_finish(errors, {
		"schema": "worldgen9.landform_profile_tour_live_key.v1",
		"v_key_elapsed_ms": elapsed_ms,
		"profile": str(report.get("active_profile", "")),
	})


func _finish(errors: Array[String], report: Dictionary) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-landform-profile-tour-live-key] status=fail errors=%d report=%s" % [errors.size(), str(report)])
		quit(1)
		return
	print("[wg9-landform-profile-tour-live-key] status=pass report=%s" % str(report))
	quit(0)
