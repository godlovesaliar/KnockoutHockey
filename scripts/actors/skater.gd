class_name Skater
extends CharacterBody3D
## Arcade skater: hand-tuned skating, puck carrying, passing, shooting, deking,
## body checks, poke checks and knockdowns.
##
## A Brain fills `intent` each tick; this script turns intent into motion and actions.
## Everything feel-related is a constant or stat mapping near the top of this file.

signal pass_released(skater: Skater, receiver: Skater)
signal shot_released(skater: Skater, kind: StringName, speed: float)
signal switch_requested(skater: Skater)
signal hit_landed(attacker: Skater, victim: Skater, power: float, kind: StringName, into_boards: bool)
signal poke_succeeded(skater: Skater, victim: Skater)
## A possible infraction; the director decides whether the referee calls it.
signal foul_committed(offender: Skater, victim: Skater, kind: StringName)

enum State { SKATE, WINDUP, FOLLOW_THROUGH, DEKE, CHECK, POKE, STUMBLE, DOWN }

# --- Skating feel ---
const TURN_SLOW := 14.0           ## rad/s turn rate when nearly stopped
const HARD_STOP_ANGLE := 2.2689   ## 130 degrees: reversing the stick past this = hockey stop
const HARD_STOP_DECEL := 24.0
const GLIDE_DECEL := 2.2          ## coasting with no stick input
const DOWN_DECEL := 5.0           ## sliding on the ice after a hit
const OVERSPEED_DECEL := 6.0      ## bleeding off turbo speed
const CARVE_BLEED := 0.35         ## speed lost per rad/s of turning
const TURBO_SPEED_MULT := 1.25
const BOARD_BOUNCE := 0.35

# --- Puck handling ---
const BLADE_FORWARD := 1.0
const BLADE_SIDE := 0.38
const INTENDED_REACH := 1.5       ## the intended receiver catches passes from any side
const AIM_MEMORY := 0.35          ## a pass aims where the stick pointed this recently (stick released first)
const PASS_LEAD_MAX := 3.0        ## meters a pass leads a moving receiver, at most
const BACKWARD_SPEED := 0.72      ## top speed skating backwards (share of forward)
const PASS_CONE := 1.1345         ## 65 degrees
const SAUCER_HOLD := 0.22         ## hold pass this long for a saucer pass

# --- Shooting ---
const WRIST_WINDOW := 0.16        ## release shoot within this = wrist shot
const SLAP_CHARGE_TIME := 0.45    ## extra hold for a full slap shot
const MAX_WINDUP := 1.4
const FOLLOW_TIME := 0.22
const ONE_TIMER_BUFFER := 0.35
const ONE_TIMER_RANGE := 26.0

# --- Deke ---
const DEKE_TIME := 0.28
const DEKE_COOLDOWN := 0.55
const DEKE_RETURN := 0.45         ## after a deke, puck drifts back to the forehand

# --- Checking ---
const CHECK_TIME := 0.3
const CHECK_LUNGE := 3.0          ## m/s burst along the check direction
const CHECK_COOLDOWN := 0.7
const CHECK_RANGE := 1.25
const CHECK_CONE := 1.22          ## 70 degrees
const BUMP_LIMIT := 6.0           ## hit power (after balance) below this = bump
const CHECK_LIMIT := 12.5         ## below this = knockdown, above = BIG HIT
const BOARDS_MULT := 1.4
const STUMBLE_TIME := 0.35
const DOWN_TIME := 0.9
const BIG_DOWN_TIME := 1.5

# --- Poke check ---
const POKE_TIME := 0.3
const POKE_HIT_AT := 0.08
const POKE_REACH := 0.9
const POKE_COOLDOWN := 0.6

@export var team := 0
@export var number := 19
@export var shoots_left := true
@export var team_color := Color(0.78, 0.1, 0.12)
@export var handles_puck := true  ## false for practice pylons
@export var stats: PlayerStats

var brain: Brain
var ai_brain: Brain
var intent := SkaterIntent.new()
var is_human := false
var frozen := false               ## faceoff setup: stand still (the brain still runs)
var puck: Puck
var rink: Rink
var teammates: Array[Skater] = []
var opponents: Array[Skater] = [] ## checkable skaters (not goalies)

var state := State.SKATE
var heading := Vector3.FORWARD
var stamina := 1.0
var turbo_active := false
var stopping := false
var turn_speed := 0.0             ## rad/s, for the visual lean
var windup_time := 0.0
var shot_charge := 0.0
var last_shot_kind: StringName = &""
var fall_side := 1.0              ## which way a knockdown topples (visual)
var energy := 1.0                 ## shift fatigue: drains on the ice, recovers on the bench
var fatigue_enabled := true
var benched := false              ## off the ice (bench or penalty box)
## Where a benched skater stands: their spot on the team bench, or in the penalty box
## while `in_box_spot` (MatchDirector sets both). INF = hidden under the rink instead.
var bench_spot := Vector3.INF
var box_spot := Vector3.INF
var in_box_spot := false
var bench_sit := true              ## on the bench: a seat (false: standing at the boards)
## Picks this skater's bench spot when they park: returns [spot, seated] (MatchDirector:
## the first free seat). Unset: keep bench_spot / bench_sit as they are.
var bench_claim := Callable()
var _walk: Tween
var momentum := false             ## the team won a fight lately: a little faster, hits harder
var changing := false             ## heading to the bench for a line change
var is_defense := false
var position_name := "C"
var first_name := ""              ## from the roster sheet (Rosters); empty for generated players
var last_name := ""
var nickname := ""
var playstyle := ""
var body_type := "male"           ## body model: "male", "female" or "ybot" (see tools/build_characters.gd)
var height_m := 0.0               ## the player's height and weight (BodyBuild); 0 = the body type's average
var weight_kg := 0.0
var uniform := {}                ## team palette (Teams.LIST colors); empty = derived from team_color
var crest: Texture2D             ## team logo on the jersey front (null = none)
var skin_tone := Color(0.91, 0.73, 0.60)   ## sRGB; see SkaterVisual.SKIN_TONES
var gear_style := 0              ## helmet model (goalies: mask model); see SkaterVisual.HELMETS / GoalieVisual.MASKS
var visor := true                ## a visor on the helmet (skaters); see Skater.visor_for
var hair_style := ""              ## SkaterVisual.HAIR_STYLES / "braid"; "" = none showing
var facial_hair := ""             ## "beard", "moustache" or ""
var hair_color := Color(0.16, 0.1, 0.06)
var eye_color := Color(0.34, 0.2, 0.09)   ## sRGB; see SkaterVisual.EYE_COLORS
var stick_style := "black"        ## SkaterVisual.STICK_STYLES: "wood", "black", "black_white", ...
var stick_tape := "white"         ## SkaterVisual.TAPES: "white", "black", "team" or "none"
## The club's home and road jersey colors, for team-colored sticks and tape (empty: the
## uniform's jersey on white).
var club_colors: Array[Color] = []
var human_index := -1             ## which human (P1..P4) controls this skater, -1 = AI
var visual: SkaterVisual

var _state_time := 0.0
var _down_time := 0.0
var _pass_hold := -1.0
var _aim_dir := Vector3.ZERO     ## last firm stick direction (for passes)
var _aim_age := INF
var _shoot_buffer := 0.0
var _deke_cooldown := 0.0
var _deke_return := 0.0
var _check_cooldown := 0.0
var _check_dir := Vector3.FORWARD
var _poke_cooldown := 0.0
var _poke_done := false
var _turbo_locked := false
var _juke_dir := Vector3.ZERO
var _juke_speed := 0.0
var _juke_decay := 0.0
var _puck_lat := 1.0              ## puck side across the body: -1 left .. +1 right
var _puck_lat_target := 1.0
var _dangle_t := 0.0
var _rng := RandomNumberGenerator.new()
var _since_puck := 99.0           ## seconds since this skater last had the puck


func _ready() -> void:
	if stats == null:
		stats = PlayerStats.new()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1 << 3
	collision_mask = 1 | (1 << 1) | (1 << 3) | (1 << 6)
	set_meta("surface", "body")
	_puck_lat = forehand_side()
	_puck_lat_target = _puck_lat
	_rng.randomize()
	visual = _make_visual()
	add_child(visual)
	visual.build(self)


func _make_visual() -> SkaterVisual:
	return SkaterVisual.new()


## Teleports the skater, stopped, facing `face`.
## Whether a player wears a visor, fixed by a key (their team and name): about three in
## four do. Hashed rather than drawn from the look RNG, so other looks don't shift.
static func visor_for(key: String) -> bool:
	return absi(hash(key + " visor")) % 100 < 75


func place(pos: Vector3, face := Vector3.FORWARD) -> void:
	_stop_walk()
	_clear_motion_flags()
	global_position = Vector3(pos.x, 0.0, pos.z)
	velocity = Vector3.ZERO
	heading = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	_set_state(State.SKATE)
	_pass_hold = -1.0
	_juke_speed = 0.0
	reset_physics_interpolation()
	if visual:
		visual.snap()


func seed_rng(value: int) -> void:
	_rng.seed = value


func forehand_side() -> float:
	return -1.0 if shoots_left else 1.0


func right_dir() -> Vector3:
	return heading.cross(Vector3.UP)


func has_puck() -> bool:
	return puck != null and puck.carrier == self


func team_has_puck() -> bool:
	return puck != null and puck.carrier != null and puck.carrier.team == team


func attacking_net() -> Net:
	return rink.attacked_net(team) if rink else null


func defending_net() -> Net:
	return rink.defended_net(team) if rink else null


func flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_down() -> bool:
	return state == State.DOWN


func can_act() -> bool:
	return state != State.DOWN and state != State.STUMBLE


## 0.82 .. 1.0 multiplier from shift fatigue.
func fatigue_mult() -> float:
	return lerpf(0.82, 1.0, energy) if fatigue_enabled else 1.0


## Takes the skater off the ice (no physics, no processing) or puts them back. Off the
## ice they stand at their bench or box spot (or, without one, hidden under the rink).
func set_benched(b: bool) -> void:
	changing = false
	if b == benched:
		return
	benched = b
	process_mode = Node.PROCESS_MODE_DISABLED if b else Node.PROCESS_MODE_INHERIT
	_stop_walk()
	_clear_motion_flags()
	if b:
		if has_puck():
			puck.strip(self, Vector3.ZERO)
		velocity = Vector3.ZERO
		frozen = false
		_set_state(State.SKATE)
		repark()
	else:
		visible = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		reset_physics_interpolation()
		if visual:
			visual.process_mode = Node.PROCESS_MODE_INHERIT
			visual.bench_off()


## Benched: moves to the current spot (box or bench) at once.
func repark() -> void:
	if not benched:
		return
	if not in_box_spot and bench_claim.is_valid():
		var r: Array = bench_claim.call(self)
		bench_spot = r[0]
		bench_sit = r[1]
	var spot := box_spot if in_box_spot and box_spot != Vector3.INF else bench_spot
	if spot == Vector3.INF:
		visible = false
		global_position = Vector3(0.0, -40.0, 0.0)
		return
	visible = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = spot
	heading = Vector3(-signf(spot.x), 0.0, 0.0)   # facing the ice
	velocity = Vector3.ZERO
	_park_pose()


## Parked: the visual keeps running (the skater itself doesn't) to play the bench idle:
## seated in the box and on the bench's seats, standing at the boards otherwise.
func _park_pose() -> void:
	if visual == null:
		return
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	visual.snap()
	visual.bench_pose(in_box_spot or bench_sit)


## Scripted walk (through a bench or box door) along `path`, at `speed` m/s, with no
## physics: used for line changes and trips to and from the penalty box. `face`: the
## heading at the end. `done` runs at the end (unless the walk is cut off by a teleport).
func walk(path: Array, speed: float, face: Vector3, done := Callable()) -> void:
	_stop_walk()
	_clear_motion_flags()
	if path.is_empty():
		return
	process_mode = Node.PROCESS_MODE_DISABLED
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = true
	if visual:
		visual.process_mode = Node.PROCESS_MODE_PAUSABLE
		visual.bench_off()
	# A tree tween, not the skater's own: a node's tweens stop while it can't process,
	# and the walk turns the skater's processing off.
	_walk = get_tree().create_tween()
	_walk.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	var from := global_position
	for p: Vector3 in path:
		var leg := p - from
		leg.y = 0.0
		var secs := maxf(leg.length() / speed, 0.05)
		if leg.length() > 0.05:
			var dir := leg.normalized()
			_walk.tween_callback(func() -> void:
				heading = dir
				velocity = dir * speed)
		_walk.tween_property(self, "global_position", p, secs)
		from = p
	_walk.tween_callback(func() -> void:
		heading = face.normalized()
		velocity = Vector3.ZERO
		_walk = null
		if benched:
			_park_pose()
		else:
			_resume_live()
		if done.is_valid():
			done.call())


func walking() -> bool:
	return _walk != null and _walk.is_running()


func _stop_walk() -> void:
	if _walk != null:
		_walk.kill()
		_walk = null
		if not benched:
			_resume_live()


## Per-tick movement flags (the hockey stop's spray and crouch, the carve lean) are only
## refreshed by _update_movement; anything that takes over from it clears them, or a
## skater caught mid-stop keeps spraying on the way to the box and sitting in it.
func _clear_motion_flags() -> void:
	stopping = false
	turn_speed = 0.0


## Back to normal play after a scripted walk: physics, processing, interpolation.
func _resume_live() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	reset_physics_interpolation()
	if visual:
		visual.process_mode = Node.PROCESS_MODE_INHERIT


# --- Tick ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	intent.clear()
	if brain:
		brain.update(self, intent, delta)
	if frozen:
		velocity = Vector3.ZERO
		_clear_motion_flags()
		return
	_state_time += delta
	_tick_timers(delta)
	_update_actions(delta)
	_update_stamina(delta)
	_update_movement(delta)
	_update_heading(delta)
	_move(delta)
	_try_pickup()


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	if s != State.WINDUP:
		windup_time = 0.0
		shot_charge = 0.0


func _tick_timers(delta: float) -> void:
	_shoot_buffer = maxf(0.0, _shoot_buffer - delta)
	_deke_cooldown = maxf(0.0, _deke_cooldown - delta)
	_check_cooldown = maxf(0.0, _check_cooldown - delta)
	_poke_cooldown = maxf(0.0, _poke_cooldown - delta)
	if _deke_return > 0.0:
		_deke_return -= delta
		if _deke_return <= 0.0:
			_puck_lat_target = forehand_side()
	_puck_lat = move_toward(_puck_lat, _puck_lat_target, 9.0 * delta)
	_dangle_t += delta * (5.0 + flat_speed() * 0.4)
	_since_puck = 0.0 if has_puck() else _since_puck + delta


# --- Actions ---------------------------------------------------------------

func _update_actions(delta: float) -> void:
	var has := has_puck()
	match state:
		State.SKATE:
			if has:
				if intent.shoot_down:
					_set_state(State.WINDUP)
					_pass_hold = -1.0
					return
				if intent.check_down and _check_cooldown <= 0.0:
					_begin_check()
					return
				if intent.deke_down and _deke_cooldown <= 0.0:
					_begin_deke()
				if intent.pass_down:
					_pass_hold = 0.0
				if _pass_hold >= 0.0:
					_pass_hold += delta
					if intent.pass_up or not intent.pass_held:
						var saucer := _pass_hold >= SAUCER_HOLD
						_pass_hold = -1.0
						_fire_pass(saucer)
			else:
				_pass_hold = -1.0
				if intent.pass_down and not team_has_puck():
					switch_requested.emit(self)
				if intent.shoot_down:
					_shoot_buffer = ONE_TIMER_BUFFER
				if intent.check_down and _check_cooldown <= 0.0:
					_begin_check()
				elif intent.deke_down and not team_has_puck() and _poke_cooldown <= 0.0:
					_begin_poke()
		State.WINDUP:
			if not has:
				_set_state(State.SKATE)
				return
			windup_time += delta
			shot_charge = clampf((windup_time - WRIST_WINDOW) / SLAP_CHARGE_TIME, 0.0, 1.0)
			if intent.shoot_up or not intent.shoot_held or windup_time >= MAX_WINDUP:
				if windup_time < WRIST_WINDOW:
					_fire_shot(&"wrist", 0.0)
				else:
					_fire_shot(&"slap", shot_charge)
		State.FOLLOW_THROUGH:
			if _state_time >= FOLLOW_TIME:
				_set_state(State.SKATE)
		State.DEKE:
			if _state_time >= DEKE_TIME:
				_set_state(State.SKATE)
		State.CHECK:
			_check_contact()
			if state == State.CHECK and _state_time >= CHECK_TIME:
				_set_state(State.SKATE)
		State.POKE:
			if not _poke_done and _state_time >= POKE_HIT_AT:
				_poke_done = true
				_try_poke()
			if _state_time >= POKE_TIME:
				_set_state(State.SKATE)
		State.STUMBLE, State.DOWN:
			if _state_time >= _down_time:
				_set_state(State.SKATE)


func _juke(dir: Vector3, burst: float, duration: float) -> void:
	_juke_dir = dir
	_juke_speed = burst
	_juke_decay = burst / duration


func _begin_deke() -> void:
	_set_state(State.DEKE)
	_deke_cooldown = DEKE_COOLDOWN
	_deke_return = DEKE_TIME + DEKE_RETURN
	var right := right_dir()
	var lateral := intent.move.dot(right)
	var side := signf(lateral) if absf(lateral) > 0.2 else -signf(_puck_lat)
	if side == 0.0:
		side = -forehand_side()
	_puck_lat_target = side
	# A sideways juke on top of normal skating; heading stays put.
	_juke(right * side, PlayerStats.lerp_stat(stats.agility, 4.5, 6.5), DEKE_TIME)


func choose_pass_target(dir: Vector3) -> Skater:
	var best: Skater = null
	var best_score := INF
	for m in teammates:
		if m == self or not is_instance_valid(m):
			continue
		var to := m.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < 1.5:
			continue
		var ang := dir.angle_to(to)
		if ang > PASS_CONE:
			continue
		# Where the stick points matters far more than who is closest.
		var score := rad_to_deg(ang) * 1.6 + d * 0.25
		if score < best_score:
			best_score = score
			best = m
	return best


func pass_aim_dir() -> Vector3:
	if intent.move.length() > 0.3:
		return intent.move.normalized()
	# The stick often comes back to center a moment before the pass button does.
	if _aim_age < AIM_MEMORY:
		return _aim_dir
	return heading


func reception_point() -> Vector3:
	return global_position + heading * 0.75


func _fire_pass(saucer: bool) -> void:
	var dir := pass_aim_dir()
	var receiver := choose_pass_target(dir)
	var origin := puck.global_position
	var max_speed := PlayerStats.lerp_stat(stats.passing, 17.0, 25.0)
	var v: Vector3
	if receiver:
		var dist := origin.distance_to(receiver.global_position)
		var spd := clampf(9.0 + dist * 0.9, 10.0, max_speed)
		var horiz := spd * (0.7 if saucer else 1.0)
		var avg := horiz * 0.88 # ice friction slows the pass on the way
		var aim := receiver.reception_point()
		for i in 3:
			var t := Vector2(aim.x - origin.x, aim.z - origin.z).length() / avg
			aim = receiver.reception_point() + (receiver.velocity * t).limit_length(PASS_LEAD_MAX)
		var flat := aim - origin
		flat.y = 0.0
		var err := deg_to_rad(_rng.randfn(0.0, PlayerStats.lerp_stat(stats.passing, 2.5, 0.4)))
		var fdir := flat.normalized().rotated(Vector3.UP, err)
		v = fdir * horiz
		if saucer:
			var t := flat.length() / horiz
			v.y = minf(0.5 * Puck.GRAVITY * t, 6.0)
	else:
		v = dir * max_speed * 0.8
		if saucer:
			v = v * 0.75 + Vector3.UP * 4.0
	puck.release(v, self, receiver)
	pass_released.emit(self, receiver)
	_set_state(State.FOLLOW_THROUGH)


func _can_one_time() -> bool:
	var net := attacking_net()
	return net != null and global_position.distance_to(net.global_position) < ONE_TIMER_RANGE


func _fire_shot(kind: StringName, charge: float) -> void:
	var net := attacking_net()
	var origin := puck.global_position
	var aim := intent.move
	var dir := aim.normalized() if aim.length() > 0.3 else heading
	var wrist_speed := PlayerStats.lerp_stat(stats.shot_power, 22.0, 30.0) * lerpf(0.92, 1.0, energy if fatigue_enabled else 1.0)
	var spd: float
	var spread: float
	var h_lo := 0.12
	var h_hi := 0.85
	match kind:
		&"slap":
			spd = lerpf(wrist_speed, PlayerStats.lerp_stat(stats.shot_power, 33.0, 44.0), charge)
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 6.0, 2.0) * (0.8 + 0.4 * charge)
			h_lo = 0.05
			h_hi = 0.65
		&"one_timer":
			spd = PlayerStats.lerp_stat(stats.shot_power, 31.0, 41.0)
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 5.0, 1.6)
			h_lo = 0.05
			h_hi = 0.7
		_:
			spd = wrist_speed
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 4.0, 1.2)

	var target: Vector3
	var to_net := Vector3.ZERO
	if net:
		to_net = net.global_position - origin
		to_net.y = 0.0
	var on_net := net != null and to_net.length() < 32.0 \
			and (kind == &"one_timer" or dir.angle_to(to_net) < deg_to_rad(80.0))
	if on_net:
		# Left/right on the stick picks the side of the net (screen x = world x).
		var ax := clampf(aim.x, -1.0, 1.0)
		if absf(ax) < 0.2:
			ax = _rng.randf_range(-0.55, 0.55)
		var half := RinkSpec.NET_WIDTH * 0.5 - 0.12
		target = Vector3(net.global_position.x + ax * half, _rng.randf_range(h_lo, h_hi), net.global_position.z)
	else:
		target = origin + dir * 20.0
		target.y = 0.3 if kind == &"wrist" else 0.0

	var flat := target - origin
	flat.y = 0.0
	var dist := maxf(flat.length(), 0.5)
	var fdir := flat.normalized().rotated(Vector3.UP, deg_to_rad(_rng.randfn(0.0, spread)))
	var t := dist / spd
	var vy := (target.y - origin.y) / t + 0.5 * Puck.GRAVITY * t
	vy += _rng.randfn(0.0, spread * 0.05)
	vy = clampf(vy, 0.0, 12.0)
	var v := fdir * spd + Vector3.UP * vy
	puck.release(v, self, null)
	last_shot_kind = kind
	shot_released.emit(self, kind, v.length())
	_set_state(State.FOLLOW_THROUGH)


# --- Checking ------------------------------------------------------------------

func _begin_check() -> void:
	_set_state(State.CHECK)
	_check_cooldown = CHECK_COOLDOWN
	_check_dir = intent.move.normalized() if intent.move.length() > 0.3 else heading
	_juke(_check_dir, CHECK_LUNGE, CHECK_TIME)


func _check_contact() -> void:
	for o in opponents:
		if not is_instance_valid(o) or o.state == State.DOWN:
			continue
		var to := o.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > CHECK_RANGE or d < 0.01:
			continue
		var dir := to / d
		if dir.angle_to(_check_dir) > CHECK_CONE:
			continue
		# Skating speed does the damage; the lunge just adds a flat bonus.
		var closing := (velocity - o.velocity).dot(dir)
		var power := maxf(closing, 0.0) * PlayerStats.lerp_stat(stats.checking, 0.85, 1.25) + 2.0
		if momentum:
			power *= 1.1
		var had_puck := o.has_puck() or o._since_puck < 0.8
		var from_behind := dir.dot(o.heading) > 0.55
		var result := o.receive_hit(power, dir, self)
		hit_landed.emit(self, o, power, result.kind, result.boards)
		if not had_puck:
			foul_committed.emit(self, o, &"interference")
		elif from_behind and result.boards:
			foul_committed.emit(self, o, &"boarding")
		velocity *= 0.4
		_juke_speed = 0.0
		_set_state(State.SKATE)
		return


## Applies a body check. Returns {kind: &"bump"/&"check"/&"big_hit", boards: bool}.
func receive_hit(power: float, dir: Vector3, _attacker: Skater) -> Dictionary:
	var resist := PlayerStats.lerp_stat(stats.strength, 0.85, 1.2) * (1.2 if intent.protect else 1.0)
	var p := power / resist
	var boards := false
	var pos2 := Vector2(global_position.x, global_position.z)
	if RinkSpec.sdf(pos2.x, pos2.y) > -1.6:
		var e := 0.05
		var out := Vector3(RinkSpec.sdf(pos2.x + e, pos2.y) - RinkSpec.sdf(pos2.x - e, pos2.y), 0.0,
				RinkSpec.sdf(pos2.x, pos2.y + e) - RinkSpec.sdf(pos2.x, pos2.y - e)).normalized()
		if dir.dot(out) > 0.4:
			p *= BOARDS_MULT
			boards = true
	fall_side = signf(dir.dot(right_dir())) if absf(dir.dot(right_dir())) > 0.1 else 1.0
	var kind: StringName
	if p < BUMP_LIMIT:
		kind = &"bump"
		_knock(dir * p * 0.5, State.STUMBLE, STUMBLE_TIME)
		if has_puck() and _rng.randf() < 0.35:
			puck.strip(self, dir * 2.0)
	elif p < CHECK_LIMIT:
		kind = &"check"
		_knock(dir * p * 0.6, State.DOWN, DOWN_TIME)
		if has_puck():
			puck.strip(self, dir * 3.0)
	else:
		kind = &"big_hit"
		_knock(dir * minf(p * 0.7, 9.0), State.DOWN, BIG_DOWN_TIME)
		if has_puck():
			puck.strip(self, dir * 4.0)
	return {"kind": kind, "boards": boards}


func _knock(v: Vector3, s: State, duration: float) -> void:
	velocity = velocity * 0.3 + v
	velocity.y = 0.0
	_juke_speed = 0.0
	_pass_hold = -1.0
	_set_state(s)
	_down_time = duration


func _begin_poke() -> void:
	_set_state(State.POKE)
	_poke_cooldown = POKE_COOLDOWN
	_poke_done = false


func _try_poke() -> void:
	var c := puck.carrier
	if c == null or c.team == team or c is Goalie:
		return
	var tip := global_position + heading * 1.25
	if Vector2(puck.global_position.x - tip.x, puck.global_position.z - tip.z).length() > POKE_REACH:
		# Missed the puck — did the stick catch the carrier's skates instead?
		if Vector2(c.global_position.x - tip.x, c.global_position.z - tip.z).length() < 0.75:
			foul_committed.emit(self, c, &"tripping")
		return
	var chance := 0.5 + (stats.defense - c.stats.puck_handling) * 0.005 - (0.3 if c.intent.protect else 0.0)
	if _rng.randf() < clampf(chance, 0.1, 0.9):
		puck.strip(c, (heading * 2.5 + right_dir() * _rng.randf_range(-2.0, 2.0)), self)
		poke_succeeded.emit(self, c)


# --- Pickup ------------------------------------------------------------------

func puck_anchor() -> Vector3:
	var right := right_dir()
	var fwd := BLADE_FORWARD + 0.1 * (1.0 - absf(_puck_lat))
	var lat := _puck_lat * BLADE_SIDE
	if intent.protect:
		fwd = 0.6
		lat = _puck_lat * 0.62
	if state == State.WINDUP:
		fwd += 0.1
	elif state == State.SKATE and absf(turn_speed) < 1.0:
		lat += sin(_dangle_t) * 0.07
	var p := global_position + heading * fwd + right * lat
	var c := RinkSpec.clamp_inside(p.x, p.z, RinkSpec.PUCK_RADIUS + 0.03)
	return Vector3(c.x, RinkSpec.PUCK_THICKNESS * 0.5, c.y)


## Where the blade rests when not carrying the puck.
func blade_rest() -> Vector3:
	return global_position + heading * BLADE_FORWARD + right_dir() * forehand_side() * BLADE_SIDE


func _try_pickup() -> void:
	if not handles_puck or puck == null or puck.carrier != null or not can_act():
		return
	if state == State.FOLLOW_THROUGH or not puck.can_pick(self):
		return
	var pp := puck.global_position
	if pp.y > 0.9:
		return
	var intended := puck.intended_receiver == self
	var reach := PlayerStats.lerp_stat(stats.puck_handling, 0.35, 0.5)
	var right := right_dir()
	var a := global_position + heading * 0.7 - right * 0.5
	var b := global_position + heading * 0.9 + right * 0.5
	var in_reach := _dist_to_segment_flat(pp, a, b) <= reach
	if intended and not in_reach:
		in_reach = Vector2(pp.x - global_position.x, pp.z - global_position.z).length() <= INTENDED_REACH
	if not in_reach:
		return
	if intended and (intent.shoot_held or _shoot_buffer > 0.0) and _can_one_time():
		puck.attach(self)
		_fire_shot(&"one_timer", 1.0)
		return
	var rel := (puck.velocity - velocity).length()
	var limit := 30.0 if intended else PlayerStats.lerp_stat(stats.puck_handling, 13.0, 21.0)
	if rel <= limit:
		var off := pp - global_position
		_puck_lat = clampf(off.dot(right) / BLADE_SIDE, -1.3, 1.3)
		_puck_lat_target = forehand_side()
		puck.attach(self)
	else:
		puck.deflect(self, _rng)


static func _dist_to_segment_flat(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)


# --- Movement --------------------------------------------------------------

func _update_stamina(delta: float) -> void:
	turbo_active = intent.turbo and not _turbo_locked and intent.move.length() > 0.2 \
			and state != State.WINDUP and can_act()
	if turbo_active:
		stamina -= PlayerStats.lerp_stat(stats.endurance, 0.38, 0.22) * delta
		if stamina <= 0.0:
			stamina = 0.0
			_turbo_locked = true
			turbo_active = false
	else:
		stamina = minf(1.0, stamina + 0.12 * delta)
		if _turbo_locked and stamina > 0.25:
			_turbo_locked = false
	if fatigue_enabled:
		var drain := PlayerStats.lerp_stat(stats.endurance, 1.0 / 38.0, 1.0 / 58.0)
		energy = maxf(0.0, energy - (drain + (0.012 if turbo_active else 0.0)) * delta)


func top_speed() -> float:
	var top := PlayerStats.lerp_stat(stats.speed, 7.3, 9.7)
	if has_puck():
		top *= PlayerStats.lerp_stat(stats.puck_handling, 0.9, 0.98)
	if intent.protect:
		top *= 0.8
	if intent.backward:
		top *= BACKWARD_SPEED
	if turbo_active:
		top *= TURBO_SPEED_MULT
	if momentum:
		top *= 1.05
	return top * fatigue_mult()


func _update_movement(delta: float) -> void:
	var top := top_speed()
	var accel := PlayerStats.lerp_stat(stats.acceleration, 10.0, 17.0) * (1.3 if turbo_active else 1.0) * fatigue_mult()
	var turn_fast := PlayerStats.lerp_stat(stats.agility, 3.0, 5.0)
	if has_puck():
		turn_fast *= PlayerStats.lerp_stat(stats.puck_handling, 0.85, 1.0)

	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := hv.length()
	var dir := hv / spd if spd > 0.05 else heading
	var want := intent.move
	if want.length() > 0.3:
		_aim_dir = want.normalized()
		_aim_age = 0.0
	else:
		_aim_age += delta
	if state == State.STUMBLE:
		want *= 0.3
	var want_len := minf(want.length(), 1.0)
	stopping = false
	turn_speed = 0.0

	if state == State.DOWN:
		spd = maxf(0.0, spd - DOWN_DECEL * delta)
	elif state == State.WINDUP and windup_time > WRIST_WINDOW:
		# Loading a slap shot: coast and barely steer.
		spd = maxf(0.0, spd - 3.0 * delta)
		if want_len > 0.15:
			var a := dir.signed_angle_to(want, Vector3.UP)
			dir = dir.rotated(Vector3.UP, clampf(a, -1.2 * delta, 1.2 * delta))
	elif want_len > 0.15:
		var want_dir := want / want.length()
		var a := dir.signed_angle_to(want_dir, Vector3.UP)
		if absf(a) > HARD_STOP_ANGLE and spd > 0.8 and not intent.backward:
			stopping = true
			spd = maxf(0.0, spd - HARD_STOP_DECEL * delta)
		elif spd < 1.0:
			dir = want_dir
			spd = minf(spd + accel * 1.3 * delta, top * want_len)
		else:
			var rate := lerpf(TURN_SLOW, turn_fast, clampf(spd / top, 0.0, 1.0))
			var step := clampf(a, -rate * delta, rate * delta)
			dir = dir.rotated(Vector3.UP, step)
			turn_speed = step / delta
			var target := top * want_len
			if spd < target:
				var k := lerpf(1.3, 0.55, clampf(spd / top, 0.0, 1.0))
				spd = minf(target, spd + accel * k * delta)
			else:
				spd = maxf(target, spd - OVERSPEED_DECEL * delta)
			spd = maxf(0.0, spd - absf(turn_speed) * CARVE_BLEED * delta)
	else:
		spd = maxf(0.0, spd - GLIDE_DECEL * delta)

	hv = dir.normalized() * spd
	velocity = Vector3(hv.x, 0.0, hv.z)


func _update_heading(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := hv.length()
	if stopping or state == State.DOWN:
		return
	if intent.backward and state == State.SKATE:
		if spd > 0.6:
			heading = _rotate_toward(heading, -hv / spd, 10.0 * delta)
		elif intent.move.length() > 0.15:
			heading = _rotate_toward(heading, -intent.move.normalized(), 10.0 * delta)
		return
	if state == State.WINDUP and intent.move.length() > 0.3:
		heading = _rotate_toward(heading, intent.move.normalized(), 6.0 * delta)
	elif state == State.CHECK:
		heading = _rotate_toward(heading, _check_dir, 14.0 * delta)
	elif spd > 0.6:
		heading = _rotate_toward(heading, hv / spd, 18.0 * delta)
	elif intent.move.length() > 0.15:
		heading = _rotate_toward(heading, intent.move.normalized(), 12.0 * delta)
	elif intent.face.length() > 0.1:
		heading = _rotate_toward(heading, intent.face.normalized(), 6.0 * delta)


static func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var a := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(a, -max_angle, max_angle)).normalized()


func _move(delta: float) -> void:
	var juke := _juke_dir * _juke_speed
	_juke_speed = maxf(0.0, _juke_speed - delta * _juke_decay)
	velocity += juke
	var pre := velocity
	move_and_slide()
	velocity -= juke
	# Bounce off the boards (and nets) on hard contact.
	var bounce := Vector3.ZERO
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is Skater:
			continue
		var n := c.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var vn := pre.dot(n)
		if vn < -4.0:
			bounce = n * (-vn * BOARD_BOUNCE)
	velocity += bounce
	velocity.y = 0.0
	if absf(global_position.y) > 0.001:
		global_position.y = 0.0
