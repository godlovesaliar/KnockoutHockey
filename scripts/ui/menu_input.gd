class_name MenuInput
extends Node
## Menu navigation from every keyboard and pad at once. Held directions repeat.
## Remembers whether a pad or a keyboard spoke last, so screens can show that device's
## button prompts.
##
##   Keyboard 1: W A S D, accept J / Space / Enter, back L / Esc / Backspace, Q / E bumpers.
##   Keyboard 2: arrows, accept Num 1 / Num Enter, back Num 3, Num 7 / Num 9 bumpers.
##   Pads: d-pad or left stick, accept A, back B, Start, LB / RB bumpers.
##
## Screens that only need one cursor use moved / side / accepted / back. Screens where
## each controller acts for itself (team select) use the dev_* signals, which name the
## device: "kb1", "kb2" or "pad<n>" (the joypad id).

signal moved(dir: int)        ## -1 up, +1 down
signal side(dir: int)         ## -1 left, +1 right
signal accepted
signal back
signal started                ## pad Start (also counts as accepted, see start_accepts)
signal dev_moved(dev: String, dir: int)
signal dev_side(dev: String, dir: int)
signal dev_bumper(dev: String, dir: int)   ## -1 left bumper, +1 right
signal dev_accepted(dev: String)
signal dev_back(dev: String)

const REPEAT_FIRST := 0.38
const REPEAT_NEXT := 0.09

const KEYS := {
	"kb1": {"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"ok": [KEY_J, KEY_SPACE, KEY_ENTER], "back": [KEY_L, KEY_ESCAPE, KEY_BACKSPACE],
		"lb": [KEY_Q], "rb": [KEY_E]},
	"kb2": {"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"ok": [KEY_KP_1, KEY_KP_ENTER], "back": [KEY_KP_3], "lb": [KEY_KP_7], "rb": [KEY_KP_9]},
}

var using_pad := false
## Pad Start also counts as accept (front-end screens). The pause menu turns this off:
## there Start resumes.
var start_accepts := true
var _held := {}               ## "<dev>:v" / "<dev>:h" -> [dir, timer]
var _buttons := {}            ## previous button state per "<dev>:<button>"


func _ready() -> void:
	using_pad = not Input.get_connected_joypads().is_empty()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	for dev: String in KEYS:
		var k: Dictionary = KEYS[dev]
		_device(dev, false, delta, _keys(k.down) - _keys(k.up), _keys(k.right) - _keys(k.left),
				_keys(k.ok) > 0, _keys(k.back) > 0, false, _keys(k.lb) > 0, _keys(k.rb) > 0)
	for p in Input.get_connected_joypads():
		var y := Input.get_joy_axis(p, JOY_AXIS_LEFT_Y)
		var x := Input.get_joy_axis(p, JOY_AXIS_LEFT_X)
		var v := int(Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_DOWN) or y > 0.6) \
				- int(Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_UP) or y < -0.6)
		var h := int(Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_RIGHT) or x > 0.6) \
				- int(Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_LEFT) or x < -0.6)
		_device("pad%d" % p, true, delta, v, h, Input.is_joy_button_pressed(p, JOY_BUTTON_A),
				Input.is_joy_button_pressed(p, JOY_BUTTON_B), Input.is_joy_button_pressed(p, JOY_BUTTON_START),
				Input.is_joy_button_pressed(p, JOY_BUTTON_LEFT_SHOULDER),
				Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_SHOULDER))


## Labels for the prompt bar, matching the device in use.
func accept_label() -> String:
	return "A" if using_pad else "ENTER"


func back_label() -> String:
	return "B" if using_pad else "ESC"


func _device(dev: String, pad: bool, delta: float, v: int, h: int, ok: bool, bk: bool, start: bool, lb: bool, rb: bool) -> void:
	if _repeat(dev + ":v", v, delta):
		using_pad = pad
		dev_moved.emit(dev, v)
		moved.emit(v)
	if _repeat(dev + ":h", h, delta):
		using_pad = pad
		dev_side.emit(dev, h)
		side.emit(h)
	if _pressed(dev + ":ok", ok):
		using_pad = pad
		dev_accepted.emit(dev)
		accepted.emit()
	if _pressed(dev + ":back", bk):
		using_pad = pad
		dev_back.emit(dev)
		back.emit()
	if _pressed(dev + ":start", start):
		using_pad = pad
		started.emit()
		if start_accepts:
			accepted.emit()
	if _pressed(dev + ":lb", lb):
		using_pad = pad
		dev_bumper.emit(dev, -1)
	if _pressed(dev + ":rb", rb):
		using_pad = pad
		dev_bumper.emit(dev, 1)


func _keys(keys: Array) -> int:
	for k: Key in keys:
		if Input.is_physical_key_pressed(k):
			return 1
	return 0


## True when a held direction should fire (first press, then repeats).
func _repeat(key: String, dir: int, delta: float) -> bool:
	var st: Array = _held.get(key, [0, 0.0])
	if dir == 0:
		_held[key] = [0, 0.0]
		return false
	if dir != st[0]:
		_held[key] = [dir, REPEAT_FIRST]
		return true
	st[1] -= delta
	_held[key] = st
	if st[1] <= 0.0:
		st[1] = REPEAT_NEXT
		return true
	return false


## Fresh presses only. Buttons start "held", so a press carried over from the previous
## screen doesn't fire on this one.
func _pressed(key: String, down: bool) -> bool:
	var fire: bool = down and not _buttons.get(key, true)
	_buttons[key] = down
	return fire
