class_name TerrainPageTextureBackend
extends RefCounted

const TerrainGpuPageResidencyScript := preload("res://worldgen_terrain/core/terrain_gpu_page_residency.gd")

var use_persistent_page_mesh: bool = false
var gpu_page_residency_max_pages: int = 0
var use_gpu_rd_page_textures: bool = false
var use_gpu_rd_compute_normals: bool = false

var _gpu_page_residency: RefCounted


func configure(
	p_use_persistent_page_mesh: bool,
	p_gpu_page_residency_max_pages: int,
	p_use_gpu_rd_page_textures: bool,
	p_use_gpu_rd_compute_normals: bool
) -> void:
	use_persistent_page_mesh = p_use_persistent_page_mesh
	gpu_page_residency_max_pages = maxi(0, p_gpu_page_residency_max_pages)
	use_gpu_rd_page_textures = p_use_gpu_rd_page_textures
	use_gpu_rd_compute_normals = p_use_gpu_rd_compute_normals
	if use_persistent_page_mesh:
		_ensure_gpu_page_residency()
	elif _gpu_page_residency != null:
		_gpu_page_residency.clear()


func clear() -> void:
	if _gpu_page_residency != null:
		_gpu_page_residency.clear()


func has_page(cache_key: String) -> bool:
	return _gpu_page_residency != null and _gpu_page_residency.has_page(cache_key)


func set_protected_keys(keys: Array) -> void:
	if _gpu_page_residency == null:
		return
	_gpu_page_residency.set_protected_keys(keys)


func get_or_create_textures(cache_key: String, descriptor: Dictionary) -> Dictionary:
	if use_persistent_page_mesh:
		_ensure_gpu_page_residency()
		var resident: Dictionary = _gpu_page_residency.get_or_create_textures(cache_key, descriptor) as Dictionary
		if resident.get("status", "fail") == "pass":
			return resident
	return _image_texture_entry(cache_key, descriptor)


func gpu_page_residency_state() -> Dictionary:
	if _gpu_page_residency == null:
		return {
			"max_pages": gpu_page_residency_max_pages,
			"count": 0,
			"protected_count": 0,
			"hits": 0,
			"misses": 0,
			"uploads": 0,
			"evictions": 0,
			"rejected": 0,
			"texture_reuses": 0,
			"pooled_textures": 0,
			"rd_uploads": 0,
			"image_uploads": 0,
			"rd_unavailable": 0,
			"rd_compute_normal_uploads": 0,
			"rd_compute_normal_failures": 0,
			"last_rd_compute_normal_error": "",
			"use_rd_textures": use_gpu_rd_page_textures,
			"use_rd_compute_normals": use_gpu_rd_compute_normals,
			"height_mib": 0.0,
			"normal_mib": 0.0,
			"total_mib": 0.0,
			"keys": [],
			"protected_keys": [],
		}
	return _gpu_page_residency.debug_state()


func _ensure_gpu_page_residency() -> void:
	if _gpu_page_residency == null:
		_gpu_page_residency = TerrainGpuPageResidencyScript.new()
	_gpu_page_residency.configure(
		gpu_page_residency_max_pages,
		use_gpu_rd_page_textures,
		use_gpu_rd_compute_normals
	)


func _image_texture_entry(cache_key: String, descriptor: Dictionary) -> Dictionary:
	var height_image: Image = descriptor.get("height_image") as Image
	var normal_image: Image = descriptor.get("normal_image") as Image
	if height_image == null or normal_image == null:
		return {"status": "fail", "error": "missing_fallback_images"}
	return {
		"status": "pass",
		"cache_key": cache_key,
		"height_texture": ImageTexture.create_from_image(height_image),
		"normal_texture": ImageTexture.create_from_image(normal_image),
		"texture_backend": "image",
	}
