extends Node3D
## Close-up character check (M5). Lines up skaters doing different things in front of a
## perspective camera.  `-- shot=<png> wait=<s> view=front|side|back|goalie`
##   1 standing   2 skating a circle   3 slap-shot windup   4 knocked down
##   5 celebrating (or `clip=<name>`; `fight=1`: gloves off, fists)   6 stickhandling the puck
##   + a goalie behind them
## Looks: `seed=<n>` reshuffles hair; `hair=<style>` / `facial=<beard|moustache|>` force one;
## Faces: `expr=` `talk=1` `lookcam=1` `lids=<0..1>` `eyes=<html>` (see FaceRig).
## Size: `sizes=<in>x<lb>,...` per skater (BodyBuild); `lineup=1 view=lineup` stands all six in a row.
## `nohelmet=1` takes helmets off (hair fit checks); `helmetoff=<s>` plays skater 4 taking it off; `pose=<id>` menu display poses; `gripdbg=1` draws the stick grip axes.

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

var rink: Rink
var puck: Puck
var cam: Camera3D
var skaters: Array[Skater] = []
var goalie: Goalie


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	add_child(sun)
	rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	add_child(rink)
	puck = (load("res://scenes/match/Puck.tscn") as PackedScene).instantiate()
	add_child(puck)

	var plans := [
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(s: Skater, i: SkaterIntent, t: float) -> void:
			i.move = Vector3(cos(t * 0.9), 0, -sin(t * 0.9)) if t > 0.2 else Vector3.ZERO
			i.turbo = t > 1.0,
		func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.shoot_down = t > 0.3 and t < 0.3 + 1.0 / 120.0
			i.shoot_held = t > 0.3,
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.move = Vector3(sin(t * 1.3) * 0.4, 0, -0.3) if t > 0.3 else Vector3.ZERO,
	]
	for k in plans.size():
		var s: Skater = SKATER_SCENE.instantiate()
		s.team = k % 2
		s.number = [19, 4, 88, 27, 11, 91][k]
		# Sample nameplates: plain, very long, a short nickname, accents, punctuation, short.
		s.last_name = ["Raposo", "Shellenberger", "Nickerson", "Côté", "Lindqvist", "Wu"][k]
		s.nickname = ["", "", "Bog", "", "TIMBER!", ""][k]
		_dress(s, int(_arg("home", "0")) if k % 2 == 0 else int(_arg("away", "2")))
		s.shoots_left = k % 3 == 0
		s.stats = PlayerStats.new()
		s.puck = puck
		s.rink = rink
		s.fatigue_enabled = false
		s.body_type = _arg("body", ["male", "female"][k % 2])
		# `sizes=<in>x<lb>,...`: each skater's height (inches) and weight (BodyBuild).
		var sizes := _arg("sizes", "").split(",", false)
		if k < sizes.size() and "x" in sizes[k]:
			s.height_m = int(sizes[k].get_slice("x", 0)) * 0.0254
			s.weight_kg = int(sizes[k].get_slice("x", 1)) * 0.4536
		s.skin_tone = SkaterVisual.SKIN_TONES[k % SkaterVisual.SKIN_TONES.size()]
		s.gear_style = int(_arg("style", str(k / 2)))
		s.visor = _arg("visor", str(k % 2 if k < 4 else 1)) != "0"   # `visor=0|1`; default: a mix
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_arg("seed", "3")) * 31 + k
		var look := SkaterVisual.random_look(rng, s.body_type, s.skin_tone)
		s.hair_style = _arg("hair", look.hair_style)
		s.facial_hair = _arg("facial", look.facial_hair)
		s.hair_color = look.hair_color
		s.eye_color = Color.html(_arg("eyes", look.eye_color.to_html()))
		add_child(s)
		# `lineup=1`: all six standing side by side, doing nothing (size comparisons).
		var lineup := _arg("lineup", "") != ""
		s.brain = ScriptBrain.new(plans[0] if lineup else plans[k])
		s.place(Vector3(-2.75 + k * 1.1, 0, 2.0) if lineup else Vector3(-5.0 + k * 2.0, 0, 2.0), Vector3.BACK)
		skaters.append(s)
	for s in skaters:
		s.teammates = skaters
	goalie = GOALIE_SCENE.instantiate()
	goalie.team = 1
	goalie.number = 31
	goalie.last_name = "Bouchard"
	goalie.nickname = "The Abyss"   # too long for the back: the last name goes on
	_dress(goalie, int(_arg("away", "2")))
	goalie.stats = PlayerStats.new()
	goalie.body_type = _arg("body", "female")
	goalie.gear_style = int(_arg("style", "0"))
	goalie.skin_tone = SkaterVisual.SKIN_TONES[int(_arg("gskin", "1")) % SkaterVisual.SKIN_TONES.size()]
	var grng := RandomNumberGenerator.new()
	grng.seed = int(_arg("seed", "3")) * 31 + 99
	var glook := SkaterVisual.random_look(grng, goalie.body_type, goalie.skin_tone)
	goalie.hair_style = _arg("hair", glook.hair_style)
	goalie.facial_hair = _arg("facial", glook.facial_hair)
	goalie.hair_color = glook.hair_color
	goalie.eye_color = Color.html(_arg("eyes", glook.eye_color.to_html()))
	goalie.puck = puck
	goalie.rink = rink
	add_child(goalie)

	# Give the windup and stickhandling skaters a puck each (only one puck: the windup one).
	puck.place(skaters[2].puck_anchor())
	puck.attach(skaters[2])

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	_set_view(_arg("view", "front"))
	_run()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _set_view(v: String) -> void:
	match v:
		"side":
			cam.look_at_from_position(Vector3(8, 1.6, 2.5), Vector3(0, 0.9, 2.0))
		"back":
			cam.look_at_from_position(Vector3(0, 1.8, -7.5), Vector3(0, 0.9, 2.0))
		"goalie":
			cam.look_at_from_position(Vector3(0, 1.4, 22.0), Vector3(0, 0.7, net_z()))
		"lineup":
			cam.look_at_from_position(Vector3(0, 1.25, 8.2), Vector3(0, 1.0, 2.0))
		"top":
			cam.look_at_from_position(Vector3(0, 18, 12), Vector3(0, 0, 2.0))
		_:
			cam.look_at_from_position(Vector3(0, 1.7, 10.5), Vector3(0, 0.9, 2.0))


func _process(_delta: float) -> void:
	if goalie and goalie.net:
		match _arg("save", ""):
			"glove":
				goalie.save_point = Vector2(0.6, 1.1)
				goalie.save_anim = 1.0
			"blocker":
				goalie.save_point = Vector2(-0.6, 0.9)
				goalie.save_anim = 1.0
			"butterfly":
				goalie.butterfly = true

	_grip_debug()
	if _arg("helmhair", "") != "":   # the helmet shell hidden, the hair under it left as is
		for s in skaters:
			var h: Node3D = s.visual.find_child("Helmet", true, false)
			if h:
				h.visible = false
	if _arg("nohelmet", "") != "":
		for s in skaters:
			if s.visual.helmet_on():
				s.visual.set_helmet(false)
	var f := int(_arg("focus", "-1"))
	if f < 0 or cam == null:
		return
	var s: Skater = goalie if f >= skaters.size() else skaters[f]
	var p := s.visual.global_position
	# `view=face|face_side|face_back|face_quarter`: squared up to the head bone itself
	# (the stance leans the head forward, so body-relative views look up at the face).
	if _arg("view", "").begins_with("face"):
		var helm: Node3D = s.visual.find_child("Helmet", true, false)
		var hb := helm.global_transform.basis.orthonormalized()
		var mid := helm.global_position - hb.y * float(_arg("face_drop", "0.04"))
		var dir := hb.z
		match _arg("view", ""):
			"face_side": dir = hb.x
			"face_back": dir = -hb.z
			"face_quarter": dir = (hb.z + hb.x).normalized()
		cam.fov = 30.0
		cam.look_at_from_position(mid + dir * float(_arg("dist", "0.8")), mid, hb.y)
		return
	# `view=glove|glove_r` (`glove_side=<k>` turns around it): close-up of a glove.
	if _arg("view", "").begins_with("glove"):
		var gl: Node3D = s.visual._gloves[1 if _arg("view", "") == "glove_r" else 0]
		var at := gl.global_transform * (gl as MeshInstance3D).get_aabb().get_center()
		var around := float(_arg("glove_side", "0.6"))
		var dir := (s.heading.rotated(Vector3.UP, around) + Vector3(0, 0.45, 0)).normalized()
		cam.fov = 30.0
		cam.look_at_from_position(at + dir * float(_arg("dist", "0.5")), at)
		return
	var off := Vector3(3.6, 1.2, 0.0)
	match _arg("view", "side"):
		"front":
			off = s.heading * 3.6 + Vector3(0, 1.0, 0)
		"back":
			off = -s.heading * 3.6 + Vector3(0, 1.4, 0)
		"high_back":
			off = -s.heading * 3.0 + Vector3(0, 6.0, 0)
		"quarter":
			off = (s.heading + s.right_dir()).normalized() * 3.6 + Vector3(0, 1.3, 0)
		_:
			off = s.right_dir() * 3.6 + Vector3(0, 1.0, 0)
	var look := p + Vector3(0, float(_arg("look_y", "0.85")), 0)
	off *= float(_arg("zoom", "1"))
	cam.look_at_from_position(look + off - Vector3(0, 0.85, 0) * (1.0 - float(_arg("zoom", "1"))), look)


var _dbg: Array[MeshInstance3D] = []


## `gripdbg=1`: each hand's grip point (white) and its glove's knuckle line (red),
## finger direction (green) and palm direction (blue), 10 cm each.
func _grip_debug() -> void:
	if _arg("gripdbg", "") == "" or skaters.is_empty():
		return
	var v: SkaterVisual = skaters[int(_arg("focus", "0"))].visual
	if _dbg.is_empty():
		for i in 8:
			var mi := MeshInstance3D.new()
			mi.mesh = ImmediateMesh.new()
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.no_depth_test = true
			mi.material_override = m
			add_child(mi)
			_dbg.append(mi)
	var sk := v.skel.global_transform
	if _arg("handdbg", "") != "" and not v.rig.modification_processed.is_connected(_hand_debug):
		v.rig.modification_processed.connect(_hand_debug.bind(v))
	var im := _dbg[0].mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in 2:
		var d: Array = v.rig.grip_debug[s]
		if d.is_empty():
			continue
		var g: Vector3 = sk * (d[0] as Vector3)
		for k in 3:
			im.surface_set_color([Color.RED, Color.GREEN, Color.BLUE][k])
			im.surface_add_vertex(g)
			im.surface_add_vertex(g + sk.basis * (d[k + 1] as Vector3) * 0.1)
		im.surface_set_color(Color.WHITE)
		for a in 3:
			var e := Vector3.ZERO
			e[a] = 0.02
			im.surface_add_vertex(g - e)
			im.surface_add_vertex(g + e)
	im.surface_end()


## `handdbg=1`: each glove's axes against its forearm, printed once a second (posed
## bones are only valid right after the rig runs).
func _hand_debug(v: SkaterVisual) -> void:
	if Engine.get_process_frames() % 60 != 0:
		return
	if _arg("posedump", "") != "":
		_pose_dump(v, _arg("posedump", ""))
	var sk := v.skel.global_transform
	if true:
		# Each glove's axes against its forearm, in the skater's frame (x right, y up, z ahead).
		var sx := v.skater.right_dir()
		var sz := v.skater.heading
		var fr := func(d: Vector3) -> String: return "(r %+.2f u %+.2f f %+.2f)" % [d.dot(sx), d.y, d.dot(sz)]
		for side in ["Left", "Right"]:
			var fore := sk * v.skel.get_bone_global_pose(v.skel.find_bone(side + "ForeArm")).origin
			var hand := sk * v.skel.get_bone_global_pose(v.skel.find_bone(side + "Hand")).origin
			var g: Node3D = v._gloves[0 if side == "Left" else 1]
			var gt := sk * v.skel.get_bone_global_pose(v.skel.find_bone(side + "Hand")) * g.transform
			print("%s fore->hand %s  glove fingers %s back %s thumb(-x) %s  glove origin - wrist %.3f m" % [side,
				fr.call((hand - fore).normalized()), fr.call(gt.basis.y.normalized()), fr.call(gt.basis.z.normalized()),
				fr.call(-gt.basis.x.normalized()), gt.origin.distance_to(hand)])
		# Each hand's grip point against the shaft line (top grip to blade).
		var blade := v.skel.global_transform.affine_inverse() * v.rig.blade_world
		var g0: Vector3 = v.rig.grip_debug[0][0] if not v.rig.grip_debug[0].is_empty() else Vector3.ZERO
		var g1: Vector3 = v.rig.grip_debug[1][0] if not v.rig.grip_debug[1].is_empty() else Vector3.ZERO
		var top := g0 if v.rig.stick_side > 0.0 else g1
		var axis := (blade - top).normalized()
		for gp: Vector3 in [g0, g1]:
			var d := gp - top
			print("  grip off shaft %.3f m, %.2f m down it" % [(d - axis * axis.dot(d)).length(), axis.dot(d)])
		# The bottom shoulder against the shaft: how close the line comes, and the arm.
		var bot := "Right" if v.rig.stick_side > 0.0 else "Left"
		var shp := v.skel.get_bone_global_pose(v.skel.find_bone(bot + "Arm")).origin
		var arm := shp.distance_to(v.skel.get_bone_global_pose(v.skel.find_bone(bot + "ForeArm")).origin) + v.skel.get_bone_global_pose(v.skel.find_bone(bot + "ForeArm")).origin.distance_to(v.skel.get_bone_global_pose(v.skel.find_bone(bot + "Hand")).origin)
		var ds := shp - top
		print("  dip %.3f  bottom short %.3f" % [v._dip, v.rig.bottom_short])
		print("  %s shoulder: height %.2f, nearest shaft %.3f m at %.2f m down it, arm %.3f m" % [bot, shp.y, (ds - axis * axis.dot(ds)).length(), axis.dot(ds), arm])


## `posedump=<json path>` (with gripdbg=1 handdbg=1): every bone's joint, both gloves'
## axes and the stick ends, in the skater's frame (meters, +X the character's left, +Y
## up from the ice, +Z ahead) - for copying the pose onto tools/blender/pose_rig.py.
func _pose_dump(v: SkaterVisual, path: String) -> void:
	var o := v.global_position
	var left := -v.skater.right_dir()
	var ahead := v.skater.heading
	var f := func(p: Vector3) -> Array:
		var d := p - o
		return [d.dot(left), d.y, d.dot(ahead)]
	var fd := func(d: Vector3) -> Array:
		return [d.dot(left), d.y, d.dot(ahead)]
	var sk := v.skel.global_transform
	var bones := {}
	for i in v.skel.get_bone_count():
		bones[v.skel.get_bone_name(i)] = f.call(sk * v.skel.get_bone_global_pose(i).origin)
	var gloves := {}
	for side in ["Left", "Right"]:
		var g: Node3D = v._gloves[0 if side == "Left" else 1]
		var gt := sk * v.skel.get_bone_global_pose(v.skel.find_bone(side + "Hand")) * g.transform
		gloves[side] = {"origin": f.call(gt.origin), "x": fd.call(gt.basis.x.normalized()),
			"y": fd.call(gt.basis.y.normalized()), "z": fd.call(gt.basis.z.normalized())}
	var data := {"bones": bones, "gloves": gloves, "stick_top": f.call(v.rig.stick_top_world),
		"blade": f.call(v.rig.blade_world), "height": float(v.body.get_meta("height", 1.8))}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))


func net_z() -> float:
	return goalie.net.global_position.z if goalie.net else 26.0


func _run() -> void:
	await get_tree().physics_frame
	goalie.net = rink.get_net(0)
	if goalie.has_method("reset_in_net"):
		goalie.reset_in_net()
	if _arg("gwalk", "") != "":
		# `gwalk=1`: the goalie skates a long loop at the period opener's pace, as when
		# coming out of the bench door (Skater.walk); `focus=6` follows it.
		var c := Vector3(0, 0, 8.0)
		var path := []
		for k in 13:
			var a := TAU * k / 12.0
			path.append(c + Vector3(sin(a) * 7.0, 0, -cos(a) * 4.0))
		goalie.place(path[0], Vector3.RIGHT)
		goalie.walk(path + path + path, 5.0, Vector3.BACK)
	await get_tree().create_timer(0.3).timeout
	if _arg("lineup", "") == "":
		skaters[3].visual.play_clip("knocked_down", Vector3.ONE, -1.0, 1.7, 0.08)
	# `rig.<property>=<number>` / `vis.<property>=<number>` tune every skater's rig or
	# visual (stance experiments).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("rig.") and a.contains("="):
			for sk in skaters:
				sk.visual.rig.set(a.substr(4, a.find("=") - 4), float(a.substr(a.find("=") + 1)))
		if a.begins_with("vis.") and a.contains("="):
			for sk in skaters:
				sk.visual.set(a.substr(4, a.find("=") - 4), float(a.substr(a.find("=") + 1)))
	if _arg("hide", "") != "":   # `hide=<node name pattern>`: hide parts of every skater (layer checks)
		for sk: Skater in skaters + [goalie]:
			for n: Node in sk.visual.find_children(_arg("hide", ""), "VisualInstance3D", true, false):
				(n as VisualInstance3D).visible = false
	# Faces: `expr=<FaceRig expression>`, `talk=1`, `lookcam=1` (eyes on the camera),
	# `lids=<0..1>` holds the eyelids, `eyes=<html color>` sets every eye color.
	for sk in skaters:
		var fc := sk.visual.face
		if fc == null:
			continue
		if _arg("expr", "") != "":
			fc.set_expression(_arg("expr", ""))
		if _arg("talk", "") != "":
			fc.talk(999.0)
		if _arg("lookcam", "") != "":
			fc.look_at_camera = true
		if _arg("lids", "") != "":
			fc.lid_override = float(_arg("lids", "0"))
	if _arg("pose", "") != "":   # `pose=side|middle|hips|across`: menu display poses
		for sk in skaters:
			sk.visual.display_pose = _arg("pose", "")
	if _arg("fight", "") != "":   # gloves off, fists (close-ups of the fight look)
		skaters[4].visual.set_fight_mode(true)
	if _arg("helmetoff", "") != "":   # `helmetoff=<s>`: skater 4 takes the helmet off after s
		get_tree().create_timer(float(_arg("helmetoff", "0"))).timeout.connect(skaters[4].visual.take_off_helmet)
	if _arg("clip", "") != "":   # `at=<s>`: one frame held (fight guards); `bow=<rad>`: SkaterRig.bow over it
		var held := _arg("at", "") != ""
		skaters[4].visual.play_clip(_arg("clip", ""), Vector3(float(_arg("legs", "0")), 1, 1), -1.0,
				0.0 if held else 1.0, 0.12, float(_arg("at", "0")))
		skaters[4].visual.rig.bow = float(_arg("bow", "0"))
	elif _arg("lineup", "") == "":
		skaters[4].visual.celebrate()
	var shot := _arg("shot", "")
	if shot != "":
		await get_tree().create_timer(float(_arg("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


## Team uniform and crest (Teams.LIST index), as MatchDirector dresses players.
func _dress(s: Skater, team: int) -> void:
	var info := Teams.team(team)
	s.uniform = Teams.uniform_vs(team, team, false)
	s.team_color = info.colors.jersey
	if ResourceLoader.exists(info.get("logo", "")):
		s.crest = load(info.logo)
