class_name FightHud
extends CanvasLayer
## Fight overlay, in the front-end menu style (MenuStyle) like the match's TV graphics,
## drawn on the 1600 x 900 design canvas:
##   - a slim header across the top: each fighter's dark strip (team-color stripe, crest,
##     name and style) over one health bar and two hairlines, balance (yellow) and stamina
##     (blue), mirrored either side of a small steel clock. They drain toward the
##     outside; what was just lost lingers as a white chunk; the stamina line shows the
##     tank worn away for the rest of the fight. The panel of the one hit jolts. Under
##     each: a tab for what the human has to act on (HOLDING / HELD / ROCKED) and, for a
##     human, short coaching call-outs.
##   - banners (wipe in across the middle) and flashes (a small tab), like the match's.
##   - bottom: the controls that matter right now, on the human's own buttons (the clinch
##     set while holding, the struggle while held).
##   - red screen edges when the human takes a clean one.
## Also the "drop the gloves?" prompt. Timing runs on real time, so slow motion and
## hitstop don't drag the graphics.

const HEALTH := Color(0.92, 0.22, 0.2)
const BALANCE := Color(0.98, 0.78, 0.2)
const STAMINA := Color(0.3, 0.68, 1.0)
const SPENT := Color(0.45, 0.1, 0.12)
const CLOCK_W := 88.0
const CLOCK_H := 44.0
const TOP := 20.0
const PANEL_W := 380.0
const PANEL_H := 56.0
const SKEW := 14.0
const GAP := 10.0             ## between a panel and the clock
const BARS := [               ## key, name, color, height, y in the panel
	["health", "HEALTH", HEALTH, 11.0, 32.0],
	["balance", "BALANCE", BALANCE, 4.0, 45.0],
	["stamina", "STAMINA", STAMINA, 4.0, 50.0],
]
const WIPE := 0.22

var fight: Fight
var _canvas: Control
var _panels: Array[Dictionary] = []   ## per fighter: bar animation, call-out
var _prompt: Control
var _prompt_canvas: Control
var _prompt_art: Control
var _prompt_share := 1.0
var _prompt_at := 0     ## ms when the prompt opened (its pop-in runs on real time)
var _show_fight := false
var _banner := {}       ## text, start, until (in _now seconds)
var _flash := {}
var _now := 0.0         ## real seconds the HUD has run
var _last_tick := 0.0
var _fight_t := 0.0
var _hurt: TextureRect   ## red edges when the human takes a clean one
var _hurt_t := 0.0


func setup(f: Fight) -> void:
	fight = f
	layer = 5
	_hurt = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.7, 0.0, 0.0, 0.85))
	grad.add_point(0.55, Color(0.7, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	_hurt.texture = tex
	_hurt.stretch_mode = TextureRect.STRETCH_SCALE
	_hurt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.modulate.a = 0.0
	add_child(_hurt)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	_canvas.draw.connect(_draw)
	for k in 2:
		var p := {"call": "", "call_until": -1.0}
		for spec: Array in BARS:
			p[spec[0]] = {"shown": 1.0, "ghost_v": 1.0, "hold": 0.0}
		_panels.append(p)
	_build_prompt()


## "Drop the gloves?" in the front-end style (MenuStyle): the game dimmed, a navy panel
## with the red FIGHT tag and the question, both fighters on their team colors (yours on
## the left), the yes / no buttons as the device's own glyphs, and a red bar running down
## the time left to answer.
func _build_prompt() -> void:
	_prompt = Control.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	add_child(_prompt)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(dim)
	_prompt_canvas = Control.new()
	_prompt_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(_prompt_canvas)
	MenuStyle.fit(_prompt_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_prompt_canvas))
	_prompt_art = Control.new()
	_prompt_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_art.draw.connect(_draw_prompt)
	_prompt_canvas.add_child(_prompt_art)


func _draw_prompt() -> void:
	var ci := _prompt_art
	var w := _prompt_canvas.size.x
	var k := ease(clampf((Time.get_ticks_msec() - _prompt_at) / 250.0, 0.0, 1.0), -2.0)
	var pw := 860.0
	var ph := 330.0
	var r := Rect2(w * 0.5 - pw * 0.5 + (1.0 - k) * 60.0, 450.0 - ph * 0.5, pw, ph)
	var a := k
	MenuStyle.draw_slant(ci, Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.45 * a), 34)
	MenuStyle.draw_slant(ci, r.grow(5), Color(MenuStyle.INK, a), 34)
	MenuStyle.draw_slant(ci, r, Color(MenuStyle.NAVY, 0.96 * a), 34)
	# The tag and the question.
	var tag := "FIGHT!"
	var tw := MenuStyle.text_width(tag, 20, 0.12) + 40.0
	var tp := r.position + Vector2(56, 28)
	MenuStyle.draw_slant(ci, Rect2(tp, Vector2(tw, 30)), Color(MenuStyle.RED, a), 12)
	ci.draw_string(MenuStyle.font(0.12), tp + Vector2(22, 22), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, a))
	MenuStyle.draw_bold(ci, r.position + Vector2(48, 118), "DROP THE GLOVES?", 60, Color(1, 1, 1, a), 0, MenuStyle.INK, 0.2, true)
	# The pair: yours (the one asked) on the left.
	var h := fight.prompt_brain
	var mine: Fight.Fighter = fight.a
	if h and fight.b.s.team == h.team:
		mine = fight.b
	var y := r.position.y + 150.0
	var chip_w := 330.0
	for i in 2:
		var f: Fight.Fighter = mine if i == 0 else mine.other
		var id: int = fight.director.team_ids[f.s.team]
		var cx := r.position.x + 40.0 + i * (chip_w + 100.0) - (y - r.position.y) * 34.0 / ph
		var cr := Rect2(cx, y, chip_w, 54)
		MenuStyle.draw_slant(ci, cr.grow(3), Color(MenuStyle.INK, a), 14)
		MenuStyle.draw_slant(ci, cr, Color(MenuStyle.team_color(id), a), 14)
		var nm := MenuStyle.player_name(f.s)
		var fs := 30 if MenuStyle.text_width(nm, 30) < chip_w - 40 else 24
		MenuStyle.draw_bold(ci, Vector2(cx + 22, y + 39), nm, fs, Color(1, 1, 1, a), 6, Color(MenuStyle.INK, a), 0.2, false)
		# Their style, on a tag over the chip's top corner, and (for the other one) what that
		# means: the read you get before you decide.
		var sname: String = Fight.STYLE_NAMES[f.style]
		var scol: Color = Fight.STYLE_COLORS[f.style]
		var sw := MenuStyle.text_width(sname, 16, 0.12) + 26.0
		var sp := Vector2(cx + chip_w - sw - 4.0, y - 13.0)
		MenuStyle.draw_slant(ci, Rect2(sp - Vector2(2, 2), Vector2(sw + 4, 26)), Color(MenuStyle.INK, a), 8)
		MenuStyle.draw_slant(ci, Rect2(sp, Vector2(sw, 22)), Color(scol.darkened(0.25), a), 8)
		ci.draw_string(MenuStyle.font(0.12), sp + Vector2(13, 17), sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, a))
		if i == 1:
			ci.draw_string(MenuStyle.font(0.12), Vector2(cx + chip_w - pw, y + 73), Fight.STYLE_BLURBS[f.style],
					HORIZONTAL_ALIGNMENT_RIGHT, pw, 17, Color(scol.lightened(0.45), a))
	MenuStyle.draw_bold(ci, Vector2(r.position.x + 40.0 + chip_w + 26.0 - 150.0 * 34.0 / ph, y + 40), "VS", 32,
			Color(MenuStyle.RED.lightened(0.2), a), 6, Color(MenuStyle.INK, a), 0.2, false)
	# Yes / no, on this device's buttons.
	var pad := h == null or h.kind == HumanBrain.Kind.PAD or (h.kind == HumanBrain.Kind.ANY and not Input.get_connected_joypads().is_empty())
	var yes := "CROSS" if pad else h.button_label("pass")
	var no := "CIRCLE" if pad else h.button_label("check")
	var px := r.position.x + 32.0
	var py := r.position.y + 228.0
	var f2 := MenuStyle.font(0.12)
	for opt: Array in [[yes, "DROP 'EM"], [no, "BACK OFF"]]:
		px += MenuStyle.draw_glyph(ci, Vector2(px, py), opt[0], pad, 40.0) + 12.0
		ci.draw_string(f2, Vector2(px, py + 30), opt[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, a))
		px += f2.get_string_size(opt[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 56.0
	# Time to answer.
	var bar := Rect2(r.position.x + 14.0, r.end.y - 30.0, pw - 40.0, 14.0)
	MenuStyle.draw_slant(ci, bar, Color(0, 0, 0, 0.5 * a), 6)
	MenuStyle.draw_slant(ci, Rect2(bar.position, Vector2(bar.size.x * _prompt_share, bar.size.y)), Color(MenuStyle.RED, a), 6)


func show_prompt(on: bool) -> void:
	_prompt.visible = on
	_prompt_at = Time.get_ticks_msec()


func prompt_left(share: float) -> void:
	_prompt_share = clampf(share, 0.0, 1.0)
	_prompt_art.queue_redraw()


func show_fight(on: bool) -> void:
	_show_fight = on
	_fight_t = 0.0


## A big call across the middle.
func banner(text: String) -> void:
	_banner = {"text": text, "start": _now, "until": _now + 2.6}


## The human took a clean one: the screen edges flash red (`strength` 0..1).
func hurt(strength: float) -> void:
	_hurt_t = maxf(_hurt_t, clampf(strength, 0.0, 1.0))


## A call-out for both to see (a grab, a slip, a break).
func flash(text: String) -> void:
	_flash = {"text": text, "start": _now, "until": _now + 1.0}


## A call-out under one fighter's panel (blocked, out of reach, how to do something):
## coaching, so only for a human.
func flash_for(f: Fight.Fighter, text: String) -> void:
	if f.human == null:
		return
	var p := _panels[0 if f == fight.a else 1]
	p.call = text
	p.call_until = _now + 1.3


func refresh() -> void:
	var t := Time.get_ticks_usec() / 1000000.0
	var delta := minf(t - _last_tick, 0.1) if _last_tick > 0.0 else 0.0
	_last_tick = t
	_now += delta
	_hurt_t = maxf(0.0, _hurt_t - delta * 2.2)
	_hurt.modulate.a = _hurt_t if _show_fight else 0.0
	if _show_fight:
		_fight_t += delta
		for k in 2:
			var f: Fight.Fighter = fight.a if k == 0 else fight.b
			var p := _panels[k]
			_ease_bar(p.health, f.health / f.max_health, delta)
			_ease_bar(p.balance, f.balance / f.max_balance, delta)
			_ease_bar(p.stamina, f.stamina / f.max_stamina, delta)
	_canvas.queue_redraw()


## The bar eases to its value; what was lost lingers as a white chunk, then drains.
func _ease_bar(b: Dictionary, share: float, delta: float) -> void:
	share = clampf(share, 0.0, 1.0)
	if share < b.shown - 0.004:
		b.hold = 0.5
	b.shown = share
	if share > b.ghost_v:
		b.ghost_v = share
	b.hold -= delta
	if b.hold <= 0.0:
		b.ghost_v = move_toward(b.ghost_v, share, delta * 0.6)


## 0 -> 1 sliding in, 1 holding, 1 -> 0 sliding out.
func _show(item: Dictionary) -> float:
	if item.is_empty() or _now > item.until + WIPE:
		return 0.0
	var t_in := clampf((_now - item.start) / WIPE, 0.0, 1.0)
	var t_out := clampf((item.until + WIPE - _now) / WIPE, 0.0, 1.0)
	return ease(minf(t_in, t_out), -2.0)


func _draw() -> void:
	if fight == null:
		return
	if _show_fight:
		var cw := _canvas.size.x
		_draw_clock(cw)
		for k in 2:
			_draw_panel(k, cw)
		_draw_controls(cw)
	_draw_banner()
	_draw_flash()


# --- Header ------------------------------------------------------------------------------

## The clock on brushed steel with a red hairline, like the scorebug's.
func _draw_clock(cw: float) -> void:
	var r := Rect2(cw * 0.5 - CLOCK_W * 0.5, TOP, CLOCK_W, CLOCK_H)
	_canvas.draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.3))
	_canvas.draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
			PackedColorArray([Color(0.92, 0.94, 0.97), Color(0.78, 0.81, 0.87), Color(0.6, 0.64, 0.72), Color(0.72, 0.76, 0.83)]))
	_canvas.draw_rect(Rect2(r.position - Vector2(0, 3), Vector2(r.size.x, 3)), MenuStyle.RED)
	var left := maxf(fight.time_left(), 0.0)
	var txt := "%d" % ceili(left)
	var col := MenuStyle.RED if left < 6.0 else MenuStyle.INK
	MenuStyle.draw_bold(_canvas, Vector2(r.get_center().x - MenuStyle.text_width(txt, 30) * 0.5, r.position.y + 33), txt, 30,
			col, 0, MenuStyle.INK, 0.2, false)


## A fighter's panel: a slim dark strip with a team-color stripe on top, the crest and
## name (and style) at the outer end, one health bar and two hairline meters (balance,
## stamina) under it, all draining toward the outside. Side 0 hugs the clock from the
## left, side 1 from the right (mirrored).
func _draw_panel(k: int, cw: float) -> void:
	var f: Fight.Fighter = fight.a if k == 0 else fight.b
	var p := _panels[k]
	var right := k == 1
	var x0 := cw * 0.5 + CLOCK_W * 0.5 + GAP if right else cw * 0.5 - CLOCK_W * 0.5 - GAP - PANEL_W - SKEW
	var jolt := f.flash_t / 0.35
	var o := Vector2(x0, TOP) + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 5.0 * jolt * jolt
	var id: int = fight.director.team_ids[f.s.team]
	_slant(Rect2(o + Vector2(4, 5), Vector2(PANEL_W, PANEL_H)), Color(0, 0, 0, 0.3), SKEW, right)
	_slant(Rect2(o, Vector2(PANEL_W, PANEL_H)), Color(0.03, 0.04, 0.09, 0.9), SKEW, right)
	# The team's stripe along the top edge.
	_canvas.draw_rect(Rect2(o + Vector2(SKEW if not right else 0.0, -3), Vector2(PANEL_W, 3)), MenuStyle.team_color(id))
	# Inside: the content runs between the slanted ends.
	var in_x := o.x + SKEW + 10.0 if not right else o.x + 10.0
	var in_w := PANEL_W - 20.0 - SKEW * 0.5
	# Crest and name at the outer end, the style after the name in its color.
	var logo := MenuStyle.team_logo(id)
	var crest := 22.0
	var row_y := o.y + 5.0
	var nm := MenuStyle.player_name(f.s)
	var fs := 19 if MenuStyle.text_width(nm, 19) < in_w - 140.0 else 16
	var nw := MenuStyle.text_width(nm, fs)
	var sname: String = Fight.STYLE_NAMES[f.style]
	var sw := MenuStyle.text_width(sname, 12, 0.12)
	var scol: Color = (Fight.STYLE_COLORS[f.style] as Color).lerp(Color.WHITE, 0.25)
	if not right:
		if logo:
			_canvas.draw_texture_rect(logo, Rect2(in_x, row_y, crest, crest), false)
		MenuStyle.draw_bold(_canvas, Vector2(in_x + crest + 8.0, row_y + 18), nm, fs, Color.WHITE, 0, MenuStyle.INK, 0.2, false)
		_canvas.draw_string(MenuStyle.font(0.12), Vector2(in_x + crest + 8.0 + nw + 12.0, row_y + 17), sname,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, scol)
	else:
		var ex := in_x + in_w
		if logo:
			_canvas.draw_texture_rect(logo, Rect2(ex - crest, row_y, crest, crest), false)
		MenuStyle.draw_bold(_canvas, Vector2(ex - crest - 8.0 - nw, row_y + 18), nm, fs, Color.WHITE, 0, MenuStyle.INK, 0.2, false)
		_canvas.draw_string(MenuStyle.font(0.12), Vector2(ex - crest - 8.0 - nw - 12.0 - sw, row_y + 17), sname,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, scol)
	# Health, then the balance and stamina hairlines. The bars sit square in the slanted
	# strip, indented so the slant doesn't cut them.
	var bx := in_x - SKEW * 0.35 if not right else in_x + SKEW * 0.4
	var bw := in_w
	for spec: Array in BARS:
		var key: String = spec[0]
		var b: Dictionary = p[key]
		var bh: float = spec[3]
		var y: float = o.y + float(spec[4])
		_canvas.draw_rect(Rect2(bx, y, bw, bh), Color(1, 1, 1, 0.08))
		_fill(bx, y, bw, bh, b.ghost_v, Color(1, 1, 1, 0.8), right)
		var fc: Color = spec[2]
		if key == "health" and f.flash_t > 0.0 and fmod(f.flash_t, 0.12) > 0.06:
			fc = fc.lerp(Color.WHITE, 0.5)
		_fill(bx, y, bw, bh, b.shown, fc, right)
		if key == "stamina":
			# The tank worn away for the rest of the fight (Fight's ceiling), at the inner end.
			var spent := clampf(1.0 - f.stamina_cap / f.max_stamina, 0.0, 1.0) * bw
			_canvas.draw_rect(Rect2(bx + bw - spent if not right else bx, y, spent, bh), SPENT)
	# Under the panel: what needs the human's attention, then a call-out.
	var ty := o.y + PANEL_H + 8.0
	var status := _status(f)
	if status[0] != "":
		_tab(status[0], status[1], o.x, ty, right)
		ty += 30.0
	var ca := clampf((float(p.call_until) + WIPE - _now) / WIPE, 0.0, 1.0)
	if p.call != "" and ca > 0.0:
		_tab(p.call, MenuStyle.NAVY, o.x, ty, right, ca)


## A bar's fill, from the outer end toward the inner one.
func _fill(x: float, y: float, w: float, h: float, share: float, c: Color, right: bool) -> void:
	var fw := w * clampf(share, 0.0, 1.0)
	_canvas.draw_rect(Rect2(x + w - fw if right else x, y, fw, h), c)


## A small slanted tab under a panel, at its outer end.
func _tab(text: String, c: Color, px: float, y: float, right: bool, a := 1.0) -> void:
	var w := MenuStyle.text_width(text, 14, 0.12) + 28.0
	var x := px + 2.0 if not right else px + PANEL_W - w + 2.0
	_slant(Rect2(Vector2(x + 3, y + 4), Vector2(w, 24)), Color(0, 0, 0, 0.3 * a), 9.0, right)
	_slant(Rect2(Vector2(x, y), Vector2(w, 24)), Color(c, 0.94 * a), 9.0, right)
	MenuStyle.draw_bold(_canvas, Vector2(x + 14, y + 17), text, 14, Color(1, 1, 1, a), 3, Color(MenuStyle.INK, a), 0.12, false)


## [text, tab color] for a state the human has to act on (text "" = nothing to show; the
## rest, winded, wobbly, a guard, shows in the meters and the fighter).
func _status(f: Fight.Fighter) -> Array:
	if f.act == "down":
		return ["", MenuStyle.NAVY]
	if f.grabbing > 0.0:
		return [("HOLD ON — MASH  %d%%" % int(f.other.escape * 100.0)) if f.other.escape > 0.3 else "HOLDING", MenuStyle.NAVY]
	if f.other.grabbing > 0.0:
		return ["HELD — MASH TO BREAK FREE  %d%%" % int(f.escape * 100.0), MenuStyle.RED_DARK]
	if f.rocked:
		return ["ROCKED — COVER UP  %d%%" % int(f.recover * 100.0), MenuStyle.RED]
	return ["", MenuStyle.NAVY]


# --- Controls ----------------------------------------------------------------------------

## The controls that matter now, in one strip at the bottom: the set for the moment
## (free / holding / held), on the human's own buttons.
func _draw_controls(cw: float) -> void:
	var h := fight.human_brain()
	if h == null:
		return
	var me: Fight.Fighter = fight.a if fight.a.human == h else fight.b
	var pad := h.kind == HumanBrain.Kind.PAD or (h.kind == HumanBrain.Kind.ANY and not Input.get_connected_joypads().is_empty())
	var items: Array = []   # [button, action]; button "" = words only
	if me.other.grabbing > 0.0:
		items = [[h.button_label("check"), "MASH TO BREAK FREE"], [h.button_label("pass"), "JAB"]]
	elif me.grabbing > 0.0:
		items = [[h.button_label("pass"), "BODY SHOT"], [h.button_label("shoot"), "HOOK"], [h.button_label("deke"), "UPPERCUT"],
			[h.button_label("check"), "HANG ON"]]
	else:
		items = [[h.button_label("pass"), "JAB"], [h.button_label("shoot"), "CROSS"], [h.button_label("deke"), "HOOK"],
			[h.button_label("protect"), "+ TO THE BODY"], [h.button_label("check"), "GRAB"], [h.button_label("block"), "BLOCK"]]
		var mv: Array = h.move_labels()
		items.append(["", "STICK  STEP · SLIP" if pad else "%s STEP  ·  %s SLIP" % [str(mv[0]).to_upper(), str(mv[1]).to_upper()]])
	var gh := 28.0
	var fsz := 16
	var f := MenuStyle.font(0.12)
	var total := 0.0
	for it: Array in items:
		if it[0] != "":
			total += MenuStyle.glyph_width(it[0], pad, gh) + 8.0
		total += f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 26.0
	var w := total + 30.0
	var y := 846.0
	var x := cw * 0.5 - w * 0.5
	# Full strength for the first seconds and while tied up, softer after.
	var a := 1.0 if _fight_t < 10.0 or me.grabbing > 0.0 or me.other.grabbing > 0.0 else 0.7
	MenuStyle.draw_slant(_canvas, Rect2(x + 4, y + 5, w, 38), Color(0, 0, 0, 0.3 * a), 12)
	MenuStyle.draw_slant(_canvas, Rect2(x, y, w, 38), Color(0.03, 0.04, 0.09, 0.82 * a), 12)
	MenuStyle.draw_slant(_canvas, Rect2(x + 12, y - 2, w, 2), Color(MenuStyle.RED, a), 0)
	var cx := x + 24.0
	for it: Array in items:
		if it[0] != "":
			cx += MenuStyle.draw_glyph(_canvas, Vector2(cx, y + 5), it[0], pad, gh) + 8.0
		_canvas.draw_string(f, Vector2(cx, y + 25), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(MenuStyle.ICE, a))
		cx += f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 26.0


# --- Banner and flash ----------------------------------------------------------------------

## The match's banner: a red slanted bar that wipes in across the middle.
func _draw_banner() -> void:
	var k := _show(_banner)
	if k <= 0.0:
		return
	var cw := _canvas.size.x
	var text: String = _banner.text
	var size := 64 if text.length() <= 14 else (46 if text.length() <= 26 else 34)
	var w := MenuStyle.text_width(text, size) + 120.0
	var h := 26.0 + size * 1.15
	var y := 250.0
	var x := (cw - w) * 0.5
	var grow := w * k
	MenuStyle.draw_slant(_canvas, Rect2(x - 10, y + 2, grow + 36, h + 16), Color(0, 0, 0, 0.35), 26)
	MenuStyle.draw_slant(_canvas, Rect2(x - 18, y - 8, grow + 36, h + 16), MenuStyle.INK, 26)
	MenuStyle.draw_slant(_canvas, Rect2(x, y, grow, h), MenuStyle.RED, 22)
	MenuStyle.draw_slant(_canvas, Rect2(x, y + h * 0.58, grow, h * 0.42), Color(0, 0, 0, 0.16), 9)
	MenuStyle.draw_slant(_canvas, Rect2(x + 10, y - 4, grow * 0.7, 4), Color(1, 1, 1, 0.75), 2)
	if k < 0.7:
		return
	var ta := clampf((k - 0.7) / 0.25, 0.0, 1.0)
	MenuStyle.draw_bold(_canvas, Vector2(x + 60.0, y + h * 0.5 + size * 0.36), text, size, Color(1, 1, 1, ta),
			int(size * 0.18), Color(MenuStyle.INK, ta), 0.2, ta > 0.9)


## A quick call in a small navy tab under the banner spot.
func _draw_flash() -> void:
	var k := _show(_flash)
	if k <= 0.0:
		return
	var text: String = _flash.text
	var w := MenuStyle.text_width(text, 26) + 60.0
	var x := (_canvas.size.x - w) * 0.5
	var y := 372.0 + (1.0 - k) * 30.0
	MenuStyle.draw_slant(_canvas, Rect2(x + 5, y + 6, w, 46), Color(0, 0, 0, 0.3 * k), 14)
	MenuStyle.draw_slant(_canvas, Rect2(x, y, w, 46), Color(MenuStyle.NAVY, 0.94 * k), 14)
	MenuStyle.draw_slant(_canvas, Rect2(x, y + 43, w, 3), Color(MenuStyle.RED, k), 1)
	MenuStyle.draw_bold(_canvas, Vector2(x + 32, y + 33), text, 26, Color(1, 1, 1, k), 0, MenuStyle.INK, 0.2, false)


## MenuStyle.draw_slant, leaning the other way when `mirror` (the right-hand panel).
func _slant(r: Rect2, c: Color, skew: float, mirror: bool) -> void:
	if not mirror:
		MenuStyle.draw_slant(_canvas, r, c, skew)
		return
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	_canvas.draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
			r.position + Vector2(r.size.x + skew, r.size.y), r.position + Vector2(skew, r.size.y)]), c)
