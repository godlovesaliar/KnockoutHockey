extends SceneTree
## Pause menu navigation with simulated pad input: d-pad, left stick, A, B.
##   godot --headless --path . -s res://scripts/tests/pause_nav_check.gd

var fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		fails += 1

func _btn(i: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = i
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventJoypadButton.new()
	u.button_index = i
	Input.parse_input_event(u)

func _stick(v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	Input.parse_input_event(e)

func _focus() -> String:
	var f := root.gui_get_focus_owner()
	return (f as Button).text.strip_edges() if f is Button else "<none>"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var m := PauseMenu.new()
	root.add_child(m)
	await process_frame
	_check(_focus() == "Resume", "starts on Resume (%s)" % _focus())
	_btn(JOY_BUTTON_DPAD_DOWN); await process_frame
	_check(_focus() == "Controls", "d-pad down -> Controls (%s)" % _focus())
	_stick(0.9); await process_frame
	_stick(0.95); await process_frame
	_check(_focus() == "Restart game", "stick down once -> Restart (%s)" % _focus())
	_stick(0.0); await process_frame
	_stick(-0.9); await process_frame
	_check(_focus() == "Controls", "stick up -> Controls (%s)" % _focus())
	_btn(JOY_BUTTON_A); await process_frame
	_check(m._controls.visible, "A opens Controls")
	_btn(JOY_BUTTON_B); await process_frame
	_check(m._main.visible and _focus() == "Resume", "B goes back (%s)" % _focus())
	var closed := [false]
	m.closed.connect(func() -> void: closed[0] = true)
	_btn(JOY_BUTTON_A); await process_frame
	_check(closed[0] and not paused, "A on Resume closes and unpauses")
	print("PAUSE NAV %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(fails)
