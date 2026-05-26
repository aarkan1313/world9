extends SceneTree

const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	_check_near_elevation_material(errors)
	_check_far_elevation_material(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-elevation-color-material] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-elevation-color-material] status=pass")
	return 0


func _check_near_elevation_material(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.debug_mode = TerrainWorldScript.DEBUG_ELEVATION_COLOR
	node.use_fast_gray_material = true
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("near_setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	node.update_viewer(Vector2.ZERO)
	node.rebuild_all_active_for_preview(1)
	if node.built_chunk_count() < 1:
		errors.append("near_chunk_not_built")
		node.queue_free()
		return
	var found_shader := false
	for mesh_value in node.chunk_nodes.values():
		var mesh_instance: MeshInstance3D = mesh_value as MeshInstance3D
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if material != null and material.shader != null and material.shader.code.find("elevation_palette") >= 0:
			found_shader = true
			break
	if not found_shader:
		errors.append("near_elevation_shader_missing")
	node.queue_free()


func _check_far_elevation_material(errors: Array[String]) -> void:
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("far_world_setup_failed:%s" % str(world.errors))
		return
	var far: Node3D = TerrainFarClipmapNodeScript.new()
	far.use_elevation_color_material = true
	get_root().add_child(far)
	if not far.setup(world):
		errors.append("far_setup_failed")
		far.queue_free()
		return
	if far.level_nodes.is_empty():
		errors.append("far_no_levels")
		far.queue_free()
		return
	var material: ShaderMaterial = (far.level_nodes[0] as MeshInstance3D).material_override as ShaderMaterial
	if material == null or material.shader == null:
		errors.append("far_material_missing")
	elif material.shader.code.find("elevation_palette") < 0:
		errors.append("far_elevation_shader_missing")
	elif not bool(material.get_shader_parameter("elevation_color_enabled")):
		errors.append("far_elevation_param_disabled")
	far.queue_free()
