class_name RefBrain
extends Brain
## The referee follows the play the way NHL referees do: along the boards on the far side
## from the puck, a few meters deeper into the zone it's in (near the goal line in the
## end zones), facing it, and stepping aside from players who come close. During a
## cutscene MatchDirector sets `hold` to a spot to skate to and stay at instead.

var director: MatchDirector
var hold := Vector3.INF
var face_at := Vector3.INF   ## cutscenes: look this way instead of at the puck


func _init(d: MatchDirector) -> void:
	director = d


func update(s: Skater, i: SkaterIntent, _delta: float) -> void:
	var puck := director.puck
	var p := puck.global_position
	var look := face_at if face_at != Vector3.INF else p
	i.face = Vector3(look.x - s.global_position.x, 0.0, look.z - s.global_position.z)
	var target: Vector3
	if hold != Vector3.INF:
		target = hold
	else:
		# Far side boards, deeper toward the end the puck is in, held off the end boards.
		var side := -signf(p.x) if absf(p.x) > 1.0 else (signf(s.global_position.x) if absf(s.global_position.x) > 0.5 else 1.0)
		var deep := signf(p.z) * 4.0 if absf(p.z) > RinkSpec.BLUE_LINE_Z else 0.0
		var z := clampf(p.z + deep, -RinkSpec.GOAL_LINE_Z + 1.0, RinkSpec.GOAL_LINE_Z - 1.0)
		target = Vector3(side * (RinkSpec.HALF_W - 2.2), 0.0, z)
		# Step aside from players skating close.
		for t in 2:
			for o: Skater in director.lineup(t).on_ice:
				var away := s.global_position - o.global_position
				away.y = 0.0
				var d := away.length()
				if d < 2.2 and d > 0.01:
					target += away / d * (2.2 - d) * 2.0
	var c := RinkSpec.clamp_inside(target.x, target.z, 1.2)
	var to := Vector3(c.x, 0.0, c.y) - s.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.5:
		return
	i.move = to / dist * clampf(dist / 4.0, 0.25, 0.85)
	i.turbo = dist > 12.0
