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
##             your punches hit harder (and cost more). It goes past a guard; a punch
##             beats it. While holding, only the free right hand punches:
##             Cross = right to the body, Square = right hook, Triangle = uppercut
##             (the same for every style).
##             Held? Mash Circle to break free. Holding and they're getting loose? Mash
##             Circle to hang on. Every press costs a little stamina, on either side, and
##             counts for strength, balance and wind against the other's.
##   hold R1   block high; R1 + L1 blocks low. Blocks only the punches aimed at that level
##             (much less damage, costs stamina); the wrong guard lets it through.
## Stick toward / away from the other steps in / backs off (out of reach, punches miss and
## stamina comes back faster); up / down slips to the side.
##
## Timing: a clean hit leaves the one hit reeling until just after the thrower recovers,
## so landing first wins the next exchange (for two in a row; from the third, the one
## taking them recovers first). A blocked punch holds the blocker in the guard until just
## before the thrower recovers.
## Stamina: wind (spent and refilled) under a ceiling that every punch wears down (misses
## more). Low wind means slower, softer punches and a leakier guard.
##
## Styles (PlayerStats.fighting_style()): each throws its own jab, cross and hook from its
## own idle; the body versions are the same clips bent over at the waist. The uppercut, the
## clinch hook, guards and reactions are shared.
##   BOXER    quick, tight, cheap punches that hit a little lighter
##   BRAWLER  looping haymakers: slower, heavier, costlier and easier to slip
##   GRINDER  short and compact: works the balance and the body
## Reach comes from the body, not the style: a punch lands if the target is within its
## share of the thrower's own arm length from the punching shoulder (_need).
## The computer also fights each its own way (AI_STYLE): the boxer jabs from range and
## counters, the brawler presses and swings, the grinder ties up and digs to the body.

signal finished(winner: Skater, loser: Skater)   ## winner null = draw (loser null too)
signal declined
signal knockout(winner: Skater, loser: Skater)   ## the moment one goes down (for the replay)

enum Stage { PROMPT, SQUARE_UP, FIGHT, OVER }

const PROMPT_TIME := 3.0
const SQUARE_TIME := 1.6
const HELMET_AT := [0.3, 0.4]   ## square-up s each fighter starts taking the helmet off (after the stick drops)
const GEAR_FALL := 0.35          ## s for the stick and gloves to hit the ice
const TIME_LIMIT := 40.0
const OVER_TIME := 3.2
const GAP := 0.95             ## meters between the fighters' centers at fighting range
const START_GAP := 1.6        ## ...when they square up: arm's length apart, they step in to engage
const GAP_MIN := 0.68         ## closest they get (held in a clinch)
const GAP_MAX := 1.9          ## widest apart while squaring up / after it's over
const FIGHT_GAP_MAX := 1.45   ## widest apart during the fight: just past a jab, so backing off buys a breath but never escapes
const STEP_IN := 1.8          ## m/s stepping in...
const STEP_BACK := 1.05       ## ...and backing off (slower, so a chaser always closes)
const STALL_TIME := 2.5      ## s backing off out of range before the linesman shoves them back in
const LEAN_DIST := 0.26
const RING_RADIUS := 4.6
const GRAB_TIME := 4.5         ## longest a grip lasts (mashing breaks it sooner)
const GRAB_POWER := 1.15       ## the holder's punches hit this much harder
const GRAB_COST := 1.3         ## ...and cost this much more (one arm, hauling on the jersey)
const MASH_COST := 0.5         ## stamina per Circle press while tied up, either side
const ESCAPE_PER := 0.085      ## escape progress per press (× strength, balance and wind vs the holder's)
const HOLD_PER := 0.06         ## escape progress a holder's press takes back (same weighting)
## A clean hit leaves the one hit reeling until this long after the thrower can go again
## (light / heavy), so landing first wins the next exchange instead of trading.
const HIT_EDGE := 0.1
const HIT_EDGE_HEAVY := 0.2
const CHAIN_EDGE := 2         ## clean hits in a row that get the edge; after that the one hit recovers first
const CHAIN_RESET := 1.2      ## s without taking a clean one ends the run
## Rocked: clean damage builds a shock meter (heavier shots and a glass jaw build it
## faster; it ebbs at ROCK_EBB a second). Past ROCK_AT of their full health (scaled from
## ×1.5 fresh down to ×0.5 nearly out), or an uppercut on the chin once they're under half,
## they're rocked: they take ROCK_TAKEN more, punch ROCK_POWER as hard and slower, and
## under ROCK_KO_BELOW of their health (after ROCK_KO_AFTER) a heavy clean shot drops them.
## Being rocked breaks any clinch and knocks them apart. They come
## back by covering up (R1), backing off or tying up, until the recovery meter fills;
## every clean hit knocks some of it back.
const ROCK_AT := 0.35
const ROCK_KO_BELOW := 0.35
const ROCK_KO_AFTER := 1.0    ## s rocked before a heavy shot can drop them outright (a chance to cover up)
const ROCK_EBB := 8.0
const ROCK_TAKEN := 1.3
const ROCK_POWER := 0.75
const ROCK_RATE := 0.75       ## their punches' speed
const ROCK_RECOVER := 0.07    ## recovery a second, standing in and taking it...
const ROCK_COVER := 3.5       ## ...this many times faster covering up,
const ROCK_APART := 2.0       ## backed off out of reach,
const ROCK_HOLD := 2.5        ## or tying them up
const ROCK_SETBACK := 0.2     ## recovery a clean hit takes back (a heavy one twice that)
const ROCK_GRACE := 3.0       ## s after coming back before they can be rocked again
## A blocked punch holds the blocker in their guard until this long before the thrower
## recovers: a block buys a slight counter, not a free swing back.
const BLOCK_EDGE := 0.06
## Voices (_voice): chance of a shout on a heavy punch / a grab / any other punch, and of
## a cry from the one a clean jab / other punch lands on (always on a heavy one). One
## sound per fighter per VOICE_GAP s, so they don't stack up in a flurry.
const SHOUT_HEAVY := 0.55
const SHOUT_GRAB := 0.35
const SHOUT_CHANCE := 0.15
const HURT_JAB := 0.3
const HURT_CHANCE := 0.7
const VOICE_GAP := 0.6
## Stamina has two layers: wind (spent and refilled) and a ceiling the wind refills to.
## Every punch thrown lowers the ceiling by its cost × CEIL_PER_COST (a miss by CEIL_MISS
## more), never below CEIL_MIN of the start: spend it all early and you're gassed late.
const CEIL_PER_COST := 0.3
const CEIL_MISS := 0.4
const CEIL_MIN := 0.4
const REGEN_CLOSE := 3.0       ## wind back per s within reach...
const REGEN_APART := 6.0       ## ...and backed off out of it (past the other's arm, AI_REACH[2])
const EXHAUSTED_TIME := 4.0    ## both out of wind this long: a decision
const DRAW_MARGIN := 0.08     ## damage within this share of each other = a draw
const BUFFER := 0.3           ## a press this long before the fighter is free still fires
const STANCE_YAW := 0.42      ## rad the body turns to square the bladed clips up to the other
## A punch is called STEER s before contact, so the hand can be eased onto the target (the
## clips throw at chest height: head shots lift 20-40 cm), with REACH_EARLY slack (arm
## lengths: the punch is still turning the shoulders and lunging in). At contact it's
## judged again for real (reach, a slip, a guard), so the defender's time is the same; out
## of reach then, the arm straightens at the target and stops short.
const STEER := 0.2
const REACH_EARLY := 0.3

## clip, start (clip s), contact (clip s), end (clip s), clip speed, hand (0 left / 1 right),
## damage, balance damage, stamina cost, lunge (m), reach (how far the target may be from
## the punching shoulder, in the thrower's own arm lengths: a bigger fighter reaches
## farther; hooks land on a bent arm), stun (s
## the one hit can't act), aim ("head" / "body" / "chin" / "collar"), slip (the other's
## lean that dodges it; 0 = can't be slipped). Optional: drain (the other's stamina on a
## clean hit), heavy (hit-stop, shake, rocks a holder loose), bow (rad the thrower bends
## forward over the clip, so a head clip reads as a body shot), yaw (the body's turn
## during the move instead of STANCE_YAW; a mirrored clip is bladed the other way).
const MOVES := {
	"jab": {"clip": "lead_jab", "from": 0.18, "contact": 0.5, "end": 0.95, "speed": 1.7, "hand": 0,
		"dmg": 6.5, "bal": 2.5, "cost": 3.0, "lunge": 0.12, "reach": 1.02, "stun": 0.22, "aim": "head", "slip": 0.8},
	"cross": {"clip": "cross_punch", "from": 0.5, "contact": 1.1, "end": 1.6, "speed": 1.8, "hand": 1,
		"dmg": 11.0, "bal": 6.0, "cost": 5.0, "lunge": 0.16, "reach": 1.0, "stun": 0.32, "aim": "head", "slip": 0.7},
	"hook": {"clip": "hook", "from": 0.15, "contact": 0.48, "end": 0.95, "speed": 1.1, "hand": 0,
		"dmg": 17.0, "bal": 10.0, "cost": 9.0, "lunge": 0.1, "reach": 0.95, "stun": 0.45, "aim": "head", "slip": 0.55, "heavy": true},
	"body_jab": {"clip": "lead_jab", "from": 0.18, "contact": 0.5, "end": 0.95, "speed": 1.6, "hand": 0,
		"dmg": 4.0, "bal": 4.0, "drain": 5.0, "cost": 3.0, "lunge": 0.12, "reach": 1.02, "stun": 0.2, "aim": "body", "slip": 0.8, "bow": 0.5},
	"body_cross": {"clip": "boxing_1", "from": 0.25, "contact": 0.72, "end": 1.15, "speed": 1.4, "hand": 1,
		"dmg": 7.0, "bal": 7.0, "drain": 8.0, "cost": 5.0, "lunge": 0.14, "reach": 1.0, "stun": 0.3, "aim": "body", "slip": 0.7, "bow": 0.15},
	"body_hook": {"clip": "boxing", "from": 0.12, "contact": 0.48, "end": 1.0, "speed": 1.15, "hand": 0,
		"dmg": 10.0, "bal": 12.0, "drain": 12.0, "cost": 8.0, "lunge": 0.08, "reach": 0.95, "stun": 0.45, "aim": "body", "slip": 0.55, "bow": 0.12, "heavy": true},
	# Clinch shots (GRAB_MOVES): shared by every style and all thrown with the right hand,
	# since the left is on the jersey. Short, for the clinch's close range.
	"g_body": {"clip": "boxing_1", "from": 0.25, "contact": 0.72, "end": 1.15, "speed": 1.5, "hand": 1,
		"dmg": 7.0, "bal": 8.0, "drain": 9.0, "cost": 5.0, "lunge": 0.04, "reach": 1.0, "stun": 0.3, "aim": "body", "slip": 0.0, "bow": 0.15},
	"g_hook": {"clip": "punching", "from": 0.12, "contact": 0.45, "end": 0.78, "speed": 1.5, "hand": 1, "yaw": 0.0,
		"dmg": 13.0, "bal": 8.0, "cost": 6.0, "lunge": 0.04, "reach": 1.0, "stun": 0.4, "aim": "head", "slip": 0.0, "heavy": true},
	"upper": {"clip": "elbow_uppercut_combo", "from": 1.0, "contact": 1.42, "end": 1.75, "speed": 1.3, "hand": 1,
		"dmg": 19.0, "bal": 17.0, "cost": 8.0, "lunge": 0.06, "reach": 1.0, "stun": 0.5, "aim": "chin", "slip": 0.0, "heavy": true},
	# Grab: no clip, the hand is steered from the stance, where even the lead shoulder sits
	# well back (pressed together it's 1-1.5 arm lengths to the collar); the grip then pulls
	# the pair together.
	"grab": {"clip": "", "from": 0.0, "contact": 0.2, "end": 0.34, "speed": 1.0, "hand": 0,
		"dmg": 0.0, "bal": 4.0, "cost": 4.0, "lunge": 0.15, "reach": 1.6, "stun": 0.0, "aim": "collar", "slip": 0.0},
}
## Only while holding the jersey (the free right hand).
const GRAB_MOVES := ["g_body", "g_hook", "upper"]
const HIT_CLIPS := {"jab": "light_hit_to_head", "cross": "head_hit", "hook": "big_side_hit", "g_hook": "big_side_hit", "g_body": "stomach_hit",
	"upper": "receive_uppercut_to_the_face", "body_jab": "stomach_hit", "body_cross": "stomach_hit", "body_hook": "big_stomach_hit"}
enum Style { BOXER, BRAWLER, GRINDER }
const STYLE_NAMES := ["BOXER", "BRAWLER", "GRINDER"]
const STYLE_COLORS := [Color(0.35, 0.75, 1.0), Color(0.95, 0.32, 0.22), Color(0.95, 0.72, 0.22)]
## A one-line read on each style, for the prompt.
const STYLE_BLURBS := ["quick hands, counters, keeps you at the end of the jab",
	"walks you down and swings for the fences", "ties you up and works the body"]
## How the computer fights each style (_ai): reach (arm lengths added to AI_REACH's
## distance: + at the end of its punches, - crowding in), think
## (× the time between moves: < 1 is busier), read (× how often it reads a punch coming),
## slip (share of the hooks it reads that it slips), counter (chance it fires back right
## after blocking or slipping one), winded / recovered (share of stamina it backs off at /
## comes back at), pick (× the weight of each move in its mix), clinch (upper, g_hook
## weights; the rest g_body), hold (× how hard it hangs on in a clinch).
## The computer's fighting distance, hip to hip, in its own arm lengths: [calm, hot-headed]
## (by aggression), and past [2] it doesn't throw, only closes in. (About 0.77 / 0.7 m for an average
## man, arm 0.54 m; punches land up to about 1.55.)
const AI_REACH := [1.42, 1.3, 1.55]
const AI_STYLE := [
	{   # BOXER: out-fights. Stays at the end of the jab, reads and slips, makes you miss and
		# pays you back with the straight right, backs off to breathe before it's spent.
		"reach": 0.04, "think": 0.95, "read": 1.25, "slip": 0.7, "counter": 0.6, "counter_move": "cross",
		"winded": 0.3, "recovered": 0.55, "hold": 0.8,
		"pick": {"jab": 1.7, "cross": 1.3, "hook": 0.6, "body_jab": 1.1, "body_cross": 0.8, "body_hook": 0.5, "grab": 0.4},
		"clinch": [0.25, 0.35]},
	{   # BRAWLER: pressure. Walks you down, swings big and often, guards lazily, fights on
		# until it's nearly empty, and jumps on anyone who's hurt.
		"reach": -0.1, "think": 0.75, "read": 0.7, "slip": 0.15, "counter": 0.2, "counter_move": "hook",
		"winded": 0.12, "recovered": 0.35, "hold": 1.0,
		"pick": {"jab": 0.6, "cross": 1.3, "hook": 2.2, "body_jab": 0.5, "body_cross": 0.9, "body_hook": 1.4, "grab": 0.8},
		"clinch": [0.45, 0.4]},
	{   # GRINDER: the clinch. Grabs a lot, hangs on, digs to the body, answers a blocked
		# punch by tying you up.
		"reach": -0.05, "think": 0.9, "read": 1.0, "slip": 0.35, "counter": 0.45, "counter_move": "grab",
		"winded": 0.2, "recovered": 0.45, "hold": 1.4,
		"pick": {"jab": 0.8, "cross": 0.8, "hook": 0.8, "body_jab": 1.4, "body_cross": 1.6, "body_hook": 1.6, "grab": 3.0},
		"clinch": [0.25, 0.25]},
]
## Per style: the idle loop and its speed, and whether it is a still stance (breathing laid
## over it, like the guards).
const STYLE_IDLE := [["idle1", 1.0, false], ["idle2", 1.0, false], ["idle3", 1.0, true]]
## Per style, the clip behind each punch (and its body version): clip, from, contact, end
## (clip s), speed, hand, bow for the body version (rad; head-height clips bend more), yaw /
## body_yaw (the body's turn while throwing it, aimed so the clip's own fist arrives on the
## target: calibrated with `-- fightdebug fightmove=<move> fightstyle=<n> fightyaw=<rad>`,
## about 0.67 m sideways per rad), and optionally blend (s into the clip; big windups
## start mid-swing). Speeds keep contact near
## the base timings so the styles differ by feel, not by a whole beat.
const STYLE_CLIPS := [
	{   # BOXER
		"jab": {"clip": "jab1", "from": 0.3, "contact": 0.56, "end": 0.9, "speed": 1.55, "hand": 0, "bow": 0.5, "yaw": 0.28, "body_yaw": 0.33},
		"cross": {"clip": "cross1", "from": 0.12, "contact": 0.4, "end": 0.85, "speed": 1.0, "hand": 1, "bow": 0.3, "yaw": 0.17, "body_yaw": 0.02},
		# Mirrored: the clip throws it with the left; Triangle is always the dominant hand.
		"hook": {"clip": "hook1_mirrored", "from": 0.2, "contact": 0.64, "end": 1.25, "speed": 1.55, "hand": 1, "bow": 0.45, "yaw": -0.13, "body_yaw": -0.26},
	},
	{   # BRAWLER
		"jab": {"clip": "jab2", "from": 0.05, "contact": 0.4, "end": 0.8, "speed": 1.6, "hand": 0, "bow": 0.55, "yaw": 0.03, "body_yaw": 0.26},
		"cross": {"clip": "cross2", "from": 0.5, "contact": 1.1, "end": 1.6, "speed": 1.6, "hand": 1, "bow": 0.4, "yaw": 0.22, "body_yaw": 0.04},
		"hook": {"clip": "hook2", "from": 0.45, "contact": 1.08, "end": 1.6, "speed": 1.4, "hand": 1, "bow": 0.3, "blend": 0.15, "yaw": 0.65, "body_yaw": 0.39},
	},
	{   # GRINDER
		"jab": {"clip": "jab3", "from": 0.3, "contact": 0.57, "end": 1.0, "speed": 1.5, "hand": 0, "bow": 0.25, "yaw": 0.30, "body_yaw": 0.27},
		"cross": {"clip": "cross3", "from": 0.1, "contact": 0.37, "end": 0.75, "speed": 1.0, "hand": 1, "bow": 0.25, "yaw": 0.02, "body_yaw": 0.02},
		"hook": {"clip": "hook3", "from": 0.15, "contact": 0.32, "end": 0.75, "speed": 0.85, "hand": 1, "bow": 0.5, "blend": 0.1, "yaw": 0.18, "body_yaw": 0.02},
	},
]
## Per style, on the punches it has its own clips for: MOVES numbers multiplied. slip < 1
## means less lean dodges it. (Reach is the fighter's arms, never the style.)
const STYLE_MODS := [
	{"dmg": 0.92, "cost": 0.8, "stun": 0.9},
	{"dmg": 1.15, "bal": 1.15, "cost": 1.15, "slip": 0.85},
	{"dmg": 0.97, "bal": 1.2, "drain": 1.3},
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
	var stamina_cap := 100.0   ## the ceiling wind refills to (drops with every punch thrown)
	var guard_lock := 0.0      ## s a blocked punch keeps this fighter in their guard
	var chain := 0             ## clean hits taken in a row (CHAIN_EDGE)
	var chain_t := 99.0        ## s since the last one
	var shock := 0.0           ## the rocked meter (ROCK_AT)
	var rocked := false
	var recover := 0.0         ## 0..1 back from being rocked
	var rock_grace := 0.0      ## s before they can be rocked again
	var rocked_t := 0.0        ## s rocked
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
	var ai_range := GAP        ## AI: separation it backs off to when tired, or holds in a clinch
	var ai_winded := false     ## AI: backing off for wind (until its style's "recovered")
	var ai_counter := ""       ## AI: a counter to fire at its next move (AI_STYLE counter)
	var ai_read := false       ## AI: already judged the other's current punch for a counter
	var stall_t := 0.0         ## seconds backing off out of range (linesman at STALL_TIME)
	var buffered := ""
	var buffer_t := 0.0
	var pose := ""            ## the looping clip playing ("idle" / "block_high" / "block_low")
	var flash_t := 0.0        ## HUD: seconds the bars flash after a hit
	var reach := [0.0, 0.0]   ## per hand, the IK weight this tick
	var voice_t := 0.0        ## s until this fighter shouts / cries out again (_voice)

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
var _shove_t := 0.0   ## seconds left of a linesman shove (pushes the pair back to fighting range)
var _debug_move := ""  ## `-- fightmove=<move>` (see _ai)
var _debug_b := false  ## `-- fightside=b`: the second fighter throws it (the first stands)
var _debug_clinch := false  ## `-- fightclinch`: ...thrown from a clinch
var _debug_yaw := INF      ## `-- fightyaw=<rad>`: the turn while throwing the fightmove= move (aiming clips)
var _debug_reach := false   ## `-- fightdebug`: at each contact, mark and log the clip's fist vs the target
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("fightmove=") and MOVES.has(arg.substr(10)):
			_debug_move = arg.substr(10)
		elif arg == "fightside=b":
			_debug_b = true
		elif arg == "fightclinch":
			_debug_clinch = true
		elif arg == "fightdebug":
			_debug_reach = true
		elif arg.begins_with("fightyaw="):
			_debug_yaw = float(arg.substr(9))
	center =(fa.global_position + fb.global_position) * 0.5
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
	# `-- fighteven`: both fighters on the same middling ratings (for weighing the styles
	# against each other; pair with fightstyle=).
	if "fighteven" in OS.get_cmdline_user_args():
		s.stats = s.stats.duplicate()
		for k in ["fighting", "durability", "strength", "endurance", "aggression", "agility"]:
			s.stats.set(k, 60)
	f.max_health = PlayerStats.lerp_stat(int((s.stats.fighting + s.stats.durability) / 2.0), 105.0, 170.0)
	f.health = f.max_health
	f.max_balance = PlayerStats.lerp_stat(s.stats.strength, 75.0, 125.0)
	f.balance = f.max_balance
	f.max_stamina = PlayerStats.lerp_stat(s.stats.endurance, 60.0, 110.0)
	f.stamina = f.max_stamina
	f.stamina_cap = f.max_stamina
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
			if c.has("yaw"):
				m.yaw = c.get("body_yaw", c.yaw) if k.begins_with("body_") else c.yaw
			if k.begins_with("body_"):
				m.bow = c.bow
			for key: String in STYLE_MODS[style]:
				if m.has(key):
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
	_check_stalling(delta)
	_move(delta)
	# Out of gas on both sides, or out of time: a decision.
	_exhausted = _exhausted + delta if a.stamina < 6.0 and b.stamina < 6.0 else 0.0
	if stage == Stage.FIGHT and (_time_left <= 0.0 or _exhausted > EXHAUSTED_TIME):
		_decision()


## Hanging back out of range (not stepping in) runs a clock; at STALL_TIME the linesman
## shoves the pair back together.
func _check_stalling(delta: float) -> void:
	var apart := separation() > 1.3 and a.grabbing <= 0.0 and b.grabbing <= 0.0
	for f: Fighter in [a, b]:
		if apart and f.step <= 0.1 and f.act != "down":
			f.stall_t += delta
		else:
			f.stall_t = maxf(0.0, f.stall_t - delta * 2.0)
		if f.stall_t >= STALL_TIME:
			a.stall_t = 0.0
			b.stall_t = 0.0
			_shove_t = 0.4
			_log["shove"] = int(_log.get("shove", 0)) + 1
			_hud.flash("LINESMAN SHOVES %s BACK IN" % _name(f.s))
			return


## Free to start something new (not mid-punch, not reeling, not held in the guard by a
## punch just blocked).
func _free(f: Fighter) -> bool:
	return f.act == "" and f.guard_lock <= 0.0


## 0..1: how much wind f has left for full-strength work (1 at half the full tank or more).
func _wind(f: Fighter) -> float:
	return clampf(f.stamina / (f.max_stamina * 0.5), 0.0, 1.0)


## Seconds until f's current move ends.
func _left(f: Fighter) -> float:
	if not f.act in MOVES:
		return 0.0
	return maxf(0.0, _dur(f.moves[f.act]) / f.rate - f.act_t)


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
			want = "g_body" if holding else ("body_jab" if i.protect else "jab")
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
	# Each press counts for f's pull against the other's: strength, footing and wind.
	var power := _pull(f) / maxf(_pull(o), 0.1)
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


## How hard f pulls in a tie-up: strength, a little less off balance, less out of wind.
func _pull(f: Fighter) -> float:
	return PlayerStats.lerp_stat(f.s.stats.strength, 0.7, 1.3) * lerpf(0.8, 1.0, f.balance / f.max_balance) * lerpf(0.55, 1.0, _wind(f)) * (0.7 if f.rocked else 1.0)


## Computer fighter: keeps its range, reads visible punches (slips the big ones, guards the
## right level by skill), mashes when tied up, mixes head and body, backs off to get its
## wind back. Its style (AI_STYLE) sets the range, pace, mix, defense and counters.
func _ai(f: Fighter, delta: float) -> void:
	var skill := PlayerStats.lerp_stat(f.s.stats.fighting, 0.25, 0.85)
	var aggr := PlayerStats.lerp_stat(f.s.stats.aggression, 0.0, 1.0)
	var st: Dictionary = AI_STYLE[f.style]
	var o := f.other
	if f == (a if _debug_b else b) and _debug_move != "":
		f.step = 0.0   # checking a clip: the other one stands and takes it
		return
	f.lean_hold -= delta
	if f.lean_hold <= 0.0:
		f.lean_target = 0.0
	# Range: close in to fight, back off when winded (until the wind is back, not just over
	# the line, so it doesn't hover there). Backing off only ever reaches just out of a jab.
	# Back in once the wind is back: to its style's line, or near the ceiling every punch
	# has worn down (which can end up below that line: waiting for it, both fighters hung
	# back and ran out the clock).
	if f.stamina < f.max_stamina * float(st.winded):
		f.ai_winded = true
	elif f.stamina > minf(f.max_stamina * float(st.recovered), f.stamina_cap * 0.85):
		f.ai_winded = false
	# Winded against someone just as gassed: no point backing off, fight on.
	var o_gassed := o.stamina < o.max_stamina * 0.25 or o.rocked
	var tired := (f.ai_winded and not o_gassed) or f.rocked
	var tied := o.grabbing > 0.0 or f.grabbing > 0.0
	var sep := separation()
	# Its fighting distance in its own arm lengths (a bigger fighter stands further off),
	# set by temper and style. (Measured hip to hip: in the stance the rear shoulder sits
	# well back until the punch turns the body, so a shoulder reading says "too far" even
	# chest to chest.)
	var arm := _arm(f, "Right")
	if tired or tied:
		f.ai_range = 1.4 if not tied else lerpf(1.0, 0.86, aggr)
	else:
		f.ai_range = arm * (lerpf(AI_REACH[0], AI_REACH[1], aggr) + float(st.reach))
	f.step = clampf((sep - f.ai_range) * 3.0, -1.0, 1.0) if absf(sep - f.ai_range) > 0.05 else 0.0
	# Too far to throw: close at full speed (easing in, it only matched a retreat and the
	# pair froze just out of range).
	if not tired and not tied and sep > arm * AI_REACH[2]:
		f.step = 1.0
	# Tied up: mash Circle, faster with skill (the holder only once they're getting loose).
	f.mash_t -= delta
	if f.mash_t <= 0.0 and f.act != "down":   # like a human, presses even while reeling
		# A human pace, uneven, never a machine-gun.
		var rate := lerpf(3.0, 5.5, skill) * (0.7 if tired else 1.0)
		if o.grabbing > 0.0:
			_mash(f, true)
			f.mash_t = _rng.randf_range(0.6, 1.5) / rate
		elif f.grabbing > 0.0 and o.escape > 0.15 / float(st.hold):
			_mash(f, false)
			f.mash_t = _rng.randf_range(0.6, 1.5) / (rate * float(st.hold))
	# A punch coming: slip the hooks or get the right guard up, if quick enough to read it.
	var incoming := o.act in MOVES and o.act != "grab" and not o.landed
	if not incoming:
		# Their punch just ended on the guard or in the air: maybe fire right back.
		if f.ai_read and o.act in MOVES and o.landed and o.connects in ["block", "miss"] and f.act == "" \
				and not tied and _rng.randf() < float(st.counter) * lerpf(0.6, 1.2, skill):
			f.ai_counter = st.counter_move
			_log["counter " + f.ai_counter] = int(_log.get("counter " + f.ai_counter, 0)) + 1
			f.ai_next = minf(f.ai_next, 0.05)
		f.ai_read = false
	elif f.act == "" and f.lean_target == 0.0 and not f.blocking and _rng.randf() < skill * float(st.read) * delta * 7.0:
		var m: Dictionary = o.moves[o.act]
		f.ai_read = true
		if o.act in ["hook", "body_hook", "cross"] and o.grabbing <= 0.0 and _rng.randf() < float(st.slip) * (1.0 if o.act != "cross" else 0.5):
			f.lean_target = 1.0 if _rng.randf() < 0.5 else -1.0
			f.lean_hold = 0.55
		else:
			var low: bool = m.aim == "body"
			f.blocking = true
			f.block_low = low if _rng.randf() < lerpf(0.55, 0.95, skill) else not low
			f.ai_next = 0.45
	f.ai_next -= delta
	if f.ai_next > 0.0 or not _free(f):
		return
	f.blocking = false
	f.ai_next = _rng.randf_range(0.25, 0.7) * lerpf(1.3, 0.7, skill) * float(st.think)
	if f.ai_counter != "":
		var c := f.ai_counter
		f.ai_counter = ""
		if not tired and sep < 1.3:
			_try(f, c)
			return
	if tired:
		# Winded or rocked and they're on top of it: tie them up to survive, or cover up
		# (rocked: nearly always, that's how it comes back).
		if sep < arm * AI_REACH[2] and not tied and _rng.randf() < (0.35 if f.rocked else 0.3) * (1.5 if f.style == Style.GRINDER else 1.0):
			_try(f, "grab")
			return
		# (Only within their reach: a guard costs wind, and out there it's what it's getting back.)
		if sep < _arm(o, "Right") * AI_REACH[2] + 0.1 and _rng.randf() < (0.9 if f.rocked else 0.5):
			f.blocking = true
			# Hurt: the hands go up to the head, where the finishing shots come.
			f.block_low = _rng.randf() < (0.15 if f.rocked else 0.35)
			f.ai_next = 0.6
		return
	# `-- fightmove=<move>`: the first fighter (an AI) only throws that move, grabbing first
	# for the clinch ones or with `-- fightclinch` (for checking a clip).
	if f == (b if _debug_b else a) and _debug_move != "":
		_try(f, "grab" if (_debug_move in GRAB_MOVES or _debug_clinch) and f.grabbing <= 0.0 else _debug_move)
		f.ai_next = 0.6
		return
	if o.grabbing > 0.0:
		_try(f, "body_jab" if _rng.randf() < 0.5 else "jab")
		return
	if f.grabbing > 0.0:
		var g := _rng.randf()
		var cw: Array = st.clinch
		_try(f, "upper" if g < cw[0] else ("g_hook" if g < cw[0] + cw[1] else "g_body"))
		return
	if sep > arm * AI_REACH[2]:
		return   # still closing in
	if o.rocked:
		# They're hurt: go for the finish with the big ones, and don't wait about (a brawler
		# all the more).
		f.ai_next *= 0.7 if f.style != Style.BRAWLER else 0.5
		if _rng.randf() < (0.55 if f.style != Style.BRAWLER else 0.8):
			_try(f, "hook" if _rng.randf() < 0.7 else "cross")
			return
	var pk_mul: Dictionary = st.pick
	var picks := [["jab", 0.26], ["cross", 0.16], ["hook", 0.1 + aggr * 0.08], ["body_jab", 0.09],
			["body_cross", 0.08], ["body_hook", 0.06 + aggr * 0.04],
			# Grabs mostly when the other is covering up (a grab goes past a guard).
			["grab", 0.04 + (0.16 if o.blocking else 0.0)]]
	# Weights scaled by style, then renormalised so the share left over for covering up
	# stays the same (about a seventh of its turns).
	var total := 0.0
	for pk: Array in picks:
		pk[1] *= float(pk_mul.get(pk[0], 1.0))
		total += pk[1]
	var r := _rng.randf() * total / 0.86
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
	# Tired fighters throw slower; one hand on a jersey costs more. Every punch also wears
	# the ceiling the wind comes back to.
	var cost: float = m.cost * (GRAB_COST if f.grabbing > 0.0 else 1.0)
	f.rate = 0.7 if f.stamina < cost else lerpf(0.78, 1.0, _wind(f))
	if f.rocked:
		f.rate *= ROCK_RATE
	f.stamina = maxf(0.0, f.stamina - cost)
	f.stamina_cap = maxf(f.max_stamina * CEIL_MIN, f.stamina_cap - cost * CEIL_PER_COST)
	f.vx += f.toward() * m.lunge * 3.0
	# A shout on some punches: most big ones, now and then the rest; less once worn out.
	var shout := SHOUT_HEAVY if m.get("heavy", false) else (SHOUT_GRAB if move == "grab" else SHOUT_CHANCE)
	if f.rocked or _wind(f) < 0.3:
		shout *= 0.5
	if _rng.randf() < shout:
		_voice(f, "shout", -4.0)
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
	f.voice_t = maxf(0.0, f.voice_t - delta)
	if f.act == "down":
		return
	var o := f.other
	var sep := separation()
	# Wind comes back (up to the ceiling), faster out of reach.
	var regen := REGEN_CLOSE if sep < _arm(o, "Right") * AI_REACH[2] else REGEN_APART
	if f.blocking:
		regen = -2.0
	if f.rocked and regen > 0.0:
		regen *= 0.5
	f.stamina = clampf(f.stamina + regen * delta, 0.0, maxf(f.stamina, f.stamina_cap))
	f.guard_lock = maxf(0.0, f.guard_lock - delta)
	f.shock = maxf(0.0, f.shock - ROCK_EBB * delta)
	f.rock_grace = maxf(0.0, f.rock_grace - delta)
	if f.rocked:
		f.rocked_t += delta
		var rate := ROCK_RECOVER
		if f.blocking:
			rate *= ROCK_COVER
		elif f.grabbing > 0.0:
			rate *= ROCK_HOLD
		elif sep > 1.3:
			rate *= ROCK_APART
		f.recover += rate * delta
		if f.recover >= 1.0:
			_unrock(f)
	f.chain_t += delta
	# Held by the jersey: balance drains (more against a strong grabber).
	f.grabbing = maxf(0.0, f.grabbing - delta)
	if o.grabbing <= 0.0:
		f.escape = 0.0
	f.jolt = move_toward(f.jolt, 0.0, delta * 5.0)
	var bow_to: float = f.moves[f.act].get("bow", 0.0) if f.act in MOVES else 0.0
	f.bow = move_toward(f.bow, bow_to, delta * 3.0)
	f.s.visual.rig.bow = f.bow
	# A mirrored clip is bladed the other way: square it up with the opposite turn.
	f.s.visual.yaw_offset = f.moves[f.act].get("yaw", STANCE_YAW) if f.act in MOVES else STANCE_YAW
	if _debug_yaw != INF and f.act == _debug_move:
		f.s.visual.yaw_offset = _debug_yaw
	if o.grabbing > 0.0:
		f.balance -= PlayerStats.lerp_stat(o.s.stats.strength, 2.5, 5.0) * delta
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
		_set_pose(f, ("block_low" if f.block_low else "block_high") if f.blocking else ("rocked" if f.rocked else "idle"))
		return
	f.act_t += delta
	if f.act == "hit":
		if f.act_t > f.stun:
			f.act = ""
		return
	var m: Dictionary = f.moves[f.act]
	var contact := _windup(m) / f.rate
	if not f.landed and f.connects == "" and f.act_t >= contact - STEER:
		f.connects = _will_connect(f, f.act)
	# Steer the punching hand onto the target around contact.
	if f.connects in ["hit", "block"]:
		var w := 0.0
		var t := f.act_t - contact
		if t < 0.0:
			w = smoothstep(-STEER, 0.0, t)
		else:
			w = 1.0 - smoothstep(0.06, 0.2, t)
		if f.act == "grab":
			w = smoothstep(-0.2, 0.0, t)
		f.reach[m.hand] = maxf(f.reach[m.hand], w)
	if not f.landed and f.act_t >= contact:
		f.landed = true
		if _debug_reach:
			_measure_reach(f, f.act)
		_land(f, f.act)
	if f.act != "" and f.act != "down" and f.act_t >= _dur(m) / f.rate:
		f.act = ""


## Does the move land, hit the guard, or miss (out of reach, slipped)? `final`: at contact
## (no reach slack; see STEER).
func _will_connect(f: Fighter, move: String, final := false) -> String:
	var o := f.other
	var m: Dictionary = f.moves[move]
	if _need(f, move) > m.reach + (0.0 if final else REACH_EARLY):
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
	# Called STEER s before contact (with slack, to steer the hand): now for real.
	var how := _will_connect(f, move, true)
	f.connects = how
	var key := "%s %s" % [move, how]
	_log[key] = int(_log.get(key, 0)) + 1
	if how == "miss":
		f.stamina_cap = maxf(f.max_stamina * CEIL_MIN, f.stamina_cap - m.cost * CEIL_MISS)
		if _need(f, move) > m.reach:
			_hud.flash_for(f, "OUT OF REACH — STEP IN")
		else:
			f.balance -= 6.0 if m.get("heavy", false) else 2.0
			_hud.flash("%s SLIPS IT!" % _name(o.s))
		Sfx.play("swish" if Sfx.has("swish") else "pad", at, -12.0, 1.4)
		return
	if move == "grab":
		# A grab goes straight past a guard: it's the answer to someone covering up.
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
		power *= GRAB_POWER
	power *= lerpf(0.65, 1.0, _wind(f))   # arm-weary punches land soft
	if f.rocked:
		power *= ROCK_POWER
	if o.rocked and how == "hit":
		power *= ROCK_TAKEN
	var dmg: float = m.dmg * power
	var bal: float = m.bal * power
	if m.slip > 0.0 and absf(o.lean) > m.slip * 0.5:
		dmg *= 0.5   # leaning away: it only glances
	var heavy: bool = m.get("heavy", false)
	var drain: float = m.get("drain", 0.0) * power
	if how == "block":
		# A tired guard lets more through.
		dmg *= lerpf(0.5, 0.25, _wind(o))
		bal *= 0.35
		drain *= 0.25
		o.stamina = maxf(0.0, o.stamina - (7.0 if heavy else 3.0))
		o.guard_lock = maxf(o.guard_lock, _left(f) - BLOCK_EDGE)
		o.chain = 0
		o.vx -= o.toward() * (0.5 if heavy else 0.2)
		Sfx.play("hit_block", at, 0.0 if heavy else -3.0, 0.9 if heavy else 1.05)
		_hud.flash_for(o, "BLOCKED")
	else:
		var thud := "hit_body" if m.aim == "body" else "hit_head"
		Sfx.play(thud, at, 2.0 if heavy else -1.0, 0.92 if heavy else 1.05)
		# The one hit cries out: always on a big one, often otherwise, now and then off a jab.
		var cry := 1.0 if heavy else (HURT_JAB if move == "jab" or move == "body_jab" else HURT_CHANCE)
		if _rng.randf() < cry:
			_voice(o, "hurt", -3.0, heavy)
		o.vx -= o.toward() * (1.1 if heavy else 0.45)
		_shake = maxf(_shake, 0.09 if heavy else 0.035)
		if heavy:
			_hitstop(70)
		if o.blocking:
			_hud.flash_for(o, "WRONG GUARD — BLOCK LOW (L1)" if m.aim == "body" else "WRONG GUARD — BLOCK HIGH")
		# Every clean blow interrupts; the one hit reels for a moment.
		# They reel until a beat after the thrower recovers: landing first wins the next
		# exchange.
		# Only the first CHAIN_EDGE in a row: after that the one taking them comes back
		# first, so a run of hits can be covered or answered, never a stun-lock.
		o.chain = o.chain + 1 if o.chain_t < CHAIN_RESET else 1
		o.chain_t = 0.0
		o.act = "hit"
		o.act_t = 0.0
		if o.chain <= CHAIN_EDGE:
			o.stun = maxf(m.stun, _left(f) + (HIT_EDGE_HEAVY if heavy else HIT_EDGE))
		else:
			o.stun = clampf(_left(f) - 0.08, 0.12, m.stun)
		o.landed = false
		o.blocking = false
		o.guard_lock = 0.0
		o.s.visual.play_clip(HIT_CLIPS.get(move, "head_hit"), FULL, o.stun + 0.3, 1.5, 0.04)
		o.pose = ""
		o.flash_t = 0.35
		_impact(f, o, m, heavy)
		if not o.human:
			# A computer fighter takes a moment to come back after a clean one (not once
			# it's taking a run of them: then it answers at once).
			var skill := PlayerStats.lerp_stat(o.s.stats.fighting, 0.25, 0.85)
			o.ai_next = maxf(o.ai_next, o.stun + (lerpf(0.25, 0.1, skill) if o.chain <= CHAIN_EDGE else 0.0))
		# A big shot can knock a holder's hand loose: likelier the shakier they are.
		if o.grabbing > 0.0 and heavy and _rng.randf() < 0.3 + 0.5 * (1.0 - o.balance / o.max_balance):
			o.grabbing = 0.0
	o.health -= dmg
	o.balance -= bal
	o.stamina = maxf(0.0, o.stamina - drain)
	f.damage_dealt += dmg
	if how == "hit":
		f.chain = 0   # landing one back breaks the run
		if o.rocked:
			if heavy and o.health < o.max_health * ROCK_KO_BELOW and o.rocked_t >= ROCK_KO_AFTER:
				o.health = 0.0   # hurt, rocked, and a big one lands clean: that's it
				_log["rock ko"] = int(_log.get("rock ko", 0)) + 1
			else:
				o.recover = maxf(0.0, o.recover - ROCK_SETBACK * (2.0 if heavy else 1.0))
		elif o.rock_grace <= 0.0:
			var jaw := PlayerStats.lerp_stat(o.s.stats.durability, 1.3, 0.75)
			o.shock += dmg * (1.4 if heavy else 1.0) * jaw
			var chin: bool = m.aim == "chin" and o.health < o.max_health * 0.5
			var rock_at := o.max_health * ROCK_AT * lerpf(0.5, 1.5, o.health / o.max_health)
			if o.health > 0.0 and (o.shock >= rock_at or chin):
				_rock(f, o)
	if o.health <= 0.0 or o.balance <= 0.0:
		_knockdown(f, o, move)


## `o` is rocked (by `f`): hurt, slow and one big shot from going down until they recover.
func _rock(f: Fighter, o: Fighter) -> void:
	o.rocked = true
	o.recover = 0.0
	o.rocked_t = 0.0
	o.shock = 0.0
	# The clinch breaks, both ways, and the blow sends them apart.
	o.grabbing = 0.0
	f.grabbing = 0.0
	o.vx -= o.toward() * 1.2
	_log["rocked"] = int(_log.get("rocked", 0)) + 1
	if OS.has_environment("KH_FIGHT_LOG"):
		print("[fight]   %.1f s  rocked: %s  hp %.0f/%.0f  by %s" % [TIME_LIMIT - _time_left, _name(o.s), o.health, o.max_health, f.act])
	_hud.banner("%s GOT ROCKED!" % _name(o.s))
	if o.human:
		_hud.flash_for(o, "COVER UP (R1), BACK OFF OR TIE UP")
	elif f.human:
		_hud.flash_for(f, "THEY'RE HURT — FINISH IT")
	_shake = maxf(_shake, 0.12)
	_hitstop(110)
	Sfx.crowd_react("cheer", -3.0, 2)


func _unrock(f: Fighter) -> void:
	f.rocked = false
	f.recover = 0.0
	f.shock = 0.0
	f.rock_grace = ROCK_GRACE
	_hud.flash_for(f, "SHAKES IT OFF")


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
		print("[fight] styles a %s b %s  winner %s" % [STYLE_NAMES[a.style], STYLE_NAMES[b.style],
				"a" if w == a.s else ("b" if w == b.s else "draw")])
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
	elif pose == "rocked":
		f.s.visual.play_clip("dizzy_idle", FULL, -1.0, 1.0, 0.2)
	else:
		var idle: Array = STYLE_IDLE[f.style]
		f.s.visual.play_clip(idle[0], FULL, -1.0, idle[1], 0.14)


## A fighter's voice ("shout" throwing, "hurt" hit): shout_male / hurt_female etc. by
## body type. One at a time per fighter (VOICE_GAP), unless `force` (a big shot taken).
func _voice(f: Fighter, kind: String, volume_db: float, force := false) -> void:
	if f.voice_t > 0.0 and not force:
		return
	var sound := "%s_%s" % [kind, "female" if f.s.body_type == "female" else "male"]
	f.voice_t = VOICE_GAP
	Sfx.play(sound, f.s.visual.bone_world("Head"), volume_db, 1.0)


## A clean one lands: a flare where it hit, spit off a head shot, and blood once `o` is
## under half health (the Blood option). The human who took it gets red screen edges.
func _impact(f: Fighter, o: Fighter, m: Dictionary, heavy: bool) -> void:
	var head: bool = m.aim != "body"
	var at := o.s.visual.bone_world("Head" if head else "Spine1")
	if head:
		at += Vector3.UP * 0.04
	# Out along the blow: away from the thrower, a little up.
	var dir := (axis * -o.toward() + Vector3.UP * 0.35).normalized()
	at -= axis * -o.toward() * 0.08   # the face side, toward the fist
	_flare(at, 0.38 if heavy else 0.24)
	if o.human:
		_hud.hurt(0.85 if heavy else 0.5)
	if not heavy:
		_hitstop(30)
	if not head:
		return
	_spray(at, dir, Color(0.9, 0.95, 1.0, 0.85), 26 if heavy else 14, 0.036, 3.2 if heavy else 2.4)
	if bool(GameSettings.options.get("blood", true)) and o.health < o.max_health * 0.5:
		var hurt := 1.0 - o.health / (o.max_health * 0.5)   # 0 at half health, 1 at empty
		var n := int(lerpf(10.0, 24.0, hurt) * (1.6 if heavy else 1.0))
		_spray(at, dir, Color(0.62, 0.03, 0.04), n, 0.055, 2.8 if heavy else 2.0)
		var drops := (3 if heavy else 1) + int(hurt * 2.0)
		for i in drops:
			var d := Vector3(at.x, 0.0, at.z) + Vector3(dir.x, 0.0, dir.z) * _rng.randf_range(0.2, 1.1) 					+ Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
			_drop(d, _rng.randf_range(0.07, 0.16))


## A one-shot burst of droplets (freed when done).
func _spray(at: Vector3, dir: Vector3, color: Color, n: int, size: float, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(n, 1)
	p.lifetime = 0.9
	p.local_coords = false
	var q := SphereMesh.new()
	q.radius = size * 0.5
	q.height = size
	q.radial_segments = 6
	q.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = mat
	p.mesh = q
	p.direction = dir
	p.spread = 24.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 0.8))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	p.damping_min = 0.5
	p.damping_max = 1.5
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## A blood spot on the ice (stays until the fight's props are cleared).
func _drop(at: Vector3, r: float) -> void:
	var d := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.002
	disc.radial_segments = 10
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.02, 0.03, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	disc.material = mat
	d.mesh = disc
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	d.global_position = at + Vector3.UP * 0.006
	d.scale = Vector3(_rng.randf_range(0.7, 1.4), 1.0, _rng.randf_range(0.7, 1.4))
	d.rotation.y = _rng.randf() * TAU
	_props.append(d)


## A quick bright starburst where a punch landed.
func _flare(at: Vector3, size: float) -> void:
	var q := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = true
	mat.albedo_texture = _flare_tex()
	mat.albedo_color = Color(1.0, 0.95, 0.8, 0.8)
	quad.material = mat
	q.mesh = quad
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	q.global_position = at
	q.scale = Vector3.ONE * 0.4
	var tw := q.create_tween().set_parallel()
	tw.tween_property(q, "scale", Vector3.ONE * 1.3, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_delay(0.05)
	tw.chain().tween_callback(q.queue_free)


var _flare_texture: Texture2D

func _flare_tex() -> Texture2D:
	if _flare_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 0.9, 0.6, 0.7))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_flare_texture = t
	return _flare_texture


func _hitstop(ms: int) -> void:
	Engine.time_scale = 0.12
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + ms)


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
		var want := f.step * (STEP_IN if f.step > 0.0 else STEP_BACK) * f.toward()
		if f.act in ["hit", "down"]:
			want = 0.0
		if held:
			want = 0.0
		f.vx = move_toward(f.vx, want, (7.0 if want != 0.0 else 3.2) * delta)
		f.x += f.vx * delta
		f.lean = move_toward(f.lean, f.lean_target, delta * 7.0)
	# A grip pulls them together; nobody passes through anybody.
	var sep := separation()
	if _shove_t > 0.0:
		_shove_t -= delta
		if sep > GAP:
			var shove := minf((sep - GAP) * 0.5, 1.4 * delta)
			a.x += shove
			b.x -= shove
			a.vx = maxf(a.vx, 0.0)
			b.vx = minf(b.vx, 0.0)
		sep = separation()
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
	# Too far apart: drawn back in (gently during the fight, so the square-up gap eases shut).
	var gap_max := FIGHT_GAP_MAX if stage == Stage.FIGHT else GAP_MAX
	if sep > gap_max:
		var pull2 := (sep - gap_max) * 0.5
		if stage == Stage.FIGHT:
			pull2 = minf(pull2, 1.2 * delta)
		a.x += pull2
		b.x -= pull2
		a.vx = maxf(a.vx, 0.0)
		b.vx = minf(b.vx, 0.0)
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
		if f.rocked:   # unsteady on the skates
			f.s.visual.roll_offset += sin(_t * 2.6 + f.side) * 0.09
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
		var target := _target(f, aim)
		if aim == "collar":
			# Yanked about while they struggle.
			target += Vector3(sin(_t * 41.0), cos(_t * 37.0) * 0.6, 0.0) * 0.05 * maxf(f.jolt, o.jolt)
		if f.connects == "block" and aim != "collar":
			target += dir * 0.12   # stopped by the forearms
		rig.reach_world[k] = target


## Where f's hand goes on the other for `aim` ("collar", "body", "chin", else the face):
## the surface, a little toward f from the bone.
func _target(f: Fighter, aim: String) -> Vector3:
	var o := f.other
	var dir := (f.s.global_position - o.s.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else axis
	match aim:
		"collar":
			return o.s.visual.bone_world("Spine2").lerp(o.s.visual.bone_world("Neck"), 0.55) + dir * 0.12
		"body":
			return o.s.visual.bone_world("Spine1") + dir * 0.14
		"chin":
			return o.s.visual.bone_world("Head") + dir * 0.07 + Vector3.DOWN * 0.08
	return o.s.visual.bone_world("Head") + dir * 0.1 + Vector3.DOWN * 0.02


## How far f's punch has to go for `move`: from the punching shoulder to where it lands,
## in f's own arm lengths (upper arm + forearm, scaled with the body). Over 1 the arm
## can't get there straight; MOVES reach is how much each move gets.
func _need(f: Fighter, move: String) -> float:
	var m: Dictionary = f.moves[move]
	var side := "Left" if int(m.hand) == 0 else "Right"
	return f.s.visual.bone_world(side + "Arm").distance_to(_target(f, m.aim)) / _arm(f, side)


func _arm(f: Fighter, side: String) -> float:
	var rig := f.s.visual.rig
	return (float(rig._len[side + "Upper"]) + float(rig._len[side + "Fore"])) * f.s.visual.body_size.x


## `-- fightdebug`: at contact, how far the clip's own fist (before the reach IK) is from
## where the punch lands, split into along the line between them (+ past the target,
## - short), up and sideways; and how far the target is from the shoulder in arm lengths
## (past 1 the IK can't get there). Marks both: red the clip's fist, green the target.
func _measure_reach(f: Fighter, move: String) -> void:
	var m: Dictionary = f.moves[move]
	var v := f.s.visual
	var k: int = m.hand
	var side := "Left" if k == 0 else "Right"
	var fist: Vector3 = v.rig.raw_hand_world[k] if v.rig.reach_w[k] > 0.001 else v.bone_world(side + "Hand")
	var target := _target(f, m.aim)
	var fwd := target - v.bone_world("Hips")
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d := fist - target
	var up := d.y
	var along := d.dot(fwd)
	var lateral := (d - fwd * along - Vector3.UP * up).length()
	# Signed: + to the thrower's right. As a turn of the body (rad, + turns the fist left
	# onto the target), what aiming the clip at it would take.
	var right := fwd.cross(Vector3.UP)
	var lat := d.dot(right)
	var shoulder := v.bone_world(side + "Arm")
	var to_t := target - shoulder
	var to_f := fist - shoulder
	to_t.y = 0.0
	to_f.y = 0.0
	var turn := to_f.signed_angle_to(to_t, Vector3.UP)
	var need := _need(f, move)
	print("[reach] %s %s %s scale=%.3f sep=%.2f reach=%.2f %s  d=%.2f along=%+.2f up=%+.2f side=%.2f need=%.2f arm=%.2f lat=%+.2f turn=%+.2f yaw=%.2f" % [
		STYLE_NAMES[f.style], move, f.s.body_type, v.body_size.x, separation(), m.reach, f.connects if f.connects != "" else "?",
		d.length(), along, up, lateral, need, _arm(f, side), lat, turn, float(m.get("yaw", STANCE_YAW))])
	for pair: Array in [[fist, Color(1, 0.2, 0.2)], [target, Color(0.2, 1, 0.3)]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = pair[1]
		mat.no_depth_test = true
		mi.material_override = mat
		add_child(mi)
		mi.global_position = pair[0]
		get_tree().create_timer(1.2, true, false, true).timeout.connect(mi.queue_free)


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
