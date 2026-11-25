class_name Stinger
extends CanvasLayer
## The broadcast's league stinger: a navy band edged in red sweeps across the screen with
## the KHL logo riding on it. It covers the whole screen through its middle, where the cut
## happens, so whatever changes underneath (a replay starting, the stats screen, the next
## period) is never seen snapping.
##
## Two ways to use it:
##   - Stinger.play(parent, on_cover): a one-off; `on_cover` runs once the screen is
##     covered, then the band carries on out and the node frees itself.
##   - Stinger.draw(ci, w, k): draw it yourself at progress k (0..1, covered around 0.5),
##     e.g. inside the replay's own overlay.
## It runs while the tree is paused.

const LEN := 0.9                   ## s for the whole sweep
const LOGO_PATH := "res://assets/images/khl_main.png"
const LOGO_SIZE := 640.0
const SKEW := 260.0

static var _logo: Texture2D

var _t := 0.0
var _on_cover := Callable()
var _covered := false
var _canvas: Control


## Plays a stinger over everything and calls `on_cover` once the screen is covered.
## `sound`: its sweep (in, the logo's thump, out).
static func play(parent: Node, on_cover := Callable(), sound := true) -> Stinger:
	var s := Stinger.new()
	s._on_cover = on_cover
	parent.add_child(s)
	if sound:
		Sfx.play("tv_sting", Vector3.INF, -4.0)
	return s


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	MenuStyle.fit(_canvas)
	_canvas.draw.connect(func() -> void: Stinger.draw(_canvas, _canvas.size.x, _t / LEN))


func _process(delta: float) -> void:
	# Real time: a paused tree or slow motion doesn't slow the sweep.
	_t += minf(delta / maxf(Engine.time_scale, 0.01), 0.05)
	if not _covered and _t >= LEN * 0.5:
		_covered = true
		if _on_cover.is_valid():
			_on_cover.call()
	if _t >= LEN:
		queue_free()
		return
	_canvas.queue_redraw()


## True while the band hides the whole screen (the middle of the sweep).
func covering() -> bool:
	return absf(_t / LEN - 0.5) < 0.08


static func logo() -> Texture2D:
	if _logo == null and ResourceLoader.exists(LOGO_PATH):
		_logo = load(LOGO_PATH)
	return _logo


## The sweep at progress k (0 = off left, 0.5 = covering, 1 = off right) on a canvas
## `w` wide (MenuStyle's 900-high design canvas).
static func draw(ci: CanvasItem, w: float, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	var u := k * 2.0 - 1.0
	# Fast in, a held beat in the middle (u³ is flat there), fast out.
	var bw := w * 1.5
	var span := w * 0.5 + bw * 0.5 + SKEW + 80.0
	var cx := w * 0.5 + u * u * u * span
	var x0 := cx - bw * 0.5
	# A red rim, the ink edge, the navy body with red-and-white pinstripes near each end.
	MenuStyle.draw_slant(ci, Rect2(x0 - 70.0, -10, bw + 140, 920), MenuStyle.RED, SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0 - 24, -10, bw + 48, 920), MenuStyle.INK, SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0, -10, bw, 920), MenuStyle.NAVY, SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0 + bw * 0.08, -10, 14, 920), MenuStyle.RED, SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0 + bw * 0.08 + 22, -10, 5, 920), Color(1, 1, 1, 0.8), SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0 + bw * 0.92 - 14, -10, 14, 920), MenuStyle.RED, SKEW)
	MenuStyle.draw_slant(ci, Rect2(x0 + bw * 0.92 - 27, -10, 5, 920), Color(1, 1, 1, 0.8), SKEW)
	# The logo rides the band: it punches in to full size as the band settles, with a
	# little turn, then leaves with it.
	var tex := logo()
	if tex == null:
		var title := "KNOCKOUT HOCKEY"
		MenuStyle.draw_bold(ci, Vector2(cx - MenuStyle.text_width(title, 84) * 0.5 + SKEW * 0.1, 480), title, 84, Color.WHITE, 16, MenuStyle.INK, 0.2, true)
		return
	var a := absf(u)
	var punch := 1.0 + 0.08 * sin(clampf(1.0 - a / 0.35, 0.0, 1.0) * PI)   # a bump as it lands
	var size := LOGO_SIZE * lerpf(1.0, 0.72, clampf(a, 0.0, 1.0)) * punch
	var rot := -0.12 * u * u * u
	ci.draw_set_transform(Vector2(cx + SKEW * 0.05, 450.0), rot, Vector2.ONE)
	var shadow := Rect2(Vector2(-size, -size) * 0.5 + Vector2(10, 14), Vector2(size, size))
	ci.draw_texture_rect(tex, shadow, false, Color(0, 0, 0, 0.45))
	ci.draw_texture_rect(tex, Rect2(Vector2(-size, -size) * 0.5, Vector2(size, size)), false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
