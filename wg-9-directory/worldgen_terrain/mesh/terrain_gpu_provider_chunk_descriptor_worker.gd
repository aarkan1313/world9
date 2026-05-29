class_name TerrainGpuProviderChunkDescriptorWorker
extends RefCounted

const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")

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
			"cache_key": str(request.get("cache_key", "")),
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
	var result: Dictionary = _build_descriptor_blocks(request)
	result["worker_elapsed_ms"] = Time.get_ticks_msec() - started_ms
	_mutex.lock()
	_result = result
	_done = true
	_mutex.unlock()


func _build_descriptor_blocks(request: Dictionary) -> Dictionary:
	var descriptor_builder = TerrainGpuHeightPageBackendScript.new()
	var descriptor_blocks: Array = []
	var blocks: Array = request.get("blocks", []) as Array
	var step_m: float = float(request.get("step_m", 0.0))
	var count: int = int(request.get("count", 0))
	var world_seed: int = int(request.get("world_seed", 0))
	var region_size_m: float = float(request.get("region_size_m", 0.0))
	for block_value in blocks:
		var block: Dictionary = block_value as Dictionary
		var descriptor: Dictionary = descriptor_builder.build_prepared_provider_page_descriptor(
			block.get("prepared_request", {}) as Dictionary,
			float(block.get("origin_x", 0.0)),
			float(block.get("origin_z", 0.0)),
			step_m,
			int(block.get("count_x", count)),
			int(block.get("count_z", count)),
			world_seed,
			region_size_m
		)
		if descriptor.get("status", "fail") != "pass":
			return {
				"status": "fail",
				"error": str(descriptor.get("error", "descriptor_failed")),
				"cache_key": str(request.get("cache_key", "")),
			}
		descriptor_blocks.append({
			"descriptor": descriptor,
			"offset_x": int(block.get("offset_x", 0)),
			"offset_z": int(block.get("offset_z", 0)),
		})
	return {
		"status": "pass",
		"cache_key": str(request.get("cache_key", "")),
		"descriptor_blocks": descriptor_blocks,
	}
