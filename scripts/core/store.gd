class_name Store
## The Pro Shop's shelves: what pucks buy (Profile keeps what's owned), and the checks the
## rest of the game uses to see whether something is still locked.
##
## Locked means it can't be picked: a locked rink isn't offered for a game or as a home
## arena, and Create Arena can't build in its style; a locked goalie mask or head gear
## isn't offered in Create Player / Create Team. Nothing already saved stops working, and
## the league's own teams and goalies wear what they always did.
##
## The Old-Time Set is one item for a whole look (SkaterVisual.OLD): playing bare-headed
## (or in one of its two leather helmets, the flapped one and the hockey head guard),
## leather gauntlets, leather skates on tube frames, a wooden stick, and a goalie's
## leather pads, waffle board and mitt. Bought, each piece is offered on its own in Create
## Player, and Create Team can put a whole team in it.
##
## Teams are a two-step unlock. The locked teams (the top three of each conference, and
## the classic teams, Teams.CLASSIC) can't be picked anywhere. Buying one buys its challenge: a game against them in their
## arena, on Pro or harder, started from the shop as often as it takes. Winning it
## unlocks the team for good (Profile.unlock_team, banked with the game's pucks). The
## classic teams wear the Old-Time Set whether or not it's bought (a league team's own
## gear, like the Campers' masks).
##
## Extras change how a game looks or plays for both teams alike. Once bought, each has a
## switch (in the shop: accept on it); MatchDirector applies the ones that are on
## (extras_on) to real games and Knockout Mode. They don't change what a game pays.
##
## `-- unlockall` opens everything for that run (testing; nothing is saved).
## `-- oldtime` dresses every team in the Old-Time Set, bare-headed, for that run.
## `-- extras=<key>,<key>` switches those extras on for that run, owned or not.

const CATEGORIES := ["teams", "rinks", "gear", "extras"]
const CATEGORY_NAMES := ["TEAMS", "RINKS", "GEAR", "EXTRAS"]
const CHALLENGE_DIFFICULTY := 0.5   ## challenge games are played at this CPU difficulty (Pro) or harder

## Team items: `team` is the team's `call` (Teams.LIST). Extras: `extra` is the key the
## game knows it by (extra_on).
## Prices: the whole store is meant to cost about what 50 games pay (some 13,000 pucks;
## scenes/tests/StoreCheck.tscn prints the total; the classic teams, added later and not
## balanced in yet, take it well past that). Teams 1,400 / 900 / 500 by seed, a classic team 500, a rink
## 500, a single piece of gear 200, a team's signature gear 100 (it comes on top of the
## team's own price), a set of gear 500, an extra 250 to 400.
const ITEMS := [
	{"id": "team_whalers", "cat": "teams", "team": "whalers", "name": "New Bedford Whalers", "price": 1400, "text": "The East's first seed."},
	{"id": "team_campers", "cat": "teams", "team": "campers", "name": "Pine Barrens Campers", "price": 900, "text": "The East's second seed."},
	{"id": "team_sweettea", "cat": "teams", "team": "sweettea", "name": "Carolina Sweet Tea", "price": 500, "text": "The East's third seed."},
	{"id": "team_geese", "cat": "teams", "team": "geese", "name": "Minnesota Geese", "price": 1400, "text": "The Central's first seed."},
	{"id": "team_luchadores", "cat": "teams", "team": "luchadores", "name": "Mexico City Luchadores", "price": 900, "text": "The Central's second seed."},
	{"id": "team_floridaman", "cat": "teams", "team": "floridaman", "name": "Florida Man", "price": 500, "text": "The Central's third seed."},
	{"id": "team_grays", "cat": "teams", "team": "grays", "name": "Roswell Grays", "price": 1400, "text": "The West's first seed."},
	{"id": "team_stuntmen", "cat": "teams", "team": "stuntmen", "name": "Hollywood Stuntmen", "price": 900, "text": "The West's second seed."},
	{"id": "team_chupacabras", "cat": "teams", "team": "chupacabras", "name": "Baja Chupacabras", "price": 500, "text": "The West's third seed."},
	# (a team's text shares its card with the line ratings: keep it to a few words)
	{"id": "team_beacon", "cat": "teams", "team": "beacon", "name": "Boston Beacon", "price": 500, "text": "A classic team, in leather."},
	{"id": "team_anchor", "cat": "teams", "team": "anchor", "name": "Narragansett Anchor", "price": 500, "text": "A classic team, in leather."},
	{"id": "team_boxcar", "cat": "teams", "team": "boxcar", "name": "Omaha Boxcar", "price": 500, "text": "A classic team, in leather."},
	{"id": "team_copper", "cat": "teams", "team": "copper", "name": "Butte Copper", "price": 500, "text": "A classic team, in leather."},
	{"id": "team_clipper", "cat": "teams", "team": "clipper", "name": "Honolulu Clipper", "price": 500, "text": "A classic team, in leather."},
	{"id": "team_jalopy", "cat": "teams", "team": "jalopy", "name": "Detroit Jalopy", "price": 500, "text": "A classic team, in leather."},
	{"id": "rink_community", "cat": "rinks", "name": "Community Rink", "price": 500,
		"text": "The local barn: block walls, a wooden roof and bleachers down both sides. Play any game there, make it a team's home, or build your own in Create Arena."},
	{"id": "rink_outdoor", "cat": "rinks", "name": "Outdoor Rink", "price": 500,
		"text": "A frozen pond in the woods, with snowbanks, floodlights and a warming hut. Play any game there, or build your own in Create Arena: afternoon, sunset or night, with or without snow."},
	{"id": "mask_cage", "cat": "gear", "name": "Helmet & Cage", "price": 200,
		"text": "A goalie mask for Create Player: the classic skater's helmet with a full wire cage."},
	{"id": "mask_molded", "cat": "gear", "name": "Molded Mask", "price": 200,
		"text": "A goalie mask for Create Player: the molded fiberglass mask, ready for paint."},
	{"id": "gear_vintage", "cat": "gear", "name": "Vintage Face Mask", "price": 100,
		"text": "The Campers' old-school fiberglass face mask, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_lucha", "cat": "gear", "name": "Lucha Hood", "price": 100,
		"text": "The Luchadores' wrestling hood in your team's colors, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_florida", "cat": "gear", "name": "Cap & Shades", "price": 100,
		"text": "Florida Man's backwards ball cap and wraparound mirrored shades, the cap in your team's colors, in place of a helmet. Put them on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_cowboy", "cat": "gear", "name": "Cowboy Hat", "price": 100,
		"text": "A cowboy hat with a band in your team's color, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_chupa", "cat": "gear", "name": "Spines, Eyes & Fangs", "price": 100,
		"text": "The Chupacabras' three cosmetics, each switched on its own: a ridge of spines on the helmet, glowing red eyes, and fangs hung from the visor. For one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_stunt", "cat": "gear", "name": "Stunt Helmet", "price": 100,
		"text": "The Stuntmen's helmet: an open-face daredevil's helmet with a snap-on peak, painted with flames in your team's colors, in place of a hockey helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_watch", "cat": "gear", "name": "Watch Cap", "price": 100,
		"text": "The Whalers' cap: a knit fisherman's watch cap, ribbed, with a deep folded cuff and a stripe round it, in your team's colors, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_golf", "cat": "gear", "name": "Golf Visor", "price": 100,
		"text": "The Sweet Tea's visor: a golf visor, a band round the head in your team's colors with a see-through tinted bill and the top of the head left open, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_beanie", "cat": "gear", "name": "Pom Beanie", "price": 100,
		"text": "A winter knit beanie pulled down over the tops of the ears, striped in your team's colors, with a pom on top, in place of a helmet. Put it on one player in Create Player, or a whole team in Create Team."},
	{"id": "gear_grays", "cat": "gear", "name": "Alien Visor", "price": 100,
		"text": "The Grays' visor: a pair of great black slanted eyes, a bulging mirrored lens over each of your own, in place of the visor on any helmet. For one player in Create Player, or a whole team in Create Team."},
	{"id": "helmet_bucket", "cat": "gear", "name": "'80s Bucket", "price": 200,
		"text": "A helmet for Create Player: the round one-piece shell of the early '80s, cut high over the ears, which stay open inside a loop."},
	{"id": "face_full", "cat": "gear", "name": "Cage & Full Shield", "price": 200,
		"text": "Full face protection for Create Player, on any helmet in place of the visor: a chromed wire cage, or a clear shield from the brow to under the chin."},
	{"id": "visor_tints", "cat": "gear", "name": "Tinted Visors", "price": 200,
		"text": "Visor tints for Create Player: smoked, amber, blue mirror and gold mirror. They tint the full shield too."},
	{"id": "gear_oldtime", "cat": "gear", "name": "Old-Time Set", "price": 500,
		"text": "Hockey as it looked before helmets: bare heads or one of two leather helmets, leather gauntlets, tan leather skates on steel tube frames, heavy wool socks, canvas pants and a straight wooden stick, and for goalies leather pads, a waffle board and a mitt. Wear any piece in Create Player, or dress a whole team in Create Team."},
	{"id": "gear_longpants", "cat": "gear", "name": "Long Pants", "price": 200,
		"text": "One long nylon shell from the waist to the skates in place of pants and socks, striped down the side, as a few teams wore in the early '80s. For one player in Create Player, or a whole team in Create Team."},
	{"id": "extra_bighead", "cat": "extras", "extra": "bighead", "name": "Big Head Mode", "price": 400,
		"text": "Everyone on the ice gets a giant head: skaters, goalies and the referee, in games and in Knockout Mode."},
	{"id": "extra_rainbow", "cat": "extras", "extra": "rainbow", "name": "Rainbow Puck", "price": 300,
		"text": "The puck leaves a rainbow trail behind it."},
	{"id": "extra_bigpuck", "cat": "extras", "extra": "bigpuck", "name": "Big Puck", "price": 250,
		"text": "A puck twice the size. Easier to follow, and it plays just the same."},
	{"id": "extra_glass", "cat": "extras", "extra": "glass", "name": "Breakaway Glass", "price": 400,
		"text": "Every big hit into the boards puts someone through the glass, as often as you like."},
	{"id": "extra_retro", "cat": "extras", "extra": "retro", "name": "Retro Broadcast", "price": 300,
		"text": "The game the way an old tube TV showed it: scan lines, soft color and a rounded picture."},
]

## What each lockable thing is sold as: arena styles, goalie mask models (GoalieVisual.MASKS
## index) and head gear (SkaterVisual.TEAM_MASKS key).
const RINK_ITEMS := {"community": "rink_community", "outdoor": "rink_outdoor"}
const MASK_ITEMS := {1: "mask_cage", 3: "mask_molded"}
const OLDTIME := "gear_oldtime"
const LONGPANTS := "gear_longpants"          ## long pants (SkaterVisual.PANTS_LONG)
const HELMET_ITEMS := {2: "helmet_bucket"}   ## skater helmet models (SkaterVisual.HELMETS index)
const FACE_ITEM := "face_full"               ## the cage and the full shield (SkaterVisual.FACE_GEAR)
const FACE_ITEMS := {"shield": FACE_ITEM, "cage": FACE_ITEM, "alien": "gear_grays"}   ## each face gear's item
## Face gear as Create Team lists it for a whole team ("" first: each player their own).
const TEAM_FACES := ["", "shield", "cage", "alien"]
const TEAM_FACE_NAMES := ["Each Their Own", "Full Shields", "Cages", "Alien Visors"]
const TINT_ITEM := "visor_tints"             ## every visor tint but clear (SkaterVisual.VISOR_TINTS)
const HEADGEAR_ITEMS := {"vintage": "gear_vintage", "lucha": "gear_lucha", "none": OLDTIME, "leather": OLDTIME, "guard": OLDTIME, "beanie": "gear_beanie", "florida": "gear_florida", "cowboy": "gear_cowboy", "stunt": "gear_stunt", "watch": "gear_watch", "golf": "gear_golf"}
const HEADGEAR := ["", "vintage", "lucha", "none", "leather", "guard", "florida", "cowboy", "stunt", "watch", "golf", "beanie"]
const HEADGEAR_NAMES := ["None", "Vintage Face Mask", "Lucha Hood", "Bare Head", "Leather Helmet", "Leather Hockey Helmet", "Cap & Shades", "Cowboy Hat", "Stunt Helmet", "Watch Cap", "Golf Visor", "Pom Beanie"]
## Cosmetics (SkaterVisual.CRESTS / EYE_FX / DANGLERS keys) and the item each comes with.
const COSMETIC_ITEMS := {"spines": "gear_chupa", "red": "gear_chupa", "fangs": "gear_chupa"}

## The shop tab to open on (the screen sets it when it leaves for a challenge game).
static var shop_tab := ""
## The main menu list the shop goes back to ("" = the main list; "extras" when it was
## opened from GAME EXTRAS > UNLOCKABLES).
static var shop_back := ""
static var _all := -1   ## `-- unlockall` (1 / 0; -1: not looked yet)
static var _oldtime := -1   ## `-- oldtime`, likewise


static func in_category(cat: String) -> Array:
	return ITEMS.filter(func(it: Dictionary) -> bool: return it.cat == cat)


static func item(id: String) -> Dictionary:
	for it: Dictionary in ITEMS:
		if it.id == id:
			return it
	return {}


static func owns(id: String) -> bool:
	return Profile.owns(id)


static func can_afford(id: String) -> bool:
	return int(item(id).get("price", 0)) <= Profile.pucks()


## Buys the item if it isn't owned and the pucks are there.
static func buy(id: String) -> bool:
	var it := item(id)
	return not it.is_empty() and Profile.buy(id, int(it.price))


## Everything open for this run (`-- unlockall`).
static func all_open() -> bool:
	if _all < 0:
		_all = 1 if OS.get_cmdline_user_args().has("unlockall") else 0
	return _all == 1


static func rink_open(style: String) -> bool:
	return not RINK_ITEMS.has(style) or Profile.owns(RINK_ITEMS[style]) or all_open()


static func goalie_mask_open(index: int) -> bool:
	return not MASK_ITEMS.has(index) or Profile.owns(MASK_ITEMS[index]) or all_open()


static func helmet_open(index: int) -> bool:
	return not HELMET_ITEMS.has(index) or Profile.owns(HELMET_ITEMS[index]) or all_open()


static func face_gear_open() -> bool:
	return Profile.owns(FACE_ITEM) or all_open()


## One piece of face gear (a SkaterVisual.FACE_GEAR key) is bought.
static func face_open(kind: String) -> bool:
	return not FACE_ITEMS.has(kind) or Profile.owns(FACE_ITEMS[kind]) or all_open()


## [values, names] of the face gear Create Team may put on a whole team: what's owned,
## plus `keep` (what the team being edited already wears).
static func team_face_choices(keep := "") -> Array:
	var v := []
	var n := []
	for i in TEAM_FACES.size():
		if face_open(TEAM_FACES[i]) or TEAM_FACES[i] == keep:
			v.append(TEAM_FACES[i])
			n.append(TEAM_FACE_NAMES[i])
	return [v, n]


static func tints_open() -> bool:
	return Profile.owns(TINT_ITEM) or all_open()


static func cosmetic_open(value: String) -> bool:
	return not COSMETIC_ITEMS.has(value) or Profile.owns(COSMETIC_ITEMS[value]) or all_open()


## [values, names] of a cosmetic slot (CustomPlayers.COSMETICS) a Create screen may offer:
## what's owned, plus `keep` (what the thing being edited already has).
static func cosmetic_choices(slot: String, keep := "") -> Array:
	var all: Array = CustomPlayers.COSMETICS[slot]
	var v := []
	var n := []
	for i in (all[0] as Array).size():
		if cosmetic_open(all[0][i]) or all[0][i] == keep:
			v.append(all[0][i])
			n.append(all[1][i])
	return [v, n]


static func headgear_open(kind: String) -> bool:
	return not HEADGEAR_ITEMS.has(kind) or Profile.owns(HEADGEAR_ITEMS[kind]) or all_open()


## [values, names] of the head gear a Create screen may offer: what's owned, plus `keep`
## (what the thing being edited already wears).
static func headgear_choices(keep := "") -> Array:
	var v := []
	var n := []
	for i in HEADGEAR.size():
		if headgear_open(HEADGEAR[i]) or HEADGEAR[i] == keep:
			v.append(HEADGEAR[i])
			n.append(HEADGEAR_NAMES[i])
	return [v, n]


## Every team wears the Old-Time Set this run (`-- oldtime`; Teams.uniform_of applies it).
static func oldtime_run() -> bool:
	if _oldtime < 0:
		_oldtime = 1 if OS.get_cmdline_user_args().has("oldtime") else 0
	return _oldtime == 1


## The Old-Time Set is bought (or `-- unlockall`).
static func oldtime_open() -> bool:
	return Profile.owns(OLDTIME) or all_open()


## [values, names] for a Create screen's row that offers one old-time piece: `standard`
## ("" = the usual gear), and `old` (SkaterVisual.OLD) once the set is bought or where it
## is `keep` (what the thing being edited already has).
static func oldtime_choices(keep := "", standard := "Standard", old := "Old-Time") -> Array:
	if oldtime_open() or keep == SkaterVisual.OLD:
		return [["", SkaterVisual.OLD], [standard, old]]
	return [[""], [standard]]


static func longpants_open() -> bool:
	return Profile.owns(LONGPANTS) or all_open()


## [values, names] for a Create screen's socks row: the usual knit, taped, and the Old-Time
## Set's wool once the set is bought or where it is `keep`.
static func sock_choices(keep := "") -> Array:
	var v := ["", SkaterVisual.SOCKS_TAPED]
	var n := ["Standard", "Taped"]
	if oldtime_open() or keep == SkaterVisual.OLD:
		v.append(SkaterVisual.OLD)
		n.append("Wool")
	return [v, n]


## ... and its pants row: the usual shell, the Old-Time Set's canvas (`canvas` false leaves
## it out: for a whole team it comes with the kit) and long pants, each once bought or
## where it is `keep`.
static func pants_choices(keep := "", canvas := true) -> Array:
	var v := [""]
	var n := ["Standard"]
	if canvas and (oldtime_open() or keep == SkaterVisual.OLD):
		v.append(SkaterVisual.OLD)
		n.append("Canvas")
	if longpants_open() or keep == SkaterVisual.PANTS_LONG:
		v.append(SkaterVisual.PANTS_LONG)
		n.append("Long Pants")
	return [v, n]


# --- Extras ----------------------------------------------------------------------------

## The keys of the extras a game should apply: bought (or `-- unlockall`) and switched
## on, plus any named by `-- extras=`.
static func extras_on() -> Array:
	var out := []
	for it: Dictionary in ITEMS:
		if it.has("extra") and (Profile.owns(it.id) or all_open()) and Profile.extra_on(it.id):
			out.append(str(it.extra))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("extras="):
			for k: String in a.substr(7).split(",", false):
				if not (k in out):
					out.append(k)
	return out


# --- Teams -----------------------------------------------------------------------------

## The item a team (a Teams index) is sold as; "" for a team that was never locked.
static func team_item(team: int) -> String:
	if team < 0 or Teams.is_custom(team):
		return ""
	var call := str(Teams.base_team(team).get("call", ""))
	for it: Dictionary in ITEMS:
		if str(it.get("team", "")) == call:
			return it.id
	return ""


## The Teams index of a team item's team (-1 if it isn't one).
static func team_index(id: String) -> int:
	var call := str(item(id).get("team", ""))
	if call != "":
		for i in Teams.LIST.size():
			if str(Teams.LIST[i].get("call", "")) == call:
				return i
	return -1


## The team can be played as (and shows in the editors): never locked, or its challenge won.
static func team_open(team: int) -> bool:
	var id := team_item(team)
	return id == "" or Profile.team_unlocked(str(item(id).team)) or all_open()


## A team item whose challenge is bought and not won yet.
static func challenge_ready(id: String) -> bool:
	var it := item(id)
	return it.has("team") and Profile.owns(id) and not Profile.team_unlocked(str(it.team))


## A team item that's done with: bought and beaten.
static func team_unlocked(id: String) -> bool:
	var it := item(id)
	return it.has("team") and Profile.team_unlocked(str(it.team))


## Every team that can be played as, in menu order (Teams.menu_order).
static func open_teams() -> Array[int]:
	var out: Array[int] = []
	for i: int in Teams.menu_order():
		if team_open(i):
			out.append(i)
	return out


## `team` if it can be played as (and isn't `other`), else the first team that can.
static func open_team(team: int, other := -1) -> int:
	if team >= 0 and team < Teams.count() and team != other and team_open(team):
		return team
	for i: int in open_teams():
		if i != other:
			return i
	return 0
