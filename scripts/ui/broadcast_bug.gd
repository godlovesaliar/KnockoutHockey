class_name BroadcastBug
extends CanvasLayer
## The network's on-screen bug: a league mark in the top-right corner, a little see-through,
## for as long as the game is on the air. The KHL monogram in regular games, the
## championship belt in Knockout Mode. The scorebug owns the top left, the replay tag
## takes the top right only while the game's layers are hidden, so they never meet.
## MatchDirector shows it whenever the rink is on screen (not over the matchup intro or
## a stats screen).

const MONO := "res://assets/images/khl_mono.png"
const BELT := "res://assets/images/khl_belt.png"
const MARGIN := Vector2(36, 26)     ## from the top-right corner (the scorebug's inset)
const HEIGHT := 72.0
const ALPHA := 0.85
const FADE := 0.4                   ## s to fade in or out

var tex: Texture2D
var shown := true                   ## where it's headed; it fades there
var _canvas: Control
var _a := 0.0


func setup(knockout: bool) -> void:
	layer = 4   # under the fight overlay (5), the knockout cards (6) and the menus
	process_mode = Node.PROCESS_MODE_ALWAYS
	var path := BELT if knockout else MONO
	tex = load(path) if ResourceLoader.exists(path) else null
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_canvas))
	_canvas.draw.connect(_draw)


func _process(delta: float) -> void:
	var want := 1.0 if shown else 0.0
	if not is_equal_approx(_a, want):
		_a = move_toward(_a, want, delta / FADE)
		_canvas.queue_redraw()


func _draw() -> void:
	if tex == null or _a <= 0.0:
		return
	var h := HEIGHT * (1.1 if tex.resource_path == BELT else 1.0)
	var w := h * tex.get_width() / float(tex.get_height())
	var r := Rect2(Vector2(_canvas.size.x - MARGIN.x - w, MARGIN.y), Vector2(w, h))
	_canvas.draw_texture_rect(tex, Rect2(r.position + Vector2(3, 4), r.size), false, Color(0, 0, 0, 0.3 * _a))
	_canvas.draw_texture_rect(tex, r, false, Color(1, 1, 1, ALPHA * _a))
