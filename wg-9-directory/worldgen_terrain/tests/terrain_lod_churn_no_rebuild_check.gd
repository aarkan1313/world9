extends SceneTree

const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_full_density_lod_churn_skips_rebuild(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-lod-churn-no-rebuild] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-lod-churn-no-rebuild] status=pass")
	quit(0)


func _check_full_density_lod_churn_skips_rebuild(errors: Array[String]) -> void:
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = 33
	node.use_lod_mesh_density = false
	node.use_fast_gray_material = true
	node.use_gpu_page_chunks = false
	node.use_native_chunk_workers = false
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 9917):
		errors.append("setup_failed:%s" % str(node.errors))
		node.queue_free()
		return
	node.world.configure_streamer({
		"chunk_size_m": 512.0,
		"visible_radius_chunks": 3,
		"max_lod": 2,
		"build_budget_per_frame": 128,
		"prefetch_forward_chunks": 0,
		"residency_halo_chunks": 0,
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	node.update_viewer(Vector2.ZERO)
	node.rebuild_all_active_for_preview(0)
	var before_stats: Dictionary = node.build_stats()
	var before_builds: int = int(before_stats.get("total_chunk_builds", 0))
	var report: Dictionary = node.update_viewer(Vector2(512.0, 0.0))
	var after_stats: Dictionary = node.build_stats()
	var build_delta: int = int(after_stats.get("total_chunk_builds", 0)) - before_builds
	var created: int = int(report.get("created_count", 0))
	var lod_changed: int = int(report.get("lod_changed_count", 0))
	if created <= 0:
		errors.append("expected_created_chunks:%s" % str(report))
	if lod_changed <= created:
		errors.append("expected_lod_churn:%s" % str(report))
	if build_delta > created:
		errors.append("rebuilt_lod_changed_chunks:delta:%d created:%d report:%s stats:%s" % [build_delta, created, str(report), str(after_stats)])
	if int(after_stats.get("active_missing_chunk_count", 0)) != 0:
		errors.append("active_missing_after_move:%s" % str(after_stats))
	if int(report.get("queued_build_count", 0)) != 0:
		errors.append("queued_noop_lod_changes:%s" % str(report))
	node.clear_chunks()
	node.queue_free()
