extends Control
## GAME EXTRAS > CREDITS: a credits roll in the menu style over the arena. It scrolls on its
## own; up / down (or the mouse wheel) takes over for a moment. Back: the main menu.
##
## Every CC-BY asset in the game must be listed here (and in assets/CREDITS.md, which has
## the files and links). `-- shot=<png> [wait=<s>] [scroll=<px>]` saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

## [kind, text, (detail)]: "head" a section heading, "item" a name with a detail line under
## it, "line" a plain line, "gap" some space.
const ROLL := [
	["title", "KNOCKOUT HOCKEY"],
	["gap"],
	["head", "GAME"],
	["item", "Design, teams and rosters", "Booker"],
	["item", "Team logos and board ads", "Booker, made with Google Gemini"],
	["item", "Built with", "Godot Engine 4.7 (MIT license, Juan Linietsky, Ariel Manzur and contributors)"],
	["item", "Physics", "Jolt Physics (MIT license, Jorrit Rouwe)"],
	["gap"],
	["head", "PLAYERS"],
	["item", "Female Character Base - Rigged", "Braingapps · Sketchfab · CC BY 4.0"],
	["item", "Male Character Base - Rigged", "Braingapps · Sketchfab · CC BY 4.0"],
	["item", "Rigging and animations", "Mixamo (Adobe)"],
	["item", "Hair and Beard Pubg Mobile 3D Model", "BilloXD · Sketchfab · CC BY 4.0"],
	["item", "MOSTACHE", "vajidkm · Sketchfab · CC BY 4.0"],
	["item", "ported hair", "bbb59149 · Sketchfab · CC BY 4.0"],
	["gap"],
	["head", "EQUIPMENT"],
	["item", "Helmet for Puck (goalie mask)", "Domenico (@K31THUZ4D) · Sketchfab · CC BY 4.0"],
	["item", "Hockey Goalie Mask", "matýsek (@matyprokop09), remade by Mat3ssZ3Dd · Sketchfab · CC BY 4.0"],
	["gap"],
	["head", "FONTS"],
	["item", "Playstation Buttons (button prompts)", "TracerTong · fonts4free.net · Free for personal use"],
	["gap"],
	["head", "SOUND AND MUSIC"],
	["item", "Sound effects, crowd, organ and announcers", "Generated with ElevenLabs"],
	["item", "Extreme Sports - Extreme", "GR0ZA · Pixabay · Pixabay Content License"],
	["item", "Uplifting Action Sport Energetic Rock", "ikoliks · Pixabay · Pixabay Content License"],
	["item", "Sports - Sport Rock", "JonasBlakewood · Pixabay · Pixabay Content License"],
	["item", "Surf Rock", "Alex Morgan · Pixabay · Pixabay Content License"],
	["item", "Indie Rock", "AtlasAudio · Pixabay · Pixabay Content License"],
	["item", "Rock Instrumental", "SigmaMusicArt · Pixabay · Pixabay Content License"],
	["item", "Hip Hop Beat Urban Rap", "Sound4Stock · Pixabay · Pixabay Content License"],
	["item", "East Coast Instrumental", "Sub_Clair · Pixabay · Pixabay Content License"],
	["item", "Powerful Rock", "The_Mountain · Pixabay · Pixabay Content License"],
	["gap"],
	["line", "All teams and players are fictional. Some board ads are parodies."],
	["line", "Thanks for playing."],
]

const PANEL := Rect2(260, 150, 1080, 650)
const SPEED := 46.0          ## pixels a second, rolling on its own
const MANUAL_HOLD := 2.5     ## seconds the roll waits after you scroll it

var _canvas: Control
var _panel: Control
var _roll: Control
var _input: MenuInput
var _footer: Control
var _fade: ColorRect
var _scroll := 0.0
var _hold := 0.0
var _height := 0.0
var _leaving := false


func _ready() -> void:
	Sfx.play_music()
	add_child(MenuBackdrop.new())
	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void: _nudge(dir * 70.0))
	_input.accepted.connect(_back)
	_input.back.connect(_back)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.1, 0.55)
	shade.size = Vector2(4000, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	var header := Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.draw.connect(func() -> void: MenuStyle.draw_tag(header, Vector2(60, 40), "GAME EXTRAS", "CREDITS"))
	_canvas.add_child(header)

	_panel = Control.new()
	_panel.position = PANEL.position
	_panel.size = PANEL.size
	_panel.clip_contents = true
	_panel.draw.connect(func() -> void:
		_panel.draw_rect(Rect2(Vector2.ZERO, PANEL.size), Color(0.03, 0.05, 0.1, 0.72))
		_panel.draw_rect(Rect2(0, 0, PANEL.size.x, 3), MenuStyle.RED))
	_panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_nudge(60.0)
			elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_nudge(-60.0))
	_canvas.add_child(_panel)
	_roll = Control.new()
	_roll.size = PANEL.size
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.draw.connect(_draw_roll)
	_panel.add_child(_roll)

	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(func() -> void:
		MenuStyle.draw_footer(_footer, _canvas.size.x, "Up / down to scroll.",
				[[_input.back_label(), "BACK"]], _input.using_pad))
	_canvas.add_child(_footer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)

	_height = _measure()
	_scroll = -PANEL.size.y * 0.35 if _arg("scroll", "") == "" else float(_arg("scroll", "0"))
	if _arg("scroll", "") != "":
		_hold = 1e9   # a fixed spot for screenshots


func _process(delta: float) -> void:
	_hold = maxf(0.0, _hold - delta)
	if _hold <= 0.0:
		_scroll += SPEED * delta
	# Off the end: start again from below the panel.
	if _scroll > _height:
		_scroll = -PANEL.size.y
	_roll.queue_redraw()
	_footer.queue_redraw()


func _nudge(px: float) -> void:
	_hold = MANUAL_HOLD
	_scroll = clampf(_scroll + px, -PANEL.size.y * 0.5, _height)


## Height of the whole roll (and the step for each kind of line).
func _measure() -> float:
	var y := 0.0
	for r: Array in ROLL:
		y += _step(r[0])
	return y


static func _step(kind: String) -> float:
	match kind:
		"title": return 110.0
		"head": return 74.0
		"item": return 70.0
		"line": return 40.0
		_: return 34.0


func _draw_roll() -> void:
	var cx := PANEL.size.x * 0.5
	var y := -_scroll   # the roll's top, in the panel
	var f := MenuStyle.font(0.12)
	for r: Array in ROLL:
		var kind: String = r[0]
		var step := _step(kind)
		# Only draw what's in view.
		if y > -step and y < PANEL.size.y + step:
			match kind:
				"title":
					var tw := MenuStyle.text_width(r[1], 64)
					MenuStyle.draw_bold(_roll, Vector2(cx - tw * 0.5, y + 74), r[1], 64, Color.WHITE, 10, MenuStyle.RED_DARK)
				"head":
					var hw := MenuStyle.text_width(r[1], 30)
					MenuStyle.draw_slant(_roll, Rect2(cx - hw * 0.5 - 30, y + 18, hw + 60, 42), MenuStyle.RED, 16.0)
					MenuStyle.draw_bold(_roll, Vector2(cx - hw * 0.5 + 8, y + 50), r[1], 30, Color.WHITE, 0, MenuStyle.INK, 0.2, false)
				"item":
					var nw := f.get_string_size(r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
					_roll.draw_string(f, Vector2(cx - nw * 0.5, y + 30), r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
					var dw := f.get_string_size(r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
					var dc := Color(1.0, 0.72, 0.5) if str(r[2]).begins_with("Author to be added") else MenuStyle.DIM
					_roll.draw_string(f, Vector2(cx - dw * 0.5, y + 56), r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, dc)
				"line":
					var lw := f.get_string_size(r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
					_roll.draw_string(f, Vector2(cx - lw * 0.5, y + 28), r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.86, 0.86))
		y += step


func _back() -> void:
	if _leaving:
		return
	GameSettings.menu_select = 5
	Sfx.play("pad", Vector3.INF, -8.0)
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


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
