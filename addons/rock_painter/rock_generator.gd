@tool
extends RefCounted
## Turns an outline + seed + RockType into a pixel-art texture (1 texel = 1 px).
## The art never leaves the outline: roughness only bites inward.

const LIGHT_DIR := Vector2(-0.70710678, -0.70710678)


## Returns {"image": Image, "offset": Vector2} or {} if the outline is unusable.
static func generate_image(outline: PackedVector2Array, rock_seed: int, type: RockType, roughness: float) -> Dictionary:
	if outline.size() < 3:
		return {}
	var min_v := outline[0]
	var max_v := outline[0]
	for p in outline:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var origin := Vector2i(floori(min_v.x), floori(min_v.y))
	var w := ceili(max_v.x) - origin.x
	var h := ceili(max_v.y) - origin.y
	if w <= 0 or h <= 0:
		return {}

	var mask := _rasterize(outline, origin, w, h)
	_erode(mask, w, h, rock_seed, roughness)
	var dist := _distance(mask, w, h)

	var colors := PackedColorArray()
	colors.resize(w * h)
	var levels := PackedByteArray()
	levels.resize(w * h)
	var normals := PackedVector2Array()
	normals.resize(w * h)
	_shade(mask, dist, w, h, rock_seed, type, colors, levels, normals)

	if not type.streak_colors.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(rock_seed)
		if type.patterns & RockType.Pattern.BANDS:
			_bands(mask, w, h, rock_seed, type, colors, levels)
		if type.patterns & RockType.Pattern.PATCHES:
			_patches(mask, dist, normals, w, h, rock_seed, type, colors, levels)
		if type.patterns & RockType.Pattern.VEINS:
			_veins(mask, w, h, rng, type, colors)
		if type.patterns & RockType.Pattern.SPECKLES:
			_speckles(mask, w, h, rng, type, colors)

	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			var edge := not _in(mask, w, h, x - 1, y) or not _in(mask, w, h, x + 1, y) \
				or not _in(mask, w, h, x, y - 1) or not _in(mask, w, h, x, y + 1)
			img.set_pixel(x, y, type.outline_color if edge else colors[i])
	return {"image": img, "offset": Vector2(origin)}


static func _d(dist: PackedFloat32Array, w: int, h: int, x: int, y: int) -> float:
	return dist[y * w + x] if x >= 0 and y >= 0 and x < w and y < h else 0.0


static func _in(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and mask[y * w + x] == 1


## Scanline fill: a pixel is inside if its centre is inside the polygon.
static func _rasterize(outline: PackedVector2Array, origin: Vector2i, w: int, h: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	var n := outline.size()
	for y in h:
		var cy := origin.y + y + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := outline[i]
			var b := outline[(i + 1) % n]
			if (a.y <= cy) != (b.y <= cy):
				xs.append(a.x + (cy - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := maxi(ceili(xs[k] - origin.x - 0.5), 0)
			var x1 := mini(floori(xs[k + 1] - origin.x - 0.5), w - 1)
			for x in range(x0, x1 + 1):
				mask[y * w + x] = 1
	return mask


## Chamfer distance (in px) from each inside pixel to the nearest outside pixel.
static func _distance(mask: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	const D := 1.41421356
	var d := PackedFloat32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = 1e9 if mask[i] else 0.0
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			var v := d[i]
			v = minf(v, (d[i - 1] if x > 0 else 0.0) + 1.0)
			v = minf(v, (d[i - w] if y > 0 else 0.0) + 1.0)
			v = minf(v, (d[i - w - 1] if x > 0 and y > 0 else 0.0) + D)
			v = minf(v, (d[i - w + 1] if x < w - 1 and y > 0 else 0.0) + D)
			d[i] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if not mask[i]:
				continue
			var v := d[i]
			v = minf(v, (d[i + 1] if x < w - 1 else 0.0) + 1.0)
			v = minf(v, (d[i + w] if y < h - 1 else 0.0) + 1.0)
			v = minf(v, (d[i + w + 1] if x < w - 1 and y < h - 1 else 0.0) + D)
			v = minf(v, (d[i + w - 1] if x > 0 and y < h - 1 else 0.0) + D)
			d[i] = v
	return d


## Noise bites taken out of the edge, only inward, up to `roughness` px deep.
static func _erode(mask: PackedByteArray, w: int, h: int, rock_seed: int, roughness: float) -> void:
	if roughness <= 0.0:
		return
	var dist := _distance(mask, w, h)
	var noise := FastNoiseLite.new()
	noise.seed = rock_seed
	noise.frequency = 0.06
	noise.fractal_octaves = 2
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			var n := clampf((noise.get_noise_2d(x, y) + 0.15) / 0.65, 0.0, 1.0)
			if dist[i] < roughness * n + 0.5:
				mask[i] = 0
	# Drop stray pixels left hanging off the edge.
	for _pass in 2:
		for y in h:
			for x in w:
				var i := y * w + x
				if not mask[i]:
					continue
				var c := int(_in(mask, w, h, x - 1, y)) + int(_in(mask, w, h, x + 1, y)) \
					+ int(_in(mask, w, h, x, y - 1)) + int(_in(mask, w, h, x, y + 1))
				if c < 2:
					mask[i] = 0


## Base shading: lit from the top-left, flat facets, quantized to 4 palette levels.
static func _shade(mask: PackedByteArray, dist: PackedFloat32Array, w: int, h: int, rock_seed: int,
		type: RockType, colors: PackedColorArray, levels: PackedByteArray, normals: PackedVector2Array) -> void:
	var facets := FastNoiseLite.new()
	facets.seed = rock_seed + 1
	facets.noise_type = FastNoiseLite.TYPE_CELLULAR
	facets.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	facets.fractal_type = FastNoiseLite.FRACTAL_NONE
	facets.frequency = 0.07
	var grain := FastNoiseLite.new()
	grain.seed = rock_seed + 2
	grain.fractal_type = FastNoiseLite.FRACTAL_NONE
	grain.frequency = 0.35
	var pal := type.palette()
	var depth := clampf(minf(w, h) * 0.25, 3.0, 12.0)
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			# Wide (±2 px) differences give smoother normals than ±1.
			var gx := _d(dist, w, h, x + 2, y) + _d(dist, w, h, x + 1, y) - _d(dist, w, h, x - 1, y) - _d(dist, w, h, x - 2, y)
			var gy := _d(dist, w, h, x, y + 2) + _d(dist, w, h, x, y + 1) - _d(dist, w, h, x, y - 1) - _d(dist, w, h, x, y - 2)
			var outward := -Vector2(gx, gy).normalized()
			normals[i] = outward
			var edge := clampf(1.0 - (dist[i] - 1.0) / depth, 0.0, 1.0)
			var v := 0.5 + 0.55 * outward.dot(LIGHT_DIR) * edge
			v += 0.1 * facets.get_noise_2d(x, y)
			v += 0.05 * grain.get_noise_2d(x, y)
			v += 0.2 * (0.5 - float(y) / h)
			var level := 0 if v < 0.32 else (1 if v < 0.6 else (2 if v < 0.82 else 3))
			levels[i] = level
			colors[i] = pal[level]


static func _bands(mask: PackedByteArray, w: int, h: int, rock_seed: int, type: RockType,
		colors: PackedColorArray, levels: PackedByteArray) -> void:
	var warp := FastNoiseLite.new()
	warp.seed = rock_seed + 3
	warp.frequency = 0.04
	var sc := type.streak_colors
	var thickness := float(type.width) / type.band_spacing
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			var t := (y + warp.get_noise_2d(x, y) * type.band_spacing * 1.5) / type.band_spacing
			var idx := floori(t)
			if t - idx >= thickness:
				continue
			var r: float = (rand_from_seed(rock_seed * 31 + idx)[0] % 1000) / 1000.0
			if r >= type.density:
				continue
			var c := sc[posmod(idx * 7 + rock_seed, sc.size())]
			# Keep the shading: tint the shaded colour instead of replacing it.
			colors[i] = colors[i].lerp(c, 0.6)


static func _patches(mask: PackedByteArray, dist: PackedFloat32Array, normals: PackedVector2Array,
		w: int, h: int, rock_seed: int, type: RockType, colors: PackedColorArray, levels: PackedByteArray) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rock_seed + 4
	noise.frequency = 0.1
	var sc := type.streak_colors
	var depth := clampf(minf(w, h) * 0.2, 2.0, 8.0)
	for y in h:
		for x in w:
			var i := y * w + x
			if not mask[i]:
				continue
			var top := 1.0 if normals[i].y < -0.6 and dist[i] <= depth else 0.0
			var v := (noise.get_noise_2d(x, y) + 1.0) * 0.3 + top * 0.5 + 0.15 * (1.0 - float(y) / h)
			if v > 1.0 - type.density:
				colors[i] = sc[clampi(levels[i] * sc.size() / 4, 0, sc.size() - 1)]


static func _veins(mask: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator, type: RockType,
		colors: PackedColorArray) -> void:
	var area := 0
	for m in mask:
		area += m
	var count := maxi(1, roundi(area * type.density / type.vein_length))
	var sc := type.streak_colors
	for _v in count:
		var pos := Vector2(-1, -1)
		for _try in 50:
			var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
			if mask[p.y * w + p.x]:
				pos = Vector2(p) + Vector2(0.5, 0.5)
				break
		if pos.x < 0:
			continue
		var c := sc[rng.randi() % sc.size()]
		var angle := rng.randf() * TAU
		for _step in type.vein_length:
			var px := Vector2i(pos.floor())
			if not _in(mask, w, h, px.x, px.y):
				break
			_dab(mask, w, h, px, type.width, c, colors)
			angle += rng.randf_range(-0.35, 0.35)
			pos += Vector2.from_angle(angle)


static func _speckles(mask: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator, type: RockType,
		colors: PackedColorArray) -> void:
	var sc := type.streak_colors
	for y in h:
		for x in w:
			if mask[y * w + x] and rng.randf() < type.density:
				_dab(mask, w, h, Vector2i(x, y), type.width, sc[rng.randi() % sc.size()], colors)


## Paints a width x width square at p, clipped to the rock.
static func _dab(mask: PackedByteArray, w: int, h: int, p: Vector2i, size: int, c: Color, colors: PackedColorArray) -> void:
	for dy in size:
		for dx in size:
			if _in(mask, w, h, p.x + dx, p.y + dy):
				colors[(p.y + dy) * w + p.x + dx] = c
