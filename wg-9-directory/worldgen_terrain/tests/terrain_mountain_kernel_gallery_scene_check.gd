extends SceneTree

const TerrainKernelGallerySceneScript := preload("res://worldgen_terrain/runtime/terrain_kernel_gallery_scene.gd")


func _init() -> void:
	var errors: Array[String] = []
	var packed: PackedScene = load("res://worldgen_terrain/scenes/terrain_mountain_kernel_gallery.tscn") as PackedScene
	if packed == null:
		errors.append("packed_scene_load_failed")
	else:
		var packed_instance: Node = packed.instantiate()
		if packed_instance == null:
			errors.append("packed_scene_instantiate_failed")
		else:
			if str(packed_instance.get("family_filter")) != "mountain":
				errors.append("packed_family_filter:%s" % str(packed_instance.get("family_filter")))
			packed_instance.queue_free()

	var scene: Node3D = TerrainKernelGallerySceneScript.new()
	scene.auto_setup_on_ready = false
	scene.family_filter = "mountain"
	scene.variants_per_kernel = 3
	scene.target_tile_count = 12
	scene.scan_radius_regions = 24
	scene.vertices_per_tile_side = 65
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = scene.gallery_report()
	if report.get("status", "fail") != "pass":
		errors.append("report_status:%s errors:%s" % [str(report.get("status", "")), str(report.get("errors", []))])
	if str(report.get("family_filter", "")) != "mountain":
		errors.append("report_family_filter:%s" % str(report.get("family_filter", "")))
	if int(report.get("tile_count", 0)) < 8:
		errors.append("tile_count:%d" % int(report.get("tile_count", 0)))
	if int(report.get("unique_kernel_count", 0)) < 4:
		errors.append("unique_kernel_count:%d" % int(report.get("unique_kernel_count", 0)))
	if int(report.get("tile_count", 0)) <= int(report.get("unique_kernel_count", 0)):
		errors.append("missing_kernel_variants:%s" % str(report))
	for site_value in scene.selected_sites:
		var site: Dictionary = site_value as Dictionary
		var kernel_id: String = str(site.get("kernel_id", ""))
		if not kernel_id.begins_with("mountain__"):
			errors.append("non_mountain_kernel:%s" % kernel_id)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-mountain-kernel-gallery] status=fail errors=%d report=%s" % [errors.size(), str(report)])
		quit(1)
		return
	print("[wg9-mountain-kernel-gallery] status=pass tiles=%d kernels=%d" % [
		int(report.get("tile_count", 0)),
		int(report.get("unique_kernel_count", 0)),
	])
	quit(0)
