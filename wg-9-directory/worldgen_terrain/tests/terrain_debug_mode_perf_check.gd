extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")

const OUT_DIR := "factory/runtime/godot_performance"
const VERTICES_PER_SIDE := 33
const VISIBLE_RADIUS_CHUNKS := 1
const MAX_HYDROLOGY_SWITCH_MS := 25000
const MAX_GRAY_SWITCH_MS := 10000


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var node: Node3D = TerrainWorldNodeScript.new()
	node.auto_setup_on_ready = false
	node.vertices_per_side = VERTICES_PER_SIDE
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.use_fast_gray_material = true
	get_root().add_child(node)
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
	else:
		node.world.configure_streamer({
			"chunk_size_m": TerrainSettingsScript.CHUNK_SIZE_M,
			"visible_radius_chunks": VISIBLE_RADIUS_CHUNKS,
			"max_lod": 4,
			"build_budget_per_frame": 9,
			"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
		})
		node.update_viewer(Vector2(TerrainSettingsScript.CHUNK_SIZE_M * 8.0, TerrainSettingsScript.CHUNK_SIZE_M * 8.0))
		for _index in range(4):
			node.update_viewer(Vector2(TerrainSettingsScript.CHUNK_SIZE_M * 8.0, TerrainSettingsScript.CHUNK_SIZE_M * 8.0))
	var built_chunks: int = node.built_chunk_count()
	if built_chunks != 9:
		errors.append("built_chunks:%d expected:9" % built_chunks)

	var hydrology_ms: int = _timed_debug_switch(node, TerrainWorldScript.DEBUG_HYDROLOGY)
	var hydrology_tiles: int = 0
	if node._hydrology_cache != null:
		hydrology_tiles = int(node._hydrology_cache.built_tile_count())
	var gray_ms: int = _timed_debug_switch(node, TerrainWorldScript.DEBUG_GRAY)
	if hydrology_ms > MAX_HYDROLOGY_SWITCH_MS:
		errors.append("hydrology_switch_ms:%d limit:%d" % [hydrology_ms, MAX_HYDROLOGY_SWITCH_MS])
	if gray_ms > MAX_GRAY_SWITCH_MS:
		errors.append("gray_switch_ms:%d limit:%d" % [gray_ms, MAX_GRAY_SWITCH_MS])
	var report := {
		"schema": "worldgen9.debug_mode_perf_report.v1",
		"seed": 1337,
		"vertices_per_side": VERTICES_PER_SIDE,
		"visible_radius_chunks": VISIBLE_RADIUS_CHUNKS,
		"built_chunks": built_chunks,
		"hydrology_tiles_built": hydrology_tiles,
		"hydrology_overlay_tile_grid_size": 65,
		"hydrology_overlay_padding_cells": 16,
		"hydrology_overlay_tile_origin_offset_m": [
			TerrainSettingsScript.REGION_SIZE_M * 0.5,
			TerrainSettingsScript.REGION_SIZE_M * 0.5,
		],
		"timing_policy": "raw measured milliseconds are printed to stdout only so this locked artifact stays deterministic",
		"timing_checks": {
			"hydrology_switch_within_limit": hydrology_ms <= MAX_HYDROLOGY_SWITCH_MS,
			"gray_switch_within_limit": gray_ms <= MAX_GRAY_SWITCH_MS,
			"limits_ms": {
				"hydrology_switch": MAX_HYDROLOGY_SWITCH_MS,
				"gray_switch": MAX_GRAY_SWITCH_MS,
			},
		},
	}
	_save_report(report, errors)
	node.queue_free()
	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-debug-mode-perf] status=pass hydrology_ms=%d gray_ms=%d tiles=%d" % [
		hydrology_ms,
		gray_ms,
		hydrology_tiles,
	])
	return 0


func _timed_debug_switch(node: Node3D, mode: String) -> int:
	var start_ms: int = Time.get_ticks_msec()
	node.apply_debug_mode(mode)
	return Time.get_ticks_msec() - start_ms


func _save_report(report: Dictionary, errors: Array[String]) -> void:
	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join("debug_mode_perf_report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-debug-mode-perf] status=fail errors=%d" % errors.size())
