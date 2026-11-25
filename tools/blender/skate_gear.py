# Builds the hockey skate in Blender the same way hand_gear.py builds the glove: the parts
# fused into one skin by a voxel remesh and smoothed, construction carved back in as
# stitched seams and raised panels, shading baked into vertex colors for
# scenes/actors/glove.gdshader:
#   R  open / tucked (ambient occlusion)
#   G  the lower quarter panels (a second, greyer material)
#   B  stitched seams, panel lines and eyelets
#   A  1 - trim: the white parts (the holder, the tongue's felt, the laces)
# The boot, holder and laces are one mesh (skate.glb); the steel runner is its own
# (skate_steel.glb). tools/build_gear.gd (only=skate) makes assets/characters/skate.res:
# surface 0 the boot, 1 the steel.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/skate_gear.py").read()); build_all(True)
# or headless:     blender -b -P tools/blender/skate_gear.py -- export
# The Old-Time Set's tube skate alone: build_old(True) (headless: `-- export old`) ->
# skate_old.glb and skate_old_steel.glb; build_gear.gd only=old makes skate_old.res.
#
# Frame (game coordinates, meters, a 1.8 m body's skate; SkaterVisual scales it by its
# length, SKATE_LEN): toe +Z, up +Y, +X the outside of a right skate (they are symmetric),
# origin on the ice under the runner, 8 cm ahead of the ankle joint. The boot's sole sits
# at SOLE (the game's SKATE_LIFT), where the body's foot stands.
#
# Shape (second version). The first boot was a tube wide enough to swallow the padded
# sock (14 cm across at the collar) on a foot that tapered to a narrow toe: it read as a
# short, thin foot under a wide ankle. This one has a real skate's proportions: a long
# low foot ending in a blunt, boxy toe cap, a shaft only as wide as an ankle (10 cm) that
# is waisted above the heel, and a holder of two towers on a rail with an open arch
# between them. The sock no longer goes down inside the boot: the game ends it at the
# collar (SkaterVisual.add_skates, `sock_end`), over the boot's top as a real sock sits,
# with the tongue standing in front of it and the tendon guard behind.

import math
import os
import sys

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
STEEL_Z = (-0.162, 0.152)   # the runner's ends
STEEL_TOP = 0.035    # the runner's top, up inside the holder's rail
HOLDER_BOT = 0.022   # the holder's bottom edge: the steel below it is bare
RAIL_TOP = 0.041     # the top of the rail between the towers (the bottom of the arch)
COLLAR = 0.172       # the top of the boot's shaft, above the sole
GUARD_TOP = 0.24     # the top of the tendon guard, above the sole
TONGUE_TOP = 0.238   # the top of the tongue, above the sole


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
# are (z), traced off a side view of a real skate. The front bulges out over the toe cap,
# rounds over its nearly flat top (6 cm up), then climbs the instep in one scoop that
# steepens into the upright lacing of the shaft. The back swells over the heel counter,
# draws in at the Achilles and flares again at the collar.
BOOT_FRONT = [(0.0, 0.156), (0.012, 0.165), (0.03, 0.164), (0.045, 0.155), (0.054, 0.138),
              (0.059, 0.112), (0.064, 0.09), (0.078, 0.066), (0.095, 0.042), (0.113, 0.02),
              (0.132, 0.001), (0.152, -0.013), (COLLAR, -0.021)]
BOOT_BACK = [(0.0, -0.141), (0.02, -0.15), (0.05, -0.151), (0.085, -0.146), (0.12, -0.146), (COLLAR, -0.151)]
# Half widths. The foot by where along it (its outline from above: heel, waist, the ball
# of the foot, a toe nearly as wide as the ball); the shaft by height (waisted over the
# heel, out again over the ankle bones, a slight flare at the collar).
FOOT_W = [(-0.15, 0.035), (-0.11, 0.04), (-0.05, 0.043), (0.02, 0.047), (0.075, 0.051), (0.12, 0.05), (0.165, 0.045)]
SHAFT_W = [(0.05, 0.046), (0.075, 0.0465), (0.1, 0.0505), (0.13, 0.0495), (COLLAR, 0.052)]


def _half(z, s):
    """The boot's half width at height s, where its outline is widest across z."""
    foot = _lerp_table(FOOT_W, z) * _lerp_table([(0.0, 0.93), (0.012, 1.0), (0.05, 1.0)], s)
    return foot + (_lerp_table(SHAFT_W, s) - foot) * _smoothstep(0.045, 0.09, s)


def _slice(s, n=96):
    """One ring of the boot at height s above the sole (game points). A superellipse, far
    squarer at the front (a blunt toe cap, a flat lacing face) than at the heel: an
    ordinary ellipse this long comes to a point."""
    zf, zb = _lerp_table(BOOT_FRONT, s), _lerp_table(BOOT_BACK, s)
    cz, rz = (zf + zb) / 2, (zf - zb) / 2
    up = _smoothstep(0.05, 0.11, s)
    ef, eb = 4.0 - 1.0 * up, 2.7 - 0.3 * up
    ring = []
    for k in range(n):
        a = math.tau * k / n
        c, si = math.cos(a), math.sin(a)
        e = ef if c > 0 else eb
        z = cz + rz * math.copysign(abs(c) ** (2 / e), c)
        x = _half(z, s) * math.copysign(abs(si) ** (2 / e), si)
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


def _steel_bottom(z):
    """The runner's edge: flat under the foot, rockered up toward each end (more at the toe)."""
    if z > 0:
        return 0.03 * max(0.0, (z - 0.08) / 0.072) ** 2.2
    return 0.014 * max(0.0, (-z - 0.115) / 0.047) ** 2.5


TOWERS = ((-0.134, -0.07), (0.056, 0.138))   # where the rear and front towers meet the sole


def _tower(z):
    """1 where a tower stands at z, 0 in the arch between them (and beyond the ends)."""
    (r0, r1), (f0, f1) = TOWERS
    rear = _smoothstep(r0 - 0.03, r0, z) * (1 - _smoothstep(r1, r1 + 0.03, z))
    front = _smoothstep(f0 - 0.03, f0, z) * (1 - _smoothstep(f1, f1 + 0.012, z))
    return max(rear, front)


def _holder(bm, n=96):
    """The holder: a narrow rail gripping the steel from end to end, and two towers
    standing on it (under the heel and under the ball of the foot) that flare out to
    flanges on the sole. Between the towers the rail runs bare: an open arch."""
    rings = []
    z0, z1 = STEEL_Z[0] - 0.005, STEEL_Z[1] + 0.002
    for k in range(n + 1):
        z = z0 + (z1 - z0) * k / n
        tw = _tower(z)
        bot = HOLDER_BOT + _steel_bottom(z) * 0.85
        rail = max(RAIL_TOP, bot + 0.016)
        top = rail + (SOLE + 0.004 - rail) * tw
        end = min(1.0, (z - z0) / 0.012, (z1 - z) / 0.012) ** 0.5     # rounded off at the ends
        wt = (0.034 if z < 0 else 0.037) * (0.55 + 0.45 * tw) * end   # the flange
        wb = 0.0062 * (0.5 + 0.5 * end)
        ring = []
        for j in range(24):
            t = j / 23
            y = top + (bot - top) * t
            f = max(0.0, (y - rail) / max(1e-6, SOLE + 0.004 - rail))
            w = wb + (wt - wb) * f ** 2.4 if y > rail else wb * (0.8 + 0.2 * (y - bot) / (rail - bot))
            ring.append(Vector((w, y, z)))
        rings.append(ring + [Vector((-p.x, p.y, p.z)) for p in reversed(ring)])
    _loft(bm, rings)


def _bvh(obj_or_bm):
    from mathutils.bvhtree import BVHTree
    if isinstance(obj_or_bm, bmesh.types.BMesh):
        return BVHTree.FromBMesh(obj_or_bm)
    me = obj_or_bm.data
    return BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])


def _surface(bvh, x, y):
    """Where a ray from in front of the skate, at (x, y), meets the boot (game point and
    normal), or None."""
    hit = bvh.ray_cast(g(x, y, 0.4), g(0, 0, -1), 0.6)
    if hit[0] is None:
        return None
    return Vector((hit[0].x, hit[0].z, -hit[0].y)), Vector((hit[1].x, hit[1].z, -hit[1].y))


def _nearest(bvh, p):
    """The boot's surface nearest a game point (game point and normal)."""
    hit = bvh.find_nearest(_gv(p))
    return Vector((hit[0].x, hit[0].z, -hit[0].y)), Vector((hit[1].x, hit[1].z, -hit[1].y))


def _eye_x(s):
    """The eyelet rows' distance from the middle: close together behind the toe cap,
    wider up the shaft."""
    return 0.0235 + 0.0075 * _smoothstep(0.065, 0.15, s)


def _eyelet_heights(count=9, s0=0.0665, s1=0.161):
    """Heights of the eyelets, evenly spaced along the lacing (not by height: the instep
    is a shallow slope, the shaft nearly upright)."""
    steps = 200
    ss = [s0 + (s1 - s0) * k / steps for k in range(steps + 1)]
    acc = [0.0]
    for a, b in zip(ss, ss[1:]):
        acc.append(acc[-1] + math.hypot(b - a, _lerp_table(BOOT_FRONT, b) - _lerp_table(BOOT_FRONT, a)))
    out = []
    for k in range(count):
        want = acc[-1] * k / (count - 1)
        i = next(j for j in range(steps + 1) if acc[j] >= want - 1e-9)
        out.append(ss[i])
    return out


EYELET_S = _eyelet_heights()
PITCH = 0.012        # how much higher the boot's heel sits than its toe (forward lean)


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


def _cap_edge(p):
    """How far ahead of the toe cap's rear edge a point is (the edge leans: further
    forward at the sole)."""
    return p.z - (0.094 - 0.4 * (p.y - SOLE - 0.03))


def _sweep(z):
    """The line across the quarters, from high behind the ankle down to the ball of the
    foot (height above the sole): the lower panel is under it."""
    t = (z + 0.135) / 0.215
    return 0.148 - 0.108 * t - 0.022 * math.sin(math.pi * max(0.0, min(1.0, t)))


# --- Boot and holder -------------------------------------------------------------------

def build_boot(voxel=0.0012, tris=10000, old=False):
    """The boot (with its holder and laces). old: the Old-Time Set's leather boot for the
    tube frame (build_old_steel): no plastic holder under it, a short felt tongue that
    flops forward, a low leather tab over the Achilles in place of the tall tendon guard,
    a plain stitched toe cap; the toe cap, heel and lower quarters are its darker leather
    (the G channel), the laces and felt its trim."""
    tongue_top = 0.214 if old else TONGUE_TOP
    guard_top = 0.2 if old else GUARD_TOP
    bm = bmesh.new()
    _loft(bm, [_slice(COLLAR * k / 72) for k in range(73)])
    shell = _bvh(bm)
    # Where the eyelets sit on the shell (unpitched), both rows, bottom to top.
    eyes = []
    for s in EYELET_S:
        row = [_surface(shell, side * _eye_x(s), SOLE + s) for side in (-1, 1)]
        if all(row):
            eyes.append(row)
    # Eyestays: raised bands either side of the lacing, from the toe cap up the instep to
    # the collar.
    for side in (-1, 1):
        pts = []
        for k in range(22):
            s = 0.062 + (COLLAR - 0.066) * k / 21
            hit = _surface(shell, side * (_eye_x(s) + 0.003), SOLE + s)
            if hit:
                pts.append(_gv(hit[0] - hit[1] * 0.0015))
        _tube(bm, pts, [(0.0095, 0.004)] * len(pts), across=Vector((1, 0, 0)), segs=12)
    # Tongue: a thick felt plate behind the lacing, curved round the shin, that stands
    # well above the collar and falls a little forward; its top corners rounded off.
    zc = _lerp_table(BOOT_FRONT, COLLAR)
    rings = []
    for k in range(25):
        s = 0.1 + (tongue_top - 0.1) * k / 24
        front = (_lerp_table(BOOT_FRONT, s) - 0.003 if s < COLLAR else
                 _lerp_table([(COLLAR, zc - 0.003), ((COLLAR + tongue_top) / 2, zc + 0.003),
                              (tongue_top, zc + (0.02 if old else 0.012))], s))
        r, thick = 0.066, 0.0125
        top = max(0.0, (s - (tongue_top - 0.022)) / 0.022)
        half = math.radians(34.0 * (1.0 - 0.55 * top * top))
        cz = front - r
        ring = []
        for j in range(16):
            a = -half + 2 * half * j / 15
            ring.append(Vector((math.sin(a) * r, SOLE + s, cz + math.cos(a) * r)))
        for j in reversed(range(16)):
            a = -half + 2 * half * j / 15
            ring.append(Vector((math.sin(a) * (r - thick), SOLE + s, cz + math.cos(a) * (r - thick))))
        rings.append(ring)
    _loft(bm, rings)
    # Tendon guard: a plate curved round the Achilles, standing above the collar and
    # leaning back, narrow where it hinges on the boot and flaring wider at the top.
    rings = []
    for k in range(15):
        s = 0.118 + (guard_top - 0.118) * k / 14
        if old:
            half = math.radians(_lerp_table([(0.118, 58), (0.172, 44), (guard_top - 0.012, 40), (guard_top, 30)], s))
            back = _lerp_table([(0.118, -0.1475), (0.172, -0.157), (guard_top, -0.161)], s)
            thick = _lerp_table([(0.118, 0.005), (0.172, 0.006), (guard_top, 0.005)], s)
        else:
            half = math.radians(_lerp_table([(0.118, 58), (0.172, 42), (0.2, 46), (GUARD_TOP - 0.014, 52), (GUARD_TOP, 40)], s))
            back = _lerp_table([(0.118, -0.1475), (0.172, -0.158), (0.205, -0.164), (GUARD_TOP, -0.172)], s)
            thick = _lerp_table([(0.118, 0.005), (0.172, 0.0075), (GUARD_TOP, 0.007)], s)
        r = 0.05
        cz = back + r
        ring = []
        for j in range(14):
            a = -half + 2 * half * j / 13
            ring.append(Vector((math.sin(a) * r, SOLE + s, cz - math.cos(a) * r)))
        for j in reversed(range(14)):
            a = -half + 2 * half * j / 13
            ring.append(Vector((math.sin(a) * (r - thick), SOLE + s, cz - math.cos(a) * (r - thick))))
        rings.append(ring)
    _loft(bm, rings)
    if not old:
        _holder(bm)
    for v in bm.verts:                     # the heel up, the toe down: the boot's pitch
        v.co.z += _pitch(-v.co.y, v.co.z)
    obj = make_object("SkateOld" if old else "Skate", bm)
    _fuse(obj, voxel, 3, 0.5)

    def lower(p):
        """The lower quarter panel (0..1): under the sweep, between the heel's backstay
        and the toe cap."""
        s = p.y - SOLE
        return (_smoothstep(0.006, 0.009, s) * _smoothstep(_sweep(p.z) + 0.0015, _sweep(p.z) - 0.0015, s)
                * _smoothstep(-0.132, -0.127, p.z) * _smoothstep(-0.012, -0.016, _cap_edge(p)))

    def eyelet(p):
        """Distance to the nearest eyelet."""
        return min((p - e[0]).length for row in eyes for e in row)

    def carve(p, n):
        p = _flat(p)
        s = p.y - SOLE
        d = 0.0
        side = abs(n.x) > 0.35
        # the outsole: a thin plate under the boot, proud of the upper by a groove
        d += _groove(abs(s - 0.006), 0.0013, 0.0014) * (s < 0.05)
        if s > 0.006:
            e = _cap_edge(p)
            if p.z > 0.04 and s < 0.075:
                # the toe cap: a hard shell standing proud of the boot behind it
                d -= 0.0022 * _smoothstep(-0.001, 0.003, e)
                d += _groove(abs(e + 0.002), 0.0012, 0.0014)
                d += _groove(abs(e + 0.008), 0.0009, 0.0006) * side          # stitching
                # two shallow ribs across the cap's top
                if n.y > 0.5 and not old:
                    for zz in (0.118, 0.138):
                        d += _groove(abs(p.z - zz), 0.0018, 0.0008) * _smoothstep(0.036, 0.026, abs(p.x))
            if side and s < COLLAR + 0.004:
                # the lower quarter panel, stood out from the boot and stitched round its edge
                d -= 0.0016 * lower(p)
                if -0.13 < p.z and e < -0.012:
                    sw = _sweep(p.z)
                    d += _groove(abs(s - sw), 0.0012, 0.0012)
                    d += _groove(abs(s - (sw - 0.006)), 0.0009, 0.0006)
                    d += _groove(abs(s - (sw + 0.022)), 0.0011, 0.0008) * (s > 0.03)   # a second line above
                d += _groove(abs(e + 0.014), 0.0012, 0.001) * (s < _sweep(p.z))
                # the backstay up the heel, and the heel counter's top
                d += _groove(abs(p.z + 0.1295), 0.0012, 0.0011) * (s < COLLAR)
                d += _groove(abs(s - 0.062), 0.0011, 0.0008) * (p.z < -0.1295)
        # the tendon guard: its hinge line, and a stitched border
        if p.z < -0.1 and s > COLLAR - 0.004 and n.z < -0.2:
            d += _groove(abs(s - (COLLAR + 0.012)), 0.0016, 0.0016)
            d += _groove(abs(s - (guard_top - 0.01)), 0.001, 0.0006)
        # the holder: a line under its flanges, and a recessed panel in each tower
        if s < -0.002 and side:
            d += _groove(abs(s + 0.007), 0.0011, 0.0009)
            tw = _tower(p.z)
            d += 0.0011 * _smoothstep(0.93, 1.0, tw) * _smoothstep(RAIL_TOP + 0.004, RAIL_TOP + 0.007, p.y) * _smoothstep(SOLE - 0.012, SOLE - 0.015, p.y)
        if p.y < RAIL_TOP and abs(n.x) > 0.6:
            d += _groove(abs(p.y - (RAIL_TOP - 0.005)), 0.0011, 0.0008)
        # eyelets on the eyestays: a rim round a hole
        if eyes and n.z > 0.05 and s > 0.05:
            r = eyelet(p)
            d += 0.0016 * _smoothstep(0.003, 0.0017, r)
            d -= 0.0006 * _smoothstep(0.0052, 0.004, r) * _smoothstep(0.0024, 0.0034, r)
        return d

    _carve(obj, carve)
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.35
    sm.iterations = 1
    _apply_all(obj)
    _decimate(obj, tris)

    # Laces, built after the remesh (too fine for it): crossing between the eyelets up the
    # lacing, pulled straight from eyelet to eyelet over the tongue.
    me = obj.data
    bvh = _bvh(obj)
    bm = bmesh.new()
    bm.from_mesh(me)
    solid = len(bm.verts)
    rows = []
    for row in eyes:
        pr = []
        for p, _n in row:
            q = Vector(p)
            q.y += _pitch(q.z, q.y)
            hit, nrm = _nearest(bvh, q)
            pr.append((hit + nrm * 0.0016, nrm))
        rows.append(pr)

    def lace(a, b, lift):
        nrm = (a[1] + b[1]).normalized()
        pts = [_gv(a[0].lerp(b[0], k / 6) + nrm * lift * math.sin(math.pi * k / 6)) for k in range(7)]
        add_sweep(bm, pts, [(0.0037, 0.0013)] * len(pts), segs=6, across=Vector((0, 0, 1)))

    lace(rows[0][0], rows[0][1], 0.001)
    for k in range(len(rows) - 1):
        lace(rows[k][0], rows[k + 1][1], 0.0016 + 0.0016 * (k % 2))
        lace(rows[k][1], rows[k + 1][0], 0.0032 - 0.0016 * (k % 2))
    # A line of white piping across each quarter, between the two stitched lines over the
    # sweep (geometry like the laces: too fine a stripe for the mesh's vertex colors).
    for side in (() if old else (-1, 1)):
        pts = []
        for k in range(41):
            z = -0.122 + 0.2 * k / 40
            q = Vector((0.0, SOLE + _sweep(z) + 0.011, z))
            if _cap_edge(q) > -0.02:
                break
            q.y += _pitch(q.z, q.y)
            hit = bvh.ray_cast(g(0.2 * side, q.y, q.z), g(-side, 0, 0), 0.3)
            if hit[0] is not None:
                pts.append(hit[0] + hit[1] * 0.0005)
        add_sweep(bm, pts, [(0.0026, 0.001)] * len(pts), segs=6, across=Vector((0, 0, 1)))
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()

    def panel(p, n):
        p = _flat(p)
        low = lower(p) * _smoothstep(0.3, 0.5, abs(n.x)) * (p.y - SOLE < COLLAR + 0.004)
        if not old:
            return low
        # the darker leather: the toe cap, the heel counter and backstay, the sole's edge
        s = p.y - SOLE
        cap = _smoothstep(-0.003, 0.0, _cap_edge(p)) * (p.z > 0.04) * (s < 0.075)
        heel = _smoothstep(-0.1275, -0.1315, p.z) * (s < COLLAR + 0.002) * (abs(p.x) < 0.047 or s < 0.062)
        counter = _smoothstep(0.064, 0.06, s) * _smoothstep(-0.085, -0.095, p.z)
        sole = _smoothstep(0.007, 0.005, s)
        return max(low, cap, heel, counter, sole)

    def trim(p, n):
        p = _flat(p)
        s = p.y - SOLE
        holder = 0.0 if old else 1 - _smoothstep(-0.003, 0.001, s)
        # the tongue's felt: rolled over its top, and down its back (against the shin)
        on_tongue = _smoothstep(-0.085, -0.075, p.z) * (abs(p.x) < 0.046)
        felt = on_tongue * max(_smoothstep(tongue_top - 0.012, tongue_top - 0.006, s),
                               _smoothstep(COLLAR + 0.008, COLLAR + 0.014, s) * _smoothstep(0.45, 0.15, n.z))
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
    (rounder at the toe), its top up inside the holder's rail."""
    bm = bmesh.new()
    prof = []
    n = 64
    for k in range(n + 1):
        z = STEEL_Z[0] + (STEEL_Z[1] - STEEL_Z[0]) * k / n
        prof.append((z, min(_steel_bottom(z), STEEL_TOP - 0.004)))
    top = [(z, max(STEEL_TOP, y + 0.004)) for z, y in reversed(prof)]
    outline = prof + top
    half = 0.0021
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


# --- The old-time tube skate -----------------------------------------------------------
#
# Before molded holders a skate's runner hung from a frame of steel tube: one tube along
# the top of the blade, a cup under the heel and one under the ball of the foot standing
# on it, each flaring out to a plate riveted to the sole, and a thin stanchion at the toe.

TUBE_Y = 0.036       # the tube's center line above the ice
TUBE_R = 0.0064
CUPS = ((-0.104, 0.0085, 0.0185, (0.031, 0.043)),     # (z, radius at the tube, at the plate, the plate's half size x / z)
        (0.076, 0.0085, 0.02, (0.036, 0.056)),
        (0.132, 0.0052, 0.008, None))


def build_old_steel():
    bm = bmesh.new()
    X = Vector((1, 0, 0))
    z0, z1 = STEEL_Z[0] + 0.006, STEEL_Z[1] - 0.008
    add_sweep(bm, [g(0, TUBE_Y, z0 + (z1 - z0) * k / 4) for k in range(5)], [(TUBE_R, TUBE_R)] * 5, across=X, segs=12)
    for z, r0, r1, plate in CUPS:
        top = SOLE + _pitch(z, SOLE) + 0.001
        pts, radii = [], []
        for k in range(7):
            t = k / 6
            pts.append(g(0, TUBE_Y + (top - TUBE_Y) * t, z))
            radii.append((r0 + (r1 - r0) * t ** 2.2,) * 2)      # a cup: flaring out toward the sole
        add_sweep(bm, pts, radii, segs=14, across=X)
        if plate:      # (a flat oval; Blender axes: x, the skate's length, up)
            add_sphere(bm, g(0, top, z + (0.006 if z > 0 else 0.0)), 1.0, segs=16, rings=6, scale=(plate[0], plate[1], 0.0032))
    for f in bm.faces:
        f.smooth = True
    # The runner, its top up inside the tube, its toe curling up to meet the tube's end.
    prof = []
    n = 64
    for k in range(n + 1):
        z = STEEL_Z[0] + (STEEL_Z[1] - STEEL_Z[0]) * k / n
        prof.append((z, min(_steel_bottom(z), TUBE_Y - 0.004)))
    outline = prof + [(z, TUBE_Y) for z, _y in reversed(prof)]
    half = 0.0021
    front = [bm.verts.new(g(half, y, z)) for z, y in outline]
    back = [bm.verts.new(g(-half, y, z)) for z, y in outline]
    m = len(outline)
    for i in range(m):
        j = (i + 1) % m
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bm.faces.new(list(reversed(front)))
    bm.faces.new(back)
    obj = make_object("SkateOldSteel", bm, smooth=False)
    obj.data.materials.append(material("Steel", (0.8, 0.82, 0.85, 1.0)))
    return obj


def build_old(do_export=False):
    """The Old-Time Set's skate: skate_old.glb (boot) and skate_old_steel.glb (tube frame
    and runner); tools/build_gear.gd (only=skate) makes skate_old.res from them."""
    boot = build_boot(old=True)
    boot.location = Vector((0.3, 0, 0))
    steel = build_old_steel()
    steel.location = Vector((0.3, 0, 0))
    if do_export:
        for o, name in ((boot, "skate_old.glb"), (steel, "skate_old_steel.glb")):
            o.location = Vector((0, 0, 0))
            export(o, name)
            o.location = Vector((0.3, 0, 0))
    return boot, steel


def build_all(do_export=False):
    boot = build_boot()
    steel = build_steel()
    if do_export:
        export(boot, "skate.glb")
        export(steel, "skate_steel.glb")
    build_old(do_export)
    return boot, steel


if "--" in sys.argv and __name__ == "__main__":      # headless: blender -b -P skate_gear.py -- [export] [old]
    _args = sys.argv[sys.argv.index("--") + 1:]
    (build_old if "old" in _args else build_all)("export" in _args)
