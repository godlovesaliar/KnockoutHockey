class_name PauseMenu
extends CanvasLayer
## In-game pause menu (Esc / Start), in the front-end style: the game dimmed behind, the
## mode tag and PAUSED heading, slanted bars (Resume, Controls, Restart, Quit to menu)
## and the prompt bar. Controls opens a button chart in place. The game tree is paused
## while it's open; the menu runs anyway (PROCESS_MODE_ALWAYS).
##
## Any keyboard or pad drives it (MenuInput), the mouse too. Accept picks; Back (Circle / Esc)
## or Start resumes (from the chart: back to the list).
## Set `mode` ("EXHIBITION", "PRACTICE") and `restart_text` before adding it.
## `camera_host` (a MatchDirector or Practice: `camera`, `camera_follow`, `apply_camera()`,
## `human_team()`) adds CAMERA and CAMERA TURNS items that change the play angle live;
## the choice is kept in GameSettings for the next game.

signal closed

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

## Every control: [action, pad, keyboard 1, keyboard 2].
const CONTROLS := [
	["Skate", "L-STICK", "W A S D", "ARROWS"],
	["Pass (tap) · saucer (hold) · switch player on defense", "CROSS", "J", "NUM 1"],
	["Shoot (tap wrist, hold slap) · hook on defense", "SQUARE", "K", "NUM 2"],
	["Check (hold for a bigger hit)", "CIRCLE", "L", "NUM 3"],
	["Deke · poke check on defense", "TRIANGLE", "I", "NUM 5"],
	["Turbo", "R2", "SHIFT", "NUM 0"],
	["Skate backwards (hold)", "L2", "Q", "NUM 6"],
	["Protect the puck (hold): slower, harder to strip", "L1", "SPACE", "NUM ENTER"],
	["Pause", "START", "ESC", "ESC"],
]
const TIPS := [
	"One-timer: hold shoot while a pass is on its way.   Goalie with the puck: Cross pass out, Square clear, Triangle cover.",
	"Fights: Cross jab · Square cross · Triangle hook · hold L1 for body shots · Circle grab (holding: Cross cross, Square hook, Triangle uppercut) · mash Circle to break free or hang on · hold R1 block (+L1 low) · stick up / down slips.",
]

const ITEM_POS := Vector2(118, 250)
const ITEM_SIZE := Vector2(540, 56)
const ITEM_GAP := 12.0

var mode := "EXHIBITION"
var restart_text := "RESTART GAME"
var camera_host: Node

var _canvas: Control
var _input: MenuInput
var _items: Array[MenuItem] = []
var _actions: Array[Callable] = []
var _hints: Array[String] = []
var _index := 0
var _main: Control
var _controls: Control
var _chart: Control
var _back_item: MenuItem
var _header: Control
var _footer: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.85))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	g.add_point(0.5, Color(0.02, 0.04, 0.1, 0.6))
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
	_header.draw.connect(func() -> void:
		MenuStyle.draw_tag(_header, Vector2(60, 40), mode, "CONTROLS" if _controls.visible else "PAUSED"))
	_canvas.add_child(_header)

	_input = MenuInput.new()
	_input.start_accepts = false
	add_child(_input)
	_input.moved.connect(_move)
	_input.accepted.connect(_accept)
	_input.back.connect(_back)
	_input.started.connect(_back)

	_build_main()
	_build_controls()
	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_canvas.add_child(_footer)
	_show_main()
	get_tree().paused = true
	Sfx.play("pad", Vector3.INF, -8.0)


func _process(_delta: float) -> void:
	_footer.queue_redraw()
	_header.queue_redraw()


func _build_main() -> void:
	_main = Control.new()
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_main)
	var entries := [
		["RESUME", _resume, "Back to the game."],
		["CONTROLS", _show_controls, "Every button, on pad and both keyboards."],
	]
	if camera_host:
		entries.append(["CAMERA", _next_camera, "The play angle. Pick to switch."])
		if camera_host.human_team() >= 0:
			entries.append(["CAMERA TURNS", _toggle_follow, "With my team: the view turns at the change of ends so you always attack up."])
	entries.append_array([
		[restart_text, _restart, {"PRACTICE": "Start the practice over.", "KNOCKOUT MODE": "Start the card over: new fighters, new pairs."}.get(mode, "Start over from the opening faceoff.")],
		["QUIT TO MENU", _quit, "Leave this game for the main menu."],
	])
	for i in entries.size():
		var it := MenuItem.new()
		it.text = entries[i][0]
		it.position = ITEM_POS + Vector2(0, i * (ITEM_SIZE.y + ITEM_GAP))
		it.size = ITEM_SIZE
		it.intro(0.03 + i * 0.04)
		it.hovered.connect(func() -> void:
			if _index != i:
				_select(i))
		it.clicked.connect(func() -> void:
			_select(i, true)
			_accept())
		_main.add_child(it)
		_items.append(it)
		_actions.append(entries[i][1])
		_hints.append(entries[i][2])
	_refresh_camera()


func _refresh_camera() -> void:
	if camera_host == null:
		return
	for it in _items:
		if it.text == "CAMERA":
			it.value = BroadcastCamera.label_of(camera_host.camera)
			it.value_w = 190.0
		elif it.text == "CAMERA TURNS":
			it.value = "My team" if camera_host.camera_follow else "Never"
			it.value_w = 190.0


func _next_camera() -> void:
	var modes := BroadcastCamera.PLAY_MODES
	var cur := BroadcastCamera.Mode.keys().find(str(camera_host.camera).to_upper())
	var next: int = modes[(modes.find(cur) + 1) % modes.size()]
	var angle := str(BroadcastCamera.Mode.keys()[next]).to_lower()
	camera_host.apply_camera(angle, camera_host.camera_follow)
	GameSettings.config["camera"] = angle
	GameSettings.save_settings()
	_refresh_camera()


func _toggle_follow() -> void:
	camera_host.apply_camera(camera_host.camera, not camera_host.camera_follow)
	GameSettings.config["camera_follow"] = camera_host.camera_follow
	GameSettings.save_settings()
	_refresh_camera()


func _build_controls() -> void:
	_controls = Control.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_controls)
	_chart = Control.new()
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.draw.connect(_draw_chart)
	_controls.add_child(_chart)
	_back_item = MenuItem.new()
	_back_item.text = "BACK"
	_back_item.position = Vector2(118, 752)
	_back_item.size = Vector2(300, 50)
	_back_item.clicked.connect(_show_main)
	_controls.add_child(_back_item)


func _show_main() -> void:
	_controls.visible = false
	_main.visible = true
	_select(0, true)


func _show_controls() -> void:
	_main.visible = false
	_controls.visible = true
	_back_item.selected = true
	_back_item.glyph = _input.accept_label()
	_back_item.glyph_pad = _input.using_pad
	_back_item.intro(0.0)


func _select(i: int, quiet := false) -> void:
	_index = i
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = _input.accept_label()
		_items[k].glyph_pad = _input.using_pad
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


func _move(dir: int) -> void:
	if _main.visible:
		_select(wrapi(_index + dir, 0, _items.size()))


func _accept() -> void:
	if _controls.visible:
		_show_main()
		return
	Sfx.play("glove", Vector3.INF, -6.0)
	_actions[_index].call()


func _back() -> void:
	if _controls.visible:
		_show_main()
	else:
		_resume()


func _resume() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().paused = false
	if ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file(MENU_SCENE)
	else:
		get_tree().quit()


## The button chart: a dark panel, one striped row per action, pad buttons as colored
## face buttons and keys as key caps.
func _draw_chart() -> void:
	draw_controls_chart(_chart, _canvas.size.x)


## The controls chart, drawn into `ci` on the 1600 x 900 menu canvas `w` wide (the options
## screen shows it too).
static func draw_controls_chart(ci: CanvasItem, w: float, y := 175.0) -> void:
	var x := 80.0
	var pw := minf(w - 160.0, 1440.0)
	var row_h := 48.0
	var cols := [x + pw * 0.56, x + pw * 0.68, x + pw * 0.84]
	var f := MenuStyle.font(0.12)
	ci.draw_rect(Rect2(x, y, pw, 70 + row_h * CONTROLS.size() + 112), Color(0.03, 0.05, 0.1, 0.82))
	ci.draw_rect(Rect2(x, y, pw, 3), MenuStyle.RED)
	for c in 3:
		ci.draw_string(f, Vector2(cols[c], y + 44), ["PAD", "KEYBOARD 1", "KEYBOARD 2"][c],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MenuStyle.DIM)
	for i in CONTROLS.size():
		var r: Array = CONTROLS[i]
		var ry := y + 64 + i * row_h
		if i % 2 == 0:
			ci.draw_rect(Rect2(x + 10, ry, pw - 20, row_h), Color(1, 1, 1, 0.04))
		ci.draw_string(f, Vector2(x + 30, ry + 32), r[0], HORIZONTAL_ALIGNMENT_LEFT, cols[0] - x - 50, 21, Color.WHITE)
		for c in 3:
			MenuStyle.draw_glyph(ci, Vector2(cols[c], ry + 8), r[c + 1], c == 0, 32.0)
	var ty := y + 64 + CONTROLS.size() * row_h + 34
	for t: String in TIPS:
		ci.draw_string(f, Vector2(x + 30, ty), t, HORIZONTAL_ALIGNMENT_LEFT, pw - 60, 18, Color(1.0, 0.86, 0.7))
		ty += 32


func _draw_footer() -> void:
	var hint := "The game is paused." if _controls.visible else _hints[_index]
	var prompts := [[_input.back_label(), "BACK"]] if _controls.visible \
			else [[_input.accept_label(), "SELECT"], [_input.back_label(), "RESUME"]]
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint, prompts, _input.using_pad)
