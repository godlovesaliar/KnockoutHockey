extends Control
## CUSTOMIZE > CREATE UNIFORM: any team's home or road uniform, league or created. Two
## tabs of settings on the left (COLORS, STRIPES); on the right the team's home and road
## players side by side, the one being edited in front, rebuilt as you change things.
##
## Up / down picks a row, left / right changes it, accept runs an action row. L1 / R1
## (Q / E) or a click switches tabs; Triangle (I) turns the players round to see the
## back. Saving stores the set (Uniforms) and every game uses it. RESET puts the team's
## original uniform back. Changing team or set with unsaved changes, or leaving, asks
## for a second press.
##
## `-- shot=<png> [wait=<s>] [tab=colors|stripes] [team=<i>] [set=home|road] [back=1]
## [<color key>=<html> ...] [style= hem= sleeve= sock= alternate= yoke= width=] [save=1]`
## saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const MENU_SELECT := 3          ## CREATE UNIFORM's place in the CUSTOMIZE list
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")

const TABS := ["colors", "stripes"]
const TAB_NAMES := ["COLORS", "STRIPES"]
const TAB_POS := Vector2(40, 152)
const TAB_SIZE := Vector2(190, 44)
const ROW_POS := Vector2(60, 216)
const ROW_SIZE := Vector2(720, 38)
const ROW_GAP := 4.0
const VALUE_W := 300.0
const CARD := Rect2(1030, 40, 520, 128)
const SPOT := Vector3(-3.0, 0.0, 4.0)
const PAIR_GAP := 0.75          ## m between the two players
const REBUILD_DELAY := 0.15
const WARN := 3.0
const SETS := ["home", "road"]
const COLOR_ROWS := [
	["jersey", "JERSEY", "The jersey's body."],
	["trim", "STRIPES", "Stripes, cuffs, collar and yoke."],
	["number_outline", "ACCENT", "Every other stripe (when stripes alternate) and the number's outline."],
	["number", "NUMBERS", "The back number and the nameplate."],
	["pants", "PANTS", "Pants and shell."],
	["gloves", "GLOVES", "Glove shells."],
	["helmet", "HELMET", "The helmet."],
	["skates", "SKATES", "Skate boots."],
]

var _team := 0
var _which := "home"
var _u := {}                ## the set being edited (Uniforms format)
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
var _warn := 0.0            ## a second press within this goes ahead (switch, leave, reset)
var _warn_key := ""
var _toast := ""
var _toast_t := 0.0
var _leaving := false
var _time := 0.0
var _back_view := false
var _yaw := 0.0

var _stage: Node3D
var _arena := {}
var _cam: Camera3D
var _players: Array[Skater] = []
var _rebuild_in := -1.0


func _ready() -> void:
	Sfx.play_music()
	_team = Store.open_team(clampi(int(_arg("team", str(GameSettings.config.get("home_team", 0)))), 0, Teams.count() - 1))
	_which = "road" if _arg("set", "home") == "road" else "home"
	_load_set()
	for k: String in Uniforms.COLOR_KEYS:
		if _arg(k, "") != "":
			_u.colors[k] = _arg(k, "")
	if _arg("style", "") != "":
		Uniforms.set_style(_u, _arg("style", "classic"))
	for k: String in ["hem", "sleeve", "sock", "sock_pattern", "yoke", "width"]:
		if _arg(k, "") != "":
			_u[k] = int(_arg(k, ""))
	if _arg("alternate", "") != "":
		_u.alternate = _arg("alternate", "") == "true"
	_back_view = _arg("back", "") != ""
	_build_stage()

	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if not _leaving and not _items.is_empty():
			_select(wrapi(_index + dir, 0, _items.size())))
	_input.side.connect(func(dir: int) -> void:
		if not _leaving:
			_step(_index, dir))
	_input.accepted.connect(func() -> void:
		if not _leaving:
			_accept())
	_input.back.connect(func() -> void:
		if not _leaving:
			_back())
	_input.dev_bumper.connect(func(_dev: String, dir: int) -> void:
		if not _leaving:
			_show_tab(wrapi(_tab + dir, 0, TABS.size())))
	_input.button.connect(_on_button)

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
	_header.draw.connect(func() -> void: MenuStyle.draw_tag(_header, Vector2(60, 30), "CUSTOMIZE", "CREATE UNIFORM"))
	_canvas.add_child(_header)

	_tabs = Control.new()
	_tabs.position = TAB_POS
	_tabs.size = Vector2(TAB_SIZE.x * TABS.size() + 40, TAB_SIZE.y)
	_tabs.draw.connect(_draw_tabs)
	_tabs.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _leaving:
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

	_show_tab(maxi(0, TABS.find(_arg("tab", "colors"))), true)
	_rebuild()


func _process(delta: float) -> void:
	_time += delta
	_warn = maxf(0.0, _warn - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			_rebuild()
	var target := PI if _back_view else 0.0
	_yaw = lerp_angle(_yaw, target, 1.0 - exp(-delta * 6.0))
	_place_camera()
	_footer.queue_redraw()
	_tabs.queue_redraw()
	_card.queue_redraw()


func _on_button(b: String) -> void:
	if _leaving:
		return
	if b == "triangle":
		_back_view = not _back_view
		Sfx.play("click", Vector3.INF, -8.0, 1.3)
		_rebuild_in = 0.0   # (the edited one steps to the camera's side)


# --- The set ------------------------------------------------------------------------

## The team's home uniform before Create Uniform (and its design).
func _base_home() -> Dictionary:
	return Teams.uniform_of(Teams.base_team(_team), Teams.base_team(_team), false)


## What the set looks like unedited: home from the league list; road worked out from
## the (possibly edited) home one.
func _original(which: String) -> Dictionary:
	var home := _base_home()
	if which == "home":
		return Uniforms.from_uniform(home, str(home.design))
	var cur := Teams.uniform_of(Teams.team(_team), Teams.team(_team), false)
	return Uniforms.from_uniform(Teams.auto_road(cur), str(cur.design))


func _abbr() -> String:
	return str(Teams.team(_team).abbr)


func _load_set() -> void:
	var saved := Uniforms.get_set(_abbr(), _which)
	_u = saved.duplicate(true) if not saved.is_empty() else _original(_which)
	_saved = JSON.stringify(_u)


func _dirty() -> bool:
	return JSON.stringify(_u) != _saved


func _edited() -> bool:
	return not Uniforms.get_set(_abbr(), _which).is_empty()


func _changed() -> void:
	_rebuild_in = REBUILD_DELAY
	_refresh()


## A second press of the same thing within WARN goes ahead.
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
	if tab == "colors":
		rows = [
			{"key": "team", "label": "TEAM", "kind": "choice", "hint": "Whose uniform: any team, league or created."},
			{"key": "set", "label": "UNIFORM", "kind": "choice",
				"hint": "Home, or road (worn away from home unless it clashes with the home team's)."},
		]
		for c: Array in COLOR_ROWS:
			rows.append({"key": c[0], "label": c[1], "kind": "choice", "hint": c[2]})
	else:
		rows = [
			{"key": "style", "label": "STYLE", "kind": "choice",
				"hint": "Start from a stripe layout; the rows below change it from there."},
			{"key": "hem", "label": "HEM STRIPES", "kind": "choice", "hint": "Stripes round the bottom of the jersey."},
			{"key": "sleeve", "label": "SLEEVE STRIPES", "kind": "choice", "hint": "Stripes round the sleeves, below the elbow."},
			{"key": "sock", "label": "SOCK STRIPES", "kind": "choice",
				"hint": "Stripes round the socks: more rings on a barber pole, thin stripes over a two-tone sock."},
			{"key": "sock_pattern", "label": "SOCK PATTERN", "kind": "choice",
				"hint": "Stripes in one band, a barber pole all the way down, two-tone, or one broad block."},
			{"key": "width", "label": "STRIPE WIDTH", "kind": "choice", "hint": "How much room the stripes take."},
			{"key": "alternate", "label": "ALTERNATE", "kind": "choice",
				"hint": "Every other stripe in the accent color instead of the stripe color."},
			{"key": "yoke", "label": "YOKE", "kind": "choice", "hint": "A shoulder yoke in the stripe color."},
		]
	rows.append({"key": "save", "label": "SAVE UNIFORM", "kind": "action",
		"hint": "Saves this uniform. Every game uses it from now on."})
	rows.append({"key": "reset", "label": "RESET TO ORIGINAL", "kind": "action",
		"hint": "Back to the team's own uniform. Press twice."})
	return rows


func _choices(key: String) -> Array:
	match key:
		"team":
			var order := Store.open_teams()   # (not the teams still locked in the shop)
			return [order, order.map(func(i: int) -> String: return Teams.full_name(i))]
		"set":
			return [SETS, ["Home", "Road"]]
		"style":
			return [CustomTeams.DESIGN_NAMES.keys(), CustomTeams.DESIGN_NAMES.values()]
		"hem", "sleeve", "sock":
			var r := range(Uniforms.MAX_STRIPES + 1)
			return [r, r.map(func(n: int) -> String: return "None" if n == 0 else str(n))]
		"sock_pattern":
			return [range(Teams.SOCK_PATTERNS.size()), Teams.SOCK_PATTERN_NAMES]
		"width":
			return [[0, 1, 2], ["Thin", "Normal", "Wide"]]
		"alternate":
			return [[false, true], ["No", "Yes"]]
		"yoke":
			return [[0, 1, 2], ["None", "Small", "Large"]]
	if key in Uniforms.COLOR_KEYS:
		# The original color first, then the palette.
		var orig := str(_original(_which).colors[key])
		var v := [orig]
		var n := ["Original"]
		for p: Array in CustomTeams.PALETTE:
			var h := (p[1] as Color).to_html(false)
			if h != orig:
				v.append(h)
				n.append(p[0])
		return [v, n]
	return [[], []]


func _value_of(key: String) -> Variant:
	match key:
		"team":
			return _team
		"set":
			return _which
	if key in Uniforms.COLOR_KEYS:
		return str(_u.colors.get(key, ""))
	return _u.get(key)


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
			y += 12.0 + 8.0 * (i - first_action)
		it.position = ROW_POS + Vector2(0, y)
		it.size = ROW_SIZE if not action else Vector2(420, 44)
		it.value_w = VALUE_W
		it.intro(0.04 + i * 0.02)
		it.hovered.connect(func() -> void:
			if _index != i and not _leaving:
				_select(i))
		it.gui_input.connect(func(e: InputEvent) -> void:
			if not (e is InputEventMouseButton and e.pressed) or _leaving:
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


func _refresh() -> void:
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		var it := _items[i]
		if d.kind == "choice":
			var ch := _choices(d.key)
			var idx: int = ch[0].find(_value_of(d.key))
			it.value = str(ch[1][idx]) if idx >= 0 else ("Custom" if d.key in Uniforms.COLOR_KEYS else str(_value_of(d.key)))
		elif d.key == "reset":
			it.text = "PRESS AGAIN TO RESET" if _warn > 0.0 and _warn_key == "reset" else d.label
		it.modulate.a = 0.4 if d.key == "reset" and not _edited() and not _dirty() else 1.0


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label() if _rows[k].kind == "action" else ""
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
		"team", "set":
			if _dirty() and not _confirm("switch"):
				_items[i].nudge()
				return
			if key == "team":
				_team = int(nv)
			else:
				_which = nv
			_load_set()
		"style":
			Uniforms.set_style(_u, nv)
		_:
			if key in Uniforms.COLOR_KEYS:
				_u.colors[key] = nv
			else:
				_u[key] = nv
	Sfx.play("click", Vector3.INF, -8.0, 1.6)
	_changed()


func _accept() -> void:
	if _index >= _rows.size():
		return
	var d: Dictionary = _rows[_index]
	if d.kind == "choice":
		_step(_index, 1)
		return
	match d.key:
		"save":
			Uniforms.save_set(_abbr(), _which, _u)
			_saved = JSON.stringify(_u)
			_say("%s UNIFORM SAVED" % _which.to_upper())
			Sfx.play("glove", Vector3.INF, -4.0)
			_items[_index].nudge()
			_changed()
		"reset":
			if not _edited() and not _dirty():
				_items[_index].nudge()
				return
			if not _confirm("reset"):
				_refresh()
				return
			Uniforms.clear_set(_abbr(), _which)
			_load_set()
			_say("BACK TO THE ORIGINAL")
			Sfx.play("glove", Vector3.INF, -4.0)
			_changed()


func _say(text: String) -> void:
	_toast = text
	_toast_t = 2.4


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
	_arena = MenuArena.build(_stage, SPOT)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.attributes = MenuArena.camera_attributes()
	_stage.add_child(_cam)


## The two uniforms as they'll look: the one being edited from _u, the other as saved
## (a road set nobody saved follows the home one).
func _preview(which: String) -> Dictionary:
	if which == _which:
		return Uniforms.uniform(_u)
	var t := Teams.team(_team)
	if which == "home":
		return Teams.uniform_of(t, t, false)
	if t.has("road"):
		return t.road.duplicate()
	return Teams.auto_road(Uniforms.uniform(_u) if _which == "home" else Teams.uniform_of(t, t, false))


func _rebuild() -> void:
	_rebuild_in = -1.0
	for s in _players:
		s.queue_free()
	_players.clear()
	var crest := Teams.logo(_team)
	var rink := _arena.rink as Rink
	rink.set_center_logo(crest)
	var home := _preview("home")
	var road := _preview("road")
	var abbr := _abbr()
	for k in 2:
		var which: String = SETS[k]
		var s: Skater = SKATER_SCENE.instantiate()
		var u := home if k == 0 else road
		s.uniform = u
		s.team_color = u.jersey
		s.club_colors = [home.jersey, road.jersey]
		if crest:
			s.crest = crest
		var p := CustomPlayers.blank()
		p.last = abbr
		p.number = 19 if k == 0 else 91
		p.gender = "Male" if k == 0 else "Female"
		p.height_in = 74 if k == 0 else 69
		p.weight_lbs = 205 if k == 0 else 165
		p.hair_style = "messy" if k == 0 else "braid"
		CustomPlayers.apply(s, p)
		s.puck = _arena.puck
		s.rink = _arena.rink
		s.fatigue_enabled = false
		_stage.add_child(s)
		s.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _tt: float) -> void: pass)
		s.teammates = [s]
		# The set being edited stands a step nearer the camera.
		var x := (-0.5 if k == 0 else 0.5) * PAIR_GAP * 2.0
		var z := 0.55 if which == _which else -0.35
		if _back_view:
			z = -z
		s.place(SPOT + Vector3(x, 0, z), Vector3.BACK)
		if s.visual != null:
			s.visual.display_pose = "side"
			if s.visual.face != null:
				s.visual.face.look_at_camera = true
			s.visual.snap()
		_players.append(s)


func _place_camera() -> void:
	if _cam == null:
		return
	var look := SPOT + Vector3(0, 0.9, 0)
	var yaw := _yaw + sin(_time * 0.25) * 0.1
	var pitch := 0.1
	var d := 6.2
	_cam.look_at_from_position(look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d, look)
	var half_h := tan(deg_to_rad(_cam.fov * 0.5)) * d
	var half_w := half_h * get_viewport_rect().size.aspect()
	_cam.h_offset = -0.5 * half_w
	_cam.v_offset = 0.12 * half_h


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


## Top right: the team, which uniform, and whether it's been changed.
func _draw_card() -> void:
	var r := CARD
	r.position.x = _canvas.size.x - r.size.x - 50.0
	var col := MenuStyle.team_color(_team)
	MenuStyle.draw_slant(_card, Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.35), 22.0)
	MenuStyle.draw_slant(_card, r, Color(0.03, 0.05, 0.1, 0.85), 22.0)
	MenuStyle.draw_slant(_card, Rect2(r.position, Vector2(r.size.x, 5)), col, 2.0)
	var x := r.position.x + 30.0
	var logo := Teams.logo(_team)
	if logo:
		var s := 96.0
		var lw := MenuStyle.logo_slot(logo, s)   # (wide crests get a wider slot)
		MenuStyle.draw_logo(_card, logo, Rect2(x, r.position.y + 16, lw, s))
		x += lw + 22.0
	var name := Teams.full_name(_team).to_upper()
	var fs := 30
	while fs > 16 and MenuStyle.text_width(name, fs) > r.end.x - x - 20.0:
		fs -= 2
	MenuStyle.draw_bold(_card, Vector2(x, r.position.y + 54), name, fs, Color.WHITE, 0, MenuStyle.INK)
	var what := "%s UNIFORM" % _which.to_upper()
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, r.position.y + 86), what, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.86, 0.45))
	var state := "UNSAVED CHANGES" if _dirty() else ("EDITED" if _edited() else "ORIGINAL")
	_card.draw_string(MenuStyle.font(0.12), Vector2(x, r.position.y + 112), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(1, 0.7, 0.45) if _dirty() else MenuStyle.DIM)
	# A swatch beside each color row's value.
	for i in _rows.size():
		var key: String = _rows[i].key
		if key in Uniforms.COLOR_KEYS and i < _items.size():
			var it := _items[i]
			var sw := Rect2(it.position + Vector2(ROW_SIZE.x - VALUE_W - 40.0, 8.0), Vector2(24, ROW_SIZE.y - 16.0))
			_card.draw_rect(sw.grow(2.0), Color(0, 0, 0, 0.6))
			_card.draw_rect(sw, Color.html(str(_u.colors.get(key, "000000"))))
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := MenuStyle.text_width(_toast, 24)
		var tp := Vector2(r.end.x - tw - 20.0, r.end.y + 52)
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
			"reset":
				hint = "Press %s again to put the original uniform back." % _input.accept_label()
	var prompts := []
	if _index < _rows.size():
		prompts.append([_input.accept_label(), "SELECT" if _rows[_index].kind == "action" else "CHANGE"])
	prompts.append([_input.button_label("triangle"), "FRONT" if _back_view else "BACK VIEW"])
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
		await get_tree().create_timer(0.3).timeout
		Uniforms.save_set(_abbr(), _which, _u)
		_saved = JSON.stringify(_u)
		_rebuild_in = 0.0
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
