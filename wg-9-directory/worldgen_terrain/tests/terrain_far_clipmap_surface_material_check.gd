extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup:%s" % str(world.errors))
		_report_and_quit(errors)
		return

	_check_default_descriptor_path(world, errors)
	_check_texture_material_path(world, errors)
	_report_and_quit(errors)


func _check_default_descriptor_path(world: RefCounted, errors: Array[String]) -> void:
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	clipmap.level_count = 2
	clipmap.vertices_per_side = 129
	clipmap.base_spacing_m = 64.0
	clipmap.base_outer_extent_m = 4096.0
	clipmap.near_hole_extent_m = 2048.0
	get_root().add_child(clipmap)
	if not clipmap.setup(world):
		errors.append("default_setup_failed")
		clipmap.queue_free()
		return
	var update: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	if update.get("status", "fail") != "pass":
		errors.append("default_update:%s" % str(update))
	if bool(update.get("use_surface_texture_material", true)):
		errors.append("default_texture_enabled")
	if int(update.get("last_surface_texture_ms", -1)) != 0:
		errors.append("default_texture_ms:%d" % int(update.get("last_surface_texture_ms", -1)))
	var descriptors: Array[Dictionary] = clipmap.active_surface_texture_descriptors()
	_check_descriptors(descriptors, 2, errors)
	clipmap.queue_free()


func _check_texture_material_path(world: RefCounted, errors: Array[String]) -> void:
	var clipmap: Node3D = TerrainFarClipmapNodeScript.new()
	clipmap.level_count = 2
	clipmap.vertices_per_side = 129
	clipmap.base_spacing_m = 64.0
	clipmap.base_outer_extent_m = 4096.0
	clipmap.near_hole_extent_m = 2048.0
	clipmap.use_surface_texture_material = true
	clipmap.surface_texture_normal_strength = 0.65
	get_root().add_child(clipmap)
	if not clipmap.setup(world):
		errors.append("texture_setup_failed")
		clipmap.queue_free()
		return
	var update: Dictionary = clipmap.update_viewer(Vector2.ZERO)
	if update.get("status", "fail") != "pass":
		errors.append("texture_update:%s" % str(update))
	if not bool(update.get("use_surface_texture_material", false)):
		errors.append("texture_stats_disabled")
	if int(update.get("last_surface_texture_ms", -1)) < 0:
		errors.append("texture_ms:%d" % int(update.get("last_surface_texture_ms", -1)))
	var descriptors: Array[Dictionary] = clipmap.active_surface_texture_descriptors()
	_check_descriptors(descriptors, 2, errors)
	for level in range(2):
		_check_level_material(clipmap.level_nodes[level] as MeshInstance3D, level, errors)
	clipmap.queue_free()


func _check_descriptors(descriptors: Array[Dictionary], expected_count: int, errors: Array[String]) -> void:
	if descriptors.size() != expected_count:
		errors.append("descriptor_count:%d expected:%d" % [descriptors.size(), expected_count])
		return
	for index in range(descriptors.size()):
		var descriptor: Dictionary = descriptors[index]
		if descriptor.get("status", "fail") != "pass":
			errors.append("descriptor_failed:%d:%s" % [index, str(descriptor)])
			continue
		if int(descriptor.get("level", -1)) != index:
			errors.append("descriptor_level:%d expected:%d" % [int(descriptor.get("level", -1)), index])
		if int(descriptor.get("vertices_per_side", 0)) != 129:
			errors.append("descriptor_vertices:%d" % int(descriptor.get("vertices_per_side", 0)))
		var expected_spacing: float = 64.0 * float(1 << index)
		if absf(float(descriptor.get("spacing_m", 0.0)) - expected_spacing) > 0.000001:
			errors.append("descriptor_spacing:%.6f expected:%.6f" % [float(descriptor.get("spacing_m", 0.0)), expected_spacing])
		var height_image: Image = descriptor["height_image"] as Image
		var normal_image: Image = descriptor["normal_image"] as Image
		var slope_image: Image = descriptor["slope_deg_image"] as Image
		var curvature_image: Image = descriptor["curvature_image"] as Image
		var heatmap_image: Image = descriptor["debug_heatmap_image"] as Image
		var displacement_image: Image = descriptor["visual_displacement_image"] as Image
		if height_image.get_width() != 129 or height_image.get_height() != 129:
			errors.append("height_image:%dx%d" % [height_image.get_width(), height_image.get_height()])
		if normal_image.get_width() != 129 or normal_image.get_height() != 129:
			errors.append("normal_image:%dx%d" % [normal_image.get_width(), normal_image.get_height()])
		if slope_image.get_width() != 129 or slope_image.get_height() != 129:
			errors.append("slope_image:%dx%d" % [slope_image.get_width(), slope_image.get_height()])
		if curvature_image.get_width() != 129 or curvature_image.get_height() != 129:
			errors.append("curvature_image:%dx%d" % [curvature_image.get_width(), curvature_image.get_height()])
		if heatmap_image.get_width() != 129 or heatmap_image.get_height() != 129:
			errors.append("heatmap_image:%dx%d" % [heatmap_image.get_width(), heatmap_image.get_height()])
		if displacement_image.get_width() != 129 or displacement_image.get_height() != 129:
			errors.append("displacement_image:%dx%d" % [displacement_image.get_width(), displacement_image.get_height()])
		var slope_values: PackedFloat32Array = descriptor["slope_deg_values"] as PackedFloat32Array
		var curvature_values: PackedFloat32Array = descriptor["curvature_values"] as PackedFloat32Array
		var displacement_values: PackedFloat32Array = descriptor["visual_displacement_values"] as PackedFloat32Array
		if slope_values.size() != 129 * 129:
			errors.append("slope_values:%d" % slope_values.size())
		if curvature_values.size() != 129 * 129:
			errors.append("curvature_values:%d" % curvature_values.size())
		if displacement_values.size() != 129 * 129:
			errors.append("displacement_values:%d" % displacement_values.size())
		if absf(float(displacement_values[0])) > 0.000001:
			errors.append("edge_displacement:%.6f" % float(displacement_values[0]))


func _check_level_material(mesh_instance: MeshInstance3D, level: int, errors: Array[String]) -> void:
	if mesh_instance == null:
		errors.append("level_mesh_null:%d" % level)
		return
	var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material == null:
		errors.append("level_material_null:%d" % level)
		return
	var height_texture: Texture2D = material.get_shader_parameter("height_texture") as Texture2D
	var normal_texture: Texture2D = material.get_shader_parameter("normal_texture") as Texture2D
	if height_texture == null:
		errors.append("level_height_texture_null:%d" % level)
	elif height_texture.get_width() != 129 or height_texture.get_height() != 129:
		errors.append("level_height_texture_size:%d:%dx%d" % [level, height_texture.get_width(), height_texture.get_height()])
	if normal_texture == null:
		errors.append("level_normal_texture_null:%d" % level)
	elif normal_texture.get_width() != 129 or normal_texture.get_height() != 129:
		errors.append("level_normal_texture_size:%d:%dx%d" % [level, normal_texture.get_width(), normal_texture.get_height()])
	var normal_strength: float = float(material.get_shader_parameter("normal_strength"))
	if absf(normal_strength - 0.65) > 0.000001:
		errors.append("level_normal_strength:%d:%.6f" % [level, normal_strength])


func _report_and_quit(errors: Array[String]) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-far-clipmap-surface-material] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-far-clipmap-surface-material] status=pass")
	quit(0)
