extends Node3D
## Fans in plain clothes, close up (Fan, tools/build_fans.gd).
##   -- n=6 seed=1 pose=sit|stand mood=cheer|clap|groan|laugh|talk team=<i>
##      view=row|face|top|feet|back focus=<k> shot=<png> wait=<s> bones=1
##      clips=a,b,c at=<s>   fan k frozen in clip k, that far in (choosing idles)
## `team` dresses every other fan in that team's colors with its crest. `bones=1` prints
## the first fan's hand bones and which of them the idle clip moves.

var fans: Array[Fan] = []


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(155), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	floor_mi.material_override = MeshUtil.material(Color(0.3, 0.31, 0.33), 0.9)
	add_child(floor_mi)

	var n := int(args.get("n", "6"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.get("seed", "1"))
	var sitting := str(args.get("pose", "sit")) == "sit"
	var team := int(args.get("team", "-1"))
	var gap := 0.62
	for k in n:
		var look := Fan.random_look(rng)
		if team >= 0 and k % 2 == 0:
			var c: Dictionary = Teams.team(team).colors
			look = Fan.in_colors(look, c.jersey, c.trim, Teams.logo(team))
		var f := Fan.create(look)
		f.position = Vector3((k - (n - 1) * 0.5) * gap, 0.0, 0.0)
		f.rotation.y = PI      # toward the camera (+Z)
		add_child(f)
		if sitting:
			var seat := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.46, 0.42)
			seat.mesh = bm
			seat.material_override = MeshUtil.material(Color(0.18, 0.22, 0.34), 0.7)
			seat.position = f.position + Vector3(0, 0.23, -0.22)
			add_child(seat)
		else:
			f.stand()
		fans.append(f)
	if args.has("bones"):
		_print_bones(fans[0])

	var cam := Camera3D.new()
	add_child(cam)
	var focus := clampi(int(args.get("focus", str(n / 2))), 0, n - 1)
	var fx := fans[focus].position.x
	var eye_y := 1.22 if sitting else 1.68
	match str(args.get("view", "row")):
		"face":
			cam.fov = 20.0
			cam.look_at_from_position(Vector3(fx + 0.25, eye_y + 0.02, 1.6), Vector3(fx, eye_y - 0.03, 0.1))
		"top":
			cam.fov = 30.0
			cam.look_at_from_position(Vector3(fx + 0.5, eye_y, 2.4), Vector3(fx, eye_y - 0.3, 0.1))
		"feet":
			cam.fov = 30.0
			cam.look_at_from_position(Vector3(fx + 0.6, 0.5, 1.8), Vector3(fx, 0.2, 0.3))
		"back":
			cam.fov = 34.0
			cam.look_at_from_position(Vector3(0.8, 1.5, -4.0), Vector3(0, 0.85, 0))
		"one":
			cam.fov = 30.0
			cam.look_at_from_position(Vector3(fx + 1.0, 1.25, 3.4), Vector3(fx, 0.85 if not sitting else 0.7, 0.1))
		_:
			cam.fov = 34.0
			cam.look_at_from_position(Vector3(0.9, 1.5, 1.6 + n * 0.5), Vector3(0, 0.85 if not sitting else 0.72, 0))
	cam.make_current()

	if args.has("clips"):   # clips=a,b,c: fan k holds clip k (at=<s> into it)
		var names := str(args["clips"]).split(",")
		for k in fans.size():
			var cn := names[k % names.size()]
			if fans[k].anim.has_animation(cn):
				fans[k].anim.play(cn)
				fans[k].anim.seek(float(args.get("at", "1.0")), true)
				fans[k].anim.speed_scale = 0.0
			else:
				print("no clip ", cn)
	if args.has("mood"):
		await get_tree().create_timer(0.3).timeout
		for k in fans.size():
			fans[k].react(str(args["mood"]), k * 0.08)
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["shot"]))
		get_tree().quit()


func _print_bones(f: Fan) -> void:
	var moved := {}
	var clip := f.anim.get_animation("sitting")
	for t in clip.get_track_count():
		moved[String(clip.track_get_path(t).get_subname(0))] = true
	var names: Array[String] = []
	for b in f.skel.get_bone_count():
		var n := f.skel.get_bone_name(b)
		if n.contains("Hand") or n.contains("Thumb") or n.contains("Finger"):
			names.append(n + ("*" if moved.has(n) else ""))
	print("hand bones (* = the sitting clip moves it): ", ", ".join(names))
	print("clips: ", ", ".join(f.anim.get_animation_list()))
	await get_tree().create_timer(0.6).timeout
	for bn in ["Hips", "Head", "LeftLeg", "LeftFoot", "LeftHand"]:
		print("%s at %s" % [bn, f.global_transform.affine_inverse() * (f.skel.global_transform * f.skel.get_bone_global_pose(f.skel.find_bone(bn)).origin)])
