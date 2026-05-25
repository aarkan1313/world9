class_name TerrainProviderDecisions
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainHashScript := preload("res://worldgen_terrain/height/terrain_hash.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")

const REGION_PALETTES: Array[Dictionary] = [
	{"id": "alpine", "families": ["mountain", "glacial", "grassland"]},
	{"id": "drylands", "families": ["badlands", "desert", "karst"]},
	{"id": "humid_hills", "families": ["rainforest", "mountain", "grassland"]},
	{"id": "volcanic_coast", "families": ["volcanic", "coast", "rainforest"]},
	{"id": "coastal_ridges", "families": ["coast", "mountain", "glacial"]},
	{"id": "open_steppe", "families": ["grassland", "badlands", "desert"]},
]

const PALETTE_COMPATIBILITY: Dictionary = {
	"alpine": ["coastal_ridges", "humid_hills", "open_steppe"],
	"drylands": ["open_steppe", "volcanic_coast", "coastal_ridges"],
	"humid_hills": ["alpine", "volcanic_coast", "coastal_ridges"],
	"volcanic_coast": ["coastal_ridges", "humid_hills", "drylands"],
	"coastal_ridges": ["alpine", "volcanic_coast", "humid_hills"],
	"open_steppe": ["drylands", "alpine", "coastal_ridges"],
}

var pack: RefCounted
var kernels_by_family: Dictionary = {}


func setup(runtime_pack: RefCounted) -> void:
	pack = runtime_pack
	_index_kernels()


func decision(world_x: float, world_z: float, world_seed: int, region_size_m: float) -> Dictionary:
	var gx: float = world_x / region_size_m
	var gz: float = world_z / region_size_m
	var rx: int = int(floor(gx))
	var rz: int = int(floor(gz))
	var frac_x: float = gx - float(rx)
	var frac_z: float = gz - float(rz)
	var tx: float = TerrainHashScript.smoothstep_unit(frac_x)
	var tz: float = TerrainHashScript.smoothstep_unit(frac_z)
	var corner_defs: Array[Dictionary] = [
		{"rx": rx, "rz": rz, "weight": (1.0 - tx) * (1.0 - tz)},
		{"rx": rx + 1, "rz": rz, "weight": tx * (1.0 - tz)},
		{"rx": rx, "rz": rz + 1, "weight": (1.0 - tx) * tz},
		{"rx": rx + 1, "rz": rz + 1, "weight": tx * tz},
	]
	var corners: Array[Dictionary] = []
	for corner_def in corner_defs:
		corners.append(_corner_decision(corner_def, world_seed, region_size_m))

	var weight_sum: float = 0.0
	for corner in corners:
		weight_sum += float(corner["corner_weight"])

	return {
		"world_x": world_x,
		"world_z": world_z,
		"base_region": [rx, rz],
		"region_fraction": [frac_x, frac_z],
		"smooth_fraction": [tx, tz],
		"corner_weight_sum": weight_sum,
		"corners": corners,
	}


func _corner_decision(corner_def: Dictionary, world_seed: int, region_size_m: float) -> Dictionary:
	var rx: int = int(corner_def["rx"])
	var rz: int = int(corner_def["rz"])
	var corner_weight: float = float(corner_def["weight"])
	var palette := region_info(rx, rz, world_seed)
	var biases := family_biases(rx, rz, world_seed)
	var entries: Array[Dictionary] = []
	var families: Array = palette["families"] as Array
	for index in range(families.size()):
		var family: String = str(families[index])
		var bias: float = float(biases[index])
		var kernel := kernel_for_family(family, rx, rz, world_seed)
		if kernel.is_empty():
			continue
		var kernel_id: String = str(kernel.get("id", ""))
		var family_params := pack.families.get(family, {}) as Dictionary
		var relief: float = float(family_params.get("relief_scale_m", 0.0))
		var detail: float = float(family_params.get("detail_scale_m", 0.0))
		var slope_p95: float = float((kernel.get("stats", {}) as Dictionary).get("slope_p95_deg", 0.0))
		var moderation: float = kernel_runtime_moderation(slope_p95)
		entries.append({
			"family": family,
			"family_bias": bias,
			"corner_family_weight": corner_weight * bias,
			"kernel_id": kernel_id,
			"kernel_slope_p95_deg": slope_p95,
			"kernel_moderation": moderation,
			"relief_scale_m": relief,
			"detail_scale_m": detail,
			"effective_relief_scale_m": relief * moderation,
			"effective_detail_scale_m": detail * moderation,
			"transform": kernel_transform(kernel_id, rx, rz, world_seed, region_size_m),
		})

	return {
		"region": [rx, rz],
		"province": [floor_div(rx, TerrainSettingsScript.PROVINCE_SIZE_REGIONS), floor_div(rz, TerrainSettingsScript.PROVINCE_SIZE_REGIONS)],
		"corner_salt": 0,
		"corner_weight": corner_weight,
		"palette": str(palette["id"]),
		"families": entries,
	}


func region_info(rx: int, rz: int, world_seed: int) -> Dictionary:
	var prx: int = floor_div(rx, TerrainSettingsScript.PROVINCE_SIZE_REGIONS)
	var prz: int = floor_div(rz, TerrainSettingsScript.PROVINCE_SIZE_REGIONS)
	var primary: String = province_palette_name(prx, prz, world_seed)
	var roll: int = TerrainHashScript.stable_hash(["palette_local", rx, rz, prx, prz, world_seed]) % 100
	if roll < 72:
		return palette_by_name(primary)
	if roll < 94:
		var compatible: Array = PALETTE_COMPATIBILITY[primary] as Array
		var compatible_index: int = TerrainHashScript.stable_hash(["palette_compatible", rx, rz, world_seed]) % compatible.size()
		return palette_by_name(str(compatible[compatible_index]))
	var rare_index: int = TerrainHashScript.stable_hash(["palette_rare", rx, rz, world_seed]) % REGION_PALETTES.size()
	return REGION_PALETTES[rare_index]


func province_palette_name(prx: int, prz: int, world_seed: int) -> String:
	var index: int = TerrainHashScript.stable_hash(["province_palette", prx, prz, world_seed]) % REGION_PALETTES.size()
	return str(REGION_PALETTES[index]["id"])


func palette_by_name(name: String) -> Dictionary:
	for palette in REGION_PALETTES:
		if str(palette["id"]) == name:
			return palette
	return {}


func family_biases(rx: int, rz: int, world_seed: int) -> Array[float]:
	var values: Array[float] = [0.55, 0.30, 0.15]
	var roll: int = TerrainHashScript.stable_hash(["family_roll", rx, rz, world_seed]) % values.size()
	if roll == 0:
		return values
	return values.slice(values.size() - roll, values.size()) + values.slice(0, values.size() - roll)


func kernel_for_family(family: String, rx: int, rz: int, world_seed: int) -> Dictionary:
	var kernels: Array = kernels_by_family.get(family, []) as Array
	if kernels.is_empty():
		kernels = kernels_by_family.get("uncategorized", []) as Array
	if kernels.is_empty():
		return {}
	var index: int = TerrainHashScript.stable_hash(["kernel", family, rx, rz, world_seed]) % kernels.size()
	return kernels[index] as Dictionary


func kernel_transform(kernel_id: String, rx: int, rz: int, world_seed: int, region_size_m: float) -> Dictionary:
	var scale_span: int = int((TerrainSettingsScript.KERNEL_WORLD_SCALE_MAX_REGION_MULTIPLIER - TerrainSettingsScript.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER) * 1000.0)
	var scale_jitter: float = float(TerrainHashScript.stable_hash(["scale", kernel_id, rx, rz, world_seed]) % scale_span) / 1000.0
	var scale_multiplier: float = TerrainSettingsScript.KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER + scale_jitter
	return {
		"scale_multiplier": round_to(scale_multiplier, 6),
		"world_scale_m": round_to(region_size_m * scale_multiplier, 6),
		"rotation_quadrants": TerrainHashScript.stable_hash(["rot", kernel_id, rx, rz, world_seed]) % 4,
		"offset_u": round_to(float(TerrainHashScript.stable_hash(["offu", kernel_id, rx, rz, world_seed]) % 10000) / 10000.0, 6),
		"offset_v": round_to(float(TerrainHashScript.stable_hash(["offv", kernel_id, rx, rz, world_seed]) % 10000) / 10000.0, 6),
	}


func kernel_runtime_moderation(slope_p95: float) -> float:
	if slope_p95 <= 42.0:
		return 1.0
	return clampf(42.0 / slope_p95, 0.58, 1.0)


func floor_div(value: int, divisor: int) -> int:
	return int(floor(float(value) / float(divisor)))


func round_to(value: float, places: int) -> float:
	var factor: float = pow(10.0, float(places))
	return round(value * factor) / factor


func _index_kernels() -> void:
	kernels_by_family.clear()
	for kernel in pack.kernels:
		var item := kernel as Dictionary
		var family: String = str(item.get("family", "uncategorized"))
		if not kernels_by_family.has(family):
			kernels_by_family[family] = []
		(kernels_by_family[family] as Array).append(item)
	for family in kernels_by_family.keys():
		(kernels_by_family[family] as Array).sort_custom(_kernel_sort_desc)


func _kernel_sort_desc(a: Dictionary, b: Dictionary) -> bool:
	var stats_a := a.get("stats", {}) as Dictionary
	var stats_b := b.get("stats", {}) as Dictionary
	var quality_a: float = float(stats_a.get("quality_score", 0.0))
	var quality_b: float = float(stats_b.get("quality_score", 0.0))
	if quality_a != quality_b:
		return quality_a > quality_b
	var range_a: float = float(stats_a.get("height_range_m", 0.0))
	var range_b: float = float(stats_b.get("height_range_m", 0.0))
	if range_a != range_b:
		return range_a > range_b
	var slope_a: float = float(stats_a.get("slope_p95_deg", 0.0))
	var slope_b: float = float(stats_b.get("slope_p95_deg", 0.0))
	return slope_a > slope_b
