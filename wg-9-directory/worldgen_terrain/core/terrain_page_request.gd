class_name TerrainPageRequest
extends RefCounted

const SCHEMA_VERSION: int = 1
const DEFAULT_PROVIDER_REVISION: int = 1

var origin_xz: Vector2 = Vector2.ZERO
var count_x: int = 0
var count_z: int = 0
var step_m: float = 0.0
var world_seed: int = 1337
var purpose: String = "height"
var quality_profile: String = ""
var provider_revision: int = DEFAULT_PROVIDER_REVISION
var runtime_pack_hash: String = ""
var feature_flags: Dictionary = {}
var metadata: Dictionary = {}


static func from_grid(
		p_origin_xz: Vector2,
		p_count_x: int,
		p_count_z: int,
		p_step_m: float,
		p_world_seed: int = 1337,
		p_purpose: String = "height",
		p_quality_profile: String = "",
		p_feature_flags: Dictionary = {},
		p_metadata: Dictionary = {}
) -> TerrainPageRequest:
	var request := TerrainPageRequest.new()
	request.origin_xz = p_origin_xz
	request.count_x = p_count_x
	request.count_z = p_count_z
	request.step_m = p_step_m
	request.world_seed = p_world_seed
	request.purpose = p_purpose
	request.quality_profile = p_quality_profile
	request.feature_flags = p_feature_flags.duplicate(true)
	request.metadata = p_metadata.duplicate(true)
	return request


static func from_chunk(
		chunk_x: int,
		chunk_z: int,
		chunk_size_m: float,
		vertices_per_side: int,
		p_world_seed: int = 1337,
		p_purpose: String = "chunk",
		p_quality_profile: String = "",
		p_feature_flags: Dictionary = {},
		p_metadata: Dictionary = {}
) -> TerrainPageRequest:
	var step := 0.0
	if vertices_per_side > 1:
		step = chunk_size_m / float(vertices_per_side - 1)
	var request := from_grid(
		Vector2(float(chunk_x) * chunk_size_m, float(chunk_z) * chunk_size_m),
		vertices_per_side,
		vertices_per_side,
		step,
		p_world_seed,
		p_purpose,
		p_quality_profile,
		p_feature_flags,
		p_metadata
	)
	request.metadata["chunk_x"] = chunk_x
	request.metadata["chunk_z"] = chunk_z
	request.metadata["chunk_size_m"] = chunk_size_m
	return request


func extent_x_m() -> float:
	return maxf(0.0, float(count_x - 1) * step_m)


func extent_z_m() -> float:
	return maxf(0.0, float(count_z - 1) * step_m)


func center_xz() -> Vector2:
	return origin_xz + Vector2(extent_x_m() * 0.5, extent_z_m() * 0.5)


func validate() -> String:
	if purpose.is_empty():
		return "purpose_empty"
	if count_x < 1:
		return "count_x:%d" % count_x
	if count_z < 1:
		return "count_z:%d" % count_z
	if not is_finite(origin_xz.x) or not is_finite(origin_xz.y):
		return "origin_nonfinite"
	if not is_finite(step_m) or step_m <= 0.0:
		return "step_m:%f" % step_m
	if provider_revision < 1:
		return "provider_revision:%d" % provider_revision
	return ""


func is_valid() -> bool:
	return validate().is_empty()


func deterministic_key() -> String:
	return "schema=%d|purpose=%s|seed=%d|profile=%s|origin=%.9f,%.9f|count=%d,%d|step=%.9f|provider=%d|pack=%s|flags=%s" % [
		SCHEMA_VERSION,
		purpose,
		world_seed,
		quality_profile,
		origin_xz.x,
		origin_xz.y,
		count_x,
		count_z,
		step_m,
		provider_revision,
		runtime_pack_hash,
		_stable_variant_key(feature_flags),
	]


func cache_key() -> String:
	return "wg9_terrain_page|" + deterministic_key()


func version_stamp() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"purpose": purpose,
		"quality_profile": quality_profile,
		"provider_revision": provider_revision,
		"runtime_pack_hash": runtime_pack_hash,
		"world_seed": world_seed,
	}


func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"origin_x": origin_xz.x,
		"origin_z": origin_xz.y,
		"count_x": count_x,
		"count_z": count_z,
		"step_m": step_m,
		"world_seed": world_seed,
		"purpose": purpose,
		"quality_profile": quality_profile,
		"provider_revision": provider_revision,
		"runtime_pack_hash": runtime_pack_hash,
		"feature_flags": feature_flags.duplicate(true),
		"metadata": metadata.duplicate(true),
		"request_key": deterministic_key(),
		"cache_key": cache_key(),
	}


static func _stable_variant_key(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var keys: Array[String] = []
			for key in dict.keys():
				keys.append(str(key))
			keys.sort()
			var parts: Array[String] = []
			for key in keys:
				parts.append("%s:%s" % [key, _stable_variant_key(dict[key])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value:
				items.append(_stable_variant_key(item))
			return "[%s]" % ",".join(items)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = value
			var items: Array[String] = []
			for item in strings:
				items.append(str(item))
			return "[%s]" % ",".join(items)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var items: Array[String] = []
			for item in value:
				items.append(str(item))
			return "[%s]" % ",".join(items)
		TYPE_FLOAT:
			return "%.9f" % float(value)
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		_:
			return str(value)
