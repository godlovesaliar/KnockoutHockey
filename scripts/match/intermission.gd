class_name Intermission
extends CanvasLayer
## The stats screen between periods and at the final horn, in the front-end style (like
## the pause menu): the game dimmed behind, the mode tag and heading, both teams' plates
## with the score, a game-stats panel (twin bars in the team colors), and the prompt bar.
##   Between periods: each team's HOT and COLD player over the period just played (from
##     MatchDirector.box; cold only for a player who hurt their team).
##   At the end: the THREE STARS of the game.
## Accept (A / Enter / Space / J, or Start) continues: the next period, or the menu.
## Presses in the first INPUT_DELAY seconds are ignored. With no humans in the game (AI vs
## AI, tests) it moves on by itself after AUTO_CONTINUE seconds.

signal continued

const INPUT_DELAY := 1.0
const AUTO_CONTINUE := 3.0
const PLATE_W := 470.0
const SCORE_W := 110.0
const PLATE_H := 104.0
const PLATE_Y := 172.0
const PANEL_Y := 318.0
const STAR_COLORS := [Color(1.0, 0.82, 0.25), Color(0.85, 0.88, 0.94), Color(0.86, 0.55, 0.3)]

var d: MatchDirector
var final := false
var _age := 0.0
var _done := false
var _canvas: Control
var _input: MenuInput
var _rows: Array = []           ## [label, away value, home value]
var _hot := []                  ## per team (index = team): [hot, cold]
var _stars: Array[Skater] = []


func open(director: MatchDirector, is_final := false) -> void:
	d = director
	final = is_final
	layer = 10
	_gather()
	_build()


func _players(t: int) -> Array:
	var out: Array = d.lineup(t).all_skaters()
	if d.lineup(t).goalie:
		out.append(d.lineup(t).goalie)
	return out


func _gather() -> void:
	var s := d.stats
	var played := mini(d.period, s.period_goals[0].size())
	for p in range(1, played + 1):
		_rows.append(["GOALS, %s" % ("OT" if p > d.periods else d.period_name(p)), s.period_goals[1][p - 1], s.period_goals[0][p - 1]])
	_rows.append(["SHOTS ON GOAL", d.shots_on_goal(1), d.shots_on_goal(0)])
	_rows.append(["SAVES", s.saves[1], s.saves[0]])
	_rows.append(["HITS", s.hits[1], s.hits[0]])
	_rows.append(["BIG HITS", s.big_hits[1], s.big_hits[0]])
	_rows.append(["FACEOFFS WON", s.faceoffs[1], s.faceoffs[0]])
	_rows.append(["PENALTIES", s.penalties[1], s.penalties[0]])
	_rows.append(["POWER-PLAY GOALS", s.pp_goals[1], s.pp_goals[0]])
	if final:
		var winner := -1
		if d.score[0] != d.score[1]:
			winner = 0 if d.score[0] > d.score[1] else 1
		_stars = d.box.stars(_players(0) + _players(1), winner)
	else:
		_hot = [d.box.hot_cold(_players(0)), d.box.hot_cold(_players(1))]


func _build() -> void:
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
	_input.accepted.connect(_try_continue)
	_input.started.connect(_try_continue)


func _process(delta: float) -> void:
	_age += delta
	for c in _canvas.get_children():
		c.queue_redraw()
	if d.humans.is_empty() and _age > AUTO_CONTINUE:
		_continue()


## Slide-in progress (0 → 1) for something that starts `delay` s after the screen opens.
func _in(delay: float) -> float:
	return ease(clampf((_age - delay) / 0.3, 0.0, 1.0), -2.0)


func _paint(ci: Control) -> void:
	var w := _canvas.size.x
	var mode := "INTERMISSION"
	var title := "END OF %s" % d.period_name(d.period)
	if d.period > d.periods and not final:
		title = "END OF OVERTIME"
	if final:
		mode = "EXHIBITION"
		title = "FINAL" if d.period <= d.periods else "FINAL / %s" % d.period_name(d.period)
	MenuStyle.draw_tag(ci, Vector2(60, 40), mode, title)
	_draw_plates(ci)
	var left_w := minf(700.0, (w - 180.0) * 0.48)
	_draw_stats(ci, Rect2(60 - (1.0 - _in(0.15)) * 80.0, PANEL_Y, left_w, 480))
	var rx := 60.0 + left_w + 60.0
	var rr := Rect2(rx + (1.0 - _in(0.25)) * 80.0, PANEL_Y, w - rx - 60.0, 480)
	if final:
		_draw_stars(ci, rr)
	else:
		_draw_hot_cold(ci, rr)
	var hint := ""
	if d.humans.is_empty():
		hint = "AI vs AI — continuing."
	elif final:
		hint = "Back to team select."
	else:
		hint = "Next: the %s." % ("overtime" if d.period + 1 > d.periods else "%s period" % d.period_name(d.period + 1).to_lower())
	MenuStyle.draw_footer(ci, w, hint, [] if d.humans.is_empty() else [[_input.accept_label(), "CONTINUE"]], _input.using_pad)


# --- Team plates and score -------------------------------------------------------------

func _draw_plates(ci: Control) -> void:
	var x := 60.0
	var winner := -1
	if final and d.score[0] != d.score[1]:
		winner = 0 if d.score[0] > d.score[1] else 1
	for i in 2:
		var t := 1 - i   # away on the left, home on the right
		var k := _in(0.05 + i * 0.07)
		var id: int = d.team_ids[t]
		var col := MenuStyle.team_color(id)
		var px := x + (1.0 - k) * (-120.0 if i == 0 else 120.0)
		var faded := winner >= 0 and winner != t
		var a := k * (0.55 if faded else 1.0)
		# Plate: shadow, ink rim, the color, a darker lower band.
		var plate := Rect2(px, PLATE_Y, PLATE_W, PLATE_H)
		MenuStyle.draw_slant(ci, Rect2(plate.position + Vector2(8, 9), plate.size), Color(0, 0, 0, 0.4 * k), 22)
		MenuStyle.draw_slant(ci, plate.grow(5), Color(MenuStyle.INK, a), 22)
		MenuStyle.draw_slant(ci, plate, Color(col, a), 22)
		MenuStyle.draw_slant(ci, Rect2(px, PLATE_Y + PLATE_H * 0.6, PLATE_W, PLATE_H * 0.4), Color(0, 0, 0, 0.2 * a), 9)
		var logo := MenuStyle.team_logo(id)
		if logo:
			ci.draw_texture_rect(logo, Rect2(px + 26, PLATE_Y - 10, PLATE_H + 20, PLATE_H + 20), false, Color(1, 1, 1, a))
		var info := Teams.team(id)
		var nx := px + PLATE_H + 60.0
		ci.draw_string(MenuStyle.font(0.12), Vector2(nx, PLATE_Y + 34), str(info.city).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85 * a))
		var name := str(info.name).to_upper()
		var fs := 44 if MenuStyle.text_width(name, 44) < PLATE_W - PLATE_H - 90 else 34
		MenuStyle.draw_bold(ci, Vector2(nx, PLATE_Y + 80), name, fs, Color(1, 1, 1, a), 8, Color(MenuStyle.INK, a), 0.2, false)
		# Score box.
		var sx := px + PLATE_W + 14.0
		MenuStyle.draw_slant(ci, Rect2(sx, PLATE_Y, SCORE_W, PLATE_H), Color(MenuStyle.INK, 0.95 * k), 22)
		var sc := str(d.score[t])
		MenuStyle.draw_bold(ci, Vector2(sx + (SCORE_W - MenuStyle.text_width(sc, 72)) * 0.5 + 10, PLATE_Y + 80), sc, 72,
				Color(1, 1, 1, a) if not faded else Color(MenuStyle.DIM, k), 0, MenuStyle.INK, 0.2, false)
		if winner == t:
			MenuStyle.draw_slant(ci, Rect2(sx, PLATE_Y + PLATE_H - 6, SCORE_W, 6), MenuStyle.RED, 2)
		x += PLATE_W + SCORE_W + 70.0


# --- Game stats ------------------------------------------------------------------------

func _draw_stats(ci: Control, r: Rect2) -> void:
	_panel(ci, r, "GAME STATS")
	var f := MenuStyle.font(0.12)
	var cols := [MenuStyle.team_color(d.team_ids[1]), MenuStyle.team_color(d.team_ids[0])]
	var abbr := [str(Teams.team(d.team_ids[1]).abbr), str(Teams.team(d.team_ids[0]).abbr)]
	ci.draw_string(f, r.position + Vector2(24, 82), abbr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	ci.draw_string(f, r.position + Vector2(r.size.x - 24 - MenuStyle.text_width(abbr[1], 18, 0.12), 82), abbr[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	var row_h := minf(38.0, (r.size.y - 110.0) / maxf(_rows.size(), 1))
	var cx := r.position.x + r.size.x * 0.5
	var bar_w := r.size.x * 0.5 - 90.0
	for i in _rows.size():
		var row: Array = _rows[i]
		var k := _in(0.25 + i * 0.03)
		var y := r.position.y + 100.0 + i * row_h
		if i % 2 == 0:
			ci.draw_rect(Rect2(r.position.x + 10, y, r.size.x - 20, row_h), Color(1, 1, 1, 0.035))
		var a: int = row[1]
		var b: int = row[2]
		var total := maxf(a + b, 1)
		# Twin bars growing out from the middle, each team's share in its color.
		var by := y + row_h - 9.0
		ci.draw_rect(Rect2(cx - bar_w * (a / total) * k, by, bar_w * (a / total) * k, 4), cols[0])
		ci.draw_rect(Rect2(cx, by, bar_w * (b / total) * k, 4), cols[1])
		var lw := MenuStyle.text_width(row[0], 17, 0.12)
		ci.draw_string(f, Vector2(cx - lw * 0.5, y + row_h * 0.55), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MenuStyle.ICE)
		var lead := 0 if a > b else (1 if b > a else -1)
		ci.draw_string(MenuStyle.font(0.2), Vector2(r.position.x + 26, y + row_h * 0.7), str(a), HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
				Color.WHITE if lead == 0 else MenuStyle.DIM)
		var bw := MenuStyle.text_width(str(b), 24)
		ci.draw_string(MenuStyle.font(0.2), Vector2(r.end.x - 26 - bw, y + row_h * 0.7), str(b), HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
				Color.WHITE if lead == 1 else MenuStyle.DIM)


func _panel(ci: Control, r: Rect2, heading: String) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.3))
	ci.draw_rect(r, Color(0.03, 0.05, 0.1, 0.86))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), MenuStyle.RED)
	MenuStyle.draw_bold(ci, r.position + Vector2(24, 48), heading, 30, Color.WHITE, 0, MenuStyle.INK, 0.2, true)


# --- Hot and cold, three stars ---------------------------------------------------------

func _draw_hot_cold(ci: Control, r: Rect2) -> void:
	_panel(ci, r, "HOT AND COLD")
	ci.draw_string(MenuStyle.font(0.12), r.position + Vector2(r.size.x - 24 - MenuStyle.text_width("THIS PERIOD", 16, 0.12), 44),
			"THIS PERIOD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
	var card_w := (r.size.x - 72.0) * 0.5
	var card_h := 140.0
	for row in 2:   # 0 hot, 1 cold
		var tag := "HOT" if row == 0 else "COLD"
		var tag_col := Color(1.0, 0.45, 0.1) if row == 0 else Color(0.35, 0.68, 1.0)
		for i in 2:
			var t := 1 - i
			var k := _in(0.35 + row * 0.1 + i * 0.05)
			var cr := Rect2(r.position.x + 24 + i * (card_w + 24) + (1.0 - k) * 40.0, r.position.y + 100 + row * (card_h + 40), card_w, card_h)
			var s: Skater = _hot[t][row]
			_player_card(ci, cr, t, s, tag, tag_col, d.box.line_text(s, d.box.period_line(s)) if s else "", k)


func _draw_stars(ci: Control, r: Rect2) -> void:
	_panel(ci, r, "THREE STARS")
	var card_h := 106.0
	for i in _stars.size():
		var s := _stars[i]
		var k := _in(0.4 + i * 0.18)
		var cr := Rect2(r.position.x + 24 + (1.0 - k) * 60.0, r.position.y + 100 + i * (card_h + 30), r.size.x - 48, card_h)
		_player_card(ci, cr, s.team, s, ["1ST STAR", "2ND STAR", "3RD STAR"][i], STAR_COLORS[i], d.box.line_text(s), k, i + 1)


## One player: a tag on top, a team-colored plate (crest, name, position), the stat line
## below on ink. `s` null: an empty card ("nobody"). `star` > 0 draws that star.
func _player_card(ci: Control, r: Rect2, t: int, s: Skater, tag: String, tag_col: Color, line: String, k: float, star := 0) -> void:
	var id: int = d.team_ids[t]
	var col := MenuStyle.team_color(id)
	var f := MenuStyle.font(0.12)
	var a := k
	var tw := MenuStyle.text_width(tag, 18, 0.12) + 34
	MenuStyle.draw_slant(ci, Rect2(r.position + Vector2(4, -26), Vector2(tw, 26)), Color(tag_col, a), 10)
	ci.draw_string(f, r.position + Vector2(20, -6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(MenuStyle.INK, a))
	var top := r.size.y * 0.62
	ci.draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.3 * a))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, top)), Color(col, a if s else a * 0.35))
	ci.draw_rect(Rect2(r.position + Vector2(0, top), Vector2(r.size.x, r.size.y - top)), Color(0.02, 0.03, 0.07, 0.95 * a))
	ci.draw_rect(Rect2(r.position + Vector2(0, top - 3), Vector2(r.size.x, 3)), Color(tag_col, a))
	var x := r.position.x + 16.0
	if star > 0:
		_star(ci, Vector2(x + 30, r.position.y + top * 0.5), 30.0, Color(tag_col, a))
		x += 70.0
	var logo := MenuStyle.team_logo(id)
	if logo:
		var ls := top - 12.0
		ci.draw_texture_rect(logo, Rect2(x, r.position.y + 6, ls, ls), false, Color(1, 1, 1, a))
		x += ls + 12.0
	if s == null:
		MenuStyle.draw_bold(ci, Vector2(x, r.position.y + top * 0.66), "NOBODY", 26, Color(1, 1, 1, 0.5 * a), 0, MenuStyle.INK, 0.2, false)
		ci.draw_string(f, Vector2(r.position.x + 16, r.end.y - 18), "Clean period for %s." % Teams.team(id).abbr if tag == "COLD" else "Nobody stood out.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(MenuStyle.DIM, a))
		return
	var name := MenuStyle.player_name(s)
	var avail := r.end.x - x - 70.0
	var fs := 34
	while fs > 20 and MenuStyle.text_width(name, fs) > avail:
		fs -= 2
	MenuStyle.draw_bold(ci, Vector2(x, r.position.y + top * 0.5 + fs * 0.36), name, fs, Color(1, 1, 1, a), 6, Color(MenuStyle.INK, a), 0.2, false)
	var pos := "G" if s is Goalie else s.position_name
	var pw := MenuStyle.text_width(pos, 20, 0.12)
	ci.draw_string(f, Vector2(r.end.x - 18 - pw, r.position.y + top * 0.5 + 8), pos, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75 * a))
	ci.draw_string(f, Vector2(r.position.x + 16, r.end.y - (r.size.y - top) * 0.5 + 7), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32, 19, Color(MenuStyle.ICE, a))


func _star(ci: Control, c: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * (radius if i % 2 == 0 else radius * 0.45))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(3, 4))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.4 * col.a))
	ci.draw_colored_polygon(pts, col)


# --- Continue --------------------------------------------------------------------------

func _try_continue() -> void:
	if _age >= INPUT_DELAY:
		Sfx.play("glove", Vector3.INF, -6.0)
		_continue()


func _continue() -> void:
	if _done:
		return
	_done = true
	continued.emit()
	queue_free()
