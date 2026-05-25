class_name TerrainSurfaceTextureBuilder
extends RefCounted


static func build_descriptor(
	height: PackedFloat32Array,
	vertices_per_side: int,
	spacing_m: float,
	include_debug_maps: bool = true,
	include_visual_displacement: bool = true,
	precomputed_normals: PackedVector3Array = PackedVector3Array(),
	precomputed_visual_displacement: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
	var count: int = max(2, vertices_per_side)
	if height.size() != count * count:
		return {
			"status": "fail",
			"error": "height_size:%d expected:%d" % [height.size(), count * count],
		}
	var height_range_info: Dictionary = height_range(height)
	var normals: PackedVector3Array = (
		precomputed_normals
		if precomputed_normals.size() == count * count
		else build_normals(height, count, spacing_m)
	)
	var descriptor: Dictionary = {
		"status": "pass",
		"vertices_per_side": count,
		"spacing_m": spacing_m,
		"height_min_m": float(height_range_info["min"]),
		"height_max_m": float(height_range_info["max"]),
		"height_range_m": float(height_range_info["max"]) - float(height_range_info["min"]),
		"height_image": build_height_image(height, count),
		"normal_image": build_normal_image(normals, count),
		"normal_values": normals,
	}
	if include_debug_maps:
		var slope_deg: PackedFloat32Array = build_slope_deg_values(height, count, spacing_m)
		var curvature: PackedFloat32Array = build_curvature_values(height, count, spacing_m)
		descriptor.merge({
			"slope_deg_image": build_float_image(slope_deg, count),
			"slope_deg_values": slope_deg,
			"curvature_image": build_float_image(curvature, count),
			"curvature_values": curvature,
			"debug_heatmap_image": build_debug_heatmap_image(height, slope_deg, curvature, count, height_range_info),
		})
	if include_visual_displacement:
		var displacement: PackedFloat32Array = (
			precomputed_visual_displacement
			if precomputed_visual_displacement.size() == count * count
			else build_visual_displacement_values(height, count, 1)
		)
		descriptor.merge({
			"visual_displacement_image": build_float_image(displacement, count),
			"visual_displacement_values": displacement,
			"visual_displacement_max_abs_m": max_abs_float(displacement),
			"visual_displacement_edge_lock_samples": 1,
		})
	return descriptor


static func build_height_image(height: PackedFloat32Array, vertices_per_side: int) -> Image:
	var count: int = max(2, vertices_per_side)
	return _rf_image_from_values(height, count)


static func build_normal_image(normals: PackedVector3Array, vertices_per_side: int) -> Image:
	var count: int = max(2, vertices_per_side)
	var data := PackedByteArray()
	data.resize(count * count * 12)
	for index in range(count * count):
		var normal: Vector3 = normals[index]
		var offset: int = index * 12
		data.encode_float(offset, normal.x * 0.5 + 0.5)
		data.encode_float(offset + 4, normal.y * 0.5 + 0.5)
		data.encode_float(offset + 8, normal.z * 0.5 + 0.5)
	return Image.create_from_data(count, count, false, Image.FORMAT_RGBF, data)


static func build_float_image(values: PackedFloat32Array, vertices_per_side: int) -> Image:
	var count: int = max(2, vertices_per_side)
	return _rf_image_from_values(values, count)


static func build_debug_heatmap_image(
	height: PackedFloat32Array,
	slope_deg: PackedFloat32Array,
	curvature: PackedFloat32Array,
	vertices_per_side: int,
	height_range_info: Dictionary
) -> Image:
	var count: int = max(2, vertices_per_side)
	var min_height: float = float(height_range_info.get("min", 0.0))
	var height_span: float = max(0.000001, float(height_range_info.get("max", 0.0)) - min_height)
	var max_abs_curvature: float = 0.000001
	for value in curvature:
		max_abs_curvature = max(max_abs_curvature, absf(float(value)))
	var data := PackedByteArray()
	data.resize(count * count * 12)
	for index in range(count * count):
		var height_t: float = clampf((float(height[index]) - min_height) / height_span, 0.0, 1.0)
		var slope_t: float = clampf(float(slope_deg[index]) / 45.0, 0.0, 1.0)
		var curve_t: float = clampf(absf(float(curvature[index])) / max_abs_curvature, 0.0, 1.0)
		var offset: int = index * 12
		data.encode_float(offset, slope_t)
		data.encode_float(offset + 4, curve_t)
		data.encode_float(offset + 8, height_t)
	return Image.create_from_data(count, count, false, Image.FORMAT_RGBF, data)


static func build_normals(height: PackedFloat32Array, vertices_per_side: int, spacing_m: float) -> PackedVector3Array:
	var count: int = max(2, vertices_per_side)
	var step_m: float = max(0.000001, spacing_m)
	var normals := PackedVector3Array()
	normals.resize(count * count)
	for z in range(count):
		for x in range(count):
			var dx: float = _gradient_x(height, count, x, z, step_m)
			var dz: float = _gradient_z(height, count, x, z, step_m)
			normals[z * count + x] = Vector3(-dx, 1.0, -dz).normalized()
	return normals


static func build_slope_deg_values(height: PackedFloat32Array, vertices_per_side: int, spacing_m: float) -> PackedFloat32Array:
	var count: int = max(2, vertices_per_side)
	var step_m: float = max(0.000001, spacing_m)
	var slopes := PackedFloat32Array()
	slopes.resize(count * count)
	for z in range(count):
		for x in range(count):
			var dx: float = _gradient_x(height, count, x, z, step_m)
			var dz: float = _gradient_z(height, count, x, z, step_m)
			slopes[z * count + x] = rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
	return slopes


static func build_curvature_values(height: PackedFloat32Array, vertices_per_side: int, spacing_m: float) -> PackedFloat32Array:
	var count: int = max(2, vertices_per_side)
	var step_sq: float = max(0.000001, spacing_m * spacing_m)
	var curvature := PackedFloat32Array()
	curvature.resize(count * count)
	for z in range(count):
		for x in range(count):
			var center: float = _height_at_clamped(height, count, x, z)
			var left: float = _height_at_clamped(height, count, x - 1, z)
			var right: float = _height_at_clamped(height, count, x + 1, z)
			var up: float = _height_at_clamped(height, count, x, z - 1)
			var down: float = _height_at_clamped(height, count, x, z + 1)
			curvature[z * count + x] = (left + right + up + down - center * 4.0) / step_sq
	return curvature


static func build_visual_displacement_values(height: PackedFloat32Array, vertices_per_side: int, edge_lock_samples: int = 1) -> PackedFloat32Array:
	var count: int = max(2, vertices_per_side)
	var edge_lock: int = max(1, edge_lock_samples)
	var displacement := PackedFloat32Array()
	displacement.resize(count * count)
	for z in range(count):
		for x in range(count):
			var center: float = _height_at_clamped(height, count, x, z)
			var total := 0.0
			var samples := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					total += _height_at_clamped(height, count, x + dx, z + dz)
					samples += 1
			var residual: float = center - total / float(samples)
			var distance_to_edge: int = min(min(x, z), min(count - 1 - x, count - 1 - z))
			var edge_fade: float = clampf(float(distance_to_edge) / float(edge_lock), 0.0, 1.0)
			displacement[z * count + x] = residual * edge_fade
	return displacement


static func max_abs_float(values: PackedFloat32Array) -> float:
	var max_abs := 0.0
	for value in values:
		max_abs = max(max_abs, absf(float(value)))
	return max_abs


static func height_range(height: PackedFloat32Array) -> Dictionary:
	if height.is_empty():
		return {"min": 0.0, "max": 0.0}
	var min_height := INF
	var max_height := -INF
	for value in height:
		var height_m: float = float(value)
		min_height = min(min_height, height_m)
		max_height = max(max_height, height_m)
	return {
		"min": min_height,
		"max": max_height,
	}


static func _rf_image_from_values(values: PackedFloat32Array, vertices_per_side: int) -> Image:
	var count: int = max(2, vertices_per_side)
	var data := PackedByteArray()
	data.resize(count * count * 4)
	for index in range(count * count):
		data.encode_float(index * 4, float(values[index]))
	return Image.create_from_data(count, count, false, Image.FORMAT_RF, data)


static func decode_normal_color(color: Color) -> Vector3:
	return Vector3(color.r * 2.0 - 1.0, color.g * 2.0 - 1.0, color.b * 2.0 - 1.0).normalized()


static func _height_at_clamped(height: PackedFloat32Array, count: int, x: int, z: int) -> float:
	var clamped_x: int = clampi(x, 0, count - 1)
	var clamped_z: int = clampi(z, 0, count - 1)
	return float(height[clamped_z * count + clamped_x])


static func _gradient_x(height: PackedFloat32Array, count: int, x: int, z: int, spacing_m: float) -> float:
	var row: int = z * count
	if x == 0:
		return (float(height[row + 1]) - float(height[row])) / spacing_m
	if x == count - 1:
		return (float(height[row + x]) - float(height[row + x - 1])) / spacing_m
	return (float(height[row + x + 1]) - float(height[row + x - 1])) / (spacing_m * 2.0)


static func _gradient_z(height: PackedFloat32Array, count: int, x: int, z: int, spacing_m: float) -> float:
	if z == 0:
		return (float(height[count + x]) - float(height[x])) / spacing_m
	if z == count - 1:
		var row: int = z * count
		var prev_row: int = (z - 1) * count
		return (float(height[row + x]) - float(height[prev_row + x])) / spacing_m
	return (float(height[(z + 1) * count + x]) - float(height[(z - 1) * count + x])) / (spacing_m * 2.0)
