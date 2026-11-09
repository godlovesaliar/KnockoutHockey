extends Node
## Builds the input map in code so bindings can be remapped and, later (M3),
## split per controller for local multiplayer.

const DEADZONE := 0.2

const KEYS := {
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"move_up": [KEY_W],
	"move_down": [KEY_S],
	"pass": [KEY_J],
	"shoot": [KEY_K],
	"check": [KEY_L],
	"deke": [KEY_I],
	"turbo": [KEY_SHIFT],
	"protect": [KEY_SPACE],
	"backward": [KEY_Q],
	"pause": [KEY_ESCAPE],
	"debug_camera": [KEY_C],
}

const PAD_BUTTONS := {
	"pass": JOY_BUTTON_A,
	"shoot": JOY_BUTTON_X,
	"check": JOY_BUTTON_B,
	"deke": JOY_BUTTON_Y,
	"pause": JOY_BUTTON_START,
	"debug_camera": JOY_BUTTON_BACK,
	"protect": JOY_BUTTON_LEFT_SHOULDER,
}

## action -> [axis, direction]
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	"turbo": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"backward": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}


func _enter_tree() -> void:
	var actions := {}
	for a in KEYS:
		actions[a] = true
	for a in PAD_BUTTONS:
		actions[a] = true
	for a in PAD_AXES:
		actions[a] = true

	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		for key: Key in KEYS.get(action, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if PAD_BUTTONS.has(action):
			var btn := InputEventJoypadButton.new()
			btn.device = -1
			btn.button_index = PAD_BUTTONS[action]
			InputMap.action_add_event(action, btn)
		if PAD_AXES.has(action):
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = PAD_AXES[action][0]
			motion.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, motion)


## Screen-up on the ice for the gameplay camera (BroadcastCamera keeps it current):
## -Z for the default end-to-end angle.
var screen_fwd := Vector3(0, 0, -1)


## Left stick / WASD in screen terms (y < 0 is up).
func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Movement as a flat world-space direction, matched to the camera.
func move_world() -> Vector3:
	var v := move_vector()
	return to_world(Vector3(v.x, 0.0, v.y))


## A stick direction in screen terms (x right, z down) to the ice under the camera.
func to_world(v: Vector3) -> Vector3:
	var right := screen_fwd.cross(Vector3.UP)
	return right * v.x - screen_fwd * v.z


## The inverse of to_world: a world direction back into stick terms.
func to_screen(w: Vector3) -> Vector3:
	var right := screen_fwd.cross(Vector3.UP)
	return Vector3(w.dot(right), 0.0, -w.dot(screen_fwd))
