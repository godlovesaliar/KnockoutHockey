extends RefCounted
## (Loaded by path where used: `const MeshLod := preload("res://scripts/core/mesh_lod.gd")`.)
## Automatic levels of detail for meshes built in code or by the project's tools (Godot
## only makes them on import, for .glb/.fbx files). Each mesh gets Godot's simplified
## copies, which the renderer swaps in by on-screen size while keeping the error under
## about a pixel (rendering/mesh_lod/lod_change/threshold_pixels), so it looks the same up
## close and costs far less far off and in shadow maps. Made once per mesh and shared.

const MIN_TRIS := 1500      ## smaller meshes aren't worth it

static var _done := {}      ## mesh instance ids already given LODs (or skipped)


## Adds LODs to `mesh` in place (in memory only: nothing is saved). The mesh stays the same
## resource, with its path, name and metas (the stick's "blade"/"shaft"), which code keys
## caches and placement on; only its surfaces are rebuilt with the extra index levels.
static func add_lods(mesh: Mesh) -> void:
	var am := mesh as ArrayMesh
	if am == null or _done.has(am.get_instance_id()):
		return
	_done[am.get_instance_id()] = true
	if am.get_faces().size() / 3 < MIN_TRIS:
		return
	# Blend shapes (the face, the body's build) carry over: the levels are only index
	# lists over the same vertices, which the shapes move.
	var shapes: Array[StringName] = []
	for b in am.get_blend_shape_count():
		shapes.append(am.get_blend_shape_name(b))
	var keep := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for sh in [Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT,
			Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT]:
		keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << sh
	var im := ImporterMesh.new()
	for nm in shapes:
		im.add_blend_shape(nm)
	im.set_blend_shape_mode(am.blend_shape_mode)
	var flags: Array[int] = []
	var mats: Array[Material] = []
	var names: Array[String] = []
	for s in am.get_surface_count():
		if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return
		# Keep the 8-weight skinning flag and the custom arrays' formats (shaders read them).
		flags.append(am.surface_get_format(s) & keep)
		mats.append(am.surface_get_material(s))
		names.append(am.surface_get_name(s))
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(s), am.surface_get_blend_shape_arrays(s), {}, mats[s], names[s], flags[s])
	im.generate_lods(25.0, 60.0, [])
	var aabb := am.custom_aabb
	am.clear_surfaces()
	for s in im.get_surface_count():
		var lods := {}
		for l in im.get_surface_lod_count(s):
			lods[im.get_surface_lod_size(s, l)] = im.get_surface_lod_indices(s, l)
		var bs := []
		for b in shapes.size():
			bs.append(im.get_surface_blend_shape_arrays(s, b))
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, im.get_surface_arrays(s), bs, lods, flags[s])
		am.surface_set_material(s, mats[s])
		am.surface_set_name(s, names[s])
	am.custom_aabb = aabb


## Adds LODs to the mesh of every MeshInstance3D under `root`.
static func apply(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			add_lods(mi.mesh)
