class_name Puck
extends CharacterBody3D
## Arcade puck: hand-tuned ice friction plus swept collision against boards, glass, nets and bodies.
##
## The ice is handled analytically (a plane at y = 0), so the puck never jitters on
## the floor. Walls use move_and_collide sweeps each 120 Hz tick, so even 50 m/s
## shots can't tunnel through. Bounce behaviour comes from each collider's "surface" meta.
##
## Possession: a carrier skater "owns" the puck and it's swept toward the carrier's
## stick blade each tick. If something blocks it (net, another body), the carrier loses it.

signal hit_surface(surface: String, impact_speed: float, at: Vector3)
signal left_play
signal possession_changed(carrier: Skater)
signal touched(by: Skater)                 ## any skater/goalie touch (rules: offsides, icing, delayed penalties)
signal released(by: Skater, at: Vector3)   ## a pass or shot leaves the stick

const GRAVITY := 9.81
const MAX_SPEED := 50.0
const MAX_SWEEPS := 4
const VISUAL_THICK := 1.5         ## visual thickness scale (visual_scale widens it)
const LOSE_DISTANCE := 0.45       ## carried puck this far from the blade = lost
const RECEIVER_TIMEOUT := 2.5     ## seconds a pass stays "intended" for its receiver
const PASS_HOMING := 4.5          ## rad/s a pass on the ice can curve toward its receiver...
const PASS_HOMING_RANGE := 6.0    ## ...within this many meters of them

## surface -> Vector2(restitution, tangential friction)
const SURFACES := {
	"boards": Vector2(0.55, 0.12),
	"glass": Vector2(0.42, 0.08),
	"post": Vector2(0.75, 0.05),
	"net": Vector2(0.05, 0.7),
	"body": Vector2(0.15, 0.5),
}

@export var ice_decel := 1.0          ## constant sliding deceleration, m/s^2
@export var ice_drag := 0.12          ## extra deceleration per m/s of speed
@export var air_drag := 0.05
@export var ice_bounce := 0.3         ## restitution when landing hard on the ice
@export var visual_scale := 2.0       ## readability from the broadcast camera

var on_ice := true
var in_play := true
var rest_y := RinkSpec.PUCK_THICKNESS * 0.5

var dead := false      ## during stoppages: nobody can pick the puck up
var flight := 0        ## bumps whenever the puck's path changes (goalies track shots by this)

var carrier: Skater = null
var last_touch: Skater = null
var intended_receiver: Skater = null
var _receiver_time := 0.0
var _no_pickup := {}    # Skater -> seconds remaining
var _exceptions := {}   # PhysicsBody3D -> seconds remaining (INF while carried)


func _ready() -> void:
	add_to_group("puck")
	process_physics_priority = 10 # after skaters, before nets
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1 << 5
	collision_mask = 1 | (1 << 1) | (1 << 3)
	safe_margin = 0.001
	$Visual.scale = Vector3(visual_scale, VISUAL_THICK, visual_scale)
	# The thickened visual grows from the ice up instead of sinking half into it.
	$Visual.position.y = RinkSpec.PUCK_THICKNESS * (VISUAL_THICK - 1.0) * 0.5


## Teleports the puck (to the ice if pos.y is at or below ice level), stops it and clears possession.
func place(pos: Vector3) -> void:
	if carrier:
		carrier = null
		possession_changed.emit(null)
	for body in _exceptions.keys():
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	_exceptions.clear()
	_no_pickup.clear()
	intended_receiver = null
	flight += 1
	global_position = Vector3(pos.x, maxf(pos.y, rest_y), pos.z)
	velocity = Vector3.ZERO
	on_ice = pos.y <= rest_y + 0.001
	in_play = true
	reset_physics_interpolation()


## Sets the puck moving. Any upward component lifts it off the ice.
func launch(v: Vector3) -> void:
	velocity = v.limit_length(MAX_SPEED)
	if velocity.y > 0.01:
		on_ice = false


## Radius of the drawn (enlarged) puck, so a stick blade can sit against its edge.
func visual_radius() -> float:
	return RinkSpec.PUCK_RADIUS * visual_scale


func speed() -> float:
	return velocity.length()


# --- Possession --------------------------------------------------------------

func attach(s: Skater) -> void:
	if carrier == s:
		return
	carrier = s
	last_touch = s
	intended_receiver = null
	on_ice = true
	global_position.y = rest_y
	_add_exception(s, INF)
	possession_changed.emit(s)
	touched.emit(s)


## The carrier passes or shoots. `receiver` marks the pass's intended target.
func release(v: Vector3, by: Skater, receiver: Skater = null) -> void:
	carrier = null
	last_touch = by
	velocity = v.limit_length(MAX_SPEED)
	on_ice = velocity.y <= 0.01 and global_position.y <= rest_y + 0.01
	intended_receiver = receiver
	flight += 1
	_receiver_time = RECEIVER_TIMEOUT
	block_pickup(by, 0.3)
	_add_exception(by, 0.3)
	possession_changed.emit(null)
	released.emit(by, global_position)


## A puck too hot to handle bounces off the stick.
func deflect(by: Skater, rng: RandomNumberGenerator) -> void:
	velocity = velocity.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)) * 0.5
	velocity.y = 0.0
	last_touch = by
	flight += 1
	block_pickup(by, 0.2)
	touched.emit(by)


## Knocks the puck off its carrier (a check or poke check).
func strip(from: Skater, push: Vector3, by: Skater = null) -> void:
	if carrier != from:
		return
	_drop_carrier()
	velocity += push
	velocity.y = 0.0
	flight += 1
	if by:
		last_touch = by
		touched.emit(by)


## A goalie's save sends the puck back out.
func rebound(v: Vector3, by: Skater) -> void:
	velocity = v.limit_length(MAX_SPEED)
	on_ice = velocity.y <= 0.01 and global_position.y <= rest_y + 0.01
	last_touch = by
	intended_receiver = null
	flight += 1
	block_pickup(by, 0.4)
	reset_physics_interpolation()
	touched.emit(by)


func block_pickup(s: Skater, seconds: float) -> void:
	_no_pickup[s] = maxf(_no_pickup.get(s, 0.0), seconds)


func can_pick(s: Skater) -> bool:
	return not dead and _no_pickup.get(s, 0.0) <= 0.0


func _drop_carrier() -> void:
	var c := carrier
	carrier = null
	block_pickup(c, 0.35)
	_add_exception(c, 0.3)
	velocity = c.velocity * 0.5
	velocity.y = 0.0
	possession_changed.emit(null)


func _add_exception(body: PhysicsBody3D, seconds: float) -> void:
	if not _exceptions.has(body):
		add_collision_exception_with(body)
	_exceptions[body] = seconds


func _tick_timers(delta: float) -> void:
	for s in _no_pickup.keys():
		_no_pickup[s] -= delta
		if _no_pickup[s] <= 0.0 or not is_instance_valid(s):
			_no_pickup.erase(s)
	for body in _exceptions.keys():
		if body == carrier:
			continue
		if _exceptions[body] == INF:
			_exceptions[body] = 0.3
		_exceptions[body] -= delta
		if _exceptions[body] <= 0.0 or not is_instance_valid(body):
			if is_instance_valid(body):
				remove_collision_exception_with(body)
			_exceptions.erase(body)
	if intended_receiver:
		_receiver_time -= delta
		if _receiver_time <= 0.0:
			intended_receiver = null


# --- Simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if carrier:
		_carry()
	else:
		_free_move(delta)

	if in_play:
		var p := global_position
		if RinkSpec.sdf(p.x, p.z) > 0.3 or p.y < -1.0:
			in_play = false
			left_play.emit()


func _carry() -> void:
	var target := carrier.puck_anchor()
	move_and_collide(target - global_position)
	velocity = carrier.velocity
	on_ice = true
	if global_position.distance_to(target) > LOSE_DISTANCE:
		_drop_carrier()


## A pass sliding toward its intended receiver bends a little onto their stick (the
## "sticky" pass): only in front of the puck, only near the receiver, at most
## PASS_HOMING rad/s, so a pass into traffic can still be cut off.
func _home_on_receiver(delta: float) -> void:
	var r := intended_receiver
	if r == null or not is_instance_valid(r) or r.puck != self:
		return
	var hv := Vector2(velocity.x, velocity.z)
	var spd := hv.length()
	if spd < 2.0:
		return
	var target := r.reception_point()
	var to := Vector2(target.x - global_position.x, target.z - global_position.z)
	var d := to.length()
	if d > PASS_HOMING_RANGE or d < 0.2 or to.dot(hv) <= 0.0:
		return
	var turn := clampf(hv.angle_to(to), -PASS_HOMING * delta, PASS_HOMING * delta)
	hv = hv.rotated(turn)
	velocity.x = hv.x
	velocity.z = hv.y


func _free_move(delta: float) -> void:
	if on_ice:
		velocity.y = 0.0
		_home_on_receiver(delta)
		var hv := Vector2(velocity.x, velocity.z)
		var s := hv.length()
		if s > 0.0:
			var ns := maxf(0.0, s - (ice_decel + ice_drag * s) * delta)
			hv *= ns / s
			velocity.x = hv.x
			velocity.z = hv.y
	else:
		velocity.y -= GRAVITY * delta
		velocity -= velocity * air_drag * delta

	_sweep(velocity * delta, delta)

	# Ice contact.
	if not on_ice and global_position.y <= rest_y:
		if velocity.y < -1.5:
			velocity.y = -velocity.y * ice_bounce
			velocity.x *= 0.9
			velocity.z *= 0.9
		else:
			velocity.y = 0.0
			on_ice = true
		global_position.y = rest_y


func _sweep(motion: Vector3, delta: float) -> void:
	for i in MAX_SWEEPS:
		var length := motion.length()
		if length < 1e-6:
			return
		var col := move_and_collide(motion)
		if col == null:
			return
		var n := col.get_normal()
		var vn := velocity.dot(n)
		if vn < 0.0:
			var surface := _surface_of(col)
			var props: Vector2 = SURFACES.get(surface, SURFACES["boards"])
			var vt := velocity - n * vn
			velocity = vt * (1.0 - props.y) - n * vn * props.x
			if on_ice:
				velocity.y = 0.0
			var other := col.get_collider()
			if other is Skater:
				last_touch = other
				touched.emit(other)
			flight += 1
			hit_surface.emit(surface, -vn, col.get_position())
		var fraction := col.get_remainder().length() / length
		motion = velocity * delta * fraction


func _surface_of(col: KinematicCollision3D) -> String:
	var collider := col.get_collider()
	var surface := "boards"
	if collider and collider.has_meta("surface"):
		surface = str(collider.get_meta("surface"))
	if surface == "boards" and col.get_position().y > RinkSpec.BOARD_HEIGHT:
		surface = "glass"
	return surface
