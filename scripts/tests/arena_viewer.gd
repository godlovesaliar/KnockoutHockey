extends Node3D
## Looks around the arena (stands, roof, lights, scoreboard) from a fixed camera, with
## match lighting and no game. Command line (after --):
##   look=x,y,z,tx,ty,tz   camera position and target (default: center-ice, low)
##   fov=<deg>             lens (default 60)
##   excite=<0..1>         crowd excitement (fans stand and cheer)
##   goal=<0|1>            the screens flash GOAL for that team
##   home=<i> away=<i>     Teams indices (default 0, 1)
##   arena=<id>            an arena (Arenas; default: the home team's)
##   time= snow= lights=   override those arena options (outdoor: day|dusk|night, none|light|heavy)
##   shot=<png> wait=<s>   save a screenshot after `wait` seconds and quit
##   wear=<0..1>           ice wear: that much of a period's skating on the sheet (IceWear.prewear)
##   zamboni=<0..1>        a Zamboni on the ice, that far through its pass (needs wear)
##   zcam=side|quarter|front|back|wide  the camera on its driver; zsteer=<rad> its front wheels turned
##                         that far (+ left); zsweep=<rad>: swinging between -zsweep and +zsweep
##   closeup=<side>,<z>[,<mood>]  a close-up into the stands with real people in the seats
##                         (Arena.show_close_fans): side 1 / -1, z along the rink, a Fan.MOODS key
##   warmfans              builds the close-up people and leaves them hidden (what they cost unseen)
##   nofans                with closeup: the same picture of the crowd's own fans (to compare costs)
##   fans=<n> reach=<m>    with closeup: that many people, in seats up to that far from the middle
##                         of the picture (default 40 within 5 m); `still`: none of them animate
##   noarena               the bare rink (for comparing stats)
##   stats                 print fps, draw calls and primitives with the shot
##   uncap                 no v-sync and no frame cap, so fps is what the machine can do

var _rink: Rink
var _zamboni: Zamboni
var _zsweep := 0.0
var _zt := 0.0


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
	var home := int(args.get("home", "0"))
	_rink.arena_spec = (Arenas.find(str(args["arena"])) if args.has("arena") else Arenas.home_of(home)).duplicate()
	for k: String in ["time", "snow", "lights"]:
		if args.has(k):
			_rink.arena_spec[k] = str(args[k])
	add_child(_rink)
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
	if args.has("wear") and _rink.wear:
		_rink.wear.prewear(float(args["wear"]))
		if args.has("zamboni"):
			var z := Zamboni.new()
			z.wear = _rink.wear
			_rink.add_child(z)
			z.set_trim(MenuStyle.team_color(home))
			z.set_logo(Teams.logo(home))
			if Fan.available():
				var rng := RandomNumberGenerator.new()
				rng.seed = int(args.get("seed", "2"))
				var c: Dictionary = Teams.team(home).colors
				z.set_driver(Fan.create(Fan.in_colors(Fan.random_look(rng), c.jersey, c.trim, Teams.logo(home))))
			_zamboni = z
			_rink.wear.begin_sweep()
			var to := z.length * clampf(float(args["zamboni"]), 0.0, 1.0)
			var d := 0.0
			while d < to:
				d = minf(d + 0.3, to)
				z.place(d, true)
			_rink.wear.upload()
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "60"))
	cam.far = 400.0
	add_child(cam)
	var v := str(args.get("look", "0,2.2,24,0,12,0")).split_floats(",")
	cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	cam.current = true
	if _zamboni != null:
		_zsweep = float(args.get("zsweep", "0"))
		if args.has("zsteer"):
			_steer_zamboni(float(args["zsteer"]))
		if args.has("zcam"):
			var views := {"side": [Vector3(-2.3, 2.3, 1.2), Vector3(-0.36, 1.9, 1.8), 34.0],
					"front": [Vector3(0.5, 2.9, -0.3), Vector3(-0.36, 1.95, 1.9), 34.0],
					"back": [Vector3(-1.0, 3.0, 3.5), Vector3(-0.36, 1.75, 1.5), 34.0],
					"quarter": [Vector3(-1.9, 2.7, 0.5), Vector3(-0.36, 1.85, 1.75), 34.0],
					"wide": [Vector3(-4.5, 2.4, -2.5), Vector3(0.0, 1.3, 0.8), 40.0]}
			var v2: Array = views.get(str(args["zcam"]), views.side)
			cam.fov = float(args.get("fov", str(v2[2])))
			cam.look_at_from_position(_zamboni.global_transform * (v2[0] as Vector3), _zamboni.global_transform * (v2[1] as Vector3))
	if args.has("warmfans") and _rink.arena:
		_rink.arena.warm_close_fans()
	if args.has("closeup") and _rink.arena:
		var cu := str(args["closeup"]).split(",")
		var seat: Variant = _rink.arena.close_up_seat(float(cu[0]), float(cu[1]) if cu.size() > 1 else 0.0)
		if seat != null:
			var st: Transform3D = seat
			var heads := st.origin + Vector3.UP * 1.1
			var lens := heads + st.basis.z.normalized() * 12.0 + Vector3.UP * 2.2
			if not args.has("nofans"):
				_rink.arena.close_count = int(args.get("fans", "40"))
				_rink.arena.close_reach = float(args.get("reach", "5"))
				var n: int = _rink.arena.show_close_fans(lens, heads, cu[2] if cu.size() > 2 else "")
				var total := 0
				for mm: MultiMesh in _rink.arena._fans:
					total += mm.instance_count
				print("close-up: %d people (of %d fans in the building)" % [n, total])
				if args.has("still"):
					for f: Fan in _rink.arena._close:
						f.anim.active = false
						f.set_process(false)
			if not args.has("look"):
				cam.fov = float(args.get("fov", "8"))
				cam.look_at_from_position(lens, heads)
	if args.has("uncap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if args.has("shot"):
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		await get_tree().create_timer(float(args.get("wait", "2"))).timeout
		# GPU time averaged over a second of frames (fps is capped by v-sync).
		var gpu := 0.0
		var cpu := 0.0
		var proc := 0.0
		var frames := 0
		var until := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			frames += 1
		get_viewport().get_texture().get_image().save_png(str(args["shot"]))
		if args.has("stats"):
			print("fps %d (%d frames in the second)  gpu %.2f ms  render cpu %.2f ms  process %.2f ms  draw calls %d  primitives %d" % [Engine.get_frames_per_second(),
					frames, gpu / maxi(frames, 1), cpu / maxi(frames, 1), proc / maxi(frames, 1),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()


func _steer_zamboni(steer: float) -> void:
	var fwd := -_zamboni.global_basis.z
	_zamboni.pose(Vector2(_zamboni.position.x, _zamboni.position.z), Vector2(fwd.x, fwd.z), 0.0, steer)


func _process(delta: float) -> void:
	if _zamboni != null and _zsweep > 0.0:
		_zt += delta
		_steer_zamboni(sin(_zt * 1.3) * _zsweep)
