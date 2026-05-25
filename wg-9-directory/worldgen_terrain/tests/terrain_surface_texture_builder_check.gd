extends SceneTree

const TerrainSurfaceTextureBuilderScript := preload("res://worldgen_terrain/runtime/terrain_surface_texture_builder.gd")

const NORMAL_EPSILON := 0.0005
const FLOAT_EPSILON := 0.0005


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_flat_surface(errors)
	_check_sloped_surface(errors)
	_check_curved_surface(errors)
	_check_lightweight_descriptor(errors)
	_check_invalid_size(errors)
	_report_and_quit(errors)


func _check_flat_surface(errors: Array[String]) -> void:
	var height := PackedFloat32Array()
	height.resize(9)
	for index in range(height.size()):
		height[index] = 12.5
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(height, 3, 1.0)
	if descriptor.get("status", "fail") != "pass":
		errors.append("flat_descriptor_failed:%s" % str(descriptor))
		return
	if absf(float(descriptor["height_min_m"]) - 12.5) > 0.000001:
		errors.append("flat_min:%.6f" % float(descriptor["height_min_m"]))
	if absf(float(descriptor["height_max_m"]) - 12.5) > 0.000001:
		errors.append("flat_max:%.6f" % float(descriptor["height_max_m"]))
	var height_image: Image = descriptor["height_image"] as Image
	var normal_image: Image = descriptor["normal_image"] as Image
	var slope_image: Image = descriptor["slope_deg_image"] as Image
	var curvature_image: Image = descriptor["curvature_image"] as Image
	var debug_heatmap_image: Image = descriptor["debug_heatmap_image"] as Image
	var displacement_image: Image = descriptor["visual_displacement_image"] as Image
	if height_image.get_width() != 3 or height_image.get_height() != 3:
		errors.append("flat_height_image_size:%dx%d" % [height_image.get_width(), height_image.get_height()])
	if normal_image.get_width() != 3 or normal_image.get_height() != 3:
		errors.append("flat_normal_image_size:%dx%d" % [normal_image.get_width(), normal_image.get_height()])
	if slope_image.get_width() != 3 or slope_image.get_height() != 3:
		errors.append("flat_slope_image_size:%dx%d" % [slope_image.get_width(), slope_image.get_height()])
	if curvature_image.get_width() != 3 or curvature_image.get_height() != 3:
		errors.append("flat_curvature_image_size:%dx%d" % [curvature_image.get_width(), curvature_image.get_height()])
	if debug_heatmap_image.get_width() != 3 or debug_heatmap_image.get_height() != 3:
		errors.append("flat_debug_image_size:%dx%d" % [debug_heatmap_image.get_width(), debug_heatmap_image.get_height()])
	if displacement_image.get_width() != 3 or displacement_image.get_height() != 3:
		errors.append("flat_displacement_image_size:%dx%d" % [displacement_image.get_width(), displacement_image.get_height()])
	if absf(height_image.get_pixel(1, 1).r - 12.5) > 0.000001:
		errors.append("flat_height_pixel:%.6f" % height_image.get_pixel(1, 1).r)
	var decoded: Vector3 = TerrainSurfaceTextureBuilderScript.decode_normal_color(normal_image.get_pixel(1, 1))
	if decoded.distance_to(Vector3.UP) > NORMAL_EPSILON:
		errors.append("flat_normal:%s" % str(decoded))
	var slopes: PackedFloat32Array = descriptor["slope_deg_values"] as PackedFloat32Array
	var curvature: PackedFloat32Array = descriptor["curvature_values"] as PackedFloat32Array
	if absf(float(slopes[4])) > FLOAT_EPSILON:
		errors.append("flat_slope:%.6f" % float(slopes[4]))
	if absf(float(curvature[4])) > FLOAT_EPSILON:
		errors.append("flat_curvature:%.6f" % float(curvature[4]))
	var displacement: PackedFloat32Array = descriptor["visual_displacement_values"] as PackedFloat32Array
	if absf(float(displacement[4])) > FLOAT_EPSILON:
		errors.append("flat_displacement:%.6f" % float(displacement[4]))
	if absf(float(descriptor["visual_displacement_max_abs_m"])) > FLOAT_EPSILON:
		errors.append("flat_displacement_max:%.6f" % float(descriptor["visual_displacement_max_abs_m"]))


func _check_sloped_surface(errors: Array[String]) -> void:
	var height := PackedFloat32Array()
	height.resize(9)
	for z in range(3):
		for x in range(3):
			height[z * 3 + x] = float(x) * 2.0
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(height, 3, 1.0)
	if descriptor.get("status", "fail") != "pass":
		errors.append("slope_descriptor_failed:%s" % str(descriptor))
		return
	var expected := Vector3(-2.0, 1.0, 0.0).normalized()
	var normals: PackedVector3Array = descriptor["normal_values"] as PackedVector3Array
	var center: Vector3 = normals[4]
	if center.distance_to(expected) > NORMAL_EPSILON:
		errors.append("slope_normal:%s expected:%s" % [str(center), str(expected)])
	var normal_image: Image = descriptor["normal_image"] as Image
	var decoded: Vector3 = TerrainSurfaceTextureBuilderScript.decode_normal_color(normal_image.get_pixel(1, 1))
	if decoded.distance_to(expected) > NORMAL_EPSILON:
		errors.append("slope_normal_image:%s expected:%s" % [str(decoded), str(expected)])
	var slopes: PackedFloat32Array = descriptor["slope_deg_values"] as PackedFloat32Array
	var expected_slope: float = rad_to_deg(atan(2.0))
	if absf(float(slopes[4]) - expected_slope) > FLOAT_EPSILON:
		errors.append("slope_deg:%.6f expected:%.6f" % [float(slopes[4]), expected_slope])
	var slope_image: Image = descriptor["slope_deg_image"] as Image
	if absf(slope_image.get_pixel(1, 1).r - expected_slope) > FLOAT_EPSILON:
		errors.append("slope_image:%.6f expected:%.6f" % [slope_image.get_pixel(1, 1).r, expected_slope])
	var curvature: PackedFloat32Array = descriptor["curvature_values"] as PackedFloat32Array
	if absf(float(curvature[4])) > FLOAT_EPSILON:
		errors.append("slope_curvature:%.6f" % float(curvature[4]))
	var displacement: PackedFloat32Array = descriptor["visual_displacement_values"] as PackedFloat32Array
	if absf(float(displacement[4])) > FLOAT_EPSILON:
		errors.append("slope_displacement:%.6f" % float(displacement[4]))


func _check_curved_surface(errors: Array[String]) -> void:
	var height := PackedFloat32Array()
	height.resize(9)
	for z in range(3):
		for x in range(3):
			height[z * 3 + x] = float(x * x + z * z)
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(height, 3, 1.0)
	if descriptor.get("status", "fail") != "pass":
		errors.append("curved_descriptor_failed:%s" % str(descriptor))
		return
	var curvature: PackedFloat32Array = descriptor["curvature_values"] as PackedFloat32Array
	if absf(float(curvature[4]) - 4.0) > FLOAT_EPSILON:
		errors.append("curved_curvature:%.6f" % float(curvature[4]))
	var curvature_image: Image = descriptor["curvature_image"] as Image
	if absf(curvature_image.get_pixel(1, 1).r - 4.0) > FLOAT_EPSILON:
		errors.append("curved_curvature_image:%.6f" % curvature_image.get_pixel(1, 1).r)
	var heatmap: Image = descriptor["debug_heatmap_image"] as Image
	var center: Color = heatmap.get_pixel(1, 1)
	if center.g <= 0.0:
		errors.append("curved_heatmap_curvature:%.6f" % center.g)
	var displacement: PackedFloat32Array = descriptor["visual_displacement_values"] as PackedFloat32Array
	if absf(float(displacement[0])) > FLOAT_EPSILON:
		errors.append("curved_edge_displacement:%.6f" % float(displacement[0]))
	if absf(float(displacement[4])) <= FLOAT_EPSILON:
		errors.append("curved_center_displacement:%.6f" % float(displacement[4]))
	var displacement_image: Image = descriptor["visual_displacement_image"] as Image
	if absf(displacement_image.get_pixel(1, 1).r - float(displacement[4])) > FLOAT_EPSILON:
		errors.append("curved_displacement_image:%.6f expected:%.6f" % [displacement_image.get_pixel(1, 1).r, float(displacement[4])])


func _check_invalid_size(errors: Array[String]) -> void:
	var height := PackedFloat32Array([1.0, 2.0, 3.0])
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(height, 3, 1.0)
	if descriptor.get("status", "pass") == "pass":
		errors.append("invalid_size_passed")


func _check_lightweight_descriptor(errors: Array[String]) -> void:
	var height := PackedFloat32Array()
	height.resize(9)
	for index in range(height.size()):
		height[index] = float(index)
	var descriptor: Dictionary = TerrainSurfaceTextureBuilderScript.build_descriptor(height, 3, 1.0, false, true)
	if descriptor.get("status", "fail") != "pass":
		errors.append("lightweight_descriptor_failed:%s" % str(descriptor))
		return
	if descriptor.has("slope_deg_image") or descriptor.has("curvature_image") or descriptor.has("debug_heatmap_image"):
		errors.append("lightweight_debug_maps_present")
	if not descriptor.has("visual_displacement_image"):
		errors.append("lightweight_displacement_missing")


func _report_and_quit(errors: Array[String]) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-surface-texture-builder] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-surface-texture-builder] status=pass")
	quit(0)
