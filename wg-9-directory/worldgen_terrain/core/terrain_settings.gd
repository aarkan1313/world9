class_name TerrainSettings
extends RefCounted

const CHUNK_SIZE_M: float = 2048.0
const LOD0_VERTICES_PER_SIDE: int = 129
const HIGH_DETAIL_LOD0_VERTICES_PER_SIDE: int = 257
const VISIBLE_RADIUS_CHUNKS: int = 4
const REGION_SIZE_M: float = 32768.0
const PROVINCE_SIZE_REGIONS: int = 4
const KERNEL_WORLD_SCALE_MIN_REGION_MULTIPLIER: float = 2.20
const KERNEL_WORLD_SCALE_MAX_REGION_MULTIPLIER: float = 3.20

const RUNTIME_PACK_PATH: String = "factory/runtime/kernel_pack_v1.json"
const HASH_REFERENCE_PATH: String = "factory/runtime/hash_reference/hash_reference.json"
const PROVIDER_DECISIONS_PATH: String = "factory/runtime/provider_decisions/provider_decisions_reference.json"
const TERRAIN_SAMPLE_REFERENCE_PATH: String = "factory/runtime/terrain_sample_reference.json"
const STREAMER_REFERENCE_PATH: String = "factory/runtime/streamer_reference/streamer_reference.json"
const STREAMER_FIFO_REFERENCE_PATH: String = "factory/runtime/streamer_reference_fifo/streamer_reference.json"


static func project_root() -> String:
	return ProjectSettings.globalize_path("res://").simplify_path()


static func workspace_root() -> String:
	return project_root().path_join("..").simplify_path()


static func workspace_path(relative_path: String) -> String:
	return workspace_root().path_join(relative_path).simplify_path()


static func runtime_pack_path() -> String:
	return workspace_path(RUNTIME_PACK_PATH)


static func hash_reference_path() -> String:
	return workspace_path(HASH_REFERENCE_PATH)


static func provider_decisions_path() -> String:
	return workspace_path(PROVIDER_DECISIONS_PATH)


static func terrain_sample_reference_path() -> String:
	return workspace_path(TERRAIN_SAMPLE_REFERENCE_PATH)


static func streamer_reference_path() -> String:
	return workspace_path(STREAMER_REFERENCE_PATH)


static func streamer_fifo_reference_path() -> String:
	return workspace_path(STREAMER_FIFO_REFERENCE_PATH)
