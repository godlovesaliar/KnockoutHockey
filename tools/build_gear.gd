extends SceneTree
## Offline build step for equipment models:
##   godot --headless --path . -s res://tools/build_gear.gd [-- only=helmet|mask|stick|goalie_stick|skate|glove|catcher|goalie_gear]
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
## Skater glove sources: upright right gloves (fingers +Y, palm -Z, thumb -X) with the
## fingers more or less flat. GLOVE picks the one the game uses.
##   length: cuff to fingertips before curling (m) · knuckle: the fingers bend from here
##   down from the tips · wrist: the wrist (model origin) down from the tips (fractions of
##   the length) · thumb_x / thumb_z: the thumb lies left of thumb_x (fraction of the
##   width from center) and thumb_z palm-side of the fingers (fraction of the depth), and
##   isn't curled · curl: finger curl (rad) · thumb_fold: the thumb swings in toward the
##   palm this far (rad, more toward its tip) · puff: bulk scale · tris: simplify to.
const GLOVES := {
	# Armored moto glove: knuckle guard, finger armor, short strapped cuff.
	"srg": {"src": EQUIP + "srg_glove.glb", "length": 0.27, "knuckle": 0.42, "wrist": 0.66,
		"thumb_x": -0.27, "thumb_z": 0.1, "curl": 2.0, "thumb_fold": 1.1, "thumb_reach": 0.35, "puff": Vector3(1.18, 1.0, 1.25), "tris": 9000, "cluster": false, "weld": 0.004},
	# Long-cuff leather gauntlet (the first glove; its cuff flared out of the grip).
	"leather": {"src": EQUIP + "glove.glb", "length": 0.36, "knuckle": 0.27, "wrist": 0.48,
		"thumb_x": -0.29, "thumb_z": 0.12, "curl": 1.6, "puff": Vector3(1.12, 1.0, 1.3), "tris": 0},
}
## "blender" takes the glove modeled by tools/blender/hand_gear.py: already closed around
## the stick and in game axes, so it's only copied over. "hockey" builds the older padded
## glove from scratch (_build_hockey_glove); the scans above stay as options.
const GLOVE := "blender"
const BLENDER_GLOVE := EQUIP + "hockey_glove.glb"
## Its cuff, a separate mesh the game hangs on the forearm (same axes, origin at the wrist).
const BLENDER_CUFF := EQUIP + "hockey_glove_cuff.glb"
## The bare fist worn in fights (also from hand_gear.py), same axes as the glove.
const FIST_SRC := EQUIP + "fist.glb"
## Where the stick runs through the closed fist, from the wrist: up the fingers, then in
## toward the palm (meters, 1.8 m body). SkaterVisual.GRIP_OFFSET / GRIP_PALM match these.
const GRIP_UP := 0.065
const GRIP_IN := 0.05
const GOALIE_GEAR := ["goalie_pad", "goalie_boot", "goalie_thigh", "blocker", "goalie_catcher"]
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
	if what in ["all", "glove", "fist"]:
		_save([_simplify(_merge(_parts(FIST_SRC)), 0)], "fist")
	if what in ["all", "catcher"]:
		_build_catcher()
	if what in ["all", "goalie_gear"]:
		# Leg pads, thigh rises and blocker from tools/blender/goalie_gear.py: modeled in
		# game axes with their shading baked into vertex colors, so only copied over.
		for name in GOALIE_GEAR:
			_save([_simplify(_merge(_parts(EQUIP + name + ".glb")), 0)], name)
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
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	return {"verts": v, "norms": nr, "idx": idx, "colors": cols, "avg": _avg_color(mat as BaseMaterial3D), "name": name, "surf": surf}


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
	var cols := PackedColorArray()   # kept only when every part has vertex colors
	var all_cols := true
	for p: Dictionary in parts:
		var base := v.size()
		v.append_array(p.verts)
		if (p.norms as PackedVector3Array).size() == (p.verts as PackedVector3Array).size():
			nr.append_array(p.norms)
		else:
			nr.resize(v.size())
		var pc: PackedColorArray = p.get("colors", PackedColorArray())
		if pc.size() == (p.verts as PackedVector3Array).size():
			cols.append_array(pc)
		else:
			all_cols = false
		for i: int in p.idx:
			idx.append(base + i)
	return {"verts": v, "norms": nr, "idx": idx, "colors": cols if all_cols else PackedColorArray()}


## Welds by position (dropping UV seams) and simplifies to about `target` triangles,
## with smooth normals. target <= 0 keeps the part as it is.
func _simplify(p: Dictionary, target: int, allow_cluster := true, weld_dist := 1e-6) -> Dictionary:
	if target <= 0 or _tris(p) <= target:
		if (p.norms as PackedVector3Array).size() != (p.verts as PackedVector3Array).size() or (p.norms as PackedVector3Array).has(Vector3.ZERO):
			p.norms = _normals(p.verts, p.idx)
		return p
	var weld := {}
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for i: int in p.idx:
		var q: Vector3 = (p.verts as PackedVector3Array)[i]
		var key := q.snapped(Vector3.ONE * weld_dist)
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
	if allow_cluster and ni.size() / 3 > target * 1.5:
		# Still far off (scans full of tiny holes): fall back to vertex clustering.
		var cl := _cluster(nv, ni, target)
		nv = cl[0]
		ni = cl[1]
	print("    simplified %d -> %d tris%s" % [_tris(p), ni.size() / 3, "" if lod.size() / 3 <= target * 1.5 else " (vertex clustering)"])
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
			var pc: PackedColorArray = p.get("colors", PackedColorArray())
			if pc.size() == (p.verts as PackedVector3Array).size():
				a[Mesh.ARRAY_COLOR] = pc   # baked shading for the glove shader (tools/blender/hand_gear.py)
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

## Modeled in tools/blender/skate_gear.py in game axes (toe +Z, origin under the middle of
## the runner) with the boot's shading baked into vertex colors: only copied over.
func _build_skate() -> void:
	var boot := _simplify(_merge(_parts(EQUIP + "skate.glb")), 0)
	var steel := _simplify(_merge(_parts(EQUIP + "skate_steel.glb")), 0)
	_save([boot, steel], "skate")


# --- Glove ---------------------------------------------------------------------

## The source is upright (fingers +Y, palm -Z, thumb -X: a right glove) with the fingers
## flat; they are bent toward the palm around the knuckle line so the glove grips the
## stick, and the glove is puffed up to hockey-glove bulk.
func _build_glove() -> void:
	if GLOVE == "blender":
		_save([_simplify(_merge(_parts(BLENDER_GLOVE)), 0)], "glove")
		_save([_simplify(_merge(_parts(BLENDER_CUFF)), 0)], "glove_cuff")
		return
	if GLOVE == "hockey":
		_build_hockey_glove()
		return
	var g: Dictionary = GLOVES.get(GLOVE, {})
	var p := _simplify(_merge(_parts(g.src)), g.tris, g.get("cluster", true), g.get("weld", 1e-6))
	var box := _bounds([p])
	var top := box.end.y
	var len := box.size.y
	var y_k: float = top - len * g.knuckle
	var x_thumb: float = box.get_center().x + box.size.x * g.thumb_x
	var finger_len := top - y_k
	var r: float = finger_len / g.curl
	# Mid-plane of the fingers (their z center).
	var zs := 0.0
	var n := 0
	for q: Vector3 in p.verts:
		if q.y > y_k and q.x > x_thumb:
			zs += q.z
			n += 1
	var z_m := zs / maxi(n, 1)
	var z_thumb: float = z_m - box.size.z * g.thumb_z
	var thumb_reach: float = g.get("thumb_reach", 9.0)   # the thumb tip ends this far up the fingers (fraction)
	var bend := func(q: Vector3) -> Vector3:
		if q.y <= y_k or (q.x <= x_thumb and q.z < z_thumb and q.y < y_k + finger_len * thumb_reach):
			return q
		var th := (q.y - y_k) / r
		var w := clampf(q.z - z_m, -r * 0.5, r * 0.45)   # armor plates on the back of the fingers would fling out
		return Vector3(q.x, y_k + (r + w) * sin(th), z_m - r + (r + w) * cos(th))
	var v: PackedVector3Array = p.verts
	for i in v.size():
		v[i] = bend.call(v[i])
	# The thumb swings in toward the palm (about the vertical axis at its root), so it
	# closes around the stick instead of sticking out to the side.
	var fold: float = g.get("thumb_fold", 0.0)
	if fold > 0.0:
		var x_edge := box.position.x
		for i in v.size():
			var q := v[i]
			if q.x >= x_thumb or q.y <= box.position.y + len * (1.0 - g.wrist):
				continue
			var t := clampf((x_thumb - q.x) / maxf(x_thumb - x_edge, 0.001), 0.0, 1.0)
			var a := -fold * t * t * (3.0 - 2.0 * t)
			var dx := q.x - x_thumb
			var dz := q.z - z_m
			v[i] = Vector3(x_thumb + dx * cos(a) + dz * sin(a), q.y, z_m - dx * sin(a) + dz * cos(a))
	p.verts = v
	var wrist := Vector3(box.get_center().x, top - len * g.wrist, box.get_center().z)
	var scale: float = g.length / len
	var puff: Vector3 = g.puff
	_map(p, func(q: Vector3) -> Vector3: return (q - wrist) * puff * scale, Basis.IDENTITY)
	p.norms = _normals(p.verts, p.idx)
	_save([p], "glove")


## A hockey glove built from padded tubes, already closed around the stick: a right
## glove, wrist at the origin, fingers up +Y curling toward the palm (-Z), back of the
## hand +Z, thumb on the -X side. The stick runs along X through (0, GRIP_UP, -GRIP_IN).
## Pieces: a flared cuff with a rolled rim, a padded backhand with two cross rolls and a
## big knuckle roll, four two-segment finger rolls wrapped around the shaft, and a thumb
## lying along it.
func _build_hockey_glove() -> void:
	var p := {"verts": PackedVector3Array(), "norms": PackedVector3Array(), "idx": PackedInt32Array()}
	var grip := Vector3(0, GRIP_UP, -GRIP_IN)
	# Cuff: an oval tube from the forearm up to the wrist, slightly flared, rim rolled.
	var cuff: Array = []
	var cr: Array = []
	for i in 6:
		var t := i / 5.0
		cuff.append(Vector3(0, lerpf(-0.07, 0.012, t), 0.0))
		cr.append(Vector2(lerpf(0.056, 0.05, t), lerpf(0.05, 0.043, t)))
	_tube(p, cuff, cr, Vector3.RIGHT, 18, false)
	var rim: Array = []
	var rr: Array = []
	for k in 25:
		var a := TAU * k / 24.0
		rim.append(Vector3(cos(a) * 0.056, -0.068, sin(a) * 0.05))
		rr.append(Vector2(0.008, 0.008))
	_tube(p, rim, rr, Vector3.UP, 8)
	# Backhand and palm: rounded blocks filling the hand, two padded rolls across the
	# back, the knuckle roll.
	_blob(p, Vector3(0.002, 0.038, 0.0), Vector3(0.052, 0.044, 0.036))
	_blob(p, Vector3(0.0, 0.03, -0.036), Vector3(0.047, 0.036, 0.026))
	for y in [0.02, 0.048]:
		_tube(p, [Vector3(-0.038, y, 0.031), Vector3(0.0, y, 0.037), Vector3(0.04, y, 0.031)],
				[Vector2(0.013, 0.013), Vector2(0.014, 0.014), Vector2(0.013, 0.013)], Vector3.UP, 10)
	_tube(p, [Vector3(-0.048, 0.074, 0.002), Vector3(0.0, 0.08, 0.008), Vector3(0.05, 0.074, 0.002)],
			[Vector2(0.018, 0.018), Vector2(0.02, 0.02), Vector2(0.017, 0.017)], Vector3.UP, 12)
	# Fingers: index (thumb side) to pinky, each an arc around the shaft, two pads long.
	var fingers := [[-0.033, 0.017, 3.6], [-0.011, 0.0175, 3.7], [0.012, 0.017, 3.6], [0.034, 0.015, 3.4]]
	for f: Array in fingers:
		var x: float = f[0]
		var rad: float = f[1]
		var r := 0.033
		var path: Array = []
		var rads: Array = []
		var n := 14
		for i in n + 1:
			var th: float = lerpf(0.25, f[2], float(i) / n)
			path.append(grip + Vector3(x, sin(th) * r, cos(th) * r))
			var bump := 1.0 + 0.1 * cos(float(i) / n * TAU * 2.0)   # two padded segments
			rads.append(Vector2(0.0118, rad) * bump)
		_tube(p, path, rads, Vector3.RIGHT, 10)
	# Thumb: from the base of the palm along the shaft's far side, tip over the index finger.
	_tube(p, [Vector3(-0.044, 0.012, -0.022), Vector3(-0.056, 0.03, -0.05), Vector3(-0.05, 0.04, -0.076), Vector3(-0.036, 0.044, -0.09)],
			[Vector2(0.016, 0.016), Vector2(0.016, 0.016), Vector2(0.014, 0.014), Vector2(0.012, 0.012)], Vector3.UP, 10)
	_save([p], "glove")


## Adds a tube along `path` (rings of `segs` points; `rad` per point: half-size along
## `ref` and across) with rounded end caps.
func _tube(p: Dictionary, path: Array, rad: Array, ref: Vector3, segs := 10, caps := true) -> void:
	var v: PackedVector3Array = p.verts
	var nr: PackedVector3Array = p.norms
	var idx: PackedInt32Array = p.idx
	var n := path.size()
	var base := v.size()
	var frames: Array = []
	for i in n:
		var t: Vector3 = ((path[mini(i + 1, n - 1)] as Vector3) - (path[maxi(i - 1, 0)] as Vector3)).normalized()
		var u := (ref - t * t.dot(ref))
		u = u.normalized() if u.length() > 1e-4 else t.cross(Vector3.FORWARD).normalized()
		var w := t.cross(u)
		frames.append([t, u, w])
		var r: Vector2 = rad[i]
		for k in segs:
			var a := TAU * k / segs
			v.append((path[i] as Vector3) + u * cos(a) * r.x + w * sin(a) * r.y)
			nr.append((u * cos(a) * r.y + w * sin(a) * r.x).normalized())
	for i in n - 1:
		for k in segs:
			var a := base + i * segs + k
			var b := base + i * segs + (k + 1) % segs
			var c := a + segs
			var d := b + segs
			idx.append_array([a, c, b, b, c, d])
	# Caps: a rounded dome on each end.
	for e in (2 if caps else 0):
		var i := 0 if e == 0 else n - 1
		var t: Vector3 = frames[i][0] * (-1.0 if e == 0 else 1.0)
		var r: Vector2 = rad[i]
		var tip := v.size()
		v.append((path[i] as Vector3) + t * minf(r.x, r.y) * 0.8)
		nr.append(t)
		for k in segs:
			var a := base + i * segs + k
			var b := base + i * segs + (k + 1) % segs
			idx.append_array([tip, a, b] if e == 1 else [tip, b, a])
	p.verts = v
	p.norms = nr
	p.idx = idx


## Adds an ellipsoid (semi-axes `r`) at `c`.
func _blob(p: Dictionary, c: Vector3, r: Vector3) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var base := (p.verts as PackedVector3Array).size()
	var v: PackedVector3Array = p.verts
	var nr: PackedVector3Array = p.norms
	var idx: PackedInt32Array = p.idx
	for q: Vector3 in arr[Mesh.ARRAY_VERTEX]:
		v.append(c + q * r)
		nr.append((q / r).normalized())
	for i: int in arr[Mesh.ARRAY_INDEX]:
		idx.append(base + i)
	p.verts = v
	p.norms = nr
	p.idx = idx


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
