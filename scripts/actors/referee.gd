class_name Referee
extends Skater
## The on-ice referee: a skater with no stick who never touches the puck and passes
## through players (no collisions with them or the puck; the boards still hold). Skated
## by a RefBrain; the visual (RefereeVisual) shows the signals:
##   signal_arm "up"     arm straight up: a delayed penalty (the offending team touches
##                        the puck and the whistle goes)
##   signal_arm "point"  pointing at `point_at` (the offender, then the box)
##   ""                  arms down at the sides

## The referee's stripes: white and black, orange armbands, black pants, gloves, helmet.
const UNIFORM := {
	"jersey": Color(0.95, 0.95, 0.93), "trim": Color(1.0, 0.42, 0.04), "pants": Color(0.05, 0.05, 0.06),
	"gloves": Color(0.06, 0.06, 0.07), "helmet": Color(0.05, 0.05, 0.06), "skates": Color(0.04, 0.04, 0.05),
	"number": Color(0.95, 0.95, 0.93), "number_outline": Color(0.04, 0.04, 0.05), "design": "referee",
}

var signal_arm := ""
var point_at := Vector3.ZERO


func _ready() -> void:
	handles_puck = false
	fatigue_enabled = false
	uniform = UNIFORM
	super._ready()
	collision_layer = 0
	collision_mask = 1   # the boards only


func _make_visual() -> SkaterVisual:
	return RefereeVisual.new()
