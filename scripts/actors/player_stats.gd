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


## How this player fights (Fight.Style: 0 boxer, 1 brawler, 2 grinder). Most hockey
## fighters are untrained swingers, so the brawler is the common style (about 60% on the
## rosters); the grinder is for the heavy, slow ones and the boxer, the clean, trained
## technique, is rare (about 20% each). The ratings tilt the odds and a pick seeded from
## the ratings settles it, so a player always fights the same way:
##   boxer    technique (fighting), more so with quick feet (agility over strength)
##   brawler  temper (aggression)
##   grinder  strength over agility
## The sheet's ratings all follow PHY, so a strict rule either made nobody a boxer or made
## every heavyweight one; odds keep a mix in every kind of player.
func fighting_style() -> int:
	var tech := clampf((fighting - 45) / 40.0, 0.0, 1.0)
	var feet := clampf((agility - strength + 20) / 40.0, 0.0, 1.0)
	var heavy := clampf((strength - agility) / 25.0, 0.0, 1.0)
	var temper := clampf((aggression - 40) / 45.0, 0.0, 1.0)
	var w := [0.45 + 1.2 * tech * feet + 0.6 * tech, 1.1 + 3.0 * temper, 0.3 + 3.0 * heavy]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([speed, acceleration, agility, endurance, shot_power, shot_accuracy, passing,
			puck_handling, checking, strength, defense, fighting, durability, aggression])
	return rng.rand_weighted(PackedFloat32Array(w))


## Maps a 1–99 rating linearly onto [lo, hi].
static func lerp_stat(value: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, (clampf(value, 1, 99) - 1.0) / 98.0)
