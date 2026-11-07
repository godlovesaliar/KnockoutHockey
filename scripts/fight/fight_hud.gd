class_name FightHud
extends CanvasLayer
## Fight overlay: each fighter's name and health / balance / stamina bars, the clock,
## a controls hint when a human is fighting, the "drop the gloves?" prompt, and banners.

const HEALTH := Color(0.9, 0.2, 0.18)
const BALANCE := Color(0.98, 0.78, 0.2)
const STAMINA := Color(0.3, 0.65, 1.0)

var fight: Fight
var _panels: Array[Dictionary] = []   ## per fighter: {name, health, balance, stamina}
var _fight_root: Control
var _clock: Label
var _hint: Label
var _prompt: Control
var _prompt_bar: ColorRect
var _banner: Label
var _banner_t := 0.0
var _flash: Label
var _flash_t := 0.0


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
	_clock = _label("", 34, Color.WHITE)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.offset_top = 24
	_clock.offset_left = -60
	_clock.offset_right = 60
	_fight_root.add_child(_clock)
	_hint = _label("A jab   X haymaker   B grab   RT uppercut (from a grab)   hold Y block   stick: lean / dodge", 18, Color(0.85, 0.9, 1.0))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -48
	_hint.offset_left = -600
	_hint.offset_right = 600
	_hint.visible = f.is_human_fight()
	_fight_root.add_child(_hint)
	_build_prompt()
	_banner = _label("", 52, Color(1.0, 0.85, 0.2))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 150
	_banner.visible = false
	add_child(_banner)
	_flash = _label("", 30, Color.WHITE)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_flash.offset_top = 220
	_flash.visible = false
	add_child(_flash)


func _panel(fighter: Fight.Fighter, side: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.position = Vector2(30, 24) if side == 0 else Vector2(0, 24)
	box.custom_minimum_size = Vector2(380, 0)
	if side == 1:
		box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		box.position = Vector2(-410, 24)
	_fight_root.add_child(box)
	var info := Teams.team(fight.director.team_ids[fighter.s.team])
	var who: String = fighter.s.last_name.to_upper() if fighter.s.last_name != "" else str(info.name).to_upper()
	var name := _label("#%d  %s" % [fighter.s.number, who], 24, (info.colors.jersey as Color).lerp(Color.WHITE, 0.35))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(name)
	var out := {"name": name}
	for key in ["health", "balance", "stamina"]:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.custom_minimum_size = Vector2(380, 14 if key == "health" else 9)
		box.add_child(bg)
		var bar := ColorRect.new()
		bar.color = {"health": HEALTH, "balance": BALANCE, "stamina": STAMINA}[key]
		bar.size = bg.custom_minimum_size
		bg.add_child(bar)
		out[key] = bar
	out["side"] = side
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
	var c := _label("A — Yes        B — No", 28, Color.WHITE)
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
	return l


func show_prompt(on: bool) -> void:
	_prompt.visible = on


func prompt_left(share: float) -> void:
	_prompt_bar.size.x = 660.0 * clampf(share, 0.0, 1.0)


func show_fight(on: bool) -> void:
	_fight_root.visible = on


func banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_t = 2.6


func flash(text: String) -> void:
	_flash.text = text
	_flash.visible = true
	_flash_t = 0.9


func refresh() -> void:
	var delta := get_process_delta_time()
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	if not _fight_root.visible:
		return
	_clock.text = "%d" % ceili(maxf(fight._time_left, 0.0))
	for k in 2:
		var f: Fight.Fighter = fight.a if k == 0 else fight.b
		var p := _panels[k]
		_set_bar(p.health, f.health / f.max_health, p.side)
		_set_bar(p.balance, f.balance / f.max_balance, p.side)
		_set_bar(p.stamina, f.stamina / f.max_stamina, p.side)


func _set_bar(bar: ColorRect, share: float, side: int) -> void:
	var full := 380.0
	bar.size.x = full * clampf(share, 0.0, 1.0)
	bar.position.x = 0.0 if side == 0 else full - bar.size.x
