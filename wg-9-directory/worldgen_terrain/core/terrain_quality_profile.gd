class_name TerrainQualityProfile
extends RefCounted

const WALK_REVIEW := "walk_review"
const LOCAL_DETAIL_REVIEW := "local_detail_review"
const HIGH_DENSITY_257_REVIEW := "high_density_257_review"
const GPU_PAGE_REVIEW := "gpu_page_review"


static func profile(profile_id: String) -> Dictionary:
	match profile_id:
		WALK_REVIEW:
			return _walk_review_profile()
		LOCAL_DETAIL_REVIEW:
			return _local_detail_review_profile()
		HIGH_DENSITY_257_REVIEW:
			return _high_density_257_review_profile()
		GPU_PAGE_REVIEW:
			return _gpu_page_review_profile()
		_:
			return {}


static func profile_ids() -> Array[String]:
	return [WALK_REVIEW, LOCAL_DETAIL_REVIEW, HIGH_DENSITY_257_REVIEW, GPU_PAGE_REVIEW]


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
		"description": "Default live walk/fly review profile for 129v near chunks plus 4-level direct-RD page-backed far clipmap when the renderer device is available.",
		"settings": {
			"chunk_size_m": 512.0,
			"debug_mode": "elevation_color",
			"vertices_per_side": 129,
			"visible_radius_chunks": 3,
			"max_lod": 2,
			"build_budget_per_frame": 8,
			"prefetch_forward_chunks": 1,
			"residency_halo_chunks": 1,
			"warmup_build_steps": 4,
			"preload_active_chunks_before_start": true,
			"preload_active_chunk_limit": 0,
			"move_speed_mps": 18.0,
			"fast_multiplier": 60.0,
			"slow_multiplier": 0.25,
			"max_native_chunk_workers": 8,
			"max_native_chunk_worker_results_per_update": 4,
			"review_sync_hole_fill_radius_chunks": 3,
			"review_sync_hole_fill_max_chunks_per_frame": 2,
			"defer_inactive_chunk_retire_until_active_ready": false,
			"max_retained_inactive_chunk_nodes": 0,
			"use_lod_mesh_density": false,
			"use_mesh_skirts": false,
			"mesh_skirt_depth_m": 48.0,
			"use_far_clipmap": true,
			"far_clipmap_level_count": 4,
			"far_clipmap_base_spacing_m": 64.0,
			"far_clipmap_base_outer_extent_m": 4096.0,
			"far_clipmap_handoff_overlap_m": 64.0,
			"far_clipmap_visual_y_bias_per_level_m": -0.08,
			"far_clipmap_full_underlay_level0": true,
			"far_clipmap_recenter_distance_m": 768.0,
			"far_clipmap_rebuild_levels_per_update": 4,
			"far_clipmap_transition_fade_seconds": 0.35,
			"use_far_clipmap_native_workers": true,
			"use_persistent_page_clipmap": true,
			"far_clipmap_page_cache_max_pages": 64,
			"far_clipmap_gpu_page_residency_max_pages": 64,
			"use_far_clipmap_gpu_page_normal_backend": true,
			"use_far_clipmap_gpu_rd_page_textures": true,
			"use_far_clipmap_gpu_rd_compute_normals": true,
			"use_far_clipmap_gpu_provider_page_textures": true,
			"far_clipmap_gpu_provider_max_sync_blocks": 1,
			"distance_fog_depth_begin_m": 30000.0,
			"distance_fog_depth_end_m": 33000.0,
			"camera_far_m": 120000.0,
			"use_fast_gray_material": true,
			"use_native_chunk_payloads": true,
			"use_native_chunk_workers": true,
			"use_gpu_page_chunks": true,
			"use_gpu_provider_page_chunk_textures": true,
			"use_gpu_provider_page_chunk_descriptor_staging": true,
			"use_gpu_rd_chunk_page_textures": true,
			"use_gpu_rd_chunk_compute_normals": true,
			"max_gpu_page_chunk_builds_per_update": 8,
			"max_gpu_page_prefetch_chunk_builds_per_update": 1,
			"max_gpu_page_chunk_build_ms_per_update": 45,
			"max_gpu_provider_chunk_descriptor_stages_per_update": 8,
			"max_gpu_provider_chunk_descriptor_workers": 8,
			"chunk_page_cache_max_pages": 384,
			"chunk_gpu_page_residency_max_pages": 384,
			"gpu_provider_chunk_descriptor_cache_max_entries": 384,
			"fast_gray_exposure": 0.42,
			"fast_gray_contrast": 1.42,
		},
	}


static func _local_detail_review_profile() -> Dictionary:
	var profile_data: Dictionary = _walk_review_profile()
	profile_data["id"] = LOCAL_DETAIL_REVIEW
	profile_data["description"] = "Opt-in live walk review profile for one active 1m local-detail patch with texture material and bounded visual displacement."
	var settings: Dictionary = (profile_data["settings"] as Dictionary).duplicate(true)
	settings.merge({
		"use_local_detail": true,
		"local_detail_radius_patches": 0,
		"local_detail_max_active_patches": 1,
		"use_local_detail_workers": true,
		"use_local_detail_surface_material": true,
		"local_detail_surface_normal_strength": 0.85,
		"use_local_detail_visual_displacement": true,
		"local_detail_visual_displacement_strength": 0.45,
		"local_detail_visual_displacement_limit_m": 2.5,
		"enable_local_collision_bodies": false,
	}, true)
	profile_data["settings"] = settings
	profile_data["budgets"] = {
		"local_detail_max_drain_frames": 140,
		"local_detail_max_patch_assign_ms": 120,
		"local_detail_max_surface_texture_ms": 90,
		"local_detail_max_param_refresh_ms": 20,
		"local_detail_max_toggle_displacement_texture_ms": 45,
		"local_detail_max_patch_move_update_ms": 35,
	}
	profile_data["review_only"] = true
	return profile_data


static func _gpu_page_review_profile() -> Dictionary:
	var profile_data: Dictionary = _walk_review_profile()
	profile_data["id"] = GPU_PAGE_REVIEW
	profile_data["description"] = "Explicit GPU page review profile using direct Texture2DRD page residency for far clipmap pages and near chunk page-displacement."
	var settings: Dictionary = (profile_data["settings"] as Dictionary).duplicate(true)
	settings.merge({
		"far_clipmap_rebuild_levels_per_update": 4,
		"visible_radius_chunks": 2,
		"prefetch_forward_chunks": 3,
		"residency_halo_chunks": 1,
		"max_native_chunk_workers": 8,
		"max_native_chunk_worker_results_per_update": 4,
		"use_far_clipmap_gpu_page_normal_backend": true,
		"use_far_clipmap_gpu_rd_page_textures": true,
		"use_far_clipmap_gpu_rd_compute_normals": true,
		"use_far_clipmap_gpu_provider_page_textures": true,
		# Near GPU page chunks stay OFF in the accepted saved review profile per
		# roadmap 61zg / the renderer-correctness hard stop: saved review proves
		# the direct-RD far-page path over native-worker near chunks. The near
		# page-displacement path is still exercised by the hitch-profile scene.
		# The near-page settings below remain as ready configuration but are
		# inert while this master switch is false.
		"use_gpu_page_chunks": false,
		"use_gpu_provider_page_chunk_textures": true,
		"use_gpu_provider_page_chunk_descriptor_staging": true,
		"use_gpu_rd_chunk_page_textures": true,
		"use_gpu_rd_chunk_compute_normals": true,
		"max_gpu_page_chunk_builds_per_update": 8,
		"max_gpu_page_prefetch_chunk_builds_per_update": 1,
		"max_gpu_page_chunk_build_ms_per_update": 45,
		"max_gpu_provider_chunk_descriptor_stages_per_update": 8,
		"max_gpu_provider_chunk_descriptor_workers": 8,
		"chunk_page_cache_max_pages": 384,
		"chunk_gpu_page_residency_max_pages": 384,
		"gpu_provider_chunk_descriptor_cache_max_entries": 384,
	}, true)
	profile_data["settings"] = settings
	profile_data["budgets"] = {
		"gpu_page_review_max_image_uploads": 0,
		"gpu_page_review_min_rd_uploads": 4,
		"gpu_page_review_min_normal_dispatches": 0,
		"gpu_page_review_min_rd_compute_normal_uploads": 4,
		"gpu_page_review_min_provider_page_dispatches": 0,
		"gpu_page_review_expected_near_page_chunks": 0,
	}
	profile_data["review_only"] = true
	return profile_data


static func _high_density_257_review_profile() -> Dictionary:
	var profile_data: Dictionary = _walk_review_profile()
	profile_data["id"] = HIGH_DENSITY_257_REVIEW
	profile_data["description"] = "Opt-in 257v / 2m near-chunk density review profile for scale/detail checks; not a default runtime profile."
	var settings: Dictionary = (profile_data["settings"] as Dictionary).duplicate(true)
	settings.merge({
		"vertices_per_side": 257,
		"visible_radius_chunks": 3,
		"build_budget_per_frame": 2,
		"warmup_build_steps": 1,
		"preload_active_chunks_before_start": false,
		"preload_active_chunk_limit": 0,
		"max_native_chunk_workers": 4,
		"prefetch_forward_chunks": 0,
		"review_sync_hole_fill_radius_chunks": 1,
		"review_sync_hole_fill_max_chunks_per_frame": 1,
	}, true)
	profile_data["settings"] = settings
	profile_data["budgets"] = {
		"high_density_max_drain_steps": 260,
		"high_density_max_setup_ms": 800,
		"high_density_max_avg_build_ms": 90.0,
		"high_density_max_native_payload_ms": 140.0,
		"high_density_max_move_step_ms": 20,
	}
	profile_data["review_only"] = true
	return profile_data


static func _values_match(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		return absf(float(actual) - float(expected)) <= 0.0001
	if typeof(actual) == TYPE_BOOL or typeof(expected) == TYPE_BOOL:
		return bool(actual) == bool(expected)
	return actual == expected
