class_name MenuStyle
## The front-end look shared by every menu screen: the heavy slanted font, the
## red / navy / ice palette, the chrome title and the controller button glyphs.
##
## Menus are laid out on a 1600 x 900 design canvas (DESIGN_SIZE) that fit() scales to
## the window, so sizes in menu code are design pixels.

const DESIGN_SIZE := Vector2(1600, 900)

const RED := Color(0.86, 0.09, 0.11)
const RED_DARK := Color(0.42, 0.02, 0.05)
const NAVY := Color(0.1, 0.13, 0.24)
const INK := Color(0.02, 0.03, 0.06)
const ICE := Color(0.88, 0.93, 1.0)
const DIM := Color(0.62, 0.66, 0.74)

## Pad prompts are PlayStation buttons. Code may still name pad buttons by their Xbox
## position (A = bottom face, LB = left shoulder...); pad_label() turns either into the
## PlayStation name. draw_glyph draws every prompt itself (no button font): the face
## buttons as a ringed symbol on a dark button, the shoulder buttons as badges, Start
## and Select as their shape over the word on a dark plate.
const PS_NAMES := {"A": "CROSS", "B": "CIRCLE", "X": "SQUARE", "Y": "TRIANGLE",
		"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2", "BACK": "SELECT",
		"LS": "L3", "RS": "R3"}
const SHOULDERS := ["L1", "R1", "L2", "R2", "L3", "R3"]
## Start (a long triangle pointing right) and Select (a bar), each over its name.
const PLATES := ["START", "SELECT"]
## The face buttons' symbol colors.
const PAD_COLORS := {"CROSS": Color(0.49, 0.7, 0.93), "CIRCLE": Color(1.0, 0.42, 0.42),
		"SQUARE": Color(0.92, 0.6, 0.8), "TRIANGLE": Color(0.27, 0.88, 0.66)}
const PLATE_LIGHT := Color(0.93, 0.95, 0.98)

const CHROME_SHADER := "
shader_type canvas_item;
// Brushed-chrome fill for title text: bright top, a dark horizon band just below the
// middle, then light again. `top` / `height`: where the glyphs sit in the label.
uniform float top = 0.0;
uniform float height = 100.0;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float t = clamp((ly - top) / height, 0.0, 1.0);
	vec3 c;
	if (t < 0.48) c = mix(vec3(1.0), vec3(0.74, 0.77, 0.82), t / 0.48);
	else if (t < 0.56) c = mix(vec3(0.36, 0.39, 0.46), vec3(0.55, 0.58, 0.64), (t - 0.48) / 0.08);
	else c = mix(vec3(0.78, 0.81, 0.86), vec3(0.97, 0.98, 1.0), (t - 0.56) / 0.44);
	COLOR = vec4(c, texture(TEXTURE, UV).a * COLOR.a);
}
"

## The game title's typeface (chrome_text), upright, with TITLE_SPACING extra pixels
## between letters per 100 px of size; TITLE_WORD_FONTS gives single words their own face
## (files in assets/fonts). `-- titlefont=<file in assets/fonts>` (every word) and
## `-- titlespacing=<n>` override them for a run, to compare.
const TITLE_FONT := "res://assets/fonts/sprayme.ttf"
const TITLE_WORD_FONTS := {"HOCKEY": "RussoOne-Regular.ttf"}
const TITLE_SPACING := 12.0
const FONT_DIR := "res://assets/fonts/"

static var _fonts := {}
static var _title_fonts := {}
static var _chrome: Shader


## The heavy sports face: italic unless `slant` is 0.
static func font(slant := 0.2) -> Font:
	var key := snappedf(slant, 0.01)
	if not _fonts.has(key):
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial Black", "Impact"])
		base.font_weight = 900
		base.font_italic = slant > 0.0
		_fonts[key] = base
	return _fonts[key]


## The title face at `size` (TITLE_FONT, or the `titlefont=` override), letter-spaced,
## leaned by `slant` if it's above 0 (a synthetic oblique). Falls back to font().
static func title_font(size: int, slant := 0.0, font_file := "") -> Font:
	var path := TITLE_FONT
	var spacing := TITLE_SPACING
	for a in OS.get_cmdline_user_args():
		if a.begins_with("titlefont="):
			path = FONT_DIR + a.substr(10)
		elif a.begins_with("titlespacing="):
			spacing = float(a.substr(13))
	if font_file != "":
		path = FONT_DIR + font_file
	var key := "%s|%d|%.2f|%.1f" % [path, size, slant, spacing]
	if not _title_fonts.has(key):
		var base := load(path) as FontFile if ResourceLoader.exists(path) else null
		if base == null:
			_title_fonts[key] = font(slant)
		else:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-slant, 1), Vector2.ZERO)
			v.spacing_glyph = roundi(spacing * size / 100.0)
			_title_fonts[key] = v
	return _title_fonts[key]


## Scales `canvas` (a plain Control) so its DESIGN_SIZE height fills the window; its
## width grows with wider windows. Call on ready and when the window resizes.
static func fit(canvas: Control) -> void:
	var vp := canvas.get_viewport_rect().size
	var s := vp.y / DESIGN_SIZE.y
	canvas.scale = Vector2(s, s)
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(vp.x / s, DESIGN_SIZE.y)


## Room the chrome title leaves left of the text (a fraction of the font size).
const CHROME_PAD := 0.2
const TITLE_BAKED := "res://assets/ui/title/"


## The font file (in assets/fonts) TITLE_WORD_FONTS gives `text`, or "" for TITLE_FONT
## (always "" while `titlefont=` is comparing faces).
static func word_font(text: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("titlefont="):
			return ""
	return TITLE_WORD_FONTS.get(text, "")


## The Control size chrome_text gives `text` at `size`.
static func chrome_size(text: String, size: int) -> Vector2:
	var ts := title_font(size, 0.0, word_font(text)).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	return Vector2(ts.x + size * CHROME_PAD * 2.0, ts.y)


## How far a baked title image reaches past chrome_text's Control on every side (rims, shadow).
static func bake_margin(size: int) -> float:
	return ceilf(size * 0.35)


## The brushed-chrome fill (CHROME_SHADER's gradient), t = 0 at the top of the letters.
static func chrome_color(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.48:
		return Color(1, 1, 1).lerp(Color(0.74, 0.77, 0.82), t / 0.48)
	if t < 0.56:
		return Color(0.36, 0.39, 0.46).lerp(Color(0.55, 0.58, 0.64), (t - 0.48) / 0.08)
	return Color(0.78, 0.81, 0.86).lerp(Color(0.97, 0.98, 1.0), (t - 0.56) / 0.44)


## A word in the game's title style: chrome letters inside a red rim and a dark navy
## outer rim, with a drop shadow. Returns a Control sized to the text.
## When tools/BuildTitle.tscn has baked the word (TITLE_BAKED/<word>_<size>.png) the image
## is used: its rims go round the letters only, not the font's splatter specks. Otherwise
## it's built live from layered Labels (rims round everything).
## `font_file` (a file in assets/fonts) sets this word's face on its own, built live;
## otherwise it's TITLE_WORD_FONTS' face for the word, or TITLE_FONT.
static func chrome_text(text: String, size: int, slant := 0.0, font_file := "") -> Control:
	var baked := TITLE_BAKED + "%s_%d.png" % [text.to_lower(), size]
	var titlefont_override := false   # comparing faces from the command line: build live
	for a in OS.get_cmdline_user_args():
		titlefont_override = titlefont_override or a.begins_with("titlefont=") or a.begins_with("titlespacing=")
	var live := font_file != ""
	if font_file == "":
		font_file = word_font(text)
	if slant == 0.0 and not titlefont_override and not live and ResourceLoader.exists(baked):
		var box := Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.size = chrome_size(text, size)
		box.custom_minimum_size = box.size
		var tr := TextureRect.new()
		tr.texture = load(baked)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var m := bake_margin(size)
		tr.position = Vector2(-m, -m)
		tr.size = tr.texture.get_size() / 2.0
		box.add_child(tr)
		return box
	var f := title_font(size, slant, font_file)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layers := [
		# [offset, outline size, outline color, fill]
		[Vector2(8, 10), int(size * 0.3), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)],
		[Vector2.ZERO, int(size * 0.3), Color(0.04, 0.06, 0.14), Color(0.04, 0.06, 0.14)],
		[Vector2.ZERO, int(size * 0.18), RED, RED],
		[Vector2.ZERO, int(size * 0.07), Color(0.98, 0.98, 1.0), Color(0.98, 0.98, 1.0)],
		[Vector2.ZERO, 0, Color.TRANSPARENT, Color.WHITE],
	]
	var text_size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pad := size * CHROME_PAD
	for i in layers.size():
		var l := Label.new()
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", layers[i][3])
		l.add_theme_color_override("font_outline_color", layers[i][2])
		l.add_theme_constant_override("outline_size", layers[i][1])
		l.position = Vector2(pad, 0) + layers[i][0]
		if i == layers.size() - 1:
			if _chrome == null:
				_chrome = Shader.new()
				_chrome.code = CHROME_SHADER
			var m := ShaderMaterial.new()
			m.shader = _chrome
			var asc := f.get_ascent(size)
			m.set_shader_parameter("top", asc * 0.22)
			m.set_shader_parameter("height", asc * 0.95)
			l.material = m
		holder.add_child(l)
	holder.custom_minimum_size = Vector2(text_size.x + pad * 2.0, text_size.y)
	holder.size = holder.custom_minimum_size
	return holder


## A button prompt: a colored face button for pads, a key cap for keyboards.
## Returns the width it took (so prompts can be laid out in a row).
static func draw_glyph(ci: CanvasItem, pos: Vector2, label: String, pad: bool, h := 34.0) -> float:
	var f := font(0.0)
	if pad:
		label = pad_label(label)
	if pad and label in PAD_COLORS:
		var r := h * 0.5
		var c: Vector2 = pos + Vector2(r, r)
		ci.draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		ci.draw_circle(c, r, Color(0.1, 0.11, 0.14))
		ci.draw_circle(c, r - 2.5, Color(0.2, 0.22, 0.26))
		_draw_symbol(ci, c, label, h, PAD_COLORS[label])
		return h
	if pad and label in SHOULDERS:
		# A shoulder button: a light badge with the name in dark, like the font's badges
		# (drawn here: the font's badges sit unevenly in their cells).
		var w := glyph_width(label, true, h)
		var badge := Rect2(pos + Vector2(0, h * 0.2), Vector2(w, h * 0.6))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.95, 0.98)
		sb.border_color = Color(0.1, 0.11, 0.14)
		sb.set_border_width_all(maxi(1, int(h * 0.05)))
		sb.set_corner_radius_all(int(h * 0.1))
		ci.draw_style_box(sb, badge)
		var bf := font(0.0)
		var bs := int(h * 0.42)
		var bw := bf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
		ci.draw_string(bf, badge.get_center() + Vector2(-bw * 0.5, bs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, INK)
		return w
	if pad and label in PLATES:
		# Start / Select: the button's shape over its name, light on a dark rounded plate.
		var w := glyph_width(label, true, h)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.11, 0.14)
		sb.set_corner_radius_all(int(h * 0.14))
		ci.draw_style_box(sb, Rect2(pos, Vector2(w, h)))
		var mid := pos + Vector2(w * 0.5, h * 0.36)
		if label == "START":
			var tri := PackedVector2Array([mid + Vector2(-h * 0.31, -h * 0.16),
					mid + Vector2(h * 0.31, 0.0), mid + Vector2(-h * 0.31, h * 0.16)])
			ci.draw_colored_polygon(tri, PLATE_LIGHT)
			_draw_loop(ci, tri, PLATE_LIGHT, 1.0)   # smooths the fill's edge
		else:
			ci.draw_rect(Rect2(mid - Vector2(h * 0.31, h * 0.15), Vector2(h * 0.62, h * 0.3)), PLATE_LIGHT)
		var pf := font(0.0)
		var ps := _plate_font_size(h)
		var pw := pf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
		ci.draw_string(pf, pos + Vector2((w - pw) * 0.5, h * 0.86), label, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, PLATE_LIGHT)
		return w
	var fs2 := int(h * 0.46)
	var w := maxf(h, f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + h * 0.5)
	var box := Rect2(pos, Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.95, 0.98)
	sb.border_color = Color(0.55, 0.58, 0.65)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(6)
	ci.draw_style_box(sb, box)
	var tw2 := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	ci.draw_string(f, pos + Vector2((w - tw2) * 0.5, h * 0.5 + fs2 * 0.3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, INK)
	return w


## The prompt bar along the bottom of every menu screen: brushed steel with a red
## hairline, a hint on the left, button prompts on the right.
## `prompts`: [[button label, action], ...] left to right.
static func draw_footer(ci: CanvasItem, w: float, hint: String, prompts: Array, pad: bool) -> void:
	var y := 826.0
	var h := 50.0
	ci.draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(w, y), Vector2(w, y + h), Vector2(0, y + h)]),
			PackedColorArray([Color(0.86, 0.89, 0.94, 0.92), Color(0.7, 0.74, 0.8, 0.85),
				Color(0.5, 0.54, 0.62, 0.85), Color(0.62, 0.66, 0.74, 0.92)]))
	ci.draw_rect(Rect2(0, y - 3, w, 3), RED)
	ci.draw_rect(Rect2(0, y + h, w, 30), Color(0.04, 0.06, 0.12, 0.85))
	var f := font(0.12)
	ci.draw_string(f, Vector2(60, y + 33), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	var x := w - 60.0
	for i in range(prompts.size() - 1, -1, -1):
		var action: String = prompts[i][1]
		x -= f.get_string_size(action, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		ci.draw_string(f, Vector2(x, y + 33), action, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
		x -= glyph_width(prompts[i][0], pad) + 10.0
		draw_glyph(ci, Vector2(x, y + 8), prompts[i][0], pad, 34.0)
		x -= 34.0


## The PlayStation name for a pad button ("A" -> "CROSS", "LB" -> "L1"); PlayStation
## names and anything else pass through.
static func pad_label(label: String) -> String:
	return PS_NAMES.get(label, label)


## A face button's mark for a prompt `h` tall, centered on `c`: a ring in the button's
## color around its symbol (a cross, a circle, a square or a triangle), all drawn as lines.
static func _draw_symbol(ci: CanvasItem, c: Vector2, label: String, h: float, col: Color) -> void:
	var w := maxf(1.4, h * 0.05)
	ci.draw_arc(c, h * 0.46, 0.0, TAU, 48, col, maxf(1.2, h * 0.04), true)
	match label:
		"CROSS":
			var d := h * 0.2
			ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), col, w, true)
			ci.draw_line(c + Vector2(-d, d), c + Vector2(d, -d), col, w, true)
		"CIRCLE":
			ci.draw_arc(c, h * 0.26, 0.0, TAU, 40, col, w * 1.3, true)
		"SQUARE":
			var d := h * 0.23
			_draw_loop(ci, PackedVector2Array([c + Vector2(-d, -d), c + Vector2(d, -d),
					c + Vector2(d, d), c + Vector2(-d, d)]), col, w)
		"TRIANGLE":
			# The triangle's middle sits a little low so its tip and base clear the ring evenly.
			var o := c + Vector2(0.0, h * 0.045)
			var r := h * 0.29
			_draw_loop(ci, PackedVector2Array([o + Vector2(0.0, -r), o + Vector2(r * 0.866, r * 0.5),
					o + Vector2(-r * 0.866, r * 0.5)]), col, w)


## A closed outline through `pts`. It starts and ends mid-edge, so every corner is a
## proper joint (a polyline's own two ends would leave a notch at a corner).
static func _draw_loop(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var line := PackedVector2Array([(pts[pts.size() - 1] + pts[0]) * 0.5])
	line.append_array(pts)
	line.append(line[0])
	ci.draw_polyline(line, col, w, true)


static func _plate_font_size(h: float) -> int:
	return maxi(6, int(h * 0.22))


static func glyph_width(label: String, pad: bool, h := 34.0) -> float:
	if pad:
		label = pad_label(label)
	if pad and label in PAD_COLORS:
		return h
	if pad and label in SHOULDERS:
		return h * 1.3
	if pad and label in PLATES:
		return maxf(h * 1.25, font(0.0).get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _plate_font_size(h)).x + h * 0.3)
	return maxf(h, font(0.0).get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.46)).x + h * 0.5)


## A screen's heading: a small red slanted tag (the mode) over a big italic title.
static func draw_tag(ci: CanvasItem, pos: Vector2, mode: String, title: String) -> void:
	var f := font(0.2)
	var tw := font(0.12).get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var h := 30.0
	var sk := h * 0.4
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(sk, 0), pos + Vector2(tw + 40 + sk, 0),
			pos + Vector2(tw + 40, h), pos + Vector2(0, h)]), RED)
	ci.draw_string(font(0.12), pos + Vector2(22, 22), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	ci.draw_string(f, pos + Vector2(4, h + 64) + Vector2(3, 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(0, 0, 0, 0.5))
	ci.draw_string(f, pos + Vector2(4, h + 64), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color.WHITE)


## A team's color for panels and plates: the jersey, or for white / pale jerseys the trim
## (then the number outline), so the plate is never white.
static func team_color(team_id: int) -> Color:
	var c: Dictionary = Teams.team(team_id).colors
	for k: String in ["jersey", "trim", "number_outline", "pants"]:
		var col: Color = c[k]
		if col.get_luminance() < 0.72:
			return col
	return NAVY


## The team's crest (cached), or null.
static func team_logo(team_id: int) -> Texture2D:
	return Teams.logo(team_id)


## Where `tex` goes in `box` at its own proportions: as large as fits, centered. Crests
## come in every shape (Florida Man's is twice as wide as it is tall, the Lobsters' nearly
## twice as tall as wide): never stretch one to a box, fit it in.
static func logo_rect(tex: Texture2D, box: Rect2) -> Rect2:
	var ts := tex.get_size()
	var sz := ts * minf(box.size.x / maxf(ts.x, 1.0), box.size.y / maxf(ts.y, 1.0))
	return Rect2(box.position + (box.size - sz) * 0.5, sz)


## How wide a crest's slot is where the slot is `h` tall: `h` for square and tall crests,
## wider for wide ones (as wide as the crest at full height, up to `most` times `h`), so a
## wordmark isn't shrunk to a sliver in a square. Whatever sits beside the crest moves over
## by the difference.
const LOGO_WIDE := 1.6
static func logo_slot(tex: Texture2D, h: float, most := LOGO_WIDE) -> float:
	if tex == null:
		return h
	return h * clampf(tex.get_width() / maxf(float(tex.get_height()), 1.0), 1.0, most)


## Draws a crest in `box`, fitted (see logo_rect).
static func draw_logo(ci: CanvasItem, tex: Texture2D, box: Rect2, modulate := Color.WHITE) -> void:
	if tex != null:
		ci.draw_texture_rect(tex, logo_rect(tex, box), false, modulate)


## A slanted bar (the menu's parallelogram): `skew` pixels of lean on each end.
static func draw_slant(ci: CanvasItem, r: Rect2, color: Color, skew := 14.0) -> void:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return   # mid-slide: nothing to draw yet
	ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(skew, 0), r.position + Vector2(r.size.x + skew, 0),
			r.position + Vector2(r.size.x, r.size.y), r.position + Vector2(0, r.size.y)]), color)


## The player's pucks on a slanted ink plate whose right end is at `right` (the main menu
## and the store, top right). `k`: its slide-in, 0 to 1.
static func draw_wallet(ci: CanvasItem, right: float, y: float, pucks: int, k := 1.0) -> void:
	var text := Pucks.fmt(pucks)
	var tw := text_width(text, 38)
	var w := tw + 196.0
	var r := Rect2(right - w + (1.0 - k) * 80.0, y, w, 58)
	draw_slant(ci, Rect2(r.position + Vector2(6, 7), r.size), Color(0, 0, 0, 0.35 * k), 16)
	draw_slant(ci, r.grow(3), Color(RED, k), 16)
	draw_slant(ci, r, Color(INK, 0.95 * k), 16)
	draw_puck(ci, r.position + Vector2(50, 30), 19.0, k)
	draw_bold(ci, r.position + Vector2(84, 43), text, 38, Color(1, 1, 1, k), 0, INK, 0.2, false)
	ci.draw_string(font(0.12), r.position + Vector2(96 + tw, 41), "PUCKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(DIM, k))


## The currency's mark: a puck seen from a little above, `r` across at half-width, centered
## on `c`. A pale rim keeps it readable on the dark panels.
static func draw_puck(ci: CanvasItem, c: Vector2, r: float, a := 1.0) -> void:
	var ry := r * 0.4
	var h := r * 0.46
	var top := c - Vector2(0, h * 0.5)
	var o := maxf(1.5, r * 0.09)
	_draw_puck_body(ci, top + Vector2(r * 0.1, r * 0.14), r + o, ry + o, h, Color(0, 0, 0, 0.4 * a))
	_draw_puck_body(ci, top, r + o, ry + o, h, Color(ICE, a))
	_draw_puck_body(ci, top, r, ry, h, Color(0.03, 0.03, 0.05, a))
	ci.draw_colored_polygon(_ellipse(top, r, ry), Color(0.25, 0.27, 0.32, a))
	ci.draw_colored_polygon(_ellipse(top, r * 0.88, ry * 0.86), Color(0.1, 0.11, 0.14, a))


## A puck's outline: the top ellipse, the wall, the bottom ellipse.
static func _draw_puck_body(ci: CanvasItem, top: Vector2, r: float, ry: float, h: float, col: Color) -> void:
	ci.draw_colored_polygon(_ellipse(top, r, ry), col)
	ci.draw_rect(Rect2(top.x - r, top.y, r * 2.0, h), col)
	ci.draw_colored_polygon(_ellipse(top + Vector2(0, h), r, ry), col)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var ang := TAU * i / 32.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts


## Text with the menu's heavy outline (and an optional drop shadow).
static func draw_bold(ci: CanvasItem, pos: Vector2, text: String, size: int, color := Color.WHITE,
		outline := 0, outline_color := INK, slant := 0.2, shadow := true) -> void:
	var f := font(slant)
	if shadow:
		ci.draw_string(f, pos + Vector2(3, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.45))
	if outline > 0:
		ci.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_width(text: String, size: int, slant := 0.2) -> float:
	return font(slant).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## "#19 RIVERA" (or "#19" for players without a sheet name).
static func player_name(s: Skater) -> String:
	if s == null:
		return ""
	return ("#%d %s" % [s.number, s.last_name.to_upper()]) if s.last_name != "" else "#%d" % s.number
