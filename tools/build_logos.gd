extends SceneTree
## Cuts the team logos out of the logo sheets into transparent PNGs:
##   godot --headless --path . -s res://tools/build_logos.gd [-- only=<sheet file>]
##
## Each sheet (assets/images/) has one logo, or four, one per quadrant, on a dark background
## (or a light one, for sheets marked `light`: then the fill takes pale pixels).
## In each quadrant the background is flood-filled from the quadrant's border: pixels
## darker than the sheet's `lum` (and, if `sat` < 1, less saturated than `sat`)
## connected to the edge. Each logo's bright outer border stops the fill, so dark parts
## inside a logo survive. Leftovers (corner numbers, ghost-logo scraps in busy
## backgrounds) are dropped unless they're a sizable share of the logo. The edge gets a
## one-pixel soft alpha, and the logo is cropped and scaled to at most MAX_SIZE.
##   -> res://assets/characters/logo_<team>.png   (team = Teams.LIST "id")
## Like an NHL crest, each logo gets a keyline: a band just outside its black outline in
## a color that stands off that team's jersey (see keyline_color), so a navy logo still
## reads on a navy jersey.

const SHEETS := [
	# Old 4-logo sheets, kept for the two spare logos. Faint, colored ghost logos in the
	# background: brightness alone decides.
	{"file": "res://assets/images/logos2.webp", "teams": ["", "anchor", "", ""], "lum": 0.3, "sat": 1.0},
	{"file": "res://assets/images/logos3.webp", "teams": ["", "", "", "beacon"], "lum": 0.3, "sat": 1.0},
	# Redrawn logos: one per image on a white or off-white background. "keep" lowers
	# KEEP_SHARE for logos with small separate pieces (script lettering). "recolor" swaps
	# the logo's flat colors to match the team (see _apply_recolor): [from, to, tolerance].
	{"file": "res://assets/images/whalers.jfif", "teams": ["whalers"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/quahogs.jfif", "teams": ["quahogs"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/lobsters (2).jfif", "teams": ["lobsters"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/lakemonsters.jfif", "teams": ["lakemonsters"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/trailblazers.jfif", "teams": ["trailblazers"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/mariners.jfif", "teams": ["mariners"], "lum": 0.8, "sat": 0.12, "light": true, "holes": true},
	{"file": "res://assets/images/granite.jfif", "teams": ["granite"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/cranberries.jfif", "teams": ["cranberries"], "lum": 0.8, "sat": 0.12, "light": true},   # alt: cranberries2.jfif (Cape Cod C)
	{"file": "res://assets/images/rats.jfif", "teams": ["rats"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/poutine.jfif", "teams": ["poutine"], "lum": 0.8, "sat": 0.12, "light": true, "holes": [[0.5, 0.48]]},
	{"file": "res://assets/images/geese.jfif", "teams": ["geese"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/mitts.jfif", "teams": ["mitts"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/curds.jfif", "teams": ["curds"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/gale.jfif", "teams": ["gales"], "lum": 0.8, "sat": 0.12, "light": true, "recolor": [["e0a030", "9ed1ed", 0.25]]},   # gold -> ice blue: the team's new storm gray / ice blue
	{"file": "res://assets/images/moosejaws.jfif", "teams": ["moosejaws"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/twang.jfif", "teams": ["twang"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/moonshiners.jfif", "teams": ["moonshiners"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/swampthings.jfif", "teams": ["swampthings"], "lum": 0.8, "sat": 0.12, "light": true, "recolor": [["606030", "1f3d26", 0.17]]},   # moss creature -> dark green, off the moss jersey
	{"file": "res://assets/images/floridaman.jfif", "teams": ["floridaman"], "lum": 0.8, "sat": 0.12, "light": true, "keep": 0.0005},
	{"file": "res://assets/images/armadillos.jfif", "teams": ["armadillos"], "lum": 0.8, "sat": 0.12, "light": true, "recolor": [["208080", "ad4d0f", 0.22]]},   # teal star -> burnt orange (new colors)
	{"file": "res://assets/images/geoducks.jfif", "teams": ["geoducks"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/grays.jfif", "teams": ["grays"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/sourdoughs.jfif", "teams": ["sourdoughs"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/lumberjacks.jfif", "teams": ["lumberjacks"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/otters.jfif", "teams": ["otters"], "lum": 0.8, "sat": 0.12, "light": true, "keep": 0.0005, "recolor": [["8080d0", "f2f2ed", 0.2]], "holes": true},   # periwinkle script -> white, off the periwinkle jersey
	{"file": "res://assets/images/gilamonsters.jfif", "teams": ["gilamonsters"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/spuds.jfif", "teams": ["spuds"], "lum": 0.8, "sat": 0.12, "light": true, "recolor": [["502080", "f2f2ed", 0.2], ["ffffff", "572e85", 0.1]]},   # purple glove <-> white cuff, off the purple jersey
	{"file": "res://assets/images/stuntmen.jfif", "teams": ["stuntmen"], "lum": 0.8, "sat": 0.12, "light": true},   # alt: stuntmen2.jfif (S)
	{"file": "res://assets/images/seagulls.jfif", "teams": ["seagulls"], "lum": 0.8, "sat": 0.12, "light": true},
	{"file": "res://assets/images/geysers.jfif", "teams": ["geysers"], "lum": 0.8, "sat": 0.12, "light": true},
]   ## teams: quadrants TL, TR, BL, BR ("" = superseded); a one-team entry is the whole image
const OUT := "res://assets/characters/logo_%s.png"
const MAX_SIZE := 768
const KEEP_SHARE := 0.03    ## pieces smaller than this share of the biggest are dropped
const PAD := 6
const KEYLINE := 0.014      ## outer keyline width, as a share of the logo's longer side

var _lum := 0.33
var _sat := 0.09
var _light := false
var _keep := KEEP_SHARE
var _recolor: Array = []
var _holes: Variant = false   ## see _clear_holes


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	for sheet: Dictionary in SHEETS:
		if only != "" and not (sheet.file as String).ends_with(only):
			continue
		var img := Image.new()
		var bytes := FileAccess.get_file_as_bytes(sheet.file)
		var file: String = sheet.file
		var err := img.load_webp_from_buffer(bytes) if file.ends_with(".webp") else (img.load_png_from_buffer(bytes) if file.ends_with(".png") else img.load_jpg_from_buffer(bytes))
		if err != OK:
			push_error("can't read %s: %s" % [sheet.file, error_string(err)])
			continue
		img.convert(Image.FORMAT_RGBA8)
		_sat = sheet.sat
		_light = sheet.get("light", false)
		_holes = true if OS.get_cmdline_user_args().has("allholes") else sheet.get("holes", false)
		var w := img.get_width()
		var h := img.get_height()
		_keep = sheet.get("keep", KEEP_SHARE)
		_recolor = sheet.get("recolor", [])
		if sheet.teams.size() == 1:
			_lum = sheet.lum
			_cut(img, sheet.teams[0])
			continue
		for q in 4:
			if sheet.teams[q] == "":
				continue
			_lum = (sheet.get("lum_for", {}) as Dictionary).get(sheet.teams[q], sheet.lum)
			var r := Rect2i((q % 2) * (w / 2), (q / 2) * (h / 2), w / 2, h / 2)
			_cut(img.get_region(r), sheet.teams[q])
	quit()


func _is_bg(c: Color) -> bool:
	if _light:
		return c.get_luminance() > _lum and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < _sat
	return c.get_luminance() < _lum and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < _sat


func _cut(img: Image, name: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] == 1:
			continue
		var x := i % w
		var y := i / w
		if not _is_bg(img.get_pixel(x, y)):
			continue
		bg[i] = 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	if _holes is Array or _holes == true:
		_clear_holes(img, bg, w, h)
	# Stray specks the fill missed (texture noise, corner numbers, ghost scraps): keep
	# only the logo's own pieces, i.e. connected regions at least KEEP_SHARE of the biggest.
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var sizes := PackedInt32Array()
	for start in w * h:
		if bg[start] == 1 or comp[start] >= 0:
			continue
		var id := sizes.size()
		var n := 0
		stack.append(start)
		comp[start] = id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var x := i % w
			for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if j >= 0 and j < w * h and bg[j] == 0 and comp[j] < 0:
					comp[j] = id
					stack.append(j)
		sizes.append(n)
	var biggest := 0
	for n in sizes:
		biggest = maxi(biggest, n)
	for i in w * h:
		if bg[i] == 0 and sizes[comp[i]] < biggest * _keep:
			bg[i] = 1
	# Alpha: background clear, logo opaque, its outermost pixels half (soft edge).
	var box := Rect2i()
	var first := true
	for y in h:
		for x in w:
			var i := y * w + x
			var c := img.get_pixel(x, y)
			if bg[i] == 1:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
				continue
			var edge := (x > 0 and bg[i - 1] == 1) or (x < w - 1 and bg[i + 1] == 1) \
					or (y > 0 and bg[i - w] == 1) or (y < h - 1 and bg[i + w] == 1)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.5 if edge else 1.0))
			box = Rect2i(x, y, 1, 1) if first else box.expand(Vector2i(x, y)).merge(Rect2i(x, y, 1, 1))
			first = false
	box = box.grow(PAD).intersection(Rect2i(0, 0, w, h))
	var out := img.get_region(box)
	var s := minf(1.0, float(MAX_SIZE) / maxi(out.get_width(), out.get_height()))
	if s < 1.0:
		out.resize(int(out.get_width() * s), int(out.get_height() * s), Image.INTERPOLATE_LANCZOS)
	if not _recolor.is_empty():
		_apply_recolor(out, _recolor)
	var ring := keyline_color(name)
	if ring.a > 0.0:
		out = _keyline(out, ring, maxi(3, roundi(maxf(out.get_width(), out.get_height()) * KEYLINE)))
	var path := OUT % name
	var err := out.save_png(path)
	print("%s: %s  %s" % [path, error_string(err), out.get_size()])


## The keyline color for a team's logo: whichever of white and the team's trim, number
## and number-outline colors differs most in brightness from its jersey. Transparent
## for logos no team uses (spares).
static func keyline_color(id: String) -> Color:
	var path := OUT % id
	for t: Dictionary in Teams.LIST:
		if t.get("logo", "") != path:
			continue
		var c: Dictionary = t.colors
		var jersey: Color = c.jersey
		var best := Color(0.96, 0.96, 0.94)
		var best_d := absf(best.get_luminance() - jersey.get_luminance())
		for k in ["trim", "number", "number_outline"]:
			var cand: Color = c[k]
			var d := absf(cand.get_luminance() - jersey.get_luminance())
			if d > best_d + 0.05:
				best = cand
				best_d = d
		return best
	return Color(0, 0, 0, 0)


## `img` with a band `r` px wide in `color` around everything opaque, under it (the
## image grows by r on each side). Distance by a two-pass chamfer (3-4) transform.
func _keyline(img: Image, color: Color, r: int) -> Image:
	var w := img.get_width() + r * 2 + 2
	var h := img.get_height() + r * 2 + 2
	var src := Image.create(w, h, false, Image.FORMAT_RGBA8)
	src.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(r + 1, r + 1))
	var big := 1 << 20
	var dist := PackedInt32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			dist[y * w + x] = 0 if src.get_pixel(x, y).a > 0.4 else big
	# Holes (clear pixels the outside can't reach) count as inside: the band only grows
	# outward from the silhouette, and the holes stay clear.
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack := PackedInt32Array([0])
	outside[0] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := i % w
		for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if j >= 0 and j < w * h and outside[j] == 0 and dist[j] == big:
				outside[j] = 1
				stack.append(j)
	for i in w * h:
		if dist[i] == big and outside[i] == 0:
			dist[i] = 0
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if x > 0: d = mini(d, dist[i - 1] + 3)
			if y > 0:
				d = mini(d, dist[i - w] + 3)
				if x > 0: d = mini(d, dist[i - w - 1] + 4)
				if x < w - 1: d = mini(d, dist[i - w + 1] + 4)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if x < w - 1: d = mini(d, dist[i + 1] + 3)
			if y < h - 1:
				d = mini(d, dist[i + w] + 3)
				if x < w - 1: d = mini(d, dist[i + w + 1] + 4)
				if x > 0: d = mini(d, dist[i + w - 1] + 4)
			dist[i] = d
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dd := dist[y * w + x] / 3.0
			var ra := clampf(r + 0.5 - dd, 0.0, 1.0)   # soft outer edge
			if outside[y * w + x] == 0 and src.get_pixel(x, y).a <= 0.4:
				ra = 0.0   # a hole: stays clear
			var base := Color(color.r, color.g, color.b, ra)
			var top := src.get_pixel(x, y)
			# The logo over the band.
			var a := top.a + base.a * (1.0 - top.a)
			if a <= 0.0:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rgb := (Color(top.r, top.g, top.b) * top.a + Color(base.r, base.g, base.b) * base.a * (1.0 - top.a)) / a
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return out


## Swaps a logo's flat colors in place: each [from, to, tolerance] (html, html, RGB
## distance) moves pixels within tolerance of `from` by (to - from), so shading and
## highlights inside a color area survive; pixels near two entries take the closer one.
## Anti-aliased edges into the black outline are part-way, so they shift part-way.
func _apply_recolor(img: Image, swaps: Array) -> void:
	var froms: Array[Color] = []
	var deltas: Array[Color] = []
	var tols: Array[float] = []
	for sw: Array in swaps:
		var f := Color.html(sw[0])
		var t := Color.html(sw[1])
		froms.append(f)
		deltas.append(Color(t.r - f.r, t.g - f.g, t.b - f.b, 0.0))
		tols.append(float(sw[2]))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var best := -1
			var best_d := 9.0
			for i in froms.size():
				var d := Vector3(c.r - froms[i].r, c.g - froms[i].g, c.b - froms[i].b).length()
				if d < tols[i] and d < best_d:
					best = i
					best_d = d
			if best < 0:
				continue
			var w := 1.0 - smoothstep(tols[best] * 0.6, tols[best], best_d)
			var dl := deltas[best]
			img.set_pixel(x, y, Color(clampf(c.r + dl.r * w, 0, 1), clampf(c.g + dl.g * w, 0, 1), clampf(c.b + dl.b * w, 0, 1), c.a))


## Background enclosed by the logo (the counter of an O or P, the gaps between a ship
## wheel's spokes) that the border fill can't reach: connected background-like pixels
## whose average color matches the sheet's background (sampled at a corner) are cleared
## too. Opt-in per entry, since a logo's own whites are often the paper's exact white
## (stripes, a gull's head): "holes": true clears every such pocket; "holes": [[x, y], ..]
## only the pockets centered near those points (fractions of the image). Run the cutter
## with `-- only=<file> allholes` to list every pocket's size and center.
const HOLE_MATCH := 0.05       ## mean RGB distance from the background to count as a hole
const HOLE_MIN := 0.00002      ## smallest hole, as a share of the image (smaller: left)

func _clear_holes(img: Image, bg: PackedByteArray, w: int, h: int) -> void:
	var ref := img.get_pixel(2, 2)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var cleared := 0
	for start in w * h:
		if bg[start] == 1 or seen[start] == 1:
			continue
		if not _is_bg(img.get_pixel(start % w, start / w)):
			continue
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var members := PackedInt32Array()
		var sum := Vector3.ZERO
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			members.append(i)
			var c := img.get_pixel(i % w, i / w)
			sum += Vector3(c.r, c.g, c.b)
			var x := i % w
			for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if j >= 0 and j < w * h and seen[j] == 0 and bg[j] == 0 and _is_bg(img.get_pixel(j % w, j / w)):
					seen[j] = 1
					stack.append(j)
		var mean := sum / members.size()
		var d := mean.distance_to(Vector3(ref.r, ref.g, ref.b))
		if members.size() >= w * h * HOLE_MIN and d < HOLE_MATCH:
			var cx := 0.0
			var cy := 0.0
			for i in members:
				cx += i % w
				cy += i / w
			var at := Vector2(cx / members.size() / w, cy / members.size() / h)
			if _holes is Array:
				var near := false
				for pt: Array in _holes:
					near = near or at.distance_to(Vector2(pt[0], pt[1])) < 0.05
				if not near:
					continue
			if OS.get_cmdline_user_args().has("allholes"):
				print("    hole %d px at (%.2f, %.2f)" % [members.size(), at.x, at.y])
			for i in members:
				bg[i] = 1
			cleared += 1
	if cleared > 0:
		print("  holes cleared: %d" % cleared)
