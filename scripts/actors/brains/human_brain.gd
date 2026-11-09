class_name HumanBrain
extends Brain
## One human player's controller. Kinds:
##   ANY  – the shared input map (keyboard 1 + any pad), for single-player
##   KB1  – WASD · J pass · K shoot · L check · I deke · Shift turbo · Space protect · Q backwards
##   KB2  – Arrows · Num1/, pass · Num2/. shoot · Num3// check · Num5/; deke · Num0/RCtrl turbo · NumEnter/' protect · Num6/M backwards
##   PAD  – one specific gamepad (A pass, X shoot, B check, Y deke, RT turbo, LT backwards, LB protect)
## Input is read once per physics frame and cached, so if control switches skaters
## mid-tick both see the same snapshot.

enum Kind { ANY, KB1, KB2, PAD }

const PLAYER_COLORS := [Color(1.0, 0.85, 0.15), Color(0.2, 0.9, 1.0), Color(0.4, 1.0, 0.35), Color(1.0, 0.4, 0.9)]

const KB1 := {
	"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
	"pass": [KEY_J], "shoot": [KEY_K], "check": [KEY_L], "deke": [KEY_I],
	"turbo": [KEY_SHIFT], "protect": [KEY_SPACE], "backward": [KEY_Q],
}
const KB2 := {
	"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
	"pass": [KEY_KP_1, KEY_COMMA], "shoot": [KEY_KP_2, KEY_PERIOD], "check": [KEY_KP_3, KEY_SLASH],
	"deke": [KEY_KP_5, KEY_SEMICOLON], "turbo": [KEY_KP_0, KEY_CTRL], "protect": [KEY_KP_ENTER, KEY_APOSTROPHE],
	"backward": [KEY_KP_6, KEY_M],
}
const PAD := {
	"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_X, "check": JOY_BUTTON_B, "deke": JOY_BUTTON_Y,
}
const BUTTONS := ["pass", "shoot", "check", "deke"]

var kind := Kind.ANY
var pad := 0
var player_index := 0             ## 0..3 → P1..P4 (ring color)
var team := 0

var _frame := -1
var _cur := {}
var _prev := {}


func _init(p_kind := Kind.ANY, p_pad := 0, p_index := 0, p_team := 0) -> void:
	kind = p_kind
	pad = p_pad
	player_index = p_index
	team = p_team


static func from_spec(spec: Dictionary, index: int) -> HumanBrain:
	var k: Kind = {"any": Kind.ANY, "kb1": Kind.KB1, "kb2": Kind.KB2, "pad": Kind.PAD}.get(str(spec.get("kind", "any")), Kind.ANY)
	return HumanBrain.new(k, int(spec.get("pad", 0)), index, int(spec.get("team", 0)))


func color() -> Color:
	return PLAYER_COLORS[player_index % PLAYER_COLORS.size()]


func device_name() -> String:
	match kind:
		Kind.KB1:
			return "Keyboard 1"
		Kind.KB2:
			return "Keyboard 2"
		Kind.PAD:
			return "Pad %d" % (pad + 1)
	return "Keyboard / Pad"


## What to press for a button on this device ("pass" -> "A" on a pad, "J" on keyboard 1).
## Buttons: pass, shoot, check, deke, turbo, protect, backward.
func button_label(b: String) -> String:
	if kind == Kind.KB1 or kind == Kind.KB2:
		var map: Dictionary = KB1 if kind == Kind.KB1 else KB2
		var keys: Array = map.get(b, [])
		return OS.get_keycode_string(keys[0]) if not keys.is_empty() else "?"
	return {"pass": "A", "shoot": "X", "check": "B", "deke": "Y", "turbo": "RT", "protect": "LB", "backward": "LT"}.get(b, "?")


## The movement control on this device: [left / right, up / down].
func move_labels() -> Array:
	match kind:
		Kind.KB1:
			return ["A / D", "W / S"]
		Kind.KB2:
			return ["Left / Right", "Up / Down"]
	return ["Stick left / right", "Stick up / down"]


func update(_skater: Skater, i: SkaterIntent, _delta: float) -> void:
	_poll()
	i.move = InputRouter.to_world(_cur.move)   # the stick in screen terms, turned to the camera
	i.turbo = _cur.turbo
	i.protect = _cur.protect
	i.backward = _cur.get("backward", false)
	i.pass_down = _cur.pass and not _prev.get("pass", false)
	i.pass_held = _cur.pass
	i.pass_up = not _cur.pass and _prev.get("pass", false)
	i.shoot_down = _cur.shoot and not _prev.get("shoot", false)
	i.shoot_held = _cur.shoot
	i.shoot_up = not _cur.shoot and _prev.get("shoot", false)
	i.deke_down = _cur.deke and not _prev.get("deke", false)
	i.deke_held = _cur.deke
	i.check_down = _cur.check and not _prev.get("check", false)


func _poll() -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	_prev = _cur
	_cur = _read()


func _read() -> Dictionary:
	var s := {}
	match kind:
		Kind.ANY:
			var mv := InputRouter.move_vector()
			s.move = Vector3(mv.x, 0.0, mv.y)
			s.turbo = Input.is_action_pressed("turbo")
			s.protect = Input.is_action_pressed("protect")
			s.backward = Input.is_action_pressed("backward")
			for b in BUTTONS:
				s[b] = Input.is_action_pressed(b)
		Kind.KB1, Kind.KB2:
			var map: Dictionary = KB1 if kind == Kind.KB1 else KB2
			var v := Vector3(_k(map.right) - _k(map.left), 0.0, _k(map.down) - _k(map.up))
			s.move = v.normalized() if v.length() > 1.0 else v
			s.turbo = _k(map.turbo) > 0.0
			s.protect = _k(map.protect) > 0.0
			s.backward = _k(map.backward) > 0.0
			for b in BUTTONS:
				s[b] = _k(map[b]) > 0.0
		Kind.PAD:
			var v := Vector3(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), 0.0, Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): v.x = -1.0
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): v.x = 1.0
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): v.z = -1.0
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): v.z = 1.0
			var l := v.length()
			s.move = Vector3.ZERO if l < InputRouter.DEADZONE else v / maxf(l, 1.0)
			s.turbo = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.4
			s.protect = Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER)
			s.backward = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.4
			for b in BUTTONS:
				s[b] = Input.is_joy_button_pressed(pad, PAD[b])
	return s


func _k(keys: Array) -> float:
	for key: Key in keys:
		if Input.is_physical_key_pressed(key):
			return 1.0
	return 0.0
