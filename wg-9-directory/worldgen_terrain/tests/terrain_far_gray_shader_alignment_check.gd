extends SceneTree

const TerrainFarClipmapNodeScript := preload("res://worldgen_terrain/runtime/terrain_far_clipmap_node.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var terrain: Node3D = TerrainWorldNodeScript.new()
	terrain.use_fast_gray_material = true
	terrain.fast_gray_exposure = 0.42
	terrain.fast_gray_contrast = 1.42
	var near_material: ShaderMaterial = terrain._fast_gray_material()
	var near_code: String = near_material.shader.code
	var far: Node3D = TerrainFarClipmapNodeScript.new()
	var far_shader: Shader = far._gray_material_shader(false)
	var far_code: String = far_shader.code
	var required_snippets: Array[String] = [
		"vec3 review_n = normalize(vec3(n.x * 0.65, n.y, n.z * 0.65));",
		"float slope_shadow = clamp((1.0 - review_n.y) * 0.04, 0.0, 0.025);",
		"float shade = clamp(0.30 + lambert * 0.08 + compressed_height * 0.30 - slope_shadow, 0.16, 0.70);",
	]
	for snippet in required_snippets:
		if not near_code.contains(snippet):
			errors.append("near_missing:%s" % snippet)
		if not far_code.contains(snippet):
			errors.append("far_missing:%s" % snippet)
	if not near_code.contains("shade = (shade - 0.5) * gray_contrast + 0.5;"):
		errors.append("near_missing_contrast_uniform")
	if not near_code.contains("shade = clamp(shade * gray_exposure, 0.035, 0.58);"):
		errors.append("near_missing_exposure_uniform")
	if not far_code.contains("shade = (shade - 0.5) * 1.42 + 0.5;"):
		errors.append("far_missing_walk_contrast")
	if not far_code.contains("shade = clamp(shade * 0.42, 0.035, 0.58);"):
		errors.append("far_missing_walk_exposure")
	if not far_code.contains("edge_fog_square_enabled"):
		errors.append("far_missing_square_edge_fog_toggle")
	if not far_code.contains("max(abs(world_position.x - edge_fog_center_xz.x), abs(world_position.z - edge_fog_center_xz.y))"):
		errors.append("far_missing_square_edge_fog_distance")
	if not far_code.contains("ALPHA = fade_alpha * mix(1.0, 0.04, fog_t);"):
		errors.append("far_missing_edge_alpha_fade")
	if far_code.contains("n.x * 3.0"):
		errors.append("far_old_normal_scale")
	if far_code.contains("n.x * 1.35") or near_code.contains("n.x * 1.35"):
		errors.append("old_review_normal_scale")
	if far_code.contains("lambert * 0.24") or near_code.contains("lambert * 0.24"):
		errors.append("old_lambert_weight")
	terrain.free()
	far.free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-far-gray-shader-alignment] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-far-gray-shader-alignment] status=pass")
	quit(0)
