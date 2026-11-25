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
## A puck battle on the boards (BoardBattle) starts and ends; `result` is how (BoardBattle.finish).
signal pin_started(pinner: Skater, pinned: Skater)
signal pin_ended(pinner: Skater, pinned: Skater, result: StringName)

## PIN: holding an opponent against the boards; PINNED: held there (both: `battle`).
enum State { SKATE, WINDUP, FOLLOW_THROUGH, DEKE, CHECK, POKE, STUMBLE, DOWN, PIN, PINNED }

# --- Skating feel ---
const TURN_SLOW := 14.0           ## rad/s turn rate when nearly stopped
const HARD_STOP_ANGLE := 2.2689   ## 130 degrees: reversing the stick past this = hockey stop
const HARD_STOP_DECEL := 24.0
const GLIDE_DECEL := 2.2          ## coasting with no stick input
const DOWN_DECEL := 8.0           ## sliding on the ice after a hit (a body on the ice grabs: a short slide)
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
const SHOT_RANGE := 32.0          ## meters from the net a shot still goes at it
const SHOT_AIM_CLOSE := 18.0      ## inside this, a stick pointing away still aims (low)
const SHOT_POST_INSET := 0.17     ## a full-corner aim sits this far inside the post (m)
const SHOT_REST_HEIGHT := 0.35    ## aim height with the stick sideways or idle (0 ice .. 1 top)
const SHOT_SCATTER := 0.55        ## Accuracy's degrees become meters at the net, times this
const PASS_LANE_WIDTH := 1.1      ## an opponent this close to the line is "in the lane" (m)
const PASS_LANE_PENALTY := 30.0   ## per opponent in the lane (about 19 degrees of stick angle)
const PASS_STICKY_BONUS := 8.0    ## the current pick's edge (about 5 degrees)
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
const CHECK_LEAD_IN := 0.06       ## s the hit loads before it can land
const CHECK_TIME := 0.36          ## the lead-in, then 0.3 s in which it can land
const CHECK_LUNGE := 3.0          ## m/s burst along the check direction
const SHOVE_SPEED := 3.0          ## m/s closing on the target when the check starts: slower is a shove
const WHIFF_TIME := 0.35          ## s off balance after a check that hit nothing
const WHIFF_ACCEL := 0.45         ## acceleration while off balance
const HITSTOP := {&"check": 0.045, &"big_hit": 0.06}   ## s both bodies hold at the point of impact
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

# --- Fouls (the director rolls whether the referee calls them) ---
const TRIP_REACH := 0.75          ## a missed poke whose tip lands this close to the carrier: tripping
const HOOK_REACH := 1.05          ## ...or, from behind, this close: hooking (the stick catches the body)
const HOOK_BEHIND := 0.35         ## "from behind": poker-to-carrier direction · carrier heading above this
const CHARGE_RUNUP := 0.9         ## s of turbo straight into a check before it counts as a run-up
const CHARGE_CLOSING := 9.0       ## m/s closing speed at contact, with a run-up: charging
const HIGHSTICK_RANGE := 1.35     ## a slap shot's windup catches an opponent this close on the stick side
const HIGHSTICK_CHARGE := 0.35    ## only a real windup (slap charge at least this)
const HOLD_RANGE := 0.8           ## draped on the carrier: closer than this, beside or behind them
const HOLD_TIME := 1.8            ## s glued on before it's holding
const HOLD_COOLDOWN := 6.0        ## s before the same skater can be flagged for holding again

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
var autopilot: Brain              ## set: drives the skater instead of `brain` (skating to a faceoff)
var _ignored := SkaterIntent.new()   ## what `brain` wants while the autopilot drives
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
## Body checks, for the visual. Checker: which shoulder (or hip) leads the check (+1 right,
## -1 left), what kind it is (&"shoulder"; &"hip", thrown skating backward; &"shove", from
## a near standstill), seconds since the last one landed, what it did and how hard, and
## seconds since the last one that hit nothing. Victim: the push direction (flat, world),
## how hard (after balance) and seconds since.
var check_lead := 1.0
var check_kind: StringName = &"shoulder"
var since_check_landed := 10.0
var landed_kind: StringName = &""
var landed_power := 0.0
var since_check_missed := 10.0
var hitstop := 0.0                ## s left held in place by a hit (given or taken)
## The puck battle on the boards this skater is in (State.PIN / PINNED), and its jostles
## for the visual: a count that goes up with each one, and its push (flat, world).
var battle: BoardBattle
var pin_bump := 0
var pin_bump_dir := Vector3.ZERO
var _pin_cooldown := 0.0
var hit_dir := Vector3.ZERO
var hit_power := 0.0
var since_hit := 10.0
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
var catch_up := 0.0               ## 0..1: catch-up AI for a team two or more goals down (a touch faster, sharper shots)
var injured := false              ## hurt and out for the rest of the game (MatchDirector._injure)
var last_impact := 0.0            ## the last body check this skater took, after balance and the boards (glass breaks)
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
var mask_paint := ""             ## goalies: their own mask paint (a GoalieVisual.MASK_PAINTS name or MASK_PLAIN), "" = the team's or one from their name
var mask_colors := 0             ## ... and which of the design's color schemes
var gear_style := 0              ## helmet model (goalies: mask model): an index, or a roll (SkaterVisual.gear_roll); see SkaterVisual.HELMETS / GoalieVisual.MASKS
var headgear := ""               ## a mask worn instead of the helmet (SkaterVisual.TEAM_MASKS key) whatever the team wears; "" = the team's way
var visor := true                ## a visor on the helmet (skaters); see Skater.visor_for
var visor_tint := ""             ## its tint (SkaterVisual.VISOR_TINTS: "" clear, "smoke", "amber", "mirror", "gold"); the full shield's too
## Cosmetics, each its own slot: "" = as the team does (its uniform's key of the same
## name; nothing, for nearly every team), else this player's own (SkaterVisual.cosmetic).
var helmet_crest := ""           ## on top of the helmet (SkaterVisual.CRESTS): "spines"
var eye_fx := ""                 ## the eyes (SkaterVisual.EYE_FX): "red" = glowing red
var dangler := ""                ## hung under the visor (SkaterVisual.DANGLERS): "fangs"; the slot a goalie's throat dangler will share
var face_gear := ""              ## worn on the helmet in place of the visor (SkaterVisual.FACE_GEAR): "" none, "shield" a full clear shield, "cage" a wire cage
var hair_style := ""              ## SkaterVisual.HAIR_STYLES; "" = none showing
var facial_hair := ""             ## SkaterVisual.FACIAL_HAIR, or ""
var hair_color := Color(0.16, 0.1, 0.06)
var eye_color := Color(0.34, 0.2, 0.09)   ## sRGB; see SkaterVisual.EYE_COLORS
var stick_style := "black"        ## SkaterVisual.STICK_STYLES: "wood", "black", "black_white", ...
var stick_tape := "white"         ## SkaterVisual.TAPES: "white", "black", "team" or "none"
## The Old-Time Set (SkaterVisual.OLD): "" = as the team does (the standard gear, unless
## the team's uniform says `kit` = "old"), "old" = this player's own old-time piece.
var glove_style := ""             ## "old": leather gauntlets
var skate_style := ""             ## "old": leather boots on tube frames
var pad_style := ""               ## goalies: "old" = leather pads, a waffle board and a mitt
## The legs (SkaterVisual.dress_legs), likewise "" = as the team does.
var sock_style := ""              ## "taped": clear tape round the shins; "old": heavy wool
var pants_style := ""             ## "old": canvas; "long": long pants down over the socks
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
var _last_pass_target: Skater = null
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
var _turbo_run := 0.0             ## s of unbroken turbo (charging run-ups)
var _check_runup := 0.0           ## _turbo_run when the current check began
var _draped_on: Skater = null       ## the carrier this skater is draped on (holding)
var _draped_time := 0.0
var _draped_cooldown := 0.0


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
	hitstop = 0.0
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
	# The same goes for a check: its timers only run in _tick_timers, and the visual poses
	# from them, so a skater frozen or walked off mid-hit would hold the hit pose.
	since_check_landed = 10.0
	since_check_missed = 10.0
	hitstop = 0.0
	if state == State.CHECK or state == State.PIN or state == State.PINNED:
		_set_state(State.SKATE)


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
	if autopilot:
		if brain:
			# Still read (into nothing), so a pad's button edges stay current for later.
			brain.update(self, _ignored, delta)
			_ignored.clear()
		autopilot.update(self, intent, delta)
	elif brain:
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
	if battle != null and s != State.PIN and s != State.PINNED:
		battle.abort()   # knocked, whistled or walked out of a board battle
	state = s
	_state_time = 0.0
	if s != State.WINDUP:
		windup_time = 0.0
		shot_charge = 0.0


func _tick_timers(delta: float) -> void:
	_shoot_buffer = maxf(0.0, _shoot_buffer - delta)
	_deke_cooldown = maxf(0.0, _deke_cooldown - delta)
	_check_cooldown = maxf(0.0, _check_cooldown - delta)
	_pin_cooldown = maxf(0.0, _pin_cooldown - delta)
	since_check_landed += delta
	since_check_missed += delta
	since_hit += delta
	_poke_cooldown = maxf(0.0, _poke_cooldown - delta)
	if _deke_return > 0.0:
		_deke_return -= delta
		if _deke_return <= 0.0:
			_puck_lat_target = forehand_side()
	_puck_lat = move_toward(_puck_lat, _puck_lat_target, 9.0 * delta)
	_dangle_t += delta * (5.0 + flat_speed() * 0.4)
	_since_puck = 0.0 if has_puck() else _since_puck + delta
	_draped_cooldown = maxf(0.0, _draped_cooldown - delta)
	_check_holding(delta)


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
				since_check_missed = 0.0
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
		State.PIN:
			_pass_hold = -1.0
			if battle == null:
				_set_state(State.SKATE)
			else:
				battle.tick(delta)
		State.PINNED:
			# The pinner's tick runs the battle; this only catches one that stopped running.
			_pass_hold = -1.0
			if battle == null:
				_set_state(State.SKATE)
			elif _state_time > BoardBattle.MAX_TIME + 0.5:
				battle.abort()


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


## The teammate a pass in `dir` goes to: mostly where the stick points, then the open
## lane, then distance. The last pick gets a small edge so the marker doesn't flicker.
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
		score += _lane_blockers(m) * PASS_LANE_PENALTY
		if m == _last_pass_target:
			score -= PASS_STICKY_BONUS
		if score < best_score:
			best_score = score
			best = m
	_last_pass_target = best
	return best


## Opponents standing in the passing lane to `mate` (close to the line, between the two).
func _lane_blockers(mate: Skater) -> int:
	var a := Vector2(global_position.x, global_position.z)
	var b := Vector2(mate.global_position.x, mate.global_position.z)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.01:
		return 0
	var n := 0
	for o in opponents:
		if not is_instance_valid(o):
			continue
		var p := Vector2(o.global_position.x, o.global_position.z)
		var t := (p - a).dot(ab) / len2
		if t < 0.08 or t > 0.95:
			continue
		if p.distance_to(a + ab * t) < PASS_LANE_WIDTH:
			n += 1
	return n


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
	var max_speed := PlayerStats.lerp_stat(stats.passing, 19.0, 28.0)
	var v: Vector3
	if receiver:
		var dist := origin.distance_to(receiver.global_position)
		var spd := clampf(11.0 + dist * 1.1, 12.0, max_speed)
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


## The stick direction a shot aims with: held now, or let go of a moment ago.
func shot_aim() -> Vector3:
	if intent.move.length() > 0.3:
		return intent.move
	if _aim_age < AIM_MEMORY:
		return _aim_dir
	return Vector3.ZERO


## A shot from here goes at the net (in range and facing it), rather than along the stick.
func _shot_on_net(kind: StringName, aim: Vector3) -> bool:
	var net := attacking_net()
	if net == null:
		return false
	var to_net := net.global_position - global_position
	to_net.y = 0.0
	var d := to_net.length()
	if d >= SHOT_RANGE:
		return false
	if kind == &"one_timer":
		return true
	var dir := aim.normalized() if aim.length() > 0.3 else heading
	if dir.angle_to(to_net) < deg_to_rad(80.0):
		return true
	# Close in and facing the net, any stick direction is an aim (pull back = low).
	return d < SHOT_AIM_CLOSE and heading.angle_to(to_net) < deg_to_rad(95.0)


## Where on the goal mouth the stick aims (no scatter). Left/right on the stick picks
## the side (screen x = world x); toward the net end of the ice is high, away is low.
## No stick: low-to-mid on the side the goalie leaves open (far side if centered).
func aimed_spot(kind: StringName, aim: Vector3) -> Vector3:
	var net := attacking_net()
	var np := net.global_position
	var half := RinkSpec.NET_WIDTH * 0.5 - SHOT_POST_INSET
	var top := RinkSpec.NET_HEIGHT - (0.3 if kind == &"slap" else 0.22)
	var ax := 0.0
	var up := 0.0
	if aim.length() > 0.3:
		var n := aim.normalized()
		var toward := signf(np.z - global_position.z)
		ax = clampf(n.x * 1.4, -1.0, 1.0)
		up = clampf(n.z * toward * 1.4, -1.0, 1.0)
	else:
		var g := _goalie_of(net)
		var gx := (g.global_position.x - np.x) if g else 0.0
		if absf(gx) > 0.08:
			ax = -signf(gx) * 0.75
		else:
			var from := global_position.x - np.x
			ax = -signf(from) * 0.6 if absf(from) > 0.5 else 0.0
	var v := SHOT_REST_HEIGHT + (up * (1.0 - SHOT_REST_HEIGHT) if up > 0.0 else up * SHOT_REST_HEIGHT)
	return Vector3(np.x + ax * half, lerpf(0.06, top, v), np.z)


func _goalie_of(net: Net) -> Goalie:
	for g in get_tree().get_nodes_in_group("goalies"):
		if g is Goalie and g.net == net and is_instance_valid(g):
			return g
	return null


func _fire_shot(kind: StringName, charge: float) -> void:
	var net := attacking_net()
	var origin := puck.global_position
	var aim := shot_aim()
	var dir := aim.normalized() if aim.length() > 0.3 else heading
	var wrist_speed := PlayerStats.lerp_stat(stats.shot_power, 22.0, 30.0) * lerpf(0.92, 1.0, energy if fatigue_enabled else 1.0)
	var spd: float
	var spread: float
	match kind:
		&"slap":
			spd = lerpf(wrist_speed, PlayerStats.lerp_stat(stats.shot_power, 33.0, 44.0), charge)
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 6.0, 2.0) * (0.8 + 0.4 * charge)
		&"one_timer":
			spd = PlayerStats.lerp_stat(stats.shot_power, 31.0, 41.0)
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 5.0, 1.6)
		_:
			spd = wrist_speed
			spread = PlayerStats.lerp_stat(stats.shot_accuracy, 4.0, 1.2)
	spread *= 1.0 - 0.15 * catch_up
	spd *= 1.0 + 0.03 * catch_up

	var target: Vector3
	var fdir: Vector3
	var on_net := _shot_on_net(kind, aim)
	if on_net:
		# Aimed at a spot on the goal mouth; Accuracy decides how close to it the puck goes
		# (meters at the net, so a long shot strays further than one from the slot).
		target = aimed_spot(kind, aim)
		var reach := Vector2(target.x - origin.x, target.z - origin.z).length()
		var sigma := clampf(reach * deg_to_rad(spread) * SHOT_SCATTER, 0.04, 0.6)
		target.x += _rng.randfn(0.0, sigma)
		target.y = maxf(0.03, target.y + _rng.randfn(0.0, sigma * 0.7))
	else:
		target = origin + dir * 20.0
		target.y = 0.3 if kind == &"wrist" else 0.0

	var flat := target - origin
	flat.y = 0.0
	var dist := maxf(flat.length(), 0.5)
	fdir = flat.normalized()
	if not on_net:
		fdir = fdir.rotated(Vector3.UP, deg_to_rad(_rng.randfn(0.0, spread)))
	var t := dist / spd
	var vy := (target.y - origin.y) / t + 0.5 * Puck.GRAVITY * t
	vy = clampf(vy, 0.0, 12.0)
	var v := fdir * spd + Vector3.UP * vy
	puck.release(v, self, null)
	last_shot_kind = kind
	if kind == &"slap" and charge >= HIGHSTICK_CHARGE:
		_check_high_stick()
	shot_released.emit(self, kind, v.length())
	_set_state(State.FOLLOW_THROUGH)


# --- Checking ------------------------------------------------------------------

func _begin_check() -> void:
	_check_runup = _turbo_run
	_set_state(State.CHECK)
	_check_cooldown = CHECK_COOLDOWN
	_check_dir = intent.move.normalized() if intent.move.length() > 0.3 else heading
	_juke(_check_dir, CHECK_LUNGE, CHECK_TIME)
	# Lead with the shoulder nearer the target (the nearest opponent ahead); with nobody
	# there, the one away from the stick blade.
	check_lead = -forehand_side()
	var best := 3.5
	var closing := flat_speed()
	for o in opponents:
		if not is_instance_valid(o) or o.is_down():
			continue
		var to := o.global_position - global_position
		to.y = 0.0
		if to.length() < best and to.length() > 0.05 and to.normalized().dot(_check_dir) > 0.2:
			best = to.length()
			closing = (velocity - o.velocity).dot(to.normalized())
			var across := to.dot(right_dir())
			if absf(across) > 0.08:
				check_lead = signf(across)
	# Skating backward: a hip check, the body staying turned as it is. Barely closing on
	# the target: a shove. Otherwise the shoulder.
	if intent.backward:
		check_kind = &"hip"
	elif closing < SHOVE_SPEED:
		check_kind = &"shove"
	else:
		check_kind = &"shoulder"


func _check_contact() -> void:
	if _state_time < CHECK_LEAD_IN:
		return
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
		if BoardBattle.can_start(self, o, dir, closing):
			# Slow contact into the boards, still on the button: a pin, not a hit.
			BoardBattle.new().start(self, o)
			return
		var had_puck := o.has_puck() or o._since_puck < 0.8
		var from_behind := dir.dot(o.heading) > 0.55
		var result := o.receive_hit(power, dir, self)
		hit_landed.emit(self, o, power, result.kind, result.boards)
		if not had_puck:
			foul_committed.emit(self, o, &"interference")
		elif from_behind and result.boards:
			foul_committed.emit(self, o, &"boarding")
		elif _check_runup >= CHARGE_RUNUP and closing >= CHARGE_CLOSING:
			# A long turbo run straight into the hit: charging.
			foul_committed.emit(self, o, &"charging")
		velocity *= 0.4
		_juke_speed = 0.0
		since_check_landed = 0.0
		landed_kind = result.kind
		landed_power = o.hit_power
		hitstop = HITSTOP.get(result.kind, 0.0)
		o.hitstop = hitstop
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
	last_impact = p
	hit_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	hit_power = p
	since_hit = 0.0
	var kind: StringName
	if p < BUMP_LIMIT:
		kind = &"bump"
		_knock(dir * p * 0.5, State.STUMBLE, STUMBLE_TIME)
		if has_puck() and _rng.randf() < 0.35:
			puck.strip(self, dir * 2.0)
	elif p < CHECK_LIMIT:
		kind = &"check"
		_knock(dir * p * 0.42, State.DOWN, DOWN_TIME)
		if has_puck():
			puck.strip(self, dir * 3.0)
	else:
		kind = &"big_hit"
		_knock(dir * minf(p * 0.5, 6.5), State.DOWN, BIG_DOWN_TIME)
		if has_puck():
			puck.strip(self, dir * 4.0)
	return {"kind": kind, "boards": boards}


## Hurt: stays down on the ice this long (from now) before getting up.
func stay_down(seconds: float) -> void:
	if state == State.DOWN:
		_down_time = maxf(_down_time, _state_time + seconds)


func _knock(v: Vector3, s: State, duration: float) -> void:
	velocity = velocity * 0.2 + v
	velocity.y = 0.0
	_juke_speed = 0.0
	_pass_hold = -1.0
	_set_state(s)
	_down_time = duration


## A big slap-shot windup with an opponent tight on the stick side: the stick comes up
## into them (high-sticking).
func _check_high_stick() -> void:
	var side := right_dir() * forehand_side()
	for o in opponents:
		if not is_instance_valid(o) or o.is_down() or o.benched:
			continue
		var to := o.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.05 or d > HIGHSTICK_RANGE:
			continue
		# On the stick side, and not out in front (the blade comes back and up over the shoulder).
		if to.dot(side) / d > 0.25 and to.dot(heading) / d < 0.6:
			foul_committed.emit(self, o, &"high_sticking")
			return


## Holding: glued to the other team's carrier, beside or behind them, for HOLD_TIME.
func _check_holding(delta: float) -> void:
	var c: Skater = puck.carrier if puck else null
	var ok := c != null and not (c is Goalie) and c.team != team and not has_puck() 			and can_act() and not benched and _draped_cooldown <= 0.0 and c.flat_speed() > 1.0
	if ok:
		var to := c.global_position - global_position
		to.y = 0.0
		var d := to.length()
		ok = d < HOLD_RANGE and d > 0.05 and to.dot(c.heading) / d > -0.2
	if not ok or c != _draped_on:
		_draped_on = c if ok else null
		_draped_time = 0.0
		return
	_draped_time += delta
	if _draped_time >= HOLD_TIME:
		foul_committed.emit(self, c, &"holding")
		_draped_on = null
		_draped_time = 0.0
		_draped_cooldown = HOLD_COOLDOWN


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
		# Missed the puck — did the stick catch the carrier instead? From behind it hooks
		# the body (hooking); otherwise it takes the skates (tripping).
		var miss := Vector2(c.global_position.x - tip.x, c.global_position.z - tip.z).length()
		var to := c.global_position - global_position
		to.y = 0.0
		var behind := to.length() > 0.05 and to.normalized().dot(c.heading) > HOOK_BEHIND
		if behind and miss < HOOK_REACH:
			foul_committed.emit(self, c, &"hooking")
		elif miss < TRIP_REACH:
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
	_turbo_run = _turbo_run + delta if turbo_active else 0.0
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
	top *= 1.0 + 0.03 * catch_up
	return top * fatigue_mult()


func _update_movement(delta: float) -> void:
	if battle != null and (state == State.PIN or state == State.PINNED):
		# A board battle: held on its spot.
		var to_spot := battle.stand(self) - global_position
		to_spot.y = 0.0
		velocity = (to_spot * 14.0).limit_length(6.0)
		stopping = false
		turn_speed = 0.0
		return
	var top := top_speed()
	var accel := PlayerStats.lerp_stat(stats.acceleration, 10.0, 17.0) * (1.3 if turbo_active else 1.0) * fatigue_mult()
	if since_check_missed < WHIFF_TIME:
		accel *= WHIFF_ACCEL
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
	if battle != null and (state == State.PIN or state == State.PINNED):
		heading = _rotate_toward(heading, battle.facing(self), 12.0 * delta)
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
		if check_kind != &"hip":
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
	if hitstop > 0.0:
		# A hit just landed: both bodies stay where they met for a few ticks, then fly.
		hitstop -= delta
		return
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
