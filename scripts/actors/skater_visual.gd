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
## Skin tones to pick from (sRGB), light to dark. The player editor (M7) will set them.
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.80, 0.69), Color(0.91, 0.73, 0.60), Color(0.82, 0.62, 0.47),
	Color(0.68, 0.48, 0.33), Color(0.50, 0.34, 0.23), Color(0.34, 0.22, 0.15),
]
const SKATE_LIFT := 0.08          ## skate blade height under the boot (tools/blender/skate_gear.py SOLE)
## Hair and facial hair (tools/build_hair.gd): meshes in head space, tinted per player.
const HAIR_DIR := "res://assets/characters/hair/"
const HAIR_STYLES := ["messy", "buzz", "shaggy", "mop", "quiff"]   ## anyone; women also "braid"
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
var stance_bend := 1.15   ## forward bend of the spine in the ready stance (rad)
var _dip := 0.0
var windup_arc_end := 120.0     ## degrees around from straight ahead the blade swings back
var windup_arc_reach := 0.9     ## its distance out from the body at the top (m, flat)
var windup_arc_height := 1.9    ## its height at the top (m)
var _follow_hold := 0.0
var _swing_charge := 0.0   ## the slap shot's charge at release (the downswing starts there)
var dip_max := 0.15      ## most the bottom shoulder dips past stance_sway to reach (rad)
var dip_lean := 0.0     ## the dip also leans the chest forward this much of it (over the shaft)
var _twist := 0.0
var _stride := 0.0
var _stride_amt := 0.0
var _free_arm := 0.0
var _blade := Vector3.ZERO        ## blade position relative to the skater
var _marker_on := false
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

static var _materials := {}
static var _visor: StandardMaterial3D
## Helmet models (tools/build_gear.gd), picked by Skater.gear_style. fit = helmet width /
## head width; raise = shell center above the head's center, in head heights; back =
## shell center behind the head's center, in head depths.
const HELMETS := [
	{"mesh": preload("res://assets/characters/helmet.res"), "fit": 1.18, "raise": 0.2, "back": 0.04},
	{"mesh": preload("res://assets/characters/helmet_b.res"), "fit": 1.16, "raise": 0.2, "back": 0.04},
]
const STICK_MESH := preload("res://assets/characters/stick.res")
const SKATE_MESH := preload("res://assets/characters/skate.res")
const GLOVE_MESH := preload("res://assets/characters/glove.res")   ## a right glove, origin at the wrist, sized for 1.8 m
const CUFF_MESH := preload("res://assets/characters/glove_cuff.res")   ## the glove's cuff: rides the forearm, not the hand
const FIST_MESH := preload("res://assets/characters/fist.res")     ## a bare right fist for fights, same axes as the glove
const SKATE_LEN := 0.3         ## skate length for a 1.8 m body
const DIGITS := preload("res://assets/characters/digits.png")   ## tools/build_digits.gd
const DIGIT_FILL := 0.84        ## share of a digit-sheet cell's height the digit fills
const LETTERS := preload("res://assets/characters/letters.png")   ## tools/build_letters.gd
const LETTER_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZÉÑÔÚÛ0123456789-'.!"   ## the sheet's cells, in order
const NUMBER_LOWER := 0.2        ## m the back number sits below where it used to (room for the name)
const NAME_HEIGHT := 0.056       ## nameplate cap height for a 1.8 m body
const NAME_GAP := 0.025          ## m between the nameplate and the top of the number
const NAME_MAX_W := 0.29        ## widest nameplate (longer names are squeezed to fit)
const NICKNAME_MAX := 8          ## nicknames this short go on the back instead of the last name
const NUMBER_HEIGHT := 0.24     ## back number height for a 1.8 m body
const CREST_WIDTH := 0.34       ## jersey crest width for a 1.8 m body
const STICK_PUCK := 0.1        ## where on the blade the puck sits, from the heel (m)
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
var display_lift := 0.0   ## menus: m the player stands above the ice
const DISPLAY_POSES := ["side", "middle", "rest", "lean", "across", "shoulders"]
const FEMALE_POSES := ["hips", "hips_b"]
var _disp_top := Vector3.ZERO     ## the pose's stick: butt end, heel and blade direction (local)
var _disp_heel := Vector3.ZERO
var _disp_out := Vector3.ZERO
var _disp_age := 0.0                   ## s in the current display pose
var _disp_chest_ref := Transform3D()   ## the chest (local) once the pose settled; "fixed" sticks follow it from there
var _helmet: MeshInstance3D       ## on the Head bone; comes off for fights (take_off_helmet)
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
const HELMET_SPEED := 1.5
const HELMET_LIFT := 1.1      ## s: the hands come off the head, the helmet with the right one
const HELMET_DROP := 1.45     ## s: let go
const HELMET_END := 1.7       ## s: the clip fades out
static var _numbers := {}         ## "number|fill|outline" -> ImageTexture
static var _names := {}           ## "NAME|fill|outline" -> [ImageTexture, cap height share]
static var _letter_sheet: Image
static var _letter_spans := {}    ## char -> [x0 in the sheet, width]
static var _cap_rows := Vector2i.ZERO   ## the sheet rows a capital letter fills (top, bottom)
var hs := 1.0                     ## body height / 1.8 m, scales gear offsets


# --- Build -----------------------------------------------------------------------

func build(sk: Skater) -> void:
	skater = sk
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_body()
	_build_gear()
	_build_stick()
	_build_markers()
	snap()


func _build_body() -> void:
	model = Node3D.new()
	add_child(model)
	var assets := body_assets(skater.body_type)
	body = (assets[0] as PackedScene).instantiate()
	hs = float(body.get_meta("height", 1.8)) / 1.8
	body.rotation.y = PI
	body.position.y = SKATE_LIFT
	model.add_child(body)
	skel = body.get_node("Skeleton3D")
	var c := team_colors()
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", false, false):
		if mi.name == "Eyes":
			mi.material_override = eye_material(body)
		elif mi.name.begins_with("Outfit_"):
			mi.material_override = uniform_material(c, 0.8 if mi.name.ends_with("Alpha_Joints") else 1.0)
		else:
			mi.material_override = skin_material(body, skater.skin_tone)
	face = FaceRig.create(self)
	anim = AnimationPlayer.new()
	body.add_child(anim)
	anim.add_animation_library("", assets[1])
	rig = SkaterRig.new()
	skel.add_child(rig)
	rig.modification_processed.connect(_after_rig)


static func visor_material() -> StandardMaterial3D:
	if _visor == null:
		_visor = StandardMaterial3D.new()
		_visor.albedo_color = Color(0.55, 0.65, 0.75, 0.35)
		_visor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_visor.roughness = 0.1
		_visor.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _visor


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
	var key := "%s|%s|%s|%s|%s|%s|%s|%.2f" % [c.jersey.to_html(), c.trim.to_html(), c.pants.to_html(), c.gloves.to_html(), c.skates.to_html(), accent.to_html(), design, darken]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = UNIFORM_SHADER
	for k: String in c:
		if c[k] is Color:
			m.set_shader_parameter(k, c[k])
	m.set_shader_parameter("accent_color", accent)
	var params: Dictionary = Teams.DESIGNS.get(design, {})
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
	var helmet := MeshUtil.material(c.helmet, 0.35)
	var dark := MeshUtil.material(Color(0.06, 0.06, 0.07), 0.4)
	var glove := glove_material(c.gloves, c.trim)
	var skin := MeshUtil.material(skater.skin_tone, 0.62)
	# Chest and hip bulk wear the uniform material, so the yoke, stripes and fabric carry
	# across them and the jersey layer (see _cloth_mesh).
	var cloth := uniform_material(c)
	# Offsets are relative to the body's own joints (rest pose: +Z forward, +X = left).
	var head := anchor_box("head", "Head", Vector3(0.2, 0.25, 0.22) * hs)
	# Helmet model (tools/build_gear.gd): sized to the head's width, shell over the crown.
	var hspec: Dictionary = HELMETS[skater.gear_style % HELMETS.size()]
	var hmesh: Mesh = hspec.mesh
	var fit: float = head.size.x * hspec.fit / hmesh.get_aabb().size.x
	var hm := attach("Head", hmesh, null, head.get_center() + Vector3(0, head.size.y * hspec.raise, -head.size.z * hspec.back), Basis.from_scale(Vector3.ONE * fit))
	hm.material_override = null
	hm.name = "Helmet"
	hm.set_surface_override_material(0, helmet)
	hm.set_surface_override_material(1, MeshUtil.material(Color(0.92, 0.92, 0.9), 0.4))
	hm.set_surface_override_material(2, dark)
	hm.set_surface_override_material(3, visor_material())
	_helmet = hm
	_helmet_rest = hm.transform
	_add_hair(head)
	var chest := anchor_box("chest", "Spine2", Vector3(0.36, 0.2, 0.24) * hs)
	var cc := chest.get_center()
	var cr := Vector3(maxf(chest.size.x * 0.62, 0.25 * hs), 0.13 * hs, maxf(chest.size.z * 0.6, 0.15 * hs))
	var chest_at := cc + Vector3(0, 0.02 * hs, 0)
	# Bodies with a modelled jersey (tools/blender/build_jersey.py) already carry the
	# shoulder and chest bulk in its shape; the pad ball would poke through it.
	if not body.get_meta("jersey", false):
		attach("Spine2", _cloth_mesh(_sphere(), chest_at, Basis.from_scale(cr)), cloth, chest_at, Basis.from_scale(cr))
	# Hockey pants: a slim band around the pelvis plus a padded shell on each thigh that
	# moves with the leg (one big pelvis ball stuck out behind like a diaper when the
	# skater bent forward).
	var hips := anchor_box("hips", "Hips", Vector3(0.34, 0.2, 0.24) * hs)
	var hips_at := hips.get_center() + Vector3(0, -0.035 * hs, 0.0)
	var hips_b := Basis.from_scale(Vector3(maxf(hips.size.x * 0.53, 0.17 * hs), 0.1 * hs, maxf(hips.size.z * 0.46, 0.115 * hs)))
	attach("Hips", _cloth_mesh(_sphere(), hips_at, hips_b), cloth, hips_at, hips_b)
	for side in ["Left", "Right"]:
		var hip := bone_pos(side + "UpLeg")
		var thigh := bone_pos(side + "Leg") - hip
		var at := hip + thigh * 0.3 + Vector3(0, 0, 0.005 * hs)
		var tb := limb_frame(side + "UpLeg", side + "Leg", Vector3(0.1 * hs, thigh.length() * 0.36, 0.108 * hs))
		attach(side + "UpLeg", _cloth_mesh(_sphere(), at, tb), cloth, at, tb)
	for side in ["Left", "Right"]:
		# Glove model: fingers along the hand, palm down in the T-pose, thumb forward. The
		# model is a right glove; the left one is mirrored.
		var hand := bone_pos(side + "Hand")
		var arm_dir := (hand - bone_pos(side + "ForeArm")).normalized()
		var lf := limb_frame(side + "ForeArm", side + "Hand")
		var gb := Basis(-lf.z, lf.y, lf.x) if side == "Right" else Basis(-lf.z, lf.y, -lf.x)
		_gloves.append(attach(side + "Hand", GLOVE_MESH, glove, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs)))
		# The cuff hangs on the forearm, so it stays on the arm while the hand turns.
		_cuffs.append(attach(side + "ForeArm", CUFF_MESH, glove, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs)))
		var fist := attach(side + "Hand", FIST_MESH, skin, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs))
		fist.visible = false
		_fists.append(fist)
	# The body's own fingers would poke out of both: the rig folds them away.
	rig.hide_fingers = true
	add_skates(c)
	_add_number(cc + Vector3(0, (-0.04 - number_drop(c)) * hs, -cr.z), NUMBER_HEIGHT * hs)
	# Under a modelled jersey's laced V collar: lower and a little smaller, so the crest
	# stays clear of the collar and laces.
	var modelled: bool = body.get_meta("jersey", false)
	_add_crest(cc + Vector3(0, (-0.14 if modelled else -0.07) * hs, cr.z), CREST_WIDTH * (0.85 if modelled else 1.0) * hs)


## Hair (what shows under the helmet) and facial hair, sized to this body's head.
func _add_hair(head: AABB) -> void:
	var top := Vector3(head.get_center().x, head.end.y, head.get_center().z)
	var b := Basis.from_scale(Vector3.ONE * head.size.x)
	for id: String in [skater.hair_style, skater.facial_hair]:
		var path := HAIR_DIR + id + ".res"
		if id == "" or not ResourceLoader.exists(path):
			continue
		var mi := attach("Head", load(path), hair_material(id, skater.hair_color), top, b)
		mi.name = "Hair_" + id
		if id == skater.facial_hair and face != null:
			face.follow_jaw(mi)
		# Hairstyles have a flattened copy for under the helmet (facial hair doesn't).
		var helm_path := HAIR_DIR + id + "_helm.res"
		if ResourceLoader.exists(helm_path):
			var hm := attach("Head", load(helm_path), hair_material(id, skater.hair_color), top, b)
			hm.name = "HairHelm_" + id
			_hair_full.append(mi)
			_hair_helm.append(hm)
			# Under the helmet the strands are thin on the crown: a hair-colored cap on the
			# scalp shows through the vents.
			var cap := attach("Head", _scalp_cap(), _cap_material(skater.hair_color), top + b * HAIR_CAP_AT, b * Basis.from_scale(HAIR_CAP_R))
			cap.name = "HairCap"
			_hair_helm.append(cap)
	_show_hair(true)


## Head space (head widths from the top of the head): the cap's center and radii.
const HAIR_CAP_AT := Vector3(0.0, -0.5, -0.04)
const HAIR_CAP_R := Vector3(0.54, 0.6, 0.63)
static var _cap_mesh: SphereMesh


static func _scalp_cap() -> SphereMesh:
	if _cap_mesh == null:
		_cap_mesh = SphereMesh.new()
		_cap_mesh.radius = 1.0
		_cap_mesh.height = 1.0
		_cap_mesh.is_hemisphere = true
		_cap_mesh.radial_segments = 24
		_cap_mesh.rings = 8
	return _cap_mesh


static func _cap_material(color: Color) -> StandardMaterial3D:
	var key := "haircap|" + color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color.darkened(0.25)
		m.roughness = 0.85
		_materials[key] = m
	return _materials[key]


func _show_hair(helmet_on: bool) -> void:
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
	if not helmet_on():
		return
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


static func hair_material(id: String, color: Color) -> StandardMaterial3D:
	var key := "hair|%s|%s" % [id, color.to_html()]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		var tex := HAIR_DIR + id + ".png"
		if ResourceLoader.exists(tex):
			m.albedo_texture = load(tex)
			# The strand textures are light gray: lift the tint so it lands on `color`.
			m.albedo_color = Color(minf(color.r * 1.6, 1.0), minf(color.g * 1.6, 1.0), minf(color.b * 1.6, 1.0))
		else:
			m.albedo_color = color
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## A hairstyle, facial hair, hair and eye color for a player: {hair_style, facial_hair,
## hair_color, eye_color}. Darker skin tones lean to darker hair and brown eyes; some
## players go gray.
static func random_look(rng: RandomNumberGenerator, body_type: String, skin: Color) -> Dictionary:
	var styles: Array = HAIR_STYLES.duplicate()
	var facial := ""
	if body_type == "female":
		styles.append_array(["braid", "braid", "shaggy", "mop"])
	else:
		var r := rng.randf()
		facial = "beard" if r < 0.2 else ("chinstrap" if r < 0.3 else ("moustache" if r < 0.5 else ""))
	var colors := HAIR_COLORS.size() - 1   # gray is its own roll
	if skin.get_luminance() < 0.45:
		colors = 2
	var color := HAIR_COLORS[rng.randi() % colors]
	if rng.randf() < 0.08:
		color = HAIR_COLORS[HAIR_COLORS.size() - 1]
	var style: String = styles[rng.randi() % styles.size()]
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
	rig.lock_root = on
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
	# skate color, greyer side panels, the holder, laces and tongue felt in white.
	var boot := glove_material(c.skates)
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
		sk.mesh = _skate_mesh(xf)
		var skin := Skin.new()
		for b in [side + "Foot", side + "Leg"]:
			skin.add_named_bind(b, skel.get_bone_global_rest(skel.find_bone(b)).affine_inverse())
		sk.skin = skin
		skel.add_child(sk)
		sk.skeleton = NodePath("..")
		sk.set_surface_override_material(0, boot)
		sk.set_surface_override_material(1, steel)


## Upper boot: where the skate starts following the shin, and where it follows it fully
## (heights in the skate model, above the ice).
const SKATE_FLEX := Vector2(0.13, 0.22)
static var _skate_meshes := {}


## The skate model placed by `xf` (skeleton space), weighted to two binds: 0 the foot,
## 1 the shin, blending up the boot's shaft. Shared per placement.
static func _skate_mesh(xf: Transform3D) -> ArrayMesh:
	var key := str(xf)
	if _skate_meshes.has(key):
		return _skate_meshes[key]
	var out := ArrayMesh.new()
	for s in SKATE_MESH.get_surface_count():
		var arr := SKATE_MESH.surface_get_arrays(s)
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


## Back number: a Decal projected forward onto the jersey from just behind `at` (a point
## on the back's surface, T-pose), so the digits wrap with the jersey and the pads under
## it instead of floating on a flat card. Surfaces facing away (the chest) are faded
## out by normal_fade.
## Yoke designs carry the back number a little lower, clear of the yoke.
static func number_drop(c: Dictionary) -> float:
	var d: Dictionary = Teams.DESIGNS.get(c.get("design", "classic"), {})
	return 0.06 if float(d.get("yoke_r", 0.0)) > 0.0 else 0.0


func _add_number(at: Vector3, height: float) -> void:
	var c := team_colors()
	at.y -= NUMBER_LOWER * hs
	var tex := number_texture(skater.number, c.number, c.number_outline)
	var h := height / DIGIT_FILL
	_back_decal(tex, Vector2(h * tex.get_width() / float(tex.get_height()), h), at)
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
	_back_decal(ntex, Vector2(nw, nh), name_at)


## A Decal on the back: projected forward onto the jersey from just behind `at` (T-pose),
## `size` (width, height) in meters.
func _back_decal(tex: Texture2D, size: Vector2, at: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(size.x, 0.36 * hs, size.y)
	d.normal_fade = 0.72
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	# Projects along its -Y: here body +Z (into the back). Texture right = the
	# character's right (body -X), texture down = body down.
	var b := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
	attach_node("Spine2", d, Transform3D(b, at + Vector3(0, 0, 0.04 * hs)))


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


## Team crest on the jersey front: a Decal projected backward onto the chest from just
## in front of `at` (a point on the chest's surface, T-pose), so it wraps with the
## jersey like the back number.
func _add_crest(at: Vector3, width: float) -> void:
	if skater.crest == null:
		return
	var tex := skater.crest
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(width, 0.36 * hs, width * tex.get_height() / float(tex.get_width()))
	d.normal_fade = 0.72
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	# Projects along its -Y: here body -Z (into the chest). Texture right = the
	# viewer's right facing the player (body +X), texture down = body down.
	var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	attach_node("Spine2", d, Transform3D(b, at - Vector3(0, 0, 0.04 * hs)))


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
	var black := MeshUtil.material(Color(0.05, 0.05, 0.06), 0.5)
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tape := MeshUtil.material(Color(0.92, 0.92, 0.9), 0.6)
	tape.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft = _add_mesh(self, STICK_MESH, null, Vector3.ZERO)
	shaft.set_surface_override_material(0, black)
	shaft.set_surface_override_material(1, tape)
	blade = shaft


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
	# The blade hooks toward -X in the model, so -X is the forehand face.
	var world := Basis(-f, s / l0, out * Vector3(db.x, 0.0, db.z).length())
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


func _play_bench_loop() -> void:
	var len := anim.get_animation(bench_loop).length
	play_clip(bench_loop, Vector3.ONE, -1.0, randf_range(0.85, 1.1), 0.35, randf() * len)


## Back to playing (walking out through a door, or onto the ice).
func bench_off() -> void:
	if bench_loop == "":
		return
	bench_loop = ""
	rig.clip_only = false
	stop_clip(0.25)
	shaft.visible = true
	blade.visible = true


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
			var big := skater._down_time > Skater.DOWN_TIME + 0.1
			play_clip("knocked_down" if big else "falling_down", Vector3.ONE, -1.0, 1.7 if big else 1.9, 0.08)
		Skater.State.STUMBLE:
			play_clip("big_side_hit" if randf() < 0.5 else "hit_to_body", Vector3(0.0, 0.8, 0.7), Skater.STUMBLE_TIME + 0.15, 1.4, 0.06)
		_:
			if was == Skater.State.DOWN:
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
	_process(0.0)


func _heading_yaw() -> float:
	return atan2(-skater.heading.x, -skater.heading.z)


func _process(delta: float) -> void:
	if skater == null:
		return
	global_position = skater.get_global_transform_interpolated().origin + Vector3.UP * display_lift
	if bench_loop != "" and _clip_left <= 0.0:
		_play_bench_loop()   # a reaction finished: back to the idle
	_state_clips()
	_tick_clip(delta)
	_tick_helmet(delta)
	_pose(delta)
	_update_stick(delta)
	_update_human_tag()
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
	_yaw = lerp_angle(_yaw, target_yaw, _ease(14.0 if not skater.is_down() else 6.0, delta))

	var lean_target := clampf(skater.turn_speed * spd * 0.035, -0.45, 0.45)
	if skater.stopping:
		lean_target = 0.3 * side
	if skater.is_down():
		lean_target = 0.0
	_lean = lerpf(_lean, lean_target, _ease(8.0, delta))

	var fast := clampf(spd / 9.0, 0.0, 1.0)
	# Ready stance: knees well bent, chest forward over the knees, so the arms can reach
	# the stick with the elbows bent.
	var crouch := 0.21 + fast * 0.08 + (0.04 if skater.turbo_active else 0.0) + (0.08 if skater.stopping else 0.0)
	var bend := stance_bend + fast * 0.2 + (0.1 if skater.turbo_active else 0.0)
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
			bend += 0.25
			twist = side * 0.35
			crouch += 0.06
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

	# Stride: cadence follows speed; amplitude follows how hard the skater is pushing.
	var pushing := clampf(skater.intent.move.length(), 0.0, 1.0)
	var amt := pushing * clampf(spd / 3.0, 0.35, 1.0) * (1.25 if skater.turbo_active else 1.0)
	if skater.stopping or skater.frozen or skater.state == Skater.State.CHECK:
		amt = 0.0
	if spd > skater.top_speed() * 1.02:
		amt *= 0.4
	_stride_amt = lerpf(_stride_amt, amt, _ease(5.0, delta))
	_stride += delta * (4.5 + spd * 0.55)
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

	rig.hips_drop = _crouch
	rig.lean = _bend + _dip * dip_lean
	rig.twist = _twist
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

	rig.breath = 0.0
	if display_pose != "":
		_display_pose(delta)
	var pitch := 0.0
	var roll := _lean + roll_offset
	if skater.state == Skater.State.STUMBLE:
		roll += sin(skater._state_time * 40.0) * 0.12
	model.rotation = Vector3(pitch, _yaw, roll)


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
				target.y = 0.03
				follow = 1.0
			elif skater.intent.shoot_held or skater._shoot_buffer > 0.0:
				target = right * side * 0.6 - h * 0.1 + Vector3.UP * 0.8 # loaded for a one-timer
			else:
				target = stance_blade()
				target.y = 0.03
	# While a clip owns the arms (celebrating), the stick hangs from the top hand.
	if _clip_w.z > 0.5 and not skater.is_down():
		target = (rig.top_hand_world - global_position) + h * 0.5 + Vector3.DOWN * 1.1
		follow = _ease(10.0, delta)
	_blade = _blade.lerp(target, follow) if delta > 0.0 else target
	rig.blade_world = global_position + _blade


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
	"shoulders": {"clip": "back_squat", "hold": 9.3, "stick": "level", "back": 0.12},
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
	var bl := _blade
	# The puck point is part-way down the blade; the heel sits back toward the hands.
	var flat := Vector3(bl.x - top.x, 0.0, bl.z - top.z)
	var heel := bl - flat.normalized() * STICK_PUCK if flat.length() > 0.05 else bl
	_place_stick(top, heel, skater.heading - skater.right_dir() * skater.forehand_side())


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
