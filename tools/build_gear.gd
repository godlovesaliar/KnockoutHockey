extends SceneTree
## Offline build step for equipment models:
##   godot --headless --path . -s res://tools/build_gear.gd [-- only=helmet|mask|stick|goalie_stick|skate|glove|catcher]
##
## Source models (assets/equip/, credits in assets/CREDITS.md) become plain meshes in
## meters, with their textures dropped (they carry real team and brand logos) and
## surfaces split by role, so the game paints them per team:
## * Helmets (HELMETS): one surface per role: 0 shell, 1 trim, 2 dark, 3 visor. Front +Z,
##   centered on the shell.
## * Goalie masks (MASKS): 0 shell, 1 cage. Front +Z, centered.
## * Stick: 0 shaft, 1 blade. Heel at the origin, shaft up +Y (STICK_SHAFT m long), the
##   blade in the YZ plane toward +Z; its heel-to-toe vector is saved as the "blade" meta.
## * Goalie stick: the same layout; 0 body (shaft and paddle), 1 grip, 2 blade tape.
## * Skate: 0 boot, 1 steel. Toe +Z, origin under the middle of the runner.
## * Glove: one surface. A right glove gripping: fingers along +Y curled toward -Z (the
##   palm), back of the hand +Z, thumb -X, origin at the wrist.
## * Catcher (goalie glove): one surface. Fingers +Y, pocket +Z, origin at the hand.
## Dense scans are welded and simplified with Godot's mesh optimizer.
##   -> res://assets/characters/<out>.res

const OUT_DIR := "res://assets/characters/"
const EQUIP := "res://assets/equip/"

const HELMETS := [
	{"out": "helmet", "src": EQUIP + "hockey_helmet_washington_capitals.glb", "front": Vector3.RIGHT, "length": 0.29, "tris": 0},
	{"out": "helmet_b", "src": EQUIP + "hockeyhelmet/source/hockey_helmet_whiteblackwithlogo.glb", "front": Vector3.BACK, "length": 0.29, "tris": 7000,
		"roles": {0: 2, 11: 0}},   # chin strap dark, the front shell piece in team color too
]
## (`roles` overrides the automatic role of a part by index: 0 shell, 1 trim, 2 dark, 3 visor.)
## cage: "node" = nodes named *cage*, "surface1" = the model's second surface;
## front: the model's front axis (default +Z).
const MASKS := [
	{"out": "goalie_mask", "src": EQUIP + "helmet-for-puck/source/helmet_sketchfab.fbx", "cage": "node", "height": 0.53, "tris": [0, 0]},
	{"out": "goalie_mask_b", "src": EQUIP + "GMask.obj", "cage": "surface1", "height": 0.36, "tris": [7000, 3000], "front": Vector3.LEFT},
]
const STICK_SRC := EQUIP + "hockey-stick/source/untitled.fbx"
const STICK_SHAFT := 1.45        ## heel to butt end, meters
const GOALIE_STICK_SRC := EQUIP + "ccm_premier_goaliestick.blend"
const GOALIE_STICK_NODES := ["Cube", "Cube_002"]   ## the rest of the .blend is a display scene
const GOALIE_STICK_SHAFT := 1.4
const SKATE_SRC := EQUIP + "ice-hockey-skate/source/IceHockey_Skate.fbx"
const SKATE_LENGTH := 0.31
const SKATE_TRIS := 1800
const SKATE_STEEL := 0.028       ## the runner: everything this close to the bottom
const GLOVE_SRC := EQUIP + "glove.glb"   ## a long-cuff leather gauntlet, fingers flat
const GLOVE_LENGTH := 0.36       ## cuff to fingertips before curling, meters
const GLOVE_KNUCKLE := 0.27      ## fingers bend from here down from the tips (fraction of length)
const GLOVE_WRIST := 0.48        ## the wrist (model origin), from the tips (fraction of length)
const GLOVE_THUMB_X := -0.29     ## the thumb: left of this (fraction of width from center)...
const GLOVE_THUMB_Z := 0.12      ## ...and this far palm-side of the fingers (fraction of depth): not curled
const GLOVE_CURL := 1.6          ## finger curl, radians
const GLOVE_PUFF := Vector3(1.12, 1.0, 1.3)   ## hockey gloves are bulkier than the leather source
const CATCHER_SRC := EQUIP + "baseball_glove.glb"
const CATCHER_HEIGHT := 0.42
const CATCHER_TRIS := 3500
const CATCHER_HAND := 0.38      ## where the hand (model origin) sits, from the bottom (fraction of height)


func _init() -> void:
	var what := "all"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			what = a.substr(5)
	if what in ["all", "helmet"]:
		for spec: Dictionary in HELMETS:
			_build_helmet(spec)
	if what in ["all", "mask"]:
		for spec: Dictionary in MASKS:
			_build_mask(spec)
	if what in ["all", "stick"]:
		_build_stick()
	if what in ["all", "goalie_stick"]:
		_build_goalie_stick()
	if what in ["all", "skate"]:
		_build_skate()
	if what in ["all", "glove"]:
		_build_glove()
	if what in ["all", "catcher"]:
		_build_catcher()
	quit()


## Rotation taking the model's (front, up) to (+Z, +Y).
static func orient(front: Vector3, up: Vector3) -> Basis:
	var from := Basis(up.cross(front).normalized(), up.normalized(), front.normalized())
	return from.transposed()


# --- Loading and mesh helpers ------------------------------------------------------

## Every surface of a model as {verts, norms, idx (model space), avg color, name, surf}.
func _parts(path: String) -> Array:
	var res = load(path)
	var out := []
	if res is Mesh:
		for s in (res as Mesh).get_surface_count():
			out.append(_part((res as Mesh).surface_get_arrays(s), Transform3D.IDENTITY, (res as Mesh).surface_get_material(s), "mesh", s))
		return out
	var root: Node3D = (res as PackedScene).instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			out.append(_part(mi.mesh.surface_get_arrays(s), xf, mi.mesh.surface_get_material(s), mi.name, s))
	root.free()
	return out


func _part(arr: Array, xf: Transform3D, mat: Material, name: String, surf: int) -> Dictionary:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in v.size():
			idx.append(i)
	var nb := xf.basis.inverse().transposed()
	for i in v.size():
		v[i] = xf * v[i]
		if i < nr.size():
			nr[i] = (nb * nr[i]).normalized()
	return {"verts": v, "norms": nr, "idx": idx, "avg": _avg_color(mat as BaseMaterial3D), "name": name, "surf": surf}


## Applies `f(v) -> v` to a part's vertices and `b` to its normals.
func _map(p: Dictionary, f: Callable, b: Basis) -> void:
	var v: PackedVector3Array = p.verts
	var nr: PackedVector3Array = p.norms
	for i in v.size():
		v[i] = f.call(v[i])
		if i < nr.size():
			nr[i] = (b * nr[i]).normalized()
	p.verts = v
	p.norms = nr


func _bounds(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for p: Dictionary in parts:
		for v: Vector3 in p.verts:
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
	return box


func _tris(p: Dictionary) -> int:
	return (p.idx as PackedInt32Array).size() / 3


## Several parts merged into one {verts, norms, idx}.
func _merge(parts: Array) -> Dictionary:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var idx := PackedInt32Array()
	for p: Dictionary in parts:
		var base := v.size()
		v.append_array(p.verts)
		if (p.norms as PackedVector3Array).size() == (p.verts as PackedVector3Array).size():
			nr.append_array(p.norms)
		else:
			nr.resize(v.size())
		for i: int in p.idx:
			idx.append(base + i)
	return {"verts": v, "norms": nr, "idx": idx}


## Welds by position (dropping UV seams) and simplifies to about `target` triangles,
## with smooth normals. target <= 0 keeps the part as it is.
func _simplify(p: Dictionary, target: int) -> Dictionary:
	if target <= 0 or _tris(p) <= target:
		if (p.norms as PackedVector3Array).size() != (p.verts as PackedVector3Array).size() or (p.norms as PackedVector3Array).has(Vector3.ZERO):
			p.norms = _normals(p.verts, p.idx)
		return p
	var weld := {}
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for i: int in p.idx:
		var q: Vector3 = (p.verts as PackedVector3Array)[i]
		var key := q.snapped(Vector3.ONE * 1e-6)
		var j: int = weld.get(key, -1)
		if j < 0:
			j = v.size()
			weld[key] = j
			v.append(q)
		idx.append(j)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = _normals(v, idx)
	arrays[Mesh.ARRAY_INDEX] = idx
	# The optimizer stops early on noisy scans; running it again on its own output
	# gets further.
	var lod := idx
	for attempt in 6:
		arrays[Mesh.ARRAY_INDEX] = lod
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		var next := st.generate_lod(1.0, target * 3)
		if next.size() >= lod.size() * 0.97:
			break
		lod = next
		if lod.size() <= target * 3 * 1.05:
			break
	var remap := {}
	var nv := PackedVector3Array()
	var ni := PackedInt32Array()
	for old in lod:
		var j: int = remap.get(old, -1)
		if j < 0:
			j = nv.size()
			remap[old] = j
			nv.append(v[old])
		ni.append(j)
	if ni.size() / 3 > target * 1.5:
		# Still far off (scans full of tiny holes): fall back to vertex clustering.
		var cl := _cluster(nv, ni, target)
		nv = cl[0]
		ni = cl[1]
	print("    simplified %d -> %d tris" % [_tris(p), ni.size() / 3])
	return {"verts": nv, "norms": _normals(nv, ni), "idx": ni}


## Vertex clustering: snaps vertices to a grid (averaging each cell) and drops collapsed
## triangles; the cell size is searched for about `target` triangles. Fine for blobby
## shapes like a glove, not for thin shells.
func _cluster(v: PackedVector3Array, idx: PackedInt32Array, target: int) -> Array:
	var box := AABB(v[0], Vector3.ZERO)
	for q in v:
		box = box.expand(q)
	var lo := box.get_longest_axis_size() / 400.0
	var hi := box.get_longest_axis_size() / 8.0
	var best := [v, idx]
	for step in 16:
		var cell := sqrt(lo * hi)
		var cells := {}
		var sums := PackedVector3Array()
		var counts := PackedInt32Array()
		var ni := PackedInt32Array()
		var seen := {}
		for t in range(0, idx.size(), 3):
			var ids := [0, 0, 0]
			for k in 3:
				var q := v[idx[t + k]]
				var key := Vector3i(floori(q.x / cell), floori(q.y / cell), floori(q.z / cell))
				var c: int = cells.get(key, -1)
				if c < 0:
					c = sums.size()
					cells[key] = c
					sums.append(Vector3.ZERO)
					counts.append(0)
				ids[k] = c
			for k in 3:
				sums[ids[k]] += v[idx[t + k]]
				counts[ids[k]] += 1
			if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
				continue
			var sorted_ids := ids.duplicate()
			sorted_ids.sort()
			if seen.has(sorted_ids):
				continue
			seen[sorted_ids] = true
			ni.append_array(ids)
		var nv := PackedVector3Array()
		nv.resize(sums.size())
		for i in sums.size():
			nv[i] = sums[i] / maxi(counts[i], 1)
		best = [nv, ni]
		var n := ni.size() / 3
		if absf(n - target) < target * 0.08:
			break
		if n > target:
			lo = cell
		else:
			hi = cell
	return best


func _normals(v: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var fn := (v[idx[t + 2]] - a).cross(v[idx[t + 1]] - a)
		n[idx[t]] += fn
		n[idx[t + 1]] += fn
		n[idx[t + 2]] += fn
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 0.0 else Vector3.UP
	return n


## Saves surfaces ({verts, norms, idx} each; empty ones get a degenerate triangle so
## the slots stay stable).
func _save(surfaces: Array, out: String, metas := {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for p: Dictionary in surfaces:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		if (p.idx as PackedInt32Array).is_empty():
			a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
			a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
		else:
			a[Mesh.ARRAY_VERTEX] = p.verts
			a[Mesh.ARRAY_NORMAL] = p.norms
			a[Mesh.ARRAY_INDEX] = p.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	for k: String in metas:
		mesh.set_meta(k, metas[k])
	var err := ResourceSaver.save(mesh, OUT_DIR + out + ".res")
	var counts := []
	for p: Dictionary in surfaces:
		counts.append(_tris(p))
	print("%s.res: %s  tris %s  size %s" % [out, error_string(err), counts, mesh.get_aabb().size])
	return mesh


## Splits a part's triangles in two by `pick(centroid) -> bool` (true = second).
func _split(p: Dictionary, pick: Callable) -> Array:
	var ia := PackedInt32Array()
	var ib := PackedInt32Array()
	var v: PackedVector3Array = p.verts
	var idx: PackedInt32Array = p.idx
	for t in range(0, idx.size(), 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if pick.call(c):
			ib.append_array([idx[t], idx[t + 1], idx[t + 2]])
		else:
			ia.append_array([idx[t], idx[t + 1], idx[t + 2]])
	return [{"verts": v, "norms": p.norms, "idx": ia}, {"verts": v, "norms": p.norms, "idx": ib}]


func _avg_color(mat: BaseMaterial3D) -> Color:
	if mat == null:
		return Color.WHITE
	var tint := mat.albedo_color
	if mat.albedo_texture == null:
		return tint
	var img := mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	var c := Vector4.ZERO
	var k := 0
	var step := maxi(1, img.get_width() / 24)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var p := img.get_pixel(x, y)
			c += Vector4(p.r, p.g, p.b, p.a)
			k += 1
	c /= maxf(k, 1)
	return Color(c.x * tint.r, c.y * tint.g, c.z * tint.b, c.w * tint.a)


# --- Helmets -----------------------------------------------------------------------

## Parts by role: the biggest is the shell, see-through ones the visor, the rest trim
## (bright) or dark.
func _build_helmet(spec: Dictionary) -> void:
	var parts := _parts(spec.src)
	var shell := 0
	var total := 0
	for i in parts.size():
		total += _tris(parts[i])
		if _tris(parts[i]) > _tris(parts[shell]):
			shell = i
	var rot := orient(spec.front, Vector3.UP)
	for p: Dictionary in parts:
		_map(p, func(v: Vector3) -> Vector3: return rot * v, rot)
	var shell_box := _bounds([parts[shell]])
	var scale: float = spec.length / shell_box.size.z
	var center := shell_box.get_center()
	var roles := [[], [], [], []]
	for i in parts.size():
		var p: Dictionary = parts[i]
		_map(p, func(v: Vector3) -> Vector3: return (v - center) * scale, Basis.IDENTITY)
		var c: Color = p.avg
		var role := 0 if i == shell else (3 if c.a < 0.7 else (1 if c.get_luminance() > 0.55 else 2))
		role = (spec.get("roles", {}) as Dictionary).get(i, role)
		roles[role].append(p)
		print("  %s part %2d: %5d tris  avg %s -> %s" % [spec.out, i, _tris(p), c.to_html(true), ["shell", "trim", "dark", "visor"][role]])
	var surfaces := []
	for r: Array in roles:
		var m := _merge(r)
		var target: int = 0 if spec.tris <= 0 else maxi(12, int(spec.tris * _tris(m) / float(total)))
		surfaces.append(_simplify(m, target))
	_save(surfaces, spec.out)


# --- Goalie masks ------------------------------------------------------------------

func _build_mask(spec: Dictionary) -> void:
	var parts := _parts(spec.src)
	var shell := []
	var cage := []
	for p: Dictionary in parts:
		var is_cage: bool = (p.name as String).to_lower().contains("cage") if spec.cage == "node" else p.surf == 1
		(cage if is_cage else shell).append(p)
	var rot := orient(spec.get("front", Vector3.BACK), Vector3.UP)
	for p: Dictionary in parts:
		_map(p, func(v: Vector3) -> Vector3: return rot * v, rot)
	var box := _bounds(parts)
	var scale: float = spec.height / box.size.y
	var center := box.get_center()
	for p: Dictionary in parts:
		_map(p, func(v: Vector3) -> Vector3: return (v - center) * scale, Basis.IDENTITY)
	_save([_simplify(_merge(shell), spec.tris[0]), _simplify(_merge(cage), spec.tris[1])], spec.out)


# --- Stick -------------------------------------------------------------------------

## The source lies flat: shaft along +X, the blade bending off toward -Z at the heel,
## blade faces toward ±Y.
func _build_stick() -> void:
	var p: Dictionary = _merge(_parts(STICK_SRC))
	var v: PackedVector3Array = p.verts
	var box := _bounds([p])
	# Shaft: the vertices within its thickness of the far +Z side.
	var thick := 0.0
	var heel_x := INF
	var top_x := -INF
	var zmax := box.end.z
	for q in v:
		top_x = maxf(top_x, q.x)
	# Thickness of the shaft = its Z extent near the butt end.
	var zmin_butt := INF
	for q in v:
		if q.x > top_x - box.size.x * 0.1:
			zmin_butt = minf(zmin_butt, q.z)
	thick = zmax - zmin_butt
	for q in v:
		if q.z > zmin_butt - thick * 0.25:
			heel_x = minf(heel_x, q.x)
	var toe := v[0]
	for q in v:
		if q.z < toe.z:
			toe = q
	var heel := Vector3(heel_x, box.get_center().y, zmax - thick * 0.5)
	var scale := STICK_SHAFT / (top_x - heel_x)
	# Model (x, y, z) -> (y, x, -z): shaft to +Y, blade to +Z, faces to ±X.
	var rot := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
	_map(p, func(q: Vector3) -> Vector3: return rot * (q - heel) * scale, rot)
	var blade := rot * (toe - heel) * scale
	var parts := _split(p, func(c: Vector3) -> bool: return c.y < 0.04 or c.z > 0.025)
	print("  stick: heel %s  blade %s  shaft %.2f m" % [heel, blade, STICK_SHAFT])
	_save([_simplify(parts[0], 0), _simplify(parts[1], 0)], "stick", {"blade": blade, "shaft": STICK_SHAFT})


# --- Skate -------------------------------------------------------------------------

func _build_skate() -> void:
	var p := _simplify(_merge(_parts(SKATE_SRC)), SKATE_TRIS)
	var box := _bounds([p])
	var scale := SKATE_LENGTH / box.size.z
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_map(p, func(q: Vector3) -> Vector3: return (q - base) * scale, Basis.IDENTITY)
	var parts := _split(p, func(c: Vector3) -> bool: return c.y < SKATE_STEEL)
	_save(parts, "skate")


# --- Glove ---------------------------------------------------------------------

## The source is upright (fingers +Y, palm -Z, thumb -X: a right glove) with the fingers
## flat; they are bent toward the palm around the knuckle line so the glove grips the
## stick, and the glove is puffed up to hockey-glove bulk.
func _build_glove() -> void:
	var p := _merge(_parts(GLOVE_SRC))
	var box := _bounds([p])
	var top := box.end.y
	var len := box.size.y
	var y_k := top - len * GLOVE_KNUCKLE
	var x_thumb := box.get_center().x + box.size.x * GLOVE_THUMB_X
	var finger_len := top - y_k
	var r := finger_len / GLOVE_CURL
	# Mid-plane of the fingers (their z center).
	var zs := 0.0
	var n := 0
	for q: Vector3 in p.verts:
		if q.y > y_k and q.x > x_thumb:
			zs += q.z
			n += 1
	var z_m := zs / maxi(n, 1)
	var z_thumb := z_m - box.size.z * GLOVE_THUMB_Z
	var bend := func(q: Vector3) -> Vector3:
		if q.y <= y_k or (q.x <= x_thumb and q.z < z_thumb):
			return q
		var th := (q.y - y_k) / r
		var w := q.z - z_m
		return Vector3(q.x, y_k + (r + w) * sin(th), z_m - r + (r + w) * cos(th))
	var v: PackedVector3Array = p.verts
	for i in v.size():
		v[i] = bend.call(v[i])
	p.verts = v
	var wrist := Vector3(box.get_center().x, top - len * GLOVE_WRIST, box.get_center().z)
	var scale := GLOVE_LENGTH / len
	_map(p, func(q: Vector3) -> Vector3: return (q - wrist) * GLOVE_PUFF * scale, Basis.IDENTITY)
	p.norms = _normals(p.verts, p.idx)
	_save([p], "glove")


## Baseball glove as the goalie's catcher: fingers +Y, pocket +Z in the source.
func _build_catcher() -> void:
	var p := _simplify(_merge(_parts(CATCHER_SRC)), CATCHER_TRIS)
	var box := _bounds([p])
	var scale := CATCHER_HEIGHT / box.size.y
	# The hand sits in the lower part of the glove, not at the bottom of its flaps.
	var hand := Vector3(box.get_center().x, box.position.y + box.size.y * CATCHER_HAND, box.get_center().z)
	_map(p, func(q: Vector3) -> Vector3: return (q - hand) * scale, Basis.IDENTITY)
	_save([p], "catcher")


# --- Goalie stick ------------------------------------------------------------------

## The source stands diagonally in its YZ plane; the frame is found from the parts: the
## blade runs along the tape's long axis, the butt end is the body's farthest point from
## the tape, and the heel is the tape end nearest the butt.
func _build_goalie_stick() -> void:
	var parts := []
	for q: Dictionary in _parts(GOALIE_STICK_SRC):
		if q.name in GOALIE_STICK_NODES:
			parts.append(q)
	var body := []
	var grip := []
	var tape := []
	for q: Dictionary in parts:
		if q.name == "Cube_002":
			tape.append(q)
		elif q.surf == 1:
			grip.append(q)
		else:
			body.append(q)
	var tv: PackedVector3Array = _merge(tape).verts
	var tc := Vector3.ZERO
	for q in tv:
		tc += q
	tc /= tv.size()
	# Long axis of the tape: the pair of tape vertices farthest apart (sampled).
	var a := tv[0]
	for q in tv:
		if q.distance_squared_to(tc) > a.distance_squared_to(tc):
			a = q
	var b := a
	for q in tv:
		if q.distance_squared_to(a) > b.distance_squared_to(a):
			b = q
	var butt := tc
	for p: Dictionary in body + grip:
		for q: Vector3 in p.verts:
			if q.distance_squared_to(tc) > butt.distance_squared_to(tc):
				butt = q
	var heel := a if a.distance_squared_to(butt) < b.distance_squared_to(butt) else b
	var toe := b if heel == a else a
	var up := (butt - heel).normalized()
	var n := up.cross(toe - heel).normalized()
	var fwd := n.cross(up)
	var rot := Basis(n, up, fwd).transposed()   # n -> X, up -> Y, fwd -> Z
	var scale := GOALIE_STICK_SHAFT / heel.distance_to(butt)
	for p: Dictionary in parts:
		_map(p, func(q: Vector3) -> Vector3: return rot * (q - heel) * scale, rot)
	var blade := rot * (toe - heel) * scale
	print("  goalie stick: blade %s  shaft %.2f m" % [blade, GOALIE_STICK_SHAFT])
	_save([_simplify(_merge(body), 0), _simplify(_merge(grip), 0), _simplify(_merge(tape), 0)], "goalie_stick",
			{"blade": blade, "shaft": GOALIE_STICK_SHAFT})
