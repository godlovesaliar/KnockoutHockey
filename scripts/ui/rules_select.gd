extends Control
## Game rules, the second step of an exhibition (after TeamSelect): a column of settings
## bars over the arena, with the matchup card in the corner. The cursor starts on
## START GAME, so accepting straight away plays with the current rules.
##
## Up / down picks a row, left / right changes it (accept steps it forward too; the mouse:
## click a row to step it, right-click to step back). Pad Start starts from anywhere.
## Back: team select. Choices stay in GameSettings.config for next time.
##
## `-- shot=<png> [wait=<s>] [sel=<n>] [home=<i>] [away=<i>]` saves a screenshot and quits.

const MATCH_SCENE := "res://scenes/match/Match.tscn"
const TEAMS_SCENE := "res://scenes/ui/TeamSelect.tscn"

const RULES := [
	{"key": "format", "label": "FORMAT", "values": [5, 3], "names": ["5 on 5", "3 on 3"],
		"hint": "Skaters a side, plus the goalies."},
	{"key": "period_length", "label": "PERIOD LENGTH", "values": [60.0, 120.0, 180.0, 300.0, 420.0, 600.0, 1200.0],
		"names": ["1 min", "2 min", "3 min", "5 min", "7 min", "10 min", "20 min"], "hint": "Three periods of game clock."},
	{"key": "overtime", "label": "OVERTIME", "values": ["sd_so", "sudden_death", "shootout", "off"],
		"names": ["Sudden death + SO", "Sudden death", "Shootout", "Off"], "hint": "What breaks a tie after regulation."},
	{"key": "ot_length", "label": "OT LENGTH", "values": [60.0, 180.0, 300.0], "names": ["1 min", "3 min", "5 min"],
		"hint": "Sudden-death overtime: next goal wins."},
	{"key": "shootout_rounds", "label": "SHOOTOUT ROUNDS", "values": [3, 5], "names": ["3", "5"],
		"hint": "Shooters a side before it goes to sudden death."},
	{"key": "offsides", "label": "OFFSIDES", "values": [true, false], "names": ["On", "Off"],
		"hint": "The puck must cross the blue line before the attackers."},
	{"key": "icing", "label": "ICING", "values": [true, false], "names": ["On", "Off"],
		"hint": "Clearing it the length of the ice brings it back."},
	{"key": "penalties", "label": "PENALTIES", "values": [true, false], "names": ["On", "Off"],
		"hint": "Trips, boarding and interference send players to the box."},
	{"key": "fighting", "label": "FIGHTING", "values": [true, false], "names": ["On", "Off"],
		"hint": "Big hits can start a fight: drop the gloves or skate away."},
	{"key": "line_changes", "label": "LINE CHANGES", "values": [true, false], "names": ["Auto", "Off"],
		"hint": "Tired lines change on the fly. Off: no fatigue."},
	{"key": "difficulty", "label": "CPU DIFFICULTY", "values": [0.2, 0.5, 0.75, 0.95], "names": ["Rookie", "Pro", "All-Star", "Legend"],
		"hint": "How sharp the computer plays."},
]

const ROW_POS := Vector2(80, 178)
const ROW_SIZE := Vector2(800, 44)
const ROW_GAP := 6.0

var config := {}
var _canvas: Control
var _items: Array[MenuItem] = []
var _index := 0
var _input: MenuInput
var _footer: Control
var _card: Control
var _fade: ColorRect
var _leaving := false
var _crests: Array[TextureRect] = []


func _ready() -> void:
	config = GameSettings.config.duplicate(true)
	for k in ["home", "away"]:
		if _arg(k, "") != "":
			config[k + "_team"] = int(_arg(k, "0"))
	Sfx.play_music()
	var back := MenuBackdrop.new()
	back.team = int(config.get("home_team", 0))
	add_child(back)
	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void: _select(wrapi(_index + dir, 0, _items.size())))
	_input.side.connect(func(dir: int) -> void: _step(_index, dir))
	_input.accepted.connect(_accept)
	_input.started.connect(_start)
	_input.back.connect(_back)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.82))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	g.add_point(0.55, Color(0.02, 0.04, 0.1, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(1200, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	var header := Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.draw.connect(func() -> void: MenuStyle.draw_tag(header, Vector2(60, 40), "EXHIBITION", "GAME RULES"))
	_canvas.add_child(header)

	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.draw.connect(_draw_card)
	_canvas.add_child(_card)
	for t in 2:
		var cr := TextureRect.new()
		cr.texture = MenuArena.logo(int(config.get("home_team" if t == 0 else "away_team", t)))
		cr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cr.size = Vector2(100, 100)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(cr)
		_crests.append(cr)

	var rows := RULES.duplicate()
	rows.append({"key": "", "label": "START GAME", "hint": "Drop the puck."})
	for i in rows.size():
		var d: Dictionary = rows[i]
		var it := MenuItem.new()
		it.text = d.label
		it.position = ROW_POS + Vector2(0, i * (ROW_SIZE.y + ROW_GAP) + (14.0 if d.key == "" else 0.0))
		it.size = ROW_SIZE if d.key != "" else Vector2(480, 56)
		it.value_w = 290.0
		it.intro(0.1 + i * 0.03)
		it.hovered.connect(func() -> void:
			if _index != i:
				_select(i))
		it.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				if e.button_index == MOUSE_BUTTON_LEFT:
					_select(i, true)
					_accept()
				elif e.button_index == MOUSE_BUTTON_RIGHT:
					_select(i, true)
					_step(i, -1))
		_canvas.add_child(it)
		_items.append(it)
	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_canvas.add_child(_footer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)

	_refresh()
	_select(int(_arg("sel", str(_items.size() - 1))), true)


func _process(_delta: float) -> void:
	_footer.queue_redraw()
	_card.queue_redraw()


func _refresh() -> void:
	for i in RULES.size():
		var st: Dictionary = RULES[i]
		var idx: int = st.values.find(config.get(st.key))
		_items[i].value = st.names[idx] if idx >= 0 else str(config.get(st.key))
		# OT length / shootout rounds only matter with that kind of overtime.
		var ot: String = config.get("overtime", "sd_so")
		_items[i].soon = false
		_items[i].modulate.a = 0.45 if (st.key == "ot_length" and ot in ["off", "shootout"]) \
				or (st.key == "shootout_rounds" and ot in ["off", "sudden_death"]) else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if k == _items.size() - 1 else ""
		_items[k].glyph_pad = _input.using_pad
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _step(i: int, dir: int) -> void:
	if i >= RULES.size() or _leaving:
		return
	var st: Dictionary = RULES[i]
	var values: Array = st.values
	var cur := values.find(config.get(st.key))
	config[st.key] = values[wrapi(cur + dir, 0, values.size()) if cur >= 0 else 0]
	Sfx.play("click", Vector3.INF, -8.0, 1.6 if dir > 0 else 1.25)
	_refresh()


func _accept() -> void:
	if _index == _items.size() - 1:
		_start()
	else:
		_step(_index, 1)


func _start() -> void:
	if _leaving:
		return
	GameSettings.config = config
	Sfx.play("glove", Vector3.INF, -4.0)
	Sfx.stop_music(1.2)
	_go(MATCH_SCENE)


func _back() -> void:
	if _leaving:
		return
	GameSettings.config = config   # keep the rules for next time
	Sfx.play("pad", Vector3.INF, -8.0)
	_go(TEAMS_SCENE)


func _go(scene: String) -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


## The matchup in the top-right corner: both crests, abbreviations and who plays which.
func _draw_card() -> void:
	var w := _canvas.size.x
	var cw := 470.0
	var x := w - cw - 50.0
	var y := 40.0
	var h := 170.0
	_card.draw_rect(Rect2(x, y, cw, h), Color(0.03, 0.05, 0.1, 0.72))
	_card.draw_rect(Rect2(x, y, cw, 3), MenuStyle.RED)
	for t in 2:
		var cx := x + (cw * 0.22 if t == 0 else cw * 0.78)
		_crests[t].position = Vector2(cx - 50, y + 12)
	var f := MenuStyle.font(0.2)
	var small := MenuStyle.font(0.12)
	var vw := f.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_card.draw_string(f, Vector2(x + cw * 0.5 - vw * 0.5, y + 82), "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 0.85, 0.85))
	for t in 2:
		var info := Teams.team(int(config.get("home_team" if t == 0 else "away_team", t)))
		var cx := x + (cw * 0.22 if t == 0 else cw * 0.78)
		var name := str(info.name).to_upper()
		var nw := small.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_card.draw_string(small, Vector2(cx - nw * 0.5, y + 132), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		var who := _who(t)
		var ww := small.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_card.draw_string(small, Vector2(cx - ww * 0.5, y + 156), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				HumanBrain.PLAYER_COLORS[0] if who != "CPU" else MenuStyle.DIM)


## "P1 P2" for the humans on a team, else "CPU".
func _who(team: int) -> String:
	var out := PackedStringArray()
	var n := 0
	for h: Dictionary in GameSettings.humans:
		n += 1
		if int(h.get("team", 0)) == team:
			out.append("P%d" % n)
	return "CPU" if out.is_empty() else "  ".join(out)


func _draw_footer() -> void:
	var hint: String = (RULES[_index].hint if _index < RULES.size() else "Drop the puck.")
	var prompts := [[_input.accept_label(), "START" if _index == _items.size() - 1 else "CHANGE"], [_input.back_label(), "BACK"]]
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint, prompts, _input.using_pad)


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


## Screenshot hook for automated checks: `-- shot=<png> wait=<s>`.
func _enter_tree() -> void:
	var shot := _arg("shot", "")
	if shot != "":
		_shot.call_deferred(shot, float(_arg("wait", "2.0")))


func _shot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
