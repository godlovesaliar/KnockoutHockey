class_name MatchRules
extends RefCounted
## Linesman + referee logic: delayed offsides, no-touch icing, and delayed penalties.
## The director feeds it puck events and ticks it during live play; it calls
## `director.whistle(reason, dot, text)` when play should stop.
##
## Zones: a net's "zone" is beyond the blue line on that net's side. The team attacking
## that net is offside if a teammate is fully in the zone before the puck crosses.

const IN_ZONE := RinkSpec.BLUE_LINE_Z + RinkSpec.LINE_WIDE * 0.5

var d: MatchDirector
var offsides := true
var icing := true
var penalties := true

var offside_team := -1     ## team with a delayed offside (linesman's arm up), -1 = none
var offside_zone := -1     ## net index of that zone
var icing_team := -1       ## team whose untouched clear could become icing
var icing_net := -1        ## the net index whose goal line it must cross
var pending := [null, null] ## per team: {offender: Skater, kind: StringName} delayed penalty

var _puck_zone := -1


func _init(director: MatchDirector) -> void:
	d = director


func reset() -> void:
	offside_team = -1
	offside_zone = -1
	icing_team = -1
	icing_net = -1
	_puck_zone = _zone_of_puck()


## Net index whose zone contains z (margin = how far past the line counts as "in"), else -1.
static func zone_of(z: float, margin := 0.0) -> int:
	if z > IN_ZONE + margin:
		return 0
	if z < -(IN_ZONE + margin):
		return 1
	return -1


func _zone_of_puck() -> int:
	return zone_of(d.puck.global_position.z, RinkSpec.PUCK_RADIUS)


func _attackers_in_zone(team: int, zone: int, except: Skater = null) -> bool:
	for s in d.lineup(team).on_ice:
		if s != except and zone_of(s.global_position.z, 0.2) == zone:
			return true
	return false


func tick() -> void:
	var pz := _zone_of_puck()
	if offsides:
		if pz != _puck_zone and pz != -1:
			var att := 1 - d.rink.team_defending(pz)
			var last: Skater = d.puck.carrier if d.puck.carrier else d.puck.last_touch
			if last and last.team == att and _attackers_in_zone(att, pz, d.puck.carrier):
				offside_team = att
				offside_zone = pz
		if offside_team >= 0:
			if pz != offside_zone or not _attackers_in_zone(offside_team, offside_zone):
				offside_team = -1 # puck left the zone, or everyone tagged up
	_puck_zone = pz

	if icing and icing_team >= 0:
		var p := d.puck.global_position
		var net := d.rink.get_net(icing_net)
		if absf(p.z) > RinkSpec.GOAL_LINE_Z + RinkSpec.PUCK_RADIUS and signf(p.z) == signf(net.global_position.z) \
				and absf(p.x) > RinkSpec.NET_WIDTH * 0.5 + 0.2:
			var t := icing_team
			icing_team = -1
			d.whistle(&"icing", end_dot(t, p.x), "ICING")
		elif d.puck.speed() < 0.8 and d.puck.carrier == null:
			icing_team = -1


func on_touched(s: Skater) -> void:
	icing_team = -1
	if d.phase != MatchDirector.Phase.LIVE:
		return
	if pending[s.team] != null:
		d.whistle(&"penalty", Vector2.ZERO, "")
		return
	if offside_team >= 0 and s.team == offside_team and _zone_of_puck() == offside_zone:
		var zone := offside_zone
		offside_team = -1
		var zsign := 1.0 if zone == 0 else -1.0
		var x := RinkSpec.END_DOT_X * (signf(d.puck.global_position.x) if absf(d.puck.global_position.x) > 0.1 else 1.0)
		d.whistle(&"offside", Vector2(x, zsign * RinkSpec.NEUTRAL_DOT_Z), "OFFSIDE")


func on_released(by: Skater, at: Vector3) -> void:
	if not icing or d.phase != MatchDirector.Phase.LIVE:
		return
	var t := by.team
	var own := signf(d.rink.defended_net(t).global_position.z)
	if signf(at.z) == own and absf(at.z) > 0.3 and d.strength(t) >= d.strength(1 - t):
		icing_team = t
		icing_net = d.rink.attacked_net(t).index
	else:
		icing_team = -1


## End-zone dot in team t's defensive zone, on the side of x.
func end_dot(t: int, x: float) -> Vector2:
	var z := signf(d.rink.defended_net(t).global_position.z) * RinkSpec.END_DOT_Z
	return Vector2(RinkSpec.END_DOT_X * (1.0 if x >= 0.0 else -1.0), z)


## A foul the referee decided to call. Returns true if it's delayed (offended team has the puck).
func call_penalty(offender: Skater, kind: StringName) -> bool:
	var t := offender.team
	if pending[t] != null:
		return true
	pending[t] = {"offender": offender, "kind": kind}
	var c := d.puck.carrier
	if c and c.team == t:
		d.whistle(&"penalty", Vector2.ZERO, "")
		return false
	return true


func has_delayed_penalty() -> bool:
	return pending[0] != null or pending[1] != null
