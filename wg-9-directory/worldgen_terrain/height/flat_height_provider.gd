class_name FlatHeightProvider
extends RefCounted

const SOURCE_MASK_NONE: int = 0

var height_m: float = 0.0


func setup(flat_height_m: float = 0.0) -> void:
	height_m = flat_height_m


func sample_height(_world_x: float, _world_z: float, _seed: int = 1337, _region_size_m: float = 32768.0) -> float:
	return height_m


func sample_height_grid(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int = 1337, region_size_m: float = 32768.0) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if (
		not is_finite(origin_x)
		or not is_finite(origin_z)
		or not is_finite(step_m)
		or step_m <= 0.0
		or count_x < 1
		or count_z < 1
		or not is_finite(region_size_m)
		or region_size_m <= 0.0
	):
		return values
	values.resize(count_x * count_z)
	var index := 0
	for z_index in range(count_z):
		var _world_z: float = origin_z + float(z_index) * step_m
		for x_index in range(count_x):
			var _world_x: float = origin_x + float(x_index) * step_m
			values[index] = sample_height(_world_x, _world_z, world_seed, region_size_m)
			index += 1
	return values


func sample(world_x: float, world_z: float, world_seed: int = 1337, region_size_m: float = 32768.0, _slope_step_m: float = 32.0) -> Dictionary:
	return {
		"world_x": world_x,
		"world_z": world_z,
		"height_m": height_m,
		"valid": true,
		"source_mask": SOURCE_MASK_NONE,
		"region_id": 0,
		"primary_family_id": 0,
		"primary_family": "flat",
		"secondary_family_id": 0,
		"secondary_family": "unknown",
		"kernel_a_id": 0,
		"kernel_a": "",
		"kernel_b_id": 0,
		"kernel_b": "",
		"blend_weight": 1.0,
		"secondary_blend_weight": 0.0,
		"macro_height_m": height_m,
		"kernel_relief_m": 0.0,
		"detail_height_m": 0.0,
		"valley_adjust_m": 0.0,
		"slope_hint": 0.0,
		"roughness_hint": 0.0,
		"confidence": 1.0,
		"source_confidence": 0.0,
		"source_resolution_m": 0.0,
		"primary_source_resolution_m": 0.0,
		"secondary_source_resolution_m": 0.0,
		"seed": world_seed,
		"region_size_m": region_size_m,
	}
