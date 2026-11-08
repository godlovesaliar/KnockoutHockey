class_name PauseMenu
extends CanvasLayer
## In-game pause menu (Esc / Start): Resume, Controls, Restart, Quit to menu. The game
## tree is paused while it's open; the menu runs anyway (PROCESS_MODE_ALWAYS). Navigate
## with the d-pad / arrows / mouse, A / Enter to choose, B / Esc / Start to go back.

signal closed

const MENU_SCENE := "res://scenes/ui/MatchSetup.tscn"

## Every control: [action, pad, keyboard 1, keyboard 2].
const CONTROLS := [
	["Skate", "Left stick", "W A S D", "Arrows"],
	["Pass (tap) · saucer (hold) · switch player on defense", "A", "J", "Num1 / ,"],
	["Shoot (tap wrist, hold slap) · hook on defense", "X", "K", "Num2 / ."],
	["Check (hold for a bigger hit)", "B", "L", "Num3 / /"],
	["Deke · poke check on defense", "Y", "I", "Num5 / ;"],
	["Turbo", "RT", "Shift", "Num0 / R-Ctrl"],
	["Skate backwards (hold)", "LT", "Q", "Num6 / M"],
	["Protect the puck (hold): slower, harder to strip", "LB", "Space", "NumEnter / '"],
	["Pause", "Start", "Esc", "Esc"],
]

const STICK_ON := 0.6
const STICK_OFF := 0.3

var _stick := {}    ## device -> last left-stick direction (-1, 0, 1)
var _box: VBoxContainer
var _main: VBoxContainer
var _controls: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	center.add_child(_box)
	_build_main()
	_build_controls()
	_show_main()
	get_tree().paused = true


func _build_main() -> void:
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 12)
	_main.add_child(_label("PAUSED", 48, Color(1.0, 0.85, 0.2)))
	for item in [["Resume", _resume], ["Controls", _show_controls], ["Restart game", _restart], ["Quit to menu", _quit]]:
		var b := Button.new()
		b.text = "   %s   " % item[0]
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(item[1])
		_main.add_child(b)
	_box.add_child(_main)


func _build_controls() -> void:
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 10)
	_controls.add_child(_label("CONTROLS", 40, Color(1.0, 0.85, 0.2)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	for h in ["", "Pad", "Keyboard 1", "Keyboard 2"]:
		grid.add_child(_label(h, 20, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_LEFT))
	for row: Array in CONTROLS:
		grid.add_child(_label(row[0], 19, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
		for k in range(1, 4):
			grid.add_child(_label(row[k], 19, Color(1.0, 0.9, 0.55), HORIZONTAL_ALIGNMENT_LEFT))
	_controls.add_child(grid)
	_controls.add_child(_label("A one-timer: hold shoot while a pass is on its way.  Goalie with the puck: A pass out, X clear, Y cover.", 16, Color(0.75, 0.8, 0.9)))
	_controls.add_child(_label("Fights — A jab · X haymaker · B grab / break free · RT uppercut (while holding) · hold Y block · stick toward / away: step in / back off · up / down: slip (keyboard: same keys as pass / shoot / check / turbo / deke)", 16, Color(1.0, 0.75, 0.6)))
	var back := Button.new()
	back.text = "   Back   "
	back.add_theme_font_size_override("font_size", 24)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_show_main)
	_controls.add_child(back)
	_box.add_child(_controls)


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _show_main() -> void:
	_controls.visible = false
	_main.visible = true
	(_main.get_child(1) as Button).grab_focus()


func _show_controls() -> void:
	_main.visible = false
	_controls.visible = true
	(_controls.get_child(_controls.get_child_count() - 1) as Button).grab_focus()


## Buttons on the page that's showing, top to bottom.
func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in (_controls if _controls.visible else _main).get_children():
		if c is Button:
			out.append(c)
	return out


func _move_focus(step: int) -> void:
	var bs := _buttons()
	if bs.is_empty():
		return
	var i := bs.find(get_viewport().gui_get_focus_owner())
	i = 0 if i < 0 else wrapi(i + step, 0, bs.size())
	bs[i].grab_focus()


func _press_focused() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is Button and f.is_visible_in_tree():
		(f as Button).pressed.emit()
	elif not _buttons().is_empty():
		_buttons()[0].grab_focus()


## Menu navigation by hand, so every pad works the same: d-pad or left stick to move,
## A to choose (plus arrows / W S and Enter / Space on the keyboard).
func _navigate(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				_move_focus(-1)
			JOY_BUTTON_DPAD_DOWN:
				_move_focus(1)
			JOY_BUTTON_A:
				_press_focused()
			_:
				return false
		return true
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		var dev: int = event.device
		var dir := 0
		if event.axis_value < -STICK_ON:
			dir = -1
		elif event.axis_value > STICK_ON:
			dir = 1
		elif absf(event.axis_value) > STICK_OFF:
			return true   # between thresholds: keep the stick's last state
		if dir != int(_stick.get(dev, 0)) and dir != 0:
			_move_focus(dir)
		_stick[dev] = dir
		return true
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_UP, KEY_W:
				_move_focus(-1)
			KEY_DOWN, KEY_S:
				_move_focus(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if event.echo:
					return true
				_press_focused()
			_:
				return false
		return true
	return false


func _input(event: InputEvent) -> void:
	if _navigate(event):
		get_viewport().set_input_as_handled()
		return
	var back: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START])
	if not back:
		return
	get_viewport().set_input_as_handled()
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
