class_name HoldSpotBrain
extends Brain
## Practice teammate: skates back to a spot, faces the puck, and waits for passes.

var spot := Vector3.ZERO
var moves := true


func _init(p_spot := Vector3.ZERO, p_moves := true) -> void:
	spot = p_spot
	moves = p_moves


func update(s: Skater, i: SkaterIntent, _delta: float) -> void:
	if s.puck:
		i.face = s.puck.global_position - s.global_position
		i.face.y = 0.0
		if s.puck.intended_receiver == s:
			return # glide and let the pass arrive
	if not moves:
		return
	var to := spot - s.global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.5:
		i.move = to / d * clampf(d / 4.0, 0.3, 1.0)
