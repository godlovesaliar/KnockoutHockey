class_name BadgeLogo
## A created team's logo, built from parts in Create Team: a shape with a border, a
## pattern inside it, an icon and/or lettering, each part in one of the team's color
## slots (CustomTeams.SLOTS). draw() paints it into any rect on a CanvasItem; Create
## Team draws it big on its card and into a 512 px viewport that's saved as the team's
## logo PNG (which the game then uses like any crest).
##
## Settings (all JSON-friendly):
##   shape, border, pattern, icon, layout ("text" / "icon" / "icon_text"), text (empty:
##   the team's code), font (index into FONTS), italic, and the colors: fill, edge,
##   pattern_color, icon_color, text_color, outline (SLOTS names).

const SHAPES := ["shield", "crest", "round", "diamond", "hexagon", "square", "none"]
const SHAPE_NAMES := ["Shield", "Crest", "Round", "Diamond", "Hexagon", "Square", "None"]
const BORDERS := ["none", "thin", "thick", "double"]
const BORDER_NAMES := ["None", "Thin", "Thick", "Double"]
const PATTERNS := ["none", "band", "sash", "split", "chevron", "chief", "hoops", "quarters"]
const PATTERN_NAMES := ["None", "Band", "Sash", "Split", "Chevron", "Top Bar", "Hoops", "Quarters"]
## Stock logos (drawn art, cut by `tools/build_logos.gd -- mascots`): each is a strip of
## five layers in res://assets/ui/mascots/<id>.png, the silhouette (in `outline`) and then
## the art's navy, red, gold and white areas, each tinted with the slot in MASCOT_KEYS.
const MASCOTS := ["wolverine", "owl", "crow", "shark", "narwhal", "turtle", "sasquatch", "jackalope", "viking", "coffee", "donut"]
const MASCOT_NAMES := ["Wolverine", "Owl", "Crow", "Shark", "Narwhal", "Snapping Turtle", "Sasquatch", "Jackalope", "Viking", "Coffee Cup", "Donut"]
const MASCOT_KEYS := ["logo_navy", "logo_red", "logo_gold", "logo_white"]
const ICONS := ["none", "star", "three_stars", "bolt", "crown", "sticks", "puck", "mountains", "wave", "claws"] + MASCOTS
const ICON_NAMES := ["None", "Star", "Three Stars", "Lightning", "Crown", "Crossed Sticks", "Puck", "Mountains", "Wave", "Claws"] + MASCOT_NAMES
const LAYOUTS := ["icon_text", "text", "icon"]
const LAYOUT_NAMES := ["Icon and Letters", "Letters Only", "Icon Only"]
## [name, font file under res://assets/fonts/ or system font names].
const FONTS := [
	["Block", ["Segoe UI Black", "Arial Black", "Impact"]],
	["Russo", "RussoOne-Regular.ttf"],
	["Wide", "Michroma.ttf"],
	["Slab", ["Rockwell Extra Bold", "Rockwell", "Georgia"]],
	["Classic", ["Georgia", "Times New Roman"]],
	["Condensed", ["Impact", "Arial Narrow", "Arial Black"]],
]
const TEXT_MAX := 4

static var _fonts := {}


static func blank() -> Dictionary:
	return {
		"shape": "shield", "border": "thick", "pattern": "none", "icon": "star", "layout": "icon_text",
		"text": "", "font": 0, "italic": true,
		"fill": "primary", "edge": "secondary", "pattern_color": "accent",
		"icon_color": "accent", "text_color": "secondary", "outline": "black",
		"logo_navy": "primary", "logo_red": "secondary", "logo_gold": "accent", "logo_white": "white",
	}


## JSON numbers come back as floats; badges saved before a setting existed get its default.
static func fix_types(b: Dictionary) -> void:
	b.font = int(b.get("font", 0))
	b.italic = bool(b.get("italic", true))
	var d := blank()
	for k: String in d:
		if not b.has(k):
			b[k] = d[k]


static func is_mascot(icon: String) -> bool:
	return icon in MASCOTS


static var _mascot_tex := {}

static func mascot_texture(id: String) -> Texture2D:
	if not _mascot_tex.has(id):
		var path := "res://assets/ui/mascots/%s.png" % id
		_mascot_tex[id] = load(path) if ResourceLoader.exists(path) else null
	return _mascot_tex[id]


## A stock logo fitted into `r` (kept to its own proportions): the silhouette in the
## outline color, then each color area over it. `tints`: outline, navy, red, gold, white.
static func _mascot(ci: CanvasItem, id: String, r: Rect2, tints: Array[Color]) -> void:
	var tex := mascot_texture(id)
	if tex == null:
		return
	var lw := tex.get_width() / 5.0
	var lh := float(tex.get_height())
	var k := minf(r.size.x / lw, r.size.y / lh)
	var dst := Rect2(r.get_center() - Vector2(lw, lh) * k * 0.5, Vector2(lw, lh) * k)
	for layer in 5:
		ci.draw_texture_rect_region(tex, dst, Rect2(lw * layer, 0, lw, lh), tints[layer])


static func font(index: int, italic: bool) -> Font:
	var key := "%d|%s" % [index, italic]
	if _fonts.has(key):
		return _fonts[key]
	var spec: Variant = FONTS[clampi(index, 0, FONTS.size() - 1)][1]
	var base: Font = null
	if spec is String and ResourceLoader.exists("res://assets/fonts/" + spec):
		base = load("res://assets/fonts/" + spec)
	if base == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(spec if spec is Array else ["Arial Black"])
		sf.font_weight = 800
		base = sf
	var v := FontVariation.new()
	v.base_font = base
	if italic:
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2.ZERO)
	_fonts[key] = v
	return v


## Paints the badge into `r`. `colors`: the team's slot colors (CustomTeams.slot_colors);
## `fallback`: the lettering when the badge has none of its own (the team's code).
static func draw(ci: CanvasItem, r: Rect2, b: Dictionary, colors: Array[Color], fallback := "") -> void:
	var col := func(key: String) -> Color:
		var i := CustomTeams.SLOTS.find(str(b.get(key, "primary")))
		return colors[maxi(i, 0)]
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var map := func(pts: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(o + p * s)
		return out

	var shape_name := str(b.get("shape", "shield"))
	var inner := PackedVector2Array()
	if shape_name != "none":
		var outer := shape(shape_name)
		inner = outer
		var border := str(b.get("border", "thick"))
		var w: float = {"none": 0.0, "thin": 0.03, "thick": 0.065, "double": 0.035}.get(border, 0.0)
		if w > 0.0:
			ci.draw_colored_polygon(map.call(outer), col.call("edge"))
			inner = _offset(outer, -w)
		ci.draw_colored_polygon(map.call(inner), col.call("fill"))
		# The pattern, clipped to the inside.
		for part in pattern(str(b.get("pattern", "none"))):
			for clip in Geometry2D.intersect_polygons(inner, part):
				ci.draw_colored_polygon(map.call(clip), col.call("pattern_color"))
		if border == "double":
			var ring := _offset(inner, -0.03)
			if ring.size() > 2:
				var pts: PackedVector2Array = map.call(ring)
				pts.append(pts[0])
				ci.draw_polyline(pts, col.call("edge"), maxf(1.0, s * 0.016), true)

	# Icon and lettering.
	var layout := str(b.get("layout", "icon_text"))
	var icon := str(b.get("icon", "none"))
	var text := str(b.get("text", "")).strip_edges()
	if text == "":
		text = fallback
	if icon == "none":
		layout = "text"
	if text == "":
		layout = "icon" if icon != "none" else ""
	var outline: Color = col.call("outline")
	var line_w := maxf(1.0, s * 0.012)
	var top := 0.0 if shape_name in ["round", "diamond", "hexagon", "square", "none"] else -0.04
	var mascot := is_mascot(icon)
	var tints: Array[Color] = [outline]
	for k: String in MASCOT_KEYS:
		tints.append(col.call(k))
	var draw_icon := func(ir: Rect2) -> void:
		if mascot:
			_mascot(ci, icon, ir, tints)
		else:
			_icon(ci, icon, ir, col.call("icon_color"), outline, line_w)
	match layout:
		"icon":
			# A stock logo on its own fills the badge; inside a shape it sits a bit larger
			# than a plain icon, since it has its own outline and shape.
			var ir := Rect2(0.2, 0.2 + top, 0.6, 0.6)
			if mascot:
				ir = Rect2(0.02, 0.02, 0.96, 0.96) if shape_name == "none" else Rect2(0.15, 0.15 + top, 0.7, 0.7)
			draw_icon.call(Rect2(o + ir.position * s, ir.size * s))
		"text":
			_text(ci, text, Rect2(o + Vector2(0.17, 0.3 + top) * s, Vector2(0.66, 0.36) * s), b, col.call("text_color"), outline)
		"icon_text":
			var ir := Rect2(0.31, 0.13 + top, 0.38, 0.38)
			var tr := Rect2(0.2, 0.53 + top, 0.6, 0.22)
			if mascot and shape_name == "none":
				ir = Rect2(0.08, 0.0, 0.84, 0.66)
				tr = Rect2(0.12, 0.7, 0.76, 0.26)
			elif mascot:
				ir = Rect2(0.24, 0.1 + top, 0.52, 0.44)
			draw_icon.call(Rect2(o + ir.position * s, ir.size * s))
			_text(ci, text, Rect2(o + tr.position * s, tr.size * s), b, col.call("text_color"), outline)


## The shape's outline in a unit box (y down).
static func shape(name: String) -> PackedVector2Array:
	var p := PackedVector2Array()
	match name:
		"shield":
			# Straight sides, then curving in to the point.
			p.append_array([Vector2(0.12, 0.05), Vector2(0.88, 0.05)])
			p.append_array(_point_sides(0.12, 0.88, 0.48, 0.97))
		"crest":
			for i in 13:   # a dipped top
				var t := i / 12.0
				p.append(Vector2(0.06 + 0.88 * t, 0.04 + 0.09 * sin(t * PI)))
			p.append_array(_point_sides(0.06, 0.94, 0.5, 0.97))
		"round":
			for i in 72:
				var a := TAU * i / 72.0
				p.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.46)
		"diamond":
			p.append_array([Vector2(0.5, 0.02), Vector2(0.98, 0.5), Vector2(0.5, 0.98), Vector2(0.02, 0.5)])
		"hexagon":
			for i in 6:
				var a := TAU * i / 6.0
				p.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.48)
		"square":
			var rr := 0.12
			for c: Array in [[Vector2(0.92 - rr, 0.08 + rr), -PI * 0.5], [Vector2(0.92 - rr, 0.92 - rr), 0.0],
					[Vector2(0.08 + rr, 0.92 - rr), PI * 0.5], [Vector2(0.08 + rr, 0.08 + rr), PI]]:
				for i in 7:
					var a: float = c[1] + PI * 0.5 * i / 6.0
					p.append(c[0] + Vector2(cos(a), sin(a)) * rr)
	return p


## A shield's lower half: down the right side from `y0`, curving in to a point at the
## bottom, and back up the left.
static func _point_sides(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var half := (x1 - x0) * 0.5
	var mid := (x0 + x1) * 0.5
	for i in 13:
		var t := i / 12.0
		p.append(Vector2(mid + half * (1.0 - pow(t, 2.2)), y0 + (y1 - y0) * t))
	for i in range(11, -1, -1):
		var t := i / 12.0
		p.append(Vector2(mid - half * (1.0 - pow(t, 2.2)), y0 + (y1 - y0) * t))
	return p


## The pattern's pieces in a unit box (clipped to the shape by draw()).
static func pattern(name: String) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	match name:
		"band":
			out.append(_rect(0, 0.4, 1, 0.24))
		"sash":
			out.append(PackedVector2Array([Vector2(-0.2, 0.18), Vector2(0.02, -0.04), Vector2(1.2, 1.14), Vector2(0.98, 1.36)]))
		"split":
			out.append(_rect(0.5, 0, 0.5, 1))
		"chevron":
			out.append(PackedVector2Array([Vector2(0, 0.42), Vector2(0.5, 0.78), Vector2(1, 0.42),
					Vector2(1, 0.6), Vector2(0.5, 0.96), Vector2(0, 0.6)]))
		"chief":
			out.append(_rect(0, 0, 1, 0.3))
		"hoops":
			out.append(_rect(0, 0.3, 1, 0.07))
			out.append(_rect(0, 0.72, 1, 0.07))
		"quarters":
			out.append(_rect(0.5, 0, 0.5, 0.5))
			out.append(_rect(0, 0.5, 0.5, 0.5))
	return out


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func _offset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND)
	return res[0] if not res.is_empty() else poly


## An icon's polygons in a unit box.
static func icon_parts(name: String) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	match name:
		"star":
			out.append(_star(Vector2(0.5, 0.53), 0.5, 0.2))
		"three_stars":
			out.append(_star(Vector2(0.5, 0.4), 0.3, 0.12))
			out.append(_star(Vector2(0.17, 0.66), 0.2, 0.08))
			out.append(_star(Vector2(0.83, 0.66), 0.2, 0.08))
		"bolt":
			out.append(PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.18, 0.56), Vector2(0.46, 0.56),
					Vector2(0.34, 1.0), Vector2(0.84, 0.38), Vector2(0.55, 0.38), Vector2(0.72, 0.0)]))
		"crown":
			out.append(PackedVector2Array([Vector2(0.08, 0.78), Vector2(0.04, 0.24), Vector2(0.3, 0.5), Vector2(0.5, 0.12),
					Vector2(0.7, 0.5), Vector2(0.96, 0.24), Vector2(0.92, 0.78)]))
			out.append(_rect(0.08, 0.83, 0.84, 0.12))
		"sticks":
			for side in [-1.0, 1.0]:
				# A shaft from a top corner down across, and the blade turned out at the bottom.
				var a := Vector2(0.5 - 0.42 * side, 0.02)
				var b := Vector2(0.5 + 0.3 * side, 0.86)
				var n := (b - a).normalized().orthogonal() * 0.045
				out.append(PackedVector2Array([a + n, a - n, b - n, b + n]))
				var hull := Geometry2D.convex_hull(PackedVector2Array([b + n * 1.2, b - n * 1.2,
						b + Vector2(0.2 * side, 0.03), b + Vector2(0.2 * side, 0.12)]))
				hull.remove_at(hull.size() - 1)   # (convex_hull closes the loop)
				out.append(hull)
			out.append(_ellipse(Vector2(0.5, 0.88), Vector2(0.15, 0.07)))
		"puck":
			var side := _rect(0.1, 0.42, 0.8, 0.22)
			out.append(_ellipse(Vector2(0.5, 0.64), Vector2(0.4, 0.17)))
			out.append(side)
			out.append(_ellipse(Vector2(0.5, 0.42), Vector2(0.4, 0.17)))
		"mountains":
			out.append(PackedVector2Array([Vector2(0.0, 0.88), Vector2(0.36, 0.2), Vector2(0.56, 0.56), Vector2(0.7, 0.38),
					Vector2(1.0, 0.88)]))
		"wave":
			# Two rolling waves, one above the other.
			for row in 2:
				var y := 0.32 + 0.3 * row
				var w := PackedVector2Array()
				for i in 33:
					var t := i / 32.0
					w.append(Vector2(t, y - 0.1 * sin(t * TAU * 1.5)))
				for i in range(32, -1, -1):
					var t := i / 32.0
					w.append(Vector2(t, y + 0.13 - 0.1 * sin(t * TAU * 1.5 - 0.5)))
				out.append(w)
		"claws":
			for k in 3:
				var x := 0.18 + 0.3 * k
				out.append(PackedVector2Array([Vector2(x + 0.12, 0.0), Vector2(x + 0.22, 0.04), Vector2(x - 0.04, 1.0),
						Vector2(x - 0.1, 0.94)]))
	return out


static func _star(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		p.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return p


static func _ellipse(c: Vector2, rad: Vector2) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		p.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return p


static func _icon(ci: CanvasItem, name: String, r: Rect2, fill: Color, outline: Color, w: float) -> void:
	for part in icon_parts(name):
		var pts := PackedVector2Array()
		for p in part:
			pts.append(r.position + p * r.size)
		# The outline first, a little fat, so it frames the shape.
		var ring := pts.duplicate()
		ring.append(pts[0])
		ci.draw_polyline(ring, outline, w * 2.0, true)
		ci.draw_colored_polygon(pts, fill)


## Lettering fitted to `r` (as wide as it can be without getting taller than r).
static func _text(ci: CanvasItem, text: String, r: Rect2, b: Dictionary, fill: Color, outline: Color) -> void:
	var f := font(int(b.get("font", 0)), bool(b.get("italic", true)))
	var probe := 100
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, probe)
	var cap := f.get_ascent(probe) * 0.72   # about the capitals' height
	var k := minf(r.size.x / maxf(sz.x, 1.0), r.size.y / maxf(cap, 1.0))
	var fs := maxi(4, int(probe * k))
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(r.get_center().x - w * 0.5, r.get_center().y + f.get_ascent(fs) * 0.36)
	var ow := maxi(2, int(fs * 0.14))
	ci.draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, outline)
	ci.draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
