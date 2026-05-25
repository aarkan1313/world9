extends SceneTree

const TerrainLocalDetailNodeScript := preload("res://worldgen_terrain/runtime/terrain_local_detail_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report_and_quit(errors)
		return

	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		errors.append("world_setup_failed:%s" % str(world.errors))
		_report_and_quit(errors)
		return

	var node: Node3D = TerrainLocalDetailNodeScript.new()
	node.enabled = true
	node.patch_size_m = 256.0
	node.vertices_per_side = 257
	node.radius_patches = 0
	node.max_active_patches = 1
	node.use_native_payloads = true
	node.use_native_workers = false
	node.use_surface_texture_material = true
	node.surface_texture_normal_strength = 0.75
	node.use_visual_displacement = true
	node.visual_displacement_strength = 0.50
	node.visual_displacement_limit_m = 3.25
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("node_setup_failed:%s" % str(node.errors))
		_report_and_quit(errors)
		return

	var report: Dictionary = node.update_viewer(Vector2(12.0, 80.0))
	if report.get("status", "fail") != "pass":
		errors.append("update_failed:%s" % str(report))
	if not node.patch_nodes.has("0,0"):
		errors.append("missing_patch_0_0")
	else:
		_check_material(node.patch_nodes["0,0"] as MeshInstance3D, errors)

	var stats: Dictionary = node.build_stats()
	if not bool(stats.get("use_surface_texture_material", false)):
		errors.append("stats_surface_material_disabled")
	if int(stats.get("last_surface_texture_ms", -1)) < 0:
		errors.append("stats_surface_texture_ms:%d" % int(stats.get("last_surface_texture_ms", -1)))
	node.queue_free()
	_check_material_without_displacement(world, errors)
	_report_and_quit(errors, stats)


func _check_material(patch: MeshInstance3D, errors: Array[String]) -> void:
	if patch == null:
		errors.append("patch_null")
		return
	var material: ShaderMaterial = patch.material_override as ShaderMaterial
	if material == null:
		errors.append("material_null")
		return
	var height_texture: Texture2D = material.get_shader_parameter("height_texture") as Texture2D
	var normal_texture: Texture2D = material.get_shader_parameter("normal_texture") as Texture2D
	var displacement_texture: Texture2D = material.get_shader_parameter("visual_displacement_texture") as Texture2D
	if height_texture == null:
		errors.append("height_texture_null")
	elif height_texture.get_width() != 257 or height_texture.get_height() != 257:
		errors.append("height_texture_size:%dx%d" % [height_texture.get_width(), height_texture.get_height()])
	if normal_texture == null:
		errors.append("normal_texture_null")
	elif normal_texture.get_width() != 257 or normal_texture.get_height() != 257:
		errors.append("normal_texture_size:%dx%d" % [normal_texture.get_width(), normal_texture.get_height()])
	if displacement_texture == null:
		errors.append("displacement_texture_null")
	elif displacement_texture.get_width() != 257 or displacement_texture.get_height() != 257:
		errors.append("displacement_texture_size:%dx%d" % [displacement_texture.get_width(), displacement_texture.get_height()])
	var height_range_m: float = float(material.get_shader_parameter("height_range_m"))
	if height_range_m <= 0.0:
		errors.append("height_range_m:%.6f" % height_range_m)
	var normal_strength: float = float(material.get_shader_parameter("normal_strength"))
	if absf(normal_strength - 0.75) > 0.000001:
		errors.append("normal_strength:%.6f" % normal_strength)
	var displacement_strength: float = float(material.get_shader_parameter("visual_displacement_strength"))
	if absf(displacement_strength - 0.50) > 0.000001:
		errors.append("displacement_strength:%.6f" % displacement_strength)
	var displacement_limit: float = float(material.get_shader_parameter("visual_displacement_limit_m"))
	if absf(displacement_limit - 3.25) > 0.000001:
		errors.append("displacement_limit:%.6f" % displacement_limit)
	var displacement_max_abs: float = float(material.get_shader_parameter("visual_displacement_max_abs_m"))
	if displacement_max_abs < 0.0:
		errors.append("displacement_max_abs:%.6f" % displacement_max_abs)


func _check_material_without_displacement(world: RefCounted, errors: Array[String]) -> void:
	var node: Node3D = TerrainLocalDetailNodeScript.new()
	node.enabled = true
	node.patch_size_m = 16.0
	node.vertices_per_side = 17
	node.radius_patches = 0
	node.max_active_patches = 1
	node.use_native_payloads = true
	node.use_native_workers = false
	node.use_surface_texture_material = true
	node.use_visual_displacement = false
	get_root().add_child(node)
	if not node.setup(world):
		errors.append("no_displacement_setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	var report: Dictionary = node.update_viewer(Vector2(1.0, 1.0))
	if report.get("status", "fail") != "pass":
		errors.append("no_displacement_update_failed:%s" % str(report))
		node.queue_free()
		return
	if not node.patch_nodes.has("0,0"):
		errors.append("no_displacement_patch_missing")
		node.queue_free()
		return
	var patch: MeshInstance3D = node.patch_nodes["0,0"] as MeshInstance3D
	var material: ShaderMaterial = patch.material_override as ShaderMaterial
	if material == null:
		errors.append("no_displacement_material_null")
		node.queue_free()
		return
	var displacement_texture: Texture2D = material.get_shader_parameter("visual_displacement_texture") as Texture2D
	if displacement_texture == null:
		errors.append("no_displacement_texture_null")
	elif displacement_texture.get_width() != 1 or displacement_texture.get_height() != 1:
		errors.append("no_displacement_texture_size:%dx%d" % [displacement_texture.get_width(), displacement_texture.get_height()])
	var displacement_strength: float = float(material.get_shader_parameter("visual_displacement_strength"))
	if absf(displacement_strength) > 0.000001:
		errors.append("no_displacement_strength:%.6f" % displacement_strength)
	node.queue_free()


func _report_and_quit(errors: Array[String], stats: Dictionary = {}) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-local-detail-surface-material] status=fail errors=%d stats=%s" % [errors.size(), JSON.stringify(stats)])
		quit(1)
		return
	print("[wg9-local-detail-surface-material] status=pass stats=%s" % JSON.stringify(stats))
	quit(0)
