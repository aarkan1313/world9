extends SceneTree


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var errors: Array[String] = []
	_check_texture_rd(errors)
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		print("[wg9-gpu-texture-rd-probe] status=fail errors=%d" % errors.size())
		quit(1)
		return
	print("[wg9-gpu-texture-rd-probe] status=pass")
	quit(0)


func _check_texture_rd(errors: Array[String]) -> void:
	if not ClassDB.class_exists("Texture2DRD"):
		errors.append("texture2drd_class_missing")
		return
	if not RenderingServer.has_method("get_rendering_device"):
		errors.append("rendering_server_get_rendering_device_missing")
		return
	var rd: RenderingDevice = RenderingServer.call("get_rendering_device") as RenderingDevice
	if rd == null:
		print("[wg9-gpu-texture-rd-probe] status=unsupported rendering_device_unavailable")
		quit(0)
		return
	var format := RDTextureFormat.new()
	format.width = 4
	format.height = 4
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(4 * 4 * 4)
	for index in range(16):
		data.encode_float(index * 4, float(index))
	var texture_rid: RID = rd.texture_create(format, view, [data])
	if not texture_rid.is_valid():
		errors.append("texture_create_failed")
		return
	var texture = ClassDB.instantiate("Texture2DRD")
	if texture == null:
		rd.free_rid(texture_rid)
		errors.append("texture2drd_instantiate_failed")
		return
	texture.set("texture_rd_rid", texture_rid)
	if int(texture.get_width()) != 4 or int(texture.get_height()) != 4:
		errors.append("texture2drd_size:%dx%d" % [int(texture.get_width()), int(texture.get_height())])
	texture.set("texture_rd_rid", RID())
	rd.free_rid(texture_rid)
