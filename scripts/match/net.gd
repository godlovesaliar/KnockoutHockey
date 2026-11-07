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
