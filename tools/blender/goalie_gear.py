# Builds the goalie's leg pads (pad + thigh rise) and blocker in Blender, the same way
# hand_gear.py builds the skater glove: overlapping padded volumes fused into one skin by a
# voxel remesh and smoothed, construction carved back in as stitched seams, then shading
# baked into vertex colors for scenes/actors/glove.gdshader:
#   R  open / tucked (ambient occlusion)
#   G  grey leather (knee landings, calf wedges, the blocker's palm)
#   B  stitched seams
#   A  1 - trim: the parts in the team color (outer roll, knee stack, boot stripe,
#      thigh-rise roll, blocker border)
# Exported to assets/equip/goalie_pad.glb, goalie_boot.glb, goalie_thigh.glb, blocker.glb,
# goalie_catcher.glb;
# tools/build_gear.gd (only=goalie_gear) turns them into assets/characters/*.res.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/goalie_gear.py").read()); build_all(True)
# The Old-Time Set's leather pads, waffle board and mitt: build_old(True) -> goalie_pad_old.glb,
# goalie_boot_old.glb, goalie_thigh_old.glb, blocker_old.glb, goalie_catcher_old.glb
# (build_gear.gd only=old).
#
# Frames (game coordinates, meters, sized for a 1.8 m body; GoalieVisual places them):
#   pad    a LEFT leg pad: origin at the ankle joint, +Y up the shin (to the knee at
#          0.42), +Z forward, +X the outer side. The right pad is the same one mirrored.
#   boot   the pad's boot, same frame as the pad (the game hangs it on the foot).
#   thigh  the left thigh rise: origin at the knee, +Y on up the shin's line, +Z forward,
#          +X out (rides the shin with the pad).
#   blocker  on the right hand: origin at the wrist, +Y along the hand, +Z the board's
#          side (the hand frame's z), +X the hand frame's x.

import math
import os

import bpy
from mathutils import Vector

_here = os.path.dirname(os.path.abspath(globals().get(
    "__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\goalie_gear.py")))
_hg = {"__file__": os.path.join(_here, "hand_gear.py"), "__name__": "hand_gear"}
exec(compile(open(_hg["__file__"]).read(), _hg["__file__"], "exec"), _hg)
for _k, _v in _hg.items():
    if not _k.startswith("__"):
        globals()[_k] = _v

G3 = (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0)))   # game x, y, z in Blender
SHIN = 0.42


def _pillow(bm, c, r, sq=PAD):
    _ellipsoid(bm, g(*c), G3, r, sq)


def _seams(lines):
    """Groove function from [(axis 'x'|'y', value, (lo, hi) along the other axis,
    front_only)]: a stitched line on the pad's face."""
    def fn(p, n):
        d = 0.0
        for axis, val, (lo, hi), front in lines:
            if front and n.z < 0.35:
                continue
            if axis == "y":
                if lo <= p.x <= hi:
                    d += _groove(abs(p.y - val), 0.0016, 0.0016)
            else:
                if lo <= p.y <= hi:
                    d += _groove(abs(p.x - val), 0.0016, 0.0014)
        return d
    return fn


# --- Leg pad -----------------------------------------------------------------------

def build_pad(voxel=0.0028, tris=6000):
    """The shin part, from the ankle to above the knee (the boot is build_boot: it rides
    the foot, so the skate under it can flex without poking through)."""
    bm = bmesh.new()
    # Face: a tall, flat-fronted pillow up past the knee.
    _pillow(bm, (0.008, 0.215, 0.06), (0.13, 0.255, 0.075), 0.3)
    # Side wings wrapping the leg most of the way round (the back stays open, as on real
    # pads, but the socks under it don't show from the side).
    _pillow(bm, (0.112, 0.2, -0.015), (0.03, 0.24, 0.095), 0.45)
    _pillow(bm, (-0.104, 0.2, -0.015), (0.03, 0.24, 0.095), 0.45)
    # Knee stack, proud of the face.
    _pillow(bm, (0.0, 0.4, 0.13), (0.1, 0.058, 0.035), 0.4)
    # Outer roll down the outside edge.
    _tube(bm, [g(0.128, y, 0.07) for y in (-0.02, 0.06, 0.15, 0.25, 0.35, 0.42, 0.46)], [(0.022, 0.022)] * 7)
    # Inside: knee landing block and calf wedge (they take the ice in the butterfly).
    _pillow(bm, (-0.1, 0.4, 0.015), (0.045, 0.065, 0.07), 0.45)
    _pillow(bm, (-0.096, 0.15, -0.035), (0.032, 0.14, 0.042), 0.45)
    obj = make_object("GoaliePad", bm)
    _fuse(obj, voxel, 12, 0.6)
    seams = _seams([
        ("y", 0.338, (-0.14, 0.11), True),     # under the knee stack
        ("x", -0.045, (0.0, 0.33), True),      # vertical channels down the face
        ("x", 0.04, (0.0, 0.33), True),
        ("x", 0.104, (-0.03, 0.46), True),     # along the outer roll
    ])
    _carve(obj, seams)
    _decimate(obj, tris)

    def trim(p, n):
        roll = _smoothstep(0.1, 0.108, p.x) * _smoothstep(0.03, 0.05, p.z)
        knee = _smoothstep(0.342, 0.35, p.y) * (1 - _smoothstep(0.455, 0.465, p.y)) * _smoothstep(0.1, 0.115, p.z)
        return max(roll, knee)

    def landing(p, n):
        return _smoothstep(-0.075, -0.085, p.x) * _smoothstep(0.3, 0.7, -n.x)

    _bake_colors(obj, landing, seams, trim, reach=0.05)
    obj.data.materials.append(material("PadMat", (0.92, 0.92, 0.9, 1.0)))
    return obj


def build_boot(voxel=0.0026, tris=2600):
    """The pad's boot: over the skate from the ankle down, curving forward over the toe.
    Same frame as the pad (origin at the ankle, +Y up the shin), but the game hangs it on
    the foot. Long and wide enough to cover a skate toed out in the stance."""
    bm = bmesh.new()
    # upper part reaching up inside the pad, so they still overlap when the foot flexes
    # (deep enough at the front to cover the skate's tongue)
    _pillow(bm, (0.01, -0.02, 0.07), (0.134, 0.075, 0.105), 0.4)
    _pillow(bm, (0.014, -0.093, 0.16), (0.14, 0.098, 0.15), 0.4)   # down to the ice, over the toe box
    _tube(bm, [g(0.13, y, 0.07) for y in (-0.16, -0.1, -0.03)], [(0.021, 0.021)] * 3)
    obj = make_object("GoalieBoot", bm)
    _fuse(obj, voxel, 10, 0.6)
    seams = _seams([("y", -0.06, (-0.14, 0.12), True), ("x", 0.104, (-0.14, -0.01), True)])
    _carve(obj, seams)
    _decimate(obj, tris)

    def trim(p, n):
        roll = _smoothstep(0.1, 0.108, p.x) * _smoothstep(0.03, 0.05, p.z)
        stripe = _smoothstep(-0.052, -0.048, p.y) * (1 - _smoothstep(-0.03, -0.026, p.y)) * _smoothstep(0.0, 0.03, n.z)
        return max(roll, stripe)

    _bake_colors(obj, None, seams, trim, reach=0.04)
    obj.data.materials.append(material("PadMat", (0.92, 0.92, 0.9, 1.0)))
    return obj


def build_thigh(voxel=0.0026, tris=2400):
    """Thigh rise: stands up from the pad's top in line with the shin (rigid with the pad,
    as on real pads), so it covers the knee and the front of the thigh in a crouch."""
    bm = bmesh.new()
    _pillow(bm, (0.005, 0.12, 0.08), (0.12, 0.125, 0.05), 0.35)
    _tube(bm, [g(x, 0.235, 0.09) for x in (-0.1, -0.05, 0.0, 0.05, 0.1)], [(0.021, 0.021)] * 5)
    obj = make_object("GoalieThigh", bm)
    _fuse(obj, voxel, 10, 0.6)
    seams = _seams([("y", 0.213, (-0.12, 0.12), True), ("x", 0.0, (0.0, 0.2), True)])
    _carve(obj, seams)
    _decimate(obj, tris)
    _bake_colors(obj, None, seams, lambda p, n: _smoothstep(0.215, 0.223, p.y), reach=0.04)
    obj.data.materials.append(material("PadMat", (0.92, 0.92, 0.9, 1.0)))
    return obj


# --- Blocker -----------------------------------------------------------------------

def build_blocker(voxel=0.0022, tris=5000):
    bm = bmesh.new()
    # The board: flat, rounded corners, off the back of the hand.
    _pillow(bm, (0.0, 0.06, 0.11), (0.19, 0.14, 0.022), 0.22)
    # Padded mitt under it, holding the stick, and a short cuff up the wrist.
    _pillow(bm, (0.0, 0.065, 0.05), (0.062, 0.088, 0.05), 0.5)
    for x in (-0.03, 0.0, 0.03):     # finger rolls on the palm side
        _tube(bm, [g(x, y, -0.005) for y in (0.03, 0.07, 0.11, 0.135)], [(0.016, 0.018)] * 4)
    _tube(bm, [g(0.0, y, 0.035) for y in (-0.085, -0.06, -0.03, 0.0)], [(0.058, 0.052)] * 4)
    obj = make_object("Blocker", bm)
    _fuse(obj, voxel, 10, 0.6)

    def seams(p, n):
        d = 0.0
        if n.z > 0.5 and p.z > 0.115:     # the board's face
            # a stitched border inset from the edge, two channels across
            ex = 0.19 - 0.022 - abs(p.x)
            ey = 0.14 - 0.022 - abs(p.y - 0.06)
            if ex > -0.003 and ey > -0.003:
                d += _groove(min(ex, ey), 0.0016, 0.0016)
            for y in (0.02, 0.1):
                if abs(p.x) < 0.165:
                    d += _groove(abs(p.y - y), 0.0016, 0.0012)
        # finger breaks on the mitt
        if p.z < 0.01:
            for y in (0.06, 0.1):
                d += _groove(abs(p.y - y), 0.0015, 0.0015)
        return d
    _carve(obj, seams)
    _decimate(obj, tris)

    def trim(p, n):
        # border band round the board's face and its edge
        ex = 0.19 - abs(p.x)
        ey = 0.14 - abs(p.y - 0.06)
        on_board = _smoothstep(0.075, 0.09, p.z)
        return on_board * (1.0 - _smoothstep(0.018, 0.024, min(ex, ey)))

    def palm(p, n):
        return _smoothstep(0.01, -0.01, p.z) * _smoothstep(0.2, 0.6, -n.z) * (1 - _smoothstep(-0.02, -0.03, p.y))

    _bake_colors(obj, palm, seams, trim, reach=0.04)
    obj.data.materials.append(material("PadMat", (0.92, 0.92, 0.9, 1.0)))
    return obj


# --- Catcher -------------------------------------------------------------------------
#
# A trapper is a padded clam: one broad palm sheet whose thumb side folds well forward
# and whose finger side and toe curl up a little, so it closes round a deep pocket. A
# laced binding runs round its whole edge, an open net web fills the notch between the
# thumb's tip and the long finger lobe, a tall hollow cuff takes the wrist, and padded
# bands wrap the back of the hand. Frame (game): origin at the hand, fingers +Y on along the
# forearm (the cuff toward -Y), pocket +Z, thumb -X (a left hand). It is laid out below with
# the thumb on +X and mirrored at the end.

C_Z0 = 0.036                                       # mid-plane of the palm sheet
C_FINGER = ((-0.05, 0.11), (0.095, 0.2), 2.4)      # (center, radii, exponent) of the long lobe
C_THUMB = ((0.1, 0.03), (0.065, 0.13), 2.2)        # the thumb lobe
C_WEB = ((0.14, 0.135), (-0.01, 0.3))              # the web's free edge: thumb tip to the lobe
C_WEB_BOW = 0.055                                  # how far that edge rounds outward
C_NOTCH = (0.035, 0.14)                            # where the lobes meet under the web


def _web_edge(n=14):
    """The web's free edge (game x, y), from the thumb's tip round to the finger lobe."""
    (ax, ay), (bx, by) = C_WEB
    ln = math.hypot(bx - ax, by - ay)
    nx, ny = (by - ay) / ln, -(bx - ax) / ln          # outward (away from the palm)
    return [(ax + (bx - ax) * k / n + nx * C_WEB_BOW * math.sin(math.pi * k / n),
             ay + (by - ay) * k / n + ny * C_WEB_BOW * math.sin(math.pi * k / n)) for k in range(n + 1)]


def _web_strap():
    """The T-web's strap: from the middle of the free edge down to the notch."""
    e = _web_edge()
    m = e[len(e) // 2]
    pts = [(m[0] + (C_NOTCH[0] - m[0]) * k / 12, m[1] + (C_NOTCH[1] - m[1]) * k / 12) for k in range(13)]
    # it ends where it runs into the lobes' binding (on into the pocket, it left a lump)
    n = next((k for k, p in enumerate(pts) if _in_sheet(*p)), len(pts))
    return pts[:n + 1]


def _seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay)))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - ay * t)


def _poly_dist(p, pts):
    return min(_seg_dist(p, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def _se_inside(shape, x, y):
    (cx, cy), (rx, ry), e = shape
    return (abs(x - cx) / rx) ** e + (abs(y - cy) / ry) ** e


def _bowl(x, y):
    """Height of the palm sheet's mid-plane: the thumb folds forward, the finger edge and
    the toe curl up, a dish in the middle."""
    z = C_Z0
    z += 6.0 * max(0.0, x - 0.02) ** 2
    z += 4.5 * max(0.0, -x - 0.03) ** 2
    z += 2.4 * max(0.0, y - 0.17) ** 2
    z -= 0.022 * math.exp(-((x / 0.075) ** 2 + ((y - 0.08) / 0.11) ** 2))
    return z


C_HEEL = ((0.03, -0.035), (0.1, 0.07), 2.5)       # fills the V between the lobes at the wrist


_SOLID_WEB = False    # the old-time mitt: the web is leather, part of the palm sheet


def _in_web_poly(x, y):
    """Inside the web's outline: its free edge closed through the notch."""
    poly = _web_edge() + [C_NOTCH]
    inside = False
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i - 1], poly[i]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def _in_sheet(x, y):
    if any(_se_inside(s, x, y) < 1.0 for s in (C_FINGER, C_THUMB, C_HEEL)):
        return True
    # (and round the notch, where the lobes' outlines leave a sliver open under the web)
    return _SOLID_WEB and (_in_web_poly(x, y) or math.hypot(x - C_NOTCH[0], y - C_NOTCH[1]) < 0.03)


def _catcher_rim(n=420):
    """The palm sheet's outline, counter-clockwise from the wrist on the thumb side round
    to the wrist on the finger side, as game (x, y) points (not across the bottom, which
    runs into the cuff)."""
    cx, cy = 0.0, 0.08
    pts = []
    for k in range(n):
        a = math.tau * k / n
        dx, dy = math.cos(a), math.sin(a)
        last = 0.0
        for j in range(1, 200):
            if _in_sheet(cx + dx * j * 0.002, cy + dy * j * 0.002):
                last = j * 0.002
        pts.append((cx + dx * last, cy + dy * last))
    keep = [p[1] > -0.06 for p in pts]
    start = next(k for k in range(n) if keep[k] and not keep[k - 1])
    pts = [pts[(start + k) % n] for k in range(n)]
    return pts[:next((k for k in range(n) if pts[k][1] <= -0.06), n)]


def _in_web(x, y, margin=0.0):
    """Inside a net window: within the web's free edge, outside both lobes and clear of the
    strap, at least `margin` in from all of them."""
    e = _web_edge()
    poly = e + [C_NOTCH]
    inside = False
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i - 1], poly[i]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    if not inside:
        return False
    p = (x, y)
    return (_poly_dist(p, e) > margin + 0.008 and _poly_dist(p, _web_strap()) > margin + 0.012
            and _se_inside(C_FINGER, x, y) > 1.0 + margin * 12 and _se_inside(C_THUMB, x, y) > 1.0 + margin * 12)


def _web_depth(x, y):
    """0 at the web's edge, rising to 1 a couple of centimeters in."""
    return sum(_in_web(x, y, m) for m in (0.004, 0.009, 0.014, 0.02)) / 4.0


def _sheet(bm, step=0.004):
    """The palm sheet over both lobes (a single surface; solidified by the caller)."""
    tmp = bmesh.new()
    xs = [-0.16 + step * i for i in range(int(0.33 / step) + 1)]
    ys = [-0.11 + step * j for j in range(int(0.45 / step) + 1)]
    vs = {}
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            if _in_sheet(x, y):
                vs[i, j] = tmp.verts.new(g(x, y, _bowl(x, y)))
    for (i, j), v in vs.items():
        q = [vs.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
        if all(q):
            tmp.faces.new(q)
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    _merge(bm, tmp)


def build_catcher(voxel=0.0024, tris=7000, old=False):
    """Goalie trapper on the left hand (see the section comment); about 0.45 long.
    old: the Old-Time Set's mitt, closer to a first baseman's than a trapper: the web a
    solid piece of leather laced in with the rest (no net), a rounder leather gauntlet
    for a cuff, a plain padded back."""
    global _SOLID_WEB
    _SOLID_WEB = old
    try:
        return _build_catcher(voxel, tris, old)
    finally:
        _SOLID_WEB = False


def _build_catcher(voxel, tris, old):
    # The palm sheet, thickened.
    bm = bmesh.new()
    _sheet(bm)
    obj = make_object("CatcherOld" if old else "Catcher", bm)
    so = obj.modifiers.new("Solidify", "SOLIDIFY")
    so.thickness = 0.034
    so.offset = 0.0
    _apply_all(obj)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Laced binding round the whole outline (a proud bead, thicker than the sheet).
    # It stops where the lobes run into the cuff (carried on across the bottom, it came out
    # of the cuff's top as lumps in the pocket).
    rim = _catcher_rim()
    # It breaks off in the notch under the web, where it would dip into the pocket as a
    # lump (the strap and the net tie in there instead).
    runs, run = [], []
    for x, y in rim[::3]:
        if math.hypot(x - C_NOTCH[0], y - C_NOTCH[1]) < 0.035:
            if run:
                runs.append(run)
            run = []
        else:
            run.append(g(x, y, _bowl(x, y)))
    runs.append(run)
    for run in runs:
        if len(run) >= 2:
            _tube(bm, run, [(0.013, 0.021)] * len(run), across=Vector((0, 0, 1)), segs=14)
    # The web's free edge: a rounded binding from the thumb's tip to the finger lobe, and
    # the T's strap down its middle (two net windows either side).
    web_edge = _web_edge()
    strap = _web_strap() if not old else []
    if not old:
        _tube(bm, [g(x, y, _bowl(x, y)) for x, y in web_edge], [(0.012, 0.016)] * len(web_edge),
              across=Vector((0, 0, 1)), segs=14)
        _tube(bm, [g(x, y, _bowl(x, y) - 0.004) for x, y in strap], [(0.014, 0.008)] * len(strap),
              across=Vector((0, 0, 1)), segs=14)
    # Cuff: tall and boxy over the wrist (hollowed below); the old mitt's a rounder gauntlet.
    if old:
        _pillow(bm, (0.004, -0.14, 0.004), (0.09, 0.088, 0.064), 0.55)
    else:
        _pillow(bm, (0.008, -0.15, 0.004), (0.13, 0.08, 0.078), 0.3)
    # Back of the hand: a padded block, and bands wrapping across it and round its sides.
    _pillow(bm, (-0.03, 0.06, -0.005), (0.105, 0.14, 0.04), 0.45)
    band = ((-0.118, -0.008), (-0.105, -0.032), (-0.075, -0.044), (-0.03, -0.048), (0.015, -0.044), (0.05, -0.033), (0.066, -0.012))
    for y in ((0.0, 0.11) if old else (-0.04, 0.02, 0.08, 0.14)):
        _tube(bm, [g(x, y, z) for x, z in band], [(0.012, 0.009), (0.02, 0.014)] + [(0.022, 0.016)] * (len(band) - 4) + [(0.02, 0.014), (0.012, 0.009)], across=Vector((0, 0, 1)))
    bm.to_mesh(obj.data)
    bm.free()
    _fuse(obj, voxel, 10, 0.6)

    # The hand's way in: a hollow up the cuff from its open end.
    bmh = bmesh.new()
    _pillow(bmh, (0.0, -0.21, 0.0), (0.052, 0.085, 0.046), 0.6)
    hole = make_object("CatcherHole", bmh)
    bo = obj.modifiers.new("Hollow", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = hole
    _apply_all(obj)
    bpy.data.objects.remove(hole, do_unlink=True)
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 3
    _apply_all(obj)

    # Lacing along the binding: arc length round the rim, for the lace grooves.
    from mathutils.kdtree import KDTree
    rim_s, s = [], 0.0
    for k, p in enumerate(rim):
        if k:
            s += math.hypot(p[0] - rim[k - 1][0], p[1] - rim[k - 1][1])
        rim_s.append(s)
    edge_s = [0.0]
    for k in range(1, len(web_edge)):
        edge_s.append(edge_s[-1] + math.hypot(web_edge[k][0] - web_edge[k - 1][0], web_edge[k][1] - web_edge[k - 1][1]))
    lines = [(p, s) for p, s in zip(rim, rim_s) if math.hypot(p[0] - C_NOTCH[0], p[1] - C_NOTCH[1]) >= 0.035]
    if not old:
        lines += [(p, s) for p, s in zip(web_edge, edge_s)]
    kd = KDTree(len(lines))
    for i, (p, _s) in enumerate(lines):
        kd.insert(Vector((p[0], p[1], 0.0)), i)
    kd.balance()

    def near_rim(p):
        co, i, d = kd.find(Vector((p.x, p.y, 0.0)))
        return i, d

    def pocket_r(p):
        return math.sqrt((p.x / 0.055) ** 2 + ((p.y - 0.06) / 0.085) ** 2)

    def carve(p, n):
        d = 0.0
        i, dist = near_rim(p)
        if p.y > -0.075 and dist < 0.03:
            # lace crossings over the binding, and the seam where it meets the sheet
            ph = (lines[i][1] / 0.024) % 1.0
            d += _groove(min(ph, 1 - ph) * 0.024, 0.0022, 0.0016) * _smoothstep(0.022, 0.012, dist)
            d += _groove(abs(dist - 0.014), 0.0018, 0.0014)
        if n.z > 0.3 and p.y < 0.14:
            # stitched U-shapes round the pocket
            r = pocket_r(p)
            for lv in (1.0, 1.4, 1.8):
                d += _groove(abs(r - lv) * 0.055, 0.0015, 0.0012)
        if old and n.z > 0.2 and _in_web_poly(p.x, p.y):
            # the leather web: laced to the thumb and the finger lobe along both edges,
            # and a stitched line down its middle
            for lobe in (C_FINGER, C_THUMB):
                e = _se_inside(lobe, p.x, p.y) - 1.0
                d += _groove(e * 0.05, 0.002, 0.0016)
            mid = _web_edge()[7]
            d += _groove(_seg_dist((p.x, p.y), mid, C_NOTCH), 0.0016, 0.0012)
        # cuff: the seam where it meets the glove and a panel line round its middle
        d += _groove(abs(p.y + 0.072), 0.002, 0.0018)
        d += _groove(abs(p.y + 0.15), 0.0016, 0.0012) * _smoothstep(0.06, 0.07, abs(p.z) + abs(p.x) * 0.5)
        # breaks between the bands on the back
        if n.z < -0.4:
            for y in (-0.01, 0.05, 0.11):
                d += _groove(abs(p.y - y), 0.0018, 0.0016)
        return d

    _carve(obj, carve)
    _decimate(obj, tris)

    # The net: crossing cords across the web, built after the remesh (too fine for it).
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    solid_verts = len(bm.verts)
    sp = 0.017
    for dx_, dy_ in (() if old else ((0.7071, 0.7071), (0.7071, -0.7071))):
        for k in range(-30, 31):
            pts = []
            for t in range(-60, 61):
                u = t * 0.004
                x = 0.09 + dx_ * u - dy_ * k * sp
                y = 0.2 + dy_ * u + dx_ * k * sp
                if _in_web(x, y, 0.004):
                    pts.append((x, y))
                elif len(pts) >= 2:
                    break
                else:
                    pts = []
            if len(pts) >= 2:
                # extend each cord into the binding so it is tied off
                (x0, y0), (x1, y1) = pts[0], pts[-1]
                dx, dy = (x1 - x0), (y1 - y0)
                ln = math.hypot(dx, dy)
                ex, ey = dx / ln * 0.012, dy / ln * 0.012
                pts = [(x0 - ex, y0 - ey)] + pts + [(x1 + ex, y1 + ey)]
                pts = pts[::2] + ([pts[-1]] if len(pts) % 2 == 0 else [])
                # the net sags back into the pocket away from its binding
                cord = [g(x, y, _bowl(x, y) - 0.012 * _web_depth(x, y)) for x, y in pts]
                add_sweep(bm, cord, [(0.0022, 0.0022)] * len(cord), segs=6, across=Vector((0, 0, 1)))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.shade_smooth()

    def pocket(p, n):
        return _smoothstep(0.2, 0.5, n.z) * (1 - _smoothstep(1.7, 1.9, pocket_r(p)))

    def trim(p, n):
        i, dist = near_rim(p)
        bind = (1 - _smoothstep(0.011, 0.015, dist)) * _smoothstep(-0.08, -0.07, p.y)
        if strap:
            bind = max(bind, 1 - _smoothstep(0.013, 0.017, _poly_dist((p.x, p.y), strap)))
        cuff_end = 1 - _smoothstep(-0.215, -0.205, p.y)
        cuff_band = _smoothstep(-0.135, -0.13, p.y) * (1 - _smoothstep(-0.098, -0.093, p.y)) * _smoothstep(-0.2, 0.2, -n.y)
        return max(bind, cuff_end, cuff_band)

    _bake_colors(obj, pocket, carve, trim, reach=0.05)
    # The net is dark cord.
    col = obj.data.color_attributes["glove"]
    for i in range(solid_verts, len(obj.data.vertices)):
        col.data[i].color = (0.05, 1.0, 0.0, 1.0)
    # Everything above is laid out with the thumb on +X, which is a right hand; mirror it
    # into the left hand it is worn on (thumb on -X).
    me = obj.data
    for v in me.vertices:
        v.co.x = -v.co.x
    me.flip_normals()
    me.update()
    obj.data.materials.append(material("PadMat", (0.92, 0.92, 0.9, 1.0)))
    return obj


# --- The old-time set ------------------------------------------------------------------
#
# Leather pads stuffed with deer hair, as goalies wore them before foam: narrower and
# rounder than the modern slab, the shin a row of stuffed ribs between stitched channels,
# three fat rolls across the knee, one roll down the outside, and a short flat thigh
# board with a rounded top. The same frames as the modern pieces, so the game hangs them
# the same way. Vertex colors as above; the game gives them leather (glove.gdshader
# `leather`): A the rolls (a darker leather), G the worn inside faces.

OLD_RIBS = (-0.064, -0.022, 0.02, 0.062)       # the stitched channels down the shin (x)
OLD_KNEE = (0.342, 0.39, 0.438)               # the knee rolls (y)


def _old_seams(p, n, ribs, y_range, lines):
    """Deep channels at `ribs` (x) over y_range on the pad's face, plus _seams lines."""
    d = _seams(lines)(p, n)
    if n.z > 0.35 and y_range[0] <= p.y <= y_range[1]:
        for x in ribs:
            d += _groove(abs(p.x - x), 0.0045, 0.0034)
    return d


def build_old_pad(voxel=0.0028, tris=6000):
    bm = bmesh.new()
    Yb = Vector((0, 0, 1))      # (game +Y in Blender: across a roll running side to side)
    # Face, to just under the knee rolls, and the block the knee rolls sit on.
    _pillow(bm, (0.006, 0.185, 0.05), (0.115, 0.215, 0.062), 0.42)
    _pillow(bm, (0.004, 0.39, 0.036), (0.106, 0.08, 0.05), 0.45)
    # Side wings round the leg (the back open).
    _pillow(bm, (0.098, 0.2, -0.014), (0.026, 0.235, 0.085), 0.5)
    _pillow(bm, (-0.092, 0.2, -0.014), (0.026, 0.235, 0.085), 0.5)
    # Three rolls across the knee, and the roll down the outside edge.
    for y in OLD_KNEE:
        _tube(bm, [g(x, y, 0.084) for x in (-0.084, -0.04, 0.0, 0.045, 0.09)], [(0.0215, 0.034)] * 5, across=Yb)
    _tube(bm, [g(0.117, y, 0.06) for y in (-0.02, 0.06, 0.15, 0.24, 0.312)], [(0.022, 0.023)] * 5)
    # Inside: a calf flap (it takes the ice in the butterfly).
    _pillow(bm, (-0.092, 0.16, -0.035), (0.028, 0.14, 0.042), 0.5)
    obj = make_object("GoaliePadOld", bm)
    _fuse(obj, voxel, 6, 0.6)
    lines = [("y", 0.318, (-0.13, 0.1), True),            # under the knee rolls
             ("y", 0.366, (-0.11, 0.11), True), ("y", 0.414, (-0.11, 0.11), True),
             ("x", 0.095, (-0.03, 0.33), True)]           # along the outer roll

    def seams(p, n):
        return _old_seams(p, n, OLD_RIBS, (0.0, 0.305), lines)
    _carve(obj, seams)
    _decimate(obj, tris)

    def trim(p, n):
        roll = _smoothstep(0.09, 0.098, p.x) * _smoothstep(0.02, 0.04, p.z) * (1 - _smoothstep(0.33, 0.34, p.y))
        knee = _smoothstep(0.32, 0.327, p.y) * _smoothstep(0.066, 0.08, p.z)
        return max(roll, knee)

    def landing(p, n):
        return _smoothstep(-0.07, -0.08, p.x) * _smoothstep(0.3, 0.7, -n.x)

    _bake_colors(obj, landing, seams, trim, reach=0.05)
    obj.data.materials.append(material("OldPadMat", (0.45, 0.27, 0.13, 1.0)))
    return obj


def build_old_boot(voxel=0.0026, tris=2600):
    """The old pad's boot: the same frame as build_boot, a little narrower and shorter,
    two stitched breaks across the instep."""
    bm = bmesh.new()
    _pillow(bm, (0.008, -0.02, 0.06), (0.119, 0.075, 0.094), 0.45)
    _pillow(bm, (0.012, -0.092, 0.147), (0.123, 0.095, 0.138), 0.45)
    _tube(bm, [g(0.113, y, 0.058) for y in (-0.155, -0.095, -0.03)], [(0.019, 0.02)] * 3)
    obj = make_object("GoalieBootOld", bm)
    _fuse(obj, voxel, 10, 0.6)
    lines = [("y", -0.045, (-0.13, 0.1), True), ("y", -0.082, (-0.13, 0.1), True), ("x", 0.092, (-0.15, -0.01), True)]

    def seams(p, n):
        return _old_seams(p, n, OLD_RIBS, (-0.035, 0.03), lines)
    _carve(obj, seams)
    _decimate(obj, tris)

    def trim(p, n):
        return _smoothstep(0.09, 0.098, p.x) * _smoothstep(0.02, 0.04, p.z)

    _bake_colors(obj, None, seams, trim, reach=0.04)
    obj.data.materials.append(material("OldPadMat", (0.45, 0.27, 0.13, 1.0)))
    return obj


def build_old_thigh(voxel=0.0026, tris=2000):
    """The old pad's thigh board: short, flat, its top rounded off; stitched in three
    panels with a line round its edge."""
    bm = bmesh.new()
    _pillow(bm, (0.004, 0.08, 0.066), (0.104, 0.105, 0.04), 0.5)
    obj = make_object("GoalieThighOld", bm)
    _fuse(obj, voxel, 10, 0.6)

    def seams(p, n):
        d = 0.0
        if n.z > 0.35:
            for x in (-0.035, 0.04):
                d += _groove(abs(p.x - x), 0.0035, 0.0024) * (p.y < 0.16)
            # a line round the edge
            e = 1.0 - (abs((p.x - 0.004) / 0.104) ** 4 + abs((p.y - 0.08) / 0.105) ** 4) ** 0.25
            d += _groove(abs(e - 0.14) * 0.1, 0.0016, 0.0014)
        return d
    _carve(obj, seams)
    _decimate(obj, tris)
    _bake_colors(obj, None, seams, None, reach=0.04)
    obj.data.materials.append(material("OldPadMat", (0.45, 0.27, 0.13, 1.0)))
    return obj


WAFFLE = ((0.0, 0.06, 0.106), (0.176, 0.118, 0.016))     # the board: center, half size
WAFFLE_GRID = 0.031                                      # hole spacing


def _waffle_holes():
    """Where the holes are on the board's face (game x, y)."""
    (cx, cy, _cz), (hx, hy, _hz) = WAFFLE
    nx, ny = int((hx - 0.03) / WAFFLE_GRID), int((hy - 0.026) / WAFFLE_GRID)
    return [(cx + ix * WAFFLE_GRID, cy + iy * WAFFLE_GRID) for ix in range(-nx, nx + 1) for iy in range(-ny, ny + 1)]


def build_waffle(voxel=0.002, tris=5200):
    """The waffle board: the old blocker, a flat rectangle of felt under leather punched
    with rows of holes, on the back of a plain leather mitt with a short gauntlet cuff."""
    (cx, cy, cz), (hx, hy, hz) = WAFFLE
    bm = bmesh.new()
    _pillow(bm, (cx, cy, cz), (hx, hy, hz), 0.14)
    # The mitt under it, holding the stick, and its cuff up the wrist.
    _pillow(bm, (0.0, 0.065, 0.05), (0.062, 0.088, 0.05), 0.5)
    for x in (-0.03, 0.0, 0.03):     # finger rolls on the palm side
        _tube(bm, [g(x, y, -0.005) for y in (0.03, 0.07, 0.11, 0.135)], [(0.016, 0.018)] * 4)
    ys = (-0.115, -0.085, -0.055, -0.025, 0.0)
    _tube(bm, [g(0.0, y, 0.035) for y in ys], [(0.058 + 0.012 * (-y / 0.115) ** 1.3, 0.052 + 0.009 * (-y / 0.115) ** 1.3) for y in ys])
    obj = make_object("Waffle", bm)
    _fuse(obj, voxel, 6, 0.5)

    def seams(p, n):
        d = 0.0
        if n.z > 0.5 and p.z > cz + hz * 0.4:     # the board's face
            ex = hx - 0.017 - abs(p.x - cx)
            ey = hy - 0.017 - abs(p.y - cy)
            if ex > -0.003 and ey > -0.003:
                d += _groove(min(ex, ey), 0.0016, 0.0016)     # the stitched border
        if p.z < 0.01:
            for y in (0.06, 0.1):                 # finger breaks on the mitt
                d += _groove(abs(p.y - y), 0.0015, 0.0015)
        d += _groove(abs(p.y + 0.1), 0.0014, 0.0012) * (p.z < cz - hz)   # the cuff's binding
        return d
    _carve(obj, seams)
    _decimate(obj, tris)

    # The holes, laid on after the remesh (carved in, they came out of the decimation as
    # ragged pits): a dark disc each, a hair proud of the face.
    from mathutils.bvhtree import BVHTree
    me = obj.data
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [list(q.vertices) for q in me.polygons])
    bm = bmesh.new()
    bm.from_mesh(me)
    solid = len(bm.verts)
    for x, y in _waffle_holes():
        hit = bvh.ray_cast(g(x, y, cz + 0.1), g(0, 0, -1), 0.2)
        if hit[0] is None:
            continue
        c = hit[0] + hit[1] * 0.0005
        ring = [bm.verts.new(c + g(math.cos(math.tau * k / 12) * 0.0072, math.sin(math.tau * k / 12) * 0.0072, 0)) for k in range(12)]
        mid = bm.verts.new(c)
        for k in range(12):
            bm.faces.new((mid, ring[k], ring[(k + 1) % 12]))
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()

    def trim(p, n):
        # the leather binding round the board's edge
        ex = hx - abs(p.x - cx)
        ey = hy - abs(p.y - cy)
        on_board = _smoothstep(cz - hz - 0.004, cz - hz + 0.004, p.z)
        return on_board * (1.0 - _smoothstep(0.014, 0.019, min(ex, ey)))

    def palm(p, n):
        return _smoothstep(0.01, -0.01, p.z) * _smoothstep(0.2, 0.6, -n.z) * (1 - _smoothstep(-0.02, -0.03, p.y))

    _bake_colors(obj, palm, seams, trim, reach=0.04)
    col = obj.data.color_attributes["glove"]
    for i in range(solid, len(obj.data.vertices)):
        col.data[i].color = (0.2, 0.0, 1.0, 1.0)          # the holes: dark
    obj.data.materials.append(material("OldPadMat", (0.45, 0.27, 0.13, 1.0)))
    return obj


OLD_FILES = ("goalie_pad_old.glb", "goalie_boot_old.glb", "goalie_thigh_old.glb", "blocker_old.glb", "goalie_catcher_old.glb")


def build_old(do_export=False, only=None):
    """The Old-Time Set's goalie gear, laid out in a row behind the modern pieces:
    leather pads (pad, boot, thigh board), the waffle board and the mitt. `only`: a list
    of indices into OLD_FILES to build just those. tools/build_gear.gd
    (only=goalie_gear) turns the files into assets/characters/*.res."""
    builders = (build_old_pad, build_old_boot, build_old_thigh, build_waffle, lambda: build_catcher(old=True))
    out = []
    for i, (fn, name) in enumerate(zip(builders, OLD_FILES)):
        if only is not None and i not in only:
            continue
        o = fn()
        if do_export:
            export(o, name)
        o.location = Vector((0.35 * min(i, 4) if i != 1 else 0.0, 0.6, 0))
        out.append(o)
    return out


def build_all(do_export=False):
    pad = build_pad()
    boot = build_boot()
    thigh = build_thigh()
    thigh.location = Vector((0.35, 0, 0))
    blocker = build_blocker()
    blocker.location = Vector((0.7, 0, 0))
    catcher = build_catcher()
    catcher.location = Vector((1.05, 0, 0))
    if do_export:
        for o, name in ((pad, "goalie_pad.glb"), (boot, "goalie_boot.glb"), (thigh, "goalie_thigh.glb"),
                        (blocker, "blocker.glb"), (catcher, "goalie_catcher.glb")):
            loc = o.location.copy()
            o.location = Vector((0, 0, 0))
            export(o, name)
            o.location = loc
    return pad, boot, thigh, blocker, catcher
