# Builds the two skater helmets in Blender and exports them to assets/equip/helmet_a.glb
# and helmet_b.glb; tools/build_gear.gd (only=helmet) turns them into
# assets/characters/helmet.res and helmet_b.res.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/helmet_gear.py").read()); build_all(True)
# The chin straps are laid on the male head: dump it first with
#   godot --headless --path . -s res://tools/dump_heads.gd -- out=<dir>
# import <dir>/head_male.obj (forward -Z, up Y) and name its skin object as HEAD_OBJ says
# (as tools/blender/mask_gear.py wants it too); without it the straps follow their control
# paths unprojected.
#
#   A  modern two-piece shell: a crown piece riding over a lower band, long slot vents
#      along the top, side slots, a rear adjuster, a short "pro cut" visor.
#   B  classic one-piece: squarer and flatter-topped, a molded rib around it above the
#      brow, vertical forehead slots, vent grooves on the sides, a rubber edge, a short
#      straight-cut visor.
#   C  the round '80s bucket (the Pro Shop's): a smooth round dome, round vent holes, cut
#      high over the ears, which stay open inside a loop hanging from the shell.
# All: a Y chin strap (front and rear straps meeting at a buckle under the ear, then along
# the jaw to a chin cup) laid along the head's own surface; A and B have ear holes and guards.
#
# Face gear (the Pro Shop's, worn in place of the visor): a full wire cage and a full clear
# shield, built once per helmet so each hangs from that helmet's own brow, and exported to
# assets/equip/face_<a|b|c>.glb (nodes cage, cage_hw, shield, shield_hw); build_gear.gd
# makes face_cage_<x>.res and face_shield_<x>.res, which the game hangs on the helmet.
# build_new(True) builds helmet C and all the face gear without touching A and B.
#
# The Grays' alien visor (their signature gear; face gear, worn in place of the visor): a
# pair of great black slanted eyes, a bulging almond lens over each of the player's own,
# its inner corner low beside the nose and its outer corner drawn up to a point at the
# temple, the two joined by a thin bar over the nose. (One shield with a notch for the
# nose, tried first, read as ski goggles.)
# Built per helmet (build_alien, build_aliens(True)) and exported to
# assets/equip/alien_<a|b|c>.glb (nodes lens, hw); build_gear.gd (only=face) makes
# face_alien_<x>.res.
#
# The Chupacabras' pieces (their signature gear, worn on whichever helmet a player has; in
# the game each is its own cosmetic): a ridge of spines down the middle of the shell from
# the brow to the nape (a helmet crest), and two fangs hanging from the visor's lower edge
# (a dangler). Their glowing red eyes are the game's work, on the player's own eyes.
# Built per helmet (build_chupa, build_dress(True)) and exported to
# assets/equip/chupa_<a|b|c>.glb (nodes spines, fangs); build_gear.gd (only=dress) makes
# crest_spines_<x>.res and dangler_fangs_<x>.res.
#
# Frame (game coordinates, meters): the origin CROWN below the top of a head HEAD_W wide,
# centered, +Y up, +Z the face, +X the head's left. The game sets a helmet on each body's
# crown, scaled by its head width (SkaterVisual._build_helmet); the male head is brought
# into the frame the same way here (head_fit), so the straps lie on him as he wears it.
# The frame's numbers are the downloaded male body's the game began with: our own male's
# head is 1% narrower and its crown 6 mm lower over the same face, so on him the helmet is
# that much smaller and sits that much lower on the brow, as it would on a real head.
# Objects become glTF nodes, and build_gear.gd sorts the surfaces by node name:
#   shell (team color) · trim (white) · dark (straps, buckles, ear guards, liner, screws)
#   · visor (clear shield) · visor_hw (its clips and screws; shown with the visor only)

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\helmet_gear.py")))))
OUT = os.path.join(PROJECT, "assets", "equip")
COLLECTION = "HelmetGear"

# SkaterVisual's fitting constants: HELMET_CROWN, HELMET_HEAD_W.
CROWN = 0.1447
HEAD_W = 0.1939
# The male head (tools/dump_heads.gd, imported and named as above) and its head box
# (skeleton space, from the dump's printout).
HEAD_OBJ = "head_male"
HEAD_BOX = ((-0.095738, 1.553988, -0.049997), (0.191476, 0.286012, 0.237688))


def head_fit():
    """(at, scale): where the game puts the helmets' frame on the male body (skeleton
    space), as SkaterVisual._build_helmet does."""
    pos, size = Vector(HEAD_BOX[0]), Vector(HEAD_BOX[1])
    k = size.x / HEAD_W
    return Vector((pos.x + size.x * 0.5, pos.y + size.y - CROWN * k, pos.z + size.z * 0.5)), k


# Where the finished helmets stand in the scene: on the male head.
HEAD_CENTER = tuple(head_fit()[0])


def g(x, y, z):
    """Game coordinates (Y up, +Z front) to Blender (Z up); the glTF exporter maps back."""
    return Vector((x, -z, y))


def gv(v):
    """Blender vector back to game coordinates."""
    return Vector((v.x, v.z, -v.y))


def _smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _lerp(a, b, t):
    return a + (b - a) * t


def keyed(keys, a):
    """A smooth curve through [(angle deg, value)] at |a| (deg, 0..180): monotone cubic
    (no overshoot), level at 0 and 180 so it's smooth across the front and back where
    the two sides meet. (Easing each span on its own flattened the line at every key, a
    visible wave along edges.)"""
    a = min(abs(wrap_deg(a)), 180.0)
    xs = [k[0] for k in keys]
    ys = [k[1] for k in keys]
    n = len(xs)
    if a <= xs[0]:
        return ys[0]
    if a >= xs[-1]:
        return ys[-1]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1 = 2 * (xs[i + 1] - xs[i]) + (xs[i] - xs[i - 1])
            w2 = (xs[i + 1] - xs[i]) + 2 * (xs[i] - xs[i - 1])
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    if xs[0] > 0.0:
        m[0] = d[0]
    if xs[-1] < 180.0:
        m[-1] = d[-1]
    k = next(i for i in range(n - 1) if xs[i] <= a <= xs[i + 1])
    h = xs[k + 1] - xs[k]
    t = (a - xs[k]) / h
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * m[k]
            + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h * m[k + 1])


# --- Shell surface -----------------------------------------------------------------------
#
# The outer surface: walls running straight down from a superellipsoid cap, tucking in a
# little toward the rim. In plan the helmet is a superellipse (exponent p); the cap's
# curve from the walls over to the top has its own exponent pv: higher = squarer
# shoulders and a flatter top (hockey helmets, not a dome); pv_fb is the same toward the
# front and back, rounder, so the side profile stays a smooth arc. cy is the widest level (the
# top of the walls), b the cap's height above it. Azimuth a: 0 = front (+Z), 90 = the left
# side (+X), 180 = back.

class Shape:
    def __init__(self, ax, cf, cb, cy, b, p, tuck=0.05, zc=0.0, tuck_back=0.0, pv=None, tuck_y=None,
                 pv_fb=None):
        self.ax, self.cf, self.cb, self.cy, self.b, self.p, self.tuck, self.zc = ax, cf, cb, cy, b, p, tuck, zc
        self.tuck_back = tuck_back   # more tuck toward the back (under the skull)
        self.pv = pv if pv is not None else p
        # Rounder toward the front and back: squared off seen from the front, a long smooth
        # arc from the brow over to the back seen from the side.
        self.pv_fb = pv_fb if pv_fb is not None else self.pv
        self.tuck_y = tuck_y if tuck_y is not None else cy   # the walls tuck in below this

    def rho(self, a):
        """Horizontal radius at the widest level, toward azimuth a (deg)."""
        s, c = math.sin(math.radians(a)), math.cos(math.radians(a))
        cz = self.cf if c >= 0 else self.cb
        p = self.p
        return 1.0 / ((abs(s) / self.ax) ** p + (abs(c) / cz) ** p) ** (1.0 / p)

    def profile(self, a, y_rim, n=44, grow=0.0, y_top=None):
        """Points (game Vectors) from the rim at y_rim up over the cap to the top (or up
        to y_top), evenly spaced, toward azimuth a; `grow` pushes the surface out along
        its normal."""
        d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
        r0 = self.rho(a)
        pts = []
        # Wall: from the rim up to the widest level.
        if y_rim < self.cy:
            k = 24
            for i in range(k):
                y = _lerp(y_rim, self.cy, i / k)
                t = max(0.0, self.tuck_y - y) / 0.12
                tk = self.tuck + self.tuck_back * _smooth(100.0, 180.0, abs(a))
                pts.append((r0 * (1 - tk * t * t), y))
        # Cap (from exactly the rim when the rim is above the widest level).
        k = 120
        pv = _lerp(self.pv_fb, self.pv, math.sin(math.radians(a)) ** 2)
        e0 = 0.0
        if y_rim > self.cy:
            e0 = math.asin(min(1.0, ((y_rim - self.cy) / self.b) ** (pv / 2.0)))
        for i in range(k + 1):
            e = e0 + (math.pi * 0.5 - e0) * i / k
            ce, se = max(0.0, math.cos(e)), max(0.0, math.sin(e))
            h = r0 * (ce ** (2.0 / pv))
            y = self.cy + self.b * (se ** (2.0 / pv))
            if y >= y_rim - 1e-9:
                pts.append((h, y))
        if y_top is not None:
            keep = [q for q in pts if q[1] <= y_top]
            nxt = next((q for q in pts if q[1] > y_top), None)
            if nxt is not None and keep:
                q0 = keep[-1]
                t = (y_top - q0[1]) / max(nxt[1] - q0[1], 1e-9)
                keep.append((_lerp(q0[0], nxt[0], t), y_top))
            pts = keep
        # Resample by arc length.
        L = [0.0]
        for (h0, y0), (h1, y1) in zip(pts, pts[1:]):
            L.append(L[-1] + math.hypot(h1 - h0, y1 - y0))
        out = []
        for i in range(n + 1):
            s = L[-1] * i / n
            j = max(0, min(len(L) - 2, next((q for q in range(len(L) - 1) if L[q + 1] >= s), len(L) - 2)))
            t = 0.0 if L[j + 1] == L[j] else (s - L[j]) / (L[j + 1] - L[j])
            h = _lerp(pts[j][0], pts[j + 1][0], t)
            y = _lerp(pts[j][1], pts[j + 1][1], t)
            out.append(Vector((d.x * h, y, self.zc + d.z * h)))
        if grow:
            # Push out along the profile's normal (in its vertical plane).
            res = []
            for i, q in enumerate(out):
                a0 = out[max(0, i - 1)]
                a1 = out[min(len(out) - 1, i + 1)]
                tng = (a1 - a0).normalized()
                hor = Vector((q.x, 0.0, q.z - self.zc))
                hor = hor.normalized() if hor.length > 1e-6 else Vector((0, 0, 0))
                nrm = (hor * tng.y - Vector((0, 1, 0)) * (tng.x * hor.x + tng.z * hor.z))
                nrm = nrm.normalized() if nrm.length > 1e-6 else Vector((0, 1, 0))
                res.append(q + nrm * grow)
            out = res
        return out


def shell_patch(bm, shape, rim_fn, top_fn=None, nu=128, nv=44, grow=0.0):
    """The outer surface between rim_fn(a) and top_fn(a) (None: over the top), as a grid
    of quads (a fan at the top pole). Returns nothing; faces go into bm."""
    rings = []
    for i in range(nu):
        a = 360.0 * i / nu - 180.0
        prof = shape.profile(a, rim_fn(a), nv, grow, None if top_fn is None else top_fn(a))
        rings.append([bm.verts.new(g(q.x, q.y, q.z)) for q in (prof if top_fn else prof[:-1])])
    m = min(len(r) for r in rings)
    for i in range(nu):
        r0, r1 = rings[i], rings[(i + 1) % nu]
        for j in range(m - 1):
            f = bm.faces.new((r0[j], r1[j], r1[j + 1], r0[j + 1]))
            f.smooth = True
    if top_fn is None:
        top = shape.profile(0.0, rim_fn(0.0), nv, grow)[-1]
        pole = bm.verts.new(g(top.x, top.y, top.z))
        for i in range(nu):
            f = bm.faces.new((rings[i][m - 1], rings[(i + 1) % nu][m - 1], pole))
            f.smooth = True


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


def grid(bm, pts):
    """Quads over a grid of game points pts[i][j]."""
    vs = [[bm.verts.new(g(*q)) for q in row] for row in pts]
    for i in range(len(vs) - 1):
        for j in range(len(vs[0]) - 1):
            f = bm.faces.new((vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]))
            f.smooth = True


def band_patch(bm, shape, a0, a1, lo_fn, hi_fn, nu=40, nv=6, grow=0.0):
    """An open strip of the surface from azimuth a0 to a1 (a1 may pass 180), between
    lo_fn(a) and hi_fn(a): a raised piece once solidified."""
    rows = []
    for i in range(nu + 1):
        a = wrap_deg(_lerp(a0, a1, i / nu))
        rows.append(shape.profile(a, lo_fn(a), nv, grow, hi_fn(a)))
    m = min(len(r) for r in rows)
    grid(bm, [r[:m] for r in rows])


def surf_dir(shape, d, grow=0.0):
    """(point, normal) where a ray from the shape's center (0, cy, zc) along d meets the
    surface."""
    a = math.degrees(math.atan2(d.x, d.z))
    el = math.atan2(d.y, math.hypot(d.x, d.z))
    prof = shape.profile(a, -0.12, 220, grow)
    c = Vector((0.0, shape.cy, shape.zc))

    def elev(q):
        r = q - c
        return math.atan2(r.y, math.hypot(r.x, r.z))
    lo, hi = 0, len(prof) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if elev(prof[mid]) < el:
            lo = mid
        else:
            hi = mid
    e0, e1 = elev(prof[lo]), elev(prof[hi])
    t = 0.0 if e1 == e0 else max(0.0, min(1.0, (el - e0) / (e1 - e0)))
    p = prof[lo].lerp(prof[hi], t)
    n = (prof[hi] - prof[lo]).normalized()
    hor = Vector((p.x, 0.0, p.z - shape.zc))
    hor = hor.normalized() if hor.length > 1e-6 else Vector((0, 0, 1))
    nrm = (hor * n.y - Vector((0, 1, 0)) * (n.x * hor.x + n.z * hor.z))
    return p, (nrm.normalized() if nrm.length > 1e-6 else Vector((0, 1, 0)))


def meridian(shape, y_front, y_back, n=60):
    """Points along the center line (x = 0) from y_front at the front, over the top, down
    to y_back at the back, evenly spaced."""
    f = shape.profile(0.0, y_front, 120)
    b = shape.profile(180.0, y_back, 120)
    pts = f + list(reversed(b))[1:]
    L = [0.0]
    for p0, p1 in zip(pts, pts[1:]):
        L.append(L[-1] + (p1 - p0).length)
    out = []
    for i in range(n + 1):
        s = L[-1] * i / n
        j = max(0, min(len(L) - 2, next((q for q in range(len(L) - 1) if L[q + 1] >= s), len(L) - 2)))
        t = 0.0 if L[j + 1] == L[j] else (s - L[j]) / (L[j + 1] - L[j])
        out.append(pts[j].lerp(pts[j + 1], t))
    return out


def spine_patch(bm, shape, y_front, y_back, width_fn, grow, nv=48, nu=10):
    """A strip along the center line over the top (front y_front to back y_back), width_fn(t)
    to each side (t 0 front .. 1 back), on the surface pushed out by grow."""
    mer = meridian(shape, y_front, y_back, nv)
    c = Vector((0.0, shape.cy, shape.zc))
    rows = []
    for i, m in enumerate(mer):
        w = width_fn(i / nv)
        row = []
        for j in range(nu + 1):
            q = m + Vector((_lerp(-w, w, j / nu), 0.0, 0.0))
            p, _ = surf_dir(shape, q - c, grow)
            row.append(p)
        rows.append(row)
    grid(bm, rows)


# --- Objects and modifiers ---------------------------------------------------------------

def collection():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def new_object(name, build, offset=Vector()):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    if bpy.data.meshes.get(name) is not None:
        bpy.data.meshes.remove(bpy.data.meshes[name])
    bm = bmesh.new()
    build(bm)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # Open surfaces (shells) face out from the head's center.
    c = g(0.0, 0.02, 0.0)
    out = sum((f.calc_center_median() - c).dot(f.normal) for f in bm.faces)
    if out < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection().objects.link(obj)
    obj.location = offset
    return obj


def solidify(obj, thick, bevel=0.0012):
    m = obj.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thick
    m.offset = -1.0
    m.use_rim = True
    m.use_even_offset = False   # (even offset spikes at the pole fan)
    if bevel > 0:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 1
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(50)
        b.harden_normals = False


def apply_all(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    mesh = bpy.data.meshes.new_from_object(ev)
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    bpy.data.meshes.remove(old)
    mesh.name = obj.name


def cut(obj, cutters):
    """Boolean-subtracts the cutter objects (then deletes them)."""
    for c in cutters:
        c.location = obj.location   # cutters are built in the helmet's own frame
        m = obj.modifiers.new("cut", "BOOLEAN")
        m.operation = "DIFFERENCE"
        m.solver = "EXACT"
        m.object = c
        c.hide_set(True)
        c.hide_render = True
    apply_all(obj)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)


def stadium_cutter(name, center, along, across, length, width, depth, segs=10):
    """A rounded slot (stadium) of `length` x `width` in the plane spanned by along/across
    (game unit vectors), extruded `depth` both ways along their normal: a vent cutter."""
    along = along.normalized()
    across = (across - along * across.dot(along)).normalized()
    nrm = along.cross(across)

    def build(bm):
        r = width * 0.5
        half = max(0.0, length * 0.5 - r)
        ring = []
        for k in range(segs + 1):
            t = math.pi * k / segs - math.pi * 0.5
            ring.append(along * (half + r * math.cos(t)) + across * (r * math.sin(t)))
        for k in range(segs + 1):
            t = math.pi * k / segs + math.pi * 0.5
            ring.append(along * (-half + r * math.cos(t)) + across * (r * math.sin(t)))
        lo = [bm.verts.new(g(*(center + q - nrm * depth))) for q in ring]
        hi = [bm.verts.new(g(*(center + q + nrm * depth))) for q in ring]
        n = len(ring)
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
        bm.faces.new(list(reversed(lo)))
        bm.faces.new(hi)
    global _cut_n
    _cut_n += 1
    return new_object("%s_%d" % (name, _cut_n), build)


_cut_n = 0


def material(name, color, rough=0.5, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (color[0], color[1], color[2], alpha)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except (AttributeError, TypeError):
            pass
    return m


def mats():
    return {"shell": material("HelmetShell", (0.1, 0.25, 0.7), 0.3),
            "trim": material("HelmetTrim", (0.92, 0.92, 0.9), 0.4),
            "dark": material("HelmetDark", (0.05, 0.05, 0.06), 0.5),
            "visor": material("HelmetVisor", (0.6, 0.7, 0.8), 0.05, 0.35),
            "visor_hw": material("HelmetVisorHW", (0.08, 0.08, 0.09), 0.4)}


def head_offset():
    return g(*HEAD_CENTER)


# --- Surface queries and the head ------------------------------------------------------------

def surf_pt(shape, a, y, grow=0.0):
    """(point, outward normal) on the shape's outer surface at azimuth a, height y."""
    prof = shape.profile(a, -0.12, 260, grow)
    for i in range(len(prof) - 1):
        q0, q1 = prof[i], prof[i + 1]
        if q0.y <= y <= q1.y or i == len(prof) - 2:
            t = 0.0 if q1.y == q0.y else (y - q0.y) / (q1.y - q0.y)
            p = q0.lerp(q1, max(0.0, min(1.0, t)))
            tng = (q1 - q0).normalized()
            hor = Vector((p.x, 0.0, p.z - shape.zc))
            hor = hor.normalized() if hor.length > 1e-6 else Vector((0, 0, 1))
            n = hor * tng.y - Vector((0, 1, 0)) * (tng.x * hor.x + tng.z * hor.z)
            return p, n.normalized()
    return prof[-1], Vector((0, 1, 0))


def side_pt(shape, z, y, side=1.0, grow=0.0):
    """The surface point on the left (side 1) or right (-1) at depth z, height y."""
    a = 90.0 * side
    for _ in range(6):
        p, n = surf_pt(shape, a, y, grow)
        a = math.degrees(math.atan2(p.x, z - shape.zc))
    return surf_pt(shape, a, y, grow)


_bvh = None


def head_bvh():
    """BVH of the male head in the helmets' frame, or None."""
    global _bvh
    if _bvh is not None:
        return _bvh
    o = bpy.data.objects.get(HEAD_OBJ)
    if o is None:
        print("(reference head %s not loaded: straps follow their plain paths)" % HEAD_OBJ)
        return None
    c, k = head_fit()
    verts = [(gv(o.matrix_world @ v.co) - c) / k for v in o.data.vertices]
    polys = [tuple(p.vertices) for p in o.data.polygons]
    _bvh = BVHTree.FromPolygons(verts, polys)
    return _bvh


def on_head(p, lift):
    """p moved onto the head's surface, `lift` out along its normal."""
    bvh = head_bvh()
    if bvh is None:
        return p, Vector((0, -1, 0))
    loc, nrm, _, _ = bvh.find_nearest(p)
    if loc is None:
        return p, Vector((0, -1, 0))
    if (p - loc).length > 1e-5 and nrm.dot(p - loc) < 0:
        nrm = -nrm
    return loc + nrm * lift, nrm


# --- Parts ---------------------------------------------------------------------------------

def ring_pts(c, u, v, ru, rv, segs, p=2.0):
    out = []
    for k in range(segs):
        t = math.tau * k / segs
        cu, su = math.cos(t), math.sin(t)
        out.append(c + u * (ru * math.copysign(abs(cu) ** (2.0 / p), cu))
                   + v * (rv * math.copysign(abs(su) ** (2.0 / p), su)))
    return out


def tube(bm, rings, closed=False, caps=True):
    """Joins equal-size rings (game Vectors) into a tube; `closed` loops it."""
    loops = [[bm.verts.new(g(*q)) for q in r] for r in rings]
    n = len(loops)
    segs = len(loops[0])
    for i in range(n if closed else n - 1):
        a, b = loops[i], loops[(i + 1) % n]
        for k in range(segs):
            k2 = (k + 1) % segs
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.smooth = True
    if caps and not closed:
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])


def strap_along(bm, pts, nrms, width, thick, segs=10):
    """A flat strap through pts, its flat side against the surface normals."""
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = nrms[i] - t * nrms[i].dot(t)
        n = n.normalized() if n.length > 1e-6 else Vector((0, 0, 1))
        across = t.cross(n).normalized()
        rings.append(ring_pts(p, across, n, width * 0.5, thick * 0.5, segs, 5.0))
    tube(bm, rings)


def spline(ctrl, n):
    """Catmull-Rom through control points, n samples."""
    pts = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    out = []
    for i in range(n):
        s = i / (n - 1) * (len(ctrl) - 1)
        j = min(int(s), len(ctrl) - 2)
        t = s - j
        p0, p1, p2, p3 = pts[j], pts[j + 1], pts[j + 2], pts[j + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    return out


def lay(ctrl, n, lift, free_until=0.0):
    """Samples a spline through ctrl and lays it on the head; the first `free_until`
    fraction eases from the plain path (inside the helmet) onto the skin."""
    pts, nrms = [], []
    samples = spline(ctrl, n)
    for i, q in enumerate(samples):
        p, nr = on_head(q, lift)
        k = _smooth(0.0, free_until, i / (n - 1)) if free_until > 0 else 1.0
        pts.append(q.lerp(p, k))
        nrms.append(nr)
    return pts, nrms


def chin_strap(bm, front, back, buckle, jaw, width=0.015, thick=0.0022, lift=0.0035):
    """Y chin strap: the front and rear straps (from inside the helmet's band) meet at a
    buckle below the ear; from there one strap runs along the jaw and under the chin to
    the other side, laid on the head's surface. Points are the left side's (+X)."""
    m = Vector((-1, 1, 1))
    for s in (1.0, -1.0):
        f = (lambda v: v) if s > 0 else (lambda v: v * m)
        for start in (front, back):
            pts, nrms = lay([f(start), f(start.lerp(buckle, 0.5)), f(buckle)], 10, lift, 0.6)
            strap_along(bm, pts, nrms, width * 0.85, thick)
        # The buckle: a small rounded block on the strap.
        p, n = on_head(f(buckle), lift + 0.002)
        u = (f(jaw[0]) - f(buckle)).normalized()
        u = (u - n * u.dot(n)).normalized()
        rounded_box(bm, p, u, n.cross(u).normalized(), n, 0.011, 0.0095, 0.0035, segs=12, rings=5)
    ctrl = [buckle] + list(jaw) + [q * m for q in reversed(jaw)] + [buckle * m]
    pts, nrms = lay(ctrl, 56, lift)
    strap_along(bm, pts, nrms, width, thick)


def chin_cup(bm, at, size=(0.034, 0.024, 0.006), lift=0.006):
    """The padded cup under the chin, on the strap."""
    p, n = on_head(at, lift)
    u = Vector((1, 0, 0))
    v = n.cross(u).normalized()
    u = v.cross(n).normalized()
    rounded_box(bm, p, u, v, n, size[0] * 0.5, size[1] * 0.5, size[2] * 0.5, segs=16, rings=6, p=3.0)


def rounded_box(bm, c, u, v, w, su, sv, sw, segs=8, rings=6, p=4.0):
    """A rounded box (superellipsoid) centered at c with axes u, v, w (unit, game)."""
    rs = []
    for i in range(1, rings):
        e = -math.pi / 2 + math.pi * i / rings
        ce, se = math.cos(e), math.sin(e)
        ce2 = abs(ce) ** (2.0 / p)
        se2 = math.copysign(abs(se) ** (2.0 / p), se)
        rs.append(ring_pts(c + w * (sw * se2), u, v, su * ce2, sv * ce2, segs, p))
    tube(bm, rs, caps=True)


def screw(bm, p, n, r=0.004, h=0.0016):
    u = n.cross(Vector((0, 1, 0)))
    u = u.normalized() if u.length > 1e-4 else Vector((1, 0, 0))
    v = n.cross(u)
    rounded_box(bm, p + n * h * 0.3, u, v, n, r, r, h, segs=12, rings=4, p=2.4)


def ear_ring(bm, shape, z, y, lz, ly, side, grow=0.0012, r=0.0026):
    """A rubber surround on the ear hole's edge (an oval lz x ly around (z, y))."""
    loop = []
    nseg = 32
    for k in range(nseg):
        t = math.tau * k / nseg
        loop.append(side_pt(shape, z + (lz * 0.5) * math.cos(t), y + (ly * 0.5) * math.sin(t), side, grow))
    rings = []
    for i, (p, n) in enumerate(loop):
        t = (loop[(i + 1) % nseg][0] - loop[i - 1][0]).normalized()
        v = t.cross(n).normalized()
        rings.append(ring_pts(p, n, v, r, r * 1.3, 8))
    tube(bm, rings, closed=True)


def visor_shield(bm, shape, a_max, y_top, bottom_keys, gap=0.007, flare=0.05, nu=48, nv=14):
    """The clear shield: an arc around the front from -a_max to a_max, y_top down to the
    bottom edge (bottom_keys: deg -> y), standing off the shell by `gap` and flaring out
    toward its bottom edge."""
    rows = []
    for i in range(nu + 1):
        a = -a_max + 2 * a_max * i / nu
        top_p, _ = surf_pt(shape, a, y_top)
        d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
        r_top = Vector((top_p.x, 0.0, top_p.z - shape.zc)).length + gap
        yb = keyed(bottom_keys, a)
        col = []
        for j in range(nv + 1):
            y = _lerp(y_top, yb, j / nv)
            r = r_top + flare * (y_top - y)
            col.append(Vector((d.x * r, y, shape.zc + d.z * r)))
        rows.append(col)
    vs = [[bm.verts.new(g(*q)) for q in col] for col in rows]
    for i in range(nu):
        for j in range(nv):
            f = bm.faces.new((vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]))
            f.smooth = True


def join(name, objs):
    objs = [o for o in objs if o is not None]
    for o in objs:
        if o.modifiers:
            apply_all(o)
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
                                       selected_objects=objs, object=objs[0]):
            bpy.ops.object.join()
    o = objs[0]
    old = bpy.data.objects.get(name)
    if old is not None and old != o:
        bpy.data.objects.remove(old, do_unlink=True)
    o.name = name
    o.data.name = name
    return o




# --- Helmet A: modern two-piece ------------------------------------------------------------

A_SHAPE = Shape(ax=0.108, cf=0.124, cb=0.144, cy=0.07, b=0.097, p=2.3, pv=3.4, tuck=0.12, zc=-0.004,
                tuck_back=0.1, tuck_y=0.03, pv_fb=2.1)
# The lower band's bottom edge (deg from the front: y): over the brow, cut up at the
# temples, down in front of the ear, around the back of the skull.
A_RIM = [(0, 0.066), (28, 0.064), (46, 0.046), (58, 0.006), (70, -0.036), (95, -0.044),
         (125, -0.05), (150, -0.068), (180, -0.076)]
# Where the crown piece's lower edge runs (over the band).
A_SPLIT = [(0, 0.092), (35, 0.09), (60, 0.078), (95, 0.062), (130, 0.046), (160, 0.03), (180, 0.026)]
# Ear hole: center z, y, length (z), height (y). (Both helmets' holes went up 5 mm with our
# own male head: under a crown that much lower his ears sit that much higher in the frame.)
A_EAR = (-0.006, 0.005, 0.034, 0.024)
A_SCREWS = (63.0, (0.028, 0.048))      # visor screws: azimuth, heights
A_VISOR_BOTTOM = [(0, -0.03), (28, -0.028), (44, -0.016), (54, 0.01), (62, 0.032), (66, 0.04)]


def build_a(offset=Vector()):
    sh = A_SHAPE
    M = mats()
    # Shell: the band, and the crown riding over it.
    band = new_object("a_band", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(A_RIM, a), lambda a: keyed(A_SPLIT, a) + 0.016, nu=72, nv=10), offset)
    crown = new_object("a_crown", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(A_SPLIT, a), None, nu=72, nv=22, grow=0.0045), offset)
    for o in (band, crown):
        solidify(o, 0.0032)
        apply_all(o)
    # Vents: a long slot in the channel either side of the spine, shorter ones outboard,
    # two at the brow and two at the back. They go through the liner too (below), so the
    # hair shows in them.
    up, fwd, left = Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))

    def vents():
        cutters = []
        for s in (1.0, -1.0):
            cutters.append(stadium_cutter("cut", Vector((s * 0.042, 0.2, -0.006)), fwd, left, 0.15, 0.012, 0.11))
            cutters.append(stadium_cutter("cut", Vector((s * 0.074, 0.2, -0.045)), fwd, left, 0.07, 0.01, 0.11))
            # Side slot on the crown above the temple, along its edge.
            p, n = surf_pt(sh, s * 72.0, 0.098, 0.0045)
            cutters.append(stadium_cutter("cut", p, Vector((0, -0.25, 1)), up, 0.045, 0.009, 0.03))
            cutters.append(stadium_cutter("cut", Vector((s * 0.05, 0.112, 0.12)), left, up, 0.026, 0.008, 0.05))
            cutters.append(stadium_cutter("cut", Vector((s * 0.046, 0.09, -0.14)), left, up, 0.028, 0.008, 0.05))
        return cutters

    cut(crown, vents())
    # The raised spine down the middle (front to back over the top): its edges and the
    # channels beside it give the top its angular look.
    spine = new_object("a_spine", lambda bm: spine_patch(
        bm, sh, keyed(A_SPLIT, 0.0) + 0.008, keyed(A_SPLIT, 180.0) + 0.034,
        lambda t: _lerp(0.021, 0.03, math.sin(math.pi * min(1.0, t * 1.4)) ** 0.5), 0.0098), offset)
    solidify(spine, 0.0068, bevel=0.0016)
    apply_all(spine)
    # A raised plate across the brow, on the band under the crown's front edge.
    brow = new_object("a_brow", lambda bm: band_patch(
        bm, sh, -44.0, 44.0, lambda a: keyed(A_RIM, a) + 0.001, lambda a: keyed(A_SPLIT, a) - 0.001,
        nu=40, nv=5, grow=0.0034), offset)
    solidify(brow, 0.0048, bevel=0.0014)
    apply_all(brow)
    # Ear holes through the band.
    ez, ey, el, eh = A_EAR
    cut(band, [stadium_cutter("cut", Vector((s * 0.115, ey, ez)), fwd, up, el, eh, 0.06) for s in (1.0, -1.0)])
    shell = join("a_shell", [band, crown, spine, brow])
    shell.data.materials.append(M["shell"])

    # Trim: side adjuster clips where the crown meets the band, a plate on the back.
    def trim(bm):
        for s in (1.0, -1.0):
            p, n = surf_pt(sh, s * 108.0, keyed(A_SPLIT, 108.0) + 0.004, 0.0045)
            t = Vector((0, 1, 0)) - n * n.y
            rounded_box(bm, p + n * 0.0016, n.cross(t.normalized()).normalized(), t.normalized(), n,
                        0.013, 0.007, 0.0022, segs=16, rings=5)
        p, n = surf_pt(sh, 180.0, -0.022)
        rounded_box(bm, p + n * 0.001, Vector((1, 0, 0)), (Vector((0, 1, 0)) - n * n.y).normalized(), n,
                    0.03, 0.012, 0.0025, segs=20, rings=5)
    tr = new_object("a_trim", trim, offset)
    tr.data.materials.append(M["trim"])

    # Dark: liner, ear surrounds, visor screws, chin strap and cup.
    lin = new_object("a_liner", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(A_RIM, a) + 0.005, None, nu=48, nv=12, grow=-0.0035), offset)
    solidify(lin, 0.009, bevel=0.0)
    cut(lin, vents())   # the vents are open: the hair under the helmet shows in them

    def dark(bm):
        for s in (1.0, -1.0):
            ear_ring(bm, sh, ez, ey, el + 0.002, eh + 0.002, s)
            for y in A_SCREWS[1]:
                p, n = surf_pt(sh, s * A_SCREWS[0], y)
                screw(bm, p, n)
        f, _ = side_pt(sh, 0.034, -0.022)
        f -= Vector((0.008, 0, 0))
        b, _ = side_pt(sh, -0.062, -0.034)
        b -= Vector((0.008, 0, 0))
        chin_strap(bm, f, b, Vector((0.094, -0.07, -0.006)),
                   [Vector((0.074, -0.098, 0.024)), Vector((0.046, -0.114, 0.05)), Vector((0.018, -0.116, 0.062))])
        chin_cup(bm, Vector((0.0, -0.112, 0.064)))
    dk = join("a_dark", [new_object("a_dark", dark, offset), lin])
    dk.data.materials.append(M["dark"])

    # Visor: the shield and its clips.
    vi = new_object("a_visor", lambda bm: visor_shield(bm, sh, 66.0, 0.074, A_VISOR_BOTTOM, nu=36, nv=6), offset)
    solidify(vi, 0.0025, bevel=0.0008)
    apply_all(vi)
    vi.data.materials.append(M["visor"])

    def hw(bm):
        for s in (1.0, -1.0):
            p, n = surf_pt(sh, s * A_SCREWS[0], sum(A_SCREWS[1]) * 0.5)
            t = (Vector((0, 1, 0)) - n * n.y).normalized()
            rounded_box(bm, p + n * 0.006, n.cross(t).normalized(), t, n, 0.009, 0.019, 0.0028, segs=16, rings=5)
    vh = new_object("a_visor_hw", hw, offset)
    vh.data.materials.append(M["visor_hw"])
    return {"shell": shell, "trim": tr, "dark": dk, "visor": vi, "visor_hw": vh}


# --- Helmet B: classic one-piece ------------------------------------------------------------
#
# Squarer and flatter on top than A: one shell with a brim block across the front standing
# out over the visor (vents in its sides), a raised panel over the top, a molded rib from
# the brim around the back, dark rivet strips on the sides, slots on top and at the back, a
# rubber edge, and a short straight-cut visor tucked under the brim.

B_SHAPE = Shape(ax=0.109, cf=0.122, cb=0.14, cy=0.072, b=0.093, p=2.5, pv=3.6, tuck=0.12, zc=-0.004,
                tuck_back=0.06, tuck_y=0.03, pv_fb=2.2)
B_RIM = [(0, 0.06), (30, 0.058), (46, 0.042), (58, 0.004), (66, -0.04), (100, -0.052),
         (135, -0.056), (160, -0.068), (180, -0.072)]
B_RIB = [(0, 0.083), (60, 0.077), (100, 0.066), (140, 0.058), (180, 0.054)]   # the rib's center line
B_BRIM_A = 58.0                                           # the brim runs from -58 to 58 deg
B_BRIM_LO = [(0, 0.058), (40, 0.056), (58, 0.05)]           # its lower edge (over the visor)
B_BRIM_HI = [(0, 0.083), (40, 0.08), (58, 0.071)]           # its upper edge
B_BRIM_VENTS = (31.0, 37.0, 43.0)
B_STRIP = (-0.022, 0.03)                                    # side rivet strip: center z, y
B_RIB_H = 0.0095
B_EAR = (-0.004, 0.001, 0.034, 0.026)
B_SCREWS = (64.0, (0.026, 0.044))
B_VISOR_BOTTOM = [(0, -0.024), (44, -0.024), (54, -0.016), (59, 0.004), (62, 0.03)]


def _surface_frame(sh, a, y, grow=0.0):
    """(point, normal, up tangent, sideways tangent) on the shell."""
    p, n = surf_pt(sh, a, y, grow)
    side = Vector((math.cos(math.radians(a)), 0.0, -math.sin(math.radians(a))))
    up = side.cross(n).normalized()
    if up.y < 0:
        up = -up
    return p, n, up, n.cross(up).normalized()


def build_b(offset=Vector()):
    sh = B_SHAPE
    M = mats()
    dome = new_object("b_dome", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(B_RIM, a), None, nu=72, nv=26), offset)
    solidify(dome, 0.0034)
    apply_all(dome)
    up, fwd, left = Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))

    def brim_vents():
        """Three upright slots in each side of the brim (through the shell behind it)."""
        out = []
        for sd in (1.0, -1.0):
            for a in B_BRIM_VENTS:
                p, n, u, t = _surface_frame(sh, sd * a, _lerp(keyed(B_BRIM_LO, a), keyed(B_BRIM_HI, a), 0.5), 0.011)
                out.append(stadium_cutter("cut", p, u, t, 0.016, 0.0036, 0.03))
        return out

    def vents():
        """The open vents (through the liner too, so the hair shows in them)."""
        out = []
        for s in (1.0, -1.0):
            # Top: a slot either side of the raised panel.
            out.append(stadium_cutter("cut", Vector((s * 0.07, 0.2, -0.03)), fwd, left, 0.065, 0.0095, 0.1))
            # Back: an upright slot either side of the panel.
            p, n, u, sd = _surface_frame(sh, 180.0 - s * 24.0, 0.086)
            out.append(stadium_cutter("cut", p, u, sd, 0.028, 0.008, 0.02))
        return out

    cutters = brim_vents() + vents()
    ez, ey, el, eh = B_EAR
    for s in (1.0, -1.0):
        cutters.append(stadium_cutter("cut", Vector((s * 0.115, ey, ez)), fwd, up, el, eh, 0.06))
    cut(dome, cutters)
    # The brim: a block across the front standing out over the visor, with vents in its sides.
    brim = new_object("b_brim", lambda bm: band_patch(
        bm, sh, -B_BRIM_A, B_BRIM_A, lambda a: keyed(B_BRIM_LO, a), lambda a: keyed(B_BRIM_HI, a),
        nu=44, nv=5, grow=0.011), offset)
    solidify(brim, 0.0145, bevel=0.0018)
    apply_all(brim)
    cut(brim, brim_vents())
    # A raised panel over the top, from above the brim to the back.
    panel = new_object("b_panel", lambda bm: spine_patch(
        bm, sh, keyed(B_BRIM_HI, 0.0) + 0.006, 0.074,
        lambda t: _lerp(0.044, 0.056, math.sin(math.pi * t) ** 0.6) - 0.012 * max(0.0, t - 0.7) / 0.3, 0.0046,
        nv=44, nu=12), offset)
    solidify(panel, 0.0058, bevel=0.0016)
    apply_all(panel)
    # The molded rib, from the brim's ends around the back.
    rib = new_object("b_rib", lambda bm: band_patch(
        bm, sh, B_BRIM_A - 4.0, 360.0 - B_BRIM_A + 4.0, lambda a: keyed(B_RIB, a) - B_RIB_H * 0.5,
        lambda a: keyed(B_RIB, a) + B_RIB_H * 0.5, nu=56, nv=4, grow=0.0026), offset)
    solidify(rib, 0.0028, bevel=0.0013)
    apply_all(rib)
    shell = join("b_shell", [dome, brim, panel, rib])
    shell.data.materials.append(M["shell"])

    # Trim: the rear adjuster, and the screw heads on the side strips.
    def trim(bm):
        p, n, u, s = _surface_frame(sh, 180.0, -0.028)
        rounded_box(bm, p + n * 0.001, s, u, n, 0.026, 0.011, 0.0025, segs=20, rings=5)
        for sd in (1.0, -1.0):
            for dz in (-0.014, 0.014):
                p, n = side_pt(sh, B_STRIP[0] + dz, B_STRIP[1], sd)
                screw(bm, p + n * 0.0026, n, r=0.0034, h=0.0014)
    tr = new_object("b_trim", trim, offset)
    tr.data.materials.append(M["trim"])

    # Dark: liner, a thin rubber edge, ear surrounds, screws, chin strap and cup.
    lin = new_object("b_liner", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(B_RIM, a) + 0.005, None, nu=48, nv=12, grow=-0.0036), offset)
    solidify(lin, 0.009, bevel=0.0)
    cut(lin, vents())

    def dark(bm):
        rim = []
        n = 96
        for i in range(n):
            a = 360.0 * i / n - 180.0
            p, nr = surf_pt(sh, a, keyed(B_RIM, a) + 0.0012)
            rim.append((p - nr * 0.0013, nr))
        rings = []
        for i, (p, nr) in enumerate(rim):
            t = (rim[(i + 1) % n][0] - rim[i - 1][0]).normalized()
            rings.append(ring_pts(p, nr, t.cross(nr).normalized(), 0.0026, 0.0028, 8))
        tube(bm, rings, closed=True)
        for s in (1.0, -1.0):
            # The rivet strip on the side (its screws are trim).
            p, nr = side_pt(sh, B_STRIP[0], B_STRIP[1], s)
            t = (Vector((0, 0, 1)) - nr * nr.z).normalized()
            rounded_box(bm, p + nr * 0.0012, t, nr.cross(t).normalized(), nr, 0.03, 0.0075, 0.0022,
                        segs=16, rings=5)
            ear_ring(bm, sh, ez, ey, el + 0.002, eh + 0.002, s)
            for y in B_SCREWS[1]:
                p, nr = surf_pt(sh, s * B_SCREWS[0], y)
                screw(bm, p, nr)
        f, _ = side_pt(sh, 0.034, -0.026)
        f -= Vector((0.008, 0, 0))
        b, _ = side_pt(sh, -0.058, -0.038)
        b -= Vector((0.008, 0, 0))
        chin_strap(bm, f, b, Vector((0.094, -0.072, -0.006)),
                   [Vector((0.074, -0.098, 0.024)), Vector((0.046, -0.114, 0.05)), Vector((0.018, -0.116, 0.062))])
        chin_cup(bm, Vector((0.0, -0.112, 0.064)), size=(0.036, 0.024, 0.0065))
    dk = join("b_dark", [new_object("b_dark", dark, offset), lin])
    dk.data.materials.append(M["dark"])

    # Visor: short, straight across the bottom with rounded corners.
    vi = new_object("b_visor", lambda bm: visor_shield(
        bm, sh, 62.0, 0.069, B_VISOR_BOTTOM, gap=0.006, flare=0.03, nu=36, nv=6), offset)
    solidify(vi, 0.0025, bevel=0.0008)
    apply_all(vi)
    vi.data.materials.append(M["visor"])

    def hw(bm):
        for s in (1.0, -1.0):
            p, nr = surf_pt(sh, s * B_SCREWS[0], sum(B_SCREWS[1]) * 0.5)
            t = (Vector((0, 1, 0)) - nr * nr.y).normalized()
            rounded_box(bm, p + nr * 0.0058, nr.cross(t).normalized(), t, nr, 0.008, 0.016, 0.0026, segs=16, rings=5)
    vh = new_object("b_visor_hw", hw, offset)
    vh.data.materials.append(M["visor_hw"])
    return {"shell": shell, "trim": tr, "dark": dk, "visor": vi, "visor_hw": vh}


# --- Helmet C: the round '80s bucket ----------------------------------------------------------
#
# The one-piece helmets of the early 1980s: a smooth dome, rounder over the shoulders of
# the head than A or B and with nothing molded into it but two rows of round vent holes,
# cut high over the ears. The ears stay in the open inside a loop that hangs from the
# shell's edge and carries the chin strap.

C_SHAPE = Shape(ax=0.108, cf=0.123, cb=0.142, cy=0.066, b=0.097, p=2.15, pv=2.7, tuck=0.1, zc=-0.004,
                tuck_back=0.08, tuck_y=0.03, pv_fb=2.1)
# The edge: over the brow, down a little at the temple, an arch over the ear, down behind it.
C_RIM = [(0, 0.06), (30, 0.058), (48, 0.044), (62, 0.031), (76, 0.027), (92, 0.029), (104, 0.022),
         (118, -0.018), (132, -0.05), (156, -0.066), (180, -0.07)]
C_HOLES = (0.045, (0.05, 0.005, -0.04))        # round vents on top: x either side, z of each
C_HOLE_R = 0.0068
C_LOOP = [(0.036, 0.032), (0.034, 0.0), (0.02, -0.03), (-0.008, -0.04), (-0.036, -0.03), (-0.05, -0.006)]   # the ear loop (z, y)
C_SCREWS = (61.0, (0.04, 0.055))
C_VISOR_BOTTOM = [(0, -0.03), (28, -0.028), (44, -0.016), (54, 0.012), (61, 0.034)]


def build_c(offset=Vector()):
    sh = C_SHAPE
    M = mats()
    up, fwd, left = Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))
    dome = new_object("c_dome", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(C_RIM, a), None, nu=72, nv=26), offset)
    solidify(dome, 0.0034)
    apply_all(dome)

    def vents():
        """Round holes: three either side of the top, three along each side, two on the back."""
        out = []
        for s in (1.0, -1.0):
            for z in C_HOLES[1]:
                out.append(stadium_cutter("cut", Vector((s * C_HOLES[0], 0.2, z)), fwd, left, C_HOLE_R * 2, C_HOLE_R * 2, 0.11))
            p, n, u, sd = _surface_frame(sh, 180.0 - s * 20.0, 0.07)
            out.append(stadium_cutter("cut", p, u, sd, C_HOLE_R * 2, C_HOLE_R * 2, 0.02))
            for a in (74.0, 96.0, 118.0):       # ... and three along each side, above the ear
                p, n, u, sd = _surface_frame(sh, s * a, 0.084)
                out.append(stadium_cutter("cut", p, u, sd, C_HOLE_R * 1.7, C_HOLE_R * 1.7, 0.02))
        return out

    cut(dome, vents())
    # A raised band across the brow, round to the temples (the shell's one molded line).
    brow = new_object("c_brow", lambda bm: band_patch(
        bm, sh, -66.0, 66.0, lambda a: keyed(C_RIM, a) + 0.0015, lambda a: keyed(C_RIM, a) + 0.021,
        nu=44, nv=4, grow=0.0026), offset)
    solidify(brow, 0.004, bevel=0.0014)
    apply_all(brow)
    shell = join("c_shell", [dome, brow])
    shell.data.materials.append(M["shell"])

    # Trim: the rear adjuster plate and a screw at each temple.
    def trim(bm):
        p, n, u, s = _surface_frame(sh, 180.0, -0.03)
        rounded_box(bm, p + n * 0.001, s, u, n, 0.024, 0.01, 0.0024, segs=20, rings=5)
        for sd in (1.0, -1.0):
            p, n = surf_pt(sh, sd * 84.0, 0.05)
            screw(bm, p + n * 0.0004, n, r=0.0036, h=0.0015)
    tr = new_object("c_trim", trim, offset)
    tr.data.materials.append(M["trim"])

    # Dark: liner, a rubber edge, the ear loops, visor screws, chin strap and cup.
    lin = new_object("c_liner", lambda bm: shell_patch(
        bm, sh, lambda a: keyed(C_RIM, a) + 0.005, None, nu=48, nv=12, grow=-0.0036), offset)
    solidify(lin, 0.009, bevel=0.0)
    cut(lin, vents())

    def dark(bm):
        rim = []
        n = 96
        for i in range(n):
            a = 360.0 * i / n - 180.0
            p, nr = surf_pt(sh, a, keyed(C_RIM, a) + 0.0012)
            rim.append((p - nr * 0.0013, nr))
        rings = []
        for i, (p, nr) in enumerate(rim):
            t = (rim[(i + 1) % n][0] - rim[i - 1][0]).normalized()
            rings.append(ring_pts(p, nr, t.cross(nr).normalized(), 0.0026, 0.0028, 8))
        tube(bm, rings, closed=True)
        for s in (1.0, -1.0):
            # The ear loop: a flat band from the edge ahead of the ear, down under it and
            # back up behind (it lies on the shell's own line carried on down).
            loop = [side_pt(sh, q.x, q.y, s, 0.0005) for q in spline([Vector(c) for c in C_LOOP], 26)]
            rings = []
            for i, (p, nr) in enumerate(loop):
                t = (loop[min(i + 1, len(loop) - 1)][0] - loop[max(i - 1, 0)][0]).normalized()
                rings.append(ring_pts(p, nr, t.cross(nr).normalized(), 0.0024, 0.0055, 10, 3.5))
            tube(bm, rings)
            for y in C_SCREWS[1]:
                p, nr = surf_pt(sh, s * C_SCREWS[0], y)
                screw(bm, p, nr)
        f, _ = side_pt(sh, C_LOOP[2][0], C_LOOP[2][1])
        f -= Vector((0.004, 0, 0))
        b, _ = side_pt(sh, C_LOOP[4][0], C_LOOP[4][1])
        b -= Vector((0.004, 0, 0))
        chin_strap(bm, f, b, Vector((0.094, -0.072, -0.006)),
                   [Vector((0.074, -0.098, 0.024)), Vector((0.046, -0.114, 0.05)), Vector((0.018, -0.116, 0.062))])
        chin_cup(bm, Vector((0.0, -0.112, 0.064)), size=(0.036, 0.024, 0.0065))
    dk = join("c_dark", [new_object("c_dark", dark, offset), lin])
    dk.data.materials.append(M["dark"])

    # Visor: a short shield with rounded corners, screwed to the temples.
    vi = new_object("c_visor", lambda bm: visor_shield(
        bm, sh, 61.0, 0.066, C_VISOR_BOTTOM, gap=0.006, flare=0.04, nu=36, nv=6), offset)
    solidify(vi, 0.0025, bevel=0.0008)
    apply_all(vi)
    vi.data.materials.append(M["visor"])

    def hw(bm):
        for s in (1.0, -1.0):
            p, nr = surf_pt(sh, s * C_SCREWS[0], sum(C_SCREWS[1]) * 0.5)
            t = (Vector((0, 1, 0)) - nr * nr.y).normalized()
            rounded_box(bm, p + nr * 0.0058, nr.cross(t).normalized(), t, nr, 0.008, 0.015, 0.0026, segs=16, rings=5)
    vh = new_object("c_visor_hw", hw, offset)
    vh.data.materials.append(M["visor_hw"])
    return {"shell": shell, "trim": tr, "dark": dk, "visor": vi, "visor_hw": vh}


# --- Face gear: the cage and the full shield ---------------------------------------------------
#
# Both lie on one surface in front of the face: from under the helmet's brow, round to just
# ahead of the ears, down and in under the chin. In plan it is a superellipse, FACE_W wide
# and FACE_FRONT deep at each height (off the helmet's axis); its outline as seen from the
# front is (azimuth deg, y), the top following the helmet's own edge.

FACE_SIDE = [(60.0, 0.008), (68.0, -0.036), (70.0, -0.072), (62.0, -0.106), (42.0, -0.13), (18.0, -0.142), (0.0, -0.145)]
FACE_W = [(-0.16, 0.05), (-0.14, 0.07), (-0.10, 0.088), (-0.05, 0.1), (0.0, 0.106), (0.08, 0.108)]
FACE_FRONT = [(-0.158, 0.034), (-0.15, 0.082), (-0.138, 0.109), (-0.112, 0.132), (-0.075, 0.146), (-0.035, 0.152),
              (0.005, 0.152), (0.04, 0.146), (0.072, 0.134)]
FACE_P = 2.3
FACE_BARS_Y = (0.012, -0.026, -0.064, -0.1)       # the cage's level bars
FACE_BARS_A = (-46.0, -30.0, -15.0, 0.0, 15.0, 30.0, 46.0)   # ... and its upright ones
FACE_WIRE = 0.0019


def _table(tbl, x):
    """Straight-line reading of [(x, value)], level beyond its ends."""
    if x <= tbl[0][0]:
        return tbl[0][1]
    for (x0, v0), (x1, v1) in zip(tbl, tbl[1:]):
        if x <= x1:
            return _lerp(v0, v1, (x - x0) / (x1 - x0))
    return tbl[-1][1]


class Face:
    """The face gear's surface under one helmet (its Shape and edge keys)."""

    def __init__(self, sh, rim):
        self.sh, self.rim = sh, rim
        ctrl = [(a, keyed(rim, a) - 0.004) for a in (0.0, 15.0, 30.0, 44.0)] + FACE_SIDE
        self.half = [(q.x, q.y) for q in spline([Vector(c) for c in ctrl], 110)]   # the outline's +x half, top to bottom
        self.top_y = self.half[0][1]
        brow, _ = surf_pt(sh, 0.0, keyed(rim, 0.0))
        self.top_r = brow.z - sh.zc + 0.009

    def front(self, y):
        """How deep the surface is at height y: the table's, drawn in to just off the
        helmet's own brow at the top."""
        return _lerp(_table(FACE_FRONT, y), self.top_r, _smooth(0.0, self.top_y, y))

    def pt(self, a, y):
        s, c = math.sin(math.radians(a)), math.cos(math.radians(a))
        r = 1.0 / ((abs(s) / _table(FACE_W, y)) ** FACE_P + (abs(c) / self.front(y)) ** FACE_P) ** (1.0 / FACE_P)
        return Vector((s * r, y, self.sh.zc + c * r))

    def a_max(self, y):
        """How far round the outline reaches at height y (deg)."""
        best = 0.0
        for (a0, y0), (a1, y1) in zip(self.half, self.half[1:]):
            if (y0 - y) * (y1 - y) <= 0 and y0 != y1:
                best = max(best, _lerp(a0, a1, (y - y0) / (y1 - y0)))
        return best

    def y_range(self, a):
        """(top, bottom) of the outline at azimuth a."""
        a = abs(a)
        ys = []
        for (a0, y0), (a1, y1) in zip(self.half, self.half[1:]):
            if (a0 - a) * (a1 - a) <= 0 and a0 != a1:
                ys.append(_lerp(y0, y1, (a - a0) / (a1 - a0)))
        if not ys:
            return self.top_y, self.half[-1][1]
        return max(ys), min(ys)

    def loop(self):
        """The whole outline as surface points, from the top center round by +x."""
        pts = [self.pt(a, y) for a, y in self.half]
        return pts + [self.pt(-a, y) for a, y in reversed(self.half[1:-1])]


def wire(bm, pts, r, sides=5):
    """A round wire through pts (game Vectors)."""
    rings, prev = [], None
    n = len(pts)
    for i, q in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        u = t.orthogonal().normalized() if prev is None else (prev - t * prev.dot(t)).normalized()
        prev = u
        rings.append(ring_pts(q, u, t.cross(u), r, r, sides))
    tube(bm, rings)


def _out(fc, q):
    """Outward from the head at a point of the face surface (roughly its normal)."""
    d = q - Vector((0.0, q.y * 0.5 - 0.02, fc.sh.zc))
    return d.normalized()


def _face_hw(bm, fc, chin_strip):
    """The dark fittings both pieces share: a clip either side of the brow up onto the
    shell, a clip at each side, the chin cup; `chin_strip` adds a guard band along the
    bottom edge (the shield's)."""
    sh = fc.sh
    for s in (1.0, -1.0):
        a = 22.0 * s
        low = fc.pt(a, fc.y_range(a)[0] - 0.006)
        high, n = surf_pt(sh, a, keyed(fc.rim, a) + 0.008)
        along = high + n * 0.002 - low
        side = Vector((math.cos(math.radians(a)), 0.0, -math.sin(math.radians(a))))
        w = side.cross(along.normalized()).normalized()
        rounded_box(bm, low + along * 0.5 + w * 0.001, side, along.normalized(), w, 0.0065, along.length * 0.5 + 0.004, 0.0022,
                    segs=14, rings=5)
        a = 66.0 * s
        q = fc.pt(a, -0.034)
        o = _out(fc, q)
        t = Vector((0, 1, 0))
        rounded_box(bm, q - o * 0.002, o.cross(t).normalized(), t, o, 0.0075, 0.012, 0.0032, segs=14, rings=5)
    q = fc.pt(0.0, -0.126)
    o = _out(fc, q)
    u = Vector((1, 0, 0))
    rounded_box(bm, q - o * 0.011, u, o.cross(u).normalized(), o, 0.03, 0.019, 0.008, segs=16, rings=6, p=3.0)
    if chin_strip:
        lp = [q for q in fc.loop() if q.y < -0.088]
        lp.sort(key=lambda q: math.atan2(q.x, q.z - sh.zc))
        strap_along(bm, lp, [_out(fc, q) for q in lp], 0.013, 0.0034)


def build_face(key, sh, rim, offset=Vector()):
    """The cage and the full shield for one helmet: {cage, cage_hw, shield, shield_hw}."""
    fc = Face(sh, rim)
    M = mats()

    def cage(bm):
        for y in FACE_BARS_Y:
            a1 = fc.a_max(y)
            k = max(8, int(a1 / 4.0))
            wire(bm, [fc.pt(_lerp(-a1, a1, i / (2 * k)), y) for i in range(2 * k + 1)], FACE_WIRE)
        for a in FACE_BARS_A:
            y1, y0 = fc.y_range(a)
            k = max(6, int((y1 - y0) / 0.009))
            wire(bm, [fc.pt(a, _lerp(y1, y0, i / k)) for i in range(k + 1)], FACE_WIRE)
        lp = fc.loop()[::2]
        wire(bm, lp + [lp[0]], 0.0027, sides=6)
    cg = new_object("%s_cage" % key, cage, offset)
    cg.data.materials.append(material("FaceCage", (0.75, 0.77, 0.8), 0.25))
    ch = new_object("%s_cage_hw" % key, lambda bm: _face_hw(bm, fc, False), offset)
    ch.data.materials.append(M["dark"])

    def shield(bm):
        nu, nv = 36, 18
        cols = []
        for i in range(nu + 1):
            a = _lerp(-69.0, 69.0, i / nu)
            y1, y0 = fc.y_range(a)
            cols.append([fc.pt(a, _lerp(y1, y0, j / nv)) for j in range(nv + 1)])
        grid(bm, cols)
    sd = new_object("%s_shield" % key, shield, offset)
    solidify(sd, 0.0025, bevel=0.0008)
    apply_all(sd)
    # Breathing slots in front of the mouth.
    slots = []
    for a in (-13.0, 13.0):
        for y in (-0.078, -0.092, -0.106):
            q = fc.pt(a, y)
            slots.append(stadium_cutter("cut", q, Vector((math.cos(math.radians(a)), 0.0, -math.sin(math.radians(a)))),
                                        Vector((0, 1, 0)), 0.024, 0.0046, 0.02))
    cut(sd, slots)
    sd.data.materials.append(M["visor"])
    shw = new_object("%s_shield_hw" % key, lambda bm: _face_hw(bm, fc, True), offset)
    shw.data.materials.append(M["dark"])
    return {"cage": cg, "cage_hw": ch, "shield": sd, "shield_hw": shw}


FACE_HELMETS = {"a": (A_SHAPE, A_RIM), "b": (B_SHAPE, B_RIM), "c": (C_SHAPE, C_RIM)}


# --- The Chupacabras' spines and eyes ----------------------------------------------------------

# Per helmet: its shape; where the ridge starts on the brow and ends at the nape (y), and
# how far off the plain shell it stands (on A's raised spine, B's raised panel); and its
# visor as visor_shield was given it (top, gap, flare, the keys of its lower edge).
CHUPA_HELMETS = {
    "a": dict(sh=A_SHAPE, ridge=(0.1, 0.0, 0.0098), visor=(0.074, 0.007, 0.05, A_VISOR_BOTTOM)),
    "b": dict(sh=B_SHAPE, ridge=(0.092, -0.008, 0.0046), visor=(0.069, 0.006, 0.03, B_VISOR_BOTTOM)),
    "c": dict(sh=C_SHAPE, ridge=(0.088, -0.016, 0.0), visor=(0.066, 0.006, 0.04, C_VISOR_BOTTOM)),
}
CHUPA_SPINES = 9
CHUPA_FANG = (13.0, 0.045, 0.0082, 0.0064, 0.011)   # a fang: azimuth, length, root half width / half depth, how far its tip curls in


def _ridge(sh, y_front, y_back, grow, n):
    """n + 1 points along the shell's middle line from the brow over the top to the nape,
    evenly spaced, `grow` off the surface, with the outward normal at each."""
    f = sh.profile(0.0, y_front, 120, grow)
    b = sh.profile(180.0, y_back, 120, grow)
    pts = f + list(reversed(b))[1:]
    L = [0.0]
    for p0, p1 in zip(pts, pts[1:]):
        L.append(L[-1] + (p1 - p0).length)
    out = []
    for i in range(n + 1):
        d = L[-1] * i / n
        j = max(0, min(len(L) - 2, next((q for q in range(len(L) - 1) if L[q + 1] >= d), len(L) - 2)))
        t = 0.0 if L[j + 1] == L[j] else (d - L[j]) / (L[j + 1] - L[j])
        q = pts[j].lerp(pts[j + 1], t)
        tng = (pts[min(j + 2, len(pts) - 1)] - pts[max(j - 1, 0)]).normalized()
        out.append((q, Vector((1, 0, 0)).cross(tng).normalized(), tng))
    return out


def _visor_edge(spec, a):
    """The middle of a helmet's visor's lower edge at azimuth a (between its two skins),
    and the way out from the head there."""
    sh = spec["sh"]
    y_top, gap, flare, bottom = spec["visor"]
    top, _ = surf_pt(sh, a, y_top)
    y = keyed(bottom, a)
    r = Vector((top.x, 0.0, top.z - sh.zc)).length + gap + flare * (y_top - y) - 0.00125
    d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
    return Vector((d.x * r, y, sh.zc + d.z * r)), d


def build_chupa(key, offset=Vector()):
    """The pieces for one helmet: {spines, fangs}."""
    spec = CHUPA_HELMETS[key]
    sh = spec["sh"]

    def spines(bm):
        y_front, y_back, grow = spec["ridge"]
        line = _ridge(sh, y_front, y_back, grow, 200)
        for k in range(CHUPA_SPINES):
            t = 0.04 + 0.92 * k / (CHUPA_SPINES - 1)
            q, nrm, tng = line[int(round(t * 200))]
            # Small on the brow, tallest over the back of the crown, smaller again to the nape.
            tall = 0.02 + 0.044 * math.sin(math.pi * min(1.0, max(0.0, (t - 0.02) / 0.9)) ** 1.25) ** 1.1
            along, across = 0.015 + tall * 0.22, 0.0078 + tall * 0.07
            rings = []
            for i in range(7):
                u = i / 6.5
                c = q - nrm * 0.003 + nrm * (tall * u) + tng * (tall * 0.5 * u ** 1.7)      # swept back
                k_ = (1.0 - u) ** 0.85
                rings.append(ring_pts(c, tng, Vector((1, 0, 0)), along * k_, across * k_, 10, 2.2))
            tube(bm, rings)
    sp = new_object("ch%s_spines" % key, spines, offset)
    sp.data.materials.append(material("ChupaSpines", (0.9, 0.85, 0.72), 0.5))

    def fangs(bm):
        # Two long canines hung from the visor's lower edge, either side of the nose: fat
        # where they meet the visor, curving in toward the lip as they come to a point.
        a0, length, wide, deep, curl = CHUPA_FANG
        for s in (1.0, -1.0):
            root, out = _visor_edge(spec, s * a0)
            side = Vector((out.z, 0.0, -out.x))
            rings = []
            for i in range(9):
                t = i / 8.6
                c = root + Vector((0, 0.003, 0)) - Vector((0, 1, 0)) * (length * t) - out * (curl * t * t)
                k = (1.0 - t) ** 0.8 * (1.0 + 0.12 * math.sin(math.pi * min(1.0, t * 2.5)))     # a slight belly below the root
                rings.append(ring_pts(c, side, out, wide * k, deep * k, 10, 2.1))
            tube(bm, rings)
    fg = new_object("ch%s_fangs" % key, fangs, offset)
    fg.data.materials.append(material("ChupaFangs", (0.93, 0.9, 0.8), 0.35))
    return {"spines": sp, "fangs": fg}


CHUPA_ROLES = ["spines", "fangs"]


# --- The Grays' alien visor --------------------------------------------------------------------

ALIEN_A = (4.0, 78.0)              # a lens: from its inner corner beside the nose round to the temple (a visor stops near 64)
ALIEN_IN_Y = 0.0                   # the inner corner's height (the eye itself is at 0.03: the lens slants up from here)
ALIEN_SCREWS = {"a": A_SCREWS, "b": B_SCREWS, "c": C_SCREWS}


def _alien_top(y_top, a):
    """A lens's upper edge: up from the inner corner to the helmet's brow, along under it,
    then down a little to the point at the temple."""
    keys = [(ALIEN_A[0], ALIEN_IN_Y + 0.002), (8, 0.024), (14, y_top - 0.022), (22, y_top - 0.005), (30, y_top), (52, y_top),
            (ALIEN_A[1], y_top - 0.03)]
    return keyed(keys, a)


def _alien_bottom(y_top, a):
    """Its lower edge: down from the inner corner to the cheek, then up to the temple."""
    keys = [(ALIEN_A[0], ALIEN_IN_Y - 0.002), (8, -0.018), (15, -0.034), (25, -0.042), (37, -0.031), (49, -0.009),
            (60, 0.014), (71, y_top - 0.042), (ALIEN_A[1], y_top - 0.034)]
    return keyed(keys, a)


def _alien_bulge(a, y):
    """How far a lens swells out of a visor's plain curve: an eye's dome."""
    u = (abs(a) - 33.0) / 38.0
    v = (y - 0.012) / 0.066
    return 0.013 * max(0.0, 1.0 - u * u) * max(0.0, 1.0 - v * v)


def build_alien(key, offset=Vector()):
    """The alien visor for one helmet: {lens, hw}."""
    spec = CHUPA_HELMETS[key]
    sh = spec["sh"]
    y_top, gap, flare, _bottom = spec["visor"]

    def at(a, y, out=0.0):
        top, _ = surf_pt(sh, a, y_top)
        r = Vector((top.x, 0.0, top.z - sh.zc)).length + gap + flare * (y_top - y) + _alien_bulge(a, y) + out
        return Vector((math.sin(math.radians(a)) * r, y, sh.zc + math.cos(math.radians(a)) * r))

    def lens(bm):
        nu, nv = 40, 10
        for side in (1.0, -1.0):
            rows = []
            for i in range(nu + 1):
                a = _lerp(ALIEN_A[0], ALIEN_A[1], i / nu)
                y1, y0 = _alien_top(y_top, a), _alien_bottom(y_top, a)
                rows.append([at(side * a, _lerp(y1, y0, j / nv)) for j in range(nv + 1)])
            grid(bm, rows)
    ln = new_object("al%s_lens" % key, lens, offset)
    solidify(ln, 0.0025, bevel=0.0008)
    apply_all(ln)
    ln.data.materials.append(material("AlienLens", (0.02, 0.02, 0.03), 0.06))

    def hw(bm):
        # The bar over the nose between the two inner corners, and a clip at each temple,
        # as the visor's.
        bar = [at(_lerp(-ALIEN_A[0] - 1.5, ALIEN_A[0] + 1.5, i / 10), ALIEN_IN_Y + 0.006 * math.sin(math.pi * i / 10), -0.001) for i in range(11)]
        wire(bm, bar, 0.0026, sides=6)
        az, ys = ALIEN_SCREWS[key]
        for s_ in (1.0, -1.0):
            q, nr = surf_pt(sh, s_ * az, sum(ys) * 0.5)
            t = (Vector((0, 1, 0)) - nr * nr.y).normalized()
            rounded_box(bm, q + nr * 0.0058, nr.cross(t).normalized(), t, nr, 0.008, 0.016, 0.0026, segs=16, rings=5)
    h = new_object("al%s_hw" % key, hw, offset)
    h.data.materials.append(mats()["visor_hw"])
    return {"lens": ln, "hw": h}


ALIEN_ROLES = ["lens", "hw"]


def build_aliens(do_export=False):
    """The alien visor for all three helmets, each where its helmet stands in build_new's row."""
    for o in list(bpy.data.objects):
        if o.name.startswith(("ala_", "alb_", "alc_")):
            bpy.data.objects.remove(o, do_unlink=True)
    out = {}
    for i, key in enumerate("abc"):
        out[key] = build_alien(key, head_offset() + g((0.0, -0.5, 0.5)[i], 0.0, 0.0))
        if do_export:
            export(out[key], "alien_%s.glb" % key, ALIEN_ROLES)
    return out


def build_dress(do_export=False):
    """The Chupacabras' dressing for all three helmets, each where its helmet stands in
    build_new's row (A in the middle, B and C either side)."""
    for o in list(bpy.data.objects):
        if o.name.startswith(("cha_", "chb_", "chc_")):
            bpy.data.objects.remove(o, do_unlink=True)
    out = {}
    for i, key in enumerate("abc"):
        out[key] = build_chupa(key, head_offset() + g((0.0, -0.5, 0.5)[i], 0.0, 0.0))
        if do_export:
            export(out[key], "chupa_%s.glb" % key, CHUPA_ROLES)
    return out
FACE_ROLES = ["cage", "cage_hw", "shield", "shield_hw"]


def build_new(do_export=False):
    """Helmet C and the face gear for all three helmets, in a row beside where A stands
    (A and B themselves are not rebuilt)."""
    for o in list(bpy.data.objects):
        if o.name.startswith(("cut_", "c_", "fa_", "fb_", "fc_")) and o.name not in (HEAD_OBJ,):
            bpy.data.objects.remove(o, do_unlink=True)
    c = build_c(head_offset() + g(0.5, 0.0, 0.0))
    if do_export:
        export(c, "helmet_c.glb")
    faces = {}
    for i, key in enumerate("abc"):
        sh, rim = FACE_HELMETS[key]
        faces[key] = build_face("f" + key, sh, rim, head_offset() + g((0.0, -0.5, 0.5)[i], 0.0, 0.0))
        if do_export:
            export(faces[key], "face_%s.glb" % key, FACE_ROLES)
    return c, faces


# --- Export --------------------------------------------------------------------------------

ROLES = ["shell", "trim", "dark", "visor", "visor_hw"]


def export(parts, filename, roles=ROLES):
    """Exports one helmet (or one helmet's face gear: FACE_ROLES), its parts named by role
    (the glTF node names build_gear.gd reads), at the origin."""
    objs = [parts[r] for r in roles]
    keep = [(o, o.name, o.location.copy()) for o in objs]
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for r, o in zip(roles, objs):
        clash = bpy.data.objects.get(r)
        if clash is not None and clash not in objs:
            clash.name = r + "_tmp"
        o.name = r
        o.location = Vector()
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
                              export_yup=True, export_apply=True, export_normals=True,
                              export_texcoords=False, export_materials="NONE")
    for o, name, loc in keep:
        o.name = name
        o.location = loc
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print("exported %s: %d tris" % (path, tris))


def build_all(do_export=False):
    for o in list(bpy.data.objects):
        if o.name.startswith(("cut_", "a_", "b_")) and o.name not in (HEAD_OBJ,):
            bpy.data.objects.remove(o, do_unlink=True)
    a = build_a(head_offset())
    b = build_b(head_offset() + g(-0.5, 0.0, 0.0))
    if do_export:
        export(a, "helmet_a.glb")
        export(b, "helmet_b.glb")
    build_new(do_export)
    return a, b
