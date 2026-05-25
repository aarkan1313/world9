extends SceneTree

const FLOAT_EPSILON := 0.000001


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
		_report(errors)
		return
	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	if backend == null:
		errors.append("native_backend_instantiate_failed")
		_report(errors)
		return
	var count := 5
	var spacing := 1.0
	var outer_extent := 2.0
	var inner_extent := 1.0
	var height := PackedFloat32Array()
	height.resize(count * count)
	for z in range(count):
		for x in range(count):
			height[z * count + x] = float(x + z * 10)
	var native: Dictionary = backend.call(
		"build_clipmap_mesh_payload_from_height",
		height,
		count,
		spacing,
		outer_extent,
		inner_extent
	) as Dictionary
	if native.get("status", "fail") != "pass":
		errors.append("native_failed:%s" % str(native))
		_report(errors)
		return
	var vertices: PackedVector3Array = native["vertices"] as PackedVector3Array
	var normals: PackedVector3Array = native["normals"] as PackedVector3Array
	var uvs: PackedVector2Array = native["uvs"] as PackedVector2Array
	var indices: PackedInt32Array = native["indices"] as PackedInt32Array
	if vertices.size() != count * count:
		errors.append("vertex_count:%d" % vertices.size())
	if normals.size() != count * count:
		errors.append("normal_count:%d" % normals.size())
	if uvs.size() != count * count:
		errors.append("uv_count:%d" % uvs.size())
	_check_vec3(vertices[0], Vector3(-2.0, 0.0, -2.0), "vertex_0", errors)
	_check_vec3(vertices[12], Vector3(0.0, 22.0, 0.0), "vertex_center", errors)
	_check_vec2(uvs[0], Vector2(0.0, 0.0), "uv_0", errors)
	_check_vec2(uvs[24], Vector2(1.0, 1.0), "uv_24", errors)
	var expected_indices: PackedInt32Array = _expected_clipmap_indices(count, spacing, outer_extent, inner_extent)
	if indices != expected_indices:
		errors.append("indices_mismatch:%d expected:%d" % [indices.size(), expected_indices.size()])
	_check_invalid_clipmap_inputs(backend, height, count, spacing, outer_extent, errors)
	_report(errors, indices.size())


func _check_invalid_clipmap_inputs(
	backend: Object,
	height: PackedFloat32Array,
	count: int,
	spacing: float,
	outer_extent: float,
	errors: Array[String]
) -> void:
	var zero_step: Dictionary = backend.call("build_clipmap_mesh_payload_from_height", height, count, 0.0, outer_extent, 1.0) as Dictionary
	if zero_step.get("status", "pass") != "fail":
		errors.append("clipmap_zero_step_passed:%s" % str(zero_step))
	var bad_inner: Dictionary = backend.call("build_clipmap_mesh_payload_from_height", height, count, spacing, outer_extent, outer_extent) as Dictionary
	if bad_inner.get("status", "pass") != "fail":
		errors.append("clipmap_bad_inner_passed:%s" % str(bad_inner))


func _expected_clipmap_indices(count: int, spacing: float, outer_extent: float, inner_extent: float) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for z in range(count - 1):
		var z_center: float = -outer_extent + (float(z) + 0.5) * spacing
		for x in range(count - 1):
			var x_center: float = -outer_extent + (float(x) + 0.5) * spacing
			if absf(x_center) < inner_extent and absf(z_center) < inner_extent:
				continue
			var row: int = z * count
			var next_row: int = (z + 1) * count
			var a: int = row + x
			var b: int = row + x + 1
			var c: int = next_row + x
			var d: int = next_row + x + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	return indices


func _check_vec3(actual: Vector3, expected: Vector3, label: String, errors: Array[String]) -> void:
	if actual.distance_to(expected) > FLOAT_EPSILON:
		errors.append("%s:%s expected:%s" % [label, str(actual), str(expected)])


func _check_vec2(actual: Vector2, expected: Vector2, label: String, errors: Array[String]) -> void:
	if actual.distance_to(expected) > FLOAT_EPSILON:
		errors.append("%s:%s expected:%s" % [label, str(actual), str(expected)])


func _report(errors: Array[String], index_count: int = 0) -> void:
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-native-clipmap-mesh-payload] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-native-clipmap-mesh-payload] status=pass indices=%d" % index_count)
	quit(0)
