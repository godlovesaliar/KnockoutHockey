extends Node
## Checks for the store's extras: buying one and its on / off switch (Store, Profile on a
## throwaway save), and that a match with them on gets big heads, a big puck, the rainbow
## trail, the retro picture and glass that always breaks, all put back afterwards.
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/ExtrasCheck.tscn
## Exits 0 on pass, 1 on failure.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")
const KEYS := ["bighead", "rainbow", "bigpuck", "glass", "retro"]

var failures := 0


func _ready() -> void:
	Profile.use_fresh("check")
	_switches()
	await _match()
	print("EXTRAS CHECK %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		failures += 1


func _until(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds and not cond.call():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return cond.call()


func _switches() -> void:
	var shelf := Store.in_category("extras")
	var keys := shelf.map(func(it: Dictionary) -> String: return str(it.get("extra", "")))
	keys.sort()
	var want := KEYS.duplicate()
	want.sort()
	_check(keys == want, "the extras shelf has the five the game knows (%s)" % str(keys))
	_check(Store.extras_on().is_empty(), "a new profile has none on")
	Profile.set_extra("extra_bighead", true)
	_check(Store.extras_on().is_empty(), "one that isn't bought can't be on")
	Profile.set_extra("extra_bighead", false)
	Profile.add_pucks(700)
	_check(Store.buy("extra_bighead") and Store.buy("extra_rainbow") and Profile.pucks() == 0, "700 pucks buy Big Head Mode and the Rainbow Puck")
	_check(Store.extras_on().is_empty(), "bought isn't on until it's switched on")
	Profile.set_extra("extra_bighead", true)
	_check(Store.extras_on() == ["bighead"], "switched on, it's on (%s)" % str(Store.extras_on()))
	Profile.set_extra("extra_rainbow", true)
	Profile.set_extra("extra_bighead", false)
	_check(Store.extras_on() == ["rainbow"], "each has its own switch (%s)" % str(Store.extras_on()))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profile_check.json"))
	_check(saved is Dictionary and saved.get("extras_on", []) == ["extra_rainbow"], "the switches are in the save file")


## A computer-vs-computer game with every extra on.
func _match() -> void:
	_check(is_equal_approx(SkaterRig.head_scale, 1.0), "heads are their own size outside a game")
	var m: MatchDirector = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = []
	m.show_hud = false
	m.fighting = false
	m.penalties = false
	m.rng_seed = 5
	m.extras = KEYS.duplicate()
	add_child(m)
	_check(await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 40.0), "the game goes live with every extra on")
	# Big heads: the rig setting, and the head bone as it's posed.
	_check(is_equal_approx(SkaterRig.head_scale, MatchDirector.BIG_HEAD), "Big Head Mode: the rigs are told")
	var s: Skater = m.lineup(0).on_ice[0]
	var seen := {"scale": 0.0}
	s.visual.rig.modification_processed.connect(func() -> void:
		var sk: Skeleton3D = s.visual.rig.get_skeleton()
		seen.scale = sk.get_bone_pose_scale(sk.find_bone("Head")).x)
	await _until(func() -> bool: return float(seen.scale) > 0.0, 3.0)
	_check(is_equal_approx(float(seen.scale), MatchDirector.BIG_HEAD), "a skater's head bone is posed at %.1fx (%.2f)" % [MatchDirector.BIG_HEAD, float(seen.scale)])
	# Big puck: the look only.
	var vis: Node3D = m.puck.get_node("Visual")
	_check(is_equal_approx(m.puck.visual_scale, MatchDirector.BIG_PUCK) and is_equal_approx(vis.scale.x, MatchDirector.BIG_PUCK), "Big Puck: drawn twice the size")
	_check(is_equal_approx((m.puck.get_node("Collision") as CollisionShape3D).scale.x, 1.0), "its collision is a real puck's")
	# Rainbow trail.
	var trail := m.get_node_or_null("PuckTrail") as PuckTrail
	_check(trail != null, "Rainbow Puck: the trail is there")
	if trail != null:
		await _until(func() -> bool: return trail.length() >= 3, 20.0)
		_check(trail.length() >= 3, "it grows behind a moving puck (%d points)" % trail.length())
	# Retro picture.
	_check(m.get_node_or_null("RetroTV") != null and (m.get_node("RetroTV") as CanvasLayer).layer == 9, "Retro Broadcast: the picture layer is up, under the menus")
	# Breakaway glass: a soft hit by the boards still breaks a pane, time after time.
	await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 30.0)
	var a: Skater = m.lineup(0).on_ice[0]
	var v: Skater = m.lineup(1).on_ice[0]
	v.global_position = Vector3(RinkSpec.HALF_W - 0.4, 0, -14.0)
	v.last_impact = 0.0
	m._glass_breaks = 5
	_check(m._try_break_glass(a, v), "Breakaway Glass: a soft hit at the boards breaks a pane, past the usual limit")
	m.extras.erase("glass")
	m._glass_at = Vector3.INF
	m.rink.repair_glass()
	_check(not m._try_break_glass(a, v), "without it, the same hit doesn't")
	# Leaving the game puts heads back.
	m.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(SkaterRig.head_scale, 1.0), "heads go back to their own size after the game")
