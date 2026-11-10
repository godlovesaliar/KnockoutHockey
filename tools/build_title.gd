extends Node
## Bakes the chrome title words (MenuStyle.chrome_text) into images, so the rims go
## around the letters only and not around the title font's loose splatter specks:
##   godot --path . res://tools/BuildTitle.tscn        (needs a window, not --headless)
##
## Each word is drawn plain at 2x, split into connected shapes, and the big ones (letters,
## with any drips still attached) become the letter mask; small detached shapes are specks.
## The white, red and navy rims and the drop shadow are grown from the letter mask (exact
## distance transform); the chrome fill covers letters and specks alike.
##   -> res://assets/ui/title/<word>_<size>.png   (chrome_text uses it when it exists)
## Rerun after changing MenuStyle.TITLE_FONT, TITLE_SPACING or the words below.

const WORDS := [["KNOCKOUT", 120], ["HOCKEY", 120], ["VS", 110]]
const OUT_DIR := "res://assets/ui/title/"
const SCALE := 2                 ## baked at this multiple of the design size
const SPECK := 0.12              ## a shape smaller than this fraction of the biggest is a speck
## Rim radii as fractions of the font size (design px), and the shadow's offset.
const R_WHITE := 0.035
const R_RED := 0.09
const R_NAVY := 0.15
const SHADOW := Vector2(8, 10)
const NAVY := Color(0.04, 0.06, 0.14)
const WHITE_RIM := Color(0.98, 0.98, 1.0)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for w: Array in WORDS:
		await _bake(w[0], w[1])
	get_tree().quit()


func _bake(text: String, size: int) -> void:
	var t0 := Time.get_ticks_msec()
	var m := MenuStyle.bake_margin(size)
	var holder := MenuStyle.chrome_size(text, size)
	var big := size * SCALE
	var f := MenuStyle.title_font(big)
	var w := int(ceil((holder.x + m * 2.0) * SCALE))
	var h := int(ceil((holder.y + m * 2.0) * SCALE))
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", big)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.position = Vector2(m + size * MenuStyle.CHROME_PAD, m) * SCALE
	vp.add_child(l)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()

	var n := w * h
	var a := PackedFloat64Array()
	a.resize(n)
	for y in h:
		for x in w:
			a[y * w + x] = img.get_pixel(x, y).a

	# Connected shapes (8-connected, alpha over half), biggest first.
	var lab := PackedInt32Array()
	lab.resize(n)
	lab.fill(-1)
	var areas: Array[int] = []
	var stack := PackedInt32Array()
	for i in n:
		if a[i] < 0.5 or lab[i] >= 0:
			continue
		var id := areas.size()
		var area := 0
		stack.clear()
		stack.append(i)
		lab[i] = id
		while not stack.is_empty():
			var p: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			area += 1
			var px := p % w
			var py := p / w
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var qx: int = px + dx
					var qy: int = py + dy
					if qx < 0 or qy < 0 or qx >= w or qy >= h:
						continue
					var q := qy * w + qx
					if lab[q] < 0 and a[q] >= 0.5:
						lab[q] = id
						stack.append(q)
		areas.append(area)
	var biggest := 0
	for ar in areas:
		biggest = maxi(biggest, ar)
	var keep := PackedByteArray()
	keep.resize(areas.size())
	var letters := 0
	for k in areas.size():
		keep[k] = 1 if areas[k] >= biggest * SPECK else 0
		letters += keep[k]

	# Letter mask: kept shapes, plus their soft edge pixels.
	var inside := PackedByteArray()
	inside.resize(n)
	for i in n:
		if lab[i] >= 0:
			inside[i] = keep[lab[i]]
	var edge := PackedFloat64Array()   # a letter's own antialiased edge coverage
	edge.resize(n)
	for y in h:
		for x in w:
			var i := y * w + x
			if inside[i]:
				edge[i] = 1.0
			elif a[i] > 0.0:
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var qx: int = x + dx
						var qy: int = y + dy
						if qx >= 0 and qy >= 0 and qx < w and qy < h and inside[qy * w + qx]:
							edge[i] = a[i]

	var dist := _edt(inside, w, h)
	var s := float(SCALE)
	var asc := f.get_ascent(big)
	var top := m * s + asc * 0.22
	var height := asc * 0.95
	var sh := Vector2i(roundi(SHADOW.x * s), roundi(SHADOW.y * s))
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			var c := Color(0, 0, 0, 0)
			# Shadow: the navy rim's shape, offset.
			var sx := x - sh.x
			var sy := y - sh.y
			if sx >= 0 and sy >= 0:
				var sa := _cover(dist[sy * w + sx], R_NAVY * size * s) * 0.45
				c = _over(c, Color(0, 0, 0, sa))
			c = _over(c, Color(NAVY, _cover(d, R_NAVY * size * s)))
			c = _over(c, Color(MenuStyle.RED, _cover(d, R_RED * size * s)))
			c = _over(c, Color(WHITE_RIM, _cover(d, R_WHITE * size * s)))
			# Chrome fill on every glyph pixel, letters and specks.
			var fa := maxf(a[i], edge[i])
			if fa > 0.0:
				c = _over(c, Color(MenuStyle.chrome_color((y - top) / height), fa))
			out.set_pixel(x, y, c)
	var path := OUT_DIR + "%s_%d.png" % [text.to_lower(), size]
	out.save_png(path)
	print("%s: %d x %d, %d shapes, %d letters, %d ms -> %s" % [text, w, h, areas.size(), letters,
			Time.get_ticks_msec() - t0, path])


## Coverage of a rim of radius `r` at distance `d` (px) from the letters, antialiased.
static func _cover(d: float, r: float) -> float:
	return clampf(r - d + 0.5, 0.0, 1.0)


static func _over(dst: Color, src: Color) -> Color:
	var oa := src.a + dst.a * (1.0 - src.a)
	if oa <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Color(src.r, src.g, src.b) * src.a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / oa
	return Color(rgb.r, rgb.g, rgb.b, oa)


## Euclidean distance (px) from each pixel to the nearest `inside` pixel
## (Felzenszwalb & Huttenlocher: 1D squared transforms down the columns, then the rows).
static func _edt(inside: PackedByteArray, w: int, h: int) -> PackedFloat64Array:
	const BIG := 1e12
	var g := PackedFloat64Array()
	g.resize(w * h)
	var col := PackedFloat64Array()
	col.resize(h)
	for x in w:
		for y in h:
			col[y] = 0.0 if inside[y * w + x] else BIG
		var r := _edt1(col)
		for y in h:
			g[y * w + x] = r[y]
	var row := PackedFloat64Array()
	row.resize(w)
	var out := PackedFloat64Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			row[x] = g[y * w + x]
		var r := _edt1(row)
		for x in w:
			out[y * w + x] = sqrt(r[x])
	return out


static func _edt1(f: PackedFloat64Array) -> PackedFloat64Array:
	var n := f.size()
	var d := PackedFloat64Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat64Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var s := ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		while s <= z[k]:
			k -= 1
			s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]
	return d
