class_name TerrainKernelGalleryScene
extends Node3D

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

@export var seed: int = 1337
@export_range(8, 36, 1) var target_tile_count: int = 36
@export_range(4, 32, 1) var scan_radius_regions: int = 18
@export_range(33, 129, 16) var vertices_per_tile_side: int = 65
@export_range(2, 12, 1) var gallery_columns: int = 6
@export var family_filter: String = ""
@export_range(1, 4, 1) var variants_per_kernel: int = 1
@export var sample_span_m: float = TerrainSettingsScript.REGION_SIZE_M * 0.42
@export var display_tile_size_m: float = 320.0
@export var display_gap_m: float = 90.0
@export var vertical_scale: float = 0.045
@export var label_height_m: float = 48.0
@export var auto_setup_on_ready: bool = true

var world: RefCounted
var selected_sites: Array[Dictionary] = []
var missing_kernel_ids: Array[String] = []
var errors: Array[String] = []
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment


func _ready() -> void:
	if auto_setup_on_ready:
		setup()


func setup() -> bool:
	clear_gallery()
	errors.clear()
	world = TerrainWorldScript.new()
	if not world.setup_procedural(seed):
		for error in world.errors:
			errors.append("world_setup:%s" % str(error))
		return false
	selected_sites = _select_kernel_sites()
	if selected_sites.is_empty():
		errors.append("no_kernel_sites_selected")
		return false
	_build_gallery_tiles()
	_add_light()
	_add_environment()
	_add_camera()
	return errors.is_empty()


func clear_gallery() -> void:
	for child in get_children():
		child.queue_free()
	world = null
	selected_sites.clear()
	missing_kernel_ids.clear()
	camera = null
	sun = null
	environment = null


func gallery_report() -> Dictionary:
	var kernels: Dictionary = {}
	var families: Dictionary = {}
	var palettes: Dictionary = {}
	for site_value in selected_sites:
		var site: Dictionary = site_value as Dictionary
		kernels[str(site.get("kernel_id", ""))] = true
		families[str(site.get("primary_family", ""))] = true
		palettes[str(site.get("palette", ""))] = true
	return {
		"status": "pass" if errors.is_empty() else "fail",
		"family_filter": family_filter,
		"variants_per_kernel": variants_per_kernel,
		"tile_count": selected_sites.size(),
		"unique_kernel_count": kernels.size(),
		"unique_family_count": families.size(),
		"unique_palette_count": palettes.size(),
		"missing_kernel_count": missing_kernel_ids.size(),
		"missing_kernel_ids": missing_kernel_ids.duplicate(),
		"errors": errors.duplicate(),
	}


func _select_kernel_sites() -> Array[Dictionary]:
	var expected_kernel_ids: Dictionary = {}
	for kernel_value in world.runtime_pack.kernels:
		var kernel: Dictionary = kernel_value as Dictionary
		var kernel_id: String = str(kernel.get("id", ""))
		if not kernel_id.is_empty() and _kernel_family_matches(kernel):
			expected_kernel_ids[kernel_id] = true

	var candidates_by_kernel: Dictionary = {}
	var used_region_keys: Dictionary = {}
	var region_size: float = world.region_size_m
	for rz in range(-scan_radius_regions, scan_radius_regions + 1):
		for rx in range(-scan_radius_regions, scan_radius_regions + 1):
			var center := Vector2((float(rx) + 0.5) * region_size, (float(rz) + 0.5) * region_size)
			var sample: Dictionary = world.sample(center.x, center.y)
			var palette: Dictionary = world.provider.decisions.region_info(rx, rz, world.seed)
			_add_kernel_candidate(candidates_by_kernel, expected_kernel_ids, used_region_keys, rx, rz, center, sample, palette, str(sample.get("kernel_a", "")), "a")
			_add_kernel_candidate(candidates_by_kernel, expected_kernel_ids, used_region_keys, rx, rz, center, sample, palette, str(sample.get("kernel_b", "")), "b")

	var selected: Array[Dictionary] = []
	var sorted_kernel_ids: Array = expected_kernel_ids.keys()
	sorted_kernel_ids.sort()
	for kernel_id_value in sorted_kernel_ids:
		if selected.size() >= target_tile_count:
			break
		var kernel_id: String = str(kernel_id_value)
		if not candidates_by_kernel.has(kernel_id):
			missing_kernel_ids.append(kernel_id)
			continue
		var candidates: Array = candidates_by_kernel[kernel_id] as Array
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["distance"]) != int(b["distance"]):
				return int(a["distance"]) < int(b["distance"])
			var ar: Vector2i = a["region"] as Vector2i
			var br: Vector2i = b["region"] as Vector2i
			if ar.y != br.y:
				return ar.y < br.y
			return ar.x < br.x
		)
		var variant_limit: int = min(max(1, variants_per_kernel), candidates.size())
		for variant_index in range(variant_limit):
			if selected.size() >= target_tile_count:
				break
			selected.append(candidates[variant_index] as Dictionary)
	if selected.size() < min(target_tile_count, expected_kernel_ids.size() * max(1, variants_per_kernel)):
		errors.append("kernel_gallery_tile_count:%d expected:%d filter:%s" % [
			selected.size(),
			min(target_tile_count, expected_kernel_ids.size() * max(1, variants_per_kernel)),
			family_filter,
		])
	return selected


func _kernel_family_matches(kernel: Dictionary) -> bool:
	if family_filter.strip_edges().is_empty():
		return true
	return str(kernel.get("family", "")) == family_filter


func _add_kernel_candidate(
	candidates_by_kernel: Dictionary,
	expected_kernel_ids: Dictionary,
	used_region_keys: Dictionary,
	rx: int,
	rz: int,
	center: Vector2,
	sample: Dictionary,
	palette: Dictionary,
	kernel_id: String,
	slot: String
) -> void:
	if kernel_id.is_empty():
		return
	if not expected_kernel_ids.has(kernel_id):
		return
	var region_key := "%d,%d:%s" % [rx, rz, slot]
	if used_region_keys.has(region_key):
		return
	used_region_keys[region_key] = true
	if not candidates_by_kernel.has(kernel_id):
		candidates_by_kernel[kernel_id] = []
	var families: Array = palette.get("families", []) as Array
	(candidates_by_kernel[kernel_id] as Array).append({
		"kernel_id": kernel_id,
		"kernel_slot": slot,
		"region": Vector2i(rx, rz),
		"center_m": center,
		"palette": str(palette.get("id", "")),
		"families": families.duplicate(),
		"primary_family": str(sample.get("primary_family", "unknown")),
		"secondary_family": str(sample.get("secondary_family", "unknown")),
		"distance": abs(rx) + abs(rz),
	})


func _build_gallery_tiles() -> void:
	var step_m: float = sample_span_m / float(max(1, vertices_per_tile_side - 1))
	var display_step_m: float = display_tile_size_m / float(max(1, vertices_per_tile_side - 1))
	for index in range(selected_sites.size()):
		var site: Dictionary = selected_sites[index] as Dictionary
		var center: Vector2 = site["center_m"] as Vector2
		var origin_x: float = center.x - sample_span_m * 0.5
		var origin_z: float = center.y - sample_span_m * 0.5
		var height: PackedFloat32Array = world.sample_height_grid(origin_x, origin_z, step_m, vertices_per_tile_side, vertices_per_tile_side)
		if height.size() != vertices_per_tile_side * vertices_per_tile_side:
			errors.append("tile_height_size:%d:%d" % [index, height.size()])
			continue
		var display_height: PackedFloat32Array = _normalized_display_heights(height)
		var colors: PackedColorArray = _tile_colors(display_height, site)
		var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(display_height, vertices_per_tile_side, display_step_m, colors)
		var mesh: ArrayMesh = TerrainMeshBuilderScript.build_array_mesh(arrays)
		var tile := MeshInstance3D.new()
		tile.name = "KernelTile_%02d_%s" % [index, str(site["kernel_id"])]
		tile.mesh = mesh
		tile.material_override = _vertex_color_material()
		tile.position = _tile_position(index)
		tile.set_meta("kernel_id", str(site["kernel_id"]))
		tile.set_meta("region", site["region"])
		add_child(tile)
		_add_label(index, site, tile.position)


func _normalized_display_heights(height: PackedFloat32Array) -> PackedFloat32Array:
	var min_height := INF
	var max_height := -INF
	for value in height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var midpoint: float = (min_height + max_height) * 0.5
	var result := PackedFloat32Array()
	result.resize(height.size())
	for index in range(height.size()):
		result[index] = (float(height[index]) - midpoint) * vertical_scale
	return result


func _tile_colors(display_height: PackedFloat32Array, site: Dictionary) -> PackedColorArray:
	var min_height := INF
	var max_height := -INF
	for value in display_height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var denom: float = max(0.0001, max_height - min_height)
	var family_tint: Color = _family_tint(str(site.get("primary_family", "")))
	var colors := PackedColorArray()
	colors.resize(display_height.size())
	for index in range(display_height.size()):
		var t: float = clampf((float(display_height[index]) - min_height) / denom, 0.0, 1.0)
		var ramp: Color = _elevation_ramp(t)
		colors[index] = ramp.lerp(family_tint, 0.18)
	return colors


func _elevation_ramp(t: float) -> Color:
	if t < 0.25:
		return Color(0.02, 0.03, 0.08).lerp(Color(0.06, 0.28, 0.62), t / 0.25)
	if t < 0.50:
		return Color(0.06, 0.28, 0.62).lerp(Color(0.12, 0.54, 0.24), (t - 0.25) / 0.25)
	if t < 0.75:
		return Color(0.12, 0.54, 0.24).lerp(Color(0.78, 0.64, 0.26), (t - 0.50) / 0.25)
	return Color(0.78, 0.64, 0.26).lerp(Color(0.98, 0.98, 0.96), (t - 0.75) / 0.25)


func _family_tint(family: String) -> Color:
	match family:
		"glacial":
			return Color(0.72, 0.88, 1.0)
		"volcanic":
			return Color(0.88, 0.30, 0.18)
		"desert":
			return Color(0.90, 0.73, 0.32)
		"coast":
			return Color(0.18, 0.58, 0.74)
		"rainforest":
			return Color(0.12, 0.58, 0.24)
		"mountain":
			return Color(0.62, 0.58, 0.54)
		"karst":
			return Color(0.60, 0.66, 0.48)
		"wetland":
			return Color(0.20, 0.44, 0.36)
		_:
			return Color(0.60, 0.62, 0.66)


func _tile_position(index: int) -> Vector3:
	var column: int = index % max(1, gallery_columns)
	var row: int = index / max(1, gallery_columns)
	var pitch: float = display_tile_size_m + display_gap_m
	var width: float = float(max(1, min(gallery_columns, selected_sites.size())) - 1) * pitch
	return Vector3(float(column) * pitch - width * 0.5, 0.0, float(row) * pitch)


func _add_label(index: int, site: Dictionary, position: Vector3) -> void:
	var label := Label3D.new()
	label.name = "KernelLabel_%02d" % index
	var region: Vector2i = site["region"] as Vector2i
	label.text = "%02d %s\n%s / %s\nregion %d,%d" % [
		index + 1,
		str(site["kernel_id"]),
		str(site["primary_family"]),
		str(site["palette"]),
		region.x,
		region.y,
	]
	label.position = position + Vector3(display_tile_size_m * 0.5, label_height_m, -display_gap_m * 0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 18
	label.modulate = Color(0.92, 0.94, 0.96)
	add_child(label)


func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	return material


func _add_light() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "KernelGallerySun"
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 1.0
	add_child(sun)


func _add_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.72)
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "KernelGalleryCamera"
	var rows: int = int(ceil(float(selected_sites.size()) / float(max(1, gallery_columns))))
	var center_z: float = float(max(0, rows - 1)) * (display_tile_size_m + display_gap_m) * 0.5
	var view_width: float = float(min(gallery_columns, selected_sites.size())) * (display_tile_size_m + display_gap_m)
	var view_depth: float = float(max(1, rows)) * (display_tile_size_m + display_gap_m)
	var distance: float = max(view_width, view_depth) * 1.05
	camera.far = max(10000.0, distance * 4.0)
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(
		Vector3(0.0, distance * 0.78, center_z + distance * 0.72),
		Vector3(0.0, 0.0, center_z),
		Vector3.UP
	)
