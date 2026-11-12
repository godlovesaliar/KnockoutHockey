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

const PATH := "res://data/knockout_hockey_rosters.csv"
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

static var _by_abbr := {}
static var _loaded := false


## The team's players as row dictionaries (empty if the sheet doesn't have the team).
static func for_team(abbr: String) -> Array:
	_load()
	return _by_abbr.get(abbr, [])


## The name to show for a player: the sheet's display_name ("Dag Bakken", or a ring
## name like "El Muro Azul" with no first / last split), else first + last.
static func display_name(p: Dictionary) -> String:
	var d := str(p.get("display_name", "")).strip_edges()
	return d if d != "" else ("%s %s" % [p.get("first", ""), p.get("last", "")]).strip_edges()


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
		var team: Array = _by_abbr.get_or_add(d.abbr, [])
		team.append(d)


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
