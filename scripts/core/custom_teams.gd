class_name CustomTeams
## Teams made in CUSTOMIZE > CREATE TEAM, saved to `user://custom_teams.json`. Teams
## lists them after the league's 39 (Teams.team(i) for i >= Teams.LIST.size()), so every
## screen and game takes them like any team. Their players come from Free Agency (Edit
## Roster, or Create Team's FILL ROSTER).
##
## Each team is a dictionary in Teams.LIST's format (city, name, abbr, conference, call,
## chant, logo, colors) plus what the editor sets:
##   id, custom (true), primary / secondary / accent (indices into PALETTE),
##   pants / helmet (a SLOTS name), design (a Teams.DESIGNS key), badge (BadgeLogo's
##   settings). `colors` is worked out from those (uniform_colors) and not saved.
## `logo` is the badge drawn to `user://team_logos/<id>.png` when the team is saved.

const SAVE_PATH := "user://custom_teams.json"
const LOGO_DIR := "user://team_logos/"
const MAX_TEAMS := 24

## Team colors to pick from.
const PALETTE := [
	["Red", Color(0.78, 0.08, 0.12)], ["Crimson", Color(0.6, 0.05, 0.13)],
	["Maroon", Color(0.36, 0.05, 0.1)], ["Orange", Color(0.95, 0.42, 0.08)],
	["Gold", Color(0.98, 0.72, 0.1)], ["Vegas Gold", Color(0.72, 0.62, 0.38)],
	["Yellow", Color(1.0, 0.86, 0.12)], ["Kelly Green", Color(0.0, 0.52, 0.26)],
	["Forest Green", Color(0.05, 0.3, 0.17)], ["Lime", Color(0.55, 0.82, 0.18)],
	["Teal", Color(0.0, 0.47, 0.5)], ["Sky Blue", Color(0.35, 0.65, 0.9)],
	["Royal Blue", Color(0.08, 0.28, 0.72)], ["Navy", Color(0.05, 0.1, 0.27)],
	["Purple", Color(0.36, 0.15, 0.58)], ["Pink", Color(0.93, 0.4, 0.62)],
	["Brown", Color(0.36, 0.22, 0.12)], ["Silver", Color(0.68, 0.7, 0.73)],
	["Charcoal", Color(0.22, 0.23, 0.25)], ["Black", Color(0.07, 0.07, 0.08)],
	["Cream", Color(0.93, 0.89, 0.78)], ["White", Color(0.95, 0.95, 0.93)],
]
## Color slots the uniform and the badge pick from.
const SLOTS := ["primary", "secondary", "accent", "white", "black"]
const SLOT_NAMES := ["Primary", "Secondary", "Accent", "White", "Black"]
const DESIGN_NAMES := {
	"classic": "Classic", "double": "Double Stripe", "triple": "Triple Stripe", "bold": "Bold Band",
	"yoke": "Yoke", "yoke_stripe": "Yoke and Stripes", "pinstripe": "Pinstripe", "hoops": "Hoops",
}

static var _list: Array = []
static var _loaded := false


## A new team with every setting at its default.
static func blank() -> Dictionary:
	var t := {
		"id": "", "custom": true, "city": "", "name": "", "abbr": "", "conference": "East",
		"call": "", "chant": "", "logo": "",
		"primary": 12, "secondary": 21, "accent": 4, "pants": "black", "helmet": "primary",
		"design": "classic", "badge": BadgeLogo.blank(),
	}
	t.colors = uniform_colors(t)
	return t


static func all() -> Array:
	_load()
	return _list


static func color(t: Dictionary, slot: String) -> Color:
	match slot:
		"white":
			return Color(0.95, 0.95, 0.93)
		"black":
			return Color(0.07, 0.07, 0.08)
	return PALETTE[clampi(int(t.get(slot, 0)), 0, PALETTE.size() - 1)][1]


## Primary, secondary, accent, white, black (the order of SLOTS).
static func slot_colors(t: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for s: String in SLOTS:
		out.append(color(t, s))
	return out


## The uniform from the team's colors (Teams.LIST's colors format).
static func uniform_colors(t: Dictionary) -> Dictionary:
	var p := color(t, "primary")
	var s := color(t, "secondary")
	var a := color(t, "accent")
	var black := color(t, "black")
	return {
		"jersey": p, "trim": s,
		"pants": color(t, str(t.get("pants", "black"))), "gloves": p,
		"helmet": color(t, str(t.get("helmet", "primary"))), "skates": Color(0.05, 0.05, 0.06),
		"number": s, "number_outline": a if a.get_luminance() < 0.6 or s.get_luminance() < 0.6 else black,
	}


## "" if `abbr` can be this team's code, else why not.
static func abbr_problem(abbr: String, id: String) -> String:
	if abbr.length() < 2:
		return "THE CODE NEEDS 2 TO 4 LETTERS"
	if abbr == Rosters.FREE_AGENT:
		return "FA IS FREE AGENCY"
	for i in Teams.count():
		var t := Teams.team(i)
		if str(t.abbr) == abbr and str(t.get("id", "")) != id:
			return "%s IS TAKEN (%s)" % [abbr, Teams.full_name(i).to_upper()]
	return ""


## Saves a team (a new one when `index` is -1). Returns its index in all(). The badge
## PNG is written by the caller (Create Team draws it) to logo_path(id).
static func save_team(t: Dictionary, index: int) -> int:
	_load()
	var copy := t.duplicate(true)
	copy.erase("colors")
	if str(copy.get("id", "")) == "":
		copy.id = new_id()
	copy.logo = logo_path(copy.id)
	var old_abbr := ""
	if index >= 0 and index < _list.size():
		old_abbr = str(_list[index].abbr)
		_list[index] = copy
	else:
		_list.append(copy)
		index = _list.size() - 1
	_list[index].colors = uniform_colors(_list[index])
	_write()
	if old_abbr != "" and old_abbr != str(copy.abbr):
		Rosters.rename_club(old_abbr, str(copy.abbr))
		Uniforms.rename(old_abbr, str(copy.abbr))
		Arenas.rename_team(old_abbr, str(copy.abbr))
	Teams.changed()
	Rosters.changed()
	return index


## Deletes a team; its players go to Free Agency.
static func delete_team(index: int) -> void:
	_load()
	if index < 0 or index >= _list.size():
		return
	var t: Dictionary = _list[index]
	Rosters.release_club(str(t.abbr))
	Uniforms.remove(str(t.abbr))
	Arenas.remove_team(str(t.abbr))
	DirAccess.remove_absolute(logo_path(str(t.id)))
	_list.remove_at(index)
	_write()
	Teams.changed()
	Rosters.changed()


static func new_id() -> String:
	return "ct%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]


static func logo_path(id: String) -> String:
	return LOGO_DIR + id + ".png"


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_list = []
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Array:
		return
	for d: Variant in data:
		if not d is Dictionary:
			continue
		var t := blank()
		var badge: Dictionary = t.badge
		t.merge(d, true)
		badge.merge(t.get("badge", {}), true)
		t.badge = badge
		for k: String in ["primary", "secondary", "accent"]:
			t[k] = int(t[k])
		BadgeLogo.fix_types(t.badge)
		t.colors = uniform_colors(t)
		_list.append(t)


static func _write() -> void:
	var out := []
	for t: Dictionary in _list:
		var copy := t.duplicate(true)
		copy.erase("colors")
		out.append(copy)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("CustomTeams: can't write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(out, "\t"))
