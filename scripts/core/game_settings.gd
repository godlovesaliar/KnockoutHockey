extends Node
## Match settings chosen on the setup screen and read by MatchDirector, plus the player's
## options (audio, video). Both are saved to `user://settings.cfg` and loaded at startup:
## the rules last used become the defaults for the next game.

const SAVE_PATH := "user://settings.cfg"

## Audio buses made at startup (Sfx puts its players on them); each has a volume option.
const BUSES := {"Music": "music", "Effects": "effects", "Crowd": "crowd", "Announcer": "announcer"}

## Overtime modes: "off", "sudden_death", "shootout", "sd_so" (sudden death, then shootout).
var config := default_config()

## Volumes are 0..10 (0 mutes the bus); video options apply to the window and root viewport.
var options := default_options()

## Who plays: [{kind: "any"|"kb1"|"kb2"|"pad", pad: int, team: 0|1}]
var humans: Array = [{"kind": "any", "pad": 0, "team": 0}]

## What the setup screens lead to: "exhibition" (a game) or "knockout" (Knockout Mode). Not saved.
var mode := "exhibition"

## The main menu item to land on when coming back to it (-1: the first). Not saved.
var menu_select := -1
## ...and the main menu list to open on ("" = the main list; "customize", ...). Not saved.
var menu_list := ""


static func default_config() -> Dictionary:
	return {
		"format": 5,
		"period_length": 180.0,
		"periods": 3,
		"overtime": "sd_so",
		"ot_length": 180.0,
		"shootout_rounds": 3,
		"offsides": true,
		"icing": true,
		"penalties": true,
		"fighting": true,
		"line_changes": true,
		"difficulty": 0.5,
		"camera": "broadcast",      ## BroadcastCamera play angle
		"camera_follow": false,      ## turn the angle so your team always attacks up
		"home_team": 0,    ## Teams.LIST index
		"away_team": 1,
	}


static func default_options() -> Dictionary:
	return {
		"master": 8,
		"music": 7,
		"effects": 8,
		"crowd": 8,
		"announcer": 8,
		"window": "windowed",    ## "windowed", "fullscreen" (exclusive), "borderless" (fullscreen window)
		"vsync": true,
		"msaa": 2,               ## 0, 2, 4 or 8 samples
		"max_fps": 0,            ## 0 = no cap
	}


func _ready() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	apply_audio()
	# Video options touch the window: not for headless runs and tests.
	if DisplayServer.get_name() != "headless":
		apply_video()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k: String in config:
		config[k] = cf.get_value("rules", k, config[k])
	for k: String in options:
		options[k] = cf.get_value("options", k, options[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k: String in config:
		cf.set_value("rules", k, config[k])
	for k: String in options:
		cf.set_value("options", k, options[k])
	cf.save(SAVE_PATH)


## Volume steps 0..10 to dB: 10 is full, each step about -3 dB, 0 is silent.
static func volume_db(step: int) -> float:
	return linear_to_db(pow(clampf(step / 10.0, 0.0, 1.0), 1.6))


func apply_audio() -> void:
	_set_bus("Master", int(options.master))
	for bus: String in BUSES:
		_set_bus(bus, int(options[BUSES[bus]]))


func _set_bus(bus: String, step: int) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, step <= 0)
	AudioServer.set_bus_volume_db(i, volume_db(step))


func apply_video() -> void:
	var win := get_window()
	match str(options.window):
		"fullscreen":
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		"borderless":
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			win.mode = Window.MODE_FULLSCREEN
		_:
			if win.mode != Window.MODE_WINDOWED:
				win.mode = Window.MODE_WINDOWED
			win.borderless = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if options.vsync else DisplayServer.VSYNC_DISABLED)
	var msaa := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}
	get_viewport().msaa_3d = msaa.get(int(options.msaa), Viewport.MSAA_2X)
	Engine.max_fps = int(options.max_fps)
