@tool
class_name Net
extends Node3D
## Gray-box goal: posts, crossbar, netting, colliders and goal-line detection.
## Local frame: the goal line runs along local X at z = 0; the mouth faces +Z; the net extends to -Z.

signal goal_scored(net: Net)

const NETTING_SHADER_PATH := "res://scenes/match/netting.gdshader"

@export var index := 0   ## 0 = the +Z net, 1 = the -Z net
@export var frame_color := Color(0.82, 0.06, 0.06)

var _puck: Node3D
var _prev_local := Vector3.ZERO
var _armed := true


func _ready() -> void:
	process_physics_priority = 20 # after the puck has moved this tick
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


func _build_frame() -> void:
	var w := RinkSpec.NET_WIDTH
	var h := RinkSpec.NET_HEIGHT
	var r := RinkSpec.POST_RADIUS
	var post_x := w * 0.5 + r
	var mat := MeshUtil.material(frame_color, 0.35, 0.3)

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
		_add_cylinder_visual(r, h + r, cs.transform, mat)

	var bar := CylinderShape3D.new()
	bar.radius = r
	bar.height = w + 4.0 * r
	var bar_cs := CollisionShape3D.new()
	bar_cs.shape = bar
	bar_cs.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, h + r, 0.0))
	body.add_child(bar_cs)
	_add_cylinder_visual(r, w + 4.0 * r, bar_cs.transform, mat)

	# Base frame tube along the ice at the back (visual only).
	var base_t := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, r, -RinkSpec.NET_DEPTH))
	_add_cylinder_visual(r * 0.8, w + 2.0 * r, base_t, mat)


func _add_cylinder_visual(radius: float, height: float, xform: Transform3D, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	add_child(mi)


func _build_netting() -> void:
	var w := RinkSpec.NET_WIDTH
	var h := RinkSpec.NET_HEIGHT
	var d := RinkSpec.NET_DEPTH
	var t := RinkSpec.NET_TOP_DEPTH
	var r := RinkSpec.POST_RADIUS
	var hx := w * 0.5 + r

	# --- Visual mesh (UVs in meters) ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Back panel slants from the top (z = -t) down to the base (z = -d).
	# Inward-facing normal (toward the mouth) of the slanted back panel.
	var back_n := Vector3(0.0, -(d - t), h).normalized()
	var slant := Vector2(h, d - t).length()
	MeshUtil.quad(st,
			Vector3(-hx, 0.0, -d), Vector3(hx, 0.0, -d), Vector3(hx, h, -t), Vector3(-hx, h, -t), back_n,
			Vector2(0, 0), Vector2(2 * hx, 0), Vector2(2 * hx, slant), Vector2(0, slant))
	# Top panel.
	MeshUtil.quad(st,
			Vector3(-hx, h, 0.0), Vector3(hx, h, 0.0), Vector3(hx, h, -t), Vector3(-hx, h, -t), Vector3.DOWN,
			Vector2(0, 0), Vector2(2 * hx, 0), Vector2(2 * hx, t), Vector2(0, t))
	# Side panels (trapezoids, drawn as a quad + triangle-ish quad).
	for sx in [-1.0, 1.0]:
		var x: float = sx * hx
		var n := Vector3(-sx, 0.0, 0.0)
		MeshUtil.quad(st,
				Vector3(x, 0.0, 0.0), Vector3(x, 0.0, -d), Vector3(x, h, -t), Vector3(x, h, 0.0), n,
				Vector2(0, 0), Vector2(d, 0), Vector2(t, h), Vector2(0, h))
	var mat := ShaderMaterial.new()
	mat.shader = load(NETTING_SHADER_PATH)
	var mi := MeshInstance3D.new()
	mi.name = "Netting"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# --- Colliders: soft "net" surface that kills the puck's speed ---
	var body := StaticBody3D.new()
	body.name = "Mesh"
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	body.set_meta("surface", "net")
	add_child(body)
	var thick := 0.04
	var below := 0.2

	var back := BoxShape3D.new()
	back.size = Vector3(2.0 * hx + 0.1, slant + below * 2.0, thick)
	var back_up := Vector3(0.0, h, d - t).normalized()
	var back_cs := CollisionShape3D.new()
	back_cs.shape = back
	var back_center := Vector3(0.0, h * 0.5, -(d + t) * 0.5) - back_n * thick * 0.5
	back_cs.transform = Transform3D(Basis(Vector3.RIGHT, back_up, back_n), back_center)
	body.add_child(back_cs)

	var top := BoxShape3D.new()
	top.size = Vector3(2.0 * hx + 0.1, thick, t + 0.05)
	var top_cs := CollisionShape3D.new()
	top_cs.shape = top
	top_cs.position = Vector3(0.0, h + thick * 0.5, -t * 0.5)
	body.add_child(top_cs)

	for sx in [-1.0, 1.0]:
		var side := BoxShape3D.new()
		side.size = Vector3(thick, h + below, d)
		var side_cs := CollisionShape3D.new()
		side_cs.shape = side
		side_cs.position = Vector3(sx * (hx + thick * 0.5), (h - below) * 0.5, -d * 0.5)
		body.add_child(side_cs)
