class_name Fan
extends Node3D
## A person in plain clothes on one of the game's own bodies (tools/build_fans.gd): a fan
## for the close-ups in the stands, the Zamboni's driver. The players' skeleton, clips,
## hair and faces, with a sweatshirt, jeans and boots instead of a uniform, and hands.
##
## Not for live play: each is a skinned body of its own (about 35 thousand triangles and
## seven draw calls), where the crowd's fans (Arena) are one draw call a section. Hidden,
## one costs nothing but memory: it stops animating (see _notification).
##
## Faces -Z like everything else in the game; its origin is on the floor under the feet
## (or under the seat, sitting: the hips sit about Rink.SEAT_H over it).

const CLOTH_SHADER := preload("res://scenes/actors/plain_cloth.gdshader")
## Seated idles for the stands: mostly hands in the lap (out on the knees, they show beside
## the head of whoever sits in the row in front; the two hunched clips, sitting_1 and
## sitting_3, show the camera the top of a head). At the wheel: hands forward on the knees.
const SIT_LOOPS := ["sitting_talking", "sitting_talking", "sitting", "sitting_talking", "sitting_talking", "sitting_laughing"]
const DRIVE_LOOPS := ["sitting", "sitting_2"]
const STAND_LOOPS := ["holding_idle"]
## What the fans in close-ups do, by mood: [seated, standing] clips, and the face that goes
## with it.
const MOODS := {
	"cheer": [["sitting_clap", "sitting_clap_2", "sitting_fist_pump", "sitting_yell", "cheering_while_sitting"],
			["standing_clap", "fist_pump", "cheering", "cheering_1", "rallying"], "cheer"],
	"clap": [["sitting_clap", "sitting_clap_2"], ["standing_clap"], "happy"],
	"groan": [["sitting_disbelief", "sitting_disapproval", "sitting_angry"], ["angry_gesture"], "angry"],
	"laugh": [["sitting_laughing", "sitting_clap_2"], ["standing_clap"], "happy"],
	"talk": [["sitting_talking"], ["holding_idle"], "smirk"],
}
## Sweatshirts when nothing says otherwise, jeans, boots (upper / sole).
const TOPS: Array[Color] = [
	Color(0.12, 0.13, 0.16), Color(0.72, 0.72, 0.7), Color(0.22, 0.28, 0.42), Color(0.4, 0.42, 0.45),
	Color(0.5, 0.12, 0.12), Color(0.16, 0.3, 0.2), Color(0.58, 0.52, 0.4), Color(0.3, 0.42, 0.6),
	Color(0.2, 0.2, 0.22), Color(0.42, 0.3, 0.22), Color(0.55, 0.34, 0.4), Color(0.84, 0.82, 0.78),
]
const JEANS: Array[Color] = [
	Color(0.13, 0.19, 0.32), Color(0.2, 0.27, 0.42), Color(0.09, 0.12, 0.2), Color(0.3, 0.38, 0.52),
	Color(0.07, 0.07, 0.08), Color(0.2, 0.2, 0.21), Color(0.45, 0.4, 0.3),
]
const BOOTS := [
	[Color(0.3, 0.2, 0.12), Color(0.1, 0.08, 0.07)], [Color(0.07, 0.07, 0.07), Color(0.05, 0.05, 0.05)],
	[Color(0.5, 0.38, 0.22), Color(0.82, 0.78, 0.68)], [Color(0.2, 0.2, 0.22), Color(0.85, 0.85, 0.83)],
	[Color(0.16, 0.12, 0.1), Color(0.3, 0.2, 0.12)],
]
const CREST_WIDTH := 0.2        ## m across, on a 1.8 m body
const CREST_DROP := 0.1         ## m its middle sits below the middle of the chest (the same)
## How far the fingers curl at rest, per joint down each finger (rad): the clips move the
## wrists but mostly leave the fingers flat.
const FINGER_CURL := [0.3, 0.45, 0.3]
const FINGER_CURL_ONE := 0.5     ## ...on a rig with one joint a finger (the male's)
## The seated clips are players slumped on a bench, eyes on the floor: fans hold their
## heads up to watch (rad, at the head's own joint: the neck stays put in its collar).
const HEAD_LIFT := {"sitting": 0.3, "sitting_2": 0.3, "sitting_talking": 0.12}
const GRIP_CURL := 2.0           ## how much further the fingers close round something held

var look := {}
var body: Node3D                  ## the instanced fan body (turned to face -Z)
var skel: Skeleton3D
var anim: AnimationPlayer
var face: FaceRig
var seated := true
var size := 1.0                   ## height scale

var head_lift := 1.0              ## how much of HEAD_LIFT the head is held up by, seated (0: as the clip has it)
## Over the clip, for whoever is doing something with their body (a driver): the back
## bent forward (rad), tipped to the left (rad), and the head turned to the left (rad).
var lean := 0.0
var sway := 0.0
var head_turn := 0.0
## How far short the arms are of what the hands hold (m; under 0: that much to spare, with
## the elbows a little bent), as last posed: whoever seats a fan leans it by this.
var reach_short := 0.0

var _loop := ""
var _loops: Array = SIT_LOOPS
var _busy := 0.0                  ## s left of a one-off reaction
var _fingers := []                ## [bone, the curl as a rotation in the bone's own axes]
var _nod := []                    ## the same for the neck and head: [bone, axis in the bone's own axes]
var _lift := 0.0
var _spine := []                  ## [bone, its own axes for "to the right" and "forward"]
var _arms := []                   ## per side (left, right): {arm, fore, hand, rest: the hand's rest frame, pole}
var _hold_frame: Node3D           ## what the hands hold on to (see hold)
var _hold := [[], []]
var _grip := 0.0                  ## 0 hands as the clip has them .. 1 on what they hold


## Runs after the clip each frame (a skeleton modifier's changes last one frame, so
## nothing here piles up): bends the back, curls the fingers, lifts and turns the head,
## and reaches the hands to whatever they hold.
class Pose extends SkeletonModifier3D:
	var fan: Fan

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or fan == null:
			return
		if absf(fan.lean) > 0.001 or absf(fan.sway) > 0.001:
			for f: Array in fan._spine:
				var q := Quaternion(f[1] as Vector3, fan.lean / fan._spine.size()) * Quaternion(f[2] as Vector3, -fan.sway / fan._spine.size())
				sk.set_bone_pose_rotation(f[0], sk.get_bone_pose_rotation(f[0]) * q)
		var curl := lerpf(1.0, GRIP_CURL, fan._grip)
		for f: Array in fan._fingers:
			var q: Quaternion = f[1]
			sk.set_bone_pose_rotation(f[0], sk.get_bone_pose_rotation(f[0]) * Quaternion(q.get_axis(), q.get_angle() * curl))
		for f: Array in fan._nod:
			# (the head stays level and looking ahead over a bent back)
			var up := -(fan._lift + fan.lean * 0.7) / fan._nod.size()
			sk.set_bone_pose_rotation(f[0], sk.get_bone_pose_rotation(f[0]) * Quaternion(f[1] as Vector3, up) * Quaternion(f[2] as Vector3, fan.head_turn / fan._nod.size()))
		if fan._grip > 0.001 and is_instance_valid(fan._hold_frame):
			fan.reach_short = -1.0
			var to_sk := sk.global_transform.affine_inverse() * fan._hold_frame.global_transform
			for side in 2:
				var h: Array = fan._hold[side]
				if h.size() == 3 and side < fan._arms.size():
					_reach(sk, fan._arms[side], to_sk * (h[0] as Vector3), (to_sk.basis * (h[1] as Vector3)).normalized(),
							(to_sk.basis * (h[2] as Vector3)).normalized(), fan._grip)

	## Two-bone reach: the wrist to `at`, the fingers pointing along `fingers`, the palm
	## facing `palm` (skeleton space), by `w` of the way from where the clip has the arm.
	func _reach(sk: Skeleton3D, arm: Dictionary, at: Vector3, fingers: Vector3, palm: Vector3, w: float) -> void:
		var a := sk.get_bone_global_pose(arm.arm)
		var f := sk.get_bone_global_pose(arm.fore)
		var h := sk.get_bone_global_pose(arm.hand)
		var s := a.origin
		var l1 := s.distance_to(f.origin)
		var l2 := f.origin.distance_to(h.origin)
		fan.reach_short = maxf(fan.reach_short, s.distance_to(at) - (l1 + l2) * 0.9)
		var to := h.origin.lerp(at, w) - s
		var d := clampf(to.length(), 0.05, (l1 + l2) * 0.995)
		var dir := to.normalized()
		# The elbow: on the circle both bones allow, toward the pole (down and out).
		var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var out := sqrt(maxf(l1 * l1 - along * along, 0.0))
		var pole: Vector3 = arm.pole
		var bend := pole - dir * pole.dot(dir)
		bend = bend.normalized() if bend.length() > 0.01 else Vector3.DOWN
		var elbow := s + dir * along + bend * out
		a.basis = Basis(Quaternion((f.origin - s).normalized(), (elbow - s).normalized())) * a.basis
		sk.set_bone_global_pose(arm.arm, a)
		f = sk.get_bone_global_pose(arm.fore)
		h = sk.get_bone_global_pose(arm.hand)
		f.basis = Basis(Quaternion((h.origin - f.origin).normalized(), (s + dir * d - f.origin).normalized())) * f.basis
		sk.set_bone_global_pose(arm.fore, f)
		h = sk.get_bone_global_pose(arm.hand)
		var p := (palm - fingers * palm.dot(fingers)).normalized()
		var want := Basis(fingers, p, fingers.cross(p)) * (arm.rest as Basis)
		h.basis = Basis(h.basis.orthonormalized().get_rotation_quaternion().slerp(want.get_rotation_quaternion(), w))
		sk.set_bone_global_pose(arm.hand, h)

static var _scenes := {}
static var _mats := {}


## Whether the fan bodies have been built (tools/build_fans.gd).
static func available() -> bool:
	return ResourceLoader.exists("res://assets/characters/fan_male.scn") and ResourceLoader.exists("res://assets/characters/fan_female.scn")


## A person at random: body, face, hair and clothes. Keys: body_type, skin_tone, hair_style,
## facial_hair, hair_color, eye_color, top, rib, pants, shoes, sole, size, build, seed, and
## optionally crest (a Texture2D printed on the chest).
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var l := {}
	l.body_type = "female" if rng.randf() < 0.42 else "male"
	l.skin_tone = SkaterVisual.SKIN_TONES[rng.rand_weighted(PackedFloat32Array([3.0, 3.0, 2.0, 1.2, 1.0, 0.8]))]
	l.merge(SkaterVisual.random_look(rng, l.body_type, l.skin_tone))
	l.top = TOPS[rng.randi() % TOPS.size()]
	l.rib = l.top
	l.pants = JEANS[rng.randi() % JEANS.size()]
	var b: Array = BOOTS[rng.randi() % BOOTS.size()]
	l.shoes = b[0]
	l.sole = b[1]
	l.size = rng.randf_range(0.94, 1.03)
	l.build = clampf(rng.randfn(0.04, 0.1), -0.12, 0.3)
	l.seed = rng.randi()
	return l


## The look dressed for a team: the sweatshirt in `color` with `trim` rib knit and the
## team's `logo` on the chest (null: none).
static func in_colors(l: Dictionary, color: Color, trim: Color, logo: Texture2D) -> Dictionary:
	var out := l.duplicate()
	out.top = color
	out.rib = trim
	if logo != null:
		out.crest = logo
	return out


static func create(l: Dictionary) -> Fan:
	var f := Fan.new()
	f.look = l
	f._build()
	return f


func _build() -> void:
	var kind: String = look.get("body_type", "male")
	if not _scenes.has(kind):
		_scenes[kind] = load("res://assets/characters/fan_%s.scn" % kind)
	body = (_scenes[kind] as PackedScene).instantiate()
	size = float(look.get("size", 1.0))
	body.rotation.y = PI          # (the bodies face +Z)
	body.scale = Vector3.ONE * size
	body.position.y = float(body.get_meta("sole", 0.0)) * size
	add_child(body)
	skel = body.get_node("Skeleton3D")
	var hs := float(body.get_meta("height", 1.8)) / 1.8
	var tone: Color = look.get("skin_tone", SkaterVisual.SKIN_TONES[1])
	var chest: AABB = body.get_meta("chest_box", AABB(Vector3(-0.18, 1.3, -0.1), Vector3(0.36, 0.2, 0.24)))
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", false, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match String(mi.name):
			"Skin":
				mi.material_override = SkaterVisual.skin_material(body, tone)
			"Outfit_Top":
				var crest: Texture2D = look.get("crest")
				mi.material_override = _cloth_material(0, crest)
				_dress(mi, look.get("top", TOPS[0]), look.get("rib", look.get("top", TOPS[0])))
				var c := chest.get_center()
				mi.set_instance_shader_parameter("crest_box", Vector4(c.x, c.y - CREST_DROP * hs, CREST_WIDTH * 0.5 * hs, c.z))
			"Outfit_Pants":
				mi.material_override = _cloth_material(1, null)
				_dress(mi, look.get("pants", JEANS[0]), look.get("pants", JEANS[0]))
			"Outfit_Shoes":
				mi.material_override = _cloth_material(2, null)
				_dress(mi, look.get("shoes", BOOTS[0][0]), look.get("sole", BOOTS[0][1]))
		if mi.name.begins_with("Outfit_") and mi.name != &"Outfit_Shoes":
			mi.mesh = BodyBuild.with_build(mi.mesh, skel, mi.skin)
	face = FaceRig.create_for(skel, body, kind, {"hair_color": look.get("hair_color", Color(0.2, 0.13, 0.08)),
			"eye_color": look.get("eye_color", Color(0.3, 0.2, 0.12)), "skin_tone": tone, "seed": look.get("seed", 0)}, "_fan")
	BodyBuild.apply(skel, float(look.get("build", 0.0)))
	_add_hair(kind)
	anim = AnimationPlayer.new()
	body.add_child(anim)
	anim.add_animation_library("", SkaterVisual.body_assets(kind)[1])
	_find_fingers()
	for bn in ["Head"]:
		var b := skel.find_bone(bn)
		if b >= 0:
			var inv := skel.get_bone_global_rest(b).basis.inverse()
			_nod.append([b, (inv * Vector3.RIGHT).normalized(), (inv * Vector3.UP).normalized()])
	for bn in ["Spine", "Spine1", "Spine2"]:
		var b := skel.find_bone(bn)
		if b >= 0:
			var inv := skel.get_bone_global_rest(b).basis.inverse()
			_spine.append([b, (inv * Vector3.RIGHT).normalized(), (inv * Vector3.BACK).normalized()])
	var pose := Pose.new()
	pose.fan = self
	skel.add_child(pose)
	sit()


static func _cloth_material(kind: int, crest: Texture2D) -> ShaderMaterial:
	var key := "%d|%d" % [kind, crest.get_instance_id() if crest else 0]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = CLOTH_SHADER
		m.set_shader_parameter("kind", kind)
		if crest != null:
			m.set_shader_parameter("crest", crest)
			m.set_shader_parameter("has_crest", true)
			m.set_shader_parameter("crest_aspect", float(crest.get_width()) / maxf(crest.get_height(), 1.0))
		_mats[key] = m
	return _mats[key]


static func _dress(mi: MeshInstance3D, cloth: Color, second: Color) -> void:
	mi.set_instance_shader_parameter("cloth", cloth)
	mi.set_instance_shader_parameter("second", second)


## Changes the clothes' colors (and the crest) of a fan already built.
func wear(top: Color, rib: Color, crest: Texture2D = null) -> void:
	look.top = top
	look.rib = rib
	var mi := skel.get_node_or_null("Outfit_Top") as MeshInstance3D
	if mi != null:
		mi.material_override = _cloth_material(0, crest)
		_dress(mi, top, rib)


func _attach(bone: String, node: Node3D, rest_xform: Transform3D) -> void:
	var att: BoneAttachment3D = null
	for c in skel.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == bone:
			att = c
	if att == null:
		att = BoneAttachment3D.new()
		att.bone_name = bone
		skel.add_child(att)
	node.transform = skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse() * rest_xform
	att.add_child(node)


## Hair and facial hair, as SkaterVisual fits them (no helmet to press them flat).
func _add_hair(kind: String) -> void:
	var head: AABB = body.get_meta("head_box", AABB(Vector3(-0.1, 1.55, -0.1), Vector3(0.2, 0.25, 0.22)))
	var top := Vector3(head.get_center().x, head.end.y, head.get_center().z)
	var b := Basis.from_scale(Vector3.ONE * head.size.x)
	var hair_color: Color = look.get("hair_color", Color(0.2, 0.13, 0.08))
	for id: String in [look.get("hair_style", ""), look.get("facial_hair", "")]:
		var path := SkaterVisual.hair_mesh_path(id, kind)
		if id == "" or path == "":
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = load(path)
		mi.material_override = SkaterVisual.hair_material(id, hair_color)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_attach("Head", mi, Transform3D(b, top))
		mi.name = "Hair_" + id
		if id == look.get("facial_hair", "") and face != null:
			face.follow_jaw(mi)


func _find_fingers() -> void:
	for side: String in ["Left", "Right"]:
		var hand := skel.find_bone(side + "Hand")
		if hand < 0:
			continue
		# The fingers' first joints (the thumb apart), from the thumb's side to the little
		# finger's as the rig lists them.
		var roots: Array[int] = []
		for c in skel.get_bone_children(hand):
			var n := skel.get_bone_name(c).trim_prefix("x_")
			if n.contains("Thumb"):
				continue
			if n.contains("FingerBase"):   # (the CMU rig hangs its fingers off one more bone)
				for cc in skel.get_bone_children(c):
					roots.append(cc)
			else:
				roots.append(c)
		if roots.is_empty():
			continue
		var h := skel.get_bone_global_rest(hand).origin
		var mid := Vector3.ZERO
		for r in roots:
			mid += skel.get_bone_global_rest(r).origin
		var along := (mid / roots.size() - h).normalized()
		# Across the hand, toward the thumb: forward when the arm points out to the side.
		var across := (Vector3.BACK - along * along.dot(Vector3.BACK)).normalized()
		var turn := -1.0 if side == "Left" else 1.0
		# For reaching (Pose._reach): the hand's rest frame from its own shape (fingers,
		# palm, across), so a grip can be asked for by where the fingers and palm point.
		var palm := along.cross(across) if side == "Left" else across.cross(along)
		_arms.append({"arm": skel.find_bone(side + "Arm"), "fore": skel.find_bone(side + "ForeArm"), "hand": hand,
				"rest": Basis(along, palm, along.cross(palm)).inverse() * skel.get_bone_global_rest(hand).basis,
				"pole": Vector3(0.5 if side == "Left" else -0.5, -1.0, -0.25).normalized()})
		for r in roots:
			var b := r
			var depth := 0
			var one := skel.get_bone_children(r).is_empty()
			while b >= 0 and depth < FINGER_CURL.size():
				var local := (skel.get_bone_global_rest(b).basis.inverse() * across).normalized()
				_fingers.append([b, Quaternion(local, turn * (FINGER_CURL_ONE if one else float(FINGER_CURL[depth])))])
				var kids := skel.get_bone_children(b)
				b = kids[0] if kids.size() > 0 else -1
				depth += 1


# --- What they do -------------------------------------------------------------------

## Sits (the default): a looping idle from a random point, so a row doesn't move as one.
## `loops`: the idles to pick from (DRIVE_LOOPS at a wheel).
func sit(loops: Array = SIT_LOOPS) -> void:
	seated = true
	_loops = loops
	_idle()


func stand() -> void:
	seated = false
	_idle()


func _idle(blend := 0.3) -> void:
	var pool: Array = _loops if seated else STAND_LOOPS
	var clip: String = pool[randi() % pool.size()]
	if not anim.has_animation(clip):
		return
	_loop = clip
	_busy = 0.0
	anim.play(clip, blend, randf_range(0.85, 1.1))
	anim.seek(randf() * anim.get_animation(clip).length, true)


## Puts the hands on something that moves with `frame` (a steering wheel): per hand, in
## `frame`'s own space, [where the wrist goes, the way the fingers point, the way the palm
## faces]; an empty array leaves that hand to the clip. Call it as often as the grips move.
func hold(frame: Node3D, left: Array, right: Array) -> void:
	_hold_frame = frame
	_hold = [left, right]


func let_go() -> void:
	_hold_frame = null


## A one-off reaction (MOODS), then back to the idle. `delay` staggers a group.
func react(mood: String, delay := 0.0) -> void:
	if not MOODS.has(mood):
		return
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
		if not is_inside_tree():
			return
	var m: Array = MOODS[mood]
	var pool: Array = m[0 if seated else 1]
	var clip: String = pool[randi() % pool.size()]
	if not anim.has_animation(clip):
		return
	var length := anim.get_animation(clip).length
	_busy = clampf(length, 2.0, 4.5)
	anim.play(clip, 0.25, randf_range(0.95, 1.1))
	if face != null:
		face.set_expression(m[2], _busy)
		if mood == "cheer" or mood == "talk":
			face.talk(_busy * 0.7)


func _process(delta: float) -> void:
	if _busy > 0.0:
		_busy -= delta
		if _busy <= 0.0:
			_idle(0.35)
	# (the reactions hold their own heads up)
	_lift = move_toward(_lift, _lift_want(), delta * 1.5)
	_grip = move_toward(_grip, 1.0 if is_instance_valid(_hold_frame) else 0.0, delta * 3.0)


func _lift_want() -> float:
	return head_lift * float(HEAD_LIFT.get(_loop, 0.0)) if seated and _busy <= 0.0 else 0.0


func _ready() -> void:
	_lift = _lift_want()
	_notification(NOTIFICATION_VISIBILITY_CHANGED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and anim != null:
		# Out of sight, nothing runs: no clip, no face, no skinning to update.
		var on := is_visible_in_tree()
		anim.active = on
		set_process(on)
