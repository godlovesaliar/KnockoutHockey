class_name SkaterIntent
extends RefCounted
## What a skater's brain (human or AI) wants to do this physics tick.
## Brains rewrite every field each tick; *_down / *_up are one-tick edges.

var move := Vector3.ZERO     ## flat world direction, length 0..1
var face := Vector3.ZERO     ## optional direction to face when standing still
var turbo := false
var protect := false
var backward := false        ## skate backwards: face away from the direction of travel

var pass_down := false
var pass_held := false
var pass_up := false

var shoot_down := false
var shoot_held := false
var shoot_up := false

var deke_down := false
var deke_held := false
var check_down := false
var block_held := false      ## fights: R1 held


func clear() -> void:
	move = Vector3.ZERO
	face = Vector3.ZERO
	turbo = false
	protect = false
	backward = false
	pass_down = false
	pass_held = false
	pass_up = false
	shoot_down = false
	shoot_held = false
	shoot_up = false
	deke_down = false
	deke_held = false
	check_down = false
	block_held = false
