class_name BoxScore
extends RefCounted
## Per-player game stats, kept by MatchDirector from its events: goals, assists, shots,
## hits, big hits, +/-, penalty minutes, fights; goalies' saves and goals against.
## `rating()` folds a line into one number (a simple game score), which picks the hot
## and cold players between periods (`hot_cold`, from what each did that period) and the
## three stars at the end (`stars`, from the whole game).

## Game-score weights.
const W := {"g": 1.0, "a": 0.7, "shots": 0.08, "hits": 0.06, "big_hits": 0.14, "pm": 0.18,
		"pim": -0.06, "fight_w": 0.45, "sv": 0.075, "ga": -0.55}

var _rec := {}           ## Skater -> line (Dictionary)
var _period_base := {}   ## Skater -> their line when the period started
var _chain: Array[Skater] = []   ## touches by the team that has the puck, newest last


func rec(s: Skater) -> Dictionary:
	if not _rec.has(s):
		_rec[s] = {"g": 0, "a": 0, "shots": 0, "hits": 0, "big_hits": 0, "pm": 0, "pim": 0,
				"fights": 0, "fight_w": 0, "sv": 0, "ga": 0}
	return _rec[s]


func add(s: Skater, key: String, n := 1) -> void:
	if s != null and is_instance_valid(s):
		rec(s)[key] += n


## Every puck touch: the chain of one team's touches gives the assists.
func on_touch(s: Skater) -> void:
	if s == null:
		return
	if not _chain.is_empty() and _chain[-1].team != s.team:
		_chain.clear()
	if _chain.is_empty() or _chain[-1] != s:
		_chain.append(s)
	if _chain.size() > 6:
		_chain.pop_front()


## A goal by `scorer`'s team: credits the goal, up to two assists (the teammates who
## touched it before the scorer, newest first) and +/- for the skaters on the ice
## (not on the power play). Returns the assists.
func on_goal(scorer: Skater, team: int, for_ice: Array, against_ice: Array, beaten: Goalie, pp: bool) -> Array[Skater]:
	var assists: Array[Skater] = []
	if scorer != null and scorer.team == team:
		add(scorer, "g")
		var i := _chain.size() - 1
		while i >= 0 and _chain[i] == scorer:
			i -= 1
		while i >= 0 and assists.size() < 2:
			var s := _chain[i]
			if s.team != team:
				break
			if s != scorer and not (s in assists):
				assists.append(s)
				add(s, "a")
			i -= 1
	if beaten != null:
		add(beaten, "ga")
	if not pp:
		for s: Skater in for_ice:
			if not (s is Goalie):
				add(s, "pm", 1)
		for s: Skater in against_ice:
			if not (s is Goalie):
				add(s, "pm", -1)
	_chain.clear()
	return assists


static func rating(line: Dictionary) -> float:
	var r := 0.0
	for k: String in W:
		r += float(line.get(k, 0)) * W[k]
	return r


func period_start() -> void:
	_period_base.clear()
	for s in _rec:
		_period_base[s] = _rec[s].duplicate()


## What `s` did in the current period (their line minus where it stood at its start).
func period_line(s: Skater) -> Dictionary:
	var now := rec(s)
	var base: Dictionary = _period_base.get(s, {})
	var out := {}
	for k: String in now:
		out[k] = now[k] - base.get(k, 0)
	return out


func period_rating(s: Skater) -> float:
	return rating(period_line(s))


## Top `n` players of the game, both teams (ties go to the winning team, then goals).
func stars(players: Array, winner: int, n := 3) -> Array[Skater]:
	var list: Array[Skater] = []
	for s: Skater in players:
		if is_instance_valid(s):
			list.append(s)
	list.sort_custom(func(x: Skater, y: Skater) -> bool:
		var rx := rating(rec(x)) + (0.05 if x.team == winner else 0.0)
		var ry := rating(rec(y)) + (0.05 if y.team == winner else 0.0)
		if absf(rx - ry) > 0.001:
			return rx > ry
		return rec(x).g > rec(y).g)
	return list.slice(0, n)


## [hot, cold] for one team's players over the period just played. Cold is only someone
## who did harm (a negative period); otherwise null.
func hot_cold(players: Array) -> Array:
	var best: Skater = null
	var worst: Skater = null
	for s: Skater in players:
		if not is_instance_valid(s):
			continue
		var r := period_rating(s)
		if best == null or r > period_rating(best):
			best = s
		if worst == null or r < period_rating(worst):
			worst = s
	if best != null and period_rating(best) <= 0.0:
		best = null
	if worst != null and period_rating(worst) >= 0.0:
		worst = null
	return [best, worst]


## A short stat line: "2 G · 1 A · +2 · 4 SHOTS" (goalies: "24 SV · 1 GA · .960").
## `r`: the line to show (default: the whole game).
func line_text(s: Skater, r := {}) -> String:
	if r.is_empty():
		r = rec(s)
	var parts: Array[String] = []
	if s is Goalie:
		parts.append("%d SV" % r.sv)
		parts.append("%d GA" % r.ga)
		if r.sv + r.ga > 0:
			parts.append(("%.3f" % (float(r.sv) / (r.sv + r.ga))).trim_prefix("0"))
		return " · ".join(parts)
	if r.g > 0:
		parts.append("%d G" % r.g)
	if r.a > 0:
		parts.append("%d A" % r.a)
	if r.pm != 0:
		parts.append("%+d" % r.pm)
	if r.shots > 0:
		parts.append("%d SHOT%s" % [r.shots, "" if r.shots == 1 else "S"])
	if r.hits > 0:
		parts.append("%d HIT%s" % [r.hits, "" if r.hits == 1 else "S"])
	if r.fight_w > 0:
		parts.append("FIGHT WIN")
	if r.pim > 0:
		parts.append("%d PIM" % r.pim)
	return " · ".join(parts) if not parts.is_empty() else "—"

