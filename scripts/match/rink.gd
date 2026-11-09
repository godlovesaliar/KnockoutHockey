@tool
class_name Rink
extends Node3D
## Gray-box regulation rink: ice with markings, boards, glass, colliders and both nets.
## Everything is generated at load time from RinkSpec (also visible in the editor).

## net_index: 0 = the +Z net, 1 = the -Z net. Use team_defending() to see whose net it was.
signal goal_scored(net_index: int)

const ICE_SHADER_PATH := "res://scenes/match/ice.gdshader"
const CENTER_LOGO_WIDTH := 6.4   ## meters; the center circle is 9.1 m across
const NET_SCENE_PATH := "res://scenes/match/Net.tscn"

const SEGS := 24
const BOARD_THICKNESS := 0.15
const COLLIDER_THICKNESS := 0.5
const KICK_HEIGHT := 0.25
const ADS_DIR := "res://assets/images/ads/"   ## every image here can show up on the boards
const AD_HEIGHT := 0.7     ## meters, inside the white band above the kick plate
const AD_GAP := 1.6        ## meters of plain board between ads (stretched to fill the side)

@export var board_color := Color(0.96, 0.96, 0.94)
@export var kick_color := Color(0.95, 0.78, 0.12)
@export var cap_color := Color(0.14, 0.2, 0.36)
@export var floor_color := Color(0.16, 0.16, 0.18)
## How many different sponsors a game shows (picked at random from ADS_DIR each load).
@export var ad_count := 6
## Build the arena around the rink (stands, roof, lights, scoreboard: see Arena).
@export var build_arena := true

var ice_material: ShaderMaterial
var arena: Arena   ## null when build_arena is off (or in the editor)
var nets: Array[Net] = []
## Teams switch ends every period. Unswapped: team 0 defends the +Z net (bottom of the screen).
var ends_swapped := false
var _doors := {}   ## id ("bench0_0", "bench0_1", "box0"...) -> {pivot, sign, angle, hold}
var _bench_walls: Array[MeshInstance3D] = []   ## per team: the bench's back wall (team color)

const DOOR_OPEN := deg_to_rad(105.0)
const DOOR_SPEED := 4.5          ## rad/s
const BENCH_WALL_H := 1.15
const SEAT_H := 0.5
const SEAT_GAP := 0.6            ## meters between players on the bench seat
const SEAT_HIPS := 0.27          ## a seated player's hips: this far in front of the back wall


func _ready() -> void:
	add_to_group("rink")
	_build_ice()
	_build_boards()
	_build_ads()
	_build_colliders()
	_build_floor()
	_build_benches()
	_build_doors()
	_build_nets()
	if build_arena and not Engine.is_editor_hint():
		arena = Arena.new()
		arena.name = "Arena"
		add_child(arena)


func get_net(index: int) -> Net:
	return nets[index]


func defended_net(team: int) -> Net:
	return nets[team if not ends_swapped else 1 - team]


func attacked_net(team: int) -> Net:
	return defended_net(1 - team)


func team_defending(net_index: int) -> int:
	return net_index if not ends_swapped else 1 - net_index


func rearm_nets() -> void:
	for net in nets:
		net.rearm()


func disarm_nets() -> void:
	for net in nets:
		net.disarm()


# --- Ice -------------------------------------------------------------------

func _build_ice() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(RinkSpec.WIDTH + 0.2, RinkSpec.LENGTH + 0.2)
	ice_material = ShaderMaterial.new()
	ice_material.shader = load(ICE_SHADER_PATH)
	var params := {
		"half_w": RinkSpec.HALF_W,
		"half_l": RinkSpec.HALF_L,
		"corner_r": RinkSpec.CORNER_RADIUS,
		"goal_line_z": RinkSpec.GOAL_LINE_Z,
		"blue_line_z": RinkSpec.BLUE_LINE_Z,
		"line_wide": RinkSpec.LINE_WIDE,
		"line_thin": RinkSpec.LINE_THIN,
		"faceoff_r": RinkSpec.FACEOFF_RADIUS,
		"end_dot_x": RinkSpec.END_DOT_X,
		"end_dot_z": RinkSpec.END_DOT_Z,
		"neutral_dot_z": RinkSpec.NEUTRAL_DOT_Z,
		"crease_r": RinkSpec.CREASE_RADIUS,
	}
	for key in params:
		ice_material.set_shader_parameter(key, params[key])
	var mi := MeshInstance3D.new()
	mi.name = "Ice"
	mi.mesh = mesh
	mi.material_override = ice_material
	add_child(mi)

	# Ground plane for skaters (the puck handles the ice analytically).
	var body := StaticBody3D.new()
	body.name = "IceCollider"
	body.collision_layer = 1 << 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


## The home team's logo painted into the ice at center (under the lines), `width`
## meters across. Pass null to clear it.
func set_center_logo(tex: Texture2D, width := CENTER_LOGO_WIDTH) -> void:
	ice_material.set_shader_parameter("has_logo", tex != null)
	if tex == null:
		return
	ice_material.set_shader_parameter("center_logo", tex)
	ice_material.set_shader_parameter("logo_size", Vector2(width, width * tex.get_height() / float(tex.get_width())))


# --- Boards & glass (visual) -----------------------------------------------

func _build_boards() -> void:
	var inner := RinkSpec.perimeter(0.0, SEGS)
	var outer := RinkSpec.perimeter(BOARD_THICKNESS, SEGS)
	var glass_line := RinkSpec.perimeter(0.03, SEGS)

	var doors := RinkSpec.door_gaps()
	_add_wall(inner, 0.0, KICK_HEIGHT, true, MeshUtil.material(kick_color, 0.6), "KickPlate", doors)
	_add_wall(inner, KICK_HEIGHT, RinkSpec.BOARD_HEIGHT, true, MeshUtil.material(board_color, 0.45), "Boards", doors)
	_add_wall(outer, 0.0, RinkSpec.BOARD_HEIGHT, false, MeshUtil.material(board_color, 0.45), "BoardsOuter", doors)
	_add_cap(inner, outer, RinkSpec.BOARD_HEIGHT, MeshUtil.material(cap_color, 0.4), "BoardCap", doors)

	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.82, 0.9, 1.0, 0.12)
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_wall(glass_line, RinkSpec.BOARD_HEIGHT, RinkSpec.GLASS_TOP, true, glass, "Glass", RinkSpec.glass_gaps())
	_add_glass_rail(glass_line, RinkSpec.glass_gaps())


## Board ads: a random few sponsors this game, repeated along both long sides in a
## different order on each, the way real dasher boards repeat their sponsors.
func _build_ads() -> void:
	var files := ResourceLoader.list_directory(ADS_DIR)
	var pool: Array[Texture2D] = []
	for f in files:
		if f.get_extension() in ["png", "jpg", "jpeg", "webp"]:
			var tex := load(ADS_DIR + f) as Texture2D
			if tex:
				pool.append(tex)
	if pool.is_empty():
		return
	pool.shuffle()
	pool.resize(mini(ad_count, pool.size()))
	var y := KICK_HEIGHT + (RinkSpec.BOARD_HEIGHT - KICK_HEIGHT) * 0.5
	var half_span := RinkSpec.HALF_L - RinkSpec.CORNER_RADIUS - 0.6
	var mats := {}
	for side: float in [1.0, -1.0]:
		# The stretches of board between the doors, each filled with whole ads.
		var spans := [Vector2(-half_span, half_span)]
		for g: Array in RinkSpec.door_gaps():
			if g[0] != side:
				continue
			var next := []
			for sp: Vector2 in spans:
				if g[2] + 0.15 <= sp.x or g[1] - 0.15 >= sp.y:
					next.append(sp)
					continue
				if g[1] - 0.15 > sp.x:
					next.append(Vector2(sp.x, g[1] - 0.15))
				if g[2] + 0.15 < sp.y:
					next.append(Vector2(g[2] + 0.15, sp.y))
			spans = next
		var order := pool.duplicate()
		order.shuffle()
		var i := 0
		for sp: Vector2 in spans:
			i = _ad_row(side, sp, order, i, y, mats)


## Fills one stretch of board [span.x, span.y] (z) with whole ads, cycling through
## `order` from `i`; returns where it got to.
func _ad_row(side: float, span: Vector2, order: Array, i: int, y: float, mats: Dictionary) -> int:
		var length := span.y - span.x
		var row: Array[Texture2D] = []
		var used := 0.0
		while true:
			var tex: Texture2D = order[i % order.size()]
			var w := AD_HEIGHT * tex.get_width() / float(tex.get_height())
			if used + w + (AD_GAP if row.size() > 0 else 0.0) > length:
				break
			used += w + (AD_GAP if row.size() > 0 else 0.0)
			row.append(tex)
			i += 1
		if row.is_empty():
			return i
		var gap := (length - (used - AD_GAP * (row.size() - 1))) / float(row.size() + 1)
		var z := span.x + gap
		var n := Vector3(-side, 0.0, 0.0)   # facing the ice
		for tex in row:
			var w := AD_HEIGHT * tex.get_width() / float(tex.get_height())
			var mi := MeshInstance3D.new()
			mi.name = "Ad_%s" % tex.resource_path.get_file().get_basename()
			var q := QuadMesh.new()
			q.size = Vector2(w, AD_HEIGHT)
			mi.mesh = q
			if not mats.has(tex):
				var m := StandardMaterial3D.new()
				m.albedo_texture = tex
				m.roughness = 0.55
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mats[tex] = m
			mi.material_override = mats[tex]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var along := z + w * 0.5
			mi.transform = Transform3D(Basis.looking_at(-n, Vector3.UP),
					Vector3(side * (RinkSpec.HALF_W - 0.006), y, along))
			add_child(mi)
			z += w + gap
		return i


## The pieces of the segment a -> b left after cutting out `gaps` ([x sign, z0, z1]):
## only the straight sides (constant x) are cut. Returns [[from t, to t], ...] along a -> b.
static func _keep(a: Vector2, b: Vector2, gaps: Array) -> Array:
	if gaps.is_empty() or absf(a.x - b.x) > 0.001 or absf(a.x) < RinkSpec.HALF_W - 0.01:
		return [[0.0, 1.0]]
	var spans := [[0.0, 1.0]]
	for g: Array in gaps:
		if signf(a.x) != signf(g[0]):
			continue
		var t0: float = inverse_lerp(a.y, b.y, g[1])
		var t1: float = inverse_lerp(a.y, b.y, g[2])
		var lo := minf(t0, t1)
		var hi := maxf(t0, t1)
		var next := []
		for sp: Array in spans:
			if hi <= sp[0] or lo >= sp[1]:
				next.append(sp)
				continue
			if lo > sp[0]:
				next.append([sp[0], lo])
			if hi < sp[1]:
				next.append([hi, sp[1]])
		spans = next
	return spans


func _add_wall(pts: PackedVector2Array, y0: float, y1: float, inward: bool, mat: Material, node_name: String, gaps := []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	for i in pts.size():
		var a0 := pts[i]
		var b0 := pts[(i + 1) % pts.size()]
		var seg := b0 - a0
		var n2 := Vector2(-seg.y, seg.x).normalized()
		if (n2.dot((a0 + b0) * 0.5) > 0.0) == inward:
			n2 = -n2
		var n := Vector3(n2.x, 0.0, n2.y)
		for sp: Array in _keep(a0, b0, gaps):
			var a := a0.lerp(b0, sp[0])
			var b := a0.lerp(b0, sp[1])
			var ua: float = u + seg.length() * sp[0]
			var ub: float = u + seg.length() * sp[1]
			MeshUtil.quad(st,
					Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), n,
					Vector2(ua, y0), Vector2(ub, y0), Vector2(ub, y1), Vector2(ua, y1))
		u += seg.length()
	_add_mesh(st, mat, node_name)


func _add_cap(inner: PackedVector2Array, outer: PackedVector2Array, y: float, mat: Material, node_name: String, gaps := []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in inner.size():
		var j := (i + 1) % inner.size()
		for sp: Array in _keep(inner[i], inner[j], gaps):
			var a := inner[i].lerp(inner[j], sp[0])
			var b := inner[i].lerp(inner[j], sp[1])
			var c := outer[i].lerp(outer[j], sp[1])
			var d := outer[i].lerp(outer[j], sp[0])
			MeshUtil.quad(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3(d.x, y, d.y), Vector3.UP)
	_add_mesh(st, mat, node_name)


func _add_glass_rail(line: PackedVector2Array, gaps := []) -> void:
	# Thin top rail so the glass edge reads from the broadcast camera.
	_add_cap(line, RinkSpec.perimeter(0.09, SEGS), RinkSpec.GLASS_TOP,
			MeshUtil.material(Color(0.7, 0.72, 0.75), 0.3, 0.6), "GlassRail", gaps)


func _add_mesh(st: SurfaceTool, mat: Material, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


# --- Colliders ---------------------------------------------------------------

func _build_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "BoardsCollider"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "boards")
	var pts := RinkSpec.perimeter(0.0, SEGS)
	var bottom := -0.5
	var top := RinkSpec.GLASS_TOP
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var seg := b - a
		var length := seg.length()
		var out2 := Vector2(-seg.y, seg.x) / length
		if out2.dot((a + b) * 0.5) < 0.0:
			out2 = -out2
		var box := BoxShape3D.new()
		box.size = Vector3(length + 0.08, top - bottom, COLLIDER_THICKNESS)
		var cs := CollisionShape3D.new()
		cs.shape = box
		var c2 := (a + b) * 0.5 + out2 * COLLIDER_THICKNESS * 0.5
		var basis := MeshUtil.basis_from(Vector3(seg.x, 0.0, seg.y), Vector3.UP, Vector3(out2.x, 0.0, out2.y))
		cs.transform = Transform3D(basis, Vector3(c2.x, (top + bottom) * 0.5, c2.y))
		body.add_child(cs)
	add_child(body)


func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(140.0, 140.0)
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = mesh
	mi.material_override = MeshUtil.material(floor_color, 0.9)
	mi.position.y = -0.02
	add_child(mi)


# --- Nets ----------------------------------------------------------------------

func _build_nets() -> void:
	var scene: PackedScene = load(NET_SCENE_PATH)
	for side in 2:
		var net: Net = scene.instantiate()
		net.name = "Net%d" % side
		net.index = side
		# Each net's local +Z (its mouth) faces center ice.
		net.position = Vector3(0.0, 0.0, RinkSpec.GOAL_LINE_Z * (1.0 if side == 0 else -1.0))
		if side == 0:
			net.rotation.y = PI
		add_child(net)
		nets.append(net)
		net.goal_scored.connect(func(n: Net) -> void: goal_scored.emit(n.index))


# --- Benches, penalty boxes, doors (RinkSpec layout) ---------------------------------

## The x of a point `depth` meters out from the boards' outer face on side `sx`.
static func _out_x(sx: float, depth: float) -> float:
	return sx * (RinkSpec.HALF_W + BOARD_THICKNESS + depth)


## A box from x0..x1, y0..y1, z0..z1 (any order) as its own mesh.
func _block(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: Material, node_name: String, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	parent.add_child(mi)
	return mi


func _glass_mat() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.82, 0.9, 1.0, 0.14)
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass


## Team benches on the -X side, the penalty boxes and timekeeper on +X: a rubber floor,
## a back wall, end walls with glass partitions above, and a bench seat along the back.
## The bench backs take the team colors later (set_bench_colors).
func _build_benches() -> void:
	var root := Node3D.new()
	root.name = "BenchesAndBoxes"
	add_child(root)
	var rubber := MeshUtil.material(Color(0.09, 0.09, 0.11), 0.95)
	var wall := MeshUtil.material(cap_color, 0.5)
	var seat := MeshUtil.material(Color(0.18, 0.19, 0.23), 0.6)
	var trim := MeshUtil.material(Color(0.7, 0.72, 0.75), 0.3, 0.6)
	var glass := _glass_mat()
	_bench_walls.clear()
	for t in 2:
		# Bench.
		var sx := RinkSpec.BENCH_SIDE
		var z: Vector2 = RinkSpec.BENCH_Z[t]
		var z0 := minf(z.x, z.y)
		var z1 := maxf(z.x, z.y)
		var d := RinkSpec.BENCH_DEPTH
		var xi := _out_x(sx, 0.0)
		var xb := _out_x(sx, d)
		_block(xi, xb, -0.02, 0.012, z0, z1, rubber, "BenchFloor%d" % t, root)
		var back := _block(xb, xb + sx * 0.12, 0.0, BENCH_WALL_H, z0 - 0.06, z1 + 0.06, MeshUtil.material(cap_color, 0.5), "BenchBack%d" % t, root)
		_bench_walls.append(back)
		_block(xb, xb - sx * 0.48, 0.0, SEAT_H, z0 + 0.1, z1 - 0.1, seat, "BenchSeat%d" % t, root)
		for ez: float in [z0, z1]:
			_block(xi, xb, 0.0, RinkSpec.BOARD_HEIGHT, ez - 0.05, ez + 0.05, wall, "BenchEnd%d" % t, root)
			_block(xi - sx * 0.03, xb, RinkSpec.BOARD_HEIGHT, 2.0, ez - 0.012, ez + 0.012, glass, "BenchGlass%d" % t, root)
			_block(xi - sx * 0.03, xb, 2.0, 2.04, ez - 0.03, ez + 0.03, trim, "BenchGlassRail%d" % t, root)
		# Penalty box: same build, glass in front (the rink's own), a taller back.
		sx = RinkSpec.BOX_SIDE
		z = RinkSpec.BOX_Z[t]
		z0 = minf(z.x, z.y)
		z1 = maxf(z.x, z.y)
		d = RinkSpec.BOX_DEPTH
		xi = _out_x(sx, 0.0)
		xb = _out_x(sx, d)
		_block(xi, xb, -0.02, 0.012, z0, z1, rubber, "BoxFloor%d" % t, root)
		_block(xb, xb + sx * 0.12, 0.0, BENCH_WALL_H, z0 - 0.06, z1 + 0.06, wall, "BoxBack%d" % t, root)
		_block(xb, xb + sx * 0.03, BENCH_WALL_H, RinkSpec.GLASS_TOP, z0, z1, glass, "BoxBackGlass%d" % t, root)
		_block(xb, xb - sx * 0.48, 0.0, SEAT_H, z0 + 0.1, z1 - 0.1, seat, "BoxSeat%d" % t, root)
		for ez: float in [z0, z1]:
			_block(xi, xb, 0.0, RinkSpec.BOARD_HEIGHT, ez - 0.05, ez + 0.05, wall, "BoxEnd%d" % t, root)
			_block(xi, xb, RinkSpec.BOARD_HEIGHT, RinkSpec.GLASS_TOP, ez - 0.012, ez + 0.012, glass, "BoxGlass%d" % t, root)
		_block(xb - sx * 0.02, xb + sx * 0.06, RinkSpec.GLASS_TOP, RinkSpec.GLASS_TOP + 0.05, z0, z1, trim, "BoxRail%d" % t, root)
	# The timekeeper's box between the penalty boxes: a desk instead of a seat.
	var sx2 := RinkSpec.BOX_SIDE
	var tz: Vector2 = RinkSpec.TIMEKEEPER_Z
	var xi2 := _out_x(sx2, 0.0)
	var xb2 := _out_x(sx2, RinkSpec.BOX_DEPTH)
	_block(xi2, xb2, -0.02, 0.012, tz.x, tz.y, rubber, "TimekeeperFloor", root)
	_block(xb2, xb2 + sx2 * 0.12, 0.0, BENCH_WALL_H, tz.x, tz.y, wall, "TimekeeperBack", root)
	_block(xb2, xb2 + sx2 * 0.03, BENCH_WALL_H, RinkSpec.GLASS_TOP, tz.x, tz.y, glass, "TimekeeperBackGlass", root)
	_block(xi2 + sx2 * 0.05, xi2 + sx2 * 0.65, 0.0, 0.95, tz.x + 0.15, tz.y - 0.15, wall, "TimekeeperDesk", root)
	_block(xi2 + sx2 * 0.02, xi2 + sx2 * 0.7, 0.95, 0.99, tz.x + 0.1, tz.y - 0.1, seat, "TimekeeperDeskTop", root)
	_block(xb2 - sx2 * 0.02, xb2 + sx2 * 0.06, RinkSpec.GLASS_TOP, RinkSpec.GLASS_TOP + 0.05, tz.x, tz.y, trim, "TimekeeperRail", root)


## The bench backs in each team's color (called by MatchDirector once teams are known).
func set_bench_colors(colors: Array) -> void:
	for t in mini(colors.size(), _bench_walls.size()):
		_bench_walls[t].material_override = MeshUtil.material(colors[t], 0.5)


## The hinged doors: board-height panels in the bench boards, full-height (board and
## glass) panels in the box boards. Each swings out of the rink about its hinge.
func _build_doors() -> void:
	_doors.clear()
	for t in 2:
		for i in 2:
			var dz: Vector2 = RinkSpec.BENCH_DOORS[t][i]
			_make_door("bench%d_%d" % [t, i], RinkSpec.BENCH_SIDE, dz, false)
		_make_door("box%d" % t, RinkSpec.BOX_SIDE, RinkSpec.BOX_DOORS[t], true)


func _make_door(id: String, sx: float, dz: Vector2, glass: bool) -> void:
	var pivot := Node3D.new()
	pivot.name = "Door_" + id
	pivot.position = Vector3(sx * (RinkSpec.HALF_W + BOARD_THICKNESS * 0.5), 0.0, dz.x)
	add_child(pivot)
	var ld := signf(dz.y - dz.x)          # local +Z toward the latch
	var w := absf(dz.y - dz.x) - 0.02
	var th := BOARD_THICKNESS - 0.01
	var zc := ld * (w * 0.5 + 0.01)
	var hx := th * 0.5
	_block(-hx, hx, 0.0, KICK_HEIGHT, zc - w * 0.5, zc + w * 0.5, MeshUtil.material(kick_color, 0.6), "Kick", pivot)
	_block(-hx, hx, KICK_HEIGHT, RinkSpec.BOARD_HEIGHT, zc - w * 0.5, zc + w * 0.5, MeshUtil.material(board_color, 0.45), "Panel", pivot)
	_block(-hx - 0.01, hx + 0.01, RinkSpec.BOARD_HEIGHT, RinkSpec.BOARD_HEIGHT + 0.03, zc - w * 0.5, zc + w * 0.5, MeshUtil.material(cap_color, 0.4), "Cap", pivot)
	# A dark seam and a latch handle on the outside, so the door reads as a door.
	_block(-hx - 0.004, hx + 0.004, 0.0, RinkSpec.BOARD_HEIGHT, zc + ld * (w * 0.5 - 0.012), zc + ld * w * 0.5, MeshUtil.material(Color(0.15, 0.15, 0.17), 0.6), "Seam", pivot)
	_block(sx * hx, sx * (hx + 0.05), 0.75, 0.82, zc + ld * (w * 0.5 - 0.16), zc + ld * (w * 0.5 - 0.05), MeshUtil.material(Color(0.7, 0.72, 0.75), 0.3, 0.7), "Handle", pivot)
	if glass:
		var frame := MeshUtil.material(Color(0.7, 0.72, 0.75), 0.3, 0.6)
		var gx := -sx * (hx - 0.03)
		_block(gx - 0.008, gx + 0.008, RinkSpec.BOARD_HEIGHT + 0.03, RinkSpec.GLASS_TOP, zc - w * 0.5 + 0.03, zc + w * 0.5 - 0.03, _glass_mat(), "Glass", pivot)
		for ez: float in [zc - w * 0.5 + 0.015, zc + w * 0.5 - 0.015]:
			_block(gx - 0.02, gx + 0.02, RinkSpec.BOARD_HEIGHT + 0.03, RinkSpec.GLASS_TOP, ez - 0.015, ez + 0.015, frame, "Post", pivot)
		_block(gx - 0.03, gx + 0.03, RinkSpec.GLASS_TOP - 0.04, RinkSpec.GLASS_TOP, zc - w * 0.5, zc + w * 0.5, frame, "Top", pivot)
	# Swinging out of the rink: the latch moves toward +sx.
	_doors[id] = {"pivot": pivot, "sign": sx * ld, "angle": 0.0, "hold": 0.0}


## Opens a door (it swings out and stays open `hold` seconds, then closes).
func open_door(id: String, hold := 1.2) -> void:
	if _doors.has(id):
		_doors[id].hold = maxf(_doors[id].hold, hold)


func door_angle(id: String) -> float:
	return _doors[id].angle if _doors.has(id) else 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for id: String in _doors:
		var dr: Dictionary = _doors[id]
		dr.hold = maxf(0.0, dr.hold - delta)
		var target := DOOR_OPEN if dr.hold > 0.0 else 0.0
		dr.angle = move_toward(dr.angle, target, DOOR_SPEED * delta)
		(dr.pivot as Node3D).rotation.y = dr.angle * dr.sign


# --- Where players go off the ice ----------------------------------------------------

## The bench door `i` (0: nearer center ice, 1: nearer the end) of team `t`.
func bench_door_id(t: int, i: int) -> String:
	return "bench%d_%d" % [t, i]


func box_door_id(t: int) -> String:
	return "box%d" % t


## The middle of a door's opening, `out` meters off the boards (negative: onto the ice).
func door_point(id: String, out: float) -> Vector3:
	var t := int(id[id.length() - 1]) if id.begins_with("box") else int(id[5])
	var dz: Vector2 = RinkSpec.BOX_DOORS[t] if id.begins_with("box") else RinkSpec.BENCH_DOORS[t][int(id[7])]
	var sx := RinkSpec.BOX_SIDE if id.begins_with("box") else RinkSpec.BENCH_SIDE
	return Vector3(sx * (RinkSpec.HALF_W + BOARD_THICKNESS * 0.5 + out), 0.0, (dz.x + dz.y) * 0.5)


## The on-ice spot in front of a team's bench where changing skaters swap.
func bench_gate(t: int) -> Vector3:
	var z: Vector2 = RinkSpec.BENCH_Z[t]
	return Vector3(RinkSpec.BENCH_SIDE * (RinkSpec.HALF_W - 1.3), 0.0, (z.x + z.y) * 0.5)


## The stretch of bench between its doors (z, low to high), where players sit or stand.
func _bench_span(t: int) -> Vector2:
	var doors: Array = RinkSpec.BENCH_DOORS[t]
	var a: float = (doors[0] as Vector2).y
	var b: float = (doors[1] as Vector2).y
	return Vector2(minf(a, b) + 0.3, maxf(a, b) - 0.3)


## How many sit on team `t`'s bench seat (spots 0 .. n-1); the rest stand at the boards.
func bench_seats(t: int) -> int:
	var sp := _bench_span(t)
	return int((sp.y - sp.x) / SEAT_GAP) + 1


## Spot `i` on team `t`'s bench: first along the seat (hips over it, for the sitting
## clips), then standing at the boards, staggered between the seated players.
func bench_spot(t: int, i: int) -> Vector3:
	var sp := _bench_span(t)
	var n := bench_seats(t)
	var step := (sp.y - sp.x) / maxf(n - 1, 1)
	if i < n:
		return Vector3(_out_x(RinkSpec.BENCH_SIDE, RinkSpec.BENCH_DEPTH - SEAT_HIPS), 0.0, sp.x + step * i)
	var k := i - n
	var z := sp.x + step * (0.5 + 2.0 * k)   # every other gap, so they don't block each other
	if z > sp.y:
		z = sp.x + step * (1.5 + 2.0 * k) - (sp.y - sp.x)
	return Vector3(_out_x(RinkSpec.BENCH_SIDE, 0.5), 0.0, clampf(z, sp.x, sp.y))


## Spot `i` in team `t`'s penalty box (two seats past the door).
func box_spot(t: int, i: int) -> Vector3:
	var z: Vector2 = RinkSpec.BOX_Z[t]
	var door: Vector2 = RinkSpec.BOX_DOORS[t]
	var far := z.y if absf(z.y) > absf(z.x) else z.x
	var near := (door.x + door.y) * 0.5
	var u := 0.42 + 0.22 * (i % 3)
	return Vector3(_out_x(RinkSpec.BOX_SIDE, RinkSpec.BOX_DEPTH - SEAT_HIPS), 0.0, lerpf(near, far, u))
