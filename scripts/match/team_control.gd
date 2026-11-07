class_name TeamControl
extends RefCounted
## Decides which skater each human on a team controls (one skater per human):
## - a pass hands the passer's human the receiver the moment it's released (one-timers),
## - an AI teammate who gains the puck goes to the nearest human,
## - "switch" (A / J without the puck) takes the free skater nearest the puck,
## - the goalie while it holds the puck, then back to a skater once it's played.

signal controlled_changed(human: HumanBrain, skater: Skater)

var team := 0
var on_ice: Array[Skater] = []        ## shared with the Lineup
var humans: Array[HumanBrain] = []
var controlled := {}                  ## HumanBrain -> Skater
var puck: Puck
var goalie: Goalie

var _changed_frame := -1


func _init(p_team: int, p_on_ice: Array[Skater], roster: Array[Skater], p_humans: Array[HumanBrain],
		p_puck: Puck, p_goalie: Goalie = null) -> void:
	team = p_team
	on_ice = p_on_ice
	humans = p_humans
	puck = p_puck
	goalie = p_goalie
	for s in roster:
		s.brain = s.ai_brain
		s.switch_requested.connect(_on_switch_requested)
		s.pass_released.connect(_on_pass_released)
	if goalie:
		goalie.pass_released.connect(_on_pass_released)
	puck.possession_changed.connect(_on_possession_changed)


func primary() -> HumanBrain:
	return humans[0] if not humans.is_empty() else null


func skater_of(h: HumanBrain) -> Skater:
	return controlled.get(h)


## The skater P-first human controls (for HUD / single-player code).
func controlled_skater() -> Skater:
	return skater_of(primary()) if primary() else null


func human_of(s: Skater) -> HumanBrain:
	for h in controlled:
		if controlled[h] == s:
			return h
	return null


func set_controlled(h: HumanBrain, s: Skater) -> void:
	if h == null:
		return
	var owner := human_of(s) if s else null
	if owner and owner != h:
		return # another human already has this skater
	var old: Skater = controlled.get(h)
	if old == s:
		return
	if old and is_instance_valid(old):
		old.brain = old.ai_brain
		old.is_human = false
		old.human_index = -1
	controlled[h] = s
	if s:
		s.brain = h
		s.is_human = true
		s.human_index = h.player_index
		s.changing = false
	_changed_frame = Engine.get_physics_frames()
	controlled_changed.emit(h, s)


## Faceoff / line change: hand out the on-ice skaters (P1 gets the faceoff taker).
func reset_to(list: Array[Skater]) -> void:
	for h in humans:
		set_controlled(h, null)
	var order := list.duplicate()
	order.sort_custom(func(a: Skater, b: Skater) -> bool: return int(a.is_defense) < int(b.is_defense))
	for i in mini(humans.size(), order.size()):
		set_controlled(humans[i], order[i])


func nearest_free(h: HumanBrain, point: Vector3) -> Skater:
	var best: Skater = null
	var best_d := INF
	for s in on_ice:
		var owner := human_of(s)
		if owner and owner != h:
			continue
		var d := s.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = s
	return best


func _nearest_human_to(p: Vector3) -> HumanBrain:
	var best: HumanBrain = null
	var best_d := INF
	for h in humans:
		var s := skater_of(h)
		var d := s.global_position.distance_squared_to(p) if s else 1e9
		if best == null or d < best_d:
			best_d = d
			best = h
	return best


## A skater left the ice (bench, box): its human takes someone else.
func on_skater_removed(s: Skater) -> void:
	var h := human_of(s)
	if h:
		set_controlled(h, null)
		set_controlled(h, nearest_free(h, puck.global_position))


func _on_possession_changed(carrier: Skater) -> void:
	if carrier and carrier.team == team:
		if human_of(carrier) == null:
			set_controlled(_nearest_human_to(carrier.global_position), carrier)
	elif carrier == null:
		for h in humans:
			if skater_of(h) is Goalie:
				set_controlled(h, nearest_free(h, puck.global_position))


func _on_pass_released(passer: Skater, receiver: Skater) -> void:
	var h := human_of(passer)
	if h == null and passer is Goalie:
		h = primary()
	if h and receiver and human_of(receiver) == null:
		set_controlled(h, receiver)


func _on_switch_requested(s: Skater) -> void:
	if Engine.get_physics_frames() == _changed_frame:
		return # the same button press that just changed control
	var h := human_of(s)
	if h:
		set_controlled(h, nearest_free(h, puck.global_position))
