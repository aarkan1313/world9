class_name TerrainWorld
extends RefCounted

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainChunkScript := preload("res://worldgen_terrain/core/terrain_chunk.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const FlatHeightProviderScript := preload("res://worldgen_terrain/height/flat_height_provider.gd")
const ProceduralHeightProviderScript := preload("res://worldgen_terrain/height/procedural_height_provider.gd")

const PROVIDER_FLAT := "flat"
const PROVIDER_PROCEDURAL := "procedural"

const DEBUG_GRAY := "gray"
const DEBUG_ELEVATION_COLOR := "elevation_color"
const DEBUG_CHUNK_ID := "chunk_id"
const DEBUG_LOD_RING := "lod_ring"
const DEBUG_HEIGHT_BANDS := "height_bands"
const DEBUG_SEAM := "seam"
const DEBUG_FAMILY_PALETTE := "family_palette"
const DEBUG_HYDROLOGY := "hydrology"

var provider: RefCounted
var runtime_pack: RefCounted
var streamer: RefCounted
var chunks: Dictionary = {}
var provider_mode: String = ""
var debug_mode: String = DEBUG_GRAY
var seed: int = 1337
var region_size_m: float = TerrainSettingsScript.REGION_SIZE_M
var chunk_size_m: float = TerrainSettingsScript.CHUNK_SIZE_M
var lod0_vertices_per_side: int = TerrainSettingsScript.LOD0_VERTICES_PER_SIDE
var last_step: Dictionary = {}
var errors: Array[String] = []


func setup_flat(flat_height_m: float = 0.0, p_seed: int = 1337) -> void:
	seed = p_seed
	region_size_m = TerrainSettingsScript.REGION_SIZE_M
	chunk_size_m = TerrainSettingsScript.CHUNK_SIZE_M
	lod0_vertices_per_side = TerrainSettingsScript.LOD0_VERTICES_PER_SIDE
	provider = FlatHeightProviderScript.new()
	provider.setup(flat_height_m)
	provider_mode = PROVIDER_FLAT
	_configure_default_streamer()


func setup_procedural(p_seed: int = 1337) -> bool:
	errors.clear()
	runtime_pack = RuntimeKernelPackScript.new()
	if not runtime_pack.load_default():
		for error in runtime_pack.errors:
			errors.append(str(error))
		return false
	provider = ProceduralHeightProviderScript.new()
	provider.setup(runtime_pack)
	provider.use_native_prepared_height_grid = ClassDB.class_exists("Wg9TerrainNativeBackend")
	provider_mode = PROVIDER_PROCEDURAL
	seed = p_seed
	region_size_m = TerrainSettingsScript.REGION_SIZE_M
	chunk_size_m = TerrainSettingsScript.CHUNK_SIZE_M
	lod0_vertices_per_side = TerrainSettingsScript.LOD0_VERTICES_PER_SIDE
	_configure_default_streamer()
	return true


func configure_streamer(settings: Dictionary) -> bool:
	streamer = TerrainStreamerScript.new()
	if not streamer.setup(settings):
		errors.append_array(streamer.errors)
		return false
	chunk_size_m = float(settings["chunk_size_m"])
	chunks.clear()
	last_step.clear()
	return true


func update_viewer(world_position_xz: Vector2) -> Dictionary:
	if streamer == null:
		_configure_default_streamer()
	last_step = streamer.update_viewer(world_position_xz)
	if last_step.get("status", "pass") != "pass":
		return last_step
	_sync_chunks(last_step)
	return last_step


func set_stream_priority_direction(direction: Vector2) -> void:
	if streamer != null and streamer.has_method("set_priority_direction"):
		streamer.call("set_priority_direction", direction)


func sample_height(world_x: float, world_z: float) -> float:
	return provider.sample_height(world_x, world_z, seed, region_size_m)


func sample(world_x: float, world_z: float, slope_step_m: float = 32.0) -> Dictionary:
	return provider.sample(world_x, world_z, seed, region_size_m, slope_step_m)


func sample_height_grid(origin_x: float, origin_z: float, step_m: float, count_x: int, count_z: int) -> PackedFloat32Array:
	return provider.sample_height_grid(
		origin_x,
		origin_z,
		step_m,
		count_x,
		count_z,
		seed,
		region_size_m
	)


func sample_height_grid_for_chunk(chunk_x: int, chunk_z: int, vertices_per_side: int = -1) -> PackedFloat32Array:
	var count: int = lod0_vertices_per_side if vertices_per_side <= 0 else vertices_per_side
	var step_m: float = chunk_size_m / float(count - 1)
	return sample_height_grid(
		float(chunk_x) * chunk_size_m,
		float(chunk_z) * chunk_size_m,
		step_m,
		count,
		count
	)


func apply_landform_profile(profile: Variant) -> bool:
	if provider == null or not provider.has_method("apply_landform_profile"):
		return false
	return bool(provider.call("apply_landform_profile", profile))


func landform_profile_report() -> Dictionary:
	if provider == null or not provider.has_method("landform_profile_report"):
		return {}
	return provider.call("landform_profile_report") as Dictionary


func active_count() -> int:
	return chunks.size()


func queued_build_count() -> int:
	return int(last_step.get("queued_build_count", 0))


func build_now() -> Array:
	return last_step.get("build_now", []) as Array


func set_debug_mode(mode: String) -> void:
	if valid_debug_modes().has(mode):
		debug_mode = mode
	else:
		push_warning("Unknown terrain debug mode: %s" % mode)


func valid_debug_modes() -> Array[String]:
	return [
		DEBUG_GRAY,
		DEBUG_ELEVATION_COLOR,
		DEBUG_CHUNK_ID,
		DEBUG_LOD_RING,
		DEBUG_HEIGHT_BANDS,
		DEBUG_SEAM,
		DEBUG_FAMILY_PALETTE,
		DEBUG_HYDROLOGY,
	]


func _configure_default_streamer() -> void:
	configure_streamer({
		"chunk_size_m": TerrainSettingsScript.CHUNK_SIZE_M,
		"visible_radius_chunks": TerrainSettingsScript.VISIBLE_RADIUS_CHUNKS,
		"max_lod": 4,
		"build_budget_per_frame": 2,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})


func _sync_chunks(step: Dictionary) -> void:
	var next_chunks: Dictionary = {}
	for item_value in step.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var key: String = TerrainChunkScript.key_from_coords(chunk_x, chunk_z)
		var chunk: RefCounted
		if chunks.has(key):
			chunk = chunks[key] as RefCounted
			chunk.ring = int(item["ring"])
			chunk.lod = int(item["lod"])
		else:
			chunk = TerrainChunkScript.new(chunk_x, chunk_z, int(item["ring"]), int(item["lod"]))
		next_chunks[key] = chunk
	chunks = next_chunks
