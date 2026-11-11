extends CanvasLayer
## A small frame-rate readout at the top center of the screen, over everything (menus,
## matches, pause). Hidden at start; F3 shows or hides it. Every half second it shows the average FPS, the
## average frame time, and the slowest frame in that window (as FPS), so stutters show up
## even when the average looks fine. With vsync on, FPS tops out at the display's refresh rate.

const UPDATE_EVERY := 0.5   ## seconds

var _label: Label
var _panel: PanelContainer
var _time := 0.0
var _frames := 0
var _worst := 0.0


func _ready() -> void:
	layer = 100
	visible = false   # hidden until F3
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps counting while the game is paused
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	_panel.add_theme_stylebox_override("panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.text = "-- FPS"
	_panel.add_child(_label)
	add_child(_panel)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	_panel.reset_size()
	var w := get_viewport().get_visible_rect().size.x
	_panel.position = Vector2((w - _panel.size.x) * 0.5, 6.0)


func _process(delta: float) -> void:
	_time += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _time < UPDATE_EVERY:
		return
	var fps := _frames / _time
	var ms := 1000.0 * _time / _frames
	var low := 1.0 / maxf(_worst, 0.0001)
	_label.text = "%d FPS   %.1f ms   low %d" % [roundi(fps), ms, roundi(low)]
	# Green at 55+, yellow at 30+, red below.
	var c := Color(0.85, 1.0, 0.85) if fps >= 55.0 else (Color(1.0, 0.9, 0.5) if fps >= 30.0 else Color(1.0, 0.55, 0.5))
	_label.add_theme_color_override("font_color", c)
	_place()
	_time = 0.0
	_frames = 0
	_worst = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F3:
		visible = not visible
