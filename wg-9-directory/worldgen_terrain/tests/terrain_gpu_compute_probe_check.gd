extends SceneTree

const TerrainGpuComputeProbeScript := preload("res://worldgen_terrain/core/terrain_gpu_compute_probe.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var probe = TerrainGpuComputeProbeScript.new()
	var result: Dictionary = probe.run_float_buffer_probe(128)
	if result.get("status", "fail") == "unsupported":
		print("[wg9-gpu-compute-probe] status=unsupported result=%s" % str(result))
		quit(0)
		return
	if result.get("status", "fail") != "pass":
		errors.append("float_buffer_probe_failed:%s" % str(result))
	if int(result.get("count", 0)) != 128:
		errors.append("float_buffer_probe_count:%s" % str(result))
	if float(result.get("max_delta", 1.0)) > 0.00001:
		errors.append("float_buffer_probe_delta:%s" % str(result))
	var normal_result: Dictionary = probe.run_height_normal_probe(16, 2.0)
	if normal_result.get("status", "fail") != "pass":
		errors.append("height_normal_probe_failed:%s" % str(normal_result))
	if float(normal_result.get("max_delta", 1.0)) > 0.0001:
		errors.append("height_normal_probe_delta:%s" % str(normal_result))
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-compute-probe] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-compute-probe] status=pass float=%s normal=%s" % [str(result), str(normal_result)])
	quit(0)
