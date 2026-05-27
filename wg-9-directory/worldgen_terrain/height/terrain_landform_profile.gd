class_name TerrainLandformProfile
extends RefCounted

const BALANCED_CURRENT := "balanced_current"
const STRONG_MOUNTAINS := "strong_mountains"
const MEDIUM_SCALE := "medium_scale"
const COMPRESSED_SCALE := "compressed_scale"


static func profile_ids() -> Array[String]:
	return [BALANCED_CURRENT, STRONG_MOUNTAINS, MEDIUM_SCALE, COMPRESSED_SCALE]


static func profile(profile_id: String) -> Dictionary:
	match profile_id:
		BALANCED_CURRENT:
			return _balanced_current()
		STRONG_MOUNTAINS:
			return _strong_mountains()
		MEDIUM_SCALE:
			return _medium_scale()
		COMPRESSED_SCALE:
			return _compressed_scale()
		_:
			return {}


static func settings(profile_id: String) -> Dictionary:
	return profile(profile_id).get("settings", {}) as Dictionary


static func _balanced_current() -> Dictionary:
	return {
		"id": BALANCED_CURRENT,
		"schema": "worldgen9.landform_profile.v1",
		"description": "Neutral current generator balance; this must stay equivalent to unprofiled terrain.",
		"settings": {
			"macro_relief_scale": 1.0,
			"kernel_relief_strength": 1.0,
			"mountain_boost": 1.0,
			"regional_scale_multiplier": 1.0,
			"valley_bias_strength": 1.0,
			"pass_corridor_strength": 0.0,
		},
	}


static func _strong_mountains() -> Dictionary:
	var profile_data: Dictionary = _balanced_current()
	profile_data["id"] = STRONG_MOUNTAINS
	profile_data["description"] = "Review-only profile for taller mountain/glacial/volcanic relief without changing region layout."
	profile_data["settings"] = {
		"macro_relief_scale": 1.22,
		"kernel_relief_strength": 1.45,
		"mountain_boost": 1.80,
		"regional_scale_multiplier": 1.0,
		"valley_bias_strength": 1.18,
		"pass_corridor_strength": 0.0,
	}
	profile_data["review_only"] = true
	return profile_data


static func _medium_scale() -> Dictionary:
	var profile_data: Dictionary = _balanced_current()
	profile_data["id"] = MEDIUM_SCALE
	profile_data["description"] = "Review-only candidate between balanced terrain and the stronger compressed-scale close-read profile."
	profile_data["settings"] = {
		"macro_relief_scale": 1.0,
		"kernel_relief_strength": 1.12,
		"mountain_boost": 1.08,
		"regional_scale_multiplier": 0.68,
		"valley_bias_strength": 1.0,
		"pass_corridor_strength": 0.0,
	}
	profile_data["review_only"] = true
	return profile_data


static func _compressed_scale() -> Dictionary:
	var profile_data: Dictionary = _balanced_current()
	profile_data["id"] = COMPRESSED_SCALE
	profile_data["description"] = "Review-only profile that compresses sampled landform frequency so variation appears over shorter travel distance."
	profile_data["settings"] = {
		"macro_relief_scale": 1.0,
		"kernel_relief_strength": 1.25,
		"mountain_boost": 1.18,
		"regional_scale_multiplier": 0.45,
		"valley_bias_strength": 1.0,
		"pass_corridor_strength": 0.0,
	}
	profile_data["review_only"] = true
	return profile_data
