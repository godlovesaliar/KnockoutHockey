class_name Teams
## The league's 30 teams in three conferences of ten (East, Central, West): the four launch
## teams, then the rest in the order their logos came in. Each team's colors dress its
## players: jersey and its stripes (trim), pants, gloves, helmet, skates, and the back
## number's face and outline. `chant` names the crowd's chant clip (Sfx); `logo` is
## the crest (cut from the logo sheets by tools/build_logos.gd); `call` names the team's
## announcer clips (intro_home_<call> / intro_away_<call>).
## The team editor (M7) will replace this table.

const LIST := [
	{
		"city": "New Bedford", "name": "Whalers", "abbr": "NBW", "conference": "East", "call": "whalers", "chant": "chant_whalers", "logo": "res://assets/characters/logo_whalers.png",
		"colors": {
			"jersey": Color(0.76, 0.09, 0.13), "trim": Color(0.95, 0.95, 0.93),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.76, 0.09, 0.13),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.07, 0.07, 0.08),
		},
	},
	{
		"city": "Minnesota", "name": "Geese", "abbr": "MIN", "conference": "Central", "call": "geese", "chant": "chant_geese", "logo": "res://assets/characters/logo_geese.png",
		"colors": {
			"jersey": Color(0.05, 0.36, 0.19), "trim": Color(0.95, 0.72, 0.12),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.05, 0.36, 0.19),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.72, 0.12), "number_outline": Color(0.07, 0.07, 0.08),
		},
	},
	{
		"city": "Rhode Island", "name": "Quahogs", "abbr": "RIQ", "conference": "East", "call": "quahogs", "chant": "chant_quahogs", "logo": "res://assets/characters/logo_quahogs.png",
		"colors": {
			"jersey": Color(0.1, 0.3, 0.7), "trim": Color(0.66, 0.68, 0.71),
			"pants": Color(0.06, 0.11, 0.28), "gloves": Color(0.1, 0.3, 0.7),
			"helmet": Color(0.08, 0.2, 0.5), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.98, 0.82, 0.15), "number_outline": Color(0.06, 0.11, 0.28),
		},
	},
	{
		"city": "Maine", "name": "Lobsters", "abbr": "MEL", "conference": "East", "call": "lobsters", "chant": "chant_lobsters", "logo": "res://assets/characters/logo_lobsters.png",
		"colors": {
			"jersey": Color(0.95, 0.94, 0.92), "trim": Color(0.46, 0.07, 0.14),
			"pants": Color(0.46, 0.07, 0.14), "gloves": Color(0.46, 0.07, 0.14),
			"helmet": Color(0.46, 0.07, 0.14), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.46, 0.07, 0.14), "number_outline": Color(0.1, 0.42, 0.24),
		},
	},
	{
		"city": "Burlington", "name": "Lake Monsters", "abbr": "BUR", "conference": "East", "call": "monsters", "logo": "res://assets/characters/logo_lakemonsters.png",
		"colors": {
			"jersey": Color(0.07, 0.47, 0.42), "trim": Color(0.8, 0.82, 0.84),
			"pants": Color(0.08, 0.14, 0.18), "gloves": Color(0.07, 0.47, 0.42),
			"helmet": Color(0.08, 0.14, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.8, 0.82, 0.84), "number_outline": Color(0.08, 0.14, 0.18),
		},
	},
	{
		"city": "Adirondack", "name": "Trailblazers", "abbr": "ADK", "conference": "East", "call": "trailblazers", "logo": "res://assets/characters/logo_trailblazers.png",
		"colors": {
			"jersey": Color(0.1, 0.33, 0.18), "trim": Color(0.88, 0.42, 0.1),
			"pants": Color(0.05, 0.16, 0.09), "gloves": Color(0.1, 0.33, 0.18),
			"helmet": Color(0.1, 0.33, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.93, 0.9), "number_outline": Color(0.88, 0.42, 0.1),
		},
	},
	{
		"city": "Mystic", "name": "Mariners", "abbr": "MYS", "conference": "East", "call": "mariners", "logo": "res://assets/characters/logo_mariners.png",
		"colors": {
			"jersey": Color(0.4, 0.68, 0.58), "trim": Color(0.07, 0.13, 0.2),
			"pants": Color(0.07, 0.13, 0.2), "gloves": Color(0.07, 0.13, 0.2),
			"helmet": Color(0.07, 0.13, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.07, 0.13, 0.2), "number_outline": Color(0.5, 0.31, 0.17),
		},
	},
	{
		"city": "New Hampshire", "name": "Granite", "abbr": "NHG", "conference": "East", "call": "granite", "logo": "res://assets/characters/logo_granite.png",
		"colors": {
			"jersey": Color(0.55, 0.56, 0.58), "trim": Color(0.6, 0.25, 0.15),
			"pants": Color(0.08, 0.08, 0.09), "gloves": Color(0.08, 0.08, 0.09),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.08, 0.08, 0.09), "number_outline": Color(0.6, 0.25, 0.15),
		},
	},
	{
		"city": "Cape Cod", "name": "Cranberries", "abbr": "CCC", "conference": "East", "call": "cranberries", "logo": "res://assets/characters/logo_cranberries.png",
		"colors": {
			"jersey": Color(0.62, 0.07, 0.14), "trim": Color(0.95, 0.9, 0.78),
			"pants": Color(0.12, 0.35, 0.2), "gloves": Color(0.62, 0.07, 0.14),
			"helmet": Color(0.12, 0.35, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.9, 0.78), "number_outline": Color(0.12, 0.35, 0.2),
		},
	},
	{
		"city": "New York", "name": "Rats", "abbr": "NYR", "conference": "East", "call": "rats", "logo": "res://assets/characters/logo_rats.png",
		"colors": {
			"jersey": Color(0.1, 0.14, 0.32), "trim": Color(0.72, 0.1, 0.15),
			"pants": Color(0.1, 0.14, 0.32), "gloves": Color(0.1, 0.14, 0.32),
			"helmet": Color(0.1, 0.14, 0.32), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.95), "number_outline": Color(0.72, 0.1, 0.15),
		},
	},
	{
		"city": "Michigan", "name": "Mitts", "abbr": "MIM", "conference": "Central", "call": "mitts", "logo": "res://assets/characters/logo_mitts.png",
		"colors": {
			"jersey": Color(0.08, 0.12, 0.26), "trim": Color(0.95, 0.75, 0.2),
			"pants": Color(0.08, 0.12, 0.26), "gloves": Color(0.08, 0.12, 0.26),
			"helmet": Color(0.08, 0.12, 0.26), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.95, 0.75, 0.2),
		},
	},
	{
		"city": "Quebec", "name": "Poutine", "abbr": "QCP", "conference": "East", "call": "poutine", "logo": "res://assets/characters/logo_poutine.png",
		"colors": {
			"jersey": Color(0.66, 0.1, 0.1), "trim": Color(0.94, 0.7, 0.2),
			"pants": Color(0.3, 0.17, 0.08), "gloves": Color(0.66, 0.1, 0.1),
			"helmet": Color(0.3, 0.17, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.94, 0.7, 0.2), "number_outline": Color(0.3, 0.17, 0.08),
		},
	},
	{
		"city": "Tacoma", "name": "Geoducks", "abbr": "TAC", "conference": "West", "call": "geoducks", "logo": "res://assets/characters/logo_geoducks.png",
		"colors": {
			"jersey": Color(0.15, 0.45, 0.43), "trim": Color(0.88, 0.78, 0.6),
			"pants": Color(0.07, 0.15, 0.25), "gloves": Color(0.15, 0.45, 0.43),
			"helmet": Color(0.07, 0.15, 0.25), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.88, 0.78, 0.6), "number_outline": Color(0.07, 0.15, 0.25),
		},
	},
	{
		"city": "Roswell", "name": "Grays", "abbr": "ROS", "conference": "West", "call": "grays", "logo": "res://assets/characters/logo_grays.png",
		"colors": {
			"jersey": Color(0.33, 0.17, 0.48), "trim": Color(0.55, 0.85, 0.2),
			"pants": Color(0.18, 0.18, 0.2), "gloves": Color(0.33, 0.17, 0.48),
			"helmet": Color(0.18, 0.18, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.55, 0.85, 0.2), "number_outline": Color(0.18, 0.18, 0.2),
		},
	},
	{
		"city": "Wisconsin", "name": "Curds", "abbr": "WIS", "conference": "Central", "call": "curds", "logo": "res://assets/characters/logo_curds.png",
		"colors": {
			"jersey": Color(0.48, 0.1, 0.13), "trim": Color(0.96, 0.73, 0.18),
			"pants": Color(0.48, 0.1, 0.13), "gloves": Color(0.48, 0.1, 0.13),
			"helmet": Color(0.48, 0.1, 0.13), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.96, 0.73, 0.18), "number_outline": Color(0.95, 0.93, 0.88),
		},
	},
	{
		"city": "Lake Superior", "name": "Gales", "abbr": "LSG", "conference": "Central", "call": "gales", "logo": "res://assets/characters/logo_gales.png",
		"colors": {
			"jersey": Color(0.07, 0.13, 0.27), "trim": Color(0.93, 0.7, 0.2),
			"pants": Color(0.07, 0.13, 0.27), "gloves": Color(0.07, 0.13, 0.27),
			"helmet": Color(0.07, 0.13, 0.27), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.7, 0.2), "number_outline": Color(0.55, 0.58, 0.62),
		},
	},
	{
		"city": "Anchorage", "name": "Sourdoughs", "abbr": "ANC", "conference": "West", "call": "sourdoughs", "logo": "res://assets/characters/logo_sourdoughs.png",
		"colors": {
			"jersey": Color(0.1, 0.3, 0.2), "trim": Color(0.86, 0.66, 0.26),
			"pants": Color(0.35, 0.22, 0.12), "gloves": Color(0.1, 0.3, 0.2),
			"helmet": Color(0.35, 0.22, 0.12), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.86, 0.66, 0.26), "number_outline": Color(0.35, 0.22, 0.12),
		},
	},
	{
		"city": "Manitoba", "name": "Moose Jaws", "abbr": "MBJ", "conference": "Central", "call": "moosejaws", "logo": "res://assets/characters/logo_moosejaws.png",
		"colors": {
			"jersey": Color(0.3, 0.2, 0.13), "trim": Color(0.9, 0.86, 0.76),
			"pants": Color(0.12, 0.28, 0.2), "gloves": Color(0.3, 0.2, 0.13),
			"helmet": Color(0.12, 0.28, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.9, 0.86, 0.76), "number_outline": Color(0.12, 0.28, 0.2),
		},
	},
	{
		"city": "Nashville", "name": "Twang", "abbr": "NSH", "conference": "Central", "call": "twang", "logo": "res://assets/characters/logo_twang.png",
		"colors": {
			"jersey": Color(0.93, 0.68, 0.15), "trim": Color(0.08, 0.13, 0.27),
			"pants": Color(0.08, 0.13, 0.27), "gloves": Color(0.93, 0.68, 0.15),
			"helmet": Color(0.08, 0.13, 0.27), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.08, 0.13, 0.27), "number_outline": Color(0.95, 0.95, 0.93),
		},
	},
	{
		"city": "Kentucky", "name": "Moonshiners", "abbr": "KYM", "conference": "Central", "call": "moonshiners", "logo": "res://assets/characters/logo_moonshiners.png",
		"colors": {
			"jersey": Color(0.1, 0.24, 0.16), "trim": Color(0.86, 0.56, 0.18),
			"pants": Color(0.55, 0.3, 0.15), "gloves": Color(0.1, 0.24, 0.16),
			"helmet": Color(0.55, 0.3, 0.15), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.86, 0.56, 0.18), "number_outline": Color(0.95, 0.9, 0.78),
		},
	},
	{
		"city": "Okefenokee", "name": "Swamp Things", "abbr": "OKE", "conference": "Central", "call": "swampthings", "logo": "res://assets/characters/logo_swampthings.png",
		"colors": {
			"jersey": Color(0.3, 0.38, 0.18), "trim": Color(0.78, 0.7, 0.5),
			"pants": Color(0.08, 0.18, 0.12), "gloves": Color(0.3, 0.38, 0.18),
			"helmet": Color(0.08, 0.18, 0.12), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.78, 0.7, 0.5), "number_outline": Color(0.08, 0.18, 0.12),
		},
	},
	{
		"city": "Florida", "name": "Man", "abbr": "FLA", "conference": "Central", "call": "floridaman", "logo": "res://assets/characters/logo_floridaman.png",
		"colors": {
			"jersey": Color(0.1, 0.6, 0.6), "trim": Color(0.95, 0.4, 0.6),
			"pants": Color(0.06, 0.1, 0.2), "gloves": Color(0.1, 0.6, 0.6),
			"helmet": Color(0.06, 0.1, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.95, 0.4, 0.6),
		},
	},
	{
		"city": "Texas", "name": "Armadillos", "abbr": "TXA", "conference": "Central", "call": "armadillos", "logo": "res://assets/characters/logo_armadillos.png",
		"colors": {
			"jersey": Color(0.13, 0.55, 0.55), "trim": Color(0.86, 0.66, 0.4),
			"pants": Color(0.35, 0.2, 0.1), "gloves": Color(0.13, 0.55, 0.55),
			"helmet": Color(0.35, 0.2, 0.1), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.86, 0.66, 0.4), "number_outline": Color(0.35, 0.2, 0.1),
		},
	},
	{
		"city": "Portland", "name": "Lumberjacks", "abbr": "POR", "conference": "West", "call": "lumberjacks", "logo": "res://assets/characters/logo_lumberjacks.png",
		"colors": {
			"jersey": Color(0.85, 0.62, 0.12), "trim": Color(0.1, 0.08, 0.06),
			"pants": Color(0.1, 0.08, 0.06), "gloves": Color(0.85, 0.62, 0.12),
			"helmet": Color(0.1, 0.08, 0.06), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.1, 0.08, 0.06), "number_outline": Color(0.86, 0.72, 0.5),
		},
	},
	{
		"city": "Monterey", "name": "Otters", "abbr": "MON", "conference": "West", "call": "otters", "logo": "res://assets/characters/logo_otters.png",
		"colors": {
			"jersey": Color(0.55, 0.55, 0.86), "trim": Color(0.12, 0.15, 0.36),
			"pants": Color(0.12, 0.15, 0.36), "gloves": Color(0.55, 0.55, 0.86),
			"helmet": Color(0.12, 0.15, 0.36), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.12, 0.15, 0.36), "number_outline": Color(0.95, 0.95, 0.93),
		},
	},
	{
		"city": "Hollywood", "name": "Stuntmen", "abbr": "HOL", "conference": "West", "call": "stuntmen", "logo": "res://assets/characters/logo_stuntmen.png",
		"colors": {
			"jersey": Color(0.08, 0.08, 0.09), "trim": Color(0.9, 0.15, 0.55),
			"pants": Color(0.08, 0.08, 0.09), "gloves": Color(0.08, 0.08, 0.09),
			"helmet": Color(0.08, 0.08, 0.09), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.9, 0.15, 0.55), "number_outline": Color(0.76, 0.77, 0.79),
		},
	},
	{
		"city": "Mojave", "name": "Gila Monsters", "abbr": "MOJ", "conference": "West", "call": "gilamonsters", "logo": "res://assets/characters/logo_gilamonsters.png",
		"colors": {
			"jersey": Color(0.9, 0.42, 0.1), "trim": Color(0.08, 0.07, 0.07),
			"pants": Color(0.08, 0.07, 0.07), "gloves": Color(0.9, 0.42, 0.1),
			"helmet": Color(0.08, 0.07, 0.07), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.9, 0.8), "number_outline": Color(0.08, 0.07, 0.07),
		},
	},
	{
		"city": "Boise", "name": "Spuds", "abbr": "BOI", "conference": "West", "call": "spuds", "logo": "res://assets/characters/logo_spuds.png",
		"colors": {
			"jersey": Color(0.34, 0.18, 0.52), "trim": Color(0.96, 0.72, 0.15),
			"pants": Color(0.2, 0.1, 0.3), "gloves": Color(0.34, 0.18, 0.52),
			"helmet": Color(0.2, 0.1, 0.3), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.96, 0.72, 0.15), "number_outline": Color(0.95, 0.95, 0.93),
		},
	},
	{
		"city": "Seattle", "name": "Seagulls", "abbr": "SEA", "conference": "West", "call": "seagulls", "logo": "res://assets/characters/logo_seagulls.png",
		"colors": {
			"jersey": Color(0.27, 0.33, 0.4), "trim": Color(0.55, 0.76, 0.9),
			"pants": Color(0.1, 0.14, 0.2), "gloves": Color(0.27, 0.33, 0.4),
			"helmet": Color(0.1, 0.14, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.55, 0.76, 0.9),
		},
	},
	{
		"city": "Yellowstone", "name": "Geysers", "abbr": "YEL", "conference": "West", "call": "geysers", "logo": "res://assets/characters/logo_geysers.png",
		"colors": {
			"jersey": Color(0.08, 0.12, 0.3), "trim": Color(0.15, 0.7, 0.85),
			"pants": Color(0.08, 0.12, 0.3), "gloves": Color(0.08, 0.12, 0.3),
			"helmet": Color(0.08, 0.12, 0.3), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.15, 0.7, 0.85),
		},
	},
]

## The league's three conferences, ten teams each (each team's `conference` above;
## the roster sheet's conference column agrees).
const CONFERENCES := ["East", "Central", "West"]


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
	# Officials (Referee): black and white vertical stripes, orange armbands high on the
	# sleeves (the trim color), long black pants.
	"referee": {"hem_stripes": 0, "sleeve_stripes": 1, "sock_stripes": 0, "sleeve_band": Vector2(0.1, 0.2),
		"vstripes": 20.0, "long_pants": true},
}

## Each team's design, by `call`.
const DESIGN_OF := {
	"whalers": "triple", "geese": "yoke", "quahogs": "double", "lobsters": "triple",
	"monsters": "bold", "trailblazers": "yoke_stripe", "mariners": "pinstripe",
	"granite": "bold", "cranberries": "triple", "rats": "double",
	"mitts": "classic", "poutine": "yoke_stripe", "geoducks": "hoops", "grays": "bold",
	"curds": "triple", "gales": "double", "sourdoughs": "yoke", "moosejaws": "pinstripe",
	"twang": "yoke_stripe", "moonshiners": "classic", "swampthings": "bold", "floridaman": "hoops",
	"armadillos": "yoke", "lumberjacks": "hoops", "otters": "double", "stuntmen": "bold",
	"gilamonsters": "triple", "spuds": "yoke_stripe", "seagulls": "pinstripe", "geysers": "triple",
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


## Teams.LIST indices of the teams in a conference, in list order.
static func in_conference(conference: String) -> Array[int]:
	var out: Array[int] = []
	for i in LIST.size():
		if LIST[i].conference == conference:
			out.append(i)
	return out


static func full_name(i: int) -> String:
	var t := team(i)
	return "%s %s" % [t.city, t.name]
