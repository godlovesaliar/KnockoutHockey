class_name ArenaOutdoor
## Outdoor Rink (an Arena style): the rink set up on a frozen pond in the woods.
##   - a few rows of aluminum bleachers down each side (ArenaCommunity.bleachers), and
##     snowbanks plowed up round the ends with fans sitting on top;
##   - the pond's ice out to a snowy shore, woods all round, low hills far off;
##   - light poles with floodlights, strings of bulbs between them, a warming hut;
##   - a lamp scoreboard on posts past one end, home banners on poles (the options);
##   - the sky, sun or moon, fog and ambient light for the time of day (the `time`
##     option), and snow falling (`snow`).
## The sky and sun belong to the scene (its WorldEnvironment and DirectionalLight3D):
## they're swapped while the arena is in the tree and put back when it leaves
## (Arena.on_exit), as is the rink's floor, which the pond replaces.

const SKY_SHADER := preload("res://scenes/match/outdoor_sky.gdshader")
const BLEACHER_HALF := 17.0
const POND := Vector2(46.0, 62.0)     ## the pond's half-size (x, z) before its wobble
const HUT := Vector3(-36.0, 0.0, 52.0)
const POLE_H := 17.0

## Per time of day: the sun (elevation, azimuth, color, energy), the sky colors, stars,
## ambient light, the floodlights' and bulbs' brightness.
const TIMES := {
	"day": {"elev": 32.0, "az": 150.0, "sun": Color(1.0, 0.96, 0.9), "energy": 1.25,
		"top": Color(0.22, 0.43, 0.78), "horizon": Color(0.74, 0.82, 0.92), "ground": Color(0.82, 0.85, 0.9),
		"stars": 0.0, "ambient": 0.55, "floods": 0.0, "bulbs": 0.5, "glow": 0.35, "disc": 0.99955, "disc_energy": 8.0, "fog": 0.001},
	"dusk": {"elev": 5.0, "az": 200.0, "sun": Color(1.0, 0.56, 0.3), "energy": 0.8,
		"top": Color(0.12, 0.15, 0.34), "horizon": Color(0.96, 0.52, 0.3), "ground": Color(0.32, 0.27, 0.32),
		"stars": 0.12, "ambient": 0.38, "floods": 3.5, "bulbs": 2.2, "glow": 0.9, "disc": 0.9993, "disc_energy": 5.0, "fog": 0.0014},
	"night": {"elev": 40.0, "az": 210.0, "sun": Color(0.62, 0.72, 1.0), "energy": 0.16,
		"top": Color(0.006, 0.01, 0.03), "horizon": Color(0.04, 0.06, 0.11), "ground": Color(0.03, 0.035, 0.05),
		"stars": 1.0, "ambient": 0.9, "floods": 7.0, "bulbs": 3.0, "glow": 0.25, "disc": 0.99965, "disc_energy": 3.0, "fog": 0.002},
}


static func build(a: Arena) -> void:
	var t: Dictionary = TIMES.get(str(a.spec.get("time", "dusk")), TIMES.dusk)
	var seats := ArenaCommunity.bleachers(a, BLEACHER_HALF)
	seats.append_array(_snowbanks(a))
	a.seat_crowd(seats, [0.8, 0.6, 0.5], [null, null, null])
	a.crowd_look = Vector2(a.low_o(3), a.low_y(3) + 1.0)
	_ground(a)
	_trees(a)
	_hills(a)
	var poles := _poles(a, t)
	_bulbs(a, t, poles)
	_hut(a, t)
	if a.spec.get("scoreboard", true):
		_scoreboard(a)
	if a.spec.get("banners", false):
		_flags(a)
	_snow(a, str(a.spec.get("snow", "light")))
	_sky(a, t)
	_wind(a, str(a.spec.get("snow", "light")))


## Wind under the crowd while the game's here, stronger with heavier snow (off when the
## arena leaves).
const WIND_DB := {"none": -15.0, "light": -11.0, "heavy": -6.0}


static func _wind(a: Arena, snow: String) -> void:
	var sfx := a.get_node_or_null("/root/Sfx")
	if sfx == null or not sfx.has_method("set_ambience"):
		return
	sfx.set_ambience("wind", float(WIND_DB.get(snow, -11.0)))
	var prev := a.on_exit
	a.on_exit = func() -> void:
		if prev.is_valid():
			prev.call()
		if is_instance_valid(sfx):
			sfx.set_ambience("")


# --- The pond and its shore -------------------------------------------------------------

## How far the pond's shore is in direction `ang` (radians, atan2(z, x)).
static func pond_r(ang: float) -> float:
	var c := cos(ang) / POND.x
	var s := sin(ang) / POND.y
	return (1.0 / sqrt(c * c + s * s)) * (1.0 + 0.06 * sin(3.0 * ang + 0.5) + 0.04 * sin(7.0 * ang + 1.3))


static func _ground(a: Arena) -> void:
	var snow := MeshInstance3D.new()
	snow.name = "Snow"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
	snow.mesh = pm
	snow.material_override = MeshUtil.material(Color(0.9, 0.92, 0.96), 0.85)
	snow.position.y = -0.08
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(snow)
	# The pond: dark clear ice out to the shore, a dusting of snow over its edge.
	var ice := Arena._st()
	var rim := Arena._st()
	var n := 96
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var r0 := pond_r(a0)
		var r1 := pond_r(a1)
		var p0 := Vector3(cos(a0) * r0, -0.04, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r1, -0.04, sin(a1) * r1)
		MeshUtil.quad(ice, Vector3(0, -0.04, 0), p0, p1, p1, Vector3.UP)
		var q0 := Vector3(cos(a0) * (r0 - 2.5), -0.03, sin(a0) * (r0 - 2.5))
		var q1 := Vector3(cos(a1) * (r1 - 2.5), -0.03, sin(a1) * (r1 - 2.5))
		MeshUtil.quad(rim, q0, q1, p1 + Vector3(0, 0.03, 0), p0 + Vector3(0, 0.03, 0), Vector3.UP)
	var ice_m := MeshUtil.material(Color(0.42, 0.53, 0.62), 0.12)
	a._commit(ice, ice_m, "PondIce", false)
	var rim_m := MeshUtil.material(Color(0.8, 0.84, 0.9), 0.8)
	a._commit(rim, rim_m, "PondEdge", false)
	var rink := a.get_parent()
	var floor := rink.get_node_or_null("Floor") as Node3D if rink else null
	if floor:
		floor.visible = false


## The snow plowed up round the ends (|z| past the bleachers), a mound between the boards
## and the shore; returns seats for fans sitting along its top (bowl 1, no shins).
static func _snowbanks(a: Arena) -> Array:
	var offs := [0.9, 1.7, 2.8, 4.2, 5.6]
	var hs := [0.0, 0.85, 1.25, 0.9, 0.0]
	# Every loop has the same segments (Arena._loop): split each the same way so the
	# loops stay in step, ~0.8 m apart along the inner one.
	var loops := []
	for o: float in offs:
		loops.append(Arena._loop(o))
	var base: PackedVector2Array = loops[0]
	var m := base.size()
	var pts := []      # per loop: resampled points
	for k in offs.size():
		pts.append(PackedVector2Array())
	for i in m:
		var steps := maxi(1, ceili(base[i].distance_to(base[(i + 1) % m]) / 0.8))
		for s in steps:
			var f := float(s) / steps
			for k in offs.size():
				var lp: PackedVector2Array = loops[k]
				pts[k].append(lp[i].lerp(lp[(i + 1) % m], f))
	var n: int = pts[0].size()
	var grid := []     # per loop: Vector3 points
	for k in offs.size():
		var row := PackedVector3Array()
		for i in n:
			var p: Vector2 = pts[k][i]
			var z0: float = absf(pts[0][i].y)
			var taper := smoothstep(19.0, 24.0, z0)
			var wob := 1.0 + 0.22 * sin(i * 0.61) + 0.12 * sin(i * 1.73 + 1.0)
			row.append(Vector3(p.x, hs[k] * wob * taper - 0.05, p.y))
		grid.append(row)
	var st := Arena._st()
	for k in offs.size() - 1:
		for i in n:
			var j := (i + 1) % n
			if grid[1][i].y <= 0.0 and grid[1][j].y <= 0.0:
				continue
			var q := [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
			var nn := [_grid_normal(grid, k, i), _grid_normal(grid, k, j), _grid_normal(grid, k + 1, j), _grid_normal(grid, k + 1, i)]
			_tri(st, [q[0], q[1], q[2]], [nn[0], nn[1], nn[2]])
			_tri(st, [q[0], q[2], q[3]], [nn[0], nn[2], nn[3]])
	var mi := a._commit(st, MeshUtil.material(Color(0.92, 0.94, 0.98), 0.8), "Snowbanks", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Fans along the top, every other point, well past the bleachers.
	var seats := []
	var i2 := 0
	while i2 < n:
		var top: Vector3 = grid[2][i2]
		if absf(top.z) > 25.0:
			var inward := Vector2(grid[0][i2].x - top.x, grid[0][i2].z - top.z).normalized()
			var p := Vector2(top.x, top.z)
			seats.append([1, Arena._seat_xf([p, inward], top.y - 0.4), Arena._sector(p), Arena._chunk(1, p, 1)])
		i2 += 1
	return seats


static func _grid_normal(grid: Array, k: int, i: int) -> Vector3:
	var n: int = grid[0].size()
	var along: Vector3 = grid[k][(i + 1) % n] - grid[k][(i - 1 + n) % n]
	var across: Vector3 = grid[mini(k + 1, grid.size() - 1)][i] - grid[maxi(k - 1, 0)][i]
	var nn := along.cross(across).normalized()
	return -nn if nn.y < 0.0 else nn


## A triangle with per-corner normals, wound to face them.
static func _tri(st: SurfaceTool, p: Array, n: Array) -> void:
	var avg: Vector3 = n[0] + n[1] + n[2]
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(avg) > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		st.set_normal(n[i])
		st.add_vertex(p[i])


# --- Trees and hills --------------------------------------------------------------------

## The woods are the project's own trees (tools/blender/trees.py: bare hardwoods grown with
## the Easy Tree extension, and snowy evergreens). trees.glb holds each kind 1 m tall with
## its base at the origin; a `<kind>_card` cut-out of it on crossed quads, for the far
## ones; a `shrub_card`; and the `treeline` strip. Per kind: how tall we make it (m) and
## how often it turns up in the woods.
const TREE_SET := "res://assets/trees/trees.glb"
const TREE_DIR := "res://assets/trees/"
const BARK_SHADER := preload("res://scenes/match/tree_bark.gdshader")
const TREE_KINDS := {
	"ev_spruce": {"h": [11.0, 18.0], "weight": 0.24},
	"ev_fir": {"h": [8.0, 13.0], "weight": 0.18},
	"ev_narrow": {"h": [9.0, 15.0], "weight": 0.12},
	"hw_broad": {"h": [9.0, 14.0], "weight": 0.15},
	"hw_tall": {"h": [11.0, 17.0], "weight": 0.14},
	"hw_slim": {"h": [8.0, 13.0], "weight": 0.12},
	"hw_gnarled": {"h": [6.0, 10.0], "weight": 0.05},
}
## Trees this near the shore (m) are models; past it they're cut-outs.
const TREE_MODELS_WITHIN := 34.0
const TREE_MODELS_WITHIN_LOW := 14.0
static var _set := {}   ## node name -> [mesh (our materials on it), its width over its height]


## A picture cut out by its alpha, seen from both sides. A hard cutoff: no sorting trouble.
static func _cutout(file: String, cutoff := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TREE_DIR + file) as Texture2D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = cutoff
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## The tree set's meshes by node name, with the game's materials on their surfaces (the
## file carries only the materials' names).
static func _tree_set() -> Dictionary:
	if not _set.is_empty():
		return _set
	var ps := load(TREE_SET) as PackedScene
	if ps == null:
		return _set
	var bark := ShaderMaterial.new()
	bark.shader = BARK_SHADER
	bark.set_shader_parameter("bark", load(TREE_DIR + "bark.jpg"))
	var mats := {
		"KH Bark": bark,
		"Boughs": _cutout("bough.png"),
		"Cards": _cutout("cards.png", 0.4),
		"Treeline": _cutout("treeline.png", 0.4),
	}
	var root := ps.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mesh := mi.mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			if src and mats.has(src.resource_name):
				mesh.surface_set_material(s, mats[src.resource_name])
		var box := mesh.get_aabb()
		_set[str(mi.name)] = [mesh, box.size.x / maxf(box.size.y, 0.001)]
	root.free()
	return _set


## A MultiMesh of one of the set's meshes at `xfs` (each a ground spot, a turn and a size).
static func _instances(a: Arena, kind: String, xfs: Array, node_name: String) -> void:
	var entry: Array = _tree_set().get(kind, [])
	if entry.is_empty() or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = entry[0]
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i] as Transform3D)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(mmi)


## The woods: snowy evergreens and bare hardwoods, thick at the shore and thinning out
## (models near the shore, cut-outs past them); shrubs and young firs along the shore;
## and two rings of the treeline strip far off, in front of the hills.
static func _trees(a: Arena) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var count := 220 if Arena.low_detail else 480
	var models_within := TREE_MODELS_WITHIN_LOW if Arena.low_detail else TREE_MODELS_WITHIN
	var by_kind := {}
	for k: String in TREE_KINDS:
		by_kind[k] = []
		by_kind[k + "_card"] = []
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 6:
		tries += 1
		var ang := rng.randf() * TAU
		var off := 5.0 + pow(rng.randf(), 1.6) * 110.0
		var d := pond_r(ang) + off
		var p := Vector3(cos(ang) * d, -0.1, sin(ang) * d)
		if Vector2(p.x - HUT.x, p.z - HUT.z).length() < 9.0:
			continue
		var roll := rng.randf()
		var kind: String = TREE_KINDS.keys()[0]
		for k: String in TREE_KINDS:
			roll -= float(TREE_KINDS[k].weight)
			if roll <= 0.0:
				kind = k
				break
		var hr: Array = TREE_KINDS[kind].h
		var h := rng.randf_range(hr[0], hr[1])
		var w := h * rng.randf_range(0.88, 1.12)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w)), p)
		by_kind[kind if off < models_within else kind + "_card"].append(xf)
		placed += 1
	for k: String in by_kind:
		_instances(a, k, by_kind[k], "Trees_" + k)
	# Along the shore, in twos and threes: bare shrubs and young firs.
	var low := {"shrub_card": [], "ev_fir_card": []}
	for i in (40 if Arena.low_detail else 90):
		var ang := rng.randf() * TAU
		var d := pond_r(ang) + rng.randf_range(0.5, 6.0)
		for j in rng.randi_range(1, 3):
			var off := Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
			var p := Vector3(cos(ang) * d, -0.15, sin(ang) * d) + off
			if Vector2(p.x - HUT.x, p.z - HUT.z).length() < 8.0:
				continue
			var kind := "shrub_card" if rng.randf() < 0.55 else "ev_fir_card"
			var h := rng.randf_range(1.2, 2.3) if kind == "shrub_card" else rng.randf_range(1.0, 2.6)
			low[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * h), p))
	for k: String in low:
		_instances(a, k, low[k], "Shore_" + k)
	# The far woods: treeline strips facing in, two staggered rings, overlapping.
	var strip: Array = _tree_set().get("treeline", [])
	if not strip.is_empty():
		var aspect: float = strip[1]
		var strips := []
		for ring: Array in [[175.0, 0.0, 26.0], [205.0, 0.5, 32.0]]:
			var r: float = ring[0]
			var n := 20
			var h: float = ring[2]
			var w := TAU * r / n * 1.35
			for i in n:
				var ang := TAU * (i + float(ring[1])) / n
				var p := Vector3(cos(ang) * r, -0.5, sin(ang) * r)
				# The strip's face (its local Z) toward the rink.
				var face := Basis.looking_at(Vector3(cos(ang), 0, sin(ang)), Vector3.UP)
				strips.append(Transform3D(face.scaled_local(Vector3(w / aspect, h * rng.randf_range(0.85, 1.1), 1.0)), p))
		_instances(a, "treeline", strips, "TreeLine")


## Low snowy hills all round, far off in the haze.
static func _hills(a: Arena) -> void:
	var st := Arena._st()
	var n := 120
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var rings := []
		for ang: float in [a0, a1]:
			var h := 22.0 + 14.0 * sin(3.0 * ang + 1.0) + 9.0 * sin(7.0 * ang) + 5.0 * sin(13.0 * ang + 2.0)
			h = maxf(h, 6.0)
			var dir := Vector3(cos(ang), 0, sin(ang))
			rings.append([dir * 250.0 + Vector3(0, -0.1, 0), dir * 330.0 + Vector3(0, h, 0), dir * 420.0 + Vector3(0, h * 0.6, 0)])
		for k in 2:
			var p0: Vector3 = rings[0][k]
			var p1: Vector3 = rings[1][k]
			var p2: Vector3 = rings[1][k + 1]
			var p3: Vector3 = rings[0][k + 1]
			var nrm := (p1 - p0).cross(p3 - p0).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			MeshUtil.quad(st, p0, p1, p2, p3, nrm)
	a._commit(st, MeshUtil.material(Color(0.78, 0.82, 0.88), 0.9), "Hills", false)


# --- Lights -----------------------------------------------------------------------------

## Light poles behind the bleachers and past the ends, each with a bank of floodlights
## aimed at the ice (lit at sunset and night). Returns the poles' tops (for the bulbs).
static func _poles(a: Arena, t: Dictionary) -> Array:
	var px := RinkSpec.HALF_W + a.low_o(a.LOW_ROWS) + 2.4
	var ez := RinkSpec.HALF_L + 7.0
	var spots := [Vector3(-px, 0, -15.0), Vector3(-px, 0, 15.0), Vector3(px, 0, -15.0), Vector3(px, 0, 15.0),
		Vector3(-14.0, 0, -ez), Vector3(14.0, 0, -ez), Vector3(-14.0, 0, ez), Vector3(14.0, 0, ez)]
	var steel := Arena._st()
	var lens := Arena._st()
	var floods: float = t.floods
	var tint := a.light_color()
	var tops := []
	for p: Vector3 in spots:
		var top := p + Vector3(0, POLE_H, 0)
		tops.append(top + Vector3(0, -POLE_H * 0.45, 0))
		Arena._box(steel, p + Vector3(-0.18, 0, -0.18), top + Vector3(0.18, 0, 0.18))
		var aim := Vector3(p.x * 0.15, 0.0, p.z * 0.45)
		var fwd := Vector3(aim.x - p.x, 0, aim.z - p.z).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		Arena._beam(steel, top - right * 1.8 + Vector3(0, 0.2, 0), top + right * 1.8 + Vector3(0, 0.2, 0), 0.08)
		var down := (aim - top).normalized()
		for k in 4:
			var c := top + right * (-1.35 + k * 0.9) + fwd * 0.3
			Arena._beam(steel, c - down * 0.25, c + down * 0.25, 0.32)
			var face := c + down * 0.26
			var u := right * 0.27
			var v := down.cross(right).normalized() * 0.27
			MeshUtil.quad(lens, face - u - v, face + u - v, face + u + v, face - u + v, down)
		if floods > 0.0:
			var s := SpotLight3D.new()
			s.name = "Floodlight"
			a.add_child(s)
			s.look_at_from_position(top + fwd * 0.6, aim)
			s.spot_range = top.distance_to(aim) * 1.7
			s.spot_angle = 38.0
			s.spot_attenuation = 0.5
			s.light_energy = floods
			s.light_specular = 0.0
			s.light_color = tint
	a._commit(steel, MeshUtil.material(Color(0.36, 0.38, 0.4), 0.5, 0.6), "LightPoles", false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var lit := Arena._emissive(Color(0.95, 0.97, 1.0) * tint / Color(0.94, 0.96, 1.0), 9.0) if floods > 0.0 else MeshUtil.material(Color(0.5, 0.52, 0.55), 0.2, 0.3)
	a._commit(lens, lit, "Floods", false)
	return tops


## Strings of bulbs round the rink from pole to pole, sagging, in mixed colors.
static func _bulbs(a: Arena, t: Dictionary, tops: Array) -> void:
	# Pole order round the rink: -x side, -z end, +x side, +z end.
	var ring := [tops[0], tops[4], tops[5], tops[2], tops[3], tops[7], tops[6], tops[1]]
	var wire := Arena._st()
	var colors := [Color(1.0, 0.82, 0.5), Color(1.0, 0.25, 0.15), Color(0.3, 0.9, 0.35), Color(0.3, 0.5, 1.0), Color(1.0, 0.75, 0.2)]
	var bulbs := []
	for c in colors:
		bulbs.append(Arena._st())
	var k := 0
	for i in ring.size():
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % ring.size()]
		var len := p0.distance_to(p1)
		var sag := 0.06 * len
		var steps := maxi(2, int(len / 0.9))
		var prev := p0
		for s in range(1, steps + 1):
			var f := float(s) / steps
			var p := p0.lerp(p1, f) - Vector3(0, sag * 4.0 * f * (1.0 - f), 0)
			Arena._beam(wire, prev, p, 0.012)
			Arena._box(bulbs[k % colors.size()], p + Vector3(-0.06, -0.16, -0.06), p + Vector3(0.06, -0.04, 0.06))
			prev = p
			k += 1
	a._commit(wire, MeshUtil.material(Color(0.05, 0.05, 0.05), 0.6), "BulbWire", false)
	for i in colors.size():
		a._commit(bulbs[i], Arena._emissive(colors[i], float(t.bulbs)), "Bulbs", false)


# --- The hut, scoreboard, flags -----------------------------------------------------------

## The warming hut on the shore is our own log cabin (tools/blender/hut.py builds
## assets/hut/): hut.glb, its porch toward its +Z, with a `lamp` and a `smoke` marker in
## it. The file carries only the materials' names; ours go on here. Its windows and
## lantern are lit after dark, and its chimney smokes at any hour.
const HUT_SET := "res://assets/hut/hut.glb"
const HUT_DIR := "res://assets/hut/"
const HUT_TURN := PI         ## radians: turns the porch toward the rink


static func _hut(a: Arena, t: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "WarmingHut"
	a.add_child(root)
	# Local -Z toward the rink.
	root.transform = Transform3D(Basis.looking_at(-HUT.normalized() * Vector3(1, 0, 1), Vector3.UP), HUT)
	var ps := load(HUT_SET) as PackedScene
	if ps == null:
		return
	var hut := ps.instantiate() as Node3D
	hut.name = "Hut"
	hut.transform = Transform3D(Basis(Vector3.UP, HUT_TURN), Vector3.ZERO)
	root.add_child(hut)
	var lit := float(t.floods) > 0.0
	var glass := MeshUtil.material(Color(0.1, 0.13, 0.17), 0.12)
	var mats := {
		"HutWood": _hut_material("wood.jpg"),
		"HutStone": _hut_material("stone.jpg"),
		"HutPaint": _hut_material(""),
		"HutSnow": _hut_material("", 0.85),
		"HutGlow": Arena._emissive(Color(1.0, 0.7, 0.38), 2.4) if lit else glass,
	}
	for n in hut.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src and mats.has(src.resource_name):
				mi.set_surface_override_material(s, mats[src.resource_name])
	var lamp := hut.get_node_or_null("lamp") as Node3D
	if lit and lamp:
		# The lantern by the door, and the light spilling out over the porch and the snow.
		var glow := OmniLight3D.new()
		glow.position = Vector3(0.0, 0.0, 0.5)
		glow.omni_range = 9.0
		glow.light_energy = 1.5
		glow.light_color = Color(1.0, 0.7, 0.4)
		lamp.add_child(glow)
		# A little of it out front too, so the sign on the porch beam reads.
		var fill := OmniLight3D.new()
		fill.position = Vector3(0.0, 2.5, 5.4)
		fill.omni_range = 6.0
		fill.light_energy = 0.5
		fill.light_color = Color(1.0, 0.75, 0.5)
		hut.add_child(fill)
	var mouth := hut.get_node_or_null("smoke") as Node3D
	if mouth:
		mouth.add_child(_smoke(t))


## The hut's wood and stone: a tiling picture (none for the painted bits or the snow)
## tinted by the mesh's vertex colors.
static func _hut_material(file: String, roughness := 0.9) -> StandardMaterial3D:
	var m := MeshUtil.material(Color.WHITE, roughness)
	m.vertex_color_use_as_albedo = true
	if file != "":
		m.albedo_texture = load(HUT_DIR + file) as Texture2D
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Wood smoke off the chimney: slow puffs that swell, drift downwind and thin out. Pale
## by day, dim against the night sky.
static func _smoke(t: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 18
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.22, 0.05, 0.1)
	p.damping_min = 0.08
	p.damping_max = 0.12
	p.angle_min = 0.0
	p.angle_max = 360.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.22))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	p.color_ramp = fade
	var puff := GradientTexture2D.new()
	puff.width = 64
	puff.height = 64
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	puff.gradient = soft
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff
	m.albedo_color = Color(0.86, 0.87, 0.9).lerp(Color(0.2, 0.21, 0.26), clampf(float(t.stars) * 4.0, 0.0, 1.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The lamp scoreboard on two posts past the +Z end, facing the ice.
static func _scoreboard(a: Arena) -> void:
	var z := RinkSpec.HALF_L + 10.0
	var posts := Arena._st()
	for x: float in [-2.6, 2.6]:
		Arena._box(posts, Vector3(x - 0.15, 0.0, z + 0.1), Vector3(x + 0.15, 7.4, z + 0.4))
	a._commit(posts, MeshUtil.material(Color(0.3, 0.32, 0.34), 0.5, 0.5), "BoardPosts", false)
	ArenaCommunity.wall_board(a, Vector3(0.0, 5.6, z - 0.2), Vector3(0, 0, -1), Vector2(6.6, 3.0))


## Home banners on poles behind each end.
static func _flags(a: Arena) -> void:
	var root := Node3D.new()
	root.name = "PoleBanners"
	a.add_child(root)
	var steel := Arena._st()
	for end: float in [-1.0, 1.0]:
		var z := end * (RinkSpec.HALF_L + 7.8)
		for x: float in [-9.5, -5.5, 5.5, 9.5]:
			Arena._box(steel, Vector3(x - 0.07, 0.0, z - 0.07), Vector3(x + 0.07, 9.0, z + 0.07))
			Arena._box(steel, Vector3(x - 0.95, 8.7, z - 0.04), Vector3(x + 0.95, 8.78, z + 0.04))
			a.hang_banner(root, Vector2(1.6, 3.2), Vector3(x, 7.05, z - end * 0.06), Vector3(0, 0, -end))
	a._commit(steel, MeshUtil.material(Color(0.36, 0.38, 0.4), 0.5, 0.6), "BannerPoles", false)


# --- Snow and sky -------------------------------------------------------------------------

static func _snow(a: Arena, amount: String) -> void:
	if amount == "none":
		return
	var heavy := amount == "heavy"
	var p := GPUParticles3D.new()
	p.name = "Snowfall"
	p.amount = (9000 if heavy else 3500) / (2 if Arena.low_detail else 1)
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.position = Vector3(0, 26.0, 0)
	p.visibility_aabb = AABB(Vector3(-60, -32, -75), Vector3(120, 36, 150))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(48.0, 1.0, 62.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.2 if not heavy else 2.0
	pm.initial_velocity_max = 2.0 if not heavy else 3.2
	pm.gravity = Vector3(0.35 if heavy else 0.1, -0.25, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07) if not heavy else Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(p)


## Swaps the scene's sky and sun for the time of day (put back when the arena leaves).
static func _sky(a: Arena, t: Dictionary) -> void:
	var world := a.get_world_3d()
	var we: WorldEnvironment = null
	var sun: DirectionalLight3D = null
	for n in a.get_viewport().find_children("*", "WorldEnvironment", true, false):
		var wn := n as WorldEnvironment
		if wn.get_viewport() and wn.get_viewport().find_world_3d() == world:
			we = wn
			break
	for n in a.get_viewport().find_children("*", "DirectionalLight3D", true, false):
		var dl := n as DirectionalLight3D
		if dl.visible and dl.get_world_3d() == world:
			sun = dl
			break
	var old_env: Environment = we.environment if we else null
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("top_color", t.top)
	sm.set_shader_parameter("horizon_color", t.horizon)
	sm.set_shader_parameter("ground_color", t.ground)
	sm.set_shader_parameter("stars", t.stars)
	sm.set_shader_parameter("glow", t.glow)
	sm.set_shader_parameter("disc", t.disc)
	sm.set_shader_parameter("disc_energy", t.disc_energy)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = t.ambient
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if old_env:
		e.tonemap_mode = old_env.tonemap_mode
		e.tonemap_white = old_env.tonemap_white
		e.glow_enabled = old_env.glow_enabled
		e.glow_intensity = old_env.glow_intensity
		e.glow_bloom = old_env.glow_bloom
		e.glow_hdr_threshold = old_env.glow_hdr_threshold
	e.fog_enabled = true
	e.fog_light_color = (t.horizon as Color).lerp(t.top, 0.25)
	e.fog_density = t.fog
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.4
	if we:
		we.environment = e
	var sun_was := []
	if sun:
		sun_was = [sun.rotation, sun.light_color, sun.light_energy]
		sun.rotation = Vector3(-deg_to_rad(t.elev), deg_to_rad(t.az), 0.0)
		sun.light_color = t.sun
		sun.light_energy = t.energy
	var rink := a.get_parent()
	a.on_exit = func() -> void:
		if is_instance_valid(we) and we.environment == e:
			we.environment = old_env
		if is_instance_valid(sun) and not sun_was.is_empty():
			sun.rotation = sun_was[0]
			sun.light_color = sun_was[1]
			sun.light_energy = sun_was[2]
		if is_instance_valid(rink) and rink.has_node("Floor"):
			(rink.get_node("Floor") as Node3D).visible = true
