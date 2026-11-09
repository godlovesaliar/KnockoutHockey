class_name CelebrateBrain
extends Brain
## After a goal: skates to `spot` (the scorer: the corner glass; linemates: a place in the
## huddle around the scorer) and, once there, faces `look_at`. Fast at first, easing in.
## `arrived` fires once on getting there (the director starts the cheering).

signal arrived(s: Skater)

var spot := Vector3.ZERO
var look_at := Vector3.ZERO
var fast := true
var _here := false


func _init(p_spot: Vector3, p_look: Vector3, p_fast := true) -> void:
	spot = p_spot
	look_at = p_look
	fast = p_fast


func update(s: Skater, i: SkaterIntent, _delta: float) -> void:
	var to := spot - s.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.6:
		i.face = Vector3(look_at.x - s.global_position.x, 0.0, look_at.z - s.global_position.z)
		if not _here:
			_here = true
			arrived.emit(s)
		return
	i.move = to / d * clampf(d / 3.0, 0.3, 1.0)
	i.turbo = fast and d > 5.0
