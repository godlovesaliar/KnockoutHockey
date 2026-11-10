extends SceneTree
## Writes each body's head (rest pose, skeleton space) and the current helmets as
## the game places them to OBJ files, for modeling new helmets in Blender.
##   godot --headless --path . -s res://tools/dump_heads.gd -- out=<dir>

const HELMETS := [
	{"mesh": "res://assets/characters/helmet.res", "fit": 1.18, "raise": 0.2, "back": 0.04},
	{"mesh": "res://assets/characters/helmet_b.res", "fit": 1.16, "raise": 0.2, "back": 0.04},
]


func _init() -> void:
	var out := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	for b in ["male", "female"]:
		var body: Node3D = (load("res://assets/characters/body_%s.scn" % b) as PackedScene).instantiate()
		var skel: Skeleton3D = body.get_node("Skeleton3D")
		var hs := float(body.get_meta("height", 1.8)) / 1.8
		var head: AABB = body.get_meta("head_box") if body.has_meta("head_box") else AABB()
		print(b, " hs ", hs, " head_box ", head)
		var f := FileAccess.open(out + "/head_%s.obj" % b, FileAccess.WRITE)
		var base := 1
		for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", false, false):
			if mi.name.begins_with("Outfit_"):
				continue
			base = _write(f, mi.name, mi.mesh, mi.transform, base, head.position.y - 0.14 * hs)
		for i in HELMETS.size():
			var spec: Dictionary = HELMETS[i]
			var m: Mesh = load(spec.mesh)
			var fit: float = head.size.x * spec.fit / m.get_aabb().size.x
			var at: Vector3 = head.get_center() + Vector3(0, head.size.y * spec.raise, -head.size.z * spec.back)
			base = _write(f, "helmet%d" % i, m, Transform3D(Basis.from_scale(Vector3.ONE * fit), at), base, -INF)
		f.close()
		body.free()
	quit()


func _write(f: FileAccess, name: String, m: Mesh, xf: Transform3D, base: int, min_y: float) -> int:
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		f.store_line("o %s_s%d" % [name, s])
		for q in v:
			var p := xf * q
			f.store_line("v %f %f %f" % [p.x, p.y, p.z])
		for t in range(0, idx.size(), 3):
			var ok := true
			for k in 3:
				if (xf * v[idx[t + k]]).y < min_y:
					ok = false
			if ok:
				f.store_line("f %d %d %d" % [base + idx[t], base + idx[t + 2], base + idx[t + 1]])
		base += v.size()
	return base
