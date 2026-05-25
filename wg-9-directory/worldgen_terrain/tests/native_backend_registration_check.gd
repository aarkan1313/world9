extends SceneTree


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		errors.append("native_class_not_registered")
	else:
		var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
		if backend == null:
			errors.append("native_class_instantiate_failed")
		else:
			var status: Dictionary = backend.call("debug_status") as Dictionary
			if str(status.get("status", "")) != "registered":
				errors.append("unexpected_status:%s" % str(status))
			if bool(status.get("supports_mesh_payload_generation", false)) != true:
				errors.append("native_mesh_payload_not_supported:%s" % str(status))
			if bool(status.get("supports_threaded_calls", false)) != true:
				errors.append("native_threaded_calls_not_supported:%s" % str(status))
			var metrics: Dictionary = backend.call("chunk_grid_metrics", {
				"vertices_per_side": 129,
				"chunk_size_m": 512.0,
			}) as Dictionary
			if absf(float(metrics.get("sample_spacing_m", 0.0)) - 4.0) > 0.0001:
				errors.append("spacing_mismatch:%s" % str(metrics))
			if int(metrics.get("triangle_count", 0)) != 32768:
				errors.append("triangle_count_mismatch:%s" % str(metrics))
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-native-backend] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-native-backend] status=pass class=Wg9TerrainNativeBackend spacing=4.0m triangles=32768")
	quit(0)
