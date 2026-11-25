class_name FreeAgentGen
## Random players for Free Agency (CustomPlayers.generated), so the pool isn't only
## created players. Made once from a seed and saved; Edit Roster signs them like anyone.
##
## They're depth players: ratings around the bottom half of the roster sheet (skaters
## mostly 66 to 74 overall, goalies 74 to 80), with a few better ones to find. Ratings
## lean the way the play style does (a Sniper shoots better than he defends).

## How many of each position.
const COUNTS := {"C": 9, "LW": 8, "RW": 8, "D": 14, "G": 9}
const FEMALE_SHARE := 0.47

const FIRST_M := ["Aaron", "Anders", "Andrei", "Beau", "Brady", "Brock", "Caleb", "Carter", "Casey", "Cole",
	"Colton", "Dane", "Dmitri", "Dylan", "Emil", "Erik", "Felix", "Gage", "Gavin", "Hank", "Henrik",
	"Ivan", "Jace", "Jake", "Jarome", "Jonas", "Kade", "Kasper", "Lars", "Luc", "Marc", "Matti",
	"Milo", "Nate", "Nico", "Oskar", "Owen", "Pavel", "Pierre", "Quinn", "Reid", "Remy", "Rhett",
	"Ryder", "Sami", "Seth", "Silas", "Teemu", "Theo", "Toby", "Trent", "Tyce", "Viktor", "Wade",
	"Wes", "Yanni", "Zach"]
const FIRST_F := ["Abby", "Alexa", "Anya", "Bailey", "Bree", "Callie", "Camille", "Dana", "Elise", "Emma",
	"Freya", "Gemma", "Greta", "Hailey", "Hanna", "Ingrid", "Jess", "Josie", "Kaia", "Kara", "Kenzie",
	"Lena", "Liv", "Maddie", "Maren", "Mia", "Nadia", "Noemie", "Paige", "Petra", "Rachel", "Riley",
	"Rosalie", "Saga", "Shea", "Signe", "Sloane", "Tatum", "Tess", "Val", "Wren", "Yulia", "Zoe"]
const LAST := ["Abbott", "Arsenault", "Bergeron", "Bjorklund", "Boucher", "Brennan", "Carlsson", "Chartier",
	"Cormier", "Dahl", "Desrosiers", "Doyle", "Dupuis", "Ekholm", "Falk", "Fischer", "Fortin",
	"Gallant", "Granlund", "Haldane", "Hartley", "Holm", "Hurley", "Ivanov", "Jansson", "Kaminski",
	"Keller", "Kerr", "Koivu", "Kowalski", "Lachance", "Landry", "Larkin", "Lindqvist", "MacInnis",
	"Madden", "Malone", "Marchand", "McAvoy", "Morin", "Novak", "Nyberg", "O'Rourke", "Ouellet",
	"Paquette", "Pelletier", "Petrov", "Poirier", "Quigley", "Rask", "Reinholt", "Roy", "Ryan",
	"Salo", "Savard", "Schultz", "Sorensen", "Stahl", "Strand", "Tremblay", "Turcotte", "Vachon",
	"Varga", "Volkov", "Walsh", "Whitlock", "Wilde", "Yakovlev", "Zajac"]
const NICKNAMES := ["The Mule", "Moose", "Tank", "Sparky", "The Wall", "Bones", "Rocket", "Hammer",
	"Tiny", "Wheels", "Doc", "Turbo", "The Plumber", "Sarge", "Snipes", "Bulldog", "Iceberg", "Pickles"]

## Rating leans per play style (on the roster sheet's scale).
const LEAN := {
	"Sniper": {"SHT": 8, "HND": 3, "DEF": -6, "PHY": -3},
	"Playmaker": {"PAS": 8, "HND": 4, "PHY": -5},
	"Power Forward": {"PHY": 7, "SHT": 3, "SKA": -3},
	"Speedster": {"SKA": 9, "PHY": -5, "DEF": -2},
	"Grinder": {"PHY": 7, "DEF": 3, "SHT": -5, "HND": -3},
	"Two-Way": {"DEF": 4},
	"Offensive D": {"SHT": 5, "PAS": 4, "DEF": -4},
	"Puck-Moving D": {"PAS": 6, "SKA": 3, "PHY": -3},
	"Stay-at-Home D": {"DEF": 6, "PHY": 3, "SHT": -6},
	"Shutdown D": {"DEF": 8, "SHT": -6, "HND": -3},
	"Enforcer D": {"PHY": 10, "DEF": 2, "SKA": -4, "HND": -5, "SHT": -3},
	"Butterfly": {"BLK": 3, "RBD": 2, "GLV": -2},
	"Stand-Up": {"POS": 5, "REF": -3},
	"Hybrid": {},
	"Scrambler": {"REF": 6, "POS": -4, "RBD": -3},
}


## The whole pool, in CustomPlayers format, all in Free Agency.
static func make(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	var names := {}
	var numbers := {}
	var n := 0
	for pos: String in COUNTS:
		for i in int(COUNTS[pos]):
			out.append(_player(rng, pos, n, names, numbers))
			n += 1
	return out


static func _player(rng: RandomNumberGenerator, pos: String, n: int, names: Dictionary, numbers: Dictionary) -> Dictionary:
	var p := CustomPlayers.blank()
	p.id = "gen:%d" % n
	p.generated = true
	p.skill_mode = "free"
	CustomPlayers.set_position(p, pos)
	var female := rng.randf() < FEMALE_SHARE
	p.gender = "Female" if female else "Male"
	# A name nobody else in the pool has.
	for tries in 20:
		p.first = (FIRST_F if female else FIRST_M)[rng.randi() % (FIRST_F if female else FIRST_M).size()]
		p.last = LAST[rng.randi() % LAST.size()]
		if not names.has(p.first + p.last):
			break
	names[p.first + p.last] = true
	p.nickname = NICKNAMES[rng.randi() % NICKNAMES.size()] if rng.randf() < 0.14 else ""
	p.hand = "L" if rng.randf() < 0.62 else "R"
	var styles: Array = CustomPlayers.STYLES[CustomPlayers.group(p)]
	p.playstyle = styles[rng.randi() % styles.size()]
	p.number = _number(rng, pos, numbers)

	# Ratings: a target overall (now and then a better one), leaned by the play style.
	var goalie := pos == "G"
	var target := rng.randfn(77.0, 2.6) if goalie else rng.randfn(70.0, 2.8)
	if rng.randf() < 0.1:
		target += rng.randf_range(4.0, 7.0)
	var lean: Dictionary = LEAN.get(p.playstyle, {})
	var r := {}
	for k: String in CustomPlayers.rating_keys(p):
		r[k] = clampi(roundi(target + float(lean.get(k, 0)) + rng.randfn(0.0, 3.0)), 45, 92)
	p.ratings = r

	# Size.
	if female:
		p.height_in = clampi(roundi(rng.randfn(68.0, 2.4)), 62, 75)
		p.weight_lbs = 160 + (p.height_in - 68) * 5
	else:
		p.height_in = clampi(roundi(rng.randfn(73.5, 2.4)), 67, 80)
		p.weight_lbs = 205 + int((p.height_in - 74) * 6.5)
	if pos == "D":
		p.weight_lbs += 8
	if p.playstyle in ["Power Forward", "Grinder", "Enforcer D"]:
		p.weight_lbs += 12
	elif p.playstyle == "Speedster":
		p.weight_lbs -= 10
	p.weight_lbs = clampi(int(round((p.weight_lbs + rng.randfn(0.0, 9.0)) / 5.0)) * 5,
			CustomPlayers.WEIGHTS[0], CustomPlayers.WEIGHTS[1])

	# Looks.
	p.skin = rng.rand_weighted(PackedFloat32Array([3.0, 3.0, 2.0, 1.5, 1.2, 1.0]))
	var dark: bool = p.skin >= 4
	p.hair_color = rng.randi() % 2 if dark else rng.rand_weighted(PackedFloat32Array([1.5, 2.5, 2.0, 1.5, 1.4, 0.5, 0.0]))
	if rng.randf() < 0.05:
		p.hair_color = CustomPlayers.HAIR_COLOR_NAMES.size() - 1   # gray
	p.eyes = rng.randi() % 2 if dark else rng.randi() % CustomPlayers.EYE_NAMES.size()
	p.hair_style = SkaterVisual.pick_hair(rng.randi(), "female" if female else "male", dark)
	p.facial_hair = "" if female or rng.randf() < 0.55 else CustomPlayers.FACIAL_HAIR[1 + rng.randi() % (CustomPlayers.FACIAL_HAIR.size() - 1)]
	p.helmet = rng.randi() % 2
	p.visor = rng.randf() < 0.75
	p.stick = SkaterVisual.STICK_STYLES[rng.randi() % SkaterVisual.STICK_STYLES.size()]
	p.tape = SkaterVisual.TAPES[rng.randi() % SkaterVisual.TAPES.size()]
	return p


## A sweater number: goalies like 1, 30-something; skaters anything but 1. Unique in
## the pool when it can be.
static func _number(rng: RandomNumberGenerator, pos: String, used: Dictionary) -> int:
	var pick := 0
	for tries in 30:
		if pos == "G":
			pick = [1, 29, 30, 31, 33, 34, 35, 37, 39, 40, 41, 50, 60, 70, 80][rng.randi() % 15]
		else:
			pick = 2 + rng.randi() % 97
		if not used.has(pick):
			break
	used[pick] = true
	return pick
