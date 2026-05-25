class_name TerrainMeshBuilder
extends RefCounted

static var _indices_cache: Dictionary = {}
static var _uvs_cache: Dictionary = {}
static var _layout_xz_cache: Dictionary = {}


static func build_indices(vertices_per_side: int) -> PackedInt32Array:
	if _indices_cache.has(vertices_per_side):
		return _indices_cache[vertices_per_side] as PackedInt32Array
	var quads: int = vertices_per_side - 1
	var indices := PackedInt32Array()
	indices.resize(quads * quads * 6)
	var write := 0
	for z in range(quads):
		var row: int = z * vertices_per_side
		var next_row: int = (z + 1) * vertices_per_side
		for x in range(quads):
			var a: int = row + x
			var b: int = row + x + 1
			var c: int = next_row + x
			var d: int = next_row + x + 1
			indices[write] = a
			indices[write + 1] = c
			indices[write + 2] = b
			indices[write + 3] = b
			indices[write + 4] = c
			indices[write + 5] = d
			write += 6
	_indices_cache[vertices_per_side] = indices
	return indices


static func build_uvs(vertices_per_side: int) -> PackedVector2Array:
	if _uvs_cache.has(vertices_per_side):
		return _uvs_cache[vertices_per_side] as PackedVector2Array
	var uvs := PackedVector2Array()
	uvs.resize(vertices_per_side * vertices_per_side)
	var write := 0
	var denom: float = float(vertices_per_side - 1)
	for z in range(vertices_per_side):
		for x in range(vertices_per_side):
			uvs[write] = Vector2(float(x) / denom, float(z) / denom)
			write += 1
	_uvs_cache[vertices_per_side] = uvs
	return uvs


static func build_layout_xz(vertices_per_side: int, step_m: float) -> PackedVector2Array:
	var key: String = _layout_xz_key(vertices_per_side, step_m)
	if _layout_xz_cache.has(key):
		return _layout_xz_cache[key] as PackedVector2Array
	var layout := PackedVector2Array()
	layout.resize(vertices_per_side * vertices_per_side)
	var write := 0
	for z in range(vertices_per_side):
		for x in range(vertices_per_side):
			layout[write] = Vector2(float(x) * step_m, float(z) * step_m)
			write += 1
	_layout_xz_cache[key] = layout
	return layout


static func _layout_xz_key(vertices_per_side: int, step_m: float) -> String:
	var step_bytes := PackedByteArray()
	step_bytes.resize(8)
	step_bytes.encode_double(0, step_m)
	return "%d:%s" % [vertices_per_side, step_bytes.hex_encode()]


static func build_vertices(height: PackedFloat32Array, vertices_per_side: int, step_m: float) -> PackedVector3Array:
	return build_vertices_from_layout(height, build_layout_xz(vertices_per_side, step_m))


static func build_vertices_from_layout(height: PackedFloat32Array, layout_xz: PackedVector2Array) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	vertices.resize(height.size())
	for index in range(height.size()):
		var layout: Vector2 = layout_xz[index]
		vertices[index] = Vector3(layout.x, float(height[index]), layout.y)
	return vertices


static func build_surface_arrays(
	height: PackedFloat32Array,
	vertices_per_side: int,
	step_m: float,
	colors: PackedColorArray = PackedColorArray(),
	skirt_depth_m: float = 0.0
) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = build_vertices(height, vertices_per_side, step_m)
	arrays[Mesh.ARRAY_NORMAL] = build_normals(height, vertices_per_side, step_m)
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = build_uvs(vertices_per_side)
	arrays[Mesh.ARRAY_INDEX] = build_indices(vertices_per_side)
	if skirt_depth_m > 0.0:
		return append_skirts_to_surface_arrays(arrays, vertices_per_side, skirt_depth_m)
	return arrays


static func append_skirts_to_surface_arrays(arrays: Array, vertices_per_side: int, skirt_depth_m: float) -> Array:
	if skirt_depth_m <= 0.0:
		return arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var top_vertex_count: int = vertices_per_side * vertices_per_side
	if vertices.size() != top_vertex_count or normals.size() != top_vertex_count or uvs.size() != top_vertex_count:
		return arrays
	var perimeter: PackedInt32Array = build_perimeter_indices(vertices_per_side)
	var skirt_count: int = perimeter.size()
	var new_vertices := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_uvs := PackedVector2Array()
	new_vertices.resize(top_vertex_count + skirt_count)
	new_normals.resize(top_vertex_count + skirt_count)
	new_uvs.resize(top_vertex_count + skirt_count)
	for index in range(top_vertex_count):
		new_vertices[index] = vertices[index]
		new_normals[index] = normals[index]
		new_uvs[index] = uvs[index]
	for skirt_index in range(skirt_count):
		var top_index: int = perimeter[skirt_index]
		var vertex: Vector3 = vertices[top_index]
		new_vertices[top_vertex_count + skirt_index] = Vector3(vertex.x, vertex.y - skirt_depth_m, vertex.z)
		new_normals[top_vertex_count + skirt_index] = normals[top_index]
		new_uvs[top_vertex_count + skirt_index] = uvs[top_index]
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size() + skirt_count * 6)
	for index in range(indices.size()):
		new_indices[index] = indices[index]
	var write: int = indices.size()
	for skirt_index in range(skirt_count):
		var next_skirt_index: int = (skirt_index + 1) % skirt_count
		var top_a: int = perimeter[skirt_index]
		var top_b: int = perimeter[next_skirt_index]
		var bottom_a: int = top_vertex_count + skirt_index
		var bottom_b: int = top_vertex_count + next_skirt_index
		new_indices[write] = top_a
		new_indices[write + 1] = bottom_a
		new_indices[write + 2] = top_b
		new_indices[write + 3] = top_b
		new_indices[write + 4] = bottom_a
		new_indices[write + 5] = bottom_b
		write += 6
	var new_arrays: Array = arrays.duplicate()
	new_arrays[Mesh.ARRAY_VERTEX] = new_vertices
	new_arrays[Mesh.ARRAY_NORMAL] = new_normals
	new_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
	new_arrays[Mesh.ARRAY_INDEX] = new_indices
	if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		if colors.size() == top_vertex_count:
			var new_colors := PackedColorArray()
			new_colors.resize(top_vertex_count + skirt_count)
			for index in range(top_vertex_count):
				new_colors[index] = colors[index]
			for skirt_index in range(skirt_count):
				new_colors[top_vertex_count + skirt_index] = colors[perimeter[skirt_index]]
			new_arrays[Mesh.ARRAY_COLOR] = new_colors
	return new_arrays


static func build_perimeter_indices(vertices_per_side: int) -> PackedInt32Array:
	var count: int = max(2, vertices_per_side)
	var perimeter := PackedInt32Array()
	perimeter.resize(count * 4 - 4)
	var write := 0
	for x in range(count):
		perimeter[write] = x
		write += 1
	for z in range(1, count):
		perimeter[write] = z * count + count - 1
		write += 1
	var last_row: int = (count - 1) * count
	for x in range(count - 2, -1, -1):
		perimeter[write] = last_row + x
		write += 1
	for z in range(count - 2, 0, -1):
		perimeter[write] = z * count
		write += 1
	return perimeter


static func build_array_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_normals(height: PackedFloat32Array, vertices_per_side: int, step_m: float) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices_per_side * vertices_per_side)
	for z in range(vertices_per_side):
		for x in range(vertices_per_side):
			var dx: float = _gradient_x(height, vertices_per_side, x, z, step_m)
			var dz: float = _gradient_z(height, vertices_per_side, x, z, step_m)
			normals[z * vertices_per_side + x] = Vector3(-dx, 1.0, -dz).normalized()
	return normals


static func build_gray_hillshade_colors(height: PackedFloat32Array, vertices_per_side: int, step_m: float) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(height.size())
	if height.is_empty():
		return colors
	var light_dir := Vector3(-0.42, 0.74, -0.52).normalized()
	var radius: int = 3 if vertices_per_side >= 65 else 2
	for z in range(vertices_per_side):
		for x in range(vertices_per_side):
			var index: int = z * vertices_per_side + x
			var compressed_height: float = 0.5 + atan(float(height[index]) / 1800.0) / PI
			var normal: Vector3 = _wide_review_normal(height, vertices_per_side, x, z, step_m, radius)
			var review_normal := Vector3(normal.x * 5.0, normal.y, normal.z * 5.0).normalized()
			var lambert: float = review_normal.dot(light_dir) * 0.5 + 0.5
			var slope_shadow: float = clampf((1.0 - review_normal.y) * 1.05, 0.0, 0.30)
			var shade: float = clampf(0.16 + lambert * 0.58 + compressed_height * 0.20 - slope_shadow, 0.09, 0.94)
			colors[index] = Color(shade, shade, shade)
	return colors


static func _wide_review_normal(height: PackedFloat32Array, vertices_per_side: int, x: int, z: int, step_m: float, radius: int) -> Vector3:
	var x0: int = max(0, x - radius)
	var x1: int = min(vertices_per_side - 1, x + radius)
	var z0: int = max(0, z - radius)
	var z1: int = min(vertices_per_side - 1, z + radius)
	var dx_denom: float = max(0.000001, float(x1 - x0) * step_m)
	var dz_denom: float = max(0.000001, float(z1 - z0) * step_m)
	var dx: float = (float(height[z * vertices_per_side + x1]) - float(height[z * vertices_per_side + x0])) / dx_denom
	var dz: float = (float(height[z1 * vertices_per_side + x]) - float(height[z0 * vertices_per_side + x])) / dz_denom
	return Vector3(-dx, 1.0, -dz).normalized()


static func _gradient_x(height: PackedFloat32Array, vertices_per_side: int, x: int, z: int, step_m: float) -> float:
	var row: int = z * vertices_per_side
	if x == 0:
		return (float(height[row + 1]) - float(height[row])) / step_m
	if x == vertices_per_side - 1:
		return (float(height[row + x]) - float(height[row + x - 1])) / step_m
	return (float(height[row + x + 1]) - float(height[row + x - 1])) / (step_m * 2.0)


static func _gradient_z(height: PackedFloat32Array, vertices_per_side: int, x: int, z: int, step_m: float) -> float:
	if z == 0:
		return (float(height[vertices_per_side + x]) - float(height[x])) / step_m
	if z == vertices_per_side - 1:
		var row: int = z * vertices_per_side
		var prev_row: int = (z - 1) * vertices_per_side
		return (float(height[row + x]) - float(height[prev_row + x])) / step_m
	return (float(height[(z + 1) * vertices_per_side + x]) - float(height[(z - 1) * vertices_per_side + x])) / (step_m * 2.0)
