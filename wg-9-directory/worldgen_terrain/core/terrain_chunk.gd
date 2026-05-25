class_name TerrainChunk
extends RefCounted

var chunk_x: int
var chunk_z: int
var ring: int
var lod: int


func _init(p_chunk_x: int = 0, p_chunk_z: int = 0, p_ring: int = 0, p_lod: int = 0) -> void:
	chunk_x = p_chunk_x
	chunk_z = p_chunk_z
	ring = p_ring
	lod = p_lod


func key() -> String:
	return key_from_coords(chunk_x, chunk_z)


func to_reference_dict() -> Dictionary:
	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": ring,
		"lod": lod,
	}


static func key_from_coords(p_chunk_x: int, p_chunk_z: int) -> String:
	return "%d,%d" % [p_chunk_x, p_chunk_z]
