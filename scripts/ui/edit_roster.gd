extends Control
## CUSTOMIZE > EDIT ROSTER: two rosters side by side. Each side shows a team or Free
## Agency (created players and generated ones, see CustomPlayers / FreeAgentGen, plus
## anyone released). Changes save as they're made (Rosters) and every game uses them.
##
##   Left / right: which side you're on.  Up / down: pick a player.
##   L1 / R1 (Q / E): change that side's team.
##   Cross (Enter): send the player to the other side's team (sign, release or move).
##   Square (K): trade: mark a player, then Square on one on the other side swaps them.
##   Triangle (I): sort by position or by overall.
##   Select (Tab), twice: reset every roster (sheet players home, the rest to Free Agency).
##   Circle (Esc): drop the trade mark, else back to CUSTOMIZE.
##
## A team keeps what it needs to dress a game (Rosters.MIN_*) and carries at most
## Rosters.MAX_PLAYERS. A player who joins a team where his number is taken gets the
## closest free one.
##
## `-- shot=<png> [wait=<s>] [left=<abbr|FA>] [right=<abbr|FA>] [side=0|1] [sel=<n>]`
## saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const MENU_SELECT := 4          ## EDIT ROSTER's place in the CUSTOMIZE list
const PANEL_W := 720.0
const PANEL_X := [50.0, 830.0]
const PANEL_Y := 150.0
const LIST_Y := 280.0           ## first row's top
const ROW_H := 33.0
const VISIBLE := 13
const DETAIL_Y := 742.0
const RESET_WARN := 3.0
const POS_ORDER := ["C", "LW", "RW", "D", "G"]
## Columns (x from the panel's left).
const COL_NUM := 34.0
const COL_NAME := 76.0
const COL_POS := 400.0
const COL_STYLE := 462.0
const COL_OVR := 668.0

var _clubs: Array[String] = []  ## FREE_AGENT then every team's abbr, in menu order
var _team_of := {}              ## abbr -> Teams.LIST index
var _club := [0, 1]             ## each side's index into _clubs
var _rows := [[], []]           ## each side's players, sorted
var _sel := [0, 0]
var _top := [0, 0]              ## first visible row per side
var _side := 0
var _by_overall := false
var _mark := {}                 ## the row marked for a trade ({} = none)
var _mark_side := -1
var _reset_warn := 0.0
var _toast := ""
var _toast_bad := false
var _toast_t := 0.0
var _leaving := false

var _input: MenuInput
var _canvas: Control
var _view: Control
var _footer: Control
var _fade: ColorRect


func _ready() -> void:
	Sfx.play_music()
	add_child(MenuBackdrop.new())
	_clubs.append(Rosters.FREE_AGENT)
	for i: int in Teams.menu_order():
		var abbr := str(Teams.team(i).abbr)
		_clubs.append(abbr)
		_team_of[abbr] = i
	var home := str(Teams.team(int(GameSettings.config.get("home_team", 0))).abbr)
	_club = [maxi(0, _clubs.find(_arg("left", Rosters.FREE_AGENT))), maxi(1, _clubs.find(_arg("right", home)))]
	if _club[0] == _club[1]:
		_club[1] = 1 if _club[0] != 1 else 2
	_side = clampi(int(_arg("side", "0")), 0, 1)

	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if not _leaving:
			_move(dir))
	_input.side.connect(func(dir: int) -> void:
		if not _leaving and (dir < 0) != (_side == 0):
			_side = 1 - _side
			Sfx.play("click", Vector3.INF, -8.0, 1.6)
			_view.queue_redraw())
	_input.dev_bumper.connect(func(_dev: String, dir: int) -> void:
		if not _leaving:
			_cycle_club(dir))
	_input.accepted.connect(func() -> void:
		if not _leaving:
			_send())
	_input.back.connect(func() -> void:
		if not _leaving:
			_back())
	_input.button.connect(_on_button)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.1, 0.72)
	shade.size = Vector2(4000, 4000)
	shade.position = Vector2(-1000, -1000)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	_view = Control.new()
	_view.size = MenuStyle.DESIGN_SIZE
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_click)
	_canvas.add_child(_view)

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

	_refresh()
	if _arg("sel", "") != "":
		_sel[_side] = clampi(int(_arg("sel", "0")), 0, maxi(0, _rows[_side].size() - 1))
		_scroll(_side)


func _on_button(b: String) -> void:
	if _leaving:
		return
	match b:
		"square":
			_trade()
		"triangle":
			_by_overall = not _by_overall
			Sfx.play("click", Vector3.INF, -8.0, 1.6)
			_refresh()
		"select":
			_reset()


func _process(delta: float) -> void:
	_reset_warn = maxf(0.0, _reset_warn - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	_view.queue_redraw()
	_footer.queue_redraw()


# --- Rosters ------------------------------------------------------------------------

func _refresh() -> void:
	for side in 2:
		var rows: Array = Rosters.for_team(_clubs[_club[side]]).duplicate()
		rows.sort_custom(_sorter)
		_rows[side] = rows
		_sel[side] = clampi(_sel[side], 0, maxi(0, rows.size() - 1))
		_scroll(side)
	if not _mark.is_empty():
		# The mark follows the player (rows are rebuilt after every change).
		var found := false
		for side in 2:
			for r: Dictionary in _rows[side]:
				if r.id == _mark.id:
					_mark = r
					_mark_side = side
					found = true
		if not found:
			_clear_mark()
	_view.queue_redraw()


func _sorter(a: Dictionary, b: Dictionary) -> bool:
	var oa := int(a.overall)
	var ob := int(b.overall)
	if not _by_overall:
		var pa := POS_ORDER.find(str(a.position))
		var pb := POS_ORDER.find(str(b.position))
		if pa != pb:
			return pa < pb
	if oa != ob:
		return oa > ob
	return str(a.get("last", "")) < str(b.get("last", ""))


func _scroll(side: int) -> void:
	var n: int = _rows[side].size()
	if _sel[side] < _top[side]:
		_top[side] = _sel[side]
	elif _sel[side] >= _top[side] + VISIBLE:
		_top[side] = _sel[side] - VISIBLE + 1
	_top[side] = clampi(_top[side], 0, maxi(0, n - VISIBLE))


func _current() -> Dictionary:
	var rows: Array = _rows[_side]
	return rows[_sel[_side]] if _sel[_side] < rows.size() else {}


func _move(dir: int) -> void:
	var n: int = _rows[_side].size()
	if n == 0:
		return
	_sel[_side] = wrapi(_sel[_side] + dir, 0, n)
	_scroll(_side)
	Sfx.play("click", Vector3.INF, -10.0, 1.8)


func _cycle_club(dir: int) -> void:
	var other: int = _club[1 - _side]
	var k: int = _club[_side]
	for i in _clubs.size():
		k = wrapi(k + dir, 0, _clubs.size())
		if k != other:
			break
	_club[_side] = k
	_sel[_side] = 0
	_top[_side] = 0
	if _mark_side == _side:
		_clear_mark()
	Sfx.play("click", Vector3.INF, -8.0, 1.4)
	_refresh()


## Cross: the player goes to the other side's team.
func _send() -> void:
	var row := _current()
	if row.is_empty():
		_nope("NOBODY HERE")
		return
	var to: String = _clubs[_club[1 - _side]]
	var why := Rosters.leave_block(row)
	if why == "":
		why = Rosters.join_block(to)
	if why != "":
		_nope(why)
		return
	var was := int(row.number)
	var num := Rosters.move(row, to)
	var name := str(row.get("last", "")).to_upper()
	if name == "":
		name = Rosters.display_name(row).to_upper()
	if to == Rosters.FREE_AGENT:
		_say("%s RELEASED TO FREE AGENCY" % name)
	elif str(row.club) == Rosters.FREE_AGENT:
		_say("%s SIGNS WITH %s" % [name, _club_name(to, true)])
	else:
		_say("%s MOVES TO %s" % [name, _club_name(to, true)])
	if num != was and to != Rosters.FREE_AGENT:
		_toast += "  ·  NOW #%d" % num
	if _mark.get("id", "") == row.id:
		_clear_mark()
	Sfx.play("glove", Vector3.INF, -4.0)
	_refresh()


## Square: mark a player for a trade, or trade the marked one for this one.
func _trade() -> void:
	var row := _current()
	if row.is_empty():
		_nope("NOBODY HERE")
		return
	if _mark.is_empty() or _mark_side == _side:
		if _mark.get("id", "") == row.id:
			_clear_mark()
			Sfx.play("pad", Vector3.INF, -8.0)
			return
		_mark = row
		_mark_side = _side
		Sfx.play("click", Vector3.INF, -6.0, 1.2)
		_say("PICK A PLAYER ON THE OTHER SIDE TO TRADE FOR")
		return
	var why := _swap_block(_mark, row)
	if why != "":
		_nope(why)
		return
	var a := str(_mark.get("last", "")).to_upper()
	var b := str(row.get("last", "")).to_upper()
	Rosters.swap(_mark, row)
	_clear_mark()
	_say("TRADED: %s FOR %s" % [a if a != "" else "?", b if b != "" else "?"])
	Sfx.play("glove", Vector3.INF, -3.0)
	_refresh()


## Why two players can't trade places ("" if they can): each team must still dress a game.
func _swap_block(a: Dictionary, b: Dictionary) -> String:
	var ga := _group(a)
	var gb := _group(b)
	if ga == gb:
		return ""
	for pair: Array in [[a, ga, gb], [b, gb, ga]]:
		var club := str(pair[0].club)
		if club == Rosters.FREE_AGENT:
			continue
		var n := Rosters.count(Rosters.for_team(club))
		n[pair[1]] -= 1
		n[pair[2]] += 1
		if n.G < Rosters.MIN_GOALIES:
			return "%s NEEDS A GOALIE" % club
		if n.D < Rosters.MIN_DEFENSE:
			return "%s NEEDS %d DEFENSE" % [club, Rosters.MIN_DEFENSE]
		if n.F < Rosters.MIN_FORWARDS:
			return "%s NEEDS %d FORWARDS" % [club, Rosters.MIN_FORWARDS]
	return ""


static func _group(r: Dictionary) -> String:
	var pos := str(r.position)
	return pos if pos in ["D", "G"] else "F"


func _clear_mark() -> void:
	_mark = {}
	_mark_side = -1


func _reset() -> void:
	if _reset_warn <= 0.0:
		_reset_warn = RESET_WARN
		Sfx.play("pad", Vector3.INF, -6.0)
		return
	_reset_warn = 0.0
	Rosters.reset_all()
	_clear_mark()
	_say("ROSTERS RESET")
	Sfx.play("glove", Vector3.INF, -3.0)
	_refresh()


func _back() -> void:
	if not _mark.is_empty():
		_clear_mark()
		Sfx.play("pad", Vector3.INF, -8.0)
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	GameSettings.menu_list = "customize"
	GameSettings.menu_select = MENU_SELECT
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


func _say(text: String) -> void:
	_toast = text
	_toast_bad = false
	_toast_t = 2.6


func _nope(text: String) -> void:
	_toast = text
	_toast_bad = true
	_toast_t = 2.2
	Sfx.play("pad", Vector3.INF, -6.0)


func _club_name(abbr: String, short := false) -> String:
	if abbr == Rosters.FREE_AGENT:
		return "FREE AGENCY"
	var i: int = _team_of.get(abbr, -1)
	if i < 0:
		return abbr
	return str(Teams.team(i).name).to_upper() if short else Teams.full_name(i).to_upper()


# --- Mouse --------------------------------------------------------------------------

func _on_click(e: InputEvent) -> void:
	if _leaving or not (e is InputEventMouseButton and e.pressed):
		return
	var mb := e as InputEventMouseButton
	for side in 2:
		var x: float = PANEL_X[side]
		if mb.position.x < x or mb.position.x > x + PANEL_W:
			continue
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_side = side
			_move(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.position.y >= PANEL_Y and mb.position.y < PANEL_Y + 64.0:
			_side = side
			_cycle_club(-1 if mb.position.x < x + PANEL_W * 0.5 else 1)
			return
		var i := int((mb.position.y - LIST_Y) / ROW_H)
		if mb.position.y >= LIST_Y and i < VISIBLE and _top[side] + i < _rows[side].size():
			var again: bool = _side == side and _sel[side] == _top[side] + i
			_side = side
			_sel[side] = _top[side] + i
			if again and mb.double_click:
				_send()
			else:
				Sfx.play("click", Vector3.INF, -10.0, 1.8)
		return


# --- Drawing ------------------------------------------------------------------------

func _draw_view() -> void:
	MenuStyle.draw_tag(_view, Vector2(60, 30), "CUSTOMIZE", "EDIT ROSTER")
	var sort := "SORTED BY OVERALL" if _by_overall else "SORTED BY POSITION"
	var sw := MenuStyle.text_width(sort, 16, 0.12)
	_view.draw_string(MenuStyle.font(0.12), Vector2(PANEL_X[1] + PANEL_W - sw, 120), sort,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
	for side in 2:
		_draw_panel(side)
	_draw_detail()
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := MenuStyle.text_width(_toast, 24)
		var tp := Vector2((MenuStyle.DESIGN_SIZE.x - tw) * 0.5, 112)
		var col := Color(0.55, 0.12, 0.1) if _toast_bad else MenuStyle.RED
		MenuStyle.draw_slant(_view, Rect2(tp - Vector2(26, 31), Vector2(tw + 52, 42)), Color(col, 0.92 * a), 14.0)
		MenuStyle.draw_bold(_view, tp, _toast, 24, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)


func _draw_panel(side: int) -> void:
	var x: float = PANEL_X[side]
	var on := side == _side
	var abbr: String = _clubs[_club[side]]
	var fa := abbr == Rosters.FREE_AGENT
	var col := Color(0.16, 0.18, 0.24) if fa else MenuStyle.team_color(_team_of[abbr])
	var pad := _input.using_pad

	# Body.
	var body := Rect2(x, PANEL_Y + 70.0, PANEL_W, DETAIL_Y - PANEL_Y - 82.0)
	_view.draw_rect(body, Color(0.03, 0.05, 0.1, 0.82 if on else 0.6))
	if on:
		_view.draw_rect(body, Color(1, 1, 1, 0.5), false, 2.0)

	# Team bar.
	var bar := Rect2(x, PANEL_Y, PANEL_W, 62.0)
	MenuStyle.draw_slant(_view, Rect2(bar.position + Vector2(5, 5), bar.size), Color(0, 0, 0, 0.35), 18.0)
	MenuStyle.draw_slant(_view, bar, col.lerp(Color.BLACK, 0.15) if on else col.lerp(Color.BLACK, 0.55), 18.0)
	if on:
		_view.draw_rect(Rect2(bar.position + Vector2(18, bar.size.y - 4), Vector2(bar.size.x - 18, 4)), Color(1, 1, 1, 0.85))
	var lx := x + 56.0
	if not fa:
		var logo := MenuStyle.team_logo(_team_of[abbr])
		if logo:
			var s := 52.0
			var ls := logo.get_size()
			var k := s / maxf(ls.x, ls.y)
			_view.draw_texture_rect(logo, Rect2(Vector2(lx + (s - ls.x * k) * 0.5, PANEL_Y + 5 + (s - ls.y * k) * 0.5), ls * k), false)
		lx += 64.0
	var name := _club_name(abbr)
	var fs := 30
	while fs > 16 and MenuStyle.text_width(name, fs) > PANEL_W - (lx - x) - 70.0:
		fs -= 2
	MenuStyle.draw_bold(_view, Vector2(lx, PANEL_Y + 31 + fs * 0.36), name, fs,
			Color.WHITE if on else Color(1, 1, 1, 0.7), 0, MenuStyle.INK, 0.2)
	if on:
		MenuStyle.draw_glyph(_view, Vector2(x + 10, PANEL_Y + 14), "L1" if pad else "Q", pad, 34.0)
		MenuStyle.draw_glyph(_view, Vector2(x + PANEL_W - 48, PANEL_Y + 14), "R1" if pad else "E", pad, 34.0)

	# Head counts.
	var rows: Array = _rows[side]
	var n := Rosters.count(rows)
	var counts := "%d PLAYERS   ·   F %d   D %d   G %d" % [rows.size(), n.F, n.D, n.G]
	if fa:
		counts = "%d FREE AGENTS   ·   F %d   D %d   G %d" % [rows.size(), n.F, n.D, n.G]
	_view.draw_string(MenuStyle.font(0.12), Vector2(x + 18, PANEL_Y + 96), counts,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.86, 0.45) if on else MenuStyle.DIM)

	# Column heads.
	var hy := LIST_Y - 8.0
	var f := MenuStyle.font(0.12)
	for c: Array in [[COL_NUM, "#"], [COL_NAME, "NAME"], [COL_POS, "POS"], [COL_STYLE, "STYLE"], [COL_OVR - 10, "OVR"]]:
		_view.draw_string(f, Vector2(x + c[0], hy), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuStyle.DIM)

	if rows.is_empty():
		_view.draw_string(f, Vector2(x + COL_NAME, LIST_Y + 30), "NOBODY HERE YET", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MenuStyle.DIM)
		return
	var last_pos := ""
	for i in range(_top[side], mini(rows.size(), _top[side] + VISIBLE)):
		var r: Dictionary = rows[i]
		var y: float = LIST_Y + (i - _top[side]) * ROW_H
		var rr := Rect2(x + 10, y + 2, PANEL_W - 20, ROW_H - 4)
		var cur: bool = i == _sel[side]
		if cur and on:
			MenuStyle.draw_slant(_view, rr, MenuStyle.RED, 10.0)
		elif cur:
			MenuStyle.draw_slant(_view, rr, Color(1, 1, 1, 0.12), 10.0)
		elif i % 2 == 1:
			_view.draw_rect(rr, Color(1, 1, 1, 0.03))
		# A thin line between position groups (position sort).
		if not _by_overall and last_pos != "" and _group(r) != last_pos and i != _top[side]:
			_view.draw_rect(Rect2(x + 20, y, PANEL_W - 40, 1), Color(1, 1, 1, 0.18))
		last_pos = _group(r)
		if _mark.get("id", "") == r.id:
			_view.draw_rect(rr.grow(1.0), Color(1, 0.84, 0.3), false, 2.0)
		var tc := Color.WHITE if cur and on else Color(0.92, 0.94, 0.98)
		var num := str(r.number)
		var nw := MenuStyle.text_width(num, 20)
		MenuStyle.draw_bold(_view, Vector2(x + COL_NUM + 14 - nw * 0.5, y + 24), num, 20, tc, 0, MenuStyle.INK, 0.2, false)
		var who := Rosters.display_name(r)
		var nfs := 20
		while nfs > 13 and MenuStyle.text_width(who, nfs, 0.12) > COL_POS - COL_NAME - 64.0:
			nfs -= 1
		_view.draw_string(f, Vector2(x + COL_NAME, y + 24), who, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, tc)
		# Tags: created players, and anyone not where the sheet put them.
		var tag := ""
		if r.has("custom"):
			tag = "GEN" if r.custom.get("generated", false) else "NEW"
		elif fa or Rosters.is_moved(r):
			tag = str(r.abbr)
		if tag != "":
			var tx := x + COL_NAME + MenuStyle.text_width(who, nfs, 0.12) + 10.0
			var tagw := MenuStyle.text_width(tag, 12, 0.0) + 10.0
			var tagc := Color(0.35, 0.7, 1.0) if tag == "NEW" else (Color(0.6, 0.62, 0.7) if tag == "GEN" else Color(1, 0.75, 0.3))
			_view.draw_rect(Rect2(tx, y + 10, tagw, 17), Color(tagc, 0.25))
			_view.draw_string(MenuStyle.font(0.0), Vector2(tx + 5, y + 23), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tagc.lightened(0.3))
		_view.draw_string(f, Vector2(x + COL_POS, y + 24), str(r.position), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tc)
		var style := str(r.get("playstyle", "")).to_upper()
		_view.draw_string(f, Vector2(x + COL_STYLE, y + 23), style, HORIZONTAL_ALIGNMENT_LEFT, COL_OVR - COL_STYLE - 30, 14,
				tc if cur and on else MenuStyle.DIM)
		var ovr := int(r.overall)
		var oc := _rating_color(ovr, str(r.position) == "G")
		var os := str(ovr)
		var ow := MenuStyle.text_width(os, 20)
		MenuStyle.draw_bold(_view, Vector2(x + COL_OVR + 6 - ow * 0.5, y + 24), os, 20, Color.WHITE if cur and on else oc, 0, MenuStyle.INK, 0.2, false)

	# Scroll bar.
	if rows.size() > VISIBLE:
		var track := Rect2(x + PANEL_W - 8, LIST_Y, 4, VISIBLE * ROW_H)
		_view.draw_rect(track, Color(1, 1, 1, 0.1))
		var h := track.size.y * VISIBLE / rows.size()
		var t: float = track.size.y * _top[side] / rows.size()
		_view.draw_rect(Rect2(track.position + Vector2(0, t), Vector2(4, h)), Color(1, 1, 1, 0.55))


## The highlighted player across the bottom: who they are and their ratings.
func _draw_detail() -> void:
	var r := _current()
	var box := Rect2(PANEL_X[0], DETAIL_Y, PANEL_X[1] + PANEL_W - PANEL_X[0], 70)
	_view.draw_rect(box, Color(0.03, 0.05, 0.1, 0.88))
	_view.draw_rect(Rect2(box.position, Vector2(box.size.x, 3)), MenuStyle.RED)
	if r.is_empty():
		return
	var f := MenuStyle.font(0.12)
	var name := Rosters.display_name(r).to_upper()
	MenuStyle.draw_bold(_view, box.position + Vector2(18, 34), "#%s  %s" % [r.number, name], 24, Color.WHITE, 0, MenuStyle.INK, 0.2)
	var goalie := str(r.position) == "G"
	var hand := ("CATCHES " if goalie else "SHOOTS ") + ("LEFT" if str(r.get("hand", "L")) == "L" else "RIGHT")
	var bits := [str(r.get("playstyle", "")).to_upper(), hand]
	if str(r.get("height", "")) != "":
		bits.append("%s  %s LB" % [r.height, r.get("weight_lbs", "")])
	if str(r.get("age", "")) != "":
		bits.append("AGE %s" % r.age)
	var nick := str(r.get("nickname", ""))
	var line := "   ·   ".join(bits)
	if nick != "":
		line = "\"%s\"   ·   %s" % [nick.to_upper(), line]
	_view.draw_string(f, box.position + Vector2(20, 60), line, HORIZONTAL_ALIGNMENT_LEFT, 760, 16, MenuStyle.DIM)
	# Ratings, right-aligned.
	var keys: Array = CustomPlayers.GOALIE_RATINGS if goalie else CustomPlayers.SKATER_RATINGS
	var x := box.end.x - 20.0 - keys.size() * 78.0 - 96.0
	for k: String in keys:
		var v := int(str(r.get(k, "0")))
		_view.draw_string(f, Vector2(x, box.position.y + 28), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuStyle.DIM)
		MenuStyle.draw_bold(_view, Vector2(x, box.position.y + 58), str(v), 26, _rating_color(v, goalie), 0, MenuStyle.INK, 0.2, false)
		x += 78.0
	_view.draw_string(f, Vector2(x + 8, box.position.y + 28), "OVR", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuStyle.DIM)
	MenuStyle.draw_bold(_view, Vector2(x + 8, box.position.y + 60), str(r.overall), 32, Color.WHITE, 0, MenuStyle.INK, 0.2, false)


## Red (weak) to green (strong) on the sheet's scale.
static func _rating_color(v: int, goalie: bool) -> Color:
	var lo := 70.0 if goalie else 62.0
	var hi := 88.0 if goalie else 84.0
	return Color(0.95, 0.42, 0.35).lerp(Color(0.45, 0.92, 0.5), clampf((v - lo) / (hi - lo), 0.0, 1.0))


func _draw_footer() -> void:
	var hint := ""
	var to: String = _clubs[_club[1 - _side]]
	var row := _current()
	if _reset_warn > 0.0:
		hint = "Press %s again to reset every roster." % _input.button_label("select")
	elif not _mark.is_empty():
		hint = "Trading %s: pick a player on the other side and press %s." % [Rosters.display_name(_mark), _input.button_label("square")]
	elif row.is_empty():
		hint = "Change teams with %s / %s." % ["L1" if _input.using_pad else "Q", "R1" if _input.using_pad else "E"]
	elif to == Rosters.FREE_AGENT:
		hint = "%s releases %s to Free Agency." % [_input.accept_label(), Rosters.display_name(row)]
	elif str(row.club) == Rosters.FREE_AGENT:
		hint = "%s signs %s with the %s." % [_input.accept_label(), Rosters.display_name(row), _club_name(to, true).capitalize()]
	else:
		hint = "%s moves %s to the %s." % [_input.accept_label(), Rosters.display_name(row), _club_name(to, true).capitalize()]
	var send := "RELEASE" if to == Rosters.FREE_AGENT else ("SIGN" if _clubs[_club[_side]] == Rosters.FREE_AGENT else "MOVE")
	var prompts := [[_input.accept_label(), send], [_input.button_label("square"), "TRADE"],
			[_input.button_label("triangle"), "SORT"], [_input.button_label("select"), "RESET"],
			[_input.back_label(), "BACK"]]
	MenuStyle.draw_footer(_footer, _canvas.size.x, hint, prompts, _input.using_pad)


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


## Screenshot hook for automated checks: `-- shot=<png> wait=<s>`.
func _enter_tree() -> void:
	var shot := _arg("shot", "")
	if shot != "":
		_take_shot.call_deferred(shot, float(_arg("wait", "2.5")))


func _take_shot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
