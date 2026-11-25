extends Control
## PRO SHOP: what the player's pucks buy (Store's shelves). Tabs across the top, one per
## category; a column of bars on the left, each an item with its price (or OWNED); a card
## on the right for the selected one: what it is, what it costs, and whether the pucks are
## there. The balance sits top right, as on the main menu.
##
## Up / down picks an item, L1 / R1 (Q / E) or a click switches tabs. Accept buys: the
## first press asks, the second pays (moving off the item calls it off). Back: the main menu.
##
## A team is bought as a challenge: once paid for, its bar reads CHALLENGE and accept
## starts the game against them (team select in challenge mode, then the rules); winning
## it turns the bar to UNLOCKED. The game comes back here afterwards.
##
## `-- shot=<png> [wait=<s>] [tab=teams|rinks|gear] [sel=<n>] [arm=1]` saves a screenshot and quits.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const TEAMS_SCENE := "res://scenes/ui/TeamSelect.tscn"
const MENU_SELECT := 4          ## PRO SHOP's place on the main menu
const ROW_POS := Vector2(80, 178)
const ROW_SIZE := Vector2(700, 50)
const ROW_GAP := 8.0
const VISIBLE_ROWS := 11        ## rows that fit above the footer; a longer shelf scrolls
const TAB_POS := Vector2(500, 70)     ## (clear of the balance plate, top right)
const TAB_SIZE := Vector2(160, 46)
const CARD_X := 860.0
const CARD_Y := 178.0
const CARD_H := 400.0
const GOLD := Color(1.0, 0.82, 0.25)

var _tab := 0
var _rows: Array = []       ## the current tab's items (Store.ITEMS entries)
var _canvas: Control
var _items: Array[MenuItem] = []
var _list: Control
var _tabs: Control
var _art: Control
var _index := 0
var _scroll := 0            ## the first row showing (a shelf longer than VISIBLE_ROWS)
var _armed := false         ## accept was pressed once on this item: the next one buys
var _bought_t := -10.0      ## _t when the last purchase went through (the card flashes)
var _input: MenuInput
var _fade: ColorRect
var _leaving := false
var _t := 0.0


func _ready() -> void:
	Sfx.play_music()
	add_child(MenuBackdrop.new())
	_input = MenuInput.new()
	add_child(_input)
	_input.moved.connect(func(dir: int) -> void:
		if not _items.is_empty():
			_select(wrapi(_index + dir, 0, _items.size())))
	_input.accepted.connect(_accept)
	_input.back.connect(_back)
	_input.dev_bumper.connect(func(_dev: String, dir: int) -> void: _show_tab(wrapi(_tab + dir, 0, Store.CATEGORIES.size())))

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))

	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.1, 0.82))
	g.set_color(1, Color(0.02, 0.04, 0.1, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(2200, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_paint)
	_canvas.add_child(_art)

	_tabs = Control.new()
	_tabs.position = TAB_POS
	_tabs.size = Vector2(TAB_SIZE.x * Store.CATEGORIES.size() + 40, TAB_SIZE.y)
	_tabs.draw.connect(_draw_tabs)
	_tabs.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var k := int((e.position.x - 30.0) / TAB_SIZE.x)
			if k >= 0 and k < Store.CATEGORIES.size() and k != _tab:
				_show_tab(k))
	_canvas.add_child(_tabs)

	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_list)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)

	# (back from a challenge game: the tab it was started from)
	_show_tab(maxi(0, Store.CATEGORIES.find(_arg("tab", Store.shop_tab))), true)
	Store.shop_tab = ""
	if _arg("sel", "") != "" and not _items.is_empty():
		_select(clampi(int(_arg("sel", "0")), 0, _items.size() - 1), true)
	_armed = _arg("arm", "") == "1"


func _process(delta: float) -> void:
	_t += delta
	_art.queue_redraw()
	_tabs.queue_redraw()


func _show_tab(k: int, quiet := false) -> void:
	_tab = k
	for it in _items:
		it.queue_free()
	_items.clear()
	_rows = Store.in_category(Store.CATEGORIES[k])
	for i in _rows.size():
		var it := MenuItem.new()
		it.text = str(_rows[i].name).to_upper()
		it.size = ROW_SIZE
		it.value_w = 200.0
		it.arrows = false
		it.intro(0.05 + i * 0.04)
		it.hovered.connect(func() -> void:
			if _index != i:
				_select(i))
		it.clicked.connect(func() -> void:
			if _index != i:
				_select(i, true)
			_accept())
		_list.add_child(it)
		_items.append(it)
	_scroll = 0
	_layout()
	_refresh()
	if not _items.is_empty():
		_select(0, true)
	if not quiet:
		Sfx.play("click", Vector3.INF, -8.0, 1.1)


func _refresh() -> void:
	for i in _rows.size():
		var id := str(_rows[i].id)
		var done := _done(id)
		_items[i].value = Pucks.fmt(int(_rows[i].price))
		if Store.challenge_ready(id):
			_items[i].value = "CHALLENGE"
		elif _rows[i].has("extra") and Store.owns(id):
			_items[i].value = "ON" if Profile.extra_on(id) else "OFF"
		elif done:
			_items[i].value = "UNLOCKED" if _rows[i].has("team") else "OWNED"
		_items[i].modulate.a = 0.6 if done else 1.0


## Nothing left to do with this item: bought (a team: bought and beaten). An extra is
## never done: once bought, accept is its on / off switch.
func _done(id: String) -> bool:
	var it := Store.item(id)
	if it.has("extra"):
		return false
	return Store.team_unlocked(id) if it.has("team") else Store.owns(id)


## Puts the rows from `_scroll` on in their places; the rest of a long shelf is hidden.
func _layout() -> void:
	for k in _items.size():
		_items[k].position = ROW_POS + Vector2(0, (k - _scroll) * (ROW_SIZE.y + ROW_GAP))
		_items[k].visible = k >= _scroll and k < _scroll + VISIBLE_ROWS


func _select(i: int, quiet := false) -> void:
	_index = i
	_armed = false
	# Keep the picked row in view.
	_scroll = clampi(clampi(_scroll, i - VISIBLE_ROWS + 1, i), 0, maxi(0, _items.size() - VISIBLE_ROWS))
	_layout()
	for k in _items.size():
		_items[k].selected = k == i
		_items[k].glyph = "" if _done(str(_rows[k].id)) else _input.accept_label()
		_items[k].glyph_pad = _input.using_pad
	if not quiet:
		Sfx.play("click", Vector3.INF, -10.0, 1.4)


## The first press on something the pucks cover asks; the second buys it.
func _accept() -> void:
	if _leaving or _index >= _rows.size():
		return
	var id := str(_rows[_index].id)
	if Store.challenge_ready(id):
		_challenge(id)
		return
	if _rows[_index].has("extra") and Store.owns(id):
		# A bought extra: its switch.
		Profile.set_extra(id, not Profile.extra_on(id))
		Sfx.play("click", Vector3.INF, -4.0, 1.5 if Profile.extra_on(id) else 1.0)
		_refresh()
		return
	if Store.owns(id) or not Store.can_afford(id):
		_armed = false
		_items[_index].nudge()
		Sfx.play("pad", Vector3.INF, -8.0)
		return
	if not _armed:
		_armed = true
		Sfx.play("click", Vector3.INF, -6.0, 1.2)
		return
	_armed = false
	if Store.buy(id):
		_bought_t = _t
		if _rows[_index].has("extra"):
			Profile.set_extra(id, true)   # a new extra starts switched on
		Sfx.play("glove", Vector3.INF, -2.0)
		Sfx.play("pad", Vector3.INF, -4.0)
		_refresh()
		_select(_index, true)


## Off to play a bought team's challenge: team select with them at home, then the rules.
func _challenge(id: String) -> void:
	GameSettings.mode = "challenge"
	GameSettings.challenge = Store.team_index(id)
	Store.shop_tab = Store.CATEGORIES[_tab]
	Sfx.play("glove", Vector3.INF, -4.0)
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(TEAMS_SCENE))


func _back() -> void:
	if _leaving:
		return
	Sfx.play("pad", Vector3.INF, -8.0)
	if _armed:
		_armed = false   # (back calls the purchase off first)
		return
	GameSettings.menu_select = MENU_SELECT
	if Store.shop_back == "extras":   # (opened from GAME EXTRAS > UNLOCKABLES: back to that list)
		GameSettings.menu_list = "extras"
		GameSettings.menu_select = 2
	Store.shop_back = ""
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


func _paint() -> void:
	var w := _canvas.size.x
	MenuStyle.draw_tag(_art, Vector2(60, 40), "PRO SHOP", Store.CATEGORY_NAMES[_tab])
	MenuStyle.draw_wallet(_art, w - 60.0, 44.0, Profile.pucks(), ease(clampf((_t - 0.2) / 0.35, 0.0, 1.0), -2.0))
	# More of the shelf above or below what shows: a small arrow beside the list.
	var ax := ROW_POS.x + ROW_SIZE.x + 44.0
	var top := ROW_POS.y + 14.0
	var bottom := ROW_POS.y + VISIBLE_ROWS * (ROW_SIZE.y + ROW_GAP) - ROW_GAP - 14.0
	if _scroll > 0:
		_art.draw_colored_polygon(PackedVector2Array([Vector2(ax, top), Vector2(ax + 11, top + 16), Vector2(ax - 11, top + 16)]), GOLD)
	if _scroll + VISIBLE_ROWS < _items.size():
		_art.draw_colored_polygon(PackedVector2Array([Vector2(ax, bottom), Vector2(ax + 11, bottom - 16), Vector2(ax - 11, bottom - 16)]), GOLD)
	if _index < _rows.size():
		_draw_card(_rows[_index], Rect2(CARD_X + (1.0 - ease(clampf((_t - 0.15) / 0.3, 0.0, 1.0), -2.0)) * 80.0, CARD_Y, w - CARD_X - 60.0, CARD_H))
	var hint := "Everything here is bought with pucks. Play games to earn more."
	var prompts := []
	if _index < _rows.size():
		var id := str(_rows[_index].id)
		if Store.challenge_ready(id):
			hint = "Beat them in their arena, on Pro or harder, to unlock them. Try as often as it takes."
			prompts.append([_input.accept_label(), "PLAY"])
		elif _rows[_index].has("extra") and Store.owns(id):
			hint = "On for every game and Knockout Mode, for both teams. It doesn't change what a game pays."
			prompts.append([_input.accept_label(), "SWITCH OFF" if Profile.extra_on(id) else "SWITCH ON"])
		elif _done(id):
			hint = "Yours already."
		elif not Store.can_afford(id):
			hint = "Not enough pucks yet. Play games to earn more."
		else:
			hint = "Press again to buy it. Back calls it off." if _armed else \
					("Buys the challenge: beat them to unlock them." if _rows[_index].has("team") else "Bought once, yours for good.")
			prompts.append([_input.accept_label(), "CONFIRM" if _armed else "BUY"])
	prompts.append([_input.back_label(), "BACK"])
	MenuStyle.draw_footer(_art, w, hint, prompts, _input.using_pad)


## The selected item: its name, what it is, the price, and where the player stands.
func _draw_card(it: Dictionary, r: Rect2) -> void:
	var f := MenuStyle.font(0.12)
	var id := str(it.id)
	var owned := Store.owns(id)
	var price := int(it.price)
	var flash := clampf(1.0 - (_t - _bought_t) / 0.8, 0.0, 1.0)
	_art.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.3))
	_art.draw_rect(r, Color(0.03, 0.05, 0.1, 0.88).lerp(Color(0.5, 0.4, 0.1, 0.9), flash * 0.6))
	_art.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), MenuStyle.RED)
	var name := str(it.name).to_upper()
	var fs := 40
	while fs > 24 and MenuStyle.text_width(name, fs) > r.size.x - 48.0:
		fs -= 2
	MenuStyle.draw_bold(_art, r.position + Vector2(24, 58), name, fs, Color.WHITE, 0, MenuStyle.INK, 0.2, true)
	var text := str(it.text)
	var text_w := r.size.x - 52.0
	if it.has("team"):
		# A team: its crest, its line ratings, and how the challenge works.
		var team := Store.team_index(id)
		var logo := MenuStyle.team_logo(team)
		if logo:
			# (wide crests get a wider slot, out to the left; less so than elsewhere, the
			# text beside it has to keep to four lines)
			var lw := MenuStyle.logo_slot(logo, 170.0, 1.3)
			MenuStyle.draw_logo(_art, logo, Rect2(r.end.x - 26 - lw, r.position.y + 78, lw, 170))
			text_w -= lw + 20.0
		var rat := MenuArena.ratings(team)
		var x := r.position.x + 26.0
		for k: String in ["OFF", "DEF", "GOAL"]:
			if rat.has(k):
				_art.draw_string(f, Vector2(x, r.position.y + 232), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
				x += MenuStyle.text_width(k, 16, 0.12) + 8.0
				MenuStyle.draw_bold(_art, Vector2(x, r.position.y + 234), str(rat[k]), 28, Color.WHITE, 0, MenuStyle.INK, 0.2, false)
				x += MenuStyle.text_width(str(rat[k]), 28) + 26.0
		text += " Buying them buys the challenge: a game against them in their arena. Win it and they're yours to play as."
	_art.draw_multiline_string(f, r.position + Vector2(26, 104), text, HORIZONTAL_ALIGNMENT_LEFT, text_w, 21, 6, MenuStyle.ICE)
	# The price (or OWNED) on a darker band along the bottom, with what's missing or what to press.
	var band := Rect2(r.position.x, r.end.y - 130, r.size.x, 130)
	_art.draw_rect(band, Color(0, 0, 0, 0.3))
	_art.draw_rect(Rect2(band.position, Vector2(band.size.x, 2)), Color(1, 1, 1, 0.08))
	if Store.challenge_ready(id):
		MenuStyle.draw_bold(_art, band.position + Vector2(26, 78), "CHALLENGE READY", 46, GOLD, 0, MenuStyle.INK, 0.2, false)
		_art.draw_string(f, band.position + Vector2(28, 110), "Beat them to unlock them. Rematches are free.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
		return
	if owned and it.has("extra"):
		var on := Profile.extra_on(id)
		MenuStyle.draw_bold(_art, band.position + Vector2(26, 78), "ON" if on else "OFF", 52, GOLD if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
		_art.draw_string(f, band.position + Vector2(28, 110), "Yours. Switch it on and off here.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
		return
	if owned:
		MenuStyle.draw_bold(_art, band.position + Vector2(26, 78), "UNLOCKED" if it.has("team") else "OWNED", 52, GOLD, 0, MenuStyle.INK, 0.2, false)
		_art.draw_string(f, band.position + Vector2(28, 110), "Beaten, and yours to play as." if it.has("team") else "Bought for %s pucks." % Pucks.fmt(price),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
		return
	var short := price - Profile.pucks()
	MenuStyle.draw_puck(_art, band.position + Vector2(52, 52), 24.0)
	MenuStyle.draw_bold(_art, band.position + Vector2(92, 74), Pucks.fmt(price), 52, Color.WHITE if short <= 0 else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	var note := "You have enough."
	var note_col := MenuStyle.DIM
	if short > 0:
		note = "%s more pucks to go." % Pucks.fmt(short)
		note_col = Color(1.0, 0.55, 0.5)
	elif _armed:
		note = "PRESS AGAIN TO BUY"
		note_col = GOLD if fmod(_t, 0.7) < 0.45 else Color.WHITE
	_art.draw_string(f, band.position + Vector2(28, 110), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, note_col)


## The tab strip: slanted plates, the current one red, with the L1 / R1 prompts either side.
func _draw_tabs() -> void:
	var pad := _input.using_pad
	var gy := (TAB_SIZE.y - 30.0) * 0.5
	MenuStyle.draw_glyph(_tabs, Vector2(-14, gy), "L1" if pad else "Q", false, 30.0)
	for k in Store.CATEGORIES.size():
		var r := Rect2(Vector2(30.0 + k * TAB_SIZE.x, 0), TAB_SIZE - Vector2(12, 0))
		var on := k == _tab
		MenuStyle.draw_slant(_tabs, Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.35), 16.0)
		MenuStyle.draw_slant(_tabs, r, MenuStyle.RED if on else Color(0.06, 0.08, 0.15, 0.85), 16.0)
		if on:
			_tabs.draw_rect(Rect2(r.position + Vector2(16, r.size.y - 4), Vector2(r.size.x - 16, 4)), Color(1, 1, 1, 0.85))
		var name: String = Store.CATEGORY_NAMES[k]
		var tw := MenuStyle.text_width(name, 22)
		MenuStyle.draw_bold(_tabs, r.position + Vector2((r.size.x - tw) * 0.5 + 8, 31), name, 22,
				Color.WHITE if on else MenuStyle.DIM, 0, MenuStyle.INK, 0.2, false)
	MenuStyle.draw_glyph(_tabs, Vector2(30.0 + Store.CATEGORIES.size() * TAB_SIZE.x + 6.0, gy), "R1" if pad else "E", false, 30.0)


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
