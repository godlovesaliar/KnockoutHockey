class_name Lineup
extends RefCounted
## A team's roster and who is on the ice: forward groups, defense groups, bench, penalty box.
##
## 5v5: forward lines of 3 and defense pairs of 2. 3v3: units of 2 forwards + 1 defenseman.
## `on_ice` is shared by reference with TeamAI and every skater's teammates/opponents
## lists, so it's only ever changed in place.

const MINOR := 120.0

var team := 0
var format := 5
var line_changes := true
var forwards: Array[Skater] = []
var defense: Array[Skater] = []
var goalie: Goalie
var f_groups: Array = []
var d_groups: Array = []
var cur_f := 0
var cur_d := 0
var pending := {false: -1, true: -1}   ## is_defense -> incoming group index for an on-the-fly change
var on_ice: Array[Skater] = []
var in_box := {}                       ## Skater -> seconds left
var offsetting := {}                   ## in the box without leaving the team short (fighting majors)
var injured: Array[Skater] = []        ## out for the game: off the lines, sitting on the bench


func all_skaters() -> Array[Skater]:
	var out: Array[Skater] = []
	out.append_array(forwards)
	out.append_array(defense)
	return out


func build_groups() -> void:
	f_groups.clear()
	d_groups.clear()
	var fs := 3 if format == 5 else 2
	var ds := 2 if format == 5 else 1
	for i in range(0, forwards.size(), fs):
		f_groups.append(forwards.slice(i, i + fs))
	for i in range(0, defense.size(), ds):
		d_groups.append(defense.slice(i, i + ds))


## (forwards, defense) on the ice for a given team strength.
func composition(strength: int) -> Vector2i:
	strength = clampi(strength, 3, 5)
	if format == 5:
		return [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)][strength - 3]
	return [Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2)][strength - 3]


## Rebuilds who's on the ice (at a faceoff). Forwards first, then defense. `extra`: more
## forwards on top (an extra attacker for a pulled goalie).
func fill(strength: int, extra := 0) -> void:
	var comp := composition(strength)
	var pick: Array[Skater] = []
	_take(pick, f_groups, cur_f, comp.x + extra)
	_take(pick, d_groups, cur_d, comp.y)
	on_ice.clear()
	on_ice.append_array(pick)
	pending = {false: -1, true: -1}
	for s in all_skaters():
		s.set_benched(not (s in on_ice))


func _take(pick: Array[Skater], groups: Array, start: int, n: int) -> void:
	var count := 0
	for k in groups.size():
		for s: Skater in groups[(start + k) % groups.size()]:
			if count >= n:
				return
			if in_box.has(s) or s in pick:
				continue
			pick.append(s)
			count += 1


## The freshest skater on the bench (not in the box): forwards first. Null if none.
func freshest_on_bench() -> Skater:
	for group: Array[Skater] in [forwards, defense]:
		var best: Skater = null
		for s in group:
			if s in on_ice or in_box.has(s) or s.injured:
				continue
			if best == null or s.energy > best.energy:
				best = s
		if best:
			return best
	return null


## Takes a skater off the roster for the rest of the game (injured) and rebuilds the
## lines without them. They stay on the bench.
func remove_skater(s: Skater) -> void:
	on_ice.erase(s)
	in_box.erase(s)
	offsetting.erase(s)
	forwards.erase(s)
	defense.erase(s)
	if not s in injured:
		injured.append(s)
	build_groups()
	cur_f = cur_f % maxi(f_groups.size(), 1)
	cur_d = cur_d % maxi(d_groups.size(), 1)
	pending = {false: -1, true: -1}


func forwards_on_ice() -> Array[Skater]:
	return on_ice.filter(func(s: Skater) -> bool: return not s.is_defense)


func defense_on_ice() -> Array[Skater]:
	return on_ice.filter(func(s: Skater) -> bool: return s.is_defense)


func avg_energy(list: Array) -> float:
	if list.is_empty():
		return 1.0
	var e := 0.0
	for s: Skater in list:
		e += s.energy
	return e / list.size()


func _most_rested(groups: Array, current: int) -> int:
	var best := current
	var best_e := -1.0
	for i in groups.size():
		if i == current:
			continue
		var avail: Array = groups[i].filter(func(s: Skater) -> bool: return not in_box.has(s))
		if avail.is_empty():
			continue
		var e := avg_energy(avail)
		if e > best_e:
			best_e = e
			best = i
	return best


## At a stoppage: send out fresh legs if the current group is tired.
func choose_fresh() -> void:
	if not line_changes:
		return
	if avg_energy(f_groups[cur_f]) < 0.75:
		cur_f = _most_rested(f_groups, cur_f)
	if avg_energy(d_groups[cur_d]) < 0.7:
		cur_d = _most_rested(d_groups, cur_d)


## Live: tired skaters of one kind start heading to the bench. Returns true if a change began.
func plan_change(defense_kind: bool) -> bool:
	if not line_changes or pending[defense_kind] >= 0:
		return false
	var groups := d_groups if defense_kind else f_groups
	var cur := cur_d if defense_kind else cur_f
	var mine := defense_on_ice() if defense_kind else forwards_on_ice()
	var next := _most_rested(groups, cur)
	if next == cur or avg_energy(groups[next]) < avg_energy(mine) + 0.25:
		return false
	pending[defense_kind] = next
	for s in mine:
		if not s.is_human:
			s.changing = true
	return true


## A changing skater reached the bench gate: swap in a fresh one. Returns the new skater.
func swap_at_gate(s: Skater) -> Skater:
	var kind := s.is_defense
	var g: int = pending[kind]
	if g < 0:
		s.changing = false
		return null
	var incoming: Skater = null
	var groups := d_groups if kind else f_groups
	for c: Skater in groups[g]:
		if not (c in on_ice) and not in_box.has(c):
			incoming = c
			break
	if incoming == null:
		s.changing = false
		return null
	var idx := on_ice.find(s)
	on_ice[idx] = incoming
	s.set_benched(true)
	incoming.set_benched(false)
	var any_left := on_ice.any(func(o: Skater) -> bool: return o.changing and o.is_defense == kind)
	if not any_left:
		if kind:
			cur_d = g
		else:
			cur_f = g
		pending[kind] = -1
	return incoming


## Benched skaters (not in the box) get their legs back.
func recover(delta: float) -> void:
	for s in all_skaters():
		if s.benched and not in_box.has(s):
			s.energy = minf(1.0, s.energy + delta / 25.0)


## `counts` = false for offsetting penalties (fighting majors): the team replaces the
## player, so it doesn't play short.
func send_to_box(s: Skater, seconds := MINOR, counts := true) -> void:
	in_box[s] = seconds
	if counts:
		offsetting.erase(s)
	else:
		offsetting[s] = true
	if s in on_ice:
		on_ice.erase(s)
	s.set_benched(true)


## Ticks box time; returns skaters whose penalties just expired.
func tick_box(delta: float) -> Array[Skater]:
	var out: Array[Skater] = []
	for s in in_box.keys():
		in_box[s] -= delta
		if in_box[s] <= 0.0:
			in_box.erase(s)
			offsetting.erase(s)
			out.append(s)
	return out


## Power-play goal against: the minor with the least time left ends.
func release_earliest() -> Skater:
	var best: Skater = null
	for s in in_box.keys():
		if offsetting.has(s):
			continue
		if best == null or in_box[s] < in_box[best]:
			best = s
	if best:
		in_box.erase(best)
	return best


func box_count() -> int:
	return in_box.size() - offsetting.size()


func box_time_left() -> float:
	var t := 0.0
	for s in in_box:
		if not offsetting.has(s):
			t = maxf(t, in_box[s])
	return t
