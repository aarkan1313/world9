class_name TerrainGpuPageResidency
extends RefCounted

var max_pages: int = 0
var use_rd_textures: bool = false
var use_rd_compute_normals: bool = false

var _pages: Dictionary = {}
var _last_used_tick: Dictionary = {}
var _protected_keys: Dictionary = {}
var _texture_pool: Dictionary = {}
var _normal_compute_shaders: Dictionary = {}
var _normal_compute_pipelines: Dictionary = {}
var _tick: int = 0
var _hits: int = 0
var _misses: int = 0
var _uploads: int = 0
var _evictions: int = 0
var _rejected: int = 0
var _texture_reuses: int = 0
var _rd_uploads: int = 0
var _image_uploads: int = 0
var _rd_unavailable: int = 0
var _rd_compute_normal_uploads: int = 0
var _rd_compute_normal_failures: int = 0
var _last_rd_compute_normal_error: String = ""


func configure(
	p_max_pages: int,
	p_use_rd_textures: bool = false,
	p_use_rd_compute_normals: bool = false
) -> void:
	max_pages = maxi(0, p_max_pages)
	use_rd_textures = p_use_rd_textures
	use_rd_compute_normals = p_use_rd_compute_normals
	_evict_to_budget()


func clear() -> void:
	_sync_rendering_device()
	for key in _pages.keys():
		_release_page_resources(str(key), false)
	_sync_rendering_device()
	_pages.clear()
	_last_used_tick.clear()
	_protected_keys.clear()
	_texture_pool.clear()
	_release_compute_resources()
	_tick = 0
	_hits = 0
	_misses = 0
	_uploads = 0
	_evictions = 0
	_rejected = 0
	_texture_reuses = 0
	_rd_uploads = 0
	_image_uploads = 0
	_rd_unavailable = 0
	_rd_compute_normal_uploads = 0
	_rd_compute_normal_failures = 0
	_last_rd_compute_normal_error = ""


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
		_release_descriptor_rd_resources(descriptor)
		_rejected += 1
		return {"status": "fail", "error": "cache_disabled"}
	if descriptor.get("status", "fail") != "pass":
		_rejected += 1
		return {"status": "fail", "error": "descriptor_not_pass"}
	var entry: Dictionary = {}
	var attempted_rd_entry := false
	if use_rd_textures:
		attempted_rd_entry = true
		entry = _rd_texture_entry(cache_key, descriptor)
	if entry.get("status", "fail") != "pass":
		if attempted_rd_entry and not bool(entry.get("rd_descriptor_resources_released", false)):
			_release_descriptor_rd_resources(descriptor)
		entry = _image_texture_entry(cache_key, descriptor)
	if entry.get("status", "fail") != "pass":
		_rejected += 1
		return entry
	_pages[cache_key] = entry
	_uploads += 1
	_touch(cache_key)
	_evict_to_budget()
	if not _pages.has(cache_key):
		return {"status": "fail", "error": "evicted_on_insert"}
	return (_pages[cache_key] as Dictionary).duplicate()


func _image_texture_entry(cache_key: String, descriptor: Dictionary) -> Dictionary:
	var height_image: Image = descriptor.get("height_image") as Image
	var normal_image: Image = descriptor.get("normal_image") as Image
	if height_image == null or normal_image == null:
		return {"status": "fail", "error": "missing_images"}
	var height_texture: ImageTexture = _texture_from_pool_or_create(height_image)
	var normal_texture: ImageTexture = _texture_from_pool_or_create(normal_image)
	_image_uploads += 1
	return {
		"status": "pass",
		"cache_key": cache_key,
		"height_texture": height_texture,
		"normal_texture": normal_texture,
		"height_bytes": _image_byte_size(height_image),
		"normal_bytes": _image_byte_size(normal_image),
		"width": height_image.get_width(),
		"height": height_image.get_height(),
		"texture_backend": "image",
	}


func _rd_texture_entry(cache_key: String, descriptor: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("Texture2DRD") or not RenderingServer.has_method("get_rendering_device"):
		_rd_unavailable += 1
		return {"status": "fail", "error": "texture2drd_unavailable"}
	var side: int = int(descriptor.get("vertices_per_side", 0))
	if side <= 0:
		_rd_unavailable += 1
		return {"status": "fail", "error": "rd_side:%d" % side}
	var height_data: PackedByteArray = descriptor.get("height_image_data", PackedByteArray()) as PackedByteArray
	var normal_data: PackedByteArray = descriptor.get("normal_image_data", PackedByteArray()) as PackedByteArray
	var supplied_height_rid: RID = descriptor.get("height_texture_rid", RID()) as RID
	var has_supplied_height_rid := supplied_height_rid.is_valid()
	if not has_supplied_height_rid and height_data.size() != side * side * 4:
		return {"status": "fail", "error": "rd_missing_preencoded_data"}
	if not use_rd_compute_normals and normal_data.size() != side * side * 12:
		return {"status": "fail", "error": "rd_missing_preencoded_data"}
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd == null:
		_rd_unavailable += 1
		return {"status": "fail", "error": "rendering_device_unavailable"}
	var texture_usage: int = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	if use_rd_compute_normals:
		texture_usage |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var height_rid: RID = supplied_height_rid
	var height_texture_mode := "rd_external" if has_supplied_height_rid else "preencoded"
	var height_texture_owned_by_residency := bool(descriptor.get("height_texture_owned_by_residency", false))
	if not has_supplied_height_rid:
		height_rid = _create_rd_texture(rd, side, RenderingDevice.DATA_FORMAT_R32_SFLOAT, height_data, texture_usage)
		height_texture_owned_by_residency = true
	var normal_result: Dictionary = _create_rd_normal_texture(rd, side, descriptor, height_rid, normal_data)
	var normal_rid: RID = normal_result.get("normal_rid", RID()) as RID
	if not height_rid.is_valid() or not normal_rid.is_valid():
		if height_rid.is_valid() and height_texture_owned_by_residency:
			rd.free_rid(height_rid)
		if normal_rid.is_valid():
			rd.free_rid(normal_rid)
		_free_rd_owned_rids(rd, descriptor)
		return {
			"status": "fail",
			"error": str(normal_result.get("error", "rd_texture_create_failed")),
			"rd_descriptor_resources_released": true,
		}
	var height_texture = ClassDB.instantiate("Texture2DRD")
	var normal_texture = ClassDB.instantiate("Texture2DRD")
	if height_texture == null or normal_texture == null:
		if height_rid.is_valid() and height_texture_owned_by_residency:
			rd.free_rid(height_rid)
		if normal_rid.is_valid():
			rd.free_rid(normal_rid)
		_free_rd_owned_rids(rd, descriptor)
		return {
			"status": "fail",
			"error": "texture2drd_instantiate_failed",
			"rd_descriptor_resources_released": true,
		}
	height_texture.set("texture_rd_rid", height_rid)
	normal_texture.set("texture_rd_rid", normal_rid)
	_rd_uploads += 1
	return {
		"status": "pass",
		"cache_key": cache_key,
		"height_texture": height_texture,
		"normal_texture": normal_texture,
		"height_texture_rid": height_rid,
		"normal_texture_rid": normal_rid,
		"normal_compute_uniform_set": normal_result.get("uniform_set", RID()),
		"height_texture_owned_by_residency": height_texture_owned_by_residency,
		"rd_owned_rids": descriptor.get("rd_owned_rids", []) as Array,
		"height_bytes": int(descriptor.get("height_bytes", side * side * 4)) if has_supplied_height_rid else height_data.size(),
		"normal_bytes": int(normal_result.get("normal_bytes", normal_data.size())),
		"width": side,
		"height": side,
		"texture_backend": "rd",
		"height_texture_mode": height_texture_mode,
		"normal_texture_mode": str(normal_result.get("mode", "preencoded")),
	}


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
		"texture_reuses": _texture_reuses,
		"pooled_textures": _pooled_texture_count(),
		"rd_uploads": _rd_uploads,
		"image_uploads": _image_uploads,
		"rd_unavailable": _rd_unavailable,
		"rd_compute_normal_uploads": _rd_compute_normal_uploads,
		"rd_compute_normal_failures": _rd_compute_normal_failures,
		"last_rd_compute_normal_error": _last_rd_compute_normal_error,
		"use_rd_textures": use_rd_textures,
		"use_rd_compute_normals": use_rd_compute_normals,
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
		for key in _pages.keys():
			_release_page_resources(str(key), false)
		_pages.clear()
		_last_used_tick.clear()
		_texture_pool.clear()
		return
	while _pages.size() > max_pages:
		var key: String = _oldest_evictable_key(false)
		if key.is_empty():
			key = _oldest_evictable_key(true)
		if key.is_empty():
			return
		_release_page_resources(key, true)
		_pages.erase(key)
		_last_used_tick.erase(key)
		_evictions += 1
	_trim_texture_pool()


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


func _create_rd_texture(
	rd: RenderingDevice,
	side: int,
	data_format: int,
	data: PackedByteArray,
	usage_bits: int
) -> RID:
	var format := RDTextureFormat.new()
	format.width = side
	format.height = side
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.format = data_format
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = usage_bits
	return rd.texture_create(format, RDTextureView.new(), [data])


func _create_empty_rd_texture(
	rd: RenderingDevice,
	side: int,
	data_format: int,
	usage_bits: int,
	bytes_per_pixel: int
) -> RID:
	var format := RDTextureFormat.new()
	format.width = side
	format.height = side
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.format = data_format
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = usage_bits
	var texture_rid: RID = rd.texture_create(format, RDTextureView.new(), [])
	if texture_rid.is_valid():
		return texture_rid
	var zero_data := PackedByteArray()
	zero_data.resize(side * side * max(1, bytes_per_pixel))
	return rd.texture_create(format, RDTextureView.new(), [zero_data])


func _create_rd_normal_texture(
	rd: RenderingDevice,
	side: int,
	descriptor: Dictionary,
	height_rid: RID,
	normal_data: PackedByteArray
) -> Dictionary:
	if use_rd_compute_normals:
		var compute: Dictionary = _create_compute_normal_texture(rd, side, descriptor, height_rid)
		if compute.get("status", "fail") == "pass":
			return compute
		_rd_compute_normal_failures += 1
		_last_rd_compute_normal_error = str(compute.get("error", "compute_normal_failed"))
	if normal_data.size() != side * side * 12:
		return {"status": "fail", "error": "rd_missing_preencoded_normal_data"}
	var normal_usage: int = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var normal_rid: RID = _create_rd_texture(
		rd,
		side,
		RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT,
		normal_data,
		normal_usage
	)
	if not normal_rid.is_valid():
		return {"status": "fail", "error": "rd_normal_texture_create_failed"}
	return {
		"status": "pass",
		"normal_rid": normal_rid,
		"normal_bytes": normal_data.size(),
		"mode": "preencoded",
	}


func _create_compute_normal_texture(
	rd: RenderingDevice,
	side: int,
	descriptor: Dictionary,
	height_rid: RID
) -> Dictionary:
	var step_m: float = float(descriptor.get("spacing_m", 0.0))
	if side < 2 or not is_finite(step_m) or step_m <= 0.0:
		return {"status": "fail", "error": "compute_normal_shape:%d %.6f" % [side, step_m]}
	var normal_usage: int = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var normal_rid: RID = _create_empty_rd_texture(
		rd,
		side,
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
		normal_usage,
		16
	)
	if not normal_rid.is_valid():
		return {"status": "fail", "error": "compute_normal_texture_create_failed"}
	var pipeline_result: Dictionary = _normal_compute_pipeline(rd, side, step_m)
	if pipeline_result.get("status", "fail") != "pass":
		rd.free_rid(normal_rid)
		return pipeline_result
	var shader_rid: RID = pipeline_result["shader_rid"] as RID
	var pipeline_rid: RID = pipeline_result["pipeline_rid"] as RID
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	height_uniform.binding = 0
	height_uniform.add_id(height_rid)
	var normal_uniform := RDUniform.new()
	normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	normal_uniform.binding = 1
	normal_uniform.add_id(normal_rid)
	var uniform_set: RID = rd.uniform_set_create([height_uniform, normal_uniform], shader_rid, 0)
	if not uniform_set.is_valid():
		rd.free_rid(normal_rid)
		return {"status": "fail", "error": "compute_normal_uniform_set_failed"}
	var compute_list: int = rd.compute_list_begin()
	if compute_list < 0:
		rd.free_rid(uniform_set)
		rd.free_rid(normal_rid)
		return {"status": "fail", "error": "compute_normal_list_begin_failed"}
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(float(side) / 8.0)), int(ceil(float(side) / 8.0)), 1)
	rd.compute_list_end()
	_rd_compute_normal_uploads += 1
	return {
		"status": "pass",
		"normal_rid": normal_rid,
		"normal_bytes": side * side * 16,
		"uniform_set": uniform_set,
		"mode": "rd_compute",
	}


func _normal_compute_pipeline(rd: RenderingDevice, side: int, step_m: float) -> Dictionary:
	var pipeline_key: String = "%d:%.9f" % [side, step_m]
	if _normal_compute_shaders.has(pipeline_key) and _normal_compute_pipelines.has(pipeline_key):
		return {
			"status": "pass",
			"shader_rid": _normal_compute_shaders[pipeline_key],
			"pipeline_rid": _normal_compute_pipelines[pipeline_key],
		}
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = _normal_compute_shader_source(side, step_m)
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv == null or not shader_spirv.compile_error_compute.is_empty():
		return {
			"status": "fail",
			"error": "compute_normal_shader_compile:%s" % (shader_spirv.compile_error_compute if shader_spirv != null else "null"),
		}
	var shader_rid: RID = rd.shader_create_from_spirv(shader_spirv)
	var pipeline_rid: RID = rd.compute_pipeline_create(shader_rid)
	if not shader_rid.is_valid() or not pipeline_rid.is_valid():
		if pipeline_rid.is_valid():
			rd.free_rid(pipeline_rid)
		if shader_rid.is_valid():
			rd.free_rid(shader_rid)
		return {"status": "fail", "error": "compute_normal_pipeline_create_failed"}
	_normal_compute_shaders[pipeline_key] = shader_rid
	_normal_compute_pipelines[pipeline_key] = pipeline_rid
	return {
		"status": "pass",
		"shader_rid": shader_rid,
		"pipeline_rid": pipeline_rid,
	}


func _normal_compute_shader_source(side: int, step_m: float) -> String:
	return """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform readonly image2D height_tex;
layout(rgba32f, set = 0, binding = 1) uniform writeonly image2D normal_tex;

const int SIDE = %d;
const float STEP_M = %.9f;

float height_at(ivec2 pixel) {
	ivec2 clamped_pixel = clamp(pixel, ivec2(0, 0), ivec2(SIDE - 1, SIDE - 1));
	return imageLoad(height_tex, clamped_pixel).r;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= SIDE || pixel.y >= SIDE) {
		return;
	}
	float left_h = height_at(pixel + ivec2(-1, 0));
	float right_h = height_at(pixel + ivec2(1, 0));
	float down_h = height_at(pixel + ivec2(0, -1));
	float up_h = height_at(pixel + ivec2(0, 1));
	vec3 normal = normalize(vec3(left_h - right_h, STEP_M * 2.0, down_h - up_h));
	vec3 encoded = normal * 0.5 + vec3(0.5);
	imageStore(normal_tex, pixel, vec4(encoded, 1.0));
}
""" % [side, step_m]


func _texture_from_pool_or_create(image: Image) -> ImageTexture:
	var pool_key: String = _texture_pool_key_for_image(image)
	var bucket: Array = _texture_pool.get(pool_key, []) as Array
	if not bucket.is_empty():
		var texture: ImageTexture = bucket.pop_back() as ImageTexture
		_texture_pool[pool_key] = bucket
		texture.update(image)
		_texture_reuses += 1
		return texture
	return ImageTexture.create_from_image(image)


func _release_page_resources(cache_key: String, allow_pool: bool) -> void:
	var entry: Dictionary = _pages.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return
	if str(entry.get("texture_backend", "")) == "rd":
		var rd: RenderingDevice = null
		if RenderingServer.has_method("get_rendering_device"):
			rd = RenderingServer.call("get_rendering_device") as RenderingDevice
		var height_texture: Object = entry.get("height_texture") as Object
		var normal_texture: Object = entry.get("normal_texture") as Object
		if rd != null:
			var height_rid: RID = entry.get("height_texture_rid", RID()) as RID
			var normal_rid: RID = entry.get("normal_texture_rid", RID()) as RID
			var uniform_set: RID = entry.get("normal_compute_uniform_set", RID()) as RID
			if height_texture != null:
				height_texture.set("texture_rd_rid", RID())
			if normal_texture != null:
				normal_texture.set("texture_rd_rid", RID())
			if uniform_set.is_valid():
				rd.free_rid(uniform_set)
			_free_rd_owned_rids(rd, entry)
			if height_rid.is_valid() and bool(entry.get("height_texture_owned_by_residency", true)):
				rd.free_rid(height_rid)
			if normal_rid.is_valid():
				rd.free_rid(normal_rid)
		return
	if not allow_pool:
		return
	_pool_texture(entry.get("height_texture") as ImageTexture, int(entry.get("width", 0)), int(entry.get("height", 0)), Image.FORMAT_RF)
	_pool_texture(entry.get("normal_texture") as ImageTexture, int(entry.get("width", 0)), int(entry.get("height", 0)), Image.FORMAT_RGBF)


func _free_rd_owned_rids(rd: RenderingDevice, source: Dictionary) -> void:
	var rids: Array = source.get("rd_owned_rids", []) as Array
	for value in rids:
		var rid: RID = value as RID
		if rid.is_valid():
			rd.free_rid(rid)


func _release_descriptor_rd_resources(descriptor: Dictionary) -> void:
	var height_rid: RID = descriptor.get("height_texture_rid", RID()) as RID
	var owns_height := bool(descriptor.get("height_texture_owned_by_residency", false))
	if not height_rid.is_valid() and (descriptor.get("rd_owned_rids", []) as Array).is_empty():
		return
	if not RenderingServer.has_method("get_rendering_device"):
		return
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd == null:
		return
	if height_rid.is_valid() and owns_height:
		rd.free_rid(height_rid)
	_free_rd_owned_rids(rd, descriptor)


func _pool_texture(texture: ImageTexture, width: int, height: int, format: int) -> void:
	if texture == null or width <= 0 or height <= 0:
		return
	var pool_key: String = _texture_pool_key(width, height, format)
	var bucket: Array = _texture_pool.get(pool_key, []) as Array
	bucket.append(texture)
	_texture_pool[pool_key] = bucket


func _trim_texture_pool() -> void:
	var max_pooled_textures: int = max(0, max_pages * 2)
	while _pooled_texture_count() > max_pooled_textures:
		var keys := _sorted_keys(_texture_pool)
		if keys.is_empty():
			return
		var key: String = keys[0]
		var bucket: Array = _texture_pool.get(key, []) as Array
		if bucket.is_empty():
			_texture_pool.erase(key)
			continue
		bucket.pop_front()
		if bucket.is_empty():
			_texture_pool.erase(key)
		else:
			_texture_pool[key] = bucket


func _release_compute_resources() -> void:
	var rd: RenderingDevice = null
	if RenderingServer.has_method("get_rendering_device"):
		rd = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd != null:
		for pipeline_value in _normal_compute_pipelines.values():
			var pipeline_rid: RID = pipeline_value as RID
			if pipeline_rid.is_valid():
				rd.free_rid(pipeline_rid)
		for shader_value in _normal_compute_shaders.values():
			var shader_rid: RID = shader_value as RID
			if shader_rid.is_valid():
				rd.free_rid(shader_rid)
	_normal_compute_pipelines.clear()
	_normal_compute_shaders.clear()


func _sync_rendering_device() -> void:
	# This residency cache uses Godot's main renderer device. Main RenderingDevice
	# instances are owned by the renderer; calling sync() here can crash/error on
	# shutdown because only local devices may be manually submitted or synced.
	return


func _pooled_texture_count() -> int:
	var count := 0
	for value in _texture_pool.values():
		count += (value as Array).size()
	return count


func _texture_pool_key_for_image(image: Image) -> String:
	return _texture_pool_key(image.get_width(), image.get_height(), image.get_format())


func _texture_pool_key(width: int, height: int, format: int) -> String:
	return "%d:%d:%d" % [width, height, int(format)]


func _sorted_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key_value in dict.keys():
		out.append(str(key_value))
	out.sort()
	return out


func _mib(byte_count: int) -> float:
	return snapped(float(byte_count) / (1024.0 * 1024.0), 0.001)
