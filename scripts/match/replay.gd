class_name Replay
extends Node
## Instant replays: goals, big hits and knockouts.
##
## Every player's skeleton ends with a ReplayTap that records its finished pose (and the
## stick) about 30 times a second of game time; this node records the puck. A highlight
## is a clip cut from those rings: `capture()` marks one `pre` seconds back and cuts it
## `post` seconds later (so the moment plays out), then either plays it at once or
## keeps it for later (`play_pending`: the next stoppage, or the intermission).
##
## Playing pauses the game tree, hides the game's HUD layers, swaps in a replay camera
## and writes the recorded poses back onto the same skeletons (each tap overrides its
## skeleton's pose; the skeleton's world transform and the stick are set directly). The
## real puck's look is hidden and a copy follows the recorded puck. A red wipe covers the
## cut in and out. Any accept / back / Start skips. Afterwards everything is put back
## exactly as it was and play continues.
##
## Cameras: "net" (goals: low, off the post of the net it went into, following the
## puck) and "orbit" (hits and knockouts: circling the players involved, close).

signal finished

static var now := 0.0              ## game seconds recorded so far (stops during replays)
static var recording := true

const PUCK_HZ := 30.0
const KEEP := 14.0
const WIPE := 0.5                  ## s for the wipe to cross the screen
const STOPPAGE_MAX_AGE := 45.0     ## a saved highlight older than this waits for the intermission

var director: MatchDirector
var taps: Array[ReplayTap] = []
var highlights: Array[Dictionary] = []   ## cut clips not played at once: kind, label, shown...
var playing := false

var _puck_frames: Array = []       ## [t, Transform3D, visible]
var _puck_last := -1.0
var _captures: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _clip: Dictionary
var _t := 0.0
var _stage := ""                   ## "in" (wipe, cut at its middle), "play", "out", "done"
var _stage_t := 0.0
var _last_real := 0.0
var _done := Callable()
var _saved := []
var _hidden_layers: Array[CanvasLayer] = []
var _cam: Camera3D
var _prev_cam: Camera3D
var _ghost: MeshInstance3D
var _look := Vector3.ZERO
var _overlay: Control
var _layer: CanvasLayer
var _input: MenuInput
var _skip := false
var _sfx_mode := Node.PROCESS_MODE_INHERIT


func setup(d: MatchDirector) -> void:
	director = d
	process_mode = Node.PROCESS_MODE_ALWAYS
	now = 0.0
	recording = true
	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_cam)
	_layer = CanvasLayer.new()
	_layer.layer = 15
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_overlay)
	MenuStyle.fit(_overlay)
	get_viewport().size_changed.connect(func() -> void: MenuStyle.fit(_overlay))
	_overlay.draw.connect(_draw_overlay)
	_layer.visible = false
	_input = MenuInput.new()
	_input.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_input)
	_input.accepted.connect(_on_skip)
	_input.back.connect(_on_skip)
	_input.started.connect(_on_skip)


## Adds a tap to a player's skeleton (after the rig, so it sees the finished pose).
func register(s: Skater) -> void:
	if s == null or s.visual == null or s.visual.skel == null:
		return
	var tap := ReplayTap.new()
	tap.name = "ReplayTap"
	tap.visual = s.visual
	tap.process_mode = Node.PROCESS_MODE_ALWAYS
	s.visual.skel.add_child(tap)
	taps.append(tap)


func _process(_delta: float) -> void:
	var real := Time.get_ticks_usec() / 1000000.0
	var dt := clampf(real - _last_real, 0.0, 0.1) if _last_real > 0.0 else 0.0
	_last_real = real
	if playing:
		_tick_play(dt)
		return
	if get_tree().paused:
		return
	now += _delta
	_record_puck()
	for c in _captures.duplicate():
		if now >= c.t1:
			_captures.erase(c)
			_cut(c)


func _record_puck() -> void:
	if director.puck == null or now - _puck_last < 1.0 / PUCK_HZ:
		return
	_puck_last = now
	var vis: MeshInstance3D = director.puck.get_node("Visual")
	_puck_frames.append([now, vis.global_transform, director.puck.is_visible_in_tree()])
	while not _puck_frames.is_empty() and _puck_frames[0][0] < now - KEEP:
		_puck_frames.pop_front()


# --- Capturing -------------------------------------------------------------------------

## Marks a highlight: from `pre` seconds ago until `post` seconds from now. `focus`: the
## players the orbit camera circles. opts: play_now (bool), speed (playback rate),
## cam ("net" / "orbit"), net (the net's position, "net" cam).
func capture(kind: String, label: String, focus: Array, pre: float, post: float, opts := {}) -> void:
	var c := {"kind": kind, "label": label, "focus": focus.filter(func(s) -> bool: return is_instance_valid(s)),
		"t0": maxf(now - pre, 0.0), "t1": now + post, "at": now, "shown": false,
		"play_now": opts.get("play_now", false), "speed": opts.get("speed", 1.0),
		"cam": opts.get("cam", "orbit"), "net": opts.get("net", Vector3.ZERO)}
	_captures.append(c)


## True while a highlight is waiting to be cut and played straight away (goals count:
## theirs plays after the celebration).
func busy() -> bool:
	return playing or _captures.any(func(c: Dictionary) -> bool: return c.play_now or c.kind == "goal")


func _cut(c: Dictionary) -> void:
	var tracks := {}
	for tap in taps:
		if is_instance_valid(tap):
			var tr := tap.slice(c.t0, c.t1)
			if not tr.is_empty():
				tracks[tap] = tr
	var puck: Array = []
	for i in _puck_frames.size():
		var t: float = _puck_frames[i][0]
		if t >= c.t0 - 0.1 and t <= c.t1 + 0.1:
			puck.append(_puck_frames[i])
	c.tracks = tracks
	c.puck = puck
	c.focus_taps = []
	for s in c.focus:
		if is_instance_valid(s) and s.visual and s.visual.skel:
			for tap in taps:
				if tap.visual == s.visual:
					c.focus_taps.append(tap)
	if c.play_now:
		c.shown = true
		play([c])
	else:
		highlights.append(c)


## Plays up to `n` saved highlights not shown yet (newest first among `kinds`, any kind
## if empty, no older than `max_age` game seconds). Returns true if something plays.
func play_pending(n: int, kinds: Array = [], max_age := INF, done := Callable()) -> bool:
	var pick: Array[Dictionary] = []
	for i in range(highlights.size() - 1, -1, -1):
		var h := highlights[i]
		if h.shown or (not kinds.is_empty() and not (h.kind in kinds)) or now - h.at > max_age:
			continue
		pick.push_front(h)
		if pick.size() >= n:
			break
	if pick.is_empty():
		return false
	for h in pick:
		h.shown = true
	return play(pick, done)


## Plays the newest highlight of `kind` now, or, if it's still being recorded, as soon as
## it's cut. (A goal: after its celebration.)
func play_soon(kind: String) -> void:
	for c in _captures:
		if c.kind == kind:
			c.play_now = true
			return
	play_pending(1, [kind])


## Clears saved highlights (a new period).
func forget() -> void:
	highlights.clear()


# --- Playing ---------------------------------------------------------------------------

func play(clips: Array, done := Callable()) -> bool:
	if playing or clips.is_empty() or director.get_tree().paused:
		return false   # (the pause menu is up: not now)
	playing = true
	recording = false
	_skip = false
	_done = done
	_queue.clear()
	for c: Dictionary in clips:
		_queue.append(c)
	_clip = _queue.pop_front()
	_stage = "in"
	_stage_t = 0.0
	get_tree().paused = true
	# The arena keeps sounding through the replay (crowd, organ, the booth): only the game
	# stops. (The pause menu still silences it.)
	_sfx_mode = Sfx.process_mode
	Sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.visible = true
	return true


func _on_skip() -> void:
	if playing and _stage == "play":
		_skip = true
		_queue.clear()
		_stage = "out"
		_stage_t = 0.0


func _tick_play(dt: float) -> void:
	_stage_t += dt
	match _stage:
		"in":
			if _stage_t >= WIPE * 0.5 and _saved.is_empty():
				_begin_clip()
			if _stage_t >= WIPE:
				_stage = "play"
		"play":
			_t += dt * float(_clip.speed)
			if _t >= _clip.t1:
				_t = _clip.t1
				if _queue.is_empty():
					_stage = "out"
				else:
					_stage = "next"
				_stage_t = 0.0
		"next":
			# Between two highlights: the wipe covers the switch.
			if _stage_t >= WIPE * 0.5 and _clip.has("tracks") and not _clip.get("left", false):
				_clip.left = true
				_clip = _queue.pop_front()
				_t = _clip.t0
				_look = _focus_point()
				_place_cam(true)
			if _stage_t >= WIPE:
				_stage = "play"
		"out":
			if _stage_t >= WIPE * 0.5 and not _saved.is_empty():
				_end_clips()
			if _stage_t >= WIPE:
				_finish()
				return
	if not _saved.is_empty():
		_apply(_t)
		_place_cam(false, dt)
	_overlay.queue_redraw()


func _begin_clip() -> void:
	# Put the game's HUD layers away and remember every player's live state.
	_hidden_layers.clear()
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl != _layer and cl.visible:
			cl.visible = false
			_hidden_layers.append(cl)
	_saved.clear()
	for tap in taps:
		if not is_instance_valid(tap):
			continue
		var v := tap.visual
		var sk := v.skel
		_saved.append({"tap": tap, "skel_x": sk.transform, "skel_pm": sk.process_mode, "rig": v.rig.active,
			"shaft_x": v.shaft.transform if v.shaft else Transform3D(), "shaft_vis": v.shaft.visible if v.shaft else false,
			"vis": v.skater.visible})
		sk.process_mode = Node.PROCESS_MODE_ALWAYS
		v.rig.active = false
	var real_vis: MeshInstance3D = director.puck.get_node("Visual")
	if _ghost == null:
		_ghost = real_vis.duplicate() as MeshInstance3D
		_ghost.process_mode = Node.PROCESS_MODE_ALWAYS
		director.add_child(_ghost)
	_ghost.visible = true
	real_vis.visible = false
	_prev_cam = get_viewport().get_camera_3d()
	_cam.current = true
	_t = _clip.t0
	_look = _focus_point()
	_place_cam(true)


func _apply(t: float) -> void:
	for tap: ReplayTap in _clip.tracks:
		if not is_instance_valid(tap):
			continue
		var f := ReplayTap.sample(_clip.tracks[tap], t)
		if f.is_empty():
			continue
		tap.override = f
		var v := tap.visual
		v.skel.global_transform = ReplayTap.get_xform(f, 1).orthonormalized()
		v.skater.visible = f[25] > 0.5
		if v.shaft:
			var sx := ReplayTap.get_xform(f, 13)
			v.shaft.visible = sx.basis.x.length_squared() > 0.0001
			if v.shaft.visible:
				v.shaft.global_transform = sx
	# The puck.
	var pf: Array = _clip.puck
	if pf.is_empty():
		_ghost.visible = false
		return
	var a: Array = pf[0]
	var b: Array = pf[0]
	for i in pf.size():
		if pf[i][0] <= t:
			a = pf[i]
			b = pf[mini(i + 1, pf.size() - 1)]
	var u := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
	_ghost.global_transform = (a[1] as Transform3D).interpolate_with(b[1], u)
	_ghost.visible = bool(a[2])


func _end_clips() -> void:
	for st: Dictionary in _saved:
		var tap: ReplayTap = st.tap
		if not is_instance_valid(tap):
			continue
		tap.override = PackedFloat32Array()
		var v := tap.visual
		v.skel.transform = st.skel_x
		v.skel.process_mode = st.skel_pm
		v.rig.active = st.rig
		if v.shaft:
			v.shaft.transform = st.shaft_x
			v.shaft.visible = st.shaft_vis
		v.skater.visible = st.vis
	_saved.clear()
	(director.puck.get_node("Visual") as MeshInstance3D).visible = true
	if _ghost:
		_ghost.visible = false
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	for cl in _hidden_layers:
		if is_instance_valid(cl):
			cl.visible = true
	_hidden_layers.clear()


func _finish() -> void:
	playing = false
	recording = true
	_layer.visible = false
	_stage = ""
	get_tree().paused = false
	Sfx.process_mode = _sfx_mode
	finished.emit()
	if _done.is_valid():
		_done.call()


# --- Cameras ---------------------------------------------------------------------------

## Where the replay looks: the focus players (their recorded hips), else the puck.
func _focus_point() -> Vector3:
	var pts: Array[Vector3] = []
	for tap in _clip.get("focus_taps", []):
		if is_instance_valid(tap) and _clip.tracks.has(tap):
			var f := ReplayTap.sample(_clip.tracks[tap], _t)
			if not f.is_empty():
				pts.append(ReplayTap.get_xform(f, 1).origin)
	if _clip.cam == "net" or pts.is_empty():
		return _puck_at(_t) + Vector3.UP * 0.4
	var m := Vector3.ZERO
	for p in pts:
		m += p
	return m / pts.size() + Vector3.UP * 1.05


## How far apart the focus players are now (0 for one), so the orbit stays clear of them.
func _focus_spread() -> float:
	var pts: Array[Vector3] = []
	for tap in _clip.get("focus_taps", []):
		if is_instance_valid(tap) and _clip.tracks.has(tap):
			var f := ReplayTap.sample(_clip.tracks[tap], _t)
			if not f.is_empty():
				pts.append(ReplayTap.get_xform(f, 1).origin)
	return pts[0].distance_to(pts[1]) if pts.size() >= 2 else 0.0


func _puck_at(t: float) -> Vector3:
	var pf: Array = _clip.puck
	if pf.is_empty():
		return Vector3.ZERO
	var best: Array = pf[0]
	for f in pf:
		if f[0] <= t:
			best = f
	return (best[1] as Transform3D).origin


func _place_cam(snap: bool, dt := 0.0) -> void:
	var target := _focus_point()
	_look = target if snap else _look.lerp(target, 1.0 - exp(-6.0 * dt))
	var elapsed := (_t - float(_clip.t0)) / maxf(float(_clip.speed), 0.05)
	var pos: Vector3
	if _clip.cam == "net":
		# Off the post of the net the puck went into, low, a little beyond the goal line.
		var net: Vector3 = _clip.net
		var out := signf(net.z) if absf(net.z) > 0.1 else 1.0
		var side := -1.0 if _look.x > 0.0 else 1.0
		pos = net + Vector3(side * 4.4, 2.2, out * 1.3)
	else:
		# Circling the players, starting on the ice side so the boards stay behind them.
		var base := atan2(-_look.x, -_look.z)
		var ang := base + 0.6 + elapsed * 0.22
		var r := (3.6 if _clip.kind == "ko" else 4.6) + _focus_spread() * 0.6
		pos = Vector3(_look.x + sin(ang) * r, 1.9, _look.z + cos(ang) * r)
		var inside := RinkSpec.clamp_inside(pos.x, pos.z, 0.6)
		pos = Vector3(inside.x, pos.y, inside.y)
	_cam.look_at_from_position(pos, _look)
	# The lens zooms in on far-off play (about 12 m of ice across the frame), out up close.
	var want := clampf(rad_to_deg(2.0 * atan(6.0 / maxf(pos.distance_to(_look), 0.1))), 16.0, 52.0)
	_cam.fov = want if snap else lerpf(_cam.fov, want, 1.0 - exp(-4.0 * dt))


# --- Overlay ---------------------------------------------------------------------------

func _draw_overlay() -> void:
	var ci := _overlay
	var w := _overlay.size.x
	if _stage == "play" or _stage == "next" or (_stage == "out" and _stage_t < WIPE * 0.5) or (_stage == "in" and _stage_t >= WIPE * 0.5):
		_draw_tag(ci, w)
	if _stage in ["in", "next", "out"]:
		_draw_wipe(ci, w, clampf(_stage_t / WIPE, 0.0, 1.0))


## Top right: a red REPLAY tag, what it is under it, slow motion noted; the skip prompt.
func _draw_tag(ci: Control, w: float) -> void:
	var x := w - 470.0
	var y := 34.0
	MenuStyle.draw_slant(ci, Rect2(x + 6, y + 7, 420, 58), Color(0, 0, 0, 0.35), 18)
	MenuStyle.draw_slant(ci, Rect2(x, y, 420, 58), MenuStyle.RED, 18)
	MenuStyle.draw_slant(ci, Rect2(x, y + 52, 420, 6), MenuStyle.RED_DARK, 2)
	MenuStyle.draw_bold(ci, Vector2(x + 30, y + 45), "REPLAY", 40, Color.WHITE, 8, MenuStyle.INK, 0.2, false)
	if float(_clip.speed) < 0.7:
		ci.draw_string(MenuStyle.font(0.12), Vector2(x + 250, y + 40), "SLOW MOTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	var label: String = _clip.label
	var lw := MenuStyle.text_width(label, 22, 0.12) + 40
	MenuStyle.draw_slant(ci, Rect2(x + 420 - lw - 10, y + 62, lw, 34), Color(0.03, 0.04, 0.09, 0.9), 12)
	ci.draw_string(MenuStyle.font(0.12), Vector2(x + 420 - lw + 10, y + 86), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, MenuStyle.ICE)
	# Skip prompt, bottom right.
	var pad := _input.using_pad
	var gl := _input.accept_label()
	var px := w - 60.0 - MenuStyle.text_width("SKIP", 22, 0.12)
	ci.draw_string(MenuStyle.font(0.12), Vector2(px, 860), "SKIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	MenuStyle.draw_glyph(ci, Vector2(px - MenuStyle.glyph_width(gl, pad) - 10, 834), gl, pad, 34.0)


## The stinger: a red slanted band sweeping across, wide enough to cover the screen at
## its middle (where the cut happens), the game's name on it.
func _draw_wipe(ci: Control, w: float, k: float) -> void:
	var bw := w * 1.5
	var cx := lerpf(-bw * 0.6, w + bw * 0.6, ease(k, -1.6))
	var skew := 260.0
	MenuStyle.draw_slant(ci, Rect2(cx - bw * 0.5 - 30, -10, bw + 60, 920), MenuStyle.INK, skew)
	MenuStyle.draw_slant(ci, Rect2(cx - bw * 0.5, -10, bw, 920), MenuStyle.RED, skew)
	MenuStyle.draw_slant(ci, Rect2(cx - bw * 0.5 + bw * 0.42, -10, bw * 0.06, 920), Color(1, 1, 1, 0.85), skew)
	var title := "INSTANT REPLAY"
	var tw := MenuStyle.text_width(title, 84)
	MenuStyle.draw_bold(ci, Vector2(cx - tw * 0.5 + skew * 0.1, 480), title, 84, Color.WHITE, 16, MenuStyle.INK, 0.2, true)
