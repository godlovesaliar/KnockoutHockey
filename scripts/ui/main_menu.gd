extends Control
## Title screen: the chrome KNOCKOUT HOCKEY title over a live arena shot, a column of
## slanted menu bars, and a prompt bar along the bottom. Any keyboard or pad drives it
## (MenuInput); the mouse works too. GAME MODES, CUSTOMIZE and GAME EXTRAS open a second
## list in place.
##
## `-- shot=<png> [wait=<s>] [sel=<n>] [list=modes|customize|extras]` saves a screenshot and quits.

const SETUP_SCENE := "res://scenes/ui/TeamSelect.tscn"
const PRACTICE_SCENE := "res://scenes/match/Practice.tscn"
const OPTIONS_SCENE := "res://scenes/ui/Options.tscn"
const CREDITS_SCENE := "res://scenes/ui/Credits.tscn"
const CREATE_PLAYER_SCENE := "res://scenes/ui/CreatePlayer.tscn"

const MAIN := [
	{"id": "play", "text": "PLAY NOW", "hint": "Pick your teams and controllers, then drop the puck."},
	{"id": "modes", "text": "GAME MODES", "hint": "Exhibition, practice and more."},
	{"id": "season", "text": "SEASON MODE", "soon": true, "hint": "Take a team through a full season and the playoffs."},
	{"id": "customize", "text": "CUSTOMIZE", "hint": "Create your own players, teams, arenas and uniforms."},
	{"id": "options", "text": "RULES AND OPTIONS", "hint": "Default rules, controls, audio and video."},
	{"id": "extras", "text": "GAME EXTRAS", "hint": "Credits, records and unlockables."},
	{"id": "quit", "text": "QUIT", "hint": "Back to the desktop."},
]
const MODES := [
	{"id": "play", "text": "EXHIBITION", "hint": "A single game: any two teams, your rules."},
	{"id": "knockout", "text": "KNOCKOUT MODE", "hint": "Pick two teams: five fights between random players. Best score wins."},
	{"id": "practice", "text": "PRACTICE", "hint": "Free skate with your line against pylons. Esc to come back."},
	{"id": "shootout", "text": "SHOOTOUT", "soon": true, "hint": "Straight to the shootout."},
	{"id": "back", "text": "BACK", "hint": "Back to the main menu."},
]
const CUSTOMIZE := [
	{"id": "create_player", "text": "CREATE PLAYER", "hint": "Build a skater or goalie: look, equipment and ratings."},
	{"id": "create_team", "text": "CREATE TEAM", "soon": true, "hint": "Build your own club: name, colors, logo and roster."},
	{"id": "create_arena", "text": "CREATE ARENA", "soon": true, "hint": "Design a home rink: ice, boards, seats and lights."},
	{"id": "create_uniform", "text": "CREATE UNIFORM", "soon": true, "hint": "Design jerseys, pants, socks and helmets."},
	{"id": "edit_roster", "text": "EDIT ROSTER", "soon": true, "hint": "Sign free agents (your created players) and move players between teams."},
	{"id": "back", "text": "BACK", "hint": "Back to the main menu."},
]
const EXTRAS := [
	{"id": "credits", "text": "CREDITS", "hint": "Who made what: models, music, sound and code."},
	{"id": "records", "text": "RECORDS", "soon": true, "hint": "Your best games and season records."},
	{"id": "unlockables", "text": "UNLOCKABLES", "soon": true, "hint": "Secret teams, rinks and cheats."},
	{"id": "back", "text": "BACK", "hint": "Back to the main menu."},
]

const ITEM_POS := Vector2(118, 346)
const ITEM_SIZE := Vector2(560, 52)
const ITEM_GAP := 10.0

var _canvas: Control
var _list: Control
var _items: Array[MenuItem] = []
var _entries: Array = MAIN
var _index := 0
var _main_index := 0
var _input: MenuInput
var _footer: Control
var _heading: Label
var _fade: ColorRect
var _title: Control
var _t := 0.0
var _leaving := false


func _ready() -> void:
	Sfx.play_music()
	add_child(MenuBackdrop.new())
	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(_move)
	_input.accepted.connect(_accept)
	_input.back.connect(_back)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	# Darken the left side so the menu reads over the bright ice.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.78))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	g.add_point(0.42, Color(0.02, 0.04, 0.1, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2.ZERO
	shade.size = Vector2(1150, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_title)
	var w1 := MenuStyle.chrome_text("KNOCKOUT", 120)
	w1.position = Vector2(70, 26)
	_title.add_child(w1)
	var w2 := MenuStyle.chrome_text("HOCKEY", 120)
	w2.position = Vector2(150, 156)
	_title.add_child(w2)
	_title.pivot_offset = Vector2(420, 190)

	_heading = Label.new()
	_heading.add_theme_font_override("font", MenuStyle.font(0.2))
	_heading.add_theme_font_size_override("font_size", 26)
	_heading.add_theme_color_override("font_color", Color(1, 0.86, 0.86))
	_heading.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_heading.add_theme_constant_override("outline_size", 8)
	_canvas.add_child(_heading)

	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_list)

	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_canvas.add_child(_footer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)

	var lists := {"modes": MODES, "customize": CUSTOMIZE, "extras": EXTRAS}
	var sel := int(_arg("sel", str(maxi(GameSettings.menu_select, 0))))
	var list := _arg("list", GameSettings.menu_list)
	GameSettings.menu_select = -1
	GameSettings.menu_list = ""
	if list != "":
		_main_index = MAIN.map(func(d: Dictionary) -> String: return d.id).find(list)
	_show_list(lists.get(list, MAIN), sel)


func _process(delta: float) -> void:
	_t += delta
	# The title drops in, then breathes very slightly.
	var k := clampf(_t / 0.55, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_title.modulate.a = e
	_title.scale = Vector2.ONE * (lerpf(1.25, 1.0, e) + sin(_t * 1.3) * 0.004)
	_footer.queue_redraw()


func _show_list(entries: Array, select := 0) -> void:
	for it in _items:
		it.queue_free()
	_items.clear()
	_entries = entries
	_heading.text = _heading_for(entries)
	var top := ITEM_POS + Vector2(0, 56 if _heading.text != "" else 0)   # room for the heading
	_heading.position = top + Vector2(30, -46)
	for i in entries.size():
		var d: Dictionary = entries[i]
		var it := MenuItem.new()
		it.text = d.text
		it.soon = d.get("soon", false)
		it.position = top + Vector2(0, i * (ITEM_SIZE.y + ITEM_GAP))
		it.size = ITEM_SIZE
		it.intro(0.15 + i * 0.05)
		it.hovered.connect(func() -> void:
			if _index != i:
				_select(i))
		it.clicked.connect(func() -> void:
			_select(i)
			_accept())
		_list.add_child(it)
		_items.append(it)
	_select(clampi(select, 0, entries.size() - 1), true)


## The heading shown over a second-level list (none over MAIN).
func _heading_for(entries: Array) -> String:
	if entries == MODES:
		return "GAME MODES"
	if entries == CUSTOMIZE:
		return "CUSTOMIZE"
	if entries == EXTRAS:
		return "GAME EXTRAS"
	return ""


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label()
		_items[k].glyph_pad = _input.using_pad
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _move(dir: int) -> void:
	if _leaving:
		return
	_select(wrapi(_index + dir, 0, _items.size()))


func _accept() -> void:
	if _leaving or _items.is_empty():
		return
	var d: Dictionary = _entries[_index]
	if d.get("soon", false):
		_items[_index].nudge()
		Sfx.play("pad", Vector3.INF, -6.0)
		return
	Sfx.play("glove", Vector3.INF, -4.0)
	match d.id:
		"play":
			GameSettings.mode = "exhibition"
			_go(SETUP_SCENE)
		"knockout":
			GameSettings.mode = "knockout"
			_go(SETUP_SCENE)
		"practice":
			Sfx.stop_music(1.0)
			_go(PRACTICE_SCENE)
		"modes":
			_main_index = _index
			_show_list(MODES)
		"customize":
			_main_index = _index
			_show_list(CUSTOMIZE)
		"extras":
			_main_index = _index
			_show_list(EXTRAS)
		"options":
			_go(OPTIONS_SCENE)
		"credits":
			_go(CREDITS_SCENE)
		"create_player":
			_go(CREATE_PLAYER_SCENE)
		"back":
			_show_list(MAIN, _main_index)
		"quit":
			_leaving = true
			var tw := create_tween()
			Sfx.stop_music(0.3)
			tw.tween_property(_fade, "color:a", 1.0, 0.3)
			tw.tween_callback(get_tree().quit)


func _back() -> void:
	if _leaving:
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	if _entries != MAIN:
		_show_list(MAIN, _main_index)
	elif _index != MAIN.size() - 1:
		_select(MAIN.size() - 1, true)   # back on the main list lands on QUIT


func _go(scene: String) -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


func _draw_footer() -> void:
	var hint: String = _entries[_index].get("hint", "") if _index < _entries.size() else ""
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint,
			[[_input.accept_label(), "SELECT"], [_input.back_label(), "BACK"]], _input.using_pad)


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
