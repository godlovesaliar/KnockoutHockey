class_name MatchHud
extends CanvasLayer
## Scoreboard, event banners and the controlled player's status line.

var d: MatchDirector
var _board: Label
var _sub: Label
var _banner: Label
var _flash: Label
var _info: Label
var _banner_t := 0.0
var _flash_t := 0.0


func setup(director: MatchDirector) -> void:
	d = director
	_board = _label(30, Color.WHITE, 8)
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_board.offset_top = 10
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _label(16, Color(0.85, 0.88, 0.95), 5)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_sub.offset_top = 52
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner = _label(60, Color(1.0, 0.85, 0.2), 12)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 150
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_flash = _label(36, Color.WHITE, 8)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_flash.offset_top = 230
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.visible = false
	_info = _label(15, Color.WHITE, 5)
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_info.offset_left = 16
	_info.offset_top = -110
	_info.offset_bottom = -10


func _label(size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	add_child(l)
	return l


func banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_t = seconds


func flash(text: String) -> void:
	_flash.text = text
	_flash.visible = true
	_flash_t = 0.6


func _process(delta: float) -> void:
	if d == null:
		return
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0

	var c := int(ceil(d.clock))
	var time := "%d:%02d" % [c / 60, c % 60]
	if d.phase == MatchDirector.Phase.SHOOTOUT or (d.phase == MatchDirector.Phase.FINAL and not d.shootout.is_empty()):
		time = ""
	_board.text = "%s  %d   —   %d  %s        %s  %s" % [
		d.team_name(0), d.score[0], d.score[1], d.team_name(1), d.period_name(d.period), time]

	var sub := "Shots %d – %d    Hits %d – %d    Faceoffs %d – %d" % [
		d.shots_on_goal(0), d.shots_on_goal(1), d.stats.hits[0], d.stats.hits[1],
		d.stats.faceoffs[0], d.stats.faceoffs[1]]
	var s0 := d.strength(0)
	var s1 := d.strength(1)
	if s0 != s1:
		var pp := 0 if s0 > s1 else 1
		sub += "     %s POWER PLAY %d-on-%d  %s" % [d.team_name(pp), maxi(s0, s1), mini(s0, s1),
			_mmss(d.lineup(1 - pp).box_time_left())]
	if d.rules:
		if d.rules.offside_team >= 0:
			sub += "     ⚑ DELAYED OFFSIDE"
		if d.rules.has_delayed_penalty():
			sub += "     ⚑ DELAYED PENALTY"
	if not d.shootout.is_empty() and d.shootout.has("results"):
		sub = "Shootout   %s %s   |   %s %s" % [d.team_name(0), _so(d.shootout.results[0]), d.team_name(1), _so(d.shootout.results[1])]
	_sub.text = sub

	var lines := ""
	var any_human := false
	for t in 2:
		var ctl := d.control(t)
		if ctl == null:
			continue
		for h in ctl.humans:
			var sk := ctl.skater_of(h)
			if sk == null:
				continue
			any_human = true
			lines += "P%d %s  #%d %s%s  %3.0f km/h  legs %d%%%s
" % [h.player_index + 1, h.device_name(),
				sk.number, (sk.last_name.to_upper() + " ") if sk.last_name != "" else "", sk.position_name if not (sk is Goalie) else "G", sk.flat_speed() * 3.6,
				int(sk.energy * 100), "   GOALIE HAS IT: A pass · X clear · Y cover" if sk is Goalie else ""]
	if not any_human:
		lines += "AI vs AI
"
	if d.phase == MatchDirector.Phase.FACEOFF and any_human:
		lines += "FACEOFF — press pass or shoot right as the puck drops (too early = slow)
"
	lines += "Esc / Start: pause menu and controls  ·  R restart · C camera"
	_info.text = lines


static func _mmss(t: float) -> String:
	var c := int(ceil(t))
	return "%d:%02d" % [c / 60, c % 60]


static func _so(results: Array) -> String:
	var out := ""
	for r in results:
		out += "● " if r else "○ "
	return out if out != "" else "–"
