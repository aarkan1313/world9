extends SceneTree

const TerrainChunkRendererScript := preload("res://worldgen_terrain/runtime/terrain_chunk_renderer.gd")


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var root := Node3D.new()
	get_root().add_child(root)
	var renderer: RefCounted = TerrainChunkRendererScript.new()
	renderer.call("setup", root, true, 2)
	var mesh := ArrayMesh.new()
	var material := StandardMaterial3D.new()
	renderer.call("apply_chunk", "0,0", 0, 0, 0, 0, 512.0, mesh, material)
	renderer.call("apply_chunk", "1,0", 1, 0, 1, 1, 512.0, mesh, material)
	if int(renderer.call("built_chunk_count")) != 2:
		errors.append("built_before_retire:%d" % int(renderer.call("built_chunk_count")))
	if root.get_child_count() != 2:
		errors.append("children_before_retire:%d" % root.get_child_count())
	renderer.call("retire_inactive", {"1,0": true})
	if int(renderer.call("built_chunk_count")) != 1:
		errors.append("built_after_retire:%d" % int(renderer.call("built_chunk_count")))
	if int(renderer.call("pooled_chunk_count")) != 1:
		errors.append("pooled_after_retire:%d" % int(renderer.call("pooled_chunk_count")))
	renderer.call("apply_chunk", "2,0", 2, 0, 0, 0, 512.0, mesh, material)
	if root.get_child_count() != 2:
		errors.append("pool_reuse_child_count:%d" % root.get_child_count())
	renderer.call("sync_settings", true, 0)
	if int(renderer.call("pooled_chunk_count")) != 0:
		errors.append("pool_trim:%d" % int(renderer.call("pooled_chunk_count")))
	renderer.call("clear_all")
	if int(renderer.call("built_chunk_count")) != 0:
		errors.append("built_after_clear:%d" % int(renderer.call("built_chunk_count")))
	if int(renderer.call("pooled_chunk_count")) != 0:
		errors.append("pooled_after_clear:%d" % int(renderer.call("pooled_chunk_count")))
	root.queue_free()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-chunk-renderer] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-chunk-renderer] status=pass")
	return 0
