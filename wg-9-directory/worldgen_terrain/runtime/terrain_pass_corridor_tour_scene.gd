class_name TerrainPassCorridorTourScene
extends "res://worldgen_terrain/runtime/terrain_kernel_tour_scene.gd"

@export_range(3, 18, 1) var corridor_site_target_count: int = 9
@export_range(4, 18, 1) var corridor_scan_radius_regions: int = 12
@export_range(0.0, 1.5, 0.05) var corridor_strength: float = 1.0
@export var corridor_shaping_enabled: bool = true

var corridor_sites: Array[Dictionary] = []


func _init() -> void:
	super._init()
	auto_select_diverse_review_sites = false
	restart_at_first_site_on_setup = false
	auto_tour_enabled = false
	capture_mouse_on_ready = false
	free_fly_enabled = true
	debug_mode = TerrainWorldScript.DEBUG_HEIGHT_BANDS
	fly_start_height_m = 760.0
	fly_min_ground_clearance_m = 90.0
	look_pitch_deg = -35.0
	camera_yaw_deg = 38.0
	review_site_target_count = 9
	review_site_scan_radius_regions = 12
	build_when_idle = false
	show_diagnostics_overlay = true
	far_clipmap_full_underlay_level0 = true
	far_clipmap_rebuild_levels_per_update = 1


func setup() -> bool:
	var wanted_warmup_build_steps: int = warmup_build_steps
	var wanted_preload_active_chunks: bool = preload_active_chunks_before_start
	warmup_build_steps = min(warmup_build_steps, 1)
	preload_active_chunks_before_start = false
	var ok: bool = super.setup()
	warmup_build_steps = wanted_warmup_build_steps
	preload_active_chunks_before_start = wanted_preload_active_chunks
	if not ok:
		return false
	_select_corridor_sites()
	if corridor_sites.is_empty():
		errors.append("corridor_sites_empty")
		return false
	_apply_corridor_profile(true)
	review_site_index = -1
	jump_review_site(1)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			toggle_corridor_shaping()
			return
	super._unhandled_input(event)


func jump_review_site(direction: int) -> void:
	if terrain == null or terrain.world == null:
		return
	if corridor_sites.is_empty():
		_select_corridor_sites()
	if corridor_sites.is_empty():
		return
	review_site_index = posmod(review_site_index + direction, corridor_sites.size())
	var site: Dictionary = corridor_sites[review_site_index] as Dictionary
	var focus: Vector2 = site["focus_m"] as Vector2
	viewer_position_xz = focus
	var start: Vector2 = site["start_m"] as Vector2
	var end: Vector2 = site["end_m"] as Vector2
	var direction_xz: Vector2 = (end - start).normalized()
	if direction_xz.length_squared() > 0.000001:
		camera_yaw_rad = atan2(direction_xz.x, direction_xz.y)
	_camera_height_initialized = false
	_update_streamer()
	_tour_elapsed_s = 0.0
	if stabilize_review_jumps:
		_stabilize_review_residency()
	else:
		_update_camera()
		_update_diagnostics()


func toggle_corridor_shaping() -> void:
	corridor_shaping_enabled = not corridor_shaping_enabled
	_apply_corridor_profile(true)
	if stabilize_review_jumps:
		_stabilize_review_residency()
	else:
		_update_streamer()
		_update_camera()
		_update_diagnostics()


func _stabilize_review_residency() -> void:
	if terrain == null:
		return
	if terrain.has_method("clear_native_worker_backlog_for_preview"):
		terrain.call("clear_native_worker_backlog_for_preview")
	if last_stream_report.is_empty():
		last_stream_report = terrain.update_viewer(viewer_position_xz)
	if terrain.has_method("build_missing_nearby_for_preview"):
		last_preload_chunk_count = int(terrain.call(
			"build_missing_nearby_for_preview",
			1,
			max(1, build_budget_per_frame)
		))
	if far_clipmap != null:
		far_clipmap.update_viewer(_far_clipmap_center_xz())
	_update_camera()
	_update_diagnostics()


func corridor_tour_report() -> Dictionary:
	var site: Dictionary = _current_corridor_site()
	var profile_report: Dictionary = landform_profile_report()
	return {
		"schema": "worldgen9.pass_corridor_tour.v1",
		"site_count": corridor_sites.size(),
		"site_index": review_site_index,
		"corridor_shaping_enabled": corridor_shaping_enabled,
		"corridor_strength": corridor_strength,
		"landform_profile": profile_report,
		"current_site": _site_report(site),
		"sites": _site_reports(),
	}


func diagnostics_text() -> String:
	var site: Dictionary = _current_corridor_site()
	return "corridor %s %d/%d %s cut %.0fm shape %s | %s" % [
		str(site.get("kind", "")),
		review_site_index + 1,
		corridor_sites.size(),
		str(site.get("families_label", "")),
		float(site.get("expected_cut_m", 0.0)),
		"on" if corridor_shaping_enabled else "off",
		super.diagnostics_text(),
	]


func _select_corridor_sites() -> void:
	corridor_sites.clear()
	if terrain == null or terrain.world == null:
		return
	var candidates: Array[Dictionary] = []
	for rz in range(-corridor_scan_radius_regions, corridor_scan_radius_regions + 1):
		for rx in range(-corridor_scan_radius_regions, corridor_scan_radius_regions + 1):
			var facts: Dictionary = terrain.world.pass_corridor_facts_for_region(rx, rz)
			if facts.get("status", "fail") != "pass":
				continue
			for fact_value in facts.get("facts", []) as Array:
				var candidate: Dictionary = _best_site_for_fact(fact_value as Dictionary)
				if not candidate.is_empty():
					candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) > float(b["score"])
		var ar: Vector2i = a["region"] as Vector2i
		var br: Vector2i = b["region"] as Vector2i
		if ar.y != br.y:
			return ar.y < br.y
		return ar.x < br.x
	)
	var used_regions: Dictionary = {}
	for candidate in candidates:
		if corridor_sites.size() >= corridor_site_target_count:
			break
		var region: Vector2i = candidate["region"] as Vector2i
		var key := "%d,%d" % [region.x, region.y]
		if used_regions.has(key):
			continue
		used_regions[key] = true
		corridor_sites.append(candidate)
	review_regions.clear()
	for site in corridor_sites:
		review_regions.append(site["region"] as Vector2i)


func _best_site_for_fact(fact: Dictionary) -> Dictionary:
	var start_values: Array = fact.get("start_m", []) as Array
	var end_values: Array = fact.get("end_m", []) as Array
	if start_values.size() < 2 or end_values.size() < 2:
		return {}
	var start := Vector2(float(start_values[0]), float(start_values[1]))
	var end := Vector2(float(end_values[0]), float(end_values[1]))
	var best: Dictionary = {}
	var best_score := -1.0
	var ruggedness: float = float(fact.get("ruggedness", 0.0))
	var priority: float = float(fact.get("priority", 0.0))
	for sample_index in range(1, 10):
		var t: float = float(sample_index) / 10.0
		var point: Vector2 = start.lerp(end, t)
		var hint: Dictionary = terrain.world.sample_pass_corridor_hint(point.x, point.y)
		var strength: float = float(hint.get("corridor_strength", 0.0))
		var height_m: float = terrain.world.sample_height(point.x, point.y)
		var high_factor: float = _smoothstep_unit((height_m + 90.0) / 560.0)
		var expected_cut_m: float = _expected_corridor_cut_m(strength, ruggedness, priority, high_factor)
		var score: float = expected_cut_m * 4.0 + ruggedness * 80.0 + priority * 40.0
		if score > best_score:
			best_score = score
			var region_values: Array = fact.get("region", []) as Array
			if region_values.size() < 2:
				continue
			var families: Array = fact.get("families", []) as Array
			best = {
				"id": str(fact.get("id", "")),
				"kind": str(fact.get("kind", "")),
				"region": Vector2i(int(region_values[0]), int(region_values[1])),
				"families": families.duplicate(),
				"families_label": _family_label(families),
				"start_m": start,
				"end_m": end,
				"focus_m": point,
				"width_m": float(fact.get("width_m", 0.0)),
				"priority": priority,
				"ruggedness": ruggedness,
				"corridor_strength": strength,
				"neutral_height_m": height_m,
				"expected_cut_m": expected_cut_m,
				"score": score,
			}
	return best


func _apply_corridor_profile(rebuild_existing: bool) -> void:
	if terrain == null or terrain.world == null:
		return
	var profile := {
		"id": "corridor_tour_on" if corridor_shaping_enabled else "corridor_tour_off",
		"settings": {
			"macro_relief_scale": 1.0,
			"kernel_relief_strength": 1.0,
			"mountain_boost": 1.0,
			"regional_scale_multiplier": 1.0,
			"valley_bias_strength": 1.0,
			"pass_corridor_strength": corridor_strength if corridor_shaping_enabled else 0.0,
		},
	}
	_apply_corridor_backend_policy()
	if not bool(terrain.call("apply_landform_profile", profile, false)):
		errors.append("corridor_profile_apply_failed")
		return
	if rebuild_existing:
		if terrain.has_method("clear_native_worker_backlog_for_preview"):
			terrain.call("clear_native_worker_backlog_for_preview")
		_update_streamer()
		if terrain.has_method("build_missing_nearby_for_preview"):
			last_review_sync_fill_count = int(terrain.call("build_missing_nearby_for_preview", 1, max(1, build_budget_per_frame)))
		if far_clipmap != null:
			if far_clipmap.has_method("invalidate_pages_for_profile_change"):
				far_clipmap.call("invalidate_pages_for_profile_change")
			else:
				far_clipmap.update_viewer(_far_clipmap_center_xz())
		if local_detail != null:
			local_detail.clear_patches()
		_update_camera()
		_update_diagnostics()
	else:
		if far_clipmap != null:
			if far_clipmap.has_method("invalidate_pages_for_profile_change"):
				far_clipmap.call("invalidate_pages_for_profile_change")
			elif not far_clipmap.setup(terrain.world):
				errors.append("corridor_far_clipmap_queue_failed")
				return
		if local_detail != null:
			local_detail.clear_patches(true)


func _apply_corridor_backend_policy() -> void:
	var native_allowed := true
	if terrain != null:
		terrain.use_native_chunk_payloads = use_native_chunk_payloads and native_allowed
		terrain.use_native_chunk_workers = use_native_chunk_workers and native_allowed
	if far_clipmap != null:
		far_clipmap.use_native_workers = use_far_clipmap_native_workers and native_allowed


func _current_corridor_site() -> Dictionary:
	if corridor_sites.is_empty() or review_site_index < 0 or review_site_index >= corridor_sites.size():
		return {}
	return corridor_sites[review_site_index] as Dictionary


func _site_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for site in corridor_sites:
		reports.append(_site_report(site))
	return reports


func _site_report(site: Dictionary) -> Dictionary:
	if site.is_empty():
		return {}
	var region: Vector2i = site["region"] as Vector2i
	var focus: Vector2 = site["focus_m"] as Vector2
	var start: Vector2 = site["start_m"] as Vector2
	var end: Vector2 = site["end_m"] as Vector2
	return {
		"id": str(site.get("id", "")),
		"kind": str(site.get("kind", "")),
		"region": [region.x, region.y],
		"families": (site.get("families", []) as Array).duplicate(),
		"start_m": [start.x, start.y],
		"end_m": [end.x, end.y],
		"focus_m": [focus.x, focus.y],
		"width_m": float(site.get("width_m", 0.0)),
		"priority": float(site.get("priority", 0.0)),
		"ruggedness": float(site.get("ruggedness", 0.0)),
		"corridor_strength": float(site.get("corridor_strength", 0.0)),
		"neutral_height_m": float(site.get("neutral_height_m", 0.0)),
		"expected_cut_m": float(site.get("expected_cut_m", 0.0)),
	}


func _expected_corridor_cut_m(strength: float, ruggedness: float, priority: float, high_factor: float) -> float:
	var pass_power: float = strength * strength
	var max_cut_m: float = corridor_strength * lerpf(36.0, 220.0, clampf(ruggedness, 0.0, 1.0)) * lerpf(0.55, 1.0, clampf(priority, 0.0, 1.0))
	return max_cut_m * pass_power * clampf(high_factor, 0.0, 1.0)


func _smoothstep_unit(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _family_label(families: Array) -> String:
	var labels: PackedStringArray = PackedStringArray()
	for family in families:
		labels.append(str(family))
	return "/".join(labels)
