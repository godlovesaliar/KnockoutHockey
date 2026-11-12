extends SceneTree
## Offline build step for characters. Run after adding or changing models or Mixamo clips:
##   godot --headless --path . -s res://tools/build_characters.gd
##
## For every body in BODIES:
##   * bones get the canonical Mixamo names without prefix (Hips, Spine2, LeftUpLeg…);
##     other rigs map onto them through the body's "map" (e.g. the CMU male rig)
##   * the whole body is rescaled to `height` meters with the feet on y = 0 (some exports
##     come out at 1/12 or ×10 scale)
##   * gear regions (jersey / trim / pants / gloves / skates; none = bare skin) are baked
##     into the vertices from the skin weights, so the same shaders fit every body
##   * the uniform is a separate skinned "Outfit_*" mesh: every covered triangle copied and
##     pushed out along its normal (thicker over pads), sharing the body's bones, so it
##     deforms with the body. The body keeps its skin texture (`skin_tex` / `skin_avg`
##     metas) and hides covered skin in its shader.
##   -> res://assets/characters/body_<name>.scn
##   * every clip under assets/animations (all subfolders) is retargeted from its own rest pose onto this
##     body's rest pose (A-pose vs T-pose, different bone rolls), with hip drift removed
##   -> res://assets/characters/anims_<name>.res

const ANIM_DIR := "res://assets/animations/"
const OUT_DIR := "res://assets/characters/"
const SKIP_ANIMS := ["Y Bot.fbx"]
const LOOPING := ["idle", "sitting", "clap", "cheering", "rallying", "fight", "carrying"]
## Clips that also get a left-right mirrored copy, named "<clip>_mirrored" (e.g. the
## Mixamo uppercut throws with the left hand; the clinch needs it from the right).
const MIRRORED := ["uppercut", "hook1"]
const MIN_MESH_VERTS := 500    ## drop tiny extra meshes (the eyeballs are kept as "Eyes" when the body has an eye texture)
## The outfit's CUSTOM0 / CUSTOM1 carry rest position / normal (see _shell).
const REST_TORSO := 0.6    ## the cloth's rest coordinates are scaled to this hips-to-neck length
const REST_FORMAT := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
const CLOTH_SMOOTH_PASSES := 10  ## how much the uniform layer drapes over muscle detail

## CMU-style rig (the male base): its three spine bones line up with Mixamo's three.
const CMU_MAP := {"LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2"}

const BODIES := [
	{"name": "ybot", "file": "res://assets/animations/Y Bot.fbx", "height": 1.80, "map": {}},
	{"name": "male", "file": "res://assets/player/Hombre_Base (1).fbx", "height": 1.84, "map": CMU_MAP,
		"skin": "res://assets/player/male_character_base_-_rigged_1.png", "flip_v": true,
		"eyes": "res://assets/player/male_character_base_-_rigged_0.png"},
	{"name": "female", "file": "res://assets/player/Mujer_Base.fbx", "height": 1.75, "map": {},
		"skin": "res://assets/player/female_character_base_-_rigged_0.png", "flip_v": true,
		"eyes": "res://assets/player/female_character_base_-_rigged_1.png"},
]

var _clips := []   ## [{name, anim, skel}] loaded once


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_load_clips()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("body="):
			only = a.substr(5)
	for spec: Dictionary in BODIES:
		if only != "" and spec.name != only:
			continue
		if not ResourceLoader.exists(spec.file):
			print("skip %s (missing %s)" % [spec.name, spec.file])
			continue
		var t0 := Time.get_ticks_msec()
		var skel := _build_body(spec)
		_build_library(spec, skel)
		print("  %s done in %.1fs" % [spec.name, (Time.get_ticks_msec() - t0) / 1000.0])
		skel.free()
	for c: Dictionary in _clips:
		if c.has("root"):
			(c.root as Node).free()
	quit()


static func strip_prefix(bone: String) -> String:
	if bone.begins_with("mixamorig"):
		var i := bone.find("_")
		var c := bone.find(":")
		var cut := i if i > 0 and (c < 0 or i < c) else c
		if cut > 0:
			return bone.substr(cut + 1)
	return bone


static func clip_name_for(file: String) -> String:
	var n := file.get_basename().to_lower()
	n = n.replace("(", "").replace(")", "").strip_edges()
	return n.replace(" ", "_")


# --- Clips -----------------------------------------------------------------------

func _load_clips() -> void:
	# Clips sit in use-based subfolders (fight/, hits/, bench/…); the folder never
	# changes the clip name, so file names must stay unique across folders.
	var files: Array[String] = []
	var dirs: Array[String] = [ANIM_DIR]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + sub + "/")
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".fbx") and not f in SKIP_ANIMS:
				files.append(dir + f)
	for path in files:
		var f := path.get_file()
		var root: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var clip := {"name": clip_name_for(f), "anim": ap.get_animation(ap.get_animation_list()[0]), "skel": sk, "root": root}
		_clips.append(clip)
		if clip.name in MIRRORED:
			var m := clip.duplicate()
			m.name = clip.name + "_mirrored"
			m.mirror = true
			m.erase("root")   # freed once, with the original
			_clips.append(m)
	print("clips: ", _clips.size())


## The bone on the other side of the body (LeftArm <-> RightArm); itself if centered.
static func mirror_bone(nm: String) -> String:
	if nm.begins_with("Left"):
		return "Right" + nm.substr(4)
	if nm.begins_with("Right"):
		return "Left" + nm.substr(5)
	return nm


# --- Body ------------------------------------------------------------------------

func _canonical(spec: Dictionary, raw: String) -> String:
	var n := strip_prefix(raw)
	var map: Dictionary = spec.map
	return map.get(n, n)


## Returns the new, normalized skeleton (not in a tree; caller frees it).
func _build_body(spec: Dictionary) -> Skeleton3D:
	var src: Node3D = (load(spec.file) as PackedScene).instantiate()
	var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	# Transform from the skeleton's space to the model root (some exports scale it ×10).
	var P := Transform3D.IDENTITY
	var n: Node = sk
	while n != src:
		P = (n as Node3D).transform * P
		n = n.get_parent()

	var meshes: Array[MeshInstance3D] = []
	var eyes: MeshInstance3D = null   # the small eyeball mesh, kept when the body has an eye texture
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= MIN_MESH_VERTS:
			meshes.append(mi)
		elif spec.has("eyes") and mi.name.to_lower().contains("low-poly"):
			eyes = mi

	# Height from the mesh itself (bones can stop short of the top of the head).
	var lo := INF
	var hi := -INF
	for mi in meshes:
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w := P * v
			lo = minf(lo, w.y)
			hi = maxf(hi, w.y)
	var k: float = spec.height / (hi - lo)
	var k_thick: float = spec.height / 1.8
	var off := Vector3(0, lo, 0)
	var to_new := func(p: Vector3) -> Vector3: return (P * p - off) * k

	# New skeleton: same hierarchy, canonical names, rest in meters.
	var out := Skeleton3D.new()
	out.name = "Skeleton3D"
	var count := sk.get_bone_count()
	var new_g: Array[Transform3D] = []
	var names: Array[String] = []
	for b in count:
		var g := P * sk.get_bone_global_rest(b)
		new_g.append(Transform3D(g.basis.orthonormalized(), (g.origin - off) * k))
		var cn := _canonical(spec, sk.get_bone_name(b))
		if cn in names:
			cn = "x_" + sk.get_bone_name(b)
		names.append(cn)
	for b in count:
		out.add_bone(names[b])
	for b in count:
		var p := sk.get_bone_parent(b)
		out.set_bone_parent(b, p)
		var local := new_g[b] if p < 0 else new_g[p].affine_inverse() * new_g[b]
		out.set_bone_rest(b, local)
		out.set_bone_pose(b, local)

	var root := Node3D.new()
	root.name = "Body"
	root.add_child(out)
	out.owner = root
	root.set_meta("height", float(spec.height))
	root.set_meta("body", spec.name)
	if spec.has("skin") and ResourceLoader.exists(spec.skin):
		root.set_meta("skin_tex", spec.skin)
		root.set_meta("skin_avg", _avg_linear((load(spec.skin) as Texture2D).get_image()))
	if eyes != null:
		root.set_meta("eye_tex", spec.eyes)

	var joints := {}  # rest joint positions the stripe coordinates are measured from
	for jn in ["Hips", "Neck", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		joints[jn] = new_g[names.find(jn)].origin
	# Modelled jersey (tools/blender/build_jersey.py), when there is one: it replaces the
	# torso and arms of the pushed-out shell below.
	var jersey := _jersey(spec, names, new_g, joints)
	if jersey != null:
		out.add_child(jersey)
		jersey.owner = root
		jersey.skeleton = NodePath("..")
		root.set_meta("jersey", true)
		# The goalie cut (room for a chest protector and arm pads), hidden: GoalieVisual
		# swaps it in for the skater's.
		var gj := _jersey(spec, names, new_g, joints, "_goalie", "Outfit_GoalieJersey")
		if gj != null:
			gj.visible = false
			out.add_child(gj)
			gj.owner = root
			gj.skeleton = NodePath("..")
	var all_meshes: Array[MeshInstance3D] = meshes.duplicate()
	if eyes != null:
		all_meshes.append(eyes)
	var boxes := {}   # gear anchor -> AABB of the vertices that belong to it
	for mi in all_meshes:
		var skin := mi.skin
		var new_skin := Skin.new()
		var bind_bone: Array[int] = []
		for i in skin.get_bind_count():
			var bn := skin.get_bind_name(i)
			var bi := sk.find_bone(bn) if bn != "" else skin.get_bind_bone(i)
			bind_bone.append(bi)
			new_skin.add_named_bind(names[bi], new_g[bi].affine_inverse())
		# Per mesh bone: how to swing it into a T-pose for the cloth's rest coordinates
		# (arms rotated about the shoulder joint to point straight out; everything else
		# stays), so patterns measured from them fit A-pose and T-pose bodies alike.
		var unpose: Array[Transform3D] = []
		for b in bind_bone.size():
			unpose.append(_unpose_for(names[bind_bone[b]] if bind_bone[b] >= 0 else "", joints))
		var mesh := ArrayMesh.new()
		var outfit := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			var nb := P.basis.orthonormalized()
			var colors := PackedColorArray()
			var uv2 := PackedVector2Array()
			var thick := PackedFloat32Array()
			var dom := PackedStringArray()   # each vertex's dominant bone (the shell re-measures its stripes)
			dom.resize(verts.size())
			colors.resize(verts.size())
			uv2.resize(verts.size())
			thick.resize(verts.size())
			for i in verts.size():
				verts[i] = to_new.call(verts[i])
				if norms.size() == verts.size():
					norms[i] = (nb * norms[i]).normalized()
				# Dominant bone decides the gear region.
				var best := 0
				var bw := -1.0
				for j in per:
					if weights[i * per + j] > bw:
						bw = weights[i * per + j]
						best = bones[i * per + j]
				var bi: int = bind_bone[best]
				var anchor := anchor_for(names[bi])
				if anchor != "":
					boxes[anchor] = (boxes[anchor] as AABB).expand(verts[i]) if boxes.has(anchor) else AABB(verts[i], Vector3.ZERO)
				var reg := region_of(names[bi], verts[i], joints)
				dom[i] = names[bi]
				colors[i] = reg[0]
				uv2[i] = reg[1]
				thick[i] = cloth_thickness(names[bi]) * k_thick
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TANGENT] = null
			# No hands: gloves, glove cuffs and the bare fight fists always cover them, and
			# the body's own fingers only ever showed through those (in replays, which don't
			# carry the rig's finger tricks). Gone from the skin and the uniform shell alike.
			_drop_hands(arr, dom)
			# The skin textures come from the glTF versions of these bodies; the FBX exports
			# store their texture coordinates upside down relative to them.
			if spec.get("flip_v", false) and arr[Mesh.ARRAY_TEX_UV] != null:
				var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				for i in uv.size():
					uv[i].y = 1.0 - uv[i].y
				arr[Mesh.ARRAY_TEX_UV] = uv
			arr[Mesh.ARRAY_TEX_UV2] = uv2
			var flags: int = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			# Under a modelled jersey only the skin seen through its openings is drawn: the
			# top of the chest and the base of the neck stay skin where nothing of the jersey
			# lies straight out from them (the collar's opening and V). Everywhere else they
			# are hidden like the rest of the torso, or a rolling shoulder pushes them out
			# through the tight yoke and back.
			var body_colors := colors
			var body_uv2 := uv2
			if jersey != null:
				body_colors = colors.duplicate()
				body_uv2 = uv2.duplicate()
				var grid := _vertex_grid(jersey.mesh)
				var collar_grid := _vertex_grid(jersey.mesh, true)
				var hid := 0
				var kept := 0
				for i in verts.size():
					var band: bool = (colors[i].r > 0.5 and uv2[i].y > JERSEY_SKIN_F) or dom[i].begins_with("Neck")
					if not band:
						continue
					# The front of the opening (the V, under the collar's front) stays skin even
					# under cloth: the jersey stands well off the chest there, and it's in view.
					var front: bool = norms.size() == verts.size() and norms[i].z > 0.2 and _near(collar_grid, verts[i], COLLAR_NEAR)
					if not front and norms.size() == verts.size() and _cloth_outward(grid, verts[i], norms[i]):
						body_colors[i] = Color(1, 0, 0, 0)   # torso, under the jersey: hidden
						body_uv2[i] = Vector2(0.0, 0.5)
						hid += 1
					else:
						kept += 1
						if colors[i].r > 0.5:
							body_colors[i] = Color(0, 0, 0, 0)   # seen through an opening: skin
				print("  skin under the collar: %d hidden, %d kept (openings)" % [hid, kept])
			arr[Mesh.ARRAY_COLOR] = body_colors
			arr[Mesh.ARRAY_TEX_UV2] = body_uv2
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
			arr[Mesh.ARRAY_COLOR] = colors
			arr[Mesh.ARRAY_TEX_UV2] = uv2
			var shell := _shell(arr, thick, per, dom, joints, unpose, jersey != null)
			if not shell.is_empty():
				outfit.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shell, [], {}, flags | REST_FORMAT)
		var o := MeshInstance3D.new()
		o.name = "Eyes" if mi == eyes else mi.name
		o.mesh = mesh
		o.skin = new_skin
		out.add_child(o)
		o.owner = root
		o.skeleton = NodePath("..")
		if outfit.get_surface_count() > 0:
			var oo := MeshInstance3D.new()
			oo.name = "Outfit_" + mi.name
			oo.mesh = outfit
			oo.skin = new_skin
			out.add_child(oo)
			oo.owner = root
			oo.skeleton = NodePath("..")

	# Mesh-based anchors for gear (head, chest, hips), so gear fits the body's shape even
	# when the skeleton sits off-center (the CMU rig runs along the back).
	for a: String in boxes:
		root.set_meta(a + "_box", boxes[a])
	var packed := PackedScene.new()
	packed.pack(root)
	var path := OUT_DIR + "body_%s.scn" % spec.name
	var err := ResourceSaver.save(packed, path)
	print("%s: %s  bones=%d  scale=%.3f  meshes=%d" % [path, error_string(err), count, k, meshes.size()])
	var keep := out.duplicate() as Skeleton3D
	for c in keep.get_children():
		keep.remove_child(c)
		c.free()
	src.free()
	root.free()
	return keep


## Whether a bone is part of a hand (the hand itself, the thumb or a finger).
static func is_hand_bone(bone: String) -> bool:
	var b := bone.trim_prefix("x_")
	return b.contains("Hand") or b.contains("Thumb") or b.contains("Finger") or b.contains("Index") 			or b.contains("Middle") or b.contains("Ring") or b.contains("Pinky")


## Removes every triangle with a corner on a hand (by each vertex's dominant bone, `dom`)
## from a surface's arrays. The forearm keeps its edge at the wrist, inside the cuff.
static func _drop_hands(arr: Array, dom: PackedStringArray) -> void:
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(dom.size())
		for i in dom.size():
			idx[i] = i
	var hand := PackedByteArray()
	hand.resize(dom.size())
	for i in dom.size():
		hand[i] = 1 if is_hand_bone(dom[i]) else 0
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if hand[idx[t]] == 0 and hand[idx[t + 1]] == 0 and hand[idx[t + 2]] == 0:
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	arr[Mesh.ARRAY_INDEX] = keep


static func anchor_for(bone: String) -> String:
	var b := bone.trim_prefix("x_")
	if b.begins_with("Head") or b == "Neck1":
		return "head"
	if b == "Spine2":
		return "chest"
	if b == "Hips":
		return "hips"
	return ""


## How far the uniform sits off the skin (meters for a 1.8 m body): pads under the
## shoulders, elbows, pants and shins make those parts bulkier.
static func cloth_thickness(bone: String) -> float:
	var b := bone.trim_prefix("x_")
	if b.contains("Hand") or b.contains("Thumb") or b.contains("Finger") or b.contains("Index") \
			or b.contains("Middle") or b.contains("Ring") or b.contains("Pinky"):
		return 0.012
	if b.contains("Toe") or b.ends_with("Foot"):
		return 0.012
	if b.ends_with("ForeArm"):
		return 0.024
	if b.ends_with("Arm"):
		return 0.022
	if b.ends_with("Shoulder") or b.begins_with("Spine2"):
		return 0.036
	if b.begins_with("Spine"):
		return 0.032
	if b == "Hips" or b.contains("HipJoint") or b.ends_with("UpLeg"):
		return 0.04
	if b.ends_with("Leg"):
		return 0.03
	return 0.02


## The uniform layer of one body surface: every triangle touching a covered vertex,
## pushed out along the normals. Bare-skin vertices on its edge take a neighbor's colors
## and a small offset, so the hems sit just off the skin.
func _shell(arr: Array, thick: PackedFloat32Array, per: int, dom: PackedStringArray, joints: Dictionary, unpose: Array[Transform3D], has_jersey := false) -> Array:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var cov := PackedByteArray()
	cov.resize(verts.size())
	for i in verts.size():
		var c := colors[i]
		cov[i] = 1 if c.r + c.g + c.b + c.a + uv2[i].x > 0.01 else 0
	var remap := {}
	var src := PackedInt32Array()       # new vertex -> old vertex
	var col_from := PackedInt32Array()  # new vertex -> old vertex its colors come from
	var ni := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var any := -1
		for kk in 3:
			if cov[idx[t + kk]] == 1:
				any = idx[t + kk]
		if any < 0:
			continue
		if has_jersey and _under_jersey(colors, uv2, idx[t], idx[t + 1], idx[t + 2]):
			continue
		for kk in 3:
			var o := idx[t + kk]
			var j: int = remap.get(o, -1)
			if j < 0:
				j = src.size()
				remap[o] = j
				src.append(o)
				col_from.append(o if cov[o] == 1 else any)
			ni.append(j)
	if ni.is_empty():
		return []
	# Smooth the cloth so it drapes over the muscles instead of hugging them. Vertices
	# split at UV seams are welded first so the seams don't open.
	var group := PackedInt32Array()
	var gpos := PackedVector3Array()
	var gfix := PackedByteArray()
	var by_pos := {}
	for j in src.size():
		var key := verts[src[j]].snapped(Vector3.ONE * 1e-5)
		var g: int = by_pos.get(key, -1)
		if g < 0:
			g = gpos.size()
			by_pos[key] = g
			gpos.append(verts[src[j]])
			gfix.append(0)
		group.append(g)
		if cov[src[j]] == 0:
			gfix[g] = 1   # hems stay on the skin line
	var nbr: Array[PackedInt32Array] = []
	nbr.resize(gpos.size())
	for t in range(0, ni.size(), 3):
		for kk in 3:
			var a := group[ni[t + kk]]
			var b := group[ni[t + (kk + 1) % 3]]
			if not nbr[a].has(b):
				nbr[a].append(b)
			if not nbr[b].has(a):
				nbr[b].append(a)
	for pass_i in CLOTH_SMOOTH_PASSES:
		var next := gpos.duplicate()
		for g in gpos.size():
			if gfix[g] == 1 or nbr[g].is_empty():
				continue
			var avg := Vector3.ZERO
			for h in nbr[g]:
				avg += gpos[h]
			next[g] = gpos[g].lerp(avg / nbr[g].size(), 0.5)
		gpos = next
	# Normals of the smoothed cloth (the body's normals would still light the muscles),
	# kept on the same side as the body's.
	var gn := PackedVector3Array()
	var gref := PackedVector3Array()
	gn.resize(gpos.size())
	gref.resize(gpos.size())
	for j in src.size():
		gref[group[j]] += norms[src[j]]
	for t in range(0, ni.size(), 3):
		var a := group[ni[t]]
		var b := group[ni[t + 1]]
		var c := group[ni[t + 2]]
		var fn := (gpos[b] - gpos[a]).cross(gpos[c] - gpos[a])
		gn[a] += fn
		gn[b] += fn
		gn[c] += fn
	for g in gn.size():
		var n := gn[g].normalized() if gn[g].length_squared() > 1e-20 else gref[g].normalized()
		gn[g] = -n if n.dot(gref[g]) < 0.0 else n
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nc := PackedColorArray()
	var nu2 := PackedVector2Array()
	var nb := PackedInt32Array()
	var nw := PackedFloat32Array()
	for j in src.size():
		var o := src[j]
		var d := thick[o] if cov[o] == 1 else 0.006
		nv.append(gpos[group[j]] + gn[group[j]] * d)
		nn.append(gn[group[j]])
		nc.append(colors[col_from[j]])
		# Position along the part, measured again on the smoothed cloth: smoothing slides
		# vertices along the limbs, and positions from the body would make stripe edges
		# step from one ring of triangles to the next.
		var u := uv2[col_from[j]]
		u.y = (region_of(dom[col_from[j]], gpos[group[j]], joints)[1] as Vector2).y
		if has_jersey and nc[j].r > 0.5:
			u.y = minf(u.y, JERSEY_HEM_F - 0.02)   # only pants left on the shell's torso
		nu2.append(u)
		for q in per:
			nb.append(bones[o * per + q])
			nw.append(weights[o * per + q])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_COLOR] = nc
	out[Mesh.ARRAY_TEX_UV2] = nu2
	out[Mesh.ARRAY_BONES] = nb
	out[Mesh.ARRAY_WEIGHTS] = nw
	out[Mesh.ARRAY_INDEX] = ni
	var rest := _rest_attrs(nv, nn, nb, nw, per, unpose, joints)
	out[Mesh.ARRAY_CUSTOM0] = rest[0]
	out[Mesh.ARRAY_CUSTOM1] = rest[1]
	return out


## A shell triangle the modelled jersey hides: any corner on an arm, or on the torso
## above the hips joint (the jersey's hem hangs well below that, so the pants' top edge
## stays covered). What's left of the shell's torso is all pants (see _shell).
static func _under_jersey(colors: PackedColorArray, uv2: PackedVector2Array, a: int, b: int, c: int) -> bool:
	for i in [a, b, c]:
		if colors[i].g > 0.5:
			return true
		if colors[i].r > 0.5 and uv2[i].y > 0.0:
			return true
	return false


## Arms swung out to a T-pose about the shoulder joint, for vertices skinned to `bone`
## (identity for everything else). See _rest_attrs.
static func _unpose_for(bone: String, joints: Dictionary) -> Transform3D:
	for side in ["Left", "Right"]:
		if bone.begins_with(side) and not bone.ends_with("Shoulder") and (bone.contains("Arm") or bone.contains("Hand")):
			var sh: Vector3 = joints[side + "Arm"]
			var dir: Vector3 = ((joints[side + "ForeArm"] as Vector3) - sh).normalized()
			var rot := Basis(Quaternion(dir, Vector3(signf(dir.x), 0, 0)))
			return Transform3D(rot, sh - rot * sh)
	return Transform3D.IDENTITY


## Rest-pose position and normal (CUSTOM0 / CUSTOM1) for the uniform shader's fabric
## detail: patterns pinned to the cloth, so they don't swim when the body moves. Arms
## swung out to a T-pose (blended by the skin weights, so it stays smooth), origin at the
## base of the neck, scaled to a REST_TORSO-long torso: the same pattern sizes and yoke
## shape fit every body.
static func _rest_attrs(nv: PackedVector3Array, nn: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, unpose: Array[Transform3D], joints: Dictionary) -> Array:
	var rest_p := PackedFloat32Array()
	var rest_n := PackedFloat32Array()
	var neck: Vector3 = joints.Neck
	var k := REST_TORSO / maxf(neck.y - (joints.Hips as Vector3).y, 0.01)
	for j in nv.size():
		var tp := Vector3.ZERO
		var tn := Vector3.ZERO
		var wsum := 0.0
		for q in per:
			var w := weights[j * per + q]
			if w <= 0.0:
				continue
			var xf := unpose[bones[j * per + q]]
			tp += (xf * nv[j]) * w
			tn += (xf.basis * nn[j]) * w
			wsum += w
		if wsum <= 0.0:
			tp = nv[j]
			tn = nn[j]
		else:
			tp /= wsum
		var r := (tp - neck) * k
		tn = tn.normalized()
		rest_p.append_array([r.x, r.y, r.z])
		rest_n.append_array([tn.x, tn.y, tn.z])
	return [rest_p, rest_n]


## Position along an arm (0 shoulder .. 1 wrist) from the nearer of its two segments.
static func _arm_f(v: Vector3, side: String, j: Dictionary) -> float:
	var a: Vector3 = j[side + "Arm"]
	var b: Vector3 = j[side + "ForeArm"]
	var c: Vector3 = j[side + "Hand"]
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var t1 := clampf((v - a).dot(b - a) / (l1 * l1), 0.0, 1.0)
	var t2 := clampf((v - b).dot(c - b) / (l2 * l2), 0.0, 1.2)
	var d1 := v.distance_to(a.lerp(b, t1))
	var d2 := v.distance_to(b.lerp(c, t2))
	return (l1 + t2 * l2) / (l1 + l2) if d2 < d1 else t1 * l1 / (l1 + l2)


## Torso position the jersey's hem is drawn at: just above the shader's pants_top, so the
## hem stripe (hem_band) sits along the real hem and nothing of the jersey reads as pants.
const JERSEY_HEM_F := 0.172
## Above this the jersey keeps the body's own torso positions (the yoke, the collar).
const JERSEY_KEEP_F := 0.45
## Body skin above this torso position stays drawn under a modelled jersey (the collar).
const JERSEY_SKIN_F := 0.82
const CLOTH_CELL := 0.02        ## m: grid cell for the jersey's vertices (_vertex_grid)
const CLOTH_REACH := 0.07       ## m: how far out from the skin the jersey is looked for
const NECK_STIFF_IN := 0.02     ## m from the collar: cloth fully on the upper chest...
const NECK_STIFF_OUT := 0.09    ## ...fading back to its own weights by here
const COLLAR_NEAR := 0.04       ## m: skin facing forward this close to the collar stays (the V)
const CLOTH_NEAR := 0.012       ## m: a jersey vertex this close to that line covers the skin


## The modelled jersey's body cloth (not its collar or laces, UV2.x -1; or with `collar`,
## only those) hashed into CLOTH_CELL cubes: Vector3i -> PackedVector3Array.
static func _vertex_grid(m: Mesh, collar := false) -> Dictionary:
	var grid := {}
	for s in m.get_surface_count():
		var arrs := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var u2: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV2] if arrs[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		for k in vs.size():
			if u2.size() == vs.size() and (u2[k].x < -0.5) != collar:
				continue   # cloth or collar / laces, whichever was asked for
			var v := vs[k]
			var c := Vector3i((v / CLOTH_CELL).floor())
			var cell: PackedVector3Array = grid.get(c, PackedVector3Array())
			cell.append(v)   # packed arrays are values: store it back
			grid[c] = cell
	return grid


## Is there a vertex in `grid` within `r` of `v`? (r up to CLOTH_CELL * 2)
static func _near(grid: Dictionary, v: Vector3, r: float) -> bool:
	var c := Vector3i((v / CLOTH_CELL).floor())
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for dz in range(-2, 3):
				var cell: Variant = grid.get(c + Vector3i(dx, dy, dz))
				if cell == null:
					continue
				for q: Vector3 in cell:
					if q.distance_squared_to(v) < r * r:
						return true
	return false


## Is there cloth (a vertex in `grid`) straight out from skin point `v` along `n`?
static func _cloth_outward(grid: Dictionary, v: Vector3, n: Vector3) -> bool:
	var t := CLOTH_CELL * 0.5
	while t <= CLOTH_REACH:
		var p := v + n * t
		var c := Vector3i((p / CLOTH_CELL).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var cell: Variant = grid.get(c + Vector3i(dx, dy, dz))
					if cell == null:
						continue
					for q: Vector3 in cell:
						if q.distance_squared_to(p) < CLOTH_NEAR * CLOTH_NEAR:
							return true
		t += CLOTH_CELL * 0.5
	return false


## The modelled jersey for this body, as an "Outfit_Jersey" skinned mesh on the new
## skeleton (null when there is none): positions as exported (meters, feet at 0, +Z
## forward, the same space as the body), regions and rest attributes baked like the shell.
func _jersey(spec: Dictionary, names: Array[String], new_g: Array[Transform3D], joints: Dictionary, variant := "", node_name := "Outfit_Jersey") -> MeshInstance3D:
	var path := "res://assets/characters/jersey_%s%s.glb" % [spec.name, variant]
	if not ResourceLoader.exists(path):
		return null
	var src: Node3D = (load(path) as PackedScene).instantiate()
	var gsk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = gsk.find_children("*", "MeshInstance3D", true, false)[0]
	# Both exports come from the same rig: their joints must line up, or the jersey was
	# built from a stale body.
	var to_root := Transform3D.IDENTITY
	var n: Node = gsk
	while n != src:
		to_root = (n as Node3D).transform * to_root
		n = n.get_parent()
	var worst := 0.0
	for jn in ["Hips", "Neck", "LeftHand", "RightHand"]:
		var gb := -1
		for b in gsk.get_bone_count():
			if _canonical(spec, gsk.get_bone_name(b)) == jn:
				gb = b
		if gb >= 0:
			worst = maxf(worst, (to_root * gsk.get_bone_global_rest(gb).origin).distance_to(joints[jn]))
	if worst > 0.02:
		push_error("%s: joints off by %.3f m from body_%s; re-run tools/blender/build_jersey.py" % [path, worst, spec.name])
		src.free()
		return null
	var skin := mi.skin
	var new_skin := Skin.new()
	var unpose: Array[Transform3D] = []
	var bind_names: Array[String] = []
	for i in skin.get_bind_count():
		var raw := skin.get_bind_name(i)
		if raw == "":
			raw = gsk.get_bone_name(skin.get_bind_bone(i))
		var cn := _canonical(spec, raw)
		var bi := names.find(cn)
		if bi < 0:
			push_error("%s: bone %s not in body_%s" % [path, raw, spec.name])
			src.free()
			return null
		bind_names.append(cn)
		new_skin.add_named_bind(cn, new_g[bi].affine_inverse())
		unpose.append(_unpose_for(cn, joints))
	var mesh_xf := to_root * gsk.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else to_root
	var outfit := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var parts: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var per := bones.size() / verts.size()
		for i in verts.size():
			verts[i] = mesh_xf * verts[i]
			norms[i] = (mesh_xf.basis * norms[i]).normalized()
		if not parts.is_empty():
			var bw := _stiff_neckline(verts, parts, bones, weights, per, bind_names.find("Spine2"))
			bones = bw[0]
			weights = bw[1]
		var colors := PackedColorArray()
		var uv2 := PackedVector2Array()
		colors.resize(verts.size())
		uv2.resize(verts.size())
		var reg := []
		var arm_end := {"Left": 0.01, "Right": 0.01}
		for i in verts.size():
			var best := 0
			var bw := -1.0
			for q in per:
				if weights[i * per + q] > bw:
					bw = weights[i * per + q]
					best = bones[i * per + q]
			var bn := bind_names[best]
			# Hands and head never own jersey vertices (the Blender side remaps them away);
			# the neck's collar belongs to the torso.
			if bn.begins_with("Neck") or bn.begins_with("Head"):
				bn = "Spine2"
			var r := region_of(bn, verts[i], joints)
			if (r[0] as Color).g > 0.5:
				# Along the sleeve by where the vertex is, not which bone holds it most:
				# loose cloth past the elbow can still be mostly upper arm, which would pin
				# it to the elbow and fray the sleeve stripe's edges.
				r[1] = Vector2(0, _arm_f(verts[i], "Left" if bn.begins_with("Left") else "Right", joints))
			reg.append(r)
			var c: Color = r[0]
			if c.g > 0.5:
				var side := "Left" if bn.begins_with("Left") else "Right"
				arm_end[side] = maxf(arm_end[side], (r[1] as Vector2).y)
		var f_hem := INF
		for i in verts.size():
			if (reg[i][0] as Color).r > 0.5:
				f_hem = minf(f_hem, (reg[i][1] as Vector2).y)
		for i in verts.size():
			var c: Color = reg[i][0]
			var u: Vector2 = reg[i][1]
			# Torso vs sleeve from the (smoothed) arm weights rather than the dominant
			# bone: a gradual blend over the shoulder instead of a zigzag along triangle edges.
			var w_arm := 0.0
			for q in per:
				var bn: String = bind_names[bones[i * per + q]]
				if bn.ends_with("Arm") or bn.ends_with("Hand"):
					w_arm += weights[i * per + q]
			var k := smoothstep(0.25, 0.75, w_arm)
			var side := "Left" if verts[i].x > 0.0 else "Right"
			var f_torso := (verts[i].y - (joints.Hips as Vector3).y) / ((joints.Neck as Vector3).y - (joints.Hips as Vector3).y)
			if f_torso < JERSEY_KEEP_F:
				f_torso = remap(f_torso, f_hem, JERSEY_KEEP_F, JERSEY_HEM_F, JERSEY_KEEP_F)
			var f_arm := minf(_arm_f(verts[i], side, joints) / arm_end[side], 1.0)
			c = Color(1.0 - k, k, 0, 0)
			u.y = f_arm if k > 0.5 else f_torso
			# UV2.x < 0 marks the modelled jersey (uniform_regions): -0.25 cloth, -1 collar
			# and laces (drawn in the trim color).
			u.x = -1.0 if not parts.is_empty() and parts[i].r > 0.25 else -0.25
			colors[i] = c
			uv2[i] = u
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = norms
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_BONES] = bones
		out[Mesh.ARRAY_WEIGHTS] = weights
		out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
		var rest := _rest_attrs(verts, norms, bones, weights, per, unpose, joints)
		out[Mesh.ARRAY_CUSTOM0] = rest[0]
		out[Mesh.ARRAY_CUSTOM1] = rest[1]
		var flags: int = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		outfit.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags | REST_FORMAT)
	src.free()
	var o := MeshInstance3D.new()
	o.name = node_name
	o.mesh = outfit
	o.skin = new_skin
	print("  jersey: %s (%d binds, joints within %.3f m)" % [path, new_skin.get_bind_count(), worst])
	return o


## The collar and laces (`parts`.r > 0.25) and the cloth round them ride the upper chest
## (`chest`, the Spine2 bind): fully at the collar, fading back to the jersey's own weights
## NECK_STIFF_OUT away. Weighted to the shoulders, the neckline spread wide and flat when
## the fight stance shrugs them up, laying the collar out over the shoulders (the body
## under the jersey isn't drawn, so the cloth there needn't follow the shoulders).
## Returns [bones, weights] (packed arrays are values: the caller's copies are untouched).
static func _stiff_neckline(verts: PackedVector3Array, parts: PackedColorArray, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, chest: int) -> Array:
	const CELL := 0.03
	if chest < 0:
		return [bones, weights]
	var grid := {}
	for i in verts.size():
		if parts[i].r <= 0.25:
			continue
		var c := Vector3i((verts[i] / CELL).floor())
		var cell: PackedInt32Array = grid.get(c, PackedInt32Array())
		cell.append(i)   # packed arrays are values: store it back
		grid[c] = cell
	var reach := ceili(NECK_STIFF_OUT / CELL)
	for i in verts.size():
		var d := 0.0
		if parts[i].r <= 0.25:
			var c := Vector3i((verts[i] / CELL).floor())
			var bd := INF
			for dx in range(-reach, reach + 1):
				for dy in range(-reach, reach + 1):
					for dz in range(-reach, reach + 1):
						var cell: Variant = grid.get(c + Vector3i(dx, dy, dz))
						if cell == null:
							continue
						for j: int in cell:
							bd = minf(bd, verts[j].distance_squared_to(verts[i]))
			d = sqrt(bd)
		var k := 1.0 - smoothstep(NECK_STIFF_IN, NECK_STIFF_OUT, d)
		if k <= 0.0:
			continue
		# Blend toward all-chest: scale the others down, the chest slot up (taking the
		# weakest slot if the chest isn't among them).
		var slot := -1
		var weakest := 0
		for q in per:
			if bones[i * per + q] == chest:
				slot = q
			if weights[i * per + q] < weights[i * per + weakest]:
				weakest = q
		if slot < 0:
			slot = weakest
			bones[i * per + slot] = chest
			weights[i * per + slot] = 0.0
		var total := 0.0
		for q in per:
			weights[i * per + q] *= 1.0 - k
			if q == slot:
				weights[i * per + q] += k
			total += weights[i * per + q]
		for q in per:
			weights[i * per + q] /= maxf(total, 1e-5)
	return [bones, weights]


## Average color of a texture, in linear space (the skin shader divides by it).
static func _avg_linear(img: Image) -> Color:
	if img.is_compressed():
		img.decompress()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	var step := maxi(1, img.get_width() / 64)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var p := img.get_pixel(x, y)
			r += p.r
			g += p.g
			b += p.b
			n += 1
	return Color(r / n, g / n, b / n).srgb_to_linear()


## Which part of the body a vertex belongs to, and where it sits along that part, so
## the shaders can draw clean stripes and edges (scenes/actors/uniform_regions.gdshaderinc):
## COLOR = (torso, arm, leg, hand) and UV2.x = foot, one-hot from the dominant bone
## (all zero = bare skin: head and neck); UV2.y = position along the part: the torso by
## height (0 at the hips joint, 1 at the neck), limbs 0 at the shoulder / hip to 1 at the
## wrist / ankle, continuous across the elbow and knee.
static func region_of(bone: String, v: Vector3, j: Dictionary) -> Array:
	var b := bone.trim_prefix("x_")
	if b.contains("Hand") or b.contains("Thumb") or b.contains("Finger") or b.contains("Index") 			or b.contains("Middle") or b.contains("Ring") or b.contains("Pinky"):
		return [Color(0, 0, 0, 1), Vector2(0, 0)]
	if b.begins_with("Head") or b.begins_with("Neck"):
		return [Color(0, 0, 0, 0), Vector2(0, 0)]
	if b.contains("Toe") or b.ends_with("Foot"):
		return [Color(0, 0, 0, 0), Vector2(1, 0)]
	var side := "Left" if b.begins_with("Left") else "Right"
	if b.ends_with("Arm") or b.ends_with("Shoulder"):
		return [Color(0, 1, 0, 0), Vector2(0, _limb(v, j[side + "Arm"], j[side + "ForeArm"], j[side + "Hand"], b.ends_with("ForeArm"), false))]
	if b.ends_with("UpLeg") or b.ends_with("Leg"):
		return [Color(0, 0, 1, 0), Vector2(0, _limb(v, j[side + "UpLeg"], j[side + "Leg"], j[side + "Foot"], not b.ends_with("UpLeg"), false))]
	var hips: Vector3 = j.Hips
	var neck: Vector3 = j.Neck
	return [Color(1, 0, 0, 0), Vector2(0, (v.y - hips.y) / (neck.y - hips.y))]


## Position along a two-bone limb a -> b -> c, as a fraction of its length.
static func _limb(v: Vector3, a: Vector3, b: Vector3, c: Vector3, lower: bool, root: bool) -> float:
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if root:
		return 0.0
	if lower:
		var t2 := clampf((v - b).dot(c - b) / (l2 * l2), 0.0, 1.2)
		return (l1 + t2 * l2) / (l1 + l2)
	var t1 := clampf((v - a).dot(b - a) / (l1 * l1), 0.0, 1.0)
	return t1 * l1 / (l1 + l2)


# --- Animations ------------------------------------------------------------------

const ALIGN := {"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "RightUpLeg": "RightLeg", "RightLeg": "RightFoot"}


## Global rest rotations of `tgt` re-posed so its limbs point like `src`'s rest.
func _reference_pose(tgt: Skeleton3D, src: Skeleton3D) -> Array[Quaternion]:
	var s_pos := {}
	for b in src.get_bone_count():
		s_pos[strip_prefix(src.get_bone_name(b))] = src.get_bone_global_rest(b).origin
	var n := tgt.get_bone_count()
	var corr: Array[Quaternion] = []   # world rotation applied to each bone vs. its rest
	var out: Array[Quaternion] = []
	corr.resize(n)
	out.resize(n)
	for b in n:
		var p := tgt.get_bone_parent(b)
		var q := Quaternion.IDENTITY if p < 0 else corr[p]
		var nm := tgt.get_bone_name(b)
		if ALIGN.has(nm) and s_pos.has(nm) and s_pos.has(ALIGN[nm]) and tgt.find_bone(ALIGN[nm]) >= 0:
			var c := tgt.find_bone(ALIGN[nm])
			var have := q * (tgt.get_bone_global_rest(c).origin - tgt.get_bone_global_rest(b).origin).normalized()
			var want: Vector3 = ((s_pos[ALIGN[nm]] as Vector3) - (s_pos[nm] as Vector3)).normalized()
			if have.cross(want).length() > 1e-5:
				q = Quaternion(have, want) * q
		corr[b] = q
		out[b] = q * tgt.get_bone_global_rest(b).basis.get_rotation_quaternion()
	return out


func _build_library(spec: Dictionary, tgt: Skeleton3D) -> void:
	var lib := AnimationLibrary.new()
	var tcount := tgt.get_bone_count()
	var t_rest_g: Array[Quaternion] = []
	var t_rest_l: Array[Quaternion] = []
	for b in tcount:
		t_rest_g.append(tgt.get_bone_global_rest(b).basis.get_rotation_quaternion())
		t_rest_l.append(tgt.get_bone_rest(b).basis.get_rotation_quaternion())
	var t_hips := tgt.find_bone("Hips")
	var t_hips_rest := tgt.get_bone_global_rest(t_hips).origin
	# The target's pose matching the clips' rest (T-pose): limbs turned so each bone
	# points the same way as in the source rest. Retargeting goes through this pose, so
	# A-pose bodies get the same arm directions as the T-pose source.
	var t_ref := _reference_pose(tgt, _clips[0].skel)

	for c: Dictionary in _clips:
		var src: Skeleton3D = c.skel
		var a: Animation = c.anim
		var scount := src.get_bone_count()
		var s_names: Array[String] = []
		var s_rest_g: Array[Quaternion] = []
		var s_rest_l: Array[Quaternion] = []
		var s_index := {}
		for b in scount:
			var nm := strip_prefix(src.get_bone_name(b))
			s_names.append(nm)
			s_index[nm] = b
			s_rest_g.append(src.get_bone_global_rest(b).basis.get_rotation_quaternion())
			s_rest_l.append(src.get_bone_rest(b).basis.get_rotation_quaternion())
		var s_hips: int = s_index.get("Hips", 0)
		var ratio := t_hips_rest.y / maxf(src.get_bone_global_rest(s_hips).origin.y, 0.01)

		# Source tracks by bone.
		var rot_track := {}
		var pos_track := -1
		for t in a.get_track_count():
			var parts := str(a.track_get_path(t)).split(":")
			if parts.size() != 2 or not s_index.has(strip_prefix(parts[1])):
				continue
			var sb: int = s_index[strip_prefix(parts[1])]
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot_track[sb] = t
			elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and sb == s_hips:
				pos_track = t
		var times := PackedFloat32Array()
		var ref: int = rot_track.get(s_hips, rot_track.values()[0])
		for k in a.track_get_key_count(ref):
			times.append(a.track_get_key_time(ref, k))

		# Target tracks for every bone that exists in the source.
		var out := Animation.new()
		out.length = a.length
		var t_track := {}
		var mapped: Array[int] = []
		for b in tcount:
			var nm := tgt.get_bone_name(b)
			if s_index.has(nm):
				mapped.append(b)
				var tr := out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(tr, NodePath("Skeleton3D:" + nm))
				t_track[b] = tr
		var hips_tr := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_tr, NodePath("Skeleton3D:Hips"))

		var first := Vector3.ZERO
		var s_g: Array[Quaternion] = []
		s_g.resize(scount)
		var t_g: Array[Quaternion] = []
		t_g.resize(tcount)
		for ti in times.size():
			var time := times[ti]
			# Source globals.
			for b in scount:
				var ql: Quaternion = a.rotation_track_interpolate(rot_track[b], time) if rot_track.has(b) else s_rest_l[b]
				var p := src.get_bone_parent(b)
				s_g[b] = ql if p < 0 else s_g[p] * ql
			if c.get("mirror", false):
				# Each bone takes its opposite's change from rest, reflected across the
				# body's left-right (X) axis: (x, y, z, w) -> (x, -y, -z, w).
				var delta: Array[Quaternion] = []
				for b in scount:
					delta.append(s_g[b] * s_rest_g[b].inverse())
				for b in scount:
					var d: Quaternion = delta[s_index.get(mirror_bone(s_names[b]), b)]
					s_g[b] = Quaternion(d.x, -d.y, -d.z, d.w) * s_rest_g[b]
			# Target globals: same world-space change from rest as the source bone.
			for b in tcount:
				var p := tgt.get_bone_parent(b)
				var nm := tgt.get_bone_name(b)
				if s_index.has(nm):
					var sb: int = s_index[nm]
					t_g[b] = s_g[sb] * s_rest_g[sb].inverse() * t_ref[b]
				else:
					t_g[b] = t_rest_l[b] if p < 0 else t_g[p] * t_rest_l[b]
			for b in mapped:
				var p := tgt.get_bone_parent(b)
				var local := t_g[b] if p < 0 else t_g[p].inverse() * t_g[b]
				out.track_insert_key(t_track[b], time, local.normalized())
			# Hips height scaled to this body; sideways drift removed.
			var hp: Vector3 = a.position_track_interpolate(pos_track, time) if pos_track >= 0 else src.get_bone_rest(s_hips).origin
			if ti == 0:
				first = hp
			if c.get("mirror", false):
				hp.x = 2.0 * first.x - hp.x
			out.track_insert_key(hips_tr, time, Vector3(t_hips_rest.x + (hp.x - first.x) * ratio, hp.y * ratio, t_hips_rest.z + (hp.z - first.z) * ratio))
		for l in LOOPING:
			if (c.name as String).contains(l):
				out.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(c.name, out)
	var path := OUT_DIR + "anims_%s.res" % spec.name
	var err := ResourceSaver.save(lib, path)
	print("%s: %s  clips=%d" % [path, error_string(err), lib.get_animation_list().size()])
