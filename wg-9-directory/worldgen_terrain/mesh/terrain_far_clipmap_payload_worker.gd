class_name TerrainFarClipmapPayloadWorker
extends RefCounted

var _thread: Thread
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _done := false
var _started := false

static var _detached_workers: Array = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func start(request: Dictionary) -> bool:
	if _started:
		return false
	_started = true
	_done = false
	_result = {}
	_thread = Thread.new()
	var start_result: Error = _thread.start(_thread_main.bind(request.duplicate(true)))
	if start_result != OK:
		_result = {
			"status": "fail",
			"error": "thread_start:%d" % int(start_result),
		}
		_done = true
		return false
	return true


func is_done() -> bool:
	_mutex.lock()
	var value: bool = _done
	_mutex.unlock()
	return value


func take_result() -> Dictionary:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_mutex.lock()
	var value: Dictionary = _result
	_mutex.unlock()
	return value


func detach_until_done() -> void:
	if is_done():
		take_result()
		return
	if not _detached_workers.has(self):
		_detached_workers.append(self)


static func cleanup_detached_workers(max_to_clean: int = 0, wait_for_running: bool = false, timeout_msec: int = 5000) -> int:
	var cleaned := 0
	var limit: int = max_to_clean if max_to_clean > 0 else 2147483647
	for index in range(_detached_workers.size() - 1, -1, -1):
		var worker: RefCounted = _detached_workers[index] as RefCounted
		if worker == null:
			_detached_workers.remove_at(index)
			continue
		if not worker.call("is_done"):
			if not wait_for_running:
				continue
			worker.call("wait_for_result", timeout_msec)
		else:
			worker.call("take_result")
		_detached_workers.remove_at(index)
		cleaned += 1
		if cleaned >= limit:
			break
	return cleaned


func wait_for_result(timeout_msec: int = 5000) -> Dictionary:
	var started_ms: int = Time.get_ticks_msec()
	while not is_done():
		if Time.get_ticks_msec() - started_ms > timeout_msec:
			return {
				"status": "fail",
				"error": "worker_timeout:%d" % timeout_msec,
			}
		OS.delay_msec(1)
	return take_result()


func _thread_main(request: Dictionary) -> void:
	var started_ms: int = Time.get_ticks_msec()
	var result: Dictionary = _build_payload(request)
	result["worker_elapsed_ms"] = Time.get_ticks_msec() - started_ms
	_mutex.lock()
	_result = result
	_done = true
	_mutex.unlock()


func _build_payload(request: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return {"status": "fail", "error": "native_class_not_registered"}
	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	if backend == null:
		return {"status": "fail", "error": "native_backend_instantiate_failed"}
	var side: int = int(request["side"])
	var height := PackedFloat32Array()
	height.resize(side * side)
	for block_value in request.get("blocks", []) as Array:
		var block: Dictionary = block_value as Dictionary
		var native: Dictionary = backend.call(
			"sample_height_grid_prepared",
			float(block["origin_x"]),
			float(block["origin_z"]),
			float(request["spacing_m"]),
			int(block["count_x"]),
			int(block["count_z"]),
			int(request["world_seed"]),
			float(request["region_size_m"]),
			int(block["base_rx"]),
			int(block["base_rz"]),
			block["corner_entries"] as Array
		) as Dictionary
		var native_status: String = str(native["status"]) if native.has("status") else "fail"
		if native_status != "pass":
			return {
				"status": "fail",
				"error": "height_block:%s" % (str(native["error"]) if native.has("error") else "unknown"),
				"level": int(request["level"]),
			}
		var values: PackedFloat32Array = native["values"] as PackedFloat32Array
		var x0: int = int(block["x0"])
		var z0: int = int(block["z0"])
		var count_x: int = int(block["count_x"])
		var count_z: int = int(block["count_z"])
		for local_z in range(count_z):
			var src_row: int = local_z * count_x
			var dst_row: int = (z0 + local_z) * side
			for local_x in range(count_x):
				height[dst_row + x0 + local_x] = values[src_row + local_x]
	if bool(request.get("height_page_only", false)):
		if bool(request.get("height_image_only", false)):
			return {
				"status": "pass",
				"payload_mode": "height_page",
				"height": height,
				"height_image_data": _height_image_data_from_height(height, side),
				"texture_payload_mode": "native_height_image_data",
				"height_image_only": true,
				"level": int(request["level"]),
				"origin_x": float(request["origin_x"]),
				"origin_z": float(request["origin_z"]),
				"outer_extent_m": float(request["outer_extent_m"]),
				"inner_extent_m": float(request["inner_extent_m"]),
				"spacing_m": float(request["spacing_m"]),
				"side": side,
				"request_id": str(request["request_id"]),
				"render_context_key": str(request.get("render_context_key", "")),
				"render_context_version": int(request.get("render_context_version", 0)),
			}
		var normal_payload: Dictionary = backend.call(
			"build_normal_payload_from_height",
			height,
			side,
			float(request["spacing_m"])
		) as Dictionary
		var normal_status: String = str(normal_payload["status"]) if normal_payload.has("status") else "fail"
		if normal_status != "pass":
			return {
				"status": "fail",
				"error": "normal_payload:%s" % (str(normal_payload["error"]) if normal_payload.has("error") else "unknown"),
				"level": int(request["level"]),
			}
		var normals: PackedVector3Array = normal_payload["normals"] as PackedVector3Array
		var texture_payload: Dictionary = backend.call(
			"build_page_texture_data_from_height_normals",
			height,
			normals,
			side
		) as Dictionary
		var texture_status: String = str(texture_payload["status"]) if texture_payload.has("status") else "fail"
		if texture_status != "pass":
			return {
				"status": "fail",
				"error": "texture_payload:%s" % (str(texture_payload["error"]) if texture_payload.has("error") else "unknown"),
				"level": int(request["level"]),
			}
		return {
			"status": "pass",
			"payload_mode": "height_page",
			"height": height,
			"normals": normals,
			"height_image_data": texture_payload["height_image_data"] as PackedByteArray,
			"normal_image_data": texture_payload["normal_image_data"] as PackedByteArray,
			"texture_payload_mode": "native_image_data",
			"level": int(request["level"]),
			"origin_x": float(request["origin_x"]),
			"origin_z": float(request["origin_z"]),
			"outer_extent_m": float(request["outer_extent_m"]),
			"inner_extent_m": float(request["inner_extent_m"]),
			"spacing_m": float(request["spacing_m"]),
			"side": side,
			"request_id": str(request["request_id"]),
			"render_context_key": str(request.get("render_context_key", "")),
			"render_context_version": int(request.get("render_context_version", 0)),
		}
	var mesh: Dictionary = backend.call(
		"build_clipmap_mesh_payload_from_height",
		height,
		side,
		float(request["spacing_m"]),
		float(request["outer_extent_m"]),
		float(request["inner_extent_m"])
	) as Dictionary
	var mesh_status: String = str(mesh["status"]) if mesh.has("status") else "fail"
	if mesh_status != "pass":
		return {
			"status": "fail",
			"error": "clipmap_mesh:%s" % (str(mesh["error"]) if mesh.has("error") else "unknown"),
			"level": int(request["level"]),
		}
	mesh["height"] = height
	mesh["level"] = int(request["level"])
	mesh["origin_x"] = float(request["origin_x"])
	mesh["origin_z"] = float(request["origin_z"])
	mesh["outer_extent_m"] = float(request["outer_extent_m"])
	mesh["inner_extent_m"] = float(request["inner_extent_m"])
	mesh["spacing_m"] = float(request["spacing_m"])
	mesh["side"] = side
	mesh["request_id"] = str(request["request_id"])
	mesh["render_context_key"] = str(request.get("render_context_key", ""))
	mesh["render_context_version"] = int(request.get("render_context_version", 0))
	mesh["payload_mode"] = "mesh_payload"
	return mesh


func _height_image_data_from_height(height: PackedFloat32Array, side: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(side * side * 4)
	var limit: int = min(height.size(), side * side)
	for index in range(limit):
		data.encode_float(index * 4, float(height[index]))
	return data
