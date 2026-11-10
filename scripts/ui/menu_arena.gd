class_name MenuArena
## Shared pieces of the 3D scenes behind the front-end menus: the rink under hazy arena
## lights (with banks of lights blooming high up and ice dust in the air), players in
## a team's uniform, and team facts for the menus (star player, line ratings).

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const FORWARDS := ["C", "LW", "RW"]


## Builds the arena under `root`. `focus`: where the action is (lights and dust gather
## there). Returns {rink, puck}.
static func build(root: Node3D, focus: Vector3) -> Dictionary:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.12, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.86, 0.95)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.9
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.78, 0.88)
	e.fog_density = 0.011
	e.fog_sky_affect = 1.0
	# Performance graphics: no volumetric haze (the costliest effect here); the plain fog stays.
	e.volumetric_fog_enabled = not GameSettings.performance()
	e.volumetric_fog_density = 0.006
	e.volumetric_fog_albedo = Color(0.9, 0.93, 1.0)
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.05
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-62), deg_to_rad(-35), 0)
	key.light_energy = 0.9
	key.light_color = Color(0.95, 0.97, 1.0)
	key.shadow_enabled = true
	GameSettings.sun_shadow_mode(key)
	root.add_child(key)
	# Rows of arena lights over the ice: bright spots in the haze.
	for row in 2:
		for i in 5:
			var s := SpotLight3D.new()
			s.position = Vector3(-14.0 + i * 7.0, 13.0, -14.0 - row * 16.0)
			s.rotation = Vector3(deg_to_rad(-90), 0, 0)
			s.spot_range = 22.0
			s.spot_angle = 38.0
			s.light_energy = 5.0
			s.light_volumetric_fog_energy = 2.5
			s.light_color = Color(0.92, 0.95, 1.0)
			root.add_child(s)
	# Rim light from behind so players stand out from the haze, and a soft fill.
	var rim := OmniLight3D.new()
	rim.position = focus + Vector3(1.5, 3.0, -2.5)
	rim.omni_range = 7.0
	rim.light_energy = 3.0
	rim.light_color = Color(0.85, 0.9, 1.0)
	root.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = focus + Vector3(-2.0, 1.8, 3.0)
	fill.omni_range = 8.0
	fill.light_energy = 1.2
	root.add_child(fill)

	var rink: Rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	# The stands are far off, hazy and blurred here: the simplest fans look the same.
	Arena.low_detail = true
	root.add_child(rink)
	Arena.low_detail = false
	var puck: Puck = (load("res://scenes/match/Puck.tscn") as PackedScene).instantiate()
	root.add_child(puck)
	puck.visible = false
	_add_ice_dust(root, focus)
	return {"rink": rink, "puck": puck}


## Camera settings for menu shots: the far arena melts into the haze (null in Performance
## graphics: no depth-of-field blur).
static func camera_attributes() -> CameraAttributesPractical:
	if GameSettings.performance():
		return null
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 9.0
	attrs.dof_blur_far_transition = 10.0
	attrs.dof_blur_amount = 0.09
	return attrs


## Teams with a crest (the menus show logos).
static func teams_with_logos() -> Array[int]:
	var out: Array[int] = []
	for i in Teams.count():
		if ResourceLoader.exists(str(Teams.team(i).get("logo", ""))):
			out.append(i)
	return out


static func logo(team: int) -> Texture2D:
	var path := str(Teams.team(team).get("logo", ""))
	return load(path) if ResourceLoader.exists(path) else null


## The team's best forward from the roster sheet: {number, first, last, gender,
## overall, position}; a made-up #19 for teams without a roster.
static func star(team: int) -> Dictionary:
	var best := {}
	for p: Dictionary in Rosters.for_team(str(Teams.team(team).abbr)):
		if p.get("position", "") in FORWARDS and (best.is_empty() or int(p.overall) > int(best.overall)):
			best = p
	if best.is_empty():
		return {"number": "19", "first": "", "last": "", "gender": "Male", "overall": "", "position": "C"}
	return best


## Line ratings from the roster sheet's overalls: {OFF, DEF, GOAL} (top six forwards,
## top four defenders, the starting goalie). Empty for teams without a roster.
static func ratings(team: int) -> Dictionary:
	var rows := Rosters.for_team(str(Teams.team(team).abbr))
	if rows.is_empty():
		return {}
	var f: Array[int] = []
	var d: Array[int] = []
	var g: Array[int] = []
	for p: Dictionary in rows:
		var o := int(p.overall)
		match p.get("position", ""):
			"G":
				g.append(o)
			"D":
				d.append(o)
			_:
				f.append(o)
	var top := func(a: Array[int], n: int) -> int:
		if a.is_empty():
			return 0
		a.sort()
		a.reverse()
		var s := 0
		for i in mini(n, a.size()):
			s += a[i]
		return roundi(float(s) / mini(n, a.size()))
	return {"OFF": top.call(f, 6), "DEF": top.call(d, 4), "GOAL": top.call(g, 1)}


## A player in `team`'s uniform (road colors if `away` and they'd clash with `opponent`)
## who stands still unless given a brain. `who`: a roster row from star().
static func make_skater(root: Node3D, arena: Dictionary, team: int, opponent: int, away: bool, who: Dictionary) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate()
	s.team = 1 if away else 0
	s.number = int(who.get("number", 19))
	var info := Teams.team(team)
	s.uniform = Teams.uniform_vs(team, opponent, away)
	s.team_color = info.colors.jersey
	var crest := logo(team)
	if crest:
		s.crest = crest
	s.stats = PlayerStats.new()
	s.puck = arena.puck
	s.rink = arena.rink
	s.fatigue_enabled = false
	s.body_type = "female" if who.get("gender", "") == "Female" else "male"
	# Same looks as in a game for roster players (see MatchDirector).
	var look := RandomNumberGenerator.new()
	look.seed = hash("%s %s %s" % [Teams.team(team).abbr, who.get("first", ""), who.get("last", "")])
	s.skin_tone = SkaterVisual.SKIN_TONES[look.randi() % SkaterVisual.SKIN_TONES.size()]
	s.gear_style = look.randi() % 2
	s.visor = Skater.visor_for("%s %s %s" % [Teams.team(team).abbr, who.get("first", ""), who.get("last", "")])
	var hair := SkaterVisual.random_look(look, s.body_type, s.skin_tone)
	s.hair_style = hair.hair_style
	s.facial_hair = hair.facial_hair
	s.hair_color = hair.hair_color
	s.eye_color = hair.eye_color
	root.add_child(s)
	s.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass)
	# Menu players are posing for the camera: eyes on it, a word or a smirk now and then.
	if s.visual != null and s.visual.face != null:
		s.visual.face.look_at_camera = true
		s.visual.face.chatty = true
	s.teammates = [s]
	return s


## Fine ice spray drifting through the light.
static func _add_ice_dust(root: Node3D, focus: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 900
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.position = focus + Vector3(0.0, 1.2, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(10.0, 1.4, 10.0)
	p.direction = Vector3(1, -0.3, 0)
	p.spread = 25.0
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, -0.03, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.7)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.mesh = q
	root.add_child(p)
