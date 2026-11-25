extends SceneTree
## Offline build step for hair and facial hair:
##   godot --headless --path . --import          (after a new hair.glb)
##   godot --headless --path . -s res://tools/build_hair.gd
##
## Source: assets/equip/hair.glb, the project's own hair, built in Blender by
## tools/blender/hair_gear.py: one mesh per style, body and fit, named
##   <id>                 a hairstyle or facial hair on the male head
##   <id>_female          ...on the female head
##   <id>_helm, <id>_female_helm   the hairstyle pressed under a helmet
## already in "head space": origin at the top of the head, centered, +Z toward the face,
## +Y up, one unit = the head's width (ear to ear). SkaterVisual scales it by the body's
## head width. Vertex colors carry the shading (dark volume, lighter locks), UVs the strand
## grain (assets/characters/hair/strands.png, written by the same script).
##   -> res://assets/characters/hair/<name>.res
## Meshes in the folder that the glb no longer has are removed.

const SRC := "res://assets/equip/hair.glb"
const OUT := "res://assets/characters/hair/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var root: Node3D = (load(SRC) as PackedScene).instantiate()
	var made := {}
	var tris := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xf * v[i]
			nr[i] = (xf.basis * nr[i]).normalized()
		var keep := []
		keep.resize(Mesh.ARRAY_MAX)
		keep[Mesh.ARRAY_VERTEX] = v
		keep[Mesh.ARRAY_NORMAL] = nr
		for k in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			keep[k] = arr[k]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, keep)
		var id := str(mi.name)
		ResourceSaver.save(mesh, OUT + id + ".res", ResourceSaver.FLAG_COMPRESS)
		made[id + ".res"] = true
		tris += mesh.get_faces().size() / 3
		print("%s: %d tris  size %s%s" % [id, mesh.get_faces().size() / 3, mesh.get_aabb().size,
				"" if arr[Mesh.ARRAY_COLOR] != null else "  (no vertex colors!)"])
	root.free()
	# Styles that are gone (and what the old outside models left behind).
	var dir := DirAccess.open(OUT)
	for f in dir.get_files():
		if f.ends_with(".res") and not made.has(f):
			dir.remove(f)
			print("removed ", f)
	print("%d meshes, %d tris" % [made.size(), tris])
	quit()
