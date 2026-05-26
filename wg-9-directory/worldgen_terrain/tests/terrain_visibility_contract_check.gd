extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")

const OUT_DIR := "factory/runtime/godot_visibility_contract"
const MIN_FOG_BEGIN_LOADED_FRACTION := 0.90
const MIN_FOG_TRANSITION_M := 512.0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	scene.show_diagnostics_overlay = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	var report: Dictionary = _build_report(scene, errors)
	_save_report(report, errors)
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-visibility-contract] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-visibility-contract] status=pass report=%s" % JSON.stringify(_summary_for_stdout(report)))
	quit(0)


func _build_report(scene: Node3D, errors: Array[String]) -> Dictionary:
	var profile_report: Dictionary = scene.quality_profile_report()
	var visibility: Dictionary = profile_report.get("visibility", {}) as Dictionary
	var far_budget: Dictionary = scene.far_clipmap.budget_report() if scene.far_clipmap != null else {}
	var actual_loaded_radius_m: float = _actual_loaded_radius_m(far_budget)
	var fog_begin_m: float = float(visibility.get("fog_begin_m", 0.0))
	var fog_end_m: float = float(visibility.get("fog_end_m", 0.0))
	var fog_transition_m: float = fog_end_m - fog_begin_m
	var hidden_buffer_m: float = float(visibility.get("hidden_buffer_m", 0.0))
	var profile_loaded_radius_m: float = float(visibility.get("loaded_radius_m", 0.0))
	var camera_far_m: float = scene.camera.far if scene.camera != null else 0.0
	var far_stats: Dictionary = scene.far_clipmap.stats() if scene.far_clipmap != null else {}
	var checks := {
		"profile_pass": profile_report.get("status", "fail") == "pass",
		"far_clipmap_present": scene.far_clipmap != null,
		"camera_present": scene.camera != null,
		"distance_fog_enabled": scene.use_distance_fog,
		"global_fog_density_zero": absf(scene.distance_fog_density) <= 0.000001,
		"edge_fog_enabled": scene.far_clipmap != null and bool(scene.far_clipmap.use_edge_fog),
		"loaded_radius_matches_budget": _approx(profile_loaded_radius_m, actual_loaded_radius_m, 0.01),
		"fog_begin_outer_edge": actual_loaded_radius_m > 0.0 and fog_begin_m >= actual_loaded_radius_m * MIN_FOG_BEGIN_LOADED_FRACTION,
		"fog_straddles_loaded_edge": fog_begin_m < actual_loaded_radius_m and fog_end_m > actual_loaded_radius_m,
		"fog_transition_smooth": fog_transition_m >= MIN_FOG_TRANSITION_M,
		"hidden_buffer_covers_fog": hidden_buffer_m >= fog_transition_m,
		"camera_far_past_fog": camera_far_m > fog_end_m,
		"edge_fog_begin_applied": scene.far_clipmap != null and _approx(float(scene.far_clipmap.edge_fog_begin_m), fog_begin_m, 0.01),
		"edge_fog_end_applied": scene.far_clipmap != null and _approx(float(scene.far_clipmap.edge_fog_end_m), fog_end_m, 0.01),
		"edge_fog_center_tracks_viewer": scene.far_clipmap != null and scene.far_clipmap.edge_fog_center_xz.distance_to(scene.viewer_position_xz) <= 0.01,
		"persistent_page_clipmap": scene.far_clipmap != null and bool(far_stats.get("use_persistent_page_mesh", false)),
	}
	for key in checks.keys():
		if not bool(checks[key]):
			errors.append("check_failed:%s" % str(key))
	return {
		"schema": "worldgen9.visibility_contract_report.v1",
		"profile": profile_report,
		"status": "pass" if errors.is_empty() else "fail",
		"errors": errors.duplicate(),
		"thresholds": {
			"min_fog_begin_loaded_fraction": MIN_FOG_BEGIN_LOADED_FRACTION,
			"min_fog_transition_m": MIN_FOG_TRANSITION_M,
		},
		"visibility": {
			"profile_loaded_radius_m": profile_loaded_radius_m,
			"actual_loaded_radius_m": actual_loaded_radius_m,
			"camera_far_m": camera_far_m,
			"hidden_buffer_m": hidden_buffer_m,
			"fog_begin_m": fog_begin_m,
			"fog_end_m": fog_end_m,
			"fog_transition_m": fog_transition_m,
			"fog_begin_loaded_fraction": fog_begin_m / actual_loaded_radius_m if actual_loaded_radius_m > 0.0 else 0.0,
			"distance_fog_density": scene.distance_fog_density,
			"use_distance_fog": scene.use_distance_fog,
		},
		"far_clipmap": {
			"stats": far_stats,
			"budget": far_budget,
			"edge_fog_begin_m": scene.far_clipmap.edge_fog_begin_m if scene.far_clipmap != null else 0.0,
			"edge_fog_end_m": scene.far_clipmap.edge_fog_end_m if scene.far_clipmap != null else 0.0,
			"edge_fog_center_xz": _vector2_to_array(scene.far_clipmap.edge_fog_center_xz) if scene.far_clipmap != null else [],
			"viewer_position_xz": _vector2_to_array(scene.viewer_position_xz),
		},
		"checks": checks,
	}


func _actual_loaded_radius_m(far_budget: Dictionary) -> float:
	var levels: Array = far_budget.get("levels", []) as Array
	if levels.is_empty():
		return 0.0
	var last_level: Dictionary = levels[levels.size() - 1] as Dictionary
	return float(last_level.get("diameter_m", 0.0)) * 0.5


func _approx(a: float, b: float, epsilon: float) -> bool:
	return absf(a - b) <= epsilon


func _vector2_to_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _summary_for_stdout(report: Dictionary) -> Dictionary:
	return {
		"status": report.get("status", "fail"),
		"visibility": report.get("visibility", {}),
		"checks": report.get("checks", {}),
	}


func _save_report(report: Dictionary, errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join("visibility_contract_report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
