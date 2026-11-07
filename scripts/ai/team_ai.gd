class_name TeamAI
extends RefCounted
## Assigns a role to every AI skater on a team each tick, based on who has the puck.
## The human-controlled skater is left out (unless they carry the puck), and the AI
## teammates fill the remaining roles in priority order.

enum Role { NONE, CARRIER, RECEIVE, SUPPORT_SLOT, SUPPORT_POINT, SUPPORT_POINT2, SUPPORT_NET, CHASE, PRESSURE, COVER_SLOT, COVER_MAN, CHANGE }

var team := 0
var skaters: Array[Skater] = []
var opponents: Array[Skater] = []
var goalie: Goalie
var opp_goalie: Goalie
var puck: Puck
var rink: Rink
var difficulty := 0.5     ## 0 = rookie .. 1 = legend
var offsides := true      ## stay onside: supporters wait outside the zone until the puck is in
var shootout := false
var bench_gate := Vector3.ZERO

var roles := {}           ## Skater -> Role
var marks := {}           ## Skater -> Skater (COVER_MAN target)


func _init(p_team: int, p_skaters: Array[Skater], p_opponents: Array[Skater], p_goalie: Goalie,
		p_puck: Puck, p_rink: Rink) -> void:
	team = p_team
	skaters = p_skaters
	opponents = p_opponents
	goalie = p_goalie
	puck = p_puck
	rink = p_rink


func role_of(s: Skater) -> Role:
	return roles.get(s, Role.NONE)


func attack_net() -> Net:
	return rink.attacked_net(team)


func defend_net() -> Net:
	return rink.defended_net(team)


func update() -> void:
	roles.clear()
	marks.clear()
	var free: Array[Skater] = []
	for s in skaters:
		if s.changing and not s.has_puck():
			roles[s] = Role.CHANGE
		elif not s.is_human or s.has_puck():
			free.append(s)
	var carrier := puck.carrier
	if carrier and carrier.team == team:
		if carrier in free:
			roles[carrier] = Role.CARRIER
			free.erase(carrier)
		_assign_support(free)
	elif carrier:
		if not (carrier is Goalie):
			_take_nearest(free, carrier.global_position, Role.PRESSURE)
		_take_nearest(free, defensive_slot(), Role.COVER_SLOT)
		_assign_marks(free, carrier)
	else:
		var rec := puck.intended_receiver
		if rec and rec.team == team and rec in free:
			roles[rec] = Role.RECEIVE
			free.erase(rec)
		elif not (rec and rec.team == team):
			_take_nearest(free, puck.global_position, Role.CHASE)
		if _puck_in_defensive_half():
			_take_nearest(free, defensive_slot(), Role.COVER_SLOT)
			_assign_marks(free, null)
		else:
			_assign_support(free)


## Offense without the puck: defensemen take the points, forwards the slot and net front.
func _assign_support(free: Array[Skater]) -> void:
	var d_men := free.filter(func(s: Skater) -> bool: return s.is_defense)
	var fwds := free.filter(func(s: Skater) -> bool: return not s.is_defense)
	var d_roles := [Role.SUPPORT_POINT, Role.SUPPORT_POINT2]
	var f_roles := [Role.SUPPORT_SLOT, Role.SUPPORT_NET, Role.SUPPORT_POINT2, Role.SUPPORT_POINT]
	for s in d_men:
		var r: Role = d_roles.pop_front() if not d_roles.is_empty() else f_roles.pop_back()
		roles[s] = r
		f_roles.erase(r)
	for s in fwds:
		roles[s] = f_roles.pop_front() if not f_roles.is_empty() else Role.SUPPORT_POINT


func _take_nearest(free: Array[Skater], point: Vector3, role: Role) -> void:
	var best: Skater = null
	var best_d := INF
	for s in free:
		if s.is_down():
			continue
		var d := s.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = s
	if best == null and not free.is_empty():
		best = free[0]
	if best:
		roles[best] = role
		free.erase(best)


func _assign_marks(free: Array[Skater], carrier: Skater) -> void:
	var dn := defend_net().global_position
	var targets := opponents.filter(func(o: Skater) -> bool: return o != carrier)
	targets.sort_custom(func(a: Skater, b: Skater) -> bool:
		return a.global_position.distance_squared_to(dn) < b.global_position.distance_squared_to(dn))
	for s in free:
		roles[s] = Role.COVER_MAN
		if not targets.is_empty():
			marks[s] = targets.pop_front()


func _puck_in_defensive_half() -> bool:
	var p := puck.global_position
	return p.distance_squared_to(defend_net().global_position) < p.distance_squared_to(attack_net().global_position)


# --- Spots ---------------------------------------------------------------------------

## Open ice in front of the attacked net, on the far side from the puck.
func slot_spot() -> Vector3:
	var net := attack_net()
	var side := -signf(puck.global_position.x) if absf(puck.global_position.x) > 1.0 else 1.0
	return net.global_position + net.global_basis.z * 6.5 + Vector3(side * 2.5, 0, 0)


## High outlet near the blue line, on the puck's side.
func point_spot() -> Vector3:
	var net := attack_net()
	var side := signf(puck.global_position.x) if absf(puck.global_position.x) > 1.0 else -1.0
	return net.global_position + net.global_basis.z * 15.0 + Vector3(side * 5.0, 0, 0)


## The other point, opposite the puck.
func point2_spot() -> Vector3:
	var p := point_spot()
	var net := attack_net()
	return Vector3(net.global_position.x * 2.0 - p.x, 0, p.z)


## In front of the goalie for screens and rebounds.
func net_front_spot() -> Vector3:
	var net := attack_net()
	return net.global_position + net.global_basis.z * 2.6 + Vector3(signf(puck.global_position.x) * 0.8, 0, 0)


## Is the puck in the zone we attack?
func puck_in_attack_zone() -> bool:
	return MatchRules.zone_of(puck.global_position.z, RinkSpec.PUCK_RADIUS) == attack_net().index


## Keeps a support spot onside while the puck is outside the attacking zone.
func onside(p: Vector3) -> Vector3:
	if not offsides or puck_in_attack_zone():
		return p
	var line := RinkSpec.BLUE_LINE_Z - 0.8
	var sz := signf(attack_net().global_position.z)
	if p.z * sz > line:
		p.z = line * sz
	return p


## Between the puck and our net, in front of our goalie.
func defensive_slot() -> Vector3:
	var net := defend_net()
	var base := net.global_position + net.global_basis.z * 5.0
	return base + Vector3((puck.global_position.x - base.x) * 0.3, 0, 0)


## Goal side of the marked man.
func mark_spot(s: Skater) -> Vector3:
	var m: Skater = marks.get(s)
	if m == null:
		return defensive_slot()
	var to_net := defend_net().global_position - m.global_position
	to_net.y = 0.0
	return m.global_position + to_net.normalized() * 1.6


## Is `mate` a safe pass target from `from`? Returns openness (m), or -1 if the lane is blocked.
func pass_openness(from: Skater, mate: Skater) -> float:
	var open := INF
	var a := Vector2(from.global_position.x, from.global_position.z)
	var b := Vector2(mate.global_position.x, mate.global_position.z)
	for o in opponents:
		var p := Vector2(o.global_position.x, o.global_position.z)
		open = minf(open, p.distance_to(b))
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if t > 0.1 and t < 0.95 and p.distance_to(a + ab * t) < 1.1:
			return -1.0
	return open
