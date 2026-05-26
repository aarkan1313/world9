extends SceneTree

const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")
const TerrainWorldScript := preload("res://worldgen_terrain/runtime/terrain_world.gd")

const OUT_DIR := "factory/runtime/godot_worldgen_capability"
const GRID_SIZE := 81
const SITE_COUNT := 12
const SCAN_RADIUS_REGIONS := 8
const SITE_SPAN_REGION_FRACTION := 0.45
const SHEET_COLUMNS := 4


func _init() -> void:
	var status := _run()
	quit(status)


func _run() -> int:
	var errors: Array[String] = []
	var world: RefCounted = TerrainWorldScript.new()
	if not world.setup_procedural(1337):
		for error in world.errors:
			errors.append("setup:%s" % str(error))
		_report(errors)
		return 1

	var out_dir: String = TerrainSettingsScript.workspace_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sites: Array[Dictionary] = _select_diverse_sites(world)
	var reports: Array[Dictionary] = []
	var images: Array[Image] = []
	for index in range(min(SITE_COUNT, sites.size())):
		var probed: Dictionary = _probe_site(world, sites[index], index, out_dir, errors)
		if probed.has("report"):
			reports.append(probed["report"] as Dictionary)
		if probed.has("image"):
			images.append(probed["image"] as Image)

	var summary: Dictionary = _summary(reports)
	_validate_summary(summary, reports, errors)
	if images.size() == reports.size() and not images.is_empty():
		_save_contact_sheet(images, out_dir.path_join("worldgen_capability_contact_sheet.png"), errors)
	_save_report(out_dir.path_join("worldgen_capability_report.json"), summary, reports, errors)

	if not errors.is_empty():
		_report(errors)
		return 1
	print("[wg9-worldgen-capability] status=pass sites=%d palettes=%d families=%d kernels=%d out=%s" % [
		reports.size(),
		int(summary.get("unique_palette_count", 0)),
		int(summary.get("unique_family_count", 0)),
		int(summary.get("unique_kernel_count", 0)),
		out_dir,
	])
	return 0


func _select_diverse_sites(world: RefCounted) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var region_size: float = world.region_size_m
	for rz in range(-SCAN_RADIUS_REGIONS, SCAN_RADIUS_REGIONS + 1):
		for rx in range(-SCAN_RADIUS_REGIONS, SCAN_RADIUS_REGIONS + 1):
			var center := Vector2((float(rx) + 0.5) * region_size, (float(rz) + 0.5) * region_size)
			var sample: Dictionary = world.sample(center.x, center.y)
			var palette: Dictionary = world.provider.decisions.region_info(rx, rz, world.seed)
			var kernel_a: String = str(sample.get("kernel_a", ""))
			if kernel_a.is_empty():
				continue
			candidates.append({
				"region": Vector2i(rx, rz),
				"center_m": center,
				"palette": str(palette.get("id", "")),
				"families": (palette.get("families", []) as Array).duplicate(),
				"primary_family": str(sample.get("primary_family", "unknown")),
				"secondary_family": str(sample.get("secondary_family", "unknown")),
				"kernel_a": kernel_a,
				"kernel_b": str(sample.get("kernel_b", "")),
				"distance": abs(rx) + abs(rz),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		var ar: Vector2i = a["region"] as Vector2i
		var br: Vector2i = b["region"] as Vector2i
		if ar.y != br.y:
			return ar.y < br.y
		return ar.x < br.x
	)

	var selected: Array[Dictionary] = []
	var used_palettes: Dictionary = {}
	var used_families: Dictionary = {}
	var used_kernels: Dictionary = {}
	for candidate in candidates:
		if selected.size() >= SITE_COUNT:
			break
		var palette_id: String = str(candidate["palette"])
		if used_palettes.has(palette_id):
			continue
		_add_site(candidate, selected, used_palettes, used_families, used_kernels)
	for candidate in candidates:
		if selected.size() >= SITE_COUNT:
			break
		var family_id: String = str(candidate["primary_family"])
		if used_families.has(family_id):
			continue
		_add_site(candidate, selected, used_palettes, used_families, used_kernels)
	for candidate in candidates:
		if selected.size() >= SITE_COUNT:
			break
		var kernel_id: String = str(candidate["kernel_a"])
		if used_kernels.has(kernel_id):
			continue
		_add_site(candidate, selected, used_palettes, used_families, used_kernels)
	for candidate in candidates:
		if selected.size() >= SITE_COUNT:
			break
		_add_site(candidate, selected, used_palettes, used_families, used_kernels)
	return selected


func _add_site(
	candidate: Dictionary,
	selected: Array[Dictionary],
	used_palettes: Dictionary,
	used_families: Dictionary,
	used_kernels: Dictionary
) -> void:
	var region: Vector2i = candidate["region"] as Vector2i
	for selected_site in selected:
		if (selected_site["region"] as Vector2i) == region:
			return
	selected.append(candidate)
	used_palettes[str(candidate["palette"])] = true
	used_families[str(candidate["primary_family"])] = true
	var kernel_a: String = str(candidate["kernel_a"])
	if not kernel_a.is_empty():
		used_kernels[kernel_a] = true
	var kernel_b: String = str(candidate["kernel_b"])
	if not kernel_b.is_empty():
		used_kernels[kernel_b] = true


func _probe_site(
	world: RefCounted,
	site: Dictionary,
	index: int,
	out_dir: String,
	errors: Array[String]
) -> Dictionary:
	var center: Vector2 = site["center_m"] as Vector2
	var span_m: float = world.region_size_m * SITE_SPAN_REGION_FRACTION
	var step_m: float = span_m / float(GRID_SIZE - 1)
	var origin_x: float = center.x - span_m * 0.5
	var origin_z: float = center.y - span_m * 0.5
	var heights: PackedFloat32Array = world.sample_height_grid(origin_x, origin_z, step_m, GRID_SIZE, GRID_SIZE)
	if heights.size() != GRID_SIZE * GRID_SIZE:
		errors.append("site_%d_grid_size:%d" % [index, heights.size()])
		return {}
	var metrics: Dictionary = _height_metrics(heights, step_m)
	var relief_metrics: Dictionary = _kernel_relief_metrics(world, center, span_m)
	var image: Image = _height_image(heights, metrics)
	var image_name: String = "worldgen_site_%02d_%d_%d.png" % [
		index,
		(site["region"] as Vector2i).x,
		(site["region"] as Vector2i).y,
	]
	var save_result: Error = image.save_png(out_dir.path_join(image_name))
	if save_result != OK:
		errors.append("site_%d_save:%d" % [index, int(save_result)])
	var report: Dictionary = {
		"index": index,
		"region": "%d,%d" % [(site["region"] as Vector2i).x, (site["region"] as Vector2i).y],
		"center_m": [center.x, center.y],
		"palette": str(site["palette"]),
		"families": (site["families"] as Array).duplicate(),
		"primary_family": str(site["primary_family"]),
		"secondary_family": str(site["secondary_family"]),
		"kernel_a": str(site["kernel_a"]),
		"kernel_b": str(site["kernel_b"]),
		"span_m": span_m,
		"grid_size": GRID_SIZE,
		"step_m": step_m,
		"image": image_name,
		"height_range_m": float(metrics["height_range_m"]),
		"relief_p05_p95_m": float(metrics["relief_p05_p95_m"]),
		"mean_abs_slope_deg": float(metrics["mean_abs_slope_deg"]),
		"kernel_relief_mean_abs_m": float(relief_metrics["kernel_relief_mean_abs_m"]),
		"kernel_relief_max_abs_m": float(relief_metrics["kernel_relief_max_abs_m"]),
	}
	return {"report": report, "image": image}


func _kernel_relief_metrics(world: RefCounted, center: Vector2, span_m: float) -> Dictionary:
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(-0.25, 0.0),
		Vector2(0.25, 0.0),
		Vector2(0.0, -0.25),
		Vector2(0.0, 0.25),
		Vector2(-0.2, -0.2),
		Vector2(0.2, 0.2),
	]
	var total_abs := 0.0
	var max_abs := 0.0
	for offset in offsets:
		var point: Vector2 = center + offset * span_m
		var layers: Dictionary = world.provider.sample_layers(point.x, point.y, world.seed, world.region_size_m)
		var value: float = absf(float(layers.get("relief", 0.0)))
		total_abs += value
		max_abs = max(max_abs, value)
	return {
		"kernel_relief_mean_abs_m": total_abs / float(offsets.size()),
		"kernel_relief_max_abs_m": max_abs,
	}


func _height_metrics(height: PackedFloat32Array, step_m: float) -> Dictionary:
	var min_height := INF
	var max_height := -INF
	var values: Array[float] = []
	values.resize(height.size())
	for index in range(height.size()):
		var value: float = float(height[index])
		values[index] = value
		min_height = min(min_height, value)
		max_height = max(max_height, value)
	values.sort()
	var p05: float = values[int(floor(float(values.size() - 1) * 0.05))]
	var p95: float = values[int(floor(float(values.size() - 1) * 0.95))]
	var slope_total := 0.0
	var count := 0
	for z in range(1, GRID_SIZE - 1):
		for x in range(1, GRID_SIZE - 1):
			var left: float = float(height[z * GRID_SIZE + x - 1])
			var right: float = float(height[z * GRID_SIZE + x + 1])
			var north: float = float(height[(z - 1) * GRID_SIZE + x])
			var south: float = float(height[(z + 1) * GRID_SIZE + x])
			var dx: float = (right - left) / (step_m * 2.0)
			var dz: float = (south - north) / (step_m * 2.0)
			slope_total += rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
			count += 1
	return {
		"height_range_m": max_height - min_height,
		"relief_p05_p95_m": p95 - p05,
		"mean_abs_slope_deg": slope_total / max(1, count),
	}


func _height_image(height: PackedFloat32Array, metrics: Dictionary) -> Image:
	var image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	var min_height := INF
	var max_height := -INF
	for value in height:
		min_height = min(min_height, float(value))
		max_height = max(max_height, float(value))
	var denom: float = max(0.0001, max_height - min_height)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var value: float = float(height[y * GRID_SIZE + x])
			var normalized: float = clampf((value - min_height) / denom, 0.0, 1.0)
			var shaded: float = pow(normalized, 0.82)
			image.set_pixel(x, y, Color(shaded, shaded, shaded))
	return image


func _summary(reports: Array[Dictionary]) -> Dictionary:
	var palettes: Dictionary = {}
	var families: Dictionary = {}
	var kernels: Dictionary = {}
	var relief_active_sites := 0
	var moderate_sites := 0
	for report in reports:
		palettes[str(report.get("palette", ""))] = true
		families[str(report.get("primary_family", ""))] = true
		families[str(report.get("secondary_family", ""))] = true
		var kernel_a: String = str(report.get("kernel_a", ""))
		if not kernel_a.is_empty():
			kernels[kernel_a] = true
		var kernel_b: String = str(report.get("kernel_b", ""))
		if not kernel_b.is_empty():
			kernels[kernel_b] = true
		if float(report.get("kernel_relief_max_abs_m", 0.0)) >= 2.0:
			relief_active_sites += 1
		if float(report.get("relief_p05_p95_m", 0.0)) >= 60.0 and float(report.get("mean_abs_slope_deg", 0.0)) >= 0.35:
			moderate_sites += 1
	return {
		"site_count": reports.size(),
		"unique_palette_count": palettes.size(),
		"unique_family_count": families.size(),
		"unique_kernel_count": kernels.size(),
		"palettes": palettes.keys(),
		"families": families.keys(),
		"kernels": kernels.keys(),
		"kernel_relief_active_sites": relief_active_sites,
		"moderate_landform_sites": moderate_sites,
	}


func _validate_summary(summary: Dictionary, reports: Array[Dictionary], errors: Array[String]) -> void:
	if reports.size() < SITE_COUNT:
		errors.append("site_count:%d expected:%d" % [reports.size(), SITE_COUNT])
	if int(summary.get("unique_palette_count", 0)) < 6:
		errors.append("palette_diversity:%d" % int(summary.get("unique_palette_count", 0)))
	if int(summary.get("unique_family_count", 0)) < 8:
		errors.append("family_diversity:%d" % int(summary.get("unique_family_count", 0)))
	if int(summary.get("unique_kernel_count", 0)) < 12:
		errors.append("kernel_diversity:%d" % int(summary.get("unique_kernel_count", 0)))
	if int(summary.get("kernel_relief_active_sites", 0)) < 8:
		errors.append("kernel_relief_active_sites:%d" % int(summary.get("kernel_relief_active_sites", 0)))
	if int(summary.get("moderate_landform_sites", 0)) < 8:
		errors.append("moderate_landform_sites:%d" % int(summary.get("moderate_landform_sites", 0)))


func _save_contact_sheet(images: Array[Image], path: String, errors: Array[String]) -> void:
	var rows: int = int(ceil(float(images.size()) / float(SHEET_COLUMNS)))
	var sheet := Image.create(GRID_SIZE * SHEET_COLUMNS, GRID_SIZE * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in range(images.size()):
		var column: int = index % SHEET_COLUMNS
		var row: int = index / SHEET_COLUMNS
		var dest := Vector2i(column * GRID_SIZE, row * GRID_SIZE)
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE)), dest)
	var save_result: Error = sheet.save_png(path)
	if save_result != OK:
		errors.append("save_contact_sheet:%d" % int(save_result))


func _save_report(path: String, summary: Dictionary, reports: Array[Dictionary], errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("report_open_failed:%s" % path)
		return
	file.store_string(JSON.stringify({
		"schema": "worldgen9.worldgen_capability_report.v1",
		"seed": 1337,
		"site_count": reports.size(),
		"scan_radius_regions": SCAN_RADIUS_REGIONS,
		"site_span_region_fraction": SITE_SPAN_REGION_FRACTION,
		"summary": summary,
		"sites": reports,
	}, "\t"))


func _report(errors: Array[String]) -> void:
	for error in errors:
		push_error(error)
	print("[wg9-worldgen-capability] status=fail errors=%d" % errors.size())
