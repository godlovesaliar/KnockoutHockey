class_name FightHud
extends CanvasLayer
## Fight overlay. Each fighter: name, three labeled bars (HEALTH, BALANCE, STAMINA, with
## what drains each for the first seconds), a ghost chunk showing the damage just taken,
## and a status tag (HOLDING / HELD / BLOCKING / WINDED / WOBBLY / ROCKED). Center: the
## clock and how to win. Bottom: the controls on the human's own device. Also the "drop
## the gloves?" prompt, banners and short call-outs.

const HEALTH := Color(0.92, 0.22, 0.2)
const BALANCE := Color(0.98, 0.78, 0.2)
const STAMINA := Color(0.3, 0.68, 1.0)
const GHOST := Color(1.0, 1.0, 1.0, 0.85)
const BAR_W := 280.0
const LABEL_W := 80.0
const CAPTION_TIME := 9.0     ## seconds the "what drains it" notes stay up
const BARS := [
	["health", "HEALTH", HEALTH, 18.0, "punches"],
	["balance", "BALANCE", BALANCE, 13.0, "big shots, being held"],
	["stamina", "STAMINA", STAMINA, 10.0, "every swing; back off to refill"],
]

var fight: Fight
var _panels: Array[Dictionary] = []   ## per fighter
var _fight_root: Control
var _clock: Label
var _goal: Label
var _hint: Label
var _prompt: Control
var _prompt_bar: ColorRect
var _banner: Label
var _banner_t := 0.0
var _flash: Label
var _flash_t := 0.0
var _fight_t := 0.0


func setup(f: Fight) -> void:
	fight = f
	layer = 5
	_fight_root = Control.new()
	_fight_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fight_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fight_root.visible = false
	add_child(_fight_root)
	for k in 2:
		var fighter: Fight.Fighter = f.a if k == 0 else f.b
		_panels.append(_panel(fighter, k))
	_clock = _label("", 40, Color.WHITE)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.offset_top = 16
	_clock.offset_left = -70
	_clock.offset_right = 70
	_fight_root.add_child(_clock)
	_goal = _label("DROP THEM: EMPTY THEIR HEALTH OR BALANCE\nTIME UP: MORE DAMAGE DEALT WINS", 14, Color(1.0, 0.9, 0.6))
	_goal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_goal.offset_top = 64
	_goal.offset_left = -260
	_goal.offset_right = 260
	_fight_root.add_child(_goal)
	_hint = _label(_controls_text(f.human_brain()), 19, Color(0.88, 0.92, 1.0))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -70
	_hint.offset_bottom = -14
	_hint.offset_left = -700
	_hint.offset_right = 700
	_hint.visible = f.is_human_fight()
	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0.02, 0.03, 0.06, 0.6)
	hint_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_bg.offset_top = -78
	hint_bg.visible = _hint.visible
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fight_root.add_child(hint_bg)
	_fight_root.add_child(_hint)
	_build_prompt()
	_banner = _label("", 52, Color(1.0, 0.85, 0.2))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 150
	_banner.visible = false
	add_child(_banner)
	_flash = _label("", 30, Color.WHITE)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_flash.offset_top = 215
	_flash.visible = false
	add_child(_flash)


func _controls_text(h: HumanBrain) -> String:
	if h == null:
		return ""
	var b := func(n: String) -> String: return "[%s]" % h.button_label(n)
	var mv: Array = h.move_labels()
	return "%s Jab     %s Haymaker     %s Grab / break free     %s Uppercut (while holding)     hold %s Block\n%s: step in / back off     %s: slip a punch" % [
		b.call("pass"), b.call("shoot"), b.call("check"), b.call("turbo"), b.call("deke"), mv[0], mv[1]]


func _panel(fighter: Fight.Fighter, side: int) -> Dictionary:
	var w := LABEL_W + BAR_W
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.custom_minimum_size = Vector2(w, 0)
	if side == 0:
		box.position = Vector2(28, 18)
	else:
		box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		box.position = Vector2(-w - 28, 18)
	_fight_root.add_child(box)
	var info := Teams.team(fight.director.team_ids[fighter.s.team])
	var who: String = fighter.s.last_name.to_upper() if fighter.s.last_name != "" else str(info.name).to_upper()
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_BEGIN if side == 0 else BoxContainer.ALIGNMENT_END
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var name := _label("#%d  %s" % [fighter.s.number, who], 26, (info.colors.jersey as Color).lerp(Color.WHITE, 0.35))
	var status := _label("", 17, Color(1.0, 0.9, 0.5))
	if side == 0:
		head.add_child(name)
		head.add_child(status)
	else:
		head.add_child(status)
		head.add_child(name)
	var out := {"status": status, "side": side, "box": box}
	for spec: Array in BARS:
		var key: String = spec[0]
		var row := Control.new()
		row.custom_minimum_size = Vector2(w, spec[3])
		box.add_child(row)
		var lab := _label(spec[1], 13 if key != "health" else 15, (spec[2] as Color).lerp(Color.WHITE, 0.3))
		lab.size = Vector2(LABEL_W - 8, spec[3])
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == 0 else HORIZONTAL_ALIGNMENT_LEFT
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.position = Vector2(0.0 if side == 0 else BAR_W + 8.0, 0.0)
		row.add_child(lab)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.6)
		bg.size = Vector2(BAR_W, spec[3])
		bg.position = Vector2(LABEL_W if side == 0 else 0.0, 0.0)
		row.add_child(bg)
		var ghost := ColorRect.new()
		ghost.color = GHOST
		ghost.size = bg.size
		bg.add_child(ghost)
		var bar := ColorRect.new()
		bar.color = spec[2]
		bar.size = bg.size
		bg.add_child(bar)
		var cap := _label(spec[4], 11, Color(1, 1, 1, 0.9))
		cap.add_theme_constant_override("outline_size", 5)
		cap.size = bg.size
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		cap.position = Vector2(6.0 if side == 0 else -6.0, 0.0)
		bg.add_child(cap)
		out[key] = {"bar": bar, "ghost": ghost, "cap": cap, "shown": 1.0, "ghost_v": 1.0, "hold": 0.0}
	var call := _label("", 18, Color.WHITE)
	call.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(call)
	out["call"] = call
	out["call_t"] = 0.0
	return out


func _build_prompt() -> void:
	_prompt = VBoxContainer.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -330
	_prompt.offset_right = 330
	_prompt.offset_top = -80
	_prompt.offset_bottom = 80
	_prompt.visible = false
	add_child(_prompt)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.85)
	bg.custom_minimum_size = Vector2(660, 150)
	_prompt.add_child(bg)
	var t := _label("DROP THE GLOVES?", 44, Color(1.0, 0.85, 0.2))
	t.position = Vector2(0, 14)
	t.size = Vector2(660, 50)
	bg.add_child(t)
	var h := fight.prompt_brain
	var yes := h.button_label("pass") if h else "A"
	var no := h.button_label("check") if h else "B"
	var c := _label("%s — Yes        %s — No" % [yes, no], 28, Color.WHITE)
	c.position = Vector2(0, 72)
	c.size = Vector2(660, 40)
	bg.add_child(c)
	_prompt_bar = ColorRect.new()
	_prompt_bar.color = Color(1.0, 0.85, 0.2)
	_prompt_bar.position = Vector2(0, 140)
	_prompt_bar.size = Vector2(660, 10)
	bg.add_child(_prompt_bar)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func show_prompt(on: bool) -> void:
	_prompt.visible = on


func prompt_left(share: float) -> void:
	_prompt_bar.size.x = 660.0 * clampf(share, 0.0, 1.0)


func show_fight(on: bool) -> void:
	_fight_root.visible = on
	_fight_t = 0.0


func banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_t = 2.6


## A call-out for both to see (a grab, a slip, a break).
func flash(text: String) -> void:
	_flash.text = text
	_flash.visible = true
	_flash_t = 1.0


## A call-out under one fighter's bars (blocked, out of range, how to do something).
func flash_for(f: Fight.Fighter, text: String) -> void:
	var p := _panels[0 if f == fight.a else 1]
	(p.call as Label).text = text
	p.call_t = 1.3


func refresh() -> void:
	var delta := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	if not _fight_root.visible:
		return
	_fight_t += delta
	_clock.text = "%d" % ceili(maxf(fight.time_left(), 0.0))
	_clock.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if fight.time_left() < 6.0 else Color.WHITE)
	var cap_a := clampf((CAPTION_TIME - _fight_t) / 1.5, 0.0, 1.0)
	for k in 2:
		var f: Fight.Fighter = fight.a if k == 0 else fight.b
		var p := _panels[k]
		_set_bar(p.health, f.health / f.max_health, p.side, delta, f.flash_t)
		_set_bar(p.balance, f.balance / f.max_balance, p.side, delta, f.flash_t)
		_set_bar(p.stamina, f.stamina / f.max_stamina, p.side, delta, 0.0)
		for key in ["health", "balance", "stamina"]:
			(p[key].cap as Label).modulate.a = cap_a
		(p.status as Label).text = _status(f)
		p.call_t -= delta
		(p.call as Label).visible = p.call_t > 0.0


func _status(f: Fight.Fighter) -> String:
	if f.act == "down":
		return ""
	if f.grabbing > 0.0:
		return "HOLDING"
	if f.other.grabbing > 0.0:
		return "HELD — BREAK FREE"
	if f.act == "hit":
		return "ROCKED"
	if f.balance < f.max_balance * 0.3:
		return "WOBBLY"
	if f.stamina < f.max_stamina * 0.15:
		return "WINDED"
	if f.blocking:
		return "BLOCKING"
	return ""


## The bar eases to its value; what was lost lingers as a white chunk, then drains.
func _set_bar(b: Dictionary, share: float, side: int, delta: float, flash: float) -> void:
	share = clampf(share, 0.0, 1.0)
	if share < b.shown - 0.004:
		b.hold = 0.5   # a fresh loss: the chunk lingers, then drains
	b.shown = share
	if share > b.ghost_v:
		b.ghost_v = share
	b.hold -= delta
	if b.hold <= 0.0:
		b.ghost_v = move_toward(b.ghost_v, share, delta * 0.6)
	var bar: ColorRect = b.bar
	var ghost: ColorRect = b.ghost
	bar.size.x = BAR_W * share
	bar.position.x = 0.0 if side == 0 else BAR_W - bar.size.x
	ghost.size.x = BAR_W * b.ghost_v
	ghost.position.x = 0.0 if side == 0 else BAR_W - ghost.size.x
	bar.modulate = Color(1.6, 1.6, 1.6) if flash > 0.0 and fmod(flash, 0.12) > 0.06 else Color.WHITE
