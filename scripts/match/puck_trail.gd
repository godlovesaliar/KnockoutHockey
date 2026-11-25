class_name PuckTrail
extends MeshInstance3D
## Rainbow Puck (a store extra): a ribbon behind the puck that runs through the colors
## and fades out over LIFE seconds. MatchDirector adds one when the extra is on.
##
## The ribbon is rebuilt every frame from the puck's last positions (where it was drawn,
## so it meets the puck exactly). It lies flat, as wide as the drawn puck, and narrows
## to its tail. A jump (a faceoff placement, a replay) starts it over, and it hides
## whenever the puck's own look is hidden (replays show a copy of the puck).

const LIFE := 0.8          ## s a point of the trail lasts
const MIN_STEP := 0.05     ## m the puck moves before the trail gets a new point
const JUMP := 3.0          ## m in one frame: not a move, a placement
const HUE_RATE := 1.4      ## times through the colors per second

var puck: Puck
var _pts: Array = []       ## [position, time laid]
var _t := 0.0
var _im := ImmediateMesh.new()
var _look: Node3D


func setup(p: Puck) -> void:
	puck = p
	name = "PuckTrail"
	_look = p.get_node_or_null("Visual")
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_mode = Node.PROCESS_MODE_ALWAYS   # (to hide during replays, which pause the game)
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m


## Points on the trail right now (tests).
func length() -> int:
	return _pts.size()


func _process(delta: float) -> void:
	if puck == null or not is_instance_valid(puck):
		return
	visible = puck.is_visible_in_tree() and (_look == null or _look.is_visible_in_tree())
	if get_tree().paused:
		return
	_t += delta
	var at := puck.get_global_transform_interpolated().origin
	if not _pts.is_empty() and at.distance_to(_pts.back()[0]) > JUMP:
		_pts.clear()
	if _pts.is_empty() or at.distance_to(_pts.back()[0]) >= MIN_STEP:
		_pts.append([at, _t])
	while not _pts.is_empty() and _t - float(_pts[0][1]) > LIFE:
		_pts.pop_front()
	_rebuild(at)


func _rebuild(head: Vector3) -> void:
	_im.clear_surfaces()
	var pts := _pts.duplicate()
	pts.append([head, _t])   # the ribbon runs right up to the puck
	if pts.size() < 2:
		return
	var half := puck.visual_radius() * 0.9
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p: Vector3 = pts[i][0]
		var a: Vector3 = pts[maxi(i - 1, 0)][0]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)][0]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.0001:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(Vector3.UP) * half
		var age := clampf((_t - float(pts[i][1])) / LIFE, 0.0, 1.0)
		var k := 1.0 - age
		# Full color near the puck (it has to read on white ice), fading late.
		var col := Color.from_hsv(fposmod(float(pts[i][1]) * HUE_RATE, 1.0), 1.0, 1.0, pow(k, 0.6))
		_im.surface_set_color(col)
		_im.surface_add_vertex(p + side * (0.25 + 0.75 * k))
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - side * (0.25 + 0.75 * k))
	_im.surface_end()
