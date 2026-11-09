extends SceneTree
## Offline build step for hair and facial hair:
##   godot --headless --path . -s res://tools/build_hair.gd
##
## Sources (assets/player/, credits in assets/CREDITS.md):
## * hair_and_beard__pubg_mobile_3d_model.glb: five display heads, five hairstyles laid
##   out in a row under them (shifted down HAIR_DROP from their heads), and one beard.
##   Faces look +X. The hair cards' textures are grayscale strands, tinted in game.
## * mostache.glb: a handlebar moustache in two mirrored halves.
## * ported_hair.glb: a long single braid on a sphere standing in for the head.
##
## Every piece is saved in "head space": origin at the top of the head, centered, +Z
## toward the face, +Y up, one unit = the head's width (ear to ear). SkaterVisual scales
## it by the body's head width.
##   -> res://assets/characters/hair/<id>.res (+ <id>.png when it has a texture)

const SRC := "res://assets/player/"
const OUT := "res://assets/characters/hair/"
const HAIR_DROP := 0.5       ## the PUBG hairs sit this far below their display heads
const BEARD_DROP := 0.728    ## ...and the beard this far below the first head
const BEARD_BACK := 0.05     ## ...and pushed back this far (head widths) onto the jaw
const CHINSTRAP_BACK := 0.12 ## the same beard pushed further in: only the jaw line shows
## PUBG pieces (node name contains the key) -> style id.
const PUBG_HAIR := {"rip_7": "messy", "rip_8": "buzz", "rip_9": "shaggy", "rip_10": "mop", "rip_11": "quiff"}
const PUBG_HEADS := ["rip_2", "rip_3", "rip_4", "rip_5", "rip_6"]
const PUBG_BEARD := "rip_1"
## Moustache placement in head space (head widths): its width, and the middle of it
## under the nose.
const MOUSTACHE_WIDTH := 0.4
const MOUSTACHE_AT := Vector3(0.0, -0.935, 0.56)
const BRAID_TRIS := 9000
## Every hairstyle is saved twice: <id>.res as modeled (helmet off: fights) and
## <id>_helm.res for under the helmet, where hair above the rim is pressed flat onto this
## ellipsoid (head space: center, radii) times TUCK_AT, between the scalp and the helmet
## shell, so it shows through the vents. Below RIM it is left alone.
const SHELL_C := Vector3(0.0, -0.5, -0.02)
const SHELL_R := Vector3(0.5, 0.5, 0.58)
const TUCK_AT := 1.0
const RIM := -0.62
## The game body's scalp (head space; the PUBG cuts were modeled on smaller heads): hair
## above RIM that falls inside it is pushed out onto it, so the skull doesn't show through.
const SCALP_C := Vector3(0.0, -0.5, -0.04)
const SCALP_R := Vector3(0.53, 0.59, 0.62)
const SCALP_LIFT := 1.03    ## ...to just above it
## Long hair hanging below the head is pushed back this far (head widths) so it falls
## over the jersey instead of through it.
const NAPE_PUSH := 0.7
const HANG_SQUASH := 0.75    ## ...and shortened (the skater leans forward; it would reach into the back)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_pubg()
	_moustache()
	_braid()
	quit()


## Every MeshInstance3D under a model with its global transform: [[node, xf], ...].
func _meshes(path: String) -> Array:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var out := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append([mi, xf])
	return out


func _named(meshes: Array, key: String) -> Array:
	for m: Array in meshes:
		var mi: MeshInstance3D = m[0]
		# Exact piece: "rip_1" must not match "rip_10".
		if str(mi.get_parent().name).ends_with("_" + key) or str(mi.get_parent().name) == key:
			return m
	return []


func _box(m: Array) -> AABB:
	return (m[1] as Transform3D) * (m[0] as MeshInstance3D).mesh.get_aabb()


func _pubg() -> void:
	var meshes := _meshes(SRC + "hair_and_beard__pubg_mobile_3d_model.glb")
	var heads := []
	for k: String in PUBG_HEADS:
		heads.append(_box(_named(meshes, k)))
	# Faces look +X here: turn them to +Z (x, y, z) -> (-z, y, x).
	var turn := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	for key: String in PUBG_HAIR:
		var m := _named(meshes, key)
		var box := _box(m)
		# Its head: the one in the same column.
		var head: AABB = heads[0]
		for h: AABB in heads:
			if absf(h.get_center().z - box.get_center().z) < absf(head.get_center().z - box.get_center().z):
				head = h
		_save(m, PUBG_HAIR[key], head, Vector3(0, HAIR_DROP, 0), turn, true)
	_save(_named(meshes, PUBG_BEARD), "beard", heads[0], Vector3(0, BEARD_DROP, 0), turn, false, Vector3(0, 0, -BEARD_BACK))
	_save(_named(meshes, PUBG_BEARD), "chinstrap", heads[0], Vector3(0, BEARD_DROP, 0), turn, false, Vector3(0, 0, -CHINSTRAP_BACK))


## Saves one piece in head space. `head`: its head's box (source space); `shift`: moves
## the piece onto that head; `turn`: source axes to head space; `nudge`: a last move in
## head space.
func _save(m: Array, id: String, head: AABB, shift: Vector3, turn: Basis, tuck := false, nudge := Vector3.ZERO) -> void:
	var mi: MeshInstance3D = m[0]
	var xf: Transform3D = m[1]
	var top := Vector3(head.get_center().x, head.end.y, head.get_center().z)
	var width := head.size.z   # ear to ear (faces look +X)
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = turn * (xf * v[i] + shift - top) / width + nudge
		if i < nr.size():
			nr[i] = (turn * (xf.basis * nr[i])).normalized()
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_VERTEX] = _tuck(v.duplicate(), false) if tuck else v
	var out := _write(arr, id)
	if tuck:
		arr[Mesh.ARRAY_VERTEX] = _tuck(v.duplicate(), true)
		_write(arr, id + "_helm")
	var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if mat and mat.albedo_texture:
		var img := mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.save_png(OUT + id + ".png")
	print("%s: %d tris  size %s" % [id, out.get_faces().size() / 3, out.get_aabb().size])


## Long hair below the head goes back over the jersey. `helmet`: also, points above RIM
## that stick out of the shell ellipsoid are pulled onto it (blending over the band just
## above the rim).
func _tuck(v: PackedVector3Array, helmet: bool) -> PackedVector3Array:
	for i in v.size():
		var q := v[i]
		if q.y > RIM:
			var ds := (q - SCALP_C) / SCALP_R
			var w0 := clampf((q.y - RIM) / 0.15, 0.0, 1.0)
			if ds.length() < SCALP_LIFT and ds.length() > 0.001:
				q = q.lerp(SCALP_C + ds.normalized() * SCALP_LIFT * SCALP_R, w0)
			if not helmet:
				v[i] = q
				continue
			var d := (q - SHELL_C) / SHELL_R
			if d.length() > TUCK_AT:
				var inside := SHELL_C + d.normalized() * TUCK_AT * SHELL_R
				var w := clampf((q.y - RIM) / 0.15, 0.0, 1.0)
				q = q.lerp(inside, w)
		elif q.y < -1.0:
			q.z -= NAPE_PUSH * clampf((-1.0 - q.y) / 0.8, 0.0, 1.0)
			q.y = -1.0 + (q.y + 1.0) * HANG_SQUASH
		v[i] = q
	return v


## Keeps position, normal, UV and index only.
func _write(arr: Array, id: String) -> ArrayMesh:
	var keep := []
	keep.resize(Mesh.ARRAY_MAX)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		keep[k] = arr[k]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, keep)
	ResourceSaver.save(mesh, OUT + id + ".res")
	return mesh


## The handlebar moustache, both halves, scaled and set under the nose.
func _moustache() -> void:
	var meshes := _meshes(SRC + "mostache.glb")
	var box := AABB()
	for i in meshes.size():
		box = _box(meshes[i]) if i == 0 else box.merge(_box(meshes[i]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := MOUSTACHE_WIDTH / box.size.x
	for m: Array in meshes:
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * k), MOUSTACHE_AT - box.get_center() * k) * (m[1] as Transform3D)
		st.append_from((m[0] as MeshInstance3D).mesh, 0, xf)
	var arr := st.commit_to_arrays()
	var out := _write(arr, "moustache")
	print("moustache: %d tris  size %s" % [out.get_faces().size() / 3, out.get_aabb().size])


## The braid, fitted to the sphere it was modeled on, simplified.
func _braid() -> void:
	var meshes := _meshes(SRC + "ported_hair.glb")
	var head := AABB()
	var hair: Array = []
	for m: Array in meshes:
		if str((m[0] as MeshInstance3D).name).begins_with("Sphere") or str((m[0] as MeshInstance3D).get_parent().name) == "Sphere":
			head = _box(m)
		else:
			hair = m
	var top := Vector3(head.get_center().x, head.end.y, head.get_center().z)
	# The sphere is the bare skull; real heads (with ears) are a little wider.
	var width := head.size.x * 1.12
	var mi: MeshInstance3D = hair[0]
	var xf: Transform3D = hair[1]
	var st := SurfaceTool.new()
	st.append_from(mi.mesh, 0, Transform3D(Basis.from_scale(Vector3.ONE / width), -top / width) * xf)
	st.index()
	var arr := st.commit_to_arrays()
	var lod := st.generate_lod(1.0, BRAID_TRIS * 3)
	if lod.size() > 0 and lod.size() < (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size():
		arr[Mesh.ARRAY_INDEX] = lod
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	arr[Mesh.ARRAY_VERTEX] = _tuck(v.duplicate(), false)
	var out := _write(arr, "braid")
	arr[Mesh.ARRAY_VERTEX] = _tuck(v.duplicate(), true)
	_write(arr, "braid_helm")
	print("braid: %d tris  size %s" % [out.get_faces().size() / 3, out.get_aabb().size])
