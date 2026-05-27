extends SceneTree

const TerrainGpuPageResidencyScript := preload("res://worldgen_terrain/core/terrain_gpu_page_residency.gd")
const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_residency_cache_contract(errors)
	_check_far_clipmap_residency_integration(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-page-residency] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-page-residency] status=pass")
	quit(0)


func _check_residency_cache_contract(errors: Array[String]) -> void:
	var residency = TerrainGpuPageResidencyScript.new()
	residency.configure(2)
	var descriptor_a: Dictionary = _descriptor(64, 1.0)
	var first: Dictionary = residency.get_or_create_textures("a", descriptor_a)
	if first.get("status", "fail") != "pass":
		errors.append("first_upload_failed:%s" % str(first))
		return
	var second: Dictionary = residency.get_or_create_textures("a", descriptor_a)
	if second.get("height_texture") != first.get("height_texture"):
		errors.append("cache_reused_different_height_texture")
	if second.get("normal_texture") != first.get("normal_texture"):
		errors.append("cache_reused_different_normal_texture")
	residency.set_protected_keys(["a"])
	residency.get_or_create_textures("b", _descriptor(64, 2.0))
	residency.get_or_create_textures("c", _descriptor(64, 3.0))
	var state: Dictionary = residency.debug_state()
	if not residency.has_page("a"):
		errors.append("protected_page_evicted:%s" % str(state))
	if int(state.get("count", 0)) != 2:
		errors.append("cache_count:%s" % str(state))
	if int(state.get("hits", 0)) < 1:
		errors.append("cache_hits:%s" % str(state))
	if int(state.get("uploads", 0)) < 3:
		errors.append("cache_uploads:%s" % str(state))
	if float(state.get("total_mib", 0.0)) <= 0.0:
		errors.append("cache_total_mib:%s" % str(state))
	_check_evicted_texture_reuse(errors)


func _check_evicted_texture_reuse(errors: Array[String]) -> void:
	var residency = TerrainGpuPageResidencyScript.new()
	residency.configure(1)
	residency.get_or_create_textures("a", _descriptor(32, 1.0))
	residency.get_or_create_textures("b", _descriptor(32, 2.0))
	residency.get_or_create_textures("c", _descriptor(32, 3.0))
	var state: Dictionary = residency.debug_state()
	if int(state.get("texture_reuses", 0)) < 2:
		errors.append("cache_texture_reuses:%s" % str(state))
	if int(state.get("pooled_textures", 0)) > 2:
		errors.append("cache_texture_pool_unbounded:%s" % str(state))


func _check_far_clipmap_residency_integration(errors: Array[String]) -> void:
	var world = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		return
	var node = TerrainFarClipmapNodeScript.new()
	node.level_count = 2
	node.use_persistent_page_mesh = true
	node.gpu_page_residency_max_pages = 4
	node.use_native_workers = false
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("clipmap_setup_failed")
		node.queue_free()
		return
	node.update_viewer(Vector2.ZERO)
	var stats: Dictionary = node.stats()
	var gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
	if int(gpu_state.get("count", 0)) != 2:
		errors.append("clipmap_gpu_page_count:%s" % str(gpu_state))
	if int(gpu_state.get("uploads", 0)) != 2:
		errors.append("clipmap_gpu_uploads:%s" % str(gpu_state))
	if float(gpu_state.get("total_mib", 0.0)) <= 0.0:
		errors.append("clipmap_gpu_total_mib:%s" % str(gpu_state))
	_check_persistent_page_bounds(node, errors)
	_check_persistent_page_material_reuse(node, errors)
	node.queue_free()


func _check_persistent_page_material_reuse(node: Node3D, errors: Array[String]) -> void:
	var mesh_instance: MeshInstance3D = node.level_nodes[0] as MeshInstance3D
	var first_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if first_material == null:
		errors.append("clipmap_material_missing_initial")
		return
	var first_height_texture: Texture2D = first_material.get_shader_parameter("height_texture") as Texture2D
	node.update_viewer(Vector2(node.base_spacing_m * 2.0, 0.0))
	var second_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if second_material != first_material:
		errors.append("clipmap_page_material_not_reused")
	var stats: Dictionary = node.stats()
	if not bool(stats.get("last_page_material_reused", false)):
		errors.append("clipmap_page_material_reuse_stat:%s" % str(stats))
	var active_blend_gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
	if int(stats.get("active_page_blend_count", 0)) > 0 and int(active_blend_gpu_state.get("protected_count", 0)) < node.level_count * 2:
		errors.append("clipmap_previous_blend_pages_not_protected:%s" % str(active_blend_gpu_state))
	var previous_height_texture: Texture2D = second_material.get_shader_parameter("previous_height_texture") as Texture2D
	if first_height_texture != null and previous_height_texture != first_height_texture:
		errors.append("clipmap_previous_texture_not_preserved")
	var shifted_gpu_state: Dictionary = stats.get("gpu_page_residency", {}) as Dictionary
	var shifted_uploads: int = int(shifted_gpu_state.get("uploads", 0))
	node.update_viewer(Vector2.ZERO)
	var return_stats: Dictionary = node.stats()
	var return_gpu_state: Dictionary = return_stats.get("gpu_page_residency", {}) as Dictionary
	if int(return_gpu_state.get("uploads", 0)) != shifted_uploads:
		errors.append("clipmap_cached_return_uploaded:%s shifted_uploads=%d" % [str(return_gpu_state), shifted_uploads])
	if int(return_stats.get("last_page_descriptor_texture_hits", 0)) < node.level_count:
		errors.append("clipmap_cached_return_texture_hits:%s" % str(return_stats))
	if int(return_stats.get("last_page_descriptor_image_builds", 0)) != 0:
		errors.append("clipmap_cached_return_image_builds:%s" % str(return_stats))


func _check_persistent_page_bounds(node: Node3D, errors: Array[String]) -> void:
	if node.level_nodes.is_empty() or node.level_heightfields.is_empty():
		errors.append("clipmap_bounds_missing_levels")
		return
	var mesh_instance: MeshInstance3D = node.level_nodes[0] as MeshInstance3D
	var heightfield: Dictionary = node.level_heightfields[0] as Dictionary
	var bounds: AABB = mesh_instance.custom_aabb
	if bounds.size.y <= 0.0:
		errors.append("clipmap_bounds_empty:%s" % str(bounds))
		return
	var min_y: float = float(heightfield.get("height_min_m", 0.0))
	var max_y: float = float(heightfield.get("height_max_m", 0.0))
	if bounds.position.y > min_y:
		errors.append("clipmap_bounds_min:%.3f min:%.3f" % [bounds.position.y, min_y])
	if bounds.position.y + bounds.size.y < max_y:
		errors.append("clipmap_bounds_max:%.3f max:%.3f" % [bounds.position.y + bounds.size.y, max_y])


func _descriptor(count: int, base_height: float) -> Dictionary:
	var height := PackedFloat32Array()
	height.resize(count * count)
	var normal_data := PackedByteArray()
	normal_data.resize(count * count * 12)
	for index in range(count * count):
		height[index] = base_height + float(index) * 0.25
		var offset: int = index * 12
		normal_data.encode_float(offset, 0.5)
		normal_data.encode_float(offset + 4, 1.0)
		normal_data.encode_float(offset + 8, 0.5)
	return {
		"status": "pass",
		"height_image": _height_image(height, count),
		"normal_image": Image.create_from_data(count, count, false, Image.FORMAT_RGBF, normal_data),
	}


func _height_image(height: PackedFloat32Array, count: int) -> Image:
	var data := PackedByteArray()
	data.resize(count * count * 4)
	for index in range(count * count):
		data.encode_float(index * 4, float(height[index]))
	return Image.create_from_data(count, count, false, Image.FORMAT_RF, data)
