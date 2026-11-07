class_name Fight
extends Node
## The fight mini-game (DESIGN §5.2). The director creates one when a team drops the
## gloves; it runs while the match is in Phase.FIGHT and reports the result.
##
## Stages: PROMPT (a human on the team that took the hit decides: A yes / B no) ->
## SQUARE_UP (sticks and gloves drop, the others form a ring, the camera cuts in) ->
## FIGHT -> OVER (knockdown or decision, then the director sends both to the box).
##
## Each fighter has health (fighting + durability), balance (strength) and stamina
## (endurance). Moves: jab (fast, weak), haymaker (slow visible windup, strong, can be
## dodged by leaning), grab (holds the jersey: more damage, drains the other's balance,
## and unlocks the uppercut), uppercut (only from a grab), block (hold: much less damage,
## costs stamina). Lean with the stick to dodge. Health or balance at 0 = knocked down.
## Time limit, or both out of gas, ends it on points (damage dealt); close = a draw.

signal finished(winner: Skater, loser: Skater)   ## winner null = draw (loser null too)
signal declined

enum Stage { PROMPT, SQUARE_UP, FIGHT, OVER }

const PROMPT_TIME := 3.0
const SQUARE_TIME := 1.4
const TIME_LIMIT := 30.0
const OVER_TIME := 3.2
const GAP := 0.95             ## meters between the fighters' centers
const LEAN_DIST := 0.3
const RING_RADIUS := 4.6
const GRAB_TIME := 3.0
const DRAW_MARGIN := 0.15     ## damage within this share of each other = a draw
const MOVE_INPUT_LATCH := 0.18

## Moves: clip, clip time of contact, seconds to contact, recovery after contact,
## damage, balance damage, stamina cost.
const MOVES := {
	"jab": {"clip": "lead_jab", "impact": 0.5, "windup": 0.24, "recover": 0.22, "dmg": 3.5, "bal": 2.0, "cost": 3.0},
	"hay": {"clip": "hook", "impact": 0.4, "windup": 0.5, "recover": 0.38, "dmg": 10.0, "bal": 7.0, "cost": 9.0},
	"upper": {"clip": "uppercut", "impact": 1.05, "windup": 0.42, "recover": 0.32, "dmg": 12.0, "bal": 11.0, "cost": 8.0},
	"grab": {"clip": "punching", "impact": 0.4, "windup": 0.26, "recover": 0.2, "dmg": 0.0, "bal": 3.0, "cost": 4.0},
}
const HIT_CLIPS := {"jab": "light_hit_to_head", "hay": "head_hit", "upper": "receive_uppercut_to_the_face", "body": "stomach_hit"}
const IDLE_CLIP := "bouncing_fight_idle"
const BLOCK_CLIP := "center_block"


class Fighter:
	var s: Skater
	var other: Fighter
	var human: HumanBrain
	var intent := SkaterIntent.new()
	var max_health := 100.0
	var health := 100.0
	var max_balance := 100.0
	var balance := 100.0
	var max_stamina := 100.0
	var stamina := 100.0
	var act := ""             ## "", a MOVES key, "hit" (reacting), "down"
	var act_t := 0.0
	var landed := false
	var speed := 1.0
	var blocking := false
	var grabbing := 0.0       ## seconds left holding the other's jersey
	var lean := 0.0
	var lean_target := 0.0
	var lean_hold := 0.0
	var base := Vector3.ZERO
	var facing := Vector3.FORWARD
	var damage_dealt := 0.0
	var ai_next := 0.6
	var prev_turbo := false
	var idle_playing := false

	func right() -> Vector3:
		return facing.cross(Vector3.UP).normalized()   # same as Skater.right_dir()


var director: MatchDirector
var stage := Stage.PROMPT
var a: Fighter
var b: Fighter
var center := Vector3.ZERO
var prompt_brain: HumanBrain   ## the human who decides (null = no prompt)
var winner: Skater
var loser: Skater
var _t := 0.0
var _time_left := TIME_LIMIT
var _rng := RandomNumberGenerator.new()
var _cam: Camera3D
var _cam_angle := 0.0
var _props: Array[Node3D] = []
var _hud: FightHud
var _ring: Array[Skater] = []
var _exhausted := 0.0


## `prompt` = the human brain that gets "drop the gloves?" (null: the fight is on).
func setup(d: MatchDirector, fa: Skater, fb: Skater, prompt: HumanBrain) -> void:
	director = d
	_rng.randomize()
	a = _fighter(fa)
	b = _fighter(fb)
	a.other = b
	b.other = a
	prompt_brain = prompt
	center = (fa.global_position + fb.global_position) * 0.5
	center.y = 0.0
	# Keep the fight off the boards.
	var c2 := RinkSpec.clamp_inside(center.x, center.z, 3.5)
	center = Vector3(c2.x, 0.0, c2.y)
	_hud = FightHud.new()
	add_child(_hud)
	_hud.setup(self)
	if prompt_brain:
		stage = Stage.PROMPT
		_hud.show_prompt(true)
	else:
		_begin_square_up()


func _fighter(s: Skater) -> Fighter:
	var f := Fighter.new()
	f.s = s
	f.max_health = PlayerStats.lerp_stat(int((s.stats.fighting + s.stats.durability) / 2.0), 85.0, 140.0)
	f.health = f.max_health
	f.max_balance = PlayerStats.lerp_stat(s.stats.strength, 75.0, 125.0)
	f.balance = f.max_balance
	f.max_stamina = PlayerStats.lerp_stat(s.stats.endurance, 60.0, 110.0)
	f.stamina = f.max_stamina
	f.human = _human_for(s)
	return f


func _human_for(s: Skater) -> HumanBrain:
	if s.brain is HumanBrain:
		return s.brain
	var c := director.control(s.team)
	return c.primary() if c else null


func is_human_fight() -> bool:
	return a.human != null or b.human != null


# --- Stages ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	match stage:
		Stage.PROMPT:
			_update_prompt(delta)
		Stage.SQUARE_UP:
			_hold_positions(delta)
			if _t > SQUARE_TIME:
				stage = Stage.FIGHT
				_t = 0.0
				_hud.show_fight(true)
		Stage.FIGHT:
			_update_fight(delta)
		Stage.OVER:
			_hold_positions(delta)
			if _t > OVER_TIME:
				_cleanup()
				finished.emit(winner, loser)
				queue_free()
	_update_camera(delta)
	_hud.refresh()


func _update_prompt(_delta: float) -> void:
	var i := SkaterIntent.new()
	prompt_brain.update(null, i, 0.0)
	_hud.prompt_left(1.0 - _t / PROMPT_TIME)
	if i.pass_down:
		_hud.show_prompt(false)
		_begin_square_up()
	elif i.check_down or _t > PROMPT_TIME:
		_hud.show_prompt(false)
		_cleanup()
		declined.emit()
		queue_free()


func _begin_square_up() -> void:
	stage = Stage.SQUARE_UP
	_t = 0.0
	# Line the fighters up across the rink at the fight spot.
	var axis := Vector3.RIGHT
	a.base = center - axis * GAP * 0.5
	b.base = center + axis * GAP * 0.5
	a.facing = axis
	b.facing = -axis
	for f: Fighter in [a, b]:
		var s: Skater = f.s
		if s.has_puck():
			s.puck.strip(s, Vector3.ZERO)
		s.frozen = true
		s.place(f.base, f.facing)
		s.visual.snap()
		s.visual.set_fight_mode(true)
		_drop_gear(s)
		_play_idle(f)
	# Everyone else gathers round.
	var others: Array[Skater] = []
	for t in 2:
		for s in director.lineup(t).on_ice:
			if s != a.s and s != b.s and not s.benched:
				others.append(s)
	# The ring leaves the camera's side open (the camera sits on +Z or -Z, see _update_camera).
	var cam_ang := atan2(_camera_side().z, _camera_side().x)
	for k in others.size():
		var s := others[k]
		var ang := cam_ang + deg_to_rad(55.0) + deg_to_rad(250.0) * (k + 0.5) / others.size()
		var p := center + Vector3(cos(ang), 0, sin(ang)) * RING_RADIUS
		var p2 := RinkSpec.clamp_inside(p.x, p.z, 1.0)
		s.frozen = true
		s.place(Vector3(p2.x, 0, p2.y), (center - Vector3(p2.x, 0, p2.y)).normalized())
		s.visual.snap()
		_ring.append(s)
	_make_camera()
	Sfx.announce("fighting", 3)
	Sfx.crowd_react("cheer", -2.0, 2)
	_hud.banner("GLOVES OFF!")


func _drop_gear(s: Skater) -> void:
	# The stick and gloves land on the ice at the fighter's feet.
	var r := s.global_position + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
	var stick := MeshInstance3D.new()
	stick.mesh = SkaterVisual.STICK_MESH
	stick.material_override = MeshUtil.material(Color(0.07, 0.07, 0.08), 0.5)
	add_child(stick)
	stick.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5), r + Vector3(0, 0.02, 0))
	_props.append(stick)
	for k in 2:
		var g := MeshInstance3D.new()
		g.mesh = SkaterVisual.GLOVE_MESH
		g.material_override = MeshUtil.material(s.visual.team_colors().gloves, 0.55)
		add_child(g)
		var gp := s.global_position + Vector3(_rng.randf_range(-0.7, 0.7), 0.06, _rng.randf_range(-0.7, 0.7))
		g.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), gp)
		_props.append(g)


# --- The fight -----------------------------------------------------------------------

func _update_fight(delta: float) -> void:
	_time_left -= delta
	for f: Fighter in [a, b]:
		_read_input(f, delta)
		_tick_fighter(f, delta)
	_hold_positions(delta)
	# Out of gas on both sides, or out of time: a decision.
	_exhausted = _exhausted + delta if a.stamina < 6.0 and b.stamina < 6.0 else 0.0
	if _time_left <= 0.0 or _exhausted > 2.5:
		_decision()


func _read_input(f: Fighter, delta: float) -> void:
	if f.human:
		f.intent.clear()
		f.human.update(f.s, f.intent, delta)
		var i := f.intent
		var turbo_down := i.turbo and not f.prev_turbo
		f.prev_turbo = i.turbo
		f.blocking = i.deke_held and f.act == ""
		var side := i.move.dot(f.right())
		f.lean_target = clampf(side * 1.4, -1.0, 1.0) if absf(side) > 0.3 else 0.0
		if f.act == "":
			if i.pass_down:
				_start(f, "jab")
			elif i.shoot_down:
				_start(f, "hay")
			elif i.check_down:
				_start(f, "grab")
			elif turbo_down and f.grabbing > 0.0:
				_start(f, "upper")
	else:
		_ai(f, delta)


## Computer fighter: reacts to visible haymakers, works the grab, mixes punches.
func _ai(f: Fighter, delta: float) -> void:
	var skill := PlayerStats.lerp_stat(f.s.stats.fighting, 0.25, 0.8)
	var o := f.other
	f.lean_hold -= delta
	if f.lean_hold <= 0.0:
		f.lean_target = 0.0
	# A haymaker coming: dodge or block, if quick enough.
	if o.act == "hay" and not o.landed and o.act_t < 0.3 and f.act == "" and f.lean_target == 0.0 and not f.blocking:
		if _rng.randf() < skill * delta * 9.0:
			if _rng.randf() < 0.6:
				f.lean_target = 1.0 if _rng.randf() < 0.5 else -1.0
				f.lean_hold = 0.6
			else:
				f.blocking = true
				f.ai_next = 0.5
	f.ai_next -= delta
	if f.ai_next > 0.0 or f.act != "":
		return
	f.blocking = false
	var aggr := PlayerStats.lerp_stat(f.s.stats.aggression, 0.0, 1.0)
	f.ai_next = _rng.randf_range(0.3, 0.85) * lerpf(1.25, 0.75, skill)
	if f.stamina < 8.0:
		f.blocking = true
		return
	if f.grabbing > 0.0:
		_start(f, "upper" if _rng.randf() < 0.45 else "jab")
		return
	var r := _rng.randf()
	if r < 0.42:
		_start(f, "jab")
	elif r < 0.62 + aggr * 0.12:
		_start(f, "hay")
	elif r < 0.85:
		_start(f, "grab")
	else:
		f.blocking = true
		f.ai_next = 0.6


func _start(f: Fighter, move: String) -> void:
	var m: Dictionary = MOVES[move]
	f.act = move
	f.act_t = 0.0
	f.landed = false
	f.blocking = false
	# Tired fighters throw slower.
	f.speed = 1.0 if f.stamina >= m.cost else 0.7
	f.stamina = maxf(0.0, f.stamina - m.cost)
	var clip_speed: float = m.impact / m.windup * f.speed
	f.s.visual.play_clip(m.clip, Vector3(0.0, 1.0, 1.0), (m.windup + m.recover) / f.speed, clip_speed, 0.06)
	f.idle_playing = false


func _tick_fighter(f: Fighter, delta: float) -> void:
	if f.act == "down":
		return
	f.stamina = minf(f.max_stamina, f.stamina + (2.2 if f.blocking else 3.5) * delta)
	f.grabbing = maxf(0.0, f.grabbing - delta)
	if f.other.grabbing > 0.0:
		f.balance -= 4.5 * delta
	else:
		f.balance = minf(f.max_balance, f.balance + 3.0 * delta)
	if f.blocking and f.act == "":
		f.stamina = maxf(0.0, f.stamina - 1.5 * delta)
		if not f.s.visual.anim.current_animation == BLOCK_CLIP:
			f.s.visual.play_clip(BLOCK_CLIP, Vector3(0.0, 1.0, 1.0), 0.5, 1.4, 0.08)
			f.idle_playing = false
	if f.act == "":
		if not f.blocking and not f.idle_playing:
			_play_idle(f)
		return
	f.act_t += delta
	if f.act == "hit":
		if f.act_t > 0.4:
			f.act = ""
		return
	var m: Dictionary = MOVES[f.act]
	if not f.landed and f.act_t >= m.windup / f.speed:
		f.landed = true
		_land(f, f.act)
	if f.act_t >= (m.windup + m.recover) / f.speed:
		f.act = ""


func _land(f: Fighter, move: String) -> void:
	var o := f.other
	var m: Dictionary = MOVES[move]
	if o.act == "down":
		return
	var at := (f.s.global_position + o.s.global_position) * 0.5 + Vector3.UP * 1.5
	# A haymaker into a lean whiffs and costs the thrower balance.
	if move == "hay" and absf(o.lean) > 0.55:
		f.balance -= 8.0
		_hud.flash("%s SLIPS IT!" % _name(o.s))
		return
	if move == "grab":
		if o.blocking and _rng.randf() < 0.5:
			return
		f.grabbing = GRAB_TIME
		o.grabbing = 0.0
		o.balance -= m.bal
		_hud.flash("%s GRABS THE JERSEY" % _name(f.s))
		return
	var power := PlayerStats.lerp_stat(f.s.stats.fighting, 0.8, 1.25) / PlayerStats.lerp_stat(o.s.stats.durability, 0.85, 1.15)
	if f.grabbing > 0.0:
		power *= 1.3
	if f.stamina < 10.0:
		power *= 0.7
	var dmg: float = m.dmg * power
	var bal: float = m.bal * power
	if move == "jab" and absf(o.lean) > 0.55:
		dmg *= 0.5
	if o.blocking:
		dmg *= 0.3
		bal *= 0.4
		o.stamina = maxf(0.0, o.stamina - 5.0)
		Sfx.play("pad", at, -6.0, 1.3)
	else:
		Sfx.play("punch", at, -2.0 if move == "jab" else 2.0, 1.1 if move == "jab" else 0.9)
		var grunt := "punch_female" if o.s.body_type == "female" else "punch_male"
		if move != "jab" or _rng.randf() < 0.4:
			Sfx.play(grunt, at, -3.0)
		# Big shots interrupt a windup; jabs just sting.
		if move != "jab" and o.act in MOVES:
			o.act = ""
		if o.act == "":
			o.act = "hit"
			o.act_t = 0.0
			o.s.visual.play_clip(HIT_CLIPS.get(move, "head_hit"), Vector3(0.0, 1.0, 1.0), 0.45, 1.3, 0.04)
			o.idle_playing = false
	o.health -= dmg
	o.balance -= bal
	f.damage_dealt += dmg
	if o.health <= 0.0 or o.balance <= 0.0:
		_knockdown(f, o)


func _knockdown(w: Fighter, l: Fighter) -> void:
	l.act = "down"
	l.health = maxf(l.health, 0.0)
	l.s.visual.play_clip("knocked_out", Vector3.ONE, OVER_TIME + 1.0, 1.0, 0.1)
	w.act = "down"   # done throwing
	w.s.visual.play_clip("taunt" if _rng.randf() < 0.5 else "fist_pump", Vector3(0.0, 1.0, 1.0), OVER_TIME, 1.0, 0.2)
	_over(w.s, l.s, "%s DROPS %s!" % [_name(w.s), _name(l.s)])


func _decision() -> void:
	var da := a.damage_dealt
	var db := b.damage_dealt
	if absf(da - db) <= maxf(da, db) * DRAW_MARGIN:
		for f: Fighter in [a, b]:
			f.act = "down"
			f.s.visual.play_clip("dizzy_idle", Vector3(0.0, 1.0, 1.0), OVER_TIME, 1.0, 0.2)
		_over(null, null, "THE LINESMEN STEP IN — A DRAW")
		return
	var w := a if da > db else b
	var l := w.other
	w.act = "down"
	l.act = "down"
	w.s.visual.play_clip("fist_pump", Vector3(0.0, 1.0, 1.0), OVER_TIME, 1.0, 0.2)
	l.s.visual.play_clip("dizzy_idle", Vector3(0.0, 1.0, 1.0), OVER_TIME, 1.0, 0.2)
	_over(w.s, l.s, "LINESMEN IN — %s TAKES IT ON POINTS" % _name(w.s))


func _over(w: Skater, l: Skater, text: String) -> void:
	winner = w
	loser = l
	stage = Stage.OVER
	_t = 0.0
	_hud.banner(text)
	if w == null:
		Sfx.crowd_react("cheer", -4.0, 2)
	elif w.team == MatchAudio.HOME:
		Sfx.crowd_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", -2.0, 3)
	else:
		Sfx.crowd_react("big_boo" if Sfx.has("big_boo") else "boo", -3.0, 3)


func _play_idle(f: Fighter) -> void:
	f.s.visual.play_clip(IDLE_CLIP, Vector3(0.0, 1.0, 1.0), -1.0, 1.0, 0.12)
	f.idle_playing = true


func _hold_positions(delta: float) -> void:
	if stage == Stage.PROMPT:
		return
	for f: Fighter in [a, b]:
		f.lean = move_toward(f.lean, f.lean_target, delta * 6.0)
		var p := f.base + f.right() * f.lean * LEAN_DIST
		f.s.global_position = p
		f.s.heading = f.facing
		f.s.velocity = Vector3.ZERO


func _name(s: Skater) -> String:
	return "#%d %s" % [s.number, s.last_name.to_upper() if s.last_name != "" else director.team_name(s.team)]


# --- Camera --------------------------------------------------------------------------

func _make_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 48.0
	add_child(_cam)
	_cam.make_current()


func _update_camera(delta: float) -> void:
	if _cam == null:
		return
	_cam_angle += delta * 0.12
	# Side-on to the fighters (who face along X), low, slowly drifting.
	var base := _camera_side()
	var side := (base + Vector3(sin(_cam_angle * 0.5) * 0.35, 0.0, 0.0)).normalized()
	_cam.look_at_from_position(center + side * 4.4 + Vector3.UP * 1.55, center + Vector3.UP * 1.15)


## Which side of the fight the camera watches from: toward center ice.
func _camera_side() -> Vector3:
	return Vector3.FORWARD if center.z > 0.0 else Vector3.BACK


# --- Cleanup -------------------------------------------------------------------------

func _cleanup() -> void:
	for f: Fighter in [a, b]:
		if is_instance_valid(f.s):
			f.s.visual.stop_clip(0.2)
			f.s.visual.set_fight_mode(false)
			f.s.frozen = false
	for s in _ring:
		if is_instance_valid(s):
			s.frozen = false
	for p in _props:
		p.queue_free()
	if _cam:
		director.cam.make_current()
