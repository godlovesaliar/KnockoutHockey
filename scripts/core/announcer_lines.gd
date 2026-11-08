class_name AnnouncerLines
## Every announcer line the game calls, grouped by category: who says it, the other file
## names that count as its takes, and when it plays.
##
## Two voices share the booth (one talks at a time):
##   pbp    Steve Sheldon, play-by-play: calm, British. Calls what's happening.
##   color  Bobby Niedemyer, color commentary: loud, boisterous. Reacts and remarks.
##   both   the two of them in one clip, talking to each other (ElevenLabs dialogue).
## Files: assets/sound/announcer/pbp/ (Steve), assets/sound/announcer/color/ (Bobby),
## assets/sound/announcer/both/ (duets). The announcer/ folder itself holds the original
## recordings, which are Bobby's.
## A line's takes from every voice share one pool: Bobby's original play-by-play takes
## keep playing alongside Steve's, and a duet can be a take of any line
## (both/save_01.mp3 joins the saves). A line's voice says who should record its
## new takes; "both" lines (the banter) are written as duets.
##
## File names: <line>.mp3, <line>2.mp3, <line>_01.mp3 ... (trailing digits and an
## underscore before them mark another take). `also` lists other names whose files join
## the line's takes: the names data/hockey_announcer_lines.csv uses (hit_01 -> bighit)
## and older recordings. An `also` entry that ends in a digit is an exact file name
## (period2.mp3), since its digit is part of the line rather than a take number.
##
## `tools/announcer_check.gd` prints how many takes each line has against TARGET.

const TARGET := 3   ## takes per line we want, so repeats don't stand out
const VOICES := {
	"pbp": {"name": "Steve Sheldon", "role": "play-by-play", "dir": "pbp/"},
	"color": {"name": "Bobby Niedemyer", "role": "color", "dir": "color/"},
	"both": {"name": "Steve & Bobby", "role": "duets", "dir": "both/"},
}
const SOLO := ["pbp", "color"]
const LEGACY_VOICE := "color"   ## whose files sit in announcer/ itself

## [category, [[line, voice, also, when it plays], ...]]
const GROUPS := [
	["Game flow", [
		["intro", "pbp", [], "as the matchup screen closes, only if no duet welcome is recorded"],
		["intro_duet", "both", ["doubleintro"], "every game, as the matchup screen closes (Steve and Bobby welcome everyone; stands in for the first period's call)"],
		["newperiod", "pbp", ["period_start"], "the first period starts (and any period without its own line)"],
		["second_period", "pbp", ["period2", "secondperiod"], "the second period starts"],
		["third_period", "pbp", ["period3", "thirdperiod"], "the third period starts"],
		["third_stakes", "color", [], "after the third period's call (\"Twenty minutes to decide it.\")"],
		["overtime", "pbp", [], "overtime starts"],
		["shootout", "pbp", [], "the shootout starts"],
		["final_minute", "pbp", ["oneminute"], "one minute left in the last period"],
		["periodend", "pbp", ["period_end"], "a period ends (not the game)"],
		["final_horn", "pbp", [], "the game ends"],
		["final_react", "pbp", [], "after the final horn call (\"What a game, folks.\")"],
	]],
	["Faceoffs", [
		["faceoff", "pbp", [], "players line up for a faceoff"],
		["centerice", "pbp", [], "the faceoff after a goal"],
		["faceoff_win", "pbp", [], "someone wins the draw"],
		["faceoff_loss", "pbp", [], "the player's team loses the draw"],
	]],
	["Puck movement", [
		["pass", "pbp", [], "a pass, now and then"],
		["pass_point", "pbp", [], "a pass back to a defender at the blue line (\"back to the point\")"],
		["dumpin", "pbp", [], "the puck is shot in from outside the offensive zone"],
		["downice", "pbp", [], "a carrier crosses center at speed (\"carrying it up the ice\")"],
		["blueline", "pbp", [], "a forward carries the puck into the offensive zone"],
		["defenderup", "pbp", [], "a defender carries the puck into the offensive zone"],
		["boards_carry", "pbp", ["boardscarry"], "a carrier skates along the boards"],
		["behindnet", "pbp", [], "a carrier goes behind the other team's net"],
		["setup", "pbp", [], "a carrier holds the puck in the zone, looking for an opening"],
		["cycle", "pbp", [], "quick passes low in the offensive zone"],
		["deke", "pbp", [], "a carrier dekes"],
		["breakaway", "pbp", [], "a carrier is alone in on the goalie"],
		["pokecheck", "pbp", [], "a poke check knocks the puck away"],
		["turnover", "pbp", [], "the puck goes straight from one team's carrier to the other's"],
		["checking", "pbp", [], "possession keeps flipping (\"they're really fighting for it!\")"],
	]],
	["Shots", [
		["shot", "pbp", [], "a shot (any kind)"],
		["shot_wrist", "pbp", [], "a wrist shot"],
		["shot_point", "pbp", [], "a defender shoots from the blue line"],
		["fullslapshot", "pbp", ["slapshot"], "a hard slap shot"],
		["onetimer", "pbp", [], "a one-timer"],
		["miss", "pbp", [], "a shot goes wide or over"],
		["post", "pbp", [], "a shot rings the post"],
		["block", "pbp", [], "a skater blocks a shot"],
		["rebound", "pbp", [], "a loose puck in the crease after a save"],
	]],
	["Saves", [
		["save", "pbp", [], "a save"],
		["save_pad", "pbp", [], "a pad save that kicks the puck out"],
		["save_glove", "pbp", [], "a glove save"],
		["bigsave", "pbp", ["save_big"], "a glove save or a save on a breakaway (\"Robbed!\")"],
		["save_react", "color", [], "after a big save call (\"What a save!\")"],
	]],
	["Goals", [
		["goal", "pbp", [], "a goal"],
		["goal_topshelf", "pbp", [], "a goal up high"],
		["goal_calm", "pbp", [], "a goal by a team already up three or more"],
		["goal_tie", "pbp", [], "after a goal that ties it"],
		["goal_lead", "pbp", [], "after a goal that breaks a tie"],
		["goal_insurance", "color", [], "after a goal that makes it a two-goal lead in the last period"],
		["goal_hattrick", "pbp", [], "after a player's third goal"],
		["goal_powerplay", "pbp", [], "after a power-play goal"],
		["goal_shorthanded", "pbp", [], "after a short-handed goal"],
		["goal_comeback", "pbp", [], "after a goal that erases a deficit of two or more"],
		["goal_react", "color", [], "after a goal, when nothing above fits"],
		["goal_react_home", "pbp", [], "after a home goal (\"The crowd goes wild!\")"],
	]],
	["Hits and fights", [
		["check", "pbp", [], "a regular check"],
		["bighit", "pbp", ["hit", "flattened"], "a big hit"],
		["hit_boards", "pbp", [], "a big hit into the boards"],
		["hit_react", "color", ["gottahurt"], "after a big hit call (\"Ooh, felt that one!\")"],
		["bighitenforcer", "color", [], "after a big hit by a defender or heavy hitter"],
		["fighting", "pbp", ["fight"], "a fight starts"],
	]],
	["Penalties and whistles", [
		["penalty", "pbp", [], "a penalty (any kind without its own line)"],
		["trippingcall", "pbp", ["penalty_trip"], "a tripping penalty"],
		["bigpenalty", "pbp", ["penalty_boarding"], "a boarding penalty"],
		["interference", "pbp", ["penalty_interference"], "an interference penalty"],
		["powerplay", "pbp", [], "a team goes on the power play"],
		["pk_success", "pbp", [], "a penalty is killed off"],
		["whistle", "pbp", [], "a whistle for a frozen puck or a puck out of play"],
		["icing", "pbp", [], "icing"],
		["offsides", "pbp", [], "offside"],
	]],
	["Color commentary", [
		["idle", "color", [], "a long quiet spell"],
		["hot_streak", "color", [], "one team takes four shots in a row"],
		["close_game", "color", [], "late in a one-goal or tied game"],
		["blowout", "color", [], "a team is up by four or more"],
		["crowdreactgood", "color", ["doublecrowdpositive"], "the home crowd keeps cheering"],
		["crowdreactbad", "color", [], "the home crowd keeps booing"],
	]],
	["Banter (Steve and Bobby together)", [
		["banter", "both", [], "a long quiet spell, in place of Bobby's idle remarks now and then"],
		["banter_intermission", "both", [], "after a period ends, while the teams head off (recap the period)"],
		["banter_penalty", "both", [], "after a penalty call, in place of the power-play line now and then (Bobby disputes it)"],
		["banter_fight", "both", [], "after a fight ends"],
		["banter_goal", "both", [], "after a goal, when nothing more specific fits"],
		["banter_hit", "both", [], "after a big hit, in place of Bobby's reaction now and then"],
		["banter_blowout", "both", [], "when a team is up by four or more, in place of the blowout line now and then"],
		["banter_close", "both", [], "late in a close game, in place of the close-game line now and then"],
		["banter_final", "both", [], "after the final horn, in place of Bobby's wrap-up now and then"],
	]],
]

## Lines the CSV has that nothing in the game calls (no such penalty yet).
const UNUSED := ["penalty_hook", "penalty_slash", "penalty_rough", "penalty_highstick"]

static var _alias_cache := {}
static var _voice_cache := {}


## other file name (take digits stripped) -> line
static func aliases() -> Dictionary:
	if _alias_cache.is_empty():
		for g: Array in GROUPS:
			for l: Array in g[1]:
				for a: String in l[2]:
					_alias_cache[a] = l[0]
	return _alias_cache


## Who says the line ("pbp" / "color"; lines not listed: the original voice).
static func voice_of(line: String) -> String:
	if _voice_cache.is_empty():
		for g: Array in GROUPS:
			for l: Array in g[1]:
				_voice_cache[l[0]] = l[1]
	return _voice_cache.get(line, LEGACY_VOICE)


## The line a file belongs to (`base`: the file name without its extension).
static func line_for_file(base: String) -> String:
	base = base.to_lower()
	var al := aliases()
	if al.has(base):
		return al[base]   # exact names like period2
	var line := base
	while line.length() > 1 and line.right(1).is_valid_int():
		line = line.left(-1)
	line = line.trim_suffix("_")
	return al.get(line, line)
