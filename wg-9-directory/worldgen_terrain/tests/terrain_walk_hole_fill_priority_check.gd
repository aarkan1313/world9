extends SceneTree

const TerrainWalkPreviewSceneScript := preload("res://worldgen_terrain/runtime/terrain_walk_preview_scene.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	var scene: Node3D = TerrainWalkPreviewSceneScript.new()
	scene.auto_setup_on_ready = false
	scene.capture_mouse_on_ready = false
	get_root().add_child(scene)
	if not scene.setup():
		errors.append("setup_failed:%s" % str(scene.errors))
	_report_and_quit(scene, errors, {})
	if scene.built_chunk_count() != scene.expected_active_count():
		errors.append("setup_not_fully_built:%d expected:%d" % [scene.built_chunk_count(), scene.expected_active_count()])
	_report_and_quit(scene, errors, {})

	var center: Array = scene.last_stream_report.get("viewer_chunk", [0, 0]) as Array
	var center_x: int = int(center[0])
	var center_z: int = int(center[1])
	var missing_keys: Array[String] = _select_edge_keys(scene, center_x, center_z, 7)
	var stale_keys: Array[String] = _select_inner_keys(scene, center_x, center_z, 8, missing_keys)
	if missing_keys.size() != 7:
		errors.append("missing_key_setup:%d" % missing_keys.size())
	if stale_keys.size() != 8:
		errors.append("stale_key_setup:%d" % stale_keys.size())
	for key in missing_keys:
		var mesh_instance: MeshInstance3D = scene.terrain.chunk_nodes.get(key, null) as MeshInstance3D
		if mesh_instance != null:
			scene.terrain.chunk_nodes.erase(key)
			mesh_instance.queue_free()
	for key in stale_keys:
		var stale_node: MeshInstance3D = scene.terrain.chunk_nodes.get(key, null) as MeshInstance3D
		if stale_node != null:
			stale_node.set_meta("lod", 99)

	var count_after_damage: int = scene.built_chunk_count()
	var filled: int = int(scene.terrain.call("build_missing_nearby_for_preview", scene.visible_radius_chunks, 8))
	var count_after_fill: int = scene.built_chunk_count()
	var still_missing: Array[String] = []
	for key in missing_keys:
		if not scene.terrain.chunk_nodes.has(key):
			still_missing.append(key)
	if count_after_damage != scene.expected_active_count() - missing_keys.size():
		errors.append("damage_count:%d expected:%d" % [count_after_damage, scene.expected_active_count() - missing_keys.size()])
	if filled < missing_keys.size():
		errors.append("filled_too_few:%d missing:%d" % [filled, missing_keys.size()])
	if count_after_fill != scene.expected_active_count():
		errors.append("fill_left_holes:%d expected:%d" % [count_after_fill, scene.expected_active_count()])
	if not still_missing.is_empty():
		errors.append("still_missing:%s" % str(still_missing))
	var report := {
		"missing_keys": missing_keys,
		"stale_keys": stale_keys,
		"count_after_damage": count_after_damage,
		"filled": filled,
		"count_after_fill": count_after_fill,
	}
	_report_and_quit(scene, errors, report)


func _select_edge_keys(scene: Node3D, center_x: int, center_z: int, limit: int) -> Array[String]:
	var result: Array[String] = []
	for item_value in scene.last_stream_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var ring: int = max(abs(chunk_x - center_x), abs(chunk_z - center_z))
		if ring == scene.visible_radius_chunks:
			result.append("%d,%d" % [chunk_x, chunk_z])
		if result.size() >= limit:
			return result
	return result


func _select_inner_keys(scene: Node3D, center_x: int, center_z: int, limit: int, excluded: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for item_value in scene.last_stream_report.get("active_chunks", []) as Array:
		var item: Dictionary = item_value as Dictionary
		var chunk_x: int = int(item["chunk_x"])
		var chunk_z: int = int(item["chunk_z"])
		var key: String = "%d,%d" % [chunk_x, chunk_z]
		if excluded.has(key):
			continue
		var ring: int = max(abs(chunk_x - center_x), abs(chunk_z - center_z))
		if ring <= 1:
			result.append(key)
		if result.size() >= limit:
			return result
	return result


func _report_and_quit(scene: Node3D, errors: Array[String], report: Dictionary) -> void:
	scene.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-walk-hole-fill-priority] status=fail errors=%d report=%s" % [errors.size(), JSON.stringify(report)])
		quit(1)
		return
	print("[wg9-walk-hole-fill-priority] status=pass report=%s" % JSON.stringify(report))
	quit(0)
