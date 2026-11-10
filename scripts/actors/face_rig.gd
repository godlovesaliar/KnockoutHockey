class_name FaceRig
extends Node3D
## A face that's alive: eye color, eyes that look around (or at the camera in menus),
## blinks, eyebrows, and a jaw and smile for talking and expressions. The built bodies
## have no face bones, so:
##   * the eyes stay one skinned mesh; eye.gdshader slides the iris across the eyeball
##     texture (gaze) and tints it (eye color)
##   * eyelids are sphere shells over each eyeball, cut to the lid line (eyelid.gdshader)
##   * eyebrows are ribbons laid on the brow ridge (brow.gdshader raises / knits them)
##   * the jaw and smile are blend shapes added to the body mesh on first use (and to
##     facial hair, so a beard opens with the chin)
## This node rides the Head bone in rest-pose skeleton axes (+Z forward, +X the
## character's left), origin between the eyes. Bodies without an "Eyes" mesh (ybot)
## get no face.

const EYE_SHADER := preload("res://scenes/actors/eye.gdshader")
const LID_SHADER := preload("res://scenes/actors/eyelid.gdshader")
const BROW_SHADER := preload("res://scenes/actors/brow.gdshader")
const MOUTH_SHADER := preload("res://scenes/actors/mouth.gdshader")

## Lip seam per body (rest pose, skeleton space: middle of the seam) and the mouth's half
## width. The bodies' lips are split along the seam (the mesh has an inner mouth), which
## is what lets the jaw open. Measured from the meshes; a new body needs its own entry.
const MOUTH := {
	"male": [Vector3(0.0, 1.6440, 0.0965), 0.0245],
	"female": [Vector3(0.0, 1.5617, 0.0870), 0.0227],
}
const MALE_EYE_TO_MOUTH := 0.0768   ## the face proportions below are tuned on the male body
const JAW_OPEN := 0.22              ## jaw blend shape at 1 (rad)
const FAR := 14.0                   ## past this from the camera the face stops animating

## Expression targets: jaw open, smile (negative = frown), brow raise / furrow, squint.
const EXPRESSIONS := {
	"neutral": {},
	"smirk": {"smile": 0.45, "raise": 0.15},
	"happy": {"smile": 0.85, "raise": 0.3, "squint": 0.2},
	"cheer": {"jaw": 0.8, "smile": 0.6, "raise": 0.7, "squint": 0.25},
	"angry": {"jaw": 0.06, "smile": -0.5, "raise": -0.2, "furrow": 1.0, "squint": 0.35},
	"hurt": {"jaw": 0.35, "smile": -0.6, "furrow": 0.6, "squint": 0.65},
	"ko": {"jaw": 0.3, "smile": -0.2, "raise": -0.3, "squint": 1.0},
	"focused": {"smile": -0.1, "furrow": 0.35, "squint": 0.12},
}
const REST_LID := 0.16   ## relaxed eyes: the upper lid rests a little over the iris
## Where the face's own eye opening ends, in eye radii from the eyeball center (the
## opening sits low on the ball); the lid shells only draw inside it (eyelid.gdshader).
const LID_TOP := 0.3
const LID_BOTTOM := -0.55

var look_at_camera := false   ## menus: eyes on the camera, with glances away
var chatty := false           ## menus: says something now and then (mouth moves), smirks
var look_target: Variant = null   ## a world point to look at (Vector3), or null
var lid_override := -1.0      ## >= 0: hold the lids at this closure (close-up checks)

var expression := "neutral"
var _base_expression := "neutral"
var _expr_left := 0.0

var _v: SkaterVisual
var _d: Dictionary
var _body_mi: MeshInstance3D
var _eyes_mi: MeshInstance3D
var _followers: Array[MeshInstance3D] = []
var _lids: Array[MeshInstance3D] = []
var _brows: MeshInstance3D
var _rng := RandomNumberGenerator.new()

var _cur := {"jaw": 0.0, "smile": 0.0, "raise": 0.0, "furrow": 0.0, "squint": 0.0}
var _gaze := Vector2.ZERO
var _glance := Vector2.ZERO
var _next_glance := 0.0
var _blink_t := -1.0
var _next_blink := 1.0
var _talk_left := 0.0
var _syllable := 0.0
var _syllable_left := 0.0
var _talk_raise := 0.0
var _jaw := 0.0
var _next_chat := 2.0

static var _data := {}   ## body kind -> measurements, meshes and materials (shared)


## Gives `v`'s body a face, if it has eyes. Returns null otherwise.
static func create(v: SkaterVisual) -> FaceRig:
	var eyes := v.skel.get_node_or_null("Eyes") as MeshInstance3D
	var kind := v.skater.body_type
	if eyes == null or not MOUTH.has(kind):
		return null
	var f := FaceRig.new()
	f.name = "Face"
	f._setup(v, eyes)
	return f


func _setup(v: SkaterVisual, eyes: MeshInstance3D) -> void:
	_v = v
	_eyes_mi = eyes
	var kind := v.skater.body_type
	for mi: MeshInstance3D in v.skel.find_children("*", "MeshInstance3D", false, false):
		if mi != eyes and not mi.name.begins_with("Outfit_"):
			_body_mi = mi
	_d = _body_data(kind, v.body, _body_mi.mesh, eyes.mesh)
	_body_mi.mesh = _d.mesh
	_rng.seed = hash([v.skater.hair_color, v.skater.eye_color, v.skater.skin_tone, v.skater.hair_style, v.skater.number])
	v.attach_node("Head", self, Transform3D(Basis(), _d.mid))

	eyes.material_override = _d.eye_mat
	eyes.set_instance_shader_parameter("eye_color", v.skater.eye_color)

	var r: float = _d.eye_r
	for side in 2:
		var lid := MeshInstance3D.new()
		lid.name = "Lid" + ("R" if side == 0 else "L")
		lid.mesh = _lid_mesh()
		lid.material_override = _d.lid_mat
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lid.position = (_d.eye[side] as Vector3) - (_d.mid as Vector3)
		lid.scale = Vector3.ONE * r * 1.1
		lid.set_instance_shader_parameter("tone", v.skater.skin_tone)
		add_child(lid)
		_lids.append(lid)

	_brows = MeshInstance3D.new()
	_brows.name = "Brows"
	_brows.mesh = _d.brows
	_brows.material_override = _d.brow_mat
	_brows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hc := v.skater.hair_color
	# Brows run a little darker than the hair (blond and red hair especially); gray stays gray.
	var bc := hc.darkened(0.25) if hc.s > 0.25 else hc.darkened(0.1)
	_brows.set_instance_shader_parameter("brow_color", bc)
	var thick := _rng.randf_range(0.8, 1.0) if kind == "male" else _rng.randf_range(0.7, 0.85)
	_brows.set_instance_shader_parameter("thick", thick)
	add_child(_brows)

	# The mouth's own lining faces inward (culled from the front), so an open mouth would
	# show straight through the head: a dark cavity with a hint of teeth sits behind the
	# lips instead, out of sight while they're closed.
	var cav := MeshInstance3D.new()
	cav.name = "Mouth"
	cav.mesh = _lid_mesh()
	cav.material_override = _d.mouth_mat
	cav.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m: Vector3 = _d.mouth
	var s: float = _d.scale
	cav.position = Vector3(m.x, m.y - 0.008 * s, m.z - 0.022 * s) - (_d.mid as Vector3)
	cav.scale = Vector3(float(_d.mouth_w) * 0.95, 0.02 * s, 0.016 * s)
	add_child(cav)

	_next_blink = _rng.randf_range(0.5, 4.0)
	_next_chat = _rng.randf_range(1.0, 4.0)
	_apply()


## Facial hair rides the head bone rigidly; this gives it the jaw blend shape too, so the
## chin of a beard drops with the jaw.
func follow_jaw(mi: MeshInstance3D) -> void:
	var head := _v.skel.find_bone("Head")
	var to_rest := _v.skel.get_bone_global_rest(head) * mi.transform
	var key := "%s|%s" % [_v.skater.body_type, mi.mesh.resource_path]
	if not _data.has(key):
		_data[key] = _jaw_follower_mesh(mi.mesh, to_rest, _d)
	mi.mesh = _data[key]
	_followers.append(mi)


## Holds an expression for `seconds`, or makes it the resting one (seconds < 0).
func set_expression(e: String, seconds := -1.0) -> void:
	if not EXPRESSIONS.has(e):
		return
	if seconds < 0.0:
		_base_expression = e
		if _expr_left <= 0.0:
			expression = e
	else:
		expression = e
		_expr_left = seconds


## Moves the mouth as if talking for `seconds`.
func talk(seconds: float) -> void:
	_talk_left = maxf(_talk_left, seconds)


func blink() -> void:
	if _blink_t < 0.0:
		_blink_t = 0.0


## Faces follow what the body is doing: clip names from SkaterVisual.play_clip.
func react_to_clip(clip: String, seconds: float) -> void:
	var t := seconds if seconds > 0.0 and seconds < 30.0 else 2.5
	if clip in Fight.FINISHES:   # out cold, however they go down
		set_expression("ko", t)
	elif clip == "taunt":
		set_expression("smirk", t)
		talk(t * 0.8)
	elif clip in SkaterVisual.CELEBRATIONS:
		set_expression("cheer", t)
	elif clip.contains("hit") or clip.contains("dizzy") or clip.contains("fall") or clip.contains("knocked"):
		set_expression("hurt", t)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _v.bench_frozen:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) > FAR * FAR:
		return
	_tick(delta, cam)
	_apply()


func _tick(delta: float, cam: Camera3D) -> void:
	# Expression: held ones run out back to the resting one.
	if _expr_left > 0.0:
		_expr_left -= delta
		if _expr_left <= 0.0:
			expression = _base_expression
	var want: Dictionary = EXPRESSIONS[expression]
	var k := 1.0 - exp(-10.0 * delta)
	for key: String in _cur:
		_cur[key] = lerpf(_cur[key], float(want.get(key, 0.0)), k)

	# Menus: now and then a few words, or a smirk.
	if chatty:
		_next_chat -= delta
		if _next_chat <= 0.0:
			_next_chat = _rng.randf_range(3.0, 8.0)
			var roll := _rng.randf()
			if roll < 0.55:
				talk(_rng.randf_range(0.8, 2.2))
			if roll > 0.35 and expression == _base_expression:
				set_expression("smirk" if _rng.randf() < 0.7 else "happy", _rng.randf_range(1.2, 2.5))

	# Talking: syllables of random openness, with pauses; the brows lift on some.
	var talk_jaw := 0.0
	if _talk_left > 0.0:
		_talk_left -= delta
		_syllable_left -= delta
		if _syllable_left <= 0.0:
			_syllable_left = _rng.randf_range(0.07, 0.17)
			_syllable = 0.0 if _rng.randf() < 0.2 else _rng.randf_range(0.15, 0.6)
			if _rng.randf() < 0.15:
				_talk_raise = _rng.randf_range(0.3, 0.7)
		talk_jaw = _syllable
	_talk_raise = move_toward(_talk_raise, 0.0, delta * 1.5)
	var jaw_want := maxf(_cur.jaw, talk_jaw)
	_jaw = lerpf(_jaw, jaw_want, 1.0 - exp(-22.0 * delta))

	# Blinks every few seconds (sometimes twice).
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t > 0.2:
			_blink_t = -1.0
	else:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_t = 0.0
			_next_blink = 0.25 if _rng.randf() < 0.15 else _rng.randf_range(1.8, 5.5)

	# Gaze: at the target, with small saccades and glances away.
	_next_glance -= delta
	var target: Variant = look_target
	if look_at_camera and cam != null:
		target = cam.global_position
	if _next_glance <= 0.0:
		if target != null:
			_glance = Vector2.ZERO if _rng.randf() < 0.7 else Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.1))
			_next_glance = _rng.randf_range(0.6, 2.8) if _glance == Vector2.ZERO else _rng.randf_range(0.3, 0.9)
		else:
			_glance = Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.15, 0.1))
			_next_glance = _rng.randf_range(0.5, 2.5)
		# A blink often goes with a big eye move.
		if _rng.randf() < 0.25:
			blink()
	var aim := _glance
	if target != null:
		var local: Vector3 = global_transform.affine_inverse() * (target as Vector3)
		if local.z > 0.05:
			aim += Vector2(atan2(local.x, local.z), atan2(local.y, Vector2(local.x, local.z).length()))
	aim = aim.clamp(Vector2(-0.5, -0.35), Vector2(0.5, 0.3))
	_gaze = _gaze.lerp(aim, 1.0 - exp(-28.0 * delta))


func _blink_amount() -> float:
	if _blink_t < 0.0:
		return 0.0
	if _blink_t < 0.07:
		return _blink_t / 0.07
	if _blink_t < 0.1:
		return 1.0
	return 1.0 - (_blink_t - 0.1) / 0.1


func _apply() -> void:
	var blink_c := _blink_amount()
	var squint: float = _cur.squint
	# Looking down brings the upper lid with it.
	var down := clampf(-_gaze.y / 0.35, 0.0, 1.0) * 0.3
	var up_c := maxf(blink_c, clampf(REST_LID + squint * 0.6 + down, 0.0, 1.0))
	var lo_c := maxf(blink_c, squint)
	if lid_override >= 0.0:
		up_c = lid_override
		lo_c = lid_override
	for lid in _lids:
		lid.set_instance_shader_parameter("upper", lerpf(LID_TOP, -0.32, up_c))
		lid.set_instance_shader_parameter("lower", lerpf(LID_BOTTOM, -0.26, lo_c))
	_eyes_mi.set_instance_shader_parameter("gaze", _gaze)
	_brows.set_instance_shader_parameter("raise", clampf(_cur.raise + _talk_raise - blink_c * 0.15, -1.0, 1.0))
	_brows.set_instance_shader_parameter("furrow", _cur.furrow)
	_body_mi.set_blend_shape_value(0, _jaw)
	_body_mi.set_blend_shape_value(1, _cur.smile)
	for f in _followers:
		f.set_blend_shape_value(0, _jaw)


# --- Per body (built once, shared) -------------------------------------------------

static var _lid_sphere: SphereMesh


static func _lid_mesh() -> SphereMesh:
	if _lid_sphere == null:
		_lid_sphere = SphereMesh.new()
		_lid_sphere.radius = 1.0
		_lid_sphere.height = 2.0
		_lid_sphere.radial_segments = 24
		_lid_sphere.rings = 16
	return _lid_sphere


static func _body_data(kind: String, body_root: Node, body_mesh: Mesh, eye_mesh: Mesh) -> Dictionary:
	if _data.has(kind):
		return _data[kind]
	var d := {}
	_measure_eyes(d, eye_mesh)
	d.mouth = MOUTH[kind][0]
	d.mouth_w = MOUTH[kind][1]
	d.scale = ((d.mid as Vector3).y - (d.mouth as Vector3).y) / MALE_EYE_TO_MOUTH
	d.mesh = _face_mesh(body_mesh, d)
	d.brows = _brow_mesh(body_mesh, d, kind)

	var em := ShaderMaterial.new()
	em.shader = EYE_SHADER
	var tex_path: String = body_root.get_meta("eye_tex", "")
	if tex_path != "":
		em.set_shader_parameter("eye_tex", load(tex_path))
	em.set_shader_parameter("front_r", d.front[0])
	em.set_shader_parameter("front_l", d.front[1])
	em.set_shader_parameter("axes_r", d.axes[0])
	em.set_shader_parameter("axes_l", d.axes[1])
	d.eye_mat = em
	var lm := ShaderMaterial.new()
	lm.shader = LID_SHADER
	lm.set_shader_parameter("top", LID_TOP + 0.04)
	lm.set_shader_parameter("bottom", LID_BOTTOM - 0.04)
	d.lid_mat = lm
	var mm := ShaderMaterial.new()
	mm.shader = MOUTH_SHADER
	d.mouth_mat = mm
	var bm := ShaderMaterial.new()
	bm.shader = BROW_SHADER
	bm.render_priority = 1
	d.brow_mat = bm
	_data[kind] = d
	return d


## Eyeball centers and radius (the mesh is two low-poly half spheres), and for gaze, where
## straight ahead lands on each eye's texture and how the UVs move as it turns.
static func _measure_eyes(d: Dictionary, eye_mesh: Mesh) -> void:
	var arr := eye_mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var midx := 0.0
	for p in v:
		midx += p.x
	midx /= v.size()
	var centers: Array[Vector3] = []
	var r := 0.0
	for side in 2:   # 0 = the character's right (-X), 1 = left (+X)
		var box := AABB()
		var first := true
		for p in v:
			if (p.x > midx) != (side == 1):
				continue
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
		var rr := maxf(box.size.x, box.size.y) * 0.5
		r += rr * 0.5
		centers.append(Vector3(box.get_center().x, box.get_center().y, box.end.z - rr))
	d.eye = centers
	d.eye_r = r
	d.mid = (centers[0] + centers[1]) * 0.5
	# Gaze: a least-squares fit of each eye's UVs against direction from its center, over
	# the vertices facing forward (single rays snag on the low-poly ball's UV seams).
	var fronts := []
	var axes := []
	for side in 2:
		var c := centers[side]
		var m := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)   # normal equations
		var bu := Vector3.ZERO
		var bv := Vector3.ZERO
		for i in v.size():
			var dir := (v[i] - c).normalized()
			if (v[i].x > midx) != (side == 1) or dir.z < 0.55:
				continue
			var row := Vector3(1.0, atan2(dir.x, dir.z), atan2(dir.y, dir.z))
			m.x += row * row.x
			m.y += row * row.y
			m.z += row * row.z
			bu += row * uv[i].x
			bv += row * uv[i].y
		var inv := m.inverse()
		var cu := inv * bu
		var cv := inv * bv
		fronts.append(Vector2(cu.x, cv.x))
		axes.append(Vector4(cu.y, cv.y, cu.z, cv.z))
	d.front = fronts
	d.axes = axes


## Lip seam height across the mouth (it dips a little toward the corners).
static func _seam_y(d: Dictionary, x: float) -> float:
	var m: Vector3 = d.mouth
	var u := x / float(d.mouth_w)
	return m.y - 0.0013 * float(d.scale) * u * u


## How much a point (rest pose) belongs to the lower jaw, 0..1. `below`: 1 if it's on
## the lower lip / chin side of the seam, 0 above (within the mouth's width the seam
## splits them; past the corners the cheek blends across).
static func _jaw_weight(d: Dictionary, p: Vector3, below_hard: float) -> float:
	var m: Vector3 = d.mouth
	var s: float = d.scale
	var hw: float = d.mouth_w
	var ax := absf(p.x - m.x)
	var sy := _seam_y(d, minf(ax, hw))
	var band := 0.002 * s + maxf(ax - hw, 0.0) * 0.7
	var soft := smoothstep(sy + band, sy - band, p.y)
	var below := lerpf(soft, below_hard, smoothstep(hw + 0.006 * s, hw - 0.002 * s, ax))
	var w := below
	w *= smoothstep(m.z - 0.095 * s, m.z - 0.05 * s, p.z)     # front of the face
	w *= smoothstep(m.y - 0.08 * s, m.y - 0.045 * s, p.y)     # not down the neck
	w *= smoothstep(0.075 * s, 0.05 * s, ax)                   # not the sides of the head
	return w


static func _jaw_pivot(d: Dictionary) -> Vector3:
	var m: Vector3 = d.mouth
	var s: float = d.scale
	return Vector3(m.x, m.y + 0.015 * s, m.z - 0.085 * s)


## The body mesh with two blend shapes: 0 "jaw" (open), 1 "smile" (corners up and out;
## negative frowns).
static func _face_mesh(mesh: Mesh, d: Dictionary) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var m: Vector3 = d.mouth
	var s: float = d.scale
	var hw: float = d.mouth_w
	# Which side of the seam each vertex's triangles lie on: the seam's vertices come in
	# pairs at the same spot, one for each lip.
	var tri_y := PackedFloat32Array()
	tri_y.resize(v.size())
	var tri_n := PackedInt32Array()
	tri_n.resize(v.size())
	for t in range(0, idx.size(), 3):
		var cy := (v[idx[t]].y + v[idx[t + 1]].y + v[idx[t + 2]].y) / 3.0
		for k in 3:
			tri_y[idx[t + k]] += cy
			tri_n[idx[t + k]] += 1
	var pivot := _jaw_pivot(d)
	# Blend shapes go in as offsets from the base (this Godot adds them to it as given).
	var jv := PackedVector3Array()
	jv.resize(v.size())
	var jn := jv.duplicate()
	var sv := jv.duplicate()
	var zero_n := jv.duplicate()
	var zero_t := PackedFloat32Array()
	zero_t.resize(v.size() * 4)
	for i in v.size():
		var p := v[i]
		if absf(p.x - m.x) > 0.09 * s or absf(p.y - m.y) > 0.1 * s or p.z < m.z - 0.11 * s:
			continue
		var sy := _seam_y(d, minf(absf(p.x - m.x), hw))
		var below_hard := 1.0 if p.y < sy else 0.0
		if absf(p.y - sy) < 0.0015 * s:
			# On the seam: the upper lip's copy faces down, the lower lip's up.
			if absf(n[i].y) > 0.15:
				below_hard = 1.0 if n[i].y > 0.0 else 0.0
			elif tri_n[i] > 0:
				below_hard = 1.0 if tri_y[i] / tri_n[i] < p.y else 0.0
		var w := _jaw_weight(d, p, below_hard)
		if w > 0.0:
			var rot := Basis(Vector3.RIGHT, JAW_OPEN * w)
			jv[i] = pivot + rot * (p - pivot) - p
			jn[i] = rot * n[i] - n[i]
		# Smile: around each mouth corner, up, out and back a little.
		var side := signf(p.x - m.x)
		var corner := Vector3(m.x + side * hw, _seam_y(d, hw), m.z - 0.012 * s)
		var sig := 0.011 * s
		var g := exp(-p.distance_squared_to(corner) / (2.0 * sig * sig))
		if p.z > m.z - 0.04 * s:
			sv[i] = Vector3(side * 0.0025, 0.003, -0.0015) * s * g
	var jaw := []
	jaw.resize(Mesh.ARRAY_MAX)
	jaw[Mesh.ARRAY_VERTEX] = jv
	jaw[Mesh.ARRAY_NORMAL] = jn
	jaw[Mesh.ARRAY_TANGENT] = zero_t
	var smile := []
	smile.resize(Mesh.ARRAY_MAX)
	smile[Mesh.ARRAY_VERTEX] = sv
	smile[Mesh.ARRAY_NORMAL] = zero_n
	smile[Mesh.ARRAY_TANGENT] = zero_t
	var out := ArrayMesh.new()
	out.add_blend_shape("jaw")
	out.add_blend_shape("smile")
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [jaw, smile], {}, _keep_flags(mesh.surface_get_format(0)))
	# (No custom_aabb: a fixed one overrides the skinned mesh's pose-following bounds, and
	# a skater down on the ice had the skin culled out from under the eyes and hair.)
	return out


## The format flags add_surface_from_arrays needs back (custom channel formats, 8 bone
## weights); the rest come from the arrays themselves.
static func _keep_flags(fmt: int) -> int:
	var keep := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for k in 4:
		keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	return fmt & keep


## A rigid head-space mesh (facial hair) with the jaw blend shape. `to_rest` maps its
## vertices to rest-pose skeleton space.
static func _jaw_follower_mesh(mesh: Mesh, to_rest: Transform3D, d: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.add_blend_shape("jaw")
	var back := to_rest.affine_inverse()
	var pivot := _jaw_pivot(d)
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var jv := PackedVector3Array()
		jv.resize(v.size())
		var jn := jv.duplicate()
		for i in v.size():
			var p := to_rest * v[i]
			var sy := _seam_y(d, minf(absf(p.x), d.mouth_w))
			var w := _jaw_weight(d, p, 1.0 if p.y < sy else 0.0)
			if w > 0.0:
				var rot := Basis(Vector3.RIGHT, JAW_OPEN * w)
				jv[i] = back * (pivot + rot * (p - pivot)) - v[i]
				if n != null and not n.is_empty():
					jn[i] = (back.basis * (rot * (to_rest.basis * n[i]))).normalized() - n[i]
		var bs := []
		bs.resize(Mesh.ARRAY_MAX)
		bs[Mesh.ARRAY_VERTEX] = jv
		bs[Mesh.ARRAY_NORMAL] = jn if n != null and not n.is_empty() else null
		if arr[Mesh.ARRAY_TANGENT] != null:
			var zt := PackedFloat32Array()
			zt.resize((arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size())
			bs[Mesh.ARRAY_TANGENT] = zt
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [bs], {}, _keep_flags(mesh.surface_get_format(si)))
		out.surface_set_material(si, mesh.surface_get_material(si))
	return out


## Both eyebrows as ribbons along the brow ridge (face space, origin between the eyes):
## following the ridge over each eye and tapering down at the tail, thick at the inner
## end, cast onto the skin. On both bodies the ridge peaks about 1.1-1.3 eye radii
## above the eye center.
static func _brow_mesh(body_mesh: Mesh, d: Dictionary, kind: String) -> ArrayMesh:
	var arr := body_mesh.surface_get_arrays(0)
	var bv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var mid: Vector3 = d.mid
	var r: float = d.eye_r
	# Skin triangles around the brows, to cast the ribbon onto.
	var tris := PackedVector3Array()
	for t in range(0, bi.size(), 3):
		var a := bv[bi[t]]
		if absf(a.x - mid.x) < 0.085 and a.y > mid.y - 0.005 and a.y < mid.y + 0.06 and a.z > mid.z - 0.04:
			tris.append_array([a, bv[bi[t + 1]], bv[bi[t + 2]]])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var rows := 3   # across the ribbon: bottom, middle, top (the ridge curves under it)
	var ex := absf((d.eye[1] as Vector3).x - mid.x)
	var width := 1.0 if kind == "male" else 0.85
	for side: float in [-1.0, 1.0]:
		var pts := []
		for k in segs + 1:
			var t := float(k) / segs
			var x := mid.x + side * lerpf(ex - 1.45 * r, ex + 1.25 * r, t)
			var y := mid.y + r * (1.12 + 0.2 * sin(PI * pow(t, 0.8)) - 0.3 * t * t)
			var w := r * lerpf(0.62, 0.3, pow(t, 1.2)) * width
			pts.append([Vector2(x, y), w, t])
		for k in pts.size():
			var p: Vector2 = pts[k][0]
			var prev: Vector2 = pts[maxi(k - 1, 0)][0]
			var next: Vector2 = pts[mini(k + 1, pts.size() - 1)][0]
			var tan := (next - prev).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			if nrm.y < 0.0:
				nrm = -nrm
			for e in rows:
				var f := float(e) / (rows - 1)
				var q: Vector2 = p + nrm * float(pts[k][1]) * (f - 0.5)
				var z := _skin_z(tris, q, mid.z)
				st.set_uv(Vector2(pts[k][2], f))
				st.set_normal(Vector3(0, 0.25, 1).normalized())
				st.add_vertex(Vector3(q.x, q.y, z + 0.0008) - mid)
	for side in 2:
		var o := side * (segs + 1) * rows
		for k in segs:
			for e in rows - 1:
				var a := o + k * rows + e
				var b := a + rows
				st.add_index(a)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b + 1)
	return st.commit()


## The front-most skin at (x, y): a ray cast back onto the skin triangles.
static func _skin_z(tris: PackedVector3Array, q: Vector2, fallback: float) -> float:
	var from := Vector3(q.x, q.y, fallback + 0.2)
	var best := -INF
	for t in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.BACK * -1.0, tris[t], tris[t + 1], tris[t + 2])
		if hit != null:
			best = maxf(best, (hit as Vector3).z)
	return best if best > -INF else fallback
