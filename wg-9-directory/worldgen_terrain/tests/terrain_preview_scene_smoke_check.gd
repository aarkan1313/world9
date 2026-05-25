extends SceneTree

const SCENE_PATH := "res://worldgen_terrain/scenes/terrain_preview.tscn"


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		errors.append("scene_load")
		_report(errors)
		return 1
	var scene: Node = packed.instantiate()
	if scene == null:
		errors.append("scene_instantiate")
		_report(errors)
		return 1
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var terrain: Node = scene.get_node_or_null("TerrainWorldNode")
	var composite: Node = scene.get_node_or_null("CompositeGrayPreview")
	var camera: Node = scene.get_node_or_null("PreviewCamera")
	var sun: Node = scene.get_node_or_null("PreviewSun")
	if terrain == null:
		errors.append("missing_terrain_node")
	if camera == null:
		errors.append("missing_camera")
	if sun == null:
		errors.append("missing_sun")
	if composite == null:
		errors.append("missing_composite_gray_preview")
	scene.queue_free()
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-terrain-preview-scene] status=pass path=%s chunks=%d" % [SCENE_PATH, terrain.built_chunk_count()])
	return 0


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-terrain-preview-scene] status=fail errors=%d" % errors.size())
