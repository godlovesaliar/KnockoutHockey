extends Node3D
## Looks around the arena (stands, roof, lights, scoreboard) from a fixed camera, with
## match lighting and no game. Command line (after --):
##   look=x,y,z,tx,ty,tz   camera position and target (default: center-ice, low)
##   fov=<deg>             lens (default 60)
##   excite=<0..1>         crowd excitement (fans stand and cheer)
##   goal=<0|1>            the screens flash GOAL for that team
##   home=<i> away=<i>     Teams.LIST indices (default 0, 1)
##   shot=<png> wait=<s>   save a screenshot after `wait` seconds and quit
##   noarena               the bare rink (for comparing stats)
##   stats                 print fps, draw calls and primitives with the shot

var _rink: Rink


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var match_scene: Node = (load("res://scenes/match/Match.tscn") as PackedScene).instantiate()
	var env: WorldEnvironment = match_scene.get_node("WorldEnvironment").duplicate()
	var sun: DirectionalLight3D = match_scene.get_node("Sun").duplicate()
	match_scene.free()
	add_child(env)
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	add_child(sun)
	_rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	_rink.build_arena = not args.has("noarena")
	add_child(_rink)
	var home := int(args.get("home", "0"))
	var away := int(args.get("away", "1"))
	_rink.set_bench_colors([MenuStyle.team_color(home), MenuStyle.team_color(away)])
	var logo := MenuStyle.team_logo(home)
	if logo:
		_rink.set_center_logo(logo)
	if _rink.arena:
		_rink.arena.set_teams(home, away)
		if args.has("excite"):
			_rink.arena.excite(float(args["excite"]), 9999.0)
		if args.has("goal"):
			_rink.arena.flash_team = int(args["goal"])
			_rink.arena.flash_until = INF
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "60"))
	cam.far = 400.0
	add_child(cam)
	var v := str(args.get("look", "0,2.2,24,0,12,0")).split_floats(",")
	cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	cam.current = true
	if args.has("shot"):
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		await get_tree().create_timer(float(args.get("wait", "2"))).timeout
		# GPU time averaged over a second of frames (fps is capped by v-sync).
		var gpu := 0.0
		var frames := 0
		var until := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			frames += 1
		get_viewport().get_texture().get_image().save_png(str(args["shot"]))
		if args.has("stats"):
			print("fps %d  gpu %.2f ms  draw calls %d  primitives %d" % [Engine.get_frames_per_second(), gpu / maxi(frames, 1),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()
