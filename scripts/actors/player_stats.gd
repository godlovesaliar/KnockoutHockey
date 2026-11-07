class_name PlayerStats
extends Resource
## A player's ratings (1–99). Gameplay code maps them to tuning values with lerp_stat().

@export_group("Skating")
@export_range(1, 99) var speed := 50
@export_range(1, 99) var acceleration := 50
@export_range(1, 99) var agility := 50
@export_range(1, 99) var endurance := 50

@export_group("Puck")
@export_range(1, 99) var shot_power := 50
@export_range(1, 99) var shot_accuracy := 50
@export_range(1, 99) var passing := 50
@export_range(1, 99) var puck_handling := 50

@export_group("Physical")
@export_range(1, 99) var checking := 50
@export_range(1, 99) var strength := 50
@export_range(1, 99) var defense := 50
@export_range(1, 99) var fighting := 50
@export_range(1, 99) var durability := 50
@export_range(1, 99) var aggression := 50

@export_group("Goalie")
@export_range(1, 99) var reflexes := 50
@export_range(1, 99) var positioning := 50
@export_range(1, 99) var glove := 50
@export_range(1, 99) var blocker := 50
@export_range(1, 99) var pads := 50
@export_range(1, 99) var rebound_control := 50


## A player with every rating around `base`, varied by +/- `spread` (deterministic per rng).
static func random_around(rng: RandomNumberGenerator, base := 50, spread := 12) -> PlayerStats:
	var s := PlayerStats.new()
	for p in s.get_property_list():
		if p.type == TYPE_INT and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			s.set(p.name, clampi(base + rng.randi_range(-spread, spread), 1, 99))
	return s


## Maps a 1–99 rating linearly onto [lo, hi].
static func lerp_stat(value: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, (clampf(value, 1, 99) - 1.0) / 98.0)
