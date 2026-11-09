# Builds the hockey skate in Blender the same way hand_gear.py builds the glove: the parts
# fused into one skin by a voxel remesh and smoothed, construction carved back in as
# stitched seams and raised panels, shading baked into vertex colors for
# scenes/actors/glove.gdshader:
#   R  open / tucked (ambient occlusion)
#   G  the side panels (a second, greyer material on the quarters)
#   B  stitched seams, panel lines and eyelets
#   A  1 - trim: the white parts (the holder, the tongue's felt, the laces)
# The boot, holder and laces are one mesh (skate.glb); the steel runner is its own
# (skate_steel.glb). tools/build_gear.gd (only=skate) makes assets/characters/skate.res:
# surface 0 the boot, 1 the steel.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/skate_gear.py").read()); build_all(True)
#
# Frame (game coordinates, meters, a 1.8 m body's skate; SkaterVisual scales it to
# SKATE_LEN): toe +Z, up +Y, +X the outside of a right skate (they are symmetric), origin
# on the bottom of the runner, halfway along it. The boot's sole sits at SOLE (the game's
# SKATE_LIFT), where the body's foot stands. Proportions are taken off a side photo of a
# real skate: about 8 cm from the ice to the boot (2.5 of it bare steel), the collar 17 cm
# above the sole, and the tongue and tendon guard standing well above the collar.

import math
import os

import bpy
from mathutils import Vector

_here = os.path.dirname(os.path.abspath(globals().get(
    "__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\skate_gear.py")))
_hg = {"__file__": os.path.join(_here, "hand_gear.py"), "__name__": "hand_gear"}
exec(compile(open(_hg["__file__"]).read(), _hg["__file__"], "exec"), _hg)
for _k, _v in _hg.items():
    if not _k.startswith("__"):
        globals()[_k] = _v

G3 = (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0)))   # game x, y, z in Blender
SOLE = 0.08          # top of the holder / bottom of the boot (SkaterVisual.SKATE_LIFT)
RUNNER = 0.15        # half the runner's length
STEEL_TOP = 0.044    # the runner's top, up inside the holder
HOLDER_BOT = 0.024   # the holder's bottom edge: the steel below it is bare
COLLAR = 0.172       # the top of the boot's shaft, above the sole
EYE_X = 0.034        # the eyelet rows, either side of the lacing


def _pillow(bm, c, r, sq=PAD):
    _ellipsoid(bm, g(*c), G3, r, sq)


def _lerp_table(table, s):
    """A smooth curve through (s, value) pairs (Catmull-Rom; flat beyond the ends)."""
    if s <= table[0][0]:
        return table[0][1]
    if s >= table[-1][0]:
        return table[-1][1]
    i = next(k for k in range(len(table) - 1) if s <= table[k + 1][0])
    (s1, p1), (s2, p2) = table[i], table[i + 1]
    s0, p0 = table[i - 1] if i > 0 else (2 * s1 - s2, p1)
    s3, p3 = table[i + 2] if i + 2 < len(table) else (2 * s2 - s1, p2)
    h = s2 - s1
    m1 = (p2 - p0) / (s2 - s0) * h
    m2 = (p3 - p1) / (s3 - s1) * h
    t = (s - s1) / h
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * p1 + (t3 - 2 * t2 + t) * m1 + (-2 * t3 + 3 * t2) * p2 + (t3 - t2) * m2


# The boot as horizontal slices by height above the sole (s): where its front and back
# are (z) and its half width, traced off a side photo of a real skate. The front rounds
# over the toe cap, runs low and shallow over the forefoot, then sweeps up steeply into
# the upright front of the shaft (a curved scoop, not a straight ramp); the back is
# nearly upright from the heel. Wide enough for the body's leg (11-12 cm at the ankle).
BOOT_FRONT = [(0.0, 0.138), (0.016, 0.148), (0.032, 0.146), (0.044, 0.136), (0.052, 0.118),
              (0.058, 0.098), (0.067, 0.072), (0.083, 0.041), (0.105, 0.011), (0.137, -0.009),
              (0.165, -0.016), (COLLAR, -0.017)]
BOOT_BACK = [(0.0, -0.138), (0.03, -0.149), (0.08, -0.154), (0.13, -0.156), (COLLAR, -0.155)]
BOOT_HALF = [(0.0, 0.047), (0.03, 0.054), (0.07, 0.061), (0.11, 0.066), (0.15, 0.068), (COLLAR, 0.069)]


def _slice(s, n=64, e=2.8):
    """One ring of the boot at height s above the sole (game points)."""
    zf, zb, w = _lerp_table(BOOT_FRONT, s), _lerp_table(BOOT_BACK, s), _lerp_table(BOOT_HALF, s)
    cz, rz = (zf + zb) / 2, (zf - zb) / 2
    ring = []
    for k in range(n):
        a = math.tau * k / n
        c, si = math.cos(a), math.sin(a)
        z = cz + rz * math.copysign(abs(c) ** (2 / e), c)
        x = w * math.copysign(abs(si) ** (2 / e), si)
        if z > 0.05:             # the toe is narrower than the ball of the foot...
            x *= 1.0 - 0.32 * ((z - 0.05) / 0.1) ** 2
        if z < -0.07:            # ...and the heel narrower still (the heel only: the
            # shaft above has to hold the ankle and the Achilles, as wide at the back)
            fade = 1.0 - _smoothstep(0.03, 0.08, s)
            x *= 1.0 - 0.22 * fade * ((z + 0.07) / 0.075) ** 2
        ring.append(Vector((x, SOLE + s, z)))
    return ring


def _loft(bm, rings, cap=True):
    """Quads between consecutive rings (game points, equal counts), end caps fanned."""
    tmp = bmesh.new()
    vs = [[tmp.verts.new(_gv(p)) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n):
            tmp.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    if cap:
        for r, flip in ((vs[0], True), (vs[-1], False)):
            c = tmp.verts.new(sum((v.co for v in r), Vector()) / n)
            for k in range(n):
                f = (r[k], r[(k + 1) % n], c)
                tmp.faces.new(tuple(reversed(f)) if flip else f)
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    _merge(bm, tmp)


def _holder(bm, n=60):
    """The holder: one piece along the runner, a narrow web where it grips the steel that
    flares out wide under the boot; flat along the bottom, its ends sloping up from the
    steel's ends to the toe and heel."""
    rings = []
    for k in range(n + 1):
        z = -0.143 + 0.288 * k / n
        u = abs(z + 0.0) / 0.146
        top = SOLE + 0.004
        bot = HOLDER_BOT + 0.02 * max(0.0, (u - 0.93) / 0.07)
        wt = 0.043 * max(0.2, 1 - u ** 5) ** 0.5
        wb = 0.0055
        ring = []
        for j in range(20):
            t = j / 19
            ring.append(Vector((wb + (wt - wb) * (1 - t) ** 3, top + (bot - top) * t, z)))
        rings.append(ring + [Vector((-p.x, p.y, p.z)) for p in reversed(ring)])
    _loft(bm, rings)


def _surface(bvh, x, y):
    """Where a ray from in front of the skate, at (x, y), meets the boot (game point and
    normal), or None."""
    hit = bvh.ray_cast(g(x, y, 0.4), g(0, 0, -1), 0.6)
    if hit[0] is None:
        return None
    return Vector((hit[0].x, hit[0].z, -hit[0].y)), Vector((hit[1].x, hit[1].z, -hit[1].y))


def _bvh(obj_or_bm):
    from mathutils.bvhtree import BVHTree
    if isinstance(obj_or_bm, bmesh.types.BMesh):
        return BVHTree.FromBMesh(obj_or_bm)
    me = obj_or_bm.data
    return BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])


EYELET_Y = [SOLE + 0.046 + k * 0.0155 for k in range(8)]
PITCH = 0.015        # how much higher the boot's heel sits than its toe (forward lean)


def _pitch(z, y):
    """How far the pitch raises a point (game z, y): nothing at the toe, PITCH at the heel,
    fading out down the holder to its bottom edge."""
    rise = PITCH * max(0.0, min(1.0, (0.06 - z) / 0.19))
    return rise * max(0.0, min(1.0, (y - HOLDER_BOT) / (SOLE - HOLDER_BOT)))


def _flat(p):
    """A point of the pitched skate back in the unpitched frame the details are laid out in."""
    q = Vector(p)
    q.y -= _pitch(q.z, q.y - PITCH)       # (close enough: the pitch varies slowly)
    return q


# --- Boot and holder -------------------------------------------------------------------

def build_boot(voxel=0.0012, tris=10000):
    bm = bmesh.new()
    _loft(bm, [_slice(COLLAR * k / 60) for k in range(61)])
    shell = _bvh(bm)
    # Eyestays: raised bands either side of the lacing, up the instep to the collar.
    for side in (-1, 1):
        pts = []
        for k in range(14):
            y = SOLE + 0.04 + (COLLAR - 0.045) * k / 13
            hit = _surface(shell, side * (EYE_X + 0.004), y)
            if hit:
                pts.append(_gv(hit[0] - hit[1] * 0.002))
        _tube(bm, pts, [(0.0105, 0.0045)] * len(pts), across=Vector((0, 0, 1)), segs=12)
    # Toe cap: a shell over the toe box.
    _pillow(bm, (0.0, SOLE + 0.024, 0.104), (0.04, 0.03, 0.046), 0.5)
    # Tongue: a padded plate up the front of the shaft, standing well above the collar,
    # its top a thick felt pad.
    _tube(bm, [g(0.0, SOLE + 0.11, 0.004), g(0.0, SOLE + 0.17, -0.012), g(0.0, SOLE + 0.225, -0.01)],
          [(0.036, 0.008), (0.04, 0.009), (0.042, 0.01)])
    _pillow(bm, (0.0, SOLE + 0.205, -0.037), (0.043, 0.045, 0.028), 0.4)
    # Tendon guard: a broad plate curved round the Achilles, up the back and flaring
    # wider at the top.
    rings = []
    for k in range(13):
        s = 0.09 + 0.162 * k / 12
        half = math.radians(_lerp_table([(0.09, 62), (0.17, 40), (0.252, 56)], s))
        r = 0.056
        cz = _lerp_table([(0.09, -0.103), (0.17, -0.102), (0.252, -0.115)], s)
        ring = []
        for j in range(12):
            a = -half + 2 * half * j / 11
            ring.append(Vector((math.sin(a) * r, SOLE + s, cz - math.cos(a) * r)))
        for j in reversed(range(12)):
            a = -half + 2 * half * j / 11
            ring.append(Vector((math.sin(a) * (r - 0.009), SOLE + s, cz - math.cos(a) * (r - 0.009))))
        rings.append(ring)
    _loft(bm, rings)
    # Padded collar round the top of the shaft, from one side of the tongue round the back.
    ring = _slice(COLLAR - 0.006, n=72)
    collar = [ring[k % 72] for k in range(8, 65, 2)]
    _tube(bm, [_gv(p) for p in collar], [(0.0045, 0.006)] * len(collar), across=Vector((0, 0, 1)))
    _holder(bm)
    for v in bm.verts:                     # the heel up, the toe down: the boot's pitch
        v.co.z += _pitch(-v.co.y, v.co.z)
    obj = make_object("Skate", bm)
    _fuse(obj, voxel, 4, 0.5)

    # The holder's window between its front and rear, and the slots under it.
    bmh = bmesh.new()
    _pillow(bmh, (0.0, 0.047, 0.004), (0.06, 0.0125, 0.06), 0.26)
    for z in (-0.042, -0.014, 0.014, 0.042):
        _pillow(bmh, (0.0, 0.0285, z), (0.06, 0.0035, 0.0105), 0.3)
    hole = make_object("SkateWindow", bmh)
    bo = obj.modifiers.new("Window", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = hole
    _apply_all(obj)
    bpy.data.objects.remove(hole, do_unlink=True)

    def panel_top(z):
        return SOLE + 0.112 - 0.42 * (z + 0.05)

    def in_panel(p):
        """The quarters: a panel swept from behind the ankle forward and down."""
        return SOLE + 0.01 < p.y < panel_top(p.z) and -0.13 < p.z < 0.078

    def eyelet(p):
        """Distance to the nearest eyelet (the instep's front, either row)."""
        d = 1.0
        for y in EYELET_Y:
            for x in (-EYE_X, EYE_X):
                d = min(d, math.hypot(p.x - x, p.y - y))
        return d

    def carve(p, n):
        p = _flat(p)
        d = 0.0
        side = abs(n.x) > 0.35
        # the boot's bottom edge, where it sits in the holder
        d += _groove(abs(p.y - (SOLE + 0.005)), 0.0014, 0.0014)
        if p.y > SOLE and side:
            # raised side panels: stood out from the boot, stitched round their edge
            if -0.13 < p.z < 0.078:
                top = panel_top(p.z)
                lift = _smoothstep(top + 0.002, top - 0.002, p.y) * _smoothstep(-0.128, -0.12, p.z) * _smoothstep(0.077, 0.07, p.z)
                d -= 0.0018 * lift
                d += _groove(abs(p.y - top), 0.0012, 0.0012)
                d += _groove(abs(p.y - (top - 0.006)), 0.0009, 0.0007)       # stitching
                # the lower sweep inside the panel
                d += _groove(abs(p.y - (top - 0.032)), 0.0012, 0.001) * (p.y > SOLE + 0.015) * (p.z > -0.12)
            d += _groove(abs(p.z - 0.078), 0.0012, 0.0012) * (SOLE < p.y < SOLE + 0.09)
            # the tendon guard's seam and a stitched line up it
            d += _groove(abs(p.z + 0.127), 0.0013, 0.0012) * (p.y > SOLE + 0.1)
            # the holder's flange and its ribs
            if p.y < SOLE:
                d += _groove(abs(p.y - (SOLE - 0.008)), 0.0012, 0.001)
        # the toe cap's edge, and its stitching
        if p.z > 0.05 and p.y > SOLE + 0.006:
            e = p.z - 0.088 + 0.55 * (p.y - SOLE - 0.03)
            d += _groove(abs(e), 0.0013, 0.0014)
            d += _groove(abs(e + 0.005), 0.0009, 0.0006)
        # eyelets on the eyestays
        if n.z > 0.1 and p.y > SOLE + 0.03:
            r = eyelet(p)
            d += 0.0016 * _smoothstep(0.0032, 0.0018, r)
            d -= 0.0006 * _smoothstep(0.0055, 0.004, r) * _smoothstep(0.0025, 0.0035, r)
        return d

    _carve(obj, carve)
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 1
    _apply_all(obj)
    _decimate(obj, tris)

    # Laces, built after the remesh (too fine for it): crossing between the eyelets up the
    # instep, lying on the boot.
    me = obj.data
    bvh = _bvh(obj)
    bm = bmesh.new()
    bm.from_mesh(me)
    solid = len(bm.verts)
    rows = []
    for y in EYELET_Y:
        pr = [_surface(bvh, x, y) for x in (-EYE_X, EYE_X)]
        if all(pr):     # again, raised by the pitch where they landed
            pr = [_surface(bvh, x, y + _pitch(h[0].z, y)) for x, h in zip((-EYE_X, EYE_X), pr)]
        if all(pr):
            rows.append([p + nrm * 0.002 for p, nrm in pr])

    def lace(a, b, lift=0.0032):
        pts = []
        for k in range(5):
            q = a.lerp(b, k / 4)
            hit = _surface(bvh, q.x, q.y)
            pts.append(_gv(hit[0] + hit[1] * lift if hit and 0 < k < 4 else q))
        add_sweep(bm, pts, [(0.0034, 0.0012)] * len(pts), segs=6, across=Vector((0, 0, 1)))

    lace(rows[0][0], rows[0][1])
    for k in range(len(rows) - 1):
        lace(rows[k][0], rows[k + 1][1], 0.0032 + 0.0012 * (k % 2))
        lace(rows[k][1], rows[k + 1][0], 0.0044 - 0.0012 * (k % 2))
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()

    def panel(p, n):
        p = _flat(p)
        return float(in_panel(p)) * _smoothstep(0.3, 0.5, abs(n.x))

    def trim(p, n):
        p = _flat(p)
        holder = 1 - _smoothstep(SOLE - 0.003, SOLE + 0.001, p.y)
        # the tongue's felt: rolled over its top, and down its back (against the shin)
        on_tongue = _smoothstep(-0.075, -0.065, p.z) * (abs(p.x) < 0.045)
        felt = on_tongue * max(_smoothstep(SOLE + 0.226, SOLE + 0.232, p.y),
                               _smoothstep(SOLE + 0.18, SOLE + 0.186, p.y) * _smoothstep(-0.3, -0.6, n.z))
        return max(holder, felt)

    _bake_colors(obj, panel, carve, trim, reach=0.03)
    col = me.color_attributes["glove"]
    for i in range(solid, len(me.vertices)):
        col.data[i].color = (0.85, 0.0, 0.0, 0.0)          # laces: white
    me.materials.append(material("SkateMat", (0.08, 0.08, 0.09, 1.0)))
    return obj


# --- Steel -------------------------------------------------------------------------------

def build_steel():
    """The runner: a thin blade, flat along the bottom with a rocker toward each end
    (rounder at the toe), its top up inside the holder."""
    bm = bmesh.new()
    prof = []
    n = 60
    for k in range(n + 1):
        z = -RUNNER + 2 * RUNNER * k / n
        if z > 0:
            y = 0.024 * max(0.0, (z - 0.085) / 0.065) ** 2.2
        else:
            y = 0.016 * max(0.0, (-z - 0.11) / 0.04) ** 2.5
        prof.append((z, min(y, STEEL_TOP - 0.006)))
    top = [(z, STEEL_TOP) for z, _ in reversed(prof)]
    outline = prof + top
    half = 0.0022
    front = [bm.verts.new(g(half, y, z)) for z, y in outline]
    back = [bm.verts.new(g(-half, y, z)) for z, y in outline]
    m = len(outline)
    for i in range(m):
        j = (i + 1) % m
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    obj = make_object("SkateSteel", bm, smooth=False)
    obj.data.materials.append(material("Steel", (0.8, 0.82, 0.85, 1.0)))
    return obj


def build_all(do_export=False):
    boot = build_boot()
    steel = build_steel()
    if do_export:
        export(boot, "skate.glb")
        export(steel, "skate_steel.glb")
    return boot, steel
