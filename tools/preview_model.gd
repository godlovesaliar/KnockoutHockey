extends SceneTree
## Renders a model from the front (-Z camera looking +Z... see VIEWS), side and top with an
## orthographic camera, for checking orientation and parts of source or built assets.
##   godot --path . -s res://tools/preview_model.gd -- model=res://x.glb out=C:/tmp/x [surf=1]
## Writes <out>_front.png (camera on +Z looking back), <out>_side.png (camera on +X),
## <out>_top.png (camera above). Parts are tinted by index so they can be told apart.

const TINTS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.7, 0.25), Color(0.2, 0.35, 0.9), Color(0.9, 0.8, 0.2),
	Color(0.8, 0.3, 0.9), Color(0.2, 0.85, 0.85), Color(0.95, 0.55, 0.15), Color(0.6, 0.6, 0.6)]


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(0, i)] = a.substr(i + 1)
	var res = load(args.model)
	var holder := Node3D.new()
	root.add_child(holder)
	var part := 0
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		holder.add_child(mi)
		for s in (res as Mesh).get_surface_count():
			mi.set_surface_override_material(s, _mat(s))
	else:
		var inst: Node3D = (res as PackedScene).instantiate()
		holder.add_child(inst)
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _mat(part))
				part += 1
	await process_frame
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("aabb ", box)
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, 30, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.92, 0.92, 0.92)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var c := box.get_center()
	var r := box.size.length()
	cam.size = r * 1.05
	cam.far = r * 10.0
	for v in [["front", Vector3(0, 0, 1), Vector3.UP], ["side", Vector3(1, 0, 0), Vector3.UP], ["top", Vector3(0, 1, 0), Vector3.FORWARD]]:
		cam.look_at_from_position(c + (v[1] as Vector3) * r * 2.0, c, v[2])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%s.png" % [args.out, v[0]])
	quit()


func _mat(i: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TINTS[i % TINTS.size()]
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
