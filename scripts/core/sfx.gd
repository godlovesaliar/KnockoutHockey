extends Node
## Sound effects (autoload "Sfx"). Recorded clips in assets/sound/cut/ (made by
## tools/cut_sounds.py; <name>_<n>.ogg, a random variant per play) take the place of the
## synthesized stand-ins of the same name; the rest are synthesized at startup.
##
##   Sfx.play("boards", at_position, volume_db, pitch)
##   Sfx.crowd_react("cheer", volume_db, priority)   # one crowd reaction at a time
##   Sfx.play_organ("organ_upbeat", volume_db, true) # the arena organ (one at a time)
##   Sfx.announce("bighit", priority)               # play-by-play (assets/sound/announcer/)
##   Sfx.pa_chain(["pa_goal_whalers", "pa_scored_by", "pa_n17_big"])   # the arena PA
##   Sfx.play_music() / Sfx.stop_music(fade)        # the menu playlist (assets/sound/music/)
##   Sfx.play_theme() / Sfx.theme_time() / Sfx.theme_to_bed() / Sfx.stop_theme(fade)   # the broadcast theme
##
## Positional sounds get quieter with distance from `listener` (the director keeps it on
## the puck, which is where the camera looks).

const RATE := 22050
const VOICES := 24
## Background sounds that come in floods (every skater strides several times a second): each
## has its own small budget of channels, reusing its oldest one, and they're the first to give
## a channel up, so they never cut off a horn, a hit or a crowd sting.
const BED_CAP := {"stride": 6, "carve": 3}
const CROWD_DB := -5.0            ## the crowd bed under everything
## dB on the crowd (bed and reactions) for the building and how full it is (Arena sets it:
## a half-full community rink is quieter than a sold-out arena).
var venue_db := 0.0
## A bed of outdoor sound under the crowd (set_ambience: "wind" at an outdoor rink), playing
## whenever the crowd does.
var _ambience: AudioStreamPlayer
var _ambience_kind := ""

## A crowd reaction started (the arena's fans stand and cheer with it).
signal crowd_reacted(sound: String)

var listener := Vector3.ZERO
## Prints every announcer line and crowd reaction (set KH_AUDIO_LOG=1 to tune triggers).
var log_events := OS.has_environment("KH_AUDIO_LOG")
var muted := false

const CUT_DIR := "res://assets/sound/cut/"
## Announcer lines: <line><n>.mp3/.ogg/.wav, e.g. faceoff.mp3, faceoff2.mp3 = two takes of "faceoff".
const ANNOUNCER_DIR := "res://assets/sound/announcer/"
const ANNOUNCER_DB := 1.0
## Menu music: every track in this folder, shuffled, one after another.
const MUSIC_DIR := "res://assets/sound/music/"
const MUSIC_DB := -10.0
## The TV package (made by tools/build_theme.py): the broadcast theme and the graphics'
## sounds (tv_whoosh, tv_slam, tv_clash, tv_sting), loaded like the cut recordings.
const TV_DIR := "res://assets/sound/tv/"
const THEME_PATH := TV_DIR + "theme.ogg"
## The theme's clock (build_theme.py's numbers): a two-beat pickup, eight bars of fanfare
## (the broadcast open is cut to them, see theme_bar), then an eight-bar bed that loops.
const THEME_BEAT := 60.0 / 130.0
const THEME_BAR := THEME_BEAT * 4.0
const THEME_PICKUP := THEME_BEAT * 2.0
const THEME_BED_BAR := 9          ## the bed's first bar: the loop point
const THEME_DB := -7.0            ## the fanfare, up front
const THEME_BED_DB := -20.0       ## the bed, under the booth's welcome
## The arena PA: its own voice, through the building's speakers (the "PA" bus: a touch of
## filtering, a faint echo and room, light because the voice has its own reverb), on the crowd's volume. It dips
## under the booth so Steve and Bobby stay on top, the way a broadcast hears it.
const PA_DB := -3.0
const PA_DUCK := 9.0              ## dB the PA drops while the booth talks
const PA_GAP := 0.3               ## seconds between the pieces of a PA call
const PA_BREAK := 1.0             ## seconds between one PA call and a call that waited for it
const PA_HOLD := 15.0             ## a waiting PA call is dropped if it can't start within this
## The booth doesn't talk over itself. A line that outranks the one playing waits for it
## to end when it ends soon enough (VOICE_WAIT seconds, more for big calls); only lines of
## CUT_IN priority (goals, knockouts) cut a longer one off, and then with a quick fade.
const CUT_IN := 4
const VOICE_WAIT := 1.2
const VOICE_WAIT_BIG := 3.0       ## priority 3 calls: breakaways, injuries, period calls
const CUT_FADE := 0.25

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
var _voice_speaker := ""          ## who's talking: "pbp", "color", "both" ("" = a chain or unknown)
var _stream_voice := {}           ## announcer take -> the voice that recorded it
## Routine calls (this priority and below) never cut off Bobby or a duet once one has the
## mic: Steve's play-by-play waits its turn unless it's a goal, penalty, period call etc.
const PROTECT_COLOR := 2
var _lines := {}                  ## announcer line -> Array of takes
var _last_take := {}
var _voice_takes := {}            ## voice -> announcer line -> that voice's takes
var _files := {}                ## announcer file name (no extension) -> stream, for numbered lines like period2
var _voice_queue: Array[AudioStream] = []   ## rest of an announce_chain
var _voice_end := 0.0             ## Time.get_ticks_msec() / 1000 when the announcer last went quiet
var _voice_tail: AudioStreamPlayer   ## the line a goal call cut off, fading out under it
var _tail_tween: Tween
var _cut_speaker := ""            ## who a goal call just cut off (for the log)
var _next_line := Callable()      ## a line waiting for the current one to end
var _next_priority := 0
var _next_until := 0.0
var _organ_tween: Tween
var _music: AudioStreamPlayer
var _music_tween: Tween
var _music_on := false
var _theme: AudioStreamPlayer
var _theme_tween: Tween
var _playlist: Array[String] = []
var _last_track := ""
var _rng := RandomNumberGenerator.new()
var _pa: AudioStreamPlayer
var _pa_lines := {}               ## PA line -> Array of takes
var _pa_last := {}
var _pa_queue: Array[AudioStream] = []
var _pa_priority := 0
var _pa_gen := 0                  ## bumped by every new call, so a stale gap timer does nothing
var _pa_wait := false             ## between two pieces of a call
var _voice_kind := {}             ## effects channel -> the sound it last played
var _voice_start := {}            ## effects channel -> when (ms)
var _pa_next: Array = []          ## a call waiting for the current one to end
var _pa_next_priority := 0
var _pa_next_until := 0.0


func _ready() -> void:
	_rng.seed = 7
	_build_all()
	_load_recordings()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_voices.append(p)
	_crowd = AudioStreamPlayer.new()
	_crowd.stream = _pick("crowd")
	_crowd.volume_db = CROWD_DB
	_crowd.bus = "Crowd"
	add_child(_crowd)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Effects"
	add_child(_ambience)
	_react = AudioStreamPlayer.new()
	_react.bus = "Crowd"
	add_child(_react)
	_organ = AudioStreamPlayer.new()
	_organ.bus = "Crowd"
	add_child(_organ)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = ANNOUNCER_DB
	_voice.bus = "Announcer"
	add_child(_voice)
	_voice.finished.connect(_on_voice_finished)
	_voice_tail = AudioStreamPlayer.new()
	_voice_tail.bus = "Announcer"
	add_child(_voice_tail)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(func() -> void:
		if _music_on:
			_next_track())
	_theme = AudioStreamPlayer.new()
	_theme.bus = "Music"
	add_child(_theme)
	_pa = AudioStreamPlayer.new()
	_pa.bus = _pa_bus()
	_pa.volume_db = PA_DB
	add_child(_pa)
	_pa.finished.connect(_on_pa_finished)
	_load_announcer()
	_rng.randomize()


func _process(delta: float) -> void:
	var target := PA_DB - (PA_DUCK if _voice.playing else 0.0)
	_pa.volume_db = move_toward(_pa.volume_db, target, delta * (40.0 if target < _pa.volume_db else 12.0))


## The "PA" bus: arena speakers (no lows, no sparkle), an echo off the far end, a big room.
func _pa_bus() -> String:
	if AudioServer.get_bus_index("PA") >= 0:
		return "PA"
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, "PA")
	AudioServer.set_bus_send(i, "Crowd" if AudioServer.get_bus_index("Crowd") >= 0 else "Master")
	# Kept light: the PA voice was generated with its own arena sound (reverb and all), so
	# this only sets it a little further back in the building than the booth.
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 150.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 9000.0
	var echo := AudioEffectDelay.new()
	echo.dry = 1.0
	echo.tap1_active = true
	echo.tap1_delay_ms = 180.0
	echo.tap1_level_db = -24.0
	echo.tap2_active = false
	echo.feedback_active = false
	var room := AudioEffectReverb.new()
	room.room_size = 0.6
	room.damping = 0.5
	room.predelay_msec = 40.0
	room.wet = 0.08
	room.dry = 1.0
	room.spread = 0.6
	for fx: AudioEffect in [hp, lp, echo, room]:
		AudioServer.add_bus_effect(i, fx)
	return "PA"


func has(sound: String) -> bool:
	return _streams.has(sound)


## The stream behind `sound` (null: there is none, or sound is off), for a player that lives
## outside Sfx (the resurfacer's engine loop).
func stream_of(sound: String) -> AudioStream:
	return _pick(sound) if _streams.has(sound) and not muted else null


## Plays a sound. `at` = Vector3.INF for non-positional.
func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or not _streams.has(sound):
		return
	var v := volume_db
	if at != Vector3.INF:
		v -= clampf(at.distance_to(listener) * 0.45, 0.0, 18.0)
	if v < -40.0:
		return
	var p := _bed_voice(sound) if BED_CAP.has(sound) else _free_voice()
	if p == null:
		return
	_voice_kind[p] = sound
	_voice_start[p] = Time.get_ticks_msec()
	p.stream = _pick(sound)
	p.volume_db = v
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


func set_venue(db: float) -> void:
	venue_db = db
	_crowd.volume_db = CROWD_DB + db


func start_crowd() -> void:
	if not _crowd.playing and not muted:
		_crowd.play()
	if _ambience_kind != "" and not _ambience.playing and not muted:
		_ambience.play()


## The ambience bed: `kind` "wind" (synthesized at first use, or a recorded wind_<n>.ogg in
## CUT_DIR), "" for none. Plays with the crowd (start_crowd / stop_crowd).
func set_ambience(kind: String, volume_db := 0.0) -> void:
	if kind == "":
		_ambience_kind = ""
		_ambience.stop()
		return
	if kind == "wind" and not _streams.has("wind"):
		_streams["wind"] = _wav(_wind_loop(10.0, 0.5), true)
	if not _streams.has(kind):
		return
	if kind != _ambience_kind:
		_ambience.stop()
		_ambience.stream = _pick(kind)
	_ambience_kind = kind
	_ambience.volume_db = volume_db
	if _crowd.playing and not _ambience.playing and not muted:
		_ambience.play()


func stop_crowd() -> void:
	stop_theme(0.3)
	_crowd.stop()
	_ambience.stop()
	end_reaction(0.2)
	stop_organ(0.2)
	stop_voice()
	stop_pa()


## A crowd reaction (cheer, boo, chant). Only one plays at a time: a new one replaces
## the current one if its priority is at least as high, otherwise it is skipped.
func crowd_react(sound: String, volume_db := 0.0, priority := 1) -> void:
	if muted or not _streams.has(sound):
		return
	if _react.playing and priority < _react_priority:
		return
	crowd_reacted.emit(sound)
	if _react_tween:
		_react_tween.kill()
	_react.stream = _pick(sound)
	_react.volume_db = volume_db + venue_db
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


## Starts the menu music (or keeps it going: moving between menu screens doesn't
## restart the track). Tracks play shuffled, never the same one twice in a row.
func play_music() -> void:
	stop_theme(0.3)
	if muted:
		return
	if _music_tween:
		_music_tween.kill()
		_music_tween = null
	if _music_on and _music.playing:
		_music.volume_db = MUSIC_DB   # cancel a fade-out that was under way
		return
	_music_on = true
	_next_track()


## Fades the menu music out (the game is starting).
func stop_music(fade := 1.0) -> void:
	_music_on = false
	if not _music.playing:
		return
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -60.0, fade)
	_music_tween.tween_callback(_music.stop)


func _next_track() -> void:
	if _playlist.is_empty():
		for f in ResourceLoader.list_directory(MUSIC_DIR):
			if f.get_extension() in ["mp3", "ogg", "wav"]:
				_playlist.append(MUSIC_DIR + f)
		_playlist.shuffle()
		if _playlist.size() > 1 and _playlist[0] == _last_track:
			_playlist.append(_playlist.pop_front())
	if _playlist.is_empty():
		return
	_last_track = _playlist.pop_front()
	var stream := load(_last_track) as AudioStream
	if stream == null:
		return
	_music.stream = stream
	if log_events:
		print("[music] ", _last_track.get_file(), "  %.0fs" % stream.get_length())
	_music.volume_db = -30.0
	_music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", MUSIC_DB, 1.5)


# --- The broadcast theme ---------------------------------------------------------

## Seconds into the theme where bar `n` starts (bar 1 is the first hit, after the pickup).
func theme_bar(n: float) -> float:
	return THEME_PICKUP + (n - 1.0) * THEME_BAR


## Starts the broadcast theme `from` seconds in (0: the pickup into bar 1). It plays the
## fanfare once, then loops its bed until stop_theme. False if there's no theme to play
## (sound is off, or the file is missing): the open then runs on its own clock.
func play_theme(from := 0.0) -> bool:
	if muted:
		return false
	var stream := _theme_stream()
	if stream == null:
		return false
	stream.loop = true
	stream.loop_offset = theme_bar(THEME_BED_BAR)
	if _theme_tween:
		_theme_tween.kill()
		_theme_tween = null
	_theme.stream = stream
	_theme.volume_db = THEME_DB
	_theme.play(from)
	if log_events:
		print("[music] theme from %.2fs" % from)
	return true


## The theme's stream. `-- theme=<name>` plays assets/sound/tv/options/theme_<name>.ogg in
## its place for a run (build_theme.py's `options`: themes to compare before one is picked).
func _theme_stream() -> AudioStreamOggVorbis:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("theme="):
			var path := TV_DIR + "options/theme_%s.ogg" % a.substr(6)
			if FileAccess.file_exists(path):
				return AudioStreamOggVorbis.load_from_file(path)
	return load(THEME_PATH) as AudioStreamOggVorbis if ResourceLoader.exists(THEME_PATH) else null


func theme_playing() -> bool:
	return _theme.playing


## Where the theme is right now, in seconds (what's coming out of the speakers, so pictures
## cut to it land on the beat); -1 when it isn't playing.
func theme_time() -> float:
	if not _theme.playing:
		return -1.0
	return _theme.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


## Moves the theme to `db` over `fade` seconds.
func theme_level(db: float, fade := 0.4) -> void:
	if not _theme.playing:
		return
	if _theme_tween:
		_theme_tween.kill()
	_theme_tween = create_tween()
	_theme_tween.tween_property(_theme, "volume_db", db, fade)


## The open is over: on to the bed, quietly, under the booth. A theme still in its fanfare
## (the open was skipped) jumps to the bed's first bar.
func theme_to_bed() -> void:
	if not _theme.playing:
		return
	var bed := theme_bar(THEME_BED_BAR)
	if _theme.get_playback_position() < bed - 0.3:
		_theme.seek(bed)
		_theme.volume_db = THEME_BED_DB - 8.0
	theme_level(THEME_BED_DB, 0.6)


func stop_theme(fade := 2.0) -> void:
	if not _theme.playing:
		return
	if _theme_tween:
		_theme_tween.kill()
	_theme_tween = create_tween()
	_theme_tween.tween_property(_theme, "volume_db", -60.0, fade)
	_theme_tween.tween_callback(_theme.stop)


## Says an announcer line (a random take, not the last one used). One voice, which doesn't
## talk over itself (_voice_admit): a line that outranks the one playing waits for it when
## it ends soon, a goal call fades a longer one out, anything else is dropped. Returns
## whether it plays (now or once the current line ends).
func announce(line: String, priority := 1) -> bool:
	if muted or not _lines.has(line):
		return false
	match _voice_admit(priority, func() -> void: announce(line, priority), line):
		Admit.NO:
			return false
		Admit.LATER:
			return true
	_voice_queue.clear()
	var takes: Array = _lines[line]
	var i := _rng.randi() % takes.size()
	if takes.size() > 1 and i == _last_take.get(line, -1):
		i = (i + 1) % takes.size()
	_last_take[line] = i
	var cut := _cut_speaker
	_cut_speaker = ""
	_voice.stream = takes[i]
	_voice_speaker = _stream_voice.get(takes[i], "")
	_voice.play()
	if log_events:
		print("[audio] %.1f announcer %s [%s]%s" % [Time.get_ticks_msec() / 1000.0, line, _voice_speaker,
				" (cut off %s)" % cut if cut != "" else ""])
	_voice_priority = priority
	return true


## True when the announcer is mid-line and a line of `priority` may not cut in: it has to
## outrank what's playing, and Bobby's lines and duets are held to at least PROTECT_COLOR.
func _voice_blocks(priority: int) -> bool:
	if not _voice.playing:
		return false
	var held := _voice_priority
	if _voice_speaker == "color" or _voice_speaker == "both":
		held = maxi(held, PROTECT_COLOR)
	return priority <= held


enum Admit { NOW, LATER, NO }

## Whether a line of `priority` may play: NOW (the booth is free, or a goal cuts in with a
## fade), LATER (it outranks the line playing, which ends soon: `retry` runs when it does)
## or NO (dropped).
func _voice_admit(priority: int, retry: Callable, what: String) -> Admit:
	if not announcing():
		return Admit.NOW
	if _voice_blocks(priority):
		return Admit.NO
	var left := _voice_left()
	var wait := VOICE_WAIT_BIG if priority >= 3 else VOICE_WAIT
	if left <= wait:
		if _next_line.is_valid() and priority <= _next_priority:
			return Admit.NO
		_next_line = retry
		_next_priority = priority
		_next_until = Time.get_ticks_msec() / 1000.0 + left + 0.5
		if log_events:
			print("[audio] %.1f announcer %s waits %.1fs" % [Time.get_ticks_msec() / 1000.0, what, left])
		return Admit.LATER
	if priority >= CUT_IN:
		_fade_out_voice()
		return Admit.NOW
	return Admit.NO


## Seconds left of what the booth is saying (the rest of a chain included).
func _voice_left() -> float:
	var left := 0.0
	if _voice.playing and _voice.stream:
		left = _voice.stream.get_length() - _voice.get_playback_position()
	for s in _voice_queue:
		left += s.get_length()
	return left


## Hands the line playing to the tail player to fade out under the new one.
func _fade_out_voice() -> void:
	_voice_queue.clear()
	_next_line = Callable()
	if not _voice.playing:
		return
	if _tail_tween:
		_tail_tween.kill()
	_cut_speaker = _voice_speaker if _voice_speaker != "" else "chain"
	_voice_tail.stream = _voice.stream
	_voice_tail.volume_db = _voice.volume_db
	_voice_tail.play(_voice.get_playback_position())
	_voice.stop()
	_tail_tween = create_tween()
	_tail_tween.tween_property(_voice_tail, "volume_db", -40.0, CUT_FADE)
	_tail_tween.tween_callback(_voice_tail.stop)


## Says `line` after `delay` seconds, first waiting up to `wait` s for the announcer to
## finish (so Bobby answers Steve instead of being dropped). For code without MatchAudio's
## helpers: fights and Knockout Mode.
func announce_after(line: String, delay: float, priority := 1, wait := 3.0) -> void:
	if not _lines.has(line):
		if log_events:
			print("[audio] %.1f announcer %s (not recorded)" % [Time.get_ticks_msec() / 1000.0 + delay, line])
		return
	await get_tree().create_timer(delay).timeout
	var waited := 0.0
	while announcing() and waited < wait:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	announce(line, priority)


func has_line(line: String) -> bool:
	return _lines.has(line)


## Says one exact announcer file (e.g. "period2", where the number is part of the
## line rather than a take number).
func announce_file(name: String, priority := 1) -> bool:
	if muted or not _files.has(name):
		return false
	match _voice_admit(priority, func() -> void: announce_file(name, priority), name):
		Admit.NO:
			return false
		Admit.LATER:
			return true
	_voice_queue.clear()
	_voice.stream = _files[name]
	_voice_speaker = _stream_voice.get(_files[name], "")
	_voice.play()
	_voice_priority = priority
	if log_events:
		print("[audio] %.1f announcer %s" % [Time.get_ticks_msec() / 1000.0, name])
	return true


func has_file(name: String) -> bool:
	return _files.has(name)


## Plays recorded clips (Sfx sound names, e.g. the intro halves, or announcer line names
## prefixed "line:") one after another on the announcer's voice, as one line. All must exist.
func announce_chain(sounds: Array, priority := 1) -> bool:
	if muted:
		return false
	for s: String in sounds:
		if not (_streams.has(s) or (s.begins_with("line:") and _lines.has(s.substr(5)))):
			return false
	match _voice_admit(priority, func() -> void: announce_chain(sounds, priority), " + ".join(sounds)):
		Admit.NO:
			return false
		Admit.LATER:
			return true
	_voice_queue.clear()
	_voice_speaker = ""
	for i in range(1, sounds.size()):
		_voice_queue.append(_chain_stream(sounds[i]))
	_voice.stream = _chain_stream(sounds[0])
	_voice.play()
	_voice_priority = priority
	if log_events:
		print("[audio] %.1f announcer %s" % [Time.get_ticks_msec() / 1000.0, " + ".join(sounds)])
	return true


func _chain_stream(s: String) -> AudioStream:
	if s.begins_with("line:"):
		var takes: Array = _lines[s.substr(5)]
		return takes[_rng.randi() % takes.size()]
	return _pick(s)


## How many takes an announcer line has (0 = none recorded).
func take_count(line: String) -> int:
	return (_lines.get(line, []) as Array).size()


## Cuts the announcer off (and drops the rest of a chain).
func stop_voice() -> void:
	_voice_queue.clear()
	_next_line = Callable()
	_voice_tail.stop()
	if _voice.playing:
		_voice.stop()
		_voice_end = Time.get_ticks_msec() / 1000.0


func _on_voice_finished() -> void:
	if not _voice_queue.is_empty():
		_voice.stream = _voice_queue.pop_front()
		_voice.play()
		if log_events:
			print("[audio] %.1f announcer chain: next part (%.2fs)" % [Time.get_ticks_msec() / 1000.0, _voice.stream.get_length()])
		return
	if log_events:
		print("[audio] %.1f announcer done" % (Time.get_ticks_msec() / 1000.0))
	_voice_end = Time.get_ticks_msec() / 1000.0
	if _next_line.is_valid():
		var next := _next_line
		_next_line = Callable()
		if _voice_end <= _next_until:
			next.call()


## Seconds since the announcer last finished a line (0 while talking).
func announcer_quiet_for() -> float:
	return 0.0 if _voice.playing else Time.get_ticks_msec() / 1000.0 - _voice_end


## True while a line or chain is playing, including the instant between a chain's parts
## (the player has stopped but `finished` hasn't queued the next part yet). Without
## that, something waiting on the booth (the broadcast open, before it closes) could act
## between the halves and the welcome would cut the away half.
func announcing() -> bool:
	return _voice.playing or not _voice_queue.is_empty()


## The booth's recordings (AnnouncerLines.VOICES: announcer/pbp/, announcer/color/,
## announcer/both/ for duets, and the original files in announcer/ itself). A line's
## takes from every booth voice share one pool: a new voice adds to it, never replaces it.
## The PA's (announcer/pa/) are kept apart: they play on the PA, never in the booth.
func _load_announcer() -> void:
	var dirs := [[ANNOUNCER_DIR, AnnouncerLines.LEGACY_VOICE]]
	for v: String in AnnouncerLines.VOICES:
		dirs.append([ANNOUNCER_DIR + AnnouncerLines.VOICES[v].dir, v])
	for d: Array in dirs:
		var dir: String = d[0]
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var by_line: Dictionary = _voice_takes.get_or_add(d[1], {})
		for f in ResourceLoader.list_directory(dir):
			if not (f.ends_with(".mp3") or f.ends_with(".ogg") or f.ends_with(".wav")):
				continue
			var stream := load(dir + f) as AudioStream
			if stream == null:
				continue
			_files[f.get_basename().to_lower()] = stream
			_stream_voice[stream] = d[1]
			# Trailing digits mark another take; other names join their line's takes
			# (AnnouncerLines: the CSV's names, older recordings).
			var line := AnnouncerLines.line_for_file(f.get_basename())
			by_line.get_or_add(line, []).append(stream)
	# Every voice's takes of a line share one pool (Steve's, Bobby's and duets alike).
	for v: String in _voice_takes:
		for line: String in _voice_takes[v]:
			var pool: Dictionary = _pa_lines if v == "pa" else _lines
			pool.get_or_add(line, []).append_array(_voice_takes[v][line])


# --- The arena PA ----------------------------------------------------------------

func has_pa(line: String) -> bool:
	return _pa_lines.has(line)


## A PA call: its pieces one after another with a short breath between (a random take of
## each, not the last one used), e.g. ["pa_goal_whalers", "pa_scored_by", "pa_n17_big"].
## Pieces that aren't recorded are left out; nothing plays if none are. One call at a time,
## and the PA never cuts itself off: a call made while one is playing waits for it to end
## (one waiting call, the more important one; dropped after PA_HOLD s). Returns whether it
## plays or waits.
func pa_chain(lines: Array, priority := 1) -> bool:
	if muted:
		return false
	var have := lines.filter(func(l: String) -> bool: return _pa_lines.has(l))
	if log_events and have.size() < lines.size():
		var missing := lines.filter(func(l: String) -> bool: return not _pa_lines.has(l))
		print("[audio] %.1f PA %s (not recorded: %s)" % [Time.get_ticks_msec() / 1000.0, " + ".join(lines), ", ".join(missing)])
	if have.is_empty():
		return false
	if pa_playing():
		if not _pa_next.is_empty() and priority <= _pa_next_priority:
			return false
		_pa_next = have
		_pa_next_priority = priority
		_pa_next_until = Time.get_ticks_msec() / 1000.0 + PA_HOLD
		if log_events:
			print("[audio] %.1f PA %s waits" % [Time.get_ticks_msec() / 1000.0, " + ".join(have)])
		return true
	_pa_gen += 1
	_pa_wait = false
	_pa_queue.clear()
	for l: String in have:
		var takes: Array = _pa_lines[l]
		var i := _rng.randi() % takes.size()
		if takes.size() > 1 and i == _pa_last.get(l, -1):
			i = (i + 1) % takes.size()
		_pa_last[l] = i
		_pa_queue.append(takes[i])
	_pa.stream = _pa_queue.pop_front()
	_pa.play()
	_pa_priority = priority
	if log_events and have.size() == lines.size():
		print("[audio] %.1f PA %s" % [Time.get_ticks_msec() / 1000.0, " + ".join(have)])
	return true


func pa(line: String, priority := 1) -> bool:
	return pa_chain([line], priority)


func pa_playing() -> bool:
	return _pa.playing or _pa_wait or not _pa_queue.is_empty()


func stop_pa() -> void:
	_pa_gen += 1
	_pa_wait = false
	_pa_queue.clear()
	_pa_next = []
	_pa.stop()


## Next piece of the call after a breath, or once the call is done, the call that waited.
func _on_pa_finished() -> void:
	if _pa_queue.is_empty() and _pa_next.is_empty():
		return
	var gen := _pa_gen
	_pa_wait = true
	await get_tree().create_timer(PA_GAP if not _pa_queue.is_empty() else PA_BREAK).timeout
	if gen != _pa_gen:
		return
	_pa_wait = false
	if not _pa_queue.is_empty():
		_pa.stream = _pa_queue.pop_front()
		_pa.play()
		return
	var next := _pa_next
	_pa_next = []
	if not next.is_empty() and Time.get_ticks_msec() / 1000.0 <= _pa_next_until:
		pa_chain(next, _pa_next_priority)


## Takes of a line in one voice's own recordings ("pbp" / "color" / "both" / "pa").
func voice_take_count(line: String, voice: String) -> int:
	return (_voice_takes.get(voice, {}).get(line, []) as Array).size()


func _pick(sound: String) -> AudioStream:
	var s = _streams[sound]
	if s is Array:
		return s[_rng.randi() % (s as Array).size()]
	return s


## Recorded clips replace synthesized sounds of the same name ("crowd" loops); the TV
## package's sounds (TV_DIR) are loaded the same way.
func _load_recordings() -> void:
	var found := {}
	for dir: String in [CUT_DIR, TV_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in ResourceLoader.list_directory(dir):
			if not f.ends_with(".ogg") or dir + f == THEME_PATH:
				continue
			var name := f.get_basename()
			var cut := name.rfind("_")
			if cut > 0 and name.substr(cut + 1).is_valid_int():
				name = name.substr(0, cut)
			var stream := load(dir + f) as AudioStream
			if stream == null:
				continue
			if name in ["crowd", "wind", "zamboni"] and stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			if not found.has(name):
				found[name] = []
			found[name].append(stream)
	for name: String in found:
		_streams[name] = found[name]


## A free channel; with none free, a flood sound's (the oldest), else the next in turn.
func _free_voice() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _voices[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	var bed := _oldest(func(p: AudioStreamPlayer) -> bool: return BED_CAP.has(_voice_kind.get(p, "")))
	if bed:
		return bed
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	return p


## A channel for a flood sound: its oldest once it's at its budget, else a free one (null
## when every channel is busy with something else: the sound is skipped).
func _bed_voice(sound: String) -> AudioStreamPlayer:
	var same := func(p: AudioStreamPlayer) -> bool: return p.playing and _voice_kind.get(p, "") == sound
	if _voices.filter(same).size() >= BED_CAP[sound]:
		return _oldest(same)
	for i in VOICES:
		var p := _voices[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	return _oldest(func(p: AudioStreamPlayer) -> bool: return _voice_kind.get(p, "") == sound)


func _oldest(which: Callable) -> AudioStreamPlayer:
	var best: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _voices:
		if which.call(p) and (best == null or _voice_start.get(p, 0) < _voice_start.get(best, 0)):
			best = p
	return best


# --- Synthesis -------------------------------------------------------------------

func _build_all() -> void:
	_streams["click"] = _wav(_click(0.07, 1700.0, 0.55))
	_streams["shot_wrist"] = _wav(_shot(0.16, 0.7, 30.0))
	_streams["shot_slap"] = _wav(_shot(0.3, 1.0, 18.0))
	_streams["boards"] = _wav(_thud(0.5, 70.0, 0.08, 0.6, 22.0))
	_streams["glass"] = _wav(_glass())
	_streams["shatter"] = _wav(_shatter())
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


## A pane of rink glass breaking: a body slamming the boards, the crack, then a shower of
## tinkling pieces that thins out as they land.
func _shatter() -> PackedFloat32Array:
	var s := _thud(1.8, 52.0, 0.14, 0.8, 0.0)
	var hp := 0.0
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := _n()
		hp = 0.92 * (hp + n - prev)   # bright noise for the crack
		prev = n
		s[i] = s[i] * 0.7 + hp * 0.75 * exp(-t * 14.0)
	# The shower: hundreds of tiny glassy pings, most of them early.
	for k in 150:
		var start := pow(_rng.randf(), 2.2) * 1.5
		var f := _rng.randf_range(2200.0, 7800.0)
		var dur := _rng.randf_range(0.03, 0.08)
		var amp := 0.16 * (1.0 - start / 1.7) * _rng.randf_range(0.4, 1.0)
		var i0 := int(start * RATE)
		for j in int(dur * RATE):
			if i0 + j >= s.size():
				break
			var tt := float(j) / RATE
			s[i0 + j] += amp * sin(TAU * f * tt) * exp(-tt * 60.0) + amp * 0.3 * _n() * exp(-tt * 200.0)
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


## Wind across open ice: noise through a two-pole low-pass that opens up in the gusts
## (brighter and louder), the gusts' periods fitting the loop so it repeats seamlessly.
func _wind_loop(dur: float, amp: float) -> PackedFloat32Array:
	var fade := int(0.5 * RATE)
	var raw := _buf(dur + 0.5)
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var peak := 0.0001
	for i in raw.size():
		var t := float(i) / RATE
		var g := 0.55 + 0.25 * sin(TAU * t / dur) + 0.15 * sin(TAU * 3.0 * t / dur + 1.3) + 0.08 * sin(TAU * 7.0 * t / dur + 0.4)
		var a := 0.003 + 0.025 * g * g
		lp += a * (_n() - lp)
		lp2 += a * (lp - lp2)
		lp3 += 0.0008 * (lp2 - lp3)   # take out the rumble below the howl
		raw[i] = (lp2 - lp3) * g / sqrt(a)
		peak = maxf(peak, absf(raw[i]))
	var s := _buf(dur)
	for i in s.size():
		s[i] = raw[i]
		if i < fade:
			var w := float(i) / fade
			s[i] = raw[i] * w + raw[i + s.size()] * (1.0 - w)
		s[i] *= amp / peak
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
