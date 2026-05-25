class_name TerrainHash
extends RefCounted

const U32_MASK: int = 0xffffffff
const U32_DENOMINATOR: float = 4294967295.0
const FNV1A_INITIAL: int = 0x811c9dc5
const FNV1A_MULTIPLY: int = 0x01000193


static func stable_hash(values: Array) -> int:
	var text: String = _join_values(values)
	var h: int = FNV1A_INITIAL
	for index in range(text.length()):
		h = h ^ text.unicode_at(index)
		h = (h * FNV1A_MULTIPLY) & U32_MASK
	return h & U32_MASK


static func hash_grid(ix: int, iz: int, world_seed: int, salt: int = 0) -> float:
	var n: int = (
		ix * 374761393
		+ iz * 668265263
		+ world_seed * 1442695041
		+ salt * 69069
	) & U32_MASK
	n = (n ^ (n >> 13)) * 1274126177
	n = (n ^ (n >> 16)) & U32_MASK
	return float(n) / U32_DENOMINATOR


static func value_noise(x: float, z: float, scale_m: float, world_seed: int, salt: int = 0) -> float:
	var fx: float = x / scale_m
	var fz: float = z / scale_m
	var ix: int = int(floor(fx))
	var iz: int = int(floor(fz))
	var tx: float = fade(fx - float(ix))
	var tz: float = fade(fz - float(iz))
	var a: float = hash_grid(ix, iz, world_seed, salt)
	var b: float = hash_grid(ix + 1, iz, world_seed, salt)
	var c: float = hash_grid(ix, iz + 1, world_seed, salt)
	var d: float = hash_grid(ix + 1, iz + 1, world_seed, salt)
	var ab: float = lerpf(a, b, tx)
	var cd: float = lerpf(c, d, tx)
	return lerpf(ab, cd, tz) * 2.0 - 1.0


static func fbm(x: float, z: float, scale_m: float, world_seed: int, octaves: int = 4) -> float:
	var total: float = 0.0
	var amp: float = 1.0
	var norm: float = 0.0
	for octave in range(octaves):
		total += value_noise(x, z, scale_m / float(1 << octave), world_seed, octave) * amp
		norm += amp
		amp *= 0.5
	return total / max(0.000001, norm)


static func fade(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func smoothstep_unit(t: float) -> float:
	var v: float = clampf(t, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


static func _join_values(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(_format_value(value))
	return "|".join(parts)


static func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			if is_equal_approx(value, roundf(value)):
				return str(int(roundf(value)))
			return str(value)
		_:
			return str(value)
