class_name Fight
extends Node
## The fight mini-game (DESIGN §5.2). The director creates one when a team drops the
## gloves; it runs while the match is in Phase.FIGHT and reports the result.
##
## Stages: PROMPT (a human on the team that took the hit decides: A yes / B no) ->
## SQUARE_UP (sticks and gloves drop, helmets come off, the others form a ring, the
## camera cuts in) ->
## FIGHT -> OVER (knockdown or decision, then the director sends both to the box).
##
## Each fighter has health (fighting + durability), balance (strength) and stamina
## (endurance). Empty the other's health or balance and they go down; when time runs out
## the one who did more damage wins (close = a draw).
##
## Moves (full-body clips, fists closed; at contact the punching hand is pulled onto the
## other's face / body, or their guard, so blows land). PlayStation buttons:
##   Cross     jab (lead hand, fast, light)
##   Square    cross (rear hand, straight)
##   Triangle  hook (lead hand, big, a visible windup: slip it or block it)
##   hold L1   the same three to the body (body jab / cross / hook): less damage, more
##             balance, and they drain the other's stamina
##   Circle    grab: a hand on their jersey pulls you together, drains their balance and
##             your punches hit harder. While holding, only the free right hand punches:
##             Cross = cross, Square = right hook, Triangle = uppercut.
##             Held? Mash Circle to break free. Holding and they're getting loose? Mash
##             Circle to hang on. Every press costs stamina, on either side.
##   hold R1   block high; R1 + L1 blocks low. Blocks only the punches aimed at that level
##             (much less damage, costs stamina); the wrong guard lets it through.
## Stick toward / away from the other steps in / backs off (out of range, punches miss and
## stamina comes back faster); up / down slips to the side.
##
## Styles (PlayerStats.fighting_style()): each throws its own jab, cross and hook from its
## own idle; the body versions are the same clips bent over at the waist. The uppercut, the
## clinch hook, guards and reactions are shared.
##   BOXER    quick, tight, cheap punches that hit a little lighter
##   BRAWLER  looping haymakers: slower, heavier, costlier and easier to slip
##   GRINDER  short and compact: less reach, works the balance and the body

signal finished(winner: Skater, loser: Skater)   ## winner null = draw (loser null too)
signal declined
signal knockout(winner: Skater, loser: Skater)   ## the moment one goes down (for the replay)

enum Stage { PROMPT, SQUARE_UP, FIGHT, OVER }

const PROMPT_TIME := 3.0
const SQUARE_TIME := 1.6
const HELMET_AT := [0.3, 0.4]   ## square-up s each fighter starts taking the helmet off (after the stick drops)
const GEAR_FALL := 0.35          ## s for the stick and gloves to hit the ice
const TIME_LIMIT := 25.0
const OVER_TIME := 3.2
const GAP := 0.95             ## meters between the fighters' centers at fighting range
const START_GAP := 1.6        ## ...when they square up: arm's length apart, they step in to engage
const GAP_MIN := 0.68         ## closest they get (held in a clinch)
const GAP_MAX := 1.9
const STEP_SPEED := 1.6       ## m/s stepping in or back
const LEAN_DIST := 0.26
const RING_RADIUS := 4.6
const GRAB_TIME := 6.0         ## longest a grip lasts (mashing breaks it sooner)
const MASH_COST := 1.2         ## stamina per Circle press while tied up, either side
const ESCAPE_PER := 0.085      ## escape progress per press (× strength)
const HOLD_PER := 0.06         ## escape progress a holder's press takes back (× strength)
const DRAW_MARGIN := 0.08     ## damage within this share of each other = a draw
const BUFFER := 0.3           ## a press this long before the fighter is free still fires
const STANCE_YAW := 0.42      ## rad the body turns to square the bladed clips up to the other

## clip, start (clip s), contact (clip s), end (clip s), clip speed, hand (0 left / 1 right),
## damage, balance damage, stamina cost, lunge (m), range (separation it reaches), stun (s
## the one hit can't act), aim ("head" / "body" / "chin" / "collar"), slip (the other's
## lean that dodges it; 0 = can't be slipped). Optional: drain (the other's stamina on a
## clean hit), heavy (hit-stop, shake, rocks a holder loose), bow (rad the thrower bends
## forward over the clip, so a head clip reads as a body shot).
const MOVES := {
	"jab": {"clip": "lead_jab", "from": 0.18, "contact": 0.5, "end": 0.95, "speed": 1.7, "hand": 0,
		"dmg": 6.5, "bal": 2.5, "cost": 3.0, "lunge": 0.12, "range": 1.25, "stun": 0.22, "aim": "head", "slip": 0.8},
	"cross": {"clip": "cross_punch", "from": 0.5, "contact": 1.1, "end": 1.6, "speed": 1.8, "hand": 1,
		"dmg": 11.0, "bal": 6.0, "cost": 5.0, "lunge": 0.16, "range": 1.2, "stun": 0.32, "aim": "head", "slip": 0.7},
	"hook": {"clip": "hook", "from": 0.15, "contact": 0.48, "end": 0.95, "speed": 1.1, "hand": 0,
		"dmg": 17.0, "bal": 10.0, "cost": 9.0, "lunge": 0.1, "range": 1.1, "stun": 0.45, "aim": "head", "slip": 0.55, "heavy": true},
	"body_jab": {"clip": "lead_jab", "from": 0.18, "contact": 0.5, "end": 0.95, "speed": 1.6, "hand": 0,
		"dmg": 4.0, "bal": 4.0, "drain": 5.0, "cost": 3.0, "lunge": 0.12, "range": 1.2, "stun": 0.2, "aim": "body", "slip": 0.8, "bow": 0.5},
	"body_cross": {"clip": "boxing_1", "from": 0.25, "contact": 0.72, "end": 1.15, "speed": 1.4, "hand": 1,
		"dmg": 7.0, "bal": 7.0, "drain": 8.0, "cost": 5.0, "lunge": 0.14, "range": 1.15, "stun": 0.3, "aim": "body", "slip": 0.7, "bow": 0.15},
	"body_hook": {"clip": "boxing", "from": 0.12, "contact": 0.48, "end": 1.0, "speed": 1.15, "hand": 0,
		"dmg": 10.0, "bal": 12.0, "drain": 12.0, "cost": 8.0, "lunge": 0.08, "range": 1.05, "stun": 0.45, "aim": "body", "slip": 0.55, "bow": 0.12, "heavy": true},
	"g_hook": {"clip": "punching", "from": 0.12, "contact": 0.45, "end": 0.78, "speed": 1.5, "hand": 1,
		"dmg": 13.0, "bal": 8.0, "cost": 6.0, "lunge": 0.04, "range": 1.0, "stun": 0.4, "aim": "head", "slip": 0.0, "heavy": true},
	"upper": {"clip": "uppercut", "from": 0.22, "contact": 0.5, "end": 0.85, "speed": 1.3, "hand": 1,
		"dmg": 19.0, "bal": 17.0, "cost": 8.0, "lunge": 0.06, "range": 1.0, "stun": 0.5, "aim": "chin", "slip": 0.0, "heavy": true},
	"grab": {"clip": "", "from": 0.0, "contact": 0.2, "end": 0.34, "speed": 1.0, "hand": 0,
		"dmg": 0.0, "bal": 4.0, "cost": 4.0, "lunge": 0.15, "range": 1.3, "stun": 0.0, "aim": "collar", "slip": 0.0},
}
## Only while holding the jersey (the free right hand).
const GRAB_MOVES := ["g_hook", "upper"]
const HIT_CLIPS := {"jab": "light_hit_to_head", "cross": "head_hit", "hook": "big_side_hit", "g_hook": "big_side_hit",
	"upper": "receive_uppercut_to_the_face", "body_jab": "stomach_hit", "body_cross": "stomach_hit", "body_hook": "big_stomach_hit"}
enum Style { BOXER, BRAWLER, GRINDER }
const STYLE_NAMES := ["BOXER", "BRAWLER", "GRINDER"]
## Per style: the idle loop and its speed, and whether it is a still stance (breathing laid
## over it, like the guards).
const STYLE_IDLE := [["idle1", 1.0, false], ["idle2", 1.0, false], ["idle3", 1.0, true]]
## Per style, the clip behind each punch (and its body version): clip, from, contact, end
## (clip s), speed, hand, bow for the body version (rad; head-height clips bend more), and
## optionally blend (s into the clip; big windups start mid-swing). Speeds keep contact near
## the base timings so the styles differ by feel, not by a whole beat.
const STYLE_CLIPS := [
	{   # BOXER
		"jab": {"clip": "jab1", "from": 0.3, "contact": 0.56, "end": 0.9, "speed": 1.55, "hand": 0, "bow": 0.5},
		"cross": {"clip": "cross1", "from": 0.12, "contact": 0.4, "end": 0.85, "speed": 1.0, "hand": 1, "bow": 0.3},
		"hook": {"clip": "hook1", "from": 0.2, "contact": 0.64, "end": 1.25, "speed": 1.55, "hand": 0, "bow": 0.45},
	},
	{   # BRAWLER
		"jab": {"clip": "jab2", "from": 0.05, "contact": 0.4, "end": 0.8, "speed": 1.6, "hand": 0, "bow": 0.55},
		"cross": {"clip": "cross2", "from": 0.5, "contact": 1.1, "end": 1.6, "speed": 1.6, "hand": 1, "bow": 0.4},
		"hook": {"clip": "hook2", "from": 0.45, "contact": 1.08, "end": 1.6, "speed": 1.4, "hand": 1, "bow": 0.3, "blend": 0.15},
	},
	{   # GRINDER
		"jab": {"clip": "jab3", "from": 0.3, "contact": 0.57, "end": 1.0, "speed": 1.5, "hand": 0, "bow": 0.25},
		"cross": {"clip": "cross3", "from": 0.1, "contact": 0.37, "end": 0.75, "speed": 1.0, "hand": 1, "bow": 0.25},
		"hook": {"clip": "hook3", "from": 0.15, "contact": 0.32, "end": 0.75, "speed": 0.85, "hand": 1, "bow": 0.5, "blend": 0.1},
	},
]
## Per style, on the punches it has its own clips for: MOVES numbers multiplied ("range" is
## added). slip < 1 means less lean dodges it.
const STYLE_MODS := [
	{"dmg": 0.92, "cost": 0.8, "stun": 0.9},
	{"dmg": 1.15, "bal": 1.15, "cost": 1.15, "slip": 0.85},
	{"dmg": 0.97, "bal": 1.2, "drain": 1.3, "range": -0.05},
]
## Guards: one frame of each clip held (clip s), breathing over it.
const GUARD_POSES := {"block_high": ["center_block", 0.8], "block_low": ["body_block", 1.9]}
## Knockout finishes: clip -> where to start it (clip s: where the body starts to go, so
## the fall follows the blow), its speed, and the clip s it lands on the ice.
##   knocked_out  twists and drops sideways        dying   staggers forward, then pitches over
##   dying2       a quick forward collapse         stunned straight back, at once
const FINISHES := {
	"knocked_out": {"from": 0.9, "speed": 1.1, "down": 3.0},
	"dying": {"from": 0.6, "speed": 1.15, "down": 4.3},
	"dying2": {"from": 1.1, "speed": 1.0, "down": 2.1},
	"stunned": {"from": 0.0, "speed": 1.0, "down": 1.4},
}
## Which finishes a blow can end in, weighted: big shots to the head snap them back or
## spin them down, body shots fold them up, a grip that drained their balance drags them.
const FINISH_BY := {
	"head_big": [["stunned", 0.35], ["knocked_out", 0.35], ["dying2", 0.3]],
	"head": [["knocked_out", 0.4], ["dying2", 0.4], ["stunned", 0.2]],
	"body": [["dying", 0.6], ["dying2", 0.4]],
	"": [["dying", 0.5], ["knocked_out", 0.5]],
}
const FULL := Vector3.ONE


class Fighter:
	var s: Skater
	var other: Fighter
	var human: HumanBrain
	var style := Style.BOXER
	var moves := MOVES         ## MOVES with this fighter's style applied (moves_for)
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
	var block_low := false    ## the guard is down at the body (L1 with R1)
	var grabbing := 0.0       ## seconds left holding the other's jersey
	var escape := 0.0         ## held: 0..1 progress breaking the other's grip (mashing)
	var mash_t := 0.0         ## AI: seconds to its next press
	var jolt := 0.0           ## 0..1 a struggle press just jerked the body (decays)
	var bow := 0.0            ## current forward bend (MOVES bow)
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
	var buffered := ""
	var buffer_t := 0.0
	var pose := ""            ## the looping clip playing ("idle" / "block_high" / "block_low")
	var flash_t := 0.0        ## HUD: seconds the bars flash after a hit
	var reach := [0.0, 0.0]   ## per hand, the IK weight this tick

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
var _over_time := OVER_TIME   ## the knockout's fall can hold the finish longer
## After a knockout: seconds from the blow until the loser is down on the ice (the replay
## runs that long past it).
var ko_fall := 0.0
var _axis_base := 0.0
var _log := {}   ## KH_FIGHT_LOG: "<move> <hit|block|miss>" / "escape" -> count


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
	f.style = s.stats.fighting_style()
	# `-- fightstyle=<a>[,<b>]` forces the styles (0 boxer, 1 brawler, 2 grinder) for testing.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("fightstyle="):
			var st := arg.substr(11).split(",")
			f.style = clampi(int(st[0 if a == null or st.size() < 2 else 1]), 0, 2)
	f.moves = moves_for(f.style)
	return f


## MOVES as `style` throws them: its own clips for the jab / cross / hook and their body
## versions (STYLE_CLIPS), with its numbers (STYLE_MODS). The rest are shared.
static func moves_for(style: int) -> Dictionary:
	var out := {}
	for k: String in MOVES:
		var m: Dictionary = MOVES[k].duplicate()
		var c: Dictionary = STYLE_CLIPS[style].get(k.trim_prefix("body_"), {})
		if not c.is_empty():
			for key in ["clip", "from", "contact", "end", "speed", "hand"]:
				m[key] = c[key]
			m.blend = c.get("blend", 0.07)
			if k.begins_with("body_"):
				m.bow = c.bow
			for key: String in STYLE_MODS[style]:
				if key == "range":
					m.range += STYLE_MODS[style].range
				elif m.has(key):
					m[key] *= STYLE_MODS[style][key]
		out[k] = m
	return out


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
			for k in 2:
				var f: Fighter = [a, b][k]
				if _t - delta < HELMET_AT[k] and _t >= HELMET_AT[k]:
					f.s.visual.take_off_helmet()
				var idle_at: float = HELMET_AT[k] + SkaterVisual.HELMET_END
				if _t - delta < idle_at and _t >= idle_at:
					f.pose = ""
					_set_pose(f, "idle")
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
			if _t > _over_time:
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
	a.x = -START_GAP * 0.5
	b.x = START_GAP * 0.5
	for f: Fighter in [a, b]:
		var s: Skater = f.s
		if s.has_puck():
			s.puck.strip(s, Vector3.ZERO)
		s.frozen = true
		s.place(_spot(f), axis * f.toward())
		s.visual.snap()
		var held := s.visual.held_gear()
		s.visual.set_fight_mode(true)
		s.visual.yaw_offset = STANCE_YAW
		_drop_gear(s, held)
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


## The stick and gloves fall from the fighter's hands to the ice at their feet. `held`:
## SkaterVisual.held_gear() from just before they were hidden.
func _drop_gear(s: Skater, held: Dictionary) -> void:
	var r := s.global_position + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
	var stick := MeshInstance3D.new()
	stick.mesh = SkaterVisual.STICK_MESH
	stick.material_override = MeshUtil.material(Color(0.07, 0.07, 0.08), 0.5)
	add_child(stick)
	_fall(stick, held.stick, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5), r + Vector3(0, 0.02, 0)))
	for k in 2:
		var g := MeshInstance3D.new()
		g.mesh = SkaterVisual.GLOVE_MESH
		g.material_override = SkaterVisual.glove_material(s.visual.team_colors().gloves, s.visual.team_colors().trim)
		add_child(g)
		var gp := s.global_position + Vector3(_rng.randf_range(-0.7, 0.7), 0.06, _rng.randf_range(-0.7, 0.7))
		_fall(g, held.gloves[k], Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), gp))


## A dropped prop: from `from` (in the hands) down to `to` on the ice, speeding up.
func _fall(p: Node3D, from: Transform3D, to: Transform3D) -> void:
	_props.append(p)
	p.global_transform = from
	var tw := p.create_tween()
	tw.tween_property(p, "global_transform", to, GEAR_FALL * _rng.randf_range(0.85, 1.15)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
		# The stick in screen terms: left / right steps toward or away from the other,
		# up / down slips to the side.
		var cam_right := _cam.global_basis.x if _cam else Vector3.RIGHT
		var toward_screen := signf((axis * f.toward()).dot(cam_right))
		var stick := InputRouter.to_screen(i.move)   # undo the play camera's turn
		f.step = clampf(stick.x * toward_screen, -1.0, 1.0) if absf(stick.x) > 0.25 else 0.0
		f.lean_target = clampf(stick.z * 1.5, -1.0, 1.0) if absf(stick.z) > 0.3 else 0.0
		f.blocking = i.block_held and (f.act == "" or (f.act in MOVES and f.landed))
		f.block_low = i.protect
		var holding := f.grabbing > 0.0
		var want := ""
		if i.check_down:
			# Tied up, Circle is the struggle (never buffered: every press counts now).
			if f.other.grabbing > 0.0:
				_mash(f, true)
			elif holding:
				_mash(f, false)
			else:
				want = "grab"
		if i.pass_down:
			want = "cross" if holding else ("body_jab" if i.protect else "jab")
		elif i.shoot_down:
			want = "g_hook" if holding else ("body_cross" if i.protect else "cross")
		elif i.deke_down:
			want = "upper" if holding else ("body_hook" if i.protect else "hook")
		if want != "":
			f.buffered = want
			f.buffer_t = BUFFER
		if f.buffer_t > 0.0 and f.buffered != "" and _free(f) and not f.blocking:
			var w := f.buffered
			f.buffered = ""
			_try(f, w)
	else:
		_ai(f, delta)


## Starts `want` if it still fits (the grip may have gone while it was buffered).
func _try(f: Fighter, want: String) -> void:
	if want in GRAB_MOVES and f.grabbing <= 0.0:
		return
	if want == "grab" and (f.grabbing > 0.0 or f.other.grabbing > 0.0):
		return
	_start(f, want)


## One Circle press while tied up. `escaping`: f is held and pulls toward breaking free;
## otherwise f holds and takes some of the other's progress back. Costs stamina either way.
func _mash(f: Fighter, escaping: bool) -> void:
	var o := f.other
	f.stamina = maxf(0.0, f.stamina - MASH_COST)
	var power := PlayerStats.lerp_stat(f.s.stats.strength, 0.7, 1.3) * (0.5 if f.stamina < 10.0 else 1.0)
	f.jolt = 1.0
	o.jolt = maxf(o.jolt, 0.5)
	if not escaping:
		o.escape = maxf(0.0, o.escape - HOLD_PER * power)
		return
	f.escape += ESCAPE_PER * power
	f.vx -= f.toward() * 0.25
	if f.escape < 1.0:
		return
	f.escape = 0.0
	_log["escape"] = int(_log.get("escape", 0)) + 1
	o.grabbing = 0.0
	o.balance -= 4.0
	o.vx -= o.toward() * 0.9
	f.vx -= f.toward() * 0.5
	_hud.flash("%s BREAKS FREE" % _name(f.s))
	Sfx.play("pad", _mid() + Vector3.UP * 1.3, -8.0, 0.8)


## Computer fighter: keeps its range, reads visible punches (slips the big ones, guards the
## right level by skill), mashes when tied up, mixes head and body, backs off to get its
## wind back.
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
	# Tied up: mash Circle, faster with skill (the holder only once they're getting loose).
	f.mash_t -= delta
	if f.mash_t <= 0.0 and f.act != "down":   # like a human, presses even while reeling
		var rate := lerpf(3.5, 7.5, skill) * (0.6 if tired else 1.0)
		if o.grabbing > 0.0:
			_mash(f, true)
			f.mash_t = _rng.randf_range(0.8, 1.2) / rate
		elif f.grabbing > 0.0 and o.escape > 0.3:
			_mash(f, false)
			f.mash_t = _rng.randf_range(0.8, 1.2) / rate
	# A punch coming: slip the hooks or get the right guard up, if quick enough to read it.
	var incoming := o.act in MOVES and o.act != "grab" and not o.landed
	if incoming and f.act == "" and f.lean_target == 0.0 and not f.blocking and _rng.randf() < skill * delta * 7.0:
		var m: Dictionary = o.moves[o.act]
		if o.act in ["hook", "body_hook"] and o.grabbing <= 0.0 and _rng.randf() < 0.45:
			f.lean_target = 1.0 if _rng.randf() < 0.5 else -1.0
			f.lean_hold = 0.55
		else:
			var low: bool = m.aim == "body"
			f.blocking = true
			f.block_low = low if _rng.randf() < lerpf(0.55, 0.95, skill) else not low
			f.ai_next = 0.45
	f.ai_next -= delta
	if f.ai_next > 0.0 or f.act != "":
		return
	f.blocking = false
	f.ai_next = _rng.randf_range(0.25, 0.7) * lerpf(1.3, 0.7, skill)
	if tired:
		if _rng.randf() < 0.5:
			f.blocking = true
			f.block_low = _rng.randf() < 0.35
			f.ai_next = 0.6
		return
	if o.grabbing > 0.0:
		_try(f, "body_jab" if _rng.randf() < 0.5 else "jab")
		return
	if f.grabbing > 0.0:
		var g := _rng.randf()
		_try(f, "upper" if g < 0.35 else ("g_hook" if g < 0.65 else "cross"))
		return
	if sep > 1.3:
		return   # still closing in
	var r := _rng.randf()
	var picks := [["jab", 0.26], ["cross", 0.16], ["hook", 0.1 + aggr * 0.08], ["body_jab", 0.09],
			["body_cross", 0.08], ["body_hook", 0.06 + aggr * 0.04], ["grab", 0.12]]
	for pk: Array in picks:
		r -= pk[1]
		if r < 0.0:
			_try(f, pk[0])
			return
	f.blocking = true
	f.block_low = _rng.randf() < 0.4
	f.ai_next = 0.5


func _start(f: Fighter, move: String) -> void:
	var m: Dictionary = f.moves[move]
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
		f.s.visual.play_clip(m.clip, FULL, _dur(m) / f.rate + 0.25, m.speed * f.rate, m.get("blend", 0.07), m.from)
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
	if o.grabbing <= 0.0:
		f.escape = 0.0
	f.jolt = move_toward(f.jolt, 0.0, delta * 5.0)
	var bow_to: float = f.moves[f.act].get("bow", 0.0) if f.act in MOVES else 0.0
	f.bow = move_toward(f.bow, bow_to, delta * 3.0)
	f.s.visual.rig.bow = f.bow
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
	var still: bool = f.pose in GUARD_POSES or (f.pose == "idle" and STYLE_IDLE[f.style][2])
	f.s.visual.hold_breath = 1.0 if still else 0.0
	if f.act == "":
		_set_pose(f, ("block_low" if f.block_low else "block_high") if f.blocking else "idle")
		return
	f.act_t += delta
	if f.act == "hit":
		if f.act_t > f.stun:
			f.act = ""
		return
	var m: Dictionary = f.moves[f.act]
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
	var m: Dictionary = f.moves[move]
	if separation() > m.range:
		return "miss"
	if m.slip > 0.0 and absf(o.lean) > m.slip:
		return "miss"
	if o.blocking and move != "grab" and o.block_low == (m.aim == "body"):
		return "block"
	return "hit"


func _land(f: Fighter, move: String) -> void:
	var o := f.other
	var m: Dictionary = f.moves[move]
	if o.act == "down":
		return
	var at := _mid() + Vector3.UP * 1.5
	var how := f.connects if f.connects != "" else _will_connect(f, move)
	var key := "%s %s" % [move, how]
	_log[key] = int(_log.get(key, 0)) + 1
	if how == "miss":
		if separation() > m.range:
			_hud.flash_for(f, "OUT OF RANGE — STEP IN")
		else:
			f.balance -= 6.0 if m.get("heavy", false) else 2.0
			_hud.flash("%s SLIPS IT!" % _name(o.s))
		Sfx.play("swish" if Sfx.has("swish") else "pad", at, -12.0, 1.4)
		return
	if move == "grab":
		if o.blocking and _rng.randf() < 0.5:
			_hud.flash_for(f, "GRAB SWATTED AWAY")
			return
		f.grabbing = GRAB_TIME
		o.grabbing = 0.0
		o.escape = 0.0
		f.escape = 0.0
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
	if m.slip > 0.0 and absf(o.lean) > m.slip * 0.5:
		dmg *= 0.5   # leaning away: it only glances
	var heavy: bool = m.get("heavy", false)
	var drain: float = m.get("drain", 0.0) * power
	if how == "block":
		dmg *= 0.25
		bal *= 0.35
		drain *= 0.25
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
		if o.blocking:
			_hud.flash_for(o, "WRONG GUARD — BLOCK LOW (L1)" if m.aim == "body" else "WRONG GUARD — BLOCK HIGH")
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
	o.stamina = maxf(0.0, o.stamina - drain)
	f.damage_dealt += dmg
	if o.health <= 0.0 or o.balance <= 0.0:
		_knockdown(f, o, move)


## `move`: the blow that did it ("" = their balance gave out, e.g. drained by a grip).
func _knockdown(w: Fighter, l: Fighter, move := "") -> void:
	if stage != Stage.FIGHT:
		return
	l.act = "down"
	l.health = maxf(l.health, 0.0)
	l.balance = maxf(l.balance, 0.0)
	l.grabbing = 0.0
	var clip := _pick_finish(move)
	var fin: Dictionary = FINISHES[clip]
	ko_fall = (fin.down - fin.from) / fin.speed
	_over_time = maxf(OVER_TIME, ko_fall + 1.3)
	l.s.visual.play_clip(clip, FULL, _over_time + 1.0, fin.speed, 0.05, fin.from)
	w.act = "down"   # done throwing
	w.grabbing = 0.0
	w.s.visual.play_clip("taunt" if _rng.randf() < 0.5 else "fist_pump", FULL, _over_time, 1.0, 0.2)
	_hitstop(140)
	_shake = 0.14
	_over(w.s, l.s, "%s DROPS %s!" % [_name(w.s), _name(l.s)])
	knockout.emit(w.s, l.s)


## A knockout finish for the blow that ended it (FINISH_BY). `-- kofinish=<clip>` forces one.
func _pick_finish(move: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("kofinish=") and FINISHES.has(arg.substr(9)):
			return arg.substr(9)
	var kind := ""
	if move in MOVES:
		var m: Dictionary = MOVES[move]
		if m.aim == "body":
			kind = "body"
		else:
			kind = "head_big" if m.get("heavy", false) else "head"
	var pool: Array = FINISH_BY[kind]
	var r := _rng.randf()
	for p: Array in pool:
		r -= p[1]
		if r < 0.0:
			return p[0]
	return pool.back()[0]


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
		var keys := _log.keys()
		keys.sort()
		print("[fight] ", ", ".join(keys.map(func(k: String) -> String: return "%s %d" % [k, _log[k]])))
	stage = Stage.OVER
	_t = 0.0
	_hud.banner(text)
	if w == null:
		Sfx.crowd_react("cheer", -4.0, 2)
	elif w.team == MatchAudio.HOME:
		Sfx.crowd_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", -2.0, 3)
	else:
		Sfx.crowd_react("big_boo" if Sfx.has("big_boo") else "boo", -3.0, 3)


## The looping pose between moves: the style's idle, or a guard (one frame held, breathing).
func _set_pose(f: Fighter, pose: String) -> void:
	if f.pose == pose:
		return
	f.pose = pose
	if GUARD_POSES.has(pose):
		var g: Array = GUARD_POSES[pose]
		f.s.visual.play_clip(g[0], FULL, -1.0, 0.0, 0.1, g[1])
	else:
		var idle: Array = STYLE_IDLE[f.style]
		f.s.visual.play_clip(idle[0], FULL, -1.0, idle[1], 0.14)


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
		f.s.visual.roll_offset = -f.lean * 0.3 + sin(_t * 47.0 + f.side) * 0.07 * f.jolt
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
		var target: Vector3
		match aim:
			"collar":
				target = o.s.visual.bone_world("Spine2").lerp(o.s.visual.bone_world("Neck"), 0.55) + dir * 0.12
				# Yanked about while they struggle.
				target += Vector3(sin(_t * 41.0), cos(_t * 37.0) * 0.6, 0.0) * 0.05 * maxf(f.jolt, o.jolt)
			"body":
				target = o.s.visual.bone_world("Spine1") + dir * 0.14
			"chin":
				target = o.s.visual.bone_world("Head") + dir * 0.07 + Vector3.DOWN * 0.08
			_:
				target = o.s.visual.bone_world("Head") + dir * 0.1 + Vector3.DOWN * 0.02
		if f.connects == "block" and aim != "collar":
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
			f.s.visual.hold_breath = 0.0
			f.s.visual.rig.bow = 0.0
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
