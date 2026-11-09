class_name RinkSpec
extends RefCounted
## Regulation rink dimensions (NHL, 200 x 85 ft) in meters, plus geometry helpers.
##
## Conventions: rink centered on the origin, length along Z, width along X, Y up.
## Home (side 0) defends the +Z net; away (side 1) defends the -Z net.

const FT := 0.3048
const IN := FT / 12.0

const LENGTH := 200.0 * FT
const WIDTH := 85.0 * FT
const HALF_L := LENGTH * 0.5
const HALF_W := WIDTH * 0.5
const CORNER_RADIUS := 28.0 * FT

const BOARD_HEIGHT := 42.0 * IN
const GLASS_TOP := 2.6

const GOAL_LINE_Z := HALF_L - 11.0 * FT
const BLUE_LINE_Z := 25.0 * FT
const LINE_WIDE := 12.0 * IN
const LINE_THIN := 2.0 * IN

const FACEOFF_RADIUS := 15.0 * FT
const END_DOT_X := 22.0 * FT
const END_DOT_Z := GOAL_LINE_Z - 20.0 * FT
const NEUTRAL_DOT_Z := BLUE_LINE_Z - 5.0 * FT
const CREASE_RADIUS := 6.0 * FT

const NET_WIDTH := 6.0 * FT
const NET_HEIGHT := 4.0 * FT
const NET_DEPTH := 40.0 * IN
const NET_TOP_DEPTH := 22.0 * IN
const POST_RADIUS := 1.1875 * IN

const PUCK_RADIUS := 1.5 * IN
const PUCK_THICKNESS := 1.0 * IN


## Signed distance from a point (x, z) to the inner board face. Negative = on the ice.
static func sdf(x: float, z: float) -> float:
	var qx := absf(x) - (HALF_W - CORNER_RADIUS)
	var qz := absf(z) - (HALF_L - CORNER_RADIUS)
	var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
	return outside + minf(maxf(qx, qz), 0.0) - CORNER_RADIUS


## Pushes (x, z) back onto the ice so it's at least `margin` from the boards.
static func clamp_inside(x: float, z: float, margin: float) -> Vector2:
	var d := sdf(x, z)
	if d <= -margin:
		return Vector2(x, z)
	var e := 0.01
	var g := Vector2(sdf(x + e, z) - sdf(x - e, z), sdf(x, z + e) - sdf(x, z - e)).normalized()
	return Vector2(x, z) - g * (d + margin)


## Closed loop of (x, z) points tracing the board face, pushed outward by `offset`.
## The corner arcs use `segs` segments each; the straight sides join the arcs.
static func perimeter(offset: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := CORNER_RADIUS + offset
	var cx := HALF_W - CORNER_RADIUS
	var cz := HALF_L - CORNER_RADIUS
	var centers := [Vector2(cx, cz), Vector2(-cx, cz), Vector2(-cx, -cz), Vector2(cx, -cz)]
	for c in 4:
		var a0 := c * PI * 0.5
		for i in segs + 1:
			var a := a0 + PI * 0.5 * float(i) / float(segs)
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts


# --- Benches and penalty boxes (NHL layout) -------------------------------------------
# Team benches sit along the -X boards in the neutral zone, one per team, each with two
# doors; the penalty boxes face them across the ice on the +X boards, with the timekeeper
# between them, one full-height door each. Teams keep their bench and box all game
# (team 0's are on the +Z half). Z ranges are [from, to] along the boards.

const BENCH_SIDE := -1.0              ## x sign of the bench boards
const BOX_SIDE := 1.0                 ## x sign of the penalty-box boards
const BENCH_Z := [Vector2(1.0, 8.6), Vector2(-8.6, -1.0)]   ## per team
const BENCH_DEPTH := 2.3              ## meters from the boards' outer face to the back wall
const BOX_Z := [Vector2(1.4, 5.4), Vector2(-5.4, -1.4)]
const BOX_DEPTH := 1.9
const TIMEKEEPER_Z := Vector2(-1.2, 1.2)
const DOOR_W := 0.8
## The bench doors (one at each end of the bench) and the box door (by the timekeeper),
## as [z of the hinge, z of the latch]: the door swings out of the rink about the hinge.
const BENCH_DOORS := [[Vector2(1.2, 2.0), Vector2(8.4, 7.6)], [Vector2(-1.2, -2.0), Vector2(-8.4, -7.6)]]
const BOX_DOORS := [Vector2(1.6, 2.4), Vector2(-1.6, -2.4)]


## Every door opening as [x sign, z0, z1] (z0 < z1), for cutting the boards.
static func door_gaps() -> Array:
	var out := []
	for t in 2:
		for dz: Vector2 in BENCH_DOORS[t]:
			out.append([BENCH_SIDE, minf(dz.x, dz.y), maxf(dz.x, dz.y)])
		var bz: Vector2 = BOX_DOORS[t]
		out.append([BOX_SIDE, minf(bz.x, bz.y), maxf(bz.x, bz.y)])
	return out


## Where the glass stops: the bench fronts are open above the boards ([x sign, z0, z1]),
## and the box doors carry their own glass.
static func glass_gaps() -> Array:
	var out := []
	for t in 2:
		var b: Vector2 = BENCH_Z[t]
		out.append([BENCH_SIDE, minf(b.x, b.y), maxf(b.x, b.y)])
		var bz: Vector2 = BOX_DOORS[t]
		out.append([BOX_SIDE, minf(bz.x, bz.y), maxf(bz.x, bz.y)])
	return out
