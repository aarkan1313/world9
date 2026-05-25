class_name HydrologyTileCache
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const HydrologySamplerScript := preload("res://worldgen_terrain/hydrology/hydrology_sampler.gd")

const FIELD_FLOW_ACCUMULATION := "flow_accumulation"
const FIELD_WETNESS := "wetness"
const FIELD_CHANNEL_LIKELIHOOD := "channel_likelihood"
const FIELD_SLOPE_DEG := "slope_deg"
const VALID_FIELDS := [
	FIELD_FLOW_ACCUMULATION,
	FIELD_WETNESS,
	FIELD_CHANNEL_LIKELIHOOD,
	FIELD_SLOPE_DEG,
]
const MAX_RECORDED_ERRORS := 64

var world: RefCounted
var sampler: RefCounted
var tile_size_m: float = TerrainSettingsScript.REGION_SIZE_M
var tile_origin_offset_m: Vector2 = Vector2.ZERO
var grid_size: int = 129
var padding_cells: int = 32
var max_cached_tiles: int = 32
var tiles: Dictionary = {}
var tile_access_order: Array[String] = []
var errors: Array[String] = []


func setup(
	p_world: RefCounted,
	p_tile_size_m: float = TerrainSettingsScript.REGION_SIZE_M,
	p_grid_size: int = 129,
	p_padding_cells: int = 32,
	p_tile_origin_offset_m: Vector2 = Vector2.ZERO
) -> void:
	world = p_world
	tile_size_m = p_tile_size_m
	tile_origin_offset_m = p_tile_origin_offset_m
	grid_size = p_grid_size
	padding_cells = p_padding_cells
	sampler = HydrologySamplerScript.new()
	tiles.clear()
	tile_access_order.clear()
	errors.clear()


func sample(world_x: float, world_z: float) -> Dictionary:
	var tile_coord: Vector2i = tile_coords_for_world(world_x, world_z)
	var tile: Dictionary = get_tile(tile_coord.x, tile_coord.y)
	if tile.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": str(tile.get("error", "tile_failed")),
			"tile_coord": [tile_coord.x, tile_coord.y],
		}
	var values: Dictionary = sample_tile(tile, world_x, world_z)
	values["status"] = "pass"
	values["tile_coord"] = [tile_coord.x, tile_coord.y]
	values["tile_size_m"] = tile_size_m
	values["grid_size"] = grid_size
	values["padding_cells"] = padding_cells
	return values


func sample_grid(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int, field: String) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if not _is_valid_field(field):
		_record_error("invalid_field:%s" % field)
		return values
	if not is_finite(origin_x) or not is_finite(origin_z):
		_record_error("invalid_grid_origin:%.6f,%.6f" % [origin_x, origin_z])
		return values
	if not is_finite(step_m) or step_m <= 0.0:
		_record_error("invalid_grid_step_m:%.6f" % step_m)
		return values
	if count_x <= 0 or count_z <= 0:
		_record_error("invalid_grid_count:%d,%d" % [count_x, count_z])
		return values
	values.resize(count_x * count_z)
	for z in range(count_z):
		var world_z: float = origin_z + float(z) * step_m
		for x in range(count_x):
			var world_x: float = origin_x + float(x) * step_m
			values[z * count_x + x] = sample_field(world_x, world_z, field)
	return values


func tile_coords_for_world(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(
		floori((world_x + tile_origin_offset_m.x) / tile_size_m),
		floori((world_z + tile_origin_offset_m.y) / tile_size_m)
	)


func get_tile(tile_x: int, tile_z: int) -> Dictionary:
	var key: String = _tile_key(tile_x, tile_z)
	if tiles.has(key):
		_touch_tile_key(key)
		return tiles[key] as Dictionary
	var tile: Dictionary = _build_tile(tile_x, tile_z)
	tiles[key] = tile
	_touch_tile_key(key)
	_prune_tile_cache()
	return tile


func sample_tile(tile: Dictionary, world_x: float, world_z: float) -> Dictionary:
	var origin: Vector2 = tile["origin_m"] as Vector2
	var step_m: float = float(tile["step_m"])
	var local_x: float = clampf((world_x - origin.x) / step_m, 0.0, float(grid_size - 1))
	var local_z: float = clampf((world_z - origin.y) / step_m, 0.0, float(grid_size - 1))
	var flow_dir: Vector2 = _sample_vector(tile["flow_dir"] as PackedVector2Array, local_x, local_z)
	return {
		FIELD_FLOW_ACCUMULATION: _sample_float(tile[FIELD_FLOW_ACCUMULATION] as PackedFloat32Array, local_x, local_z),
		FIELD_WETNESS: _sample_float(tile[FIELD_WETNESS] as PackedFloat32Array, local_x, local_z),
		FIELD_CHANNEL_LIKELIHOOD: _sample_float(tile[FIELD_CHANNEL_LIKELIHOOD] as PackedFloat32Array, local_x, local_z),
		FIELD_SLOPE_DEG: _sample_float(tile[FIELD_SLOPE_DEG] as PackedFloat32Array, local_x, local_z),
		"flow_dir": flow_dir,
		"tile_local": [local_x, local_z],
	}


func sample_field(world_x: float, world_z: float, field: String) -> float:
	if not _is_valid_field(field):
		_record_error("invalid_field:%s" % field)
		return NAN
	var tile_coord: Vector2i = tile_coords_for_world(world_x, world_z)
	var tile: Dictionary = get_tile(tile_coord.x, tile_coord.y)
	if tile.get("status", "fail") != "pass":
		_record_error("sample_field_tile_failed:%d,%d:%s" % [
			tile_coord.x,
			tile_coord.y,
			str(tile.get("error", "tile_failed")),
		])
		return NAN
	return sample_tile_field(tile, world_x, world_z, field)


func sample_tile_field(tile: Dictionary, world_x: float, world_z: float, field: String) -> float:
	if tile.get("status", "fail") != "pass":
		_record_error("sample_tile_field_failed:%s" % str(tile.get("error", "tile_failed")))
		return NAN
	if not _is_valid_field(field):
		_record_error("invalid_field:%s" % field)
		return NAN
	var origin: Vector2 = tile["origin_m"] as Vector2
	var step_m: float = float(tile["step_m"])
	var local_x: float = clampf((world_x - origin.x) / step_m, 0.0, float(grid_size - 1))
	var local_z: float = clampf((world_z - origin.y) / step_m, 0.0, float(grid_size - 1))
	if field == FIELD_FLOW_ACCUMULATION:
		return _sample_float(tile[FIELD_FLOW_ACCUMULATION] as PackedFloat32Array, local_x, local_z)
	if field == FIELD_WETNESS:
		return _sample_float(tile[FIELD_WETNESS] as PackedFloat32Array, local_x, local_z)
	if field == FIELD_CHANNEL_LIKELIHOOD:
		return _sample_float(tile[FIELD_CHANNEL_LIKELIHOOD] as PackedFloat32Array, local_x, local_z)
	if field == FIELD_SLOPE_DEG:
		return _sample_float(tile[FIELD_SLOPE_DEG] as PackedFloat32Array, local_x, local_z)
	_record_error("invalid_field:%s" % field)
	return NAN


func built_tile_count() -> int:
	return tiles.size()


func set_max_cached_tiles(count: int) -> void:
	max_cached_tiles = max(1, count)
	_prune_tile_cache()


func _build_tile(tile_x: int, tile_z: int) -> Dictionary:
	var origin := Vector2(
		float(tile_x) * tile_size_m - tile_origin_offset_m.x,
		float(tile_z) * tile_size_m - tile_origin_offset_m.y
	)
	var center := origin + Vector2(tile_size_m * 0.5, tile_size_m * 0.5)
	var result: Dictionary = sampler.sample_window(world, center, tile_size_m, grid_size, padding_cells)
	if result.get("status", "fail") != "pass":
		var error: String = "%d,%d:%s" % [tile_x, tile_z, str(result.get("error", "unknown"))]
		errors.append(error)
		return {
			"status": "fail",
			"error": error,
			"tile_coord": Vector2i(tile_x, tile_z),
			"origin_m": origin,
		}
	result["tile_coord"] = Vector2i(tile_x, tile_z)
	result["origin_m"] = origin
	result["tile_size_m"] = tile_size_m
	return result


func _sample_float(values: PackedFloat32Array, local_x: float, local_z: float) -> float:
	var x0: int = clampi(floori(local_x), 0, grid_size - 1)
	var z0: int = clampi(floori(local_z), 0, grid_size - 1)
	var x1: int = min(x0 + 1, grid_size - 1)
	var z1: int = min(z0 + 1, grid_size - 1)
	var tx: float = local_x - float(x0)
	var tz: float = local_z - float(z0)
	var a: float = lerpf(float(values[z0 * grid_size + x0]), float(values[z0 * grid_size + x1]), tx)
	var b: float = lerpf(float(values[z1 * grid_size + x0]), float(values[z1 * grid_size + x1]), tx)
	return lerpf(a, b, tz)


func _sample_vector(values: PackedVector2Array, local_x: float, local_z: float) -> Vector2:
	var x0: int = clampi(floori(local_x), 0, grid_size - 1)
	var z0: int = clampi(floori(local_z), 0, grid_size - 1)
	var x1: int = min(x0 + 1, grid_size - 1)
	var z1: int = min(z0 + 1, grid_size - 1)
	var tx: float = local_x - float(x0)
	var tz: float = local_z - float(z0)
	var a: Vector2 = values[z0 * grid_size + x0].lerp(values[z0 * grid_size + x1], tx)
	var b: Vector2 = values[z1 * grid_size + x0].lerp(values[z1 * grid_size + x1], tx)
	var v: Vector2 = a.lerp(b, tz)
	return v.normalized() if v.length_squared() > 0.0001 else Vector2.ZERO


func _tile_key(tile_x: int, tile_z: int) -> String:
	return "%d,%d" % [tile_x, tile_z]


func _touch_tile_key(key: String) -> void:
	var existing_index: int = tile_access_order.find(key)
	if existing_index >= 0:
		tile_access_order.remove_at(existing_index)
	tile_access_order.append(key)


func _prune_tile_cache() -> void:
	var limit: int = max(1, max_cached_tiles)
	while tiles.size() > limit and not tile_access_order.is_empty():
		var key: String = tile_access_order.pop_front()
		tiles.erase(key)


func _is_valid_field(field: String) -> bool:
	return VALID_FIELDS.has(field)


func _record_error(error: String) -> void:
	if errors.has(error):
		return
	if errors.size() >= MAX_RECORDED_ERRORS:
		return
	errors.append(error)
