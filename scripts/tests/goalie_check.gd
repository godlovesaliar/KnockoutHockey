extends Node3D
## Headless goalie save-rate check: a scripted shooter runs common plays against one
## goalie and the save percentage of each is printed. Run:
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/GoalieCheck.tscn [-- n=40 g=50 s=50 diff=0.5]
## g = every goalie stat, s = every shooter stat, diff = match difficulty (goalie sharpness).
## Exits 1 if a play's save rate falls outside a hockey-like band.

const RINK_SCENE := preload("res://scenes/match/Rink.tscn")
const PUCK_SCENE := preload("res://scenes/match/Puck.tscn")
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")
const DT := 1.0 / 120.0

var rink: Rink
var puck: Puck
var goalie: Goalie
var shooter: Skater
var failures := 0
var goals := 0
var saved := false
var shot_flight := -1
var shot_from := Vector3.ZERO


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var n := int(args.get("n", "40"))
	var g_stat := int(args.get("g", "50"))
	var s_stat := int(args.get("s", "50"))
	rink = RINK_SCENE.instantiate()
	add_child(rink)
	puck = PUCK_SCENE.instantiate()
	add_child(puck)
	rink.goal_scored.connect(func(_i: int) -> void: goals += 1)
	goalie = GOALIE_SCENE.instantiate()
	goalie.team = 1
	goalie.puck = puck
	goalie.rink = rink
	goalie.stats = _stats(g_stat)
	if args.has("diff"):
		goalie.sharpness = float(args["diff"])
	add_child(goalie)
	goalie.net = rink.defended_net(1)
	goalie.seed_rng(7)
	shooter = SKATER_SCENE.instantiate()
	shooter.team = 0
	shooter.stats = _stats(s_stat)
	shooter.puck = puck
	shooter.rink = rink
	add_child(shooter)
	shooter.shot_released.connect(func(_s: Skater, _k: StringName, _v: float) -> void:
		shot_flight = puck.flight
		shot_from = puck.global_position)
	await get_tree().physics_frame

	print("Goalie stats %d, shooter stats %d, %d shots per play" % [g_stat, s_stat, n])
	var all_s := 0
	var all_g := 0
	var plays := ["cut_far", "cut_near", "slot_far", "slot_free", "point_slap", "cross_far"]
	if args.has("play"):
		plays = [args["play"]]
	for play in plays:
		var r := await _run_play(play, n)
		all_s += r.saves
		all_g += r.goals
		var on: int = r.saves + r.goals
		var pct := float(r.saves) / maxf(1.0, on)
		print("  %-11s  %2d on net, %2d saved, %2d goals, %2d wide   SV%% %.3f" % [play, on, r.saves, r.goals, r.wide, pct])
		var lo: float = {"cut_far": 0.70, "cut_near": 0.80, "slot_far": 0.70, "slot_free": 0.78, "point_slap": 0.80, "cross_far": 0.65}[play]
		if g_stat == 50 and s_stat == 50 and pct < lo:
			failures += 1
			print("    FAIL  below %.2f" % lo)
	var tot := float(all_s) / maxf(1.0, all_s + all_g)
	print("ALL PLAYS  SV%% %.3f (%d saves, %d goals)" % [tot, all_s, all_g])
	if g_stat == 50 and s_stat == 50 and tot > 0.95:
		failures += 1
		print("  FAIL  goalie unbeatable")
	print("GOALIE CHECK %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures > 0 else 0)


func _stats(v: int) -> PlayerStats:
	var s := PlayerStats.new()
	for p in s.get_property_list():
		if p.type == TYPE_INT and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			s.set(p.name, v)
	return s


static func edge(t: float, at: float) -> bool:
	return t >= at and t - DT < at


func _ticks(k: int) -> void:
	for i in k:
		await get_tree().physics_frame


func _run_play(play: String, n: int) -> Dictionary:
	var gz := -RinkSpec.GOAL_LINE_Z
	var net_pos := Vector3(0, 0, gz)
	var res := {"saves": 0, "goals": 0, "wide": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(play)
	for k in n:
		var side := 1.0 if k % 2 == 0 else -1.0
		var start: Vector3
		var shoot_at := 0.0           # distance from the net to shoot at (cut-ins)
		var aim_x := 0.0              # stick x at release: -1 left .. 1 right
		var slap := false
		match play:
			"cut_far", "cut_near":
				start = Vector3(side * rng.randf_range(5.5, 8.5), 0, gz + rng.randf_range(13.0, 16.0))
				shoot_at = rng.randf_range(5.5, 9.0)
				aim_x = -side if play == "cut_far" else side
			"slot_far":
				start = Vector3(side * rng.randf_range(0.5, 3.0), 0, gz + rng.randf_range(7.0, 11.0))
				aim_x = -side
			"slot_free":
				start = Vector3(rng.randf_range(-3.0, 3.0), 0, gz + rng.randf_range(7.0, 11.0))
			"point_slap":
				start = Vector3(side * rng.randf_range(2.0, 8.0), 0, gz + rng.randf_range(17.0, 20.0))
				slap = true
			"cross_far":
				# Skating across the slot, shooting back against the grain.
				start = Vector3(side * 5.0, 0, gz + rng.randf_range(6.5, 9.0))
				aim_x = side
		puck.place(Vector3(0, 0, 10))
		goalie.reset_in_net()
		rink.rearm_nets()
		await _ticks(20)
		shooter.seed_rng(900 + k)
		shooter.place(start, (net_pos - start).normalized())
		puck.place(shooter.puck_anchor())
		puck.attach(shooter)
		goals = 0
		saved = false
		shot_flight = -1
		var fired := {"t": -1.0}
		var drive := func(s: Skater, i: SkaterIntent, t: float) -> void:
			if fired.t >= 0.0:
				var dt: float = t - fired.t
				i.shoot_held = slap and dt < 0.6
				i.shoot_up = slap and edge(dt, 0.6)
				return
			match play:
				"cut_far", "cut_near":
					var to := Vector3(side * 0.6, 0, gz + 3.0) - s.global_position
					to.y = 0.0
					i.move = to.normalized()
					i.turbo = true
					if s.global_position.distance_to(net_pos) < shoot_at:
						i.move = Vector3(aim_x, 0, 0)
						i.shoot_down = true
						i.shoot_held = true
						fired.t = t
				"slot_far", "slot_free", "point_slap":
					if t > 0.25:
						i.move = Vector3(aim_x, 0, 0)
						i.shoot_down = true
						i.shoot_held = true
						fired.t = t
				"cross_far":
					i.move = Vector3(-side, 0, -0.15).normalized()
					i.turbo = true
					if absf(s.global_position.x) < 1.2:
						i.move = Vector3(aim_x, 0, 0)
						i.shoot_down = true
						i.shoot_held = true
						fired.t = t
			if t > 4.0: # never got a shot off
				fired.t = 99.0
		shooter.brain = ScriptBrain.new(drive)
		var waited := 0
		while shot_flight < 0 and waited < 600:
			await _ticks(1)
			waited += 1
			if OS.get_cmdline_user_args().has("path") and k < 2 and waited % 6 == 0:
				var pl := goalie.net.to_local(puck.global_position)
				var gl := goalie.net.to_local(goalie.global_position)
				print("      t%.2f puck (%.2f, %.2f) goalie (%.2f, %.2f) target %s" % [waited / 120.0, pl.x, pl.z, gl.x, gl.z, goalie._angle_target()])
		var saves_before := goalie.save_count
		await _ticks(150)
		saved = goalie.save_count > saves_before
		if shot_flight < 0:
			continue
		if goals > 0:
			res.goals += 1
			if OS.get_cmdline_user_args().has("trace"):
				print("    goal: shot from %s  goalie try %s" % [goalie.net.to_local(shot_from), goalie.last_try])
		elif saved:
			res.saves += 1
		else:
			res.wide += 1
			if OS.get_cmdline_user_args().has("trace"):
				print("    wide: from %s end %s" % [start, puck.global_position])
		shooter.brain = ScriptBrain.new(func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass)
	return res
