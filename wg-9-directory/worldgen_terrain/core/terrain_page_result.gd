class_name TerrainPageResult
extends RefCounted

const STATUS_PASS: String = "pass"
const STATUS_FAIL: String = "fail"

var status: String = STATUS_PASS
var error: String = ""
var request_key: String = ""
var cache_key: String = ""
var version_stamp: Dictionary = {}
var origin_xz: Vector2 = Vector2.ZERO
var count_x: int = 0
var count_z: int = 0
var step_m: float = 0.0
var world_seed: int = 1337
var purpose: String = ""
var quality_profile: String = ""
var provider_revision: int = 0
var runtime_pack_hash: String = ""
var height_samples: PackedFloat32Array = PackedFloat32Array()
var collision_height_samples: PackedFloat32Array = PackedFloat32Array()
var normal_samples: PackedVector3Array = PackedVector3Array()
var timings_ms: Dictionary = {}
var metadata: Dictionary = {}

func copy_request_metadata(request) -> void:
	request_key = request.deterministic_key()
	cache_key = request.cache_key()
	version_stamp = request.version_stamp()
	origin_xz = request.origin_xz
	count_x = request.count_x
	count_z = request.count_z
	step_m = request.step_m
	world_seed = request.world_seed
	purpose = request.purpose
	quality_profile = request.quality_profile
	provider_revision = request.provider_revision
	runtime_pack_hash = request.runtime_pack_hash
	metadata = request.metadata.duplicate(true)


func is_ready() -> bool:
	return status == STATUS_PASS and error.is_empty()


func expected_sample_count() -> int:
	return maxi(0, count_x) * maxi(0, count_z)


func validate_payload_shape() -> String:
	var expected := expected_sample_count()
	if expected <= 0:
		return "expected_sample_count:%d" % expected
	if not height_samples.is_empty() and height_samples.size() != expected:
		return "height_samples:%d expected:%d" % [height_samples.size(), expected]
	if not collision_height_samples.is_empty() and collision_height_samples.size() != expected:
		return "collision_height_samples:%d expected:%d" % [collision_height_samples.size(), expected]
	if not normal_samples.is_empty() and normal_samples.size() != expected:
		return "normal_samples:%d expected:%d" % [normal_samples.size(), expected]
	return ""


func to_dictionary() -> Dictionary:
	return {
		"status": status,
		"error": error,
		"request_key": request_key,
		"cache_key": cache_key,
		"version_stamp": version_stamp.duplicate(true),
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
		"height_count": height_samples.size(),
		"collision_height_count": collision_height_samples.size(),
		"normal_count": normal_samples.size(),
		"timings_ms": timings_ms.duplicate(true),
		"metadata": metadata.duplicate(true),
	}
