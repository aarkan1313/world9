extends SceneTree

const TerrainDetailTierPolicyScript := preload("res://worldgen_terrain/core/terrain_detail_tier_policy.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_alignment(errors)
	_check_patch_selection(errors)
	_check_negative_coordinates(errors)
	_report_and_quit(errors)


func _check_alignment(errors: Array[String]) -> void:
	var one_meter: Dictionary = TerrainDetailTierPolicyScript.validate_alignment(256.0, 257, 512.0, 129)
	if one_meter.get("status", "fail") != "pass":
		errors.append("one_meter_alignment:%s" % str(one_meter))
	if absf(float(one_meter["detail_spacing_m"]) - 1.0) > 0.000001:
		errors.append("one_meter_spacing:%.6f" % float(one_meter["detail_spacing_m"]))
	if int(one_meter["detail_samples_per_base_step"]) != 4:
		errors.append("one_meter_ratio:%d" % int(one_meter["detail_samples_per_base_step"]))

	var two_meter: Dictionary = TerrainDetailTierPolicyScript.validate_alignment(512.0, 257, 512.0, 129)
	if two_meter.get("status", "fail") != "pass":
		errors.append("two_meter_alignment:%s" % str(two_meter))
	if int(two_meter["detail_samples_per_base_step"]) != 2:
		errors.append("two_meter_ratio:%d" % int(two_meter["detail_samples_per_base_step"]))

	var bad: Dictionary = TerrainDetailTierPolicyScript.validate_alignment(256.0, 258, 512.0, 129)
	if bad.get("status", "pass") == "pass":
		errors.append("bad_alignment_passed:%s" % str(bad))


func _check_patch_selection(errors: Array[String]) -> void:
	var settings: Dictionary = TerrainDetailTierPolicyScript.make_settings(256.0, 257, 1, 9)
	var patches: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(Vector2(12.0, 80.0), settings)
	if patches.size() != 9:
		errors.append("patch_count:%d" % patches.size())
		return
	var center: Dictionary = patches[0]
	if str(center["key"]) != "0,0":
		errors.append("center_key:%s" % str(center["key"]))
	if int(center["ring"]) != 0:
		errors.append("center_ring:%d" % int(center["ring"]))
	if absf(float(center["spacing_m"]) - 1.0) > 0.000001:
		errors.append("center_spacing:%.6f" % float(center["spacing_m"]))

	var stable: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(Vector2(255.9, 255.9), settings)
	if str(stable[0]["key"]) != "0,0":
		errors.append("stable_before_boundary:%s" % str(stable[0]["key"]))
	var crossed: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(Vector2(256.0, 256.0), settings)
	if str(crossed[0]["key"]) != "1,1":
		errors.append("crossed_boundary:%s" % str(crossed[0]["key"]))
	var far_settings: Dictionary = TerrainDetailTierPolicyScript.make_settings(256.0, 257, 1, 1)
	var far_patches: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(Vector2(-51200.0, -51200.0), far_settings)
	if far_patches.size() != 1 or str(far_patches[0]["key"]) != "-200,-200":
		errors.append("far_center_priority:%s" % str(far_patches))


func _check_negative_coordinates(errors: Array[String]) -> void:
	var coord: Vector2i = TerrainDetailTierPolicyScript.patch_coord_for_position(Vector2(-0.1, -256.1), 256.0)
	if coord != Vector2i(-1, -2):
		errors.append("negative_coord:%s" % str(coord))
	var settings: Dictionary = TerrainDetailTierPolicyScript.make_settings(256.0, 257, 0, 1)
	var patches: Array[Dictionary] = TerrainDetailTierPolicyScript.active_patches(Vector2(-0.1, -256.1), settings)
	if patches.size() != 1 or str(patches[0]["key"]) != "-1,-2":
		errors.append("negative_patch:%s" % str(patches))


func _report_and_quit(errors: Array[String]) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-detail-tier-policy] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-detail-tier-policy] status=pass")
	quit(0)
