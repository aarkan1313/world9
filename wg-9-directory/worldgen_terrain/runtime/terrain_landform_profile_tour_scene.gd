class_name TerrainLandformProfileTourScene
extends "res://worldgen_terrain/runtime/terrain_kernel_tour_scene.gd"

@export var auto_profile_cycle_enabled: bool = true
@export_range(2.0, 20.0, 0.5) var seconds_per_profile: float = 5.0
@export var advance_site_after_profile_cycle: bool = true

var landform_profile_index: int = 0
var _profile_elapsed_s: float = 0.0


func _init() -> void:
	super._init()
	auto_tour_enabled = false
	auto_profile_cycle_enabled = true
	seconds_per_profile = 5.0
	landform_profile_id = TerrainLandformProfileScript.BALANCED_CURRENT
	review_site_target_count = 9
	review_site_scan_radius_regions = 12
	fly_start_height_m = 980.0
	fly_min_ground_clearance_m = 100.0
	look_pitch_deg = -36.0


func setup() -> bool:
	landform_profile_index = max(0, TerrainLandformProfileScript.profile_ids().find(landform_profile_id))
	var ok: bool = super.setup()
	if ok:
		_apply_landform_profile_index(0, false)
	return ok


func _process(delta: float) -> void:
	super._process(delta)
	if not auto_profile_cycle_enabled:
		return
	if _has_pending_visual_work():
		return
	_profile_elapsed_s += delta
	if _profile_elapsed_s >= seconds_per_profile:
		_profile_elapsed_s = 0.0
		cycle_landform_profile(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			auto_profile_cycle_enabled = false
			cycle_landform_profile(1)
			return
		if event.keycode == KEY_P:
			auto_profile_cycle_enabled = not auto_profile_cycle_enabled
			return
	super._unhandled_input(event)


func cycle_landform_profile(direction: int) -> void:
	var previous_index: int = landform_profile_index
	_apply_landform_profile_index(direction, true)
	if advance_site_after_profile_cycle and direction > 0 and landform_profile_index == 0 and previous_index != 0:
		jump_review_site(1)


func profile_tour_report() -> Dictionary:
	var profile_report: Dictionary = landform_profile_report()
	return {
		"schema": "worldgen9.landform_profile_tour.v1",
		"profile_ids": TerrainLandformProfileScript.profile_ids(),
		"active_profile": str(profile_report.get("id", landform_profile_id)),
		"active_profile_index": landform_profile_index,
		"auto_profile_cycle_enabled": auto_profile_cycle_enabled,
		"seconds_per_profile": seconds_per_profile,
		"review_site_count": review_regions.size(),
		"review_site_index": review_site_index,
		"landform_profile": profile_report,
		"sites": review_site_summaries(),
	}


func diagnostics_text() -> String:
	var profile_id: String = str(landform_profile_report().get("id", landform_profile_id))
	return "profile %s %d/%d | %s" % [
		profile_id,
		landform_profile_index + 1,
		TerrainLandformProfileScript.profile_ids().size(),
		super.diagnostics_text(),
	]


func _apply_landform_profile_index(direction: int, rebuild_existing: bool) -> void:
	var profile_ids: Array[String] = TerrainLandformProfileScript.profile_ids()
	if profile_ids.is_empty():
		return
	landform_profile_index = posmod(landform_profile_index + direction, profile_ids.size())
	var profile_id: String = profile_ids[landform_profile_index]
	if not apply_landform_profile(profile_id, rebuild_existing):
		errors.append("landform_profile_apply_failed:%s" % profile_id)
