class_name SkaterVisual
extends Node3D
## Skater body: the shared Mixamo skeleton with a team-colored uniform and gear, posed by
## SkaterRig (procedural skating, stick grip) layered over AnimationPlayer clips
## (falls, hit reactions, celebrations).
##
## Top-level node that follows the skater's interpolated transform each frame, so the
## stick (which tracks the interpolated puck) never jitters against the body.

const BODY_TYPES := ["male", "female", "ybot"]
const UNIFORM_SHADER := preload("res://scenes/actors/uniform.gdshader")
const SKIN_SHADER := preload("res://scenes/actors/skin.gdshader")
const GLOVE_SHADER := preload("res://scenes/actors/glove.gdshader")
const RING_SHADER := preload("res://scenes/actors/player_ring.gdshader")
const AIM_SHADER := preload("res://scenes/actors/aim_reticle.gdshader")
const STICK_SHADER := preload("res://scenes/actors/stick.gdshader")
const MeshLod := preload("res://scripts/core/mesh_lod.gd")
## Stick finishes (Skater.stick_style): "X on Y" is X graphics on a Y stick; home / away
## are the club's home and road jersey colors (Skater.club_colors).
const STICK_STYLES := ["wood", "black", "black_white", "white_black", "home_away", "away_home"]
const STICK_STYLE_NAMES := ["Plain Wood", "Plain Black", "Black on White", "White on Black", "Home on Away", "Away on Home"]
## Blade tape (Skater.stick_tape): round the middle of the blade, heel and toe bare.
const TAPES := ["white", "black", "team", "none"]
const TAPE_NAMES := ["White", "Black", "Team Color", "No Tape"]
const STICK_WHITE := Color(0.93, 0.93, 0.91)
const STICK_BLACK := Color(0.05, 0.05, 0.06)
## Skin tones to pick from (sRGB), light to dark. The player editor (M7) will set them.
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.80, 0.69), Color(0.91, 0.73, 0.60), Color(0.82, 0.62, 0.47),
	Color(0.68, 0.48, 0.33), Color(0.50, 0.34, 0.23), Color(0.34, 0.22, 0.15),
]
const SKATE_LIFT := 0.08          ## skate blade height under the boot (tools/blender/skate_gear.py SOLE)
## Hair and facial hair, the project's own (tools/blender/hair_gear.py via
## tools/build_hair.gd): meshes in head space, built per body ("<id>", "<id>_female") and
## for under a helmet ("..._helm"), tinted per player.
const HAIR_DIR := "res://assets/characters/hair/"
const HAIR_STYLES := ["buzz", "fade", "messy", "quiff", "part", "slick", "curly", "afro", "mop", "shaggy",
		"flow", "mullet", "mohawk", "balding", "topknot", "ponytail", "braid", "long", "bob"]
const HAIR_WOMEN := ["braid", "long", "bob"]   ## styles only women wear
const HAIR_MEN := ["balding"]                  ## ...and only men
const FACIAL_HAIR := ["beard", "playoff", "chinstrap", "chops", "goatee", "moustache", "horseshoe",
		"handlebar", "soulpatch"]              ## men only
## How often random_look picks each style, men and women ("" = bare: nobody is, hair shows
## when the helmet comes off). On darker skin tones HAIR_DARK_LEAN multiplies these.
const HAIR_ODDS_MEN := {"messy": 3.0, "flow": 3.0, "quiff": 2.5, "buzz": 2.0, "shaggy": 2.0, "part": 2.0,
		"mop": 1.5, "mullet": 1.5, "slick": 1.5, "curly": 1.5, "fade": 1.5, "balding": 0.8, "afro": 0.5,
		"ponytail": 0.4, "topknot": 0.4, "mohawk": 0.3}
const HAIR_ODDS_WOMEN := {"ponytail": 4.0, "braid": 3.0, "long": 3.0, "bob": 2.0, "flow": 1.5, "shaggy": 1.5,
		"curly": 1.2, "mop": 1.0, "messy": 1.0, "topknot": 1.0, "slick": 0.8, "part": 0.5, "mullet": 0.5,
		"afro": 0.4, "quiff": 0.4, "buzz": 0.3, "fade": 0.2, "mohawk": 0.2}
const HAIR_DARK_LEAN := {"afro": 6.0, "fade": 3.0, "curly": 2.5, "buzz": 1.5, "flow": 0.3, "mop": 0.3,
		"shaggy": 0.3, "part": 0.3, "quiff": 0.3, "mullet": 0.3, "long": 0.4, "bob": 0.4}
## Men's facial hair: [id, share of players]; the rest are clean shaven.
const FACIAL_ODDS := [["beard", 0.13], ["goatee", 0.08], ["moustache", 0.08], ["playoff", 0.05],
		["chinstrap", 0.05], ["chops", 0.03], ["horseshoe", 0.03], ["handlebar", 0.03], ["soulpatch", 0.02]]
const HAIR_COLORS: Array[Color] = [
	Color(0.05, 0.04, 0.035), Color(0.13, 0.08, 0.05), Color(0.26, 0.16, 0.09),
	Color(0.42, 0.29, 0.17), Color(0.74, 0.58, 0.36), Color(0.48, 0.2, 0.09), Color(0.55, 0.53, 0.5),
]
## Eye colors (sRGB): dark brown, brown, hazel, amber, green, gray, blue, light blue.
const EYE_COLORS: Array[Color] = [
	Color(0.2, 0.11, 0.06), Color(0.34, 0.2, 0.09), Color(0.45, 0.34, 0.16), Color(0.58, 0.38, 0.12),
	Color(0.27, 0.44, 0.24), Color(0.46, 0.5, 0.53), Color(0.22, 0.42, 0.7), Color(0.45, 0.63, 0.82),
]
const CELEBRATIONS := ["fist_pump", "cheering", "cheering_1", "rallying"]
## Off the ice: looping idles on the bench seat / standing at the boards, and the
## one-off reactions (bench_react) by kind, seated and standing.
const SIT_LOOPS := ["sitting", "sitting_2", "sitting", "sitting_2", "sitting_talking"]
const STAND_LOOPS := ["holding_idle"]
const REACTIONS := {
	"cheer": [["sitting_clap", "sitting_clap_2", "sitting_fist_pump", "sitting_yell", "sitting_yell_2", "cheering_while_sitting"],
			["standing_clap", "fist_pump", "cheering"]],
	"groan": [["sitting_disbelief", "sitting_disapproval", "sitting_angry"], ["angry_gesture"]],
	"sulk": [["sitting_angry", "sitting_disapproval", "sitting_rubbing_arm"], ["angry_gesture"]],
	"laugh": [["sitting_laughing", "sitting_clap_2"], ["standing_clap"]],
}

var skater: Skater
var model: Node3D                 ## yaw / lean pivot at the skater's feet
var body: Node3D                  ## instanced body (Mixamo faces +Z, so turned around)
var skel: Skeleton3D
var rig: SkaterRig
var anim: AnimationPlayer
var shaft: MeshInstance3D
var blade: MeshInstance3D
var ring: MeshInstance3D
var marker: MeshInstance3D
var spray: CPUParticles3D

var _yaw := 0.0
var _lean := 0.0
var _crouch := 0.0
var _bend := 0.3
## Ready stance with the stick: the shoulders dip (side bend) and turn toward the blade
## side, so the bottom hand reaches the shaft low on that side (rad). On top of that the
## bottom shoulder dips as far as the bottom hand needs to reach its grip (_dip).
var stance_sway := 0.05
var stance_twist := 0.1
var stance_bend := 0.82   ## forward bend of the spine in the ready stance (rad)
## Each push of the stride: the hips sink this far (m) and the chest pumps forward this
## much (rad) at full stride; the shoulders turn against the legs (counter_twist, rad) as
## the hips turn with them (hip_turn, rad).
var stride_bob := 0.035
var stride_pump := 0.07
var counter_twist := 0.2
var hip_turn := 0.12
var _dip := 0.0
var windup_arc_end := 120.0     ## degrees around from straight ahead the blade swings back
var windup_arc_reach := 0.9     ## its distance out from the body at the top (m, flat)
var windup_arc_height := 1.9    ## its height at the top (m)
var _follow_hold := 0.0
var _swing_charge := 0.0   ## the slap shot's charge at release (the downswing starts there)
var dip_max := 0.15      ## most the bottom shoulder dips past stance_sway to reach (rad)
var dip_lean := 0.0     ## the dip also leans the chest forward this much of it (over the shaft)
var _twist := 0.0
## Hit reactions: a sprung tilt of the whole body (model pitch, roll; rad) kicked by each
## hit taken, so the impact shows the same frame, before any clip blends in.
var _jolt := Vector2.ZERO
var _jolt_v := Vector2.ZERO
var _seen_hit := 10.0
var _fight_mode := false   ## set_fight_mode: fights keep the pelvis over the feet too
## Checking: 0..1 pose weights. The load (coiled into the hit), the drive up and through
## it, and the stumble forward after one that hit nothing. `_check_size` scales the drive
## by what the hit did; `_check_tilt` is the whole body's pitch and roll for it (rad).
var _check_load := 0.0
var _check_drive := 0.0
var _check_whiff := 0.0
var _check_size := 1.0
var _check_tilt := Vector2.ZERO
var _seen_landed := 10.0
## Board battles: 0..1 pose weights for the one pinning and the one pinned, the pitch
## and roll for it, the last jostle shown, and where the puck lay and which side the
## pinner stood (kept for the ease out, once the battle is gone).
var _pin_w := 0.0
var _pinned_w := 0.0
var _pin_tilt := Vector2.ZERO
var _seen_bump := 0
var _pin_puck := Vector3.ZERO
var _pin_side := 1.0
var _stride := 0.0
var _stride_amt := 0.0
var _free_arm := 0.0
var _blade := Vector3.ZERO        ## blade position relative to the skater
var _marker_on := false
var _pass_mark: Node3D            ## under the teammate a pass would go to (human carrier only)
var _pass_mark_mat: StandardMaterial3D
var _aim_mark: Node3D             ## on the goal mouth: where a shot would go (human carrier near the net)
var _aim_mark_mat: ShaderMaterial
var _aim_pos := Vector3.INF
var _tag: Label3D
var _ring_mat: ShaderMaterial    ## the ring's sprint (outer), legs (inner) and slap-shot (middle) meters
var _name_tag: Label3D           ## the controlled player's number and name, above the P tag
var _prev_state := -1
var _was_stopping := false
var _stride_half := 0

# Clip layer: which regions (legs, spine, arms) the current clip owns and for how long.
var _clip := ""
var _clip_regions := Vector3.ZERO
var _clip_left := 0.0
var _clip_w := Vector3.ZERO
var _clip_fade := 6.0
## Fights: extra body yaw (rad) on top of the heading, to square a bladed stance up to
## the opponent.
var yaw_offset := 0.0
var roll_offset := 0.0   ## fights: sideways tilt (rad) while slipping a punch
var hold_breath := 0.0   ## fights: SkaterRig.breath over a held one-frame pose (the guard)

static var _materials := {}
static var _visor: StandardMaterial3D
## Helmet models (tools/blender/helmet_gear.py via tools/build_gear.gd), picked by
## Skater.gear_style: A modern two-piece, B classic one-piece. Surfaces: 0 shell, 1 trim, 2 dark
## (straps, liner, ear surrounds), 3 visor, 4 visor clips (3 and 4 only with Skater.visor).
## Both are modeled on the male head with their origin at its head box center: the crown
## HELMET_CROWN above it, HELMET_HEAD_W the head's width. Every body's helmet is scaled by
## its head width and set on its crown, which also lands the chin strap under its chin
## (both bodies' crown-to-chin heights follow their head widths).
const HELMETS := [
	{"mesh": preload("res://assets/characters/helmet.res")},
	{"mesh": preload("res://assets/characters/helmet_b.res")},
	{"mesh": preload("res://assets/characters/helmet_c.res")},   # C: the round '80s bucket (the Pro Shop's)
]
const HELMET_ROLLS := 2   ## a rolled gear_style (league players) only ever gives one of the first two
## Face gear worn on the helmet in place of its visor (Skater.face_gear; the Pro Shop's
## "Cage & Full Shield"): one mesh per helmet, in that helmet's frame, hung on it as a
## child so it comes off with the helmet. Surfaces: cage 0 the wire, 1 its dark clips and
## chin cup; shield 0 the clear shield (tinted as a visor is), 1 its dark fittings.
const FACE_GEAR := {
	"cage": [preload("res://assets/characters/face_cage_a.res"), preload("res://assets/characters/face_cage_b.res"),
			preload("res://assets/characters/face_cage_c.res")],
	"shield": [preload("res://assets/characters/face_shield_a.res"), preload("res://assets/characters/face_shield_b.res"),
			preload("res://assets/characters/face_shield_c.res")],
	# The Grays' signature gear: a pair of great black slanted eyes, a bulging mirrored lens
	# over each of the player's own (0 the lenses, 1 the bar over the nose and the clips).
	"alien": [preload("res://assets/characters/face_alien_a.res"), preload("res://assets/characters/face_alien_b.res"),
			preload("res://assets/characters/face_alien_c.res")],
}
## Visor tints (Skater.visor_tint; the Pro Shop's "Tinted Visors"): a see-through color and
## its roughness, or for the mirrors the color seen straight on and the one it turns to
## at a glancing angle (visor_mirror.gdshader).
const VISOR_TINTS := {
	"": {"color": Color(0.55, 0.65, 0.75, 0.35), "rough": 0.1},
	"smoke": {"color": Color(0.05, 0.055, 0.065, 0.74), "rough": 0.08},
	"amber": {"color": Color(0.96, 0.6, 0.1, 0.46), "rough": 0.08},
	"mirror": {"mirror": [Color(0.2, 0.48, 0.95), Color(0.72, 0.3, 0.9)]},
	"gold": {"mirror": [Color(0.98, 0.7, 0.16), Color(0.95, 0.24, 0.08)]},
}
const VISOR_MIRROR_SHADER := preload("res://scenes/actors/visor_mirror.gdshader")
const SHIELD_MIRROR_LOW := -0.028   ## the full shield's mirror band ends here (about where a visor's bottom edge is)
const HELMET_CROWN := 0.1447
const HELMET_HEAD_W := 0.1939
## Skater.gear_style for a player who didn't choose their gear: GEAR_ROLL plus a random
## number. Helmets take it modulo their count; goalies weigh their masks with it
## (GoalieVisual.mask_index). Below GEAR_ROLL it is a created player's own choice.
const GEAR_ROLL := 1000


static func gear_roll(r: int) -> int:
	return GEAR_ROLL + r % 2000   # (even, so the helmet a roll gives is r % 2 as it always was)
## Team masks worn instead of the helmet (Teams.HEADGEAR_OF; tools/blender/mask_gear.py via
## tools/build_gear.gd), by body type, modeled in the helmets' frame on the male head.
## "lucha": luchador hoods, A full, B open below the nose, C crested (surfaces 0 hood,
## 1 crest), each also fitted to the female head; each player's cut, pattern and color
## order come from their name and number. "vintage": an old-school fiberglass goalie face
## mask (0 shell, 1 chevrons, 2 straps), goalies too. A body with no set of its own wears
## the male's.
const TEAM_MASKS := {
	"lucha": {
		"male": [preload("res://assets/characters/lucha_a.res"), preload("res://assets/characters/lucha_b.res"),
				preload("res://assets/characters/lucha_c.res")],
		"female": [preload("res://assets/characters/lucha_a_female.res"), preload("res://assets/characters/lucha_b_female.res"),
				preload("res://assets/characters/lucha_c_female.res")],
	},
	"vintage": {"male": [preload("res://assets/characters/vintage_mask.res")]},
}
## Hats (Teams.HEADGEAR_OF, Skater.headgear; tools/blender/hat_gear.py via
## tools/build_gear.gd): head gear that isn't a mask. A hat is set on the crown as a helmet
## is, by the head's width, and it comes off in a fight as a helmet does. Under it the
## player's whole hairstyle shows, cut off at the hat's edge (hat_hair.gdshader): `edge` is
## that edge as a plane in the helmets' frame, the height at z = 0 and its rise per meter
## toward the face (a little under the real edge, so no hair comes through just above it).
##   "florida"  Florida Man's ball cap, worn backwards (0 crown in the jersey color, 1 bill,
##              button, seams and strap in the trim color), with wraparound sunglasses
##              (`eyes`: 0 frame, 1 mirrored lens) set on the eyes and hung on the cap, so
##              they come off with it
##   "cowboy"   a cowboy hat (0 felt, 1 the band in the jersey color)
##   "stunt"    the Stuntmen's open-face stunt helmet: a deep round shell over the ears and
##              the nape, the face open (0 the shell, flame-painted in the team's colors:
##              flame_material; 1 the peak and its snaps; 2 the edge, liner and strap)
##   "watch"    the Whalers' knit fisherman's watch cap: a ribbed crown and a deep folded
##              cuff, worn over the tops of the ears (0 the knit in the jersey color, 1 a
##              stripe round the cuff in the trim color)
##   "beanie"   a winter knit beanie: a tall ribbed crown, a deep cuff down over the tops
##              of the ears, a pom on top (0 the knit in the jersey color, 1 two stripes
##              round the crown and the pom in the trim color)
##   "leather"  an old leather helmet, as football players wore: a padded band round the
##              head with straps over the crown, a flap over each ear, a chin strap
##              (LEATHER_HELMET: 0 the hide, 1 the darker padding, binding and strap, 2 the
##              ear holes); it comes with the Old-Time Set
##   "guard"    a leather head guard, the hockey helmet of the same years: a broad band
##              of stiff leather round the head with a short tab over each ear, a felt
##              lining, a cross of padded leather straps over the top of the head and
##              nothing between them, a thin chin strap (GUARD_HELMET: 0 the leather,
##              1 the felt and the stitching, 2 the chin strap and rivets). The hair shows
##              below the band, and pressed flat in the open crown (`crown`). With the
##              Old-Time Set too
##   "golf"     the Sweet Tea's golf visor: a band round the head, a tall panel in front
##              and a strap behind, with a see-through tinted bill (0 the band in the
##              jersey color, 1 the bill, brim_material in the trim color, 2 the piping and
##              the tab at the back in the trim color). The top of the head is open:
##              `open` is the band's upper edge, a plane as `edge` is, and the hair shows
##              again above it
const HATS := {
	"florida": {"mesh": preload("res://assets/characters/hat_cap.res"), "eyes": preload("res://assets/characters/hat_shades.res"),
		"edge": Vector2(0.052, 0.07)},   # (low across the forehead: a fringe cut at the strap was a row of scraps in the opening)
	"cowboy": {"mesh": preload("res://assets/characters/hat_cowboy.res"), "edge": Vector2(0.068, 0.0)},
	# (its edge is far from level: the hair is cut at the height of its back and sides, so
	# none shows in the face opening either)
	"stunt": {"mesh": preload("res://assets/characters/hat_stunt.res"), "edge": Vector2(-0.058, 0.0)},
	# (its edge slopes: across the forehead in front, low on the back of the skull)
	"watch": {"mesh": preload("res://assets/characters/hat_watch.res"), "edge": Vector2(0.047, 0.14)},
	"beanie": {"mesh": preload("res://assets/characters/hat_beanie.res"), "edge": Vector2(0.023, 0.27)},
	# (cut at the height of its back, above the flaps: none shows in the face opening)
	"leather": {"mesh": preload("res://assets/characters/hat_leather.res"), "edge": Vector2(0.0, 0.0)},
	# (its band's lower edge: hat_gear.py GUARD_RIM)
	"guard": {"mesh": preload("res://assets/characters/hat_guard.res"), "edge": Vector2(0.051, 0.12), "crown": true},
	"golf": {"mesh": preload("res://assets/characters/hat_golf.res"), "edge": Vector2(0.054, 0.12), "open": Vector2(0.0925, 0.238)},
}
const HAT_CLOSED := Vector2(1000.0, 0.0)   ## `open` for a hat with a crown: no hair shows above it
const LEATHER_HELMET := [Color(0.5, 0.32, 0.17), Color(0.29, 0.175, 0.09), Color(0.05, 0.035, 0.03)]
const BALD_ON_TOP := ["balding"]   ## hairstyles with a bare crown: no scalp cap in an open crown
const GUARD_HELMET := [Color(0.42, 0.21, 0.11), Color(0.84, 0.78, 0.62), Color(0.17, 0.1, 0.06)]
const FLAME_SHADER := preload("res://scenes/actors/flame_paint.gdshader")
const HAT_HAIR_SHADER := preload("res://scenes/actors/hat_hair.gdshader")
## Cosmetics: small extras, each in its own slot, worn with whatever else the player has
## on. A skater's own choice (Skater.helmet_crest / eye_fx / dangler), else the team's (its
## uniform's `crest` / `eye_fx` / `dangler`): cosmetic(). The Chupacabras wear one of each.
##   CRESTS    on top of the helmet, one mesh per helmet (HELMETS order), hung on it like
##             the face gear: "spines", a ridge of spines from the brow to the nape, in the
##             trim color. Only on a helmet (not a hat, a mask or a goalie's mask).
##   EYE_FX    the eyes: "red", glowing red: a glow on each of the body's own eyes
##             (eye_glow.gdshader) and a small red light in front of the brow that reddens
##             the face round them. On the head, not the helmet: anyone can have them,
##             whatever they wear, and they stay when the helmet comes off.
##   DANGLERS  hung under the visor, one mesh per helmet: "fangs", two long canines either
##             side of the nose. A skater with no visor is given one to hang them from;
##             with a cage or a full shield there is nowhere to hang them. (The slot a
##             goalie's throat dangler will share, hung under the mask.)
const CRESTS := {
	"spines": [preload("res://assets/characters/crest_spines_a.res"), preload("res://assets/characters/crest_spines_b.res"),
			preload("res://assets/characters/crest_spines_c.res")],
}
const DANGLERS := {
	"fangs": {"color": Color(0.93, 0.9, 0.8), "meshes": [preload("res://assets/characters/dangler_fangs_a.res"),
			preload("res://assets/characters/dangler_fangs_b.res"), preload("res://assets/characters/dangler_fangs_c.res")]},
}
const EYE_FX := {"red": Color(1.0, 0.06, 0.03)}
const EYE_GLOW_SHADER := preload("res://scenes/actors/eye_glow.gdshader")
const COWBOY_FELT := Color(0.72, 0.59, 0.4)
const SHADES_MIRROR := [Color(0.98, 0.5, 0.1), Color(0.95, 0.25, 0.55)]   ## the sunglasses' lens: sunset orange turning pink
## Hood patterns (lucha_mask.gdshader: red accent 1, green accent 2, blue accent 3). New
## ones are painted over assets/characters/masks/lucha_uv_guide.png and added here.
const LUCHA_PATTERNS := [
	preload("res://assets/characters/masks/lucha_clasico.png"),
	preload("res://assets/characters/masks/lucha_alas.png"),
	preload("res://assets/characters/masks/lucha_dividido.png"),
	preload("res://assets/characters/masks/lucha_rayo.png"),
]
const LUCHA_SHADER := preload("res://scenes/actors/lucha_mask.gdshader")
## The male eyes' center in the masks' frame: masks are set on each body's eyes, scaled
## by its eyes-to-crown height (and across by its head width).
const MASK_EYE := Vector3(0.0, 0.0255, 0.0747)
## The vintage mask's colors: an aged white shell, red chevrons, black straps.
const VINTAGE_COLORS := [Color(0.9, 0.86, 0.74), Color(0.68, 0.08, 0.07), Color(0.05, 0.05, 0.05)]
static var _no_visor := {}   ## helmet mesh -> the same without its visor surfaces
const STICK_MESH := preload("res://assets/characters/stick.res")
const SKATE_MESH := preload("res://assets/characters/skate.res")
const GLOVE_MESH := preload("res://assets/characters/glove.res")   ## a right glove, origin at the wrist, sized for 1.8 m
const CUFF_MESH := preload("res://assets/characters/glove_cuff.res")   ## the glove's cuff: rides the forearm, not the hand
const FIST_MESH := preload("res://assets/characters/fist.res")     ## a bare right fist for fights, same axes as the glove
## The Old-Time Set (the Pro Shop's "gear_oldtime"): a wooden stick, leather gauntlets and
## leather boots on tube frames, each laid out as the modern piece it replaces (the same
## Blender scripts' build_old), plus playing bare-headed. A skater wears a piece when their
## own style says OLD (Skater.glove_style / skate_style; goalies pad_style) or, with none
## of their own, when their team's uniform has `kit` = OLD (Create Team); see old_time().
const OLD := "old"
## Leg wear (dress_legs): a player's own (Skater.sock_style / pants_style) or the team's.
## Taped socks are anyone's; long pants are the Pro Shop's "gear_longpants" (a uniform's
## `pants_style` puts a whole team in them). The old-time kit's wool socks and canvas pants
## are OLD, like its other pieces.
const SOCKS_TAPED := "taped"
const PANTS_LONG := "long"
const NO_HELMET := "none"         ## head gear (Skater.headgear / a uniform's `headgear`): nothing on the head
const STICK_OLD := "oldtime"      ## Skater.stick_style for the wooden stick (kept out of STICK_STYLES: generated players don't roll it)
const STICK_OLD_NAME := "Old-Time Wood"
const STICK_OLD_MESH := preload("res://assets/characters/stick_old.res")
const SKATE_OLD_MESH := preload("res://assets/characters/skate_old.res")   ## 0 the boot, 1 the tube frame and runner
const GLOVE_OLD_MESH := preload("res://assets/characters/glove_old.res")
const CUFF_OLD_MESH := preload("res://assets/characters/glove_cuff_old.res")
## Leather (leather_material): the gauntlets' tan and darker palm (their bound rim is the
## team's color); the skates' tan, their dark toe cap, heel and quarters, cream laces.
const LEATHER_GLOVE := [Color(0.62, 0.42, 0.23), Color(0.4, 0.26, 0.14)]
const LEATHER_SKATE := [Color(0.6, 0.4, 0.21), Color(0.25, 0.15, 0.08), Color(0.9, 0.87, 0.78)]
const SKATE_LEN := 0.34        ## skate length for a 1.8 m body (the model's own: tools/blender/skate_gear.py)
const GLOVE_SLEEVE := 0.05     ## how far short of the wrist the sleeve ends inside the glove's cuff (1.8 m body)
const GLOVE_SLEEVE_OLD := 0.1  ## ... inside the old-time gauntlet's longer, narrower cone (it poked through nearer the wrist)
const CANVAS_SLIM := Vector2(0.96, 0.9)   ## canvas pants against the padded shell: the hips' width, the thighs'
const SKATE_SOCK := 0.25      ## where the sock ends on the skate model, above the ice: just over the boot's collar
const DIGITS := preload("res://assets/characters/digits.png")   ## tools/build_digits.gd
const DIGIT_FILL := 0.84        ## share of a digit-sheet cell's height the digit fills
const LETTERS := preload("res://assets/characters/letters.png")   ## tools/build_letters.gd
const LETTER_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZÉÑÔÚÛÁÍÓÜ0123456789-'.!"   ## the sheet's cells, in order
const NUMBER_LOWER := 0.15       ## m the back number sits below where it used to (room for the name)
const NAME_HEIGHT := 0.056       ## nameplate cap height for a 1.8 m body
const NAME_GAP := 0.012          ## m between the nameplate and the top of the number
const NAME_MAX_W := 0.24        ## widest nameplate (longer names are squeezed to fit): kept
                                 ## off the back's sides, where the print fades with the curve
const NICKNAME_MAX := 8          ## nicknames this short go on the back instead of the last name
const NUMBER_HEIGHT := 0.24     ## back number height for a 1.8 m body
const CREST_WIDTH := 0.34       ## jersey crest box width for a 1.8 m body (the widest a crest gets)
const CREST_MAX_H := 0.9         ## ...and its height, as a share of that width
const CREST_INK := 0.6           ## the logo's own (opaque) area, as a share of the box: crests of
                                 ## any shape come out the same visual size, inside the box
const STICK_PUCK := 0.16       ## where on the blade the puck sits, from the heel corner (m): mid-blade
const GRIP_OFFSET := 0.065     ## wrist to the glove's knuckle line, for a 1.8 m body...
const GRIP_PALM := 0.05        ## ...and in toward the palm to the middle of the fist
var stance_blade_forward := 0.8   ## the ready stance's blade without the puck (m ahead, 1.8 m body)
var stance_blade_side := 0.55       ## ...and out to the forehand side
const FOLLOW_HOLD := 0.35     ## seconds the drawn stick keeps the finish after the shot state ends
const FOLLOW_IMPACT := 0.45   ## share of the follow-through the blade spends down on the ice at the puck
static var _bodies := {}
var _gloves: Array[Node3D] = []   ## glove meshes (hidden in a fight)
var _cuffs: Array[Node3D] = []    ## glove cuffs on the forearms (hidden in a fight)
var _fists: Array[Node3D] = []    ## bare fist meshes (shown in a fight)
## Menus: a standing display pose instead of the ready stance ("" = none), from
## DISPLAY_POSES (anyone) or FEMALE_POSES (women only); see DISPLAY_SPEC.
var display_pose := ""
var bench_loop := ""        ## parked on the bench / in the box: the idle clip looping ("" = playing)
var bench_seated := false
## On the bench or in the box and off screen: the idle loop, the rig and the face hold
## still (nobody can see them) so the skeleton isn't re-posed and re-skinned every frame.
var bench_frozen := false
var _onscreen: VisibleOnScreenNotifier3D
var display_lift := 0.0   ## menus: m the player stands above the ice
const DISPLAY_POSES := ["side", "middle", "rest", "lean", "across", "shoulders"]
const FEMALE_POSES := ["hips", "hips_b"]
var _disp_top := Vector3.ZERO     ## the pose's stick: butt end, heel and blade direction (local)
var _disp_heel := Vector3.ZERO
var _disp_out := Vector3.ZERO
var _disp_age := 0.0                   ## s in the current display pose
var _disp_chest_ref := Transform3D()   ## the chest (local) once the pose settled; "fixed" sticks follow it from there
var _helmet: MeshInstance3D       ## on the Head bone; comes off for fights (take_off_helmet)
var _mask := ""                   ## a team mask worn instead of the helmet (TEAM_MASKS key); stays on in fights
var _helmet_rest: Transform3D     ## its place on the head
var _hair_helm: Array[Node3D] = []   ## hairstyle pressed flat under the helmet
var _hair_full: Array[Node3D] = []   ## ...and as modeled (helmet off)
var face: FaceRig                 ## eyes, lids, brows, jaw (null for bodies without a face)
## Taking the helmet off (the "focus" clip, both hands on the helmet): seconds into it,
## -1 = not happening. The right hand takes it at HELMET_LIFT, lets go at HELMET_DROP;
## then it falls to the ice.
var _helmet_t := -1.0
var _helmet_vel := Vector3.ZERO
var _helmet_spin := Vector3.ZERO
var _helmet_pts := PackedVector3Array()   ## a sample of its vertices (landing on the ice)
const HELMET_CLIP := "focus"
const HELMET_FROM := 0.6      ## clip seconds skipped (the hands are already up)
const HELMET_SPEED := 2.6
## The moments below are clip seconds (lift 2.25, let go 2.78, done 3.15) turned into
## real seconds at HELMET_SPEED, so changing the speed keeps the hand and helmet in step.
const HELMET_LIFT := (2.25 - HELMET_FROM) / HELMET_SPEED   ## s: the hands come off the head, the helmet with the right one
const HELMET_DROP := (2.78 - HELMET_FROM) / HELMET_SPEED   ## s: let go
const HELMET_END := (3.15 - HELMET_FROM) / HELMET_SPEED    ## s: the clip fades out (about 1 s)
var _print_mats: Array[ShaderMaterial] = []    ## this player's own copies of the uniform material (_print_materials)
var _print_extra: Array[MeshInstance3D] = []   ## chest bulk under a jersey with no model of its own: printed on like it
static var _numbers := {}         ## "number|fill|outline" -> ImageTexture
static var _crest_ink := {}       ## crest texture path -> share of it that is opaque
static var _names := {}           ## "NAME|fill|outline" -> [ImageTexture, cap height share]
static var _letter_sheet: Image
static var _letter_spans := {}    ## char -> [x0 in the sheet, width]
static var _cap_rows := Vector2i.ZERO   ## the sheet rows a capital letter fills (top, bottom)
var hs := 1.0                     ## body height / 1.8 m, scales gear offsets
var body_size := Vector2(1.0, 0.0)   ## BodyBuild.size_for: [height scale, build]


# --- Build -----------------------------------------------------------------------

func build(sk: Skater) -> void:
	skater = sk
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_body()
	_build_gear()
	dress_legs()
	_build_stick()
	_build_markers()
	# Simpler copies of every piece for when the player is small on screen (MeshLod).
	MeshLod.apply(self)
	_onscreen = VisibleOnScreenNotifier3D.new()
	_onscreen.aabb = AABB(Vector3(-0.9, -0.2, -0.9), Vector3(1.8, 2.6, 1.8))
	add_child(_onscreen)
	snap()


func _build_body() -> void:
	model = Node3D.new()
	add_child(model)
	var assets := body_assets(skater.body_type)
	body = (assets[0] as PackedScene).instantiate()
	hs = float(body.get_meta("height", 1.8)) / 1.8
	# Height scales the whole body evenly (skates included, so the lift goes with it);
	# weight sets the build (BodyBuild).
	body_size = BodyBuild.size_for(skater.body_type, skater.height_m, skater.weight_kg)
	body.rotation.y = PI
	body.scale = Vector3.ONE * body_size.x
	body.position.y = SKATE_LIFT * body_size.x
	model.add_child(body)
	skel = body.get_node("Skeleton3D")
	var c := team_colors()
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", false, false):
		if mi.name == "Eyes":
			mi.material_override = eye_material(body)
		elif mi.name.begins_with("Outfit_"):
			mi.mesh = BodyBuild.with_build(mi.mesh, skel, mi.skin)
			mi.material_override = uniform_material(c, 0.8 if mi.name.ends_with("Alpha_Joints") else 1.0)
		else:
			mi.material_override = skin_material(body, skater.skin_tone)
	face = FaceRig.create(self)
	BodyBuild.apply(skel, body_size.y)
	anim = AnimationPlayer.new()
	body.add_child(anim)
	anim.add_animation_library("", assets[1])
	rig = SkaterRig.new()
	skel.add_child(rig)
	rig.modification_processed.connect(_after_rig)


## A helmet mesh with only its first three surfaces (no visor or visor clips), cached.
static func without_visor(m: Mesh) -> Mesh:
	if not _no_visor.has(m):
		var out := ArrayMesh.new()
		for s in mini(3, m.get_surface_count()):
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s))
		_no_visor[m] = out
	return _no_visor[m]


## The visor's material for a tint (VISOR_TINTS; "" = clear), or with `full` the full
## shield's: the same, but a mirror is coated only in a band over the eyes (below
## SHIELD_MIRROR_LOW, a height in the helmets' frame, it stays clear).
static func visor_material(tint := "", full := false) -> Material:
	if not VISOR_TINTS.has(tint):
		tint = ""
	if tint == "" and _visor != null:
		return _visor
	var spec: Dictionary = VISOR_TINTS[tint]
	var key := "visor|%s|%s" % [tint, full and spec.has("mirror")]
	if _materials.has(key):
		return _materials[key]
	var out: Material
	if spec.has("mirror"):
		var sm := ShaderMaterial.new()
		sm.shader = VISOR_MIRROR_SHADER
		sm.set_shader_parameter("face_color", spec.mirror[0])
		sm.set_shader_parameter("edge_color", spec.mirror[1])
		sm.set_shader_parameter("clear_below", SHIELD_MIRROR_LOW if full else -1000.0)
		out = sm
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = spec.color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = spec.rough
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		out = m
	# After the brows (FaceRig draws them at priority 1, over the skin), so the
	# shield tints them like the rest of the face behind it.
	out.render_priority = 2
	_materials[key] = out
	if tint == "":
		_visor = out as StandardMaterial3D
	return out


## The alien visor's lenses: a black mirror (visor_mirror.gdshader: near black face on, a
## cold blue sheen at a glancing angle and where it would catch the lights).
static func alien_lens_material() -> ShaderMaterial:
	if not _materials.has("alien"):
		var m := ShaderMaterial.new()
		m.shader = VISOR_MIRROR_SHADER
		m.set_shader_parameter("face_color", Color(0.012, 0.014, 0.02))
		m.set_shader_parameter("edge_color", Color(0.2, 0.36, 0.7))
		m.set_shader_parameter("clear_below", -1000.0)
		m.render_priority = 2
		_materials["alien"] = m
	return _materials["alien"]


## Glowing eyes' material (eye_glow.gdshader) in a color: drawn after a visor, so a dark
## shield doesn't dim them.
static func eye_glow_material(color: Color) -> ShaderMaterial:
	var key := "eyeglow|" + color.to_html()
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = EYE_GLOW_SHADER
		m.set_shader_parameter("color", color)
		m.render_priority = 3
		_materials[key] = m
	return _materials[key]


static var _quad: QuadMesh

## A 1 x 1 quad (the eye glows: sized by their node, turned to the camera by their shader).
static func _unit_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## The HELMETS index a gear_style stands for: a created player's own choice, or for a
## roll (gear_roll) one of the first HELMET_ROLLS, as it always was.
static func helmet_index(gear_style: int) -> int:
	if gear_style >= GEAR_ROLL:
		return gear_style % HELMET_ROLLS
	return posmod(gear_style, HELMETS.size())


## [PackedScene, AnimationLibrary] for a body type built by tools/build_characters.gd.
static func body_assets(kind: String) -> Array:
	if not _bodies.has(kind):
		var scene := "res://assets/characters/body_%s.scn" % kind
		if not ResourceLoader.exists(scene):
			return body_assets("ybot") if kind != "ybot" else []
		_bodies[kind] = [load(scene), load("res://assets/characters/anims_%s.res" % kind)]
	return _bodies[kind]


## Rest position of a bone in body space (+Z forward, +X = the character's left).
func bone_pos(bone: String) -> Vector3:
	return skel.get_bone_global_rest(skel.find_bone(bone)).origin


## Where a bone is now, in world space (as last posed).
func bone_world(bone: String) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin


## Where a bone is drawn right now, in world space: what's attached to it follows the pose
## the rig finished the frame with, which bone_world misses (a goalie's crouch: the
## creators' close-ups were aimed over the goalie's head).
func bone_shown(bone: String) -> Vector3:
	for c in skel.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == bone:
			return (c as BoneAttachment3D).global_position
	return bone_world(bone)


## Mesh-based gear anchor from the build step ("head", "chest", "hips"): the AABB of
## the vertices that belong to it. Falls back to a box around the bone.
func anchor_box(anchor: String, bone: String, size: Vector3) -> AABB:
	if body.has_meta(anchor + "_box"):
		return body.get_meta(anchor + "_box")
	return AABB(bone_pos(bone) - size * 0.5, size)


## Rest frame along a limb: Y from `from` toward `to`, Z as close to forward as possible.
func limb_frame(from: String, to: String, scale := Vector3.ONE) -> Basis:
	var y := (bone_pos(to) - bone_pos(from)).normalized()
	var z := (Vector3.BACK - y * y.dot(Vector3.BACK)).normalized()
	return Basis(y.cross(z), y, z) * Basis.from_scale(scale)


## Uniform palette for a team color. The editors (M7) will set these per team.
## This skater's uniform: the team's palette, or one derived from team_color.
func team_colors() -> Dictionary:
	return skater.uniform if not skater.uniform.is_empty() else uniform_colors(skater.team_color)


## A uniform palette derived from one color (tests and practice; real teams set theirs).
static func uniform_colors(team: Color) -> Dictionary:
	return {
		"jersey": team,
		"trim": Color(0.94, 0.94, 0.92),
		"pants": team.darkened(0.72),
		"gloves": team.darkened(0.35),
		"helmet": team.darkened(0.3),
		"skates": Color(0.05, 0.05, 0.06),
		"number": Color(0.94, 0.94, 0.92),
		"number_outline": team.darkened(0.6),
	}


static func uniform_material(c: Dictionary, darken := 1.0) -> ShaderMaterial:
	var design: String = c.get("design", "classic")
	var accent: Color = c.get("number_outline", Color.BLACK)
	var params := Teams.design_params(c)
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%.2f" % [c.jersey.to_html(), c.trim.to_html(), c.pants.to_html(), c.gloves.to_html(), c.skates.to_html(), accent.to_html(), design, str(params) if c.has("design_params") else "", str(c.get("socks", "")), darken]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = UNIFORM_SHADER
	for k: String in c:
		if c[k] is Color:
			m.set_shader_parameter(k, c[k])
	m.set_shader_parameter("accent_color", accent)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	m.set_shader_parameter("darken", darken)
	_materials[key] = m
	return m


## Glove and cuff material: the team's glove color on the nylon padding, a darker leather
## palm (glove.gdshader; the shading is baked into the model's vertex colors).
static func glove_material(color: Color, trim := Color(0.94, 0.94, 0.92)) -> ShaderMaterial:
	var key := "glove|%s|%s" % [color.to_html(), trim.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLOVE_SHADER
		m.set_shader_parameter("shell", color)
		m.set_shader_parameter("trim", trim)
		# Palm leather: the glove color, darker and a little greyed.
		m.set_shader_parameter("palm", color.darkened(0.45).lerp(Color(0.3, 0.29, 0.28), 0.3))
		_materials[key] = m
	return _materials[key]


## Leather for the Old-Time Set (glove.gdshader with `leather`): `shell` the piece's main
## leather, `dark` its second leather (the model's G channel: palms, toe caps, worn inside
## faces), `trim` its bindings or laces.
static func leather_material(shell: Color, dark: Color, trim: Color) -> ShaderMaterial:
	var key := "leather|%s|%s|%s" % [shell.to_html(), dark.to_html(), trim.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLOVE_SHADER
		m.set_shader_parameter("shell", shell)
		m.set_shader_parameter("palm", dark)
		m.set_shader_parameter("trim", trim)
		m.set_shader_parameter("leather", 1.0)
		_materials[key] = m
	return _materials[key]


## Whether this skater wears the old-time version of a piece: `style` is their own choice
## for it (Skater.glove_style, skate_style or pad_style); with none, the team's kit decides.
func old_time(style: String) -> bool:
	return style == OLD or (style == "" and str(team_colors().get("kit", "")) == OLD)


## What this skater wears on the legs, as uniform.gdshader's `pants_style`: 0 the padded
## shell, 1 old-time canvas, 2 long pants. Their own choice (Skater.pants_style), else the
## team's: its uniform's `pants_style`, or canvas with the old-time kit.
func pants_kind() -> int:
	var own := skater.pants_style
	if own == PANTS_LONG or (own == "" and str(team_colors().get("pants_style", "")) == PANTS_LONG):
		return 2
	return 1 if old_time(own) else 0


## ... and as its `sock_style`: 0 knit, 1 taped, 2 old-time wool.
func sock_kind() -> int:
	if skater.sock_style == SOCKS_TAPED:
		return 1
	return 2 if old_time(skater.sock_style) else 0


## Puts this skater's pants and socks on everything of theirs the uniform is drawn on
## (per instance: the team's material stays shared).
func dress_legs() -> void:
	var pants := float(pants_kind())
	var socks := float(sock_kind())
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader == UNIFORM_SHADER:
			mi.set_instance_shader_parameter("pants_style", pants)
			mi.set_instance_shader_parameter("sock_style", socks)


## The gloves this skater wears: [hand mesh, cuff mesh, material] (a fight drops copies).
func glove_gear() -> Array:
	var c := team_colors()
	if old_time(skater.glove_style):
		return [GLOVE_OLD_MESH, CUFF_OLD_MESH, leather_material(LEATHER_GLOVE[0], LEATHER_GLOVE[1], c.jersey)]
	return [GLOVE_MESH, CUFF_MESH, glove_material(c.gloves, c.trim)]


## Bare-skin material for a built body (its texture, tinted to `tone`).
static func eye_material(body_root: Node) -> StandardMaterial3D:
	var path: String = body_root.get_meta("eye_tex", "")
	var key := "eyes|" + path
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		if path != "":
			m.albedo_texture = load(path)
		m.roughness = 0.15
		_materials[key] = m
	return _materials[key]


static func skin_material(body_root: Node, tone: Color) -> ShaderMaterial:
	var tex_path: String = body_root.get_meta("skin_tex", "")
	var key := "skin|%s|%s" % [tex_path, tone.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SKIN_SHADER
	if tex_path != "":
		m.set_shader_parameter("skin_tex", load(tex_path))
		m.set_shader_parameter("has_tex", true)
		var avg: Color = body_root.get_meta("skin_avg", Color(0.6, 0.4, 0.3))
		m.set_shader_parameter("tex_avg", Vector3(avg.r, avg.g, avg.b))
	m.set_shader_parameter("tone", tone)
	_materials[key] = m
	return m


func _build_gear() -> void:
	var c := team_colors()
	var glove: Material = glove_gear()[2]
	var skin := MeshUtil.material(skater.skin_tone, 0.62)
	# Chest and hip bulk wear the uniform material, so the yoke, stripes and fabric carry
	# across them and the jersey layer (see _cloth_mesh).
	var cloth := uniform_material(c)
	# Offsets are relative to the body's own joints (rest pose: +Z forward, +X = left).
	var head := anchor_box("head", "Head", Vector3(0.2, 0.25, 0.22) * hs)
	var gear := head_gear(c)
	if gear == NO_HELMET:
		_build_bare_head(head)
	elif HATS.has(gear):
		_build_hat(head, c, gear)
	elif gear != "":
		_build_team_mask(head, c, gear)
	else:
		_build_helmet(head, c)
	_add_eye_fx(head)
	var chest := anchor_box("chest", "Spine2", Vector3(0.36, 0.2, 0.24) * hs)
	_build_body_gear(c, cloth, glove, skin, chest)


## A hat (HATS) in place of the helmet: fitted and worn as one (it is `_helmet`, and
## `_mask` stays empty), so it comes off in a fight.
func _build_hat(head: AABB, c: Dictionary, gear: String) -> void:
	var spec: Dictionary = HATS[gear]
	var fit: float = head.size.x / HELMET_HEAD_W
	var on := Transform3D(Basis.from_scale(Vector3.ONE * fit),
			Vector3(head.get_center().x, head.end.y - HELMET_CROWN * fit, head.get_center().z))
	var hm := attach("Head", spec.mesh, null, on.origin, on.basis)
	hm.material_override = null
	hm.name = "Helmet"   # tools and views find the head gear by name
	match gear:
		"cowboy":
			hm.set_surface_override_material(0, MeshUtil.material(COWBOY_FELT, 0.9))
			hm.set_surface_override_material(1, MeshUtil.material(c.jersey, 0.7))
		"stunt":
			hm.set_surface_override_material(0, flame_material(c))
			hm.set_surface_override_material(1, MeshUtil.material(Color(0.92, 0.92, 0.9), 0.35))
			hm.set_surface_override_material(2, MeshUtil.material(Color(0.05, 0.05, 0.06), 0.6))
		"watch", "beanie":
			hm.set_surface_override_material(0, MeshUtil.material(c.jersey, 0.97))
			hm.set_surface_override_material(1, MeshUtil.material(c.trim, 0.97))
		"leather":
			hm.set_surface_override_material(0, MeshUtil.material(LEATHER_HELMET[0], 0.55))
			hm.set_surface_override_material(1, MeshUtil.material(LEATHER_HELMET[1], 0.5))
			hm.set_surface_override_material(2, MeshUtil.material(LEATHER_HELMET[2], 0.7))
		"guard":
			hm.set_surface_override_material(0, MeshUtil.material(GUARD_HELMET[0], 0.5))
			hm.set_surface_override_material(1, MeshUtil.material(GUARD_HELMET[1], 0.95))
			hm.set_surface_override_material(2, MeshUtil.material(GUARD_HELMET[2], 0.55))
		"golf":
			hm.set_surface_override_material(0, MeshUtil.material(c.jersey, 0.85))
			hm.set_surface_override_material(1, brim_material(c.trim))
			hm.set_surface_override_material(2, MeshUtil.material(c.trim, 0.7))
		_:
			hm.set_surface_override_material(0, MeshUtil.material(c.jersey, 0.85))
			hm.set_surface_override_material(1, MeshUtil.material(c.trim, 0.8))
	if spec.has("eyes"):
		# The sunglasses: on this body's eyes (the masks' fit), but hung on the hat.
		var sh := MeshInstance3D.new()
		sh.name = "Shades"
		sh.mesh = spec.eyes
		hm.add_child(sh)
		sh.transform = on.affine_inverse() * _eye_fit(head)
		sh.set_surface_override_material(0, MeshUtil.material(Color(0.04, 0.04, 0.045), 0.3))
		sh.set_surface_override_material(1, shades_material())
	_helmet = hm
	_helmet_rest = hm.transform
	_add_hair(head)
	# Under the hat: not the cut pressed flat for a helmet (and its scalp cap), but a copy
	# of the whole hairstyle that ends at the hat's edge. Off comes the hat, and the
	# hairstyle itself shows.
	if spec.get("crown", false):
		# An open crown (the head guard's): there the pressed-flat cut and the scalp cap
		# stay, drawn only over the hat's edge, so they show between the straps and not
		# below the band, where the whole hairstyle does.
		for h in _hair_helm.duplicate():
			var mi := h as MeshInstance3D
			if mi.name == "HairCap" and skater.hair_style in BALD_ON_TOP:
				# (the cap would give a bald crown a full head of hair)
				_hair_helm.erase(h)
				h.queue_free()
			elif mi.name == "HairCap":
				mi.material_override = crown_cap_material(skater.hair_color, spec.edge)
			else:
				mi.material_override = hat_hair_material(skater.hair_style, skater.hair_color, spec.edge, HAT_CLOSED, true)
	else:
		for h in _hair_helm:
			h.queue_free()
		_hair_helm.clear()
	var hair := skel.find_child("Hair_" + skater.hair_style, true, false) as MeshInstance3D
	if hair != null and skater.hair_style != "":
		if not (hair in _hair_full):
			_hair_full.append(hair)
		var under := hair.duplicate() as MeshInstance3D
		under.name = "HairHat"
		under.material_override = hat_hair_material(skater.hair_style, skater.hair_color, spec.edge, spec.get("open", HAT_CLOSED))
		hair.get_parent().add_child(under)
		_hair_helm.append(under)
	_show_hair(true)


## Hair that ends at a hat's edge (hat_hair.gdshader): hair_material's look, with `edge`
## (HATS) turned into a plane in the hair model's space, and `open` into a second one over
## which the hair shows again (a hat open on top). Hair models have their origin on the
## crown and are HELMET_HEAD_W wide to the unit, whatever the body.
## `above`: only the hair over the edge (the pressed-flat cut in an open crown).
static func hat_hair_material(id: String, color: Color, edge: Vector2, open := HAT_CLOSED, above := false) -> ShaderMaterial:
	var key := "hathair|%s|%s|%s|%s|%s" % [id, color.to_html(), edge, open, above]
	if not _materials.has(key):
		var base := hair_material(id, color)
		var m := ShaderMaterial.new()
		m.shader = HAT_HAIR_SHADER
		m.set_shader_parameter("tint", base.albedo_color)
		if base.albedo_texture != null:
			m.set_shader_parameter("strands", base.albedo_texture)
			m.set_shader_parameter("has_strands", true)
		m.set_shader_parameter("clip_n", Vector3(0.0, 1.0, -edge.y))
		m.set_shader_parameter("clip_d", (edge.x - HELMET_CROWN) / HELMET_HEAD_W)
		m.set_shader_parameter("open_n", Vector3(0.0, 1.0, -open.y))
		m.set_shader_parameter("open_d", (open.x - HELMET_CROWN) / HELMET_HEAD_W)
		m.set_shader_parameter("above", above)
		_materials[key] = m
	return _materials[key]


## The scalp cap where it shows in an open crown: _cap_material's color, drawn only over
## the hat's `edge` (the cap is in the head gear's own frame, in meters).
static func crown_cap_material(color: Color, edge: Vector2) -> ShaderMaterial:
	var key := "crowncap|%s|%s" % [color.to_html(), edge]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = HAT_HAIR_SHADER
		m.set_shader_parameter("tint", _cap_material(color).albedo_color)
		m.set_shader_parameter("clip_n", Vector3(0.0, 1.0, -edge.y))
		m.set_shader_parameter("clip_d", edge.x)
		m.set_shader_parameter("above", true)
		_materials[key] = m
	return _materials[key]


## The golf visor's bill: see-through plastic tinted in a team's trim color.
static func brim_material(color: Color) -> StandardMaterial3D:
	var key := "brim|%s" % color.to_html()
	if not _materials.has(key):
		var m := MeshUtil.material(Color(color, 0.7), 0.12)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 2   # (after the brows, as the helmet's visor is)
		_materials[key] = m
	return _materials[key]


## Flame paint for a team (flame_paint.gdshader): the helmet color for the shell, flames
## in the trim color (the jersey's, if the trim is too close to the shell to show), their
## cores and pinstripe in a pale version of the number outline.
static func flame_material(c: Dictionary) -> ShaderMaterial:
	var base: Color = c.helmet
	var flame: Color = c.trim
	if Vector3(flame.r - base.r, flame.g - base.g, flame.b - base.b).length() < 0.33:
		flame = c.jersey
	var core: Color = (c.get("number_outline", Color.WHITE) as Color).lerp(Color(0.97, 0.97, 0.94), 0.45)
	if Vector3(core.r - flame.r, core.g - flame.g, core.b - flame.b).length() < 0.3:
		core = Color(0.97, 0.97, 0.94) if flame.get_luminance() < 0.6 else Color(0.06, 0.06, 0.07)
	var key := "flame|%s|%s|%s" % [base.to_html(), flame.to_html(), core.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("flame_color", flame)
		m.set_shader_parameter("core_color", core)
		_materials[key] = m
	return _materials[key]


## The sunglasses' mirrored lens (visor_mirror.gdshader, in SHADES_MIRROR's colors).
static func shades_material() -> ShaderMaterial:
	if not _materials.has("shades"):
		var m := ShaderMaterial.new()
		m.shader = VISOR_MIRROR_SHADER
		m.set_shader_parameter("face_color", SHADES_MIRROR[0])
		m.set_shader_parameter("edge_color", SHADES_MIRROR[1])
		m.set_shader_parameter("clear_below", -1000.0)
		m.render_priority = 2
		_materials["shades"] = m
	return _materials["shades"]


## No head gear at all (NO_HELMET, the Old-Time Set): the whole head of hair, as when a
## helmet comes off in a fight. Goalies too.
func _build_bare_head(head: AABB) -> void:
	_mask = NO_HELMET
	_add_hair(head)


## Helmet model (tools/build_gear.gd): sized to the head's width, shell over the crown.
func _build_helmet(head: AABB, c: Dictionary) -> void:
	var helmet := MeshUtil.material(c.helmet, 0.35)
	var dark := MeshUtil.material(Color(0.06, 0.06, 0.07), 0.4)
	var hi := helmet_index(skater.gear_style)
	var hspec: Dictionary = HELMETS[hi]
	# A cage or a full shield takes the visor's place.
	# (their own, else the team's: the Grays' alien visors)
	var face := skater.face_gear if FACE_GEAR.has(skater.face_gear) else str(c.get("face", ""))
	if not FACE_GEAR.has(face):
		face = ""
	var crest := cosmetic("crest")
	var dangler := cosmetic("dangler") if face == "" else ""   # (it hangs from the visor)
	var visor := (skater.visor or DANGLERS.has(dangler)) and face == ""
	var tint := skater.visor_tint if skater.visor_tint != "" else str(c.get("visor_tint", ""))   # (their own, else the team's)
	var hmesh: Mesh = hspec.mesh if visor else without_visor(hspec.mesh)
	var fit: float = head.size.x / HELMET_HEAD_W
	var hat := Vector3(head.get_center().x, head.end.y - HELMET_CROWN * fit, head.get_center().z)
	var hm := attach("Head", hmesh, null, hat, Basis.from_scale(Vector3.ONE * fit))
	hm.material_override = null
	hm.name = "Helmet"
	hm.set_surface_override_material(0, helmet)
	hm.set_surface_override_material(1, MeshUtil.material(Color(0.92, 0.92, 0.9), 0.4))
	hm.set_surface_override_material(2, dark)
	if visor:
		hm.set_surface_override_material(3, visor_material(tint))
		hm.set_surface_override_material(4, MeshUtil.material(Color(0.08, 0.08, 0.09), 0.35))
	if face != "":
		# In the helmet's own frame, on the helmet: it comes off with it in a fight.
		var fg := MeshInstance3D.new()
		fg.name = "FaceGear"
		fg.mesh = FACE_GEAR[face][hi]
		hm.add_child(fg)
		match face:
			"shield":
				fg.set_surface_override_material(0, visor_material(tint, true))
			"alien":
				fg.set_surface_override_material(0, alien_lens_material())
			_:
				fg.set_surface_override_material(0, MeshUtil.material(Color(0.8, 0.82, 0.85), 0.28, 0.85))   # chromed wire
		fg.set_surface_override_material(1, dark)
	# Cosmetics on the helmet (they come off with it too).
	if CRESTS.has(crest):
		var cr := MeshInstance3D.new()
		cr.name = "Crest"
		cr.mesh = CRESTS[crest][hi]
		hm.add_child(cr)
		cr.material_override = MeshUtil.material(c.trim, 0.5)
	if DANGLERS.has(dangler):
		var dg := MeshInstance3D.new()
		dg.name = "Dangler"
		dg.mesh = DANGLERS[dangler].meshes[hi]
		hm.add_child(dg)
		dg.material_override = MeshUtil.material(DANGLERS[dangler].color, 0.35)
	_helmet = hm
	_helmet_rest = hm.transform
	_add_hair(head)


## What a skater wears in a cosmetic slot ("crest", "eye_fx" or "dangler"; "" = nothing):
## their own, else the team's.
func cosmetic(slot: String) -> String:
	var own: String = {"crest": skater.helmet_crest, "eye_fx": skater.eye_fx, "dangler": skater.dangler}.get(slot, "")
	return own if own != "" else str(team_colors().get(slot, ""))


## Glowing eyes (EYE_FX): the glows and their light, on the head at this body's own eyes
## (their box in the skeleton's rest space: two balls side by side, each as wide as the
## box is tall). Goalies too.
func _add_eye_fx(head: AABB) -> void:
	var fx := cosmetic("eye_fx")
	if not EYE_FX.has(fx):
		return
	var fit: float = head.size.x / HELMET_HEAD_W
	var eyes := skel.get_node_or_null("Eyes") as MeshInstance3D
	var box := eyes.mesh.get_aabb() if eyes != null else AABB(
			Vector3(head.get_center().x - 0.05 * fit, head.end.y - 0.132 * fit, head.get_center().z + 0.068 * fit), Vector3(0.1, 0.035, 0.02) * fit)
	var front := box.end.z + 0.004 * fit
	for side: float in [-1.0, 1.0]:
		var glow := MeshInstance3D.new()
		glow.name = "EyeGlowL" if side > 0.0 else "EyeGlowR"   # (+X is the body's left)
		glow.mesh = _unit_quad()
		glow.material_override = eye_glow_material(EYE_FX[fx])
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach_node("Head", glow, Transform3D(Basis.from_scale(Vector3(0.095, 0.07, 1.0) * fit),
				Vector3(box.get_center().x + side * (box.size.x - box.size.y) * 0.5, box.get_center().y, front)))
	# What they light: the brow, the sockets, the nose and cheeks, the inside of a visor.
	var lamp := OmniLight3D.new()
	lamp.name = "EyeLight"
	lamp.light_color = (EYE_FX[fx] as Color).lerp(Color(1.0, 0.25, 0.1), 0.2)
	lamp.light_energy = 2.3
	lamp.omni_range = 0.115 * fit   # (the face and the brow's underside: not the helmet's vents, which lit up from inside)
	lamp.omni_attenuation = 1.3
	lamp.light_specular = 0.3
	lamp.shadow_enabled = false
	attach_node("Head", lamp, Transform3D(Basis.IDENTITY, Vector3(box.get_center().x, box.get_center().y - 0.004 * fit, front + 0.016 * fit)))


## The head gear worn in place of a helmet (a TEAM_MASKS or HATS key, or NO_HELMET for a
## bare head; "" = none, a helmet): the player's own (Create Player), else the team's.
func head_gear(c: Dictionary) -> String:
	var gear: String = skater.headgear if skater.headgear != "" else str(c.get("headgear", ""))
	return gear if TEAM_MASKS.has(gear) or HATS.has(gear) or gear == NO_HELMET else ""


## A team mask (TEAM_MASKS) in place of the helmet, set on the eyes. Luchador hoods cover
## the hair and follow the jaw; the vintage face mask leaves the hair as it is.
func _build_team_mask(head: AABB, c: Dictionary, gear: String) -> void:
	_mask = gear
	var h := absi(("%s %s %d" % [skater.first_name, skater.last_name, skater.number]).hash())
	var by_body: Dictionary = TEAM_MASKS[_mask]
	var meshes: Array = by_body.get(skater.body_type, by_body.male)
	var s := Vector3.ONE * (head.size.x / HELMET_HEAD_W)
	var at := Vector3(head.get_center().x, head.end.y - HELMET_CROWN * s.y, head.get_center().z)
	var eyes := skel.get_node_or_null("Eyes") as MeshInstance3D
	if eyes != null:
		var e := eyes.mesh.get_aabb().get_center()
		s.y = (head.end.y - e.y) / (HELMET_CROWN - MASK_EYE.y)
		s.z = s.y
		at = Vector3(head.get_center().x, e.y - MASK_EYE.y * s.y, e.z - MASK_EYE.z * s.z)
	var mm := attach("Head", meshes[h % meshes.size()], null, at, Basis.from_scale(s))
	mm.material_override = null
	mm.name = "Helmet"   # tools and views find the head gear by name
	if _mask == "lucha":
		var cols: Array = [c.jersey, c.trim, c.get("number_outline", Color(0.05, 0.05, 0.05))]
		# Mostly the team color as the base; some wear one of the others.
		var order: Array = [[0, 1, 2], [0, 1, 2], [0, 2, 1], [2, 0, 1], [1, 2, 0]][(h / 3) % 5]
		var pat: Texture2D = LUCHA_PATTERNS[(h / 15) % LUCHA_PATTERNS.size()]
		if face != null:
			face.follow_jaw(mm)   # (swaps the mesh: materials after)
		mm.set_surface_override_material(0, lucha_material(pat, cols[order[0]], cols[order[1]], cols[order[2]]))
		mm.set_surface_override_material(1, MeshUtil.material(cols[order[1]], 0.4))
		# No hair: the hood covers it (a beard would poke through).
	else:
		for i in VINTAGE_COLORS.size():
			var m := MeshUtil.material(VINTAGE_COLORS[i], [0.35, 0.45, 0.85][i])
			m.metallic_specular = [0.5, 0.5, 0.15][i]   # straps: dull elastic
			m.cull_mode = BaseMaterial3D.CULL_DISABLED   # one-sided shell: its inside shows at the holes
			mm.set_surface_override_material(i, m)
		_add_hair(head, false)
	_helmet = mm
	_helmet_rest = mm.transform


static func lucha_material(pat: Texture2D, base: Color, a1: Color, a2: Color) -> ShaderMaterial:
	var key := "lucha|%s|%s|%s|%s" % [pat.resource_path, base.to_html(), a1.to_html(), a2.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = LUCHA_SHADER
		m.set_shader_parameter("pattern", pat)
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("accent1", a1)
		m.set_shader_parameter("accent2", a2)
		# White details, unless the hood itself is light.
		m.set_shader_parameter("accent3", Color(0.95, 0.95, 0.93) if base.get_luminance() < 0.7 else Color(0.05, 0.05, 0.05))
		_materials[key] = m
	return _materials[key]


## Pads, gloves, skates, numbers and crest: everything but the head gear.
func _build_body_gear(c: Dictionary, cloth: Material, glove: Material, skin: Material, chest: AABB) -> void:
	var cc := chest.get_center()
	var cr := Vector3(maxf(chest.size.x * 0.62, 0.25 * hs), 0.13 * hs, maxf(chest.size.z * 0.6, 0.15 * hs))
	var chest_at := cc + Vector3(0, 0.02 * hs, 0)
	# Bodies with a modelled jersey (tools/blender/build_jersey.py) already carry the
	# shoulder and chest bulk in its shape; the pad ball would poke through it.
	if not body.get_meta("jersey", false):
		_print_extra.append(attach("Spine2", _cloth_mesh(_sphere(), chest_at, Basis.from_scale(cr)), cloth, chest_at, Basis.from_scale(cr)))
	# Hockey pants: a slim band around the pelvis plus a padded shell on each thigh that
	# moves with the leg (one big pelvis ball stuck out behind like a diaper when the
	# skater bent forward).
	var hips := anchor_box("hips", "Hips", Vector3(0.34, 0.2, 0.24) * hs)
	var hips_at := hips.get_center() + Vector3(0, -0.035 * hs, 0.0)
	# The pants pads fill out with the build like the body under them (BodyBuild.GIRTH).
	var bh := 1.0 + float(BodyBuild.GIRTH.Hips) * body_size.y
	var bt := 1.0 + float(BodyBuild.GIRTH.LeftUpLeg) * body_size.y
	# Old-time canvas pants carry less padding than the shell.
	if pants_kind() == 1:
		bh *= CANVAS_SLIM.x
		bt *= CANVAS_SLIM.y
	var hips_b := Basis.from_scale(Vector3(maxf(hips.size.x * 0.53, 0.17 * hs) * bh, 0.1 * hs, maxf(hips.size.z * 0.46, 0.115 * hs) * bh))
	attach("Hips", _cloth_mesh(_sphere(), hips_at, hips_b), cloth, hips_at, hips_b)
	for side in ["Left", "Right"]:
		var hip := bone_pos(side + "UpLeg")
		var thigh := bone_pos(side + "Leg") - hip
		var at := hip + thigh * 0.3 + Vector3(0, 0, 0.005 * hs)
		at = BodyBuild.point(skel, side + "UpLeg", at, body_size.y)
		var tb := limb_frame(side + "UpLeg", side + "Leg", Vector3(0.1 * hs * bt, thigh.length() * 0.36, 0.108 * hs * bt))
		attach(side + "UpLeg", _cloth_mesh(_sphere(), at, tb), cloth, at, tb)
	for side in ["Left", "Right"]:
		# Glove model: fingers along the hand, palm down in the T-pose, thumb forward. The
		# model is a right glove; the left one is mirrored.
		var hand := bone_pos(side + "Hand")
		var arm_dir := (hand - bone_pos(side + "ForeArm")).normalized()
		var lf := limb_frame(side + "ForeArm", side + "Hand")
		var gb := Basis(-lf.z, lf.y, lf.x) if side == "Right" else Basis(-lf.z, lf.y, -lf.x)
		var gg := glove_gear()
		_gloves.append(attach(side + "Hand", gg[0], glove, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs)))
		# The cuff hangs on the forearm, so it stays on the arm while the hand turns.
		_cuffs.append(attach(side + "ForeArm", gg[1], glove, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs)))
		var fist := attach(side + "Hand", FIST_MESH, skin, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs))
		fist.visible = false
		_fists.append(fist)
	# The body's own fingers would poke out of both: the rig folds them away.
	rig.hide_fingers = true
	# The glove's flared cuff takes the end of the sleeve, which is wider than the cuff is
	# at the wrist: while gloves are worn the sleeve stops inside the cuff (uniform.gdshader
	# `sleeve_end`, a position along the arm: 1 at the wrist).
	var arm := bone_pos("LeftArm").distance_to(bone_pos("LeftForeArm")) + bone_pos("LeftForeArm").distance_to(bone_pos("LeftHand"))
	for mi: MeshInstance3D in skel.find_children("Outfit_*", "MeshInstance3D", false, false):
		mi.set_instance_shader_parameter("sleeve_end", 1.0 - (GLOVE_SLEEVE_OLD if old_time(skater.glove_style) else GLOVE_SLEEVE) * hs / arm)
	add_skates(c)
	_add_number(cc + Vector3(0, (-0.04 - number_drop(c)) * hs, -cr.z), NUMBER_HEIGHT * hs)
	# Under a modelled jersey's laced V collar: lower and a little smaller, so the crest
	# stays clear of the collar and laces.
	var modelled: bool = body.get_meta("jersey", false)
	_add_crest(cc + Vector3(0, (-0.14 if modelled else -0.07) * hs, cr.z), CREST_WIDTH * (0.85 if modelled else 1.0) * hs)


## Hair (what shows under the helmet) and facial hair, sized to this body's head.
## `facial` false leaves the facial hair off (it would poke through a face mask).
func _add_hair(head: AABB, facial := true) -> void:
	var top := Vector3(head.get_center().x, head.end.y, head.get_center().z)
	var b := Basis.from_scale(Vector3.ONE * head.size.x)
	for id: String in [skater.hair_style, skater.facial_hair if facial else ""]:
		var path := hair_mesh_path(id, skater.body_type)
		if id == "" or path == "":
			continue
		var mi := attach("Head", load(path), hair_material(id, skater.hair_color), top, b)
		mi.name = "Hair_" + id
		if id == skater.facial_hair and face != null:
			face.follow_jaw(mi)
		# Hairstyles have a flattened copy for under the helmet (facial hair doesn't; a
		# bare head never needs it).
		var helm_path := hair_mesh_path(id, skater.body_type, true)
		if helm_path != "" and _mask != NO_HELMET:
			var hm := attach("Head", load(helm_path), hair_material(id, skater.hair_color), top, b)
			hm.name = "HairHelm_" + id
			_hair_full.append(mi)
			_hair_helm.append(hm)
			# Pressed flat, the strands are thin on the crown and the back of the head: a
			# hair-colored cap on the scalp shows in the helmet's vents and behind the
			# goalie's mask.
			var fit := _eye_fit(head)
			var cap := attach("Head", SCALP_CAP, _cap_material(skater.hair_color), fit.origin, fit.basis)
			cap.name = "HairCap"
			_hair_helm.append(cap)
	_show_hair(true)


## Where the head gear's frame (HELMET_* / MASK_EYE) sits on this body when set on the
## eyes: scaled by eyes-to-crown height and across by head width (bodies without eyes: on
## the crown, by head width).
func _eye_fit(head: AABB) -> Transform3D:
	var s := Vector3.ONE * (head.size.x / HELMET_HEAD_W)
	var at := Vector3(head.get_center().x, head.end.y - HELMET_CROWN * s.y, head.get_center().z)
	var eyes := skel.get_node_or_null("Eyes") as MeshInstance3D
	if eyes != null:
		var e := eyes.mesh.get_aabb().get_center()
		s.y = (head.end.y - e.y) / (HELMET_CROWN - MASK_EYE.y)
		s.z = s.y
		at = Vector3(head.get_center().x, e.y - MASK_EYE.y * s.y, e.z - MASK_EYE.z * s.z)
	return Transform3D(Basis.from_scale(s), at)


## The scalp cap under head gear (modeled with the goalie mask, tools/blender/
## goalie_mask_gear.py): skin-tight over the top and back of the male head, in the head
## gear's frame (_eye_fit).
const SCALP_CAP := preload("res://assets/characters/scalp_cap.res")


static func _cap_material(color: Color) -> StandardMaterial3D:
	var key := "haircap|" + color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color.darkened(0.25)
		m.roughness = 0.85
		_materials[key] = m
	return _materials[key]


func _show_hair(helmet_on: bool) -> void:
	helmet_on = helmet_on and _mask == ""   # a face mask leaves the hair as it is
	for h in _hair_full:
		h.visible = not helmet_on
	for h in _hair_helm:
		h.visible = helmet_on


func helmet_on() -> bool:
	return _helmet != null and _helmet.visible and not _helmet.top_level


## Puts the helmet back on the head at once (after a fight), or takes it off at once.
func set_helmet(on: bool) -> void:
	if _helmet == null:
		return
	_helmet_t = -1.0
	if on:
		var head_att: Node = _hair_full[0].get_parent() if not _hair_full.is_empty() else null
		if head_att == null:
			for c in skel.get_children():
				if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == "Head":
					head_att = c
		_helmet.top_level = false
		if _helmet.get_parent() != head_att:
			_helmet.reparent(head_att, false)
		_helmet.transform = _helmet_rest
	_helmet.visible = on
	_show_hair(on)


## Fights: both hands go up to the helmet, the right one pulls it off and lets it drop to
## the ice (it stays there until set_helmet(true)). About HELMET_END seconds.
func take_off_helmet() -> void:
	if not helmet_on() or _mask != "":
		return   # masks stay on (no unmasking a luchador)
	_helmet_t = 0.0
	play_clip(HELMET_CLIP, Vector3(0.0, 1.0, 1.0), HELMET_END, HELMET_SPEED, 0.2, HELMET_FROM)


func _tick_helmet(delta: float) -> void:
	if _helmet_t < 0.0 or _helmet == null:
		return
	var was := _helmet_t
	_helmet_t += delta
	if was < HELMET_LIFT and _helmet_t >= HELMET_LIFT:
		# Into the right hand, as it sits now: it leaves the head with the hand.
		var hand: Node = null
		for c in skel.get_children():
			if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == "RightHand":
				hand = c
		if hand:
			_helmet.reparent(hand, true)
		_show_hair(false)
	if was < HELMET_DROP and _helmet_t >= HELMET_DROP:
		var from := _helmet.global_transform
		_helmet.top_level = true
		_helmet.global_transform = from
		_helmet_vel = skater.heading.cross(Vector3.UP).normalized() * -0.6 + Vector3.UP * 0.4
		_helmet_spin = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
	if _helmet_t >= HELMET_DROP:
		_fall_helmet(delta)


## The dropped helmet: falls, tumbling, until its lowest point is on the ice.
func _fall_helmet(delta: float) -> void:
	if _helmet_vel == Vector3.ZERO:
		return
	_helmet_vel += Vector3.DOWN * 9.8 * delta
	var xf := _helmet.global_transform
	xf.origin += _helmet_vel * delta
	if _helmet_spin.length() > 0.0:
		xf.basis = Basis(_helmet_spin.normalized(), _helmet_spin.length() * delta) * xf.basis
	if _helmet_pts.is_empty():
		var f := _helmet.mesh.get_faces()
		for k in range(0, f.size(), 7):
			_helmet_pts.append(f[k])
	var low := INF
	for q in _helmet_pts:
		low = minf(low, (xf * q).y)
	if low <= 0.0:
		xf.origin.y -= low
		_helmet_vel = Vector3.ZERO
		_helmet_t = -1.0
	_helmet.global_transform = xf


## The mesh for a style on a body ("" if there is none): the body's own fit, else the male
## one. `helm`: the version pressed under a helmet.
static func hair_mesh_path(id: String, body_type: String, helm := false) -> String:
	if id == "":
		return ""
	var tail := "_helm.res" if helm else ".res"
	if body_type == "female" and ResourceLoader.exists(HAIR_DIR + id + "_female" + tail):
		return HAIR_DIR + id + "_female" + tail
	return HAIR_DIR + id + tail if ResourceLoader.exists(HAIR_DIR + id + tail) else ""


## Whether a body type wears a hairstyle (some are women's or men's only).
static func hair_fits(id: String, body_type: String) -> bool:
	return not (id in HAIR_MEN if body_type == "female" else id in HAIR_WOMEN)


## A hairstyle for `roll` (any integer, e.g. rng.randi()), by HAIR_ODDS_*.
static func pick_hair(roll: int, body_type: String, dark_skin: bool) -> String:
	var odds: Dictionary = HAIR_ODDS_WOMEN if body_type == "female" else HAIR_ODDS_MEN
	var total := 0.0
	for id: String in odds:
		total += float(odds[id]) * (float(HAIR_DARK_LEAN.get(id, 1.0)) if dark_skin else 1.0)
	var x := float(posmod(roll, 100003)) / 100003.0 * total
	for id: String in odds:
		x -= float(odds[id]) * (float(HAIR_DARK_LEAN.get(id, 1.0)) if dark_skin else 1.0)
		if x < 0.0:
			return id
	return "messy"


## Facial hair for `r` (0..1), by FACIAL_ODDS ("" = clean shaven).
static func pick_facial(r: float) -> String:
	for f: Array in FACIAL_ODDS:
		r -= float(f[1])
		if r < 0.0:
			return f[0]
	return ""


## The strand grain (strands.png, made by tools/blender/hair_gear.py) is white strands on
## black, which reads as dark sketch lines on an opaque mesh. Squeeze it into a narrow light
## band (gaps at HAIR_FLAT_LOW, strands at 1.0) so the hair is a near-flat color with a
## faint strand grain, like the rest of the character. Mipmapped so the grain doesn't
## shimmer at a distance. Cached per file.
const HAIR_FLAT_LOW := 0.86
const HAIR_FLAT_MEAN := 0.93
static var _flat_hair: Dictionary = {}


static func _flat_hair_texture(path: String) -> Texture2D:
	if _flat_hair.has(path):
		return _flat_hair[path]
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var v := lerpf(HAIR_FLAT_LOW, 1.0, c.get_luminance())
			img.set_pixel(x, y, Color(v, v, v, c.a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_flat_hair[path] = t
	return t


## Every style shares one material per color: the strand grain along each lock (the meshes'
## UVs) and the shading in their vertex colors (dark volume, lighter locks).
static func hair_material(_id: String, color: Color) -> StandardMaterial3D:
	var key := "hair|" + color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		var tex := HAIR_DIR + "strands.png"
		if ResourceLoader.exists(tex):
			m.albedo_texture = _flat_hair_texture(tex)
			# The flattened strands average about HAIR_FLAT_MEAN: lift the tint to land on `color`.
			var k := 1.0 / HAIR_FLAT_MEAN
			m.albedo_color = Color(minf(color.r * k, 1.0), minf(color.g * k, 1.0), minf(color.b * k, 1.0))
		else:
			m.albedo_color = color
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## A hairstyle, facial hair, hair and eye color for a player: {hair_style, facial_hair,
## hair_color, eye_color}. Darker skin tones lean to darker hair and brown eyes; some
## players go gray.
static func random_look(rng: RandomNumberGenerator, body_type: String, skin: Color) -> Dictionary:
	var facial := ""
	if body_type != "female":
		facial = pick_facial(rng.randf())
	var dark := skin.get_luminance() < 0.45
	var colors := HAIR_COLORS.size() - 1   # gray is its own roll
	if dark:
		colors = 2
	var color := HAIR_COLORS[rng.randi() % colors]
	if rng.randf() < 0.08:
		color = HAIR_COLORS[HAIR_COLORS.size() - 1]
	var style := pick_hair(rng.randi(), body_type, dark)
	# Eye color from a side generator seeded off this one, so adding it didn't change
	# anyone's existing looks (or the draws callers make after this).
	var er := RandomNumberGenerator.new()
	er.seed = rng.state ^ 0x2545F491
	return {"hair_style": style, "facial_hair": facial, "hair_color": color, "eye_color": random_eye_color(er, skin, color)}


static func random_eye_color(rng: RandomNumberGenerator, skin: Color, hair: Color) -> Color:
	var w := PackedFloat32Array([3.0, 3.0, 1.5, 0.6, 1.0, 0.6, 1.8, 1.0])
	if skin.get_luminance() < 0.45:
		w = PackedFloat32Array([6.0, 3.5, 0.6, 0.3, 0.05, 0.0, 0.05, 0.0])
	elif hair.get_luminance() > 0.3 or hair.r > hair.g * 2.0:   # fair or red hair: lighter eyes
		w = PackedFloat32Array([1.0, 1.5, 1.5, 0.6, 1.6, 0.8, 2.5, 1.8])
	var c := EYE_COLORS[rng.rand_weighted(w)]
	var shade := rng.randf_range(-0.12, 0.12)
	return c.lightened(shade) if shade > 0.0 else c.darkened(-shade)


## Where the stick and both gloves are now (world): {stick, gloves: [left, right]}, so
## a fight can drop copies from the hands.
func held_gear() -> Dictionary:
	return {"stick": shaft.global_transform, "gloves": [_gloves[0].global_transform, _gloves[1].global_transform]}


## Fights: the stick and gloves come off (the fight drops copies on the ice).
func set_fight_mode(on: bool) -> void:
	shaft.visible = not on
	blade.visible = not on
	for g in _gloves:
		g.visible = not on
	for f in _fists:
		f.visible = on
	for c in _cuffs:
		c.visible = not on
	rig.fist = 1.0 if on else 0.0
	if face != null:
		face.set_expression("angry" if on else "neutral")
	if not on:
		set_helmet(true)
	_fight_mode = on
	rig.lock_root = on or skater.is_down()
	rig.reach_w = [0.0, 0.0]
	if not on:
		yaw_offset = 0.0
	# Bare hands: the uniform's glove layer goes, the skin underneath shows.
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", false, false):
		mi.set_instance_shader_parameter("gloves_worn", 0.0 if on else 1.0)


## Skate models on both feet (shared with goalies): runner on the ice, centered a bit
## ahead of the ankle.
func add_skates(c: Dictionary) -> void:
	# The boot uses the glove shader (tools/blender/skate_gear.py bakes its shading): the
	# skate color, greyer side panels, the holder, laces and tongue felt in white. The
	# old-time skate (the same frame and size): tan leather with a dark toe cap and heel,
	# on a steel tube frame.
	var old := old_time(skater.skate_style)
	var model: Mesh = SKATE_OLD_MESH if old else SKATE_MESH
	var boot := leather_material(LEATHER_SKATE[0], LEATHER_SKATE[1], LEATHER_SKATE[2]) if old else glove_material(c.skates)
	var steel := MeshUtil.material(Color(0.8, 0.82, 0.85), 0.25)
	var k: float = SKATE_LEN * hs / SKATE_MESH.get_aabb().size.z
	for side in ["Left", "Right"]:
		var foot := bone_pos(side + "Foot")
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(foot.x, -SKATE_LIFT, foot.z + 0.08 * hs))
		# Skinned rather than hung on the foot: the boot's upper (the shaft, tongue and
		# tendon guard) follows the shin, so a bent ankle flexes the boot forward instead
		# of pushing the leg out through its front.
		var sk := MeshInstance3D.new()
		sk.name = side + "Skate"
		sk.mesh = _skate_mesh(model, xf)
		var skin := Skin.new()
		for b in [side + "Foot", side + "Leg"]:
			skin.add_named_bind(b, skel.get_bone_global_rest(skel.find_bone(b)).affine_inverse())
		sk.skin = skin
		skel.add_child(sk)
		sk.skeleton = NodePath("..")
		sk.set_surface_override_material(0, boot)
		sk.set_surface_override_material(1, steel)
	# The boot's shaft is as slim as an ankle, so the padded sock can't go down inside it:
	# it ends over the boot's collar, and the foot under the boot is not drawn
	# (uniform.gdshader `sock_end`, a position along the leg: 1 at the ankle joint).
	var ankle := bone_pos("LeftFoot")
	var knee := bone_pos("LeftLeg")
	var leg := bone_pos("LeftUpLeg").distance_to(knee) + knee.distance_to(ankle)
	var sock_end := 1.0 - (SKATE_SOCK * k - SKATE_LIFT - ankle.y) / leg
	for mi: MeshInstance3D in skel.find_children("Outfit_*", "MeshInstance3D", false, false):
		mi.set_instance_shader_parameter("sock_end", sock_end)


## Upper boot: where the skate starts following the shin, and where it follows it fully
## (heights in the skate model, above the ice).
const SKATE_FLEX := Vector2(0.13, 0.22)
static var _skate_meshes := {}


## A skate model placed by `xf` (skeleton space), weighted to two binds: 0 the foot,
## 1 the shin, blending up the boot's shaft. Shared per model and placement.
static func _skate_mesh(model: Mesh, xf: Transform3D) -> ArrayMesh:
	var key := model.resource_path + str(xf)
	if _skate_meshes.has(key):
		return _skate_meshes[key]
	var out := ArrayMesh.new()
	for s in model.get_surface_count():
		var arr := model.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(v.size() * 4)
		weights.resize(v.size() * 4)
		for i in v.size():
			var t := smoothstep(SKATE_FLEX.x, SKATE_FLEX.y, v[i].y)
			bones[i * 4] = 0
			bones[i * 4 + 1] = 1
			weights[i * 4] = 1.0 - t
			weights[i * 4 + 1] = t
			v[i] = xf * v[i]
			if i < nr.size():
				nr[i] = (xf.basis * nr[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_skate_meshes[key] = out
	return out


## Yoke designs carry the back number a little lower, clear of the yoke.
static func number_drop(c: Dictionary) -> float:
	var d := Teams.design_params(c)
	return 0.06 if float(d.get("yoke_r", 0.0)) > 0.0 else 0.0


## Back number, printed on the jersey (_print) around `at` (a point on the back, T-pose),
## and the nameplate above it.
func _add_number(at: Vector3, height: float) -> void:
	var c := team_colors()
	at.y -= NUMBER_LOWER * hs
	var tex := number_texture(skater.number, c.number, c.number_outline)
	var h := height / DIGIT_FILL
	_print("number", tex, Vector2(h * tex.get_width() / float(tex.get_height()), h), at)
	# The nameplate above it, in the number's colors.
	var nm := back_name(skater)
	if nm == "":
		return
	var plate: Array = name_texture(nm, c.number, c.number_outline)
	var ntex: ImageTexture = plate[0]
	var nh: float = NAME_HEIGHT * hs / float(plate[1])      # whole texture height
	var nw := nh * ntex.get_width() / float(ntex.get_height())
	nw = minf(nw, NAME_MAX_W * hs)                          # long names: squeezed
	var name_at := at + Vector3(0, (height * 0.5 + NAME_GAP * hs + NAME_HEIGHT * hs * 0.5), 0)
	_print("name", ntex, Vector2(nw, nh), name_at)


## Prints `tex` on this player's jersey: "crest" on the chest, "number" or "name" on the
## back, `size` (width, height) in meters around `at` (a point on the body in the T-pose:
## its x and y are what count). uniform.gdshader draws it into the cloth, in the cloth's
## rest space, so it bends and folds with the jersey and stays off whatever passes in
## front of it. (These were Decals once: a Decal paints everything inside its box, so the
## crest showed on the arms, gloves and sticks that crossed the chest.)
func _print(slot: String, tex: Texture2D, size: Vector2, at: Vector3) -> void:
	var neck := bone_pos("Neck")
	var k := 0.6 / maxf(neck.y - bone_pos("Hips").y, 0.01)   # rest space, as tools/build_characters.gd REST_TORSO
	# The build widens the trunk and what is printed on it: narrower in rest space by as
	# much, so it comes out `size` wide and in proportion on every build.
	var wide := 1.0 + (float(BodyBuild.GIRTH.Spine1) + float(BodyBuild.GIRTH.Spine2)) * 0.5 * body_size.y
	var box := Vector4((at.x - neck.x) * k, (at.y - neck.y) * k, wide / (size.x * k), 1.0 / (size.y * k))
	for m in _print_materials():
		m.set_shader_parameter(slot + "_tex", tex)
		m.set_shader_parameter(slot + "_box", box)


## This player's own copies of the uniform material on everything the jersey is drawn on
## (the team's material is shared by its players; each one's prints are their own).
func _print_materials() -> Array[ShaderMaterial]:
	if _print_mats.is_empty():
		var meshes: Array[MeshInstance3D] = []
		meshes.append_array(_print_extra)
		for mi: MeshInstance3D in skel.find_children("Outfit_*", "MeshInstance3D", false, false):
			meshes.append(mi)
		var own := {}   # the shared material -> this player's copy
		for mi in meshes:
			var m := mi.material_override as ShaderMaterial
			if m == null or m.shader != UNIFORM_SHADER:
				continue
			if not own.has(m):
				own[m] = m.duplicate()
				_print_mats.append(own[m])
			mi.material_override = own[m]
	return _print_mats


## What goes on the back above the number: a short nickname (NICKNAME_MAX letters or
## fewer) if the player has one, else the last name. Upper case; "" for none.
static func back_name(s: Skater) -> String:
	var nick := s.nickname.strip_edges()
	if nick != "" and nick.length() <= NICKNAME_MAX:
		return nick.to_upper()
	return s.last_name.strip_edges().to_upper()


## A nameplate from the letter sheet (tools/build_letters.gd): each letter cropped tight
## with a small gap, spaces as gaps, face and outline tinted. Characters not on the
## sheet are skipped. Returns [texture, the share of its height a capital fills]. Cached.
static func name_texture(text: String, fill: Color, outline: Color) -> Array:
	var key := "%s|%s|%s" % [text, fill.to_html(), outline.to_html()]
	if _names.has(key):
		return _names[key]
	_load_letters()
	var ch := _letter_sheet.get_height()
	var cw := _letter_sheet.get_width() / LETTER_CHARS.length()
	var gap := 3
	var space := int(cw * 0.32)
	# Rows to keep: the capitals plus any accents above them.
	var top := _cap_rows.x
	var bottom := _cap_rows.y
	var spans := []
	var width := 0
	for chr in text:
		if chr == " ":
			spans.append(null)
			width += space
			continue
		if not _letter_spans.has(chr):
			continue
		var sp: Array = _letter_spans[chr]
		spans.append(sp)
		width += sp[1] + gap
		top = mini(top, sp[2])
	if width <= 0:
		width = 1
	var pad := 4
	var h := bottom - top + 1
	var img := Image.create(width + pad * 2, h + pad * 2, false, Image.FORMAT_RGBA8)
	var x := pad
	for sp in spans:
		if sp == null:
			x += space
			continue
		img.blit_rect(_letter_sheet, Rect2i(sp[0], top, sp[1], h), Vector2i(x, pad))
		x += sp[1] + gap
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] == 0:
			continue
		var t := data[i] / 255.0
		data[i] = int(lerpf(outline.r, fill.r, t) * 255.0)
		data[i + 1] = int(lerpf(outline.g, fill.g, t) * 255.0)
		data[i + 2] = int(lerpf(outline.b, fill.b, t) * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var out := [ImageTexture.create_from_image(img), float(_cap_rows.y - _cap_rows.x + 1) / float(img.get_height())]
	_names[key] = out
	return out


## Reads the letter sheet once: each character's columns and top row, and the rows a
## plain capital (H) fills.
static func _load_letters() -> void:
	if _letter_sheet != null:
		return
	_letter_sheet = LETTERS.get_image()
	if _letter_sheet.is_compressed():
		_letter_sheet.decompress()
	_letter_sheet.convert(Image.FORMAT_RGBA8)
	var cw := _letter_sheet.get_width() / LETTER_CHARS.length()
	var ch := _letter_sheet.get_height()
	for i in LETTER_CHARS.length():
		var x0 := cw
		var x1 := -1
		var y0 := ch
		var y1 := -1
		for x in cw:
			for y in ch:
				if _letter_sheet.get_pixel(i * cw + x, y).a > 0.05:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		if x1 < 0:
			continue
		_letter_spans[LETTER_CHARS[i]] = [i * cw + x0, x1 - x0 + 1, y0]
		if LETTER_CHARS[i] == "H":
			_cap_rows = Vector2i(y0, y1)


## Team crest on the jersey front, printed on the cloth (_print) around `at` (a point on
## the chest, T-pose) like the back number. `width` is the crest box's width (see crest_size).
func _add_crest(at: Vector3, width: float) -> void:
	if skater.crest == null:
		return
	_print("crest", skater.crest, crest_size(skater.crest, width), at)


## A crest's size (width, height) in a box `width` wide and CREST_MAX_H of that tall:
## scaled so its opaque area is CREST_INK of the box (a tall pine tree and a round badge
## read the same size), then shrunk to fit the box if that overflows it.
static func crest_size(tex: Texture2D, width: float) -> Vector2:
	var aspect := tex.get_width() / float(tex.get_height())
	var ink := crest_ink(tex)
	var area := width * width * CREST_MAX_H * CREST_INK / ink
	var w := sqrt(area * aspect)
	var h := w / aspect
	var fit := minf(1.0, minf(width / w, width * CREST_MAX_H / h))
	return Vector2(w, h) * fit


## The share of a crest texture that is opaque (sampled on a coarse grid). Cached.
static func crest_ink(tex: Texture2D) -> float:
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if _crest_ink.has(key):
		return _crest_ink[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var n := 0
	var hit := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			n += 1
			if img.get_pixel(x, y).a > 0.5:
				hit += 1
	var ink := clampf(hit / float(maxi(n, 1)), 0.15, 1.0)
	_crest_ink[key] = ink
	return ink


## A number's digits from the digit sheet (tools/build_digits.gd), face and outline
## tinted, cropped tight. Cached.
static func number_texture(n: int, fill: Color, outline: Color) -> ImageTexture:
	var key := "%d|%s|%s" % [n, fill.to_html(), outline.to_html()]
	if _numbers.has(key):
		return _numbers[key]
	var sheet := DIGITS.get_image()
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var cw := sheet.get_width() / 10
	var ch := sheet.get_height()
	var spans := []
	var width := 0
	for chr in str(n):
		var dg := int(chr)
		var x0 := cw
		var x1 := 0
		for x in cw:
			for y in range(0, ch, 3):
				if sheet.get_pixel(dg * cw + x, y).a > 0.05:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					break
		spans.append([dg * cw + x0, x1 - x0 + 1])
		width += x1 - x0 + 1
	var pad := 6
	var gap := 2
	var img := Image.create(width + gap * (spans.size() - 1) + pad * 2, ch + pad * 2, false, Image.FORMAT_RGBA8)
	var x := pad
	for sp: Array in spans:
		img.blit_rect(sheet, Rect2i(sp[0], 0, sp[1], ch), Vector2i(x, pad))
		x += sp[1] + gap
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		if a == 0:
			continue
		var t := data[i] / 255.0
		data[i] = int(lerpf(outline.r, fill.r, t) * 255.0)
		data[i + 1] = int(lerpf(outline.g, fill.g, t) * 255.0)
		data[i + 2] = int(lerpf(outline.b, fill.b, t) * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_numbers[key] = tex
	return tex


## Adds `mesh` to `bone`, placed where `at` is in the T-pose.
func attach(bone: String, mesh: Mesh, mat: Material, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	attach_node(bone, mi, Transform3D(basis, at))
	return mi


func attach_node(bone: String, node: Node3D, rest_xform: Transform3D) -> void:
	var idx := skel.find_bone(bone)
	var att: BoneAttachment3D = null
	for c in skel.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == bone:
			att = c
	if att == null:
		att = BoneAttachment3D.new()
		att.bone_name = bone
		skel.add_child(att)
	node.transform = skel.get_bone_global_rest(idx).affine_inverse() * rest_xform
	att.add_child(node)


## One stick model (tools/build_gear.gd), stretched each frame from the heel to the top
## of the shaft (see _place_stick); `shaft` and `blade` both point at it.
func _build_stick() -> void:
	var model: Mesh = STICK_OLD_MESH if stick_style_of(skater) == STICK_OLD else STICK_MESH
	shaft = _add_mesh(self, model, null, Vector3.ZERO)
	var mats := stick_materials(skater, model)
	shaft.set_surface_override_material(0, mats[0])
	shaft.set_surface_override_material(1, mats[1])
	blade = shaft


## The finish of a skater's stick: their own (STICK_STYLES or STICK_OLD), or the old-time
## wooden stick for everyone on a team in the old-time kit.
static func stick_style_of(s: Skater) -> String:
	if str(s.uniform.get("kit", "")) == OLD:
		return STICK_OLD
	return s.stick_style if s.stick_style in STICK_STYLES or s.stick_style == STICK_OLD else "black"


## The club's [home, road] jersey colors for a skater's stick and tape.
static func club_pair(s: Skater) -> Array[Color]:
	if s.club_colors.size() >= 2:
		return s.club_colors
	var home: Color = s.uniform.get("jersey", s.team_color) if not s.uniform.is_empty() else s.team_color
	return [home, STICK_WHITE]


## [body, tape] materials for a skater's stick (stick.gdshader), from its style and
## tape. `mesh`: the stick model (its "blade" / "shaft" metas place the graphics).
## The tape material also covers the butt-end knob on skater sticks. Cached.
static func stick_materials(s: Skater, mesh: Mesh) -> Array[ShaderMaterial]:
	var club := club_pair(s)
	var style := stick_style_of(s)
	var tape := s.stick_tape if s.stick_tape in TAPES else "white"
	var key := "stick|%s|%s|%s|%s|%s" % [style, tape, club[0].to_html(), club[1].to_html(), mesh.resource_path]
	if _materials.has(key):
		return _materials[key]
	var body := ShaderMaterial.new()
	body.shader = STICK_SHADER
	var kind := 1
	var base := STICK_BLACK
	var graphic := STICK_BLACK
	match style:
		"wood":
			kind = 0
		"black_white":
			kind = 2
			base = STICK_WHITE
			graphic = STICK_BLACK
		"white_black":
			kind = 2
			base = STICK_BLACK
			graphic = STICK_WHITE
		"home_away":
			kind = 2
			base = club[1]
			graphic = club[0]
		"away_home":
			kind = 2
			base = club[0]
			graphic = club[1]
		STICK_OLD:
			kind = 3
			graphic = club[0]   # the painted band low on the shaft
	body.set_shader_parameter("style", kind)
	body.set_shader_parameter("base", base)
	body.set_shader_parameter("graphic", graphic)
	body.set_shader_parameter("shaft_len", float(mesh.get_meta("shaft", 1.5)))
	body.set_shader_parameter("blade_vec", Vector3(mesh.get_meta("blade", Vector3(0, -0.2369, 0.2369))))
	var tm := body.duplicate() as ShaderMaterial
	tm.set_shader_parameter("tape_layer", true)
	var tc: Color = {"white": STICK_WHITE, "black": Color(0.07, 0.07, 0.08), "team": club[0]}.get(tape, STICK_WHITE)
	tm.set_shader_parameter("tape_color", tc)
	tm.set_shader_parameter("bare_blade", tape == "none")
	# The knob is taped either way: the blade's tape, or white with none on the blade.
	tm.set_shader_parameter("knob_color", tc if tape != "none" else STICK_WHITE)
	if style == STICK_OLD:
		tm.set_shader_parameter("tape_span", Vector2(0.04, 0.99))   # taped heel to toe, as they were
	var out: Array[ShaderMaterial] = [body, tm]
	_materials[key] = out
	return out


## Poses the stick model: heel at `heel`, shaft up to `top`, the blade flat along the ice
## in the stick's own plane (away from the hands) unless `out` gives its direction, its
## forehand face toward `face`. Works for any stick mesh with "blade" / "shaft" metas
## (tools/build_gear.gd). The shaft can't always meet the blade at the model's angle, so
## the mesh is skewed a little rather than lifting the blade off the ice.
func _place_stick(top: Vector3, heel: Vector3, face: Vector3, out := Vector3.ZERO, any_out := false) -> void:
	var s := top - heel
	if out == Vector3.ZERO:
		out = Vector3(-s.x, 0.0, -s.z)
	if out.length() < 0.05:
		out = skater.right_dir() * skater.forehand_side()
	# `any_out`: the blade may point any way (display poses: up, with the shaft level).
	out = out.normalized() if any_out else Vector3(out.x, 0.0, out.z).normalized()
	var f := (s.normalized().cross(out) if any_out else Vector3.UP.cross(out)).normalized()
	if f.dot(face) < 0.0:
		f = -f
	var db: Vector3 = shaft.mesh.get_meta("blade")
	var l0: float = shaft.mesh.get_meta("shaft")
	# The blade hooks toward -X in the model, so -X is the forehand face. The blade line
	# drops at the stick's lie in the model and lies flat here, at its full length.
	var world := Basis(-f, s / l0, out * Vector2(db.y, db.z).length())
	var local := Basis(Vector3.RIGHT, Vector3.UP, db)
	shaft.transform = Transform3D(world * local.inverse(), heel)


func _build_markers() -> void:
	var disc := PlaneMesh.new()
	disc.size = Vector2(1.3, 1.3)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING_SHADER
	ring = _add_mesh(self, disc, _ring_mat, Vector3(0, 0.025, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker = _add_mesh(self, _torus(0.42, 0.5), _unshaded(Color(1, 1, 1, 0.8)), Vector3(0, 0.02, 0))
	marker.visible = false
	_build_pass_mark()
	_build_aim_mark()

	spray = CPUParticles3D.new()
	spray.amount = 48
	spray.lifetime = 0.45
	spray.local_coords = false
	spray.emitting = false
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var flake_mat := _unshaded(Color(0.95, 0.97, 1.0))
	flake_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_mat
	spray.mesh = flake
	spray.direction = Vector3(0, 1, 0)
	spray.spread = 55.0
	spray.initial_velocity_min = 1.5
	spray.initial_velocity_max = 4.0
	spray.gravity = Vector3(0, -9.8, 0)
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.4
	add_child(spray)

	_tag = Label3D.new()
	_tag.font_size = 64
	_tag.pixel_size = 0.004
	_tag.outline_size = 14
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position = Vector3(0, 2.5, 0)
	_tag.visible = false
	add_child(_tag)
	_name_tag = Label3D.new()
	_name_tag.font_size = 40
	_name_tag.pixel_size = 0.00036
	_name_tag.fixed_size = true    # readable at any camera distance
	_name_tag.offset = Vector2(0, 75)   # above the player on screen, even from overhead
	_name_tag.outline_size = 12
	_name_tag.outline_modulate = Color(0, 0, 0, 0.85)
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.no_depth_test = true
	_name_tag.position = Vector3(0, 2.8, 0)
	_name_tag.visible = false
	add_child(_name_tag)
	for n in [shaft, blade, ring, marker, spray, _tag, _name_tag]:
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func set_marker(on: bool) -> void:
	_marker_on = on


## A ring at the receiver's feet and an arrow over their head, in the passer's player color.
## It lives on the passer's visual (top level) and follows whoever the stick points at.
func _build_pass_mark() -> void:
	_pass_mark = Node3D.new()
	_pass_mark.top_level = true
	_pass_mark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pass_mark.visible = false
	add_child(_pass_mark)
	_pass_mark_mat = _unshaded(Color(1, 1, 1, 0.85))
	_pass_mark_mat.no_depth_test = true
	_pass_mark_mat.render_priority = 1
	var r := _add_mesh(_pass_mark, _torus(0.55, 0.68), _pass_mark_mat, Vector3(0, 0.03, 0))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.38
	cone.radial_segments = 4
	cone.rings = 1
	var a := _add_mesh(_pass_mark, cone, _pass_mark_mat, Vector3(0, 2.55, 0))
	a.name = "Arrow"
	a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const AIM_SHOW_RANGE := 20.0   ## the reticle shows inside this distance of the net (m)


## A small ring with a dot, standing on the goal line, facing the shooter.
func _build_aim_mark() -> void:
	_aim_mark = Node3D.new()
	_aim_mark.top_level = true
	_aim_mark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_aim_mark.visible = false
	add_child(_aim_mark)
	_aim_mark_mat = ShaderMaterial.new()
	_aim_mark_mat.shader = AIM_SHADER
	_aim_mark_mat.render_priority = 2
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := _add_mesh(_aim_mark, q, _aim_mark_mat, Vector3.ZERO)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_aim_mark(delta: float) -> void:
	var show := false
	if skater.is_human and skater.human_index >= 0 and skater.has_puck() and skater.can_act():
		var net := skater.attacking_net()
		var winding := skater.state == Skater.State.WINDUP
		if net and skater.global_position.distance_to(net.global_position) < AIM_SHOW_RANGE:
			var kind := &"slap" if winding and skater.windup_time > Skater.WRIST_WINDOW else &"wrist"
			var aim := skater.shot_aim()
			if skater._shot_on_net(kind, aim):
				show = true
				var want := skater.aimed_spot(kind, aim)
				# Glide between spots (the stick wobbles); snap when it first appears.
				_aim_pos = want if _aim_pos == Vector3.INF else _aim_pos.lerp(want, _ease(18.0, delta))
				_aim_mark.global_position = _aim_pos
				var c: Color = HumanBrain.PLAYER_COLORS[skater.human_index % 4]
				c.a = 1.0 if winding else 0.8
				_aim_mark_mat.set_shader_parameter("color", c)
				# A loaded slap shot is wilder: the ring opens up as it charges.
				_aim_mark.scale = Vector3.ONE * (1.0 + 0.4 * skater.shot_charge if winding else 1.0)
	if not show:
		_aim_pos = Vector3.INF
	_aim_mark.visible = show


func _update_pass_mark() -> void:
	var target: Skater = null
	if skater.is_human and skater.human_index >= 0 and skater.has_puck() and skater.can_act():
		target = skater.choose_pass_target(skater.pass_aim_dir())
	_pass_mark.visible = target != null
	if target == null:
		return
	var at: Vector3 = target.visual.global_position if target.visual else target.global_position
	var t := Time.get_ticks_msec() * 0.001
	_pass_mark.global_position = Vector3(at.x, 0.0, at.z)
	_pass_mark.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 9.0))
	var arrow := _pass_mark.get_node("Arrow") as Node3D
	arrow.position.y = 2.55 + 0.1 * sin(t * 6.0)
	arrow.rotation.y = t * 2.5
	var c: Color = HumanBrain.PLAYER_COLORS[skater.human_index % 4]
	c.a = 0.9
	_pass_mark_mat.albedo_color = c


# --- Clips -----------------------------------------------------------------------

## Plays a library clip over the given regions (legs, spine, arms: 0..1 each).
## `duration` < 0 holds until stop_clip(); `from` starts part-way in (clip seconds).
func play_clip(clip: String, regions: Vector3, duration := -1.0, speed := 1.0, blend := 0.12, from := 0.0) -> void:
	if not anim.has_animation(clip):
		return
	_clip = clip
	_clip_regions = regions
	_clip_left = duration if duration > 0.0 else INF
	_clip_fade = 1.0 / maxf(blend, 0.02)
	anim.play(clip, blend, speed)
	if face != null:
		face.react_to_clip(clip, duration)
	if from > 0.0:
		anim.seek(from, false)


func stop_clip(fade := 0.3) -> void:
	_clip_left = 0.0
	_clip_fade = 1.0 / maxf(fade, 0.02)


## Parked off the ice: sit (or stand at the boards) on a looping idle, stick put away.
## Each player starts at a random point in the loop, so the bench doesn't move as one.
func bench_pose(seated: bool) -> void:
	bench_seated = seated
	var pool: Array = SIT_LOOPS if seated else STAND_LOOPS
	var clip: String = pool[randi() % pool.size()]
	if not anim.has_animation(clip):
		bench_loop = ""
		return
	bench_loop = clip
	rig.clip_only = true
	_play_bench_loop()
	shaft.visible = false
	blade.visible = false
	_cast_shadows(false)


func _play_bench_loop() -> void:
	var len := anim.get_animation(bench_loop).length
	play_clip(bench_loop, Vector3.ONE, -1.0, randf_range(0.85, 1.1), 0.35, randf() * len)


func _set_bench_frozen(on: bool) -> void:
	if on == bench_frozen:
		return
	bench_frozen = on
	if anim:
		anim.active = not on
	if rig:
		rig.active = not on


## Off the ice, players cast no sun shadow: it falls on the bench and box floors where
## it barely shows, and drawing 15-odd players into every shadow map cost more than the
## players in the game. Each piece's own setting comes back with `on`.
func _cast_shadows(on: bool) -> void:
	for g: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		if on:
			if g.has_meta("bench_shadow"):
				g.cast_shadow = g.get_meta("bench_shadow")
				g.remove_meta("bench_shadow")
		elif g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g.set_meta("bench_shadow", g.cast_shadow)
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Back to playing (walking out through a door, or onto the ice).
func bench_off() -> void:
	if bench_loop == "":
		return
	bench_loop = ""
	_set_bench_frozen(false)
	rig.clip_only = false
	stop_clip(0.25)
	shaft.visible = true
	blade.visible = true
	_cast_shadows(true)


## A reaction from the bench or box: "cheer", "groan", "sulk" (just sent to the box) or
## "laugh". Plays once through, then back to the idle.
func bench_react(kind: String) -> void:
	if bench_loop == "" or not REACTIONS.has(kind):
		return
	var pool: Array = REACTIONS[kind][0 if bench_seated else 1]
	var clip: String = pool[randi() % pool.size()]
	if not anim.has_animation(clip):
		return
	var len := anim.get_animation(clip).length
	play_clip(clip, Vector3.ONE, clampf(len, 2.0, 4.2), randf_range(0.95, 1.1), 0.25)


func celebrate() -> void:
	if skater.is_down():
		return
	play_clip(CELEBRATIONS[randi() % CELEBRATIONS.size()], Vector3(0.0, 0.85, 1.0), 2.6, randf_range(0.9, 1.1), 0.25)


func _tick_clip(delta: float) -> void:
	_clip_left -= delta
	var want := _clip_regions if _clip_left > 0.0 else Vector3.ZERO
	if delta <= 0.0:
		_clip_w = want
	else:
		_clip_w = _clip_w.move_toward(want, _clip_fade * delta)
	if _clip_left <= 0.0 and _clip_w == Vector3.ZERO and anim.is_playing():
		anim.stop(true)
	rig.w_legs = 1.0 - _clip_w.x
	rig.w_spine = 1.0 - _clip_w.y
	rig.w_arms = 1.0 - _clip_w.z


## Reacts to skater state changes with clips (falls, hit reactions).
func _state_clips() -> void:
	var s := skater.state
	if s == _prev_state:
		return
	var was := _prev_state
	_prev_state = s
	match s:
		Skater.State.DOWN:
			# Both clips stand a beat before going over (falling_down starts dropping
			# 0.3 s in, knocked_down 0.5 s): start there, so the hit takes the legs out at
			# once. Their pelvis also travels a meter or more back; the skater's own slide
			# carries the body instead (lock_root).
			var big := skater._down_time > Skater.DOWN_TIME + 0.1
			rig.lock_root = true
			if big:
				play_clip("knocked_down", Vector3.ONE, -1.0, 1.5, 0.06, 0.5)
			else:
				play_clip("falling_down", Vector3.ONE, -1.0, 1.6, 0.06, 0.3)
		Skater.State.STUMBLE:
			# Pushed toward the left: the side-hit clip (it rocks that way); otherwise the
			# body-hit one. The jolt (_tick_jolt) tips the body the way the hit pushed.
			var to_left := skater.hit_dir.dot(skater.right_dir()) < -0.3
			play_clip("big_side_hit" if to_left else "hit_to_body", Vector3(0.0, 0.8, 0.7), Skater.STUMBLE_TIME + 0.15, 1.5, 0.05, 0.1)
		_:
			if was == Skater.State.DOWN:
				rig.lock_root = _fight_mode
				stop_clip(0.35)


# --- Per frame -------------------------------------------------------------------

## Where the blade rests in the ready stance without the puck (from the skater, flat): wide
## out on the forehand side, as posed in Blender (tools/blender/pose_rig.py). Only the
## look: gameplay keeps the puck at Skater.blade_rest(), and with the puck the blade
## goes to it.
func stance_blade() -> Vector3:
	return skater.heading * stance_blade_forward * hs + skater.right_dir() * skater.forehand_side() * stance_blade_side * hs


## The slap shot's swing at charge c (0..1, from the skater, flat frame): the blade starts
## low ahead on the forehand side, sweeps back around that side near the ice, then rises
## up behind the shoulder and over the head. The downswing runs it backward.
func _windup_arc(c: float) -> Vector3:
	var h := skater.heading
	var out := skater.right_dir() * skater.forehand_side()
	var sweep := smoothstep(0.0, 0.7, c)
	var rise := smoothstep(0.3, 1.0, c)
	var a := deg_to_rad(lerpf(20.0, windup_arc_end, sweep))
	var r := lerpf(0.95, windup_arc_reach, rise)
	return (h * cos(a) + out * sin(a)) * r * hs + Vector3.UP * lerpf(0.03, windup_arc_height, rise) * hs


## The follow-through after the blade leaves the ice, u 0..1: up and out toward the target,
## ending with the stick about level at chest height.
func _follow_end(u: float) -> Vector3:
	var h := skater.heading
	var out := skater.right_dir() * skater.forehand_side()
	return h * (0.95 + 0.6 * u) + out * (0.3 - 0.45 * u) + Vector3.UP * (0.03 + 1.05 * u)


## Jump straight to the skater's current pose (after a teleport).
func snap() -> void:
	if skater == null:
		return
	global_position = skater.global_position + Vector3.UP * display_lift
	_yaw = _heading_yaw()
	_blade = stance_blade()
	if anim and _clip != "":
		_clip_left = 0.0
		_clip_w = Vector3.ZERO
		anim.stop()
	_prev_state = skater.state
	rig.lock_root = _fight_mode or skater.is_down()
	_process(0.0)


func _heading_yaw() -> float:
	return atan2(-skater.heading.x, -skater.heading.z)


func _process(delta: float) -> void:
	if skater == null:
		return
	global_position = skater.get_global_transform_interpolated().origin + Vector3.UP * display_lift
	_set_bench_frozen(bench_loop != "" and _onscreen != null and not _onscreen.is_on_screen())
	if bench_frozen:
		return
	if bench_loop != "" and _clip_left <= 0.0:
		_play_bench_loop()   # a reaction finished: back to the idle
	_state_clips()
	_tick_clip(delta)
	_tick_helmet(delta)
	_pose(delta)
	_update_stick(delta)
	_update_human_tag()
	_update_pass_mark()
	_update_aim_mark(delta)
	marker.visible = _marker_on
	spray.emitting = skater.stopping
	spray.position = skater.heading * 0.2 + Vector3(0, 0.05, 0)


func _ease(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta) if delta > 0.0 else 1.0


func _pose(delta: float) -> void:
	var spd := skater.flat_speed()
	var vel := skater.velocity * Vector3(1, 0, 1)
	var side := skater.forehand_side()

	# Body yaw; a hockey stop turns the body sideways; a fall shows the back to the hit.
	var target_yaw := _heading_yaw() + yaw_offset
	if skater.stopping:
		target_yaw += deg_to_rad(80.0) * side
	if skater.is_down() and spd > 1.0:
		target_yaw = atan2(vel.x, vel.z)
	# A hip check turns the body side on, the lead hip at the target.
	var hip_turn_w := clampf(maxf(_check_load, _check_drive) * 1.5, 0.0, 1.0) if skater.check_kind == &"hip" else 0.0
	if hip_turn_w > 0.0 and not skater.is_down():
		var cd := skater._check_dir
		target_yaw = lerp_angle(target_yaw, atan2(-cd.x, -cd.z) + skater.check_lead * 1.2, hip_turn_w)
	# Down: turns quickly at first (the back to the hit, so the fall goes with the push),
	# then lazily as the slide settles.
	var yaw_rate := 14.0 + 6.0 * hip_turn_w
	if skater.is_down():
		yaw_rate = 16.0 if skater._state_time < 0.3 else 6.0
	_yaw = lerp_angle(_yaw, target_yaw, _ease(yaw_rate, delta))

	var lean_target := clampf(skater.turn_speed * spd * 0.035, -0.45, 0.45)
	if skater.stopping:
		lean_target = 0.3 * side
	if skater.is_down():
		lean_target = 0.0
	_lean = lerpf(_lean, lean_target, _ease(8.0, delta))

	var fast := clampf(spd / 9.0, 0.0, 1.0)
	# Ready stance: knees well bent, chest forward over the knees but the back fairly
	# straight and the head up. Driving hard folds forward more; coasting without the
	# puck straightens up a little.
	var crouch := 0.21 + fast * 0.07 + (0.04 if skater.turbo_active else 0.0) + (0.08 if skater.stopping else 0.0)
	var bend := stance_bend + _stride_amt * 0.22 + (0.08 if skater.turbo_active else 0.0)
	if skater.has_puck():
		bend += 0.12
	elif spd > 2.5:
		bend -= 0.12 * (1.0 - clampf(_stride_amt * 2.0, 0.0, 1.0))
	var twist := 0.0
	match skater.state:
		Skater.State.WINDUP:
			var c := skater.shot_charge if skater.windup_time > Skater.WRIST_WINDOW else 0.25
			twist = -side * (0.25 + 0.5 * c)
			crouch += 0.06 * c
			bend -= 0.45 * c   # stands up into the windup
		Skater.State.FOLLOW_THROUGH:
			twist = side * 0.45
			bend += 0.1
		Skater.State.CHECK:
			pass   # the check's own pose goes over the top (_check_pose)
		Skater.State.POKE:
			bend += 0.2
			crouch += 0.03
		Skater.State.DEKE:
			twist = side * 0.2
	twist += side * stance_twist
	if skater.has_puck():
		twist += side * 0.12
	_crouch = lerpf(_crouch, crouch, _ease(7.0, delta))
	_bend = lerpf(_bend, bend, _ease(8.0, delta))
	_twist = lerpf(_twist, twist, _ease(12.0, delta))
	_check_weights(delta)

	# Stride: cadence follows speed; amplitude follows how hard the skater is pushing.
	var pushing := clampf(skater.intent.move.length(), 0.0, 1.0)
	var amt := pushing * clampf(spd / 3.0, 0.35, 1.0) * (1.25 if skater.turbo_active else 1.0)
	if skater.stopping or skater.frozen or skater.state == Skater.State.CHECK:
		amt = 0.0
	if spd > skater.top_speed() * 1.02:
		amt *= 0.4
	# Pinning on the boards: short choppy strides in place, driving in.
	var pinning := skater.state == Skater.State.PIN
	if pinning:
		amt = maxf(amt, 0.4)
	elif skater.state == Skater.State.PINNED:
		amt = maxf(amt, 0.14)
	_stride_amt = lerpf(_stride_amt, amt, _ease(5.0, delta))
	_stride += delta * (4.5 + spd * 0.55 + (5.5 if pinning else 0.0))
	var backward := vel.length() > 0.8 and vel.normalized().dot(skater.heading) < -0.4

	# Skate sounds: a scrape per stride, a spray on hockey stops.
	if skater.stopping and not _was_stopping and spd > 3.0:
		Sfx.play("carve", global_position, clampf(spd - 10.0, -6.0, 0.0))
	_was_stopping = skater.stopping
	var half := int(floor(_stride / PI))
	if half != _stride_half:
		_stride_half = half
		if _stride_amt > 0.3 and delta > 0.0:
			Sfx.play("stride", global_position, -17.0 + 7.0 * _stride_amt)

	# The stride's rhythm in the upper body: each push sinks the hips and pumps the chest
	# forward; the hips turn with the legs and the shoulders against them, so the torso
	# winds and unwinds instead of riding the legs like a block.
	var push2 := 0.5 - 0.5 * cos(2.0 * _stride)     # 1 at the middle of each leg's push
	var sa := _stride_amt * (0.0 if skater.is_down() else 1.0)
	var legs_fwd := cos(_stride)                     # +1: the left foot forward
	rig.hips_drop = _crouch + push2 * stride_bob * sa
	rig.lean = _bend + _dip * dip_lean + push2 * stride_pump * sa
	rig.hips_yaw = -legs_fwd * hip_turn * sa
	rig.twist = _twist + legs_fwd * (counter_twist + hip_turn) * sa
	rig.top_rock = 0.05 + 0.07 * _free_arm
	rig.stride_phase = _stride
	rig.stride_amt = _stride_amt * (0.6 if backward else 1.0)
	rig.stride_dir = -1.0 if backward else 1.0
	# Settles where the bottom hand just reaches (a little short leaks the dip back out).
	var short := rig.bottom_short * (1.0 - rig.free_arm) if rig.arm_mode == SkaterRig.Arms.STICK and not skater.is_down() else -0.2
	_dip = lerpf(_dip, clampf(_dip + (short - 0.01) * 1.5, 0.0, dip_max), _ease(10.0, delta))
	rig.sway = sin(_stride) * 0.07 * _stride_amt - side * (stance_sway * (0.0 if skater.is_down() else 1.0) + _dip)
	rig.hips_shift = Vector3(-sin(_stride) * 0.05 * _stride_amt, 0, 0)
	# Feet about shoulder width apart when set, a little narrower in full stride.
	rig.stance = 0.24 if skater.stopping else lerpf(0.2, 0.15, _stride_amt)
	rig.toe_out = 0.08
	rig.arm_mode = SkaterRig.Arms.STICK
	rig.stick_side = side
	rig.grip_offset = GRIP_OFFSET * hs
	rig.grip_palm = GRIP_PALM * hs
	# Skating hard without the puck, the bottom hand comes off the stick to drive.
	var free := skater.state == Skater.State.SKATE and not skater.has_puck() and not skater.intent.shoot_held 			and skater._shoot_buffer <= 0.0 and not skater.stopping and _stride_amt > 0.45
	_free_arm = lerpf(_free_arm, 1.0 if free else 0.0, _ease(5.0 if free else 9.0, delta))
	rig.free_arm = _free_arm
	_check_pose()
	_pin_pose(delta)

	rig.breath = hold_breath
	if display_pose != "":
		_display_pose(delta)
	_tick_jolt(delta)
	var pitch := _jolt.x + _check_tilt.x + _pin_tilt.x
	var roll := _lean + roll_offset + _jolt.y + _check_tilt.y + _pin_tilt.y
	model.rotation = Vector3(pitch, _yaw, roll)


## Checking, in three beats. The load: sunk and coiled behind the lead shoulder, the stick
## pulled in. The drive: up and through the hit off the back skate, as big as what the hit
## did (`_check_size`). Then the finish, the drive easing back out into the stance. A check
## that hits nothing ends in a stumble forward instead (`_check_whiff`).
const CHECK_SIZES := {&"bump": 0.55, &"check": 0.8, &"big_hit": 1.0}

func _check_weights(delta: float) -> void:
	var checking := skater.state == Skater.State.CHECK
	var landed := skater.since_check_landed
	var t := skater._state_time
	if landed < _seen_landed:
		# The hit lands: the hitter's body pitches into it and springs back (the same
		# sprung tilt a hit taken kicks, smaller).
		_check_size = CHECK_SIZES.get(skater.landed_kind, 0.8)
		var local := Basis(Vector3.UP, model.rotation.y).inverse() * skater._check_dir
		_jolt_v += Vector2(local.z, -local.x) * clampf(skater.landed_power / 8.0, 0.4, 1.6) * 1.5
	_seen_landed = landed
	var coil := 0.0
	var drive := 0.0
	if landed < 0.55:
		drive = (1.0 - smoothstep(0.18, 0.55, landed)) * _check_size
	elif checking:
		# Nothing hit yet: the body starts to uncoil as the lunge runs out.
		coil = 1.0 - 0.8 * smoothstep(0.12, Skater.CHECK_TIME, t)
		drive = 0.7 * smoothstep(0.1, Skater.CHECK_TIME, t)
	_check_load = lerpf(_check_load, coil, _ease(26.0 if coil > _check_load else 14.0, delta))
	_check_drive = lerpf(_check_drive, drive, _ease(34.0 if drive > _check_drive else 7.0, delta))
	var missed := skater.since_check_missed
	var whiff := 0.0
	if missed < Skater.WHIFF_TIME and landed > missed:
		whiff = 1.0 - smoothstep(0.16, Skater.WHIFF_TIME, missed)
	_check_whiff = lerpf(_check_whiff, whiff, _ease(18.0 if whiff > _check_whiff else 9.0, delta))


func _check_pose() -> void:
	var ld := _check_load
	var dr := _check_drive
	var wh := _check_whiff
	var w := clampf(maxf(maxf(ld, dr), wh), 0.0, 1.0)
	rig.foot_offset[0] = Vector3.ZERO
	rig.foot_offset[1] = Vector3.ZERO
	rig.top_shift = Vector3.ZERO
	rig.free_hold = 0.0
	_check_tilt = Vector2.ZERO
	if w <= 0.001:
		return
	var lead := skater.check_lead        # +1: the right shoulder (or hip) leads
	var side := skater.forehand_side()   # +1: the bottom hand is the right one
	var bottom := 1 if side > 0.0 else 0
	var bx := -side                      # the bottom arm's own side in skeleton space (+X = left)
	# Skeleton space: +X the character's left, +Z ahead. Feet: [left, right].
	var back := 0 if lead > 0.0 else 1   # the skate away from the lead shoulder
	var front := 1 - back
	var free := 0.0                      # 0..1: the bottom hand off the stick
	match skater.check_kind:
		&"hip":
			# Folded low over the stick, the hips thrown at the target and the shoulders
			# tipped away from it, the far skate driving out the other way.
			var m := Basis(Vector3.UP, model.rotation.y).inverse() * skater._check_dir   # model space: -Z ahead, +X right
			var at := Vector3(-m.x, 0.0, -m.z)
			rig.hips_drop += 0.14 * ld + 0.1 * dr
			rig.lean += 0.4 * ld + 0.3 * dr
			rig.hips_shift += at * (0.06 * ld + 0.24 * dr)
			rig.stance += 0.07 * w
			var far := 0 if at.x < 0.0 else 1
			rig.foot_offset[far] = -at * (0.08 * ld + 0.26 * dr)
			rig.foot_offset[1 - far] = at * 0.08 * dr
			rig.sway += -at.x * (0.1 * ld + 0.2 * dr)
			_check_tilt = Vector2(-m.z * 0.14, m.x * 0.2) * dr
		&"shove":
			# Square to the target: the bottom hand cocked at the chest, then punched out
			# straight at shoulder height, the body stepping in behind it.
			free = 1.0
			rig.twist = lerpf(rig.twist, side * (-0.2 * ld + 0.4 * dr), w)
			rig.hips_drop += 0.04 * ld - 0.04 * dr
			rig.lean += 0.06 * ld + 0.16 * dr
			rig.hips_shift.z += 0.03 * ld + 0.12 * dr
			rig.foot_offset[bottom] = Vector3(0.0, 0.0, -0.1 * ld - 0.24 * dr)
			rig.foot_offset[1 - bottom] = Vector3(0.0, 0.0, 0.06 * ld + 0.14 * dr)
			var punch := clampf(dr * 1.6, 0.0, 1.0)
			rig.free_at = Vector3(-bx * 0.08, -0.2, 0.16).lerp(Vector3(-bx * 0.14, -0.03, 0.6), punch)
			rig.free_pole = Vector3(bx * 0.7, -0.6, -0.4).lerp(Vector3(bx * 0.3, -1.0, 0.0), punch)
			_check_tilt = Vector2(-0.07 * dr, 0.0)
		_:
			# Load: sunk onto bent knees, folded, the lead shoulder turned in and dipped at
			# the target, its forearm tucked across the chest. Drive: the legs straighten
			# up through the hit off the back skate (off the ice on a big one), the hips
			# follow the shoulder through and the whole body pitches over it.
			# Right shoulder forward = the torso turned to its left (rig twist +).
			rig.twist = lerpf(rig.twist, lead * (0.35 * ld + 0.95 * dr), w)
			rig.hips_yaw += lead * (0.1 * ld + 0.32 * dr)
			rig.hips_drop += 0.07 * ld - 0.16 * dr
			rig.lean += 0.18 * ld - 0.14 * dr
			rig.sway += -lead * (0.16 * ld - 0.07 * dr)
			rig.hips_shift += Vector3(-lead * 0.06 * dr, 0.0, 0.04 * ld + 0.17 * dr)
			rig.stance += 0.04 * ld
			var big := clampf((_check_size - 0.6) / 0.4, 0.0, 1.0)
			rig.foot_offset[back] = Vector3(lead * (0.05 * ld + 0.1 * dr), 0.13 * dr * big, -0.16 * ld - 0.44 * dr)
			rig.foot_offset[front] = Vector3(0.0, 0.0, 0.08 * ld + 0.1 * dr)
			_check_tilt = Vector2(-0.04 * ld - 0.11 * dr, -lead * 0.1 * dr)
			if lead == side:
				# The bottom hand's shoulder leads: that hand lets go and tucks, the top
				# hand carries the stick clear on the other side.
				free = 1.0
				rig.free_at = Vector3(-bx * 0.22, -0.2, 0.16).lerp(Vector3(-bx * 0.18, -0.1, 0.22), dr)
				rig.free_pole = Vector3(bx * 0.6, -0.8, 0.15)
			else:
				# The top hand's shoulder leads: both hands stay on, the top one drawn up
				# to the chest so the stick lies in tight across the body.
				rig.top_shift = Vector3(0.0, 0.22, -0.08) * maxf(ld, dr)
	# Off balance after a miss: carried on over the front skate, chest down, catching it.
	if wh > 0.001:
		rig.lean += 0.3 * wh
		rig.hips_drop += 0.05 * wh
		rig.hips_shift.z += 0.12 * wh
		rig.foot_offset[front] += Vector3(0.0, 0.0, 0.2 * wh)
		rig.foot_offset[back] += Vector3(0.0, 0.07 * wh, -0.22 * wh)
		_check_tilt += Vector2(-0.13 * wh, -lead * 0.08 * wh)
	var hold := clampf(maxf(ld, dr) * 1.5, 0.0, 1.0)
	rig.free_hold = free * hold
	rig.free_arm = lerpf(_free_arm, free, hold)


## Where the blade goes through a check (from the skater, flat frame).
func _check_blade() -> Vector3:
	var h := skater.heading
	var right := skater.right_dir()
	var side := skater.forehand_side()
	match skater.check_kind:
		&"hip":
			# Low across the front in both hands.
			return h * 0.7 + right * side * 0.25 + Vector3.UP * 0.08
		&"shove":
			# In the top hand alone, out of the way on its own side.
			return h * 0.9 - right * side * 0.75 + Vector3.UP * 0.15
	if skater.check_lead != side:
		# Both hands on, the top hand's shoulder leading: across the body, the blade out
		# past the far hip.
		return h * 0.25 + right * side * 0.9 + Vector3.UP * 0.5
	# In the top hand alone: pulled in on its own side, the blade up off the ice.
	return h * 0.9 - right * side * 0.6 + Vector3.UP * 0.35


## A board battle (BoardBattle). The one pinned: up against the boards, more upright than
## the skating stance (the glass is right there), hips back into the other, feet wide,
## the bottom hand off the stick and braced on the glass, looking back over the shoulder
## on the pinner's side. The one pinning: low behind them, hips driven in, the bottom
## hand's forearm barred across their back, chopping strides in place. Both sticks go to
## the puck at the pinned skater's skates; each jostle rocks both (_tick_jolt).
func _pin_pose(delta: float) -> void:
	var st := skater.state
	_pin_w = lerpf(_pin_w, 1.0 if st == Skater.State.PIN else 0.0, _ease(12.0 if st == Skater.State.PIN else 7.0, delta))
	_pinned_w = lerpf(_pinned_w, 1.0 if st == Skater.State.PINNED else 0.0, _ease(12.0 if st == Skater.State.PINNED else 7.0, delta))
	_pin_tilt = Vector2.ZERO
	if skater.battle != null:
		_pin_puck = skater.battle.puck_spot()
		_pin_side = skater.battle.side
	var w := maxf(_pin_w, _pinned_w)
	if w <= 0.001:
		return
	var side := skater.forehand_side()   # +1: the bottom hand is the right one
	var bx := -side                      # the bottom arm's own side in skeleton space (+X = left)
	rig.free_arm = lerpf(rig.free_arm, 1.0, w)
	rig.free_hold = maxf(rig.free_hold, w)
	if _pinned_w >= _pin_w:
		var p := _pinned_w
		rig.lean = lerpf(rig.lean, 0.32, p)
		rig.hips_shift.z -= 0.1 * p
		rig.hips_drop += 0.02 * p
		rig.stance += 0.07 * p
		rig.twist = lerpf(rig.twist, -_pin_side * 0.28, p)
		rig.free_at = Vector3(bx * 0.08, 0.1, 0.36)
		rig.free_pole = Vector3(bx * 0.7, -0.7, -0.1)
		_pin_tilt = Vector2(-0.05 * p, 0.0)
	else:
		var q := _pin_w
		rig.lean = lerpf(rig.lean, 0.5, q)
		rig.hips_shift.z += 0.08 * q
		rig.hips_drop += 0.05 * q
		rig.stance += 0.06 * q
		rig.twist = lerpf(rig.twist, side * 0.3, q)
		rig.free_at = Vector3(-bx * 0.1, -0.05, 0.38)
		rig.free_pole = Vector3(bx * 0.9, -0.25, 0.0)
		_pin_tilt = Vector2(-0.08 * q, 0.0)


## The hit-reaction tilt: each new hit kicks it away from the hitter, a stiff spring
## pulls it back within about a third of a second.
func _tick_jolt(delta: float) -> void:
	if skater.since_hit < _seen_hit:
		var yb := Basis(Vector3.UP, model.rotation.y)
		var local := yb.inverse() * skater.hit_dir
		var k := clampf(skater.hit_power / 8.0, 0.4, 1.6) * 3.2
		# Pushed toward the model's back (+Z): the head goes back (pitch +); pushed to the
		# model's left (-X): the head goes left (roll +).
		_jolt_v += Vector2(local.z, -local.x) * k
	_seen_hit = skater.since_hit
	if skater.pin_bump != _seen_bump:
		# A jostle in a board battle rocks both bodies the way it pushed.
		_seen_bump = skater.pin_bump
		var bump := Basis(Vector3.UP, model.rotation.y).inverse() * skater.pin_bump_dir
		_jolt_v += Vector2(bump.z, -bump.x) * 2.5
	if delta <= 0.0:
		return
	_jolt_v += (-_jolt * 170.0 - _jolt_v * 15.0) * delta
	_jolt += _jolt_v * delta
	if _jolt.length() < 0.001 and _jolt_v.length() < 0.01:
		_jolt = Vector2.ZERO
		_jolt_v = Vector2.ZERO


## "P1".."P4" tag, number and name, and the ring for human-controlled skaters. The ring is
## two meters: sprint (stamina) as the wide outer arc, green through yellow to red, and legs
## (shift energy) as the thin blue arc inside it. Both drain back toward the top of the screen.
## While a slap shot is held, the middle fills orange from the center until it's fully charged.
func _update_human_tag() -> void:
	ring.visible = skater.is_human
	var show_tag := skater.is_human and skater.human_index >= 0
	if skater.is_human:
		var st := clampf(skater.stamina, 0.0, 1.0)
		_ring_mat.set_shader_parameter("sprint", st)
		_ring_mat.set_shader_parameter("sprint_color", Color.from_hsv(0.33 * st, 0.85, 0.95))
		_ring_mat.set_shader_parameter("legs", clampf(skater.energy, 0.0, 1.0) if skater.fatigue_enabled else 1.0)
		# Sprint used up: the track pulses red until it's back (Skater unlocks turbo at 25%).
		var locked: bool = skater._turbo_locked
		_ring_mat.set_shader_parameter("flash", (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)) if locked else 0.0)
		var loading := skater.state == Skater.State.WINDUP and skater.windup_time > Skater.WRIST_WINDOW
		_ring_mat.set_shader_parameter("charge", maxf(0.05, skater.shot_charge) if loading else 0.0)
	if _tag:
		_tag.visible = show_tag
	if _name_tag:
		_name_tag.visible = show_tag
		if show_tag:
			_name_tag.text = ("#%d  %s" % [skater.number, skater.last_name.to_upper()]) if skater.last_name != "" else "#%d" % skater.number
	if show_tag:
		var c: Color = HumanBrain.PLAYER_COLORS[skater.human_index % 4]
		_ring_mat.set_shader_parameter("player_color", c)
		if _tag:
			_tag.text = "P%d" % (skater.human_index + 1)
			_tag.modulate = c


func _update_stick(delta: float) -> void:
	if display_pose != "":
		return
	var h := skater.heading
	var right := skater.right_dir()
	var side := skater.forehand_side()
	var target: Vector3
	var follow := _ease(25.0, delta)

	match skater.state:
		Skater.State.WINDUP when skater.windup_time > Skater.WRIST_WINDOW:
			# Swings back around to the forehand side, then up over the head.
			_swing_charge = skater.shot_charge
			target = _windup_arc(_swing_charge)
			follow = _ease(22.0, delta)
		Skater.State.POKE:
			target = h * 1.7 + right * side * 0.1 + Vector3.UP * 0.03
			follow = _ease(40.0, delta)
		Skater.State.DOWN:
			target = h * 0.2 + right * skater.fall_side * 0.9 + Vector3.UP * 0.05
			follow = _ease(10.0, delta)
		Skater.State.FOLLOW_THROUGH:
			# Down onto the ice at the puck first, then up and out toward the target, the
			# stick ending about level at chest height.
			var t := clampf(skater._state_time / Skater.FOLLOW_TIME, 0.0, 1.0)
			if t < FOLLOW_IMPACT:
				# The downswing comes back along the windup's arc to the puck.
				target = _windup_arc(_swing_charge * (1.0 - t / FOLLOW_IMPACT))
			else:
				target = _follow_end((t - FOLLOW_IMPACT) / (1.0 - FOLLOW_IMPACT))
			follow = _ease(30.0, delta)
			_follow_hold = FOLLOW_HOLD
		_ when _follow_hold > 0.0 and not skater.has_puck() and not skater.is_down():
			# The finish holds a moment after the shot's (gameplay) follow-through ends.
			_follow_hold -= delta
			target = _follow_end(1.0)
			follow = _ease(30.0, delta)
		_:
			_follow_hold = 0.0
			if skater.has_puck():
				var p := skater.puck.get_global_transform_interpolated().origin
				target = p - global_position
				target += (target * Vector3(1, 0, 1)).normalized() * 0.05
				# Cupped behind the puck, not on top of it: the puck rides against the
				# blade's front face.
				target -= Vector3(h.x, 0.0, h.z).normalized() * (skater.puck.visual_radius() + 0.01)
				target.y = 0.03
				follow = 1.0
			elif skater.intent.shoot_held or skater._shoot_buffer > 0.0:
				target = right * side * 0.6 - h * 0.1 + Vector3.UP * 0.8 # loaded for a one-timer
			else:
				target = stance_blade()
				target.y = 0.03
	# A check, and its finish after the skater is skating again: the stick stays pulled in.
	var cw := clampf(maxf(_check_load, _check_drive) * 1.5, 0.0, 1.0)
	if cw > 0.01 and not skater.has_puck() and not skater.is_down():
		target = target.lerp(_check_blade(), cw)
		follow = maxf(follow, _ease(25.0, delta))
	# A board battle: both blades at the puck by the boards, the pinner's jabbing at it.
	var bw := maxf(_pin_w, _pinned_w)
	if bw > 0.01 and not skater.has_puck() and not skater.is_down():
		var at_puck := _pin_puck - global_position
		at_puck.y = 0.03
		if _pin_w > _pinned_w:
			at_puck += right * sin(_stride * 2.0) * 0.07
		target = target.lerp(at_puck, bw)
		follow = maxf(follow, _ease(20.0, delta))
	# While a clip owns the arms (celebrating), the stick hangs from the top hand.
	if _clip_w.z > 0.5 and not skater.is_down():
		target = (rig.top_hand_world - global_position) + h * 0.5 + Vector3.DOWN * 1.1
		follow = _ease(10.0, delta)
	_blade = _blade.lerp(target, follow) if delta > 0.0 else target
	# The hands close on the shaft's line, which runs down to the heel (not to the puck
	# point out along the blade); last frame's butt end gives its direction.
	var top := to_local(rig.stick_top_world) if rig.stick_top_world != Vector3.ZERO else _blade
	rig.blade_world = global_position + _heel(top, _blade)


## Menu display poses: a clip on the whole body (looping, or held on its last frame;
## "hold": one frame of it held, at that many clip seconds), the stick placed from the
## hands each frame:
##   "low" / "high": the lower / higher hand holds it upright, planted on the ice beside
##       that hand ("high": the hand rests on the butt end)
##   "both": upright from the middle of the two hands down to the ice in front
##   "level": through both hands, the blade out past the stick-side hand, pointing up
##   "still" / "hold": a one-frame pose: SkaterRig.breath keeps it alive
##   "back": m the stick sits behind the hands (across the shoulders, behind the neck)
##   "fixed": the stick at "heel" / "top" (x out to the stick side, z forward, meters for
##       a 1.8 m body), moving with the chest (the breath), and the arms posed onto it
##       ("grips"); the clip drives only "regions" (legs, spine, arms)
const DISPLAY_SPEC := {
	"middle": {"clip": "fishing_idle", "stick": "both"},
	"side": {"clip": "holding_idle", "stick": "low"},
	"rest": {"clip": "male_standing_pose", "stick": "low", "still": true},
	"lean": {"clip": "male_standing_pose_1", "stick": "high", "still": true},
	"across": {"clip": "fishing_idle", "hold": 0.0, "regions": Vector3(1, 1, 0), "stick": "fixed",
		"heel": Vector3(0.66, 1.1, 0.24), "top": Vector3(-0.6, 1.04, 0.22), "out": Vector3(0.15, 1.0, 0.0),
		# [stick-side hand, other hand]: where along the stick (0 heel .. 1 butt end), and the
		# way the back of the glove faces: under it (palm up) at the blade end, over it
		# (palm down) at the butt end.
		"grips": [[0.32, "under"], [0.8, "over"]]},
	"shoulders": {"clip": "back_squat", "hold": 9.3, "stick": "level"},
	"hips": {"clip": "female_standing_pose", "stick": "low", "still": true},
	"hips_b": {"clip": "female_standing_pose_2", "stick": "low", "still": true},
}
const STICK_LEN := 1.5   ## heel to butt end (m, 1.8 m body)


func _display_pose(delta: float) -> void:
	var spec: Dictionary = DISPLAY_SPEC.get(display_pose, DISPLAY_SPEC["side"])
	if _clip != spec.clip:
		var held := spec.has("hold")
		play_clip(spec.clip, spec.get("regions", Vector3.ONE), -1.0, 0.0 if held else 1.0, 0.05, float(spec.get("hold", 0.0)))
		_disp_age = 0.0
		_disp_chest_ref = Transform3D()
	_disp_age += delta
	rig.hold_x[0] = Vector3.ZERO
	rig.hold_x[1] = Vector3.ZERO
	rig.breath = 1.0 if spec.get("still", false) or spec.has("hold") else 0.0
	if spec.stick == "fixed":
		_display_arms(spec)


## The x-out / up / forward frame of DISPLAY_SPEC positions, to local (scaled).
func _display_frame(v: Vector3) -> Vector3:
	return (skater.right_dir() * skater.forehand_side() * v.x + Vector3.UP * v.y + skater.heading * v.z) * hs


## "fixed" poses: the stick where the spec puts it, the arms posed onto it.
func _display_arms(spec: Dictionary) -> void:
	# The stick rides on the chest: breathing lifts and sways it, and the arms with it.
	var chest: Transform3D = global_transform.affine_inverse() * skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Spine2"))
	var follow := Transform3D.IDENTITY
	if _disp_age > 0.3:
		if _disp_chest_ref == Transform3D():
			_disp_chest_ref = chest
		follow = chest * _disp_chest_ref.affine_inverse()
	_disp_heel = follow * _display_frame(spec.heel)
	_disp_top = follow * _display_frame(spec.top)
	_disp_out = (follow.basis * _display_frame(spec.out)).normalized()
	rig.arm_mode = SkaterRig.Arms.FREE
	var xo := skater.right_dir() * skater.forehand_side()
	var near := 1 if skater.forehand_side() > 0.0 else 0   # the stick-side hand (0 left, 1 right)
	var axis := (_disp_top - _disp_heel).normalized()
	for g in 2:
		var k := near if g == 0 else 1 - near
		var grip: Array = spec.grips[g]
		var at := _disp_heel.lerp(_disp_top, float(grip[0]))
		rig.hand_world[k] = global_position + at - rig.grip_from_hand[k]
		var outward := xo if k == near else -xo
		# Over the stick the thumb points along it toward the other hand, under it away.
		rig.hold_x[k] = outward if grip[1] == "over" else -outward
		rig.hold_back[k] = (Vector3.UP if grip[1] == "over" else Vector3.DOWN) + skater.heading * 0.35


## Where the display pose's stick goes (local): sets _disp_top / _disp_heel / _disp_out.
func _display_stick() -> void:
	var spec: Dictionary = DISPLAY_SPEC.get(display_pose, DISPLAY_SPEC["side"])
	var to_world := skel.global_transform
	var g: Array[Vector3] = []
	for k in 2:
		g.append(to_local(to_world * (rig.grip_debug[k][0] as Vector3)) if not (rig.grip_debug[k] as Array).is_empty() else Vector3.ZERO)
	var fw := to_local(global_position + skater.heading)
	var len := STICK_LEN * hs
	match spec.stick:
		"fixed":
			pass   # set in _display_arms
		"level":
			var near := 1 if skater.forehand_side() > 0.0 else 0
			var mid := (g[0] + g[1]) * 0.5
			var ax := (g[near] - g[1 - near]).normalized()
			mid -= fw * float(spec.get("back", 0.0)) * hs
			_disp_heel = mid + ax * (g[0].distance_to(g[1]) * 0.5 + 0.28 * hs)
			_disp_top = _disp_heel - ax * len
			_disp_out = Vector3.UP
		"both":
			var mid := (g[0] + g[1]) * 0.5
			_disp_top = mid + Vector3.UP * 0.06 * hs
			_disp_heel = Vector3(mid.x, 0.0, mid.z) + fw * 0.12 * hs
			_disp_out = fw + to_local(global_position + skater.right_dir()) * 0.4
		_:
			var k := 0 if (g[0].y < g[1].y) == (spec.stick == "low") else 1
			var h := g[k]
			var outward := Vector3(h.x, 0.0, h.z)
			outward = outward.normalized() if outward.length() > 0.01 else fw
			var foot := Vector3(h.x, 0.0, h.z) + outward * (0.22 if spec.stick == "high" else 0.1) * hs + fw * 0.08 * hs
			var ax := (h - foot).normalized()
			_disp_heel = foot
			_disp_top = h if spec.stick == "high" else foot + ax * len
			_disp_out = (fw + outward * 0.6).normalized()


## Called once the skeleton (with the rig) is posed: the stick runs from the top hand
## to the blade.
func _after_rig() -> void:
	if display_pose != "":
		_display_stick()
		_place_stick(_disp_top, _disp_heel, skater.heading, _disp_out, true)
		return
	var top := to_local(rig.stick_top_world)
	_place_stick(top, _heel(top, _blade), skater.heading - skater.right_dir() * skater.forehand_side())

## The heel (the corner where the shaft's line meets the blade's bottom line) for the
## puck point `bl`: back along the blade toward the hands, down on the ice under the puck.
func _heel(top: Vector3, bl: Vector3) -> Vector3:
	var flat := Vector3(bl.x - top.x, 0.0, bl.z - top.z)
	var heel := bl - flat.normalized() * STICK_PUCK * hs if flat.length() > 0.05 else bl
	heel.y = maxf(heel.y - 0.03, 0.0)
	return heel


# --- Mesh helpers ----------------------------------------------------------------

func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 4
	return m


static var _unit_sphere: SphereMesh

## Unit sphere; pass Basis.from_scale(radii) to attach() for an ellipsoid.
## A copy of `mesh` dressed like the outfit layer, for bulk under the uniform placed at
## `at` / `basis` (rest pose): torso part, position up the torso, and rest position (from
## the base of the neck) and normal, so uniform.gdshader draws the same jersey / pants
## split, stripes, yoke and fabric on it as on the cloth around it.
func _cloth_mesh(mesh: Mesh, at: Vector3, basis: Basis) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var neck := bone_pos("Neck")
	var hips := bone_pos("Hips")
	var nb := basis.inverse().transposed()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var rest_p := PackedFloat32Array()
	var rest_n := PackedFloat32Array()
	for i in verts.size():
		var p := at + basis * verts[i]
		var n := (nb * norms[i]).normalized()
		colors.append(Color(1, 0, 0, 0))
		uv2.append(Vector2(0, (p.y - hips.y) / maxf(neck.y - hips.y, 0.01)))
		var q := (p - neck) * (0.6 / maxf(neck.y - hips.y, 0.01))   # as tools/build_characters.gd REST_TORSO
		rest_p.append_array([q.x, q.y, q.z])
		rest_n.append_array([n.x, n.y, n.z])
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = rest_p
	arr[Mesh.ARRAY_CUSTOM1] = rest_n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		(Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return out


func _sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
		_unit_sphere.radial_segments = 20
		_unit_sphere.rings = 10
	return _unit_sphere


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 32
	m.ring_segments = 6
	return m


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
