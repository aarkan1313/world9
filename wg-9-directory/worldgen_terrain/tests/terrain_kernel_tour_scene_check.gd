extends SceneTree

const TerrainKernelTourSceneScript := preload("res://worldgen_terrain/runtime/terrain_kernel_tour_scene.gd")


func _init() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainKernelTourSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.auto_tour_enabled = false
	scene.seconds_per_site = 2.0
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var summaries: Array[Dictionary] = scene.review_site_summaries()
	if summaries.size() < 12:
		errors.append("site_count:%d" % summaries.size())
	var kernels: Dictionary = {}
	var families: Dictionary = {}
	for summary_value in summaries:
		var summary: Dictionary = summary_value as Dictionary
		var kernel_a: String = str(summary.get("kernel_a", ""))
		var kernel_b: String = str(summary.get("kernel_b", ""))
		if not kernel_a.is_empty():
			kernels[kernel_a] = true
		if not kernel_b.is_empty():
			kernels[kernel_b] = true
		families[str(summary.get("primary_family", ""))] = true
		families[str(summary.get("secondary_family", ""))] = true
	if kernels.size() < 12:
		errors.append("kernel_diversity:%d" % kernels.size())
	if families.size() < 8:
		errors.append("family_diversity:%d" % families.size())
	var before_index: int = scene.review_site_index
	var before_position: Vector2 = scene.viewer_position_xz
	scene.jump_review_site(1)
	if scene.review_site_index == before_index:
		errors.append("site_index_not_advanced")
	if scene.viewer_position_xz.distance_to(before_position) < scene.chunk_size_m:
		errors.append("viewer_position_not_changed")
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-kernel-tour-scene] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-kernel-tour-scene] status=pass sites=%d kernels=%d families=%d" % [
		summaries.size(),
		kernels.size(),
		families.size(),
	])
	quit(0)
