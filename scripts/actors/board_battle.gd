class_name BoardBattle
extends RefCounted
## A puck battle on the boards: `pinner` holds `pinned` (who had the puck) against the
## wall. The puck sits at their skates, owned by neither, until one of them comes away
## with it, it squirts loose, or somebody else digs it out.
##
## It starts from a check: slow contact into the boards with the check button still held
## (Skater._check_contact). Skating in hard is a hit as before.
##
## The contest is `edge`, -1 (the pinner has it) .. +1 (the pinned breaks free):
##   * the pinner holding the check button leans on it (HOLD_EDGE a second) and can dig
##     for the puck (the deke / poke button) or shove off and end it (the shoot button);
##     letting go of the check button lets the carrier go with the puck
##   * the pinned fights back with each press of check or deke, or flick of the stick
##     (PUSH_EDGE each), can kick the puck up the boards (the pass button, the way the
##     stick points), and holding protect makes a dig less likely
##   * after MAX_TIME the puck squirts out toward whoever is ahead
## The pinner's physics tick runs it (Skater._update_actions); both skaters stand where
## `stand()` puts them and face `facing()`.

const BOARD_DIST := 1.7        ## the carrier is this close to the boards (m) for a pin: they're ridden the rest of the way in
const MAX_CLOSING := 5.0       ## m/s closing at contact: faster is a hit
const INTO_BOARDS := 0.1       ## the contact direction's share toward the boards: from their open-ice side, not from straight behind
const WALL_GAP := 0.4          ## the pinned skater's center off the board face
const BODY_GAP := 0.72         ## the pinner behind them
const SIDE_STEP := 0.14        ## ...and off to the side they came from
const MAX_TIME := 2.8
const LET_GO := 0.12           ## s off the check button before the pin lets go
const HOLD_EDGE := 0.22        ## per second, the pinner's lean
const PUSH_EDGE := 0.16        ## per push by the pinned
const PUSH_GAP := 0.09          ## s between pushes that count
const DIG_GAP := 0.55          ## s between digs
const KICK_GAP := 0.5
const DRIVE_GAP := 0.38        ## s between the pinner's drives into the pinned's back (the look and sound)
const COOLDOWN := 1.0          ## s before either can be in another one

var pinner: Skater
var pinned: Skater
var puck: Puck
var out := Vector3.RIGHT       ## toward the boards (flat, unit)
var along := Vector3.BACK      ## along them
var spot := Vector3.ZERO       ## where the pinned stands
var side := 1.0                ## which way along the boards the pinner stands off
var time := 0.0
var edge := 0.0
var has_puck := true           ## the puck is still in the battle
var over := false
var result: StringName = &""

var _off_button := 0.0
var _push_wait := 0.0
var _dig_wait := 0.25
var _kick_wait := 0.2
var _drive_wait := 0.0
var _flick := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


## Would this check contact (pinner into `victim`, along `dir`, closing at `closing`
## m/s) be a pin?
static func can_start(by: Skater, victim: Skater, dir: Vector3, closing: float) -> bool:
	if not by.intent.check_held or by.battle != null or victim.battle != null:
		return false
	if by._pin_cooldown > 0.0 or victim._pin_cooldown > 0.0:
		return false
	if not victim.has_puck() or victim is Goalie or not victim.can_act():
		return false
	if closing >= MAX_CLOSING:
		return false
	var p := victim.global_position
	if RinkSpec.sdf(p.x, p.z) < -BOARD_DIST:
		return false
	return dir.dot(wall_out(p)) > INTO_BOARDS


## The direction to the nearest boards from `p` (flat, unit).
static func wall_out(p: Vector3) -> Vector3:
	var e := 0.05
	var g := Vector3(RinkSpec.sdf(p.x + e, p.z) - RinkSpec.sdf(p.x - e, p.z), 0.0,
			RinkSpec.sdf(p.x, p.z + e) - RinkSpec.sdf(p.x, p.z - e))
	return g.normalized() if g.length_squared() > 1e-8 else Vector3.RIGHT


func start(by: Skater, victim: Skater) -> void:
	pinner = by
	pinned = victim
	puck = victim.puck
	_rng.seed = by._rng.randi()
	var p := victim.global_position
	out = wall_out(p)
	along = out.cross(Vector3.UP).normalized()
	# On the ice, WALL_GAP off the board face, straight in from where they are.
	var at := p - out * (RinkSpec.sdf(p.x, p.z) + WALL_GAP)
	spot = Vector3(at.x, 0.0, at.z)
	var across := (by.global_position - p).dot(along)
	side = signf(across) if absf(across) > 0.05 else (1.0 if _rng.randf() < 0.5 else -1.0)
	puck.strip(victim, Vector3.ZERO)
	by.battle = self
	victim.battle = self
	by._set_state(Skater.State.PIN)
	victim._set_state(Skater.State.PINNED)
	by._juke_speed = 0.0
	_hold_puck()
	_bump(out, 1.3)
	Sfx.play("boards", spot, -6.0)
	by.pin_started.emit(by, victim)


## Where `s` stands, and which way it faces.
func stand(s: Skater) -> Vector3:
	return spot if s == pinned else spot - out * BODY_GAP + along * side * SIDE_STEP


func facing(s: Skater) -> Vector3:
	if s == pinned:
		return out
	var to := pinned.global_position - pinner.global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else out


## Where the puck lies: on the ice between the pinned skater's skates and the boards.
func puck_spot() -> Vector3:
	var p := spot + out * (WALL_GAP - RinkSpec.PUCK_RADIUS - 0.04)
	return Vector3(p.x, puck.rest_y if puck else 0.0, p.z)


func tick(delta: float) -> void:
	if over:
		return
	if not is_instance_valid(pinned) or pinned.battle != self or pinned.state != Skater.State.PINNED:
		abort()
		return
	time += delta
	_push_wait -= delta
	_dig_wait -= delta
	_kick_wait -= delta
	if puck.carrier != null or puck.dead:
		# Somebody else came away with it (or the whistle went).
		has_puck = false
		finish(&"taken")
		return
	_hold_puck()

	# The pinner: on the button, leaning; off it, the carrier goes free.
	var pi := pinner.intent
	_off_button = 0.0 if pi.check_held else _off_button + delta
	if _off_button > LET_GO:
		finish(&"release")
		return
	var lean := _lean_of(pinner) / _lean_of(pinned)
	edge -= HOLD_EDGE * lean * delta
	pinner.stamina = maxf(0.0, pinner.stamina - 0.1 * delta)
	_drive_wait -= delta
	if _drive_wait <= 0.0:
		_drive_wait = DRIVE_GAP * _rng.randf_range(0.8, 1.25)
		_bump(out, 0.8)

	# The pinned: every press or flick pushes back.
	var vi := pinned.intent
	if _pushed(vi) and _push_wait <= 0.0:
		_push_wait = PUSH_GAP
		edge += PUSH_EDGE / lean
		pinned.stamina = maxf(0.0, pinned.stamina - 0.02)
		_bump(-out, 1.1)
	if vi.pass_down and _kick_wait <= 0.0:
		_kick_wait = KICK_GAP
		if _rng.randf() < clampf(0.55 + edge * 0.3, 0.15, 0.9):
			finish(&"kick")
			return
		edge -= 0.12
		_bump(out, 0.7)
	if pi.shoot_down:
		finish(&"shove")
		return
	if pi.deke_down and _dig_wait <= 0.0:
		_dig_wait = DIG_GAP
		var chance := 0.32 - edge * 0.3 + (pinner.stats.defense - pinned.stats.puck_handling) * 0.004 			- (0.2 if vi.protect else 0.0)
		if _rng.randf() < clampf(chance, 0.05, 0.85):
			finish(&"dig")
			return
		edge += 0.08
		_bump(-out, 0.6)

	if edge >= 1.0:
		finish(&"break")
	elif edge <= -1.0:
		finish(&"won")
	elif time >= MAX_TIME:
		finish(&"loose")


## How hard a skater leans in a battle: strength, with a little of the trade (checking
## for the one pinning, puck handling for the one shielding it).
func _lean_of(s: Skater) -> float:
	var trade: float = s.stats.checking if s == pinner else s.stats.puck_handling
	return PlayerStats.lerp_stat(s.stats.strength, 0.8, 1.25) * PlayerStats.lerp_stat(trade, 0.92, 1.08)


## A push by the pinned: a press of check or deke, or the stick flicked a new way.
func _pushed(i: SkaterIntent) -> bool:
	if i.check_down or i.deke_down:
		return true
	var m := i.move
	if m.length() < 0.6:
		if m.length() < 0.3:
			_flick = Vector3.ZERO
		return false
	if _flick == Vector3.ZERO or m.normalized().dot(_flick) < 0.5:
		_flick = m.normalized()
		return true
	return false


func _hold_puck() -> void:
	puck.velocity = Vector3.ZERO
	puck.global_position = puck_spot()
	puck.on_ice = true
	puck.intended_receiver = null
	puck.block_pickup(pinner, 0.15)
	puck.block_pickup(pinned, 0.15)


## A jostle both bodies show (SkaterVisual kicks its sprung tilt along `dir`).
func _bump(dir: Vector3, power: float) -> void:
	for s: Skater in [pinner, pinned]:
		if is_instance_valid(s):
			s.pin_bump += 1
			s.pin_bump_dir = dir * power
	if time > 0.05:
		Sfx.play("body", spot, -14.0 + 4.0 * power)


## Ends the battle. Results: &"release" (the pinner let go: the carrier keeps the puck),
## &"break" (the pinned spins off with it), &"won" (the pinner comes away with it), &"dig"
## (dug out to open ice), &"kick" (kicked up the boards), &"shove" (the pinner shoves off:
## loose at the wall), &"loose" (time: it squirts toward whoever was ahead), &"taken"
## (somebody else got it).
func finish(how: StringName) -> void:
	if over:
		return
	over = true
	result = how
	var a := pinner
	var b := pinned
	_free(a)
	_free(b)
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	# Whichever way it goes, the puck has to get out past both of them.
	puck._add_exception(a, 0.45)
	puck._add_exception(b, 0.45)
	match how:
		&"release":
			a._set_state(Skater.State.SKATE)
			b._set_state(Skater.State.SKATE)
			if has_puck:
				puck._no_pickup.erase(b)
				puck.attach(b)
		&"break":
			b._set_state(Skater.State.SKATE)
			puck._no_pickup.erase(b)
			puck.attach(b)
			b.velocity = (-along * side * 3.5 - out * 1.0)
			a._knock(-out * 1.6, Skater.State.STUMBLE, Skater.STUMBLE_TIME)
			_hit_look(a, -out, 4.0)
		&"won":
			a._set_state(Skater.State.SKATE)
			puck._no_pickup.erase(a)
			puck.attach(a)
			puck.block_pickup(b, 0.7)
			b._knock(along * -side * 1.2, Skater.State.STUMBLE, Skater.STUMBLE_TIME)
			_hit_look(b, out, 4.0)
		&"dig":
			a._set_state(Skater.State.SKATE)
			_launch(-out * 3.2 + along * _rng.randf_range(-2.0, 2.0), a)
			puck.block_pickup(b, 0.7)
			b._knock(Vector3.ZERO, Skater.State.STUMBLE, Skater.STUMBLE_TIME * 0.8)
			_hit_look(b, out, 3.0)
		&"kick":
			a._set_state(Skater.State.SKATE)
			b._set_state(Skater.State.SKATE)
			var want := b.intent.move.dot(along)
			var way := signf(want) if absf(want) > 0.25 else -side
			_launch(along * way * 9.0 - out * 0.6, b)
			puck.block_pickup(a, 0.5)
			puck.block_pickup(b, 0.4)
		&"shove":
			a._set_state(Skater.State.SKATE)
			_launch(along * (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(1.5, 3.0) - out * 0.8, a)
			puck.block_pickup(a, 0.3)
			puck.block_pickup(b, 0.6)
			b._knock(out * 0.8, Skater.State.STUMBLE, Skater.STUMBLE_TIME)
			_hit_look(b, out, 5.0)
			a.since_check_landed = 0.0
			a.landed_kind = &"bump"
			a.landed_power = 4.0
			a.check_kind = &"shove"
		&"loose":
			a._set_state(Skater.State.SKATE)
			b._set_state(Skater.State.SKATE)
			if edge > 0.0:
				_launch(-along * side * 4.0 - out * 0.8, b)
				puck.block_pickup(a, 0.5)
			else:
				_launch(-out * 3.0 + along * _rng.randf_range(-1.5, 1.5), a)
				puck.block_pickup(b, 0.5)
		_:
			a._set_state(Skater.State.SKATE)
			b._set_state(Skater.State.SKATE)
	a.pin_ended.emit(a, b, how)


## The battle is cut off from outside (a hit, a whistle, a skater taken off the ice): the
## puck stays where it lies.
func abort() -> void:
	if over:
		return
	over = true
	result = &"broken"
	var a := pinner
	var b := pinned
	_free(a)
	_free(b)
	for s: Skater in [a, b]:
		if is_instance_valid(s) and (s.state == Skater.State.PIN or s.state == Skater.State.PINNED):
			s._set_state(Skater.State.SKATE)
	if is_instance_valid(a) and is_instance_valid(b):
		a.pin_ended.emit(a, b, result)


func _free(s: Skater) -> void:
	if is_instance_valid(s) and s.battle == self:
		s.battle = null
		s._pin_cooldown = COOLDOWN
		s._check_cooldown = maxf(s._check_cooldown, 0.4)


func _launch(v: Vector3, by: Skater) -> void:
	if not has_puck or puck.carrier != null:
		return
	puck.global_position = puck_spot()
	puck.velocity = Vector3(v.x, 0.0, v.z)
	puck.last_touch = by
	puck.flight += 1
	puck.touched.emit(by)


## The stumble's look: the same tilt and clip a hit taken gives.
func _hit_look(s: Skater, dir: Vector3, power: float) -> void:
	s.hit_dir = dir
	s.hit_power = power
	s.since_hit = 0.0
