class_name TerrainPreviewScene
extends Node3D

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")

@export var auto_setup_on_ready: bool = true
@export_enum("gray", "elevation_color", "chunk_id", "lod_ring", "height_bands", "seam", "family_palette", "hydrology") var debug_mode: String = TerrainWorldScript.DEBUG_GRAY
@export_range(17, 257, 16) var vertices_per_side: int = 65
@export_range(0, 4, 1) var preview_radius_chunks: int = 1
@export var seed: int = 1337
@export var use_composite_gray_preview: bool = true
@export var use_fast_gray_material: bool = false
@export var use_native_chunk_payloads: bool = false

var terrain: Node3D
var composite_gray: MeshInstance3D
var camera: Camera3D
var sun: DirectionalLight3D


func _ready() -> void:
	if auto_setup_on_ready:
		setup(debug_mode, vertices_per_side, preview_radius_chunks, seed)


func setup(debug_mode: String, vertices_per_side: int = 65, preview_radius_chunks: int = 2, p_seed: int = 1337) -> bool:
	clear_preview()
	self.debug_mode = debug_mode
	self.vertices_per_side = vertices_per_side
	self.preview_radius_chunks = preview_radius_chunks
	self.seed = p_seed
	terrain = TerrainWorldNodeScript.new()
	terrain.name = "TerrainWorldNode"
	terrain.auto_setup_on_ready = false
	terrain.vertices_per_side = vertices_per_side
	terrain.debug_mode = debug_mode
	terrain.use_fast_gray_material = use_fast_gray_material
	terrain.use_native_chunk_payloads = use_native_chunk_payloads
	add_child(terrain)
	if not terrain.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, p_seed):
		return false
	terrain.update_viewer(Vector2.ZERO)
	if not use_composite_gray_preview or debug_mode != TerrainWorldScript.DEBUG_GRAY:
		terrain.rebuild_nearby_for_preview(preview_radius_chunks)
	if use_composite_gray_preview:
		_build_composite_gray_preview(preview_radius_chunks)
	_add_light()
	_add_camera(preview_radius_chunks)
	return true


func clear_preview() -> void:
	for child in get_children():
		child.queue_free()
	terrain = null
	composite_gray = null
	camera = null
	sun = null


func apply_debug_mode(debug_mode: String) -> void:
	self.debug_mode = debug_mode
	terrain.apply_debug_mode(debug_mode)
	if composite_gray != null:
		composite_gray.visible = debug_mode == TerrainWorldScript.DEBUG_GRAY
		terrain.visible = debug_mode != TerrainWorldScript.DEBUG_GRAY
	if debug_mode != TerrainWorldScript.DEBUG_GRAY and terrain.built_chunk_count() == 0:
		terrain.rebuild_nearby_for_preview(preview_radius_chunks)


func _build_composite_gray_preview(radius_chunks: int) -> void:
	var chunks_per_side: int = radius_chunks * 2 + 1
	var composite_vertices_per_side: int = (vertices_per_side - 1) * chunks_per_side + 1
	var step_m: float = TerrainSettingsScript.CHUNK_SIZE_M / float(vertices_per_side - 1)
	var origin_chunk: int = -radius_chunks
	var origin_x: float = float(origin_chunk) * TerrainSettingsScript.CHUNK_SIZE_M
	var origin_z: float = float(origin_chunk) * TerrainSettingsScript.CHUNK_SIZE_M
	var height: PackedFloat32Array = terrain.world.provider.sample_height_grid(
		origin_x,
		origin_z,
		step_m,
		composite_vertices_per_side,
		composite_vertices_per_side,
		terrain.world.seed,
		terrain.world.region_size_m
	)
	var normals: PackedVector3Array = TerrainMeshBuilderScript.build_normals(height, composite_vertices_per_side, step_m)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = TerrainMeshBuilderScript.build_vertices(height, composite_vertices_per_side, step_m)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = TerrainMeshBuilderScript.build_gray_hillshade_colors(height, composite_vertices_per_side, step_m)
	arrays[Mesh.ARRAY_TEX_UV] = TerrainMeshBuilderScript.build_uvs(composite_vertices_per_side)
	arrays[Mesh.ARRAY_INDEX] = TerrainMeshBuilderScript.build_indices(composite_vertices_per_side)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	composite_gray = MeshInstance3D.new()
	composite_gray.name = "CompositeGrayPreview"
	composite_gray.position = Vector3(origin_x, 0.0, origin_z)
	composite_gray.mesh = mesh
	composite_gray.visible = debug_mode == TerrainWorldScript.DEBUG_GRAY
	composite_gray.material_override = _composite_gray_material()
	composite_gray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(composite_gray)
	terrain.visible = debug_mode != TerrainWorldScript.DEBUG_GRAY


func _composite_gray_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	return material


func _add_light() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.light_energy = 2.8
	sun.rotation_degrees = Vector3(-48.0, -36.0, 0.0)
	add_child(sun)


func _add_camera(preview_radius_chunks: int) -> void:
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.current = true
	camera.fov = 42.0
	var span: float = TerrainSettingsScript.CHUNK_SIZE_M * float(preview_radius_chunks * 2 + 1)
	camera.near = 1.0
	camera.far = 50000.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span * 0.86
	add_child(camera)
	var target_x: float = TerrainSettingsScript.CHUNK_SIZE_M * 0.5
	var target_z: float = TerrainSettingsScript.CHUNK_SIZE_M * 0.5
	var target_y: float = terrain.world.sample_height(target_x, target_z)
	var target := Vector3(target_x, target_y, target_z)
	camera.position = target + Vector3(span * 0.42, span * 0.86, span * 0.68)
	camera.look_at(target, Vector3.UP)
