extends Control
## CUSTOMIZE > CREATE PLAYER: tabs of settings bars on the left (PLAYER, SKILLS, LOOK,
## GEAR), the player standing on the ice on the right, rebuilt as you change them, with a
## card showing their number, name, position and overall.
##
## Up / down picks a row, left / right changes it; accept edits a name or runs an action
## row. Names: on a pad the on-screen keyboard (PadKeyboard) comes up; from a keyboard you
## type into the row (Enter keeps it, Esc drops it). L1 / R1 (Q / E) or a click switches
## tabs. The camera moves to what the row changes: the face for looks, the back for the
## name and number, the blade for stick and tape. Drag with the mouse to turn around the
## player. Saved players go to Free Agency (CustomPlayers), where Edit Roster will sign
## them to teams. Back: the CUSTOMIZE menu (press it twice to leave unsaved changes).
##
## `-- shot=<png> [wait=<s>] [tab=player|skills|look|gear] [sel=<n>] [kb=1] [<player key>=<value> ...]`
## (kb=1 opens the pad keyboard on the selected row)
## saves a screenshot and quits (e.g. `stick=home_away tape=team gender=Female`).

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

const TABS := ["player", "skills", "look", "gear"]
const TAB_NAMES := ["PLAYER", "SKILLS", "LOOK", "GEAR"]

const TAB_POS := Vector2(40, 152)
const TAB_SIZE := Vector2(170, 44)
const ROW_POS := Vector2(60, 220)
const ROW_SIZE := Vector2(720, 40)
const ROW_GAP := 4.0
const VALUE_W := 300.0
const CARD := Rect2(1030, 40, 520, 150)
const SPOT := Vector3(-3.0, 0.0, 4.0)   ## where the player stands (clear of the center dot and logo)
const REBUILD_DELAY := 0.12      ## s after the last change before the player is rebuilt
const LEAVE_WARN := 3.0          ## s the "unsaved changes" warning waits for a second back

## Camera framings: what it looks at (see _cam_target), how far back, how high it looks
## down from (rad), and how far the subject sits right of center (share of half the width).
const SHOTS := {
	"body": {"dist": 4.6, "pitch": 0.06, "shift": 0.5},
	"face": {"dist": 1.1, "pitch": 0.02, "shift": 0.5},
	"head": {"dist": 1.3, "pitch": 0.12, "shift": 0.5},
	"back": {"dist": 2.3, "pitch": 0.1, "shift": 0.5, "yaw": PI},
	"stick": {"dist": 1.05, "pitch": 0.55, "shift": 0.45},
}

var _p := {}                ## the player being edited (CustomPlayers format)
var _edit_index := -1       ## which saved player this is (-1: a new one)
var _saved := ""            ## _p as JSON when last saved or loaded (unsaved changes test)
var _team := 0              ## preview jersey (Teams.LIST index)
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
var _typing := ""           ## the key being typed into ("" = not typing)
var _quiet_until := 0       ## msec: menu input ignored until then (after typing)
var _leave_warn := 0.0
var _was_new := false
var _delete_armed := false
var _toast := ""
var _toast_t := 0.0
var _leaving := false
var _t := 0.0

var _stage: Node3D
var _arena := {}
var _cam: Camera3D
var _skater: Skater
var _rebuild_in := -1.0
var _shot := "body"
var _yaw := 0.0             ## mouse orbit on top of the framing's own angle
var _drag := false
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_shift := 0.5
var _cam_snap := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # drags off the rows reach _unhandled_input (camera orbit)
	Sfx.play_music()
	_p = CustomPlayers.blank()
	for k: String in _p:
		var a := _arg(k, "")
		if a != "" and k != "position":
			_p[k] = (a == "true") if _p[k] is bool else (int(a) if _p[k] is int else a)
	if _arg("position", "") != "":
		CustomPlayers.set_position(_p, _arg("position", "C"))
	_saved = JSON.stringify(_p)
	_team = int(_arg("team", str(GameSettings.config.get("home_team", 0))))
	_build_stage()

	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if _busy() or _items.is_empty():
			return
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
	_header.draw.connect(func() -> void: MenuStyle.draw_tag(_header, Vector2(60, 30), "CUSTOMIZE", "CREATE PLAYER"))
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

	_show_tab(maxi(0, TABS.find(_arg("tab", "player"))), true)
	if _arg("sel", "") != "" and not _items.is_empty():
		_select(clampi(int(_arg("sel", "0")), 0, _items.size() - 1), true)
	_rebuild()
	if _arg("kb", "") != "":
		_input.using_pad = true
		_accept()


func _process(delta: float) -> void:
	_t += delta
	_leave_warn = maxf(0.0, _leave_warn - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			_rebuild()
	_place_camera(delta)
	_footer.queue_redraw()
	_tabs.queue_redraw()
	_card.queue_redraw()


## Typing a name, or just finished (the Enter / Esc that ended it mustn't reach the menu).
func _busy() -> bool:
	return _leaving or _typing != "" or Time.get_ticks_msec() < _quiet_until


# --- Rows ---------------------------------------------------------------------------

## The rows of a tab. kind: "text" (typed), "choice" (left / right through _choices),
## "rating" (a skill), "action" (accept runs it).
func _tab_rows(tab: String) -> Array:
	var goalie := CustomPlayers.is_goalie(_p)
	var rows := []
	match tab:
		"player":
			rows = [
				{"key": "editing", "label": "EDITING", "kind": "choice",
					"hint": "Make a new player, or pick a saved one to change. Unsaved changes are lost when you switch."},
				{"key": "first", "label": "FIRST NAME", "kind": "text", "max": 16, "shot": "body",
					"hint": "Press %s and type the first name." % _input_label()},
				{"key": "last", "label": "LAST NAME", "kind": "text", "max": 16, "shot": "back",
					"hint": "Goes on the back of the jersey (unless a short nickname does)."},
				{"key": "nickname", "label": "NICKNAME", "kind": "text", "max": 14, "shot": "back",
					"hint": "Optional. %d letters or fewer goes on the jersey instead of the last name." % SkaterVisual.NICKNAME_MAX},
				{"key": "number", "label": "NUMBER", "kind": "choice", "shot": "back",
					"hint": "0 to 99. Left / right steps it, or press %s and type it." % _input_label()},
				{"key": "position", "label": "POSITION", "kind": "choice",
					"hint": "Center, wings, defense or goalie. Switching between skater and goalie resets the skills."},
				{"key": "hand", "label": "CATCHES" if goalie else "SHOOTS", "kind": "choice",
					"hint": "Which hand the glove is on." if goalie else "Which side the stick's blade is on."},
				{"key": "playstyle", "label": "PLAY STYLE", "kind": "choice",
					"hint": "Tilts the ratings toward a role, and how the AI plays them."},
			]
		"skills":
			rows = [{"key": "skill_mode", "label": "SKILL MODE", "kind": "choice",
				"hint": "Realistic with Points: a limited pool to spend, high ratings cost more. Free: set any rating."}]
			for k: String in CustomPlayers.rating_keys(_p):
				rows.append({"key": k, "label": CustomPlayers.RATING_NAMES[k], "kind": "rating",
					"hint": CustomPlayers.RATING_HINTS[k]})
			rows.append({"key": "reset_skills", "label": "RESET SKILLS", "kind": "action",
				"hint": "All ratings back to where they start."})
		"look":
			rows = [
				{"key": "gender", "label": "GENDER", "kind": "choice", "shot": "body", "hint": "The body model."},
				{"key": "height_in", "label": "HEIGHT", "kind": "choice", "shot": "body",
					"hint": "How tall: the whole body scales with it, and so does a fighter's reach."},
				{"key": "weight_lbs", "label": "WEIGHT", "kind": "choice", "shot": "body",
					"hint": "Against the height, sets the build: heavier fills out the trunk, arms and legs, lighter slims them."},
				{"key": "skin", "label": "SKIN TONE", "kind": "choice", "shot": "face", "hint": "Light to dark."},
				{"key": "eyes", "label": "EYE COLOR", "kind": "choice", "shot": "face", "hint": "Eye color."},
				{"key": "hair_style", "label": "HAIR STYLE", "kind": "choice", "shot": "face",
					"hint": "Shows under the helmet, and all of it when the helmet comes off in a fight."},
				{"key": "hair_color", "label": "HAIR COLOR", "kind": "choice", "shot": "face", "hint": "Also colors facial hair."},
				{"key": "facial_hair", "label": "FACIAL HAIR", "kind": "choice", "shot": "face", "hint": "Men only."},
			]
		"gear":
			rows = [
				{"key": "helmet", "label": "MASK" if goalie else "HELMET", "kind": "choice", "shot": "head",
					"hint": "The goalie mask model." if goalie else "Modern two-piece or a classic one-piece shell."},
				{"key": "visor", "label": "VISOR", "kind": "choice", "shot": "head",
					"hint": "Goalies wear a cage." if goalie else "A clear shield over the eyes."},
				{"key": "stick", "label": "STICK", "kind": "choice", "shot": "stick",
					"hint": "Graphics on a base color. Home and away are the team's home and road jersey colors."},
				{"key": "tape", "label": "BLADE TAPE", "kind": "choice", "shot": "stick",
					"hint": "Tape round the middle of the blade. Team color is the home jersey color."},
				{"key": "preview_team", "label": "PREVIEW JERSEY", "kind": "choice", "shot": "body",
					"hint": "Only for this screen: see the player and the team-colored sticks in a team's uniform."},
			]
	rows.append({"key": "save", "label": "SAVE PLAYER", "kind": "action",
		"hint": "New players go to Free Agency, where Edit Roster (coming soon) signs them to teams."})
	if tab == "player" and _edit_index >= 0:
		rows.append({"key": "delete", "label": "DELETE PLAYER", "kind": "action",
			"hint": "Removes this saved player. Press twice to confirm."})
	return rows


## [values, names] for a choice row.
func _choices(key: String) -> Array:
	match key:
		"editing":
			var v := [-1]
			var n := ["New Player"]
			var saved := CustomPlayers.all()
			for i in saved.size():
				v.append(i)
				n.append(CustomPlayers.display_name(saved[i]))
			return [v, n]
		"number":
			return [range(0, 100), range(0, 100).map(func(x: int) -> String: return str(x))]
		"position":
			return [CustomPlayers.POSITIONS, CustomPlayers.POSITION_NAMES]
		"hand":
			return [["L", "R"], ["Left", "Right"]]
		"playstyle":
			var st: Array = CustomPlayers.STYLES[CustomPlayers.group(_p)]
			return [st, st]
		"skill_mode":
			return [["points", "free"], ["Realistic with Points", "Free"]]
		"gender":
			return [["Male", "Female"], ["Male", "Female"]]
		"height_in":
			var hv := range(CustomPlayers.HEIGHTS[0], CustomPlayers.HEIGHTS[1] + 1)
			return [hv, hv.map(func(x: int) -> String: return CustomPlayers.height_text(x))]
		"weight_lbs":
			var wv := range(CustomPlayers.WEIGHTS[0], CustomPlayers.WEIGHTS[1] + 1, 5)
			return [wv, wv.map(func(x: int) -> String: return "%d lb" % x)]
		"skin":
			return [range(CustomPlayers.SKIN_NAMES.size()), CustomPlayers.SKIN_NAMES]
		"eyes":
			return [range(CustomPlayers.EYE_NAMES.size()), CustomPlayers.EYE_NAMES]
		"hair_style":
			var v: Array = CustomPlayers.HAIR_STYLES.duplicate()
			var n: Array = CustomPlayers.HAIR_STYLE_NAMES.duplicate()
			if _p.gender != "Female":
				v.pop_back()   # braid
				n.pop_back()
			return [v, n]
		"hair_color":
			return [range(CustomPlayers.HAIR_COLOR_NAMES.size()), CustomPlayers.HAIR_COLOR_NAMES]
		"facial_hair":
			return [CustomPlayers.FACIAL_HAIR, CustomPlayers.FACIAL_HAIR_NAMES]
		"helmet":
			return [[0, 1], CustomPlayers.MASK_NAMES if CustomPlayers.is_goalie(_p) else CustomPlayers.HELMET_NAMES]
		"visor":
			return [[true, false], ["Yes", "No"]]
		"stick":
			return [SkaterVisual.STICK_STYLES, SkaterVisual.STICK_STYLE_NAMES]
		"tape":
			return [SkaterVisual.TAPES, SkaterVisual.TAPE_NAMES]
		"preview_team":
			return [range(Teams.count()), range(Teams.count()).map(func(i: int) -> String: return Teams.full_name(i))]
	return [[], []]


func _value_of(key: String) -> Variant:
	match key:
		"editing":
			return _edit_index
		"preview_team":
			return _team
	if key in _p.ratings:
		return _p.ratings[key]
	if key == "height_in":
		return CustomPlayers.height_in(_p)
	if key == "weight_lbs":
		return CustomPlayers.weight_lbs(_p)
	return _p.get(key)


## Rows that don't apply right now (dimmed, and they don't change).
func _row_off(key: String) -> bool:
	match key:
		"facial_hair":
			return _p.gender == "Female"
		"visor":
			return CustomPlayers.is_goalie(_p)
		"delete":
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
		it.position = ROW_POS + Vector2(0, i * (ROW_SIZE.y + ROW_GAP) + (12.0 if action else 0.0))
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
				if _rows[i].kind in ["choice", "rating"]:
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


## Rebuilds the current tab's rows in place (when the set of rows changes: position,
## a save), keeping the selection on the same key.
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
				var v := str(_p.get(d.key, ""))
				it.value = v if v != "" else "-"
			"rating":
				it.value = str(_p.ratings.get(d.key, 0))
			"choice":
				var ch := _choices(d.key)
				var idx: int = ch[0].find(_value_of(d.key))
				it.value = str(ch[1][idx]) if idx >= 0 else str(_value_of(d.key))
			"action":
				if d.key == "delete":
					it.text = "PRESS AGAIN TO DELETE" if _delete_armed else d.label
		it.modulate.a = 0.4 if _row_off(d.key) else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	_delete_armed = false
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if _rows[k].kind in ["action", "text"] else ""
		_items[k].glyph_pad = _input.using_pad
	_refresh()
	_shot = _rows[i].get("shot", "body") if i < _rows.size() else "body"
	if TABS[_tab] == "skills":
		_shot = "body"
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


## Left / right on a row.
func _step(i: int, dir: int) -> void:
	if i >= _rows.size():
		return
	var d: Dictionary = _rows[i]
	if _row_off(d.key):
		_items[i].nudge()
		return
	match d.kind:
		"rating":
			if not CustomPlayers.step_rating(_p, d.key, dir):
				_items[i].nudge()
				Sfx.play("pad", Vector3.INF, -12.0)
				return
			Sfx.play("click", Vector3.INF, -12.0, 1.6)
			_refresh()
			return
		"choice":
			pass
		_:
			return
	var ch := _choices(d.key)
	var values: Array = ch[0]
	if values.is_empty():
		return
	var cur := values.find(_value_of(d.key))
	var nv: Variant = values[wrapi(cur + dir, 0, values.size()) if cur >= 0 else 0]
	match d.key:
		"editing":
			_load_player(int(nv))
			return
		"preview_team":
			_team = int(nv)
			_dress_arena()
		"position":
			var was := CustomPlayers.is_goalie(_p)
			CustomPlayers.set_position(_p, nv)
			if was != CustomPlayers.is_goalie(_p):
				_reshow()   # helmet / mask and shoots / catches rows change names
		"skill_mode":
			CustomPlayers.set_mode(_p, nv)
		"gender":
			# Still on the old gender's default size: move to the new one's.
			if CustomPlayers.height_in(_p) == CustomPlayers.HEIGHT_DEFAULT.get(_p.gender, 0) 					and CustomPlayers.weight_lbs(_p) == CustomPlayers.WEIGHT_DEFAULT.get(_p.gender, 0):
				_p.height_in = CustomPlayers.HEIGHT_DEFAULT[nv]
				_p.weight_lbs = CustomPlayers.WEIGHT_DEFAULT[nv]
			_p.gender = nv
			if nv == "Female":
				_p.facial_hair = ""
			elif _p.hair_style == "braid":
				_p.hair_style = "messy"
		_:
			_p[d.key] = nv
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_refresh()
	if d.key not in ["skill_mode", "playstyle"]:
		_rebuild_in = REBUILD_DELAY


func _accept() -> void:
	if _index >= _rows.size():
		return
	var d: Dictionary = _rows[_index]
	match d.kind:
		"text":
			_start_typing(d.key, int(d.get("max", 16)))
		"choice", "rating":
			if d.key == "number":
				_start_typing("number", 2)
			else:
				_step(_index, 1)
		"action":
			match d.key:
				"save":
					_save()
				"delete":
					if not _delete_armed:
						_delete_armed = true
						_items[_index].nudge()
						Sfx.play("pad", Vector3.INF, -6.0)
						_refresh()
						return
					CustomPlayers.delete_player(_edit_index)
					Sfx.play("glove", Vector3.INF, -4.0)
					_toast = "PLAYER DELETED"
					_toast_t = 2.0
					_load_player(-1)
					_show_tab(0, true)
				"reset_skills":
					CustomPlayers.reset_ratings(_p)
					_items[_index].nudge()
					Sfx.play("glove", Vector3.INF, -6.0)
					_refresh()


func _save() -> void:
	_was_new = _edit_index < 0
	_edit_index = CustomPlayers.save_player(_p, _edit_index)
	_saved = JSON.stringify(_p)
	Sfx.play("glove", Vector3.INF, -4.0)
	_items[_index].nudge()
	_toast = "SIGNED TO FREE AGENCY" if _was_new else "SAVED"
	_was_new = false
	_toast_t = 2.2
	_reshow()


func _load_player(i: int) -> void:
	_edit_index = i
	var saved := CustomPlayers.all()
	_p = saved[i].duplicate(true) if i >= 0 and i < saved.size() else CustomPlayers.blank()
	_saved = JSON.stringify(_p)
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_reshow()
	_rebuild_in = 0.0


func _dirty() -> bool:
	return JSON.stringify(_p) != _saved


# --- Typing -------------------------------------------------------------------------

func _start_typing(key: String, max_len: int) -> void:
	_typing = key
	var it := _items[_index]
	if _input.using_pad:
		# The on-screen keyboard, over the middle of the screen.
		# A number starts empty (typed over); names start from what they are.
		_kb.open(_input, it.text, "" if key == "number" else str(_p.get(key, "")), max_len, key == "number")
		_kb.position = Vector2((_canvas.size.x - _kb.size.x) * 0.5, 210.0)
		Sfx.play("click", Vector3.INF, -8.0, 1.2)
		return
	_typer.max_length = max_len
	_typer.text = str(_p.get(key, ""))
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


## Typing's over (row or pad keyboard): `text` to keep, or null to drop it.
func _finish_text(value: Variant) -> void:
	if _typing == "":
		return
	var key := _typing
	_typing = ""
	_quiet_until = Time.get_ticks_msec() + 200
	if value != null:
		var text: String = value
		if key == "number":
			if text.is_valid_int():
				_p.number = clampi(int(text), 0, 99)
		else:
			_p[key] = text
		_rebuild_in = REBUILD_DELAY
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
	GameSettings.menu_select = 0
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


# --- 3D preview ---------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	# The menu above is not physics-interpolated; the players skating here (120 Hz physics)
	# must be, or they step unevenly against the frame rate. The camera, placed every
	# frame, must not be.
	_stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(_stage)
	_arena = MenuArena.build(_stage, SPOT)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.attributes = MenuArena.camera_attributes()
	_stage.add_child(_cam)
	_dress_arena()


func _dress_arena() -> void:
	var rink := _arena.rink as Rink
	var crest := MenuArena.logo(_team)
	if crest:
		rink.set_center_logo(crest)
	if rink.arena:
		rink.arena.set_teams(_team, -1)


## A fresh player from _p in the preview team's uniform, standing for the camera.
func _rebuild() -> void:
	_rebuild_in = -1.0
	if _skater != null:
		_skater.queue_free()
		_skater = null
	var goalie := CustomPlayers.is_goalie(_p)
	var s: Skater = (GOALIE_SCENE if goalie else SKATER_SCENE).instantiate()
	var home := Teams.uniform_vs(_team, _team, false)
	var road := Teams.uniform_vs(_team, _team, true)
	s.uniform = home
	s.team_color = home.jersey
	s.club_colors = [home.jersey, road.jersey]
	var crest := MenuArena.logo(_team)
	if crest:
		s.crest = crest
	CustomPlayers.apply(s, _p)
	s.puck = _arena.puck
	s.rink = _arena.rink
	s.fatigue_enabled = false
	_stage.add_child(s)
	s.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass)
	s.teammates = [s]
	s.place(SPOT, Vector3.BACK)
	if s.visual != null:
		if not goalie:
			s.visual.display_pose = "side"
		if s.visual.face != null:
			s.visual.face.look_at_camera = true
		s.visual.snap()
	_skater = s


## Where the current framing looks (world).
func _cam_target() -> Vector3:
	if _skater == null or _skater.visual == null:
		return SPOT + Vector3(0, 0.9, 0)
	var v := _skater.visual
	match _shot:
		"face":
			return v.bone_world("Head") + Vector3(0, 0.07, 0)
		"head":
			return v.bone_world("Head") + Vector3(0, 0.02, 0)
		"back":
			return SPOT + Vector3(0, 1.2, 0)
		"stick":
			# The middle of the blade: from the heel, half the model's heel-to-toe line.
			var sh := v.shaft
			if sh != null and sh.mesh != null:
				return sh.global_transform * (Vector3(sh.mesh.get_meta("blade", Vector3.ZERO)) * 0.5)
	return SPOT + Vector3(0, 0.9, 0)


func _place_camera(delta: float) -> void:
	if _cam == null:
		return
	var spec: Dictionary = SHOTS.get(_shot, SHOTS.body)
	var look := _cam_target()
	var yaw: float = float(spec.get("yaw", 0.0)) + _yaw + sin(_t * 0.25) * 0.06
	var pitch: float = spec.pitch
	var d: float = spec.dist
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := look + dir * d
	var k := 1.0 if _cam_snap else 1.0 - exp(-delta * 5.0)
	_cam_snap = false
	_cam_pos = _cam_pos.lerp(pos, k)
	_cam_look = _cam_look.lerp(look, k)
	_cam_shift = lerpf(_cam_shift, float(spec.shift), k)
	_cam.look_at_from_position(_cam_pos, _cam_look)
	# The subject sits right of center, clear of the menu: shift the view, not the angle.
	var half_w := tan(deg_to_rad(_cam.fov * 0.5)) * _cam_pos.distance_to(_cam_look) \
			* get_viewport_rect().size.aspect()
	_cam.h_offset = -_cam_shift * half_w


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_yaw -= e.relative.x * 0.008


# --- Drawing ------------------------------------------------------------------------

func _input_label() -> String:
	return _input.accept_label() if _input else "ENTER"


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
		MenuStyle.draw_bold(_tabs, r.position + Vector2((r.size.x - tw) * 0.5 + 8, 30), name, 22,
				Color.WHITE if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	MenuStyle.draw_glyph(_tabs, Vector2(30.0 + TABS.size() * TAB_SIZE.x + 6.0, gy), "R1" if pad else "E", false, 30.0)


## The player card, top right: number, name, position and play style, overall (and on
## SKILLS the points left).
func _draw_card() -> void:
	var r := CARD
	r.position.x = _canvas.size.x - r.size.x - 50.0
	var col := MenuStyle.team_color(_team)
	MenuStyle.draw_slant(_card, Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.35), 22.0)
	MenuStyle.draw_slant(_card, r, Color(0.03, 0.05, 0.1, 0.85), 22.0)
	MenuStyle.draw_slant(_card, Rect2(r.position, Vector2(150, r.size.y)), col.lerp(Color.BLACK, 0.2), 22.0)
	var num := str(_p.get("number", 19))
	var nw := MenuStyle.text_width(num, 78)
	MenuStyle.draw_bold(_card, r.position + Vector2(86 - nw * 0.5, 104), num, 78, Color.WHITE, 8, MenuStyle.INK)
	var name := CustomPlayers.display_name(_p).to_upper() if (str(_p.first) + str(_p.last)) != "" else "NEW PLAYER"
	var nick := str(_p.get("nickname", ""))
	var x := r.position.x + 172.0
	var fs := 34   # shrinks for long names, clear of the overall box
	while fs > 16 and MenuStyle.text_width(name, fs) > r.size.x - 300.0:
		fs -= 2
	MenuStyle.draw_bold(_card, Vector2(x, r.position.y + 50), name, fs, Color.WHITE, 0, MenuStyle.INK, 0.2)
	if nick != "":
		_card.draw_string(MenuStyle.font(0.12), Vector2(x + 2, r.position.y + 78), "\"%s\"" % nick.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 0.86, 0.86))
	var pos_name: String = CustomPlayers.POSITION_NAMES[maxi(0, CustomPlayers.POSITIONS.find(_p.position))]
	var line := "%s  ·  %s" % [pos_name.to_upper(), str(_p.playstyle).to_upper()]
	_card.draw_string(MenuStyle.font(0.12), Vector2(x + 2, r.position.y + 112), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	var hand := ("CATCHES " if CustomPlayers.is_goalie(_p) else "SHOOTS ") + ("LEFT" if _p.hand == "L" else "RIGHT")
	_card.draw_string(MenuStyle.font(0.12), Vector2(x + 2, r.position.y + 136), hand,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
	# Where they play: created players start out as free agents.
	var club := "FREE AGENT" if str(_p.get("team", CustomPlayers.FREE_AGENT)) == CustomPlayers.FREE_AGENT else str(_p.team)
	_card.draw_string(MenuStyle.font(0.12), Vector2(x + 2 + MenuStyle.text_width(hand, 16, 0.12) + 22.0, r.position.y + 136),
			club, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.86, 0.45))
	# Overall, in a box at the right end.
	var ob := Rect2(r.end.x - 112.0, r.position.y + 18, 92, 84)
	_card.draw_rect(ob, Color(1, 1, 1, 0.08))
	_card.draw_rect(Rect2(ob.position, Vector2(ob.size.x, 3)), MenuStyle.RED)
	var ovr := str(CustomPlayers.overall(_p))
	var ow := MenuStyle.text_width(ovr, 46)
	MenuStyle.draw_bold(_card, Vector2(ob.get_center().x - ow * 0.5, ob.position.y + 56), ovr, 46, Color.WHITE)
	var lw := MenuStyle.text_width("OVERALL", 14, 0.12)
	_card.draw_string(MenuStyle.font(0.12), Vector2(ob.get_center().x - lw * 0.5, ob.end.y - 6), "OVERALL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuStyle.DIM)
	if TABS[_tab] == "skills":
		_draw_points(Vector2(ROW_POS.x + ROW_SIZE.x + 70.0, ROW_POS.y))
		_draw_bars()
	if _dirty():
		_card.draw_string(MenuStyle.font(0.12), Vector2(r.end.x - 175.0, r.end.y + 26), "UNSAVED CHANGES",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.8, 0.45))
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := MenuStyle.text_width(_toast, 26)
		var tp := Vector2(r.end.x - tw - 20.0, r.end.y + 70)
		MenuStyle.draw_slant(_card, Rect2(tp - Vector2(22, 32), Vector2(tw + 44, 44)), Color(MenuStyle.RED, 0.9 * a), 14.0)
		MenuStyle.draw_bold(_card, tp, _toast, 26, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)


## SKILLS: the points pool (Realistic with Points), beside the rows.
func _draw_points(at: Vector2) -> void:
	if _p.skill_mode != "points":
		return
	var left := CustomPlayers.points_left(_p)
	var r := Rect2(at, Vector2(150, 96))
	_card.draw_rect(r, Color(0.03, 0.05, 0.1, 0.85))
	_card.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), MenuStyle.RED)
	var s := str(left)
	var w := MenuStyle.text_width(s, 50)
	MenuStyle.draw_bold(_card, Vector2(r.get_center().x - w * 0.5, r.position.y + 60), s, 50,
			Color.WHITE if left > 0 else Color(1, 0.72, 0.5))
	var lw := MenuStyle.text_width("POINTS LEFT", 15, 0.12)
	_card.draw_string(MenuStyle.font(0.12), Vector2(r.get_center().x - lw * 0.5, r.end.y - 10), "POINTS LEFT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuStyle.DIM)
	var next := ""
	if _index < _rows.size() and _rows[_index].kind == "rating":
		var v := int(_p.ratings.get(_rows[_index].key, 0))
		next = "NEXT POINT: %d" % (CustomPlayers.point_cost(v) if v >= CustomPlayers.POINTS_START else 1)
	if next != "":
		_card.draw_string(MenuStyle.font(0.12), r.position + Vector2(4, r.size.y + 24), next,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuStyle.DIM)


## SKILLS: a meter under each rating's value.
func _draw_bars() -> void:
	for i in _rows.size():
		if _rows[i].kind != "rating":
			continue
		var it := _items[i]
		var v := int(_p.ratings.get(_rows[i].key, 0))
		var x := it.position.x + ROW_SIZE.x - VALUE_W + 6.0
		var y := it.position.y + ROW_SIZE.y - 7.0
		var w := VALUE_W - 60.0
		_card.draw_rect(Rect2(x, y, w, 4), Color(0, 0, 0, 0.5))
		var c := Color(0.95, 0.3, 0.25).lerp(Color(0.35, 0.9, 0.4), clampf((v - 40.0) / 55.0, 0.0, 1.0))
		_card.draw_rect(Rect2(x, y, w * v / 99.0, 4), c)


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
		var kind: String = _rows[_index].kind
		if kind in ["text"] or _rows[_index].key == "number":
			prompts.append([_input.accept_label(), "TYPE"])
		elif kind == "action":
			prompts.append([_input.accept_label(), "SELECT"])
		else:
			prompts.append([_input.accept_label(), "CHANGE"])
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
		_take_shot.call_deferred(shot, float(_arg("wait", "2.5")))


func _take_shot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
