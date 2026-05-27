extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn"
const OUT_DIR := "factory/runtime/godot_gpu_page_review"
const MANIFEST_NAME := "gpu_page_motion_manifest.json"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not _rendering_device_available():
		print("[wg9-gpu-page-review-motion] status=unsupported rendering_device_unavailable out=%s" % out_dir)
		return 0

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		errors.append("scene_load_failed")
		_write_manifest(out_dir, {}, [], errors)
		_report(errors, out_dir)
		return 1

	var scene: Node3D = packed.instantiate() as Node3D
	if scene == null:
		errors.append("scene_instantiate_failed")
		_write_manifest(out_dir, {}, [], errors)
		_report(errors, out_dir)
		return 1

	scene.set("auto_setup_on_ready", false)
	scene.set("capture_mouse_on_ready", false)
	scene.set("show_diagnostics_overlay", false)
	get_root().add_child(scene)

	var samples: Array[Dictionary] = []
	if not bool(scene.call("setup")):
		errors.append("setup_failed:%s" % str(scene.get("errors")))
	else:
		var initial := await _drain_after_motion(scene, "initial", Vector2.ZERO, 0.0, errors)
		samples.append(initial)
		for index in range(4):
			var direction := Vector2(0.0, 1.0)
			if index % 2 == 1:
				direction = Vector2(1.0, 0.0)
			var sample := await _drain_after_motion(scene, "move_%d" % index, direction, 80.0, errors)
			samples.append(sample)
		var final_stats: Dictionary = _far_stats(scene)
		_check_motion_samples(samples, scene, errors)
		_check_final_stats(final_stats, scene, errors)
		_write_manifest(out_dir, final_stats, samples, errors)

	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap != null and far_clipmap.has_method("clear_levels"):
		far_clipmap.call("clear_levels", true)
	if scene.has_method("clear_preview"):
		scene.call("clear_preview")
	scene.queue_free()
	await process_frame

	if not errors.is_empty():
		_report(errors, out_dir)
		return 1
	var manifest_stats: Dictionary = _read_manifest_final_stats(out_dir)
	var gpu_state: Dictionary = manifest_stats.get("gpu_page_residency", {}) as Dictionary
	print("[wg9-gpu-page-review-motion] status=pass samples=%d rd_uploads=%d image_uploads=%d out=%s" % [
		samples.size(),
		int(gpu_state.get("rd_uploads", 0)),
		int(gpu_state.get("image_uploads", 0)),
		out_dir,
	])
	return 0


func _rendering_device_available() -> bool:
	return (
		ClassDB.class_exists("Texture2DRD")
		and RenderingServer.has_method("get_rendering_device")
		and RenderingServer.call("get_rendering_device") != null
	)


func _drain_after_motion(
	scene: Node3D,
	label: String,
	direction: Vector2,
	delta: float,
	errors: Array[String]
) -> Dictionary:
	var report: Dictionary = scene.call("step_viewer", delta, direction, 0.0, 0.0) as Dictionary
	if report.get("status", "fail") != "pass":
		errors.append("step_failed:%s:%s" % [label, str(report)])
	var summary := _motion_summary(label, scene, report)
	for _index in range(90):
		var far_stats: Dictionary = _far_stats(scene)
		summary = _accumulate_motion_stats(summary, far_stats)
		if _scene_settled(scene, far_stats):
			summary["settled"] = true
			summary["final_far_stats"] = far_stats
			summary["final_descriptor_state"] = _descriptor_summary(scene)
			summary["page_key_signature"] = _page_key_signature(far_stats)
			return summary
		report = scene.call("step_viewer", 0.0, Vector2.ZERO, 0.0, 0.0) as Dictionary
		if report.get("status", "fail") != "pass":
			errors.append("drain_step_failed:%s:%s" % [label, str(report)])
			break
		await process_frame
	summary["settled"] = false
	summary["final_far_stats"] = _far_stats(scene)
	summary["final_descriptor_state"] = _descriptor_summary(scene)
	summary["page_key_signature"] = _page_key_signature(summary["final_far_stats"] as Dictionary)
	errors.append("motion_drain_timeout:%s:%s" % [label, str(scene.call("diagnostics_text"))])
	return summary


func _motion_summary(label: String, scene: Node3D, report: Dictionary) -> Dictionary:
	return {
		"label": label,
		"frames": 0,
		"settled": false,
		"viewer_position_xz": _vec2_array(scene.get("viewer_position_xz")),
		"active_chunks": int(scene.call("built_chunk_count")),
		"expected_active_chunks": int(scene.call("expected_active_count")),
		"stream_report": report,
		"total_page_descriptor_image_builds": 0,
		"total_page_descriptor_texture_hits": 0,
		"total_page_descriptor_preencoded_hits": 0,
		"total_gpu_page_normal_dispatches": 0,
		"max_pending_levels": 0,
		"max_active_page_blends": 0,
		"max_active_workers": 0,
	}


func _accumulate_motion_stats(summary: Dictionary, far_stats: Dictionary) -> Dictionary:
	summary["frames"] = int(summary["frames"]) + 1
	summary["total_page_descriptor_image_builds"] = int(summary["total_page_descriptor_image_builds"]) + int(far_stats.get("last_page_descriptor_image_builds", 0))
	summary["total_page_descriptor_texture_hits"] = int(summary["total_page_descriptor_texture_hits"]) + int(far_stats.get("last_page_descriptor_texture_hits", 0))
	summary["total_page_descriptor_preencoded_hits"] = int(summary["total_page_descriptor_preencoded_hits"]) + int(far_stats.get("last_page_descriptor_preencoded_hits", 0))
	summary["total_gpu_page_normal_dispatches"] = int(summary["total_gpu_page_normal_dispatches"]) + int(far_stats.get("last_gpu_page_normal_dispatches", 0))
	summary["max_pending_levels"] = max(int(summary["max_pending_levels"]), int(far_stats.get("pending_rebuild_count", 0)))
	summary["max_active_page_blends"] = max(int(summary["max_active_page_blends"]), int(far_stats.get("active_page_blend_count", 0)))
	summary["max_active_workers"] = max(int(summary["max_active_workers"]), int(far_stats.get("active_worker_count", 0)))
	return summary


func _scene_settled(scene: Node3D, far_stats: Dictionary) -> bool:
	var gpu_state: Dictionary = far_stats.get("gpu_page_residency", {}) as Dictionary
	return (
		int(scene.call("built_chunk_count")) >= int(scene.call("expected_active_count"))
		and int(far_stats.get("pending_rebuild_count", 0)) == 0
		and int(far_stats.get("active_worker_count", 0)) == 0
		and int(far_stats.get("staged_native_payload_count", 0)) == 0
		and int(gpu_state.get("rd_uploads", 0)) >= int(scene.get("far_clipmap_level_count"))
		and int(gpu_state.get("rd_compute_normal_uploads", 0)) >= int(scene.get("far_clipmap_level_count"))
	)


func _far_stats(scene: Node3D) -> Dictionary:
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null or not far_clipmap.has_method("stats"):
		return {}
	return far_clipmap.call("stats") as Dictionary


func _descriptor_summary(scene: Node3D) -> Dictionary:
	var summary := {
		"count": 0,
		"pass_count": 0,
		"height_image_data_count": 0,
		"height_image_only_count": 0,
		"height_image_wrapper_count": 0,
		"normal_image_wrapper_count": 0,
	}
	var far_clipmap: Node = scene.get("far_clipmap") as Node
	if far_clipmap == null:
		return summary
	var descriptors: Array = far_clipmap.get("level_material_descriptors") as Array
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value as Dictionary
		if descriptor.is_empty():
			continue
		summary["count"] = int(summary["count"]) + 1
		if descriptor.get("status", "fail") == "pass":
			summary["pass_count"] = int(summary["pass_count"]) + 1
		if (descriptor.get("height_image_data", PackedByteArray()) as PackedByteArray).size() > 0:
			summary["height_image_data_count"] = int(summary["height_image_data_count"]) + 1
		if bool(descriptor.get("height_image_only", false)):
			summary["height_image_only_count"] = int(summary["height_image_only_count"]) + 1
		if descriptor.has("height_image"):
			summary["height_image_wrapper_count"] = int(summary["height_image_wrapper_count"]) + 1
		if descriptor.has("normal_image"):
			summary["normal_image_wrapper_count"] = int(summary["normal_image_wrapper_count"]) + 1
	return summary


func _check_motion_samples(samples: Array[Dictionary], scene: Node3D, errors: Array[String]) -> void:
	var expected_levels: int = int(scene.get("far_clipmap_level_count"))
	if samples.size() < 5:
		errors.append("motion_sample_count:%d" % samples.size())
	var page_key_signatures: Dictionary = {}
	for sample in samples:
		page_key_signatures[str(sample.get("page_key_signature", ""))] = true
		if not bool(sample.get("settled", false)):
			errors.append("motion_not_settled:%s" % str(sample))
		if int(sample.get("total_page_descriptor_image_builds", 0)) != 0:
			errors.append("motion_descriptor_image_builds:%s" % str(sample))
		var descriptor_state: Dictionary = sample.get("final_descriptor_state", {}) as Dictionary
		if int(descriptor_state.get("count", 0)) < expected_levels:
			errors.append("motion_descriptor_count:%s" % str(sample))
		if int(descriptor_state.get("pass_count", 0)) < expected_levels:
			errors.append("motion_descriptor_pass:%s" % str(sample))
		if int(descriptor_state.get("height_image_data_count", 0)) < expected_levels:
			errors.append("motion_descriptor_height_data:%s" % str(sample))
		if int(descriptor_state.get("height_image_only_count", 0)) < expected_levels:
			errors.append("motion_descriptor_height_only:%s" % str(sample))
		if int(descriptor_state.get("height_image_wrapper_count", 0)) != 0 or int(descriptor_state.get("normal_image_wrapper_count", 0)) != 0:
			errors.append("motion_descriptor_wrappers:%s" % str(sample))
	if page_key_signatures.size() < 3:
		errors.append("motion_distinct_page_origins:%d:%s" % [page_key_signatures.size(), str(page_key_signatures.keys())])


func _check_final_stats(stats: Dictionary, scene: Node3D, errors: Array[String]) -> void:
	if stats.is_empty():
		errors.append("final_far_stats_empty")
		return
	var expected_levels: int = int(scene.get("far_clipmap_level_count"))
	var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
	var page_cache: Dictionary = stats.get("page_cache", {}) as Dictionary
	if int(gpu_state.get("rd_uploads", 0)) < expected_levels * 2:
		errors.append("motion_rd_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("rd_compute_normal_uploads", 0)) < expected_levels * 2:
		errors.append("motion_rd_normal_uploads:%s" % str(gpu_state))
	if int(gpu_state.get("rd_compute_normal_failures", 0)) != 0:
		errors.append("motion_rd_normal_failures:%s" % str(gpu_state))
	if int(gpu_state.get("image_uploads", 0)) != 0:
		errors.append("motion_image_uploads:%s" % str(gpu_state))
	if int(page_cache.get("protected_evictions", 0)) != 0:
		errors.append("motion_protected_page_evictions:%s" % str(page_cache))


func _write_manifest(out_dir: String, final_stats: Dictionary, samples: Array[Dictionary], errors: Array[String]) -> void:
	var manifest := {
		"version": 1,
		"schema": "worldgen9.gpu_page_motion_manifest.v1",
		"scene": SCENE_PATH,
		"sample_count": samples.size(),
		"samples": samples,
		"final_far_stats": final_stats,
		"errors": errors.duplicate(),
		"status": "pass" if errors.is_empty() else "fail",
	}
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	if file == null:
		errors.append("manifest_open_failed:%d" % int(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _read_manifest_final_stats(out_dir: String) -> Dictionary:
	var file := FileAccess.open(out_dir.path_join(MANIFEST_NAME), FileAccess.READ)
	if file == null:
		return {}
	var manifest: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	return manifest.get("final_far_stats", {}) as Dictionary


func _vec2_array(value: Variant) -> Array[float]:
	var vector := Vector2.ZERO
	if value is Vector2:
		vector = value
	return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]


func _page_key_signature(far_stats: Dictionary) -> String:
	var gpu_state: Dictionary = far_stats.get("gpu_page_residency", {}) as Dictionary
	var keys: Array = gpu_state.get("protected_keys", []) as Array
	if keys.is_empty():
		keys = gpu_state.get("keys", []) as Array
	var normalized: Array[String] = []
	for key_value in keys:
		normalized.append(str(key_value))
	normalized.sort()
	return "\n".join(normalized)


func _report(errors: Array[String], out_dir: String) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-gpu-page-review-motion] status=fail errors=%d out=%s" % [errors.size(), out_dir])
