class_name ArenaScreen
extends Control
## What one of the scoreboard's video screens shows (drawn into a SubViewport by Arena):
##   - in a game: both teams (color, crest, abbreviation, score), the period and clock,
##     shots on goal; wide screens lay the teams out side by side, narrow ones stack them
##     (visitors first, as on the TV scorebug);
##   - after a goal: GOAL! in the scorers' colors with their crest, pulsing;
##   - with no game (menus): the home crest, or the game's name.
## A `classic` screen is an old lamp scoreboard instead (a community rink's or an outdoor
## rink's): HOME and GUEST scores and the clock in seven-segment digits, the period, shots.

const AMBER := Color(1.0, 0.72, 0.18)
const BG := Color(0.015, 0.015, 0.025)

var arena: Arena
var classic := false
var _key := ""


func _process(_delta: float) -> void:
	# Redraw when what's shown changes (and every frame while GOAL pulses).
	var k := _state_key()
	if k != _key or k.begins_with("goal"):
		_key = k
		queue_redraw()


func _state_key() -> String:
	if arena == null:
		return ""
	if arena.flash_until > Time.get_ticks_msec() / 1000.0:
		return "goal%d" % arena.flash_team
	var d := arena.match_ref
	if d == null or not is_instance_valid(d):
		return "idle%d" % arena.home_team
	return "%s|%s|%d|%d|%s|%s" % [_period(d), _clock(d), d.score[0], d.score[1], d.stats.shots[0], d.stats.shots[1]]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if arena == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if classic:
		_draw_classic(now)
		return
	if arena.flash_until > now:
		_draw_goal(now)
		return
	var d := arena.match_ref
	if d == null or not is_instance_valid(d):
		_draw_idle()
		return
	if size.x > size.y * 1.4:
		_draw_wide(d)
	else:
		_draw_narrow(d)


# --- Game state as text ---

static func _period(d: Node) -> String:
	if d.phase == MatchDirector.Phase.FINAL:
		return "FINAL" if d.period <= d.periods else "FINAL/" + d.period_name(d.period)
	return d.period_name(d.period)


static func _clock(d: Node) -> String:
	if d.phase == MatchDirector.Phase.FINAL or d.period_name(d.period) == "SO":
		return ""
	var c := int(ceil(d.clock))
	return "%d:%02d" % [c / 60, c % 60]


func _team_id(d: Node, t: int) -> int:
	return d.team_ids[t]


# --- Layouts ---

func _text(s: String, pos: Vector2, width: float, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string(MenuStyle.font(0.0), pos, s, align, width, font_size, color)


func _logo(team: int, rect: Rect2) -> void:
	MenuStyle.draw_logo(self, MenuStyle.team_logo(team), rect)


func _draw_wide(d: Node) -> void:
	var w := size.x
	var h := size.y
	var cw := w * 0.34
	for t in 2:
		var id := _team_id(d, t)
		var x := 0.0 if t == 1 else w - cw   # visitors on the left, like the TV scorebug
		var col := MenuStyle.team_color(id)
		draw_rect(Rect2(x, 0, cw, h), col.darkened(0.7))
		draw_rect(Rect2(x, 0, cw, h * 0.2), col)
		_text(str(Teams.team(id).abbr), Vector2(x, h * 0.16), cw, int(h * 0.13), Color.WHITE)
		_logo(id, Rect2(x + cw * 0.2, h * 0.24, cw * 0.6, h * 0.34))
		_text(str(d.score[t]), Vector2(x, h * 0.95), cw, int(h * 0.36), Color.WHITE)
	var cx := cw
	var mw := w - cw * 2.0
	_text(_period(d), Vector2(cx, h * 0.2), mw, int(h * 0.12), Color.WHITE)
	var clock := _clock(d)
	if clock != "":
		_text(clock, Vector2(cx, h * 0.5), mw, int(h * 0.22), AMBER)
	_text("SHOTS", Vector2(cx, h * 0.7), mw, int(h * 0.07), Color(0.6, 0.62, 0.68))
	_text("%s     %s" % [d.stats.shots[1], d.stats.shots[0]], Vector2(cx, h * 0.86), mw, int(h * 0.12), Color.WHITE)


func _draw_narrow(d: Node) -> void:
	var w := size.x
	var h := size.y
	_text(_period(d), Vector2(0, h * 0.13), w, int(h * 0.1), Color.WHITE)
	var clock := _clock(d)
	if clock != "":
		_text(clock, Vector2(0, h * 0.38), w, int(h * 0.24), AMBER)
	for t in 2:
		var id := _team_id(d, t)
		var y := h * (0.45 + 0.275 * (1 - t))   # visitors on top
		var rh := h * 0.25
		var col := MenuStyle.team_color(id)
		draw_rect(Rect2(0, y, w, rh), col.darkened(0.65))
		draw_rect(Rect2(0, y, w * 0.06, rh), col)
		_logo(id, Rect2(w * 0.08, y + rh * 0.08, rh * 0.84, rh * 0.84))
		_text(str(Teams.team(id).abbr), Vector2(w * 0.1 + rh, y + rh * 0.72), w * 0.4, int(rh * 0.5), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_text(str(d.score[t]), Vector2(w * 0.62, y + rh * 0.82), w * 0.34, int(rh * 0.8), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_goal(now: float) -> void:
	var w := size.x
	var h := size.y
	var d := arena.match_ref
	var id := -1
	if d != null and is_instance_valid(d) and arena.flash_team >= 0:
		id = _team_id(d, arena.flash_team)
	var col := MenuStyle.team_color(id) if id >= 0 else Color(0.8, 0.1, 0.1)
	var pulse := 0.5 + 0.5 * sin(now * 9.0)
	draw_rect(Rect2(Vector2.ZERO, size), col.lerp(Color.WHITE, 0.25 * pulse))
	# Light rays from the middle.
	var c := Vector2(w * 0.5, h * 0.42)
	for i in 12:
		var a := now * 0.8 + TAU * i / 12.0
		var p1 := c + Vector2(cos(a), sin(a)) * w
		var p2 := c + Vector2(cos(a + 0.12), sin(a + 0.12)) * w
		draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(1, 1, 1, 0.08))
	if id >= 0:
		_logo(id, Rect2(w * 0.5 - h * 0.2, h * 0.04, h * 0.4, h * 0.36))
	var fs := int(minf(h * 0.36, w * 0.28) * (1.0 + 0.06 * pulse))
	_text("GOAL!", Vector2(0, h * 0.78) + Vector2(5, 5), w, fs, Color(0, 0, 0, 0.45))
	_text("GOAL!", Vector2(0, h * 0.78), w, fs, Color.WHITE)
	if id >= 0:
		_text(str(Teams.team(id).name).to_upper(), Vector2(0, h * 0.94), w, int(h * 0.1), Color.WHITE)


func _draw_idle() -> void:
	var w := size.x
	var h := size.y
	if arena.home_team >= 0:
		draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.team_color(arena.home_team).darkened(0.6))
		_logo(arena.home_team, Rect2(w * 0.5 - h * 0.35, h * 0.08, h * 0.7, h * 0.62))
		_text(str(Teams.team(arena.home_team).name).to_upper(), Vector2(0, h * 0.9), w, int(h * 0.13), Color.WHITE)
	else:
		_text("KNOCKOUT", Vector2(0, h * 0.45), w, int(minf(h * 0.24, w * 0.17)), Color.WHITE)
		_text("HOCKEY", Vector2(0, h * 0.75), w, int(minf(h * 0.24, w * 0.17)), AMBER)


# --- The classic lamp board ---

const LAMP_RED := Color(1.0, 0.16, 0.1)
const LAMP_OFF := Color(0.09, 0.07, 0.06)
## Lit segments of each digit (a top, b top right, c bottom right, d bottom, e bottom left,
## f top left, g middle).
const SEGMENTS := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
	"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": ""}


func _draw_classic(now: float) -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.025))
	var d := arena.match_ref
	var live := d != null and is_instance_valid(d)
	var score := [0, 0]
	var clock := "20:00"
	var per := "1"
	var shots := [0, 0]
	if live:
		score = [int(d.score[0]), int(d.score[1])]
		clock = _clock(d)
		per = _period(d)
		shots = [int(d.stats.shots[0]), int(d.stats.shots[1])]
	var goal := arena.flash_until > now
	var blink := goal and fmod(now, 0.5) < 0.25
	var white := Color(0.92, 0.92, 0.88)
	for t in 2:
		var x := 0.0 if t == 0 else w * 0.68
		var cw := w * 0.32
		var id := -1
		if live:
			id = _team_id(d, t)
		elif t == 0:
			id = arena.home_team
		_text("HOME" if t == 0 else "GUEST", Vector2(x, h * 0.17), cw, int(h * 0.12), white)
		if id >= 0:
			draw_rect(Rect2(x + cw * 0.18, h * 0.21, cw * 0.64, h * 0.035), MenuStyle.team_color(id))
		var lit := not (blink and arena.flash_team == t)
		_digits("%2d" % score[t], Rect2(x + cw * 0.14, h * 0.3, cw * 0.72, h * 0.42), LAMP_RED if lit else LAMP_OFF)
		_text("SHOTS %d" % shots[t], Vector2(x, h * 0.9), cw, int(h * 0.08), Color(0.7, 0.7, 0.66))
	# The clock in the middle, the period under it.
	if clock != "":
		var parts := clock.split(":")
		var r := Rect2(w * 0.35, h * 0.1, w * 0.3, h * 0.32)
		_digits("%2s" % parts[0], Rect2(r.position, Vector2(r.size.x * 0.42, r.size.y)), AMBER)
		var cx := r.position.x + r.size.x * 0.5
		for dy: float in [0.3, 0.7]:
			draw_rect(Rect2(cx - r.size.y * 0.04, r.position.y + r.size.y * dy - r.size.y * 0.04, r.size.y * 0.08, r.size.y * 0.08), AMBER)
		_digits(parts[1], Rect2(r.position.x + r.size.x * 0.58, r.position.y, r.size.x * 0.42, r.size.y), AMBER)
	if goal:
		if not blink:
			_text("GOAL", Vector2(w * 0.3, h * 0.84), w * 0.4, int(h * 0.26), LAMP_RED)
	else:
		_text("PERIOD", Vector2(w * 0.35, h * 0.56), w * 0.3, int(h * 0.09), white)
		_text(per, Vector2(w * 0.35, h * 0.86), w * 0.3, int(h * 0.26), AMBER)


## A row of seven-segment digits filling `r` (unlit segments show faintly).
func _digits(s: String, r: Rect2, col: Color) -> void:
	var n := s.length()
	var cw := r.size.x / n
	for i in n:
		var cell := Rect2(r.position.x + cw * i + cw * 0.1, r.position.y, cw * 0.8, r.size.y)
		_digit(s[i], cell, col)


func _digit(ch: String, r: Rect2, col: Color) -> void:
	var on: String = SEGMENTS.get(ch, "")
	var t := minf(r.size.x * 0.18, r.size.y * 0.1)
	var g := t * 0.25
	var x0 := r.position.x
	var x1 := r.position.x + r.size.x
	var y0 := r.position.y
	var ym := r.position.y + r.size.y * 0.5
	var y1 := r.position.y + r.size.y
	var segs := {
		"a": Rect2(x0 + t + g, y0, r.size.x - 2 * (t + g), t),
		"g": Rect2(x0 + t + g, ym - t * 0.5, r.size.x - 2 * (t + g), t),
		"d": Rect2(x0 + t + g, y1 - t, r.size.x - 2 * (t + g), t),
		"f": Rect2(x0, y0 + t * 0.5 + g, t, ym - y0 - t - g * 2),
		"b": Rect2(x1 - t, y0 + t * 0.5 + g, t, ym - y0 - t - g * 2),
		"e": Rect2(x0, ym + t * 0.5 + g, t, y1 - ym - t - g * 2),
		"c": Rect2(x1 - t, ym + t * 0.5 + g, t, y1 - ym - t - g * 2),
	}
	for k: String in segs:
		draw_rect(segs[k], col if on.contains(k) else LAMP_OFF)
