extends SceneTree
## Headless check of the play angles: stick-to-world turns and `follow_team` flips.
## godot --headless --path . -s res://scripts/tests/camera_check.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var scene: Node = (load("res://scenes/match/Match.tscn") as PackedScene).instantiate()
	scene.set("show_hud", false)
	root.add_child(scene)
	await process_frame
	var d := scene
	var router: Node = root.get_node("InputRouter")
	# [angle, ends swapped, expected screen-up, expected world direction of stick-right]
	var cases := [
		["broadcast", false, Vector3(0, 0, -1), Vector3(1, 0, 0)],
		["broadcast", true, Vector3(0, 0, 1), Vector3(-1, 0, 0)],
		["side", false, Vector3(-1, 0, 0), Vector3(0, 0, -1)],
		["side", true, Vector3(1, 0, 0), Vector3(0, 0, 1)],
		["high", true, Vector3(0, 0, 1), Vector3(-1, 0, 0)],
	]
	d.humans = [{"kind": "any", "pad": 0, "team": 0}]
	for c: Array in cases:
		d.rink.ends_swapped = c[1]
		d.apply_camera(c[0], true)
		var up: Vector3 = router.screen_fwd
		var right: Vector3 = router.to_world(Vector3(1, 0, 0))
		# Team 0 must attack along screen-up (end to end) or screen-right (side).
		var net: Vector3 = d.rink.attacked_net(0).global_position
		var attack_ok: bool = net.dot(up if c[0] != "side" else right) > 0.0
		var round_trip: Vector3 = router.to_screen(router.to_world(Vector3(0.3, 0, -0.7)))
		var ok: bool = up.is_equal_approx(c[2]) and right.is_equal_approx(c[3]) and attack_ok \
				and round_trip.is_equal_approx(Vector3(0.3, 0, -0.7))
		print("%s %-9s swapped=%s up=%s right=%s" % ["ok  " if ok else "FAIL", c[0], c[1], up, right])
		if not ok:
			fails += 1
	d.rink.ends_swapped = false
	d.apply_camera("broadcast", false)
	print("CAMERA CHECK %s — %d failure(s)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
