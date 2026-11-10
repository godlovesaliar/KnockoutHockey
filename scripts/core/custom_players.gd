class_name CustomPlayers
## Players made in CUSTOMIZE > CREATE PLAYER, saved to `user://custom_players.json`.
## They start in Free Agency (`team` = FREE_AGENT); CUSTOMIZE > EDIT ROSTER (to come)
## signs them to teams by setting `team` to the team's abbreviation.
##
## Each player is a plain dictionary (JSON-friendly: colors are indices into the
## SkaterVisual palettes):
##   team (FREE_AGENT or a Teams.LIST abbr), first, last, nickname, number, position (C/LW/RW/D/G), hand (L/R), playstyle,
##   skill_mode ("points" or "free"), ratings {SKA SHT PAS HND PHY DEF} for skaters or
##   {REF POS GLV BLK RBD} for goalies (on the roster sheet's scale), gender
##   ("Male"/"Female"), skin, eyes, hair_color (palette indices), hair_style,
##   facial_hair, helmet (helmet or mask model), visor, stick, tape.
##
## Ratings use the roster sheet's scale, so a created player plays like a sheet player of
## the same ratings (as_row() feeds Rosters.stats()).
##
## Realistic with Points: every rating starts at POINTS_START and the player has a pool
## to spend (SKATER_POOL / GOALIE_POOL, enough for an average sheet player). Each point
## costs more the higher the rating already is (point_cost); taking a rating below the
## start (down to POINTS_MIN) gives points back. Free: any rating 1 to 99.

const SAVE_PATH := "user://custom_players.json"
const FREE_AGENT := "FA"

const POSITIONS := ["C", "LW", "RW", "D", "G"]
const POSITION_NAMES := ["Center", "Left Wing", "Right Wing", "Defense", "Goalie"]
const SKATER_RATINGS := ["SKA", "SHT", "PAS", "HND", "PHY", "DEF"]
const GOALIE_RATINGS := ["REF", "POS", "GLV", "BLK", "RBD"]
const RATING_NAMES := {
	"SKA": "SKATING", "SHT": "SHOOTING", "PAS": "PASSING", "HND": "PUCK HANDLING",
	"PHY": "PHYSICAL", "DEF": "DEFENSE", "REF": "REFLEXES", "POS": "POSITIONING",
	"GLV": "GLOVE", "BLK": "BLOCKER", "RBD": "REBOUND CONTROL",
}
const RATING_HINTS := {
	"SKA": "Speed, acceleration and agility.",
	"SHT": "Shot power and accuracy.",
	"PAS": "Pass speed and accuracy.",
	"HND": "Keeping the puck on the stick: dekes, and taking passes.",
	"PHY": "Checking, strength and staying on your feet. Physical players fight better too.",
	"DEF": "Reading the play, poke checks and blocking lanes.",
	"REF": "How fast the goalie reacts to a shot.",
	"POS": "Squaring up to the shooter and covering the net.",
	"GLV": "Glove-side saves.",
	"BLK": "Blocker-side saves.",
	"RBD": "Smothering shots instead of spitting out rebounds.",
}
## Play styles per position group, from the roster sheet (Rosters.STYLE nudges them).
const STYLES := {
	"F": ["Sniper", "Playmaker", "Power Forward", "Speedster", "Grinder", "Two-Way"],
	"D": ["Offensive D", "Puck-Moving D", "Two-Way", "Stay-at-Home D", "Shutdown D", "Enforcer D"],
	"G": ["Butterfly", "Stand-Up", "Hybrid", "Scrambler"],
}

const POINTS_START := 60
const POINTS_MIN := 40
const SKATER_POOL := 90    ## all six to 75: the sheet's average skater
const GOALIE_POOL := 130   ## all five to 86: about the sheet's average goalie

const SKIN_NAMES := ["Light", "Fair", "Medium", "Olive", "Brown", "Dark"]
const EYE_NAMES := ["Dark Brown", "Brown", "Hazel", "Amber", "Green", "Gray", "Blue", "Light Blue"]
const HAIR_COLOR_NAMES := ["Black", "Dark Brown", "Brown", "Light Brown", "Blonde", "Red", "Gray"]
const HAIR_STYLES := ["messy", "buzz", "shaggy", "mop", "quiff", "braid"]   ## "braid": women only
const HAIR_STYLE_NAMES := ["Messy", "Buzz Cut", "Shaggy", "Mop", "Quiff", "Braid"]
const FACIAL_HAIR := ["", "beard", "chinstrap", "moustache"]   ## men only
const FACIAL_HAIR_NAMES := ["None", "Beard", "Chinstrap", "Moustache"]
const HELMET_NAMES := ["Modern", "Classic"]
const MASK_NAMES := ["Mask 1", "Mask 2"]

static var _list: Array = []
static var _loaded := false


## A new player with every setting at its default.
static func blank() -> Dictionary:
	var p := {
		"team": FREE_AGENT, "first": "", "last": "", "nickname": "", "number": 19, "position": "C", "hand": "L",
		"playstyle": "Two-Way", "skill_mode": "points", "ratings": {},
		"gender": "Male", "skin": 1, "eyes": 1, "hair_style": "messy", "hair_color": 1,
		"facial_hair": "", "helmet": 0, "visor": true, "stick": "black", "tape": "white",
	}
	reset_ratings(p)
	return p


static func is_goalie(p: Dictionary) -> bool:
	return p.get("position", "C") == "G"


## The position's group for play styles: "F", "D" or "G".
static func group(p: Dictionary) -> String:
	match p.get("position", "C"):
		"G":
			return "G"
		"D":
			return "D"
	return "F"


static func rating_keys(p: Dictionary) -> Array:
	return GOALIE_RATINGS if is_goalie(p) else SKATER_RATINGS


## Ratings back to the start for the mode (points: all POINTS_START; free: the
## sheet's average, so a fresh free player isn't a scrub).
static func reset_ratings(p: Dictionary) -> void:
	var r := {}
	var v := POINTS_START
	if p.get("skill_mode", "points") == "free":
		v = 83 if is_goalie(p) else 75
	for k: String in rating_keys(p):
		r[k] = v
	p.ratings = r


## Points it costs to raise a rating from `v` to v + 1.
static func point_cost(v: int) -> int:
	if v < 80:
		return 1
	if v < 90:
		return 2
	return 3


## Points a rating of `v` takes from the pool (negative below the start).
static func points_for(v: int) -> int:
	var n := 0
	if v >= POINTS_START:
		for x in range(POINTS_START, v):
			n += point_cost(x)
	else:
		n = v - POINTS_START
	return n


static func pool(p: Dictionary) -> int:
	return GOALIE_POOL if is_goalie(p) else SKATER_POOL


static func points_left(p: Dictionary) -> int:
	var used := 0
	for k: String in rating_keys(p):
		used += points_for(int(p.ratings.get(k, POINTS_START)))
	return pool(p) - used


## Moves one rating by `dir` within the mode's rules. False if it can't move.
static func step_rating(p: Dictionary, key: String, dir: int) -> bool:
	var v := int(p.ratings.get(key, POINTS_START))
	var nv := v + dir
	if p.get("skill_mode", "points") == "free":
		if nv < 1 or nv > 99:
			return false
	else:
		if nv < POINTS_MIN or nv > 99:
			return false
		if dir > 0 and points_left(p) < (point_cost(v) if v >= POINTS_START else 1):
			return false
	p.ratings[key] = nv
	return true


## The player's overall: the average of their ratings.
static func overall(p: Dictionary) -> int:
	var keys := rating_keys(p)
	var sum := 0
	for k: String in keys:
		sum += int(p.ratings.get(k, POINTS_START))
	return roundi(float(sum) / keys.size())


## Switches the skill mode. Into points: ratings over the pool go back to the start.
static func set_mode(p: Dictionary, mode: String) -> void:
	p.skill_mode = mode
	var ok := true
	for k: String in rating_keys(p):
		var v := int(p.ratings.get(k, POINTS_START))
		if mode == "points" and v < POINTS_MIN:
			ok = false
	if mode == "points" and (not ok or points_left(p) < 0):
		reset_ratings(p)


## Changes position, keeping ratings when the player stays a skater (or a goalie), and
## picking a play style that fits.
static func set_position(p: Dictionary, pos: String) -> void:
	var was_goalie := is_goalie(p)
	p.position = pos
	if was_goalie != is_goalie(p):
		reset_ratings(p)
	if not p.get("playstyle", "") in STYLES[group(p)]:
		p.playstyle = STYLES[group(p)][0]


## A roster-sheet row for the player (what Rosters.stats() and the lineup code read).
static func as_row(p: Dictionary) -> Dictionary:
	var row := {
		"number": str(p.get("number", 19)), "first": p.get("first", ""), "last": p.get("last", ""),
		"nickname": p.get("nickname", ""), "gender": p.get("gender", "Male"),
		"position": p.get("position", "C"), "hand": p.get("hand", "L"),
		"playstyle": p.get("playstyle", ""), "overall": str(overall(p)),
	}
	for k: String in rating_keys(p):
		row[k] = str(p.ratings.get(k, POINTS_START))
	return row


## Dresses a skater (or goalie) as this player: name, number, body and looks, gear.
## Call before it enters the tree (the visual builds on _ready).
static func apply(s: Skater, p: Dictionary) -> void:
	s.number = int(p.get("number", 19))
	s.first_name = p.get("first", "")
	s.last_name = p.get("last", "")
	s.nickname = p.get("nickname", "")
	s.position_name = p.get("position", "C")
	s.playstyle = p.get("playstyle", "")
	s.shoots_left = p.get("hand", "L") == "L"
	s.is_defense = s.position_name == "D"
	s.stats = Rosters.stats(as_row(p))
	s.body_type = "female" if p.get("gender", "Male") == "Female" else "male"
	s.skin_tone = SkaterVisual.SKIN_TONES[clampi(int(p.get("skin", 1)), 0, SkaterVisual.SKIN_TONES.size() - 1)]
	s.eye_color = SkaterVisual.EYE_COLORS[clampi(int(p.get("eyes", 1)), 0, SkaterVisual.EYE_COLORS.size() - 1)]
	s.hair_color = SkaterVisual.HAIR_COLORS[clampi(int(p.get("hair_color", 1)), 0, SkaterVisual.HAIR_COLORS.size() - 1)]
	var style: String = p.get("hair_style", "messy")
	if style == "braid" and s.body_type != "female":
		style = "messy"
	s.hair_style = style
	s.facial_hair = p.get("facial_hair", "") if s.body_type == "male" else ""
	s.gear_style = int(p.get("helmet", 0))
	s.visor = bool(p.get("visor", true))
	s.stick_style = p.get("stick", "black")
	s.stick_tape = p.get("tape", "white")


# --- Storage -----------------------------------------------------------------------

static func all() -> Array:
	_load()
	return _list


static func save_player(p: Dictionary, index: int) -> int:
	_load()
	var copy := p.duplicate(true)
	if index >= 0 and index < _list.size():
		_list[index] = copy
	else:
		_list.append(copy)
		index = _list.size() - 1
	_write()
	return index


static func delete_player(index: int) -> void:
	_load()
	if index >= 0 and index < _list.size():
		_list.remove_at(index)
		_write()


## Players in Free Agency (not signed to a team), as [index, player] pairs.
static func free_agents() -> Array:
	var out := []
	var list := all()
	for i in list.size():
		if str(list[i].get("team", FREE_AGENT)) == FREE_AGENT:
			out.append([i, list[i]])
	return out


static func display_name(p: Dictionary) -> String:
	var n := ("%s %s" % [p.get("first", ""), p.get("last", "")]).strip_edges()
	return n if n != "" else "Unnamed #%d" % int(p.get("number", 19))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_list = []
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Array:
		for d: Variant in data:
			if d is Dictionary:
				var p := blank()
				p.merge(d, true)
				# JSON numbers come back as floats.
				for k: String in ["number", "skin", "eyes", "hair_color", "helmet"]:
					p[k] = int(p[k])
				for k: String in p.ratings:
					p.ratings[k] = int(p.ratings[k])
				_list.append(p)


static func _write() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("CustomPlayers: can't write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(_list, "\t"))
