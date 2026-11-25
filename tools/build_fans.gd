extends SceneTree
## Offline build step for the people in plain clothes (fans in close-ups, the Zamboni's
## driver). Run after tools/build_characters.gd or tools/blender/plain_clothes.py:
##   godot --headless --path . -s res://tools/build_fans.gd [-- body=male]
##
## For every body with a plain_<name>.glb (sweatshirt, jeans, boots):
##   * the skeleton, eyes and gear anchors are body_<name>.scn's own, so the players' clips
##     (anims_<name>.res), hair and faces fit as they are
##   * "Skin": what shows of the body, hands included (the players' bodies have none): the
##     head, hands and the neck above the collar, and the skin just inside the collar and
##     cuffs. Skin with cloth straight out from it is left out; legs and feet always are.
##   * "Outfit_Top", "Outfit_Pants", "Outfit_Shoes": the clothes on the same bones, their
##     rest position in CUSTOM0 (plain_cloth.gdshader pins its weave to it), the part in
##     COLOR.r (0 cloth or upper, 0.5 collar band or waistband, 1 sole) and in COLOR.g how
##     far it is to the end of the sleeve or the hem (0..1 over 10 cm: the rib knit's edge)
##   -> res://assets/characters/fan_<name>.scn (meta "sole": how far the boots reach under
##      the feet)

const BC := preload("res://tools/build_characters.gd")
const OUT_DIR := "res://assets/characters/"
const SOLE := 0.028         ## tools/blender/plain_clothes.py SOLE
const CELL := 0.02          ## m: grid cell for the cloth samples
const SAMPLE := 0.008       ## m: spacing of the samples laid over each cloth triangle
const REACH := 0.08         ## m: how far out from the skin cloth is looked for...
const BEHIND := 0.012       ## ...and in (cloth that sinks a little under the skin still covers it)
const NEAR := 0.011         ## m: a cloth sample this close to that line covers the skin
const MARGIN := 2           ## rings of covered skin kept round every opening...
const INSET := 0.005        ## ...each drawn in this much further (m), clear of the cloth over it
const REST_FORMAT := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("body="):
			only = a.substr(5)
	for spec: Dictionary in BC.BODIES:
		if only != "" and spec.name != only:
			continue
		if not ResourceLoader.exists(OUT_DIR + "plain_%s.glb" % spec.name) or not ResourceLoader.exists(OUT_DIR + "body_%s.scn" % spec.name):
			continue
		_build(spec)
	quit()


static func _canon(spec: Dictionary, raw: String) -> String:
	var n := BC.strip_prefix(raw)
	return (spec.map as Dictionary).get(n, n)


static func _to_root(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _is_leg(bone: String) -> bool:
	return bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe")


func _build(spec: Dictionary) -> void:
	var body: Node3D = (load(OUT_DIR + "body_%s.scn" % spec.name) as PackedScene).instantiate()
	var skel: Skeleton3D = body.get_node("Skeleton3D")
	var names: Array[String] = []
	var new_g: Array[Transform3D] = []
	for b in skel.get_bone_count():
		names.append(skel.get_bone_name(b))
		new_g.append(skel.get_bone_global_rest(b))

	var root := Node3D.new()
	root.name = "Body"
	for m in body.get_meta_list():
		root.set_meta(m, body.get_meta(m))
	root.set_meta("jersey", false)
	root.set_meta("sole", SOLE)
	var out := skel.duplicate() as Skeleton3D
	for c in out.get_children():
		if c.name != "Eyes":
			out.remove_child(c)
			c.free()
	root.add_child(out)
	out.owner = root
	for c in out.get_children():
		c.owner = root

	# The clothes.
	var cl: Node3D = (load(OUT_DIR + "plain_%s.glb" % spec.name) as PackedScene).instantiate()
	var gsk: Skeleton3D = cl.find_children("*", "Skeleton3D", true, false)[0]
	var cl_xf := _to_root(gsk, cl)
	var worst := 0.0
	for jn in ["Hips", "Neck", "LeftHand", "RightFoot"]:
		for b in gsk.get_bone_count():
			if _canon(spec, gsk.get_bone_name(b)) == jn:
				worst = maxf(worst, (cl_xf * gsk.get_bone_global_rest(b).origin).distance_to(new_g[names.find(jn)].origin))
	if worst > 0.02:
		push_error("plain_%s.glb: joints off by %.3f m from body_%s; re-run tools/blender/plain_clothes.py" % [spec.name, worst, spec.name])
		return
	var grid := {}
	var cloth_nodes: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in cl.find_children("*", "MeshInstance3D", true, false):
		var o := _cloth(spec, mi, gsk, cl_xf, names, new_g, grid)
		if o != null:
			cloth_nodes.append(o)

	# The skin that shows.
	var skin_mi := _skin(spec, names, new_g, grid)
	out.add_child(skin_mi)
	skin_mi.owner = root
	skin_mi.skeleton = NodePath("..")
	for o in cloth_nodes:
		out.add_child(o)
		o.owner = root
		o.skeleton = NodePath("..")

	var packed := PackedScene.new()
	packed.pack(root)
	var path := OUT_DIR + "fan_%s.scn" % spec.name
	var err := ResourceSaver.save(packed, path)
	print("%s: %s (clothes' joints within %.3f m)" % [path, error_string(err), worst])
	cl.free()
	body.free()
	root.free()


## One piece of clothing on the body's skeleton, and its surface sampled into `grid`.
func _cloth(spec: Dictionary, mi: MeshInstance3D, gsk: Skeleton3D, xf: Transform3D, names: Array[String],
		new_g: Array[Transform3D], grid: Dictionary) -> MeshInstance3D:
	var skin := mi.skin
	var new_skin := Skin.new()
	for i in skin.get_bind_count():
		var raw := skin.get_bind_name(i)
		if raw == "":
			raw = gsk.get_bone_name(skin.get_bind_bone(i))
		var cn := _canon(spec, raw)
		var bi := names.find(cn)
		if bi < 0:
			push_error("plain_%s.glb %s: bone %s not in the body" % [spec.name, mi.name, raw])
			return null
		new_skin.add_named_bind(cn, new_g[bi].affine_inverse())
	var mesh := ArrayMesh.new()
	var tris := 0
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var rest := PackedFloat32Array()
		rest.resize(verts.size() * 3)
		for i in verts.size():
			verts[i] = xf * verts[i]
			norms[i] = (xf.basis * norms[i]).normalized()
			rest[i * 3] = verts[i].x
			rest[i * 3 + 1] = verts[i].y
			rest[i * 3 + 2] = verts[i].z
		var colors := PackedColorArray()
		colors.resize(verts.size())
		var src_c: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		for i in verts.size():
			colors[i] = Color(src_c[i].r, src_c[i].g, 0.0, 1.0) if src_c.size() == verts.size() else Color(0.0, 1.0, 0.0, 1.0)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_BONES] = arr[Mesh.ARRAY_BONES]
		a[Mesh.ARRAY_WEIGHTS] = arr[Mesh.ARRAY_WEIGHTS]
		a[Mesh.ARRAY_INDEX] = idx
		a[Mesh.ARRAY_CUSTOM0] = rest
		var flags: int = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags | REST_FORMAT)
		tris += idx.size() / 3
		for t in range(0, idx.size(), 3):
			_sample(grid, verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]])
	var o := MeshInstance3D.new()
	o.name = "Outfit_" + String(mi.name)
	o.mesh = mesh
	o.skin = new_skin
	print("  %s: %d triangles, %d binds" % [o.name, tris, new_skin.get_bind_count()])
	return o


## Points over a cloth triangle, no further apart than SAMPLE, into the grid.
static func _sample(grid: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := maxi(1, ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / SAMPLE))
	for i in n + 1:
		for j in n + 1 - i:
			var p := a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n)
			var cell := Vector3i((p / CELL).floor())
			var pts: PackedVector3Array = grid.get(cell, PackedVector3Array())
			pts.append(p)
			grid[cell] = pts


## Is there cloth straight out from skin point `v` along `n` (or just under it)?
static func _covered(grid: Dictionary, v: Vector3, n: Vector3) -> bool:
	var t := -BEHIND
	while t <= REACH:
		var p := v + n * t
		var c := Vector3i((p / CELL).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var cell: Variant = grid.get(c + Vector3i(dx, dy, dz))
					if cell == null:
						continue
					for q: Vector3 in cell:
						if q.distance_squared_to(p) < NEAR * NEAR:
							return true
		t += NEAR
	return false


## The body's own mesh in the game's space (as tools/build_characters.gd places it), cut
## down to what the clothes leave in sight.
func _skin(spec: Dictionary, names: Array[String], new_g: Array[Transform3D], grid: Dictionary) -> MeshInstance3D:
	var src: Node3D = (load(spec.file) as PackedScene).instantiate()
	var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var P := _to_root(sk, src)
	var src_mi: MeshInstance3D = null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if spec.has("eyes") and mi.name.to_lower().ends_with("eyes"):
			continue
		if (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= BC.MIN_MESH_VERTS:
			src_mi = mi
	var lo := INF
	var hi := -INF
	for v: Vector3 in src_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var w := P * v
		lo = minf(lo, w.y)
		hi = maxf(hi, w.y)
	var k: float = spec.height / (hi - lo)
	var off := Vector3(0, lo, 0)
	var worst := 0.0
	for b in sk.get_bone_count():
		worst = maxf(worst, (((P * sk.get_bone_global_rest(b)).origin - off) * k).distance_to(new_g[b].origin))
	if worst > 0.001:
		push_error("%s: its joints are %.4f m off body_%s.scn's; re-run tools/build_characters.gd" % [spec.file, worst, spec.name])

	var skin := src_mi.skin
	var new_skin := Skin.new()
	var bind_bone: Array[int] = []
	for i in skin.get_bind_count():
		var bn := skin.get_bind_name(i)
		var bi := sk.find_bone(bn) if bn != "" else skin.get_bind_bone(i)
		bind_bone.append(bi)
		new_skin.add_named_bind(names[bi], new_g[bi].affine_inverse())

	var arr := src_mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := bones.size() / verts.size()
	var nb := P.basis.orthonormalized()
	# 0 in sight, 1 under cloth, 2 never drawn (legs and feet); shared by the copies of a
	# vertex the texture's seams split, so the margin below crosses them.
	var spot := {}
	var pid := PackedInt32Array()
	pid.resize(verts.size())
	var state := PackedByteArray()
	for i in verts.size():
		verts[i] = (P * verts[i] - off) * k
		norms[i] = (nb * norms[i]).normalized()
		var key := Vector3i((verts[i] * 20000.0).round())
		if not spot.has(key):
			spot[key] = state.size()
			state.append(0)
		pid[i] = spot[key]
		var best := 0
		var bw := -1.0
		for j in per:
			if weights[i * per + j] > bw:
				bw = weights[i * per + j]
				best = bones[i * per + j]
		var dom := names[bind_bone[best]].trim_prefix("x_")
		var st := 0
		if _is_leg(dom):
			st = 2
		# (the neck too: under a close collar its base pushed out through the cloth whenever
		# the head went back, the cloth riding the chest and the skin the neck)
		elif not (BC.is_hand_bone(dom) or dom.begins_with("Head")):
			st = 1 if _covered(grid, verts[i], norms[i]) else 0
		state[pid[i]] = maxi(state[pid[i]], st)
	var depth := {}   # spot -> which ring of the margin it is in (1 the first under cloth)
	for ring in MARGIN:
		var show := {}
		for t in range(0, idx.size(), 3):
			var seen := false
			for q in 3:
				seen = seen or state[pid[idx[t + q]]] == 0
			if seen:
				for q in 3:
					if state[pid[idx[t + q]]] == 1:
						show[pid[idx[t + q]]] = true
		for p: int in show:
			state[p] = 0
			depth[p] = ring + 1
	for i in verts.size():
		if depth.has(pid[i]):
			verts[i] -= norms[i] * INSET * float(depth[pid[i]])
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var o_v := PackedVector3Array()
	var o_n := PackedVector3Array()
	var o_uv := PackedVector2Array()
	var o_b := PackedInt32Array()
	var o_w := PackedFloat32Array()
	var o_i := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if state[pid[idx[t]]] != 0 or state[pid[idx[t + 1]]] != 0 or state[pid[idx[t + 2]]] != 0:
			continue
		for q in 3:
			var i := idx[t + q]
			if remap[i] < 0:
				remap[i] = o_v.size()
				o_v.append(verts[i])
				o_n.append(norms[i])
				var uv := uvs[i]
				if spec.get("flip_v", false):
					uv.y = 1.0 - uv.y
				o_uv.append(uv)
				for j in per:
					o_b.append(bones[i * per + j])
					o_w.append(weights[i * per + j])
			o_i.append(remap[i])
	# (the players' skin shader hides what their uniform covers, by these: nothing here)
	var o_c := PackedColorArray()
	o_c.resize(o_v.size())
	o_c.fill(Color(0, 0, 0, 0))
	var o_uv2 := PackedVector2Array()
	o_uv2.resize(o_v.size())
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = o_v
	a[Mesh.ARRAY_NORMAL] = o_n
	a[Mesh.ARRAY_TEX_UV] = o_uv
	a[Mesh.ARRAY_TEX_UV2] = o_uv2
	a[Mesh.ARRAY_COLOR] = o_c
	a[Mesh.ARRAY_BONES] = o_b
	a[Mesh.ARRAY_WEIGHTS] = o_w
	a[Mesh.ARRAY_INDEX] = o_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, src_mi.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	var o := MeshInstance3D.new()
	o.name = "Skin"
	o.mesh = mesh
	o.skin = new_skin
	print("  Skin: %d of %d triangles in sight (joints within %.4f m)" % [o_i.size() / 3, idx.size() / 3, worst])
	src.free()
	return o
