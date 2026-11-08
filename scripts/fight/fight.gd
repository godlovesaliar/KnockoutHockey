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
## (endurance). Empty the other's health or balance and they go down; when time runs out
## the one who did more damage wins (close = a draw).
##
## Moves (full-body clips, fists closed; at contact the punching hand is pulled onto the
## other's face, or their guard, so blows land):
##   jab (A)        lead hand, fast, light
##   haymaker (X)   big right with a visible windup; slip it (stick up/down) or block it
##   grab (B)       a hand on their jersey: pulls you together, drains their balance,
##                  your punches hit harder and the uppercut opens up. Held? B breaks free.
##   uppercut (RT)  only while you hold them; big balance damage
##   block (hold Y) much less damage, costs stamina
## Stick toward / away from the other steps in / backs off (out of range, punches miss and
## stamina comes back faster); up / down slips to the side.

signal finished(winner: Skater, loser: Skater)   ## winner null = draw (loser null too)
signal declined

enum Stage { PROMPT, SQUARE_UP, FIGHT, OVER }

const PROMPT_TIME := 3.0
const SQUARE_TIME := 1.4
const TIME_LIMIT := 25.0
const OVER_TIME := 3.2
const GAP := 0.95             ## meters between the fighters' centers when squared up
const GAP_MIN := 0.68         ## closest they get (held in a clinch)
const GAP_MAX := 1.9
const STEP_SPEED := 1.6       ## m/s stepping in or back
const LEAN_DIST := 0.26
const RING_RADIUS := 4.6
const GRAB_TIME := 3.5
const DRAW_MARGIN := 0.08     ## damage within this share of each other = a draw
const BUFFER := 0.3           ## a press this long before the fighter is free still fires
const STANCE_YAW := 0.42      ## rad the body turns to square the bladed clips up to the other

## clip, start (clip s), contact (clip s), end (clip s), clip speed, hand (0 left / 1 right),
## damage, balance damage, stamina cost, lunge (m), range (separation it reaches), stun (s
## the one hit can't act), aim ("head" / "body" / "chin").
const MOVES := {
	"jab": {"clip": "lead_jab", "from": 0.18, "contact": 0.5, "end": 0.95, "speed": 1.7, "hand": 0,
		"dmg": 6.5, "bal": 2.5, "cost": 3.0, "lunge": 0.12, "range": 1.25, "stun": 0.22, "aim": "head"},
	"hay": {"clip": "cross_punch", "from": 0.5, "contact": 1.1, "end": 1.6, "speed": 1.5, "hand": 1,
		"dmg": 18.0, "bal": 11.0, "cost": 9.0, "lunge": 0.2, "range": 1.15, "stun": 0.45, "aim": "head"},
	"upper": {"clip": "uppercut", "from": 0.22, "contact": 0.5, "end": 0.85, "speed": 1.3, "hand": 1,
		"dmg": 19.0, "bal": 17.0, "cost": 8.0, "lunge": 0.06, "range": 1.0, "stun": 0.5, "aim": "chin"},
	"short": {"clip": "punching", "from": 0.12, "contact": 0.4, "end": 0.75, "speed": 1.5, "hand": 1,
		"dmg": 8.0, "bal": 4.0, "cost": 3.0, "lunge": 0.04, "range": 1.0, "stun": 0.22, "aim": "body"},
	"grab": {"clip": "", "from": 0.0, "contact": 0.2, "end": 0.34, "speed": 1.0, "hand": 0,
		"dmg": 0.0, "bal": 4.0, "cost": 4.0, "lunge": 0.15, "range": 1.3, "stun": 0.0, "aim": "collar"},
}
const HIT_CLIPS := {"jab": "light_hit_to_head", "hay": "head_hit", "upper": "receive_uppercut_to_the_face", "short": "stomach_hit"}
const IDLE_CLIP := "bouncing_fight_idle"
const FULL := Vector3.ONE


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
	var act_t := 0.0          ## seconds into the act
	var stun := 0.0           ## "hit": seconds it lasts
	var landed := false
	var connects := ""        ## at contact: "hit" / "block" / "miss" (decided at contact)
	var rate := 1.0           ## act speed (tired fighters are slower)
	var blocking := false
	var grabbing := 0.0       ## seconds left holding the other's jersey
	var lean := 0.0
	var lean_target := 0.0
	var lean_hold := 0.0
	var x := 0.0              ## position along the fight axis (a < 0 < b)
	var vx := 0.0
	var step := 0.0           ## -1..1 toward (+) / away from the other, from the stick
	var side := -1.0          ## -1: a (left end of the axis), +1: b
	var damage_dealt := 0.0
	var ai_next := 0.6
	var ai_range := GAP
	var prev_turbo := false
	var buffered := ""
	var buffer_t := 0.0
	var pose := ""            ## the looping clip playing ("idle" / "block")
	var flash_t := 0.0        ## HUD: seconds the bars flash after a hit
	var reach := [0.0, 0.0]   ## per hand, the IK weight this tick
	var guard := 0.0          ## 0..1 fists up in front of the face (blocking)

	func toward() -> float:   ## +1 if the other is along +axis
		return -side


var director: MatchDirector
var stage := Stage.PROMPT
var a: Fighter
var b: Fighter
var center := Vector3.ZERO
var axis := Vector3.RIGHT
var prompt_brain: HumanBrain   ## the human who decides (null = no prompt)
var winner: Skater
var loser: Skater
var _t := 0.0
var _time_left := TIME_LIMIT
var _rng := RandomNumberGenerator.new()
var _cam: Camera3D
var _cam_side := Vector3.BACK
var _cam_fresh := true
var _shake := 0.0
var _hitstop_until := 0
var _props: Array[Node3D] = []
var _hud: FightHud
var _ring: Array[Skater] = []
var _exhausted := 0.0
var _axis_base := 0.0


## `prompt` = the human brain that gets "drop the gloves?" (null: the fight is on).
func setup(d: MatchDirector, fa: Skater, fb: Skater, prompt: HumanBrain) -> void:
	director = d
	_rng.randomize()
	a = _fighter(fa)
	b = _fighter(fb)
	a.other = b
	b.other = a
	a.side = -1.0
	b.side = 1.0
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


## The first human fighting (for the controls hint), or null.
func human_brain() -> HumanBrain:
	return a.human if a.human else b.human


func separation() -> float:
	return b.x - a.x


func time_left() -> float:
	return _time_left


# --- Stages ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0


func _physics_process(delta: float) -> void:
	_t += delta
	match stage:
		Stage.PROMPT:
			_update_prompt(delta)
		Stage.SQUARE_UP:
			_move(delta)
			if _t > SQUARE_TIME:
				stage = Stage.FIGHT
				_t = 0.0
				_hud.show_fight(true)
		Stage.FIGHT:
			_update_fight(delta)
		Stage.OVER:
			for f: Fighter in [a, b]:
				f.reach = [0.0, 0.0]
			_move(delta)
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
	# Square up across the rink at the fight spot; the camera watches from center ice.
	_cam_side = Vector3.FORWARD if center.z > 0.0 else Vector3.BACK
	_axis_base = 0.0
	axis = Vector3.RIGHT
	a.x = -GAP * 0.5
	b.x = GAP * 0.5
	for f: Fighter in [a, b]:
		var s: Skater = f.s
		if s.has_puck():
			s.puck.strip(s, Vector3.ZERO)
		s.frozen = true
		s.place(_spot(f), axis * f.toward())
		s.visual.snap()
		s.visual.set_fight_mode(true)
		s.visual.yaw_offset = STANCE_YAW
		_drop_gear(s)
		_set_pose(f, "idle")
	# Everyone else gathers round, leaving the camera's side open.
	var others: Array[Skater] = []
	for t in 2:
		for s in director.lineup(t).on_ice:
			if s != a.s and s != b.s and not s.benched:
				others.append(s)
	var cam_ang := atan2(_cam_side.z, _cam_side.x)
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
	for f: Fighter in [a, b]:
		_tick_fighter(f, delta)
	_move(delta)
	# Out of gas on both sides, or out of time: a decision.
	_exhausted = _exhausted + delta if a.stamina < 6.0 and b.stamina < 6.0 else 0.0
	if stage == Stage.FIGHT and (_time_left <= 0.0 or _exhausted > 2.5):
		_decision()


## Free to start something new (not mid-punch, not reeling).
func _free(f: Fighter) -> bool:
	return f.act == ""


func _read_input(f: Fighter, delta: float) -> void:
	f.buffer_t -= delta
	if f.human:
		f.intent.clear()
		f.human.update(f.s, f.intent, delta)
		var i := f.intent
		var turbo_down := i.turbo and not f.prev_turbo
		f.prev_turbo = i.turbo
		# The stick in screen terms: left / right steps toward or away from the other,
		# up / down slips to the side.
		var cam_right := _cam.global_basis.x if _cam else Vector3.RIGHT
		var toward_screen := signf((axis * f.toward()).dot(cam_right))
		f.step = clampf(i.move.x * toward_screen, -1.0, 1.0) if absf(i.move.x) > 0.25 else 0.0
		f.lean_target = clampf(i.move.z * 1.5, -1.0, 1.0) if absf(i.move.z) > 0.3 else 0.0
		f.blocking = i.deke_held and (f.act == "" or (f.act in MOVES and f.landed))
		var want := ""
		if i.pass_down:
			want = "short" if f.grabbing > 0.0 or f.other.grabbing > 0.0 else "jab"
		elif i.shoot_down:
			want = "hay"
		elif i.check_down:
			want = "break" if f.other.grabbing > 0.0 else "grab"
		elif turbo_down:
			want = "upper"
		if want != "":
			f.buffered = want
			f.buffer_t = BUFFER
		if f.buffer_t > 0.0 and f.buffered != "" and _free(f) and not f.blocking:
			var w := f.buffered
			f.buffered = ""
			_try(f, w)
	else:
		_ai(f, delta)


## Starts `want` if allowed now (the uppercut needs a grip; "break" shakes a grip off).
func _try(f: Fighter, want: String) -> void:
	match want:
		"upper":
			if f.grabbing > 0.0:
				_start(f, "upper")
			else:
				_hud.flash_for(f, "UPPERCUT: GRAB FIRST (B)")
		"break":
			_break_free(f)
		_:
			_start(f, want)


func _break_free(f: Fighter) -> void:
	var o := f.other
	if o.grabbing <= 0.0:
		return
	f.stamina = maxf(0.0, f.stamina - 4.0)
	var mine := PlayerStats.lerp_stat(f.s.stats.strength, 0.3, 0.75) * (0.6 if f.stamina < 10.0 else 1.0)
	if _rng.randf() < mine:
		o.grabbing = 0.0
		o.balance -= 4.0
		o.vx -= o.toward() * 0.9
		f.vx -= f.toward() * 0.5
		_hud.flash("%s BREAKS FREE" % _name(f.s))
		Sfx.play("pad", _mid() + Vector3.UP * 1.3, -8.0, 0.8)
	else:
		_hud.flash_for(f, "STILL HELD — KEEP TRYING (B)")


## Computer fighter: keeps its range, reacts to visible haymakers, works the grab, mixes
## punches, backs off to get its wind back.
func _ai(f: Fighter, delta: float) -> void:
	var skill := PlayerStats.lerp_stat(f.s.stats.fighting, 0.25, 0.85)
	var aggr := PlayerStats.lerp_stat(f.s.stats.aggression, 0.0, 1.0)
	var o := f.other
	f.lean_hold -= delta
	if f.lean_hold <= 0.0:
		f.lean_target = 0.0
	# Range: close in to fight, back off when winded.
	var tired := f.stamina < f.max_stamina * 0.22
	f.ai_range = 1.55 if tired and o.grabbing <= 0.0 and f.grabbing <= 0.0 else lerpf(1.0, 0.86, aggr)
	var sep := separation()
	f.step = clampf((sep - f.ai_range) * 3.0, -1.0, 1.0) if absf(sep - f.ai_range) > 0.06 else 0.0
	# A haymaker coming: slip it or get the guard up, if quick enough to read it.
	if o.act == "hay" and not o.landed and f.act == "" and f.lean_target == 0.0 and not f.blocking:
		if _rng.randf() < skill * delta * 7.0:
			if _rng.randf() < 0.55:
				f.lean_target = 1.0 if _rng.randf() < 0.5 else -1.0
				f.lean_hold = 0.55
			else:
				f.blocking = true
				f.ai_next = 0.45
	f.ai_next -= delta
	if f.ai_next > 0.0 or f.act != "":
		return
	f.blocking = false
	f.ai_next = _rng.randf_range(0.25, 0.7) * lerpf(1.3, 0.7, skill)
	if tired:
		if _rng.randf() < 0.5:
			f.blocking = true
			f.ai_next = 0.6
		return
	if o.grabbing > 0.0:
		_try(f, "break" if _rng.randf() < 0.45 else "short")
		return
	if f.grabbing > 0.0:
		_try(f, "upper" if _rng.randf() < 0.4 else "short")
		return
	if sep > 1.3:
		return   # still closing in
	var r := _rng.randf()
	if r < 0.4:
		_start(f, "jab")
	elif r < 0.6 + aggr * 0.12:
		_start(f, "hay")
	elif r < 0.85:
		_start(f, "grab")
	else:
		f.blocking = true
		f.ai_next = 0.5


func _start(f: Fighter, move: String) -> void:
	var m: Dictionary = MOVES[move]
	f.act = move
	f.act_t = 0.0
	f.landed = false
	f.connects = ""
	f.blocking = false
	# Tired fighters throw slower.
	f.rate = 1.0 if f.stamina >= m.cost else 0.7
	f.stamina = maxf(0.0, f.stamina - m.cost)
	f.vx += f.toward() * m.lunge * 3.0
	if m.clip != "":
		f.s.visual.play_clip(m.clip, FULL, _dur(m) / f.rate + 0.25, m.speed * f.rate, 0.07, m.from)
		f.pose = ""


## Seconds from the start of a move to its contact, and to its end.
func _windup(m: Dictionary) -> float:
	return (m.contact - m.from) / m.speed


func _dur(m: Dictionary) -> float:
	return (m.end - m.from) / m.speed


func _tick_fighter(f: Fighter, delta: float) -> void:
	f.reach = [0.0, 0.0]
	if f.act == "down":
		return
	var o := f.other
	var sep := separation()
	# Wind comes back, faster out of reach.
	var regen := 3.5 if sep < 1.3 else 7.0
	if f.blocking:
		regen = -2.0
	f.stamina = clampf(f.stamina + regen * delta, 0.0, f.max_stamina)
	# Held by the jersey: balance drains (more against a strong grabber).
	f.grabbing = maxf(0.0, f.grabbing - delta)
	if o.grabbing > 0.0:
		f.balance -= PlayerStats.lerp_stat(o.s.stats.strength, 3.5, 7.0) * delta
		f.lean_target = 0.0   # can't slip while held
	else:
		f.balance = minf(f.max_balance, f.balance + 2.0 * delta)
	if f.grabbing > 0.0:
		f.reach[0] = 1.0   # the lead hand stays on their jersey
	if f.balance <= 0.0:
		_knockdown(o, f)
		return
	f.flash_t = maxf(0.0, f.flash_t - delta)
	f.guard = move_toward(f.guard, 1.0 if f.blocking else 0.0, delta * 12.0)
	if f.guard > 0.0:
		f.reach[1] = maxf(f.reach[1], f.guard)
		if f.grabbing <= 0.0:
			f.reach[0] = maxf(f.reach[0], f.guard)
	if f.act == "":
		_set_pose(f, "idle")
		return
	f.act_t += delta
	if f.act == "hit":
		if f.act_t > f.stun:
			f.act = ""
		return
	var m: Dictionary = MOVES[f.act]
	var contact := _windup(m) / f.rate
	if not f.landed and f.connects == "" and f.act_t >= contact - 0.1:
		f.connects = _will_connect(f, f.act)
	# Steer the punching hand onto the target around contact.
	if f.connects in ["hit", "block"]:
		var w := 0.0
		var t := f.act_t - contact
		if t < 0.0:
			w = smoothstep(-0.12, 0.0, t)
		else:
			w = 1.0 - smoothstep(0.06, 0.2, t)
		if f.act == "grab":
			w = smoothstep(-0.2, 0.0, t)
		f.reach[m.hand] = maxf(f.reach[m.hand], w)
	if not f.landed and f.act_t >= contact:
		f.landed = true
		_land(f, f.act)
	if f.act != "" and f.act != "down" and f.act_t >= _dur(m) / f.rate:
		f.act = ""


## At contact: does the move land, hit the guard, or miss (out of range, slipped)?
func _will_connect(f: Fighter, move: String) -> String:
	var o := f.other
	var m: Dictionary = MOVES[move]
	if separation() > m.range:
		return "miss"
	if move == "hay" and absf(o.lean) > 0.55:
		return "miss"
	if move == "jab" and absf(o.lean) > 0.8:
		return "miss"
	if o.blocking and move != "grab":
		return "block"
	return "hit"


func _land(f: Fighter, move: String) -> void:
	var o := f.other
	var m: Dictionary = MOVES[move]
	if o.act == "down":
		return
	var at := _mid() + Vector3.UP * 1.5
	var how := f.connects if f.connects != "" else _will_connect(f, move)
	if how == "miss":
		if separation() > m.range:
			_hud.flash_for(f, "OUT OF RANGE — STEP IN")
		else:
			f.balance -= 6.0 if move == "hay" else 2.0
			_hud.flash("%s SLIPS IT!" % _name(o.s))
		Sfx.play("swish" if Sfx.has("swish") else "pad", at, -12.0, 1.4)
		return
	if move == "grab":
		if o.blocking and _rng.randf() < 0.5:
			_hud.flash_for(f, "GRAB SWATTED AWAY")
			return
		f.grabbing = GRAB_TIME
		o.grabbing = 0.0
		o.balance -= m.bal
		_hud.flash("%s GRABS THE JERSEY" % _name(f.s))
		Sfx.play("pad", at, -6.0, 0.7)
		return
	var power := PlayerStats.lerp_stat(f.s.stats.fighting, 0.8, 1.25) / PlayerStats.lerp_stat(o.s.stats.durability, 0.85, 1.15)
	if f.grabbing > 0.0:
		power *= 1.3
	if f.stamina < 10.0:
		power *= 0.7
	var dmg: float = m.dmg * power
	var bal: float = m.bal * power
	if move == "jab" and absf(o.lean) > 0.4:
		dmg *= 0.5
	var heavy: bool = move in ["hay", "upper"]
	if how == "block":
		dmg *= 0.25
		bal *= 0.35
		o.stamina = maxf(0.0, o.stamina - (7.0 if heavy else 3.0))
		o.vx -= o.toward() * (0.5 if heavy else 0.2)
		Sfx.play("pad", at, -5.0, 1.2)
		_hud.flash_for(o, "BLOCKED")
	else:
		Sfx.play("punch", at, 2.0 if heavy else -2.0, 0.9 if heavy else 1.1)
		var grunt := "punch_female" if o.s.body_type == "female" else "punch_male"
		if move != "jab" or _rng.randf() < 0.4:
			Sfx.play(grunt, at, -3.0)
		o.vx -= o.toward() * (1.1 if heavy else 0.45)
		_shake = maxf(_shake, 0.09 if heavy else 0.035)
		if heavy:
			_hitstop(70)
		# Every clean blow interrupts; the one hit reels for a moment.
		o.act = "hit"
		o.act_t = 0.0
		o.stun = m.stun
		o.landed = false
		o.blocking = false
		o.s.visual.play_clip(HIT_CLIPS.get(move, "head_hit"), FULL, m.stun + 0.3, 1.5, 0.04)
		o.pose = ""
		o.flash_t = 0.35
		if o.grabbing > 0.0 and heavy:
			o.grabbing = 0.0   # rocked: lets go
	o.health -= dmg
	o.balance -= bal
	f.damage_dealt += dmg
	if o.health <= 0.0 or o.balance <= 0.0:
		_knockdown(f, o)


func _knockdown(w: Fighter, l: Fighter) -> void:
	if stage != Stage.FIGHT:
		return
	l.act = "down"
	l.health = maxf(l.health, 0.0)
	l.balance = maxf(l.balance, 0.0)
	l.grabbing = 0.0
	l.s.visual.play_clip("knocked_out", FULL, OVER_TIME + 1.0, 1.0, 0.1)
	w.act = "down"   # done throwing
	w.grabbing = 0.0
	w.s.visual.play_clip("taunt" if _rng.randf() < 0.5 else "fist_pump", FULL, OVER_TIME, 1.0, 0.2)
	_hitstop(140)
	_shake = 0.14
	_over(w.s, l.s, "%s DROPS %s!" % [_name(w.s), _name(l.s)])


func _decision() -> void:
	var da := a.damage_dealt
	var db := b.damage_dealt
	for f: Fighter in [a, b]:
		f.grabbing = 0.0
	if absf(da - db) <= maxf(da, db) * DRAW_MARGIN:
		for f: Fighter in [a, b]:
			f.act = "down"
			f.s.visual.play_clip("dizzy_idle", FULL, OVER_TIME, 1.0, 0.2)
		_over(null, null, "THE LINESMEN STEP IN — A DRAW")
		return
	var w := a if da > db else b
	var l := w.other
	w.act = "down"
	l.act = "down"
	w.s.visual.play_clip("fist_pump", FULL, OVER_TIME, 1.0, 0.2)
	l.s.visual.play_clip("dizzy_idle", FULL, OVER_TIME, 1.0, 0.2)
	_over(w.s, l.s, "LINESMEN IN — %s TAKES IT ON POINTS" % _name(w.s))


func _over(w: Skater, l: Skater, text: String) -> void:
	winner = w
	loser = l
	if OS.has_environment("KH_FIGHT_LOG"):
		print("[fight] %.1f s  %s  | a hp %.0f/%.0f bal %.0f st %.0f dealt %.0f | b hp %.0f/%.0f bal %.0f st %.0f dealt %.0f" % [
			TIME_LIMIT - _time_left, text, a.health, a.max_health, a.balance, a.stamina, a.damage_dealt,
			b.health, b.max_health, b.balance, b.stamina, b.damage_dealt])
	stage = Stage.OVER
	_t = 0.0
	_hud.banner(text)
	if w == null:
		Sfx.crowd_react("cheer", -4.0, 2)
	elif w.team == MatchAudio.HOME:
		Sfx.crowd_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", -2.0, 3)
	else:
		Sfx.crowd_react("big_boo" if Sfx.has("big_boo") else "boo", -3.0, 3)


## Loops the idle bounce (the guard goes up on top of it, by reach).
func _set_pose(f: Fighter, pose: String) -> void:
	if f.pose == pose:
		return
	f.pose = pose
	f.s.visual.play_clip(IDLE_CLIP, FULL, -1.0, 1.15, 0.14)


func _hitstop(ms: int) -> void:
	Engine.time_scale = 0.12
	_hitstop_until = Time.get_ticks_msec() + ms


func _mid() -> Vector3:
	return (a.s.global_position + b.s.global_position) * 0.5


func _spot(f: Fighter) -> Vector3:
	var right := axis.cross(Vector3.UP).normalized()
	return center + axis * f.x + right * f.lean * LEAN_DIST * -f.side


## Gliding along the axis: stick / AI steps, lunges and knockback, the pull of a grab;
## the pair slowly circles. Then the hands that reach (punches landing, grips).
func _move(delta: float) -> void:
	var held := a.grabbing > 0.0 or b.grabbing > 0.0
	for f: Fighter in [a, b]:
		var want := f.step * STEP_SPEED * f.toward()
		if f.act in ["hit", "down"]:
			want = 0.0
		if held:
			want = 0.0
		f.vx = move_toward(f.vx, want, (7.0 if want != 0.0 else 3.2) * delta)
		f.x += f.vx * delta
		f.lean = move_toward(f.lean, f.lean_target, delta * 7.0)
	# A grip pulls them together; nobody passes through anybody.
	var sep := separation()
	if held and sep > GAP_MIN + 0.04:
		var pull := minf((sep - GAP_MIN) * 3.0 * delta, sep - GAP_MIN)
		a.x += pull * 0.5
		b.x -= pull * 0.5
	sep = separation()
	if sep < GAP_MIN:
		var push := (GAP_MIN - sep) * 0.5
		a.x -= push
		b.x += push
		a.vx = minf(a.vx, 0.0)
		b.vx = maxf(b.vx, 0.0)
	if sep > GAP_MAX:
		var pull2 := (sep - GAP_MAX) * 0.5
		a.x += pull2
		b.x -= pull2
	# Keep the pair near its spot (and both off the boards).
	var mid := (a.x + b.x) * 0.5
	if absf(mid) > 1.2:
		var back := (absf(mid) - 1.2) * signf(mid)
		a.x -= back
		b.x -= back
	# Circling a little, so it doesn't look like two posts.
	if stage != Stage.PROMPT:
		var ang := _axis_base + sin(_t * 0.35 + 0.4) * 0.3 if stage == Stage.FIGHT else _axis_base
		axis = Vector3(cos(ang), 0.0, sin(ang))
	for f: Fighter in [a, b]:
		var p := _spot(f)
		var c2 := RinkSpec.clamp_inside(p.x, p.z, 0.8)
		f.s.global_position = Vector3(c2.x, 0.0, c2.y)
		f.s.heading = axis * f.toward()
		f.s.velocity = Vector3.ZERO
		# Slipping tilts the whole body.
		f.s.visual.roll_offset = -f.lean * 0.3
	for f: Fighter in [a, b]:
		_aim_hands(f)


## The reach targets on the other fighter's body for this tick.
func _aim_hands(f: Fighter) -> void:
	var rig := f.s.visual.rig
	var o := f.other
	var dir := (f.s.global_position - o.s.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else axis
	for k in 2:
		rig.reach_w[k] = f.reach[k]
		if f.reach[k] <= 0.0:
			continue
		var aim := "collar" if (k == 0 and f.grabbing > 0.0) else ""
		if aim == "" and f.act in MOVES and f.connects in ["hit", "block"]:
			aim = MOVES[f.act].aim
		if aim == "" and f.guard > 0.0:
			aim = "guard"
		var target: Vector3
		match aim:
			"collar":
				target = o.s.visual.bone_world("Spine2").lerp(o.s.visual.bone_world("Neck"), 0.55) + dir * 0.12
			"body":
				target = o.s.visual.bone_world("Spine1") + dir * 0.14
			"guard":
				# Fists up in front of their own face, a little apart.
				var side := dir.cross(Vector3.UP).normalized() * (0.09 if k == 0 else -0.09)
				target = f.s.visual.bone_world("Head") - dir * 0.24 + side + Vector3.DOWN * 0.06
			"chin":
				target = o.s.visual.bone_world("Head") + dir * 0.07 + Vector3.DOWN * 0.08
			_:
				target = o.s.visual.bone_world("Head") + dir * 0.1 + Vector3.DOWN * 0.02
		if f.connects == "block" and not aim in ["collar", "guard"]:
			target += dir * 0.12   # stopped by the forearms
		rig.reach_world[k] = target


func _name(s: Skater) -> String:
	return "#%d %s" % [s.number, s.last_name.to_upper() if s.last_name != "" else director.team_name(s.team)]


# --- Camera --------------------------------------------------------------------------

func _make_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 46.0
	add_child(_cam)
	_cam.make_current()


func _update_camera(delta: float) -> void:
	if _cam == null:
		return
	# Side-on to the fighters, low, following the pair as it moves and circles.
	var perp := axis.cross(Vector3.UP).normalized()
	if perp.dot(_cam_side) < 0.0:
		perp = -perp
	var mid := _mid()
	mid.y = 0.0
	var dist := 3.6 + maxf(0.0, separation() - GAP) * 0.8
	var shake := Vector3.ZERO
	if _shake > 0.0:
		shake = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - delta * 0.6)
	var want := mid + perp * dist + Vector3.UP * 1.5
	var from := want if _cam_fresh else _cam.global_position.lerp(want, 1.0 - exp(-4.0 * delta))
	_cam_fresh = false
	_cam.look_at_from_position(from + shake, mid + Vector3.UP * 1.25 + shake * 0.5)


# --- Cleanup -------------------------------------------------------------------------

func _cleanup() -> void:
	if _hitstop_until > 0:
		_hitstop_until = 0
		Engine.time_scale = 1.0
	for f: Fighter in [a, b]:
		if is_instance_valid(f.s):
			f.s.visual.stop_clip(0.2)
			f.s.visual.set_fight_mode(false)
			f.s.visual.roll_offset = 0.0
			f.s.frozen = false
	for s in _ring:
		if is_instance_valid(s):
			s.frozen = false
	for p in _props:
		p.queue_free()
	if _cam:
		director.cam.make_current()


func _exit_tree() -> void:
	if _hitstop_until > 0:
		Engine.time_scale = 1.0
