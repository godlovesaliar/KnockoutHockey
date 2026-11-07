class_name Intermission
extends CanvasLayer
## Stats screen between periods (and at the final horn): both teams in their colors,
## the score, goals by period and the game stats. Play waits until someone presses
## Enter / Space, or A / Start on a pad; `continued` then fires. With no humans in the
## game (AI vs AI, tests) it moves on by itself after AUTO_CONTINUE seconds.

signal continued

const INPUT_DELAY := 1.0          ## ignore presses this long after opening (no accidental skips)
const AUTO_CONTINUE := 3.0

var d: MatchDirector
var final := false
var _age := 0.0
var _done := false


func open(director: MatchDirector, is_final := false) -> void:
	d = director
	final = is_final
	layer = 10
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := "FINAL" if final else "END OF %s PERIOD" % d.period_name(d.period)
	if not final and d.period > d.periods:
		title = "END OF OVERTIME"
	box.add_child(_label(title, 40, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER))

	# Score line: HOME 2 - 1 AWAY, names in team colors.
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 24)
	score_row.add_child(_team_label(0))
	score_row.add_child(_label("%d  –  %d" % [d.score[0], d.score[1]], 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	score_row.add_child(_team_label(1))
	box.add_child(score_row)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 70)
	grid.add_theme_constant_override("v_separation", 6)
	var center := CenterContainer.new()
	center.add_child(grid)
	box.add_child(center)
	var s := d.stats
	var rows := []
	var played := mini(d.period, s.period_goals[0].size())
	for p in range(1, played + 1):
		rows.append(["Goals, %s" % ("OT" if p > d.periods else d.period_name(p)), s.period_goals[0][p - 1], s.period_goals[1][p - 1]])
	rows.append(["Shots on goal", d.shots_on_goal(0), d.shots_on_goal(1)])
	rows.append(["Saves", s.saves[0], s.saves[1]])
	rows.append(["Hits", s.hits[0], s.hits[1]])
	rows.append(["Big hits", s.big_hits[0], s.big_hits[1]])
	rows.append(["Faceoffs won", s.faceoffs[0], s.faceoffs[1]])
	rows.append(["Penalties", s.penalties[0], s.penalties[1]])
	rows.append(["Power-play goals", s.pp_goals[0], s.pp_goals[1]])
	for r: Array in rows:
		grid.add_child(_label(str(r[1]), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_label(r[0], 22, Color(0.75, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(_label(str(r[2]), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))

	var next := "Back to the menu" if final else "Start the %s" % ("overtime" if d.period + 1 > d.periods else "%s period" % d.period_name(d.period + 1))
	var hint := _label("Press Enter / A  —  %s" % next, 20, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	if d.humans.is_empty():
		hint.text = "(AI vs AI — continuing)"
	box.add_child(hint)


func _team_label(t: int) -> Label:
	var info := Teams.team(d.team_ids[t])
	var c: Color = (info.colors.jersey as Color).lerp(Color.WHITE, 0.2)
	if c.get_luminance() > 0.85:
		c = (info.colors.trim as Color).lerp(Color.WHITE, 0.25)   # white jerseys: show the trim color
	if c.get_luminance() < 0.35:
		c = c.lerp(Color.WHITE, 0.35)   # dark colors read poorly on the dimmed rink
	var l := _label(Teams.full_name(d.team_ids[t]).to_upper(), 30, c, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(360, 0)
	return l


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _process(delta: float) -> void:
	_age += delta
	if d.humans.is_empty() and _age > AUTO_CONTINUE:
		_continue()


func _input(event: InputEvent) -> void:
	if _done or _age < INPUT_DELAY:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		go = event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventJoypadButton and event.pressed:
		go = event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]
	if go:
		get_viewport().set_input_as_handled()
		_continue()


func _continue() -> void:
	if _done:
		return
	_done = true
	continued.emit()
	queue_free()
