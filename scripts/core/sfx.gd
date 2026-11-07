extends Node
## Sound effects (autoload "Sfx"). Recorded clips in assets/sound/cut/ (made by
## tools/cut_sounds.py; <name>_<n>.ogg, a random variant per play) take the place of the
## synthesized stand-ins of the same name; the rest are synthesized at startup.
##
##   Sfx.play("boards", at_position, volume_db, pitch)
##   Sfx.crowd_react("cheer", volume_db, priority)   # one crowd reaction at a time
##   Sfx.play_organ("organ_upbeat", volume_db, true) # the arena organ (one at a time)
##   Sfx.announce("bighit", priority)               # play-by-play (assets/sound/announcer/)
##
## Positional sounds get quieter with distance from `listener` (the director keeps it on
## the puck, which is where the camera looks).

const RATE := 22050
const VOICES := 24
const CROWD_DB := -5.0            ## the crowd bed under everything

var listener := Vector3.ZERO
## Prints every announcer line and crowd reaction (set KH_AUDIO_LOG=1 to tune triggers).
var log_events := OS.has_environment("KH_AUDIO_LOG")
var muted := false

const CUT_DIR := "res://assets/sound/cut/"
## Announcer lines: <line><n>.mp3/.ogg/.wav, e.g. faceoff.mp3, faceoff2.mp3 = two takes of "faceoff".
const ANNOUNCER_DIR := "res://assets/sound/announcer/"
const ANNOUNCER_DB := 1.0

var _streams := {}                ## name -> AudioStream or Array of variants
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _crowd: AudioStreamPlayer
var _react: AudioStreamPlayer     ## crowd reactions (cheers, boos, chants)
var _react_priority := 0
var _react_tween: Tween
var _organ: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _voice_priority := 0
var _lines := {}                  ## announcer line -> Array of takes
var _last_take := {}
var _files := {}                  ## announcer file name (no extension) -> stream, for numbered lines like period2
var _voice_queue: Array[AudioStream] = []   ## rest of an announce_chain
var _voice_end := 0.0             ## Time.get_ticks_msec() / 1000 when the announcer last went quiet
var _organ_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build_all()
	_load_recordings()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_crowd = AudioStreamPlayer.new()
	_crowd.stream = _pick("crowd")
	_crowd.volume_db = CROWD_DB
	add_child(_crowd)
	_react = AudioStreamPlayer.new()
	add_child(_react)
	_organ = AudioStreamPlayer.new()
	add_child(_organ)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = ANNOUNCER_DB
	add_child(_voice)
	_voice.finished.connect(_on_voice_finished)
	_load_announcer()
	_rng.randomize()


func has(sound: String) -> bool:
	return _streams.has(sound)


## Plays a sound. `at` = Vector3.INF for non-positional.
func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or not _streams.has(sound):
		return
	var v := volume_db
	if at != Vector3.INF:
		v -= clampf(at.distance_to(listener) * 0.45, 0.0, 18.0)
	if v < -40.0:
		return
	var p := _free_voice()
	p.stream = _pick(sound)
	p.volume_db = v
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


func start_crowd() -> void:
	if not _crowd.playing and not muted:
		_crowd.play()


func stop_crowd() -> void:
	_crowd.stop()
	end_reaction(0.2)
	stop_organ(0.2)
	_voice.stop()


## A crowd reaction (cheer, boo, chant). Only one plays at a time: a new one replaces
## the current one if its priority is at least as high, otherwise it is skipped.
func crowd_react(sound: String, volume_db := 0.0, priority := 1) -> void:
	if muted or not _streams.has(sound):
		return
	if _react.playing and priority < _react_priority:
		return
	if _react_tween:
		_react_tween.kill()
	_react.stream = _pick(sound)
	_react.volume_db = volume_db
	_react.play()
	if log_events:
		print("[audio] %.1f crowd %s" % [Time.get_ticks_msec() / 1000.0, sound])
	_react_priority = priority


func reacting() -> bool:
	return _react.playing


## Fades out the current crowd reaction (if its priority is at most `max_priority`).
func end_reaction(fade := 1.0, max_priority := 99) -> void:
	if not _react.playing or _react_priority > max_priority:
		return
	if _react_tween:
		_react_tween.kill()
	_react_tween = create_tween()
	_react_tween.tween_property(_react, "volume_db", -60.0, fade)
	_react_tween.tween_callback(_react.stop)


## The arena organ: one piece at a time; `anywhere` starts long pieces at a random
## point so stoppages don't always hear the same opening.
func play_organ(sound: String, volume_db := 0.0, anywhere := false) -> void:
	if muted or not _streams.has(sound):
		return
	if _organ_tween:
		_organ_tween.kill()
	_organ.stream = _pick(sound)
	_organ.volume_db = volume_db
	var start := 0.0
	if anywhere:
		start = _rng.randf_range(0.0, maxf(0.0, _organ.stream.get_length() - 8.0))
	_organ.play(start)


func organ_playing() -> bool:
	return _organ.playing


func stop_organ(fade := 1.5) -> void:
	if not _organ.playing:
		return
	if _organ_tween:
		_organ_tween.kill()
	_organ_tween = create_tween()
	_organ_tween.tween_property(_organ, "volume_db", -60.0, fade)
	_organ_tween.tween_callback(_organ.stop)


## Says an announcer line (a random take, not the last one used). One voice: a line
## only cuts off one of lower priority; otherwise it is dropped. Returns whether it plays.
func announce(line: String, priority := 1) -> bool:
	if muted or not _lines.has(line):
		return false
	if _voice.playing and priority <= _voice_priority:
		return false
	_voice_queue.clear()
	var takes: Array = _lines[line]
	var i := _rng.randi() % takes.size()
	if takes.size() > 1 and i == _last_take.get(line, -1):
		i = (i + 1) % takes.size()
	_last_take[line] = i
	_voice.stream = takes[i]
	_voice.play()
	if log_events:
		print("[audio] %.1f announcer %s" % [Time.get_ticks_msec() / 1000.0, line])
	_voice_priority = priority
	return true


func has_line(line: String) -> bool:
	return _lines.has(line)


## Says one exact announcer file (e.g. "period2", where the number is part of the
## line rather than a take number).
func announce_file(name: String, priority := 1) -> bool:
	if muted or not _files.has(name):
		return false
	if _voice.playing and priority <= _voice_priority:
		return false
	_voice_queue.clear()
	_voice.stream = _files[name]
	_voice.play()
	_voice_priority = priority
	if log_events:
		print("[audio] %.1f announcer %s" % [Time.get_ticks_msec() / 1000.0, name])
	return true


func has_file(name: String) -> bool:
	return _files.has(name)


## Plays recorded clips (Sfx sound names, e.g. the intro halves) one after another on
## the announcer's voice, as one line. All must exist.
func announce_chain(sounds: Array, priority := 1) -> bool:
	if muted:
		return false
	for s: String in sounds:
		if not _streams.has(s):
			return false
	if _voice.playing and priority <= _voice_priority:
		return false
	_voice_queue.clear()
	for i in range(1, sounds.size()):
		_voice_queue.append(_pick(sounds[i]))
	_voice.stream = _pick(sounds[0])
	_voice.play()
	_voice_priority = priority
	if log_events:
		print("[audio] %.1f announcer %s" % [Time.get_ticks_msec() / 1000.0, " + ".join(sounds)])
	return true


## Cuts the announcer off (and drops the rest of a chain).
func stop_voice() -> void:
	_voice_queue.clear()
	if _voice.playing:
		_voice.stop()
		_voice_end = Time.get_ticks_msec() / 1000.0


func _on_voice_finished() -> void:
	if not _voice_queue.is_empty():
		_voice.stream = _voice_queue.pop_front()
		_voice.play()
		return
	_voice_end = Time.get_ticks_msec() / 1000.0


## Seconds since the announcer last finished a line (0 while talking).
func announcer_quiet_for() -> float:
	return 0.0 if _voice.playing else Time.get_ticks_msec() / 1000.0 - _voice_end


func announcing() -> bool:
	return _voice.playing


func _load_announcer() -> void:
	if not DirAccess.dir_exists_absolute(ANNOUNCER_DIR):
		return
	for f in ResourceLoader.list_directory(ANNOUNCER_DIR):
		if not (f.ends_with(".mp3") or f.ends_with(".ogg") or f.ends_with(".wav")):
			continue
		var stream := load(ANNOUNCER_DIR + f) as AudioStream
		if stream == null:
			continue
		_files[f.get_basename().to_lower()] = stream
		# Trailing digits mark another take of the same line.
		var line := f.get_basename().to_lower()
		while line.length() > 1 and line.right(1).is_valid_int():
			line = line.left(-1)
		line = line.trim_suffix("_")
		if not _lines.has(line):
			_lines[line] = []
		_lines[line].append(stream)


func _pick(sound: String) -> AudioStream:
	var s = _streams[sound]
	if s is Array:
		return s[_rng.randi() % (s as Array).size()]
	return s


## Recorded clips replace synthesized sounds of the same name ("crowd" loops).
func _load_recordings() -> void:
	if not DirAccess.dir_exists_absolute(CUT_DIR):
		return
	var found := {}
	for f in ResourceLoader.list_directory(CUT_DIR):
		if not f.ends_with(".ogg"):
			continue
		var name := f.get_basename()
		var cut := name.rfind("_")
		if cut > 0 and name.substr(cut + 1).is_valid_int():
			name = name.substr(0, cut)
		var stream := load(CUT_DIR + f) as AudioStream
		if stream == null:
			continue
		if name == "crowd" and stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		if not found.has(name):
			found[name] = []
		found[name].append(stream)
	for name: String in found:
		_streams[name] = found[name]


func _free_voice() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _voices[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	return p


# --- Synthesis -------------------------------------------------------------------

func _build_all() -> void:
	_streams["click"] = _wav(_click(0.07, 1700.0, 0.55))
	_streams["shot_wrist"] = _wav(_shot(0.16, 0.7, 30.0))
	_streams["shot_slap"] = _wav(_shot(0.3, 1.0, 18.0))
	_streams["boards"] = _wav(_thud(0.5, 70.0, 0.08, 0.6, 22.0))
	_streams["glass"] = _wav(_glass())
	_streams["post"] = _wav(_ping())
	_streams["body"] = _wav(_thud(0.3, 58.0, 0.05, 0.4, 0.0))
	_streams["big_hit"] = _wav(_thud(0.6, 48.0, 0.12, 0.9, 30.0))
	_streams["pad"] = _wav(_thud(0.18, 140.0, 0.18, 0.5, 0.0))
	_streams["glove"] = _wav(_click(0.12, 320.0, 0.8))
	_streams["net"] = _wav(_noise_burst(0.35, 0.25, 0.02, 0.25, 0.4))
	_streams["carve"] = _wav(_noise_burst(0.42, 0.45, 0.03, 0.55, 0.6))
	_streams["stride"] = _wav(_noise_burst(0.16, 0.5, 0.02, 0.6, 0.3))
	_streams["whistle"] = _wav(_whistle())
	_streams["horn"] = _wav(_horn())
	_streams["crowd"] = _wav(_crowd_loop(6.0, 0.05, 0.22), true)
	_streams["cheer"] = _wav(_cheer(3.6))
	_streams["ooh"] = _wav(_ooh(1.3))


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


func _n() -> float:
	return _rng.randf_range(-1.0, 1.0)


## Stick on puck: a bright tick with a short resonance.
func _click(dur: float, tone: float, amp: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _n()
		lp += 0.4 * (x - lp)
		s[i] = amp * ((x - lp) * exp(-t * 110.0) + 0.6 * sin(TAU * tone * t) * exp(-t * 55.0))
	return s


## Shot: a crack plus a woody thump.
func _shot(dur: float, amp: float, decay: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _n()
		lp += 0.25 * (x - lp)
		var crack := x * exp(-t * 70.0)
		var wood := sin(TAU * 820.0 * t) * exp(-t * 45.0) * 0.4
		var thump := sin(TAU * 130.0 * t) * exp(-t * decay) * 0.6
		s[i] = amp * (crack * 0.8 + lp * exp(-t * decay) * 0.5 + wood + thump)
	return s


## Low thump with an optional rattle (boards / bodies / pads).
func _thud(dur: float, freq: float, noise_lp: float, noise_amp: float, rattle_hz: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += noise_lp * (_n() - lp)
		var body := sin(TAU * freq * t) * exp(-t * 9.0) + 0.5 * sin(TAU * freq * 1.6 * t) * exp(-t * 14.0)
		var rattle := 1.0 if rattle_hz <= 0.0 else 0.55 + 0.45 * sin(TAU * rattle_hz * t)
		s[i] = 0.75 * (body * minf(1.0, t * 400.0) + lp * 3.0 * noise_amp * exp(-t * 12.0) * rattle)
	return s


func _glass() -> PackedFloat32Array:
	var s := _thud(0.55, 85.0, 0.25, 0.55, 26.0)
	for i in s.size():
		var t := float(i) / RATE
		s[i] += 0.18 * (sin(TAU * 430.0 * t) + 0.6 * sin(TAU * 1110.0 * t)) * exp(-t * 12.0)
	return s


## Puck off the post: a bright metallic ring.
func _ping() -> PackedFloat32Array:
	var s := _buf(1.0)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = 0.5 * (sin(TAU * 1250.0 * t) * exp(-t * 5.0)
				+ 0.5 * sin(TAU * 3170.0 * t) * exp(-t * 8.0)
				+ 0.25 * sin(TAU * 5230.0 * t) * exp(-t * 13.0)
				+ _n() * exp(-t * 120.0))
	return s


## Filtered noise with attack/decay (ice spray, net swish).
func _noise_burst(dur: float, lp_a: float, attack: float, hp_mix: float, amp: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _n()
		lp += lp_a * (x - lp)
		lp2 += 0.05 * (lp - lp2)
		var y := lerpf(lp, lp - lp2, hp_mix)
		var env := minf(1.0, t / attack) * pow(1.0 - t / dur, 1.6)
		s[i] = amp * 1.6 * y * env
	return s


## Referee's pea whistle: a trilling high tone.
func _whistle() -> PackedFloat32Array:
	var dur := 0.75
	var s := _buf(dur)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 2850.0 + 140.0 * sin(TAU * 31.0 * t)
		phase += TAU * f / RATE
		var env := minf(1.0, t / 0.02) * clampf((dur - t) / 0.12, 0.0, 1.0)
		var trill := 0.75 + 0.25 * sin(TAU * 31.0 * t)
		s[i] = 0.32 * env * trill * (sin(phase) + 0.15 * sin(2.0 * phase)) + 0.03 * _n() * env
	return s


## Arena goal horn: a big brassy chord.
func _horn() -> PackedFloat32Array:
	var dur := 2.8
	var s := _buf(dur)
	var freqs := [138.6, 174.6, 207.7]
	var phases := [0.0, 0.0, 0.0]
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.06) * clampf((dur - t) / 0.35, 0.0, 1.0)
		var v := 0.0
		for k in 3:
			phases[k] += TAU * freqs[k] * (1.0 + 0.003 * sin(TAU * 5.0 * t + k)) / RATE
			for h in range(1, 8):
				v += sin(phases[k] * h) / float(h)
		s[i] = 0.16 * env * tanh(v * 0.9)
	return s


## Arena murmur, seamlessly looping.
func _crowd_loop(dur: float, lp_a: float, amp: float) -> PackedFloat32Array:
	var fade := int(0.5 * RATE)
	var raw := _buf(dur + 0.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		lp += lp_a * (_n() - lp)
		lp2 += 0.01 * (lp - lp2)
		var swell := 0.75 + 0.15 * sin(TAU * 0.23 * t) + 0.1 * sin(TAU * 0.61 * t + 1.0)
		raw[i] = amp * 4.0 * (lp - lp2) * swell
	var s := _buf(dur)
	for i in s.size():
		s[i] = raw[i]
		if i < fade:
			var w := float(i) / fade
			s[i] = raw[i] * w + raw[i + s.size()] * (1.0 - w)
	return s


## Goal: the crowd erupts, with scattered "whoo" voices.
func _cheer(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var voices := []
	for k in 9:
		voices.append({"f": _rng.randf_range(380.0, 760.0), "start": _rng.randf_range(0.0, 1.2),
				"len": _rng.randf_range(0.8, 1.8), "ph": 0.0, "vib": _rng.randf_range(4.0, 7.0)})
	for i in s.size():
		var t := float(i) / RATE
		lp += 0.18 * (_n() - lp)
		lp2 += 0.01 * (lp - lp2)
		var env := minf(1.0, t / 0.35) * clampf((dur - t) / 1.6, 0.0, 1.0)
		var v := (lp - lp2) * 2.6
		for vo: Dictionary in voices:
			var lt: float = t - vo.start
			if lt > 0.0 and lt < vo.len:
				vo.ph += TAU * vo.f * (1.0 + 0.25 * lt + 0.02 * sin(TAU * vo.vib * lt)) / RATE
				v += 0.05 * sin(vo.ph) * sin(PI * lt / vo.len)
		s[i] = 0.55 * env * v
	return s


## Big hit: the crowd goes "ooh".
func _ooh(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var ph := [0.0, 0.0, 0.0]
	var fs := [210.0, 260.0, 315.0]
	for i in s.size():
		var t := float(i) / RATE
		lp += 0.08 * (_n() - lp)
		lp2 += 0.01 * (lp - lp2)
		var env := sin(PI * minf(t / dur, 1.0)) * minf(1.0, t / 0.15)
		var v := (lp - lp2) * 2.2
		for k in 3:
			ph[k] += TAU * fs[k] * (1.0 - 0.12 * t) / RATE
			v += 0.08 * sin(ph[k])
		s[i] = 0.5 * env * v
	return s
