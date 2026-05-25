extends SceneTree

const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const NpyFloat32ArrayScript := preload("res://worldgen_terrain/io/npy_float32_array.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var guard_errors: Array[String] = []
	_check_duplicate_kernel_ids(guard_errors)
	_check_npy_shape_validation(guard_errors)
	if not guard_errors.is_empty():
		for error in guard_errors:
			push_error(error)
		print("[wg9-runtime-pack] status=fail guard_errors=%d" % guard_errors.size())
		return 1

	var pack := RuntimeKernelPackScript.new()
	if not pack.load_default():
		for error in pack.errors:
			push_error(error)
		print("[wg9-runtime-pack] status=fail errors=%d" % pack.errors.size())
		return 1
	_check_variant_pack_count_flexibility(pack, guard_errors)
	if not guard_errors.is_empty():
		for error in guard_errors:
			push_error(error)
		print("[wg9-runtime-pack] status=fail guard_errors=%d" % guard_errors.size())
		return 1

	var report := pack.validate_runtime_sources(true)
	if report.get("status") != "pass":
		for error in report.get("errors", []):
			push_error(str(error))
		print("[wg9-runtime-pack] status=fail errors=%d" % (report.get("errors", []) as Array).size())
		return 1

	print("[wg9-runtime-pack] status=pass kernels=%d families=%d loaded=%s shape=%s" % [
		int(report["kernel_count"]),
		int(report["family_count"]),
		str(report["loaded_kernel_id"]),
		str(report["loaded_shape"]),
	])
	return 0


func _check_duplicate_kernel_ids(errors: Array[String]) -> void:
	var pack := RuntimeKernelPackScript.new()
	pack.data = {
		"schema": "worldgen9.runtime_kernel_pack.v1",
		"kernels": [],
		"runtime_defaults": {},
		"families": {},
	}
	pack.kernels = [
		{"id": "duplicate", "family": "a", "artifacts": {}},
		{"id": "duplicate", "family": "b", "artifacts": {}},
	]
	pack._rebuild_kernel_index()
	if pack.errors.is_empty():
		errors.append("duplicate_kernel_id_not_rejected")


func _check_npy_shape_validation(errors: Array[String]) -> void:
	if not NpyFloat32ArrayScript._parse_shape("{'shape': (512, abc), }").is_empty():
		errors.append("npy_shape_accepted_non_integer")
	if not NpyFloat32ArrayScript._parse_shape("{'shape': (512.0, 512), }").is_empty():
		errors.append("npy_shape_accepted_float_dimension")
	if not NpyFloat32ArrayScript._parse_shape("{'shape': (-1, 512), }").is_empty():
		errors.append("npy_shape_accepted_negative_dimension")


func _check_variant_pack_count_flexibility(source_pack: RefCounted, errors: Array[String]) -> void:
	if source_pack.kernels.is_empty():
		errors.append("variant_source_pack_empty")
		return
	var kernel: Dictionary = (source_pack.kernels[0] as Dictionary).duplicate(true)
	var family: String = str(kernel.get("family", ""))
	var family_data: Dictionary = (source_pack.families.get(family, {}) as Dictionary).duplicate(true)
	var variant := RuntimeKernelPackScript.new()
	var variant_data: Dictionary = source_pack.data.duplicate(true)
	variant_data["kernel_count"] = 1
	variant_data["kernels"] = [kernel]
	variant_data["families"] = {family: family_data}
	variant.data = variant_data
	variant.kernels = variant_data["kernels"] as Array
	variant.families = variant_data["families"] as Dictionary
	variant.runtime_defaults = variant_data["runtime_defaults"] as Dictionary
	variant._rebuild_kernel_index()
	var report: Dictionary = variant.validate_runtime_sources(false)
	if report.get("status", "fail") != "pass":
		errors.append("variant_pack_rejected:%s" % str(report.get("errors", [])))
