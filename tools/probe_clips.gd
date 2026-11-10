extends SceneTree
## Temporary probe: per fight clip, where each hand goes (relative to the hips, in
## torso lengths) — the farthest-forward moment, its time, height and sideways offset.

var DIR := "res://assets/animations/fight/" + OS.get_environment("PROBE_SUB")

func _init() -> void:
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".fbx"):
			continue
		var root: Node3D = (load(DIR + f) as PackedScene).instantiate()
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var anim := ap.get_animation(ap.get_animation_list()[0])
		var n := sk.get_bone_count()
		var tracks := {}   # bone -> [pos track, rot track]
		for ti in anim.get_track_count():
			var b := sk.find_bone(String(anim.track_get_path(ti).get_subname(0)))
			if b < 0:
				continue
			if not tracks.has(b):
				tracks[b] = [-1, -1]
			if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
				tracks[b][0] = ti
			elif anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				tracks[b][1] = ti
		var idx := {}
		for want in ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot"]:
			for i in n:
				if sk.get_bone_name(i).ends_with("_" + want):
					idx[want] = i
		var rows := []
		var t := 0.0
		while t <= anim.length + 0.001:
			var g: Array[Transform3D] = []
			g.resize(n)
			for i in n:
				var rest := sk.get_bone_rest(i)
				var pos := rest.origin
				var rot := rest.basis.get_rotation_quaternion()
				if tracks.has(i):
					if tracks[i][0] >= 0:
						pos = anim.position_track_interpolate(tracks[i][0], t)
					if tracks[i][1] >= 0:
						rot = anim.rotation_track_interpolate(tracks[i][1], t)
				var local := Transform3D(Basis(rot), pos)
				var p := sk.get_bone_parent(i)
				g[i] = local if p < 0 else g[p] * local
			var hips: Transform3D = g[idx.Hips]
			# Measure in a frame that turns with the hips' yaw (fighters blade their stance).
			var fwd := hips.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			if OS.get_environment("PROBE_FIXED") != "":
				fwd = Vector3.BACK   # the model's own facing (+Z), not the hips'
			var right := Vector3.UP.cross(fwd)
			var u: float = (g[idx.Head].origin - hips.origin).length()
			var row := {"t": t, "hy": hips.origin.y, "hdy": g[idx.Head].origin.y, "hz": hips.origin.z, "hx": hips.origin.x, "fy": g[idx.LeftFoot].origin.y}
			for h in ["LeftHand", "RightHand"]:
				var d: Vector3 = g[idx[h]].origin - hips.origin
				row[h] = Vector3(d.dot(right) / u, d.y / u, d.dot(fwd) / u)
			rows.append(row)
			t += 1.0 / 30.0
		var out := "%-30s %.2fs" % [f.get_basename(), anim.length]
		for h in ["LeftHand", "RightHand"]:
			var best: Dictionary = rows[0]
			var lo := 99.0
			for r in rows:
				lo = minf(lo, r[h].z)
				if r[h].z > best[h].z:
					best = r
			var v: Vector3 = best[h]
			var lvl := "HEAD" if v.y > 0.8 else ("chest" if v.y > 0.45 else "BODY")
			out += "   %s: fwd %.2f->%.2f @%.2fs %s(y%.2f) x%+.2f" % [h[0], lo, v.z, best.t, lvl, v.y, v.x]
		print(out)
		if OS.get_environment("PROBE_BODY") in f and OS.get_environment("PROBE_BODY") != "":
			var h0: float = rows[0].hdy
			for k in range(0, rows.size(), 6):
				var r: Dictionary = rows[k]
				print("   %.2f  hips y %.2f  head y %.2f  (head %.0f%%)  hips x %+.2f z %+.2f" % [r.t, r.hy, r.hdy, r.hdy / h0 * 100.0, r.hx, r.hz])
		if OS.get_environment("PROBE") in f and OS.get_environment("PROBE") != "":
			for k in range(0, rows.size(), 3):
				var r: Dictionary = rows[k]
				print("   %.2f  L(x%+.2f y%.2f f%.2f)  R(x%+.2f y%.2f f%.2f)" % [r.t, r.LeftHand.x, r.LeftHand.y, r.LeftHand.z, r.RightHand.x, r.RightHand.y, r.RightHand.z])
		root.free()
	quit()
