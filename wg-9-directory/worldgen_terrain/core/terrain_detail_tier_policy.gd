class_name TerrainDetailTierPolicy
extends RefCounted

const DEFAULT_PATCH_SIZE_M := 256.0
const DEFAULT_VERTICES_PER_SIDE := 257
const DEFAULT_RADIUS_PATCHES := 0
const DEFAULT_BASE_CHUNK_SIZE_M := 512.0
const DEFAULT_BASE_VERTICES_PER_SIDE := 129


static func make_settings(
	patch_size_m: float = DEFAULT_PATCH_SIZE_M,
	vertices_per_side: int = DEFAULT_VERTICES_PER_SIDE,
	radius_patches: int = DEFAULT_RADIUS_PATCHES,
	max_active_patches: int = 9
) -> Dictionary:
	return {
		"patch_size_m": max(1.0, patch_size_m),
		"vertices_per_side": max(2, vertices_per_side),
		"radius_patches": max(0, radius_patches),
		"max_active_patches": max(1, max_active_patches),
	}


static func active_patches(viewer_xz: Vector2, settings: Dictionary = {}) -> Array[Dictionary]:
	var patch_size_m: float = float(settings.get("patch_size_m", DEFAULT_PATCH_SIZE_M))
	var vertices_per_side: int = int(settings.get("vertices_per_side", DEFAULT_VERTICES_PER_SIDE))
	var radius_patches: int = int(settings.get("radius_patches", DEFAULT_RADIUS_PATCHES))
	var max_active_patches: int = int(settings.get("max_active_patches", 9))
	var center := patch_coord_for_position(viewer_xz, patch_size_m)
	var patches: Array[Dictionary] = []
	for dz in range(-radius_patches, radius_patches + 1):
		for dx in range(-radius_patches, radius_patches + 1):
			var patch_x: int = center.x + dx
			var patch_z: int = center.y + dz
			var ring: int = max(abs(dx), abs(dz))
			patches.append(_patch_info(patch_x, patch_z, patch_size_m, vertices_per_side, ring, abs(dx) + abs(dz)))
	patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["ring"]) != int(b["ring"]):
			return int(a["ring"]) < int(b["ring"])
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		if int(a["patch_z"]) != int(b["patch_z"]):
			return int(a["patch_z"]) < int(b["patch_z"])
		return int(a["patch_x"]) < int(b["patch_x"])
	)
	if patches.size() > max_active_patches:
		patches.resize(max_active_patches)
	return patches


static func patch_coord_for_position(viewer_xz: Vector2, patch_size_m: float = DEFAULT_PATCH_SIZE_M) -> Vector2i:
	var size_m: float = max(1.0, patch_size_m)
	return Vector2i(
		int(floor(viewer_xz.x / size_m)),
		int(floor(viewer_xz.y / size_m))
	)


static func validate_alignment(
	patch_size_m: float = DEFAULT_PATCH_SIZE_M,
	vertices_per_side: int = DEFAULT_VERTICES_PER_SIDE,
	base_chunk_size_m: float = DEFAULT_BASE_CHUNK_SIZE_M,
	base_vertices_per_side: int = DEFAULT_BASE_VERTICES_PER_SIDE
) -> Dictionary:
	var detail_spacing_m: float = patch_size_m / float(max(1, vertices_per_side - 1))
	var base_spacing_m: float = base_chunk_size_m / float(max(1, base_vertices_per_side - 1))
	var spacing_ratio: float = base_spacing_m / max(0.000001, detail_spacing_m)
	var patch_ratio: float = base_chunk_size_m / max(0.000001, patch_size_m)
	var spacing_ratio_round: float = round(spacing_ratio)
	var patch_ratio_round: float = round(patch_ratio)
	var spacing_aligned: bool = absf(spacing_ratio - spacing_ratio_round) <= 0.000001 and spacing_ratio_round >= 1.0
	var patch_aligned: bool = absf(patch_ratio - patch_ratio_round) <= 0.000001 or absf(1.0 / max(0.000001, patch_ratio) - round(1.0 / max(0.000001, patch_ratio))) <= 0.000001
	return {
		"status": "pass" if spacing_aligned and patch_aligned else "fail",
		"patch_size_m": patch_size_m,
		"vertices_per_side": vertices_per_side,
		"detail_spacing_m": detail_spacing_m,
		"base_chunk_size_m": base_chunk_size_m,
		"base_vertices_per_side": base_vertices_per_side,
		"base_spacing_m": base_spacing_m,
		"detail_samples_per_base_step": int(spacing_ratio_round) if spacing_aligned else 0,
		"spacing_aligned": spacing_aligned,
		"patch_aligned": patch_aligned,
	}


static func _patch_info(patch_x: int, patch_z: int, patch_size_m: float, vertices_per_side: int, ring: int, center_distance: int) -> Dictionary:
	var spacing_m: float = patch_size_m / float(max(1, vertices_per_side - 1))
	return {
		"key": "%d,%d" % [patch_x, patch_z],
		"patch_x": patch_x,
		"patch_z": patch_z,
		"origin_x": float(patch_x) * patch_size_m,
		"origin_z": float(patch_z) * patch_size_m,
		"patch_size_m": patch_size_m,
		"vertices_per_side": vertices_per_side,
		"spacing_m": spacing_m,
		"ring": ring,
		"priority": ring * 1000 + center_distance,
	}
