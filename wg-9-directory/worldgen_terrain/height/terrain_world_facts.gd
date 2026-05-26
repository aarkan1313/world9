class_name TerrainWorldFacts
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainHashScript := preload("res://worldgen_terrain/height/terrain_hash.gd")

const SCHEMA := "worldgen9.terrain_world_facts.v1"
const RUGGED_FAMILIES: Dictionary = {
	"mountain": 1.0,
	"glacial": 0.95,
	"volcanic": 0.82,
	"karst": 0.62,
	"badlands": 0.52,
}

var decisions: RefCounted
var _fact_cache: Dictionary = {}


func setup(p_decisions: RefCounted) -> void:
	decisions = p_decisions
	_fact_cache.clear()


func clear_cache() -> void:
	_fact_cache.clear()


func pass_corridor_facts_for_region(
	rx: int,
	rz: int,
	world_seed: int = 1337,
	region_size_m: float = TerrainSettingsScript.REGION_SIZE_M
) -> Dictionary:
	if decisions == null:
		return {"status": "fail", "error": "decisions_not_setup"}
	if not is_finite(region_size_m) or region_size_m <= 0.0:
		return {"status": "fail", "error": "invalid_region_size_m"}
	var cache_key := "%d,%d:%d:%.3f" % [rx, rz, world_seed, region_size_m]
	if _fact_cache.has(cache_key):
		return (_fact_cache[cache_key] as Dictionary).duplicate(true)

	var palette: Dictionary = decisions.region_info(rx, rz, world_seed)
	var families: Array = palette.get("families", []) as Array
	var ruggedness: float = _ruggedness_for_families(families)
	var corridor: Dictionary = _corridor_for_region(rx, rz, world_seed, region_size_m, ruggedness, str(palette.get("id", "")), families)
	var result: Dictionary = {
		"status": "pass",
		"schema": SCHEMA,
		"region": [rx, rz],
		"region_size_m": region_size_m,
		"palette": str(palette.get("id", "")),
		"families": families.duplicate(),
		"ruggedness": ruggedness,
		"affects_height": false,
		"facts": [corridor],
	}
	_fact_cache[cache_key] = result.duplicate(true)
	return result


func sample_pass_corridor_hint(
	world_x: float,
	world_z: float,
	world_seed: int = 1337,
	region_size_m: float = TerrainSettingsScript.REGION_SIZE_M
) -> Dictionary:
	if not is_finite(world_x) or not is_finite(world_z):
		return {"status": "fail", "error": "invalid_world_coord"}
	if not is_finite(region_size_m) or region_size_m <= 0.0:
		return {"status": "fail", "error": "invalid_region_size_m"}
	var rx: int = int(floor(world_x / region_size_m))
	var rz: int = int(floor(world_z / region_size_m))
	var best_strength := 0.0
	var best_fact: Dictionary = {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var facts: Dictionary = pass_corridor_facts_for_region(rx + dx, rz + dz, world_seed, region_size_m)
			if facts.get("status", "fail") != "pass":
				continue
			for fact_value in facts.get("facts", []) as Array:
				var fact: Dictionary = fact_value as Dictionary
				var strength: float = _corridor_strength_at(fact, world_x, world_z)
				if strength > best_strength:
					best_strength = strength
					best_fact = fact
	return {
		"status": "pass",
		"schema": SCHEMA,
		"world_x": world_x,
		"world_z": world_z,
		"region": [rx, rz],
		"corridor_strength": best_strength,
		"corridor_id": str(best_fact.get("id", "")),
		"corridor_kind": str(best_fact.get("kind", "")),
		"affects_height": false,
	}


func _corridor_for_region(
	rx: int,
	rz: int,
	world_seed: int,
	region_size_m: float,
	ruggedness: float,
	palette_id: String,
	families: Array
) -> Dictionary:
	var side_a: int = TerrainHashScript.stable_hash(["pass_side_a", rx, rz, world_seed]) % 4
	var side_roll: int = TerrainHashScript.stable_hash(["pass_side_b", rx, rz, world_seed]) % 100
	var side_b: int = (side_a + 2) % 4 if side_roll < 72 else (side_a + 1 + (side_roll % 2) * 2) % 4
	var t_a: float = 0.18 + float(TerrainHashScript.stable_hash(["pass_t_a", rx, rz, world_seed]) % 6400) / 10000.0
	var t_b: float = 0.18 + float(TerrainHashScript.stable_hash(["pass_t_b", rx, rz, world_seed]) % 6400) / 10000.0
	var origin := Vector2(float(rx) * region_size_m, float(rz) * region_size_m)
	var start: Vector2 = origin + _point_on_region_side(side_a, t_a, region_size_m)
	var end: Vector2 = origin + _point_on_region_side(side_b, t_b, region_size_m)
	var width_m: float = region_size_m * lerpf(0.035, 0.075, ruggedness)
	var priority: float = 0.35 + ruggedness * 0.65
	var kind := "mountain_pass" if ruggedness >= 0.55 else "regional_corridor"
	return {
		"id": "pass_%d_%d_%08x" % [rx, rz, TerrainHashScript.stable_hash(["pass_id", rx, rz, world_seed])],
		"schema": SCHEMA,
		"kind": kind,
		"region": [rx, rz],
		"palette": palette_id,
		"families": families.duplicate(),
		"start_m": [start.x, start.y],
		"end_m": [end.x, end.y],
		"width_m": width_m,
		"priority": priority,
		"ruggedness": ruggedness,
		"affects_height": false,
	}


func _point_on_region_side(side: int, t: float, region_size_m: float) -> Vector2:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	match side:
		0:
			return Vector2(clamped_t * region_size_m, 0.0)
		1:
			return Vector2(region_size_m, clamped_t * region_size_m)
		2:
			return Vector2(clamped_t * region_size_m, region_size_m)
		_:
			return Vector2(0.0, clamped_t * region_size_m)


func _ruggedness_for_families(families: Array) -> float:
	if families.is_empty():
		return 0.0
	var total := 0.0
	var weight := 0.0
	for index in range(families.size()):
		var family: String = str(families[index])
		var bias: float = 1.0 / float(index + 1)
		total += float(RUGGED_FAMILIES.get(family, 0.18)) * bias
		weight += bias
	return clampf(total / max(0.000001, weight), 0.0, 1.0)


func _corridor_strength_at(fact: Dictionary, world_x: float, world_z: float) -> float:
	var start_values: Array = fact.get("start_m", []) as Array
	var end_values: Array = fact.get("end_m", []) as Array
	if start_values.size() != 2 or end_values.size() != 2:
		return 0.0
	var start := Vector2(float(start_values[0]), float(start_values[1]))
	var end := Vector2(float(end_values[0]), float(end_values[1]))
	var width_m: float = max(0.000001, float(fact.get("width_m", 0.0)))
	var point := Vector2(world_x, world_z)
	var segment: Vector2 = end - start
	var segment_len_sq: float = max(0.000001, segment.length_squared())
	var t: float = clampf((point - start).dot(segment) / segment_len_sq, 0.0, 1.0)
	var closest: Vector2 = start + segment * t
	var distance_m: float = point.distance_to(closest)
	return 1.0 - TerrainHashScript.smoothstep_unit(distance_m / width_m)
