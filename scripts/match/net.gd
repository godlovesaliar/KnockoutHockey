@tool
class_name Net
extends Node3D
## The goal: the model (pipes, padding, netting), its colliders and goal-line detection.
## Local frame: the goal line runs along local X at z = 0; the mouth faces +Z; the net extends to -Z.
##
## The model is the project's own (tools/blender/net.py builds assets/net/net.glb). The
## colliders are built here from RinkSpec's numbers, which the model follows: the posts and
## crossbar ("post" surface) and the netting ("net": the top, and the wall from the top shelf
## down to the base, round the back corners).

signal goal_scored(net: Net)

const NETTING_SHADER_PATH := "res://scenes/match/netting.gdshader"
const MODEL_PATH := "res://assets/net/net.glb"
const PAD_COLOR := Color(0.9, 0.9, 0.9)   ## the bumper round the base, the top shelf's padding, the lacing

@export var index := 0   ## 0 = the +Z net, 1 = the -Z net
@export var frame_color := Color(0.82, 0.06, 0.06)

var _puck: Node3D
var _prev_local := Vector3.ZERO
var _armed := true


func _ready() -> void:
	process_physics_priority = 20 # after the puck has moved this tick
	_build_model()
	_build_frame()
	_build_netting()


func disarm() -> void:
	_armed = false


func rearm() -> void:
	_armed = true
	if _puck:
		_prev_local = to_local(_puck.global_position)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _puck == null:
		_puck = get_tree().get_first_node_in_group("puck")
		if _puck:
			_prev_local = to_local(_puck.global_position)
		return
	var lp := to_local(_puck.global_position)
	var r := RinkSpec.PUCK_RADIUS
	# A goal: the whole puck crosses the goal line between the posts and under the bar.
	if _armed and _prev_local.z > -r and lp.z <= -r \
			and absf(lp.x) < RinkSpec.NET_WIDTH * 0.5 and lp.y < RinkSpec.NET_HEIGHT \
			and lp.z > -RinkSpec.NET_DEPTH:
		_armed = false
		goal_scored.emit(self)
	_prev_local = lp


## Steering around the net. Returns where a body of `radius` at `from` should head next to
## reach `to` without going through this net: `to` itself when the way is clear, else the
## best corner of the net's footprint (grown by the radius). A `to` inside the footprint
## (a puck in the net) is moved out to the nearest side first.
func detour(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var hx := RinkSpec.NET_WIDTH * 0.5 + RinkSpec.POST_RADIUS * 2.0
	var d := RinkSpec.NET_DEPTH
	var f := to_local(from)
	var t := to_local(to)
	var f2 := Vector2(f.x, f.z)
	var t2 := Vector2(t.x, t.z)
	# How much room we can ask for: less when we're already up against the net.
	var c := minf(radius + 0.15, _box_dist(f2, hx, d) - 0.02)
	if c <= 0.0:
		return to # inside the frame itself (shouldn't happen): don't fight it
	var lo := Vector2(-hx - c, -d - c)
	var hi := Vector2(hx + c, c)
	if t2.x > lo.x and t2.x < hi.x and t2.y > lo.y and t2.y < hi.y:
		# Out to the nearest side of the footprint.
		var gaps := [t2.x - lo.x, hi.x - t2.x, t2.y - lo.y, hi.y - t2.y]
		var k: int = gaps.find(gaps.min())
		match k:
			0: t2.x = lo.x - 0.05
			1: t2.x = hi.x + 0.05
			2: t2.y = lo.y - 0.05
			_: t2.y = hi.y + 0.05
		to = to_global(Vector3(t2.x, t.y, t2.y))
	if not _seg_hits_box(f2, t2, lo, hi):
		return to
	var best := to
	var best_cost := INF
	for corner in [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]:
		# Aim a little past the corner so we round it instead of stopping on it.
		var p: Vector2 = corner + (corner - (lo + hi) * 0.5).normalized() * 0.25
		if _seg_hits_box(f2, p, lo, hi):
			continue
		var cost := f2.distance_to(p) + p.distance_to(t2)
		if _seg_hits_box(p, t2, lo, hi):
			cost += 3.0 # one more corner to go round
		if cost < best_cost:
			best_cost = cost
			best = to_global(Vector3(p.x, 0.0, p.y))
	best.y = from.y
	return best


## Distance from a local (x, z) point to the net's frame footprint (0 inside).
static func _box_dist(p: Vector2, hx: float, d: float) -> float:
	var qx := maxf(absf(p.x) - hx, 0.0)
	var qz := maxf(maxf(p.y, -d - p.y), 0.0)
	return Vector2(qx, qz).length()


## Whether the segment a-b passes through the inside of the box (lo, hi) (2D slab test).
static func _seg_hits_box(a: Vector2, b: Vector2, lo: Vector2, hi: Vector2) -> bool:
	var e := 0.03 # grazing an edge or corner doesn't count
	lo += Vector2(e, e)
	hi -= Vector2(e, e)
	var dir := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var o: float = a[axis]
		var v: float = dir[axis]
		if absf(v) < 1e-6:
			if o <= lo[axis] or o >= hi[axis]:
				return false
			continue
		var ta := (lo[axis] - o) / v
		var tb := (hi[axis] - o) / v
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return false
	return true


## The model, with the game's materials put on by name: the pipes in frame_color, the
## padding white, the netting drawn by its shader (its UVs are in meters along the threads).
func _build_model() -> void:
	var ps := load(MODEL_PATH) as PackedScene
	if ps == null:
		push_warning("Net: %s is missing (tools/blender/net.py builds it)" % MODEL_PATH)
		return
	var model := ps.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	var netting := ShaderMaterial.new()
	netting.shader = load(NETTING_SHADER_PATH)
	var mats := {
		"NetFrame": MeshUtil.material(frame_color, 0.35, 0.3),
		"NetPad": MeshUtil.material(PAD_COLOR, 0.85),
		"NetMesh": netting,
	}
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src and mats.has(src.resource_name):
				mi.set_surface_override_material(s, mats[src.resource_name])
		if mi.name == "net_mesh":
			mi.name = "Netting"
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The posts' and the crossbar's colliders.
func _build_frame() -> void:
	var w := RinkSpec.NET_WIDTH
	var h := RinkSpec.NET_HEIGHT
	var r := RinkSpec.POST_RADIUS
	var post_x := w * 0.5 + r

	var body := StaticBody3D.new()
	body.name = "Frame"
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	body.set_meta("surface", "post")
	add_child(body)

	for sx in [-1.0, 1.0]:
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = h + r
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(sx * post_x, (h + r) * 0.5, 0.0)
		body.add_child(cs)

	var bar := CylinderShape3D.new()
	bar.radius = r
	bar.height = w + 4.0 * r
	var bar_cs := CollisionShape3D.new()
	bar_cs.shape = bar
	bar_cs.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, h + r, 0.0))
	body.add_child(bar_cs)


## The netting's line at the top shelf or at the base, seen from above: from the -X post
## back along the side, round the corner (in `steps`), along the back and forward to the +X
## post. Points are (x, how far behind the goal line).
static func outline(depth: float, corner: float, steps := 3) -> PackedVector2Array:
	var hx := RinkSpec.NET_WIDTH * 0.5 + RinkSpec.POST_RADIUS
	var half := PackedVector2Array([Vector2(-hx, 0.0)])
	for i in steps + 1:
		var a := PI * 0.5 * i / steps
		half.append(Vector2(-hx + corner * (1.0 - cos(a)), depth - corner * (1.0 - sin(a))))
	var out := half.duplicate()
	for i in range(half.size() - 1, -1, -1):
		out.append(Vector2(-half[i].x, half[i].y))
	return out


## The netting's colliders: a soft "net" surface that kills the puck's speed. The wall is a
## slab per stretch of the outline, from the top shelf's line down to the base's (and on
## under the ice), so it turns the back corners as the model does.
func _build_netting() -> void:
	var h := RinkSpec.NET_HEIGHT
	var d := RinkSpec.NET_DEPTH
	var t := RinkSpec.NET_TOP_DEPTH
	var hx := RinkSpec.NET_WIDTH * 0.5 + RinkSpec.POST_RADIUS

	var body := StaticBody3D.new()
	body.name = "Mesh"
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	body.set_meta("surface", "net")
	add_child(body)
	var thick := 0.04
	var below := 0.2

	var top_line := outline(t, RinkSpec.NET_TOP_CORNER)
	var base_line := outline(d, RinkSpec.NET_BASE_CORNER)
	var inside := Vector3(0.0, h * 0.5, -d * 0.4)
	for i in top_line.size() - 1:
		var a := Vector3(top_line[i].x, h, -top_line[i].y)
		var b := Vector3(top_line[i + 1].x, h, -top_line[i + 1].y)
		var c := Vector3(base_line[i].x, 0.0, -base_line[i].y)
		var e := Vector3(base_line[i + 1].x, 0.0, -base_line[i + 1].y)
		c += (c - a) * (below / h)
		e += (e - b) * (below / h)
		var out := (b - a).cross(c - a).normalized()
		if out.dot(a - inside) < 0.0:
			out = -out
		var slab := ConvexPolygonShape3D.new()
		slab.points = PackedVector3Array([a, b, c, e, a + out * thick, b + out * thick, c + out * thick, e + out * thick])
		var cs := CollisionShape3D.new()
		cs.shape = slab
		body.add_child(cs)

	var top := BoxShape3D.new()
	top.size = Vector3(2.0 * hx + 0.1, thick, t + 0.05)
	var top_cs := CollisionShape3D.new()
	top_cs.shape = top
	top_cs.position = Vector3(0.0, h + thick * 0.5, -t * 0.5)
	body.add_child(top_cs)
