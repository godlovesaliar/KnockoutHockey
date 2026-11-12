extends Control
## RULES AND OPTIONS: tabs across the top (RULES, AUDIO, VIDEO, CONTROLS), each a column of
## settings bars over the arena like the game rules screen; CONTROLS shows the button chart.
##
## Up / down picks a row, left / right changes it (accept steps it forward too; the mouse:
## click to step, right-click to step back). L1 / R1 (Q / E) or a click switches tabs.
## Changes apply at once and are saved (`GameSettings.save_settings`) on the way out.
## Back: the main menu.
##
## `-- shot=<png> [wait=<s>] [tab=rules|audio|video|controls] [sel=<n>]` saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

const TABS := ["rules", "audio", "video", "controls"]
const TAB_NAMES := ["RULES", "AUDIO", "VIDEO", "CONTROLS"]

const VOLUME_VALUES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const VOLUME_NAMES := ["Off", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]

const AUDIO := [
	{"key": "master", "label": "MASTER VOLUME", "values": VOLUME_VALUES, "names": VOLUME_NAMES,
		"hint": "Everything at once."},
	{"key": "music", "label": "MENU MUSIC", "values": VOLUME_VALUES, "names": VOLUME_NAMES,
		"hint": "The front-end playlist."},
	{"key": "effects", "label": "SOUND EFFECTS", "values": VOLUME_VALUES, "names": VOLUME_NAMES,
		"hint": "Skates, shots, hits, the horn and the menus."},
	{"key": "crowd", "label": "CROWD AND ORGAN", "values": VOLUME_VALUES, "names": VOLUME_NAMES,
		"hint": "The building: crowd noise, cheers, chants and the organ."},
	{"key": "announcer", "label": "ANNOUNCERS", "values": VOLUME_VALUES, "names": VOLUME_NAMES,
		"hint": "The booth: play-by-play and color."},
]

const VIDEO := [
	{"key": "graphics", "label": "GRAPHICS", "values": ["quality", "performance"], "names": ["Quality", "Performance"],
		"hint": "Performance: lower 3D resolution (upscaled), no anti-aliasing, simpler crowd, shadows and haze. For slower PCs."},
	{"key": "window", "label": "DISPLAY", "values": ["windowed", "borderless", "fullscreen"],
		"names": ["Window", "Borderless", "Fullscreen"],
		"hint": "Borderless fills the screen as a window (quick to alt-tab); Fullscreen takes over the display."},
	{"key": "vsync", "label": "VSYNC", "values": [true, false], "names": ["On", "Off"],
		"hint": "Waits for the monitor's refresh: no tearing. Off can feel snappier."},
	{"key": "msaa", "label": "ANTI-ALIASING", "values": [0, 2, 4, 8], "names": ["Off", "2x", "4x", "8x"],
		"hint": "Smooths jagged edges. Higher costs frame rate."},
	{"key": "max_fps", "label": "FRAME CAP", "values": [0, 60, 120, 144, 240], "names": ["None", "60", "120", "144", "240"],
		"hint": "Caps the frame rate (with VSync off) to keep the PC cooler and quieter."},
	{"key": "blood", "label": "BLOOD", "values": [true, false], "names": ["On", "Off"],
		"hint": "Fights: a hurt fighter bleeds on the big shots. Off: spit only."},
]

const ROW_POS := Vector2(80, 178)
const ROW_SIZE := Vector2(800, 40)
const ROW_GAP := 4.0
const TAB_POS := Vector2(720, 70)
const TAB_SIZE := Vector2(190, 46)

var _tab := 0
var _rows: Array = []       ## the current tab's settings (+ a reset row on rules)
var _target: Dictionary     ## GameSettings.config or GameSettings.options
var _canvas: Control
var _items: Array[MenuItem] = []
var _list: Control
var _chart: Control
var _tabs: Control
var _header: Control
var _index := 0
var _input: MenuInput
var _footer: Control
var _fade: ColorRect
var _leaving := false
var _t := 0.0


func _ready() -> void:
	Sfx.play_music()
	add_child(MenuBackdrop.new())
	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if not _items.is_empty():
			_select(wrapi(_index + dir, 0, _items.size())))
	_input.side.connect(func(dir: int) -> void: _step(_index, dir))
	_input.accepted.connect(_accept)
	_input.back.connect(_back)
	_input.dev_bumper.connect(func(_dev: String, dir: int) -> void: _show_tab(wrapi(_tab + dir, 0, TABS.size())))

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

	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.draw.connect(func() -> void: MenuStyle.draw_tag(_header, Vector2(60, 40), "OPTIONS", TAB_NAMES[_tab]))
	_canvas.add_child(_header)

	_tabs = Control.new()
	_tabs.position = TAB_POS
	_tabs.size = Vector2(TAB_SIZE.x * TABS.size() + 40, TAB_SIZE.y)
	_tabs.draw.connect(_draw_tabs)
	_tabs.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var k := int((e.position.x - 30.0) / TAB_SIZE.x)
			if k >= 0 and k < TABS.size() and k != _tab:
				_show_tab(k))
	_canvas.add_child(_tabs)

	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_list)
	_chart = Control.new()
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.draw.connect(func() -> void: PauseMenu.draw_controls_chart(_chart, _canvas.size.x, 178.0))
	_canvas.add_child(_chart)

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

	_show_tab(maxi(0, TABS.find(_arg("tab", "rules"))), true)
	if _arg("sel", "") != "" and not _items.is_empty():
		_select(clampi(int(_arg("sel", "0")), 0, _items.size() - 1), true)


func _process(delta: float) -> void:
	_t += delta
	_footer.queue_redraw()
	_tabs.queue_redraw()


func _show_tab(k: int, quiet := false) -> void:
	_tab = k
	for it in _items:
		it.queue_free()
	_items.clear()
	_index = 0
	match TABS[k]:
		"rules":
			_rows = RulesSelect.RULES.duplicate()
			_rows.append({"key": "", "label": "RESET RULES", "hint": "Back to the standard rules (your teams stay picked)."})
			_target = GameSettings.config
		"audio":
			_rows = AUDIO.duplicate()
			_rows.append({"key": "", "label": "RESET AUDIO", "hint": "Back to the standard volumes."})
			_target = GameSettings.options
		"video":
			_rows = VIDEO.duplicate()
			_rows.append({"key": "", "label": "RESET VIDEO", "hint": "Back to Quality graphics in a window with VSync and 2x anti-aliasing."})
			_target = GameSettings.options
		_:
			_rows = []
	_chart.visible = TABS[k] == "controls"
	_chart.queue_redraw()
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		var it := MenuItem.new()
		it.text = d.label
		it.position = ROW_POS + Vector2(0, i * (ROW_SIZE.y + ROW_GAP) + (14.0 if d.key == "" else 0.0))
		it.size = ROW_SIZE if d.key != "" else Vector2(480, 50)
		it.value_w = 290.0
		it.intro(0.05 + i * 0.025)
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
		_list.add_child(it)
		_items.append(it)
	_header.queue_redraw()   # it shows the tab's name
	_refresh()
	if not _items.is_empty():
		_select(0, true)
	if not quiet:
		Sfx.play("click", Vector3.INF, -8.0, 1.1)


func _refresh() -> void:
	for i in _rows.size():
		var st: Dictionary = _rows[i]
		if st.key == "":
			continue
		var idx: int = st.values.find(_target.get(st.key))
		_items[i].value = st.names[idx] if idx >= 0 else str(_target.get(st.key))
		var dim := false
		if TABS[_tab] == "rules":
			var ot: String = _target.get("overtime", "sd_so")
			dim = (st.key == "ot_length" and ot in ["off", "shootout"]) \
					or (st.key == "shootout_rounds" and ot in ["off", "sudden_death"])
		elif st.key == "max_fps":
			dim = bool(_target.get("vsync", true))
		elif st.key == "msaa":
			dim = str(_target.get("graphics", "quality")) == "performance"   # performance turns it off
		_items[i].modulate.a = 0.45 if dim else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if _rows[k].key == "" else ""
		_items[k].glyph_pad = _input.using_pad
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _step(i: int, dir: int) -> void:
	if _leaving or i >= _rows.size() or _rows[i].key == "":
		return
	var st: Dictionary = _rows[i]
	var values: Array = st.values
	var cur := values.find(_target.get(st.key))
	_target[st.key] = values[wrapi(cur + dir, 0, values.size()) if cur >= 0 else 0]
	_applied(st.key)
	_refresh()


## Applies a changed option and plays something that lets you hear it.
func _applied(key: String) -> void:
	match TABS[_tab]:
		"audio":
			GameSettings.apply_audio()
			match key:
				"crowd":
					Sfx.crowd_react("cheer", 0.0, 9)
				"announcer":
					Sfx.announce("bighit", 9)
				_:
					Sfx.play("click", Vector3.INF, -8.0, 1.4)
			return
		"video":
			GameSettings.apply_video()
	Sfx.play("click", Vector3.INF, -8.0, 1.6)


func _accept() -> void:
	if _leaving or _index >= _rows.size():
		return
	if _rows[_index].key != "":
		_step(_index, 1)
		return
	# A reset row.
	Sfx.play("glove", Vector3.INF, -6.0)
	match TABS[_tab]:
		"rules":
			var keep := {"home_team": GameSettings.config.home_team, "away_team": GameSettings.config.away_team}
			GameSettings.config.merge(GameSettings.default_config(), true)
			GameSettings.config.merge(keep, true)
		"audio", "video":
			var defaults := GameSettings.default_options()
			for st: Dictionary in _rows:
				if st.key != "":
					GameSettings.options[st.key] = defaults[st.key]
			GameSettings.apply_audio()
			if TABS[_tab] == "video":
				GameSettings.apply_video()
	_items[_index].nudge()
	_refresh()


func _back() -> void:
	if _leaving:
		return
	GameSettings.save_settings()
	GameSettings.menu_select = 4
	Sfx.play("pad", Vector3.INF, -8.0)
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


## The tab strip: slanted plates, the current one red, with the L1 / R1 prompts either side.
func _draw_tabs() -> void:
	var pad := _input.using_pad
	var lb := "L1" if pad else "Q"
	var rb := "R1" if pad else "E"
	var gy := (TAB_SIZE.y - 30.0) * 0.5
	MenuStyle.draw_glyph(_tabs, Vector2(-14, gy), lb, false, 30.0)
	for k in TABS.size():
		var r := Rect2(Vector2(30.0 + k * TAB_SIZE.x, 0), TAB_SIZE - Vector2(12, 0))
		var on := k == _tab
		MenuStyle.draw_slant(_tabs, Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.35), 16.0)
		MenuStyle.draw_slant(_tabs, r, MenuStyle.RED if on else Color(0.06, 0.08, 0.15, 0.85), 16.0)
		if on:
			_tabs.draw_rect(Rect2(r.position + Vector2(16, r.size.y - 4), Vector2(r.size.x - 16, 4)), Color(1, 1, 1, 0.85))
		var name: String = TAB_NAMES[k]
		var tw := MenuStyle.text_width(name, 22)
		MenuStyle.draw_bold(_tabs, r.position + Vector2((r.size.x - tw) * 0.5 + 8, 31), name, 22,
				Color.WHITE if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	var x_end := 30.0 + TABS.size() * TAB_SIZE.x + 6.0
	MenuStyle.draw_glyph(_tabs, Vector2(x_end, gy), rb, false, 30.0)


func _draw_footer() -> void:
	var hint := "The buttons for pads and both keyboards. Keyboard 2 is the arrows and the number pad."
	if _index < _rows.size():
		hint = _rows[_index].hint
	var prompts := []
	if not _rows.is_empty():
		prompts.append([_input.accept_label(), "RESET" if _rows[_index].key == "" else "CHANGE"])
	prompts.append([_input.back_label(), "BACK"])
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
