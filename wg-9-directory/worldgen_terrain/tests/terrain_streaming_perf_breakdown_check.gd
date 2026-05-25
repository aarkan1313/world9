extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainStreamerScript := preload("res://worldgen_terrain/core/terrain_streamer.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")
const TerrainWorldNodeScript := preload("res://worldgen_terrain/runtime/terrain_world_node.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var status: int = await _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var tiers: Array[Dictionary] = [
		{"label": "33_r1_b1", "vertices": 33, "radius": 1, "budget": 1, "steps": 10, "warm_load": false},
		{"label": "33_r1_b1_warm", "vertices": 33, "radius": 1, "budget": 1, "steps": 10, "warm_load": true},
		{"label": "33_r1_b4", "vertices": 33, "radius": 1, "budget": 4, "steps": 6, "warm_load": false},
	]
	for tier in tiers:
		var result := _profile_tier(tier)
		print("[wg9-streaming-perf] tier=%s setup_ms=%d configure_ms=%d first_update_ms=%d warmup_ms=%s move_ms=%s built=%d active=%d avg_build_ms=%.1f max_build_ms=%d" % [
			str(tier["label"]),
			int(result["setup_ms"]),
			int(result["configure_ms"]),
			int(result["first_update_ms"]),
			str(result["warmup_ms"]),
			str(result["move_ms"]),
			int(result["built_chunks"]),
			int(result["active_count"]),
			float(result["avg_build_ms"]),
			int(result["max_build_ms"]),
		])
		for error in result.get("errors", []) as Array:
			errors.append("%s:%s" % [str(tier["label"]), str(error)])
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-streaming-perf] status=fail errors=%d" % errors.size())
		return 1
	print("[wg9-streaming-perf] status=pass")
	return 0


func _profile_tier(tier: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var node: Node3D = TerrainWorldNodeScript.new()
	get_root().add_child(node)
	node.auto_setup_on_ready = false
	node.vertices_per_side = int(tier["vertices"])
	node.debug_mode = TerrainWorldScript.DEBUG_GRAY
	node.use_fast_gray_material = true

	var start_ms: int = Time.get_ticks_msec()
	if not node.setup_world(TerrainWorldScript.PROVIDER_PROCEDURAL, 1337):
		errors.append("setup_failed:%s" % str(node.errors))
	if bool(tier.get("warm_load", false)):
		_warm_load_visible_region_kernels(node, int(tier["radius"]))
	var setup_ms: int = Time.get_ticks_msec() - start_ms

	start_ms = Time.get_ticks_msec()
	node.world.configure_streamer({
		"chunk_size_m": TerrainSettingsScript.CHUNK_SIZE_M,
		"visible_radius_chunks": int(tier["radius"]),
		"max_lod": 4,
		"build_budget_per_frame": int(tier["budget"]),
		"queue_policy": TerrainStreamerScript.QUEUE_POLICY_PRIORITY_CANCEL,
	})
	var configure_ms: int = Time.get_ticks_msec() - start_ms

	start_ms = Time.get_ticks_msec()
	var report: Dictionary = node.update_viewer(Vector2.ZERO)
	var first_update_ms: int = Time.get_ticks_msec() - start_ms
	if report.get("status", "fail") != "pass":
		errors.append("first_update_failed")

	var warmup_ms: Array[int] = []
	for _index in range(int(tier["steps"])):
		start_ms = Time.get_ticks_msec()
		report = node.update_viewer(Vector2.ZERO)
		warmup_ms.append(Time.get_ticks_msec() - start_ms)

	var move_ms: Array[int] = []
	var point := Vector2.ZERO
	for step in range(8):
		point += Vector2(900.0, 900.0)
		start_ms = Time.get_ticks_msec()
		report = node.update_viewer(point)
		move_ms.append(Time.get_ticks_msec() - start_ms)

	var stats: Dictionary = node.build_stats()
	var result := {
		"errors": errors,
		"setup_ms": setup_ms,
		"configure_ms": configure_ms,
		"first_update_ms": first_update_ms,
		"warmup_ms": warmup_ms,
		"move_ms": move_ms,
		"built_chunks": node.built_chunk_count(),
		"active_count": int(report.get("active_count", -1)),
		"avg_build_ms": float(stats.get("avg_recent_chunk_build_ms", 0.0)),
		"max_build_ms": int(stats.get("max_recent_chunk_build_ms", 0)),
	}
	node.queue_free()
	return result


func _warm_load_visible_region_kernels(node: Node3D, visible_radius_chunks: int) -> void:
	var provider: RefCounted = node.world.provider
	var region_size_m: float = node.world.region_size_m
	var chunk_size_m: float = node.world.chunk_size_m
	var seen: Dictionary = {}
	for cz in range(-visible_radius_chunks, visible_radius_chunks + 1):
		for cx in range(-visible_radius_chunks, visible_radius_chunks + 1):
			var origin_x: float = float(cx) * chunk_size_m
			var origin_z: float = float(cz) * chunk_size_m
			var rx: int = int(floor(origin_x / region_size_m))
			var rz: int = int(floor(origin_z / region_size_m))
			for dz in range(2):
				for dx in range(2):
					var crx: int = rx + dx
					var crz: int = rz + dz
					var key := "%d,%d" % [crx, crz]
					if seen.has(key):
						continue
					seen[key] = true
					var palette: Dictionary = provider.decisions.region_info(crx, crz, node.world.seed)
					var families: Array = palette["families"] as Array
					for family_value in families:
						var family: String = str(family_value)
						var kernel: Dictionary = provider.decisions.kernel_for_family(family, crx, crz, node.world.seed)
						if kernel.is_empty():
							continue
						node.world.runtime_pack.load_kernel_normalized_by_id(str(kernel.get("id", "")))
