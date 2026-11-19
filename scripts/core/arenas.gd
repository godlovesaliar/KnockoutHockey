class_name Arenas
## The league's arenas: one built-in per style, plus arenas made in CUSTOMIZE > CREATE
## ARENA (saved to `user://arenas.json`). Each is a style and its options:
##   id, name, style (STYLES), seats ("team" or a CustomTeams.PALETTE index), boards
##   ("white" or a palette index), lights (LIGHTS), ribbon / scoreboard / banners (bools),
##   attendance (percent of seats filled), center ("home", "league" or "none": the
##   center-ice logo); outdoor rinks also time (TIMES) and snow (SNOWS).
## Teams play at home in their home arena (`user://arena_homes.json`: abbr -> arena id;
## Modern Arena when unset). Outdoor arenas can only be a created team's home. A game's
## arena is the rules screen's ARENA pick, or the home team's (for_game).

const SAVE_PATH := "user://arenas.json"
const HOMES_PATH := "user://arena_homes.json"
const MAX_ARENAS := 24

const STYLES := ["modern", "dome", "community", "outdoor"]
const STYLE_NAMES := ["Modern Arena", "Retro Dome", "Community Rink", "Outdoor Rink"]
## Styles built so far (the rest show as coming soon).
const READY := ["modern", "dome", "community", "outdoor"]
const LIGHTS := ["cool", "neutral", "warm"]
const LIGHT_NAMES := ["Cool White", "Neutral", "Warm"]
const LIGHT_COLORS := {"cool": Color(0.94, 0.96, 1.0), "neutral": Color(1.0, 0.97, 0.9), "warm": Color(1.0, 0.86, 0.66)}
const ATTENDANCE := [25, 50, 75, 100]
const CENTERS := ["home", "league", "none"]
const CENTER_NAMES := ["Home Team Logo", "League Logo", "None"]
## Outdoor rinks only: the time of day, and the snow coming down.
const TIMES := ["day", "dusk", "night"]
const TIME_NAMES := ["Afternoon", "Sunset", "Night"]
const SNOWS := ["none", "light", "heavy"]
const SNOW_NAMES := ["None", "Flurries", "Heavy"]
## The options each style uses (CREATE ARENA shows only these).
const STYLE_OPTIONS := {
	"modern": ["seats", "boards", "lights", "attendance", "ribbon", "scoreboard", "banners", "center"],
	"dome": ["seats", "boards", "lights", "attendance", "ribbon", "scoreboard", "banners", "center"],
	"community": ["seats", "boards", "lights", "attendance", "scoreboard", "banners", "center"],
	"outdoor": ["time", "snow", "seats", "boards", "lights", "attendance", "scoreboard", "banners", "center"],
}
## How much louder or quieter the crowd is in each style, full (dB; attendance thins it too).
const CROWD_DB := {"modern": 0.0, "dome": 0.0, "community": -3.0, "outdoor": -4.0}

## Each style's building sizes, over Arena's (Modern Arena's) own.
const SIZES := {
	"modern": {},
	# One steep rake round to a ribbed concrete dome: no suite level, a short wall at the
	# cross aisle carries the ribbon board, warm concrete.
	"dome": {"SUITES": false, "CROSS_W": 2.2, "SUITE_STEP": 0.0, "SUITE_DEPTH": 0.0, "SUITE_H": 0.0,
		"OVERHANG": 0.0, "FASCIA_H": 1.1, "LOW_ROWS": 17, "UP_ROWS": 16, "UP_DEPTH": 0.82, "UP_RISE": 0.5,
		"TOP_W": 2.4, "DOME_SPRING": 21.0, "ROOF_Y": 37.0, "concrete": Color(0.46, 0.39, 0.32)},
	# A local rink: aluminum bleachers down both sides, a block-walled barn with an arched
	# wood roof (ArenaCommunity). Only the lower-bowl sizes are used (the bleacher rows).
	"community": {"LOW_ROWS": 7, "LOW_DEPTH": 0.8, "LOW_RISE": 0.4, "LOW_Y0": 0.9},
	# A frozen pond: a few rows of bleachers each side, snowbanks round the ends (ArenaOutdoor).
	"outdoor": {"LOW_ROWS": 6, "LOW_DEPTH": 0.8, "LOW_RISE": 0.4, "LOW_Y0": 0.7},
}
## Each style's built-in arena's own options (over blank()).
const STYLE_DEFAULTS := {
	"dome": {"lights": "warm", "banners": true},
	"community": {"lights": "neutral", "banners": true, "attendance": 75},
	"outdoor": {"lights": "neutral", "attendance": 75, "time": "dusk", "snow": "light"},
}

static var _list: Array = []
static var _homes := {}
static var _loaded := false


static func blank(style := "modern") -> Dictionary:
	return {
		"id": "", "name": "", "style": style, "seats": "team", "boards": "white", "lights": "cool",
		"ribbon": true, "scoreboard": true, "banners": false, "attendance": 100, "center": "home",
		"time": "dusk", "snow": "light",
	}


## The built-in arena for each style (id = the style).
static func built_in() -> Array:
	var out := []
	for i in STYLES.size():
		if STYLES[i] in READY:
			var a := blank(STYLES[i])
			a.merge(STYLE_DEFAULTS.get(STYLES[i], {}), true)
			a.id = STYLES[i]
			a.name = STYLE_NAMES[i]
			a.built_in = true
			out.append(a)
	return out


## Every arena: the built-ins, then the created ones.
static func all() -> Array:
	_load()
	return built_in() + _list


static func created() -> Array:
	_load()
	return _list


static func find(id: String) -> Dictionary:
	for a: Dictionary in all():
		if str(a.id) == id:
			return a
	return built_in()[0]


static func sizes(style: String) -> Dictionary:
	return SIZES.get(style, {})


static func style_name(style: String) -> String:
	var i := STYLES.find(style)
	return STYLE_NAMES[i] if i >= 0 else style


## The team's home arena.
static func home_of(team: int) -> Dictionary:
	_load()
	var id := str(_homes.get(str(Teams.team(team).abbr), ""))
	var a: Dictionary = find(id) if id != "" else built_in()[0]
	if not can_be_home(a, team):
		return built_in()[0]
	return a


static func home_id(team: int) -> String:
	return str(home_of(team).id)


## Outdoor rinks are home only to created teams.
static func can_be_home(a: Dictionary, team: int) -> bool:
	return str(a.get("style", "modern")) != "outdoor" or Teams.is_custom(team)


static func set_home(team: int, id: String) -> void:
	_load()
	var abbr := str(Teams.team(team).abbr)
	if id == "" or id == "modern":
		_homes.erase(abbr)
	else:
		_homes[abbr] = id
	_write_homes()


## Teams that call this arena home.
static func tenants(id: String) -> Array[int]:
	var out: Array[int] = []
	for i in Teams.count():
		if home_id(i) == id:
			out.append(i)
	return out


## The arena for a game with `home` at home: the rules screen's pick (GameSettings
## config "arena"), else the home team's.
static func for_game(home: int) -> Dictionary:
	var pick := str(GameSettings.config.get("arena", ""))
	if pick != "":
		return find(pick)
	return home_of(home)


## Saves an arena (a new one when `index` is -1); returns its index in created().
static func save_arena(a: Dictionary, index: int) -> int:
	_load()
	var copy := a.duplicate(true)
	copy.erase("built_in")
	if str(copy.get("id", "")) == "":
		copy.id = "ar%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	if index >= 0 and index < _list.size():
		_list[index] = copy
	else:
		_list.append(copy)
		index = _list.size() - 1
	_write()
	return index


static func delete_arena(index: int) -> void:
	_load()
	if index < 0 or index >= _list.size():
		return
	var id := str(_list[index].id)
	for abbr: String in _homes.keys():
		if str(_homes[abbr]) == id:
			_homes.erase(abbr)
	_write_homes()
	if str(GameSettings.config.get("arena", "")) == id:
		GameSettings.config.arena = ""
	_list.remove_at(index)
	_write()


## A created team's code changed / it was deleted.
static func rename_team(old: String, new: String) -> void:
	_load()
	if _homes.has(old):
		_homes[new] = _homes[old]
		_homes.erase(old)
		_write_homes()


static func remove_team(abbr: String) -> void:
	_load()
	if _homes.erase(abbr):
		_write_homes()


## A seat or board color option as a color (`team`: null, the caller uses the team's).
static func option_color(v: Variant, white := Color(0.96, 0.96, 0.94)) -> Variant:
	if v is String:
		return white if v == "white" else null
	return CustomTeams.PALETTE[clampi(int(v), 0, CustomTeams.PALETTE.size() - 1)][1]


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_list = []
	if FileAccess.file_exists(SAVE_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Array:
			for d: Variant in data:
				if d is Dictionary:
					var a := blank()
					a.merge(d, true)
					a.attendance = int(a.attendance)
					for k: String in ["seats", "boards"]:
						if a[k] is float:
							a[k] = int(a[k])
					_list.append(a)
	if FileAccess.file_exists(HOMES_PATH):
		var h: Variant = JSON.parse_string(FileAccess.get_file_as_string(HOMES_PATH))
		if h is Dictionary:
			_homes = h


static func _write() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_list, "\t"))


static func _write_homes() -> void:
	var f := FileAccess.open(HOMES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_homes, "\t"))
