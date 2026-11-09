class_name ReplayTap
extends SkeletonModifier3D
## The last modifier on every player's skeleton (after SkaterRig): records the finished
## pose for replays, and during a replay writes a recorded pose back.
##
## Recording (about REC_HZ times a second of game time, while Replay.recording): one
## PackedFloat32Array per sample:
##   [0]       game time (Replay.now)
##   [1..12]   the skeleton's world transform (basis columns, origin)
##   [13..24]  the stick's world transform (zeros: no stick)
##   [25]      1 if the player is visible
##   [26..]    each bone: local position (3) and rotation (quaternion, 4)
## Samples older than KEEP seconds are dropped.

const REC_HZ := 30.0
const KEEP := 14.0
const HEAD := 26
const PER_BONE := 7

var visual: SkaterVisual
var frames: Array[PackedFloat32Array] = []
## Replay: the bone part of a sample to apply (empty = leave the pose alone).
var override := PackedFloat32Array()
var _last := -1.0


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not override.is_empty():
		_apply(sk)
		return
	if not Replay.recording or visual == null:
		return
	var now := Replay.now
	if now - _last < 1.0 / REC_HZ and now >= _last:
		return
	_last = now
	var n := sk.get_bone_count()
	var f := PackedFloat32Array()
	f.resize(HEAD + n * PER_BONE)
	f[0] = now
	_put_xform(f, 1, sk.global_transform)
	if visual.shaft != null and visual.shaft.visible:
		_put_xform(f, 13, visual.shaft.global_transform)
	f[25] = 1.0 if visual.is_visible_in_tree() else 0.0
	var k := HEAD
	for b in n:
		var p := sk.get_bone_pose_position(b)
		var q := sk.get_bone_pose_rotation(b)
		f[k] = p.x
		f[k + 1] = p.y
		f[k + 2] = p.z
		f[k + 3] = q.x
		f[k + 4] = q.y
		f[k + 5] = q.z
		f[k + 6] = q.w
		k += PER_BONE
	frames.append(f)
	while not frames.is_empty() and frames[0][0] < now - KEEP:
		frames.pop_front()


func _apply(sk: Skeleton3D) -> void:
	var n := mini(sk.get_bone_count(), (override.size() - HEAD) / PER_BONE)
	var k := HEAD
	for b in n:
		sk.set_bone_pose_position(b, Vector3(override[k], override[k + 1], override[k + 2]))
		sk.set_bone_pose_rotation(b, Quaternion(override[k + 3], override[k + 4], override[k + 5], override[k + 6]))
		k += PER_BONE


static func _put_xform(f: PackedFloat32Array, at: int, x: Transform3D) -> void:
	f[at] = x.basis.x.x
	f[at + 1] = x.basis.x.y
	f[at + 2] = x.basis.x.z
	f[at + 3] = x.basis.y.x
	f[at + 4] = x.basis.y.y
	f[at + 5] = x.basis.y.z
	f[at + 6] = x.basis.z.x
	f[at + 7] = x.basis.z.y
	f[at + 8] = x.basis.z.z
	f[at + 9] = x.origin.x
	f[at + 10] = x.origin.y
	f[at + 11] = x.origin.z


static func get_xform(f: PackedFloat32Array, at: int) -> Transform3D:
	return Transform3D(Basis(Vector3(f[at], f[at + 1], f[at + 2]), Vector3(f[at + 3], f[at + 4], f[at + 5]),
			Vector3(f[at + 6], f[at + 7], f[at + 8])), Vector3(f[at + 9], f[at + 10], f[at + 11]))


## The samples between game times t0 and t1 (with one either side, for blending).
func slice(t0: float, t1: float) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for i in frames.size():
		var t := frames[i][0]
		var next_t := frames[i + 1][0] if i + 1 < frames.size() else INF
		var prev_t := frames[i - 1][0] if i > 0 else -INF
		if (t >= t0 and t <= t1) or (next_t >= t0 and t < t0) or (prev_t <= t1 and t > t1):
			out.append(frames[i])
	return out


## A sample blended between the two around game time `t` in `track` (sorted by time).
static func sample(track: Array[PackedFloat32Array], t: float) -> PackedFloat32Array:
	if track.is_empty():
		return PackedFloat32Array()
	if t <= track[0][0]:
		return track[0]
	if t >= track[-1][0]:
		return track[-1]
	var lo := 0
	var hi := track.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if track[mid][0] <= t:
			lo = mid
		else:
			hi = mid
	var a := track[lo]
	var b := track[hi]
	var u := (t - a[0]) / maxf(b[0] - a[0], 0.0001)
	var out := a.duplicate()
	out[0] = t
	# Transforms and positions: blend; rotations: slerp. Skeleton / stick bases are
	# re-orthonormalized when read (get_xform + orthonormalized at the use).
	for i in range(1, HEAD):
		out[i] = lerpf(a[i], b[i], u)
	out[25] = a[25] if u < 0.5 else b[25]
	var k := HEAD
	while k + PER_BONE <= out.size():
		out[k] = lerpf(a[k], b[k], u)
		out[k + 1] = lerpf(a[k + 1], b[k + 1], u)
		out[k + 2] = lerpf(a[k + 2], b[k + 2], u)
		var q := Quaternion(a[k + 3], a[k + 4], a[k + 5], a[k + 6]).slerp(Quaternion(b[k + 3], b[k + 4], b[k + 5], b[k + 6]), u)
		out[k + 3] = q.x
		out[k + 4] = q.y
		out[k + 5] = q.z
		out[k + 6] = q.w
		k += PER_BONE
	return out
