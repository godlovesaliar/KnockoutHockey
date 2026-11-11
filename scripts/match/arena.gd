class_name Arena
extends Node3D
## The building around the rink, generated at load (the Rink adds it as a child):
##   - a stepped lower bowl that follows the rink's rounded shape, seats and fans in
##     sections split by aisles, then a cross aisle;
##   - the suite level: a balcony with a glass rail, suite seats and lit windows behind;
##   - an overhanging fascia carrying an LED ribbon board (scrolling ads and the home crest);
##   - a steeper upper bowl, a top concourse and the back wall up to the roof;
##   - the roof: trusses, a light grid over the ice and rings of lights over the stands;
##   - a four-sided scoreboard hung over center ice whose screens show the live game
##     (ArenaScreen), above the broadcast camera so it never blocks play.
## Fans are MultiMeshes split into sectors (so off-screen stands are culled) and animated in
## scenes/match/crowd.gdshader; they stand and cheer with the crowd's sound (Sfx.crowd_reacted).
## Offsets are meters out from the inner board face (RinkSpec.perimeter), heights from the ice.

const CROWD_SHADER := preload("res://scenes/match/crowd.gdshader")
const SEGS := 24

# Lower bowl.
const START := 3.4          ## the bowl's front wall (clear of the benches and boxes)
const LOW_ROWS := 18
const LOW_DEPTH := 0.85
const LOW_RISE := 0.42
const LOW_Y0 := 1.1         ## first row: fans see over the boards
# Suite level and fascia.
const CROSS_W := 1.8        ## cross aisle behind the lower bowl
const SUITE_STEP := 1.2     ## suite floor above the cross aisle
const SUITE_DEPTH := 2.6
const SUITE_H := 3.0
const OVERHANG := 0.6       ## the upper bowl's fascia juts out over the balcony
const FASCIA_H := 1.3
# Upper bowl, top concourse, roof.
const UP_ROWS := 15
const UP_DEPTH := 0.8
const UP_RISE := 0.56
const TOP_W := 2.0
const ROOF_Y := 34.0
# Center-hung scoreboard: its bottom is above the broadcast camera (24 m up).
const BOARD_Y := 25.5
const BOARD_SIZE := Vector3(5.8, 4.9, 8.6)
const GRID_X := [-10.0, -4.5, 4.5, 10.0]   ## light grid rails over the ice (clear of the scoreboard)
const SIDE_SCREEN := Vector2(8.0, 4.5)
const END_SCREEN := Vector2(5.2, 4.5)

## Render layer of everything overhead (roof, trusses, lights, scoreboard), so a camera
## up in the rafters (BroadcastCamera HIGH) can see through it.
const RAFTERS_LAYER := 1 << 10

const SEAT_W := 0.52        ## meters per seat along a row
const AISLE_W := 1.1
const SECTORS := 8          ## groups the crowd's random looks are dealt in (keep: changing it reshuffles the crowd)
## The seats and fans are drawn in chunks: CHUNK_SECTORS around the bowl by bands of
## CHUNK_ROWS rows, so off-screen chunks are culled and far ones switch to simpler fans.
const CHUNK_SECTORS := 16
const CHUNK_ROWS := 6
## Lower-bowl and suite fans whose chunk is further than this from the camera use the
## 6-sided fan (as the upper bowl always does): a fan there is only ~20 px across at 1080p.
const FAN_LOD_DIST := 30.0
## (No visibility-range margin: with one, Godot left some chunks drawing neither mesh.)

## Set while building an arena for the menus (MenuArena): everything there is far off,
## blurred and hazy, so every fan uses the simplest mesh. Performance graphics
## (GameSettings.performance) does the same everywhere.
static var low_detail := false
const RIBBON_PX := 96       ## ribbon atlas height in pixels
const RIBBON_SPEED := 1.6   ## m/s

## Crowd excitement for each reaction (Sfx.crowd_react name) and how long it holds.
const REACTIONS := {
	"goal_cheer": [1.0, 6.0], "cheer": [0.72, 2.5], "short_cheer": [0.5, 1.2],
	"rising": [0.42, 2.0], "chant_defense": [0.5, 3.0], "outrage": [0.45, 2.0],
	"big_boo": [0.35, 2.0], "boo": [0.25, 1.5], "disappointed": [0.08, 1.0],
}
const CALM := 0.04
const CASUAL := [Color(0.12, 0.13, 0.16), Color(0.85, 0.85, 0.83), Color(0.22, 0.28, 0.42),
		Color(0.4, 0.42, 0.45), Color(0.55, 0.12, 0.12), Color(0.16, 0.3, 0.2), Color(0.62, 0.55, 0.42),
		Color(0.08, 0.08, 0.09), Color(0.3, 0.45, 0.65), Color(0.7, 0.62, 0.2), Color(0.18, 0.18, 0.2),
		Color(0.5, 0.5, 0.52), Color(0.42, 0.3, 0.22), Color(0.6, 0.36, 0.42), Color(0.92, 0.9, 0.86)]
## Jackets and dark hoodies.
const DARK_WEAR := [Color(0.07, 0.07, 0.08), Color(0.12, 0.13, 0.17), Color(0.1, 0.12, 0.2),
		Color(0.22, 0.22, 0.24), Color(0.2, 0.15, 0.1), Color(0.14, 0.18, 0.14), Color(0.32, 0.33, 0.35)]

@export var seat_color := Color(0.2, 0.24, 0.36)      ## before the home team is known
@export var concrete := Color(0.27, 0.27, 0.29)

var match_ref: Node = null          ## the MatchDirector feeding the screens (null in menus)
var home_team := -1
var away_team := -1
var flash_team := -1                ## the screens show GOAL for this team until flash_until
var flash_until := 0.0

var _crowd_mat: ShaderMaterial
var _seat_mats: Array[StandardMaterial3D] = []    ## lower bowl, upper bowl
var _fans: Array[MultiMesh] = []                  ## per chunk (the detailed or only mesh)
var _fan_twins: Array = []                        ## per chunk: its far-LOD MultiMesh, or null
## Per look group (sector and bowl, see _build_seating): a random 0..1 per fan (which team
## they back), and where its fans start in _fan_slot.
var _fan_kind: Array[PackedFloat32Array] = []
var _fan_start := PackedInt32Array()
## Where each fan is drawn, in look-group order: pairs of (chunk index, instance index).
var _fan_slot := PackedInt32Array()
var _ribbons := []                  ## [material, band height in meters]: everything showing the ribbon art
var _ribbon_px := Vector2i(1, 1)    ## the ribbon atlas's size
var _excite := CALM
var _target := CALM
var _hold := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7151
	_crowd_mat = ShaderMaterial.new()
	_crowd_mat.shader = CROWD_SHADER
	for c in 2:
		# Plain albedo, no per-seat instance colors: a standard material reading instance
		# colors on a mesh without vertex colors rendered the seats full of holes on some
		# GPUs (seen on AMD integrated graphics).
		var m := StandardMaterial3D.new()
		m.roughness = 0.6
		_seat_mats.append(m)
	_build_bowl()
	var gs := get_node_or_null("/root/GameSettings")
	var was := low_detail
	if gs and gs.has_method("performance") and gs.performance():
		low_detail = true
	_build_seating()
	low_detail = was
	_build_ribbon()
	_build_roof()
	_build_lights()
	_build_scoreboard()
	_build_ribbon_texture()
	for n: String in ["Roof", "Trusses", "LightHousings", "IceLights", "StandLights", "Scoreboard"]:
		_to_rafters(get_node(n))
	_recolor()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx and sfx.has_signal("crowd_reacted"):
		sfx.crowd_reacted.connect(_on_crowd)


# --- Heights and offsets of the levels ------------------------------------------

static func low_y(i: int) -> float:
	return LOW_Y0 + i * LOW_RISE


static func low_o(i: int) -> float:
	return START + i * LOW_DEPTH


static func cross_y() -> float:
	return low_y(LOW_ROWS - 1) + LOW_RISE


static func balcony_o() -> float:
	return low_o(LOW_ROWS) + CROSS_W


static func suite_y() -> float:
	return cross_y() + SUITE_STEP


static func fascia_o() -> float:
	return balcony_o() - OVERHANG


static func up_y(i: int) -> float:
	return suite_y() + SUITE_H + FASCIA_H + i * UP_RISE


static func up_o(i: int) -> float:
	return fascia_o() + i * UP_DEPTH


static func back_o() -> float:
	return up_o(UP_ROWS) + TOP_W


# --- Public -------------------------------------------------------------------

## Dresses the arena for a game: seats in the home colors, fans in both teams' jerseys,
## the home crest on the ribbon boards and screens.
func set_teams(home: int, away: int) -> void:
	home_team = home
	away_team = away
	_recolor()
	_build_ribbon_texture()


## The match whose score and clock the screens show.
func bind_match(d: Node) -> void:
	match_ref = d


## A goal: the screens flash GOAL in the scorers' colors and the building erupts
## (the home crowd only for home goals).
func goal(team: int) -> void:
	flash_team = team
	flash_until = _now() + 6.0
	if team == 0:
		excite(1.0, 6.0)


## Raises the crowd to `level` (0..1) for at least `hold` seconds.
func excite(level: float, hold: float) -> void:
	if level >= _target or _hold <= 0.0:
		_target = maxf(level, CALM)
		_hold = maxf(_hold, hold)


func excitement() -> float:
	return _excite


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_crowd(sound: String) -> void:
	if REACTIONS.has(sound):
		excite(REACTIONS[sound][0], REACTIONS[sound][1])
	elif sound.begins_with("chant_"):
		excite(0.55, 4.0)


func _process(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
	else:
		_target = move_toward(_target, CALM, delta * 0.3)
	_excite = lerpf(_excite, _target, 1.0 - exp(-4.0 * delta))
	_crowd_mat.set_shader_parameter("excitement", _excite)
	for r: Array in _ribbons:
		var m: StandardMaterial3D = r[0]
		m.uv1_offset.x = fposmod(m.uv1_offset.x + RIBBON_SPEED * delta * m.uv1_scale.x, 1.0)


static func _to_rafters(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = RAFTERS_LAYER
	for c in n.get_children():
		_to_rafters(c)


# --- Geometry helpers -----------------------------------------------------------

static func _loop(offset: float) -> PackedVector2Array:
	return RinkSpec.perimeter(offset, SEGS)


## A vertical band around the arena at `offset`, y0..y1, facing the ice (or away).
## UV.x runs along it in meters (or meters / `u_scale`), UV.y is 0 at the top.
static func _ring_wall(st: SurfaceTool, offset: float, y0: float, y1: float, inward := true, u_scale := 1.0) -> void:
	var pts := _loop(offset)
	var u := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var seg := b - a
		var n2 := Vector2(-seg.y, seg.x).normalized()
		if (n2.dot((a + b) * 0.5) > 0.0) == inward:
			n2 = -n2
		var ub := u + seg.length() / u_scale
		MeshUtil.quad(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y),
				Vector3(n2.x, 0.0, n2.y), Vector2(u, 1.0), Vector2(ub, 1.0), Vector2(ub, 0.0), Vector2(u, 0.0))
		u = ub


## A flat band between offsets o0 and o1 at height y, facing up (or down).
static func _ring_cap(st: SurfaceTool, o0: float, o1: float, y: float, up := true) -> void:
	var inner := _loop(o0)
	var outer := _loop(o1)
	var n := Vector3.UP if up else Vector3.DOWN
	for i in inner.size():
		var j := (i + 1) % inner.size()
		MeshUtil.quad(st, Vector3(inner[i].x, y, inner[i].y), Vector3(inner[j].x, y, inner[j].y),
				Vector3(outer[j].x, y, outer[j].y), Vector3(outer[i].x, y, outer[i].y), n)


func _commit(st: SurfaceTool, mat: Material, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.75, 0.85, 0.95, 0.16)
	g.roughness = 0.05
	g.metallic = 0.3
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g


static func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## A hexahedron from 8 corners (bottom 4 then top 4, same winding) into `st`, with
## UV (part, 0) on every vertex. Faces point away from the box's center.
static func _hex(st: SurfaceTool, c: Array, part := 0.0, skip_bottom := false) -> void:
	var center := Vector3.ZERO
	for p: Vector3 in c:
		center += p / 8.0
	var faces := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for fi in faces.size():
		if skip_bottom and fi == 0:
			continue
		var f: Array = faces[fi]
		var fc: Vector3 = (c[f[0]] + c[f[1]] + c[f[2]] + c[f[3]]) / 4.0
		var uv := Vector2(part, 0.0)
		MeshUtil.quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]], (fc - center).normalized(), uv, uv, uv, uv)


static func _box(st: SurfaceTool, a: Vector3, b: Vector3, part := 0.0, skip_bottom := false) -> void:
	_hex(st, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
			Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)], part, skip_bottom)


## A square beam from p0 to p1, `h` half-thick.
static func _beam(st: SurfaceTool, p0: Vector3, p1: Vector3, h: float, part := 0.0) -> void:
	var d := (p1 - p0).normalized()
	var s := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.UP).normalized() * h
	var t := d.cross(s).normalized() * h
	_hex(st, [p0 - s - t, p0 + s - t, p0 + s + t, p0 - s + t, p1 - s - t, p1 + s - t, p1 + s + t, p1 - s + t], part)


func _block(size: Vector3, pos: Vector3, mat: Material, node_name: String, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# --- The bowl -------------------------------------------------------------------

func _build_bowl() -> void:
	var risers := _st()
	var treads := _st()
	var dark := _st()
	# Lower bowl: a riser and a tread per row (the first riser is the front wall).
	for i in LOW_ROWS:
		_ring_wall(risers, low_o(i), 0.0 if i == 0 else low_y(i - 1), low_y(i))
		_ring_cap(treads, low_o(i), low_o(i + 1), low_y(i))
	# Cross aisle, one step up.
	_ring_wall(risers, low_o(LOW_ROWS), low_y(LOW_ROWS - 1), cross_y())
	_ring_cap(treads, low_o(LOW_ROWS), balcony_o(), cross_y())
	# Suite balcony: its front wall, floor, the lit windows at the back, the soffit above.
	_ring_wall(dark, balcony_o(), cross_y(), suite_y())
	_ring_cap(treads, balcony_o(), balcony_o() + SUITE_DEPTH, suite_y())
	var top := suite_y() + SUITE_H
	_ring_cap(dark, fascia_o(), balcony_o() + SUITE_DEPTH + 0.3, top, false)
	# Upper bowl: the fascia is its first riser (the ribbon board covers its face).
	for i in UP_ROWS:
		if i > 0:
			_ring_wall(risers, up_o(i), up_y(i - 1), up_y(i))
		_ring_cap(treads, up_o(i), up_o(i + 1), up_y(i))
	# Top concourse and the back wall up to the roof.
	var ty := up_y(UP_ROWS - 1) + UP_RISE
	_ring_wall(risers, up_o(UP_ROWS), up_y(UP_ROWS - 1), ty)
	_ring_cap(treads, up_o(UP_ROWS), back_o(), ty)
	_ring_wall(dark, back_o(), ty, ROOF_Y)
	_commit(risers, MeshUtil.material(concrete, 0.85), "BowlRisers")
	_commit(treads, MeshUtil.material(concrete.darkened(0.35), 0.9), "BowlTreads")
	_commit(dark, MeshUtil.material(Color(0.07, 0.07, 0.09), 0.8), "BowlDark")

	# Suite windows: warm rooms behind glass, split by mullions.
	var win := _st()
	_ring_wall(win, balcony_o() + SUITE_DEPTH, suite_y(), top)
	_commit(win, _emissive(Color(0.42, 0.3, 0.2), 0.25), "SuiteWindows", false)
	_mullions(balcony_o() + SUITE_DEPTH - 0.02, suite_y(), top, 4.2)
	# Glass rails: the balcony front, the upper bowl front, the cross aisle.
	var glass := _st()
	_ring_wall(glass, balcony_o() + 0.03, suite_y(), suite_y() + 1.0)
	_ring_wall(glass, fascia_o() + 0.05, up_y(0), up_y(0) + 0.95)
	_commit(glass, _glass(), "GlassRails", false)
	var rails := _st()
	_ring_cap(rails, balcony_o() - 0.02, balcony_o() + 0.08, suite_y() + 1.0)
	_ring_cap(rails, fascia_o(), fascia_o() + 0.1, up_y(0) + 0.95)
	_ring_cap(rails, low_o(LOW_ROWS) - 0.03, low_o(LOW_ROWS) + 0.05, cross_y() + 0.95)
	_ring_cap(rails, START - 0.04, START + 0.06, LOW_Y0)
	_commit(rails, MeshUtil.material(Color(0.62, 0.64, 0.68), 0.3, 0.7), "Rails", false)
	# Cross-aisle rail posts (one every few meters) so the rail reads as a rail.
	var posts := _st()
	for p in _row_spots(low_o(LOW_ROWS) + 0.01, 3.0, []):
		var q: Vector2 = p[0]
		_box(posts, Vector3(q.x - 0.025, cross_y(), q.y - 0.025), Vector3(q.x + 0.025, cross_y() + 0.95, q.y + 0.025))
	_commit(posts, MeshUtil.material(Color(0.62, 0.64, 0.68), 0.3, 0.7), "RailPosts", false)


## Dark vertical strips every `every` meters along the loop at `offset`.
func _mullions(offset: float, y0: float, y1: float, every: float) -> void:
	var st := _st()
	for p in _row_spots(offset, every, []):
		var q: Vector2 = p[0]
		var n: Vector2 = p[1]
		var t := Vector2(-n.y, n.x) * 0.08
		var a := Vector3(q.x - t.x, y0, q.y - t.y)
		var b := Vector3(q.x + t.x, y0, q.y + t.y)
		MeshUtil.quad(st, a, b, b + Vector3(0, y1 - y0, 0), a + Vector3(0, y1 - y0, 0), Vector3(n.x, 0.0, n.y))
	_commit(st, MeshUtil.material(Color(0.05, 0.05, 0.06), 0.6), "Mullions", false)


# --- Seats and fans -------------------------------------------------------------

## Aisle positions as (segment index + fraction) on the perimeter loop. Every loop has the
## same structure (corner arcs of SEGS segments, then a straight), so an aisle lines up
## from row to row. Corner c's arc is segments c*(SEGS+1) .. +SEGS-1; the straight after
## it is segment c*(SEGS+1)+SEGS (after corners 0 and 2: the ends, after 1 and 3: the sides).
static func _aisles(corner_every: int) -> Array[float]:
	var out: Array[float] = []
	for c in 4:
		var base := c * (SEGS + 1)
		var k := corner_every
		while k < SEGS:
			out.append(base + k)
			k += corner_every
		var straight := base + SEGS
		if c % 2 == 0:
			out.append(straight + 0.5)
		else:
			for f in 5:
				out.append(straight + (f + 1) / 6.0)
	return out


## Spots along the loop at `offset`, `spacing` apart, in sections between `aisles`
## (centered in each section). Each spot: [position (x, z), inward normal].
static func _row_spots(offset: float, spacing: float, aisles: Array[float]) -> Array:
	var pts := _loop(offset)
	var n := pts.size()
	var cum := PackedFloat32Array([0.0])
	for i in n:
		cum.append(cum[i] + pts[i].distance_to(pts[(i + 1) % n]))
	var total: float = cum[n]
	var cuts: Array[float] = []
	for s in aisles:
		var k := int(s)
		cuts.append(cum[k] + (s - k) * (cum[k + 1] - cum[k]))
	cuts.sort()
	var sections := []   # [from, to] arc lengths
	if cuts.is_empty():
		sections.append([0.0, total])
	else:
		for i in cuts.size():
			var a: float = cuts[i] + AISLE_W * 0.5
			var b: float = (cuts[(i + 1) % cuts.size()] + (total if i == cuts.size() - 1 else 0.0)) - AISLE_W * 0.5
			sections.append([a, b])
	var out := []
	var seg := 0
	for sec: Array in sections:
		var length: float = sec[1] - sec[0]
		var count := int(floor(length / spacing))
		if aisles.is_empty():
			count = maxi(count, 1)
		var start: float = sec[0] + (length - count * spacing) * 0.5 + spacing * 0.5
		for j in count:
			var d := fposmod(start + j * spacing, total)
			seg = 0
			while seg < n - 1 and cum[seg + 1] < d:
				seg += 1
			var a := pts[seg]
			var b := pts[(seg + 1) % n]
			var t := (b - a).normalized()
			var p := a.lerp(b, (d - cum[seg]) / maxf(cum[seg + 1] - cum[seg], 0.0001))
			var nn := Vector2(-t.y, t.x)
			if nn.dot(p) > 0.0:
				nn = -nn
			out.append([p, nn])
	return out


static func _sector(p: Vector2) -> int:
	var a := atan2(p.y / RinkSpec.HALF_L, p.x / RinkSpec.HALF_W)
	return int(fposmod(a, TAU) / TAU * SECTORS) % SECTORS


## Every seat: [bowl (0 lower, 1 upper, 2 suites), transform, look group, chunk]; then
## built into per-chunk MultiMeshes of seats and of the fans sitting in most of them.
## Each fan's looks are dealt per look group (SECTORS around the bowl, by bowl) in a fixed
## order, so how the crowd is chunked for drawing never changes who sits where or what
## they wear.
func _build_seating() -> void:
	var seats := []
	var low_aisles := _aisles(6)
	var up_aisles := _aisles(3)
	for i in LOW_ROWS:
		for s in _row_spots(low_o(i) + LOW_DEPTH - 0.44, SEAT_W, low_aisles):
			seats.append([0, _seat_xf(s, low_y(i)), _sector(s[0]), _chunk(0, s[0], i / CHUNK_ROWS)])
	for i in UP_ROWS:
		# The front row is its own band: nothing in front hides its shins.
		var band := 0 if i == 0 else 1 + (i - 1) / CHUNK_ROWS
		for s in _row_spots(up_o(i) + UP_DEPTH - 0.44, SEAT_W, up_aisles):
			seats.append([1, _seat_xf(s, up_y(i)), _sector(s[0]), _chunk(1, s[0], band)])
	for r in 2:
		for s in _row_spots(balcony_o() + 0.95 + r * 1.0, 0.75, low_aisles):
			seats.append([2, _seat_xf(s, suite_y() + r * 0.25), _sector(s[0]), _chunk(2, s[0], 0)])

	var occupancy := [0.9, 0.82, 0.55]
	var groups := {}
	for s: Array in seats:
		var key: int = s[2] * 3 + s[0]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(s)
	# Deal the looks: per group, first who's in their seat (and their size), then each
	# fan's seed, keenness and team. Same draws in the same order as ever.
	var chunks := {}     # chunk -> {bowl, seats: [xf], fans: [[xf, custom data, group, k]]}
	for sector in SECTORS:
		for bowl in 3:
			var group: Array = groups.get(sector * 3 + bowl, [])
			var in_seat := []
			for s: Array in group:
				var c: int = s[3]
				if not chunks.has(c):
					chunks[c] = {"bowl": bowl, "seats": [], "fans": []}
				chunks[c].seats.append(s[1])
				if _rng.randf() < occupancy[bowl]:
					var sc := _rng.randf_range(0.92, 1.08)
					var xf: Transform3D = s[1]
					in_seat.append([Transform3D(xf.basis.scaled_local(Vector3(sc, sc, sc)), xf.origin), c])
			if in_seat.is_empty():
				continue
			var g := _fan_kind.size()
			var kinds := PackedFloat32Array()
			for k in in_seat.size():
				# seed (phase, looks), stand threshold (suites are hard to get up); the
				# outfit goes in z and w when the teams are known (_recolor).
				var keen := _rng.randf() * (0.9 if bowl < 2 else 1.6) + 0.05
				var cd := Color(_rng.randf(), keen, 0.0, 0.0)
				kinds.append(_rng.randf())
				chunks[in_seat[k][1]].fans.append([in_seat[k][0], cd, g, k])
			_fan_kind.append(kinds)
			_fan_start.append(_fan_slot.size() / 2)
			_fan_slot.resize(_fan_slot.size() + in_seat.size() * 2)

	var seat_mesh := _seat_mesh()
	var suite_mat := MeshUtil.material(Color(0.12, 0.1, 0.09), 0.4)
	# Fan meshes: the full one up close, the 6-sided one far off. Upper-bowl fans behind
	# the front row leave out their shins and shoes (behind the seat back in front).
	var full := _fan_mesh(8)
	var far := _fan_mesh(6)
	var far_no_shins := _fan_mesh(6, false)
	var keys := chunks.keys()
	keys.sort()
	for c: int in keys:
		var ch: Dictionary = chunks[c]
		var bowl: int = ch.bowl
		var tag := "%d_%d" % [bowl, c]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = seat_mesh
		mm.instance_count = ch.seats.size()
		for k in ch.seats.size():
			mm.set_instance_transform(k, ch.seats[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Seats_" + tag
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.material_override = _seat_mats[bowl] if bowl < 2 else suite_mat
		mmi.set_meta("bowl", bowl)
		add_child(mmi)
		var fans: Array = ch.fans
		if fans.is_empty():
			continue
		var near: Mesh = far
		var twin: Mesh = null
		if bowl == 1:
			near = far if _chunk_band(c) == 0 else far_no_shins
		elif not low_detail:
			near = full
			twin = far
		var idx := _fans.size()
		var fm := _fan_multimesh(near, fans)
		for k in fans.size():
			var f: Array = fans[k]
			var at: int = (_fan_start[f[2]] + f[3]) * 2
			_fan_slot[at] = idx
			_fan_slot[at + 1] = k
		var fmi := _fan_instance(fm, "Fans_" + tag)
		_fans.append(fm)
		_fan_twins.append(null)
		if twin:
			# Swap to the simpler fan once the chunk is far off (_recolor dresses the
			# twin's fans the same).
			fmi.visibility_range_end = FAN_LOD_DIST
			var tm := _fan_multimesh(twin, fans)
			var tmi := _fan_instance(tm, "FansFar_" + tag)
			tmi.visibility_range_begin = FAN_LOD_DIST
			_fan_twins[idx] = tm


func _fan_multimesh(mesh: Mesh, fans: Array) -> MultiMesh:
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_colors = true
	fm.use_custom_data = true
	fm.mesh = mesh
	fm.instance_count = fans.size()
	for k in fans.size():
		fm.set_instance_transform(k, fans[k][0])
		fm.set_instance_custom_data(k, fans[k][1])
	return fm


func _fan_instance(fm: MultiMesh, node_name: String) -> MultiMeshInstance3D:
	var fmi := MultiMeshInstance3D.new()
	fmi.name = node_name
	fmi.multimesh = fm
	fmi.material_override = _crowd_mat
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.extra_cull_margin = 1.0
	add_child(fmi)
	return fmi


## The drawing chunk of a seat at `p` in `bowl`, `band` rows back.
static func _chunk(bowl: int, p: Vector2, band: int) -> int:
	var a := atan2(p.y / RinkSpec.HALF_L, p.x / RinkSpec.HALF_W)
	var sector := int(fposmod(a, TAU) / TAU * CHUNK_SECTORS) % CHUNK_SECTORS
	return (bowl * 8 + band) * CHUNK_SECTORS + sector


static func _chunk_band(c: int) -> int:
	return (c / CHUNK_SECTORS) % 8


static func _seat_xf(spot: Array, y: float) -> Transform3D:
	var p: Vector2 = spot[0]
	var n: Vector2 = spot[1]
	var z := Vector3(n.x, 0.0, n.y)
	var x := Vector3.UP.cross(z)
	return Transform3D(Basis(x, Vector3.UP, z), Vector3(p.x, y, p.y))


## A stadium seat facing +Z, its origin on the floor at the front of the pan.
static func _seat_mesh() -> ArrayMesh:
	var st := _st()
	_box(st, Vector3(-0.23, 0.4, -0.42), Vector3(0.23, 0.46, -0.02))
	_hex(st, [Vector3(-0.23, 0.46, -0.45), Vector3(0.23, 0.46, -0.45), Vector3(0.23, 0.46, -0.39), Vector3(-0.23, 0.46, -0.39),
			Vector3(-0.23, 0.86, -0.5), Vector3(0.23, 0.86, -0.5), Vector3(0.23, 0.86, -0.44), Vector3(-0.23, 0.86, -0.44)])
	_box(st, Vector3(-0.03, 0.0, -0.3), Vector3(0.03, 0.4, -0.22))
	return st.commit()


## A seated fan in the seat's frame (facing +Z): rounded tubes with smooth normals, the
## body part in UV.x and the position along it in UV.y (see crowd.gdshader). `sides` is
## the torso and head detail (limbs get two fewer). Without `shins` the legs stop at the
## knee (capped) and there are no shoes: for rows where the seat back in front hides them.
static func _fan_mesh(sides: int, shins := true) -> ArrayMesh:
	var st := _st()
	var limb := maxi(sides - 2, 4)
	# Torso up into the neck. Ring: [center, half width, half depth, along, part of the band below].
	_tube(st, [
		[Vector3(0.0, 0.36, -0.2), 0.165, 0.12, 0.0, 0.0],
		[Vector3(0.0, 0.64, -0.19), 0.152, 0.11, 0.4, 0.35],
		[Vector3(0.0, 0.9, -0.2), 0.195, 0.118, 0.75, 0.35],
		[Vector3(0.0, 1.01, -0.2), 0.175, 0.095, 0.95, 0.35],
		[Vector3(0.0, 1.06, -0.2), 0.058, 0.052, 1.0, 0.35],
		[Vector3(0.0, 1.14, -0.19), 0.048, 0.045, 1.0, 0.8]], sides)
	for sx: float in [-1.0, 1.0]:
		# Thigh, bent knee, shin, and a shoe.
		var hip := [Vector3(sx * 0.088, 0.5, -0.26), 0.085, 0.08, 0.0, 0.0]
		var knee := [Vector3(sx * 0.095, 0.5, 0.17), 0.07, 0.07, 0.5, 0.1]
		if not shins:
			_tube(st, [hip, knee], 4, 0.05)
		else:
			_tube(st, [hip, knee,
				[Vector3(sx * 0.1, 0.07, 0.21), 0.052, 0.052, 1.0, 0.1]], 4)   # mostly hidden by the row in front
		if sides >= 8 and shins:
			_box(st, Vector3(sx * 0.1 - 0.05, 0.0, 0.13), Vector3(sx * 0.1 + 0.05, 0.085, 0.31), 0.12, true)
		# Arm: shoulder, elbow, wrist, then the hand (capped) resting on the knee.
		_tube(st, [
			[Vector3(sx * 0.2, 0.98, -0.2), 0.06, 0.062, 0.0, 0.0],
			[Vector3(sx * 0.235, 0.72, -0.17), 0.05, 0.05, 0.45, 0.6],
			[Vector3(sx * 0.19, 0.6, 0.06), 0.04, 0.037, 0.85, 0.6],
			[Vector3(sx * 0.16, 0.585, 0.15), 0.046, 0.028, 1.0, 0.65]], limb, 0.035)
	_fan_head(st, sides)
	st.index()   # share the smooth-shaded corners: about a third of the vertices to animate
	return st.commit()


## The fan's head: a lathe around FAN_HEAD with a little nose, and a cap brim the shader
## folds away unless the fan wears a cap. Hair, hats and the face are painted on.
const FAN_HEAD := Vector3(0.0, 1.21, -0.19)

static func _fan_head(st: SurfaceTool, sides: int) -> void:
	var c := FAN_HEAD
	var prof := [[-0.12, 0.05], [-0.08, 0.095], [-0.02, 0.104], [0.04, 0.102], [0.095, 0.078], [0.13, 0.0]]
	if sides < 8:
		prof = [[-0.12, 0.05], [-0.08, 0.095], [0.03, 0.105], [0.09, 0.085], [0.13, 0.0]]
	var rings := []
	for pr: Array in prof:
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(c + Vector3(sin(ang) * pr[1], pr[0], cos(ang) * pr[1]))
		rings.append(ring)
	var uv := Vector2(0.85, 0.0)
	for r in rings.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			var p := [rings[r][k], rings[r][k1], rings[r + 1][k1], rings[r + 1][k]]
			var n := []
			for q: Vector3 in p:
				n.append(((q - c) * Vector3(1.0, 1.4, 1.0)).normalized())
			_quad_n(st, p, n, [uv, uv, uv, uv])
	if sides >= 8:
		# Nose: a small wedge on the front of the face.
		var tip := c + Vector3(0.0, -0.025, 0.125)
		var base := [c + Vector3(-0.018, -0.035, 0.1), c + Vector3(0.0, 0.005, 0.104), c + Vector3(0.018, -0.035, 0.1)]
		var nuv := Vector2(0.86, 0.0)
		for i in 2:
			var a: Vector3 = base[i]
			var b: Vector3 = base[i + 1]
			var nn := (a - tip).cross(b - tip).normalized()
			if nn.z < 0.0:
				nn = -nn
			_tri_n(st, [tip, a, b], [nn, nn, nn], nuv)
		var under := Vector3(0.0, -0.6, 0.8).normalized()
		_tri_n(st, [tip, base[0], base[2]], [under, under, under], nuv)
	# Cap brim, both faces.
	var brim := [c + Vector3(-0.09, 0.05, 0.06), c + Vector3(0.09, 0.05, 0.06),
			c + Vector3(0.075, 0.035, 0.2), c + Vector3(-0.075, 0.035, 0.2)]
	var buv := Vector2(0.97, 0.0)
	var up := Vector3(0.0, 1.0, 0.1).normalized()
	_quad_n(st, brim, [up, up, up, up], [buv, buv, buv, buv])
	_quad_n(st, brim, [-up, -up, -up, -up], [buv, buv, buv, buv])


## A tube through `rings` ([center, half width, half depth, along, part of the band
## below]) with `sides` sides and smooth normals, its last end capped `cap` long (0 = open).
static func _tube(st: SurfaceTool, rings: Array, sides: int, cap := 0.0) -> void:
	var pts := []
	var nrm := []
	var axes := []
	for i in rings.size():
		var ring: Array = rings[i]
		var c: Vector3 = ring[0]
		var prev: Vector3 = rings[maxi(i - 1, 0)][0]
		var next: Vector3 = rings[mini(i + 1, rings.size() - 1)][0]
		var t := (next - prev).normalized()
		var u := (Vector3.RIGHT - t * Vector3.RIGHT.dot(t)).normalized()
		var v := t.cross(u)
		var ru: float = ring[1]
		var rv: float = ring[2]
		var rp := []
		var rn := []
		for k in sides:
			var a := TAU * (k + 0.5) / sides
			rp.append(c + u * cos(a) * ru + v * sin(a) * rv)
			rn.append((u * cos(a) / ru + v * sin(a) / rv).normalized())
		pts.append(rp)
		nrm.append(rn)
		axes.append(t)
	for i in rings.size() - 1:
		var a0: float = rings[i][3]
		var a1: float = rings[i + 1][3]
		var part: float = rings[i + 1][4]
		for k in sides:
			var k1 := (k + 1) % sides
			_quad_n(st, [pts[i][k], pts[i][k1], pts[i + 1][k1], pts[i + 1][k]],
					[nrm[i][k], nrm[i][k1], nrm[i + 1][k1], nrm[i + 1][k]],
					[Vector2(part, a0), Vector2(part, a0), Vector2(part, a1), Vector2(part, a1)])
	if cap > 0.0:
		var last := rings.size() - 1
		var t: Vector3 = axes[last]
		var tip: Vector3 = rings[last][0] + t * cap
		var uv := Vector2(rings[last][4], 1.0)
		for k in sides:
			var k1 := (k + 1) % sides
			_tri_n(st, [pts[last][k], pts[last][k1], tip], [nrm[last][k], nrm[last][k1], t], uv)


## A quad with a normal per corner (winding set from their average, as MeshUtil.quad).
static func _quad_n(st: SurfaceTool, p: Array, n: Array, uv: Array) -> void:
	var avg: Vector3 = n[0] + n[1] + n[2] + n[3]
	var order := [0, 1, 2, 0, 2, 3]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(avg) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


static func _tri_n(st: SurfaceTool, p: Array, n: Array, uv: Vector2) -> void:
	var avg: Vector3 = n[0] + n[1] + n[2]
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(avg) > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		st.set_normal(n[i])
		st.set_uv(uv)
		st.add_vertex(p[i])


## Seat colors from the home team; fans' outfits (crowd.gdshader): about a third in the
## home jersey, more in home-colored tees, hoodies and shirts under dark jackets, a few
## in the visitors' colors, the rest in everyday clothes. Some wear hats.
func _recolor() -> void:
	var home_c := seat_color
	var colors := {}
	if home_team >= 0:
		home_c = MenuStyle.team_color(home_team)
		colors = Teams.team(home_team).colors
	_seat_mats[0].albedo_color = home_c.darkened(0.3)
	_seat_mats[1].albedo_color = home_c.darkened(0.5)
	var away_colors: Dictionary = Teams.team(away_team).colors if away_team >= 0 else {}
	_crowd_mat.set_shader_parameter("home_logo", _crest(home_team))
	_crowd_mat.set_shader_parameter("away_logo", _crest(away_team))
	var pick := RandomNumberGenerator.new()
	for f in _fan_kind.size():
		var kinds := _fan_kind[f]
		pick.seed = 99 + f
		for k in kinds.size():
			var at := (_fan_start[f] + k) * 2
			var mm := _fans[_fan_slot[at]]
			var twin: MultiMesh = _fan_twins[_fan_slot[at]]   # the same fan, far off
			var i := _fan_slot[at + 1]
			var r := kinds[k]
			var casual: Color = CASUAL[pick.randi() % CASUAL.size()]
			var dark: Color = DARK_WEAR[pick.randi() % DARK_WEAR.size()]
			var o := _outfit(r, colors, away_colors, casual, dark, pick)
			var hat := 0
			var hat_col := 0
			var h := pick.randf()
			if h < 0.08:
				hat = 1                   # beanie
			elif h < 0.19:
				hat = 2                   # ball cap
			if hat > 0:
				hat_col = pick.randi() % 4      # outfit color, second color, black, white
			var cd := mm.get_instance_custom_data(i)
			cd.b = _pack_color(o[1])
			cd.a = float(o[2] + 4 * hat + 16 * hat_col + 64 * o[3])
			mm.set_instance_custom_data(i, cd)
			mm.set_instance_color(i, o[0])
			if twin:
				twin.set_instance_custom_data(i, cd)
				twin.set_instance_color(i, o[0])


## [color A, color B, outfit, crest] for a fan whose team pick is `r` (0..1). Outfits
## (A / B): 0 tee or long sleeves (A), 1 jersey (body / trim), 2 open jacket (jacket /
## shirt), 3 hoodie (A). Crest: the logo on a jersey, 1 home, 2 away, 0 none.
static func _outfit(r: float, home: Dictionary, away: Dictionary, casual: Color, dark: Color,
		pick: RandomNumberGenerator) -> Array:
	if not home.is_empty():
		var jersey: Color = home.jersey
		var trim: Color = home.trim
		if r < 0.3:
			return [jersey, trim, 1, 1]
		if r < 0.38:
			return [trim if pick.randf() < 0.4 else jersey, casual, 0 if pick.randf() < 0.6 else 3, 0]
		if r < 0.46:
			return [dark, jersey if pick.randf() < 0.7 else trim, 2, 0]
	if not away.is_empty():
		if r < 0.52:
			return [away.jersey, away.trim, 1, 2]
		if r < 0.55:
			return [dark, away.jersey, 2, 0]
	var o := pick.randf()
	if o < 0.3:
		return [dark, casual, 2, 0]
	if o < 0.5:
		return [casual if pick.randf() < 0.5 else dark, casual, 3, 0]
	return [casual, dark, 0, 0]


## A team's logo with mipmaps, for the fans' jersey crests (null: none).
static func _crest(team_id: int) -> Texture2D:
	var logo := MenuStyle.team_logo(team_id) if team_id >= 0 else null
	if logo == null:
		return null
	var img := logo.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.resize(128, maxi(1, roundi(128.0 * img.get_height() / img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A color packed into one exact float (8 bits a channel) for the crowd shader.
static func _pack_color(c: Color) -> float:
	return float(clampi(c.r8, 0, 255) + 256 * clampi(c.g8, 0, 255) + 65536 * clampi(c.b8, 0, 255))


# --- LED ribbon board -------------------------------------------------------------

func _build_ribbon() -> void:
	var y0 := suite_y() + SUITE_H + 0.12
	var y1 := up_y(0) - 0.1
	var st := _st()
	_ring_wall(st, fascia_o() - 0.01, y0, y1, true, 1.0)
	_commit(st, _ribbon_mat(y1 - y0, 1.3), "RibbonBoard", false)


## An LED material showing the ribbon art on a band `band_h` meters tall (UV.x in meters).
func _ribbon_mat(band_h: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = Color.BLACK   # added to the texture
	m.emission_energy_multiplier = energy
	m.texture_repeat = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ribbons.append([m, band_h])
	return m


## The ribbon's artwork: the sponsors from the board ads, the home crest on its color
## between every two, each at the band's height. Sets each ribbon's UV scale to match.
func _build_ribbon_texture() -> void:
	var h := RIBBON_PX
	var tiles: Array[Image] = []
	var crest := _crest_tile(h)
	var files := ResourceLoader.list_directory(Rink.ADS_DIR)
	var n := 0
	for fn in files:
		if fn.get_extension() not in ["png", "jpg", "jpeg", "webp"]:
			continue
		var tex := load(Rink.ADS_DIR + fn) as Texture2D
		var img := _img(tex)
		if img == null:
			continue
		img.resize(maxi(1, int(img.get_width() * h / float(img.get_height()))), h, Image.INTERPOLATE_BILINEAR)
		tiles.append(img)
		n += 1
		if n % 2 == 0 and crest:
			tiles.append(crest)
		if n >= 10:
			break
	if tiles.is_empty() and crest:
		tiles.append(crest)
	if tiles.is_empty():
		return
	var gap := h / 3
	var w := 0
	for t in tiles:
		w += t.get_width() + gap
	var atlas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.02, 0.02, 0.03))
	var x := 0
	for t in tiles:
		atlas.blend_rect(t, Rect2i(0, 0, t.get_width(), h), Vector2i(x, 0))
		x += t.get_width() + gap
	atlas.generate_mipmaps()
	var tex := ImageTexture.create_from_image(atlas)
	for r: Array in _ribbons:
		var m: StandardMaterial3D = r[0]
		m.emission_texture = tex
		m.uv1_scale = Vector3(h / (float(r[1]) * w), 1.0, 1.0)


## A home-team panel for the ribbon: the crest on the team color (null without a team).
func _crest_tile(h: int) -> Image:
	if home_team < 0:
		return null
	var tile := Image.create(h * 3, h, false, Image.FORMAT_RGBA8)
	tile.fill(MenuStyle.team_color(home_team))
	var logo := _img(MenuStyle.team_logo(home_team))
	if logo:
		var lh := int(h * 0.9)
		logo.resize(maxi(1, int(logo.get_width() * lh / float(logo.get_height()))), lh, Image.INTERPOLATE_BILINEAR)
		tile.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), Vector2i((tile.get_width() - logo.get_width()) / 2, (h - lh) / 2))
	return tile


static func _img(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


# --- Roof, trusses and lights ---------------------------------------------------------

func _build_roof() -> void:
	var half_x := RinkSpec.HALF_W + back_o() + 1.0
	var half_z := RinkSpec.HALF_L + back_o() + 1.0
	var st := _st()
	MeshUtil.quad(st, Vector3(-half_x, ROOF_Y, -half_z), Vector3(half_x, ROOF_Y, -half_z),
			Vector3(half_x, ROOF_Y, half_z), Vector3(-half_x, ROOF_Y, half_z), Vector3.DOWN)
	_commit(st, MeshUtil.material(Color(0.05, 0.05, 0.06), 0.9), "Roof", false)
	# Main trusses across the building: top and bottom chords with zig-zag webbing.
	var steel := _st()
	var z := -half_z + 4.0
	while z < half_z - 2.0:
		var top := ROOF_Y - 0.3
		var bot := ROOF_Y - 2.2
		_beam(steel, Vector3(-half_x, top, z), Vector3(half_x, top, z), 0.18)
		_beam(steel, Vector3(-half_x, bot, z), Vector3(half_x, bot, z), 0.15)
		var x := -half_x
		var up := true
		while x < half_x - 2.4:
			_beam(steel, Vector3(x, bot if up else top, z), Vector3(x + 2.4, top if up else bot, z), 0.07)
			x += 2.4
			up = not up
		z += 8.0
	# The light grid over the ice: four rails along the rink and cross ties.
	for gx: float in GRID_X:
		_beam(steel, Vector3(gx, 29.4, -RinkSpec.HALF_L), Vector3(gx, 29.4, RinkSpec.HALF_L), 0.22)
		for hz: float in [-RinkSpec.HALF_L + 2.0, -10.0, 10.0, RinkSpec.HALF_L - 2.0]:
			_beam(steel, Vector3(gx, 29.6, hz), Vector3(gx, ROOF_Y - 2.2, hz), 0.04)
	for tz: float in [-RinkSpec.HALF_L, -20.0, -10.0, 10.0, 20.0, RinkSpec.HALF_L]:
		_beam(steel, Vector3(-10.5, 29.4, tz), Vector3(10.5, 29.4, tz), 0.12)
	# A catwalk ring over the stands.
	var ring := _loop(START + 6.0)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		_beam(steel, Vector3(a.x, 30.5, a.y), Vector3(b.x, 30.5, b.y), 0.25)
	_commit(steel, MeshUtil.material(Color(0.2, 0.21, 0.23), 0.6, 0.5), "Trusses", false)


## Fixtures over the ice (bright, aimed down) and over the stands (dimmer), as glowing
## lenses in dark housings; a few real spot lights put the shine on the ice.
func _build_lights() -> void:
	var spots: Array[Vector3] = []     # fixture positions, ice first
	var ice_count := 0
	for gx: float in GRID_X:
		var z := -RinkSpec.HALF_L + 2.5
		while z <= RinkSpec.HALF_L - 2.5:
			spots.append(Vector3(gx, 29.0, z))
			z += 4.4
	ice_count = spots.size()
	for s in _row_spots(START + 6.0, 4.0, []):
		var p: Vector2 = s[0]
		spots.append(Vector3(p.x, 30.0, p.y))
	var housing := _st()
	var lens := _st()
	var lens_dim := _st()
	for i in spots.size():
		var p := spots[i]
		var h := 0.45 if i < ice_count else 0.32
		_box(housing, p + Vector3(-h, 0.0, -h), p + Vector3(h, 0.5, h))
		var l := lens if i < ice_count else lens_dim
		var y := p.y - 0.01
		MeshUtil.quad(l, Vector3(p.x - h * 0.8, y, p.z - h * 0.8), Vector3(p.x + h * 0.8, y, p.z - h * 0.8),
				Vector3(p.x + h * 0.8, y, p.z + h * 0.8), Vector3(p.x - h * 0.8, y, p.z + h * 0.8), Vector3.DOWN)
	_commit(housing, MeshUtil.material(Color(0.12, 0.12, 0.13), 0.5, 0.6), "LightHousings", false)
	_commit(lens, _emissive(Color(0.95, 0.97, 1.0), 9.0), "IceLights", false)
	_commit(lens_dim, _emissive(Color(1.0, 0.95, 0.88), 5.0), "StandLights", false)
	for sx: float in [-5.0, 5.0]:
		for sz: float in [-20.0, 0.0, 20.0]:
			var s := SpotLight3D.new()
			s.name = "IceSpot"
			s.position = Vector3(sx, 28.0, sz)
			s.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			s.spot_range = 36.0
			s.spot_angle = 30.0
			s.spot_attenuation = 0.6
			s.light_energy = 1.6
			s.light_specular = 0.8
			s.light_color = Color(0.94, 0.96, 1.0)
			add_child(s)


# --- Scoreboard ------------------------------------------------------------------------

func _build_scoreboard() -> void:
	var root := Node3D.new()
	root.name = "Scoreboard"
	root.position = Vector3(0.0, BOARD_Y, 0.0)
	add_child(root)
	var shell := MeshUtil.material(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var b := BOARD_SIZE
	_block(b, Vector3(0, b.y * 0.5, 0), shell, "Body", root)
	# Top and bottom LED rings (the ribbon artwork, smaller) and the crown on top.
	var rings := _st()
	for band: Vector2 in [Vector2(-0.75, -0.1), Vector2(b.y + 0.1, b.y + 0.7)]:
		var hx := b.x * 0.5 - 0.3
		var hz := b.z * 0.5 - 0.3
		var c := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
		var u := 0.0
		for i in 4:
			var p0: Vector3 = c[i]
			var p1: Vector3 = c[(i + 1) % 4]
			var n := ((p0 + p1) * 0.5).normalized()
			n = Vector3(signf(n.x) if absf(n.x) > absf(n.z) else 0.0, 0.0, signf(n.z) if absf(n.z) >= absf(n.x) else 0.0)
			var len := p0.distance_to(p1)
			MeshUtil.quad(rings, p0 + Vector3(0, band.x, 0), p1 + Vector3(0, band.x, 0), p1 + Vector3(0, band.y, 0), p0 + Vector3(0, band.y, 0), n,
					Vector2(u, 1), Vector2(u + len, 1), Vector2(u + len, 0), Vector2(u, 0))
			u += len
	var ring_mat := _ribbon_mat(0.65, 1.4)
	var rmi := MeshInstance3D.new()
	rmi.name = "LedRings"
	rmi.mesh = rings.commit()
	rmi.material_override = ring_mat
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rmi)
	_block(Vector3(b.x - 0.6, 0.65, b.z - 0.6), Vector3(0, -0.42, 0), shell, "Underside", root)
	_block(Vector3(b.x - 0.6, 0.6, b.z - 0.6), Vector3(0, b.y + 0.4, 0), shell, "Crown", root)
	_block(Vector3(b.x - 1.6, 0.5, b.z - 1.6), Vector3(0, b.y + 0.95, 0), shell, "Rigging", root)
	# Cables up to the roof trusses.
	var cable := MeshUtil.material(Color(0.35, 0.36, 0.38), 0.4, 0.8)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var top := ROOF_Y - 2.2 - BOARD_Y
			var from := Vector3(cx * (b.x * 0.5 - 1.0), b.y + 1.2, cz * (b.z * 0.5 - 1.0))
			_block(Vector3(0.05, top - from.y, 0.05), Vector3(from.x, (from.y + top) * 0.5, from.z), cable, "Cable", root)
	# The screens: wide ones face the sides (most of the crowd), narrow ones the ends.
	var wide := _screen_viewport(Vector2i(800, 450), "WideScreen")
	var narrow := _screen_viewport(Vector2i(520, 450), "NarrowScreen")
	for side: float in [-1.0, 1.0]:
		_screen_quad(root, wide, SIDE_SCREEN, Vector3(side * (b.x * 0.5 + 0.03), b.y * 0.5, 0), Vector3(side, 0, 0))
		_screen_quad(root, narrow, END_SCREEN, Vector3(0, b.y * 0.5, side * (b.z * 0.5 + 0.03)), Vector3(0, 0, side))


func _screen_viewport(px: Vector2i, node_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = px
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var screen := ArenaScreen.new()
	screen.arena = self
	screen.size = Vector2(px)
	vp.add_child(screen)
	add_child(vp)
	return vp


func _screen_quad(root: Node3D, vp: SubViewport, size: Vector2, pos: Vector3, normal: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission_texture = vp.get_texture()
	m.emission_energy_multiplier = 1.5
	m.roughness = 0.35
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# QuadMesh faces +Z: turn it to face `normal`.
	mi.transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), pos)
	root.add_child(mi)
