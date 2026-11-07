class_name ScriptBrain
extends Brain
## Drives a skater from a callable(skater, intent, elapsed_seconds). Used by tests and demos.

var fn: Callable
var elapsed := 0.0


func _init(p_fn: Callable) -> void:
	fn = p_fn


func update(s: Skater, i: SkaterIntent, delta: float) -> void:
	elapsed += delta
	fn.call(s, i, elapsed)
