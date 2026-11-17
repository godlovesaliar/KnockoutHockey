extends Control
## CUSTOMIZE > CREATE ARENA: two tabs of settings on the left (ARENA: name, style, home
## team; LOOK: seats, boards, lights, crowd, ribbon board, scoreboard, banners, center
## ice), the building itself behind, rebuilt as you change it, the camera drifting
## round it.
##
## Up / down picks a row, left / right changes it, accept types the name or runs an
## action row (PadKeyboard on a pad). L1 / R1 (Q / E) switch tabs. Saving stores the arena
## (Arenas); HOME TEAM makes it that team's home (outdoor rinks: created teams only).
## The rules screen's ARENA row picks any arena for a game. Back: the CUSTOMIZE menu
## (press twice to leave unsaved changes).
##
## `-- shot=<png> [wait=<s>] [tab=arena|look] [<arena key>=<value> ...] [team=<i>] [save=1]`
## saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const MENU_SELECT := 2          ## CREATE ARENA's place in the CUSTOMIZE list

const TABS := ["arena", "look"]
const TAB_NAMES := ["ARENA", "LOOK"]
const TAB_POS := Vector2(40, 152)
const TAB_SIZE := Vector2(190, 44)
const ROW_POS := Vector2(60, 220)
const ROW_SIZE := Vector2(720, 40)
const ROW_GAP := 4.0
const VALUE_W := 300.0
const CARD := Rect2(1030, 40, 520, 128)
const REBUILD_DELAY := 0.35
const WARN := 3.0

var _a := {}                ## the arena being edited (Arenas format)
var _edit_index := -1       ## which created arena (-1: a new one)
var _saved := ""
var _home := -1             ## HOME TEAM pick (-1: nobody)
var _saved_home := -1
var _preview_team := 0      ## whose colors dress the preview
var _tab := 0
var _rows: Array = []
var _items: Array[MenuItem] = []
var _index := 0
var _input: MenuInput
var _canvas: Control
var _list: Control
var _tabs: Control
var _header: Control
var _card: Control
var _footer: Control
var _fade: ColorRect
var _typer: LineEdit
var _kb: PadKeyboard
var _typing := ""
var _quiet_until := 0
var _warn := 0.0
var _warn_key := ""
var _toast := ""
var _toast_t := 0.0
var _leaving := false
var _time := 0.0

var _stage: Node3D
var _arena := {}
var _cam: Camera3D
var _rebuild_in := -1.0


func _ready() -> void:
	Sfx.play_music()
	_a = Arenas.blank()
	for k: String in _a:
		var v := _arg(k, "")
		if v != "":
			_a[k] = (v == "true") if _a[k] is bool else (int(v) if _a[k] is int or v.is_valid_int() else v)
	_preview_team = clampi(int(_arg("team", str(GameSettings.config.get("home_team", 0)))), 0, Teams.count() - 1)
	_saved = _snapshot()
	_build_stage()

	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if not _busy() and not _items.is_empty():
			_select(wrapi(_index + dir, 0, _items.size())))
	_input.side.connect(func(dir: int) -> void:
		if not _busy():
			_step(_index, dir))
	_input.accepted.connect(func() -> void:
		if not _busy():
			_accept())
	_input.back.connect(func() -> void:
		if not _busy():
			_back())
	_input.dev_bumper.connect(func(_dev: String, dir: int) -> void:
		if not _busy():
			_show_tab(wrapi(_tab + dir, 0, TABS.size())))

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.86))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	g.add_point(0.5, Color(0.02, 0.04, 0.1, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(1100, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.draw.connect(func() -> void: MenuStyle.draw_tag(_header, Vector2(60, 30), "CUSTOMIZE", "CREATE ARENA"))
	_canvas.add_child(_header)

	_tabs = Control.new()
	_tabs.position = TAB_POS
	_tabs.size = Vector2(TAB_SIZE.x * TABS.size() + 40, TAB_SIZE.y)
	_tabs.draw.connect(_draw_tabs)
	_tabs.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _busy():
			var k := int((e.position.x - 30.0) / TAB_SIZE.x)
			if k >= 0 and k < TABS.size() and k != _tab:
				_show_tab(k))
	_canvas.add_child(_tabs)

	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_list)

	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.draw.connect(_draw_card)
	_canvas.add_child(_card)

	_typer = LineEdit.new()
	_typer.visible = false
	_typer.add_theme_font_override("font", MenuStyle.font(0.12))
	_typer.add_theme_font_size_override("font_size", 20)
	_typer.add_theme_color_override("font_color", Color.WHITE)
	_typer.add_theme_color_override("caret_color", Color(1, 0.92, 0.6))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.03, 0.07, 0.92)
	box.border_color = Color(1, 0.92, 0.6)
	box.set_border_width_all(2)
	box.set_content_margin_all(6)
	_typer.add_theme_stylebox_override("normal", box)
	_typer.add_theme_stylebox_override("focus", box)
	_typer.text_submitted.connect(func(_text: String) -> void: _end_typing(true))
	_typer.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_typer.accept_event()
			_end_typing(false))
	_typer.focus_exited.connect(func() -> void:
		if _typing != "":
			_end_typing(true))
	_canvas.add_child(_typer)
	_kb = PadKeyboard.new()
	_canvas.add_child(_kb)
	_kb.done.connect(func(text: String) -> void: _finish_text(text))
	_kb.cancelled.connect(func() -> void: _finish_text(null))

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

	_show_tab(maxi(0, TABS.find(_arg("tab", "arena"))), true)


func _process(delta: float) -> void:
	_time += delta
	_warn = maxf(0.0, _warn - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			_rebuild()
	_place_camera()
	_footer.queue_redraw()
	_tabs.queue_redraw()
	_card.queue_redraw()


func _busy() -> bool:
	return _leaving or _typing != "" or Time.get_ticks_msec() < _quiet_until


func _snapshot() -> String:
	return JSON.stringify(_a) + str(_home)


func _dirty() -> bool:
	return _snapshot() != _saved


func _confirm(key: String) -> bool:
	if _warn > 0.0 and _warn_key == key:
		_warn = 0.0
		return true
	_warn = WARN
	_warn_key = key
	Sfx.play("pad", Vector3.INF, -6.0)
	return false


# --- Rows ---------------------------------------------------------------------------

func _tab_rows(tab: String) -> Array:
	var rows := []
	if tab == "arena":
		rows = [
			{"key": "editing", "label": "EDITING", "kind": "choice",
				"hint": "Make a new arena, or pick a saved one to change."},
			{"key": "name", "label": "NAME", "kind": "text", "max": 24, "hint": "What the arena's called."},
			{"key": "style", "label": "STYLE", "kind": "choice", "hint": "The kind of building. More styles are on the way."},
			{"key": "home", "label": "HOME TEAM", "kind": "choice",
				"hint": "Make it a team's home. Outdoor rinks can only be home to created teams."},
		]
	else:
		rows = [
			{"key": "seats", "label": "SEATS", "kind": "choice", "hint": "Seat color: the home team's, or one of its own."},
			{"key": "boards", "label": "BOARDS", "kind": "choice", "hint": "The dasher boards' color."},
			{"key": "lights", "label": "LIGHTS", "kind": "choice", "hint": "The light over the ice: cool, neutral or warm."},
			{"key": "attendance", "label": "CROWD", "kind": "choice", "hint": "How full the seats are."},
			{"key": "ribbon", "label": "RIBBON BOARD", "kind": "choice", "hint": "The LED band round the upper bowl."},
			{"key": "scoreboard", "label": "SCOREBOARD", "kind": "choice", "hint": "The scoreboard hung over center ice."},
			{"key": "banners", "label": "BANNERS", "kind": "choice", "hint": "Banners in the home team's colors over each end."},
			{"key": "center", "label": "CENTER ICE", "kind": "choice", "hint": "The logo painted at center ice."},
			{"key": "preview_team", "label": "PREVIEW AS", "kind": "choice",
				"hint": "Only for this screen: see the arena dressed for a team."},
		]
	rows.append({"key": "save", "label": "SAVE ARENA", "kind": "action", "hint": "Saves the arena. Pick it on the rules screen before a game."})
	if tab == "arena" and _edit_index >= 0:
		rows.append({"key": "delete", "label": "DELETE ARENA", "kind": "action",
			"hint": "Removes this arena; teams that played here go back to Modern Arena. Press twice."})
	return rows


func _team_choices(with_none: bool) -> Array:
	var order := Teams.menu_order()
	var v: Array = [-1] if with_none else []
	var n: Array = ["None"] if with_none else []
	for i: int in order:
		v.append(i)
		n.append(Teams.full_name(i))
	return [v, n]


func _choices(key: String) -> Array:
	match key:
		"editing":
			var v := [-1]
			var n := ["New Arena"]
			var saved := Arenas.created()
			for i in saved.size():
				v.append(i)
				n.append(str(saved[i].name))
			return [v, n]
		"style":
			return [Arenas.STYLES, Arenas.STYLE_NAMES]
		"home":
			return _team_choices(true)
		"preview_team":
			return _team_choices(false)
		"seats":
			var v: Array = ["team"]
			var n: Array = ["Home Team"]
			for i in CustomTeams.PALETTE.size():
				v.append(i)
				n.append(CustomTeams.PALETTE[i][0])
			return [v, n]
		"boards":
			var v: Array = ["white"]
			var n: Array = ["White"]
			for i in CustomTeams.PALETTE.size():
				v.append(i)
				n.append(CustomTeams.PALETTE[i][0])
			return [v, n]
		"lights":
			return [Arenas.LIGHTS, Arenas.LIGHT_NAMES]
		"attendance":
			return [Arenas.ATTENDANCE, Arenas.ATTENDANCE.map(func(p: int) -> String: return "Sold Out" if p == 100 else "%d%%" % p)]
		"ribbon", "scoreboard", "banners":
			return [[true, false], ["On", "Off"]]
		"center":
			return [Arenas.CENTERS, Arenas.CENTER_NAMES]
	return [[], []]


func _value_of(key: String) -> Variant:
	match key:
		"editing":
			return _edit_index
		"home":
			return _home
		"preview_team":
			return _preview_team
	return _a.get(key)


func _row_off(key: String) -> bool:
	return key == "delete" and _edit_index < 0


func _show_tab(k: int, quiet := false) -> void:
	_tab = k
	_rows = _tab_rows(TABS[k])
	for it in _items:
		it.queue_free()
	_items.clear()
	_index = 0
	var first_action := _rows.size()
	for i in _rows.size():
		if _rows[i].kind == "action" and first_action == _rows.size():
			first_action = i
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		var action: bool = d.kind == "action"
		var it := MenuItem.new()
		it.text = d.label
		var y := i * (ROW_SIZE.y + ROW_GAP)
		if action:
			y += 12.0 + 6.0 * (i - first_action)
		it.position = ROW_POS + Vector2(0, y)
		it.size = ROW_SIZE if not action else Vector2(420, 46)
		it.value_w = VALUE_W
		it.arrows = d.kind != "text"
		it.intro(0.04 + i * 0.022)
		it.hovered.connect(func() -> void:
			if _index != i and not _busy():
				_select(i))
		it.gui_input.connect(func(e: InputEvent) -> void:
			if not (e is InputEventMouseButton and e.pressed) or _busy():
				return
			if e.button_index == MOUSE_BUTTON_LEFT:
				_select(i, true)
				if _rows[i].kind == "choice":
					_step(i, 1)
				else:
					_accept()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				_select(i, true)
				_step(i, -1))
		_list.add_child(it)
		_items.append(it)
	_refresh()
	if not _items.is_empty():
		_select(0, true)
	if not quiet:
		Sfx.play("click", Vector3.INF, -8.0, 1.1)


func _reshow() -> void:
	var key: String = _rows[_index].key if _index < _rows.size() else ""
	_show_tab(_tab, true)
	for i in _rows.size():
		if _rows[i].key == key:
			_select(i, true)


func _refresh() -> void:
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		var it := _items[i]
		match d.kind:
			"text":
				var v := str(_value_of(d.key))
				it.value = v if v != "" else "-"
			"choice":
				var ch := _choices(d.key)
				var idx: int = ch[0].find(_value_of(d.key))
				var shown := str(ch[1][idx]) if idx >= 0 else str(_value_of(d.key))
				if d.key == "style" and not str(_a.style) in Arenas.READY:
					shown += " (soon)"
				it.value = shown
			"action":
				if d.key == "delete":
					it.text = "PRESS AGAIN TO DELETE" if _warn > 0.0 and _warn_key == "delete" else d.label
		it.modulate.a = 0.4 if _row_off(d.key) else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if _rows[k].kind in ["action", "text"] else ""
		_items[k].glyph_pad = _input.using_pad
	_refresh()
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _step(i: int, dir: int) -> void:
	if i >= _rows.size() or _rows[i].kind != "choice":
		return
	var key: String = _rows[i].key
	var ch := _choices(key)
	var values: Array = ch[0]
	if values.is_empty():
		return
	var cur := values.find(_value_of(key))
	var nv: Variant = values[wrapi(cur + dir, 0, values.size()) if cur >= 0 else 0]
	match key:
		"editing":
			if _dirty() and not _confirm("switch"):
				_items[i].nudge()
				return
			_load_arena(int(nv))
			return
		"style":
			# Only the styles that are built (the rest step past, marked soon).
			var k := cur
			for n in values.size():
				k = wrapi(k + dir, 0, values.size())
				if values[k] in Arenas.READY:
					break
			if values[k] == _a.style:
				_items[i].nudge()
				_say("MORE STYLES ARE COMING")
				Sfx.play("pad", Vector3.INF, -8.0)
				return
			_a.style = values[k]
		"home":
			_home = int(nv)
		"preview_team":
			_preview_team = int(nv)
		_:
			_a[key] = nv
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_rebuild_in = REBUILD_DELAY
	_refresh()


func _accept() -> void:
	if _index >= _rows.size():
		return
	var d: Dictionary = _rows[_index]
	match d.kind:
		"text":
			_start_typing(d.key, int(d.get("max", 24)))
		"choice":
			_step(_index, 1)
		"action":
			match d.key:
				"save":
					_save()
				"delete":
					if _edit_index < 0:
						return
					if not _confirm("delete"):
						_items[_index].nudge()
						_refresh()
						return
					Arenas.delete_arena(_edit_index)
					_say("ARENA DELETED")
					Sfx.play("glove", Vector3.INF, -4.0)
					_load_arena(-1)


func _save() -> void:
	_a.name = str(_a.name).strip_edges()
	if _a.name == "":
		_nope("THE ARENA NEEDS A NAME")
		return
	if _home >= 0 and not Arenas.can_be_home(_a, _home):
		_nope("OUTDOOR RINKS ARE HOME TO CREATED TEAMS ONLY")
		return
	if _edit_index < 0 and Arenas.created().size() >= Arenas.MAX_ARENAS:
		_nope("NO ROOM FOR MORE ARENAS (%d)" % Arenas.MAX_ARENAS)
		return
	var was_new := _edit_index < 0
	_edit_index = Arenas.save_arena(_a, _edit_index)
	_a = Arenas.created()[_edit_index].duplicate(true)
	if _saved_home >= 0 and _saved_home != _home and Arenas.home_id(_saved_home) == str(_a.id):
		Arenas.set_home(_saved_home, "")
	if _home >= 0:
		Arenas.set_home(_home, str(_a.id))
	_saved_home = _home
	_saved = _snapshot()
	Sfx.play("glove", Vector3.INF, -4.0)
	_say("ARENA BUILT" if was_new else "SAVED")
	_reshow()


func _load_arena(i: int) -> void:
	_edit_index = i
	var saved := Arenas.created()
	_a = saved[i].duplicate(true) if i >= 0 and i < saved.size() else Arenas.blank()
	_home = -1
	if i >= 0:
		var t := Arenas.tenants(str(_a.id))
		_home = t[0] if not t.is_empty() else -1
		if _home >= 0:
			_preview_team = _home
	_saved_home = _home
	_saved = _snapshot()
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_rebuild_in = REBUILD_DELAY
	_reshow()


func _say(text: String) -> void:
	_toast = text
	_toast_t = 2.6


func _nope(text: String) -> void:
	_say(text)
	if _index < _items.size():
		_items[_index].nudge()
	Sfx.play("pad", Vector3.INF, -6.0)


# --- Typing -------------------------------------------------------------------------

func _start_typing(key: String, max_len: int) -> void:
	_typing = key
	var it := _items[_index]
	var start := str(_a.get(key, ""))
	if _input.using_pad:
		_kb.open(_input, it.text, start, max_len, false)
		_kb.position = Vector2((_canvas.size.x - _kb.size.x) * 0.5, 210.0)
		Sfx.play("click", Vector3.INF, -8.0, 1.2)
		return
	_typer.max_length = max_len
	_typer.text = start
	_typer.size = Vector2(VALUE_W + 20.0, ROW_SIZE.y + 4.0)
	_typer.position = it.position + Vector2(ROW_SIZE.x - VALUE_W - 30.0 + 26.0, -2.0)
	_typer.visible = true
	_typer.grab_focus()
	_typer.select_all()
	Sfx.play("click", Vector3.INF, -8.0, 1.2)


func _end_typing(keep: bool) -> void:
	if _typing == "" or not _typer.visible:
		return
	_typer.visible = false
	_typer.release_focus()
	_finish_text(_typer.text.strip_edges() if keep else null)


func _finish_text(value: Variant) -> void:
	if _typing == "":
		return
	var key := _typing
	_typing = ""
	_quiet_until = Time.get_ticks_msec() + 200
	if value != null:
		_a[key] = str(value)
		Sfx.play("glove", Vector3.INF, -8.0)
	_refresh()


func _back() -> void:
	if _dirty() and not _confirm("leave"):
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	GameSettings.menu_list = "customize"
	GameSettings.menu_select = MENU_SELECT
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


# --- Preview ------------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(_stage)
	# The game's own lighting (the menus' haze would hide the building).
	var match_scene: Node = (load("res://scenes/match/Match.tscn") as PackedScene).instantiate()
	var env: WorldEnvironment = match_scene.get_node("WorldEnvironment").duplicate()
	var sun: DirectionalLight3D = match_scene.get_node("Sun").duplicate()
	match_scene.free()
	_stage.add_child(env)
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	GameSettings.sun_shadow_mode(sun)
	_stage.add_child(sun)
	var rink: Rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	rink.arena_spec = _a.duplicate(true)
	_stage.add_child(rink)
	_arena = {"rink": rink}
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 400.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_stage.add_child(_cam)
	_dress()


func _rebuild() -> void:
	_rebuild_in = -1.0
	(_arena.rink as Rink).rebuild_arena(_a.duplicate(true))
	_dress()


func _dress() -> void:
	var rink := _arena.rink as Rink
	var team := _home if _home >= 0 else _preview_team
	if rink.arena:
		rink.arena.set_teams(team, -1)
	rink.set_center_logo(MatchDirector.center_logo(_a, team))


## A slow drift round the building from high over one corner, the rink and the stands
## in view.
func _place_camera() -> void:
	if _cam == null:
		return
	var a := _time * 0.06 + 0.6
	var look := Vector3(0, 6.0, 0)
	var pos := Vector3(sin(a) * 30.0, 17.0, cos(a) * 42.0)
	_cam.look_at_from_position(pos, look)
	var half_w := tan(deg_to_rad(_cam.fov * 0.5)) * pos.distance_to(look) * get_viewport_rect().size.aspect()
	_cam.h_offset = -0.28 * half_w


# --- Drawing ------------------------------------------------------------------------

func _draw_tabs() -> void:
	var pad := _input.using_pad
	var gy := (TAB_SIZE.y - 30.0) * 0.5
	MenuStyle.draw_glyph(_tabs, Vector2(-14, gy), "L1" if pad else "Q", false, 30.0)
	for k in TABS.size():
		var r := Rect2(Vector2(30.0 + k * TAB_SIZE.x, 0), TAB_SIZE - Vector2(12, 0))
		var on := k == _tab
		MenuStyle.draw_slant(_tabs, Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.35), 16.0)
		MenuStyle.draw_slant(_tabs, r, MenuStyle.RED if on else Color(0.06, 0.08, 0.15, 0.85), 16.0)
		if on:
			_tabs.draw_rect(Rect2(r.position + Vector2(16, r.size.y - 4), Vector2(r.size.x - 16, 4)), Color(1, 1, 1, 0.85))
		var name: String = TAB_NAMES[k]
		var tw := MenuStyle.text_width(name, 22)
		MenuStyle.draw_bold(_tabs, r.position + Vector2((r.size.x - tw) * 0.5 + 8, 29), name, 22,
				Color.WHITE if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	MenuStyle.draw_glyph(_tabs, Vector2(30.0 + TABS.size() * TAB_SIZE.x + 6.0, gy), "R1" if pad else "E", false, 30.0)


func _draw_card() -> void:
	var r := CARD
	r.position.x = _canvas.size.x - r.size.x - 50.0
	MenuStyle.draw_slant(_card, Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.35), 22.0)
	MenuStyle.draw_slant(_card, r, Color(0.03, 0.05, 0.1, 0.85), 22.0)
	MenuStyle.draw_slant(_card, Rect2(r.position, Vector2(r.size.x, 5)), MenuStyle.RED, 2.0)
	var x := r.position.x + 30.0
	var name := str(_a.name).to_upper() if str(_a.name) != "" else "NEW ARENA"
	var fs := 32
	while fs > 16 and MenuStyle.text_width(name, fs) > r.size.x - 60.0:
		fs -= 2
	MenuStyle.draw_bold(_card, Vector2(x, r.position.y + 50), name, fs, Color.WHITE, 0, MenuStyle.INK)
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, r.position.y + 82), Arenas.style_name(str(_a.style)).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.86, 0.45))
	var home := "NO HOME TEAM" if _home < 0 else "HOME OF THE " + str(Teams.team(_home).name).to_upper()
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, r.position.y + 110), home, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60.0, 16, MenuStyle.DIM)
	if _dirty():
		_card.draw_string(MenuStyle.font(0.12), Vector2(r.end.x - 175.0, r.end.y + 26), "UNSAVED CHANGES",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.8, 0.45))
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := MenuStyle.text_width(_toast, 24)
		var tp := Vector2(r.end.x - tw - 20.0, r.end.y + 72)
		MenuStyle.draw_slant(_card, Rect2(tp - Vector2(22, 31), Vector2(tw + 44, 42)), Color(MenuStyle.RED, 0.9 * a), 14.0)
		MenuStyle.draw_bold(_card, tp, _toast, 24, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)


func _draw_footer() -> void:
	var hint := ""
	if _index < _rows.size():
		hint = _rows[_index].hint
	if _warn > 0.0:
		match _warn_key:
			"leave":
				hint = "You have unsaved changes. Press %s again to leave without saving." % _input.back_label()
			"switch":
				hint = "You have unsaved changes. Press again to switch and drop them."
			"delete":
				hint = "Press %s again to delete this arena." % _input.accept_label()
	elif _typing != "" and _kb.visible:
		hint = "Spell it out on the keyboard, then DONE (or %s)." % MenuStyle.pad_label("START")
	elif _typing != "":
		hint = "Type, then Enter to keep it or Esc to cancel."
	var prompts := []
	if _typing == "" and _index < _rows.size():
		match str(_rows[_index].kind):
			"text":
				prompts.append([_input.accept_label(), "TYPE"])
			"action":
				prompts.append([_input.accept_label(), "SELECT"])
			_:
				prompts.append([_input.accept_label(), "CHANGE"])
	prompts.append([_input.back_label(), "BACK"])
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint, prompts, _input.using_pad)


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _enter_tree() -> void:
	var shot := _arg("shot", "")
	if shot != "":
		_take_shot.call_deferred(shot, float(_arg("wait", "4.0")))


func _take_shot(path: String, wait: float) -> void:
	if _arg("save", "") != "":
		await get_tree().create_timer(0.3).timeout
		if _arg("home", "") != "":
			_home = int(_arg("home", "-1"))
		_save()
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
