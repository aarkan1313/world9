extends SceneTree

const TerrainQualityProfileScript := preload("res://worldgen_terrain/core/terrain_quality_profile.gd")
const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not _rendering_device_available():
		print("[wg9-gpu-page-review-scene] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
	else:
		_check_scene(packed, errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-review-scene] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-page-review-scene] status=pass")
	quit(0)


func _rendering_device_available() -> bool:
	return ClassDB.class_exists("Texture2DRD") and RenderingServer.has_method("get_rendering_device") and RenderingServer.call("get_rendering_device") != null


func _check_scene(packed: PackedScene, errors: Array[String]) -> void:
	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		return
	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	get_root().add_child(scene)
	var report: Dictionary = scene.call("quality_profile_report") as Dictionary
	if report.get("status", "fail") != "pass":
		errors.append("profile_report:%s" % str(report))
	if str(scene.get("quality_profile_id")) != TerrainQualityProfileScript.GPU_PAGE_REVIEW:
		errors.append("profile_id:%s" % str(scene.get("quality_profile_id")))
	if not bool(scene.get("use_far_clipmap_gpu_page_normal_backend")):
		errors.append("normal_backend_disabled")
	if not bool(scene.get("use_far_clipmap_gpu_rd_page_textures")):
		errors.append("rd_textures_disabled")
	if not bool(scene.get("use_far_clipmap_gpu_rd_compute_normals")):
		errors.append("rd_compute_normals_disabled")
	if not bool(scene.get("use_far_clipmap_gpu_provider_page_textures")):
		errors.append("gpu_provider_page_textures_disabled")
	if not bool(scene.get("use_gpu_page_chunks")):
		errors.append("near_gpu_page_chunks_disabled")
	if not bool(scene.get("use_gpu_rd_chunk_page_textures")):
		errors.append("near_gpu_page_rd_textures_disabled")
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
	else:
		var terrain: Node = scene.get("terrain") as Node
		var terrain_stats: Dictionary = terrain.call("build_stats") as Dictionary if terrain != null else {}
		if not bool(terrain_stats.get("use_gpu_page_chunks", false)):
			errors.append("near_gpu_page_chunks_inactive:%s" % str(terrain_stats))
		if int(terrain_stats.get("gpu_page_chunk_count", 0)) <= 0:
			errors.append("near_gpu_page_chunks_not_committed:%s" % str(terrain_stats))
		if not str(terrain_stats.get("last_gpu_page_chunk_error", "")).is_empty():
			errors.append("near_gpu_page_chunk_error:%s" % str(terrain_stats))
		var far_clipmap: Node = scene.get("far_clipmap") as Node
		if far_clipmap == null:
			errors.append("far_clipmap_missing")
		else:
			var stats: Dictionary = far_clipmap.call("stats") as Dictionary
			var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
			if int(gpu_state.get("rd_uploads", 0)) < int(scene.get("far_clipmap_level_count")):
				errors.append("rd_uploads:%s" % str(gpu_state))
			if int(gpu_state.get("rd_compute_normal_uploads", 0)) < int(scene.get("far_clipmap_level_count")):
				errors.append("rd_compute_normal_uploads:%s" % str(gpu_state))
			if int(gpu_state.get("rd_compute_normal_failures", 0)) != 0:
				errors.append("rd_compute_normal_failures:%s" % str(gpu_state))
			if int(gpu_state.get("image_uploads", 0)) != 0:
				errors.append("image_uploads:%s" % str(gpu_state))
			if str(stats.get("last_gpu_provider_page_error", "")) != "":
				errors.append("gpu_provider_page_error:%s" % str(stats))
			if far_clipmap.has_method("clear_levels"):
				far_clipmap.call("clear_levels", true)
	scene.call("clear_preview")
	scene.queue_free()
