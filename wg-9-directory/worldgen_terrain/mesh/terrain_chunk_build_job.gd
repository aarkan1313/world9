class_name TerrainChunkBuildJob
extends RefCounted

const TerrainMeshBuilderScript := preload("res://worldgen_terrain/mesh/terrain_mesh_builder.gd")


static func make_request(
	chunk_x: int,
	chunk_z: int,
	vertices_per_side: int,
	chunk_size_m: float,
	ring: int = 0,
	lod: int = 0,
	debug_mode: String = "gray"
) -> Dictionary:
	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"vertices_per_side": max(2, vertices_per_side),
		"chunk_size_m": chunk_size_m,
		"step_m": chunk_size_m / float(max(1, vertices_per_side - 1)),
		"ring": ring,
		"lod": lod,
		"debug_mode": debug_mode,
	}


static func build_payload(world: RefCounted, request: Dictionary, colors: PackedColorArray = PackedColorArray()) -> Dictionary:
	var count: int = int(request["vertices_per_side"])
	var chunk_x: int = int(request["chunk_x"])
	var chunk_z: int = int(request["chunk_z"])
	var step_m: float = float(request["step_m"])
	var height: PackedFloat32Array = world.sample_height_grid_for_chunk(chunk_x, chunk_z, count)
	if height.size() != count * count:
		return {
			"status": "fail",
			"error": "height_size:%d expected:%d" % [height.size(), count * count],
			"request": request,
		}
	if not colors.is_empty() and colors.size() != height.size():
		return {
			"status": "fail",
			"error": "color_size:%d expected:%d" % [colors.size(), height.size()],
			"request": request,
		}
	var arrays: Array = TerrainMeshBuilderScript.build_surface_arrays(height, count, step_m, colors)
	return {
		"status": "pass",
		"request": request,
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"ring": int(request.get("ring", 0)),
		"lod": int(request.get("lod", 0)),
		"origin_m": [float(chunk_x) * float(request["chunk_size_m"]), float(chunk_z) * float(request["chunk_size_m"])],
		"vertices_per_side": count,
		"step_m": step_m,
		"height": height,
		"arrays": arrays,
		"has_colors": not colors.is_empty(),
	}


static func mesh_from_payload(payload: Dictionary) -> ArrayMesh:
	if payload.get("status", "fail") != "pass":
		return null
	return TerrainMeshBuilderScript.build_array_mesh(payload["arrays"] as Array)


static func payload_summary(payload: Dictionary) -> Dictionary:
	if payload.get("status", "fail") != "pass":
		return {
			"status": "fail",
			"error": str(payload.get("error", "unknown")),
		}
	var arrays: Array = payload["arrays"] as Array
	return {
		"status": "pass",
		"chunk": [int(payload["chunk_x"]), int(payload["chunk_z"])],
		"vertices_per_side": int(payload["vertices_per_side"]),
		"vertex_count": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"normal_count": (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size(),
		"index_count": (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
		"has_colors": bool(payload.get("has_colors", false)),
	}
