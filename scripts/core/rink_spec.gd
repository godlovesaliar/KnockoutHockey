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
