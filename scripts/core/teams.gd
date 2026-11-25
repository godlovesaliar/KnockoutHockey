class_name Teams
## The league's 39 teams in three conferences of thirteen (East, Central, West): the four
## launch teams, then the rest in the order their logos came in, then the nine expansion
## teams. After them the classic teams (CLASSIC: the Boston Beacon and the Narragansett
## Anchor, cut from the league and back as unlockables, then the Omaha Boxcar, the Butte
## Copper, the Honolulu Clipper and the Detroit Jalopy: two from each part of the map):
## in no conference (`region` says which part of the map
## they are from), and dressed in the Old-Time Set (`kit`, `headgear`) with the Retro Dome
## for a home (`home`).
## New teams go on the end: saved settings and created players keep team indices. Each team's colors dress its
## players: jersey and its stripes (trim), pants, gloves, helmet, skates, and the back
## number's face and outline. `chant` names the crowd's chant clip (Sfx); `logo` is
## the crest (cut from the logo sheets by tools/build_logos.gd); `call` names the team's
## announcer clips (intro_home_<call> / intro_away_<call>).
## Teams made in Create Team (CustomTeams) come after these: team(i) for
## i >= LIST.size(). Read teams through count() / team(i) / logo(i), never LIST.

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
			"jersey": Color(0.93, 0.4, 0.07), "trim": Color(0.1, 0.33, 0.18),
			"pants": Color(0.05, 0.16, 0.09), "gloves": Color(0.93, 0.4, 0.07),
			"helmet": Color(0.1, 0.33, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.93, 0.9), "number_outline": Color(0.1, 0.33, 0.18),
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
			# A dark berry red, off the Whalers' red.
			"jersey": Color(0.5, 0.04, 0.19), "trim": Color(0.95, 0.9, 0.78),
			"pants": Color(0.12, 0.35, 0.2), "gloves": Color(0.5, 0.04, 0.19),
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
			"jersey": Color(0.94, 0.7, 0.2), "trim": Color(0.66, 0.1, 0.1),
			"pants": Color(0.3, 0.17, 0.08), "gloves": Color(0.66, 0.1, 0.1),
			"helmet": Color(0.3, 0.17, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.66, 0.1, 0.1), "number_outline": Color(0.3, 0.17, 0.08),
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
			# Lime jersey, purple trim: purple jerseys made them a twin of the Spuds.
			"jersey": Color(0.55, 0.85, 0.2), "trim": Color(0.33, 0.17, 0.48),
			"pants": Color(0.18, 0.18, 0.2), "gloves": Color(0.55, 0.85, 0.2),
			"helmet": Color(0.18, 0.18, 0.2), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.33, 0.17, 0.48), "number_outline": Color(0.18, 0.18, 0.2),
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
			"jersey": Color(0.36, 0.4, 0.45), "trim": Color(0.62, 0.82, 0.93),
			"pants": Color(0.07, 0.13, 0.27), "gloves": Color(0.36, 0.4, 0.45),
			"helmet": Color(0.07, 0.13, 0.27), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.07, 0.13, 0.27),
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
			"jersey": Color(0.68, 0.3, 0.06), "trim": Color(0.86, 0.66, 0.4),
			"pants": Color(0.35, 0.2, 0.1), "gloves": Color(0.68, 0.3, 0.06),
			"helmet": Color(0.35, 0.2, 0.1), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.92, 0.84), "number_outline": Color(0.35, 0.2, 0.1),
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
	# Expansion teams (2026-11-11). North Dakote is one name with no city.
	{
		"city": "Baja", "name": "Chupacabras", "abbr": "BAJ", "conference": "West", "call": "chupacabras", "logo": "res://assets/characters/logo_chupacabras.png",
		"colors": {
			"jersey": Color(0.62, 0.06, 0.1), "trim": Color(0.9, 0.85, 0.72),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.62, 0.06, 0.1),
			"helmet": Color(0.07, 0.07, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.9, 0.85, 0.72), "number_outline": Color(0.07, 0.07, 0.08),
		},
	},
	{
		"city": "Carolina", "name": "Sweet Tea", "abbr": "CST", "conference": "East", "call": "sweettea", "logo": "res://assets/characters/logo_sweettea.png",
		"colors": {
			"jersey": Color(0.42, 0.67, 0.87), "trim": Color(0.72, 0.45, 0.12),
			"pants": Color(0.07, 0.14, 0.29), "gloves": Color(0.42, 0.67, 0.87),
			"helmet": Color(0.07, 0.14, 0.29), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.07, 0.14, 0.29), "number_outline": Color(0.72, 0.45, 0.12),
		},
	},
	{
		"city": "Chicago", "name": "Deep Dish", "abbr": "CHI", "conference": "Central", "call": "deepdish", "logo": "res://assets/characters/logo_deepdish.png",
		"colors": {
			"jersey": Color(0.11, 0.11, 0.12), "trim": Color(0.78, 0.16, 0.12),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.11, 0.11, 0.12),
			"helmet": Color(0.07, 0.07, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.9, 0.77), "number_outline": Color(0.78, 0.16, 0.12),
		},
	},
	{
		"city": "Mexico City", "name": "Luchadores", "abbr": "LUC", "conference": "Central", "call": "luchadores", "logo": "res://assets/characters/logo_luchadores.png",
		"colors": {
			"jersey": Color(0.86, 0.05, 0.48), "trim": Color(0.91, 0.71, 0.13),
			"pants": Color(0.08, 0.08, 0.08), "gloves": Color(0.86, 0.05, 0.48),
			"helmet": Color(0.08, 0.08, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.91, 0.71, 0.13), "number_outline": Color(0.08, 0.08, 0.08),
		},
	},
	{
		"city": "", "name": "North Dakote", "abbr": "NDK", "conference": "Central", "call": "northdakote", "logo": "res://assets/characters/logo_northdakote.png",
		"colors": {
			"jersey": Color(0.95, 0.95, 0.93), "trim": Color(0.12, 0.27, 0.63),
			"pants": Color(0.12, 0.27, 0.63), "gloves": Color(0.12, 0.27, 0.63),
			"helmet": Color(0.12, 0.27, 0.63), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.12, 0.27, 0.63), "number_outline": Color(0.83, 0.65, 0.16),
		},
	},
	{
		"city": "Philadelphia", "name": "Jawns", "abbr": "PHI", "conference": "East", "call": "jawns", "logo": "res://assets/characters/logo_jawns.png",
		"colors": {
			"jersey": Color(0.05, 0.55, 0.2), "trim": Color(0.95, 0.55, 0.12),
			"pants": Color(0.07, 0.07, 0.08), "gloves": Color(0.05, 0.55, 0.2),
			"helmet": Color(0.07, 0.07, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.95, 0.55, 0.12),
		},
	},
	{
		"city": "Pine Barrens", "name": "Campers", "abbr": "PBC", "conference": "East", "call": "campers", "logo": "res://assets/characters/logo_campers.png",
		"colors": {
			"jersey": Color(0.74, 0.65, 0.47), "trim": Color(0.12, 0.29, 0.18),
			"pants": Color(0.12, 0.29, 0.18), "gloves": Color(0.74, 0.65, 0.47),
			"helmet": Color(0.12, 0.29, 0.18), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.12, 0.29, 0.18), "number_outline": Color(0.7, 0.15, 0.12),
		},
	},
	{
		"city": "Rocky Mountain", "name": "Goats", "abbr": "RMG", "conference": "West", "call": "mountaingoats", "logo": "res://assets/characters/logo_mountaingoats.png",
		"colors": {
			"jersey": Color(0.96, 0.96, 0.94), "trim": Color(0.18, 0.19, 0.21),
			"pants": Color(0.18, 0.19, 0.21), "gloves": Color(0.18, 0.19, 0.21),
			"helmet": Color(0.18, 0.19, 0.21), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.18, 0.19, 0.21), "number_outline": Color(0.37, 0.66, 0.83),
		},
	},
	{
		"city": "Xochimilco", "name": "Axolotls", "abbr": "XOC", "conference": "West", "call": "axolotls", "logo": "res://assets/characters/logo_axolotls.png",
		"colors": {
			"jersey": Color(0.96, 0.62, 0.72), "trim": Color(0.07, 0.38, 0.36),
			"pants": Color(0.07, 0.38, 0.36), "gloves": Color(0.96, 0.62, 0.72),
			"helmet": Color(0.07, 0.38, 0.36), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.07, 0.38, 0.36), "number_outline": Color(0.95, 0.64, 0.06),
		},
	},
	# Classic teams (2026-11-24): the two teams cut from the league on 2026-11-08, with the
	# colors and designs they had. `kit` (SkaterVisual.OLD) and `headgear` put the whole
	# team in the Old-Time Set, in leather hockey helmets ("guard"; "leather" is the flapped,
	# football-looking one, which no league team wears) or bare-headed ("none");
	# `socks` is their sock pattern (SOCK_PATTERNS; the old kit makes them wool, and the pants canvas);
	# `home` is their home arena's id until one is picked for them (Arenas.home_of);
	# `region` is the conference they'd be in, which orders them on menus.
	{
		"city": "Boston", "name": "Beacon", "abbr": "BOS", "conference": "Classic", "call": "beacon", "logo": "res://assets/characters/logo_beacon.png",
		"kit": "old", "headgear": "guard", "socks": "barber", "home": "dome", "region": "East",
		"colors": {
			"jersey": Color(0.06, 0.1, 0.24), "trim": Color(0.88, 0.7, 0.28),
			"pants": Color(0.06, 0.1, 0.24), "gloves": Color(0.06, 0.1, 0.24),
			"helmet": Color(0.06, 0.1, 0.24), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.88, 0.7, 0.28), "number_outline": Color(0.95, 0.9, 0.78),
		},
	},
	{
		"city": "Narragansett", "name": "Anchor", "abbr": "NAR", "conference": "Classic", "call": "anchor", "logo": "res://assets/characters/logo_anchor.png",
		"kit": "old", "headgear": "guard", "home": "dome", "region": "East",
		"colors": {
			"jersey": Color(0.09, 0.16, 0.33), "trim": Color(0.94, 0.87, 0.7),
			"pants": Color(0.09, 0.16, 0.33), "gloves": Color(0.09, 0.16, 0.33),
			"helmet": Color(0.09, 0.16, 0.33), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.87, 0.33, 0.22), "number_outline": Color(0.94, 0.87, 0.7),
		},
	},
	# New classic teams (2026-11-24), made up for the part: the Boxcar in boxcar red with a
	# broad cream band, bare-headed; the Copper in black with a copper yoke, leather
	# helmets on; the Clipper in cream wool with sky blue and red stripes, bare-headed
	# (sky blue on the road, by auto_road).
	{
		"city": "Omaha", "name": "Boxcar", "abbr": "OMA", "conference": "Classic", "call": "boxcar", "logo": "res://assets/characters/logo_boxcar.png",
		"kit": "old", "headgear": "none", "socks": "block", "home": "dome", "region": "Central",
		"colors": {
			"jersey": Color(0.55, 0.17, 0.13), "trim": Color(0.94, 0.87, 0.7),
			"pants": Color(0.08, 0.07, 0.07), "gloves": Color(0.55, 0.17, 0.13),
			"helmet": Color(0.08, 0.07, 0.07), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.94, 0.87, 0.7), "number_outline": Color(0.08, 0.07, 0.07),
		},
	},
	{
		"city": "Butte", "name": "Copper", "abbr": "BUT", "conference": "Classic", "call": "copper", "logo": "res://assets/characters/logo_copper.png",
		"kit": "old", "headgear": "guard", "socks": "two_tone", "home": "dome", "region": "West",
		"colors": {
			"jersey": Color(0.09, 0.08, 0.08), "trim": Color(0.76, 0.44, 0.2),
			"pants": Color(0.09, 0.08, 0.08), "gloves": Color(0.09, 0.08, 0.08),
			"helmet": Color(0.09, 0.08, 0.08), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.76, 0.44, 0.2), "number_outline": Color(0.93, 0.87, 0.72),
		},
	},
	{
		"city": "Honolulu", "name": "Clipper", "abbr": "HON", "conference": "Classic", "call": "clipper", "logo": "res://assets/characters/logo_clipper.png",
		"kit": "old", "headgear": "none", "home": "dome", "region": "West",
		"colors": {
			"jersey": Color(0.93, 0.87, 0.72), "trim": Color(0.36, 0.62, 0.82),
			"pants": Color(0.14, 0.33, 0.55), "gloves": Color(0.36, 0.62, 0.82),
			"helmet": Color(0.14, 0.33, 0.55), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.14, 0.33, 0.55), "number_outline": Color(0.78, 0.2, 0.18),
		},
	},
	# (the sixth: maroon with cream and brass stripes on the sleeves and socks, leather helmets on)
	{
		"city": "Detroit", "name": "Jalopy", "abbr": "DET", "conference": "Classic", "call": "jalopy", "logo": "res://assets/characters/logo_jalopy.png",
		"kit": "old", "headgear": "guard", "socks": "barber", "home": "dome", "region": "Central",
		"colors": {
			"jersey": Color(0.4, 0.08, 0.13), "trim": Color(0.93, 0.87, 0.72),
			"pants": Color(0.08, 0.07, 0.07), "gloves": Color(0.4, 0.08, 0.13),
			"helmet": Color(0.08, 0.07, 0.07), "skates": Color(0.05, 0.05, 0.06),
			"number": Color(0.93, 0.87, 0.72), "number_outline": Color(0.8, 0.62, 0.25),
		},
	},
]

## The league's three conferences, thirteen teams each (each team's `conference` above;
## the roster sheet's conference column agrees).
const CONFERENCES := ["East", "Central", "West"]
## The classic teams' `conference`: not one of the league's (Create Team doesn't offer
## it), but they come up as a group of their own, after the West (GROUPS).
const CLASSIC := "Classic"
const GROUPS := ["East", "Central", "West", "Classic"]

## Each conference's badge color on menus (team select); the classic teams' is leather.
const CONFERENCE_COLORS := {
	"East": Color(0.26, 0.52, 0.92), "Central": Color(0.92, 0.66, 0.14), "West": Color(0.86, 0.3, 0.22),
	"Classic": Color(0.72, 0.5, 0.26),
}


## A team's conference as its badge reads: "EAST CONFERENCE", or "CLASSIC TEAM".
static func conference_label(conference: String) -> String:
	return "CLASSIC TEAM" if conference == CLASSIC else conference.to_upper() + " CONFERENCE"


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

## How socks are striped (uniform_regions.gdshaderinc `sock_pattern`, by index): "band" the
## design's stripes in its sock band, "barber" even rings all the way down, "two_tone" the
## lower sock in the trim color, "block" one broad band. A team's `socks` names one (the
## classic teams, Create Team); Create Uniform saves its own with the set.
const SOCK_PATTERNS := ["band", "barber", "two_tone", "block"]
const SOCK_PATTERN_NAMES := ["Stripes", "Barber Pole", "Two-Tone", "Block"]

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
	"chupacabras": "triple", "sweettea": "yoke", "deepdish": "pinstripe", "luchadores": "bold",
	"northdakote": "triple", "jawns": "double", "campers": "hoops", "mountaingoats": "yoke_stripe",
	"axolotls": "classic", "beacon": "yoke", "anchor": "hoops",
	"boxcar": "bold", "copper": "yoke_stripe", "clipper": "triple", "jalopy": "pinstripe",
}

## Teams whose players wear a mask instead of a helmet, by `call` (SkaterVisual.MASKS):
## "lucha" a luchador hood (a few cuts and patterns, in the team's colors), "vintage" an
## old-school fiberglass goalie face mask (goalies too).
## "florida" (a SkaterVisual.HATS key) Florida Man's backwards ball cap and sunglasses.
## (The Geese's signature gear is one player's: Rosters.SIGNATURE_GEAR.)
## "stunt" (a HATS key too) the Stuntmen's open-face stunt helmet, flame-painted.
## "watch" (a HATS key) the Whalers' knit fisherman's watch cap.
## "golf" (a HATS key) the Sweet Tea's golf visor.
const HEADGEAR_OF := {"luchadores": "lucha", "campers": "vintage", "floridaman": "florida", "stuntmen": "stunt", "whalers": "watch", "sweettea": "golf"}
## Cosmetics a league team wears, by slot (SkaterVisual.CRESTS / EYE_FX / DANGLERS), the
## tint of its visors, and face gear for all its skaters (SkaterVisual.FACE_GEAR). The
## Chupacabras' signature gear: a ridge of spines on the helmet, glowing red eyes, fangs
## hung from a smoked visor. The Grays': the alien visor.
const COSMETIC_SLOTS := ["crest", "eye_fx", "dangler"]
const COSMETICS_OF := {
	"chupacabras": {"crest": "spines", "eye_fx": "red", "dangler": "fangs", "visor_tint": "smoke"},
	"grays": {"face": "alien"},
}


static func count() -> int:
	return LIST.size() + CustomTeams.all().size()


## The team, wearing any uniform saved in Create Uniform (Uniforms).
static func team(i: int) -> Dictionary:
	if _dressed.has(i):
		return _dressed[i]
	var t: Dictionary = base_team(i)
	if Uniforms.has_any(str(t.abbr)):
		t = Uniforms.apply(t)
		_dressed[i] = t
	return t


## The team as the league list (or Create Team) has it, before Create Uniform.
static func base_team(i: int) -> Dictionary:
	if i >= LIST.size():
		var custom := CustomTeams.all()
		if not custom.is_empty():
			return custom[mini(i - LIST.size(), custom.size() - 1)]
	return LIST[clampi(i, 0, LIST.size() - 1)]


static var _dressed := {}   ## index -> team with its saved uniforms (Uniforms.apply)


static func is_custom(i: int) -> bool:
	return i >= LIST.size() and i < count()


## The index of the team with this abbr, or -1.
static func find_abbr(abbr: String) -> int:
	for i in count():
		if str(team(i).abbr) == abbr:
			return i
	return -1


static var _logos := {}   ## logo path -> Texture2D (or null)


## The team's crest, or null. League teams' are imported PNGs; created teams' are drawn
## badges saved under user:// (CustomTeams.logo_path), loaded once.
static func logo(i: int) -> Texture2D:
	var path := str(team(i).get("logo", ""))
	if path == "":
		return null
	if not _logos.has(path):
		var tex: Texture2D = null
		if path.begins_with("res://"):
			if ResourceLoader.exists(path):
				tex = load(path)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		_logos[path] = tex
	return _logos[path]


static func has_logo(i: int) -> bool:
	var path := str(team(i).get("logo", ""))
	return ResourceLoader.exists(path) if path.begins_with("res://") else (path != "" and FileAccess.file_exists(path))


## A created team or a uniform was saved or deleted: drop cached logos and uniforms.
static func changed() -> void:
	_logos.clear()
	_dressed.clear()


## A team's uniform for this game: its own colors, or road whites when they'd clash
## with the opponent's (jerseys too alike to tell apart from the camera).
## `design` names its entry in DESIGNS.
static func uniform_vs(i: int, opponent: int, away: bool) -> Dictionary:
	return uniform_of(team(i), team(opponent), away)


## uniform_vs for team dictionaries (Create Team previews a team that isn't saved yet).
static func uniform_of(mine_team: Dictionary, their_team: Dictionary, away: bool) -> Dictionary:
	var u := _uniform_of(mine_team, their_team, away).duplicate()
	var gear: String = mine_team.get("headgear", HEADGEAR_OF.get(mine_team.get("call", ""), ""))
	if gear != "":
		u["headgear"] = gear
	# Cosmetics: a created team's own choices, a league team's signature gear.
	var cos: Dictionary = COSMETICS_OF.get(mine_team.get("call", ""), {})
	for k: String in COSMETIC_SLOTS + ["visor_tint", "face"]:
		var v := str(mine_team.get(k, cos.get(k, "")))
		if v != "":
			u[k] = v
	# The old-time kit (Create Team, and the classic teams): everyone's gloves, skates,
	# sticks and goalie pads.
	if str(mine_team.get("kit", "")) != "":
		u["kit"] = str(mine_team.kit)
	# Sock pattern and pants cut (the classic teams' socks; Create Team).
	for k: String in ["socks", "pants_style"]:
		if str(mine_team.get(k, "")) != "":
			u[k] = str(mine_team[k])
	if Store.oldtime_run():   # (`-- oldtime`: everyone in it, bare-headed, for testing)
		u["kit"] = SkaterVisual.OLD
		u["headgear"] = SkaterVisual.NO_HELMET
	# Goalie mask paint: the team's choice (Create Team), in its home colors home and away.
	if str(mine_team.get("mask_paint", "")) != "":
		u["mask_paint"] = str(mine_team.mask_paint)
		u["mask_colors"] = int(mine_team.get("mask_colors", 0))
	if away:
		u["home_colors"] = mine_team.colors
	return u


static func _uniform_of(mine_team: Dictionary, their_team: Dictionary, away: bool) -> Dictionary:
	var mine: Dictionary = mine_team.colors.duplicate()
	mine["design"] = mine_team.get("design", DESIGN_OF.get(mine_team.get("call", ""), "classic"))
	if mine_team.has("design_params"):
		mine["design_params"] = mine_team.design_params
	if not away:
		return mine
	var theirs: Dictionary = their_team.colors
	var b: Color = theirs.jersey
	if mine_team.has("road"):
		# A road set saved in Create Uniform: worn on the road unless it clashes and the
		# home one doesn't.
		var road: Dictionary = mine_team.road.duplicate()
		if _clash(road.jersey, b) and not _clash(mine.jersey, b):
			return mine
		return road
	if not _clash(mine.jersey, b):
		return mine
	return auto_road(mine)


static func _clash(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() <= CLASH


## The road uniform worked out from the home one: white with the home color as trim, or
## for a light home jersey the trim color.
static func auto_road(mine: Dictionary) -> Dictionary:
	var road := mine.duplicate()
	if (mine.jersey as Color).get_luminance() > 0.7:
		# Already a light jersey: wear the trim color instead.
		road.jersey = mine.trim
		road.trim = mine.jersey
	else:
		road.jersey = Color(0.95, 0.95, 0.93)
		road.trim = mine.jersey
		road.number = mine.jersey
		road.number_outline = mine.trim
	return road


## A uniform's design parameters (Create Uniform's own, else the named design's).
static func design_params(c: Dictionary) -> Dictionary:
	var d: Dictionary = c.design_params if c.has("design_params") else DESIGNS.get(c.get("design", "classic"), {})
	# The team's own sock pattern, unless the design (a Create Uniform set) has one.
	if str(c.get("socks", "")) != "" and not d.has("sock_pattern"):
		d = d.duplicate()
		d["sock_pattern"] = maxi(SOCK_PATTERNS.find(str(c.socks)), 0)
	return d


## Teams.LIST indices of the teams in a conference, in list order.
static func in_conference(conference: String) -> Array[int]:
	var out: Array[int] = []
	for i in count():
		if team(i).conference == conference:
			out.append(i)
	return out


## "City Name"; just the name for a team without a city (North Dakote).
static func full_name(i: int) -> String:
	var t := team(i)
	return ("%s %s" % [t.city, t.name]).strip_edges()


## Every team in menu order: East, then Central, then West, then the classic teams, each
## in list order. Team select steps through this, so a conference's teams come up together.
static func menu_order() -> Array[int]:
	var out: Array[int] = []
	for c: String in GROUPS:
		var group := in_conference(c)
		if c == CLASSIC:
			# (the classic teams by where they are from, East to West, then list order)
			group.sort_custom(func(a: int, b: int) -> bool:
				var ra := CONFERENCES.find(str(team(a).get("region", "")))
				var rb := CONFERENCES.find(str(team(b).get("region", "")))
				return ra < rb if ra != rb else a < b)
		out.append_array(group)
	return out
