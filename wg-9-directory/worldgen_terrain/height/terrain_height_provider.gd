class_name TerrainHeightProvider
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainHashScript := preload("res://worldgen_terrain/height/terrain_hash.gd")
const TerrainLandformProfileScript := preload("res://worldgen_terrain/height/terrain_landform_profile.gd")
const TerrainProviderDecisionsScript := preload("res://worldgen_terrain/height/terrain_provider_decisions.gd")
const TerrainWorldFactsScript := preload("res://worldgen_terrain/height/terrain_world_facts.gd")

const SOURCE_MASK_CURRENT: int = 1 | 2 | 4 | 8
const FAMILY_IDS: Dictionary = {
	"unknown": 0,
	"mountain": 1,
	"glacial": 2,
	"badlands": 3,
	"desert": 4,
	"karst": 5,
	"coast": 6,
	"grassland": 7,
	"rainforest": 8,
	"volcanic": 9,
}

var pack: RefCounted
var decisions: RefCounted
var world_facts: RefCounted
var kernel_ids: Dictionary = {}
var use_native_prepared_height_grid: bool = false
var landform_profile_id: String = TerrainLandformProfileScript.BALANCED_CURRENT
var macro_relief_scale: float = 1.0
var kernel_relief_strength: float = 1.0
var mountain_boost: float = 1.0
var regional_scale_multiplier: float = 1.0
var valley_bias_strength: float = 1.0
var pass_corridor_strength: float = 0.0
var _native_backend: Object


func setup(runtime_pack: RefCounted) -> void:
	pack = runtime_pack
	decisions = TerrainProviderDecisionsScript.new()
	decisions.setup(pack)
	world_facts = TerrainWorldFactsScript.new()
	world_facts.setup(decisions)
	_index_kernel_ids()
	apply_landform_profile(TerrainLandformProfileScript.BALANCED_CURRENT)


func apply_landform_profile(profile: Variant) -> bool:
	var profile_data: Dictionary
	if profile is String:
		profile_data = TerrainLandformProfileScript.profile(str(profile))
	elif profile is Dictionary:
		profile_data = profile as Dictionary
	else:
		return false
	if profile_data.is_empty():
		return false
	var settings: Dictionary = profile_data.get("settings", {}) as Dictionary
	var next_macro: float = float(settings.get("macro_relief_scale", 1.0))
	var next_kernel: float = float(settings.get("kernel_relief_strength", 1.0))
	var next_mountain: float = float(settings.get("mountain_boost", 1.0))
	var next_scale: float = float(settings.get("regional_scale_multiplier", 1.0))
	var next_valley: float = float(settings.get("valley_bias_strength", 1.0))
	var next_pass: float = float(settings.get("pass_corridor_strength", 0.0))
	if not (
		is_finite(next_macro)
		and is_finite(next_kernel)
		and is_finite(next_mountain)
		and is_finite(next_scale)
		and is_finite(next_valley)
		and is_finite(next_pass)
	):
		return false
	if next_macro <= 0.0 or next_kernel <= 0.0 or next_mountain <= 0.0 or next_scale <= 0.0 or next_valley < 0.0 or next_pass < 0.0:
		return false
	landform_profile_id = str(profile_data.get("id", TerrainLandformProfileScript.BALANCED_CURRENT))
	macro_relief_scale = next_macro
	kernel_relief_strength = next_kernel
	mountain_boost = next_mountain
	regional_scale_multiplier = next_scale
	valley_bias_strength = next_valley
	pass_corridor_strength = next_pass
	return true


func landform_profile_report() -> Dictionary:
	return {
		"id": landform_profile_id,
		"schema": "worldgen9.landform_profile_state.v1",
		"settings": {
			"macro_relief_scale": macro_relief_scale,
			"kernel_relief_strength": kernel_relief_strength,
			"mountain_boost": mountain_boost,
			"regional_scale_multiplier": regional_scale_multiplier,
			"valley_bias_strength": valley_bias_strength,
			"pass_corridor_strength": pass_corridor_strength,
		},
		"native_prepared_grid_enabled": _can_use_native_prepared_grid(),
	}


func sample_height(world_x: float, world_z: float, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> float:
	return _sample_height_value(world_x, world_z, world_seed, region_size_m)


func sample_height_grid(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> PackedFloat32Array:
	if not _is_valid_grid_request(origin_x, origin_z, step_m, count_x, count_z, region_size_m):
		return PackedFloat32Array()
	if _grid_stays_in_one_base_region(origin_x, origin_z, step_m, count_x, count_z, region_size_m):
		return _sample_height_grid_fast_region(origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m)
	return _sample_height_grid_region_blocks(origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m)


func _sample_height_grid_region_blocks(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int, region_size_m: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(count_x * count_z)
	var z_start := 0
	while z_start < count_z:
		var z_end: int = _axis_region_block_end(origin_z, step_m, count_z, z_start, region_size_m)
		var block_count_z: int = z_end - z_start
		var block_origin_z: float = origin_z + float(z_start) * step_m
		var x_start := 0
		while x_start < count_x:
			var x_end: int = _axis_region_block_end(origin_x, step_m, count_x, x_start, region_size_m)
			var block_count_x: int = x_end - x_start
			var block_origin_x: float = origin_x + float(x_start) * step_m
			var block: PackedFloat32Array = _sample_height_grid_fast_region(
				block_origin_x,
				block_origin_z,
				step_m,
				block_count_x,
				block_count_z,
				world_seed,
				region_size_m
			)
			for block_z in range(block_count_z):
				var dst_index: int = (z_start + block_z) * count_x + x_start
				var src_index: int = block_z * block_count_x
				for block_x in range(block_count_x):
					values[dst_index + block_x] = float(block[src_index + block_x])
			x_start = x_end
		z_start = z_end
	return values


func _sample_height_grid_fast_region(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int, region_size_m: float) -> PackedFloat32Array:
	if _can_use_native_prepared_grid():
		var native: Dictionary = sample_height_grid_native_prepared(origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m)
		if native.get("status", "fail") == "pass":
			return native["values"] as PackedFloat32Array
	return _sample_height_grid_single_region(origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m)


func _axis_region_block_end(origin: float, step_m: float, count: int, start_index: int, region_size_m: float) -> int:
	var region: int = int(floor((origin + float(start_index) * step_m) / region_size_m))
	var index: int = start_index + 1
	while index < count:
		var sample_region: int = int(floor((origin + float(index) * step_m) / region_size_m))
		if sample_region != region:
			break
		index += 1
	return index


func _grid_stays_in_one_base_region(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, region_size_m: float) -> bool:
	var max_x: float = origin_x + step_m * float(count_x - 1)
	var max_z: float = origin_z + step_m * float(count_z - 1)
	return (
		int(floor(origin_x / region_size_m)) == _grid_end_region(max_x, count_x, region_size_m)
		and int(floor(origin_z / region_size_m)) == _grid_end_region(max_z, count_z, region_size_m)
	)


func _grid_end_region(end_value: float, count: int, region_size_m: float) -> int:
	if count <= 1:
		return int(floor(end_value / region_size_m))
	var scaled: float = end_value / region_size_m
	var rounded: float = round(scaled)
	if absf(scaled - rounded) <= 0.0000001:
		return int(rounded) - 1
	return int(floor(scaled))


func _sample_height_grid_single_region(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int, region_size_m: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(count_x * count_z)
	var base_rx: int = int(floor(origin_x / region_size_m))
	var base_rz: int = int(floor(origin_z / region_size_m))
	var corner_entries: Array[Dictionary] = _grid_corner_entries(base_rx, base_rz, world_seed, region_size_m)
	var index := 0
	for z_index in range(count_z):
		var z: float = origin_z + float(z_index) * step_m
		var gz: float = z / region_size_m
		var tz: float = TerrainHashScript.smoothstep_unit(gz - float(base_rz))
		var wz0: float = 1.0 - tz
		var wz1: float = tz
		for x_index in range(count_x):
			var x: float = origin_x + float(x_index) * step_m
			var gx: float = x / region_size_m
			var tx: float = TerrainHashScript.smoothstep_unit(gx - float(base_rx))
			var wx0: float = 1.0 - tx
			var corner_weights: Array[float] = [
				wx0 * wz0,
				tx * wz0,
				wx0 * wz1,
				tx * wz1,
			]
			values[index] = _sample_height_value_with_corner_entries(x, z, world_seed, corner_entries, corner_weights)
			index += 1
	return values


func sample_height_grid_native_prepared(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> Dictionary:
	if not _native_prepared_profile_supported():
		return {"status": "fail", "error": "native_profile_not_supported"}
	if not _native_backend_available():
		return {"status": "fail", "error": "native_backend_unavailable"}
	var prepared: Dictionary = native_prepared_height_grid_request(origin_x, origin_z, step_m, count_x, count_z, world_seed, region_size_m)
	if prepared.get("status", "fail") != "pass":
		return prepared
	var native: Dictionary = _native_backend.call(
		"sample_height_grid_prepared",
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		world_seed,
		region_size_m,
		int(prepared["base_rx"]),
		int(prepared["base_rz"]),
		prepared["corner_entries"] as Array
	) as Dictionary
	return native


func native_prepared_height_grid_request(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> Dictionary:
	if not _native_prepared_profile_supported():
		return {"status": "fail", "error": "native_profile_not_supported"}
	if not _is_valid_grid_request(origin_x, origin_z, step_m, count_x, count_z, region_size_m):
		return {"status": "fail", "error": "invalid_grid_request"}
	if not _grid_stays_in_one_base_region(origin_x, origin_z, step_m, count_x, count_z, region_size_m):
		return {"status": "fail", "error": "grid_crosses_region"}
	var base_rx: int = int(floor(origin_x / region_size_m))
	var base_rz: int = int(floor(origin_z / region_size_m))
	var corner_entries: Array[Dictionary] = _grid_corner_entries(base_rx, base_rz, world_seed, region_size_m)
	var corner_entries_untyped: Array = []
	for corner in corner_entries:
		corner_entries_untyped.append(corner)
	var validation: Dictionary = _validate_native_prepared_corner_entries(corner_entries_untyped)
	if validation.get("status", "fail") != "pass":
		return validation
	return {
		"status": "pass",
		"base_rx": base_rx,
		"base_rz": base_rz,
		"corner_entries": corner_entries_untyped,
	}


func _validate_native_prepared_corner_entries(corner_entries: Array) -> Dictionary:
	if corner_entries.size() != 4:
		return {"status": "fail", "error": "corner_count:%d expected:4" % corner_entries.size()}
	for corner_index in range(corner_entries.size()):
		var corner_variant: Variant = corner_entries[corner_index]
		if not (corner_variant is Dictionary):
			return {"status": "fail", "error": "corner_not_dictionary:%d" % corner_index}
		var corner: Dictionary = corner_variant as Dictionary
		var entries_variant: Variant = corner.get("entries", [])
		if not (entries_variant is Array):
			return {"status": "fail", "error": "entries_not_array:%d" % corner_index}
		var entries: Array = entries_variant as Array
		if entries.is_empty():
			return {"status": "fail", "error": "entries_empty:%d" % corner_index}
		for entry_index in range(entries.size()):
			var entry_variant: Variant = entries[entry_index]
			if not (entry_variant is Dictionary):
				return {"status": "fail", "error": "entry_not_dictionary:%d:%d" % [corner_index, entry_index]}
			var entry: Dictionary = entry_variant as Dictionary
			var rows: int = int(entry.get("rows", 0))
			var cols: int = int(entry.get("cols", 0))
			if rows < 2 or cols < 2:
				return {"status": "fail", "error": "entry_shape:%d:%d rows:%d cols:%d" % [corner_index, entry_index, rows, cols]}
			var values_variant: Variant = entry.get("values", PackedFloat32Array())
			if not (values_variant is PackedFloat32Array):
				return {"status": "fail", "error": "entry_values_not_float32:%d:%d" % [corner_index, entry_index]}
			var values: PackedFloat32Array = values_variant as PackedFloat32Array
			var expected_values: int = rows * cols
			if values.size() != expected_values:
				return {"status": "fail", "error": "entry_values_size:%d:%d size:%d expected:%d" % [corner_index, entry_index, values.size(), expected_values]}
			if float(entry.get("scale", 0.0)) <= 0.0:
				return {"status": "fail", "error": "entry_scale:%d:%d" % [corner_index, entry_index]}
	return {"status": "pass"}


func _native_backend_available() -> bool:
	if _native_backend != null:
		return true
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return false
	_native_backend = ClassDB.instantiate("Wg9TerrainNativeBackend")
	return _native_backend != null


func _can_use_native_prepared_grid() -> bool:
	return use_native_prepared_height_grid and _native_prepared_profile_supported()


func _native_prepared_profile_supported() -> bool:
	return _landform_profile_is_native_neutral()


func _landform_profile_is_native_neutral() -> bool:
	return (
		absf(macro_relief_scale - 1.0) <= 0.000001
		and absf(kernel_relief_strength - 1.0) <= 0.000001
		and absf(mountain_boost - 1.0) <= 0.000001
		and absf(regional_scale_multiplier - 1.0) <= 0.000001
		and absf(valley_bias_strength - 1.0) <= 0.000001
		and absf(pass_corridor_strength) <= 0.000001
	)


func _is_valid_grid_request(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, region_size_m: float) -> bool:
	return (
		is_finite(origin_x)
		and is_finite(origin_z)
		and is_finite(step_m)
		and step_m > 0.0
		and count_x >= 1
		and count_z >= 1
		and is_finite(region_size_m)
		and region_size_m > 0.0
	)


func _grid_corner_entries(base_rx: int, base_rz: int, world_seed: int, region_size_m: float) -> Array[Dictionary]:
	var corner_defs: Array[Vector2i] = [
		Vector2i(base_rx, base_rz),
		Vector2i(base_rx + 1, base_rz),
		Vector2i(base_rx, base_rz + 1),
		Vector2i(base_rx + 1, base_rz + 1),
	]
	var corners: Array[Dictionary] = []
	for coord in corner_defs:
		var palette: Dictionary = decisions.region_info(coord.x, coord.y, world_seed)
		var biases: Array = decisions.family_biases(coord.x, coord.y, world_seed)
		var families: Array = palette["families"] as Array
		var entries: Array[Dictionary] = []
		for index in range(families.size()):
			var family: String = str(families[index])
			var kernel: Dictionary = decisions.kernel_for_family(family, coord.x, coord.y, world_seed)
			if kernel.is_empty():
				continue
			var kernel_id: String = str(kernel.get("id", ""))
			var loaded: Dictionary = pack.load_kernel_normalized_by_id(kernel_id)
			if loaded.get("status") != "pass":
				continue
			var normalized: Dictionary = loaded["normalized"] as Dictionary
			var shape: Array = normalized["shape"] as Array
			var transform: Dictionary = decisions.kernel_transform(kernel_id, coord.x, coord.y, world_seed, region_size_m)
			var family_params: Dictionary = pack.families.get(family, {}) as Dictionary
			var moderation: float = decisions.kernel_runtime_moderation(float((kernel.get("stats", {}) as Dictionary).get("slope_p95_deg", 0.0)))
			entries.append({
				"bias": float(biases[index]),
				"family": family,
				"detail_seed": world_seed + TerrainHashScript.stable_hash([family]) % 1000,
				"runtime_weight": float(family_params.get("runtime_weight", 1.0)),
				"moderation": moderation,
				"relief_scale_m": float(family_params.get("relief_scale_m", 0.0)),
				"detail_scale_m": float(family_params.get("detail_scale_m", 0.0)),
				"values": normalized["values"] as PackedFloat32Array,
				"rows": int(shape[0]),
				"cols": int(shape[1]),
				"scale_multiplier": float(transform["scale_multiplier"]),
				"scale": float(transform["world_scale_m"]),
				"angle_i": int(transform["rotation_quadrants"]),
				"offset_u": float(transform["offset_u"]),
				"offset_v": float(transform["offset_v"]),
			})
		corners.append({"entries": entries})
	return corners


func sample(world_x: float, world_z: float, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M, slope_step_m: float = 32.0) -> Dictionary:
	var layers: Dictionary = sample_layers(world_x, world_z, world_seed, region_size_m)
	var pass_hint: Dictionary = sample_pass_corridor_hint(world_x, world_z, world_seed, region_size_m)
	var primary_info: Dictionary = primary_families(world_x, world_z, world_seed, region_size_m)
	var primary: String = str(primary_info["primary_family"])
	var secondary: String = str(primary_info["secondary_family"])
	var primary_weight: float = float(primary_info["primary_weight"])
	var secondary_weight: float = float(primary_info["secondary_weight"])
	var kernel_a: String = kernel_id_for_point(primary, world_x, world_z, world_seed, region_size_m)
	var kernel_b: String = kernel_id_for_point(secondary, world_x, world_z, world_seed, region_size_m)
	var primary_resolution_m: float = source_resolution_for_kernel(kernel_a)
	var secondary_resolution_m: float = source_resolution_for_kernel(kernel_b)
	var explained_weight: float = clampf(primary_weight + secondary_weight, 0.0, 1.0)
	return {
		"world_x": world_x,
		"world_z": world_z,
		"height_m": float(layers["height"]),
		"valid": true,
		"source_mask": SOURCE_MASK_CURRENT,
		"region_id": int(primary_info["region_id"]),
		"primary_family_id": int(FAMILY_IDS.get(primary, 0)),
		"primary_family": primary,
		"secondary_family_id": int(FAMILY_IDS.get(secondary, 0)),
		"secondary_family": secondary,
		"kernel_a_id": int(kernel_ids.get(kernel_a, 0)),
		"kernel_a": kernel_a,
		"kernel_b_id": int(kernel_ids.get(kernel_b, 0)),
		"kernel_b": kernel_b,
		"blend_weight": primary_weight,
		"secondary_blend_weight": secondary_weight,
		"macro_height_m": float(layers["macro"]),
		"kernel_relief_m": float(layers["relief"]),
		"detail_height_m": float(layers["detail"]),
		"valley_adjust_m": float(layers["valley"]),
		"pass_corridor_hint": float(pass_hint.get("corridor_strength", 0.0)),
		"pass_corridor_id": str(pass_hint.get("corridor_id", "")),
		"slope_hint": slope_hint(world_x, world_z, world_seed, region_size_m, slope_step_m),
		"roughness_hint": abs(float(layers["detail"])),
		"confidence": clampf(primary_weight, 0.0, 1.0),
		"source_confidence": explained_weight,
		"source_resolution_m": _weighted_resolution(primary_resolution_m, primary_weight, secondary_resolution_m, secondary_weight),
		"primary_source_resolution_m": primary_resolution_m,
		"secondary_source_resolution_m": secondary_resolution_m,
		"landform_profile": landform_profile_id,
	}


func sample_layers(x: float, z: float, world_seed: int, region_size_m: float) -> Dictionary:
	var layers: Dictionary = _sample_layer_values(x, z, world_seed, region_size_m)
	layers["region"] = f32(palette_weights(x, z, world_seed, region_size_m)["palette_id"])
	layers["pass_corridor"] = f32(sample_pass_corridor_hint(x, z, world_seed, region_size_m).get("corridor_strength", 0.0))
	return layers


func pass_corridor_facts_for_region(rx: int, rz: int, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> Dictionary:
	if world_facts == null:
		return {"status": "fail", "error": "world_facts_not_setup"}
	return world_facts.call("pass_corridor_facts_for_region", rx, rz, world_seed, region_size_m) as Dictionary


func sample_pass_corridor_hint(x: float, z: float, world_seed: int = 1337, region_size_m: float = TerrainSettingsScript.REGION_SIZE_M) -> Dictionary:
	if world_facts == null:
		return {"status": "fail", "error": "world_facts_not_setup"}
	return world_facts.call("sample_pass_corridor_hint", x, z, world_seed, region_size_m) as Dictionary


func _sample_height_value(x: float, z: float, world_seed: int, region_size_m: float) -> float:
	return f32(float(_sample_layer_values(x, z, world_seed, region_size_m)["height"]))


func _sample_height_value_with_corner_entries(x: float, z: float, world_seed: int, corner_entries: Array[Dictionary], corner_weights: Array[float]) -> float:
	var sample_x: float = _scaled_coord(x)
	var sample_z: float = _scaled_coord(z)
	var profile_region_size_m: float = _profile_region_size_from_entries(corner_entries)
	var continent: float = TerrainHashScript.fbm(sample_x, sample_z, 52000.0, world_seed + 3, 4)
	var upland: float = TerrainHashScript.smoothstep_unit((continent + 0.2) / 0.75)
	var basin: float = 1.0 - TerrainHashScript.smoothstep_unit((continent + 0.05) / 0.55)
	var macro: float = (
		continent * 560.0
		+ TerrainHashScript.fbm(sample_x, sample_z, 26000.0, world_seed, 4) * 430.0
		+ TerrainHashScript.fbm(sample_x + 2300.0, sample_z - 1100.0, 12000.0, world_seed + 11, 3) * 140.0
	)
	var ridge: float = ridged_noise(sample_x * 0.8 + sample_z * 0.15, sample_z * 0.65 - sample_x * 0.1, 18000.0, world_seed + 37, 3)
	macro += ridge * (190.0 + upland * 230.0)
	macro -= basin * 170.0
	macro *= macro_relief_scale

	var detail: float = 0.0
	var relief: float = 0.0
	for corner_index in range(corner_entries.size()):
		var corner_weight: float = float(corner_weights[corner_index])
		if corner_weight <= 0.00000001:
			continue
		var entries: Array = (corner_entries[corner_index] as Dictionary)["entries"] as Array
		for entry_value in entries:
			var entry: Dictionary = entry_value as Dictionary
			var weight: float = corner_weight * float(entry["bias"])
			var runtime_weight: float = float(entry["runtime_weight"])
			var moderation: float = float(entry["moderation"])
			var sampled: float = _sample_kernel_cached(entry, x, z, profile_region_size_m)
			relief += sampled * weight * runtime_weight * moderation * float(entry["relief_scale_m"]) * (0.58 + upland * 0.38) * kernel_relief_strength * _family_relief_boost(str(entry["family"]))
			detail += (
				TerrainHashScript.fbm(sample_x, sample_z, 3000.0, int(entry["detail_seed"]), 2)
				* weight
				* runtime_weight
				* moderation
				* float(entry["detail_scale_m"])
				* 0.82
			)

	var valleys: float = valley_mask(sample_x, sample_z, world_seed)
	var valley_cut: float = valleys * (110.0 + upland * 130.0) * valley_bias_strength
	var valley_floor_noise: float = TerrainHashScript.fbm(sample_x, sample_z, 4200.0, world_seed + 401, 2) * 24.0 * valleys
	return f32(macro + relief + detail - valley_cut + valley_floor_noise)


func _sample_kernel_cached(entry: Dictionary, x: float, z: float, profile_region_size_m: float = 0.0) -> float:
	var scale: float = float(entry["scale"])
	if profile_region_size_m > 0.0 and absf(regional_scale_multiplier - 1.0) > 0.000001:
		scale = profile_region_size_m * float(entry.get("scale_multiplier", 1.0))
	var u: float = x / scale
	var v: float = z / scale
	var angle_i: int = int(entry["angle_i"])
	if angle_i == 1:
		var old_u: float = u
		u = v
		v = -old_u
	elif angle_i == 2:
		u = -u
		v = -v
	elif angle_i == 3:
		var old_u3: float = u
		u = -v
		v = old_u3
	u += float(entry["offset_u"])
	v += float(entry["offset_v"])
	return bilinear_sample_values(
		entry["values"] as PackedFloat32Array,
		int(entry["rows"]),
		int(entry["cols"]),
		u,
		v
	)


func _sample_layer_values(x: float, z: float, world_seed: int, region_size_m: float) -> Dictionary:
	var sample_x: float = _scaled_coord(x)
	var sample_z: float = _scaled_coord(z)
	var profile_region_size_m: float = _profile_region_size(region_size_m)
	var continent: float = TerrainHashScript.fbm(sample_x, sample_z, 52000.0, world_seed + 3, 4)
	var upland: float = TerrainHashScript.smoothstep_unit((continent + 0.2) / 0.75)
	var basin: float = 1.0 - TerrainHashScript.smoothstep_unit((continent + 0.05) / 0.55)
	var macro: float = (
		continent * 560.0
		+ TerrainHashScript.fbm(sample_x, sample_z, 26000.0, world_seed, 4) * 430.0
		+ TerrainHashScript.fbm(sample_x + 2300.0, sample_z - 1100.0, 12000.0, world_seed + 11, 3) * 140.0
	)
	var ridge: float = ridged_noise(sample_x * 0.8 + sample_z * 0.15, sample_z * 0.65 - sample_x * 0.1, 18000.0, world_seed + 37, 3)
	macro += ridge * (190.0 + upland * 230.0)
	macro -= basin * 170.0
	macro *= macro_relief_scale

	var detail: float = 0.0
	var relief: float = 0.0
	var gx: float = x / region_size_m
	var gz: float = z / region_size_m
	var rx: int = int(floor(gx))
	var rz: int = int(floor(gz))
	var tx: float = TerrainHashScript.smoothstep_unit(gx - float(rx))
	var tz: float = TerrainHashScript.smoothstep_unit(gz - float(rz))
	var corner_defs: Array[Dictionary] = [
		{"rx": rx, "rz": rz, "weight": (1.0 - tx) * (1.0 - tz)},
		{"rx": rx + 1, "rz": rz, "weight": tx * (1.0 - tz)},
		{"rx": rx, "rz": rz + 1, "weight": (1.0 - tx) * tz},
		{"rx": rx + 1, "rz": rz + 1, "weight": tx * tz},
	]
	for corner in corner_defs:
		var crx: int = int(corner["rx"])
		var crz: int = int(corner["rz"])
		var corner_weight: float = float(corner["weight"])
		if corner_weight <= 0.00000001:
			continue
		var palette: Dictionary = decisions.region_info(crx, crz, world_seed)
		var biases: Array = decisions.family_biases(crx, crz, world_seed)
		var families: Array = palette["families"] as Array
		for index in range(families.size()):
			var family: String = str(families[index])
			var kernel: Dictionary = decisions.kernel_for_family(family, crx, crz, world_seed)
			if kernel.is_empty():
				continue
			var kernel_id: String = str(kernel.get("id", ""))
			var sampled: float = sample_kernel_field(kernel_id, x, z, world_seed, crx, crz, profile_region_size_m)
			var family_params: Dictionary = pack.families.get(family, {}) as Dictionary
			var runtime_weight: float = float(family_params.get("runtime_weight", 1.0))
			var moderation: float = decisions.kernel_runtime_moderation(float((kernel.get("stats", {}) as Dictionary).get("slope_p95_deg", 0.0)))
			var weight: float = corner_weight * float(biases[index])
			relief += sampled * weight * runtime_weight * moderation * float(family_params.get("relief_scale_m", 0.0)) * (0.58 + upland * 0.38) * kernel_relief_strength * _family_relief_boost(family)
			detail += (
				TerrainHashScript.fbm(sample_x, sample_z, 3000.0, world_seed + TerrainHashScript.stable_hash([family]) % 1000, 2)
				* weight
				* runtime_weight
				* moderation
				* float(family_params.get("detail_scale_m", 0.0))
				* 0.82
			)

	var valleys: float = valley_mask(sample_x, sample_z, world_seed)
	var valley_cut: float = valleys * (110.0 + upland * 130.0) * valley_bias_strength
	var valley_floor_noise: float = TerrainHashScript.fbm(sample_x, sample_z, 4200.0, world_seed + 401, 2) * 24.0 * valleys
	var valley_layer: float = -valley_cut + valley_floor_noise
	var height: float = macro + relief + detail + valley_layer
	return {
		"height": f32(height),
		"macro": f32(macro),
		"relief": f32(relief),
		"detail": f32(detail),
		"valley": f32(valley_layer),
	}


func sample_kernel_field(kernel_id: String, x: float, z: float, world_seed: int, rx: int, rz: int, region_size_m: float) -> float:
	var loaded: Dictionary = pack.load_kernel_normalized_by_id(kernel_id)
	if loaded.get("status") != "pass":
		return 0.0
	var normalized: Dictionary = loaded["normalized"] as Dictionary
	var transform: Dictionary = decisions.kernel_transform(kernel_id, rx, rz, world_seed, region_size_m)
	var scale: float = float(transform["world_scale_m"])
	var angle_i: int = int(transform["rotation_quadrants"])
	var u: float = x / scale
	var v: float = z / scale
	if angle_i == 1:
		var old_u: float = u
		u = v
		v = -old_u
	elif angle_i == 2:
		u = -u
		v = -v
	elif angle_i == 3:
		var old_u3: float = u
		u = -v
		v = old_u3
	u += float(transform["offset_u"])
	v += float(transform["offset_v"])
	return bilinear_sample(normalized, u, v)


func bilinear_sample(array_info: Dictionary, u: float, v: float) -> float:
	var shape: Array = array_info["shape"] as Array
	var rows: int = int(shape[0])
	var cols: int = int(shape[1])
	var values: PackedFloat32Array = array_info["values"] as PackedFloat32Array
	return bilinear_sample_values(values, rows, cols, u, v)


func bilinear_sample_values(values: PackedFloat32Array, rows: int, cols: int, u: float, v: float) -> float:
	var mu: float = 1.0 - abs(fposmod(u, 2.0) - 1.0)
	var mv: float = 1.0 - abs(fposmod(v, 2.0) - 1.0)
	var px: float = mu * float(cols - 1)
	var py: float = mv * float(rows - 1)
	var x0: int = clampi(int(floor(px)), 0, cols - 1)
	var y0: int = clampi(int(floor(py)), 0, rows - 1)
	var x1: int = min(x0 + 1, cols - 1)
	var y1: int = min(y0 + 1, rows - 1)
	var tx: float = px - float(x0)
	var ty: float = py - float(y0)
	var a: float = float(values[y0 * cols + x0])
	var b: float = float(values[y0 * cols + x1])
	var c: float = float(values[y1 * cols + x0])
	var d: float = float(values[y1 * cols + x1])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func palette_weights(x: float, z: float, world_seed: int, region_size_m: float) -> Dictionary:
	var gx: float = x / region_size_m
	var gz: float = z / region_size_m
	var rx: int = int(floor(gx))
	var rz: int = int(floor(gz))
	var tx: float = TerrainHashScript.smoothstep_unit(gx - float(rx))
	var tz: float = TerrainHashScript.smoothstep_unit(gz - float(rz))
	var family_weights: Dictionary = {}
	var palette_id: float = 0.0
	var corner_defs: Array[Dictionary] = [
		{"rx": rx, "rz": rz, "weight": (1.0 - tx) * (1.0 - tz)},
		{"rx": rx + 1, "rz": rz, "weight": tx * (1.0 - tz)},
		{"rx": rx, "rz": rz + 1, "weight": (1.0 - tx) * tz},
		{"rx": rx + 1, "rz": rz + 1, "weight": tx * tz},
	]
	for corner in corner_defs:
		var crx: int = int(corner["rx"])
		var crz: int = int(corner["rz"])
		var local_weight: float = float(corner["weight"])
		var palette: Dictionary = decisions.region_info(crx, crz, world_seed)
		palette_id += local_weight * float(palette_index(str(palette["id"])))
		var biases: Array = decisions.family_biases(crx, crz, world_seed)
		var families: Array = palette["families"] as Array
		for index in range(families.size()):
			var family: String = str(families[index])
			family_weights[family] = float(family_weights.get(family, 0.0)) + local_weight * float(biases[index])

	var total: float = 0.0
	for value in family_weights.values():
		total += float(value)
	total = max(0.000001, total)
	for family in family_weights.keys():
		family_weights[family] = float(family_weights[family]) / total
	return {
		"weights": family_weights,
		"palette_id": palette_id,
	}


func primary_families(x: float, z: float, world_seed: int, region_size_m: float) -> Dictionary:
	var weight_info: Dictionary = palette_weights(x, z, world_seed, region_size_m)
	var weights: Dictionary = weight_info["weights"] as Dictionary
	var ranked: Array[Dictionary] = []
	for family in weights.keys():
		ranked.append({"family": str(family), "weight": float(weights[family])})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
	var primary: Dictionary = ranked[0] if not ranked.is_empty() else {"family": "unknown", "weight": 1.0}
	var secondary: Dictionary = ranked[1] if ranked.size() > 1 else {"family": "unknown", "weight": 0.0}
	return {
		"primary_family": str(primary["family"]),
		"secondary_family": str(secondary["family"]),
		"primary_weight": float(primary["weight"]),
		"secondary_weight": float(secondary["weight"]),
		"region_id": int(round(float(weight_info["palette_id"]))),
	}


func kernel_id_for_point(family: String, x: float, z: float, world_seed: int, region_size_m: float) -> String:
	var rx: int = int(floor(x / region_size_m))
	var rz: int = int(floor(z / region_size_m))
	var kernel: Dictionary = decisions.kernel_for_family(family, rx, rz, world_seed)
	return str(kernel.get("id", "")) if not kernel.is_empty() else ""


func source_resolution_for_kernel(kernel_id: String) -> float:
	if kernel_id.is_empty() or pack == null:
		return 0.0
	var kernel: Dictionary = pack.kernel_metadata_by_id(kernel_id)
	var source_sample: Dictionary = kernel.get("sample", {}) as Dictionary
	var resolution: float = float(source_sample.get("approx_sample_spacing_m", 0.0))
	if resolution > 0.0:
		return resolution
	return float(pack.runtime_defaults.get("height_resolution_m", 0.0))


func _weighted_resolution(a_resolution_m: float, a_weight: float, b_resolution_m: float, b_weight: float) -> float:
	var total_weight := 0.0
	var total_resolution := 0.0
	if a_resolution_m > 0.0 and a_weight > 0.0:
		total_weight += a_weight
		total_resolution += a_resolution_m * a_weight
	if b_resolution_m > 0.0 and b_weight > 0.0:
		total_weight += b_weight
		total_resolution += b_resolution_m * b_weight
	if total_weight <= 0.000001:
		return 0.0
	return total_resolution / total_weight


func slope_hint(x: float, z: float, world_seed: int, region_size_m: float, step_m: float) -> float:
	var h_x0: float = sample_height(x - step_m, z, world_seed, region_size_m)
	var h_x1: float = sample_height(x + step_m, z, world_seed, region_size_m)
	var h_z0: float = sample_height(x, z - step_m, world_seed, region_size_m)
	var h_z1: float = sample_height(x, z + step_m, world_seed, region_size_m)
	var gx: float = (h_x1 - h_x0) / max(0.000001, step_m * 2.0)
	var gz: float = (h_z1 - h_z0) / max(0.000001, step_m * 2.0)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


func ridged_noise(x: float, z: float, scale_m: float, world_seed: int, octaves: int = 4) -> float:
	var value: float = TerrainHashScript.fbm(x, z, scale_m, world_seed, octaves)
	var ridged: float = 1.0 - abs(value)
	return ridged * ridged * 2.0 - 1.0


func valley_mask(x: float, z: float, world_seed: int) -> float:
	var broad: float = ridged_noise(x + 5000.0, z - 3100.0, 18000.0, world_seed + 101, 4)
	var tributary: float = ridged_noise(x * 1.15 - z * 0.10, z * 0.9 + x * 0.08, 6200.0, world_seed + 211, 3)
	var combined: float = broad * 0.72 + tributary * 0.28
	return TerrainHashScript.smoothstep_unit((combined - 0.16) / 0.52)


func _scaled_coord(value: float) -> float:
	if absf(regional_scale_multiplier - 1.0) <= 0.000001:
		return value
	return value / regional_scale_multiplier


func _profile_region_size(region_size_m: float) -> float:
	return max(0.000001, region_size_m * regional_scale_multiplier)


func _profile_region_size_from_entries(corner_entries: Array[Dictionary]) -> float:
	if absf(regional_scale_multiplier - 1.0) <= 0.000001:
		return 0.0
	for corner_value in corner_entries:
		var corner: Dictionary = corner_value as Dictionary
		for entry_value in corner.get("entries", []) as Array:
			var entry: Dictionary = entry_value as Dictionary
			var multiplier: float = float(entry.get("scale_multiplier", 0.0))
			if multiplier > 0.0:
				return max(0.000001, float(entry.get("scale", 0.0)) / multiplier * regional_scale_multiplier)
	return 0.0


func _family_relief_boost(family: String) -> float:
	if absf(mountain_boost - 1.0) <= 0.000001:
		return 1.0
	if family == "mountain" or family == "glacial" or family == "volcanic":
		return mountain_boost
	return 1.0


func palette_index(name: String) -> int:
	for index in range(TerrainProviderDecisionsScript.REGION_PALETTES.size()):
		if str(TerrainProviderDecisionsScript.REGION_PALETTES[index]["id"]) == name:
			return index
	return 0


func f32(value: float) -> float:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)


func _index_kernel_ids() -> void:
	var ids: Array[String] = []
	for kernel in pack.kernels:
		ids.append(str((kernel as Dictionary).get("id", "")))
	ids.sort()
	kernel_ids.clear()
	for index in range(ids.size()):
		kernel_ids[ids[index]] = index + 1
