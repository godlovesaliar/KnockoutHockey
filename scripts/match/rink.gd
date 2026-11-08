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

var ice_material: ShaderMaterial
var nets: Array[Net] = []
## Teams switch ends every period. Unswapped: team 0 defends the +Z net (bottom of the screen).
var ends_swapped := false


func _ready() -> void:
	_build_ice()
	_build_boards()
	_build_ads()
	_build_colliders()
	_build_floor()
	_build_nets()


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

	_add_wall(inner, 0.0, KICK_HEIGHT, true, MeshUtil.material(kick_color, 0.6), "KickPlate")
	_add_wall(inner, KICK_HEIGHT, RinkSpec.BOARD_HEIGHT, true, MeshUtil.material(board_color, 0.45), "Boards")
	_add_wall(outer, 0.0, RinkSpec.BOARD_HEIGHT, false, MeshUtil.material(board_color, 0.45), "BoardsOuter")
	_add_cap(inner, outer, RinkSpec.BOARD_HEIGHT, MeshUtil.material(cap_color, 0.4), "BoardCap")

	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.82, 0.9, 1.0, 0.12)
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_wall(glass_line, RinkSpec.BOARD_HEIGHT, RinkSpec.GLASS_TOP, true, glass, "Glass")
	_add_glass_rail(glass_line)


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
		# Fill the straight with whole ads, cycling through this game's sponsors.
		var order := pool.duplicate()
		order.shuffle()
		var row: Array[Texture2D] = []
		var used := 0.0
		var i := 0
		while true:
			var tex: Texture2D = order[i % order.size()]
			var w := AD_HEIGHT * tex.get_width() / float(tex.get_height())
			if used + w + (AD_GAP if row.size() > 0 else 0.0) > half_span * 2.0:
				break
			used += w + (AD_GAP if row.size() > 0 else 0.0)
			row.append(tex)
			i += 1
		var gap := (half_span * 2.0 - (used - AD_GAP * (row.size() - 1))) / float(row.size() + 1)
		var z := -half_span + gap
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


func _add_wall(pts: PackedVector2Array, y0: float, y1: float, inward: bool, mat: Material, node_name: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var seg := b - a
		var n2 := Vector2(-seg.y, seg.x).normalized()
		if (n2.dot((a + b) * 0.5) > 0.0) == inward:
			n2 = -n2
		var n := Vector3(n2.x, 0.0, n2.y)
		var u1 := u + seg.length()
		MeshUtil.quad(st,
				Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), n,
				Vector2(u, y0), Vector2(u1, y0), Vector2(u1, y1), Vector2(u, y1))
		u = u1
	_add_mesh(st, mat, node_name)


func _add_cap(inner: PackedVector2Array, outer: PackedVector2Array, y: float, mat: Material, node_name: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in inner.size():
		var j := (i + 1) % inner.size()
		MeshUtil.quad(st,
				Vector3(inner[i].x, y, inner[i].y), Vector3(inner[j].x, y, inner[j].y),
				Vector3(outer[j].x, y, outer[j].y), Vector3(outer[i].x, y, outer[i].y), Vector3.UP)
	_add_mesh(st, mat, node_name)


func _add_glass_rail(line: PackedVector2Array) -> void:
	# Thin top rail so the glass edge reads from the broadcast camera.
	var inner := line
	var outer := RinkSpec.perimeter(0.09, SEGS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := RinkSpec.GLASS_TOP
	for i in inner.size():
		var j := (i + 1) % inner.size()
		MeshUtil.quad(st,
				Vector3(inner[i].x, y, inner[i].y), Vector3(inner[j].x, y, inner[j].y),
				Vector3(outer[j].x, y, outer[j].y), Vector3(outer[i].x, y, outer[i].y), Vector3.UP)
	_add_mesh(st, MeshUtil.material(Color(0.7, 0.72, 0.75), 0.3, 0.6), "GlassRail")


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
