class_name Pucks
## Pucks, the game's currency: what a finished game or Knockout Mode card pays the player
## (into Profile). Nothing is paid during play; the receipt is worked out at the end from
## the match's stats and shown on the payout screen (PayoutScreen).
##
## Only games with a human in them pay, and only when they're played to the end. With
## humans on both teams (versus) the winning side's game pays, with no difficulty bonus.
##
## A receipt: {mode, lines: [{label, detail, amount}], total, first_win (team code or ""),
## unlock (the `call` of a team this game unlocked, or "") with unlock_team (its Teams
## index), and once banked: before, after (the balance)}.

const FINISH := 50          ## playing a game to the end...
const WIN := 100            ## ...winning it...
const SHUTOUT := 50         ## ...without giving up a goal (these three scale with the game's length)
const GOAL := 10
const GOAL_CAP := 10        ## goals that pay, per game
const HAT_TRICK := 50       ## per player with three or more
const BIG_HIT := 5
const BIG_HIT_CAP := 10
const FIGHT_WIN := 40
const FIGHT_KO := 20        ## on top, for a knockout
const GLASS := 25           ## putting someone through the glass...
const GLASS_CAP := 2        ## ...the first two panes of a game (the Breakaway Glass extra breaks many more)
const FIRST_WIN := 100      ## the first win over each league team (once ever, no multiplier)
const CHALLENGE_WIN := 200  ## winning a locked team's challenge (Store): the game that unlocks them
## Knockout Mode.
const KO_FINISH := 25
const KO_BOUT := 25
const KO_BOUT_KO := 15
const KO_SERIES := 100
## The flat bonuses are for a game of this many seconds of regulation (3 x 3:00); shorter
## and longer games pay them in proportion, within LENGTH_RANGE.
const BASE_LENGTH := 540.0
const LENGTH_RANGE := Vector2(0.33, 2.0)


## "12,345".
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## What the CPU difficulty multiplies a game's pay by: Rookie x0.5, Pro x1, All-Star x1.3,
## Legend x1.5.
static func difficulty_mult(d: float) -> float:
	var m := lerpf(0.5, 1.0, clampf(inverse_lerp(0.2, 0.5, d), 0.0, 1.0)) if d <= 0.5 \
			else lerpf(1.0, 1.5, clampf(inverse_lerp(0.5, 0.95, d), 0.0, 1.0))
	return snappedf(m, 0.1)


## The receipt for a finished game (not banked yet).
static func game_receipt(d: MatchDirector) -> Dictionary:
	var winner := -1 if d.score[0] == d.score[1] else (0 if d.score[0] > d.score[1] else 1)
	var t := d.human_team()
	var versus := t < 0
	if versus:
		t = maxi(winner, 0)
	var s := d.stats
	var length := clampf(d.periods * d.period_length / BASE_LENGTH, LENGTH_RANGE.x, LENGTH_RANGE.y)
	var note := "" if is_equal_approx(length, 1.0) else ("SHORT GAME" if length < 1.0 else "LONG GAME")
	var lines: Array = []
	_line(lines, "GAME FINISHED", note, roundi(FINISH * length))
	if winner == t:
		_line(lines, "WIN", note, roundi(WIN * length))
		if d.score[1 - t] == 0:
			_line(lines, "SHUTOUT", note, roundi(SHUTOUT * length))
	var goals := 0   # (not the score: a shootout win adds one to it)
	for g: int in s.period_goals[t]:
		goals += g
	_count(lines, "GOALS", goals, GOAL, GOAL_CAP)
	var hat_tricks := 0
	for sk in d.lineup(t).all_skaters():
		if int(d.box.rec(sk).g) >= 3:
			hat_tricks += 1
	_count(lines, "HAT TRICK" if hat_tricks == 1 else "HAT TRICKS", hat_tricks, HAT_TRICK)
	_count(lines, "BIG HITS", s.big_hits[t], BIG_HIT, BIG_HIT_CAP)
	_count(lines, "FIGHTS WON", s.fight_wins[t], FIGHT_WIN)
	_count(lines, "KNOCKOUTS", s.fight_kos[t], FIGHT_KO)
	_count(lines, "GLASS BROKEN", s.glass[t], GLASS, GLASS_CAP)
	if not versus:
		_multiply(lines, "CPU DIFFICULTY", difficulty_mult(d.difficulty))
	var first := ""
	var opp: int = d.team_ids[1 - t]
	if not versus and winner == t and not Teams.is_custom(opp):
		var info := Teams.team(opp)
		if not Profile.has_beaten(str(info.abbr)):
			first = str(info.abbr)
			_line(lines, "FIRST WIN OVER THE %s" % str(info.name).to_upper(), "", FIRST_WIN)
	# A challenge won: the team is unlocked when the receipt is banked.
	var unlock := ""
	if d.challenge_won():
		var call := str(Teams.base_team(d.challenge).get("call", ""))
		if call != "" and not Profile.team_unlocked(call):
			unlock = call
			_line(lines, "CHALLENGE WON", "", CHALLENGE_WIN)
	return {"mode": "CHALLENGE" if d.challenge >= 0 else "EXHIBITION", "lines": lines, "total": _total(lines),
			"first_win": first, "unlock": unlock, "unlock_team": d.challenge if unlock != "" else -1}


## The receipt for a finished Knockout Mode card (not banked yet).
static func knockout_receipt(km: KnockoutMode) -> Dictionary:
	var winner := 0 if km.score[0] > km.score[1] else 1
	var t := km.director.human_team()
	if t < 0:
		t = winner
	var wins := 0
	var kos := 0
	for r: Dictionary in km.results:
		if r.winner != null and r.winner.team == t:
			wins += 1
			if r.ko:
				kos += 1
	var lines: Array = []
	_line(lines, "CARD FINISHED", "", KO_FINISH)
	_count(lines, "BOUTS WON", wins, KO_BOUT)
	_count(lines, "KNOCKOUTS", kos, KO_BOUT_KO)
	if winner == t:
		_line(lines, "SERIES WON", "", KO_SERIES)
	return {"mode": "KNOCKOUT MODE", "lines": lines, "total": _total(lines), "first_win": "", "unlock": "", "unlock_team": -1}


## Pays a receipt into the profile; adds the balance `before` and `after` to it.
static func bank(r: Dictionary) -> Dictionary:
	r.before = Profile.pucks()
	if str(r.get("first_win", "")) != "":
		Profile.mark_beaten(str(r.first_win))
	if str(r.get("unlock", "")) != "":
		Profile.unlock_team(str(r.unlock))
	Profile.add_pucks(int(r.total))
	r.after = Profile.pucks()
	return r


static func _line(lines: Array, label: String, detail: String, amount: int) -> void:
	lines.append({"label": label, "detail": detail, "amount": amount})


## `n` of something at `each`; only the first `cap` pay (0 = no cap). Nothing for none.
static func _count(lines: Array, label: String, n: int, each: int, cap := 0) -> void:
	if n <= 0:
		return
	var paid := mini(n, cap) if cap > 0 else n
	var detail := "%d × %d" % [paid, each]
	if paid < n:
		detail = "%d, FIRST %s" % [n, detail]
	_line(lines, label, detail, paid * each)


## A multiplier on everything so far, as a line worth the difference.
static func _multiply(lines: Array, label: String, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		return
	var sub := _total(lines)
	_line(lines, label, "×%s" % String.num(mult, 1), roundi(sub * mult) - sub)


static func _total(lines: Array) -> int:
	var sum := 0
	for l: Dictionary in lines:
		sum += int(l.amount)
	return sum
