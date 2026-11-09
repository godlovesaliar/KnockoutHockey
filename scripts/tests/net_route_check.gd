extends SceneTree
## Headless check of `Net.detour`: a body steered by it from all around the net reaches
## its target without entering the net's footprint, and targets inside the net are moved out.
## godot --headless --path . -s res://scripts/tests/net_route_check.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var net := Net.new()
	root.add_child(net)
	# A real placement: the +Z net, mouth facing center ice (-Z in world).
	net.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, RinkSpec.GOAL_LINE_Z))
	await process_frame
	var hx := RinkSpec.NET_WIDTH * 0.5 + RinkSpec.POST_RADIUS * 2.0
	var r := 0.35

	# Clear way: unchanged.
	var a := net.to_global(Vector3(-3, 0, 4))
	var b := net.to_global(Vector3(3, 0, 4))
	if net.detour(a, b, r).distance_to(b) > 0.001:
		fails += 1
		print("FAIL clear path was changed")

	# Target in the net: moved outside the footprint.
	var inside := net.to_global(Vector3(0.2, 0, -0.3))
	var moved := net.to_local(net.detour(net.to_global(Vector3(0, 0, 6)), inside, r))
	if absf(moved.x) < hx + r and moved.z < r and moved.z > -RinkSpec.NET_DEPTH - r:
		fails += 1
		print("FAIL target in the net stays inside: ", moved)

	# Walk from a ring of starts to targets on the far side; never enter the footprint.
	var targets := [Vector3(0, 0, 4), Vector3(0, 0, -4), Vector3(1.2, 0, -2.5), Vector3(0.1, 0, -0.2)]
	var walks := 0
	for tl: Vector3 in targets:
		for k in 24:
			var ang := TAU * k / 24.0
			var start := Vector3(cos(ang) * 3.2, 0, sin(ang) * 3.2 - 0.5)
			var p := net.to_global(start)
			var goal := net.to_global(tl)
			var ok := false
			for step in 400:
				var aim := net.detour(p, goal, r)
				var to := aim - p
				to.y = 0.0
				if to.length() < 0.05:
					ok = true
					break
				p += to.normalized() * minf(0.05, to.length())
				var l := net.to_local(p)
				if absf(l.x) < hx + r * 0.9 and l.z < r * 0.9 and l.z > -RinkSpec.NET_DEPTH - r * 0.9:
					fails += 1
					print("FAIL walked into the net: start ", start, " target ", tl, " at ", l)
					ok = true
					break
			walks += 1
			if not ok:
				fails += 1
				print("FAIL never arrived: start ", start, " target ", tl, " stuck at ", net.to_local(p))
	print("net_route_check: %d walks, %s" % [walks, "OK" if fails == 0 else "%d FAILED" % fails])
	quit(1 if fails else 0)
