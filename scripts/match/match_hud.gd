class_name MatchHud
extends CanvasLayer
## The game's TV graphics, in the front-end menu style (MenuStyle), drawn on the 1600 x 900
## design canvas:
##   - the scorebug, top left: each team's plate (color, crest, abbreviation), score,
##     shots under it, then period and clock; a tab under the clock for the power play
##     (in the team's color, with the time left) or a delayed offside / penalty.
##   - banners: a slanted bar that wipes in across the middle (GOAL, BIG HIT, period
##     calls), in the team's colors when it's a team's moment.
##   - lower thirds: the goal card (scorer, assists) and the penalty card.
##   - flashes: a small tab under the banner spot for quick calls.
##   - hints, bottom left, only when they matter (faceoff timing, goalie with the puck,
##     how to pause during stoppages).
## Timing runs on real time, so slow motion doesn't drag the graphics.

const BUG_POS := Vector2(36, 26)
const TEAM_W := 156.0
const SCORE_W := 58.0
const CLOCK_W := 168.0
const ROW_H := 50.0
const SUB_H := 24.0
const WIPE := 0.22            ## s for banners and cards to slide in / out

var d: MatchDirector
var _canvas: Control
var _banner := {}             ## text, team, until, start
var _card := {}               ## kind ("goal" / "penalty"), team, title, line, sub, until, start
var _flash := {}              ## text, until, start
var _now := 0.0               ## real seconds the HUD has been running (see _process)
var _last_tick := 0.0


func setup(director: MatchDirector) -> void:
	d = director
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	_canvas.draw.connect(_draw)


## A big call across the middle. `team` >= 0 dresses it in that team's colors and crest.
func banner(text: String, seconds: float, team := -1) -> void:
	_banner = {"text": text, "team": team, "start": _now, "until": _now + seconds}


## A quick call in a small tab.
func flash(text: String) -> void:
	_flash = {"text": text, "start": _now, "until": _now + 1.1}


## Lower third: who scored, and the assists.
func goal_card(team: int, scorer: Skater, assists: Array, seconds: float) -> void:
	var names: Array[String] = []
	for a: Skater in assists:
		names.append(MenuStyle.player_name(a))
	_card = {"kind": "goal", "team": team, "title": MenuStyle.player_name(scorer),
		"line": ("ASSISTS  " + ",  ".join(names)) if not names.is_empty() else "UNASSISTED",
		"sub": d.box.line_text(scorer) if d else "", "start": _now, "until": _now + seconds}


## Lower third: who's going to the box, and for what.
func penalty_card(team: int, offender: Skater, foul: String, minutes: String, seconds: float) -> void:
	_card = {"kind": "penalty", "team": team, "title": MenuStyle.player_name(offender),
		"line": "%s  ·  %s" % [foul.to_upper(), minutes], "sub": "", "start": _now, "until": _now + seconds}


## Lower third: a player hurt and out for the game.
func injury_card(team: int, s: Skater, seconds: float) -> void:
	_card = {"kind": "injury", "team": team, "title": MenuStyle.player_name(s),
		"line": "INJURED  ·  OUT FOR THE GAME", "sub": "", "start": _now, "until": _now + seconds}


func _process(_delta: float) -> void:
	# The wall clock, so slow motion and load stalls don't drag the graphics; a long gap
	# (the game was paused) only counts a moment, so a banner survives the pause menu.
	var t := Time.get_ticks_usec() / 1000000.0
	if _last_tick > 0.0:
		_now += minf(t - _last_tick, 0.5)
	_last_tick = t
	if d != null and _canvas != null:
		_canvas.queue_redraw()


## 0 → 1 sliding in, 1 holding, 1 → 0 sliding out.
func _show(item: Dictionary) -> float:
	if item.is_empty() or _now > item.until + WIPE:
		return 0.0
	var t_in := clampf((_now - item.start) / WIPE, 0.0, 1.0)
	var t_out := clampf((item.until + WIPE - _now) / WIPE, 0.0, 1.0)
	return ease(minf(t_in, t_out), -2.0)


func _draw() -> void:
	if d == null:
		return
	_draw_bug()
	_draw_banner()
	_draw_card()
	_draw_flash()
	_draw_hints()


# --- Scorebug --------------------------------------------------------------------------

func _draw_bug() -> void:
	var ci := _canvas
	var p := BUG_POS
	var order := [1, 0]   # away, then home (the broadcast convention)
	var w := (TEAM_W + SCORE_W) * 2.0 + CLOCK_W
	# Shadow and the dark base, a red hairline on top.
	ci.draw_rect(Rect2(p + Vector2(5, 6), Vector2(w, ROW_H + SUB_H)), Color(0, 0, 0, 0.35))
	ci.draw_rect(Rect2(p, Vector2(w, ROW_H + SUB_H)), Color(0.03, 0.04, 0.09, 0.92))
	var x := p.x
	var so := not d.shootout.is_empty() and d.shootout.has("results")
	for t: int in order:
		var id: int = d.team_ids[t]
		var col := MenuStyle.team_color(id)
		# Team plate: color with a darker lower half, the crest and the abbreviation.
		ci.draw_rect(Rect2(x, p.y, TEAM_W, ROW_H), col)
		ci.draw_rect(Rect2(x, p.y + ROW_H * 0.55, TEAM_W, ROW_H * 0.45), Color(0, 0, 0, 0.18))
		var logo := MenuStyle.team_logo(id)
		if logo:
			ci.draw_texture_rect(logo, Rect2(x + 6, p.y + 4, ROW_H - 8, ROW_H - 8), false)
		MenuStyle.draw_bold(ci, Vector2(x + ROW_H + 2, p.y + 36), str(Teams.team(id).abbr), 28,
				Color.WHITE, 6, MenuStyle.INK, 0.2, false)
		# Score: white on ink.
		var sx := x + TEAM_W
		ci.draw_rect(Rect2(sx, p.y, SCORE_W, ROW_H), MenuStyle.INK)
		var sc := str(d.score[t])
		MenuStyle.draw_bold(ci, Vector2(sx + (SCORE_W - MenuStyle.text_width(sc, 34)) * 0.5, p.y + 38), sc, 34,
				Color.WHITE, 0, MenuStyle.INK, 0.2, false)
		# Under the plate: shots on goal (shootout: the attempts as dots).
		var sub := ("SO  " + _so(d.shootout.results[t])) if so else "SOG  %d" % d.shots_on_goal(t)
		ci.draw_string(MenuStyle.font(0.12), Vector2(x + 10, p.y + ROW_H + 18), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuStyle.DIM)
		x += TEAM_W + SCORE_W
	# Period and clock on brushed steel.
	var cr := Rect2(x, p.y, CLOCK_W, ROW_H)
	ci.draw_polygon(PackedVector2Array([cr.position, cr.position + Vector2(cr.size.x, 0), cr.end, cr.position + Vector2(0, cr.size.y)]),
			PackedColorArray([Color(0.92, 0.94, 0.97), Color(0.78, 0.81, 0.87), Color(0.6, 0.64, 0.72), Color(0.72, 0.76, 0.83)]))
	var per := d.period_name(d.period)
	var c := int(ceil(d.clock))
	var time := "" if d.period_name(d.period) == "SO" else "%d:%02d" % [c / 60, c % 60]
	if d.phase == MatchDirector.Phase.FINAL:
		per = "FINAL" if d.period <= d.periods else ("FINAL/" + d.period_name(d.period))
		time = ""
	var f := MenuStyle.font(0.2)
	ci.draw_string(f, Vector2(x + 14, p.y + 34), per, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, MenuStyle.RED_DARK)
	if time != "":
		var tw := MenuStyle.text_width(time, 30)
		ci.draw_string(f, Vector2(x + CLOCK_W - tw - 14, p.y + 37), time, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, MenuStyle.INK)
	ci.draw_rect(Rect2(p - Vector2(0, 3), Vector2(w, 3)), MenuStyle.RED)
	_draw_status(Vector2(x, p.y + ROW_H))


## The tab under the clock: power play, else a delayed call.
func _draw_status(at: Vector2) -> void:
	var text := ""
	var col := MenuStyle.RED
	var s0 := d.strength(0)
	var s1 := d.strength(1)
	if s0 != s1 and d.phase != MatchDirector.Phase.FINAL:
		var pp := 0 if s0 > s1 else 1
		col = MenuStyle.team_color(d.team_ids[pp])
		var tag := "POWER PLAY" if maxi(s0, s1) - mini(s0, s1) == 1 else "%d ON %d" % [maxi(s0, s1), mini(s0, s1)]
		text = "%s  %s" % [tag, _mmss(d.lineup(1 - pp).box_time_left())]
	elif d.rules and d.rules.has_delayed_penalty():
		text = "DELAYED PENALTY"
	elif d.rules and d.rules.offside_team >= 0:
		text = "DELAYED OFFSIDE"
	elif d.pulled[0] or d.pulled[1]:
		text = "EMPTY NET"
		col = MenuStyle.team_color(d.team_ids[0 if d.pulled[0] else 1])
	if text == "":
		return
	var w := maxf(CLOCK_W, MenuStyle.text_width(text, 16, 0.12) + 24)
	_canvas.draw_rect(Rect2(at, Vector2(w, SUB_H)), col)
	_canvas.draw_rect(Rect2(at + Vector2(0, SUB_H - 3), Vector2(w, 3)), Color(0, 0, 0, 0.3))
	MenuStyle.draw_bold(_canvas, at + Vector2(12, 18), text, 16, Color.WHITE, 4, MenuStyle.INK, 0.12, false)


# --- Banners, cards, flashes -----------------------------------------------------------

func _draw_banner() -> void:
	var k := _show(_banner)
	if k <= 0.0:
		return
	var ci := _canvas
	var cw := _canvas.size.x
	var text: String = _banner.text
	var team: int = _banner.team
	var size := 76 if text.length() <= 14 else (58 if text.length() <= 24 else 44)
	var tw := MenuStyle.text_width(text, size)
	var logo: Texture2D = MenuStyle.team_logo(d.team_ids[team]) if team >= 0 else null
	var w := tw + 140.0 + (120.0 if logo else 0.0)
	var h := 112.0
	var y := 268.0
	# Wipes in from the left: the bar grows, the text slides along with it.
	var x := (cw - w) * 0.5
	var col: Color = MenuStyle.team_color(d.team_ids[team]) if team >= 0 else MenuStyle.RED
	var grow := w * k
	MenuStyle.draw_slant(ci, Rect2(x - 18 + 8, y - 8 + 10, grow + 36, h + 16), Color(0, 0, 0, 0.35), 30)
	MenuStyle.draw_slant(ci, Rect2(x - 18, y - 8, grow + 36, h + 16), MenuStyle.INK, 30)
	MenuStyle.draw_slant(ci, Rect2(x, y, grow, h), col, 26)
	MenuStyle.draw_slant(ci, Rect2(x, y + h * 0.58, grow, h * 0.42), Color(0, 0, 0, 0.16), 11)
	MenuStyle.draw_slant(ci, Rect2(x + 10, y - 4, grow * 0.7, 4), Color(1, 1, 1, 0.75), 2)
	if k < 0.7:
		return
	var ta := clampf((k - 0.7) / 0.25, 0.0, 1.0)   # the text fades with the bar
	var tx := x + 70.0
	if logo:
		ci.draw_texture_rect(logo, Rect2(x + 40, y + 6, h - 12, h - 12), false, Color(1, 1, 1, ta))
		tx += 120.0
	MenuStyle.draw_bold(ci, Vector2(tx, y + h * 0.5 + size * 0.36), text, size, Color(1, 1, 1, ta),
			int(size * 0.2), Color(MenuStyle.INK, ta), 0.2, ta > 0.9)


func _draw_card() -> void:
	var k := _show(_card)
	if k <= 0.0:
		return
	var ci := _canvas
	var team: int = _card.team
	var col := MenuStyle.team_color(d.team_ids[team])
	var goal: bool = _card.kind == "goal"
	var title: String = _card.title
	var w := maxf(560.0, maxf(MenuStyle.text_width(title, 44) + 170, MenuStyle.text_width(_card.line, 20, 0.12) + 170))
	var h := 104.0
	var x := lerpf(-w - 60.0, 48.0, k)
	var y := 690.0
	# The tag: GOAL in red, PENALTY in amber, INJURY in white.
	var injury: bool = _card.kind == "injury"
	var tag := "GOAL" if goal else ("INJURY" if injury else "PENALTY")
	var tag_col := MenuStyle.RED if goal else (Color(0.92, 0.94, 0.97) if injury else Color(0.95, 0.66, 0.08))
	var tagw := MenuStyle.text_width(tag, 24, 0.12) + 40
	MenuStyle.draw_slant(ci, Rect2(x + 4, y - 34, tagw, 34), tag_col, 12)
	ci.draw_string(MenuStyle.font(0.12), Vector2(x + 22, y - 9), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE if goal else MenuStyle.INK)
	# Plate: team color, crest, name, the line below on ink.
	ci.draw_rect(Rect2(x + 6, y + 6, w, h), Color(0, 0, 0, 0.35))
	ci.draw_rect(Rect2(x, y, w, h * 0.6), col)
	ci.draw_rect(Rect2(x, y + h * 0.6, w, h * 0.4), Color(0.03, 0.04, 0.09, 0.94))
	ci.draw_rect(Rect2(x, y + h * 0.6 - 3, w, 3), tag_col)
	var logo := MenuStyle.team_logo(d.team_ids[team])
	if logo:
		ci.draw_texture_rect(logo, Rect2(x + 16, y + 4, h - 8, h - 8), false)
	var tx := x + 130.0
	MenuStyle.draw_bold(ci, Vector2(tx, y + 50), title, 44, Color.WHITE, 8, MenuStyle.INK, 0.2, false)
	ci.draw_string(MenuStyle.font(0.12), Vector2(tx, y + h - 13), _card.line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MenuStyle.ICE)


func _draw_flash() -> void:
	var k := _show(_flash)
	if k <= 0.0:
		return
	var text: String = _flash.text
	var tw := MenuStyle.text_width(text, 28)
	var w := tw + 60.0
	var x := (_canvas.size.x - w) * 0.5
	var y := 410.0 + (1.0 - k) * 30.0
	var a := k
	MenuStyle.draw_slant(_canvas, Rect2(x + 5, y + 6, w, 48), Color(0, 0, 0, 0.3 * a), 14)
	MenuStyle.draw_slant(_canvas, Rect2(x, y, w, 48), Color(MenuStyle.NAVY, 0.94 * a), 14)
	MenuStyle.draw_slant(_canvas, Rect2(x, y + 45, w, 3), Color(MenuStyle.RED, a), 1)
	MenuStyle.draw_bold(_canvas, Vector2(x + 34, y + 35), text, 28, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)


# --- Hints -----------------------------------------------------------------------------

func _draw_hints() -> void:
	if _show(_card) > 0.0:
		return   # the lower third has the corner
	var hints: Array[String] = []
	var any_human := false
	for t in 2:
		var ctl := d.control(t)
		if ctl == null:
			continue
		for h in ctl.humans:
			var sk := ctl.skater_of(h)
			if sk == null:
				continue
			any_human = true
			if sk is Goalie and not hints.has("GOALIE HAS IT   CROSS pass  ·  SQUARE clear  ·  TRIANGLE cover"):
				hints.append("GOALIE HAS IT   CROSS pass  ·  SQUARE clear  ·  TRIANGLE cover")
		var pull := d.pull_hint(t)
		if pull != "" and not hints.has(pull):
			hints.append(pull)
	if d.phase == MatchDirector.Phase.FACEOFF and any_human:
		hints.append("FACEOFF   press pass or shoot right as the puck drops")
	if d.phase in [MatchDirector.Phase.STOPPAGE, MatchDirector.Phase.FACEOFF] and any_human:
		hints.append("START / ESC   pause menu and controls")
	var y := 860.0
	var f := MenuStyle.font(0.12)
	for i in range(hints.size() - 1, -1, -1):
		var w := MenuStyle.text_width(hints[i], 17, 0.12) + 28
		_canvas.draw_rect(Rect2(30, y - 24, w, 30), Color(0.03, 0.04, 0.09, 0.78))
		_canvas.draw_rect(Rect2(30, y - 24, 4, 30), MenuStyle.RED)
		_canvas.draw_string(f, Vector2(46, y - 3), hints[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MenuStyle.ICE)
		y -= 38.0


static func _mmss(t: float) -> String:
	var c := int(ceil(t))
	return "%d:%02d" % [c / 60, c % 60]


static func _so(results: Array) -> String:
	var out := ""
	for r in results:
		out += "● " if r else "○ "
	return out if out != "" else "–"
