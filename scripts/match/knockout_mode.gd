class_name KnockoutMode
extends Node
## Knockout Mode (Game Modes): no hockey, just a card of fights. Five random skaters from
## each team are paired off at random; each pair fights at center ice in the real fight
## mini-game, ringed by the other eight. Scoring per bout: a knockout 3, a win on points
## 2, a draw 1 each. Best score after five wins; level after five, sudden-death bouts
## (any skater on the roster) until someone wins one.
##
## MatchDirector makes one instead of starting the game when GameSettings.mode is
## "knockout" (or `-- knockout`). It runs the card itself, using Fight directly, so none of
## the hockey after a fight happens (no box, no faceoff, no momentum).
##
## Screens, in the front-end style (MenuStyle, like the pause menu and stats screen): the
## tale of the tape before each bout, the result after it, a small series bug while they
## fight, and the final card. Accept skips ahead (the tape, the result) and leaves the
## final card for the Game Modes menu. Home is on the left throughout, as in the fight.

const BOUTS := 5
const PTS_KO := 3
const PTS_WIN := 2
const PTS_DRAW := 1
const CARD_TIME := 3.4        ## s the tale of the tape shows before the gloves come off
const RESULT_TIME := 3.0      ## s the result shows after a bout (after any replay)
const AUTO_LEAVE := 6.0       ## no humans: s on the final card before going back to the menu
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const PLATE_Y := 172.0        ## design px: the series plates
const PLATE_W := 470.0
const PLATE_H := 104.0
const SCORE_W := 110.0
const CARD_Y := 330.0         ## the fighter cards
const CARD_W := 560.0
const CARD_H := 270.0
const STATS := [["FIGHTING", "fighting"], ["STRENGTH", "strength"], ["DURABILITY", "durability"], ["ENDURANCE", "endurance"]]

enum Step { CARD, FIGHT, RESULT, FINAL }

signal series_over(winner_team: int)

var director: MatchDirector
var score := [0, 0]
var results: Array[Dictionary] = []   ## per bout: {a, b, winner (Skater or null), ko}
var bout := 0                         ## 0-based index of the current bout
var step := Step.CARD
var _card: Array = []                 ## per team: the five skaters, in bout order
var _pair_now: Array[Skater] = []     ## the pair on the tape / just fought
var _fight: Fight
var _ko := false
var _t := 0.0
var _leaving := false
var _ui: CanvasLayer
var _dim: ColorRect
var _canvas: Control
var _art: Control
var _input: MenuInput
var _vs: Control


func setup(d: MatchDirector) -> void:
	director = d
	name = "KnockoutMode"
	d._set_phase(MatchDirector.Phase.FIGHT)
	d.puck.dead = true
	d.puck.visible = false
	d.rink.disarm_nets()
	if d._hud:
		d._hud.visible = false
	# Five random skaters per team: they're the ones on the ice; the rest take the bench.
	for t in 2:
		var pool := d.lineup(t).all_skaters()
		_shuffle(pool)
		var five: Array[Skater] = []
		five.assign(pool.slice(0, BOUTS))
		_card.append(five)
		_set_on_ice(t, five)
	_build_ui()
	_stand_around()
	_show_card()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("kostep="):   # screenshots: `kostep=result|final` with made-up bouts
			_fake_card(arg.substr(7))


## Fills in made-up results and jumps to a screen (layout checks only).
func _fake_card(to: String) -> void:
	var n := 1 if to == "result" else BOUTS + 1
	for k in n:
		var p: Array[Skater] = [_card[0][k % BOUTS], _card[1][k % BOUTS]]
		var w: Skater = null if k == 2 else p[k % 2]
		results.append({"a": p[0], "b": p[1], "winner": w, "ko": k % 3 == 0})
		if w == null:
			score[0] += PTS_DRAW
			score[1] += PTS_DRAW
		else:
			score[w.team] += PTS_KO if k % 3 == 0 else PTS_WIN
	if score[0] == score[1]:
		score[0] += 1
	bout = n - 1
	_t = 0.0
	if to == "result":
		step = Step.RESULT
	else:
		_final()


func _set_on_ice(t: int, list: Array[Skater]) -> void:
	var lu := director.lineup(t)
	lu.on_ice.clear()
	lu.on_ice.append_array(list)
	for s in lu.all_skaters():
		s.set_benched(not (s in list))


## Everyone on the ice stands in a loose circle round center ice, facing in (between bouts).
func _stand_around() -> void:
	var all := director.on_ice_all()
	for k in all.size():
		var s := all[k]
		var ang := TAU * (k + 0.5) / all.size()
		var p := Vector3(cos(ang), 0.0, sin(ang)) * 4.2
		s.place(p, -p)
		s.frozen = true
		s.visual.snap()


func _pair() -> Array[Skater]:
	if bout < BOUTS:
		return [_card[0][bout], _card[1][bout]]
	# Sudden death: anyone on the roster.
	var out: Array[Skater] = []
	for t in 2:
		var pool := director.lineup(t).all_skaters()
		out.append(pool[director._rng.randi() % pool.size()])
	return out


func _physics_process(delta: float) -> void:
	_t += delta
	match step:
		Step.CARD:
			if _t > CARD_TIME:
				_start_bout()
		Step.RESULT:
			if director.replay and director.replay.playing:
				_t = 0.0   # the knockout replay plays out first
			elif _t > RESULT_TIME:
				_next()
		Step.FINAL:
			if director.humans.is_empty() and _t > AUTO_LEAVE:
				_to_menu()


func _process(_delta: float) -> void:
	var replaying := director.replay != null and director.replay.playing
	_dim.visible = step != Step.FIGHT and not replaying
	_art.visible = not replaying
	_vs.visible = step in [Step.CARD, Step.RESULT] and not replaying
	if _vs.visible:
		# Fade and drop in, never scaled: scaling outlined text re-rasterizes it every frame.
		var k := _in(0.2)
		_vs.modulate.a = k
		_vs.position = Vector2(_canvas.size.x * 0.5, CARD_Y + CARD_H * 0.5 - (1.0 - k) * 40.0) - _vs.size * 0.5
	_art.queue_redraw()


func _on_accept() -> void:
	match step:
		Step.CARD:
			if _t > 0.5:
				Sfx.play("glove", Vector3.INF, -4.0)
				_start_bout()
		Step.RESULT:
			if _t > 0.5 and not (director.replay and director.replay.playing):
				Sfx.play("pad", Vector3.INF, -8.0)
				_next()
		Step.FINAL:
			if _t > 1.0:
				Sfx.play("glove", Vector3.INF, -4.0)
				_to_menu()


func _show_card() -> void:
	step = Step.CARD
	_t = 0.0
	_pair_now = _pair()


func _start_bout() -> void:
	var p := _pair_now
	# A sudden-death fighter may have been on the bench.
	for t in 2:
		if p[t].benched:
			var list: Array[Skater] = []
			list.assign(director.lineup(t).on_ice)
			list[0] = p[t]
			_set_on_ice(t, list)
	# Square up at center ice (Fight centers on the pair).
	p[0].place(Vector3(-0.6, 0.0, 0.0), Vector3.RIGHT)
	p[1].place(Vector3(0.6, 0.0, 0.0), Vector3.LEFT)
	step = Step.FIGHT
	_t = 0.0
	_ko = false
	_fight = Fight.new()
	director.add_child(_fight)
	director._fight = _fight
	_fight.finished.connect(_on_bout_over)
	_fight.knockout.connect(func(w: Skater, l: Skater) -> void:
		_ko = true
		if director.replay and director.show_hud:
			director.replay.capture("ko", "KNOCKOUT  ·  %s" % MenuStyle.player_name(w), [w, l], 2.8, maxf(1.6, _fight.ko_fall + 0.8),
					{"play_now": true, "speed": 0.45, "cam": "orbit"}))
	_fight.setup(director, p[0], p[1], null)


func _on_bout_over(winner: Skater, _loser: Skater) -> void:
	var a := _fight.a.s
	var b := _fight.b.s
	_fight = null
	director._fight = null
	director.stats.fights += 1
	results.append({"a": a, "b": b, "winner": winner, "ko": _ko})
	if winner == null:
		score[0] += PTS_DRAW
		score[1] += PTS_DRAW
	else:
		score[winner.team] += PTS_KO if _ko else PTS_WIN
		director._bench_react(winner.team, "cheer", 0.8)
		director._bench_react(1 - winner.team, "groan", 0.5)
	for s in [a, b]:
		director.box.add(s, "fights")
		if s == winner:
			director.box.add(s, "fight_w")
	_stand_around()
	step = Step.RESULT
	_t = 0.0


func _next() -> void:
	bout += 1
	# After the five (or any sudden-death bout after them): settled once the totals differ.
	if bout >= BOUTS and score[0] != score[1]:
		_final()
		return
	_show_card()


func _final() -> void:
	step = Step.FINAL
	_t = 0.0
	var w := 0 if score[0] > score[1] else 1
	Sfx.crowd_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", -2.0, 3)
	director._bench_react(w, "cheer", 1.0)
	series_over.emit(w)


func _to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	GameSettings.menu_list = "modes"
	Sfx.stop_music(0.5)
	get_tree().change_scene_to_file(MENU_SCENE)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := director._rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


## The last bout's result word: "KNOCKOUT", "ON POINTS" or "DRAW".
func _how(r: Dictionary) -> String:
	if r.winner == null:
		return "DRAW"
	return "KNOCKOUT" if r.ko else "ON POINTS"


func _bout_name(k: int) -> String:
	return "BOUT %d OF %d" % [k + 1, BOUTS] if k < BOUTS else "SUDDEN DEATH"


# --- Overlay -------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6   # over the fight overlay (5), under the pause menu
	add_child(_ui)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.06, 0.5)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_dim)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_paint)
	_canvas.add_child(_art)
	_vs = MenuStyle.chrome_text("VS", 110)
	_vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_vs)
	_input = MenuInput.new()
	_input.start_accepts = false   # Start pauses
	add_child(_input)
	_input.accepted.connect(_on_accept)


## Slide-in progress (0 → 1) for something that starts `delay` s into the current screen.
func _in(delay: float) -> float:
	return ease(clampf((_t - delay) / 0.3, 0.0, 1.0), -2.0)


func _paint() -> void:
	var ci := _art
	var w := _canvas.size.x
	var pad := _input.using_pad
	var ok := _input.accept_label()
	match step:
		Step.FIGHT:
			_draw_bug(ci, w)
		Step.CARD:
			MenuStyle.draw_tag(ci, Vector2(60, 40), "KNOCKOUT MODE", _bout_name(bout))
			_draw_plates(ci, w, -1)
			_draw_fighters(ci, w, _pair_now, null, false)
			MenuStyle.draw_footer(ci, w, "Tale of the tape. The gloves come off in a moment.", [[ok, "FIGHT"]], pad)
		Step.RESULT:
			var r: Dictionary = results.back()
			MenuStyle.draw_tag(ci, Vector2(60, 40), "KNOCKOUT MODE", "%s: %s" % ["BOUT %d" % (bout + 1) if bout < BOUTS else "SUDDEN DEATH", _how(r)])
			_draw_plates(ci, w, -1)
			_draw_fighters(ci, w, [r.a, r.b], r.winner, true)
			_draw_points(ci, w, r)
			var nxt := "The final card." if bout + 1 >= BOUTS and score[0] != score[1] else ("Next: %s." % _bout_name(bout + 1).to_lower())
			MenuStyle.draw_footer(ci, w, nxt, [[ok, "NEXT"]], pad)
		Step.FINAL:
			var win := 0 if score[0] > score[1] else 1
			MenuStyle.draw_tag(ci, Vector2(60, 40), "KNOCKOUT MODE", "FINAL" if results.size() <= BOUTS else "FINAL / SUDDEN DEATH")
			_draw_plates(ci, w, win)
			_draw_card_list(ci, Rect2(60 + (1.0 - _in(0.15)) * 80.0, 318, w - 120, 480))
			var hint := "AI vs AI — back to the menu." if director.humans.is_empty() else \
					"%s win the knockout. Back to Game Modes." % str(Teams.team(director.team_ids[win]).name)
			MenuStyle.draw_footer(ci, w, hint, [] if director.humans.is_empty() else [[ok, "CONTINUE"]], pad)


## Both teams' plates with their series points, home on the left. `winner` >= 0 fades
## the other team and underlines the winner's score.
func _draw_plates(ci: Control, w: float, winner: int) -> void:
	var total := (PLATE_W + 14.0 + SCORE_W) * 2.0 + 70.0
	var x := maxf(60.0, (w - total) * 0.5)
	for t in 2:
		var k := _in(0.05 + t * 0.07)
		var id: int = director.team_ids[t]
		var col := MenuStyle.team_color(id)
		var px := x + (1.0 - k) * (-120.0 if t == 0 else 120.0)
		var faded := winner >= 0 and winner != t
		var a := k * (0.55 if faded else 1.0)
		var plate := Rect2(px, PLATE_Y, PLATE_W, PLATE_H)
		MenuStyle.draw_slant(ci, Rect2(plate.position + Vector2(8, 9), plate.size), Color(0, 0, 0, 0.4 * k), 22)
		MenuStyle.draw_slant(ci, plate.grow(5), Color(MenuStyle.INK, a), 22)
		MenuStyle.draw_slant(ci, plate, Color(col, a), 22)
		MenuStyle.draw_slant(ci, Rect2(px, PLATE_Y + PLATE_H * 0.6, PLATE_W, PLATE_H * 0.4), Color(0, 0, 0, 0.2 * a), 9)
		var logo := MenuStyle.team_logo(id)
		if logo:
			ci.draw_texture_rect(logo, Rect2(px + 26, PLATE_Y - 10, PLATE_H + 20, PLATE_H + 20), false, Color(1, 1, 1, a))
		var info := Teams.team(id)
		var nx := px + PLATE_H + 60.0
		ci.draw_string(MenuStyle.font(0.12), Vector2(nx, PLATE_Y + 34), str(info.city).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85 * a))
		var name := str(info.name).to_upper()
		var fs := 44 if MenuStyle.text_width(name, 44) < PLATE_W - PLATE_H - 90 else 34
		MenuStyle.draw_bold(ci, Vector2(nx, PLATE_Y + 80), name, fs, Color(1, 1, 1, a), 8, Color(MenuStyle.INK, a), 0.2, false)
		var sx := px + PLATE_W + 14.0
		MenuStyle.draw_slant(ci, Rect2(sx, PLATE_Y, SCORE_W, PLATE_H), Color(MenuStyle.INK, 0.95 * k), 22)
		var sc := str(score[t])
		MenuStyle.draw_bold(ci, Vector2(sx + (SCORE_W - MenuStyle.text_width(sc, 72)) * 0.5 + 10, PLATE_Y + 80), sc, 72,
				Color(1, 1, 1, a) if not faded else Color(MenuStyle.DIM, k), 0, MenuStyle.INK, 0.2, false)
		if winner == t:
			MenuStyle.draw_slant(ci, Rect2(sx, PLATE_Y + PLATE_H - 6, SCORE_W, 6), MenuStyle.RED, 2)
		x += PLATE_W + SCORE_W + 70.0


## The two fighters' cards with the VS between: crest, number and name, team, and the
## ratings that matter in a fight. After a bout (`result`), the winner's card gets a red
## WINNER tag and the loser's fades (a draw: neither).
func _draw_fighters(ci: Control, w: float, pair: Array, winner: Skater, result: bool) -> void:
	var gap := 200.0
	var x0 := w * 0.5 - gap * 0.5 - CARD_W
	for t in 2:
		var s: Skater = pair[t]
		var k := _in(0.1 + t * 0.08)
		var x := x0 + t * (CARD_W + gap) + (1.0 - k) * (-160.0 if t == 0 else 160.0)
		var faded := result and winner != null and winner != s
		var a := k * (0.5 if faded else 1.0)
		var id: int = director.team_ids[s.team]
		var col := MenuStyle.team_color(id)
		var r := Rect2(x, CARD_Y, CARD_W, CARD_H)
		MenuStyle.draw_slant(ci, Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4 * k), 30)
		MenuStyle.draw_slant(ci, r.grow(5), Color(MenuStyle.INK, a), 30)
		MenuStyle.draw_slant(ci, r, Color(MenuStyle.NAVY, 0.95 * a), 30)
		MenuStyle.draw_slant(ci, Rect2(x, CARD_Y, CARD_W, 92), Color(col, a), 30 * 92.0 / CARD_H)
		var logo := MenuStyle.team_logo(id)
		if logo:
			ci.draw_texture_rect(logo, Rect2(x + CARD_W - 120, CARD_Y - 16, 120, 120), false, Color(1, 1, 1, a))
		var info := Teams.team(id)
		ci.draw_string(MenuStyle.font(0.12), Vector2(x + 40, CARD_Y + 30), str(info.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85 * a))
		var nm := MenuStyle.player_name(s)
		var fs := 44 if MenuStyle.text_width(nm, 44) < CARD_W - 190 else 34
		MenuStyle.draw_bold(ci, Vector2(x + 36, CARD_Y + 76), nm, fs, Color(1, 1, 1, a), 8, Color(MenuStyle.INK, a), 0.2, false)
		# Ratings: slanted bars, the team color filling to the value.
		for i in STATS.size():
			var y := CARD_Y + 118 + i * 36.0
			var v: int = s.stats.get(STATS[i][1])
			var lx := x + 30.0 - i * 4.0   # follow the card's lean
			ci.draw_string(MenuStyle.font(0.12), Vector2(lx, y + 21), STATS[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(MenuStyle.ICE, 0.9 * a))
			var bar := Rect2(lx + 170, y + 3, CARD_W - 290, 22)
			MenuStyle.draw_slant(ci, bar, Color(0, 0, 0, 0.45 * a), 8)
			MenuStyle.draw_slant(ci, Rect2(bar.position, Vector2(bar.size.x * v / 99.0, bar.size.y)), Color(col.lightened(0.15), a), 8)
			MenuStyle.draw_bold(ci, Vector2(bar.end.x + 18, y + 23), str(v), 24, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, false)
		if result and winner == s:
			var tag := "WINNER"
			var tw := MenuStyle.text_width(tag, 26) + 40.0
			MenuStyle.draw_slant(ci, Rect2(x + 30, CARD_Y + CARD_H - 8, tw, 36), MenuStyle.RED, 12)
			MenuStyle.draw_bold(ci, Vector2(x + 50, CARD_Y + CARD_H + 20), tag, 26, Color.WHITE, 0, MenuStyle.INK, 0.2, false)


## Under the cards after a bout: what it was worth.
func _draw_points(ci: Control, w: float, r: Dictionary) -> void:
	var k := _in(0.35)
	var text := ""
	if r.winner == null:
		text = "+%d EACH" % PTS_DRAW
	else:
		text = "+%d  %s" % [PTS_KO if r.ko else PTS_WIN, director.team_name(r.winner.team)]
	var fs := 40
	var tw := MenuStyle.text_width(text, fs)
	var y := CARD_Y + CARD_H + 110.0
	var box := Rect2(w * 0.5 - tw * 0.5 - 40, y - 46, tw + 80, 62)
	MenuStyle.draw_slant(ci, box.grow(4), Color(MenuStyle.INK, k), 18)
	MenuStyle.draw_slant(ci, box, Color(MenuStyle.RED, k), 18)
	MenuStyle.draw_bold(ci, Vector2(w * 0.5 - tw * 0.5 + 8, y), text, fs, Color(1, 1, 1, k), 0, MenuStyle.INK, 0.2, false)


## While they fight: a small bug under the fight clock with the bout and series score.
func _draw_bug(ci: Control, w: float) -> void:
	var y := 112.0
	var h := 36.0
	var mid := _bout_name(bout)
	var mw := MenuStyle.text_width(mid, 18, 0.12) + 40.0
	var side := 230.0
	var x := w * 0.5 - mw * 0.5 - side
	for t in 2:
		var id: int = director.team_ids[t]
		var bx := x if t == 0 else w * 0.5 + mw * 0.5
		var r := Rect2(bx, y, side, h)
		MenuStyle.draw_slant(ci, r.grow(3), MenuStyle.INK, 12)
		MenuStyle.draw_slant(ci, r, MenuStyle.team_color(id), 12)
		var nm := director.team_name(t)
		var sc := str(score[t])
		if t == 0:
			MenuStyle.draw_bold(ci, Vector2(bx + 16, y + 27), nm, 22, Color.WHITE, 6, MenuStyle.INK, 0.2, false)
			MenuStyle.draw_bold(ci, Vector2(bx + side - MenuStyle.text_width(sc, 28) - 8, y + 29), sc, 28, Color.WHITE, 6, MenuStyle.INK, 0.2, false)
		else:
			MenuStyle.draw_bold(ci, Vector2(bx + 22, y + 29), sc, 28, Color.WHITE, 6, MenuStyle.INK, 0.2, false)
			MenuStyle.draw_bold(ci, Vector2(bx + side - MenuStyle.text_width(nm, 22) - 4, y + 27), nm, 22, Color.WHITE, 6, MenuStyle.INK, 0.2, false)
	var m := Rect2(w * 0.5 - mw * 0.5, y + 2, mw, h - 4)
	MenuStyle.draw_slant(ci, m, MenuStyle.RED, 10)
	ci.draw_string(MenuStyle.font(0.12), Vector2(m.position.x + 22, y + 25), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## The final card: every bout, home fighter left, away right, the result chip between.
func _draw_card_list(ci: Control, r: Rect2) -> void:
	var a := _in(0.15)
	MenuStyle.draw_slant(ci, Rect2(r.position + Vector2(8, 9), r.size), Color(0, 0, 0, 0.35 * a), 26)
	MenuStyle.draw_slant(ci, r, Color(MenuStyle.NAVY, 0.92 * a), 26)
	MenuStyle.draw_bold(ci, r.position + Vector2(36, 50), "THE CARD", 30, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, true)
	var row_h := minf(62.0, (r.size.y - 90.0) / maxf(1.0, results.size()))
	var mid := r.position.x + r.size.x * 0.5
	for k in results.size():
		var res: Dictionary = results[k]
		var y := r.position.y + 84.0 + k * row_h
		var lean := (y - r.position.y) * 26.0 / r.size.y
		var ka := _in(0.25 + k * 0.06) * a
		if k % 2 == 0:
			ci.draw_rect(Rect2(r.position.x + 30 - lean, y, r.size.x - 50, row_h - 6), Color(1, 1, 1, 0.05 * ka))
		var num := str(k + 1) if k < BOUTS else "SD"
		MenuStyle.draw_bold(ci, Vector2(r.position.x + 44 - lean, y + row_h * 0.62), num, 26, Color(MenuStyle.DIM, ka), 0, MenuStyle.INK, 0.2, false)
		for t in 2:
			var s: Skater = res.a if t == 0 else res.b
			var won: bool = res.winner == s
			var nm := MenuStyle.player_name(s)
			var col := Color.WHITE if won or res.winner == null else MenuStyle.DIM
			var nx := mid - 120.0 - MenuStyle.text_width(nm, 30) if t == 0 else mid + 120.0
			MenuStyle.draw_bold(ci, Vector2(nx - lean, y + row_h * 0.62), nm, 30, Color(col, ka), 6, Color(MenuStyle.INK, ka), 0.2, false)
		var chip := "DRAW" if res.winner == null else ("KO" if res.ko else "PTS")
		var cw := 150.0
		var cr := Rect2(mid - cw * 0.5 - lean, y + 6, cw, row_h - 18)
		var ccol := MenuStyle.RED if chip == "KO" else (MenuStyle.NAVY.lightened(0.25) if chip == "PTS" else Color(0.35, 0.37, 0.42))
		MenuStyle.draw_slant(ci, cr, Color(ccol, ka), 10)
		var cwid := MenuStyle.text_width(chip, 24)
		MenuStyle.draw_bold(ci, Vector2(cr.get_center().x - cwid * 0.5 + 4, cr.get_center().y + 9), chip, 24, Color(1, 1, 1, ka), 0, MenuStyle.INK, 0.2, false)
