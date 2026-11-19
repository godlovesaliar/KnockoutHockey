class_name GoalieVisual
extends SkaterVisual
## Goalie body: the shared skeleton with pads, glove, blocker, chest protector and mask.
## Wide crouched stance, butterfly drop on low shots, glove / blocker reach on saves,
## stick paddle flat on the ice in front of the pads.

## Mask models (tools/blender/goalie_mask_gear.py via tools/build_gear.gd), in the helmets'
## frame. Skater.gear_style picks one: a created player's own choice (an index, as
## CustomPlayers.MASK_NAMES), or a roll (SkaterVisual.gear_roll) weighted by `weight`, so
## most goalies wear the modern mask. Per mask:
##   surfaces  what each of the mesh's surfaces is: shell (team color), liner (the shell's
##             dark inside; the combo's dark parts), cage, trim (backplate, pads and
##             straps), white (the combo's helmet trim)
##   helmet    fitted as the skaters' helmets are (it is one), not on the eyes
##   squeeze   the pressed-down hair pulled in under a shell that sits closer to the
##             temples than a helmet does
##   beard     false where facial hair would poke through (the molded mask is on the face)
##   paint     the mask's letter in its paint textures' names (MASK_PAINTS), if it can be
##             painted (the combo is a plain helmet)
const MASKS := [
	# Modern: a shell standing off the head, wraparound cage, backplate and straps.
	{"mesh": preload("res://assets/characters/goalie_mask.res"), "surfaces": ["shell", "liner", "cage", "trim"],
		"weight": 5, "squeeze": Vector3(0.8, 1.0, 1.0), "paint": "a"},
	# Helmet and cage: the classic skater helmet with a full wire cage.
	{"mesh": preload("res://assets/characters/goalie_mask_b.res"), "surfaces": ["shell", "liner", "cage", "white"],
		"weight": 2, "helmet": true},
	# '80s: a rounder, closer shell, a straight-bar cage, a big backplate.
	{"mesh": preload("res://assets/characters/goalie_mask_c.res"), "surfaces": ["shell", "liner", "cage", "trim"],
		"weight": 2, "squeeze": Vector3(0.8, 1.0, 1.0), "paint": "c"},
	# Molded: a one-piece 1970s fiberglass mask over the whole face and forehead.
	{"mesh": preload("res://assets/characters/goalie_mask_d.res"), "surfaces": ["shell", "liner", "trim"],
		"weight": 2, "squeeze": Vector3(0.8, 0.6, 0.88), "beard": false, "paint": "d"},
]

## Paint jobs (tools/blender/goalie_mask_paint.py; scenes/actors/mask_paint.gdshader): a
## pattern texture per mask shape, res://assets/characters/masks/mask_<mask>_<name>.png,
## and the color schemes it suits. A scheme names the base, accent 1, accent 2 and detail
## colors: P the team's jersey color, S its trim, W white, K black. Each goalie's design
## and scheme come from their name and number, the same every game; one in five wears the
## mask plain.
const MASK_PAINTS := [
	{"name": "flames", "schemes": ["WPSK", "KPSW", "PSWK"]},    # flames, their core, their edge
	{"name": "beast", "schemes": ["PKKW", "PSKW", "SKKW"]},     # stripes, gums and brows, teeth and eyes
	{"name": "wings", "schemes": ["WPKS", "PWKS"]},             # feathers, their edges, pinstripes
	{"name": "burst", "schemes": ["WPSK", "PSWK", "KPSW"]},     # spikes, their hearts, their edges
	{"name": "stars", "schemes": ["WPSW", "WSPW"]},             # field, bars, stars
	{"name": "bolts", "schemes": ["WSPK", "KSPW"]},             # lightning, cloud, edges
	{"name": "sweep", "schemes": ["WPSK", "PSWK", "KPSW"]},     # blades, their echoes, pinstripe
	{"name": "stitches", "schemes": ["WPSK", "PSKW"]},          # (stitches are the detail color)
]
const MASK_PAINT_SHADER := preload("res://scenes/actors/mask_paint.gdshader")
const MASK_PAINT_DIR := "res://assets/characters/masks/"
## For tools (the character viewer's `paint=`): a design name every goalie wears, "plain"
## for none, or "" for each goalie's own.
static var paint_override := ""


## The paint material for a mask shell: `letter` the mask's (MASKS.paint), `seed` the
## goalie's own number; null for a plain mask.
static func mask_paint(letter: String, c: Dictionary, seed: int) -> ShaderMaterial:
	var design: Dictionary = MASK_PAINTS[(seed / 5) % MASK_PAINTS.size()]
	if paint_override != "":
		design = {}
		for d: Dictionary in MASK_PAINTS:
			if d.name == paint_override:
				design = d
	elif seed % 5 == 0:
		design = {}
	if design.is_empty():
		return null
	var path := "%smask_%s_%s.png" % [MASK_PAINT_DIR, letter, design.name]
	if not ResourceLoader.exists(path):
		return null
	var scheme: String = design.schemes[(seed / 47) % (design.schemes as Array).size()]
	# The team's two colors, kept apart: a trim too close to the jersey (or to white, where
	# the scheme has white beside it) gives way to the other candidates.
	var primary: Color = c.jersey
	var secondary: Color = c.trim
	for alt: Color in [c.trim, c.get("number_outline", c.trim), c.get("helmet", c.trim), primary.lightened(0.45), primary.darkened(0.5)]:
		secondary = alt
		if _apart(alt, primary) and (not scheme.contains("W") or _apart(alt, Color(0.94, 0.94, 0.92))) \
				and (not scheme.contains("K") or _apart(alt, Color(0.05, 0.05, 0.06))):
			break
	var cols := {"P": primary, "S": secondary, "W": Color(0.94, 0.94, 0.92), "K": Color(0.05, 0.05, 0.06)}
	var key := "maskpaint|%s|%s|%s|%s" % [path, scheme, primary.to_html(), secondary.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = MASK_PAINT_SHADER
		m.set_shader_parameter("pattern", load(path))
		m.set_shader_parameter("base_color", cols[scheme[0]])
		m.set_shader_parameter("accent1", cols[scheme[1]])
		m.set_shader_parameter("accent2", cols[scheme[2]])
		m.set_shader_parameter("detail", cols[scheme[3]])
		_materials[key] = m
	return _materials[key]


static func _apart(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.33


## The MASKS index a gear_style stands for.
static func mask_index(gear_style: int) -> int:
	if gear_style < GEAR_ROLL:
		return gear_style % MASKS.size()   # a created player's choice
	var total := 0
	for m: Dictionary in MASKS:
		total += int(m.weight)
	var k := ((gear_style - GEAR_ROLL) / 2) % total
	for i in MASKS.size():
		k -= int(MASKS[i].weight)
		if k < 0:
			return i
	return 0


const GOALIE_STICK_MESH := preload("res://assets/characters/goalie_stick.res")
## Goalie trapper (tools/blender/goalie_gear.py): origin at the hand, +Y on along the
## forearm's line (the cuff back up the wrist), pocket +Z, thumb -X.
const CATCHER_MESH := preload("res://assets/characters/goalie_catcher.res")
## Modeled pads (tools/blender/goalie_gear.py), sized for a 1.8 m body. Pad: a left pad,
## origin at the ankle, +Y up the shin (0.42 m to the knee), +Z forward, +X outward (the
## right one is mirrored). Thigh rise: the same from the knee, on up the shin's line. Blocker: in the
## right hand's limb frame, origin at the wrist, board on +Z.
const PAD_MESH := preload("res://assets/characters/goalie_pad.res")
const BOOT_MESH := preload("res://assets/characters/goalie_boot.res")    ## the pad's boot: same frame, rides the foot
const THIGH_MESH := preload("res://assets/characters/goalie_thigh.res")
const BLOCKER_MESH := preload("res://assets/characters/blocker.res")
const PAD_SHIN := 0.42
## The stick is held at its own lie (the blade-to-shaft angle of the model): the shaft
## runs down through the blocker hand to the ice at that angle, the paddle leaned back
## toward the goalie this much, and the blade lies across the crease from there.
const STICK_TILT := deg_to_rad(15.0)
## The blocker's ready position (model space, 1.8 m body): low and out beside the pad.
const BLOCKER_READY := Vector3(0.42, 0.68, -0.42)

## Skating somewhere instead of tending the net (out of the bench door, to and from the
## crease): upright and loose, a long relaxed stride, the glove swinging with it and the
## stick carried in the blocker hand, its blade skimming the ice ahead.
const CARRY_GLOVE := Vector3(-0.36, 0.8, -0.1)
const CARRY_BLOCKER := Vector3(0.36, 0.8, -0.34)
## Farther than this out from the goal line (m) the goalie is traveling, not in the crease.
const CREASE_OUT := 4.0

var goalie: Goalie
var _drop := 0.0
var _blocker_k := 0.0   ## how far a blocker save has the stick following the hand instead
var _travel := 0.0      ## 0 in the crease .. 1 skating somewhere (see CARRY_GLOVE)
var _swing := 0.0       ## the arms' swing with the stride (-1..1), eased
var _was_traveling := false

## Saves. A save is an action played over the stance: the goalie starts moving as soon as
## the shot is read (Goalie.read_eta under SAVE_LEAD), so the glove, blocker or pad gets
## there with the puck rather than after it, then holds the save and recovers. Kinds, from
## where the puck crosses (sideways from the goalie, height):
##   "butterfly"  low and close: drop to the knees
##   "pad"        low and wider: drop, the near pad kicked out along the ice
##   "stack"      low and far: laid out on the side across the ice, arm reaching
##   "reach"      up and close: glove or blocker snaps out to it, body leaning in
##   "dive"       up and far: a sideways dive, the near hand stretched to the puck
const SAVE_LEAD := 0.3
const SAVE_TIMES := {   ## kind -> [hold, recover] seconds after the impact
	"butterfly": [0.4, 0.4], "pad": [0.45, 0.5], "stack": [0.7, 0.7],
	"reach": [0.3, 0.35], "dive": [0.55, 0.65],
}
var _act_on := false
var _act_t := 0.0        ## s since the save started
var _act_hit := 0.2      ## s from its start to the impact
var _act_spot := Vector3.ZERO   ## where the puck meets the goalie (world)
var _act_from := Vector3.ZERO   ## where the goalie stood when the save started (it slides over too)
var _act_kind := "reach"
var _act_side := 1.0     ## +1 glove side (the goalie's left), -1 blocker side
var _act_catch := false
var _act_w := 0.0        ## the save's weight over the stance this frame
var _seen_saves := 0
var _counter := Vector3.ZERO   ## world: holds the body back from the goalie's slide during a save
var _hold_w := 0.0       ## holding a caught puck: the glove drawn in to the chest


func build(sk: Skater) -> void:
	goalie = sk as Goalie
	super.build(sk)
	if face != null:
		face.set_expression("focused")


func _build_gear() -> void:
	var c := team_colors()
	var head := anchor_box("head", "Head", Vector3(0.2, 0.25, 0.22) * hs)
	if TEAM_MASKS.has(c.get("headgear", "")):
		_build_team_mask(head, c)   # a team's mask (the Campers' vintage one) instead
	else:
		_build_goalie_mask(head, c)
	var chest := anchor_box("chest", "Spine2", Vector3(0.36, 0.2, 0.24) * hs)
	var cc := chest.get_center()
	var cr := Vector3(maxf(chest.size.x * 0.75, 0.3 * hs), 0.2 * hs, maxf(chest.size.z * 0.75, 0.2 * hs))
	var cloth := uniform_material(c)   # hip bulk: same uniform as the cloth layer
	# The goalie cut of the jersey (room for a chest protector and arm pads) instead of
	# the skater's; bodies without one get chest and belly bulk under the skater jersey.
	var goalie_jersey := skel.get_node_or_null("Outfit_GoalieJersey") as MeshInstance3D
	if goalie_jersey != null:
		goalie_jersey.visible = true
		var skater_jersey := skel.get_node_or_null("Outfit_Jersey") as MeshInstance3D
		if skater_jersey != null:
			skater_jersey.visible = false
	var hips := anchor_box("hips", "Hips", Vector3(0.34, 0.2, 0.24) * hs)
	var hipc := hips.get_center()
	if goalie_jersey == null:
		attach("Spine2", _cloth_mesh(_sphere(), cc, Basis.from_scale(cr)), cloth, cc, Basis.from_scale(cr))
		var belly_at := Vector3(hipc.x, lerpf(hipc.y, cc.y, 0.5), lerpf(hipc.z, cc.z, 0.5) + 0.03 * hs)
		var belly_b := Basis.from_scale(Vector3(0.22, 0.16, 0.17) * hs)
		attach("Spine", _cloth_mesh(_sphere(), belly_at, belly_b), cloth, belly_at, belly_b)
	var hips_at := hipc - Vector3(0, 0.07 * hs, 0)
	var hips_b := Basis.from_scale(Vector3(maxf(hips.size.x * 0.62, 0.23 * hs), 0.18 * hs, maxf(hips.size.z * 0.7, 0.17 * hs)))
	attach("Hips", _cloth_mesh(_sphere(), hips_at, hips_b), cloth, hips_at, hips_b)
	# Under the pads the legs are knee guards and pants, not socks: whatever shows between
	# the pads (the knees in the butterfly) is drawn in the pants color.
	for mi: MeshInstance3D in skel.find_children("Outfit_*", "MeshInstance3D", false, false):
		var m := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("pants_leg", 1.0)
		mi.material_override = m
	# Leg pads and thigh rises: white with the team color on the rolls and knee stack, grey
	# leather landing pads inside (glove.gdshader, like the skater gloves).
	var pad_mat := glove_material(Color(0.93, 0.93, 0.9), c.jersey)
	for side in ["Left", "Right"]:
		var knee := bone_pos(side + "Leg")
		var ankle := bone_pos(side + "Foot")
		var shin := knee.distance_to(ankle) / PAD_SHIN
		var mirror := 1.0 if side == "Left" else -1.0
		attach(side + "Leg", PAD_MESH, pad_mat, ankle, _pad_basis(knee - ankle, mirror) * Basis.from_scale(Vector3(hs, shin, hs))).name = side + "Pad"
		# The boot rides the foot, so the skate under it can flex without poking through.
		attach(side + "Foot", BOOT_MESH, pad_mat, ankle, _pad_basis(knee - ankle, mirror) * Basis.from_scale(Vector3.ONE * hs)).name = side + "PadBoot"
		# The thigh rise stands up from the pad in line with the shin (rigid with it, as on
		# real pads): riding the thigh, it opened a gap over the knee in the crouch.
		attach(side + "Leg", THIGH_MESH, pad_mat, knee, _pad_basis(knee - ankle, mirror) * Basis.from_scale(Vector3.ONE * hs))
	# Catcher on the left hand (pocket along the hand frame's +Z, which faces the shooter
	# in the ready pose); blocker on the right. Both white with team-color trim, like the pads.
	var lh := bone_pos("LeftHand")
	var ld := (lh - bone_pos("LeftForeArm")).normalized()
	var lf := limb_frame("LeftForeArm", "LeftHand")
	attach("LeftHand", CATCHER_MESH, pad_mat, lh + ld * 0.02 * hs, lf * Basis.from_scale(Vector3.ONE * hs))
	var rh := bone_pos("RightHand")
	var rf := limb_frame("RightForeArm", "RightHand")
	attach("RightHand", BLOCKER_MESH, pad_mat, rh, rf * Basis.from_scale(Vector3.ONE * hs))
	# The body's own fingers would poke out of the blocker and catcher: fold them away.
	rig.hide_fingers = true
	add_skates(c)
	_add_number(cc + Vector3(0, (-0.02 - number_drop(c)) * hs, -cr.z), NUMBER_HEIGHT * 1.1 * hs)
	# (lower under the goalie jersey's laced collar, as on the skaters)
	_add_crest(cc + Vector3(0, (-0.13 if goalie_jersey != null else -0.06) * hs, cr.z), CREST_WIDTH * 1.1 * hs)


## Frame for a pad model: +Y along `up` (rest pose), +Z forward, +X outward for the left
## leg; mirror -1 flips X for the right one.
static func _pad_basis(up: Vector3, mirror: float) -> Basis:
	var y := up.normalized()
	var z := (Vector3.BACK - y * y.dot(Vector3.BACK)).normalized()
	return Basis(y.cross(z) * mirror, y, z)


## Goalie stick model (tools/build_gear.gd): body, grip, blade tape.
func _build_stick() -> void:
	var mats := stick_materials(skater, GOALIE_STICK_MESH)
	var body: Material = mats[0]
	var tape: Material = mats[1]
	var grip := MeshUtil.material(Color(0.02, 0.02, 0.02), 0.8)
	grip.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft = _add_mesh(self, GOALIE_STICK_MESH, null, Vector3.ZERO)
	shaft.set_surface_override_material(0, body)
	shaft.set_surface_override_material(1, grip)
	shaft.set_surface_override_material(2, tape)
	blade = shaft


## Goalies don't fall or stumble from hits; their poses come from the rig.
func _state_clips() -> void:
	pass


## Goalie mask model (MASKS).
func _build_goalie_mask(head: AABB, c: Dictionary) -> void:
	var spec: Dictionary = MASKS[mask_index(skater.gear_style)]
	var fit := _eye_fit(head)
	if spec.get("helmet", false):
		var k: float = head.size.x / HELMET_HEAD_W
		fit = Transform3D(Basis.from_scale(Vector3.ONE * k),
				Vector3(head.get_center().x, head.end.y - HELMET_CROWN * k, head.get_center().z))
	var mm := attach("Head", spec.mesh, null, fit.origin, fit.basis)
	mm.material_override = null
	mm.name = "Helmet"   # as the skater's helmet: tools and views find the head gear by name
	# Hair (the flattened under-helmet cut, which the mask covers but the cage shows at
	# the hairline) and facial hair: without them the face behind the cage was bald.
	_add_hair(head, spec.get("beard", true))
	if spec.has("squeeze"):
		for h in _hair_helm:
			if h.name != "HairCap":   # (the scalp cap is skin-tight already)
				h.transform = h.transform * Transform3D(Basis.from_scale(spec.squeeze))
	var liner := MeshUtil.material(Color(0.07, 0.07, 0.08), 0.85)   # foam padding
	liner.metallic_specular = 0.15
	var trim := MeshUtil.material(Color(0.1, 0.1, 0.11), 0.6)       # backplate and elastic
	trim.metallic_specular = 0.3
	var mats := {
		"shell": MeshUtil.material(c.helmet if spec.get("helmet", false) else c.jersey.lerp(Color.WHITE, 0.15), 0.35),
		"liner": liner,
		"cage": MeshUtil.material(Color(0.12, 0.12, 0.13), 0.3),
		"trim": trim,
		"white": MeshUtil.material(Color(0.92, 0.92, 0.9), 0.4),
	}
	if spec.has("paint"):
		var seed := absi(("%s %s %d" % [skater.first_name, skater.last_name, skater.number]).hash())
		var painted := mask_paint(spec.paint, c, seed)
		if painted != null:
			mats["shell"] = painted
	var surfaces: Array = spec.surfaces
	for i in surfaces.size():
		mm.set_surface_override_material(i, mats[surfaces[i]])


func _pose(delta: float) -> void:
	var k := _ease(14.0, delta)
	_yaw = lerp_angle(_yaw, _heading_yaw(), k)
	_tick_save(delta)
	var low_act := _act_on and _act_kind in ["butterfly", "pad", "stack"] and _act_w > 0.15
	var want_drop := 1.0 if (goalie.butterfly or low_act) else 0.0
	_drop = lerpf(_drop, want_drop, _ease(22.0 if want_drop > _drop else 10.0, delta))
	var spd := goalie.flat_speed()
	var traveling := _is_traveling()
	_travel = lerpf(_travel, 1.0 if traveling else 0.0, _ease(4.0, delta))
	var tr := _travel

	# Stride. In the crease: short quick shuffles. Traveling: the skater's long, unhurried
	# cadence and a full push, so the legs keep pace with the ground instead of pattering.
	_stride += delta * lerpf(5.0 + spd * 2.0, 3.6 + spd * 0.5, tr)
	var amt := clampf(spd / 3.0, 0.0, 1.0) * lerpf(0.35, 0.8, tr) * (1.0 - _drop)
	_stride_amt = lerpf(_stride_amt, amt, _ease(5.0, delta))
	var st := sin(_stride)
	var sa := _stride_amt * tr   # the upper body only rides the stride when traveling
	rig.hips_drop = lerpf(0.24, 0.15, tr) + 0.36 * _drop
	rig.lean = lerpf(0.42, 0.26, tr) - 0.1 * _drop
	# The torso turns against the pushing leg and rocks over it, the head steadier.
	rig.twist = -st * 0.2 * sa
	rig.sway = st * 0.11 * sa
	rig.head_level = lerpf(0.85, 0.95, tr)
	rig.stride_phase = _stride
	rig.stride_amt = _stride_amt
	rig.stride_dir = 1.0
	rig.stance = lerpf(0.27, 0.19, tr)
	rig.toe_out = lerpf(0.25, 0.1, tr)
	rig.hips_shift = Vector3(-st * 0.05 * sa, 0, lerpf(-0.05, -0.01, tr) - 0.08 * _drop)
	# Breathing over the ready stance, so a goalie waiting on a faceoff isn't a statue.
	rig.breath = 0.6 * (1.0 - _drop) * (1.0 - tr)
	# Butterfly: knees pinch together in front, feet flare out behind.
	rig.foot_offset[0] = Vector3(0.24, 0.0, -0.3) * _drop
	rig.foot_offset[1] = Vector3(-0.24, 0.0, -0.3) * _drop
	rig.knee_pole[0] = Vector3(lerpf(0.25, 0.12, tr) - 0.55 * _drop, -0.6 * _drop, 1.0)
	rig.knee_pole[1] = Vector3(-lerpf(0.25, 0.12, tr) + 0.55 * _drop, -0.6 * _drop, 1.0)

	# Glove / blocker: ready position; a save sends one of them to the puck (below).
	rig.arm_mode = SkaterRig.Arms.FREE
	var y_drop := -0.3 * _drop
	# The arms swing against the legs: the glove (left) comes forward with the right foot.
	# (Rig: the left foot is ahead at cos(stride) = 1; model space has -Z ahead.)
	_swing = lerpf(_swing, cos(_stride) * sa, _ease(12.0, delta))
	var ready_glove := Vector3(-0.42, 1.0 + y_drop, -0.42)
	var carry_glove := CARRY_GLOVE + Vector3(0.0, absf(_swing) * 0.08, _swing * 0.32)
	var glove_p := ready_glove.lerp(carry_glove * Vector3(1, hs, 1), tr)
	# Holding a caught puck: the glove comes in against the chest.
	var holding := goalie.g == Goalie.G.HOLD and goalie.has_puck() and goalie.last_catch
	_hold_w = lerpf(_hold_w, 1.0 if holding and _act_w < 0.3 else 0.0, _ease(6.0, delta))
	glove_p = glove_p.lerp(Vector3(-0.1, 1.05, -0.3) * Vector3(1, hs, 1), _hold_w)
	# Elbows out for the ready stance; in at the sides, hanging back, when traveling.
	rig.elbow_pole[0] = Vector3(0.7, -0.6, -0.4).lerp(Vector3(0.3, -0.8, -0.6), tr)
	rig.elbow_pole[1] = Vector3(-0.7, -0.7, -0.3).lerp(Vector3(-0.35, -0.8, -0.5), tr)
	_place_model(_save_pose())
	var mt := model.global_transform
	rig.hand_world[0] = mt * glove_p
	rig.hand_world[1] = mt * _blocker_ready()
	_blocker_k = 0.0
	if _act_on and _act_w > 0.0:
		var lead := 0 if _act_side > 0.0 else 1
		var target := _act_spot
		if _act_catch and _act_t > _act_hit:
			# A caught puck: the glove snaps shut and flashes it, up and a touch back.
			var u := clampf((_act_t - _act_hit) / 0.25, 0.0, 1.0)
			target += Vector3.UP * 0.1 * u * hs - goalie.heading * 0.08 * u
		var reach_w := _act_w * (0.7 if _act_kind == "pad" else 1.0)
		if _act_kind == "butterfly":
			reach_w *= 0.5
		rig.hand_world[lead] = rig.hand_world[lead].lerp(target, reach_w)
		if lead == 1 and _act_kind in ["reach", "pad", "butterfly"]:
			_blocker_k = reach_w   # the blade stays down, the shaft swings out with the hand
		# The reaching elbow lifts out of the way.
		var sx := 1.0 if lead == 0 else -1.0
		rig.elbow_pole[lead] = rig.elbow_pole[lead].lerp(Vector3(sx * 0.6, -0.2, -0.8), _act_w)
	_face(traveling)


## Starts, steers and ends the save action (see SAVE_LEAD).
func _tick_save(delta: float) -> void:
	if goalie.net == null or goalie.walking():
		_act_on = false
		_act_w = 0.0
		return
	if goalie.save_count != _seen_saves:
		var first := _seen_saves == 0 and goalie.save_count > 1   # (joined mid-game: ignore old saves)
		_seen_saves = goalie.save_count
		if not first:
			_act_catch = goalie.last_catch
			if _act_on and _act_t <= _act_hit + 0.08:
				_act_spot = goalie.save_spot   # the read was right: land there, now
				_act_hit = minf(_act_hit, _act_t + 0.04)
			else:
				_begin_save(goalie.save_spot, 0.07)   # a pure reflex: no read, snap to it
	elif not _act_on and goalie.read_eta < SAVE_LEAD:
		_begin_save(goalie.read_spot, goalie.read_eta)
		_act_catch = false
	if not _act_on:
		_act_w = lerpf(_act_w, 0.0, _ease(10.0, delta))
		return
	_act_t += delta
	if _act_t < _act_hit and goalie.read_eta < INF:
		# Still in the air: follow the read (a tip changes it), arriving with the puck.
		_act_spot = goalie.read_spot
		_act_hit = _act_t + goalie.read_eta
		_choose_kind()
	var times: Array = SAVE_TIMES[_act_kind]
	var hold: float = times[0] + (0.25 if _act_catch else 0.0)
	var rec: float = times[1]
	if _act_t < _act_hit:
		var u := clampf(_act_t / maxf(_act_hit, 0.05), 0.0, 1.0)
		_act_w = 1.0 - (1.0 - u) * (1.0 - u)   # fast out of the stance, settling in
	elif _act_t < _act_hit + hold:
		_act_w = 1.0
	else:
		_act_w = 1.0 - smoothstep(0.0, rec, _act_t - _act_hit - hold)
		if _act_t > _act_hit + hold + rec:
			_act_on = false
			_act_w = 0.0


func _begin_save(spot: Vector3, eta: float) -> void:
	_act_on = true
	_act_t = 0.0
	_act_hit = maxf(eta, 0.05)
	_act_spot = spot
	_act_from = goalie.global_position
	_choose_kind()


## Sideways (+ = the goalie's left, the glove side) and height of the save spot, from
## where the goalie stood when the save started (`now`: from where it is now; the
## goalie slides across as it reads the shot).
func _save_offset(now := false) -> Vector2:
	var right := goalie.net.global_basis.x
	var from := goalie.global_position if now else _act_from
	return Vector2((_act_spot - from).dot(right), _act_spot.y)


func _choose_kind() -> void:
	var o := _save_offset()
	_act_side = 1.0 if o.x > 0.0 else -1.0
	var ax := absf(o.x) / hs
	var h := o.y / hs
	if h < 0.42:
		_act_kind = "butterfly" if ax < 0.42 else ("pad" if ax < 0.95 else "stack")
	else:
		_act_kind = "reach" if ax < 0.7 and h < 1.45 else "dive"


## The save's whole-body part: [roll (rad, + = toward the glove side), sideways shift (m,
## toward the save), lift (m)], with the stance's legs, sway and twist set on the rig.
func _save_pose() -> Vector3:
	if not _act_on and _act_w <= 0.001:
		_counter = Vector3.ZERO
		return Vector3.ZERO
	var w := _act_w
	var o := _save_offset()
	var ax := absf(o.x)
	# The goalie slides across as it reads the shot; during the save the body stays where it
	# started and the save itself (the lunge, dive or pad) covers that ground instead.
	var nx := goalie.net.global_basis.x
	_counter = nx * (_act_from - goalie.global_position).dot(nx) * w
	var sd := _act_side
	var lead := 0 if sd > 0.0 else 1
	var far := 1 - lead
	var roll := 0.0
	var shift := 0.0
	var lift := 0.0
	match _act_kind:
		"reach":
			shift = clampf(ax - 0.55 * hs, 0.0, 0.15) * w   # the arm does the reaching
			roll = sd * clampf((ax / hs - 0.35) * 0.6, 0.0, 0.2) * w
			rig.sway += sd * 0.22 * w
			rig.twist += sd * 0.12 * w
			if o.y > 1.0:   # the big glove: up on the toes, stretched tall
				rig.hips_drop -= 0.06 * w
		"pad":
			# Drop, the near pad kicked out flat along the ice toward the post.
			var ext := clampf(ax - 0.3 * hs, 0.0, 0.6 * hs)
			rig.foot_offset[lead] = rig.foot_offset[lead].lerp(Vector3(sd * (0.25 + ext * 0.9), 0.0, 0.05), w)
			rig.knee_pole[lead] = rig.knee_pole[lead].lerp(Vector3(sd * 0.3, 0.9, 0.4), w)
			shift = clampf(ax - 0.3 * hs, 0.0, 0.4) * w
			roll = sd * 0.15 * w
			rig.sway += sd * 0.12 * w
		"dive", "stack":
			# Push off the far leg and launch sideways, the body tipping over toward the
			# save; "stack" lays right out along the ice, "dive" stays up off it.
			var flat := _act_kind == "stack"
			var r := 1.2 if flat else clampf((ax / hs - 0.35) * 1.2, 0.5, 0.95)
			roll = sd * r * w
			shift = clampf(ax - 0.55 * hs, 0.0, 0.7 * hs) * w
			rig.lean -= 0.25 * w   # stretched out long, not folded over
			lift = (0.0 if flat else 0.1 * hs * smoothstep(0.7, 1.3, o.y / hs)) * w
			rig.hips_drop += 0.06 * w
			# The push leg trails in close behind the body, knee bent, rather than kicking up
			# (the roll already lifts it off the ice).
			rig.foot_offset[far] = rig.foot_offset[far].lerp(Vector3(sd * 0.12, 0.0, -0.12), w)
			rig.knee_pole[far] = rig.knee_pole[far].lerp(Vector3(sd * 0.3, -0.3, 1.0), w)
			rig.sway += sd * 0.28 * w
			rig.twist += sd * 0.1 * w
			rig.breath = 0.0
	return Vector3(roll, shift, lift)


## The model's pose: the heading, plus a save's roll about the near skate's edge (so that
## pad stays on the ice as the body tips over), slide sideways and lift.
func _place_model(save: Vector3) -> void:
	var yb := Basis(Vector3.UP, _yaw)
	if save == Vector3.ZERO and _counter == Vector3.ZERO:
		model.transform = Transform3D(yb, Vector3.ZERO)
		return
	# Model space: -Z ahead, the goalie's left (glove side) at -X; roll + tips the head that way.
	var sd := _act_side
	var pivot := Vector3(-sd * rig.stance * hs, 0.0, 0.0)
	var lb := Basis(Vector3.BACK, save.x)
	var origin := pivot - lb * pivot + Vector3(-sd * save.y, save.z, 0.0)
	model.transform = Transform3D(yb * lb, yb * origin + _counter)


## Skating out of the bench or back to it (scripted walks), or anywhere well out of the crease.
func _is_traveling() -> bool:
	if goalie.walking():
		return true
	if goalie.net == null or goalie.butterfly or goalie.save_anim > 0.0:
		return false
	return goalie.net.to_local(goalie.global_position).z > CREASE_OUT and goalie.flat_speed() > 1.0


## The face behind the cage: eyes on the puck in the crease, set and focused; skating
## out, looking where it's going, loose, a word or a smirk now and then.
func _face(traveling: bool) -> void:
	if face == null:
		return
	if traveling != _was_traveling:
		_was_traveling = traveling
		face.chatty = traveling
		face.set_expression("neutral" if traveling else "focused")
	var eye := bone_world("Head")
	if traveling:
		face.look_target = eye + goalie.heading * 8.0 + Vector3(0, -0.4, 0)
	elif goalie.puck != null and is_instance_valid(goalie.puck):
		face.look_target = goalie.puck.global_position
	else:
		face.look_target = null


## The blocker's ready position (model space), lower in the butterfly; held lower and
## nearer the body, swinging a little with the stride, when traveling.
func _blocker_ready() -> Vector3:
	var ready_p := BLOCKER_READY + Vector3(0, -0.3 * _drop, 0)
	var carry := CARRY_BLOCKER + Vector3(0.0, absf(_swing) * 0.04, -_swing * 0.16)
	return ready_p.lerp(carry, _travel) * Vector3(1, hs, 1)


func _update_stick(delta: float) -> void:
	# The blade flat on the ice where the shaft through the blocker's ready position
	# meets it at the stick's lie, across the crease toward the glove side.
	var hand := model.global_transform * _blocker_ready() - global_position
	var target := _heel_below(hand) + _across() * _blade_len() * 0.5
	target.y = 0.05
	_blade = _blade.lerp(target, _ease(30.0, delta)) if delta > 0.0 else target
	rig.blade_world = global_position + _blade


func _across() -> Vector3:
	var a := model.global_basis * Vector3.LEFT
	return Vector3(a.x, 0.0, a.z).normalized()


func _blade_len() -> float:
	return Vector3(GOALIE_STICK_MESH.get_meta("blade")).length() * hs


## The shaft's direction up from the heel (world axes): at the stick's lie off the blade
## (the model's angle between its shaft, +Y, and the blade), rising toward the blocker
## side, leaned back toward the goalie by STICK_TILT.
func _shaft_dir() -> Vector3:
	var back := model.global_basis * Vector3.BACK
	back = Vector3(back.x, 0.0, back.z).normalized()
	var rise := PI - Vector3.UP.angle_to(Vector3(GOALIE_STICK_MESH.get_meta("blade")))
	return (-_across() * cos(rise) + (Vector3.UP * cos(STICK_TILT) + back * sin(STICK_TILT)) * sin(rise)).normalized()


## Where the shaft through `p` (relative to the goalie) reaches the ice.
func _heel_below(p: Vector3) -> Vector3:
	var d := _shaft_dir()
	var h := p - d * (p.y / d.y)
	h.y = 0.0
	return h


func _after_rig() -> void:
	# The shaft runs through the blocker hand at the stick's lie, at the model's length.
	# During a blocker save the blade stays put and the shaft swings out to the hand.
	var hand := to_local(rig.right_hand_world)
	var rest := _blade - _across() * _blade_len() * 0.5
	rest.y = 0.0
	var heel := _heel_below(hand).lerp(rest, _blocker_k)
	var l0: float = GOALIE_STICK_MESH.get_meta("shaft") * hs
	var top := heel + (hand - heel).normalized() * maxf(l0, heel.distance_to(hand) + 0.1)
	_place_stick(top, heel, goalie.heading, _across())
