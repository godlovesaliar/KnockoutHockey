class_name BroadcastCamera
extends Camera3D
## The gameplay camera: follows a target (the puck) from one of the play angles, plus two
## debug views. Each play angle has a screen-up direction on the ice (`screen_fwd`); stick
## input is turned to match (InputRouter.screen_fwd), so up on the stick is always up on
## the screen.
##   BROADCAST  the default: high above the boards, end to end (screen-up = -Z)
##   CLOSE      lower and nearer, tilted toward the play, centered between the puck and
##              the player you control
##   SIDE       side-on from the penalty-box side, the rink running across the screen
##              (screen-up = -X; the benches are on the far side)
##   HIGH       nearly straight down from the rafters, the 16-bit look: more ice, less
##              perspective (end to end)
## `follow_team` >= 0 turns the angle 180° whenever that team would otherwise be attacking
## down the screen (or to the left, on SIDE), so it always attacks up / right.

enum Mode { BROADCAST, CLOSE, SIDE, HIGH, OVERHEAD, END_ZONE }

## The angles a player can pick (the rest are debug views).
const PLAY_MODES := [Mode.BROADCAST, Mode.CLOSE, Mode.SIDE, Mode.HIGH]
const LABELS := {
	Mode.BROADCAST: "Broadcast", Mode.CLOSE: "Close", Mode.SIDE: "Side", Mode.HIGH: "High",
	Mode.OVERHEAD: "Overhead (debug)", Mode.END_ZONE: "End zone (debug)",
}
const HINTS := {
	Mode.BROADCAST: "High above the boards, end to end. The default.",
	Mode.CLOSE: "Lower and closer, tilted toward the play and your player.",
	Mode.SIDE: "From the side: the rink runs across the screen.",
	Mode.HIGH: "Straight down from the rafters, the classic 16-bit look.",
}
## Per angle: height and distance back (m), lens, how much of the focus's sideways
## position (across the screen) the camera follows, how far it travels along the
## screen's up axis and across it (`span`), screen-up on the ice, and how much of the controlled player to frame.
const PRESETS := {
	Mode.BROADCAST: {"height": 24.0, "back": 8.5, "fov": 40.0, "across": 0.45, "travel": RinkSpec.HALF_L - 9.0, "span": 99.0,
			"fwd": Vector3(0, 0, -1), "player": 0.0},
	Mode.CLOSE: {"height": 8.5, "back": 11.0, "fov": 46.0, "across": 0.8, "travel": RinkSpec.HALF_L - 3.0, "span": 99.0,
			"fwd": Vector3(0, 0, -1), "player": 0.45},
	Mode.SIDE: {"height": 14.5, "back": 13.5, "fov": 40.0, "across": 1.0, "travel": RinkSpec.HALF_W - 9.5, "span": RinkSpec.HALF_L - 11.0,
			"fwd": Vector3(-1, 0, 0), "player": 0.0},
	Mode.HIGH: {"height": 40.0, "back": 4.0, "fov": 38.0, "across": 0.35, "travel": RinkSpec.HALF_L - 13.0, "span": 99.0,
			"fwd": Vector3(0, 0, -1), "player": 0.0},
}

@export var target_path: NodePath
@export var lead_time := 0.3        ## seconds of velocity look-ahead
@export var max_lead := 6.0
@export var smoothing := 4.0

var mode := Mode.BROADCAST
var target: Node3D
## The skater the camera should keep in frame as well (CLOSE): set by the match each frame.
var player: Node3D
## Team whose attack should always go up / right (-1: the angle never turns).
var follow_team := -1
var _flipped := false
var _focus := Vector3.ZERO
var _shake := 0.0
var _rink: Node


func _ready() -> void:
	# Placed every frame from interpolated targets: interpolating the camera too would
	# draw it a physics tick behind and jerky against the players.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not target_path.is_empty():
		target = get_node_or_null(target_path)
	make_current()
	set_mode(mode)


func set_mode(m: Mode) -> void:
	mode = m
	if mode == Mode.OVERHEAD:
		projection = PROJECTION_ORTHOGONAL
		size = RinkSpec.LENGTH + 4.0
	else:
		projection = PROJECTION_PERSPECTIVE
		fov = PRESETS[mode].fov if PRESETS.has(mode) else 40.0
	# Up in the rafters, look through the roof and the scoreboard.
	cull_mask = 0xFFFFF & ~Arena.RAFTERS_LAYER if mode == Mode.HIGH else 0xFFFFF
	_update_flip()
	_apply(true)


## A play angle by its settings name ("broadcast", "close", "side", "high").
func set_mode_name(n: String) -> void:
	var i := Mode.keys().find(n.to_upper())
	if i >= 0:
		set_mode(i as Mode)


func cycle_mode() -> void:
	set_mode(((mode + 1) % Mode.size()) as Mode)


## The next play angle after the current one (for menus).
func next_play_mode() -> Mode:
	var i := PLAY_MODES.find(mode)
	return PLAY_MODES[(i + 1) % PLAY_MODES.size()]


func mode_name() -> String:
	return Mode.keys()[mode]


static func label_of(n: String) -> String:
	var i := Mode.keys().find(n.to_upper())
	return LABELS.get(i, n.capitalize())


## Kick the camera (big hits, glass, goals). Decays on its own.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Screen-up on the ice right now (after any turn for `follow_team`).
func screen_fwd() -> Vector3:
	var f: Vector3 = PRESETS[mode].fwd if PRESETS.has(mode) else Vector3(0, 0, -1)
	return -f if _flipped else f


## Re-checks which way `follow_team` is attacking (call when the teams switch ends).
func _update_flip() -> void:
	_flipped = false
	if follow_team >= 0 and PRESETS.has(mode):
		if _rink == null:
			_rink = get_tree().get_first_node_in_group("rink") if is_inside_tree() else null
		if _rink and _rink.has_method("attacked_net"):
			var net: Node3D = _rink.attacked_net(follow_team)
			# The attack runs along the rink (Z): up the screen on end-to-end angles,
			# toward screen-right on SIDE. Turn if that net lies the other way.
			var f: Vector3 = PRESETS[mode].fwd
			var axis := f if absf(f.z) > 0.5 else f.cross(Vector3.UP)
			_flipped = net.global_position.dot(axis) < 0.0
	if is_inside_tree() and InputRouter:
		InputRouter.screen_fwd = screen_fwd()


func _process(delta: float) -> void:
	if follow_team >= 0 and Engine.get_process_frames() % 15 == 0:
		var was := _flipped
		_update_flip()
		if was != _flipped:
			_apply(true)
	_apply(false, delta)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35


func _apply(snap: bool, delta := 0.0) -> void:
	if not PRESETS.has(mode):
		match mode:
			Mode.OVERHEAD:
				global_position = Vector3(0.0, 60.0, 0.0)
				look_at(Vector3.ZERO, Vector3.FORWARD)
			Mode.END_ZONE:
				global_position = Vector3(0.0, 4.5, RinkSpec.HALF_L - 0.3)
				look_at(Vector3(0.0, 0.0, RinkSpec.GOAL_LINE_Z - 3.0), Vector3.UP)
		return
	var p: Dictionary = PRESETS[mode]
	var goal := Vector3.ZERO
	if target:
		var tp := target.get_global_transform_interpolated().origin
		var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
		goal = tp + (Vector3(v.x, 0.0, v.z) * lead_time).limit_length(max_lead)
	if p.player > 0.0 and is_instance_valid(player) and player.visible:
		goal = goal.lerp(player.global_position, p.player)
	goal.y = 0.0
	# Split the focus into along screen-up and across the screen; follow and clamp each.
	var fwd := screen_fwd()
	var right := fwd.cross(Vector3.UP)
	var along := clampf(goal.dot(fwd), -p.travel, p.travel)
	var across := clampf(goal.dot(right) * p.across, -p.span, p.span)
	goal = fwd * along + right * across
	_focus = goal if snap else _focus.lerp(goal, 1.0 - exp(-smoothing * delta))
	global_position = _focus - fwd * p.back + Vector3.UP * p.height
	look_at(_focus, fwd if p.back < 1.0 else Vector3.UP)
