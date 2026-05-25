extends SceneTree

const TerrainPageRequestScript := preload("res://worldgen_terrain/core/terrain_page_request.gd")
const TerrainPageResultScript := preload("res://worldgen_terrain/core/terrain_page_result.gd")
const TerrainPageCacheScript := preload("res://worldgen_terrain/core/terrain_page_cache.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_request_contract(errors)
	_check_result_contract(errors)
	_check_cache_contract(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-page-contract] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-terrain-page-contract] status=pass")
	return 0


func _check_request_contract(errors: Array[String]) -> void:
	var flags_a := {
		"lod": 1,
		"surface_material": true,
		"debug_mode": "gray",
	}
	var flags_b := {
		"debug_mode": "gray",
		"surface_material": true,
		"lod": 1,
	}
	var request_a = TerrainPageRequestScript.from_grid(
		Vector2(-512.0, 1024.0),
		129,
		129,
		4.0,
		1337,
		"far_clipmap",
		"walk_review",
		flags_a,
		{"level": 0}
	)
	request_a.provider_revision = 3
	request_a.runtime_pack_hash = "pack_a"
	var request_b = TerrainPageRequestScript.from_grid(
		Vector2(-512.0, 1024.0),
		129,
		129,
		4.0,
		1337,
		"far_clipmap",
		"walk_review",
		flags_b,
		{"level": 0}
	)
	request_b.provider_revision = 3
	request_b.runtime_pack_hash = "pack_a"
	if not request_a.is_valid():
		errors.append("valid_request_invalid:%s" % request_a.validate())
	if request_a.deterministic_key() != request_b.deterministic_key():
		errors.append("feature_order_changed_key")
	if request_a.cache_key() == request_a.deterministic_key():
		errors.append("cache_key_missing_prefix")
	if request_a.center_xz().distance_to(Vector2(-256.0, 1280.0)) > 0.0001:
		errors.append("center_xz:%s" % str(request_a.center_xz()))
	var changed_step = TerrainPageRequestScript.from_grid(
		Vector2(-512.0, 1024.0),
		129,
		129,
		2.0,
		1337,
		"far_clipmap",
		"walk_review",
		flags_b
	)
	changed_step.provider_revision = 3
	changed_step.runtime_pack_hash = "pack_a"
	if changed_step.deterministic_key() == request_a.deterministic_key():
		errors.append("step_not_in_key")
	var invalid_step = TerrainPageRequestScript.from_grid(Vector2.ZERO, 16, 16, 0.0)
	if invalid_step.validate().is_empty():
		errors.append("invalid_step_passed")
	var invalid_count = TerrainPageRequestScript.from_grid(Vector2.ZERO, 0, 16, 1.0)
	if invalid_count.validate().is_empty():
		errors.append("invalid_count_passed")
	var invalid_origin = TerrainPageRequestScript.from_grid(Vector2(INF, 0.0), 16, 16, 1.0)
	if invalid_origin.validate().is_empty():
		errors.append("invalid_origin_passed")


func _check_result_contract(errors: Array[String]) -> void:
	var request = TerrainPageRequestScript.from_chunk(
		2,
		-1,
		512.0,
		129,
		2026,
		"chunk",
		"walk_review",
		{"lod": 0}
	)
	request.provider_revision = 7
	request.runtime_pack_hash = "pack_result"
	var result = TerrainPageResultScript.from_request(request)
	var height := PackedFloat32Array()
	height.resize(129 * 129)
	result.height_samples = height
	if not result.is_ready():
		errors.append("result_not_ready")
	if result.request_key != request.deterministic_key():
		errors.append("result_request_key")
	if result.cache_key != request.cache_key():
		errors.append("result_cache_key")
	if str(result.version_stamp.get("runtime_pack_hash", "")) != "pack_result":
		errors.append("result_version_stamp")
	if not result.validate_payload_shape().is_empty():
		errors.append("result_shape:%s" % result.validate_payload_shape())
	var bad_normals := PackedVector3Array()
	bad_normals.resize(1)
	result.normal_samples = bad_normals
	if result.validate_payload_shape().is_empty():
		errors.append("bad_normal_shape_passed")
	var failed = TerrainPageResultScript.failed(request, "forced")
	if failed.is_ready():
		errors.append("failed_result_ready")


func _check_cache_contract(errors: Array[String]) -> void:
	var cache = TerrainPageCacheScript.new()
	cache.configure(2)
	var request_a = TerrainPageRequestScript.from_grid(Vector2(0.0, 0.0), 4, 4, 1.0, 1, "a")
	var request_b = TerrainPageRequestScript.from_grid(Vector2(4.0, 0.0), 4, 4, 1.0, 1, "b")
	var request_c = TerrainPageRequestScript.from_grid(Vector2(8.0, 0.0), 4, 4, 1.0, 1, "c")
	var request_d = TerrainPageRequestScript.from_grid(Vector2(12.0, 0.0), 4, 4, 1.0, 1, "d")
	var result_a = TerrainPageResultScript.from_request(request_a)
	var result_b = TerrainPageResultScript.from_request(request_b)
	var result_c = TerrainPageResultScript.from_request(request_c)
	var result_d = TerrainPageResultScript.from_request(request_d)
	if not cache.put_page(result_a):
		errors.append("put_a_failed")
	if not cache.put_page(result_b):
		errors.append("put_b_failed")
	cache.set_protected_keys([result_a.cache_key])
	if not cache.put_page(result_c):
		errors.append("put_c_failed")
	if not cache.has_page(result_a.cache_key):
		errors.append("protected_a_evicted")
	if cache.has_page(result_b.cache_key):
		errors.append("unprotected_b_retained")
	if not cache.has_page(result_c.cache_key):
		errors.append("new_c_missing")
	cache.clear_protected_keys()
	if cache.get_page(result_c.cache_key) == null:
		errors.append("get_c_failed")
	if not cache.put_page(result_d):
		errors.append("put_d_failed")
	if cache.has_page(result_a.cache_key):
		errors.append("old_a_retained_after_unprotect")
	var failed = TerrainPageResultScript.failed(request_b, "forced")
	if cache.put_page(failed):
		errors.append("failed_cached")
	var state: Dictionary = cache.debug_state()
	if int(state.get("evictions", 0)) < 2:
		errors.append("evictions:%s" % str(state))
	if int(state.get("hits", 0)) < 1:
		errors.append("hits:%s" % str(state))
	if int(state.get("rejected", 0)) < 1:
		errors.append("rejected:%s" % str(state))
