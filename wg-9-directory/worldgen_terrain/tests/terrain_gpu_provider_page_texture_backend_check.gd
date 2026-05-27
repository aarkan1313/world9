extends SceneTree

const RuntimeKernelPackScript := preload("res://worldgen_terrain/runtime/runtime_kernel_pack.gd")
const TerrainGpuHeightPageBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_height_page_backend.gd")
const TerrainGpuPageResidencyScript := preload("res://worldgen_terrain/core/terrain_gpu_page_residency.gd")
const TerrainGpuProviderPageTextureBackendScript := preload("res://worldgen_terrain/core/terrain_gpu_provider_page_texture_backend.gd")
const TerrainHeightProviderScript := preload("res://worldgen_terrain/height/terrain_height_provider.gd")
const TerrainSettingsScript := preload("res://worldgen_terrain/core/terrain_settings.gd")


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	if not _rendering_device_available():
		print("[wg9-gpu-provider-page-texture] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	_check_provider_texture_handoff(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-provider-page-texture] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-provider-page-texture] status=pass")
	quit(0)


func _rendering_device_available() -> bool:
	return ClassDB.class_exists("Texture2DRD") and RenderingServer.has_method("get_rendering_device") and RenderingServer.call("get_rendering_device") != null


func _check_provider_texture_handoff(errors: Array[String]) -> void:
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd == null:
		errors.append("rendering_device_unavailable")
		return
	var descriptor: Dictionary = _provider_descriptor(errors)
	if descriptor.get("status", "fail") != "pass":
		return
	var texture_backend = TerrainGpuProviderPageTextureBackendScript.new()
	var texture_descriptor: Dictionary = texture_backend.create_height_texture(rd, descriptor)
	if texture_descriptor.get("status", "fail") != "pass":
		errors.append("provider_texture:%s" % str(texture_descriptor))
		texture_backend.clear(rd)
		return
	if str(texture_descriptor.get("schema", "")) != "worldgen9.gpu_provider_page_texture.v1":
		errors.append("provider_texture_schema:%s" % str(texture_descriptor))
	if str(texture_descriptor.get("texture_payload_mode", "")) != "gpu_provider_rd_height_texture":
		errors.append("provider_texture_mode:%s" % str(texture_descriptor))
	var residency = TerrainGpuPageResidencyScript.new()
	residency.configure(4, true, true)
	var resident: Dictionary = residency.get_or_create_textures("provider_texture_page", texture_descriptor)
	if resident.get("status", "fail") != "pass":
		errors.append("provider_residency:%s" % str(resident))
		texture_backend.clear(rd)
		return
	if str(resident.get("texture_backend", "")) != "rd":
		errors.append("provider_residency_backend:%s" % str(resident))
	if str(resident.get("height_texture_mode", "")) != "rd_external":
		errors.append("provider_residency_height_mode:%s" % str(resident))
	if str(resident.get("normal_texture_mode", "")) != "rd_compute":
		errors.append("provider_residency_normal_mode:%s" % str(resident))
	var residency_state: Dictionary = residency.debug_state()
	if int(residency_state.get("image_uploads", 0)) != 0:
		errors.append("provider_residency_image_uploads:%s" % str(residency_state))
	if int(residency_state.get("rd_uploads", 0)) != 1:
		errors.append("provider_residency_rd_uploads:%s" % str(residency_state))
	if int(residency_state.get("rd_compute_normal_uploads", 0)) != 1:
		errors.append("provider_residency_normal_uploads:%s" % str(residency_state))
	var backend_state: Dictionary = texture_backend.debug_state()
	if int(backend_state.get("compile_count", 0)) != 1:
		errors.append("provider_texture_compile_count:%s" % str(backend_state))
	if int(backend_state.get("dispatch_count", 0)) != 1:
		errors.append("provider_texture_dispatch_count:%s" % str(backend_state))
	residency.clear()
	texture_backend.clear(rd)


func _provider_descriptor(errors: Array[String]) -> Dictionary:
	var pack = RuntimeKernelPackScript.new()
	if not pack.load_default():
		errors.append("provider_pack:%s" % str(pack.errors))
		return {"status": "fail", "error": "pack"}
	var provider = TerrainHeightProviderScript.new()
	provider.setup(pack)
	var origin_x := 1024.0
	var origin_z := 2048.0
	var step_m := 128.0
	var count := 17
	var world_seed := 1337
	var region_size_m: float = TerrainSettingsScript.REGION_SIZE_M
	var prepared: Dictionary = provider.native_prepared_height_grid_request(
		origin_x,
		origin_z,
		step_m,
		count,
		count,
		world_seed,
		region_size_m
	)
	if prepared.get("status", "fail") != "pass":
		errors.append("provider_prepared:%s" % str(prepared))
		return {"status": "fail", "error": "prepared"}
	var descriptor_builder = TerrainGpuHeightPageBackendScript.new()
	var descriptor: Dictionary = descriptor_builder.build_prepared_provider_page_descriptor(
		prepared,
		origin_x,
		origin_z,
		step_m,
		count,
		count,
		world_seed,
		region_size_m
	)
	if descriptor.get("status", "fail") != "pass":
		errors.append("provider_descriptor:%s" % str(descriptor))
	return descriptor
