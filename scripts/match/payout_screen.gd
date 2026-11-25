class_name PayoutScreen
extends CanvasLayer
## The pucks a game paid, after the final stats screen (and after Knockout Mode's final
## card), in the same front-end style: the game dimmed behind, the mode tag and heading, a
## panel with one line per thing that paid (sliding in one after another), and beside it
## the total and the new balance counting up.
##
## The pucks are already in the profile when this opens (Pucks.bank): the screen only
## shows the receipt. Accept first finishes the count, then continues. With no humans in
## the game it moves on by itself.

signal continued

const INPUT_DELAY := 0.6
const AUTO_CONTINUE := 3.0
const ROW_FIRST := 0.4        ## s before the first line slides in...
const ROW_STEP := 0.16        ## ...and between lines
const COUNT_TIME := 0.9       ## s the total takes to count up, once the lines are in
const PANEL_Y := 172.0
const ROW_H := 46.0
const GOLD := Color(1.0, 0.82, 0.25)

var receipt := {}
var hint := ""
var cut := true               ## the league stinger covers the way out
var _humans := true
var _age := 0.0
var _done := false
var _ticked := 0
var _landed := false
var _canvas: Control
var _input: MenuInput


func open(r: Dictionary, back_hint: String, humans := true) -> void:
	receipt = r
	hint = back_hint
	_humans = humans
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.85))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(1800, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_paint.bind(art))
	_canvas.add_child(art)
	_input = MenuInput.new()
	add_child(_input)
	_input.accepted.connect(_on_accept)
	_input.started.connect(_on_accept)


func _lines() -> Array:
	return receipt.get("lines", [])


## When the total starts counting, and when it's done.
func _count_from() -> float:
	return ROW_FIRST + _lines().size() * ROW_STEP + 0.15


func _count_end() -> float:
	return _count_from() + COUNT_TIME


func _process(delta: float) -> void:
	_age += delta
	for c in _canvas.get_children():
		c.queue_redraw()
	# A tick as each line lands, and one more when the total does.
	while _ticked < _lines().size() and _age >= ROW_FIRST + _ticked * ROW_STEP:
		Sfx.play("click", Vector3.INF, -12.0, 1.2 + 0.05 * _ticked)
		_ticked += 1
	if not _landed and _age >= _count_end():
		_landed = true
		Sfx.play("pad", Vector3.INF, -6.0)
		if int(receipt.get("unlock_team", -1)) >= 0:
			Sfx.play("glove", Vector3.INF, -2.0)
	if not _humans and _age > _count_end() + AUTO_CONTINUE:
		_continue()


## Slide-in progress (0 → 1) for something that starts `delay` s after the screen opens.
func _in(delay: float) -> float:
	return ease(clampf((_age - delay) / 0.3, 0.0, 1.0), -2.0)


func _paint(ci: Control) -> void:
	var w := _canvas.size.x
	MenuStyle.draw_tag(ci, Vector2(60, 40), str(receipt.get("mode", "EXHIBITION")), "PAYOUT")
	var left_w := minf(860.0, (w - 180.0) * 0.6)
	_draw_lines(ci, Rect2(60 - (1.0 - _in(0.1)) * 80.0, PANEL_Y, left_w, 626))
	var rx := 60.0 + left_w + 60.0
	_draw_total(ci, Rect2(rx + (1.0 - _in(0.2)) * 80.0, PANEL_Y, w - rx - 60.0, 400))
	if int(receipt.get("unlock_team", -1)) >= 0:
		_draw_unlock(ci, Rect2(rx, PANEL_Y + 446, w - rx - 60.0, 150), int(receipt.unlock_team))
	MenuStyle.draw_footer(ci, w, hint if _humans else "AI vs AI — continuing.",
			[[_input.accept_label(), "CONTINUE"]] if _humans else [], _input.using_pad)


func _panel(ci: Control, r: Rect2, heading: String) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.3))
	ci.draw_rect(r, Color(0.03, 0.05, 0.1, 0.86))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), MenuStyle.RED)
	MenuStyle.draw_bold(ci, r.position + Vector2(24, 48), heading, 30, Color.WHITE, 0, MenuStyle.INK, 0.2, true)


## One line per thing that paid: what, how many at how much, and the pucks.
func _draw_lines(ci: Control, r: Rect2) -> void:
	_panel(ci, r, "PUCKS EARNED")
	var f := MenuStyle.font(0.12)
	var lines := _lines()
	for i in lines.size():
		var l: Dictionary = lines[i]
		var k := _in(ROW_FIRST + i * ROW_STEP)
		if k <= 0.0:
			continue
		var y := r.position.y + 78.0 + i * ROW_H
		var x := r.position.x + (1.0 - k) * 40.0
		if i % 2 == 0:
			ci.draw_rect(Rect2(r.position.x + 10, y, r.size.x - 20, ROW_H), Color(1, 1, 1, 0.035 * k))
		ci.draw_string(f, Vector2(x + 26, y + 31), str(l.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(MenuStyle.ICE, k))
		var detail := str(l.detail)
		if detail != "":
			var dw := MenuStyle.text_width(detail, 18, 0.12)
			ci.draw_string(f, Vector2(r.end.x - 150 - dw, y + 30), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(MenuStyle.DIM, k))
		var amount := int(l.amount)
		var text := ("+" if amount >= 0 else "−") + Pucks.fmt(absi(amount))
		var tw := MenuStyle.text_width(text, 28)
		ci.draw_string(MenuStyle.font(0.2), Vector2(r.end.x - 26 - tw, y + 33), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28,
				Color(Color.WHITE if amount >= 0 else Color(1.0, 0.5, 0.5), k))


## The total, counting up once the lines are in, and the balance it brings.
func _draw_total(ci: Control, r: Rect2) -> void:
	_panel(ci, r, "TOTAL")
	var k := ease(clampf((_age - _count_from()) / COUNT_TIME, 0.0, 1.0), -2.4)
	var total := int(receipt.get("total", 0))
	var before := int(receipt.get("before", 0))
	var after := int(receipt.get("after", before + total))
	var text := "+" + Pucks.fmt(roundi(total * k))
	var fs := 110
	while fs > 60 and MenuStyle.text_width("+" + Pucks.fmt(total), fs) > r.size.x - 190.0:
		fs -= 6
	var pr := fs * 0.42
	var y := r.position.y + 190.0
	MenuStyle.draw_puck(ci, Vector2(r.position.x + 40 + pr, y - fs * 0.33), pr)
	MenuStyle.draw_bold(ci, Vector2(r.position.x + 64 + pr * 2.0, y), text, fs, GOLD if k >= 1.0 else Color.WHITE, 8, MenuStyle.INK, 0.2, true)
	# The balance, on a darker band along the bottom.
	var band := Rect2(r.position.x, r.end.y - 120, r.size.x, 120)
	ci.draw_rect(band, Color(0, 0, 0, 0.3))
	ci.draw_rect(Rect2(band.position, Vector2(band.size.x, 2)), Color(1, 1, 1, 0.08))
	ci.draw_string(MenuStyle.font(0.12), band.position + Vector2(26, 36), "YOUR PUCKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	MenuStyle.draw_puck(ci, band.position + Vector2(48, 78), 20.0)
	MenuStyle.draw_bold(ci, band.position + Vector2(84, 96), Pucks.fmt(roundi(lerpf(before, after, k))), 46, Color.WHITE, 0, MenuStyle.INK, 0.2, false)


## A challenge won: the team it unlocked, on a plate in its color, once the count is done.
func _draw_unlock(ci: Control, r: Rect2, team: int) -> void:
	var k := _in(_count_end() + 0.15)
	if k <= 0.0:
		return
	var col := MenuStyle.team_color(team)
	var x := r.position.x + (1.0 - k) * 120.0
	var plate := Rect2(x, r.position.y + 30, r.size.x - 30, r.size.y - 30)
	MenuStyle.draw_slant(ci, Rect2(plate.position + Vector2(8, 9), plate.size), Color(0, 0, 0, 0.4 * k), 26)
	MenuStyle.draw_slant(ci, plate.grow(5), Color(MenuStyle.INK, k), 26)
	MenuStyle.draw_slant(ci, plate, Color(col, k), 26)
	MenuStyle.draw_slant(ci, Rect2(x, plate.position.y + plate.size.y * 0.6, plate.size.x, plate.size.y * 0.4), Color(0, 0, 0, 0.2 * k), 10)
	var tag := "TEAM UNLOCKED"
	var tw := MenuStyle.text_width(tag, 20, 0.12) + 40
	MenuStyle.draw_slant(ci, Rect2(x + 30, r.position.y, tw, 30), Color(GOLD, k), 10)
	ci.draw_string(MenuStyle.font(0.12), Vector2(x + 50, r.position.y + 23), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(MenuStyle.INK, k))
	var logo := MenuStyle.team_logo(team)
	var nx := x + 40.0
	if logo:
		var lw := MenuStyle.logo_slot(logo, plate.size.y + 16)   # (wide crests get a wider slot; the name moves over)
		MenuStyle.draw_logo(ci, logo, Rect2(x + 26, plate.position.y - 8, lw, plate.size.y + 16), Color(1, 1, 1, k))
		nx = x + 44.0 + lw
	var info := Teams.team(team)
	ci.draw_string(MenuStyle.font(0.12), Vector2(nx, plate.position.y + 40), str(info.city).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85 * k))
	var name := str(info.name).to_upper()
	var fs := 46
	while fs > 26 and MenuStyle.text_width(name, fs) > plate.end.x - nx - 40.0:
		fs -= 2
	MenuStyle.draw_bold(ci, Vector2(nx, plate.position.y + 92), name, fs, Color(1, 1, 1, k), 8, Color(MenuStyle.INK, k), 0.2, false)


# --- Continue --------------------------------------------------------------------------

## The first press finishes the count; the next one moves on.
func _on_accept() -> void:
	if _age < INPUT_DELAY:
		return
	if _age < _count_end():
		_age = _count_end()
		_ticked = _lines().size()
		return
	Sfx.play("glove", Vector3.INF, -6.0)
	_continue()


func _continue() -> void:
	if _done:
		return
	_done = true
	if cut:
		Stinger.play(get_tree().root, _close)
	else:
		_close()


func _close() -> void:
	continued.emit()
	queue_free()
