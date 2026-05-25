class_name HydrologySampler
extends RefCounted

const NO_RECEIVER := -1


func sample_window(
	world: RefCounted,
	center_xz: Vector2,
	span_m: float,
	grid_size: int = 97,
	padding_cells: int = 4
) -> Dictionary:
	if world == null:
		return {"status": "fail", "error": "world_null"}
	if not world.has_method("sample_height_grid"):
		return {"status": "fail", "error": "world_missing_sample_height_grid"}
	if not is_finite(span_m) or span_m <= 0.0:
		return {"status": "fail", "error": "invalid_span_m:%.6f" % span_m}
	if grid_size <= 1:
		return {"status": "fail", "error": "invalid_grid_size:%d" % grid_size}
	if padding_cells < 0:
		return {"status": "fail", "error": "invalid_padding_cells:%d" % padding_cells}
	var step_m: float = span_m / float(grid_size - 1)
	var count: int = grid_size + padding_cells * 2
	if count <= 1:
		return {"status": "fail", "error": "invalid_sample_count:%d" % count}
	var origin_x: float = center_xz.x - span_m * 0.5 - float(padding_cells) * step_m
	var origin_z: float = center_xz.y - span_m * 0.5 - float(padding_cells) * step_m
	var height: PackedFloat32Array = world.sample_height_grid(origin_x, origin_z, step_m, count, count)
	if height.size() != count * count:
		return {"status": "fail", "error": "height_grid_size:%d" % height.size()}
	var full: Dictionary = _analyze_full_grid(height, count, step_m)
	return _crop_result(full, count, grid_size, padding_cells, step_m, center_xz, span_m)


func _analyze_full_grid(height: PackedFloat32Array, count: int, step_m: float) -> Dictionary:
	var receiver := PackedInt32Array()
	receiver.resize(count * count)
	var slope_deg := PackedFloat32Array()
	slope_deg.resize(count * count)
	var flow_dir := PackedVector2Array()
	flow_dir.resize(count * count)
	var accumulation := PackedFloat32Array()
	accumulation.resize(count * count)
	for index in range(count * count):
		receiver[index] = NO_RECEIVER
		accumulation[index] = 1.0
		flow_dir[index] = Vector2.ZERO

	var offsets: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for z in range(1, count - 1):
		for x in range(1, count - 1):
			var index: int = z * count + x
			var current_height: float = float(height[index])
			var best_receiver: int = NO_RECEIVER
			var best_slope: float = 0.0
			var best_dir := Vector2.ZERO
			for offset in offsets:
				var nx: int = x + offset.x
				var nz: int = z + offset.y
				var nindex: int = nz * count + nx
				var distance: float = step_m if offset.x == 0 or offset.y == 0 else step_m * sqrt(2.0)
				var drop: float = current_height - float(height[nindex])
				var slope: float = drop / max(0.0001, distance)
				if slope > best_slope:
					best_slope = slope
					best_receiver = nindex
					best_dir = Vector2(float(offset.x), float(offset.y)).normalized()
			if best_receiver != NO_RECEIVER:
				receiver[index] = best_receiver
				slope_deg[index] = rad_to_deg(atan(best_slope))
				flow_dir[index] = best_dir

	var donor_count := PackedInt32Array()
	donor_count.resize(count * count)
	for index in range(count * count):
		var target: int = int(receiver[index])
		if target != NO_RECEIVER:
			donor_count[target] += 1
	var ready := PackedInt32Array()
	ready.resize(count * count)
	var ready_count := 0
	for index in range(count * count):
		if int(donor_count[index]) == 0:
			ready[ready_count] = index
			ready_count += 1
	var ready_head := 0
	while ready_head < ready_count:
		var index: int = int(ready[ready_head])
		ready_head += 1
		var target: int = int(receiver[index])
		if target == NO_RECEIVER:
			continue
		accumulation[target] += accumulation[index]
		donor_count[target] -= 1
		if int(donor_count[target]) == 0:
			ready[ready_count] = target
			ready_count += 1

	return {
		"height": height,
		"receiver": receiver,
		"slope_deg": slope_deg,
		"flow_dir": flow_dir,
		"accumulation": accumulation,
	}


func _crop_result(
	full: Dictionary,
	full_count: int,
	grid_size: int,
	padding_cells: int,
	step_m: float,
	center_xz: Vector2,
	span_m: float
) -> Dictionary:
	var height_full: PackedFloat32Array = full["height"] as PackedFloat32Array
	var slope_full: PackedFloat32Array = full["slope_deg"] as PackedFloat32Array
	var dir_full: PackedVector2Array = full["flow_dir"] as PackedVector2Array
	var accumulation_full: PackedFloat32Array = full["accumulation"] as PackedFloat32Array
	var height := PackedFloat32Array()
	var slope_deg := PackedFloat32Array()
	var flow_dir := PackedVector2Array()
	var accumulation := PackedFloat32Array()
	height.resize(grid_size * grid_size)
	slope_deg.resize(grid_size * grid_size)
	flow_dir.resize(grid_size * grid_size)
	accumulation.resize(grid_size * grid_size)
	var max_accumulation := 1.0
	var min_height := INF
	var max_height := -INF
	var out_index := 0
	for z in range(padding_cells, padding_cells + grid_size):
		for x in range(padding_cells, padding_cells + grid_size):
			var full_index: int = z * full_count + x
			var h: float = float(height_full[full_index])
			height[out_index] = h
			slope_deg[out_index] = float(slope_full[full_index])
			flow_dir[out_index] = dir_full[full_index]
			accumulation[out_index] = float(accumulation_full[full_index])
			max_accumulation = max(max_accumulation, float(accumulation[out_index]))
			min_height = min(min_height, h)
			max_height = max(max_height, h)
			out_index += 1

	var wetness := PackedFloat32Array()
	var channel_likelihood := PackedFloat32Array()
	wetness.resize(grid_size * grid_size)
	channel_likelihood.resize(grid_size * grid_size)
	var accumulation_scale: float = log(1.0 + float(full_count * full_count))
	for index in range(grid_size * grid_size):
		var normalized_accumulation: float = log(1.0 + float(accumulation[index])) / accumulation_scale
		var slope_factor: float = clampf(1.0 - float(slope_deg[index]) / 45.0, 0.05, 1.0)
		var raw_wetness: float = normalized_accumulation / max(0.12, tan(deg_to_rad(float(slope_deg[index]))) + 0.12)
		var raw_channel: float = normalized_accumulation * slope_factor
		wetness[index] = clampf(1.0 - exp(-raw_wetness * 0.45), 0.0, 1.0)
		channel_likelihood[index] = clampf(raw_channel, 0.0, 1.0)

	return {
		"status": "pass",
		"center_m": [center_xz.x, center_xz.y],
		"span_m": span_m,
		"grid_size": grid_size,
		"padding_cells": padding_cells,
		"step_m": step_m,
		"stable_fields": ["height", "slope_deg", "flow_dir"],
		"window_limited_fields": ["flow_accumulation", "wetness", "channel_likelihood"],
		"height": height,
		"slope_deg": slope_deg,
		"flow_dir": flow_dir,
		"flow_accumulation": accumulation,
		"wetness": wetness,
		"channel_likelihood": channel_likelihood,
		"height_min_m": min_height,
		"height_max_m": max_height,
		"max_flow_accumulation": max_accumulation,
	}
