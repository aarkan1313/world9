class_name NpyFloat32Array
extends RefCounted

const MAGIC: Array[int] = [0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59]


static func load_2d(path: String) -> Dictionary:
	return _load(path, "<f4", 2)


static func load_u32_1d(path: String) -> Dictionary:
	return _load(path, "<u4", 1)


static func _load(path: String, expected_descr: String, expected_dims: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing_file:%s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("open_failed:%s" % path)
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 11:
		return _fail("too_small:%s" % path)
	for index in range(MAGIC.size()):
		if bytes[index] != MAGIC[index]:
			return _fail("bad_magic:%s" % path)

	var major := int(bytes[6])
	var minor := int(bytes[7])
	var header_len := 0
	var header_start := 0
	if major == 1:
		header_len = int(bytes[8]) | (int(bytes[9]) << 8)
		header_start = 10
	elif major == 2:
		if bytes.size() < 12:
			return _fail("too_small_v2_header:%s" % path)
		header_len = int(bytes[8]) | (int(bytes[9]) << 8) | (int(bytes[10]) << 16) | (int(bytes[11]) << 24)
		header_start = 12
	else:
		return _fail("unsupported_version:%d.%d:%s" % [major, minor, path])

	var data_start := header_start + header_len
	if data_start > bytes.size():
		return _fail("bad_header_length:%s" % path)

	var header := bytes.slice(header_start, data_start).get_string_from_ascii()
	var descr_single := "'descr': '%s'" % expected_descr
	var descr_double := "\"descr\": \"%s\"" % expected_descr
	if not header.contains(descr_single) and not header.contains(descr_double):
		return _fail("unsupported_dtype:%s:%s" % [path, header.strip_edges()])
	if header.contains("'fortran_order': True") or header.contains("\"fortran_order\": true"):
		return _fail("fortran_order_not_supported:%s" % path)

	var shape := _parse_shape(header)
	if shape.size() != expected_dims:
		return _fail("unexpected_shape:%s:%s" % [path, header.strip_edges()])
	var count := 1
	for dim in shape:
		count *= int(dim)
	var expected_bytes := data_start + count * 4
	if bytes.size() < expected_bytes:
		return _fail("truncated_data:%s" % path)

	var offset := data_start
	if expected_descr == "<f4":
		var values := PackedFloat32Array()
		values.resize(count)
		for index in range(count):
			values[index] = bytes.decode_float(offset)
			offset += 4
		return {
			"status": "pass",
			"path": path,
			"dtype": "float32",
			"shape": shape,
			"values": values,
		}

	var u32_values := PackedInt32Array()
	u32_values.resize(count)
	for index in range(count):
		u32_values[index] = int(bytes.decode_u32(offset))
		offset += 4

	return {
		"status": "pass",
		"path": path,
		"dtype": "uint32",
		"shape": shape,
		"values": u32_values,
	}


static func _parse_shape(header: String) -> Array[int]:
	var marker := "'shape':"
	var start := header.find(marker)
	if start < 0:
		marker = "\"shape\":"
		start = header.find(marker)
	if start < 0:
		return []
	var open := header.find("(", start)
	var close := header.find(")", open)
	if open < 0 or close < 0:
		return []
	var raw := header.substr(open + 1, close - open - 1)
	var result: Array[int] = []
	for part in raw.split(",", false):
		var text := part.strip_edges()
		if text.is_empty():
			continue
		var parsed := _parse_positive_int(text)
		if parsed <= 0:
			return []
		result.append(parsed)
	return result


static func _parse_positive_int(text: String) -> int:
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if code < 48 or code > 57:
			return -1
	return int(text)


static func _fail(error: String) -> Dictionary:
	return {
		"status": "fail",
		"error": error,
	}
