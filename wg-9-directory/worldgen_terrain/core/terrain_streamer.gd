class_name TerrainStreamer
extends RefCounted

const TerrainChunkScript := preload("res://worldgen_terrain/core/terrain_chunk.gd")

const QUEUE_POLICY_PRIORITY_CANCEL := "priority_cancel"
const QUEUE_POLICY_FIFO := "fifo"

var chunk_size_m: float = 2048.0
var visible_radius_chunks: int = 4
var max_lod: int = 4
var build_budget_per_frame: int = 2
var queue_policy: String = QUEUE_POLICY_PRIORITY_CANCEL
var prefetch_forward_chunks: int = 0
var residency_halo_chunks: int = 0
var active: Dictionary = {}
var queued_builds: Array[String] = []
var step_index: int = 0
var priority_direction := Vector2.ZERO
var errors: Array[String] = []


func setup(settings: Dictionary) -> bool:
	errors = _validate_settings(settings)
	if not errors.is_empty():
		return false
	chunk_size_m = float(settings["chunk_size_m"])
	visible_radius_chunks = int(settings["visible_radius_chunks"])
	max_lod = int(settings["max_lod"])
	build_budget_per_frame = int(settings["build_budget_per_frame"])
	queue_policy = str(settings["queue_policy"])
	prefetch_forward_chunks = max(0, int(settings.get("prefetch_forward_chunks", 0)))
	residency_halo_chunks = max(0, int(settings.get("residency_halo_chunks", 0)))
	reset()
	return true


func reset() -> void:
	active.clear()
	queued_builds.clear()
	step_index = 0
	priority_direction = Vector2.ZERO


func set_priority_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.000001:
		priority_direction = direction.normalized()
	else:
		priority_direction = Vector2.ZERO


func expected_active_count() -> int:
	return wanted_chunks(Vector2i.ZERO, visible_radius_chunks, max_lod, priority_direction, prefetch_forward_chunks, residency_halo_chunks).size()


func update_viewer(point: Vector2) -> Dictionary:
	var center: Vector2i = viewer_chunk(point, chunk_size_m)
	var wanted: Dictionary = wanted_chunks(center, visible_radius_chunks, max_lod, priority_direction, prefetch_forward_chunks, residency_halo_chunks)
	var created: Array[String] = _sorted_difference(wanted, active)
	var retired: Array[String] = _sorted_difference(active, wanted)
	var kept: Array[String] = _sorted_intersection(wanted, active)
	var lod_changed: Array[String] = []
	for key in kept:
		var active_chunk: RefCounted = active[key] as RefCounted
		var wanted_chunk: RefCounted = wanted[key] as RefCounted
		if active_chunk.lod != wanted_chunk.lod:
			lod_changed.append(key)

	var cancelled: int = 0
	for key in retired:
		active.erase(key)
		var queue_index: int = queued_builds.find(key)
		if queue_index >= 0:
			queued_builds.remove_at(queue_index)
			cancelled += 1
	for key in created:
		active[key] = wanted[key]
		_enqueue_unique(queued_builds, key)
	for key in lod_changed:
		active[key] = wanted[key]
		_enqueue_unique(queued_builds, key)

	if queue_policy == QUEUE_POLICY_PRIORITY_CANCEL:
		var before: int = queued_builds.size()
		queued_builds = _filter_wanted_queue(queued_builds, wanted)
		cancelled += before - queued_builds.size()
		_prioritize_queue(queued_builds, wanted, center, priority_direction)
	elif queue_policy != QUEUE_POLICY_FIFO:
		return {
			"step": step_index,
			"status": "fail",
			"errors": ["unknown queue policy: %s" % queue_policy],
		}

	var build_now: Array[String] = _take_front(queued_builds, build_budget_per_frame)
	queued_builds = _drop_front(queued_builds, build_budget_per_frame)
	var build_now_rings: Array[int] = []
	for key in build_now:
		var ring_value := -1
		if wanted.has(key):
			var build_chunk: RefCounted = wanted[key] as RefCounted
			ring_value = build_chunk.ring
		build_now_rings.append(ring_value)

	var report: Dictionary = {
		"step": step_index,
		"viewer_world": [point.x, point.y],
		"viewer_chunk": [center.x, center.y],
		"active_count": active.size(),
		"expected_active_count": wanted.size(),
		"visible_radius_chunks": visible_radius_chunks,
		"created_count": created.size(),
		"retired_count": retired.size(),
		"lod_changed_count": lod_changed.size(),
		"cancelled_count": cancelled,
		"build_now_count": build_now.size(),
		"build_now_rings": build_now_rings,
		"queued_build_count": queued_builds.size(),
		"lod_counts": _lod_counts(wanted),
		"active_chunks": _chunk_list(wanted),
		"created": _coord_list(created),
		"retired": _coord_list(retired),
		"lod_changed": _coord_list(lod_changed),
		"build_now": _coord_list(build_now),
		"status": "pass",
	}
	if prefetch_forward_chunks > 0:
		report["base_active_count"] = _base_active_count(visible_radius_chunks)
		report["prefetch_forward_chunks"] = prefetch_forward_chunks
		report["prefetch_step"] = _prefetch_step_array(priority_direction)
	if residency_halo_chunks > 0:
		report["residency_halo_chunks"] = residency_halo_chunks
	step_index += 1
	return report


static func viewer_chunk(point: Vector2, p_chunk_size_m: float) -> Vector2i:
	return Vector2i(int(floor(point.x / p_chunk_size_m)), int(floor(point.y / p_chunk_size_m)))


static func lod_for_ring(ring: int, p_max_lod: int) -> int:
	if ring <= 1:
		return 0
	return min(p_max_lod, ring - 1)


static func wanted_chunks(
	center: Vector2i,
	visible_radius: int,
	p_max_lod: int,
	direction: Vector2 = Vector2.ZERO,
	prefetch_steps: int = 0,
	halo_chunks: int = 0
) -> Dictionary:
	var result: Dictionary = {}
	_merge_wanted_chunks_for_center(result, center, visible_radius + max(0, halo_chunks), p_max_lod)
	var step: Vector2i = _prefetch_step_from_direction(direction)
	for prefetch_index in range(1, max(0, prefetch_steps) + 1):
		if step == Vector2i.ZERO:
			break
		_merge_wanted_chunks_for_center(result, center + step * prefetch_index, visible_radius, p_max_lod)
	return result


static func _merge_wanted_chunks_for_center(result: Dictionary, center: Vector2i, visible_radius: int, p_max_lod: int) -> void:
	for dz in range(-visible_radius, visible_radius + 1):
		for dx in range(-visible_radius, visible_radius + 1):
			var chunk_x: int = center.x + dx
			var chunk_z: int = center.y + dz
			var key := "%d,%d" % [chunk_x, chunk_z]
			if result.has(key):
				continue
			var ring: int = max(abs(dx), abs(dz))
			var chunk: RefCounted = TerrainChunkScript.new(chunk_x, chunk_z, ring, lod_for_ring(ring, p_max_lod))
			result[chunk.key()] = chunk


static func simulate(path: PackedVector2Array, settings: Dictionary) -> Dictionary:
	var settings_errors: Array[String] = _validate_settings(settings)
	if not settings_errors.is_empty():
		return _failed_report("invalid settings: %s" % ", ".join(settings_errors))
	var sim_chunk_size_m: float = float(settings["chunk_size_m"])
	var visible_radius: int = int(settings["visible_radius_chunks"])
	var sim_max_lod: int = int(settings["max_lod"])
	var sim_build_budget_per_frame: int = int(settings["build_budget_per_frame"])
	var sim_queue_policy: String = str(settings["queue_policy"])
	var sim_prefetch_forward_chunks: int = max(0, int(settings.get("prefetch_forward_chunks", 0)))
	var sim_residency_halo_chunks: int = max(0, int(settings.get("residency_halo_chunks", 0)))
	var derive_priority_direction: bool = bool(settings.get("derive_priority_direction_from_path", false))
	var fixed_priority_direction: Vector2 = _priority_direction_from_settings(settings.get("priority_direction", Vector2.ZERO))
	var sim_active: Dictionary = {}
	var sim_queued_builds: Array[String] = []
	var steps: Array[Dictionary] = []
	var max_active_count: int = 0
	var max_expected_count: int = 0
	var total_created: int = 0
	var total_retired: int = 0
	var total_lod_changed: int = 0
	var build_ring_values: Array[int] = []

	for sim_step_index in range(path.size()):
		var point: Vector2 = path[sim_step_index]
		var center: Vector2i = viewer_chunk(point, sim_chunk_size_m)
		var sim_priority_direction: Vector2 = fixed_priority_direction
		if derive_priority_direction and sim_step_index > 0:
			var delta: Vector2 = point - path[sim_step_index - 1]
			if delta.length_squared() > 0.000001:
				sim_priority_direction = delta.normalized()
		var wanted: Dictionary = wanted_chunks(center, visible_radius, sim_max_lod, sim_priority_direction, sim_prefetch_forward_chunks, sim_residency_halo_chunks)
		var expected_count: int = wanted.size()
		max_expected_count = max(max_expected_count, expected_count)
		var created: Array[String] = _sorted_difference(wanted, sim_active)
		var retired: Array[String] = _sorted_difference(sim_active, wanted)
		var kept: Array[String] = _sorted_intersection(wanted, sim_active)
		var lod_changed: Array[String] = []
		for key in kept:
			var active_chunk: RefCounted = sim_active[key] as RefCounted
			var wanted_chunk: RefCounted = wanted[key] as RefCounted
			if active_chunk.lod != wanted_chunk.lod:
				lod_changed.append(key)

		var cancelled: int = 0
		for key in retired:
			sim_active.erase(key)
			var queue_index: int = sim_queued_builds.find(key)
			if queue_index >= 0:
				sim_queued_builds.remove_at(queue_index)
				cancelled += 1
		for key in created:
			sim_active[key] = wanted[key]
			_enqueue_unique(sim_queued_builds, key)
		for key in lod_changed:
			sim_active[key] = wanted[key]
			_enqueue_unique(sim_queued_builds, key)

		if sim_queue_policy == QUEUE_POLICY_PRIORITY_CANCEL:
			var before: int = sim_queued_builds.size()
			sim_queued_builds = _filter_wanted_queue(sim_queued_builds, wanted)
			cancelled += before - sim_queued_builds.size()
			_prioritize_queue(sim_queued_builds, wanted, center, sim_priority_direction)
		elif sim_queue_policy != QUEUE_POLICY_FIFO:
			return _failed_report("unknown queue policy: %s" % sim_queue_policy)

		var build_now: Array[String] = _take_front(sim_queued_builds, sim_build_budget_per_frame)
		sim_queued_builds = _drop_front(sim_queued_builds, sim_build_budget_per_frame)
		var build_now_rings: Array[int] = []
		for key in build_now:
			var ring_value := -1
			if wanted.has(key):
				var build_chunk: RefCounted = wanted[key] as RefCounted
				ring_value = build_chunk.ring
			build_now_rings.append(ring_value)
			if ring_value >= 0:
				build_ring_values.append(ring_value)

		max_active_count = max(max_active_count, sim_active.size())
		total_created += created.size()
		total_retired += retired.size()
		total_lod_changed += lod_changed.size()

		var step_report: Dictionary = {
			"step": sim_step_index,
			"viewer_world": [point.x, point.y],
			"viewer_chunk": [center.x, center.y],
			"active_count": sim_active.size(),
			"expected_active_count": expected_count,
			"visible_radius_chunks": visible_radius,
			"created_count": created.size(),
			"retired_count": retired.size(),
			"lod_changed_count": lod_changed.size(),
			"cancelled_count": cancelled,
			"build_now_count": build_now.size(),
			"build_now_rings": build_now_rings,
			"queued_build_count": sim_queued_builds.size(),
			"lod_counts": _lod_counts(wanted),
			"active_chunks": _chunk_list(wanted),
			"created": _coord_list(created),
			"retired": _coord_list(retired),
			"lod_changed": _coord_list(lod_changed),
			"build_now": _coord_list(build_now),
		}
		if sim_prefetch_forward_chunks > 0:
			step_report["base_active_count"] = _base_active_count(visible_radius)
			step_report["prefetch_forward_chunks"] = sim_prefetch_forward_chunks
			step_report["prefetch_step"] = _prefetch_step_array(sim_priority_direction)
		if sim_residency_halo_chunks > 0:
			step_report["residency_halo_chunks"] = sim_residency_halo_chunks
		steps.append(step_report)

	var errors: Array[String] = []
	if max_active_count > max_expected_count:
		errors.append("active_count_exceeded_expected")
	for step_value in steps:
		var step: Dictionary = step_value
		if int(step["active_count"]) != int(step["expected_active_count"]):
			errors.append("active_count_not_expected_at_step_%d" % int(step["step"]))

	var report_settings: Dictionary = {
		"chunk_size_m": sim_chunk_size_m,
		"visible_radius_chunks": visible_radius,
		"max_lod": sim_max_lod,
		"build_budget_per_frame": sim_build_budget_per_frame,
		"queue_policy": sim_queue_policy,
		"expected_active_count": wanted_chunks(Vector2i.ZERO, visible_radius, sim_max_lod, fixed_priority_direction, sim_prefetch_forward_chunks, sim_residency_halo_chunks).size(),
	}
	if sim_prefetch_forward_chunks > 0:
		report_settings["prefetch_forward_chunks"] = sim_prefetch_forward_chunks
		report_settings["base_active_count"] = _base_active_count(visible_radius)
	if fixed_priority_direction.length_squared() > 0.000001:
		report_settings["priority_direction"] = [fixed_priority_direction.x, fixed_priority_direction.y]
	if derive_priority_direction:
		report_settings["derive_priority_direction_from_path"] = derive_priority_direction
	if sim_residency_halo_chunks > 0:
		report_settings["residency_halo_chunks"] = sim_residency_halo_chunks
	return {
		"version": 1,
		"schema": "worldgen9.streamer_reference.v1",
		"settings": report_settings,
		"summary": {
			"steps": steps.size(),
			"max_active_count": max_active_count,
			"total_created": total_created,
			"total_retired": total_retired,
			"total_lod_changed": total_lod_changed,
			"final_queued_build_count": sim_queued_builds.size(),
			"built_count": build_ring_values.size(),
			"mean_built_ring": _mean_int(build_ring_values),
			"max_built_ring": _max_int(build_ring_values),
		},
		"steps": steps,
		"errors": errors,
		"status": "pass" if errors.is_empty() else "fail",
	}


static func path_from_reference(report: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for step_value in report.get("steps", []) as Array:
		var step: Dictionary = step_value as Dictionary
		var world: Array = step["viewer_world"] as Array
		result.append(Vector2(float(world[0]), float(world[1])))
	return result


static func _failed_report(message: String) -> Dictionary:
	return {
		"version": 1,
		"schema": "worldgen9.streamer_reference.v1",
		"errors": [message],
		"status": "fail",
	}


static func _validate_settings(settings: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var required_keys: Array[String] = [
		"chunk_size_m",
		"visible_radius_chunks",
		"max_lod",
		"build_budget_per_frame",
		"queue_policy",
	]
	for key in required_keys:
		if not settings.has(key):
			result.append("missing:%s" % key)
	if not result.is_empty():
		return result
	var size_m: float = float(settings["chunk_size_m"])
	if not is_finite(size_m) or size_m <= 0.0:
		result.append("invalid_chunk_size_m")
	if int(settings["visible_radius_chunks"]) < 0:
		result.append("invalid_visible_radius_chunks")
	if int(settings["max_lod"]) < 0:
		result.append("invalid_max_lod")
	if int(settings["build_budget_per_frame"]) <= 0:
		result.append("invalid_build_budget_per_frame")
	if int(settings.get("prefetch_forward_chunks", 0)) < 0:
		result.append("invalid_prefetch_forward_chunks")
	if int(settings.get("residency_halo_chunks", 0)) < 0:
		result.append("invalid_residency_halo_chunks")
	var policy: String = str(settings["queue_policy"])
	if policy != QUEUE_POLICY_PRIORITY_CANCEL and policy != QUEUE_POLICY_FIFO:
		result.append("invalid_queue_policy:%s" % policy)
	return result


static func _priority_direction_from_settings(value: Variant) -> Vector2:
	var direction := Vector2.ZERO
	if value is Vector2:
		direction = value
	elif value is Array:
		var array_value: Array = value as Array
		if array_value.size() >= 2:
			direction = Vector2(float(array_value[0]), float(array_value[1]))
	elif value is Dictionary:
		var dict_value: Dictionary = value as Dictionary
		direction = Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
	if direction.length_squared() > 0.000001:
		return direction.normalized()
	return Vector2.ZERO


static func _base_active_count(visible_radius: int) -> int:
	return (visible_radius * 2 + 1) * (visible_radius * 2 + 1)


static func _prefetch_step_array(direction: Vector2) -> Array[int]:
	var step: Vector2i = _prefetch_step_from_direction(direction)
	return [step.x, step.y]


static func _prefetch_step_from_direction(direction: Vector2) -> Vector2i:
	if direction.length_squared() <= 0.000001:
		return Vector2i.ZERO
	var normalized: Vector2 = direction.normalized()
	var step_x := 0
	var step_z := 0
	if absf(normalized.x) >= 0.35:
		step_x = 1 if normalized.x > 0.0 else -1
	if absf(normalized.y) >= 0.35:
		step_z = 1 if normalized.y > 0.0 else -1
	if step_x == 0 and step_z == 0:
		if absf(normalized.x) >= absf(normalized.y):
			step_x = 1 if normalized.x > 0.0 else -1
		else:
			step_z = 1 if normalized.y > 0.0 else -1
	return Vector2i(step_x, step_z)


static func _sorted_difference(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value in left.keys():
		var key: String = str(key_value)
		if not right.has(key):
			result.append(key)
	_sort_coord_keys(result)
	return result


static func _sorted_intersection(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value in left.keys():
		var key: String = str(key_value)
		if right.has(key):
			result.append(key)
	_sort_coord_keys(result)
	return result


static func _sort_coord_keys(keys: Array[String]) -> void:
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ax: int = _key_x(a)
		var bx: int = _key_x(b)
		if ax == bx:
			return _key_z(a) < _key_z(b)
		return ax < bx
	)


static func _prioritize_queue(queue: Array[String], wanted: Dictionary, center: Vector2i, direction: Vector2 = Vector2.ZERO) -> void:
	queue.sort_custom(func(a: String, b: String) -> bool:
		return _queue_priority_less(a, b, wanted, center, direction)
	)


static func _queue_priority_less(a: String, b: String, wanted: Dictionary, center: Vector2i, direction: Vector2 = Vector2.ZERO) -> bool:
	var a_chunk: RefCounted = wanted[a] as RefCounted
	var b_chunk: RefCounted = wanted[b] as RefCounted
	var adx: int = abs(a_chunk.chunk_x - center.x)
	var adz: int = abs(a_chunk.chunk_z - center.y)
	var bdx: int = abs(b_chunk.chunk_x - center.x)
	var bdz: int = abs(b_chunk.chunk_z - center.y)
	var a_runtime_ring: int = max(adx, adz)
	var b_runtime_ring: int = max(bdx, bdz)
	var a_ahead: int = 0
	var b_ahead: int = 0
	if direction.length_squared() > 0.000001:
		var a_offset := Vector2(float(a_chunk.chunk_x - center.x), float(a_chunk.chunk_z - center.y))
		var b_offset := Vector2(float(b_chunk.chunk_x - center.x), float(b_chunk.chunk_z - center.y))
		a_ahead = int(round(a_offset.dot(direction) * 1000.0))
		b_ahead = int(round(b_offset.dot(direction) * 1000.0))
	var a_values: Array[int] = [a_runtime_ring, a_chunk.lod, a_chunk.ring, -a_ahead, adx + adz, a_chunk.chunk_z, a_chunk.chunk_x]
	var b_values: Array[int] = [b_runtime_ring, b_chunk.lod, b_chunk.ring, -b_ahead, bdx + bdz, b_chunk.chunk_z, b_chunk.chunk_x]
	for index in range(a_values.size()):
		if a_values[index] != b_values[index]:
			return a_values[index] < b_values[index]
	return a < b


static func _enqueue_unique(queue: Array[String], key: String) -> void:
	if not queue.has(key):
		queue.append(key)


static func _filter_wanted_queue(queue: Array[String], wanted: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in queue:
		if wanted.has(key):
			result.append(key)
	return result


static func _take_front(queue: Array[String], count: int) -> Array[String]:
	var result: Array[String] = []
	for index in range(min(count, queue.size())):
		result.append(queue[index])
	return result


static func _drop_front(queue: Array[String], count: int) -> Array[String]:
	var result: Array[String] = []
	for index in range(count, queue.size()):
		result.append(queue[index])
	return result


static func _lod_counts(chunks: Dictionary) -> Dictionary:
	var raw: Dictionary = {}
	for chunk_value in chunks.values():
		var chunk: RefCounted = chunk_value as RefCounted
		var key: String = str(chunk.lod)
		raw[key] = int(raw.get(key, 0)) + 1
	var keys: Array = raw.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(a) < int(b)
	)
	var result: Dictionary = {}
	for key_value in keys:
		var key: String = str(key_value)
		result[key] = raw[key]
	return result


static func _chunk_list(chunks: Dictionary) -> Array[Dictionary]:
	var keys: Array[String] = []
	for key_value in chunks.keys():
		keys.append(str(key_value))
	_sort_coord_keys(keys)
	var result: Array[Dictionary] = []
	for key in keys:
		var chunk: RefCounted = chunks[key] as RefCounted
		result.append(chunk.to_reference_dict())
	return result


static func _coord_list(keys: Array[String]) -> Array[Array]:
	var result: Array[Array] = []
	for key in keys:
		result.append([_key_x(key), _key_z(key)])
	return result


static func _key_x(key: String) -> int:
	return int(key.split(",", false, 1)[0])


static func _key_z(key: String) -> int:
	return int(key.split(",", false, 1)[1])


static func _mean_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total: int = 0
	for value in values:
		total += value
	return float(total) / float(values.size())


static func _max_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var result: int = values[0]
	for value in values:
		result = max(result, value)
	return result
