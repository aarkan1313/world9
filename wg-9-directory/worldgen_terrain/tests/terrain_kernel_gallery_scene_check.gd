extends SceneTree

const TerrainKernelGallerySceneScript := preload("res://worldgen_terrain/runtime/terrain_kernel_gallery_scene.gd")


func _init() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainKernelGallerySceneScript.new()
	scene.auto_setup_on_ready = false
	scene.target_tile_count = 36
	scene.scan_radius_regions = 18
	scene.vertices_per_tile_side = 65
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = scene.gallery_report()
	if report.get("status", "fail") != "pass":
		errors.append("report_status:%s errors:%s" % [str(report.get("status", "")), str(report.get("errors", []))])
	if int(report.get("tile_count", 0)) < 24:
		errors.append("tile_count:%d" % int(report.get("tile_count", 0)))
	if int(report.get("unique_kernel_count", 0)) != int(report.get("tile_count", 0)):
		errors.append("unique_kernel_count:%d tile_count:%d" % [
			int(report.get("unique_kernel_count", 0)),
			int(report.get("tile_count", 0)),
		])
	if int(report.get("unique_family_count", 0)) < 6:
		errors.append("unique_family_count:%d" % int(report.get("unique_family_count", 0)))
	if int(report.get("unique_palette_count", 0)) < 5:
		errors.append("unique_palette_count:%d" % int(report.get("unique_palette_count", 0)))
	if scene.get_child_count() < int(report.get("tile_count", 0)):
		errors.append("child_count:%d" % scene.get_child_count())
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-kernel-gallery-scene] status=fail errors=%d report=%s" % [errors.size(), str(report)])
		quit(1)
		return
	print("[wg9-kernel-gallery-scene] status=pass tiles=%d kernels=%d families=%d palettes=%d missing=%d" % [
		int(report.get("tile_count", 0)),
		int(report.get("unique_kernel_count", 0)),
		int(report.get("unique_family_count", 0)),
		int(report.get("unique_palette_count", 0)),
		int(report.get("missing_kernel_count", 0)),
	])
	quit(0)
