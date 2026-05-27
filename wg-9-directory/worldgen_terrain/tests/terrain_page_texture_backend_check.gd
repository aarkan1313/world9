extends SceneTree

const TerrainPageTextureBackendScript := preload("res://worldgen_terrain/core/terrain_page_texture_backend.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_image_fallback_contract(errors)
	_check_residency_contract(errors)
	_check_missing_images_fail_fast(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-page-texture-backend] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-page-texture-backend] status=pass")
	quit(0)


func _check_image_fallback_contract(errors: Array[String]) -> void:
	var backend = TerrainPageTextureBackendScript.new()
	backend.configure(false, 0, false, false)
	var entry: Dictionary = backend.get_or_create_textures("fallback_a", _descriptor(8, 10.0))
	if entry.get("status", "fail") != "pass":
		errors.append("fallback_entry:%s" % str(entry))
		return
	if str(entry.get("texture_backend", "")) != "image":
		errors.append("fallback_backend:%s" % str(entry))
	var state: Dictionary = backend.gpu_page_residency_state()
	if int(state.get("count", -1)) != 0:
		errors.append("fallback_residency_count:%s" % str(state))


func _check_residency_contract(errors: Array[String]) -> void:
	var backend = TerrainPageTextureBackendScript.new()
	backend.configure(true, 2, false, false)
	var first: Dictionary = backend.get_or_create_textures("a", _descriptor(8, 1.0))
	var second: Dictionary = backend.get_or_create_textures("a", _descriptor(8, 1.0))
	if first.get("status", "fail") != "pass" or second.get("status", "fail") != "pass":
		errors.append("residency_entries:%s:%s" % [str(first), str(second)])
		return
	if second.get("height_texture") != first.get("height_texture"):
		errors.append("residency_height_not_reused")
	if not backend.has_page("a"):
		errors.append("residency_missing_page")
	backend.set_protected_keys(["a"])
	backend.get_or_create_textures("b", _descriptor(8, 2.0))
	backend.get_or_create_textures("c", _descriptor(8, 3.0))
	var state: Dictionary = backend.gpu_page_residency_state()
	if not backend.has_page("a"):
		errors.append("residency_protected_evicted:%s" % str(state))
	if int(state.get("count", 0)) != 2:
		errors.append("residency_count:%s" % str(state))
	if int(state.get("hits", 0)) < 1:
		errors.append("residency_hits:%s" % str(state))
	backend.clear()
	var cleared: Dictionary = backend.gpu_page_residency_state()
	if int(cleared.get("count", -1)) != 0:
		errors.append("residency_clear:%s" % str(cleared))


func _check_missing_images_fail_fast(errors: Array[String]) -> void:
	var backend = TerrainPageTextureBackendScript.new()
	backend.configure(false, 0, false, false)
	var entry: Dictionary = backend.get_or_create_textures("bad", {
		"status": "pass",
		"vertices_per_side": 8,
		"spacing_m": 4.0,
	})
	if entry.get("status", "pass") != "fail":
		errors.append("missing_images_not_failed:%s" % str(entry))


func _descriptor(count: int, base_height: float) -> Dictionary:
	var height_data := PackedByteArray()
	var normal_data := PackedByteArray()
	height_data.resize(count * count * 4)
	normal_data.resize(count * count * 12)
	for index in range(count * count):
		height_data.encode_float(index * 4, base_height + float(index) * 0.25)
		var normal_offset: int = index * 12
		normal_data.encode_float(normal_offset, 0.0)
		normal_data.encode_float(normal_offset + 4, 1.0)
		normal_data.encode_float(normal_offset + 8, 0.0)
	return {
		"status": "pass",
		"vertices_per_side": count,
		"spacing_m": 4.0,
		"height_image_data": height_data,
		"normal_image_data": normal_data,
		"height_image": Image.create_from_data(count, count, false, Image.FORMAT_RF, height_data),
		"normal_image": Image.create_from_data(count, count, false, Image.FORMAT_RGBF, normal_data),
	}
