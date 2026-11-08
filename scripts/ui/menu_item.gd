class_name MenuItem
extends Control
## One slanted menu bar: dark navy fading to the right, red when selected (it also slides
## out a little). Slides in from the left after `delay` seconds when shown.
## Mouse: hovering selects it, clicking activates it.

signal hovered
signal clicked

const SLANT := 0.42   ## horizontal lean per unit of height

var text := ""
var soon := false            ## not built yet: dimmed, tagged COMING SOON
var selected := false
var delay := 0.0
var glyph := ""              ## accept-button label shown on the selected bar
var glyph_pad := true
var value := ""               ## a setting's current value, right-aligned (arrows when selected)
var value_w := 300.0          ## room the value gets at the right end of the bar
var _sel := 0.0
var _shown := 0.0
var _shake := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit())
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit())


## Replays the slide-in (when the list is rebuilt).
func intro(after: float) -> void:
	delay = after
	_shown = 0.0


func nudge() -> void:
	_shake = 1.0


func _process(delta: float) -> void:
	_sel = move_toward(_sel, 1.0 if selected else 0.0, delta * 8.0)
	if delay > 0.0:
		delay -= delta
	else:
		_shown = move_toward(_shown, 1.0, delta * 3.2)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var h := size.y
	var w := size.x
	var e := 1.0 - pow(1.0 - _shown, 3.0)
	var s := _sel * _sel * (3.0 - 2.0 * _sel)
	var x0 := lerpf(-w * 0.7, 0.0, e) + s * 26.0 + sin(_shake * 30.0) * _shake * 10.0
	var a := e
	var sk := h * SLANT
	var pts := PackedVector2Array([Vector2(x0 + sk, 0), Vector2(x0 + w + sk, 0),
			Vector2(x0 + w, h), Vector2(x0, h)])
	var top := Color(0.16, 0.2, 0.33).lerp(Color(0.98, 0.2, 0.2), s)
	var bot := Color(0.02, 0.03, 0.07).lerp(Color(0.56, 0.02, 0.06), s)
	var fade := 0.18 + 0.25 * s
	var cols := PackedColorArray([
		Color(top, 0.94 * a), Color(top, fade * a), Color(bot, fade * a), Color(bot, 0.94 * a)])
	draw_polygon(pts, cols)
	# Glossy upper half and a bright top edge.
	var mid := PackedVector2Array([pts[0], pts[1], Vector2(x0 + w + sk * 0.5, h * 0.48), Vector2(x0 + sk * 0.5, h * 0.48)])
	draw_polygon(mid, PackedColorArray([Color(1, 1, 1, 0.13 * a), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.04 * a)]))
	draw_polyline_colors(PackedVector2Array([pts[0], pts[1]]),
			PackedColorArray([Color(1, 1, 1, (0.45 + 0.4 * s) * a), Color(1, 1, 1, 0.0)]), 2.0)
	# Red accent stripe on the left edge of the selected bar.
	if s > 0.01:
		draw_colored_polygon(PackedVector2Array([pts[0] - Vector2(14, 0) * s, pts[0], pts[3], pts[3] - Vector2(14, 0) * s]),
				Color(1, 0.85, 0.85, 0.9 * s * a))

	var f := MenuStyle.font(0.2)
	var fs := int(h * 0.56)
	var tx := x0 + sk + 34.0
	if glyph != "" and s > 0.01:
		var gh := h * 0.62
		MenuStyle.draw_glyph(self, Vector2(tx - 8.0, (h - gh) * 0.5), glyph, glyph_pad, gh)
		tx += (gh + 14.0) * s
	var ty := h * 0.5 + fs * 0.36
	var col := Color.WHITE if not soon else Color(0.7, 0.73, 0.8)
	draw_string(f, Vector2(tx + 3, ty + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55 * a))
	draw_string(f, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
	if value != "":
		var vf := MenuStyle.font(0.12)
		var vs := int(h * 0.48)
		var right := x0 + w - 30.0
		var vw := vf.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x
		var center := right - value_w * 0.5
		var vy := h * 0.5 + vs * 0.36
		draw_string(vf, Vector2(center - vw * 0.5 + 2, vy + 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, Color(0, 0, 0, 0.5 * a))
		draw_string(vf, Vector2(center - vw * 0.5, vy), value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs,
				Color(Color(1, 0.92, 0.6).lerp(Color.WHITE, s), a))
		var ts2 := h * 0.18
		for dir in [-1, 1]:
			var ax: float = center + dir * (value_w * 0.5 - 6.0)
			var ay := h * 0.5
			var tri := PackedVector2Array([Vector2(ax - ts2 * dir * 0.8, ay - ts2), Vector2(ax + ts2 * dir * 0.8, ay), Vector2(ax - ts2 * dir * 0.8, ay + ts2)])
			draw_colored_polygon(tri, Color(1, 1, 1, (0.25 + 0.7 * s) * a))
	if soon:
		var tf := MenuStyle.font(0.12)
		var ts := int(h * 0.26)
		var tag := "COMING SOON"
		var tw := tf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		var tp := Vector2(tx + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0, h * 0.5 - ts * 0.75)
		draw_rect(Rect2(tp - Vector2(8, 3), Vector2(tw + 16, ts * 1.45)), Color(1, 1, 1, 0.12 * a))
		draw_string(tf, tp + Vector2(0, ts * 0.98), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0.85, 0.88, 0.95, 0.85 * a))
