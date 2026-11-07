class_name SkaterRig
extends SkeletonModifier3D
## Procedural hockey body on the shared Mixamo skeleton (prefix-free bone names).
##
## Runs after the AnimationPlayer every frame. Three regions — legs (hips + legs),
## spine (spine, neck, head) and arms — each blend between whatever the clip posed
## (weight 0) and the procedural pose (weight 1):
##   * legs: skating stride from `stride_phase` / `stride_amt`, two-bone IK to the ice
##   * spine: forward lean, twist and sway, head kept level
##   * arms: two-bone IK. ARMS_STICK grips a stick whose blade is at `blade_world`;
##     ARMS_FREE sends each hand to `hand_world[0/1]` (goalie glove / blocker)
##
## Skeleton space is the Mixamo frame: +Z forward, +X = the character's LEFT, feet at y=0.

enum Arms { STICK, FREE }

# --- Inputs (set by the visual each frame) ---
var w_legs := 1.0
var w_spine := 1.0
var w_arms := 1.0
var hips_drop := 0.0            ## m the pelvis sinks (knees bend to match)
var hips_shift := Vector3.ZERO  ## extra pelvis offset, skeleton space
var hips_yaw := 0.0
var lean := 0.0                 ## rad forward bend of the spine (+ = chest forward)
var twist := 0.0                ## rad torso yaw (+ = turn to the left)
var sway := 0.0                 ## rad side bend (+ = toward the character's left)
var head_level := 0.85          ## how much the head counters the spine lean
var stride_phase := 0.0
var stride_amt := 0.0           ## 0 glide .. 1 full sprint stride
var stride_dir := 1.0           ## +1 forward skating, -1 backward (C-cuts)
var stance := 0.14              ## half distance between the feet
var toe_out := 0.0              ## rad each foot turns outward
var foot_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   ## [left, right] extra foot target offset
var knee_pole: Array[Vector3] = [Vector3(0.15, 0, 1), Vector3(-0.15, 0, 1)]
var arm_mode := Arms.STICK
var stick_side := 1.0           ## +1 blade on the character's right (right-handed shot)
var blade_world := Vector3.ZERO
var hand_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   ## [left, right] for ARMS_FREE
## Elbow directions (skeleton space). The default flares the elbows out to the sides
## for an open stance; goalies set their own.
var elbow_pole: Array[Vector3] = [Vector3(1.0, -0.45, -0.3), Vector3(-1.0, -0.45, -0.3)]
var grip_spread := 0.46         ## distance between the hands on the stick
var free_arm := 0.0             ## 0..1: the bottom hand lets go of the stick and swings with the stride
var _top_lift := 0.0

# --- Outputs (valid after `modification_processed`) ---
var stick_top_world := Vector3.ZERO     ## butt end of the stick
var top_hand_world := Vector3.ZERO
var left_hand_world := Vector3.ZERO
var right_hand_world := Vector3.ZERO

var ankle_height := 0.105         ## from the body's rest pose

var _ok := false
var _b := {}            ## bone name -> index
var _rest_g := {}       ## index -> rest global Transform3D
var _rest_l := {}       ## index -> rest local Transform3D
var _len := {}          ## "leg_l1" etc.


func _cache(sk: Skeleton3D) -> void:
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
			"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
			"RightShoulder", "RightArm", "RightForeArm", "RightHand",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		var i := sk.find_bone(n)
		if i < 0:
			push_error("SkaterRig: missing bone " + n)
			return
		_b[n] = i
		_rest_g[i] = sk.get_bone_global_rest(i)
		_rest_l[i] = sk.get_bone_rest(i)
	for side in ["Left", "Right"]:
		_len[side + "Thigh"] = _gpos(side + "UpLeg").distance_to(_gpos(side + "Leg"))
		_len[side + "Shin"] = _gpos(side + "Leg").distance_to(_gpos(side + "Foot"))
		_len[side + "Upper"] = _gpos(side + "Arm").distance_to(_gpos(side + "ForeArm"))
		_len[side + "Fore"] = _gpos(side + "ForeArm").distance_to(_gpos(side + "Hand"))
	ankle_height = maxf(_gpos("LeftFoot").y, 0.04)
	_ok = true


func _gpos(n: String) -> Vector3:
	return (_rest_g[_b[n]] as Transform3D).origin


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_ok = false


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ok:
		_cache(sk)
		if not _ok:
			return
	var to_skel := sk.global_transform.affine_inverse()

	# --- Pelvis -------------------------------------------------------------------
	var hi: int = _b["Hips"]
	var hips_rest: Transform3D = _rest_l[hi]
	var hips_proc := Transform3D(
			Basis(Vector3.UP, hips_yaw) * Basis(Vector3.RIGHT, lean * 0.3) * hips_rest.basis,
			hips_rest.origin + Vector3(0, -hips_drop, 0) + hips_shift)
	var hips := _blend_local(sk, hi, hips_proc, w_legs, true)
	var gl := {hi: hips}   # bone -> final global this frame

	# --- Spine ---------------------------------------------------------------------
	var spine_parts := 0.7 / 3.0
	for n in ["Spine", "Spine1", "Spine2"]:
		var i: int = _b[n]
		var r: Transform3D = _rest_l[i]
		var extra := Basis(Vector3.UP, twist / 3.0) * Basis(Vector3.RIGHT, lean * spine_parts) * Basis(Vector3.BACK, -sway / 3.0)
		var proc := Transform3D(r.basis * extra, r.origin)
		var pg := _gpose(sk, sk.get_bone_parent(i), gl)
		gl[i] = pg * _blend_local(sk, i, proc, w_spine, false)
	var g_chest: Transform3D = gl[_b["Spine2"]]
	for n in ["Neck", "Head"]:
		var i: int = _b[n]
		var r: Transform3D = _rest_l[i]
		var proc := Transform3D(r.basis * Basis(Vector3.RIGHT, -lean * head_level * 0.5) * Basis(Vector3.UP, -twist * 0.35), r.origin)
		var pg := _gpose(sk, sk.get_bone_parent(i), gl)
		gl[i] = pg * _blend_local(sk, i, proc, w_spine, false)

	# --- Legs ----------------------------------------------------------------------
	for s in 2:
		var side := "Left" if s == 0 else "Right"
		var sx := 1.0 if s == 0 else -1.0
		var up_i: int = _b[side + "UpLeg"]
		var leg_i: int = _b[side + "Leg"]
		var foot_i: int = _b[side + "Foot"]
		var g_up_parent := _gpose(sk, sk.get_bone_parent(up_i), gl)
		var hip_pos := (g_up_parent * _pose_local(sk, up_i)).origin
		var ph := stride_phase + (0.0 if s == 0 else PI)
		var push := maxf(0.0, sin(ph))
		var lift := maxf(0.0, -sin(ph))
		var amt := stride_amt
		var foot := Vector3(
				sx * (stance + amt * 0.3 * push),
				ankle_height + amt * 0.09 * lift,
				stride_dir * amt * 0.32 * cos(ph) - amt * 0.08)
		foot += foot_offset[s]
		foot.x += hips_shift.x * 0.4
		foot.z += hips_shift.z * 0.6
		var pole: Vector3 = knee_pole[s]
		var knee := _two_bone(hip_pos, foot, pole, _len[side + "Thigh"], _len[side + "Shin"])
		var end: Vector3 = knee[1]
		var knee_p: Vector3 = knee[0]
		var g_up := _aim(up_i, _gpos(side + "Leg") - _gpos(side + "UpLeg"), Vector3.BACK, knee_p - hip_pos, pole, hip_pos)
		var l_up := g_up_parent.affine_inverse() * g_up
		var up_final := _blend_local(sk, up_i, l_up, w_legs, false)
		var g_up_f := g_up_parent * up_final
		var g_leg := _aim(leg_i, _gpos(side + "Foot") - _gpos(side + "Leg"), Vector3.BACK, end - knee_p, pole, g_up_f * _pose_local(sk, leg_i).origin)
		var leg_final := _blend_local(sk, leg_i, g_up_f.affine_inverse() * g_leg, w_legs, false)
		var g_leg_f := g_up_f * leg_final
		# Foot flat on the ice, toes turned out (more while pushing).
		var yaw := sx * (toe_out + amt * 0.45 * push) + hips_yaw * 0.5
		var foot_rest: Transform3D = _rest_g[foot_i]
		var g_foot := Transform3D(Basis(Vector3.UP, yaw) * foot_rest.basis, g_leg_f * _pose_local(sk, foot_i).origin)
		_blend_local(sk, foot_i, g_leg_f.affine_inverse() * g_foot, w_legs, false)

	# --- Arms ----------------------------------------------------------------------
	var targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var first := 0
	var blade := to_skel * blade_world
	if arm_mode == Arms.STICK:
		# Top hand in front of the belly on the side away from the blade, low;
		# rises with the blade for windups.
		var top := 0 if stick_side > 0.0 else 1     # right-handed shot: left hand on top
		first = top
		var lift := clampf((blade.y - 0.2) / 1.6, 0.0, 1.0)
		# Set from the top hand's own shoulder (below): forward of the body at belt
		# height, within easy reach so the elbow stays bent, rocking with the stride.
		_top_lift = lift
	else:
		targets[0] = to_skel * hand_world[0]
		targets[1] = to_skel * hand_world[1]
	var hand_out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for k in 2:
		var s := first if k == 0 else 1 - first
		var side := "Left" if s == 0 else "Right"
		var sh_i: int = _b[side + "Shoulder"]
		var arm_i: int = _b[side + "Arm"]
		var fore_i: int = _b[side + "ForeArm"]
		var hand_i: int = _b[side + "Hand"]
		var g_sh := _gpose(sk, sk.get_bone_parent(sh_i), gl) * _blend_local(sk, sh_i, _rest_l[sh_i], w_arms, false)
		var shoulder := (g_sh * _pose_local(sk, arm_i)).origin
		var target := targets[s]
		var pole: Vector3 = elbow_pole[s]
		if arm_mode == Arms.STICK and k == 0:
			var reach: float = (_len[side + "Upper"] + _len[side + "Fore"]) * 0.78
			var rock := Vector3(sin(stride_phase) * 0.05, 0.0, cos(stride_phase) * 0.05) * stride_amt
			var dir := Vector3(-stick_side * 0.12, -0.75 + _top_lift * 0.9, 0.65 - _top_lift * 0.3).normalized()
			target = shoulder + dir * reach + rock
		if arm_mode == Arms.STICK and k == 1:
			# Bottom hand slides down the shaft from wherever the top hand ended up...
			var top_hand := hand_out[first]
			target = top_hand + (blade - top_hand).normalized() * grip_spread
			if free_arm > 0.0:
				# ...or swings free: forward (and across) as the same-side leg drives back.
				var sx := 1.0 if s == 0 else -1.0
				var fz := -cos(stride_phase + (0.0 if s == 0 else PI))
				var a := clampf(stride_amt, 0.4, 1.0)
				var swing := shoulder + Vector3(sx * (0.14 - 0.16 * maxf(fz, 0.0) * a), -0.5 + 0.14 * maxf(fz, 0.0) * a, 0.1 + 0.36 * fz * a)
				target = target.lerp(swing, free_arm)
				pole = pole.lerp(Vector3(sx * 0.4, -0.2, -1.0), free_arm)
		var r := _two_bone(shoulder, target, pole, _len[side + "Upper"], _len[side + "Fore"])
		var elbow: Vector3 = r[0]
		var hand: Vector3 = r[1]
		var rest_pole := Vector3.BACK * -1.0   # elbows point backward in the T-pose
		var g_arm := _aim(arm_i, _gpos(side + "ForeArm") - _gpos(side + "Arm"), rest_pole, elbow - shoulder, pole, shoulder)
		var arm_final := _blend_local(sk, arm_i, g_sh.affine_inverse() * g_arm, w_arms, false)
		var g_arm_f := g_sh * arm_final
		var g_fore := _aim(fore_i, _gpos(side + "Hand") - _gpos(side + "ForeArm"), rest_pole, hand - elbow, pole, g_arm_f * _pose_local(sk, fore_i).origin)
		var fore_final := _blend_local(sk, fore_i, g_arm_f.affine_inverse() * g_fore, w_arms, false)
		var g_fore_f := g_arm_f * fore_final
		var g_hand := g_fore_f * _pose_local(sk, hand_i)
		hand_out[s] = g_hand.origin

	var to_world := sk.global_transform
	left_hand_world = to_world * hand_out[0]
	right_hand_world = to_world * hand_out[1]
	top_hand_world = to_world * hand_out[first]
	var dir := (blade - hand_out[first]).normalized()
	stick_top_world = to_world * (hand_out[first] - dir * 0.1)


## Global pose of bone i this frame: final if the rig already set it, otherwise built
## from its parent chain (covers extra bones like the CMU rig's hip joints and Neck1).
func _gpose(sk: Skeleton3D, i: int, gl: Dictionary) -> Transform3D:
	if i < 0:
		return Transform3D.IDENTITY
	if gl.has(i):
		return gl[i]
	var g := _gpose(sk, sk.get_bone_parent(i), gl) * _pose_local(sk, i)
	gl[i] = g
	return g


## Local pose (position + rotation) the skeleton currently holds for bone i.
func _pose_local(sk: Skeleton3D, i: int) -> Transform3D:
	return Transform3D(Basis(sk.get_bone_pose_rotation(i)), sk.get_bone_pose_position(i))


## Blends bone i from its current (animated) local pose toward `proc` by w, writes it,
## and returns the final local transform.
func _blend_local(sk: Skeleton3D, i: int, proc: Transform3D, w: float, with_position: bool) -> Transform3D:
	var cur_q := sk.get_bone_pose_rotation(i)
	var cur_p := sk.get_bone_pose_position(i)
	var q := cur_q
	var p := cur_p
	if w > 0.0:
		var pq := proc.basis.orthonormalized().get_rotation_quaternion()
		q = cur_q.slerp(pq, clampf(w, 0.0, 1.0)) if w < 1.0 else pq
		if with_position:
			p = cur_p.lerp(proc.origin, clampf(w, 0.0, 1.0))
		sk.set_bone_pose_rotation(i, q)
		if with_position:
			sk.set_bone_pose_position(i, p)
	return Transform3D(Basis(q), p)


## Global transform for bone i that rotates its rest frame so the rest bone axis `a0`
## (with reference `r0`) lines up with `a1` (reference `r1`), placed at `origin`.
func _aim(i: int, a0: Vector3, r0: Vector3, a1: Vector3, r1: Vector3, origin: Vector3) -> Transform3D:
	var rot := _frame(a1, r1) * _frame(a0, r0).transposed()
	return Transform3D(rot * (_rest_g[i] as Transform3D).basis, origin)


static func _frame(a: Vector3, r: Vector3) -> Basis:
	var x := a.normalized()
	var y := r - x * x.dot(r)
	if y.length_squared() < 1e-6:
		y = Vector3.UP if absf(x.y) < 0.9 else Vector3.FORWARD
		y = y - x * x.dot(y)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


## Two-bone IK: returns [middle joint, end] for a chain rooted at `a` reaching for `target`,
## bending toward `pole` (a direction).
static func _two_bone(a: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float) -> Array:
	var d := target - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := d.normalized() if d.length() > 1e-5 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var ang := acos(cos_a)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = Vector3.FORWARD - dir * dir.z
	bend = bend.normalized()
	var mid := a + (dir * cos(ang) + bend * sin(ang)) * l1
	return [mid, a + dir * dist]
