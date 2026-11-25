class_name Rosters
## Real team rosters from data/knockout_hockey_rosters.csv (one row per player, keyed by
## the team's `abbr` in Teams.LIST). Teams without rows get generated players instead.
##
## The sheet's ratings run around 75 (goalies around 83); gameplay was tuned around
## generated players near 57, so ratings are shifted to that center. The differences
## between players are kept one for one: a 90 skater plays 15 points above the average.
##
## Columns: team, abbr, conference, number, display_name, first, last, nickname, gender, age, position (C/LW/RW/D/G),
## hand, height, weight_lbs, playstyle, overall, SKA SHT PAS HND PHY DEF (skaters),
## REF POS GLV BLK RBD (goalies).
##
## Edit Roster changes who plays where. The rosters here are the sheet with those changes
## on top: sheet players moved to another team or released (`user://roster_moves.json`:
## id -> {team, number}), plus created and generated players signed to a team
## (CustomPlayers; they carry their own `team`). Every row gets `id` ("sheet:<abbr>:<name>"
## for sheet players) and `club` (the abbr they play for now, or FREE_AGENT); a sheet row's
## `abbr` stays its original team (it seeds their looks). Rows for created and generated
## players carry the player as `custom`.

const PATH := "res://data/knockout_hockey_rosters.csv"
const MOVES_PATH := "user://roster_moves.json"
const FREE_AGENT := "FA"
## What a team must keep to dress a game (Edit Roster won't take them below it), and the
## most it can carry.
const MIN_FORWARDS := 6
const MIN_DEFENSE := 4
const MIN_GOALIES := 1
const MAX_PLAYERS := 26
const SKATER_CENTER := 75
const GOALIE_CENTER := 83
const GAME_CENTER := 57

## Play style nudges on top of the sheet's ratings.
const STYLE := {
	"Sniper": {"shot_accuracy": 6, "shot_power": 2, "aggression": -5},
	"Power Forward": {"shot_power": 5, "checking": 5, "fighting": 15, "aggression": 15},
	"Playmaker": {"passing": 5, "aggression": -5},
	"Speedster": {"speed": 5, "acceleration": 5, "aggression": -10},
	"Grinder": {"checking": 5, "fighting": 15, "aggression": 20},
	"Two-Way": {"defense": 3},
	"Enforcer D": {"checking": 6, "fighting": 30, "aggression": 30},
	"Offensive D": {"shot_power": 4, "passing": 2},
	"Stay-at-Home D": {"defense": 4, "fighting": 8, "aggression": 10},
	"Shutdown D": {"defense": 5, "fighting": 8, "aggression": 10},
	"Puck-Moving D": {"passing": 4, "puck_handling": 2},
	"Butterfly": {"pads": 6},
	"Stand-Up": {"positioning": 3},
	"Scrambler": {"reflexes": 3, "rebound_control": -3},
}

static var _sheet: Array = []     ## every sheet row, as read
static var _moves := {}           ## sheet id -> {team, number}
static var _by_abbr := {}         ## club -> rows (built from the above and CustomPlayers)
static var _loaded := false
static var _built := false


## The team's players as row dictionaries (empty if nobody plays for it). FREE_AGENT
## gives Free Agency.
static func for_team(abbr: String) -> Array:
	_build()
	return _by_abbr.get(abbr, [])


static func free_agents() -> Array:
	return for_team(FREE_AGENT)


## Something changed who plays where (or a created player): rebuild on the next ask.
static func changed() -> void:
	_built = false


## Moves a player (a row from for_team) to `club` (an abbr or FREE_AGENT). They keep their
## number unless someone there wears it; then the closest free one. Returns the number.
static func move(row: Dictionary, club: String) -> int:
	_build()
	var num := free_number(club, int(row.number), str(row.id))
	if row.has("custom"):
		CustomPlayers.set_team(str(row.id), club, num)
	else:
		var home := str(row.abbr)
		var orig := int(_sheet_row(str(row.id)).get("number", row.number))
		if club == home and num == orig:
			_moves.erase(row.id)
		else:
			_moves[row.id] = {"team": club, "number": num}
		_write_moves()
	changed()
	return num


## Two players trade places (each takes the other's club).
static func swap(a: Dictionary, b: Dictionary) -> void:
	var ca := str(a.club)
	var cb := str(b.club)
	# Through Free Agency first, so neither blocks the other's number.
	move(a, FREE_AGENT)
	move(b, ca)
	move(_find(str(a.id)), cb)


## What FILL ROSTER builds a team up to (a sheet team's shape).
const FILL_TO := {"C": 3, "LW": 3, "RW": 2, "D": 5, "G": 2}


## Signs the best free agents to `club` until it has FILL_TO at each position (a wing
## or center stands in when Free Agency runs out of one). Returns how many signed.
static func fill_from_free_agency(club: String) -> int:
	var signed := 0
	for pos: String in FILL_TO:
		var have := for_team(club).filter(func(r: Dictionary) -> bool: return r.position == pos).size()
		for k in maxi(0, int(FILL_TO[pos]) - have):
			if join_block(club) != "":
				return signed
			var pool := free_agents().filter(func(r: Dictionary) -> bool: return r.position == pos)
			if pool.is_empty() and pos in ["C", "LW", "RW"]:
				pool = free_agents().filter(func(r: Dictionary) -> bool: return r.position in ["C", "LW", "RW"])
			if pool.is_empty():
				break
			pool.sort_custom(_by_overall)
			move(pool[0], club)
			signed += 1
	return signed


## A created team's code changed: everyone signed there follows.
static func rename_club(old: String, new: String) -> void:
	_load()
	for id: String in _moves:
		if str(_moves[id].team) == old:
			_moves[id].team = new
	_write_moves()
	for p: Dictionary in CustomPlayers.everyone():
		if str(p.get("team", "")) == old:
			CustomPlayers.set_team(str(p.id), new, int(p.number))
	changed()


## A created team is gone: its players go to Free Agency.
static func release_club(club: String) -> void:
	for r: Dictionary in for_team(club).duplicate():
		move(r, FREE_AGENT)
	changed()


## Every sheet player back home, every created and generated player back in Free Agency.
static func reset_all() -> void:
	_load()
	_moves.clear()
	_write_moves()
	CustomPlayers.release_all()
	changed()


## `want` if nobody on `club` (but `id`) wears it, else the closest free number.
## Free Agency doesn't care.
static func free_number(club: String, want: int, id := "") -> int:
	if club == FREE_AGENT:
		return want
	var used := {}
	for r: Dictionary in for_team(club):
		if str(r.id) != id:
			used[int(r.number)] = true
	for d in 100:
		for n: int in [want + d, want - d]:
			if n >= 0 and n <= 99 and not used.has(n):
				return n
	return want


## Why `row` can't leave its team ("" if it can): the team would drop below what it
## needs to dress a game.
static func leave_block(row: Dictionary) -> String:
	var club := str(row.club)
	if club == FREE_AGENT:
		return ""
	var n := count(for_team(club))
	match str(row.position):
		"G":
			if n.G <= MIN_GOALIES:
				return "%s NEEDS A GOALIE" % club
		"D":
			if n.D <= MIN_DEFENSE:
				return "%s NEEDS %d DEFENSE" % [club, MIN_DEFENSE]
		_:
			if n.F <= MIN_FORWARDS:
				return "%s NEEDS %d FORWARDS" % [club, MIN_FORWARDS]
	return ""


## Why `club` can't take another player ("" if it can).
static func join_block(club: String) -> String:
	if club != FREE_AGENT and for_team(club).size() >= MAX_PLAYERS:
		return "%s IS FULL (%d)" % [club, MAX_PLAYERS]
	return ""


## {F, D, G} head counts for rows.
static func count(rows: Array) -> Dictionary:
	var n := {"F": 0, "D": 0, "G": 0}
	for r: Dictionary in rows:
		var pos := str(r.position)
		n[pos if pos in ["D", "G"] else "F"] += 1
	return n


## True if the player isn't where the sheet has them (moved, released or signed).
static func is_moved(row: Dictionary) -> bool:
	if row.has("custom"):
		return str(row.club) != FREE_AGENT
	return _moves.has(row.id)


static func _find(id: String) -> Dictionary:
	_build()
	for club: String in _by_abbr:
		for r: Dictionary in _by_abbr[club]:
			if str(r.id) == id:
				return r
	return {}


static func _sheet_row(id: String) -> Dictionary:
	for r: Dictionary in _sheet:
		if str(r.id) == id:
			return r
	return {}


static func _build() -> void:
	_load()
	if _built:
		return
	_built = true
	_by_abbr = {}
	for base: Dictionary in _sheet:
		var row := base.duplicate()
		var mv: Dictionary = _moves.get(row.id, {})
		if not mv.is_empty():
			row.club = str(mv.get("team", row.abbr))
			row.number = str(int(mv.get("number", int(row.number))))
		var list: Array = _by_abbr.get_or_add(row.club, [])
		list.append(row)
	for p: Dictionary in CustomPlayers.everyone():
		var row := CustomPlayers.roster_row(p)
		var list: Array = _by_abbr.get_or_add(row.club, [])
		list.append(row)


static func _write_moves() -> void:
	var f := FileAccess.open(MOVES_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Rosters: can't write %s" % MOVES_PATH)
		return
	f.store_string(JSON.stringify(_moves, "	"))


## The name to show for a player: the sheet's display_name ("Dag Bakken", or a ring
## name like "El Muro Azul" with no first / last split), else first + last.
static func display_name(p: Dictionary) -> String:
	var d := str(p.get("display_name", "")).strip_edges()
	return d if d != "" else ("%s %s" % [p.get("first", ""), p.get("last", "")]).strip_edges()


## Head gear a league player wears whatever team they are on (a SkaterVisual head gear key,
## as Skater.headgear), by display name. Dwayne "Cowboy" Robertson's hat is the Geese's
## signature gear: the one player in the league who plays in a cowboy hat.
const SIGNATURE_GEAR := {"Dwayne Robertson": "cowboy"}


## A sheet player's own head gear (SIGNATURE_GEAR), "" for nearly everyone.
static func signature_gear(p: Dictionary) -> String:
	return str(SIGNATURE_GEAR.get(display_name(p), ""))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Rosters: can't open %s" % PATH)
		return
	var header := f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < header.size():
			continue
		var d := {}
		for i in header.size():
			d[header[i].strip_edges()] = row[i].strip_edges()
		d.id = "sheet:%s:%s" % [d.abbr, display_name(d)]
		d.club = d.abbr
		_sheet.append(d)
	if FileAccess.file_exists(MOVES_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOVES_PATH))
		if data is Dictionary:
			_moves = data


static func _r(p: Dictionary, key: String, center: int) -> int:
	var v := str(p.get(key, ""))
	if v.is_empty():
		return GAME_CENTER
	return clampi(GAME_CENTER + int(v) - center, 1, 99)


## Game ratings for a sheet row.
static func stats(p: Dictionary) -> PlayerStats:
	var s := PlayerStats.new()
	if p.position == "G":
		s.reflexes = _r(p, "REF", GOALIE_CENTER)
		s.positioning = _r(p, "POS", GOALIE_CENTER)
		s.glove = _r(p, "GLV", GOALIE_CENTER)
		s.blocker = _r(p, "BLK", GOALIE_CENTER)
		s.rebound_control = _r(p, "RBD", GOALIE_CENTER)
		s.pads = (s.reflexes + s.positioning) / 2
		# Skating and puck play for a goalie: average, from the overall.
		var o := _r(p, "overall", GOALIE_CENTER)
		for k in ["speed", "acceleration", "agility", "endurance", "passing", "puck_handling", "strength", "durability"]:
			s.set(k, o)
		s.fighting = 35
		s.aggression = 30
	else:
		var ska := _r(p, "SKA", SKATER_CENTER)
		var phy := _r(p, "PHY", SKATER_CENTER)
		var sht := _r(p, "SHT", SKATER_CENTER)
		s.speed = ska
		s.acceleration = ska
		s.agility = ska
		s.endurance = (ska + phy) / 2
		s.shot_power = sht
		s.shot_accuracy = sht
		s.passing = _r(p, "PAS", SKATER_CENTER)
		s.puck_handling = _r(p, "HND", SKATER_CENTER)
		s.checking = phy
		s.strength = phy
		s.durability = phy
		s.defense = _r(p, "DEF", SKATER_CENTER)
		s.fighting = clampi(int(phy * 0.7) + 12, 1, 99)
		s.aggression = clampi(int(phy * 0.5) + 25, 1, 99)
	for k: String in STYLE.get(p.get("playstyle", ""), {}):
		s.set(k, clampi(int(s.get(k)) + int(STYLE[p.playstyle][k]), 1, 99))
	return s


## A row's height and weight as [m, kg] (0 where the sheet leaves it out). Height reads
## 6'1" (feet and inches).
static func size_of(p: Dictionary) -> Vector2:
	var h := 0.0
	var parts := str(p.get("height", "")).replace("\"", "").split("'")
	if parts.size() == 2 and parts[0].is_valid_int():
		h = (int(parts[0]) * 12 + int(parts[1])) * 0.0254
	var lbs := str(p.get("weight_lbs", ""))
	return Vector2(h, int(lbs) * 0.4536 if lbs.is_valid_int() else 0.0)


## Dresses `s` in a row's height and weight.
static func apply_size(s: Skater, p: Dictionary) -> void:
	var sz := size_of(p)
	s.height_m = sz.x
	s.weight_kg = sz.y


static func _by_overall(a: Dictionary, b: Dictionary) -> bool:
	return int(a.overall) > int(b.overall)


## Forwards in line order: the best players on the top line, each line a C, LW and RW
## when the roster has them (best available otherwise).
static func forward_lines(rows: Array) -> Array:
	var pool := rows.filter(func(p: Dictionary) -> bool: return p.position in ["C", "LW", "RW"])
	pool.sort_custom(_by_overall)
	var out := []
	while not pool.is_empty():
		for pos: String in ["C", "LW", "RW"]:
			if pool.is_empty():
				break
			var pick: Dictionary = pool[0]
			for p: Dictionary in pool:
				if p.position == pos:
					pick = p
					break
			pool.erase(pick)
			out.append(pick)
	return out


## Defense in pair order, best first.
static func defense_pairs(rows: Array) -> Array:
	var d := rows.filter(func(p: Dictionary) -> bool: return p.position == "D")
	d.sort_custom(_by_overall)
	return d


## Goalies, the starter (highest overall) first.
static func goalies(rows: Array) -> Array:
	var g := rows.filter(func(p: Dictionary) -> bool: return p.position == "G")
	g.sort_custom(_by_overall)
	return g
