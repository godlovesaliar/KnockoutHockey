# Builds the two skater helmets in Blender and exports them to assets/equip/helmet_a.glb
# and helmet_b.glb; tools/build_gear.gd (only=helmet) turns them into
# assets/characters/helmet.res and helmet_b.res.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/helmet_gear.py").read()); build_all(True)
# The chin straps are laid on the male head: dump it first with
#   godot --headless --path . -s res://tools/dump_heads.gd -- out=<dir>
# and import <dir>/head_male.obj (forward -Z, up Y) so HEAD_OBJ exists; without it the
# straps follow their control paths unprojected.
#
#   A  modern two-piece shell: a crown piece riding over a lower band, long slot vents
#      along the top, side slots, a rear adjuster, a short "pro cut" visor.
#   B  classic one-piece: squarer and flatter-topped, a molded rib around it above the
#      brow, vertical forehead slots, vent grooves on the sides, a rubber edge, a short
#      straight-cut visor.
# Both: ear holes, ear guards, a Y chin strap (front and rear straps meeting at a buckle
# under the ear, then along the jaw to a chin cup) laid along the head's own surface.
#
# Frame (game coordinates, meters): the male body's head box center (its rest pose) at
# the origin, +Y up, +Z the face, +X the head's left. The game fits each body by mapping
# the crown to its crown and the chin strap to its chin (CROWN_Y / CHIN_Y below, saved as
# metas by build_gear.gd), scaling across by head width.
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

# The male head box center in skeleton space (game coords), where the models are built.
HEAD_CENTER = (0.0, 1.6953, 0.0003)
CROWN_Y = 0.145      # top of the male head above HEAD_CENTER
CHIN_Y = -0.095      # bottom of the male chin
HEAD_OBJ = "male_male_muscle_13290Mesh_s0"   # reference head (tools/_dump_heads.gd), if loaded


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
    """BVH of the reference head (game coords relative to HEAD_CENTER), or None."""
    global _bvh
    if _bvh is not None:
        return _bvh
    o = bpy.data.objects.get(HEAD_OBJ)
    if o is None:
        print("(reference head %s not loaded: straps follow their plain paths)" % HEAD_OBJ)
        return None
    c = Vector(HEAD_CENTER)
    verts = [gv(o.matrix_world @ v.co) - c for v in o.data.vertices]
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
A_EAR = (-0.006, 0.0, 0.034, 0.024)   # ear hole: center z, y, length (z), height (y)
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
    # two at the brow and two at the back.
    cutters = []
    up, fwd, left = Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))
    for s in (1.0, -1.0):
        cutters.append(stadium_cutter("cut", Vector((s * 0.042, 0.2, -0.006)), fwd, left, 0.15, 0.012, 0.11))
        cutters.append(stadium_cutter("cut", Vector((s * 0.074, 0.2, -0.045)), fwd, left, 0.07, 0.01, 0.11))
        # Side slot on the crown above the temple, along its edge.
        p, n = surf_pt(sh, s * 72.0, 0.098, 0.0045)
        cutters.append(stadium_cutter("cut", p, Vector((0, -0.25, 1)), up, 0.045, 0.009, 0.03))
        cutters.append(stadium_cutter("cut", Vector((s * 0.05, 0.112, 0.12)), left, up, 0.026, 0.008, 0.05))
        cutters.append(stadium_cutter("cut", Vector((s * 0.046, 0.09, -0.14)), left, up, 0.028, 0.008, 0.05))
    cut(crown, cutters)
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
B_EAR = (-0.004, -0.004, 0.034, 0.026)
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

    cutters = brim_vents()
    for s in (1.0, -1.0):
        # Top: a slot either side of the raised panel.
        cutters.append(stadium_cutter("cut", Vector((s * 0.07, 0.2, -0.03)), fwd, left, 0.065, 0.0095, 0.1))
        # Back: an upright slot either side of the panel.
        p, n, u, sd = _surface_frame(sh, 180.0 - s * 24.0, 0.086)
        cutters.append(stadium_cutter("cut", p, u, sd, 0.028, 0.008, 0.02))
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


# --- Export --------------------------------------------------------------------------------

ROLES = ["shell", "trim", "dark", "visor", "visor_hw"]


def export(parts, filename):
    """Exports one helmet, its parts named by role (the glTF node names build_gear.gd
    reads), at the origin."""
    objs = [parts[r] for r in ROLES]
    keep = [(o, o.name, o.location.copy()) for o in objs]
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for r, o in zip(ROLES, objs):
        clash = bpy.data.objects.get(r)
        if clash is not None and clash not in objs:
            clash.name = r + "_tmp"
        o.name = r
        o.location = Vector()
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
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
    return a, b
