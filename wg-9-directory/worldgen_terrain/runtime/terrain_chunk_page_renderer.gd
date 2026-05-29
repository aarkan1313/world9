class_name TerrainChunkPageRenderer
extends RefCounted

const TerrainPageTextureBackendScript := preload("res://worldgen_terrain/core/terrain_page_texture_backend.gd")

var cache_max_pages: int = 96
var residency_max_pages: int = 96
var use_rd_page_textures: bool = false
var use_rd_compute_normals: bool = true
var fast_gray_exposure: float = 1.0
var fast_gray_contrast: float = 1.0
var elevation_color_enabled: bool = false
var edge_fog_enabled: bool = false
var edge_fog_begin_m: float = 24000.0
var edge_fog_end_m: float = 33000.0
var edge_fog_color: Color = Color(0.18, 0.18, 0.18)

var _texture_backend: RefCounted
var _mesh_cache: Dictionary = {}
var _shader: Shader
var _flat_normal_image_data_cache: Dictionary = {}


func configure(settings: Dictionary) -> void:
	cache_max_pages = maxi(1, int(settings.get("cache_max_pages", cache_max_pages)))
	residency_max_pages = maxi(1, int(settings.get("residency_max_pages", residency_max_pages)))
	use_rd_page_textures = bool(settings.get("use_rd_page_textures", use_rd_page_textures))
	use_rd_compute_normals = bool(settings.get("use_rd_compute_normals", use_rd_compute_normals))
	fast_gray_exposure = float(settings.get("fast_gray_exposure", fast_gray_exposure))
	fast_gray_contrast = float(settings.get("fast_gray_contrast", fast_gray_contrast))
	elevation_color_enabled = bool(settings.get("elevation_color_enabled", elevation_color_enabled))
	edge_fog_enabled = bool(settings.get("edge_fog_enabled", edge_fog_enabled))
	edge_fog_begin_m = float(settings.get("edge_fog_begin_m", edge_fog_begin_m))
	edge_fog_end_m = float(settings.get("edge_fog_end_m", edge_fog_end_m))
	edge_fog_color = settings.get("edge_fog_color", edge_fog_color) as Color
	_configure_texture_backend()


func clear() -> void:
	if _texture_backend != null:
		_texture_backend.call("clear")


func flat_normal_image_data(count: int) -> PackedByteArray:
	if _flat_normal_image_data_cache.has(count):
		return _flat_normal_image_data_cache[count] as PackedByteArray
	var data := PackedByteArray()
	data.resize(count * count * 12)
	for index in range(count * count):
		var offset: int = index * 12
		data.encode_float(offset, 0.5)
		data.encode_float(offset + 4, 1.0)
		data.encode_float(offset + 8, 0.5)
	_flat_normal_image_data_cache[count] = data
	return data


func apply_descriptor(
	chunk_renderer: RefCounted,
	key: String,
	chunk_x: int,
	chunk_z: int,
	ring: int,
	lod: int,
	chunk_size_m: float,
	descriptor: Dictionary
) -> Dictionary:
	if chunk_renderer == null:
		return {"status": "fail", "error": "chunk_renderer_missing"}
	if descriptor.get("status", "fail") != "pass":
		return {"status": "fail", "error": str(descriptor.get("error", "descriptor_failed"))}
	var texture_start_ms: int = Time.get_ticks_msec()
	var texture_entry: Dictionary = _texture_entry(str(descriptor.get("cache_key", "")), descriptor)
	var texture_ms: int = Time.get_ticks_msec() - texture_start_ms
	if texture_entry.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": "texture:%s" % str(texture_entry.get("error", "unknown")),
			"texture_ms": texture_ms,
		}
	var mesh: Mesh = _chunk_page_mesh(int(descriptor["vertices_per_side"]), float(descriptor["chunk_size_m"]))
	if mesh == null:
		return {"status": "fail", "error": "mesh_failed", "texture_ms": texture_ms}
	var material: ShaderMaterial = _material_for_descriptor(descriptor, texture_entry)
	var mesh_instance: MeshInstance3D = chunk_renderer.call(
		"apply_chunk",
		key,
		chunk_x,
		chunk_z,
		ring,
		lod,
		chunk_size_m,
		mesh,
		material
	) as MeshInstance3D
	if mesh_instance == null:
		return {"status": "fail", "error": "apply_failed", "texture_ms": texture_ms}
	_apply_custom_aabb(mesh_instance, descriptor, chunk_size_m)
	mesh_instance.set_meta("gpu_page_chunk", true)
	return {
		"status": "pass",
		"mesh_instance": mesh_instance,
		"texture_ms": texture_ms,
	}


func set_protected_keys(keys: Array) -> void:
	if _texture_backend == null:
		return
	_texture_backend.call("set_protected_keys", keys)


func has_page(cache_key: String) -> bool:
	if cache_key.is_empty():
		return false
	_configure_texture_backend()
	return bool(_texture_backend.call("has_page", cache_key))


func gpu_page_residency_state() -> Dictionary:
	if _texture_backend == null:
		return {
			"max_pages": residency_max_pages,
			"count": 0,
			"uploads": 0,
			"rd_uploads": 0,
			"image_uploads": 0,
			"total_mib": 0.0,
		}
	return _texture_backend.call("gpu_page_residency_state") as Dictionary


func _texture_entry(cache_key: String, descriptor: Dictionary) -> Dictionary:
	_configure_texture_backend()
	return _texture_backend.call("get_or_create_textures", cache_key, descriptor) as Dictionary


func _configure_texture_backend() -> void:
	if _texture_backend == null:
		_texture_backend = TerrainPageTextureBackendScript.new()
	_texture_backend.call(
		"configure",
		true,
		max(1, min(cache_max_pages, residency_max_pages)),
		use_rd_page_textures,
		use_rd_compute_normals
	)


func _chunk_page_mesh(count: int, chunk_size_m: float) -> Mesh:
	var mesh_key: String = "%d:%.9f" % [count, chunk_size_m]
	if _mesh_cache.has(mesh_key):
		return _mesh_cache[mesh_key] as Mesh
	if count < 2 or not is_finite(chunk_size_m) or chunk_size_m <= 0.0:
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(count * count)
	normals.resize(count * count)
	uvs.resize(count * count)
	indices.resize((count - 1) * (count - 1) * 6)
	var denom: float = float(count - 1)
	var index_write := 0
	for z in range(count):
		for x in range(count):
			var index: int = z * count + x
			var u: float = float(x) / denom
			var v: float = float(z) / denom
			vertices[index] = Vector3(u * chunk_size_m, 0.0, v * chunk_size_m)
			normals[index] = Vector3.UP
			uvs[index] = Vector2(u, v)
	for z in range(count - 1):
		for x in range(count - 1):
			var i0: int = z * count + x
			var i1: int = i0 + 1
			var i2: int = i0 + count
			var i3: int = i2 + 1
			indices[index_write] = i0
			indices[index_write + 1] = i2
			indices[index_write + 2] = i1
			indices[index_write + 3] = i1
			indices[index_write + 4] = i2
			indices[index_write + 5] = i3
			index_write += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[mesh_key] = mesh
	return mesh


func _material_for_descriptor(descriptor: Dictionary, texture_entry: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader_resource()
	material.set_shader_parameter("height_texture", texture_entry["height_texture"] as Texture2D)
	material.set_shader_parameter("normal_texture", texture_entry["normal_texture"] as Texture2D)
	material.set_shader_parameter("chunk_size_m", float(descriptor.get("chunk_size_m", 512.0)))
	material.set_shader_parameter("normal_strength", 1.0)
	material.set_shader_parameter("gray_exposure", fast_gray_exposure)
	material.set_shader_parameter("gray_contrast", fast_gray_contrast)
	material.set_shader_parameter("elevation_color_enabled", elevation_color_enabled)
	material.set_shader_parameter("edge_fog_enabled", edge_fog_enabled)
	material.set_shader_parameter("edge_fog_begin_m", edge_fog_begin_m)
	material.set_shader_parameter("edge_fog_end_m", edge_fog_end_m)
	material.set_shader_parameter("edge_fog_color", Vector3(edge_fog_color.r, edge_fog_color.g, edge_fog_color.b))
	return material


func _shader_resource() -> Shader:
	if _shader != null:
		return _shader
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D height_texture : filter_linear, repeat_disable;
uniform sampler2D normal_texture : filter_linear, repeat_disable;
uniform float chunk_size_m = 512.0;
uniform float normal_strength = 1.0;
uniform float gray_exposure = 1.0;
uniform float gray_contrast = 1.0;
uniform bool elevation_color_enabled = false;
uniform bool edge_fog_enabled = false;
uniform float edge_fog_begin_m = 24000.0;
uniform float edge_fog_end_m = 33000.0;
uniform vec3 edge_fog_color = vec3(0.18, 0.18, 0.18);

varying vec2 chunk_uv;
varying float height_m;
varying vec3 terrain_normal;
varying vec3 world_position;

vec3 elevation_palette(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.16) {
		return mix(vec3(0.005, 0.006, 0.012), vec3(0.02, 0.05, 0.22), t / 0.16);
	}
	if (t < 0.32) {
		return mix(vec3(0.02, 0.05, 0.22), vec3(0.02, 0.35, 0.70), (t - 0.16) / 0.16);
	}
	if (t < 0.48) {
		return mix(vec3(0.02, 0.35, 0.70), vec3(0.05, 0.58, 0.24), (t - 0.32) / 0.16);
	}
	if (t < 0.64) {
		return mix(vec3(0.05, 0.58, 0.24), vec3(0.95, 0.86, 0.20), (t - 0.48) / 0.16);
	}
	if (t < 0.80) {
		return mix(vec3(0.95, 0.86, 0.20), vec3(0.90, 0.20, 0.08), (t - 0.64) / 0.16);
	}
	if (t < 0.92) {
		return mix(vec3(0.90, 0.20, 0.08), vec3(0.70, 0.24, 0.86), (t - 0.80) / 0.12);
	}
	return mix(vec3(0.70, 0.24, 0.86), vec3(1.0, 1.0, 1.0), (t - 0.92) / 0.08);
}

void vertex() {
	chunk_uv = UV;
	height_m = texture(height_texture, chunk_uv).r;
	VERTEX.y = height_m;
	terrain_normal = normalize(texture(normal_texture, chunk_uv).rgb * 2.0 - 1.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(terrain_normal);
	if (n.y < 0.0) {
		n = -n;
	}
	if (n.y < 0.25) {
		n = vec3(0.0, 1.0, 0.0);
	}
	vec3 stable_n = normalize(mix(vec3(0.0, 1.0, 0.0), n, clamp(normal_strength, 0.0, 4.0)));
	vec3 review_n = normalize(vec3(stable_n.x * 0.65, stable_n.y, stable_n.z * 0.65));
	vec3 light_dir = normalize(vec3(-0.42, 0.74, -0.52));
	float lambert = dot(review_n, light_dir) * 0.5 + 0.5;
	float compressed_height = 0.5 + atan(height_m / 1800.0) / 3.14159265;
	float height_t = clamp(compressed_height, 0.0, 1.0);
	float slope_shadow = clamp((1.0 - review_n.y) * 0.04, 0.0, 0.025);
	float shade = clamp(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70);
	shade = (shade - 0.5) * gray_contrast + 0.5;
	shade = clamp(shade * gray_exposure, 0.035, 0.58);
	vec3 elevation_tint = mix(vec3(0.56, 0.62, 0.58), vec3(0.80, 0.74, 0.62), height_t);
	vec3 color = vec3(shade) * mix(vec3(1.0), elevation_tint * 1.24, 0.28);
	if (elevation_color_enabled) {
		color = elevation_palette(height_t) * clamp(0.62 + lambert * 0.32 - (1.0 - review_n.y) * 0.08, 0.45, 1.0);
	}
	float fog_t = edge_fog_enabled ? smoothstep(edge_fog_begin_m, edge_fog_end_m, distance(world_position.xz, CAMERA_POSITION_WORLD.xz)) : 0.0;
	ALBEDO = mix(color, edge_fog_color, fog_t);
}
"""
	_shader = shader
	return _shader


func _apply_custom_aabb(mesh_instance: MeshInstance3D, descriptor: Dictionary, fallback_chunk_size_m: float) -> void:
	if mesh_instance == null:
		return
	var min_y: float = float(descriptor.get("height_min_m", -1024.0))
	var max_y: float = float(descriptor.get("height_max_m", 1024.0))
	if not is_finite(min_y) or not is_finite(max_y) or max_y < min_y:
		min_y = -2048.0
		max_y = 2048.0
	var height_range: float = max(1.0, max_y - min_y)
	var padding_y: float = maxf(64.0, height_range * 0.12)
	var chunk_size: float = max(1.0, float(descriptor.get("chunk_size_m", fallback_chunk_size_m)))
	mesh_instance.custom_aabb = AABB(
		Vector3(0.0, min_y - padding_y, 0.0),
		Vector3(chunk_size, height_range + padding_y * 2.0, chunk_size)
	)
