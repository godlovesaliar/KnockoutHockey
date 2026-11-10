class_name PadKeyboard
extends Control
## On-screen keyboard for typing with a controller (names in CREATE PLAYER, and anywhere
## else that needs text). A grid of keys in the menu style: the d-pad or stick moves,
## Cross types the key, Circle deletes (on an empty field it cancels), R1 types a space,
## L1 toggles shift, Start finishes. The mouse can click keys too.
##
## Letters cover the jersey letter sheet (SkaterVisual.LETTER_CHARS), so anything typed
## here can go on a nameplate. Shift starts on (and comes back on after a space), so names
## come out capitalized; a letter typed with shift on turns it off again.
##
## Add it to a canvas, then open(); it emits `done(text)` or `cancelled` and hides.

signal done(text: String)
signal cancelled

const KEY := Vector2(64, 52)      ## one key cell
const GAP := 6.0
const PAD := 26.0
const TOP := 128.0                ## room above the keys for the title and the field
## Rows of keys: a character, or [action, label, width in cells].
const ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "'"],
	["Z", "X", "C", "V", "B", "N", "M", "-", ".", "!"],
	[["shift", "SHIFT", 2], "É", "Ñ", "Ô", "Ú", "Û", ["space", "SPACE", 3]],
	[["delete", "DELETE", 3], ["cancel", "CANCEL", 3], ["done", "DONE", 4]],
]
const COLS := 10

var title := ""
var text := ""
var max_length := 16
var digits_only := false
var shift := true
var _keys: Array = []        ## {rect, ch, action, label, row}
var _sel := 0
var _input: MenuInput
var _age := 0.0
var _blink := 0.0
var _shake := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	size = Vector2(PAD * 2 + COLS * KEY.x + (COLS - 1) * GAP, TOP + ROWS.size() * (KEY.y + GAP) + PAD + 40)
	gui_input.connect(_on_mouse)


## Shows the keyboard over `text`, driven by `input` (the screen's MenuInput).
func open(input: MenuInput, field_title: String, start: String, max_len: int, digits := false) -> void:
	if _input != input:
		_input = input
		input.moved.connect(func(dir: int) -> void: if _live(): _move_v(dir))
		input.side.connect(func(dir: int) -> void: if _live(): _move_h(dir))
		input.accepted.connect(func() -> void: if _live(): _press(_sel))
		input.back.connect(func() -> void: if _live(): _backspace(true))
		input.started.connect(func() -> void: if _live(): _finish())
		input.dev_bumper.connect(func(_dev: String, dir: int) -> void:
			if not _live():
				return
			if dir > 0:
				_type(" ")
			else:
				shift = not shift
				_click(1.2))
	title = field_title
	text = start
	max_length = max_len
	digits_only = digits
	shift = start == "" or start.ends_with(" ")
	_sel = 0 if digits else _find_key("Q")
	_age = 0.0
	visible = true


## Open, and not on the frame (press) that opened it.
func _live() -> bool:
	return visible and _age > 0.12


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	_blink += delta
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	queue_redraw()


func _layout() -> void:
	_keys.clear()
	for r in ROWS.size():
		var col := 0
		for k: Variant in ROWS[r]:
			var w := 1
			var d := {"row": r, "ch": "", "action": "", "label": ""}
			if k is Array:
				d.action = k[0]
				d.label = k[1]
				w = k[2]
			else:
				d.ch = k
				d.label = k
			var x := PAD + col * (KEY.x + GAP)
			# Rows shorter than the grid are centered.
			var used := 0
			for k2: Variant in ROWS[r]:
				used += (k2[2] if k2 is Array else 1)
			x += (COLS - used) * (KEY.x + GAP) * 0.5
			d.rect = Rect2(x, TOP + r * (KEY.y + GAP), w * KEY.x + (w - 1) * GAP, KEY.y)
			_keys.append(d)
			col += w


func _find_key(ch: String) -> int:
	for i in _keys.size():
		if _keys[i].ch == ch:
			return i
	return 0


func _move_h(dir: int) -> void:
	var row: int = _keys[_sel].row
	var i := _sel
	while true:
		i = wrapi(i + dir, 0, _keys.size())
		if _keys[i].row == row:
			break
	_sel = i
	_click(1.5)


## Up / down: the key in the next row under the middle of this one.
func _move_v(dir: int) -> void:
	var row: int = wrapi(_keys[_sel].row + dir, 0, ROWS.size())
	var cx: float = (_keys[_sel].rect as Rect2).get_center().x
	var best := _sel
	var best_d := INF
	for i in _keys.size():
		if _keys[i].row != row:
			continue
		var d := absf((_keys[i].rect as Rect2).get_center().x - cx)
		if d < best_d:
			best_d = d
			best = i
	_sel = best
	_click(1.5)


func _press(i: int) -> void:
	var k: Dictionary = _keys[i]
	match k.action:
		"":
			var ch: String = k.ch
			if not shift and ch.to_lower() != ch:
				ch = ch.to_lower()
			_type(ch)
		"shift":
			shift = not shift
			_click(1.2)
		"space":
			_type(" ")
		"delete":
			_backspace(false)
		"cancel":
			visible = false
			Sfx.play("pad", Vector3.INF, -8.0)
			cancelled.emit()
		"done":
			_finish()


func _type(ch: String) -> void:
	if text.length() >= max_length or (digits_only and not ch.is_valid_int()) or (ch == " " and text == ""):
		_shake = 1.0
		Sfx.play("pad", Vector3.INF, -12.0)
		return
	text += ch
	_blink = 0.0
	if ch == " ":
		shift = true
	elif ch.to_lower() != ch.to_upper():
		shift = false
	_click(1.7)


## Circle: delete the last character; on an empty field it backs out (`cancel_empty`).
func _backspace(cancel_empty: bool) -> void:
	if text == "":
		if cancel_empty:
			visible = false
			Sfx.play("pad", Vector3.INF, -8.0)
			cancelled.emit()
		return
	text = text.substr(0, text.length() - 1)
	shift = text == "" or text.ends_with(" ")
	_blink = 0.0
	_click(1.1)


func _finish() -> void:
	visible = false
	Sfx.play("glove", Vector3.INF, -8.0)
	done.emit(text.strip_edges())


func _click(pitch: float) -> void:
	Sfx.play("click", Vector3.INF, -12.0, pitch)


func _on_mouse(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventMouseMotion:
		for i in _keys.size():
			if (_keys[i].rect as Rect2).has_point(e.position) and i != _sel:
				_sel = i
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in _keys.size():
			if (_keys[i].rect as Rect2).has_point(e.position):
				_sel = i
				_press(i)
	accept_event()


func _draw() -> void:
	var pad := _input.using_pad if _input else true
	draw_rect(Rect2(Vector2(6, 6), size), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.1))
	draw_rect(Rect2(0, 0, size.x, 4), MenuStyle.RED)
	var f := MenuStyle.font(0.12)
	MenuStyle.draw_bold(self, Vector2(PAD, 44), title, 26, Color.WHITE, 0, MenuStyle.INK, 0.2, false)
	# The field, with a blinking caret.
	var fr := Rect2(PAD, 60, size.x - PAD * 2, 50)
	var sx := sin(_shake * 30.0) * _shake * 8.0
	fr.position.x += sx
	draw_rect(fr, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(fr.position.x, fr.end.y - 3, fr.size.x, 3), Color(1, 0.92, 0.6))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, fr.position + Vector2(14, 36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	if fmod(_blink, 1.0) < 0.55:
		draw_rect(Rect2(fr.position.x + 16 + tw, fr.position.y + 10, 3, 32), Color(1, 0.92, 0.6))
	var count := "%d / %d" % [text.length(), max_length]
	var cw := f.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(f, Vector2(fr.end.x - cw - 12, fr.position.y + 32), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
	for i in _keys.size():
		var k: Dictionary = _keys[i]
		var r: Rect2 = k.rect
		var on := i == _sel
		var off: bool = digits_only and k.action == "" and not str(k.ch).is_valid_int()
		var fill := MenuStyle.RED if on else Color(0.12, 0.15, 0.26, 0.95)
		if k.action == "shift" and shift and not on:
			fill = Color(0.32, 0.36, 0.5)
		if k.action == "done" and not on:
			fill = Color(0.16, 0.36, 0.22)
		draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.4))
		draw_rect(r, Color(fill, 0.35 if off else fill.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.25 if on else 0.1))
		var label: String = k.label
		if k.action == "" and not shift:
			label = label.to_lower()
		var fs := 26 if k.action == "" else 18
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, r.get_center() + Vector2(-lw * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 1, 1, 0.3 if off else 1.0))
	# The buttons, along the bottom.
	var prompts := [["A", "TYPE"], ["B", "DELETE"], ["RB", "SPACE"], ["LB", "SHIFT"], ["START", "DONE"]] if pad \
			else [["ENTER", "TYPE"], ["ESC", "DELETE"], ["E", "SPACE"], ["Q", "SHIFT"]]
	var x := PAD
	var y := size.y - 44.0
	for p: Array in prompts:
		x += MenuStyle.draw_glyph(self, Vector2(x, y), p[0], pad, 30.0) + 8.0
		draw_string(f, Vector2(x, y + 22), p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		x += f.get_string_size(p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 26.0
