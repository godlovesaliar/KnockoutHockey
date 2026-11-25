class_name BroadcastOpen
extends Node
## The broadcast open: the matchup screen as a TV package, cut to the broadcast theme
## (Sfx.play_theme; tools/build_theme.py writes the music to the same clock). Four beats,
## each two bars long and each landing on the theme's big hit:
##
##   1. the title    a high shot flying in over the arena; the league logo slams down,
##                   the title bars wipe out from under it (the game, the arena).
##   2. the home team   a team-colored panel sweeps across (the camera cuts under it) to
##                   a low shot of their star; the crest slams onto the panel, then the
##                   name, the conference, the line ratings and the star's lower third.
##   3. the away team   the same from the other side.
##   4. the lockup   both colors meet in the middle and fold into a bar across the top;
##                   the crests fly in and collide (flash, sparks, the clash), "VS" lands
##                   between them, and the tale of the tape counts up under the two stars,
##                   face to face at center ice.
##
## The booth's line is split across beats 2 and 3 (`cue`: "Tonight: a matchup between the
## <home>" / "and the <away>."). `closing` fires half a stinger before the theme reaches
## its bed, so the league stinger covers the cut to the rink right on the bar line.
## Quick presentation plays the lockup alone. Accept / Start skips (`skipped`).
##
## The clock is the theme's own playback position, so the pictures stay on the music
## whatever the frame rate does; with sound off it runs on real time.

signal cue(what: StringName)   ## &"home" / &"away": that half of the booth's line (&"both": Quick)
signal closing                 ## the open is done: bring the stinger
signal skipped

const LEAD := 0.3              ## s before a beat's bar line that its wipe has the screen covered (the camera cuts under it)
const SWEEP := 0.22            ## s a wipe takes to cross the screen
const SK := 200.0              ## how far the panels' edges lean over the screen's height (design px)
const LEAN := SK / 900.0
const HOLD_MAX := 5.0          ## s the lockup waits past its two bars for the booth to finish
const HERO := Vector3(0.0, 0.0, 0.6)   ## where a team's star stands for their beat
const BAR_Y := 84.0            ## the lockup's bar across the top
const BAR_H := 150.0
const CREST := 236.0           ## the lockup's crests
const GOLD := Color(1.0, 0.85, 0.2)
const POSITIONS := {"C": "CENTER", "LW": "LEFT WING", "RW": "RIGHT WING", "D": "DEFENSE", "G": "GOALTENDER"}
const RATINGS := [["OFF", "OFFENSE"], ["DEF", "DEFENSE"], ["GOAL", "GOALTENDING"]]

var d: MatchDirector
var quick := false
var stars: Array[Skater] = []      ## each team's star (the director hides everyone else)

var _t := 0.0                      ## seconds on the theme's clock
var _t0 := 0.0                     ## where on it the open starts (Quick: just before the lockup)
var _settle := 0.2                 ## real seconds before it starts (the scene's first frames hitch)
var _running := false
var _on_theme := false             ## the clock is the theme's playback position
var _stalled := 0.0
var _beat := -1                    ## 0 title, 1 home, 2 away, 3 lockup
var _fired := {}
var _shake := 0.0
var _done := false
var _frozen := false               ## held on one moment (`-- openat=`, layout checks)
var _sway := randf() * 100.0
var _stage: Node3D
var _cam: Camera3D
var _lens: CameraAttributesPractical
var _lights: Array[OmniLight3D] = []
var _layer: CanvasLayer
var _canvas: Control
var _input: MenuInput
var _off := Vector2.ZERO           ## this frame's shake
var _w := 1600.0
var _info: Array[Dictionary] = []  ## per team: what the graphics say about it
var _title := {}
var _sparks: Array[Vector3] = []   ## the clash's sparks: angle, speed, length
var _bars: Array[float] = []       ## when each beat's bar starts: title, home, away, lockup, the end


func setup(director: MatchDirector, quick_open: bool) -> void:
	d = director
	quick = quick_open
	_bars = [Sfx.theme_bar(1), Sfx.theme_bar(3), Sfx.theme_bar(5), Sfx.theme_bar(7), Sfx.theme_bar(9)]
	_t0 = _bars[3] - Sfx.THEME_BEAT * 2.0 if quick else 0.0
	_t = _t0
	for t in 2:
		stars.append(_pick_star(t))
		_info.append(_team_info(t))
	var venue := Arenas.for_game(d.team_ids[0])
	_title = {
		"mode": "CHALLENGE GAME" if d.challenge >= 0 else "EXHIBITION GAME",
		"venue": "LIVE FROM " + str(venue.get("name", "THE ARENA")).to_upper(),
		"rules": "%d ON %d   ·   %d PERIODS OF %s" % [d.format, d.format, d.periods, MatchHud._mmss(d.period_length)],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 34:
		_sparks.append(Vector3(rng.randf() * TAU, rng.randf_range(0.45, 1.0), rng.randf_range(0.3, 1.0)))
	_build_stage()
	_build_canvas()
	_input = MenuInput.new()
	add_child(_input)
	_input.accepted.connect(_skip)
	_set_beat(3 if quick else 0)
	_aim()


## The team's star: the roster's best forward (as on team select), else the first line's center.
func _pick_star(t: int) -> Skater:
	var lu := d.lineup(t)
	var row := MenuArena.star(d.team_ids[t])
	for s: Skater in lu.forwards:
		if s.number == int(row.get("number", -1)) and str(row.get("last", "")) != "":
			return s
	return lu.forwards[0] if not lu.forwards.is_empty() else lu.all_skaters()[0]


func _team_info(t: int) -> Dictionary:
	var id: int = d.team_ids[t]
	var team := Teams.team(id)
	var col := MenuStyle.team_color(id)
	# The accent: the first uniform color that stands out from the panel's.
	var accent := Color.WHITE
	for k: String in ["trim", "number", "jersey", "number_outline"]:
		var c: Color = team.colors[k]
		if Vector3(c.r - col.r, c.g - col.g, c.b - col.b).length() > 0.35:
			accent = c
			break
	var s := stars[t]
	var row := MenuArena.star(id)
	var star_name := ("%s %s" % [s.first_name, s.last_name]).strip_edges().to_upper()
	var line: String = POSITIONS.get(s.position_name, "FORWARD")
	if s.number == int(row.get("number", -1)) and str(row.get("overall", "")) != "":
		line += "   ·   %s OVERALL" % row.overall
	var who := PackedStringArray()
	for i in d.humans.size():
		if int(d.humans[i].get("team", 0)) == t:
			who.append("P%d" % (i + 1))
	return {
		"id": id, "name": str(team.name).to_upper(), "city": str(team.get("city", "")).to_upper(),
		"conference": str(team.get("conference", "")), "color": col, "accent": accent,
		"logo": Teams.logo(id), "ratings": MenuArena.ratings(id),
		"star": ("#%d  %s" % [s.number, star_name]).strip_edges(), "star_line": line,
		"who": "CPU" if who.is_empty() else "  ".join(who),
	}


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "OpenStage"
	add_child(_stage)
	_cam = Camera3D.new()
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # placed every frame
	_stage.add_child(_cam)
	_cam.make_current()
	if not GameSettings.performance():
		# The stars' shots: the far stands melt away behind them.
		_lens = CameraAttributesPractical.new()
		_lens.dof_blur_far_enabled = true
		_lens.dof_blur_amount = 0.08
	# A rim light in each team's color, behind its star.
	for t in 2:
		var l := OmniLight3D.new()
		l.omni_range = 6.0
		l.light_energy = 3.2
		l.light_color = (_info[t].color as Color).lerp(Color.WHITE, 0.45)
		l.visible = false
		_stage.add_child(l)
		_lights.append(l)


func _build_canvas() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20   # over the game, under the league stinger
	add_child(_layer)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	_canvas.draw.connect(_draw)


func _skip() -> void:
	if _running and _t - _t0 > 0.5 and not _done:
		_done = true   # (nothing more lands under the stinger)
		skipped.emit()


## Holds the open on the moment `t` seconds into the theme (no sound; layout checks).
func freeze_at(t: float) -> void:
	_frozen = true
	_running = true
	_done = true
	_t = t
	_set_beat(_beat_at(t))
	_aim()
	_canvas.queue_redraw()


# --- The clock -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _frozen:
		return
	delta = minf(delta, 0.1)
	if not _running:
		_settle -= delta
		if _settle > 0.0:
			return
		_running = true
		_on_theme = Sfx.play_theme(_t0)
		if quick:
			cue.emit(&"both")
	var next := _t + delta
	if _on_theme:
		# The theme's own clock (never backwards; a stalled audio clock hands over to real time).
		var tt := Sfx.theme_time()
		if tt < 0.0 or tt < _t - 1.0:
			_on_theme = false
		else:
			next = clampf(tt, _t, _t + delta * 3.0 + 0.05)
			_stalled = _stalled + delta if next <= _t else 0.0
			if _stalled > 0.4:
				_on_theme = false
	_t = next
	_shake = maxf(0.0, _shake - delta * 3.2)
	_sway += delta
	if not _done:
		_events()
	var beat := _beat_at(_t)
	if beat != _beat:
		_set_beat(beat)
	_aim()
	_canvas.queue_redraw()


func _beat_at(t: float) -> int:
	if quick or t >= _bars[3] - LEAD:
		return 3
	if t >= _bars[2] - LEAD:
		return 2
	return 1 if t >= _bars[1] - LEAD else 0


## True once, when the clock reaches `time` (never for a moment before the open started).
func _at(key: String, time: float) -> bool:
	if _fired.has(key) or _t < time or time < _t0:
		return false
	_fired[key] = true
	return true


func _events() -> void:
	if _at("title", _bars[0]):
		Sfx.play("tv_slam", Vector3.INF, -3.0)
		_shake = 0.7
	for b in [1, 2, 3]:
		var ts := _bars[b]
		if _at("whoosh%d" % b, ts - LEAD - 0.36):
			Sfx.play("tv_whoosh", Vector3.INF, -2.0)
		if b == 3:
			if _at("clash", ts):
				Sfx.play("tv_clash", Vector3.INF, 0.0)
				_shake = 1.0
		elif _at("slam%d" % b, ts):
			Sfx.play("tv_slam", Vector3.INF, -4.0)
			_shake = 0.55
			cue.emit(&"home" if b == 1 else &"away")
		# The numbers tick in on the beat.
		var first := 2.0 if b == 3 else 1.0
		for i in 3:
			if _at("tick%d_%d" % [b, i], ts + Sfx.THEME_BEAT * (first + 0.5 * i)) and _has_ratings(b):
				Sfx.play("click", Vector3.INF, -9.0, 1.5 + 0.12 * i)
	var end := _bars[4] - Stinger.LEN * 0.5
	if not _done and _t >= end and (not Sfx.announcing() or _t >= end + HOLD_MAX):
		_done = true
		if Sfx.log_events:
			print("[open] %.1f closing at %.2fs of the theme" % [Time.get_ticks_msec() / 1000.0, _t])
		closing.emit()


func _has_ratings(beat: int) -> bool:
	if beat == 3:
		return not (_info[0].ratings as Dictionary).is_empty() and not (_info[1].ratings as Dictionary).is_empty()
	return not (_info[beat - 1].ratings as Dictionary).is_empty()


# --- The stage -------------------------------------------------------------------------

## Dresses the stage for a beat: who's on it, where they stand, their light.
func _set_beat(beat: int) -> void:
	_beat = beat
	if Sfx.log_events:
		print("[open] %.1f beat %d at %.2fs of the theme%s" % [Time.get_ticks_msec() / 1000.0, beat, _t, "" if _on_theme else " (own clock)"])
	for t in 2:
		var s := stars[t]
		var on := beat == 3 or beat == t + 1
		s.visual.visible = on
		_lights[t].visible = on
		if not on:
			continue
		var side := -1.0 if t == 0 else 1.0   # home on the left of the screen (the camera looks down -Z)
		if beat == 3:
			# Face to face over the dot, opened up a little to the camera.
			s.place(Vector3(side * 1.15, 0.0, 0.0), Vector3(-side, 0.0, 0.45).normalized())
			_lights[t].position = Vector3(side * 2.4, 2.3, -1.3)
		else:
			# Alone at center ice, squared to the camera (which sits a little to their side).
			s.place(HERO, Vector3(-side * 0.25, 0.0, 1.0).normalized())
			_lights[t].position = HERO + Vector3(side * 1.2, 2.4, -1.7)
		s.visual.snap()
		s.visual.play_clip("idle", Vector3.ONE, -1.0, 1.0, 0.05)
		if s.visual.face != null:
			s.visual.face.look_at_camera = beat != 3
	_cam.attributes = _lens if beat > 0 else null
	if _lens:
		_lens.dof_blur_far_distance = 10.0 if beat == 3 else 7.0
		_lens.dof_blur_far_transition = 16.0 if beat == 3 else 10.0


func _aim() -> void:
	var pos: Vector3
	var look: Vector3
	match _beat:
		0:
			# High over one end, drifting across and down toward the ice.
			var u := clampf((_t - _t0) / (_bars[1] - LEAD - _t0), 0.0, 1.0)
			pos = Vector3(lerpf(-6.5, 6.5, u), lerpf(12.5, 10.0, u), RinkSpec.HALF_L + 1.6 - 4.0 * u)
			look = Vector3(lerpf(-2.0, 2.0, u), 2.0, 0.0)
			_cam.fov = 55.0
		3:
			# Low and square on the two of them, pushing in.
			var u := clampf((_t - _bars[3] + LEAD) / (_bars[4] - _bars[3] + LEAD + HOLD_MAX), 0.0, 1.0)
			pos = Vector3(0.0, 1.2, lerpf(7.3, 5.9, u))
			look = Vector3(0.0, 1.08, 0.0)
			_cam.fov = 34.0
		_:
			# Low on the star, who sits in the half of the frame the panel leaves open; a
			# slow arc toward their front, closing in.
			var side := 1.0 if _beat == 1 else -1.0
			var ts := _bars[_beat] - LEAD
			var u := clampf((_t - ts) / (_bars[_beat + 1] - LEAD - ts), 0.0, 1.0)
			var ang := side * lerpf(-0.42, -0.1, u)
			var r := lerpf(4.4, 3.9, u)
			pos = HERO + Vector3(sin(ang) * r, 1.1, cos(ang) * r)
			var fwd := HERO - pos
			fwd.y = 0.0
			var right := fwd.normalized().cross(Vector3.UP)
			look = HERO + Vector3(0.0, 1.12, 0.0) - right * side * 1.22
			_cam.fov = 36.0
	_cam.look_at_from_position(pos, look)
	Cutscene.handheld(_cam, _sway, 0.6)
	if _shake > 0.0:
		_cam.rotate_object_local(Vector3.BACK, sin(_t * 61.0) * _shake * 0.006)


# --- The graphics ------------------------------------------------------------------------

static func _seg(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


static func _out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


## Out past the mark and back (a landing with some bounce).
static func _back(x: float) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x


func _xf(origin := Vector2.ZERO, rot := 0.0, scale := 1.0) -> void:
	_canvas.draw_set_transform(_off + origin, rot, Vector2(scale, scale))


## A full-width band from one side of the screen to a leaning edge that crosses the
## screen's mid-height at `xm`, between `y0` and `y1`.
func _band(left: bool, xm: float, y0: float, y1: float, color: Color) -> void:
	var xt := xm + LEAN * (450.0 - y0)
	var xb := xm + LEAN * (450.0 - y1)
	var far := -700.0 if left else _w + 700.0
	if (left and maxf(xt, xb) < far + 2.0) or (not left and minf(xt, xb) > far - 2.0) or y1 - y0 < 1.0:
		return
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(far, y0), Vector2(xt, y0), Vector2(xb, y1), Vector2(far, y1)]), color)


## A stripe with the bands' lean, `width` wide from the edge at `xm`.
func _stripe(xm: float, width: float, y0: float, y1: float, color: Color) -> void:
	var xt := xm + LEAN * (450.0 - y0)
	var xb := xm + LEAN * (450.0 - y1)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(xt, y0), Vector2(xt + width, y0), Vector2(xb + width, y1), Vector2(xb, y1)]), color)


## A slanted plate with a drop shadow.
func _plate(r: Rect2, color: Color, skew := 14.0, a := 1.0) -> void:
	MenuStyle.draw_slant(_canvas, Rect2(r.position + Vector2(6, 7), r.size), Color(0, 0, 0, 0.35 * a), skew)
	MenuStyle.draw_slant(_canvas, r, Color(color, color.a * a), skew)


## A crest fitted in a `size` square centered on `c` (tall and wide crests alike), with its shadow.
func _crest(tex: Texture2D, c: Vector2, size: float, a := 1.0, rot := 0.0) -> void:
	if tex == null or a <= 0.0:
		return
	var sz := Vector2(tex.get_size()) * (size / float(maxi(tex.get_width(), tex.get_height())))
	_xf(c, rot)
	_canvas.draw_texture_rect(tex, Rect2(-sz * 0.5 + Vector2(10, 14), sz), false, Color(0, 0, 0, 0.42 * a))
	_canvas.draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, a))
	_xf()


## The largest size from `size` down to `least` at which `text` fits in `width`.
static func _fit(text: String, size: int, width: float, least: int) -> int:
	while size > least and MenuStyle.text_width(text, size) > width:
		size -= 2
	return size


func _text(pos: Vector2, text: String, size: int, color: Color, a := 1.0) -> void:
	_canvas.draw_string(MenuStyle.font(0.12), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * a))


func _text_w(text: String, size: int) -> float:
	return MenuStyle.text_width(text, size, 0.12)


func _bold(pos: Vector2, text: String, size: int, a := 1.0, color := Color.WHITE, outline := -1) -> void:
	MenuStyle.draw_bold(_canvas, pos, text, size, Color(color, a), int(size * 0.16) if outline < 0 else outline,
			Color(MenuStyle.INK, a), 0.2, a > 0.9)


## A ring of light bursting out of `c` (a logo just landed), `f` 0 to 1.
func _ring(c: Vector2, f: float, from: float, to: float) -> void:
	if f <= 0.0 or f >= 1.0:
		return
	_canvas.draw_arc(_off + c, lerpf(from, to, _out(f)), 0.0, TAU, 96, Color(1, 1, 1, (1.0 - f) * 0.85), lerpf(22.0, 2.0, f), true)


func _draw() -> void:
	if d == null or not _running:
		_canvas.draw_rect(Rect2(-50, -50, _canvas.size.x + 100, 1000), Color.BLACK)
		return
	_w = _canvas.size.x
	_off = Vector2(sin(_t * 97.0), cos(_t * 83.0)) * _shake * _shake * 16.0
	_xf()
	var t := _t
	if quick:
		if t < _bars[3] - LEAD:
			_canvas.draw_rect(Rect2(-100, -100, _w + 200, 1100), Color.BLACK)
		_draw_lockup(t - _bars[3])
	else:
		match _beat:
			0:
				_draw_title(t - _bars[0])
			1, 2:
				_draw_team(_beat - 1, t - _bars[_beat])
			3:
				_draw_lockup(t - _bars[3])
		# The next beat's wipe, sweeping in over this one.
		if _beat < 2 and t >= _bars[_beat + 1] - LEAD - SWEEP:
			_draw_team(_beat, t - _bars[_beat + 1])
		elif _beat == 2 and t >= _bars[3] - LEAD - SWEEP:
			_draw_lockup(t - _bars[3])
		# Up from black.
		var black := 1.0 - _seg(t, 0.1, _bars[0] - 0.15)
		if black > 0.0:
			_canvas.draw_rect(Rect2(-100, -100, _w + 200, 1100), Color(0, 0, 0, black))
	_draw_skip()
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skip() -> void:
	var a := _seg(_t - _t0, 1.0, 1.4) * 0.9
	if a <= 0.0 or _done:
		return
	var label := _input.accept_label()
	var gw := MenuStyle.glyph_width(label, _input.using_pad, 28.0)
	var x := _w - 48.0 - gw - 58.0
	_canvas.draw_rect(Rect2(x - 10, 856, gw + 78, 36), Color(0.02, 0.03, 0.06, 0.6 * a))
	MenuStyle.draw_glyph(_canvas, Vector2(x, 860), label, _input.using_pad, 28.0)
	_text(Vector2(x + gw + 10, 881), "SKIP", 18, MenuStyle.ICE, a)


# --- Beat 1: the title -------------------------------------------------------------------

func _draw_title(s: float) -> void:
	var cx := _w * 0.5
	var c := Vector2(cx, 318.0)
	var y := 566.0
	var name := "KNOCKOUT HOCKEY LEAGUE"
	var tw := MenuStyle.text_width(name, 54)
	var bw := (tw + 150.0) * _out(_seg(s, 0.08, 0.42))
	# The game's tag rises from behind the bar; the arena's drops below it.
	var k_tag := _out(_seg(s, 0.4, 0.62))
	if k_tag > 0.0:
		var mode: String = _title.mode
		var mw := _text_w(mode, 24) + 44.0
		var my := y - 40.0 * k_tag
		MenuStyle.draw_slant(_canvas, Rect2(cx - (tw + 150.0) * 0.5 + 6, my, mw, 40), Color(MenuStyle.RED, k_tag), 12)
		_text(Vector2(cx - (tw + 150.0) * 0.5 + 28, my + 28), mode, 24, Color.WHITE, k_tag)
	var k_sub := _out(_seg(s, 0.55, 0.8))
	if k_sub > 0.0:
		var venue: String = _title.venue
		var vw := _text_w(venue, 26) + 80.0
		var vy := y + 46.0 + 42.0 * k_sub
		MenuStyle.draw_slant(_canvas, Rect2(cx - vw * 0.5 - 6, vy, vw, 46), Color(0.03, 0.04, 0.09, 0.92 * k_sub), 12)
		MenuStyle.draw_slant(_canvas, Rect2(cx - vw * 0.5 - 6, vy + 43, vw, 3), Color(MenuStyle.RED, k_sub), 1)
		_text(Vector2(cx - vw * 0.5 + 34, vy + 32), venue, 26, MenuStyle.ICE, k_sub)
	if bw > 4.0:
		var x := cx - bw * 0.5 - 13.0
		MenuStyle.draw_slant(_canvas, Rect2(x + 8, y + 10, bw, 84), Color(0, 0, 0, 0.35), 26)
		MenuStyle.draw_slant(_canvas, Rect2(x - 22, y - 8, bw + 44, 100), MenuStyle.RED, 30)
		MenuStyle.draw_slant(_canvas, Rect2(x - 10, y - 4, bw + 20, 92), MenuStyle.INK, 28)
		MenuStyle.draw_slant(_canvas, Rect2(x, y, bw, 84), MenuStyle.NAVY, 26)
		MenuStyle.draw_slant(_canvas, Rect2(x, y + 50, bw, 34), Color(0, 0, 0, 0.2), 10)
		MenuStyle.draw_slant(_canvas, Rect2(x + 14, y - 4, bw * 0.6, 4), Color(1, 1, 1, 0.75), 2)
		var ta := _seg(s, 0.3, 0.5)
		if ta > 0.0:
			_bold(Vector2(cx - tw * 0.5, y + 61), name, 54, ta)
	# The league logo comes down out of the lights and lands on the beat.
	var k := _seg(s, -0.15, 0.0)
	if k > 0.0:
		var bump := 1.0 + 0.08 * sin(_seg(s, 0.0, 0.34) * PI)
		_crest(Stinger.logo(), c, 430.0 * lerpf(2.8, 1.0, k * k) * bump, k, lerpf(-0.3, 0.0, k))
	if s >= 0.0:
		_ring(c, s / 0.45, 170.0, 640.0)
		var flash := (1.0 - _seg(s, 0.0, 0.2)) * 0.4
		if flash > 0.0:
			_canvas.draw_rect(Rect2(-100, -100, _w + 200, 1100), Color(1, 1, 1, flash))


# --- Beats 2 and 3: a team ---------------------------------------------------------------

func _draw_team(t: int, s: float) -> void:
	var info := _info[t]
	var left := t == 0
	var col: Color = info.color
	var accent: Color = info.accent
	var dir := 1.0 if left else -1.0
	# The panel's edge: across the whole screen (the cut), then back to the middle.
	var out_x := -260.0 if left else _w + 260.0
	var far_x := _w + 260.0 if left else -260.0
	var k_in := _seg(s, -LEAD - SWEEP, -LEAD)
	var xm := lerpf(out_x, far_x, k_in * k_in) if s < -LEAD else lerpf(far_x, maxf(_w * 0.5, 800.0) if left else minf(_w * 0.5, _w - 800.0), _out(_seg(s, -LEAD, -0.02)))
	_band(left, xm + dir * 34.0, -20, 920, accent)
	_band(left, xm + dir * 20.0, -20, 920, MenuStyle.INK)
	_band(left, xm, -20, 920, col)
	_band(left, xm, 520, 920, Color(0, 0, 0, 0.16))
	# Light catching the panel, and pinstripes along its edge.
	_stripe(xm - dir * 250.0 - (0.0 if left else 70.0), 70.0, -20, 920, Color(1, 1, 1, 0.05))
	_stripe(xm - dir * 380.0 - (0.0 if left else 26.0), 26.0, -20, 920, Color(1, 1, 1, 0.04))
	_stripe(xm - dir * 30.0 - (10.0 if left else 0.0), 10.0, -20, 920, accent)
	_stripe(xm - dir * 44.0 - (4.0 if left else 0.0), 4.0, -20, 920, Color(1, 1, 1, 0.7))
	if s < -0.08:
		return
	var x0 := 56.0 if left else _w - 656.0
	var cx := x0 + 300.0
	# HOME / AWAY and who's playing them.
	var k_tag := _out(_seg(s, 0.0, 0.25))
	if k_tag > 0.0:
		var tag := "HOME" if left else "AWAY"
		var who: String = info.who
		var tw := _text_w(tag, 24) + 40.0
		var ww := _text_w(who, 24) + 36.0
		var tx := cx - (tw + ww) * 0.5 - (1.0 - k_tag) * 30.0 * dir
		MenuStyle.draw_slant(_canvas, Rect2(tx, 60, tw, 38), Color(MenuStyle.INK, k_tag), 12)
		_text(Vector2(tx + 22, 87), tag, 24, Color.WHITE, k_tag)
		MenuStyle.draw_slant(_canvas, Rect2(tx + tw, 60, ww, 38), Color(0.93, 0.95, 0.98, k_tag), 12)
		_text(Vector2(tx + tw + 20, 87), who, 24, MenuStyle.INK, k_tag)
	# The name plate under the crest.
	var city: String = info.city
	var k_city := _out(_seg(s, 0.1, 0.32))
	if city != "" and k_city > 0.0:
		_text(Vector2(cx - _text_w(city, 28) * 0.5, 500 + (1.0 - k_city) * 14.0), city, 28, Color.WHITE, k_city * 0.92)
	var name: String = info.name
	var k_name := _out(_seg(s, 0.14, 0.42))
	if k_name > 0.0:
		var size := _fit(name, 92, 590.0, 44)
		_bold(Vector2(cx - MenuStyle.text_width(name, size) * 0.5, 540 + size * 0.5 + (1.0 - k_name) * 22.0), name, size, k_name)
	var k_rule := _out(_seg(s, 0.25, 0.6))
	if k_rule > 0.0:
		_canvas.draw_rect(Rect2(cx - 290.0 * k_rule, 608, 580.0 * k_rule, 6), accent)
		_canvas.draw_rect(Rect2(cx - 290.0 * k_rule, 614, 580.0 * k_rule, 2), Color(0, 0, 0, 0.3))
	var conf: String = info.conference
	var k_conf := _out(_seg(s, 0.4, 0.62))
	if conf != "" and k_conf > 0.0:
		var label := Teams.conference_label(conf)
		var lw := _text_w(label, 18) + 46.0
		var cc: Color = Teams.CONFERENCE_COLORS.get(conf, MenuStyle.DIM)
		MenuStyle.draw_slant(_canvas, Rect2(cx - lw * 0.5, 630, lw, 30), Color(0.02, 0.03, 0.07, 0.85 * k_conf), 9)
		MenuStyle.draw_slant(_canvas, Rect2(cx - lw * 0.5, 630, 8, 30), Color(cc, k_conf), 9)
		_text(Vector2(cx - lw * 0.5 + 26, 652), label, 18, cc.lightened(0.3), k_conf)
	# The line ratings pop in on the beat and count up.
	var rat: Dictionary = info.ratings
	if not rat.is_empty():
		for i in 3:
			var tb := Sfx.THEME_BEAT * (1.0 + 0.5 * i)
			var k := _seg(s, tb, tb + 0.2)
			if k <= 0.0:
				continue
			var bc := Vector2(x0 + 90.0 + 210.0 * i, 748.0)
			_xf(bc, 0.0, lerpf(0.55, 1.0, _back(k)))
			MenuStyle.draw_slant(_canvas, Rect2(-84, -51, 180, 110), Color(0, 0, 0, 0.3 * k), 14)
			MenuStyle.draw_slant(_canvas, Rect2(-90, -57, 180, 110), Color(0.03, 0.04, 0.09, 0.94 * k), 14)
			MenuStyle.draw_slant(_canvas, Rect2(-90, 47, 180, 6), Color(accent, k), 1)
			var label: String = RATINGS[i][1]
			_text(Vector2(-83 + (180.0 - _text_w(label, 17)) * 0.5, -30), label, 17, MenuStyle.DIM, k)
			var val := str(roundi(lerpf(50.0, float(rat[RATINGS[i][0]]), _out(_seg(s, tb, tb + 0.45)))))
			MenuStyle.draw_bold(_canvas, Vector2(-86 + (180.0 - MenuStyle.text_width(val, 58)) * 0.5, 32), val, 58,
					Color(1, 1, 1, k), 0, MenuStyle.INK, 0.2, false)
		_xf()
	# The crest slams onto the panel on the beat.
	var c := Vector2(cx, 288.0)
	var k_logo := _seg(s, -0.14, 0.0)
	if k_logo > 0.0:
		var bump := 1.0 + 0.08 * sin(_seg(s, 0.0, 0.32) * PI)
		_crest(info.logo, c, 336.0 * lerpf(2.6, 1.0, k_logo * k_logo) * bump, k_logo, dir * lerpf(0.3, 0.0, k_logo))
	if s >= 0.0:
		_ring(c, s / 0.4, 130.0, 430.0)
	# The star's lower third, on their side of the screen, as the tune's long note lands.
	var k_star := _out(_seg(s, Sfx.THEME_BEAT * 2.5, Sfx.THEME_BEAT * 2.5 + 0.28))
	if k_star > 0.0:
		var title: String = info.star
		var line: String = info.star_line
		var size := _fit(title, 40, 470.0, 26)
		var pw := maxf(430.0, maxf(MenuStyle.text_width(title, size), _text_w(line, 20)) + 70.0)
		var px := (_w - 70.0 - pw + (1.0 - k_star) * 90.0) if left else (70.0 - (1.0 - k_star) * 90.0)
		var py := 716.0
		var tagw := _text_w("STAR PLAYER", 20) + 38.0
		MenuStyle.draw_slant(_canvas, Rect2(px + 4, py - 32, tagw, 32), Color(0.62, 0.82, 0.95, k_star), 11)
		_text(Vector2(px + 22, py - 9), "STAR PLAYER", 20, MenuStyle.INK, k_star)
		_canvas.draw_rect(Rect2(px + 6, py + 6, pw, 98), Color(0, 0, 0, 0.35 * k_star))
		_canvas.draw_rect(Rect2(px, py, pw, 60), Color(col, k_star))
		_canvas.draw_rect(Rect2(px, py + 34, pw, 26), Color(0, 0, 0, 0.16 * k_star))
		_canvas.draw_rect(Rect2(px, py + 60, pw, 38), Color(0.03, 0.04, 0.09, 0.94 * k_star))
		_canvas.draw_rect(Rect2(px, py + 57, pw, 3), Color(accent, k_star))
		MenuStyle.draw_bold(_canvas, Vector2(px + 22, py + 30 + size * 0.36), title, size, Color(1, 1, 1, k_star), 7,
				Color(MenuStyle.INK, k_star), 0.2, false)
		_text(Vector2(px + 24, py + 87), line, 20, MenuStyle.ICE, k_star)


# --- Beat 4: the lockup ------------------------------------------------------------------

func _draw_lockup(s: float) -> void:
	var cx := _w * 0.5
	var mid := BAR_Y + BAR_H * 0.5
	# Both colors sweep in and meet in the middle (the cut), then fold up into the bar.
	var k_in := _seg(s, -LEAD - SWEEP, -LEAD)
	var k_bar := _out(_seg(s, -LEAD, -0.04))
	var y0 := lerpf(-20.0, BAR_Y, k_bar)
	var y1 := lerpf(920.0, BAR_Y + BAR_H, k_bar)
	var gap := 78.0 * k_bar
	# (the seam stays where it is on the screen as the bands shrink toward the top)
	var seam := cx + LEAN * (mid - 450.0) * k_bar
	var xl := lerpf(-260.0, seam - gap, k_in * k_in)
	var xr := lerpf(_w + 260.0, seam + gap, k_in * k_in)
	if k_bar > 0.0:
		_canvas.draw_rect(Rect2(-100, y0 + 12, _w + 200, y1 - y0), Color(0, 0, 0, 0.35 * k_bar))
		_canvas.draw_rect(Rect2(-100, y0 - 7, _w + 200, y1 - y0 + 14), MenuStyle.INK)
	for t in 2:
		var left := t == 0
		var x := xl if left else xr
		var info := _info[t]
		_band(left, x, y0, y1, info.color)
		_band(left, x, lerpf(y0, y1, 0.58), y1, Color(0, 0, 0, 0.16))
		_band(left, x, y1 - 7.0, y1, info.accent)
		_stripe(x - (16.0 if left else -6.0), 10.0, y0, y1, info.accent)
		_stripe(x - (28.0 if left else -22.0), 4.0, y0, y1, Color(1, 1, 1, 0.7))
	if s < -LEAD:
		return
	# Names along the bar, out from the crests.
	var k_name := _out(_seg(s, 0.2, 0.5))
	if k_name > 0.0:
		for t in 2:
			var info := _info[t]
			var dir := -1.0 if t == 0 else 1.0
			var room := cx - 268.0 - CREST * 0.5 - 60.0
			var name: String = info.name
			var size := _fit(name, 58, room, 26)
			var nw := MenuStyle.text_width(name, size)
			var inner := cx + dir * (268.0 + CREST * 0.5 + 18.0 + (1.0 - k_name) * -50.0)
			var nx := inner - nw if t == 0 else inner
			var city: String = info.city
			if city != "":
				var cw := _text_w(city, 22)
				_text(Vector2(inner - cw if t == 0 else inner, BAR_Y + 54), city, 22, Color.WHITE, k_name * 0.9)
			_bold(Vector2(nx, BAR_Y + 80 + size * 0.5), name, size, k_name)
	# HOME / AWAY tabs hanging under the bar's ends.
	var k_tab := _out(_seg(s, 0.4, 0.65))
	if k_tab > 0.0:
		for t in 2:
			var label := ("HOME   ·   " if t == 0 else "AWAY   ·   ") + str(_info[t].who)
			var lw := _text_w(label, 18) + 40.0
			var tx := 48.0 if t == 0 else _w - 48.0 - lw
			var ty := BAR_Y + BAR_H + 7.0 - (1.0 - k_tab) * 34.0
			MenuStyle.draw_slant(_canvas, Rect2(tx, ty, lw, 32), Color(0.03, 0.04, 0.09, 0.92 * k_tab), 9)
			_text(Vector2(tx + 22, ty + 23), label, 18, MenuStyle.ICE, k_tab)
	_draw_tape(s)
	# The crests fly in along the bar, collide on the beat and spring back to their places.
	var k_fly := _seg(s, -0.16, 0.0)
	if k_fly > 0.0:
		var k_back := _back(_seg(s, 0.0, 0.34))
		var off := lerpf(780.0, 92.0, k_fly * k_fly) if s < 0.0 else lerpf(92.0, 268.0, k_back)
		var size := CREST * (lerpf(1.22, 1.0, _seg(s, 0.0, 0.3)) if s >= 0.0 else 1.22)
		var rot := 0.28 * (1.0 - _seg(s, 0.0, 0.4)) * cos(maxf(s, 0.0) * 16.0)
		_crest(_info[0].logo, Vector2(cx - off, mid), size, k_fly, -rot)
		_crest(_info[1].logo, Vector2(cx + off, mid), size, k_fly, rot)
	if s < 0.0:
		return
	# VS punches in between them.
	var k_vs := _seg(s, 0.02, 0.24)
	if k_vs > 0.0:
		var vw := MenuStyle.text_width("VS", 92)
		_xf(Vector2(cx, mid), -0.05, lerpf(2.6, 1.0, _out(k_vs)))
		MenuStyle.draw_bold(_canvas, Vector2(-vw * 0.5 - 4, 33), "VS", 92, Color(GOLD, k_vs), 18, Color(MenuStyle.INK, k_vs), 0.2, k_vs > 0.9)
		_xf()
	# The clash: a flash, a ring, sparks off the steel.
	var c := Vector2(cx, mid)
	_ring(c, s / 0.5, 60.0, 760.0)
	var f := s / 0.75
	if f < 1.0:
		for i in _sparks.size():
			var sp := _sparks[i]
			var dirv := Vector2(cos(sp.x), sin(sp.x) * 0.75)
			var dist := 40.0 + 620.0 * sp.y * _out(f)
			var tail := 90.0 * sp.z * (1.0 - f)
			var drop := Vector2(0, 260.0 * f * f)   # they fall as they fade
			var hue: Color = [Color.WHITE, GOLD, _info[i % 2].accent][i % 3]
			_canvas.draw_line(_off + c + dirv * (dist - tail) + drop, _off + c + dirv * dist + drop, Color(hue, 1.0 - f), 4.0 * (1.0 - f) + 1.0, true)
	var flash := (1.0 - _seg(s, 0.0, 0.28)) * 0.8
	if flash > 0.0:
		_canvas.draw_rect(Rect2(-100, -100, _w + 200, 1100), Color(1, 1, 1, flash))


## The tale of the tape: each line's rating, a bar growing out from the middle for each
## team; the better one is lit. Then the strip along the bottom: where and how they play.
func _draw_tape(s: float) -> void:
	var cx := _w * 0.5
	var beat := Sfx.THEME_BEAT
	if _has_ratings(3):
		var k_head := _out(_seg(s, beat, beat + 0.25))
		if k_head > 0.0:
			var head := "TALE OF THE TAPE"
			var hw := _text_w(head, 22) + 48.0
			MenuStyle.draw_slant(_canvas, Rect2(cx - hw * 0.5 - 6, 704 + (1.0 - k_head) * 20.0, hw, 34), Color(MenuStyle.RED, k_head), 12)
			_text(Vector2(cx - hw * 0.5 + 20, 729 + (1.0 - k_head) * 20.0), head, 22, Color.WHITE, k_head)
		for i in 3:
			var tr := beat * (2.0 + 0.5 * i)
			var k := _out(_seg(s, tr, tr + 0.4))
			if k <= 0.0:
				continue
			var y := 744.0 + 38.0 * i
			var vals := [int(_info[0].ratings[RATINGS[i][0]]), int(_info[1].ratings[RATINGS[i][0]])]
			var label: String = RATINGS[i][1]
			MenuStyle.draw_slant(_canvas, Rect2(cx - 118, y, 230, 34), Color(MenuStyle.NAVY, 0.95 * k), 10)
			_text(Vector2(cx - _text_w(label, 18) * 0.5, y + 24), label, 18, MenuStyle.ICE, k)
			for t in 2:
				var dir := -1.0 if t == 0 else 1.0
				var lead: bool = vals[t] >= vals[1 - t]
				var full := clampf(70.0 + (vals[t] - 60.0) / 40.0 * 300.0, 50.0, 370.0)
				var length := full * k
				var x0 := cx + dir * 196.0
				var track := Rect2(x0 if t == 1 else x0 - 370.0, y + 4, 370.0, 26)
				_canvas.draw_rect(track, Color(0.02, 0.03, 0.07, 0.78 * k))
				var bar := Rect2(x0 if t == 1 else x0 - length, y + 4, length, 26)
				_canvas.draw_rect(bar, Color(_info[t].color, k))
				_canvas.draw_rect(Rect2(bar.position + Vector2(0, 17), Vector2(length, 9)), Color(0, 0, 0, 0.2 * k))
				_canvas.draw_rect(Rect2(bar.end.x - 5.0 if t == 1 else bar.position.x, y + 4, 5, 26), Color(_info[t].accent, k))
				var val := str(roundi(lerpf(50.0, float(vals[t]), k)))
				var vw := MenuStyle.text_width(val, 30)
				MenuStyle.draw_bold(_canvas, Vector2(cx + dir * 156.0 - vw * 0.5, y + 28), val, 30,
						Color(Color.WHITE if lead else MenuStyle.DIM, k), 5, Color(MenuStyle.INK, k), 0.2, false)
	var k_strip := _seg(s, beat * 4.0, beat * 4.0 + 0.3)
	if k_strip > 0.0:
		_canvas.draw_rect(Rect2(-100, 860, _w + 200, 60), Color(0.02, 0.03, 0.06, 0.82 * k_strip))
		_canvas.draw_rect(Rect2(-100, 857, _w + 200, 3), Color(MenuStyle.RED, k_strip))
		_text(Vector2(48, 885), "%s   ·   %s" % [_title.venue, _title.rules], 18, MenuStyle.ICE, k_strip)
