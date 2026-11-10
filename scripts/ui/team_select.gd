extends Control
## Team select, the first step of an exhibition: each team's logo on a lit board with
## its star player standing in front (as on the matchup screen), the team's name plate
## and line ratings beneath, and a chip for every controller that slides between HOME,
## the middle (watching) and AWAY.
##
## Each controller: left / right picks a side; up / down changes that side's team
## (from the middle: the home team); the bumpers change the other team (from the
## middle: the away team). The mouse can click the up / down arrows on the plates.
## Accept: on to the rules (RulesSelect), or for Knockout Mode straight into the fights.
## Back: the main menu.
##
## `-- shot=<png> [wait=<s>] [home=<i>] [away=<i>]` saves a screenshot and quits.

const RULES_SCENE := "res://scenes/ui/RulesSelect.tscn"
const MATCH_SCENE := "res://scenes/match/Match.tscn"
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

const PLAYER_X := 1.25        ## meters left / right of center for each team's player
const PLAYER_LIFT := 0.45     ## meters the players stand above the ice, level with the crests
const LOGO_POS := Vector3(1.6, 1.95, -1.6)
const PLATE_Y := 548.0        ## design pixels: top of the name plates
const PLATE_W := 560.0
const CHIPS_Y := 742.0        ## top of the controller row

var devices: Array[Dictionary] = []   ## {id, name, side: -1 home / 0 watching / 1 away, x}
var teams := [0, 1]
var _input: MenuInput
var _canvas: Control
var _plates: Control
var _chips: Control
var _footer: Control
var _fade: ColorRect
var _stage: Node3D
var _arena := {}
var _skaters: Array = [null, null]
var _logos: Array[Sprite3D] = []
var _boards: Array[MeshInstance3D] = []
var _pop := [0.0, 0.0]        ## name plate bounce after a team change
var _arrows := []             ## clickable arrow rects: [Rect2, side, dir]
var _leaving := false
var _t := 0.0


func _ready() -> void:
	var cfg: Dictionary = GameSettings.config
	teams = [int(cfg.get("home_team", 0)), int(cfg.get("away_team", 1))]
	if _arg("home", "") != "":
		teams[0] = int(_arg("home", "0"))
	if _arg("away", "") != "":
		teams[1] = int(_arg("away", "1"))
	Sfx.play_music()
	_build_stage()
	_input = MenuInput.new()
	add_child(_input)
	_input.dev_side.connect(_on_side)
	_input.dev_moved.connect(func(dev: String, dir: int) -> void: _change_for(dev, dir, false))
	_input.dev_bumper.connect(func(dev: String, dir: int) -> void: _change_for(dev, dir, true))
	_input.accepted.connect(_continue)
	_input.back.connect(_back)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.0))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, 480)
	shade.size = Vector2(4000, 420)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	var header := Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.draw.connect(_draw_header.bind(header))
	_canvas.add_child(header)

	var vs := MenuStyle.chrome_text("VS", 110)
	vs.name = "VS"
	_canvas.add_child(vs)

	_plates = Control.new()
	_plates.mouse_filter = Control.MOUSE_FILTER_STOP
	_plates.size = MenuStyle.DESIGN_SIZE
	_plates.draw.connect(_draw_plates)
	_plates.gui_input.connect(_on_plate_click)
	_canvas.add_child(_plates)
	_chips = Control.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.draw.connect(_draw_chips)
	_canvas.add_child(_chips)
	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_canvas.add_child(_footer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)

	_detect_devices()
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _detect_devices())


func _process(delta: float) -> void:
	_t += delta
	var w := _canvas.size.x
	var vs := _canvas.get_node("VS") as Control
	vs.position = Vector2(w * 0.5 - vs.size.x * 0.5, 150 + sin(_t * 2.0) * 3.0)
	for i in 2:
		_pop[i] = move_toward(_pop[i], 0.0, delta * 4.0)
		if _logos.size() > i:
			_logos[i].scale = Vector3.ONE * (1.0 + _pop[i] * 0.12)
	for d in devices:
		var target := _column_x(d.side)
		d.x = lerpf(d.x, target, 1.0 - exp(-delta * 14.0))
	_plates.queue_redraw()
	_chips.queue_redraw()
	_footer.queue_redraw()


# --- 3D stage ------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	# The menu above is not physics-interpolated; the players skating here (120 Hz physics)
	# must be, or they step unevenly against the frame rate. The camera, placed every
	# frame, must not be.
	_stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(_stage)
	_arena = MenuArena.build(_stage, Vector3.ZERO)
	var c := Camera3D.new()
	c.fov = 50.0
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	c.attributes = MenuArena.camera_attributes()
	_stage.add_child(c)
	c.look_at_from_position(Vector3(0, 1.25, 3.9), Vector3(0, 1.4, -0.6))
	for t in 2:
		var side := -1.0 if t == 0 else 1.0
		# A lit board in the team's color behind the crest.
		var board := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.5, 2.5)
		board.mesh = q
		board.position = Vector3(side * LOGO_POS.x, LOGO_POS.y, LOGO_POS.z - 0.05)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stage.add_child(board)
		_boards.append(board)
		var logo := Sprite3D.new()
		logo.shaded = false
		logo.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		logo.position = Vector3(side * LOGO_POS.x, LOGO_POS.y, LOGO_POS.z)
		_stage.add_child(logo)
		_logos.append(logo)
	for t in 2:
		_dress_side(t)


## Puts the side's crest on its board and its star player in front, in this matchup's
## uniform (the away team in road colors if they'd clash).
func _dress_side(t: int) -> void:
	var team: int = teams[t]
	var side := -1.0 if t == 0 else 1.0
	var tex := MenuArena.logo(team)
	_logos[t].texture = tex
	if tex:
		_logos[t].pixel_size = 2.2 / float(tex.get_width())
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var col: Color = Teams.team(team).colors.jersey
	m.albedo_texture = _board_texture()
	m.albedo_color = col.lerp(Color.BLACK, 0.35)
	_boards[t].material_override = m
	if _skaters[t]:
		(_skaters[t] as Node).queue_free()
	var s := MenuArena.make_skater(_stage, _arena, team, teams[1 - t], t == 1, MenuArena.star(team))
	s.place(Vector3(side * PLAYER_X, 0, 0.6), Vector3(-side * 0.25, 0, 1).normalized())
	# Standing tall for the camera, in a pose picked at random (some are for women only).
	var poses: Array = SkaterVisual.DISPLAY_POSES.duplicate()
	if s.body_type == "female":
		poses.append_array(SkaterVisual.FEMALE_POSES)
	s.visual.display_pose = _arg("pose", poses[randi() % poses.size()])
	s.visual.display_lift = PLAYER_LIFT
	s.visual.snap()
	_skaters[t] = s


static var _board_tex: GradientTexture2D


## Soft radial glow for the crest boards (bright middle, dark edges).
func _board_texture() -> Texture2D:
	if _board_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.6, 1.6, 1.6))
		g.set_color(1, Color(0.15, 0.15, 0.15))
		_board_tex = GradientTexture2D.new()
		_board_tex.gradient = g
		_board_tex.fill = GradientTexture2D.FILL_RADIAL
		_board_tex.fill_from = Vector2(0.5, 0.5)
		_board_tex.fill_to = Vector2(1.0, 1.0)
	return _board_tex


# --- Controllers ------------------------------------------------------------------

func _detect_devices() -> void:
	var old := {}
	for d in devices:
		old[d.id] = d.side
	var had_old := not old.is_empty()
	devices.clear()
	devices.append({"id": "kb1", "name": "KEYBOARD 1", "side": 0})
	devices.append({"id": "kb2", "name": "KEYBOARD 2", "side": 0})
	for p in Input.get_connected_joypads():
		devices.append({"id": "pad%d" % p, "name": "PAD %d" % (p + 1), "side": 0})
	if had_old:
		for d in devices:
			d.side = old.get(d.id, 0)
	else:
		# Coming back from the rules: keep the sides. First time: one player on HOME
		# (Pad 1 if there is one, else Keyboard 1).
		var placed := false
		for h: Dictionary in GameSettings.humans:
			var id: String = h.kind if h.kind != "pad" else "pad%d" % int(h.pad)
			for d in devices:
				if d.id == id:
					d.side = -1 if int(h.team) == 0 else 1
					placed = true
		if not placed:
			devices[2 if devices.size() > 2 else 0].side = -1
	for d in devices:
		d.x = _column_x(d.side)


func _device(id: String) -> Dictionary:
	for d in devices:
		if d.id == id:
			return d
	return {}


func _column_x(side: int) -> float:
	var w := _canvas.size.x if _canvas else MenuStyle.DESIGN_SIZE.x
	return w * 0.5 + side * w * 0.25


func _on_side(dev: String, dir: int) -> void:
	var d := _device(dev)
	if d.is_empty() or _leaving:
		return
	var s := clampi(int(d.side) + dir, -1, 1)
	if s != d.side:
		d.side = s
		Sfx.play("click", Vector3.INF, -10.0, 1.2)


## Up / down (own team) or a bumper (the other team) from one controller.
func _change_for(dev: String, dir: int, other: bool) -> void:
	var d := _device(dev)
	if d.is_empty() or _leaving:
		return
	var t := 0 if int(d.side) <= 0 else 1
	if int(d.side) == 0:
		t = 1 if other else 0
	elif other:
		t = 1 - t
	_change_team(t, dir)


func _change_team(t: int, dir: int) -> void:
	var n := Teams.count()
	var next: int = wrapi(teams[t] + dir, 0, n)
	if next == teams[1 - t]:
		next = wrapi(next + dir, 0, n)
	teams[t] = next
	_pop[t] = 1.0
	Sfx.play("click", Vector3.INF, -8.0, 1.5)
	_dress_side(t)
	# The away side's road colors depend on the home team too.
	if t == 0 and (_skaters[1] as Skater).uniform != Teams.uniform_vs(teams[1], teams[0], true):
		_dress_side(1)


func _on_plate_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for a: Array in _arrows:
			if (a[0] as Rect2).has_point(e.position):
				_change_team(a[1], a[2])
				return


func _continue() -> void:
	if _leaving:
		return
	var humans: Array = []
	for d in devices:
		if d.side != 0:
			var id: String = d.id
			var kind := "pad" if id.begins_with("pad") else id
			humans.append({"kind": kind, "pad": int(id.substr(3)) if kind == "pad" else 0,
					"team": 0 if d.side < 0 else 1})
	GameSettings.config["home_team"] = teams[0]
	GameSettings.config["away_team"] = teams[1]
	GameSettings.humans = humans
	Sfx.play("glove", Vector3.INF, -4.0)
	if GameSettings.mode == "knockout":
		GameSettings.save_settings()
		Sfx.stop_music(1.2)
		_go(MATCH_SCENE)
	else:
		_go(RULES_SCENE)


func _back() -> void:
	if _leaving:
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	if GameSettings.mode == "knockout":
		GameSettings.menu_list = "modes"
	_go(MENU_SCENE)


func _go(scene: String) -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


# --- Drawing --------------------------------------------------------------------

func _draw_header(c: Control) -> void:
	MenuStyle.draw_tag(c, Vector2(60, 40), "KNOCKOUT MODE" if GameSettings.mode == "knockout" else "EXHIBITION", "SELECT TEAMS")


func _draw_plates() -> void:
	_arrows.clear()
	var f := MenuStyle.font(0.2)
	var small := MenuStyle.font(0.12)
	for t in 2:
		var team: int = teams[t]
		var info := Teams.team(team)
		var cx := _column_x(-1 if t == 0 else 1)
		var bump: float = sin(_pop[t] * PI) * 8.0
		var x0 := cx - PLATE_W * 0.5
		var y := PLATE_Y - bump
		var col: Color = info.colors.jersey
		var trim: Color = info.colors.trim
		var h := 96.0
		var sk := h * 0.3
		# HOME / AWAY tag and who's playing it, on a dark strip so it reads over the jersey.
		_plates.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 14 + sk, y - 40), Vector2(x0 + PLATE_W + sk + 8, y - 40),
				Vector2(x0 + PLATE_W + sk, y - 2), Vector2(x0 + sk + 6, y - 2)]), Color(0.02, 0.03, 0.07, 0.72))
		var who := _players_on(-1 if t == 0 else 1)
		var tag := ("HOME" if t == 0 else "AWAY") + ("   ·   " + who if who != "" else "   ·   CPU")
		_plates.draw_string(small, Vector2(x0 + 44, y - 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85))
		# Slanted plate in the team's color.
		var pts := PackedVector2Array([Vector2(x0 + sk, y), Vector2(x0 + PLATE_W + sk, y), Vector2(x0 + PLATE_W, y + h), Vector2(x0, y + h)])
		_plates.draw_polygon(pts, PackedColorArray([col.lightened(0.15), col, col.darkened(0.45), col.darkened(0.3)]))
		_plates.draw_polyline(PackedVector2Array([pts[0], pts[1]]), Color(1, 1, 1, 0.5), 2.0)
		_plates.draw_colored_polygon(PackedVector2Array([pts[3] + Vector2(0, -6), pts[2] + Vector2(0, -6), pts[2], pts[3]]), trim)
		var ink := Color.WHITE if col.get_luminance() < 0.6 else MenuStyle.INK
		var city := str(info.city).to_upper()
		var name := str(info.name).to_upper()
		_plates.draw_string(small, Vector2(x0 + 70, y + 32), city, HORIZONTAL_ALIGNMENT_LEFT, PLATE_W - 140, 22, Color(ink, 0.85))
		var fs := 46 if f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x < PLATE_W - 150 else 36
		_plates.draw_string(f, Vector2(x0 + 66, y + 78), name, HORIZONTAL_ALIGNMENT_LEFT, PLATE_W - 140, fs, ink)
		# Up / down arrows stacked at the plate's right end, as the controls change teams
		# (click them too). Up is the previous team.
		for dir in [-1, 1]:
			var ax: float = x0 + PLATE_W - 14 + sk * (0.75 if dir < 0 else 0.25)
			var ay: float = y + h * 0.5 + dir * 22.0
			var r := Rect2(ax - 26, ay - 22, 52, 44)
			_arrows.append([r, t, dir])
			var s := 12.0
			var tri := PackedVector2Array([Vector2(ax - s, ay - s * 0.7 * dir), Vector2(ax + s, ay - s * 0.7 * dir), Vector2(ax, ay + s * 0.7 * dir)])
			_plates.draw_colored_polygon(tri, Color(ink, 0.9))
		# Star player and line ratings under the plate.
		var star := MenuArena.star(team)
		var line := "#%s  %s %s" % [star.number, str(star.first).to_upper(), str(star.last).to_upper()] if str(star.last) != "" else ""
		var rat := MenuArena.ratings(team)
		if line != "":
			_plates.draw_string(small, Vector2(x0 + 20, y + h + 34), "STAR  " + line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
		if not rat.is_empty():
			var rx := x0 + PLATE_W + sk - 10
			for k in ["GOAL", "DEF", "OFF"]:
				var val := str(rat[k])
				var vw := f.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
				rx -= vw
				_plates.draw_string(f, Vector2(rx, y - 10), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
				var kw := small.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				rx -= kw + 6
				_plates.draw_string(small, Vector2(rx, y - 12), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
				rx -= 22


## "P1  P2" for the controllers on a side ("" if none).
func _players_on(side: int) -> String:
	var out := PackedStringArray()
	var p := 0
	for d in devices:
		if d.side != 0:
			p += 1
			if d.side == side:
				out.append("P%d" % p)
	return "  ".join(out)


func _draw_chips() -> void:
	var w := _canvas.size.x
	var small := MenuStyle.font(0.12)
	# Column labels.
	for side in [-1, 0, 1]:
		var label: String = ["HOME", "WATCHING", "AWAY"][side + 1]
		var lw := small.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_chips.draw_string(small, Vector2(_column_x(side) - lw * 0.5, CHIPS_Y - 10), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	_chips.draw_line(Vector2(w * 0.12, CHIPS_Y - 3), Vector2(w * 0.88, CHIPS_Y - 3), Color(1, 1, 1, 0.15), 1.0)
	# Stack each column's chips.
	var count := {-1: 0, 0: 0, 1: 0}
	var p := 0
	for d in devices:
		var side: int = d.side
		var row: int = count[side]
		count[side] += 1
		var pn := 0
		if side != 0:
			p += 1
			pn = p
		var cw := 230.0
		var ch := 34.0
		var x: float = d.x - cw * 0.5
		var y := CHIPS_Y + 8 + row * (ch + 6)
		var col: Color = HumanBrain.PLAYER_COLORS[(pn - 1) % 4] if pn > 0 else Color(0.5, 0.53, 0.6)
		var sk := ch * 0.35
		var pts := PackedVector2Array([Vector2(x + sk, y), Vector2(x + cw + sk, y), Vector2(x + cw, y + ch), Vector2(x, y + ch)])
		_chips.draw_colored_polygon(pts, Color(0.04, 0.05, 0.1, 0.85))
		_chips.draw_colored_polygon(PackedVector2Array([pts[0], pts[0] + Vector2(8, 0), pts[3] + Vector2(8, 0), pts[3]]), col)
		var label := ("P%d  " % pn if pn > 0 else "") + str(d.name)
		_chips.draw_string(small, Vector2(x + 26, y + 24), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col if pn > 0 else Color(0.8, 0.83, 0.9))
		# Arrows hint which ways this chip can still move.
		if side > -1:
			_chips.draw_string(small, Vector2(x - 18, y + 24), "‹", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.5))
		if side < 1:
			_chips.draw_string(small, Vector2(x + cw + 14, y + 24), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.5))


func _draw_footer() -> void:
	var hint := "Left / right: pick a side.   Up / down: your team.   %s: the other team." % ("L1 / R1" if _input.using_pad else "Q / E")
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint,
			[[_input.accept_label(), "CONTINUE"], [_input.back_label(), "BACK"]], _input.using_pad)


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


## Screenshot hook for automated checks: `-- shot=<png> wait=<s>`.
func _enter_tree() -> void:
	var shot := _arg("shot", "")
	if shot != "":
		_shot.call_deferred(shot, float(_arg("wait", "2.0")))


func _shot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
