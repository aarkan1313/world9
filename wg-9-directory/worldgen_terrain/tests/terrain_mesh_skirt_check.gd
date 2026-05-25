extends SceneTree

const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var count := 5
	var step_m := 2.0
	var skirt_depth_m := 3.5
	var height := PackedFloat32Array()
	height.resize(count * count)
	var colors := PackedColorArray()
	colors.resize(count * count)
	for z in range(count):
		for x in range(count):
			var index: int = z * count + x
			height[index] = float(x + z)
			colors[index] = Color(float(x) / float(count), float(z) / float(count), 0.25)
	var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(height, count, step_m, colors, skirt_depth_m)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var skirt_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var perimeter: PackedInt32Array = TerrainMeshBuilderScript.build_perimeter_indices(count)
	var expected_vertices: int = count * count + perimeter.size()
	var expected_indices: int = (count - 1) * (count - 1) * 6 + perimeter.size() * 6
	if vertices.size() != expected_vertices:
		errors.append("vertex_count:%d expected:%d" % [vertices.size(), expected_vertices])
	if normals.size() != expected_vertices:
		errors.append("normal_count:%d expected:%d" % [normals.size(), expected_vertices])
	if uvs.size() != expected_vertices:
		errors.append("uv_count:%d expected:%d" % [uvs.size(), expected_vertices])
	if skirt_colors.size() != expected_vertices:
		errors.append("color_count:%d expected:%d" % [skirt_colors.size(), expected_vertices])
	if indices.size() != expected_indices:
		errors.append("index_count:%d expected:%d" % [indices.size(), expected_indices])
	for skirt_index in range(perimeter.size()):
		var top_index: int = perimeter[skirt_index]
		var bottom_index: int = count * count + skirt_index
		var top: Vector3 = vertices[top_index]
		var bottom: Vector3 = vertices[bottom_index]
		if top.x != bottom.x or top.z != bottom.z:
			errors.append("skirt_xz:%d" % skirt_index)
			break
		if abs((top.y - skirt_depth_m) - bottom.y) > 0.0001:
			errors.append("skirt_y:%d top=%.3f bottom=%.3f" % [skirt_index, top.y, bottom.y])
			break
		if skirt_colors[bottom_index] != skirt_colors[top_index]:
			errors.append("skirt_color:%d" % skirt_index)
			break
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-terrain-mesh-skirt] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-terrain-mesh-skirt] status=pass top=%d skirt=%d indices=%d" % [count * count, perimeter.size(), indices.size()])
	return 0
