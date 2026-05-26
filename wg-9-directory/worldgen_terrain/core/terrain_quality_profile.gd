class_name TerrainQualityProfile
extends RefCounted

const WALK_REVIEW := "walk_review"


static func profile(profile_id: String) -> Dictionary:
	match profile_id:
		WALK_REVIEW:
			return _walk_review_profile()
		_:
			return {}


static func profile_ids() -> Array[String]:
	return [WALK_REVIEW]


static func apply_to_node(node: Object, profile_data: Dictionary) -> void:
	for key in (profile_data.get("settings", {}) as Dictionary).keys():
		node.set(str(key), profile_data["settings"][key])


static func setting(profile_data: Dictionary, key: String, fallback: Variant = null) -> Variant:
	return (profile_data.get("settings", {}) as Dictionary).get(key, fallback)


static func validation_errors(node: Object, profile_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var settings: Dictionary = profile_data.get("settings", {}) as Dictionary
	for key_value in settings.keys():
		var key: String = str(key_value)
		var expected: Variant = settings[key]
		var actual: Variant = node.get(key)
		if not _values_match(actual, expected):
			errors.append("%s:%s expected:%s" % [key, str(actual), str(expected)])
	var visibility: Dictionary = visibility_contract(profile_data)
	var loaded_radius: float = float(visibility.get("loaded_radius_m", 0.0))
	var camera_far: float = float(visibility.get("camera_far_m", 0.0))
	var fog_begin: float = float(visibility.get("fog_begin_m", 0.0))
	var fog_end: float = float(visibility.get("fog_end_m", 0.0))
	if not (fog_begin > loaded_radius * 0.75):
		errors.append("fog_begin_too_near:%.3f loaded_radius:%.3f" % [fog_begin, loaded_radius])
	if not (fog_end > fog_begin):
		errors.append("fog_end_not_after_begin:%.3f %.3f" % [fog_begin, fog_end])
	if not (camera_far > fog_end):
		errors.append("camera_far_not_past_fog:%.3f fog_end:%.3f" % [camera_far, fog_end])
	return errors


static func visibility_contract(profile_data: Dictionary) -> Dictionary:
	var settings: Dictionary = profile_data.get("settings", {}) as Dictionary
	var far_levels: int = int(settings.get("far_clipmap_level_count", 0))
	var base_outer_extent_m: float = float(settings.get("far_clipmap_base_outer_extent_m", 0.0))
	var loaded_radius_m: float = base_outer_extent_m * pow(2.0, max(0, far_levels - 1))
	var fog_begin_m: float = float(settings.get("distance_fog_depth_begin_m", 0.0))
	var fog_end_m: float = float(settings.get("distance_fog_depth_end_m", 0.0))
	var camera_far_m: float = float(settings.get("camera_far_m", 0.0))
	return {
		"profile_id": str(profile_data.get("id", "")),
		"loaded_radius_m": loaded_radius_m,
		"camera_far_m": camera_far_m,
		"hidden_buffer_m": max(0.0, camera_far_m - loaded_radius_m),
		"fog_begin_m": fog_begin_m,
		"fog_end_m": fog_end_m,
		"fog_transition_m": max(0.0, fog_end_m - fog_begin_m),
		"fog_begin_loaded_fraction": fog_begin_m / loaded_radius_m if loaded_radius_m > 0.0 else 0.0,
	}


static func _walk_review_profile() -> Dictionary:
	return {
		"id": WALK_REVIEW,
		"schema": "worldgen9.terrain_quality_profile.v1",
		"description": "Default live walk/fly review profile for 129v near chunks plus 4-level page-backed far clipmap.",
		"settings": {
			"chunk_size_m": 512.0,
			"debug_mode": "elevation_color",
			"vertices_per_side": 129,
			"visible_radius_chunks": 3,
			"max_lod": 2,
			"build_budget_per_frame": 8,
			"prefetch_forward_chunks": 1,
			"warmup_build_steps": 4,
			"preload_active_chunks_before_start": true,
			"preload_active_chunk_limit": 0,
			"move_speed_mps": 18.0,
			"fast_multiplier": 60.0,
			"slow_multiplier": 0.25,
			"max_native_chunk_workers": 6,
			"review_sync_hole_fill_radius_chunks": 0,
			"review_sync_hole_fill_max_chunks_per_frame": 0,
			"use_lod_mesh_density": false,
			"use_mesh_skirts": false,
			"mesh_skirt_depth_m": 48.0,
			"use_far_clipmap": true,
			"far_clipmap_level_count": 4,
			"far_clipmap_base_spacing_m": 64.0,
			"far_clipmap_base_outer_extent_m": 4096.0,
			"far_clipmap_handoff_overlap_m": 64.0,
			"far_clipmap_recenter_distance_m": 768.0,
			"far_clipmap_rebuild_levels_per_update": 4,
			"far_clipmap_transition_fade_seconds": 0.35,
			"use_far_clipmap_native_workers": true,
			"use_persistent_page_clipmap": true,
			"far_clipmap_page_cache_max_pages": 64,
			"distance_fog_depth_begin_m": 30000.0,
			"distance_fog_depth_end_m": 33000.0,
			"camera_far_m": 120000.0,
			"use_fast_gray_material": true,
			"use_native_chunk_payloads": true,
			"use_native_chunk_workers": true,
			"fast_gray_exposure": 0.42,
			"fast_gray_contrast": 1.42,
		},
	}


static func _values_match(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		return absf(float(actual) - float(expected)) <= 0.0001
	if typeof(actual) == TYPE_BOOL or typeof(expected) == TYPE_BOOL:
		return bool(actual) == bool(expected)
	return actual == expected
