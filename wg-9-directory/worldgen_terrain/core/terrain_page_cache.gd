class_name TerrainPageCache
extends RefCounted

var max_pages: int = 0

var _pages: Dictionary = {}
var _last_used_tick: Dictionary = {}
var _protected_keys: Dictionary = {}
var _tick: int = 0
var _hits: int = 0
var _misses: int = 0
var _evictions: int = 0
var _protected_evictions: int = 0
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
	_evictions = 0
	_protected_evictions = 0
	_rejected = 0


func get_page(cache_key: String):
	if cache_key.is_empty() or not _pages.has(cache_key):
		_misses += 1
		return null
	_hits += 1
	_touch(cache_key)
	return _pages[cache_key]


func put_page(page) -> bool:
	if max_pages <= 0 or page == null:
		_rejected += 1
		return false
	if not page.has_method("is_ready") or not page.is_ready():
		_rejected += 1
		return false
	var key := str(page.cache_key)
	if key.is_empty():
		_rejected += 1
		return false
	_pages[key] = page
	_touch(key)
	_evict_to_budget()
	return _pages.has(key)


func has_page(cache_key: String) -> bool:
	return _pages.has(cache_key)


func set_protected_keys(keys: Array) -> void:
	_protected_keys.clear()
	for key_value in keys:
		var key := str(key_value)
		if not key.is_empty():
			_protected_keys[key] = true
	_evict_to_budget()


func clear_protected_keys() -> void:
	_protected_keys.clear()


func keys() -> Array[String]:
	var out: Array[String] = []
	for key in _pages.keys():
		out.append(str(key))
	out.sort()
	return out


func protected_keys() -> Array[String]:
	var out: Array[String] = []
	for key in _protected_keys.keys():
		out.append(str(key))
	out.sort()
	return out


func debug_state() -> Dictionary:
	return {
		"max_pages": max_pages,
		"count": _pages.size(),
		"hits": _hits,
		"misses": _misses,
		"evictions": _evictions,
		"protected_evictions": _protected_evictions,
		"rejected": _rejected,
		"protected_count": _protected_keys.size(),
		"keys": keys(),
		"protected_keys": protected_keys(),
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
		var key := _oldest_evictable_key(false)
		if key.is_empty():
			key = _oldest_evictable_key(true)
			if not key.is_empty() and bool(_protected_keys.get(key, false)):
				_protected_evictions += 1
		if key.is_empty():
			return
		_evict_key(key)


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


func _evict_key(cache_key: String) -> void:
	_pages.erase(cache_key)
	_last_used_tick.erase(cache_key)
	_evictions += 1
