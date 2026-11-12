class_name BodyBuild
## A player's size from their height and weight (DESIGN §8.5 "Body size").
##
## Height scales the whole body evenly (so nobody looks stretched): the roster's average
## height for the body type renders at the model's own size. Weight sets the build: how
## much heavier or lighter than their height suggests (weight / height, against the
## average) widens or slims the body through a "build" blend shape on the skin, jersey and
## pants, after taking out the few percent the height scale already widened them.
##
## The blend shape moves each vertex straight out from the bone it rides on (from the
## bone's axis, a share per bone: most at the belly and hips, some on the upper arms and
## thighs, none on the head, hands and feet). Every layer moves by the same rule, so the
## jersey stays over the skin. At 1.0 the trunk is twice as wide; players use about ±0.15.

## Roster averages (skaters and goalies), per body type: [height m, weight kg].
const AVERAGE := {"male": [1.873, 92.9], "female": [1.724, 71.6]}
## How far out each bone's flesh moves at build 1.0 (share of its distance from the bone).
const GIRTH := {
	"Hips": 0.9, "Spine": 1.0, "Spine1": 1.0, "Spine2": 0.8, "Neck": 0.45,
	"LeftShoulder": 0.55, "RightShoulder": 0.55, "LeftArm": 0.6, "RightArm": 0.6,
	"LeftForeArm": 0.3, "RightForeArm": 0.3, "LeftUpLeg": 0.7, "RightUpLeg": 0.7,
	"LeftLeg": 0.25, "RightLeg": 0.25,
}
## The bone each one's axis runs to (the rest go to their first child).
const AXIS_TO := {
	"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "RightShoulder": "RightArm", "LeftArm": "LeftForeArm", "RightArm": "RightForeArm",
	"LeftForeArm": "LeftHand", "RightForeArm": "RightHand", "LeftUpLeg": "LeftLeg", "RightUpLeg": "RightLeg",
	"LeftLeg": "LeftFoot", "RightLeg": "RightFoot",
}
const SHAPE := "build"

static var _built := {}   ## source mesh instance id -> the mesh with the build shape


## [height scale, build] for a player of `height_m` and `weight_kg` (0 = average).
static func size_for(body_type: String, height_m: float, weight_kg: float) -> Vector2:
	if not AVERAGE.has(body_type):
		return Vector2(1.0, 0.0)
	var avg: Array = AVERAGE[body_type]
	var h := height_m if height_m > 0.5 else float(avg[0])
	var w := weight_kg if weight_kg > 20.0 else float(avg[1])
	var scale := h / float(avg[0])
	# Cross-section area goes with weight / height, so width with its square root; the
	# even height scale already covers `scale` of it.
	var width := sqrt((w / h) / (float(avg[1]) / float(avg[0])))
	# Past these the pants pads show through a slimmed jersey, or the body balloons (the
	# creator reaches them; the rosters stay within about ±0.15).
	return Vector2(scale, clampf(width / scale - 1.0, -0.2, 0.35))


## Per vertex of `arrays` (a skinned surface in rest skeleton space): the offset at build
## 1.0. `skin` maps the surface's bone indices to the skeleton's (null: the same).
static func offsets(arrays: Array, sk: Skeleton3D, skin: Skin) -> PackedVector3Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or weights == null or verts.is_empty():
		return out
	var per: int = (bones as PackedInt32Array).size() / verts.size()
	# Per bind index: [axis start, axis end, girth] (girth 0 = this bone doesn't fill out).
	var axes := {}
	var count := skin.get_bind_count() if skin else sk.get_bone_count()
	for bi in count:
		var bone := bi
		if skin:
			bone = skin.get_bind_bone(bi)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(bi))
		if bone < 0:
			continue
		var nm := _plain(sk.get_bone_name(bone))
		if not GIRTH.has(nm):
			continue
		var to := -1
		for c in sk.get_bone_children(bone):
			if _plain(sk.get_bone_name(c)) == AXIS_TO.get(nm, ""):
				to = c
		if to < 0:
			continue
		axes[bi] = [sk.get_bone_global_rest(bone).origin, sk.get_bone_global_rest(to).origin, float(GIRTH[nm])]
	for i in verts.size():
		var p := verts[i]
		var off := Vector3.ZERO
		for k in per:
			var w: float = weights[i * per + k]
			if w <= 0.0:
				continue
			var ax = axes.get(bones[i * per + k])
			if ax == null:
				continue
			var a: Vector3 = ax[0]
			var ab: Vector3 = (ax[1] as Vector3) - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			off += (p - (a + ab * t)) * float(ax[2]) * w
		out[i] = off
	return out


## `mesh` with a "build" blend shape added (after any it has), made once per mesh.
static func with_build(mesh: Mesh, sk: Skeleton3D, skin: Skin) -> Mesh:
	var src := mesh as ArrayMesh
	if src == null or src.get_surface_count() == 0:
		return mesh
	if _built.has(src.get_instance_id()):
		return _built[src.get_instance_id()]
	var out := ArrayMesh.new()
	var names: Array[StringName] = []
	for b in src.get_blend_shape_count():
		names.append(src.get_blend_shape_name(b))
		out.add_blend_shape(names[b])
	out.add_blend_shape(SHAPE)
	out.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var shapes := src.surface_get_blend_shape_arrays(s)
		shapes.append(shape_arrays(arr, offsets(arr, sk, skin)))
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, shapes, {}, keep_flags(src.surface_get_format(s)))
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	_built[src.get_instance_id()] = out
	return out


## Blend shape arrays (offsets, as this Godot wants them) moving the vertices by `off`.
static func shape_arrays(arr: Array, off: PackedVector3Array) -> Array:
	var bs := []
	bs.resize(Mesh.ARRAY_MAX)
	bs[Mesh.ARRAY_VERTEX] = off
	var zn := PackedVector3Array()
	zn.resize(off.size())
	bs[Mesh.ARRAY_NORMAL] = zn
	if arr[Mesh.ARRAY_TANGENT] != null:
		var zt := PackedFloat32Array()
		zt.resize((arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size())
		bs[Mesh.ARRAY_TANGENT] = zt
	return bs


## Sets the build on every mesh under `root` that has the shape.
static func apply(root: Node, build: float) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var i := mi.find_blend_shape_by_name(SHAPE)
		if i >= 0:
			mi.set_blend_shape_value(i, build)


## A point on the body at rest (skeleton space) where the build moves it, by the same rule
## as the mesh, for things fitted to the body (pads, the crest and number).
static func point(sk: Skeleton3D, bone: String, p: Vector3, build: float) -> Vector3:
	var b := sk.find_bone(bone)
	if b < 0 or not GIRTH.has(bone):
		return p
	var to := sk.find_bone(AXIS_TO[bone])
	var a := sk.get_bone_global_rest(b).origin
	var ab := sk.get_bone_global_rest(to).origin - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p + (p - (a + ab * t)) * float(GIRTH[bone]) * build


## The format flags add_surface_from_arrays needs back (custom channel formats, 8 bone
## weights); the rest come from the arrays themselves.
static func keep_flags(fmt: int) -> int:
	var keep := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for k in 4:
		keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	return fmt & keep


static func _plain(bone: String) -> String:
	var i := bone.rfind("_")
	return bone.substr(i + 1) if i >= 0 else bone
