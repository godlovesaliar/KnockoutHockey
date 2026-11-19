extends Control
## CUSTOMIZE > CREATE TEAM: tabs of settings bars on the left (TEAM, COLORS, BADGE,
## BADGE COLORS), and on the right the badge on a card over a player in the uniform,
## standing on center ice with the badge painted there too.
##
## Up / down picks a row, left / right changes it, accept types a name or runs an action
## row (on a pad, PadKeyboard comes up). L1 / R1 (Q / E) or a click switches tabs.
## Saving writes the team (CustomTeams) and its badge as a PNG; from then on it's in
## every team list. FILL ROSTER signs the best free agents to it (Edit Roster does the
## rest). Back: the CUSTOMIZE menu (press twice to leave unsaved changes).
##
## `-- shot=<png> [wait=<s>] [tab=team|colors|badge|badge_colors] [sel=<n>] [edit=<n>]
## [<team key>=<value> ...] [b_<badge key>=<value> ...] [save=1]` saves a screenshot and
## quits (save=1 saves the team first, as the SAVE TEAM row does).

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const MENU_SELECT := 1          ## CREATE TEAM's place in the CUSTOMIZE list
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")

const TABS := ["team", "colors", "badge", "badge_colors"]
const TAB_NAMES := ["TEAM", "COLORS", "BADGE", "BADGE COLORS"]
const TAB_POS := Vector2(40, 152)
const TAB_SIZE := Vector2(190, 44)
const ROW_POS := Vector2(60, 220)
const ROW_SIZE := Vector2(720, 40)
const ROW_GAP := 4.0
const VALUE_W := 300.0
const CARD := Rect2(1030, 40, 520, 300)
const SPOT := Vector3(-3.0, 0.0, 4.0)
const REBUILD_DELAY := 0.15
const LEAVE_WARN := 3.0
const BADGE_PX := 512

var _t := {}                ## the team being edited (CustomTeams format)
var _edit_index := -1       ## which saved team (-1: a new one)
var _saved := ""
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
var _leave_warn := 0.0
var _delete_armed := false
var _toast := ""
var _toast_t := 0.0
var _leaving := false
var _time := 0.0

var _badge_vp: SubViewport
var _badge_draw: Control
var _stage: Node3D
var _arena := {}
var _cam: Camera3D
var _skater: Skater
var _rebuild_in := -1.0


func _ready() -> void:
	Sfx.play_music()
	_t = CustomTeams.blank()
	var edit := int(_arg("edit", "-1"))
	if edit >= 0 and edit < CustomTeams.all().size():
		_edit_index = edit
		_t = CustomTeams.all()[edit].duplicate(true)
	_t.home_arena = Arenas.home_id(Teams.LIST.size() + _edit_index) if _edit_index >= 0 else "modern"
	_saved = _snapshot()
	for k: String in ["city", "name", "abbr", "conference", "design", "pants", "helmet", "primary", "secondary", "accent"]:
		var a := _arg(k, "")
		if a != "":
			_t[k] = int(a) if _t[k] is int else a
	for k: String in _t.badge:
		var a := _arg("b_" + k, "")
		if a != "":
			_t.badge[k] = (a == "true") if _t.badge[k] is bool else (int(a) if _t.badge[k] is int else a)
	_t.colors = CustomTeams.uniform_colors(_t)
	_build_stage()
	_build_badge_viewport()

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
	_header.draw.connect(func() -> void: MenuStyle.draw_tag(_header, Vector2(60, 30), "CUSTOMIZE", "CREATE TEAM"))
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

	_show_tab(maxi(0, TABS.find(_arg("tab", "team"))), true)
	if _arg("sel", "") != "" and not _items.is_empty():
		_select(clampi(int(_arg("sel", "0")), 0, _items.size() - 1), true)
	_rebuild_in = 0.4   # after the badge viewport has drawn


func _process(delta: float) -> void:
	_time += delta
	_leave_warn = maxf(0.0, _leave_warn - delta)
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
	var copy := _t.duplicate(true)
	copy.erase("colors")
	return JSON.stringify(copy)


func _dirty() -> bool:
	return _snapshot() != _saved


func _changed() -> void:
	_t.colors = CustomTeams.uniform_colors(_t)
	_badge_draw.queue_redraw()
	_rebuild_in = REBUILD_DELAY


# --- Rows ---------------------------------------------------------------------------

func _tab_rows(tab: String) -> Array:
	var rows := []
	match tab:
		"team":
			rows = [
				{"key": "editing", "label": "EDITING", "kind": "choice",
					"hint": "Make a new team, or pick a saved one to change. Unsaved changes are lost when you switch."},
				{"key": "city", "label": "CITY", "kind": "text", "max": 18,
					"hint": "Where they play. Optional: leave it empty for a team known by its name alone."},
				{"key": "name", "label": "TEAM NAME", "kind": "text", "max": 16,
					"hint": "The nickname: Whalers, Geese, Quahogs..."},
				{"key": "abbr", "label": "CODE", "kind": "text", "max": 4,
					"hint": "2 to 4 letters for the scoreboard and rosters. Must not be another team's."},
				{"key": "conference", "label": "CONFERENCE", "kind": "choice",
					"hint": "Which conference they play in (and where they come up in team lists)."},
				{"key": "home_arena", "label": "HOME ARENA", "kind": "choice",
					"hint": "Where they play home games: any arena, the outdoor rink too. Saved with the team."},
			]
		"colors":
			rows = [
				{"key": "primary", "label": "PRIMARY", "kind": "choice", "hint": "The home jersey's color."},
				{"key": "secondary", "label": "SECONDARY", "kind": "choice", "hint": "Stripes and the numbers."},
				{"key": "accent", "label": "ACCENT", "kind": "choice", "hint": "Number outlines, and a third color for the badge."},
				{"key": "design", "label": "JERSEY STYLE", "kind": "choice", "hint": "The stripes on the hem, sleeves and socks."},
				{"key": "pants", "label": "PANTS", "kind": "choice", "hint": "Pants color."},
				{"key": "helmet", "label": "HELMET", "kind": "choice", "hint": "Helmet color."},
			]
		"badge":
			rows = [
				{"key": "b_shape", "label": "SHAPE", "kind": "choice", "hint": "The badge's outline. None leaves the icon and letters on their own."},
				{"key": "b_border", "label": "BORDER", "kind": "choice", "hint": "The edge round the shape."},
				{"key": "b_pattern", "label": "PATTERN", "kind": "choice", "hint": "A band, sash or split across the shape."},
				{"key": "b_icon", "label": "ICON", "kind": "choice", "hint": "The emblem: a simple shape, or a drawn logo (Wolverine to Donut) you can recolor under BADGE COLORS."},
				{"key": "b_layout", "label": "LAYOUT", "kind": "choice", "hint": "Icon over letters, letters alone, or the icon alone."},
				{"key": "b_text", "label": "LETTERS", "kind": "text", "max": BadgeLogo.TEXT_MAX,
					"hint": "Up to %d letters. Empty uses the team's code." % BadgeLogo.TEXT_MAX},
				{"key": "b_font", "label": "LETTERING", "kind": "choice", "hint": "The letters' typeface."},
				{"key": "b_italic", "label": "ITALIC", "kind": "choice", "hint": "Lean the letters forward."},
			]
		"badge_colors":
			rows = [
				{"key": "b_fill", "label": "SHAPE COLOR", "kind": "choice", "hint": "Inside the shape."},
				{"key": "b_edge", "label": "BORDER COLOR", "kind": "choice", "hint": "The border."},
				{"key": "b_pattern_color", "label": "PATTERN COLOR", "kind": "choice", "hint": "The band, sash or split."},
				{"key": "b_icon_color", "label": "ICON COLOR", "kind": "choice", "hint": "The emblem."},
				{"key": "b_logo_navy", "label": "LOGO: NAVY", "kind": "choice", "hint": "The drawn logo's navy parts."},
				{"key": "b_logo_red", "label": "LOGO: RED", "kind": "choice", "hint": "The drawn logo's red parts."},
				{"key": "b_logo_gold", "label": "LOGO: GOLD", "kind": "choice", "hint": "The drawn logo's gold parts."},
				{"key": "b_logo_white", "label": "LOGO: WHITE", "kind": "choice", "hint": "The drawn logo's white parts."},
				{"key": "b_text_color", "label": "LETTER COLOR", "kind": "choice", "hint": "The letters."},
				{"key": "b_outline", "label": "OUTLINE COLOR", "kind": "choice", "hint": "The edge round the icon and letters, and the drawn logo's black lines."},
			]
	rows.append({"key": "save", "label": "SAVE TEAM", "kind": "action",
		"hint": "Saves the team and its badge. It shows up in every team list."})
	if tab == "team" and _edit_index >= 0:
		rows.append({"key": "fill", "label": "FILL ROSTER", "kind": "action",
			"hint": "Signs the best free agents until the roster has a full lineup. Edit Roster does the rest."})
		rows.append({"key": "delete", "label": "DELETE TEAM", "kind": "action",
			"hint": "Removes this team; its players go to Free Agency. Press twice to confirm."})
	return rows


func _slot_choices() -> Array:
	return [CustomTeams.SLOTS, CustomTeams.SLOT_NAMES]


## [values, names] for a choice row.
func _choices(key: String) -> Array:
	match key:
		"editing":
			var v := [-1]
			var n := ["New Team"]
			var saved := CustomTeams.all()
			for i in saved.size():
				v.append(i)
				n.append(("%s %s" % [saved[i].city, saved[i].name]).strip_edges())
			return [v, n]
		"conference":
			return [Teams.CONFERENCES, Teams.CONFERENCES]
		"home_arena":
			var arenas := Arenas.all()
			return [arenas.map(func(a: Dictionary) -> String: return str(a.id)),
					arenas.map(func(a: Dictionary) -> String: return str(a.name))]
		"primary", "secondary", "accent":
			var r := range(CustomTeams.PALETTE.size())
			return [r, r.map(func(i: int) -> String: return CustomTeams.PALETTE[i][0])]
		"design":
			return [CustomTeams.DESIGN_NAMES.keys(), CustomTeams.DESIGN_NAMES.values()]
		"pants", "helmet":
			return _slot_choices()
		"b_shape":
			return [BadgeLogo.SHAPES, BadgeLogo.SHAPE_NAMES]
		"b_border":
			return [BadgeLogo.BORDERS, BadgeLogo.BORDER_NAMES]
		"b_pattern":
			return [BadgeLogo.PATTERNS, BadgeLogo.PATTERN_NAMES]
		"b_icon":
			return [BadgeLogo.ICONS, BadgeLogo.ICON_NAMES]
		"b_layout":
			return [BadgeLogo.LAYOUTS, BadgeLogo.LAYOUT_NAMES]
		"b_font":
			var r := range(BadgeLogo.FONTS.size())
			return [r, r.map(func(i: int) -> String: return BadgeLogo.FONTS[i][0])]
		"b_italic":
			return [[true, false], ["Yes", "No"]]
		"b_fill", "b_edge", "b_pattern_color", "b_icon_color", "b_text_color", "b_outline", 				"b_logo_navy", "b_logo_red", "b_logo_gold", "b_logo_white":
			return _slot_choices()
	return [[], []]


func _value_of(key: String) -> Variant:
	if key == "editing":
		return _edit_index
	if key.begins_with("b_"):
		return _t.badge.get(key.substr(2))
	return _t.get(key)


func _set_value(key: String, v: Variant) -> void:
	if key.begins_with("b_"):
		_t.badge[key.substr(2)] = v
	else:
		_t[key] = v


func _row_off(key: String) -> bool:
	match key:
		"b_border", "b_pattern", "b_fill", "b_edge", "b_pattern_color":
			return _t.badge.shape == "none" or (key == "b_edge" and _t.badge.border == "none") \
					or (key == "b_pattern_color" and _t.badge.pattern == "none")
		"b_icon_color":
			return _t.badge.icon == "none" or _t.badge.layout == "text" or BadgeLogo.is_mascot(_t.badge.icon)
		"b_logo_navy", "b_logo_red", "b_logo_gold", "b_logo_white":
			return not BadgeLogo.is_mascot(_t.badge.icon) or _t.badge.layout == "text"
		"b_text", "b_font", "b_italic", "b_text_color":
			return _t.badge.layout == "icon"
		"fill", "delete":
			return _edit_index < 0
	return false


func _show_tab(k: int, quiet := false) -> void:
	_tab = k
	_delete_armed = false
	_rows = _tab_rows(TABS[k])
	for it in _items:
		it.queue_free()
	_items.clear()
	_index = 0
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		var action: bool = d.kind == "action"
		var it := MenuItem.new()
		it.text = d.label
		var y := i * (ROW_SIZE.y + ROW_GAP)
		if action:
			y += 12.0 + 6.0 * (i - _first_action())
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


func _first_action() -> int:
	for i in _rows.size():
		if _rows[i].kind == "action":
			return i
	return _rows.size()


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
				it.value = v if v != "" else ("(" + str(_t.abbr) + ")" if d.key == "b_text" and str(_t.abbr) != "" else "-")
			"choice":
				var ch := _choices(d.key)
				var idx: int = ch[0].find(_value_of(d.key))
				it.value = str(ch[1][idx]) if idx >= 0 else str(_value_of(d.key))
			"action":
				if d.key == "delete":
					it.text = "PRESS AGAIN TO DELETE" if _delete_armed else d.label
				elif d.key == "fill" and _edit_index >= 0:
					it.text = "FILL ROSTER (%d PLAYERS)" % Rosters.for_team(str(_t.abbr)).size()
		it.modulate.a = 0.4 if _row_off(d.key) else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	_delete_armed = false
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if _rows[k].kind in ["action", "text"] else ""
		_items[k].glyph_pad = _input.using_pad
	_refresh()
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _step(i: int, dir: int) -> void:
	if i >= _rows.size():
		return
	var d: Dictionary = _rows[i]
	if d.kind != "choice":
		return
	if _row_off(d.key):
		_items[i].nudge()
		return
	var ch := _choices(d.key)
	var values: Array = ch[0]
	if values.is_empty():
		return
	var cur := values.find(_value_of(d.key))
	var nv: Variant = values[wrapi(cur + dir, 0, values.size()) if cur >= 0 else 0]
	if d.key == "editing":
		_load_team(int(nv))
		return
	_set_value(d.key, nv)
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_changed()
	_refresh()


func _accept() -> void:
	if _index >= _rows.size():
		return
	var d: Dictionary = _rows[_index]
	match d.kind:
		"text":
			if not _row_off(d.key):
				_start_typing(d.key, int(d.get("max", 16)))
		"choice":
			_step(_index, 1)
		"action":
			match d.key:
				"save":
					_save()
				"fill":
					if _edit_index < 0:
						return
					if _dirty():
						_nope("SAVE THE TEAM FIRST")
						return
					var n := Rosters.fill_from_free_agency(str(_t.abbr))
					if n == 0:
						_nope("ROSTER ALREADY FULL" if Rosters.free_agents().size() > 0 else "FREE AGENCY IS EMPTY")
						return
					_say("SIGNED %d FREE AGENT%s" % [n, "" if n == 1 else "S"])
					Sfx.play("glove", Vector3.INF, -4.0)
					_refresh()
				"delete":
					if not _delete_armed:
						_delete_armed = true
						_items[_index].nudge()
						Sfx.play("pad", Vector3.INF, -6.0)
						_refresh()
						return
					CustomTeams.delete_team(_edit_index)
					Sfx.play("glove", Vector3.INF, -4.0)
					_say("TEAM DELETED")
					_load_team(-1)
					_show_tab(0, true)


func _save() -> void:
	_t.name = str(_t.name).strip_edges()
	_t.city = str(_t.city).strip_edges()
	_t.abbr = str(_t.abbr).strip_edges().to_upper()
	if _t.name == "":
		_nope("THE TEAM NEEDS A NAME")
		return
	var why := CustomTeams.abbr_problem(_t.abbr, str(_t.id))
	if why != "":
		_nope(why)
		return
	if _edit_index < 0 and CustomTeams.all().size() >= CustomTeams.MAX_TEAMS:
		_nope("THE LEAGUE IS FULL (%d CREATED TEAMS)" % CustomTeams.MAX_TEAMS)
		return
	if str(_t.id) == "":
		_t.id = CustomTeams.new_id()
	_leaving = true   # (no input while the badge is drawn)
	_badge_draw.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(CustomTeams.LOGO_DIR)
	var img := _badge_vp.get_texture().get_image()
	img.save_png(CustomTeams.logo_path(str(_t.id)))
	var was_new := _edit_index < 0
	var arena := str(_t.get("home_arena", "modern"))
	_t.erase("home_arena")
	_edit_index = CustomTeams.save_team(_t, _edit_index)
	Arenas.set_home(Teams.LIST.size() + _edit_index, arena)
	_t = CustomTeams.all()[_edit_index].duplicate(true)
	_t.home_arena = arena
	_saved = _snapshot()
	_leaving = false
	Sfx.play("glove", Vector3.INF, -4.0)
	_say("TEAM CREATED: FILL ITS ROSTER ON THE TEAM TAB" if was_new else "SAVED")
	_reshow()


func _load_team(i: int) -> void:
	_edit_index = i
	var saved := CustomTeams.all()
	_t = saved[i].duplicate(true) if i >= 0 and i < saved.size() else CustomTeams.blank()
	_t.home_arena = Arenas.home_id(Teams.LIST.size() + i) if i >= 0 else "modern"
	_saved = _snapshot()
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_changed()
	_reshow()


func _say(text: String) -> void:
	_toast = text
	_toast_t = 2.6


func _nope(text: String) -> void:
	_say(text)
	_items[_index].nudge()
	Sfx.play("pad", Vector3.INF, -6.0)


# --- Typing -------------------------------------------------------------------------

func _start_typing(key: String, max_len: int) -> void:
	_typing = key
	var it := _items[_index]
	var start := str(_value_of(key))
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
		var text: String = value
		if key in ["abbr", "b_text"]:
			# Codes and badge letters: capitals, letters and digits only.
			var clean := ""
			for c in text.to_upper():
				if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
					clean += c
			text = clean
		_set_value(key, text)
		_changed()
		Sfx.play("glove", Vector3.INF, -8.0)
	_refresh()


# --- Leaving ------------------------------------------------------------------------

func _back() -> void:
	if _dirty() and _leave_warn <= 0.0:
		_leave_warn = LEAVE_WARN
		Sfx.play("pad", Vector3.INF, -6.0)
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	GameSettings.menu_list = "customize"
	GameSettings.menu_select = MENU_SELECT
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


# --- Preview ------------------------------------------------------------------------

## The badge drawn at BADGE_PX into a transparent viewport: the jersey crest, center
## ice, and (on save) the logo PNG.
func _build_badge_viewport() -> void:
	_badge_vp = SubViewport.new()
	_badge_vp.size = Vector2i(BADGE_PX, BADGE_PX)
	_badge_vp.transparent_bg = true
	_badge_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_badge_vp.disable_3d = true
	add_child(_badge_vp)
	_badge_draw = Control.new()
	_badge_draw.size = Vector2(BADGE_PX, BADGE_PX)
	_badge_draw.draw.connect(func() -> void:
		BadgeLogo.draw(_badge_draw, Rect2(Vector2.ZERO, Vector2(BADGE_PX, BADGE_PX)), _t.badge,
				CustomTeams.slot_colors(_t), _badge_text()))
	_badge_vp.add_child(_badge_draw)


func _badge_text() -> String:
	var a := str(_t.abbr)
	return a if a != "" else "NEW"


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(_stage)
	_arena = MenuArena.build(_stage, SPOT)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.attributes = MenuArena.camera_attributes()
	_stage.add_child(_cam)


## A player in the team's uniform with the badge on the chest, and the badge at center ice.
func _rebuild() -> void:
	_rebuild_in = -1.0
	var img := _badge_vp.get_texture().get_image()
	var crest: Texture2D = null
	if img != null and not img.is_empty() and not img.is_invisible():
		img.generate_mipmaps()
		crest = ImageTexture.create_from_image(img)
	(_arena.rink as Rink).set_center_logo(crest)
	if _skater != null:
		_skater.queue_free()
		_skater = null
	var s: Skater = SKATER_SCENE.instantiate()
	var home := Teams.uniform_of(_t, _t, false)
	var road := Teams.uniform_of(_t, _t, true)
	s.uniform = home
	s.team_color = home.jersey
	s.club_colors = [home.jersey, road.jersey]
	if crest:
		s.crest = crest
	var p := CustomPlayers.blank()
	p.last = str(_t.name).to_upper() if str(_t.name) != "" else ""
	p.number = 19
	p.facial_hair = "beard"
	CustomPlayers.apply(s, p)
	s.puck = _arena.puck
	s.rink = _arena.rink
	s.fatigue_enabled = false
	_stage.add_child(s)
	s.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _tt: float) -> void: pass)
	s.teammates = [s]
	s.place(SPOT, Vector3.BACK)
	if s.visual != null:
		s.visual.display_pose = "side"
		if s.visual.face != null:
			s.visual.face.look_at_camera = true
		s.visual.snap()
	_skater = s


func _place_camera() -> void:
	if _cam == null:
		return
	var look := SPOT + Vector3(0, 0.95, 0)
	var yaw := sin(_time * 0.25) * 0.12
	var pitch := 0.1
	var d := 5.6
	_cam.look_at_from_position(look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d, look)
	# The player sits under the card, right of the rows.
	var half_h := tan(deg_to_rad(_cam.fov * 0.5)) * d
	var half_w := half_h * get_viewport_rect().size.aspect()
	_cam.h_offset = -0.6 * half_w
	_cam.v_offset = 0.3 * half_h


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
		var fs := 22 if name.length() < 10 else 18
		var tw := MenuStyle.text_width(name, fs)
		MenuStyle.draw_bold(_tabs, r.position + Vector2((r.size.x - tw) * 0.5 + 8, 29), name, fs,
				Color.WHITE if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	MenuStyle.draw_glyph(_tabs, Vector2(30.0 + TABS.size() * TAB_SIZE.x + 6.0, gy), "R1" if pad else "E", false, 30.0)


## Top right: the badge big, the team's full name and code, conference and roster size.
func _draw_card() -> void:
	var r := CARD
	r.position.x = _canvas.size.x - r.size.x - 50.0
	var colors := CustomTeams.slot_colors(_t)
	MenuStyle.draw_slant(_card, Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.35), 22.0)
	MenuStyle.draw_slant(_card, r, Color(0.03, 0.05, 0.1, 0.85), 22.0)
	MenuStyle.draw_slant(_card, Rect2(r.position, Vector2(r.size.x, 6)), colors[0], 2.0)
	var bs := 210.0
	BadgeLogo.draw(_card, Rect2(r.position + Vector2(28, 30), Vector2(bs, bs)), _t.badge, colors, _badge_text())
	var x := r.position.x + bs + 56.0
	var w := r.end.x - x - 20.0
	var city := str(_t.city).to_upper()
	var name := str(_t.name).to_upper()
	if name == "":
		name = "NEW TEAM"
	if city != "":
		_card.draw_string(MenuStyle.font(0.12), Vector2(x, r.position.y + 64), city, HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color(1, 0.86, 0.86))
	var fs := 40
	while fs > 18 and MenuStyle.text_width(name, fs) > w:
		fs -= 2
	MenuStyle.draw_bold(_card, Vector2(x, r.position.y + 64 + 12 + fs), name, fs, Color.WHITE, 0, MenuStyle.INK)
	var abbr := str(_t.abbr) if str(_t.abbr) != "" else "---"
	var y := r.position.y + 170.0
	_card.draw_rect(Rect2(x, y - 28, MenuStyle.text_width(abbr, 26) + 24, 38), colors[0])
	MenuStyle.draw_bold(_card, Vector2(x + 10, y), abbr, 26, colors[1], 0, MenuStyle.INK, 0.2, false)
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, y + 40), "%s CONFERENCE" % str(_t.conference).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MenuStyle.DIM)
	var roster := "NOT SAVED YET" if _edit_index < 0 else "%d PLAYERS SIGNED" % Rosters.for_team(str(_t.abbr)).size()
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, y + 66), roster, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(1, 0.86, 0.45))
	# The three team colors as chips.
	for i in 3:
		var cr := Rect2(x + i * 54.0, r.end.y - 48, 44, 24)
		_card.draw_rect(cr, colors[i])
		_card.draw_rect(cr, Color(1, 1, 1, 0.5), false, 1.0)
	if _dirty():
		_card.draw_string(MenuStyle.font(0.12), Vector2(r.end.x - 175.0, r.end.y + 26), "UNSAVED CHANGES",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.8, 0.45))
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := MenuStyle.text_width(_toast, 24)
		var tp := Vector2(r.end.x - tw - 20.0, r.end.y + 74)
		MenuStyle.draw_slant(_card, Rect2(tp - Vector2(22, 31), Vector2(tw + 44, 42)), Color(MenuStyle.RED, 0.9 * a), 14.0)
		MenuStyle.draw_bold(_card, tp, _toast, 24, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)


func _draw_footer() -> void:
	var hint := ""
	if _index < _rows.size():
		hint = _rows[_index].hint
	if _leave_warn > 0.0:
		hint = "You have unsaved changes. Press %s again to leave without saving." % _input.back_label()
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
		_take_shot.call_deferred(shot, float(_arg("wait", "3.0")))


func _take_shot(path: String, wait: float) -> void:
	if _arg("save", "") != "":
		await get_tree().create_timer(0.6).timeout
		await _save()
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
