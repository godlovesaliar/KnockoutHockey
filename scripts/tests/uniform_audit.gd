extends Node3D
## Uniform audit: one standing skater per team, close-ups of the chest crest and of the
## back name and number, tiled into two contact sheets.
##   godot --path . res://scenes/tests/UniformAudit.tscn -- [out=<dir>] [body=male|female] [goalie=1]
##   -> <out>/audit_front.png, <out>/audit_back.png   (default out: res://docs)
## Names cycle through lengths from short to the longest a roster is likely to carry, and
## numbers through wide pairs, so the nameplate and number edges get tested on every team.

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")
const TILE := Vector2i(300, 340)
const COLS := 6
const NAMES := ["Wu", "Raposo", "Lindqvist", "Shellenberger", "Kowalczyk", "Bergeron",
	"Ovechkinov", "Delacroix-Moreau"]
const NUMBERS := [88, 19, 4, 77, 10, 96, 31, 8]

var cam: Camera3D
var players: Array = []


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _ready() -> void:
	get_window().size = TILE
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(20), 0)
	add_child(sun)
	var back_light := DirectionalLight3D.new()
	back_light.rotation = Vector3(deg_to_rad(-40), deg_to_rad(200), 0)
	back_light.light_energy = 0.7
	add_child(back_light)
	var rink: Rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	add_child(rink)
	var puck: Puck = (load("res://scenes/match/Puck.tscn") as PackedScene).instantiate()
	add_child(puck)
	var goalies := _arg("goalie", "") != ""
	for t in Teams.LIST.size():
		var s: Skater = (GOALIE_SCENE if goalies else SKATER_SCENE).instantiate()
		s.team = 0
		s.number = NUMBERS[t % NUMBERS.size()]
		s.last_name = NAMES[t % NAMES.size()]
		var info := Teams.team(t)
		s.uniform = Teams.uniform_vs(t, t, false)
		s.team_color = info.colors.jersey
		if ResourceLoader.exists(info.get("logo", "")):
			s.crest = load(info.logo)
		s.stats = PlayerStats.new()
		s.puck = puck
		s.rink = rink
		s.body_type = _arg("body", "male")
		s.skin_tone = SkaterVisual.SKIN_TONES[t % SkaterVisual.SKIN_TONES.size()]
		if not goalies:
			s.fatigue_enabled = false
			s.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass)
		add_child(s)
		var at := Vector3(-9.0 + (t % 10) * 2.0, 0, -8.0 + (t / 10) * 8.0)
		if goalies:
			s.global_position = at
		else:
			s.place(at, Vector3.BACK)
			(s as Skater).visual.display_pose = _arg("pose", "hips")   # upright, chest square to the camera
		players.append(s)
	cam = Camera3D.new()
	cam.fov = 24
	add_child(cam)
	_run()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var out := _arg("out", "res://docs")
	for view in ["front", "back"]:
		var sheet := Image.create(COLS * TILE.x, ceili(players.size() / float(COLS)) * TILE.y, false, Image.FORMAT_RGBA8)
		for t in players.size():
			var s: Node3D = players[t]
			var chest := _chest(s)
			var fwd: Vector3 = s.global_transform.basis.z
			if s is Skater:
				fwd = (s as Skater).heading
			fwd.y = 0
			fwd = fwd.normalized()
			var dir := fwd if view == "front" else -fwd
			cam.look_at_from_position(chest + dir * 1.9 + Vector3(0, 0.12, 0), chest)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(TILE.x, TILE.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((t % COLS) * TILE.x, (t / COLS) * TILE.y))
		var path := "%s/audit_%s.png" % [out, view]
		sheet.save_png(path)
		print("saved ", path)
	get_tree().quit()


## Middle of the upper torso, from the skeleton (Spine2), else a fixed height.
func _chest(s: Node3D) -> Vector3:
	var sk: Skeleton3D = s.find_child("*", true, false) as Skeleton3D
	for n in s.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk:
		var i := sk.find_bone("Spine2")
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return s.global_position + Vector3(0, 1.2, 0)
