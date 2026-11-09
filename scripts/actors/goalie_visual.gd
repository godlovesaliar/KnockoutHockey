class_name GoalieVisual
extends SkaterVisual
## Goalie body: the shared skeleton with pads, glove, blocker, chest protector and mask.
## Wide crouched stance, butterfly drop on low shots, glove / blocker reach on saves,
## stick paddle flat on the ice in front of the pads.

## Mask models (tools/build_gear.gd), picked by Skater.gear_style. Fitted to the face:
## eye = where the eyes sit in the mask model's coordinates, crown = from there up to the
## top of the head (model units), both measured on the male body where the masks were
## tuned. Bodies without eyes fall back to the head box: fit = mask height / head height,
## raise = above the head's center in head heights, fwd = ahead of it in head depths.
const MASKS := [
	{"mesh": preload("res://assets/characters/goalie_mask.res"), "eye": Vector3(0, 0.0115, 0.085), "crown": 0.168,
		"fit": 1.3, "raise": 0.06, "fwd": 0.06},
	{"mesh": preload("res://assets/characters/goalie_mask_b.res"), "eye": Vector3(0, 0.0023, 0.0646), "crown": 0.114,
		"fit": 1.3, "raise": 0.08, "fwd": 0.03},
]

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

var goalie: Goalie
var _drop := 0.0


func build(sk: Skater) -> void:
	goalie = sk as Goalie
	super.build(sk)


func _build_gear() -> void:
	var c := team_colors()
	var head := anchor_box("head", "Head", Vector3(0.2, 0.25, 0.22) * hs)
	# Goalie mask model (tools/build_gear.gd): covers the whole head, cage in front.
	var mspec: Dictionary = MASKS[skater.gear_style % MASKS.size()]
	var mmesh: Mesh = mspec.mesh
	var fit: float = head.size.y * mspec.fit / mmesh.get_aabb().size.y
	var at := head.get_center() + Vector3(0, head.size.y * mspec.raise, head.size.z * mspec.fwd)
	var eyes := skel.get_node_or_null("Eyes") as MeshInstance3D
	if eyes != null:
		# Eye opening on the eyes, sized by eyes-to-crown: the head box alone put the mask
		# too high and too small on the female body.
		var e := eyes.mesh.get_aabb().get_center()
		fit = (head.end.y - e.y) / float(mspec.crown)
		at = Vector3(head.get_center().x, e.y, e.z) - (mspec.eye as Vector3) * fit
	var mm := attach("Head", mmesh, null, at, Basis.from_scale(Vector3.ONE * fit))
	mm.material_override = null
	mm.name = "Helmet"   # as the skater's helmet: tools and views find the head gear by name
	var shell := MeshUtil.material(c.jersey.lerp(Color.WHITE, 0.15), 0.35)
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cage := MeshUtil.material(Color(0.12, 0.12, 0.13), 0.3)
	cage.cull_mode = BaseMaterial3D.CULL_DISABLED
	mm.set_surface_override_material(0, shell)
	mm.set_surface_override_material(1, cage)
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
	var body := MeshUtil.material(Color(0.07, 0.07, 0.08), 0.45)
	var grip := MeshUtil.material(Color(0.02, 0.02, 0.02), 0.8)
	var tape := MeshUtil.material(Color(0.93, 0.93, 0.9), 0.6)
	for m in [body, grip, tape]:
		(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft = _add_mesh(self, GOALIE_STICK_MESH, null, Vector3.ZERO)
	shaft.set_surface_override_material(0, body)
	shaft.set_surface_override_material(1, grip)
	shaft.set_surface_override_material(2, tape)
	blade = shaft


## Goalies don't fall or stumble from hits; their poses come from the rig.
func _state_clips() -> void:
	pass


func _pose(delta: float) -> void:
	var k := _ease(14.0, delta)
	_yaw = lerp_angle(_yaw, _heading_yaw(), k)
	var low_save := goalie.save_anim > 0.0 and goalie.save_point.y < 0.5
	var want_drop := 1.0 if (goalie.butterfly or low_save) else 0.0
	_drop = lerpf(_drop, want_drop, _ease(18.0, delta))
	var spd := goalie.flat_speed()

	_stride += delta * (5.0 + spd * 2.0)
	_stride_amt = lerpf(_stride_amt, clampf(spd / 3.0, 0.0, 1.0) * 0.35 * (1.0 - _drop), _ease(6.0, delta))
	rig.hips_drop = 0.24 + 0.36 * _drop
	rig.lean = 0.42 - 0.1 * _drop
	rig.twist = 0.0
	rig.sway = 0.0
	rig.stride_phase = _stride
	rig.stride_amt = _stride_amt
	rig.stride_dir = 1.0
	rig.stance = 0.27
	rig.toe_out = 0.25
	rig.hips_shift = Vector3(0, 0, -0.05 - 0.08 * _drop)
	# Butterfly: knees pinch together in front, feet flare out behind.
	rig.foot_offset[0] = Vector3(0.24, 0.0, -0.3) * _drop
	rig.foot_offset[1] = Vector3(-0.24, 0.0, -0.3) * _drop
	rig.knee_pole[0] = Vector3(0.25 - 0.55 * _drop, -0.6 * _drop, 1.0)
	rig.knee_pole[1] = Vector3(-0.25 + 0.55 * _drop, -0.6 * _drop, 1.0)

	# Glove / blocker: ready position, reaching toward the last save.
	rig.arm_mode = SkaterRig.Arms.FREE
	var a := goalie.save_anim
	var reach := Vector3.ZERO
	if a > 0.0 and goalie.save_point.y >= 0.5:
		# save_point.x is in the net frame (+x = goalie's left); in model space left is -x.
		reach = Vector3(-goalie.save_point.x * 0.8, goalie.save_point.y - 0.95, -0.15) * a
	var glove_reach := reach if goalie.save_point.x > 0.0 else Vector3.ZERO
	var blocker_reach := reach if goalie.save_point.x <= 0.0 else Vector3.ZERO
	var y_drop := -0.3 * _drop
	var glove_p := Vector3(-0.42, 1.0 + y_drop, -0.42) + glove_reach
	var blocker_p := Vector3(0.36, 0.78 + y_drop, -0.4) + blocker_reach
	var mt := model.global_transform
	rig.hand_world[0] = mt * glove_p
	rig.hand_world[1] = mt * blocker_p
	rig.elbow_pole[0] = Vector3(0.7, -0.6, -0.4)
	rig.elbow_pole[1] = Vector3(-0.7, -0.7, -0.3)
	model.rotation = Vector3(0.0, _yaw, 0.0)


func _update_stick(delta: float) -> void:
	# Paddle flat on the ice in front of the pads, a little toward the blocker side.
	var target := model.global_transform * Vector3(0.08, 0.0, -0.62 - 0.1 * _drop) - global_position
	target.y = 0.05
	_blade = _blade.lerp(target, _ease(30.0, delta)) if delta > 0.0 else target
	rig.blade_world = global_position + _blade


func _after_rig() -> void:
	# Blade across the crease toward the glove side, centered on the paddle point; the
	# shaft runs up through the blocker hand and on past it at the model's length.
	var across := model.global_basis * Vector3.LEFT
	var blade_len := Vector3(GOALIE_STICK_MESH.get_meta("blade")).length()
	var heel := _blade - Vector3(across.x, 0.0, across.z).normalized() * blade_len * 0.5
	var hand := to_local(rig.right_hand_world)
	var l0: float = GOALIE_STICK_MESH.get_meta("shaft") * hs
	var top := heel + (hand - heel).normalized() * maxf(l0, heel.distance_to(hand) + 0.1)
	_place_stick(top, heel, goalie.heading, across)
