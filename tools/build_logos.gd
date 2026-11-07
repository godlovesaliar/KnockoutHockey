extends SceneTree
## Cuts the team logos out of the logo sheets into transparent PNGs:
##   godot --headless --path . -s res://tools/build_logos.gd [-- only=<sheet file>]
##
## Each sheet (assets/images/) has four logos, one per quadrant, on a dark background.
## In each quadrant the background is flood-filled from the quadrant's border: pixels
## darker than the sheet's `lum` (and, if `sat` < 1, less saturated than `sat`)
## connected to the edge. Each logo's bright outer border stops the fill, so dark parts
## inside a logo survive. Leftovers (corner numbers, ghost-logo scraps in busy
## backgrounds) are dropped unless they're a sizable share of the logo. The edge gets a
## one-pixel soft alpha, and the logo is cropped and scaled to at most MAX_SIZE.
##   -> res://assets/characters/logo_<team>.png   (team = Teams.LIST "id")

const SHEETS := [
	{"file": "res://assets/images/teamlogos.jfif", "teams": ["whalers", "geese", "quahogs", "lobsters"], "lum": 0.33, "sat": 0.09},
	# These two have faint, colored ghost logos in the background: brightness alone decides.
	{"file": "res://assets/images/logos2.webp", "teams": ["lakemonsters", "anchor", "trailblazers", "mariners"], "lum": 0.3, "sat": 1.0,
		"lum_for": {"lakemonsters": 0.5}},   # its ghost lettering is brighter
	{"file": "res://assets/images/logos3.webp", "teams": ["granite", "cranberries", "rats", "beacon"], "lum": 0.3, "sat": 1.0},
	{"file": "res://assets/images/logos4.png", "teams": ["mitts", "poutine", "geoducks", "grays"], "lum": 0.33, "sat": 0.09},
	{"file": "res://assets/images/logos5.jfif", "teams": ["curds", "gales", "sourdoughs", "moosejaws"], "lum": 0.33, "sat": 0.09},
	{"file": "res://assets/images/logos6.jfif", "teams": ["twang", "moonshiners", "swampthings", "floridaman"], "lum": 0.33, "sat": 0.09},
]   ## teams: quadrants TL, TR, BL, BR
const OUT := "res://assets/characters/logo_%s.png"
const MAX_SIZE := 768
const KEEP_SHARE := 0.03    ## pieces smaller than this share of the biggest are dropped
const PAD := 6

var _lum := 0.33
var _sat := 0.09


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
		var w := img.get_width()
		var h := img.get_height()
		for q in 4:
			_lum = (sheet.get("lum_for", {}) as Dictionary).get(sheet.teams[q], sheet.lum)
			var r := Rect2i((q % 2) * (w / 2), (q / 2) * (h / 2), w / 2, h / 2)
			_cut(img.get_region(r), sheet.teams[q])
	quit()


func _is_bg(c: Color) -> bool:
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
		if bg[i] == 0 and sizes[comp[i]] < biggest * KEEP_SHARE:
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
	var path := OUT % name
	var err := out.save_png(path)
	print("%s: %s  %s" % [path, error_string(err), out.get_size()])
