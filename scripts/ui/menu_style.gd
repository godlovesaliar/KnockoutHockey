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

## Pad face buttons, Xbox layout (what HumanBrain.button_label names them).
const PAD_COLORS := {"A": Color(0.33, 0.72, 0.25), "B": Color(0.86, 0.2, 0.18),
		"X": Color(0.2, 0.45, 0.9), "Y": Color(0.95, 0.72, 0.1)}

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

static var _fonts := {}
static var _chrome: Shader
static var _logos := {}


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


## Scales `canvas` (a plain Control) so its DESIGN_SIZE height fills the window; its
## width grows with wider windows. Call on ready and when the window resizes.
static func fit(canvas: Control) -> void:
	var vp := canvas.get_viewport_rect().size
	var s := vp.y / DESIGN_SIZE.y
	canvas.scale = Vector2(s, s)
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(vp.x / s, DESIGN_SIZE.y)


## A word in the game's title style: chrome letters inside a red rim and a dark navy
## outer rim, with a drop shadow. Returns a Control sized to the text.
static func chrome_text(text: String, size: int, slant := 0.22) -> Control:
	var f := font(slant)
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
	var pad := size * 0.2
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
	if pad and label in PAD_COLORS:
		var r := h * 0.5
		var c: Vector2 = pos + Vector2(r, r)
		ci.draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		ci.draw_circle(c, r, Color(0.1, 0.11, 0.14))
		ci.draw_circle(c, r - 2.5, Color(0.2, 0.22, 0.26))
		var fs := int(h * 0.58)
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PAD_COLORS[label])
		return h
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


static func glyph_width(label: String, pad: bool, h := 34.0) -> float:
	if pad and label in PAD_COLORS:
		return h
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
	if not _logos.has(team_id):
		var path: String = Teams.team(team_id).get("logo", "")
		_logos[team_id] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _logos[team_id]


## A slanted bar (the menu's parallelogram): `skew` pixels of lean on each end.
static func draw_slant(ci: CanvasItem, r: Rect2, color: Color, skew := 14.0) -> void:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return   # mid-slide: nothing to draw yet
	ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(skew, 0), r.position + Vector2(r.size.x + skew, 0),
			r.position + Vector2(r.size.x, r.size.y), r.position + Vector2(0, r.size.y)]), color)


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
