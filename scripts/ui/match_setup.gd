extends Control
## Exhibition setup: pick sides for every controller, set match rules, start.
##
## Each device moves its own token: Keyboard 1 with A/D, Keyboard 2 with ←/→,
## pads with the d-pad / left stick. Settings use the mouse (◀ ▶ buttons).
## Enter / pad Start / the PLAY button starts the game. Esc quits.

const MATCH_SCENE := "res://scenes/match/Match.tscn"

const SETTINGS := [
	{"key": "home_team", "label": "Home team", "values": [], "names": []},   # filled from Teams in _ready
	{"key": "away_team", "label": "Away team", "values": [], "names": []},
	{"key": "format", "label": "Format", "values": [5, 3], "names": ["5 on 5", "3 on 3"]},
	{"key": "period_length", "label": "Period length", "values": [60.0, 120.0, 180.0, 300.0, 420.0, 600.0, 1200.0],
		"names": ["1 min", "2 min", "3 min", "5 min", "7 min", "10 min", "20 min"]},
	{"key": "overtime", "label": "Overtime", "values": ["sd_so", "sudden_death", "shootout", "off"],
		"names": ["Sudden death → shootout", "Sudden death", "Shootout", "Off (ties allowed)"]},
	{"key": "ot_length", "label": "OT length", "values": [60.0, 180.0, 300.0], "names": ["1 min", "3 min", "5 min"]},
	{"key": "shootout_rounds", "label": "Shootout rounds", "values": [3, 5], "names": ["3", "5"]},
	{"key": "offsides", "label": "Offsides", "values": [true, false], "names": ["On", "Off"]},
	{"key": "icing", "label": "Icing", "values": [true, false], "names": ["On", "Off"]},
	{"key": "penalties", "label": "Penalties", "values": [true, false], "names": ["On", "Off"]},
	{"key": "fighting", "label": "Fighting", "values": [true, false], "names": ["On", "Off"]},
	{"key": "line_changes", "label": "Line changes / fatigue", "values": [true, false], "names": ["Auto", "Off"]},
	{"key": "difficulty", "label": "CPU difficulty", "values": [0.2, 0.5, 0.75, 0.95], "names": ["Rookie", "Pro", "All-Star", "Legend"]},
]

var devices: Array[Dictionary] = []   ## {kind, pad, name, side: -1 home / 0 none / 1 away}
var config := {}
var _tokens: Array[Label] = []
var _value_labels := {}
var _side_box: VBoxContainer
var _prev := {}
var _side_headers: Array[Label] = []
var _settings: Array = []          ## SETTINGS with the team lists filled in


func _ready() -> void:
	config = GameSettings.config.duplicate(true)
	_settings = SETTINGS.duplicate(true)
	for st: Dictionary in _settings:
		if st.key in ["home_team", "away_team"]:
			st.values = range(Teams.count())
			st.names = range(Teams.count()).map(func(i: int) -> String: return Teams.full_name(i))
	_detect_devices()
	_build_ui()
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void:
		_detect_devices()
		_rebuild_tokens())


func _detect_devices() -> void:
	var old := {}
	for d in devices:
		old["%s%d" % [d.kind, d.pad]] = d.side
	devices.clear()
	devices.append({"kind": "kb1", "pad": 0, "name": "Keyboard 1  (WASD · J K L I)", "side": -1})
	devices.append({"kind": "kb2", "pad": 0, "name": "Keyboard 2  (Arrows · Num 1 2 3 5)", "side": 0})
	for p in Input.get_connected_joypads():
		devices.append({"kind": "pad", "pad": p, "name": "Pad %d  (%s)" % [p + 1, Input.get_joy_name(p)], "side": 0})
	# Remember previous choices; otherwise put the first pad on HOME if there's one.
	var had_old := not old.is_empty()
	for d in devices:
		var key := "%s%d" % [d.kind, d.pad]
		if old.has(key):
			d.side = old[key]
	# First time in: a solo player gets one controller — Pad 1 if there is one, else Keyboard 1.
	if not had_old and devices.size() > 2:
		devices[0].side = 0
		devices[2].side = -1


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 30
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	root.add_child(_label("KNOCKOUT HOCKEY", 54, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(_label("EXHIBITION", 22, Color(0.8, 0.85, 0.95), HORIZONTAL_ALIGNMENT_CENTER))

	root.add_child(_label("CHOOSE SIDES  — each controller moves its own name left or right", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var header := HBoxContainer.new()
	for t in ["HOME", "— watching —", "AWAY"]:
		var l := _label(t, 18, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(l)
		_side_headers.append(l)
	root.add_child(header)
	_side_box = VBoxContainer.new()
	root.add_child(_side_box)
	_rebuild_tokens()

	root.add_child(_label("MATCH SETTINGS", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)
	for i in _settings.size():
		var st: Dictionary = _settings[i]
		grid.add_child(_label(st.label, 17, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_LEFT))
		var row := HBoxContainer.new()
		var left := Button.new()
		left.text = "◀"
		left.focus_mode = Control.FOCUS_NONE
		left.pressed.connect(_step.bind(i, -1))
		var val := _label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		val.custom_minimum_size = Vector2(260, 0)
		var right := Button.new()
		right.text = "▶"
		right.focus_mode = Control.FOCUS_NONE
		right.pressed.connect(_step.bind(i, 1))
		row.add_child(left)
		row.add_child(val)
		row.add_child(right)
		grid.add_child(row)
		_value_labels[st.key] = val
	_refresh_values()

	var play := Button.new()
	play.text = "   PLAY  (Enter / Start)   "
	play.add_theme_font_size_override("font_size", 26)
	play.focus_mode = Control.FOCUS_NONE
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(_start)
	root.add_child(play)
	root.add_child(_label("Esc quits.  In a game: R restarts, Esc returns here.", 14, Color(0.6, 0.65, 0.75), HORIZONTAL_ALIGNMENT_CENTER))


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _rebuild_tokens() -> void:
	if _side_box == null:
		return
	for c in _side_box.get_children():
		_side_box.remove_child(c)
		c.queue_free()
	_tokens.clear()
	for i in devices.size():
		var row := HBoxContainer.new()
		for col in 3:
			var cell := _label("", 17, HumanBrain.PLAYER_COLORS[i % 4], HORIZONTAL_ALIGNMENT_CENTER)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(cell)
		_side_box.add_child(row)
	_refresh_tokens()


func _refresh_tokens() -> void:
	var p := 0
	for i in devices.size():
		var row := _side_box.get_child(i) as HBoxContainer
		if row == null:
			continue
		var d := devices[i]
		var tag := "P%d · " % (p + 1) if d.side != 0 else ""
		if d.side != 0:
			p += 1
		for col in 3:
			(row.get_child(col) as Label).text = (tag + d.name) if col == d.side + 1 else ""


func _step(index: int, dir: int) -> void:
	var st: Dictionary = _settings[index]
	var values: Array = st.values
	var cur := values.find(config.get(st.key))
	cur = (cur + dir + values.size()) % values.size() if cur >= 0 else 0
	config[st.key] = values[cur]
	# A team can't play itself: skip over the other side's pick.
	if st.key in ["home_team", "away_team"]:
		var other := "away_team" if st.key == "home_team" else "home_team"
		if config[st.key] == config.get(other):
			cur = (cur + dir + values.size()) % values.size()
			config[st.key] = values[cur]
	_refresh_values()


func _refresh_values() -> void:
	for st: Dictionary in _settings:
		var idx: int = st.values.find(config.get(st.key))
		_value_labels[st.key].text = st.names[idx] if idx >= 0 else str(config.get(st.key))
	if _side_headers.size() == 3:
		for k in 2:
			var t := Teams.team(int(config.get("home_team" if k == 0 else "away_team", k)))
			_side_headers[k * 2].text = "%s  %s" % ["HOME" if k == 0 else "AWAY", str(t.name).to_upper()]
			_side_headers[k * 2].add_theme_color_override("font_color", (t.colors.jersey as Color).lerp(Color.WHITE, 0.25))


func _process(_delta: float) -> void:
	for d in devices:
		var dir := _device_dir(d)
		var key := "%s%d" % [d.kind, d.pad]
		if dir != 0 and _prev.get(key, 0) == 0:
			d.side = clampi(d.side + dir, -1, 1)
			_refresh_tokens()
		_prev[key] = dir
		if d.kind == "pad" and Input.is_joy_button_pressed(d.pad, JOY_BUTTON_START):
			_start()
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		_start()


func _device_dir(d: Dictionary) -> int:
	match d.kind:
		"kb1":
			return int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		"kb2":
			return int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT))
		"pad":
			var x := Input.get_joy_axis(d.pad, JOY_AXIS_LEFT_X)
			if Input.is_joy_button_pressed(d.pad, JOY_BUTTON_DPAD_LEFT) or x < -0.6:
				return -1
			if Input.is_joy_button_pressed(d.pad, JOY_BUTTON_DPAD_RIGHT) or x > 0.6:
				return 1
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()


func _start() -> void:
	var humans: Array = []
	for d in devices:
		if d.side != 0:
			humans.append({"kind": d.kind, "pad": d.pad, "team": 0 if d.side < 0 else 1})
	GameSettings.config = config
	GameSettings.humans = humans
	set_process(false)
	get_tree().change_scene_to_file(MATCH_SCENE)


## Screenshot hook for automated checks: `-- shot=<png>`.
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot.call_deferred(a.substr(5))


func _shot(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
