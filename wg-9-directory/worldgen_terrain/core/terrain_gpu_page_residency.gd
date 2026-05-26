class_name TerrainGpuPageResidency
extends RefCounted

var max_pages: int = 0

var _pages: Dictionary = {}
var _last_used_tick: Dictionary = {}
var _protected_keys: Dictionary = {}
var _tick: int = 0
var _hits: int = 0
var _misses: int = 0
var _uploads: int = 0
var _evictions: int = 0
var _rejected: int = 0


func configure(p_max_pages: int) -> void:
	max_pages = maxi(0, p_max_pages)
	_evict_to_budget()


func clear() -> void:
	_pages.clear()
	_last_used_tick.clear()
	_protected_keys.clear()
	_tick = 0
	_hits = 0
	_misses = 0
	_uploads = 0
	_evictions = 0
	_rejected = 0


func get_or_create_textures(cache_key: String, descriptor: Dictionary) -> Dictionary:
	if cache_key.is_empty():
		_rejected += 1
		return {"status": "fail", "error": "cache_key_empty"}
	if _pages.has(cache_key):
		_hits += 1
		_touch(cache_key)
		var cached: Dictionary = _pages[cache_key] as Dictionary
		return cached.duplicate()
	_misses += 1
	if max_pages <= 0:
		_rejected += 1
		return {"status": "fail", "error": "cache_disabled"}
	if descriptor.get("status", "fail") != "pass":
		_rejected += 1
		return {"status": "fail", "error": "descriptor_not_pass"}
	var height_image: Image = descriptor.get("height_image") as Image
	var normal_image: Image = descriptor.get("normal_image") as Image
	if height_image == null or normal_image == null:
		_rejected += 1
		return {"status": "fail", "error": "missing_images"}
	var height_texture: ImageTexture = ImageTexture.create_from_image(height_image)
	var normal_texture: ImageTexture = ImageTexture.create_from_image(normal_image)
	var entry := {
		"status": "pass",
		"cache_key": cache_key,
		"height_texture": height_texture,
		"normal_texture": normal_texture,
		"height_bytes": _image_byte_size(height_image),
		"normal_bytes": _image_byte_size(normal_image),
		"width": height_image.get_width(),
		"height": height_image.get_height(),
	}
	_pages[cache_key] = entry
	_uploads += 1
	_touch(cache_key)
	_evict_to_budget()
	if not _pages.has(cache_key):
		return {"status": "fail", "error": "evicted_on_insert"}
	return (_pages[cache_key] as Dictionary).duplicate()


func has_page(cache_key: String) -> bool:
	return _pages.has(cache_key)


func set_protected_keys(keys: Array) -> void:
	_protected_keys.clear()
	for key_value in keys:
		var key := str(key_value)
		if not key.is_empty():
			_protected_keys[key] = true
	_evict_to_budget()


func debug_state() -> Dictionary:
	var height_bytes := 0
	var normal_bytes := 0
	for value in _pages.values():
		var entry: Dictionary = value as Dictionary
		height_bytes += int(entry.get("height_bytes", 0))
		normal_bytes += int(entry.get("normal_bytes", 0))
	return {
		"max_pages": max_pages,
		"count": _pages.size(),
		"protected_count": _protected_keys.size(),
		"hits": _hits,
		"misses": _misses,
		"uploads": _uploads,
		"evictions": _evictions,
		"rejected": _rejected,
		"height_mib": _mib(height_bytes),
		"normal_mib": _mib(normal_bytes),
		"total_mib": _mib(height_bytes + normal_bytes),
		"keys": _sorted_keys(_pages),
		"protected_keys": _sorted_keys(_protected_keys),
	}


func _touch(cache_key: String) -> void:
	_tick += 1
	_last_used_tick[cache_key] = _tick


func _evict_to_budget() -> void:
	if max_pages <= 0:
		_evictions += _pages.size()
		_pages.clear()
		_last_used_tick.clear()
		return
	while _pages.size() > max_pages:
		var key: String = _oldest_evictable_key(false)
		if key.is_empty():
			key = _oldest_evictable_key(true)
		if key.is_empty():
			return
		_pages.erase(key)
		_last_used_tick.erase(key)
		_evictions += 1


func _oldest_evictable_key(allow_protected: bool) -> String:
	var oldest_key := ""
	var oldest_tick: int = 0
	for key_value in _pages.keys():
		var key := str(key_value)
		if not allow_protected and bool(_protected_keys.get(key, false)):
			continue
		var used := int(_last_used_tick.get(key, 0))
		if oldest_key.is_empty() or used < oldest_tick:
			oldest_key = key
			oldest_tick = used
	return oldest_key


func _image_byte_size(image: Image) -> int:
	if image == null:
		return 0
	match image.get_format():
		Image.FORMAT_RF:
			return image.get_width() * image.get_height() * 4
		Image.FORMAT_RGBF:
			return image.get_width() * image.get_height() * 12
		Image.FORMAT_RGBAF:
			return image.get_width() * image.get_height() * 16
		_:
			return image.get_data().size()


func _sorted_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key_value in dict.keys():
		out.append(str(key_value))
	out.sort()
	return out


func _mib(byte_count: int) -> float:
	return snapped(float(byte_count) / (1024.0 * 1024.0), 0.001)
