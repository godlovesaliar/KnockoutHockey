class_name RegroupBrain
extends Brain
## After the whistle: skates to `spot` (a faceoff spot, or the bench gate going off for a
## change) at an easy pace, eases in and settles facing `face`. MatchDirector sets it as a
## skater's `autopilot`, which overrides whoever controls them until the faceoff.

const ARRIVE := 0.35     ## m: close enough to stop pushing and turn to `face`
const SETTLED := 0.7     ## m: counts as in position (see settled)

var spot := Vector3.ZERO
var face := Vector3.ZERO


func _init(p_spot: Vector3, p_face := Vector3.ZERO) -> void:
	spot = Vector3(p_spot.x, 0.0, p_spot.z)
	face = p_face


func distance(s: Skater) -> float:
	return Vector2(spot.x - s.global_position.x, spot.z - s.global_position.z).length()


## In position: there, and stopped (or nearly) so the faceoff placement doesn't jump.
## `tight`: the center, who's placed exactly on the dot.
func settled(s: Skater, tight := false) -> bool:
	return distance(s) < (ARRIVE + 0.1 if tight else SETTLED) and s.flat_speed() < 1.4


func update(s: Skater, i: SkaterIntent, _delta: float) -> void:
	var to := spot - s.global_position
	to.y = 0.0
	var d := to.length()
	if face.length() > 0.1:
		i.face = face
	if d < ARRIVE:
		return
	# Full stride from far off (a sprint only from the far end), coasting in close. (The
	# skater ignores a stick under 0.15, so the slowest push stays above that.)
	i.move = to / d * clampf(d / 3.5, 0.25, 1.0)
	i.turbo = d > 18.0 and s.stamina > 0.3
