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
## Skin tones to pick from (sRGB), light to dark. The player editor (M7) will set them.
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.80, 0.69), Color(0.91, 0.73, 0.60), Color(0.82, 0.62, 0.47),
	Color(0.68, 0.48, 0.33), Color(0.50, 0.34, 0.23), Color(0.34, 0.22, 0.15),
]
const SKATE_LIFT := 0.06          ## skate blade height under the boot
const CELEBRATIONS := ["fist_pump", "cheering", "cheering_1", "rallying"]

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
var charge_bar: MeshInstance3D
var spray: CPUParticles3D

var _yaw := 0.0
var _lean := 0.0
var _crouch := 0.0
var _bend := 0.3
var _twist := 0.0
var _stride := 0.0
var _stride_amt := 0.0
var _free_arm := 0.0
var _blade := Vector3.ZERO        ## blade position relative to the skater
var _marker_on := false
var _tag: Label3D
const STAMINA_W := 140        ## stamina bar size in (fixed, on-screen) pixels
const STAMINA_H := 14
var _stamina_back: Sprite3D      ## the controlled player's stamina, under them on screen
var _stamina_fill: Sprite3D
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
	{"mesh": preload("res://assets/characters/helmet_b.res"), "fit": 1.3, "raise": 0.16, "back": 0.04},
]
const STICK_MESH := preload("res://assets/characters/stick.res")
const SKATE_MESH := preload("res://assets/characters/skate.res")
const GLOVE_MESH := preload("res://assets/characters/glove.res")   ## a right glove, origin at the wrist, sized for 1.8 m
const SKATE_LEN := 0.3         ## skate length for a 1.8 m body
const DIGITS := preload("res://assets/characters/digits.png")   ## tools/build_digits.gd
const DIGIT_FILL := 0.84        ## share of a digit-sheet cell's height the digit fills
const NUMBER_HEIGHT := 0.24     ## back number height for a 1.8 m body
const CREST_WIDTH := 0.34       ## jersey crest width for a 1.8 m body
const STICK_PUCK := 0.1        ## where on the blade the puck sits, from the heel (m)
static var _bodies := {}
var _gloves: Array[Node3D] = []   ## glove meshes (hidden in a fight)
static var _numbers := {}         ## "number|fill|outline" -> ImageTexture
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
	var glove := MeshUtil.material(c.gloves, 0.55)
	glove.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	hm.set_surface_override_material(0, helmet)
	hm.set_surface_override_material(1, MeshUtil.material(Color(0.92, 0.92, 0.9), 0.4))
	hm.set_surface_override_material(2, dark)
	hm.set_surface_override_material(3, visor_material())
	var chest := anchor_box("chest", "Spine2", Vector3(0.36, 0.2, 0.24) * hs)
	var cc := chest.get_center()
	var cr := Vector3(maxf(chest.size.x * 0.62, 0.25 * hs), 0.13 * hs, maxf(chest.size.z * 0.6, 0.15 * hs))
	var chest_at := cc + Vector3(0, 0.02 * hs, 0)
	attach("Spine2", _cloth_mesh(_sphere(), chest_at, Basis.from_scale(cr)), cloth, chest_at, Basis.from_scale(cr))
	var hips := anchor_box("hips", "Hips", Vector3(0.34, 0.2, 0.24) * hs)
	var hips_at := hips.get_center() + Vector3(0, -0.07 * hs, hips.size.z * 0.08)
	var hips_b := Basis.from_scale(Vector3(maxf(hips.size.x * 0.55, 0.2 * hs), 0.17 * hs, maxf(hips.size.z * 0.5, 0.14 * hs)))
	attach("Hips", _cloth_mesh(_sphere(), hips_at, hips_b), cloth, hips_at, hips_b)
	for side in ["Left", "Right"]:
		# Glove model: fingers along the hand, palm down in the T-pose, thumb forward. The
		# model is a right glove; the left one is mirrored.
		var hand := bone_pos(side + "Hand")
		var arm_dir := (hand - bone_pos(side + "ForeArm")).normalized()
		var lf := limb_frame(side + "ForeArm", side + "Hand")
		var gb := Basis(-lf.z, lf.y, lf.x) if side == "Right" else Basis(-lf.z, lf.y, -lf.x)
		_gloves.append(attach(side + "Hand", GLOVE_MESH, glove, hand + arm_dir * 0.01 * hs, gb * Basis.from_scale(Vector3.ONE * hs)))
	add_skates(c)
	_add_number(cc + Vector3(0, (-0.04 - number_drop(c)) * hs, -cr.z), NUMBER_HEIGHT * hs)
	_add_crest(cc + Vector3(0, -0.07 * hs, cr.z), CREST_WIDTH * hs)


## Fights: the stick and gloves come off (the fight drops copies on the ice).
func set_fight_mode(on: bool) -> void:
	shaft.visible = not on
	blade.visible = not on
	for g in _gloves:
		g.visible = not on
	rig.fist = 1.0 if on else 0.0
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
	var boot := MeshUtil.material(c.skates, 0.4)
	var steel := MeshUtil.material(Color(0.8, 0.82, 0.85), 0.25)
	var k: float = SKATE_LEN * hs / SKATE_MESH.get_aabb().size.z
	for side in ["Left", "Right"]:
		var foot := bone_pos(side + "Foot")
		var sk := attach(side + "Foot", SKATE_MESH, null, Vector3(foot.x, -SKATE_LIFT, foot.z + 0.07 * hs), Basis.from_scale(Vector3.ONE * k))
		sk.set_surface_override_material(0, boot)
		sk.set_surface_override_material(1, steel)


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
	var tex := number_texture(skater.number, c.number, c.number_outline)
	var h := height / DIGIT_FILL
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(h * tex.get_width() / float(tex.get_height()), 0.36 * hs, h)
	d.normal_fade = 0.72
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	# Projects along its -Y: here body +Z (into the back). Texture right = the
	# character's right (body -X), texture down = body down.
	var b := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
	attach_node("Spine2", d, Transform3D(b, at + Vector3(0, 0, 0.04 * hs)))


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
func _place_stick(top: Vector3, heel: Vector3, face: Vector3, out := Vector3.ZERO) -> void:
	var s := top - heel
	if out == Vector3.ZERO:
		out = Vector3(-s.x, 0.0, -s.z)
	if out.length() < 0.05:
		out = skater.right_dir() * skater.forehand_side()
	out = Vector3(out.x, 0.0, out.z).normalized()
	var f := Vector3.UP.cross(out).normalized()
	if f.dot(face) < 0.0:
		f = -f
	var db: Vector3 = shaft.mesh.get_meta("blade")
	var l0: float = shaft.mesh.get_meta("shaft")
	# The blade hooks toward -X in the model, so -X is the forehand face.
	var world := Basis(-f, s / l0, out * Vector3(db.x, 0.0, db.z).length())
	var local := Basis(Vector3.RIGHT, Vector3.UP, db)
	shaft.transform = Transform3D(world * local.inverse(), heel)


func _build_markers() -> void:
	ring = _add_mesh(self, _torus(0.5, 0.62), _unshaded(Color(1.0, 0.85, 0.15)), Vector3(0, 0.02, 0))
	marker = _add_mesh(self, _torus(0.42, 0.5), _unshaded(Color(1, 1, 1, 0.8)), Vector3(0, 0.02, 0))
	marker.visible = false

	charge_bar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.09)
	charge_bar.mesh = quad
	var bar_mat := _unshaded(Color(1.0, 0.45, 0.1))
	bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_mat.no_depth_test = true
	charge_bar.material_override = bar_mat
	charge_bar.position = Vector3(0, 2.3, 0)
	charge_bar.visible = false
	add_child(charge_bar)

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
	_stamina_back = _bar_sprite(Color(0.03, 0.03, 0.05, 0.92), 2)
	_stamina_fill = _bar_sprite(Color.GREEN, 3)
	for n in [shaft, blade, ring, marker, charge_bar, spray, _tag, _name_tag, _stamina_back, _stamina_fill]:
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
	if from > 0.0:
		anim.seek(from, false)


func stop_clip(fade := 0.3) -> void:
	_clip_left = 0.0
	_clip_fade = 1.0 / maxf(fade, 0.02)


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

## Jump straight to the skater's current pose (after a teleport).
func snap() -> void:
	if skater == null:
		return
	global_position = skater.global_position
	_yaw = _heading_yaw()
	_blade = skater.blade_rest() - skater.global_position
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
	global_position = skater.get_global_transform_interpolated().origin
	_state_clips()
	_tick_clip(delta)
	_pose(delta)
	_update_stick(delta)
	_update_human_tag()
	marker.visible = _marker_on
	var loading := skater.state == Skater.State.WINDUP and skater.windup_time > Skater.WRIST_WINDOW
	charge_bar.visible = loading
	if loading:
		charge_bar.scale = Vector3(maxf(0.05, skater.shot_charge), 1, 1)
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
	var crouch := 0.15 + fast * 0.12 + (0.04 if skater.turbo_active else 0.0) + (0.1 if skater.stopping else 0.0)
	var bend := 0.6 + fast * 0.3 + (0.1 if skater.turbo_active else 0.0)
	var twist := 0.0
	match skater.state:
		Skater.State.WINDUP:
			var c := skater.shot_charge if skater.windup_time > Skater.WRIST_WINDOW else 0.25
			twist = -side * (0.25 + 0.5 * c)
			crouch += 0.06 * c
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
	rig.lean = _bend
	rig.twist = _twist
	rig.stride_phase = _stride
	rig.stride_amt = _stride_amt * (0.6 if backward else 1.0)
	rig.stride_dir = -1.0 if backward else 1.0
	rig.sway = sin(_stride) * 0.07 * _stride_amt
	rig.hips_shift = Vector3(-sin(_stride) * 0.05 * _stride_amt, 0, 0)
	rig.stance = 0.2 if skater.stopping else 0.13
	rig.toe_out = 0.08
	rig.arm_mode = SkaterRig.Arms.STICK
	rig.stick_side = side
	# Skating hard without the puck, the bottom hand comes off the stick to drive.
	var free := skater.state == Skater.State.SKATE and not skater.has_puck() and not skater.intent.shoot_held 			and skater._shoot_buffer <= 0.0 and not skater.stopping and _stride_amt > 0.45
	_free_arm = lerpf(_free_arm, 1.0 if free else 0.0, _ease(5.0 if free else 9.0, delta))
	rig.free_arm = _free_arm

	var pitch := 0.0
	var roll := _lean + roll_offset
	if skater.state == Skater.State.STUMBLE:
		roll += sin(skater._state_time * 40.0) * 0.12
	model.rotation = Vector3(pitch, _yaw, roll)


## A flat bar for the stamina meter: fixed on-screen size, drawn over everything,
## left-anchored so the fill drains toward the left.
func _bar_sprite(color: Color, priority: int) -> Sprite3D:
	var img := Image.create(STAMINA_W + 8, STAMINA_H + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var sp := Sprite3D.new()
	sp.texture = ImageTexture.create_from_image(img)
	sp.centered = false
	sp.region_enabled = true
	sp.region_rect = Rect2(0, 0, img.get_width(), img.get_height())
	sp.offset = Vector2(-img.get_width() / 2.0, -95)
	sp.pixel_size = 0.00036
	sp.fixed_size = true
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.shaded = false
	sp.render_priority = priority
	sp.modulate = color
	sp.position = Vector3(0, 0.2, 0)
	sp.visible = false
	add_child(sp)
	return sp


## Colored ring + "P1".."P4" tag, number and name, and stamina bar for human-controlled skaters.
func _update_human_tag() -> void:
	ring.visible = skater.is_human
	var show_tag := skater.is_human and skater.human_index >= 0
	if _tag:
		_tag.visible = show_tag
	if _name_tag:
		_name_tag.visible = show_tag
		_stamina_back.visible = show_tag
		_stamina_fill.visible = show_tag
		if show_tag:
			# Drains from green through yellow to red.
			var st := clampf(skater.stamina, 0.0, 1.0)
			_stamina_fill.offset = Vector2(-STAMINA_W / 2.0, -91)
			_stamina_fill.region_rect = Rect2(0, 0, maxf(STAMINA_W * st, 0.01), STAMINA_H)
			_stamina_fill.modulate = Color.from_hsv(0.33 * st, 0.85, 0.95)
			_name_tag.text = ("#%d  %s" % [skater.number, skater.last_name.to_upper()]) if skater.last_name != "" else "#%d" % skater.number
	if show_tag:
		var c: Color = HumanBrain.PLAYER_COLORS[skater.human_index % 4]
		(ring.material_override as StandardMaterial3D).albedo_color = c
		if _tag:
			_tag.text = "P%d" % (skater.human_index + 1)
			_tag.modulate = c


func _update_stick(delta: float) -> void:
	var h := skater.heading
	var right := skater.right_dir()
	var side := skater.forehand_side()
	var target: Vector3
	var follow := _ease(25.0, delta)

	match skater.state:
		Skater.State.WINDUP when skater.windup_time > Skater.WRIST_WINDOW:
			var c := skater.shot_charge
			target = right * side * (0.6 + 0.2 * c) - h * (0.2 + 0.6 * c) + Vector3.UP * (0.3 + 1.1 * c)
			follow = _ease(12.0, delta)
		Skater.State.POKE:
			target = h * 1.7 + right * side * 0.1 + Vector3.UP * 0.03
			follow = _ease(40.0, delta)
		Skater.State.DOWN:
			target = h * 0.2 + right * skater.fall_side * 0.9 + Vector3.UP * 0.05
			follow = _ease(10.0, delta)
		Skater.State.FOLLOW_THROUGH:
			var t := clampf(skater._state_time / Skater.FOLLOW_TIME, 0.0, 1.0)
			target = h * 1.2 - right * side * 0.25 * t + Vector3.UP * (0.25 + 0.8 * t)
			follow = _ease(30.0, delta)
		_:
			if skater.has_puck():
				var p := skater.puck.get_global_transform_interpolated().origin
				target = p - global_position
				target += (target * Vector3(1, 0, 1)).normalized() * 0.05
				target.y = 0.03
				follow = 1.0
			elif skater.intent.shoot_held or skater._shoot_buffer > 0.0:
				target = right * side * 0.6 - h * 0.1 + Vector3.UP * 0.8 # loaded for a one-timer
			else:
				target = skater.blade_rest() - skater.global_position
				target.y = 0.03
	# While a clip owns the arms (celebrating), the stick hangs from the top hand.
	if _clip_w.z > 0.5 and not skater.is_down():
		target = (rig.top_hand_world - global_position) + h * 0.5 + Vector3.DOWN * 1.1
		follow = _ease(10.0, delta)
	_blade = _blade.lerp(target, follow) if delta > 0.0 else target
	rig.blade_world = global_position + _blade


## Called once the skeleton (with the rig) is posed: the stick runs from the top hand
## to the blade.
func _after_rig() -> void:
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
