class_name TerrainNativeChunkPayloadWorker
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


func start(prepared_request: Dictionary) -> bool:
	if _started:
		return false
	_started = true
	_done = false
	_result = {}
	_thread = Thread.new()
	var start_result: Error = _thread.start(_thread_main.bind(prepared_request.duplicate(true)))
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


func _thread_main(prepared_request: Dictionary) -> void:
	var started_ms: int = Time.get_ticks_msec()
	var result: Dictionary = _build_native_payload(prepared_request)
	result["worker_elapsed_ms"] = Time.get_ticks_msec() - started_ms
	_mutex.lock()
	_result = result
	_done = true
	_mutex.unlock()


func _build_native_payload(prepared_request: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("Wg9TerrainNativeBackend"):
		return {
			"status": "fail",
			"error": "native_class_not_registered",
		}
	var backend: Object = ClassDB.instantiate("Wg9TerrainNativeBackend")
	if backend == null:
		return {
			"status": "fail",
			"error": "native_backend_instantiate_failed",
		}
	var native: Dictionary = backend.call(
		"build_chunk_payload_prepared",
		float(prepared_request["origin_x"]),
		float(prepared_request["origin_z"]),
		float(prepared_request["step_m"]),
		int(prepared_request["count"]),
		int(prepared_request["world_seed"]),
		float(prepared_request["region_size_m"]),
		int(prepared_request["base_rx"]),
		int(prepared_request["base_rz"]),
		prepared_request["corner_entries"] as Array
	) as Dictionary
	if native.get("status", "fail") == "pass" and bool(prepared_request.get("include_visual_displacement", false)):
		var displacement: Dictionary = backend.call(
			"build_visual_displacement_from_height",
			native["height"] as PackedFloat32Array,
			int(prepared_request["count"]),
			1
		) as Dictionary
		if displacement.get("status", "fail") == "pass":
			native["visual_displacement_values"] = displacement["values"] as PackedFloat32Array
			native["visual_displacement_max_abs_m"] = float(displacement["max_abs_m"])
		else:
			native["status"] = "fail"
			native["error"] = "visual_displacement:%s" % str(displacement.get("error", "unknown"))
	native["worker_request_id"] = str(prepared_request.get("request_id", ""))
	return native
