class_name Teams
## The league's teams: the four launch teams, then the next eight, then twelve more. Each team's colors dress its
## players: jersey and its stripes (trim), pants, gloves, helmet, skates, and the back
## number's face and outline. `chant` names the crowd's chant clip (Sfx); `logo` is
## the crest (cut from the logo sheets by tools/build_logos.gd); `call` names the team's
## announcer clips (intro_home_<call> / intro_away_<call>).
## The team editor (M7) will replace this table.

const LIST := [
	{
		"city": "New Bedford", "name": "Whalers", "abbr": "NBW", "call": "whalers", "chant": "chant_whalers", "logo": "res://assets/characters/logo_whalers.png",
		"colors": {
			"jersey": Color(0.76, 0.09, 0.13), "trim": Color(0.95, 0.95, 0.93),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.76, 0.09, 0.13),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.07, 0.07, 0.08),
		},
	},
	{
		"city": "Minnesota", "name": "Geese", "abbr": "MIN", "call": "geese", "chant": "chant_geese", "logo": "res://assets/characters/logo_geese.png",
		"colors": {
			"jersey": Color(0.05, 0.36, 0.19), "trim": Color(0.95, 0.72, 0.12),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.05, 0.36, 0.19),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.72, 0.12), "number_outline": Color(0.07, 0.07, 0.08),
		},
	},
	{
		"city": "Rhode Island", "name": "Quahogs", "abbr": "RIQ", "call": "quahogs", "chant": "chant_quahogs", "logo": "res://assets/characters/logo_quahogs.png",
		"colors": {
			"jersey": Color(0.1, 0.3, 0.7), "trim": Color(0.66, 0.68, 0.71),
			"pants": Color(0.06, 0.11, 0.28), "gloves": Color(0.1, 0.3, 0.7),
			"helmet": Color(0.08, 0.2, 0.5), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.98, 0.82, 0.15), "number_outline": Color(0.06, 0.11, 0.28),
		},
	},
	{
		"city": "Maine", "name": "Lobsters", "abbr": "MEL", "call": "lobsters", "chant": "chant_lobsters", "logo": "res://assets/characters/logo_lobsters.png",
		"colors": {
			"jersey": Color(0.95, 0.94, 0.92), "trim": Color(0.46, 0.07, 0.14),
			"pants": Color(0.46, 0.07, 0.14), "gloves": Color(0.46, 0.07, 0.14),
			"helmet": Color(0.46, 0.07, 0.14), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.46, 0.07, 0.14), "number_outline": Color(0.1, 0.42, 0.24),
		},
	},
	{
		"city": "Burlington", "name": "Lake Monsters", "abbr": "BUR", "call": "monsters", "logo": "res://assets/characters/logo_lakemonsters.png",
		"colors": {
			"jersey": Color(0.07, 0.47, 0.42), "trim": Color(0.8, 0.82, 0.84),
			"pants": Color(0.08, 0.14, 0.18), "gloves": Color(0.07, 0.47, 0.42),
			"helmet": Color(0.08, 0.14, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.8, 0.82, 0.84), "number_outline": Color(0.08, 0.14, 0.18),
		},
	},
	{
		"city": "Narragansett", "name": "Anchor", "abbr": "NAR", "call": "anchor", "logo": "res://assets/characters/logo_anchor.png",
		"colors": {
			"jersey": Color(0.09, 0.16, 0.33), "trim": Color(0.94, 0.87, 0.7),
			"pants": Color(0.09, 0.16, 0.33), "gloves": Color(0.09, 0.16, 0.33),
			"helmet": Color(0.09, 0.16, 0.33), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.87, 0.33, 0.22), "number_outline": Color(0.94, 0.87, 0.7),
		},
	},
	{
		"city": "Adirondack", "name": "Trailblazers", "abbr": "ADK", "call": "trailblazers", "logo": "res://assets/characters/logo_trailblazers.png",
		"colors": {
			"jersey": Color(0.1, 0.33, 0.18), "trim": Color(0.88, 0.42, 0.1),
			"pants": Color(0.05, 0.16, 0.09), "gloves": Color(0.1, 0.33, 0.18),
			"helmet": Color(0.1, 0.33, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.93, 0.9), "number_outline": Color(0.88, 0.42, 0.1),
		},
	},
	{
		"city": "Mystic", "name": "Mariners", "abbr": "MYS", "call": "mariners", "logo": "res://assets/characters/logo_mariners.png",
		"colors": {
			"jersey": Color(0.4, 0.68, 0.58), "trim": Color(0.07, 0.13, 0.2),
			"pants": Color(0.07, 0.13, 0.2), "gloves": Color(0.07, 0.13, 0.2),
			"helmet": Color(0.07, 0.13, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.07, 0.13, 0.2), "number_outline": Color(0.5, 0.31, 0.17),
		},
	},
	{
		"city": "New Hampshire", "name": "Granite", "abbr": "NHG", "call": "granite", "logo": "res://assets/characters/logo_granite.png",
		"colors": {
			"jersey": Color(0.55, 0.56, 0.58), "trim": Color(0.6, 0.25, 0.15),
			"pants": Color(0.08, 0.08, 0.09), "gloves": Color(0.08, 0.08, 0.09),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.08, 0.08, 0.09), "number_outline": Color(0.6, 0.25, 0.15),
		},
	},
	{
		"city": "Cape Cod", "name": "Cranberries", "abbr": "CCC", "call": "cranberries", "logo": "res://assets/characters/logo_cranberries.png",
		"colors": {
			"jersey": Color(0.62, 0.07, 0.14), "trim": Color(0.95, 0.9, 0.78),
			"pants": Color(0.12, 0.35, 0.2), "gloves": Color(0.62, 0.07, 0.14),
			"helmet": Color(0.12, 0.35, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.9, 0.78), "number_outline": Color(0.12, 0.35, 0.2),
		},
	},
	{
		"city": "New York", "name": "Rats", "abbr": "NYR", "call": "rats", "logo": "res://assets/characters/logo_rats.png",
		"colors": {
			"jersey": Color(0.1, 0.14, 0.32), "trim": Color(0.72, 0.1, 0.15),
			"pants": Color(0.1, 0.14, 0.32), "gloves": Color(0.1, 0.14, 0.32),
			"helmet": Color(0.1, 0.14, 0.32), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.95), "number_outline": Color(0.72, 0.1, 0.15),
		},
	},
	{
		"city": "Boston", "name": "Beacon", "abbr": "BOS", "call": "beacon", "logo": "res://assets/characters/logo_beacon.png",
		"colors": {
			"jersey": Color(0.06, 0.1, 0.24), "trim": Color(0.88, 0.7, 0.28),
			"pants": Color(0.06, 0.1, 0.24), "gloves": Color(0.06, 0.1, 0.24),
			"helmet": Color(0.06, 0.1, 0.24), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.88, 0.7, 0.28), "number_outline": Color(0.95, 0.9, 0.78),
		},
	},
	{
		"city": "Michigan", "name": "Mitts", "abbr": "MIC", "call": "mitts", "logo": "res://assets/characters/logo_mitts.png",
		"colors": {
			"jersey": Color(0.08, 0.12, 0.26), "trim": Color(0.95, 0.75, 0.2),
			"pants": Color(0.08, 0.12, 0.26), "gloves": Color(0.08, 0.12, 0.26),
			"helmet": Color(0.08, 0.12, 0.26), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.95, 0.75, 0.2),
		},
	},
	{
		"city": "Quebec", "name": "Poutine", "abbr": "QUE", "call": "poutine", "logo": "res://assets/characters/logo_poutine.png",
		"colors": {
			"jersey": Color(0.66, 0.1, 0.1), "trim": Color(0.94, 0.7, 0.2),
			"pants": Color(0.3, 0.17, 0.08), "gloves": Color(0.66, 0.1, 0.1),
			"helmet": Color(0.3, 0.17, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.94, 0.7, 0.2), "number_outline": Color(0.3, 0.17, 0.08),
		},
	},
	{
		"city": "Tacoma", "name": "Geoducks", "abbr": "TAC", "call": "geoducks", "logo": "res://assets/characters/logo_geoducks.png",
		"colors": {
			"jersey": Color(0.15, 0.45, 0.43), "trim": Color(0.88, 0.78, 0.6),
			"pants": Color(0.07, 0.15, 0.25), "gloves": Color(0.15, 0.45, 0.43),
			"helmet": Color(0.07, 0.15, 0.25), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.88, 0.78, 0.6), "number_outline": Color(0.07, 0.15, 0.25),
		},
	},
	{
		"city": "Roswell", "name": "Grays", "abbr": "ROS", "call": "grays", "logo": "res://assets/characters/logo_grays.png",
		"colors": {
			"jersey": Color(0.33, 0.17, 0.48), "trim": Color(0.55, 0.85, 0.2),
			"pants": Color(0.18, 0.18, 0.2), "gloves": Color(0.33, 0.17, 0.48),
			"helmet": Color(0.18, 0.18, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.55, 0.85, 0.2), "number_outline": Color(0.18, 0.18, 0.2),
		},
	},
	{
		"city": "Wisconsin", "name": "Curds", "abbr": "WIS", "call": "curds", "logo": "res://assets/characters/logo_curds.png",
		"colors": {
			"jersey": Color(0.48, 0.1, 0.13), "trim": Color(0.96, 0.73, 0.18),
			"pants": Color(0.48, 0.1, 0.13), "gloves": Color(0.48, 0.1, 0.13),
			"helmet": Color(0.48, 0.1, 0.13), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.96, 0.73, 0.18), "number_outline": Color(0.95, 0.93, 0.88),
		},
	},
	{
		"city": "Lake Superior", "name": "Gales", "abbr": "LSG", "call": "gales", "logo": "res://assets/characters/logo_gales.png",
		"colors": {
			"jersey": Color(0.07, 0.13, 0.27), "trim": Color(0.93, 0.7, 0.2),
			"pants": Color(0.07, 0.13, 0.27), "gloves": Color(0.07, 0.13, 0.27),
			"helmet": Color(0.07, 0.13, 0.27), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.7, 0.2), "number_outline": Color(0.55, 0.58, 0.62),
		},
	},
	{
		"city": "Anchorage", "name": "Sourdoughs", "abbr": "ANC", "call": "sourdoughs", "logo": "res://assets/characters/logo_sourdoughs.png",
		"colors": {
			"jersey": Color(0.1, 0.3, 0.2), "trim": Color(0.86, 0.66, 0.26),
			"pants": Color(0.35, 0.22, 0.12), "gloves": Color(0.1, 0.3, 0.2),
			"helmet": Color(0.35, 0.22, 0.12), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.86, 0.66, 0.26), "number_outline": Color(0.35, 0.22, 0.12),
		},
	},
	{
		"city": "Manitoba", "name": "Moose Jaws", "abbr": "MAN", "call": "moosejaws", "logo": "res://assets/characters/logo_moosejaws.png",
		"colors": {
			"jersey": Color(0.3, 0.2, 0.13), "trim": Color(0.9, 0.86, 0.76),
			"pants": Color(0.12, 0.28, 0.2), "gloves": Color(0.3, 0.2, 0.13),
			"helmet": Color(0.12, 0.28, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.9, 0.86, 0.76), "number_outline": Color(0.12, 0.28, 0.2),
		},
	},
	{
		"city": "Nashville", "name": "Twang", "abbr": "NSH", "call": "twang", "logo": "res://assets/characters/logo_twang.png",
		"colors": {
			"jersey": Color(0.93, 0.68, 0.15), "trim": Color(0.08, 0.13, 0.27),
			"pants": Color(0.08, 0.13, 0.27), "gloves": Color(0.93, 0.68, 0.15),
			"helmet": Color(0.08, 0.13, 0.27), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.08, 0.13, 0.27), "number_outline": Color(0.95, 0.95, 0.93),
		},
	},
	{
		"city": "Kentucky", "name": "Moonshiners", "abbr": "KEN", "call": "moonshiners", "logo": "res://assets/characters/logo_moonshiners.png",
		"colors": {
			"jersey": Color(0.1, 0.24, 0.16), "trim": Color(0.86, 0.56, 0.18),
			"pants": Color(0.55, 0.3, 0.15), "gloves": Color(0.1, 0.24, 0.16),
			"helmet": Color(0.55, 0.3, 0.15), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.86, 0.56, 0.18), "number_outline": Color(0.95, 0.9, 0.78),
		},
	},
	{
		"city": "Okefenokee", "name": "Swamp Things", "abbr": "OKE", "call": "swampthings", "logo": "res://assets/characters/logo_swampthings.png",
		"colors": {
			"jersey": Color(0.3, 0.38, 0.18), "trim": Color(0.78, 0.7, 0.5),
			"pants": Color(0.08, 0.18, 0.12), "gloves": Color(0.3, 0.38, 0.18),
			"helmet": Color(0.08, 0.18, 0.12), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.78, 0.7, 0.5), "number_outline": Color(0.08, 0.18, 0.12),
		},
	},
	{
		"city": "Florida", "name": "Florida Man", "abbr": "FLA", "call": "floridaman", "logo": "res://assets/characters/logo_floridaman.png",
		"colors": {
			"jersey": Color(0.1, 0.6, 0.6), "trim": Color(0.95, 0.4, 0.6),
			"pants": Color(0.06, 0.1, 0.2), "gloves": Color(0.1, 0.6, 0.6),
			"helmet": Color(0.06, 0.1, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.95, 0.4, 0.6),
		},
	},
]


const CLASH := 0.3   ## jersey colors closer than this (RGB distance) clash

## Jersey designs: stripe layout and yoke, set as uniform shader parameters (see
## scenes/actors/uniform_regions.gdshaderinc). Bands are positions along the part
## (torso hips -> neck, arm shoulder -> wrist, leg hip -> ankle). Alternating stripes
## use the team's number outline color as the accent.
const DESIGNS := {
	"classic": {},
	"double": {"hem_stripes": 2, "sleeve_stripes": 2, "sock_stripes": 2,
		"hem_band": Vector2(0.17, 0.29), "sleeve_band": Vector2(0.58, 0.7), "sock_band": Vector2(0.6, 0.72)},
	"triple": {"hem_stripes": 3, "sleeve_stripes": 3, "sock_stripes": 3, "alternate": true,
		"hem_band": Vector2(0.17, 0.33), "sleeve_band": Vector2(0.56, 0.72), "sock_band": Vector2(0.58, 0.75)},
	"yoke": {"yoke_r": 0.3, "hem_stripes": 1, "sleeve_stripes": 0, "sock_stripes": 2,
		"sock_band": Vector2(0.6, 0.72)},
	"yoke_stripe": {"yoke_r": 0.27, "hem_stripes": 2, "sleeve_stripes": 1, "sock_stripes": 1,
		"hem_band": Vector2(0.17, 0.28), "alternate": true},
	"bold": {"hem_band": Vector2(0.17, 0.34), "sleeve_band": Vector2(0.54, 0.72), "sock_band": Vector2(0.57, 0.77)},
	"pinstripe": {"hem_stripes": 0, "sleeve_stripes": 2, "sock_stripes": 3, "alternate": true,
		"sleeve_band": Vector2(0.6, 0.69), "sock_band": Vector2(0.6, 0.73)},
	"hoops": {"hem_stripes": 2, "sleeve_stripes": 2, "sock_stripes": 4, "alternate": true,
		"hem_band": Vector2(0.17, 0.3), "sleeve_band": Vector2(0.58, 0.7), "sock_band": Vector2(0.48, 0.86)},
}

## Each team's design, by `call`.
const DESIGN_OF := {
	"whalers": "triple", "geese": "yoke", "quahogs": "double", "lobsters": "triple",
	"monsters": "bold", "anchor": "hoops", "trailblazers": "yoke_stripe", "mariners": "pinstripe",
	"granite": "bold", "cranberries": "triple", "rats": "double", "beacon": "yoke",
	"mitts": "classic", "poutine": "yoke_stripe", "geoducks": "hoops", "grays": "bold",
	"curds": "triple", "gales": "double", "sourdoughs": "yoke", "moosejaws": "pinstripe",
	"twang": "yoke_stripe", "moonshiners": "classic", "swampthings": "bold", "floridaman": "hoops",
}


static func count() -> int:
	return LIST.size()


static func team(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


## A team's uniform for this game: its own colors, or road whites when they'd clash
## with the opponent's (jerseys too alike to tell apart from the camera).
## `design` names its entry in DESIGNS.
static func uniform_vs(i: int, opponent: int, away: bool) -> Dictionary:
	var mine: Dictionary = team(i).colors.duplicate()
	mine["design"] = DESIGN_OF.get(team(i).get("call", ""), "classic")
	if not away:
		return mine
	var theirs: Dictionary = team(opponent).colors
	var a: Color = mine.jersey
	var b: Color = theirs.jersey
	if Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > CLASH:
		return mine
	var road := mine.duplicate()
	if a.get_luminance() > 0.7:
		# Already a light jersey: wear the trim color instead.
		road.jersey = mine.trim
		road.trim = mine.jersey
	else:
		road.jersey = Color(0.95, 0.95, 0.93)
		road.trim = mine.jersey
		road.number = mine.jersey
		road.number_outline = mine.trim
	return road


static func full_name(i: int) -> String:
	var t := team(i)
	if str(t.name).begins_with(t.city):
		return t.name   # Florida Man
	return "%s %s" % [t.city, t.name]
