class_name MenuBackdrop
extends Node3D
## The live 3D scene behind the main menu and the rules screen: the arena (MenuArena),
## one player skating slow laps, and a camera tracking in front of them so they stay
## on the right of the frame. `team` before it enters the tree picks the player's team
## (-1: a random team with a logo).

const SPOT := Vector3(0.0, 0.0, 5.0)   ## center of the player's lap
const LAP_RADIUS := 8.0
const LAP_SPEED := 0.5                 ## fraction of full speed

var cam: Camera3D
var skater: Skater
var team := -1
var _t := 0.0
var _cam_dir := Vector3.BACK


func _ready() -> void:
	var arena := MenuArena.build(self, SPOT)
	if team < 0:
		var with_logo := MenuArena.teams_with_logos()
		team = with_logo.pick_random() if not with_logo.is_empty() else 0
	var crest := MenuArena.logo(team)
	if crest:
		(arena.rink as Rink).set_center_logo(crest)
	skater = MenuArena.make_skater(self, arena, team, team, false, MenuArena.star(team))
	# Steer for a point a little further round the lap (counter-clockwise from above).
	skater.brain = ScriptBrain.new(func(s: Skater, i: SkaterIntent, _t: float) -> void:
		var r := s.global_position - SPOT
		var a := atan2(r.z, r.x) - 0.45
		var target := SPOT + Vector3(cos(a), 0.0, sin(a)) * LAP_RADIUS
		i.move = (target - s.global_position).normalized() * LAP_SPEED)
	skater.place(SPOT + Vector3(LAP_RADIUS, 0, 0), Vector3.FORWARD)

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.attributes = MenuArena.camera_attributes()
	add_child(cam)
	_place_camera(true)


func _process(delta: float) -> void:
	_t += delta
	_place_camera(false, delta)


## Low, in front of the player and leading them, looking back so they skate toward us
## on the right of the frame.
func _place_camera(snap: bool, delta := 0.0) -> void:
	if cam == null or skater == null:
		return
	var p := skater.visual.global_position if skater.visual else skater.global_position
	var h := skater.heading
	h.y = 0.0
	if h.length() > 0.1:
		var k := 1.0 if snap else 1.0 - exp(-delta * 3.0)
		_cam_dir = _cam_dir.slerp(h.normalized(), k).normalized()
	var side := _cam_dir.cross(Vector3.UP).normalized()   # the player's right
	var pos := p + _cam_dir * 3.4 + side * 0.3 + Vector3(0, 0.8 + sin(_t * 0.23) * 0.05, 0)
	var look := p + Vector3(0, 1.05, 0) + side * 0.95
	cam.look_at_from_position(pos, look)
