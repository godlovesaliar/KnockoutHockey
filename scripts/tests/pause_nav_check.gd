extends Node
## Pause menu navigation with simulated keys (MenuInput reads every keyboard and pad the
## same way): S / W move, Enter picks, Esc goes back or resumes.
##   godot --headless --path . res://scenes/tests/PauseNavCheck.tscn

var fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		fails += 1


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		for i in 2:
			await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m := PauseMenu.new()
	add_child(m)
	for i in 3:
		await get_tree().process_frame
	_check(get_tree().paused, "opening pauses the game")
	_check(m._index == 0, "starts on Resume (%d)" % m._index)
	await _key(KEY_S)
	_check(m._index == 1, "S -> Controls (%d)" % m._index)
	await _key(KEY_S)
	await _key(KEY_W)
	_check(m._index == 1, "S then W -> back on Controls (%d)" % m._index)
	await _key(KEY_ENTER)
	_check(m._controls.visible, "Enter opens Controls")
	await _key(KEY_ESCAPE)
	_check(m._main.visible and m._index == 0, "Esc goes back to the list (%d)" % m._index)
	var closed := [false]
	m.closed.connect(func() -> void: closed[0] = true)
	await _key(KEY_ENTER)
	_check(closed[0] and not get_tree().paused, "Enter on Resume closes and unpauses")
	var m2 := PauseMenu.new()
	add_child(m2)
	for i in 3:
		await get_tree().process_frame
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused and not is_instance_valid(m2) or m2.is_queued_for_deletion(), "Esc resumes")
	print("PAUSE NAV %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(fails)
