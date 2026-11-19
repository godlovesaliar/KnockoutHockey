# Builds the goalie masks in Blender and exports them to assets/equip/goalie_mask_<key>.glb;
# tools/build_gear.gd (only=mask) turns those into assets/characters/goalie_mask*.res.
#
# Run in Blender (with the reference heads loaded, see tools/blender/mask_gear.py):
#   exec(open(r"<project>/tools/blender/goalie_mask_gear.py").read()); build_all(True)
# build_all stands the four side by side, each on a copy of the head; only="c" builds one.
#
#   a  modern: a shell standing off the head, flared to wings at the back, a wraparound
#      cage, a backplate on the back of the head and six straps
#   b  helmet-and-cage combo: the classic skater helmet with a full wire cage hung from
#      its brow down around the chin
#   c  '80s: a rounder, closer shell with ear holes and a short chin, a big straight-bar
#      cage, a large backplate on wide straps
#   d  molded: a one-piece 1970s fiberglass mask over the whole face and up over the
#      forehead, with eye holes, a brow and nose ridge, round vents and a strap harness
#
# A mask is a thin, hollow shell, as the real ones are, not a solid shape with holes in it:
# a side silhouette (chin, face, forehead, crown) swept out to side panels, open behind and
# underneath, cut along a rear edge and a jaw line, with its inside a separate dark liner.
# Backplates and pads are their own pieces on the back of the head, held by straps that
# wrap around the shell's rear edge to snaps. Cages are wire baskets bowed out from the
# shell. Proportions (heights, widths, where the edges run) of the modern mask were
# measured off the two outside masks the game used to have; the surfaces and every detail
# are built here.
#
# glTF nodes (NODES): shell (team color), liner (the shell's inside; the combo's dark parts),
# cage, trim (backplate and straps; the combo's white helmet trim). The modern mask's file
# also has scalp, the hair-colored cap over the scalp, its own mesh in game (scalp_cap.res,
# worn under every mask and the skaters' helmets).
# Frame as the helmets and team masks (mask_gear.py): the male body's head box center at the
# origin, +Y up, +Z the face.

import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

_HERE = os.path.dirname(os.path.abspath(globals().get(
    "__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\goalie_mask_gear.py")))
_saved_file = globals().get("__file__")
globals()["__file__"] = os.path.join(_HERE, "mask_gear.py")
exec(open(os.path.join(_HERE, "mask_gear.py")).read())   # head(), g(), gv(), solidify(), ...
if _saved_file is not None:
    globals()["__file__"] = _saved_file

C0 = Vector((0.0, 0.02, -0.005))   # the shell's surface is r(direction) from here
ZC = -0.005                        # the cage's cylinder axis (x = 0, z = ZC)
AZ = 0.0022                        # meters per degree of azimuth out at the cage
# The shell and cage are shaped at the outside masks' size, then brought down onto the head
# (FIT: scale per axis, then a shift forward; set by eye in Blender). Sizes below are before
# that, so they come out about three quarters as big.
FIT_S = Vector((0.7194, 0.8288, 0.7607))
FIT_Z = 0.0333
WIRE = 0.0025                      # cage wire radius
SHELL_T = 0.0058
SPHERE_N = 26                      # quads along a cube edge of the shell's sphere grid

SHELL_COL = (0.85, 0.12, 0.1)
LINER_COL = (0.06, 0.06, 0.065)
CAGE_COL = (0.08, 0.08, 0.09)
TRIM_COL = (0.15, 0.15, 0.16)


def gp(p):
    return g(p[0], p[1], p[2])


def lerp(a, b, t):
    return a + (b - a) * t


def cast(bvh, origin, d):
    loc, _, _, _ = bvh.ray_cast(origin, d)
    return loc


def cast_n(bvh, origin, d):
    """(hit, normal facing the ray's origin) or (None, None)."""
    loc, nrm, _, _ = bvh.ray_cast(origin, d)
    if loc is None:
        return None, None
    return loc, (-nrm if nrm.dot(d) > 0 else nrm)


# --- Curves and outlines -----------------------------------------------------------------------

def spline_nd(ctrl, n_per=10, closed=True):
    """Catmull-Rom through control points of any dimension -> array."""
    c = np.array(ctrl, float)
    m = len(c)
    out = []
    for i in (range(m) if closed else range(m - 1)):
        p0 = c[(i - 1) % m] if closed or i > 0 else c[0]
        p1 = c[i]
        p2 = c[(i + 1) % m]
        p3 = c[(i + 2) % m] if closed or i + 2 < m else c[-1]
        for k in range(n_per):
            t = k / n_per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(c[-1])
    return np.array(out)


def spline2(ctrl, n_per=10, closed=True):
    return [(float(p[0]), float(p[1])) for p in spline_nd(ctrl, n_per, closed)]


def mirrored(half):
    """A symmetric outline from its +x half, listed top center to bottom center."""
    return half + [(-x, y) for x, y in reversed(half) if x > 1e-6]


def sd2(p, poly):
    """Signed distance to a closed 2D polygon, > 0 inside."""
    x, y = p
    inside = False
    best = 1e9
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay + 1e-12) + ax:
            inside = not inside
        ex, ey = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey + 1e-12)))
        best = min(best, math.hypot(x - (ax + ex * t), y - (ay + ey * t)))
    return best if inside else -best


def grow(outline, by):
    """A closed outline pushed outward by `by` (inward if negative)."""
    n = len(outline)
    area = sum(outline[i][0] * outline[(i + 1) % n][1] - outline[(i + 1) % n][0] * outline[i][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        (x0, y0), (x1, y1) = outline[i - 1], outline[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1.0
        out.append((outline[i][0] + sgn * dy / ln * by, outline[i][1] - sgn * dx / ln * by))
    return out


def runs(path, keep, step=0.006):
    """Resamples a 2D polyline every `step` and splits it into the runs where keep(p)."""
    pts = []
    for i in range(len(path) - 1):
        a, b = Vector(path[i]), Vector(path[i + 1])
        n = max(1, int((b - a).length / step))
        for k in range(n):
            pts.append(a.lerp(b, k / n))
    pts.append(Vector(path[-1]))
    out, cur = [], []
    for p in pts:
        if keep((p.x, p.y)):
            cur.append((p.x, p.y))
        elif cur:
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return [r for r in out if len(r) > 1]


# --- Mesh pieces -------------------------------------------------------------------------------

def tube(bm, pts, rad, sides=5):
    n = len(pts)
    if n < 2:
        return
    rings = []
    a_prev = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        a = t.orthogonal().normalized() if a_prev is None else (a_prev - t * a_prev.dot(t)).normalized()
        b = t.cross(a)
        a_prev = a
        rings.append([bm.verts.new(gp(p + (a * math.cos(k * math.tau / sides) + b * math.sin(k * math.tau / sides)) * rad))
                      for k in range(sides)])
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def cyl(bm, center, axis, rx, ry, depth=0.05, n=16, roll_hint=Vector((0, 1, 0))):
    """Adds an elliptic cylinder along `axis` through `center` (game coords), `depth` each way."""
    axis = axis.normalized()
    u = roll_hint - axis * roll_hint.dot(axis)
    if u.length < 1e-4:
        u = axis.orthogonal()
    u.normalize()
    v = axis.cross(u)
    lo, hi = [], []
    for k in range(n):
        t = math.tau * k / n
        o = v * (rx * math.cos(t)) + u * (ry * math.sin(t))
        lo.append(bm.verts.new(gp(center + o - axis * depth)))
        hi.append(bm.verts.new(gp(center + o + axis * depth)))
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)


def bool_op(obj, cutters, op="DIFFERENCE"):
    """Cuts a surface with the cutter objects (then deletes them). The solver walls the cuts
    off with the cutters' own faces, as if the surface were a solid; those are dropped
    again (anything not lying on the surface as it was), leaving clean open edges."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    before = BVHTree.FromBMesh(bm)
    bm.free()
    for c in cutters:
        c.location = obj.location
        m = obj.modifiers.new("b", "BOOLEAN")
        m.operation = op
        m.solver = "EXACT"
        m.object = c
        m.use_hole_tolerant = True   # open surfaces: trimmed, not capped
        c.hide_set(True)
    apply_all(obj)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    walls = [f for f in bm.faces if before.find_nearest(f.calc_center_median())[3] > 3e-4]
    bmesh.ops.delete(bm, geom=walls, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()


def side_cutter(name, outline_zy, w=0.4):
    return prism_cutter(name, outline_zy, "x", -w, w)


def az_cutter(name, outline, r0=0.03, r1=0.4):
    """A wedge through a closed (azimuth deg, y) outline, from r0 to r1 off the cage axis."""
    def pt(a, y, r):
        a = math.radians(a)
        return g(math.sin(a) * r, y, ZC + math.cos(a) * r)
    bm = bmesh.new()
    lo = [bm.verts.new(pt(a, y, r0)) for a, y in outline]
    hi = [bm.verts.new(pt(a, y, r1)) for a, y in outline]
    n = len(outline)
    ym = sum(y for _, y in outline) / n
    clo, chi = bm.verts.new(pt(0.0, ym, r0)), bm.verts.new(pt(0.0, ym, r1))
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
        bm.faces.new((lo[k2], lo[k], clo))
        bm.faces.new((hi[k], hi[k2], chi))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return to_object(name, bm)


def hole_cutter(name, bvh, specs):
    """Vent holes: (ray origin, ray direction, rx, ry), cut along the surface normal."""
    bm = bmesh.new()
    for origin, d, rx, ry in specs:
        p, n = cast_n(bvh, Vector(origin), Vector(d).normalized())
        if p is not None:
            cyl(bm, p, n, rx, ry, depth=0.03, n=10)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return to_object(name, bm)


def sharpen(o, angle=40.0):
    """Smooth shading with the hard edges (rims, holes) kept sharp."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(angle))
    bm.to_mesh(o.data)
    bm.free()


def finish(o, thick, offset=-1.0, liner=False):
    """Gives a surface its thickness (the far side on material slot 1 if `liner`)."""
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thick
    m.offset = offset
    m.use_rim = True
    m.use_even_offset = False   # (even offset spikes at slivers along the cuts)
    if liner:
        m.material_offset = 1
    apply_all(o)
    sharpen(o)


def split_material(o, index, name):
    """Moves the faces on material slot `index` into a new object."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    out = bmesh.new()
    vmap = {}
    faces = [f for f in bm.faces if f.material_index == index]
    for f in faces:
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = out.verts.new(v.co)
            vs.append(vmap[v.index])
        out.faces.new(vs)
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    part = to_object(name, out)
    part.location = o.location
    for ob in (o, part):
        for p in ob.data.polygons:
            p.material_index = 0
        sharpen(ob)
    return part


def paint(o, name, col, rough=0.4):
    o.data.materials.clear()
    o.data.materials.append(material(name, col, rough))


def join(objs, name):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    res = bpy.context.view_layer.objects.active
    old = bpy.data.objects.get(name)
    if old is not None and old != res:
        bpy.data.objects.remove(old, do_unlink=True)
    res.name = name
    return res


# --- The shell's surface -----------------------------------------------------------------------
# A height field over the side view: x = half width (z, y) * a rounding that goes from 0 at
# the silhouette to 1 at depth R inside it. The silhouette runs on past the rear edge and
# the jaw line (the shell is cut there afterwards), so the panels arrive at those edges at
# full width: a hood, not an egg. A mask's spec:
#   sil    the side silhouette, closed: (z, y, R = how far in the surface takes to round out
#          to the side panel). From below the chin, up the face, over the crown, then the
#          made-up back and bottom that get cut away.
#   width  half width by height at the ear (before the flare)
#   flare  how fast the side panels spread toward the back
#   round  the rounding's exponent by height (2 = round, lower = a pointed arch)
#   rim    what is kept in the side view (z, y): down the rear edge, then the jaw line
#          forward and down under the chin, closed around the front
#   fit    (scale per axis, shift forward) from the size it is shaped at down onto the head,
#          or None if it is shaped at its final size

GZ0, GZ1, GY0, GY1, GSTEP = -0.27, 0.21, -0.34, 0.25, 0.0025


def blur(a, radius=2, passes=3):
    for _ in range(passes):
        for axis in (0, 1):
            pad = [(radius, radius) if k == axis else (0, 0) for k in (0, 1)]
            b = np.pad(a, pad, mode="edge")
            acc = np.zeros_like(a)
            for s in range(2 * radius + 1):
                acc += b[s:s + a.shape[0], :] if axis == 0 else b[:, s:s + a.shape[1]]
            a = acc / (2 * radius + 1)
    return a


def smooth_np(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def shell_field(spec):
    """X(z, y) on a grid: the shell's half width over the side view (0 outside it)."""
    sil = spline_nd(spec["sil"], 24, closed=True)
    zs = GZ0 + GSTEP * np.arange(int((GZ1 - GZ0) / GSTEP) + 1)
    ys = GY0 + GSTEP * np.arange(int((GY1 - GY0) / GSTEP) + 1)
    Z, Y = np.meshgrid(zs, ys, indexing="ij")
    inside = np.zeros(Z.shape, bool)
    n = len(sil)
    for i in range(n):
        az, ay = sil[i][0], sil[i][1]
        bz, by = sil[(i + 1) % n][0], sil[(i + 1) % n][1]
        if ay != by:
            inside ^= ((ay > Y) != (by > Y)) & (Z < (bz - az) * (Y - ay) / (by - ay) + az)
    s = np.full(Z.shape, 1e9)
    for z, y, r in sil:
        s = np.minimum(s, np.hypot(Z - z, Y - y) / r)
    s = np.where(inside, np.minimum(s, 1.5), 0.0)
    s = np.minimum(s, blur(s))   # the blur only to soften the creases deep inside
    w = np.interp(Y, [p[0] for p in spec["width"]], [p[1] for p in spec["width"]])
    back = np.maximum(0.0, -Z)
    w = w + spec["flare"] * smooth_np(0.16, 0.06, Y) * back * back / (back + 0.03)
    w = blur(w)
    nexp = blur(np.interp(Y, [p[0] for p in spec["round"]], [p[1] for p in spec["round"]]))
    s1 = np.clip(s, 0.0, 1.0)
    return w * (1.0 - (1.0 - s1) ** nexp) ** (1.0 / nexp)


def sample(F, z, y):
    fz = np.clip((z - GZ0) / GSTEP, 0.0, F.shape[0] - 1.001)
    fy = np.clip((y - GY0) / GSTEP, 0.0, F.shape[1] - 1.001)
    i, j = fz.astype(int), fy.astype(int)
    a, b = fz - i, fy - j
    return (F[i, j] * (1 - a) * (1 - b) + F[i + 1, j] * a * (1 - b)
            + F[i, j + 1] * (1 - a) * b + F[i + 1, j + 1] * a * b)


def quad_sphere(n):
    """Directions on a sphere without poles (a cube's faces, evened out) and their quads."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=n - 1, use_grid_fill=True)
    bm.verts.ensure_lookup_table()
    dirs = [Vector([math.tan(q * math.pi / 4) for q in v.co]).normalized() for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return np.array([tuple(d) for d in dirs]), faces


class Shell:
    """A spec's whole surface (before it is cut): r(direction) from C0 on a sphere grid."""

    def __init__(self, spec, n=SPHERE_N):
        self.spec = spec
        self.rim = spec.get("rim")
        self.to_head = spec.get("fit")
        self.field = shell_field(spec)
        self.dirs, self.faces = quad_sphere(n)
        c = np.array(tuple(C0))
        lo = np.full(len(self.dirs), 0.02)
        hi = np.full(len(self.dirs), 0.5)
        for _ in range(26):
            mid = (lo + hi) * 0.5
            p = c + self.dirs * mid[:, None]
            ins = np.abs(p[:, 0]) < sample(self.field, p[:, 2], p[:, 1])
            lo = np.where(ins, mid, lo)
            hi = np.where(ins, hi, mid)
        self.r = (lo + hi) * 0.5

    def points(self, extra=None):
        r = self.r if extra is None else self.r + extra
        return np.array(tuple(C0)) + self.dirs * r[:, None]

    def bvh(self, extra=None):
        return BVHTree.FromPolygons([Vector(p) for p in self.points(extra)], self.faces)

    def fit(self, p):
        """A point of the surface as shaped -> where it ends up on the head."""
        if self.to_head is None:
            return Vector(p)
        s, dz = self.to_head
        return Vector((p[0] * s.x, p[1] * s.y, p[2] * s.z + dz))

    def fit_object(self, o):
        if self.to_head is not None:
            for v in o.data.vertices:
                v.co = gp(self.fit(gv(v.co)))
            o.data.update()

    def bvh_fit(self):
        """The surface at its final size on the head."""
        return BVHTree.FromPolygons([self.fit(p) for p in self.points()], self.faces)

    def rim_z(self, y):
        """The rear edge's z at height y (both as fitted on the head), or None."""
        s, dz = self.to_head if self.to_head is not None else (Vector((1, 1, 1)), 0.0)
        y = y / s.y
        best = None
        for (z0, y0), (z1, y1) in zip(self.rim, self.rim[1:]):
            if max(z0, z1) < 0.25 and (y0 - y) * (y1 - y) <= 0 and y0 != y1:
                z = z0 + (z1 - z0) * (y - y0) / (y1 - y0)
                best = z if best is None else min(best, z)
        return None if best is None else best * s.z + dz

    def obj(self, name, extra=None, margin=0.012):
        """The surface as an object: only the part inside the rim and a margin around it,
        an open patch, which the cuts then trim as a surface instead of capping as a
        solid."""
        pts = self.points(extra)
        near = [self.rim is None or sd2((p[2], p[1]), self.rim) > -margin for p in pts]
        bm = bmesh.new()
        vs = [bm.verts.new(gp(p)) for p in pts]
        for f in self.faces:
            if any(near[i] for i in f):
                bm.faces.new([vs[i] for i in f])
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        o = to_object(name, bm)
        for p in o.data.polygons:
            p.use_smooth = True
        return o


# --- Pieces every mask is built from -------------------------------------------------------------

def az_of(p):
    return math.degrees(math.atan2(p[0], p[2] - ZC))


def deg(path):
    return [(a * AZ, y) for a, y in path]


def opening_lip(sh, open_m, side=0.003, brow=0.007):
    """A raised lip around the cage opening, heavier across the brow."""
    extra = np.zeros(len(sh.r))
    for i, p in enumerate(sh.points()):
        if p[2] < -0.02 or p[1] < -0.1 or p[1] > 0.14:
            continue
        d = sd2((az_of(p) * AZ, p[1]), open_m)
        b = smooth(0.05, 0.085, p[1])
        extra[i] = lerp(side, brow, b) * smooth(-lerp(0.014, 0.024, b), -0.003, d)
    return extra


def cage_surface(sh, open_m, bow):
    """The cage's surface: the shell's, lifted off it over the opening."""
    extra = np.zeros(len(sh.r))
    for i, p in enumerate(sh.points()):
        if p[2] < 0.0 or p[1] < -0.1 or p[1] > 0.14:
            continue
        d = sd2((az_of(p) * AZ, p[1]), open_m)
        extra[i] = 0.004 + bow * smooth(-0.004, 0.04, d)
    return sh.bvh(extra)


def az_project(bvh, q):
    """q = (azimuth in meters at the cage, y): onto the cage's surface from outside."""
    a = math.radians(q[0] / AZ)
    d = Vector((math.sin(a), 0.0, math.cos(a)))
    return cast(bvh, Vector((0.0, q[1], ZC)) + d * 0.45, -d)


def cage_wires(name, bvh, paths, keep, wire=WIRE):
    bm = bmesh.new()
    for path, r in paths:
        for run in runs(path, keep):
            pts = [az_project(bvh, q) for q in run]
            tube(bm, [p for p in pts if p is not None], r or wire)
    o = to_object(name, bm)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


UV_SPAN = math.radians(135.0)   # the paint layout reaches this far around from straight ahead


def paint_uv(o, center):
    """The paint layout (tools/blender/goalie_mask_paint.py): a fisheye view of the mask
    from the front. A point's direction from `center` (the middle of the shell's own
    surface, so no two points share one) lands at the middle of the image if it is
    straight ahead, and further out the further around it is: up is up, the head's left
    (+x) to the right."""
    me = o.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        d = (gv(me.vertices[loop.vertex_index].co) - center).normalized()
        k = math.acos(max(-1.0, min(1.0, d.z))) / UV_SPAN / max(1e-9, math.hypot(d.x, d.y))
        uv.data[loop.index].uv = (0.5 + 0.5 * k * d.x, 0.5 + 0.5 * k * d.y)


def cut_shell(sh, name, cutters, extra=None, thick=SHELL_T):
    """The spec's surface cut to its rim and by the cutters (built by `cutters(surface
    bvh)`), given its thickness and brought down onto the head: (shell, liner)."""
    shell = sh.obj(name + "_shell", extra=extra)
    bool_op(shell, [side_cutter("cut_rim", sh.rim)], "INTERSECT")
    bool_op(shell, cutters(sh.bvh()))
    paint(shell, "GMShell", SHELL_COL, 0.3)
    shell.data.materials.append(material("GMLiner", LINER_COL, 0.8))
    finish(shell, thick, liner=True)
    liner = split_material(shell, 1, name + "_liner")
    paint(liner, "GMLiner", LINER_COL, 0.8)
    for o in (shell, liner):
        sh.fit_object(o)
    paint_uv(shell, sh.fit(C0))
    return shell, liner


def head_patch(name, clear, iters, e_top=75.0, ne=27, na=27):
    """A surface over the back of the head and on over the top (to `e_top` degrees: 90 is
    straight up, past it comes down the forehead): the head's own shape there, smoothed
    (more with `iters`), `clear` off it."""
    bvh = head()["bvh"]
    c = Vector((0.0, 0.03, -0.01))

    def ray(i, j):
        a, e = math.radians(lerp(-80, 80, i / (na - 1))), math.radians(lerp(-62, e_top, j / (ne - 1)))
        return Vector((math.sin(a), math.cos(a) * math.sin(e), -math.cos(a) * math.cos(e)))

    rad = np.zeros((na, ne))
    for i in range(na):
        for j in range(ne):
            d = ray(i, j)
            loc = cast(bvh, c + d * 0.5, -d)
            # (not the neck and shoulders below the plate)
            rad[i, j] = (loc - c).length if loc is not None and loc.y > -0.115 else 0.085
    hull = rad.copy()
    for _ in range(iters):
        hull = np.maximum(rad, blur(hull, 1, 1))
    bm = bmesh.new()
    vs = {}
    for i in range(na):
        for j in range(ne):
            d = ray(i, j)
            vs[i, j] = bm.verts.new(gp(c + d * (hull[i, j] + clear)))
    for i in range(na - 1):
        for j in range(ne - 1):
            bm.faces.new((vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.faces.ensure_lookup_table()
    mid = bm.faces[len(bm.faces) // 2]
    if mid.normal.dot(mid.calc_center_median() - Vector(gp(c))) < 0:   # outward
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return to_object(name, bm)


def scalp(name, sh):
    """The hair-colored cap under head gear (the skaters' helmets too): skin-tight over
    the top and back of the head. The mask leaves the back of the head bare, mask and
    helmets have open vents, and the game's pressed-down hairstyles are thin there."""
    o = head_patch(name, 0.002, 3, e_top=150.0, ne=30, na=21)
    # In the side view: from just under the modern shell's rear edge back (a little under
    # it by the ear, not over the ear; further above it, where the flared shell shows the
    # head under it from behind), and the whole top of the head forward to the hairline,
    # for the vents.
    ys = [-0.07 + 0.01 * k for k in range(14)]
    keep = [(-0.3, ys[0])] + [((sh.rim_z(y) or -0.066) + lerp(0.014, 0.03, smooth(0.03, 0.055, y)), y) for y in ys]
    keep += [(-0.01, 0.082), (0.03, 0.098), (0.07, 0.11), (0.096, 0.116), (0.096, 0.3), (-0.3, 0.3)]
    bool_op(o, [side_cutter("cut_scalp", keep)], "INTERSECT")
    # One-sided in game: every face outward.
    bm = bmesh.new()
    bm.from_mesh(o.data)
    c = Vector(gp((0.0, 0.03, -0.01)))
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.dot(f.calc_center_median() - c) < 0])
    bm.to_mesh(o.data)
    bm.free()
    sharpen(o)
    return o


def backplate(name, outline, slots):
    """A plate fitted to the back of the head, 1 cm off it, cut to its outline from behind
    ((x, y)) with slots (x, y, rx, ry)."""
    o = head_patch(name, 0.01, 12)
    bool_op(o, [prism_cutter("cut_plate", outline, "z", -0.4, -0.02)], "INTERSECT")
    if slots:
        surf = BVHTree.FromObject(o, bpy.context.evaluated_depsgraph_get())
        bm = bmesh.new()
        for x, y, rx, ry in slots:
            p, n, _, _ = surf.ray_cast(g(x, y, -0.5), g(0, 0, 1))
            if p is not None:
                cyl(bm, gv(p), gv(n), rx, ry, depth=0.03, n=10)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bool_op(o, [to_object("cut_plate_slots", bm)])
    plate_bvh = BVHTree.FromObject(o, bpy.context.evaluated_depsgraph_get())
    finish(o, 0.004, offset=1.0)
    return o, plate_bvh


def off_head(p, clear=0.006):
    """p, pushed out if it is in the head or closer than `clear` over it."""
    c = Vector((0.0, 0.03, -0.01))
    d = p - c
    dist = d.length
    d.normalize()
    hit = cast(head()["bvh"], c + d * 0.5, -d)
    if hit is not None and hit.y > -0.115 and dist < (hit - c).length + clear:
        return c + d * ((hit - c).length + clear)
    return p


def band(bm, ctrl, side, width=0.018, thick=0.002):
    """A flat strap through the control points, its width along `side`, kept off the head."""
    dense = []
    for p, q in zip(ctrl, ctrl[1:]):
        dense += [p.lerp(q, k / 3) for k in range(3)]
    dense.append(ctrl[-1])
    pts = [off_head(Vector(a)) for a in spline_nd([tuple(p) for p in dense], 3, closed=False)]
    rings = []
    for k, p in enumerate(pts):
        t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        w = (side - t * side.dot(t)).normalized() * (width * 0.5)
        n = t.cross(w).normalized() * (thick * 0.5)
        rings.append([bm.verts.new(gp(q)) for q in (p + w + n, p + w - n, p - w - n, p - w + n)])
    for r0, r1 in zip(rings, rings[1:]):
        for q in range(4):
            q2 = (q + 1) % 4
            bm.faces.new((r0[q], r0[q2], r1[q2], r1[q]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def straps(name, sh, plate_bvh, sides, tops, width=0.018):
    """The harness, pulled tight from the backplate to the shell's rear edge, around it and
    on to a snap. sides: (height on the plate, how far out on it, height on the shell),
    one each side; tops: (x on the shell, x on the plate, the plate heights it runs up)."""
    bm = bmesh.new()
    shell_bvh = sh.bvh_fit()

    def on_plate(x, y):
        p, n, _, _ = plate_bvh.ray_cast(g(x, y, -0.5), g(0, 0, 1))
        p, n = gv(p), gv(n)
        return p + (n if n.z < 0 else -n) * 0.0055

    def on_shell(origin, d):
        p, n = cast_n(shell_bvh, Vector(origin), Vector(d))
        return p + n * 0.002, n

    for s in (1, -1):
        for yp, xp, ys in sides:
            ze = sh.rim_z(ys)
            edge, _ = on_shell((s * 0.5, ys, ze + 0.003), (-s, 0, 0))
            snap, sn = on_shell((s * 0.5, ys, ze + 0.034), (-s, 0, 0))
            turn = Vector((edge.x + s * 0.002, ys, ze - 0.004))
            band(bm, [on_plate(s * xp * 0.45, yp), on_plate(s * xp, lerp(yp, ys, 0.2)), turn, edge, snap],
                 Vector((0, 1, 0)), width)
            cyl(bm, snap + sn * 0.0015, sn, 0.005, 0.005, depth=0.0015, n=12)
    for x, xp, y0, y1 in tops:
        ze = sh.rim_z(0.2)
        edge, _ = on_shell((x, 0.5, ze + 0.003), (0, -1, 0))
        snap, sn = on_shell((x, 0.5, ze + 0.034), (0, -1, 0))
        turn = Vector((x, edge.y + 0.002, ze - 0.004))
        band(bm, [on_plate(xp * 0.85, y0), on_plate(xp, y1), turn, edge, snap], Vector((1, 0, 0)), width)
        cyl(bm, snap + sn * 0.0015, sn, 0.005, 0.005, depth=0.0015, n=12)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return to_object(name, bm)


def round_vents(face=(), side=(), top=(), r=0.008):
    """Hole specs for hole_cutter: `face` (x, y) seen from the front, `side` (z, y) from the
    side, `top` (x, z) from above; all mirrored. A third value is the hole's radius."""
    out = []
    for s in (1, -1):
        for q in face:
            if s == 1 or q[0] != 0:
                rr = q[2] if len(q) > 2 else r
                out.append(((s * q[0], q[1], 0.5), (0, 0, -1), rr, rr))
        for q in side:
            rr = q[2] if len(q) > 2 else r
            out.append(((s * 0.5, q[1], q[0]), (-s, 0, 0), rr, rr))
        for q in top:
            if s == 1 or q[0] != 0:
                rr = q[2] if len(q) > 2 else r
                out.append(((s * q[0], 0.5, q[1]), (0, -1, 0), rr, rr))
    return out


def cage_on(name, sh, opening, bow, bars, clip_y=None):
    """A cage over an (azimuth deg, y) opening: a heavy rim lying on the shell around it,
    the bars (paths in degrees, with a wire radius or 0), clips top, bottom and sides."""
    open_m = deg(opening)
    rim = grow(open_m, 0.007)
    top = max(q[1] for q in rim)
    low = min(q[1] for q in rim)
    paths = [(deg(p), r) for p, r in bars] + [(rim + [rim[0]], WIRE * 1.45),
                                              (deg([(-5, top), (5, top)]), 0.0042),
                                              (deg([(-5, low), (5, low)]), 0.0042)]
    cy = clip_y if clip_y is not None else (top + low) * 0.5 + 0.006
    for s in (1, -1):
        side = [q for q in rim if q[0] * s > 0 and abs(q[1] - cy) < 0.009]
        paths.append((sorted(side, key=lambda q: q[1]), 0.0042))
    cage = cage_wires(name, cage_surface(sh, open_m, bow), paths, lambda q: sd2(q, rim) > -0.002)
    sh.fit_object(cage)
    paint(cage, "GMCage", CAGE_COL, 0.35)
    return cage


# --- A: the modern mask ---------------------------------------------------------------------------
# A thin shell standing off the head, flared to wings at the back, with a wraparound cage,
# a backplate on the back of the head and six straps.

A_TAIL = [(-0.21, 0.15, 0.09), (-0.225, 0.10, 0.07), (-0.23, 0.03, 0.06), (-0.23, -0.06, 0.06),
          (-0.23, -0.15, 0.06), (-0.23, -0.24, 0.06), (-0.22, -0.30, 0.06), (-0.12, -0.31, 0.06),
          (0.0, -0.31, 0.06), (0.10, -0.31, 0.06)]   # the made-up back and bottom
A_SPEC = {
    "sil": [(0.176, -0.30, 0.08), (0.170, -0.23, 0.08), (0.158, -0.165, 0.085), (0.146, -0.13, 0.105),
            (0.139, -0.10, 0.13), (0.135, -0.07, 0.14), (0.135, -0.03, 0.15), (0.137, 0.01, 0.15),
            (0.135, 0.05, 0.15), (0.126, 0.09, 0.15), (0.115, 0.115, 0.145), (0.106, 0.14, 0.14),
            (0.094, 0.168, 0.135), (0.074, 0.19, 0.13), (0.04, 0.207, 0.13), (0.0, 0.212, 0.13),
            (-0.05, 0.212, 0.13), (-0.10, 0.209, 0.13), (-0.14, 0.203, 0.13), (-0.18, 0.185, 0.11)] + A_TAIL,
    # Full over the head, narrowing down the jaw to the chin.
    "width": [(-0.34, 0.045), (-0.17, 0.05), (-0.15, 0.058), (-0.13, 0.068), (-0.11, 0.078), (-0.09, 0.088),
              (-0.07, 0.096), (-0.05, 0.104), (-0.03, 0.114), (0.01, 0.121), (0.05, 0.125), (0.07, 0.127),
              (0.26, 0.127)],
    "flare": 0.33,
    # The chin's tip is a round U, the face and jaw come to a prow, the crown is rounder again.
    "round": [(-0.34, 2.1), (-0.16, 2.1), (-0.12, 1.6), (0.10, 1.65), (0.17, 1.9), (0.26, 1.9)],
    "rim": spline2([(-0.128, 0.27), (-0.127, 0.19), (-0.124, 0.13), (-0.127, 0.09), (-0.135, 0.05),
                    (-0.138, 0.02), (-0.134, -0.02), (-0.123, -0.052), (-0.103, -0.076), (-0.07, -0.086),
                    (-0.02, -0.091), (0.02, -0.103), (0.06, -0.13), (0.10, -0.152), (0.14, -0.163),
                    (0.22, -0.168)], 6, closed=False) + [(0.3, -0.168), (0.3, 0.3), (-0.128, 0.3)],
    "fit": (FIT_S, FIT_Z),
}
# The cage opening, (azimuth deg, y): it wraps around to the temples.
A_OPEN = mirrored(spline2([(0.0, 0.084), (30.0, 0.083), (58.0, 0.074), (70.0, 0.05), (69.0, 0.02),
                           (60.0, -0.012), (46.0, -0.036), (26.0, -0.05), (0.0, -0.054)], 8, closed=False))
# The backplate from behind, (x, y).
A_PLATE = mirrored(spline2([(0.0, 0.10), (0.032, 0.096), (0.055, 0.076), (0.066, 0.04), (0.068, 0.0),
                            (0.063, -0.04), (0.047, -0.072), (0.024, -0.084), (0.0, -0.086)], 8, closed=False))
A_SLOTS = [(0.0, 0.066, 0.011, 0.004), (0.034, 0.03, 0.004, 0.012), (-0.034, 0.03, 0.004, 0.012),
           (0.034, -0.035, 0.004, 0.012), (-0.034, -0.035, 0.004, 0.012), (0.0, 0.0, 0.004, 0.015)]


def build_a():
    sh = Shell(A_SPEC)
    shell, liner = cut_shell(sh, "gm_a", lambda surf: [
        az_cutter("cut_open", A_OPEN),
        hole_cutter("cut_vents", surf, round_vents(
            top=[(0.03, 0.045), (0.05, -0.02), (0.03, -0.075)],
            side=[(-0.035, 0.115), (-0.02, 0.045, 0.0085), (-0.045, -0.035, 0.0085), (0.045, -0.062, 0.0075)]))],
        extra=opening_lip(sh, deg(A_OPEN)))
    plate, plate_bvh = backplate("gm_a_plate", A_PLATE, A_SLOTS)
    harness = straps("gm_a_straps", sh, plate_bvh,
                     sides=[(0.04, 0.06, 0.058), (-0.04, 0.054, -0.034)],
                     tops=[(0.03, 0.026, 0.05, 0.086), (-0.03, -0.026, 0.05, 0.086)])
    trim = join([plate, harness], "gm_a_trim")
    paint(trim, "GMTrim", TRIM_COL, 0.5)
    hair = scalp("gm_a_scalp", sh)
    paint(hair, "GMScalp", (0.25, 0.13, 0.06), 0.85)
    # Cage: bars across at the brow, under the eyes and at the mouth, a double bar down to
    # the nose, and uprights that leave the eyes clear.
    cage = cage_on("gm_a_cage", sh, A_OPEN, 0.027, [
        ([(-80, 0.058), (80, 0.058)], 0), ([(-80, -0.002), (80, -0.002)], 0), ([(-80, -0.03), (80, -0.03)], 0),
        ([(5, 0.1), (5, -0.002)], 0), ([(-5, 0.1), (-5, -0.002)], 0),
        ([(0, -0.002), (0, -0.08)], WIRE * 1.15),
        ([(17, -0.002), (17, -0.08)], 0), ([(-17, -0.002), (-17, -0.08)], 0),
        ([(34, -0.002), (34, -0.08)], 0), ([(-34, -0.002), (-34, -0.08)], 0),
        ([(46, 0.1), (46, -0.08)], 0), ([(-46, 0.1), (-46, -0.08)], 0),
        ([(62, 0.1), (62, -0.08)], 0), ([(-62, 0.1), (-62, -0.08)], 0)], clip_y=0.021)
    return {"shell": shell, "liner": liner, "cage": cage, "trim": trim, "scalp": hair}


# --- C: the '80s mask -----------------------------------------------------------------------------
# The fiberglass-and-cage masks of the 1980s: a rounder, closer shell with no wings and a
# short chin, a big opening filled with a straight-bar cage, and a large backplate on wide
# straps. Shaped at the modern mask's size and brought down onto the head the same way.

C_SPEC = {
    "sil": [(0.165, -0.30, 0.08), (0.160, -0.22, 0.08), (0.150, -0.15, 0.09), (0.143, -0.115, 0.11),
            (0.138, -0.085, 0.13), (0.135, -0.05, 0.15), (0.136, -0.01, 0.16), (0.136, 0.03, 0.16),
            (0.132, 0.07, 0.16), (0.122, 0.105, 0.16), (0.108, 0.135, 0.155), (0.088, 0.165, 0.15),
            (0.06, 0.187, 0.15), (0.025, 0.198, 0.15), (-0.02, 0.201, 0.15), (-0.07, 0.199, 0.15),
            (-0.12, 0.192, 0.15), (-0.16, 0.175, 0.13), (-0.195, 0.145, 0.10)] + A_TAIL[1:],
    "width": [(-0.34, 0.064), (-0.15, 0.074), (-0.11, 0.092), (-0.07, 0.109), (-0.03, 0.122), (0.01, 0.128),
              (0.05, 0.131), (0.26, 0.131)],
    "flare": 0.2,
    "round": [(-0.34, 2.2), (-0.14, 2.2), (-0.10, 2.0), (0.26, 2.1)],   # a bubble, not a prow
    "rim": spline2([(-0.12, 0.27), (-0.12, 0.12), (-0.12, 0.0), (-0.115, -0.045), (-0.095, -0.072),
                    (-0.06, -0.082), (-0.01, -0.088), (0.03, -0.098), (0.07, -0.118), (0.11, -0.132),
                    (0.22, -0.136)], 6, closed=False) + [(0.3, -0.136), (0.3, 0.3), (-0.12, 0.3)],
    "fit": (FIT_S, FIT_Z),
}
C_OPEN = mirrored(spline2([(0.0, 0.09), (34.0, 0.089), (62.0, 0.08), (74.0, 0.052), (74.0, 0.015),
                           (68.0, -0.02), (54.0, -0.048), (30.0, -0.062), (0.0, -0.066)], 8, closed=False))
C_PLATE = mirrored(spline2([(0.0, 0.118), (0.04, 0.112), (0.066, 0.085), (0.078, 0.04), (0.078, -0.005),
                            (0.07, -0.05), (0.05, -0.08), (0.025, -0.092), (0.0, -0.094)], 8, closed=False))
C_SLOTS = [(x, y, 0.004, 0.011) for x in (-0.04, 0.0, 0.04) for y in (0.06, 0.01, -0.04)]


def build_c():
    sh = Shell(C_SPEC)
    shell, liner = cut_shell(sh, "gm_c", lambda surf: [
        az_cutter("cut_open", C_OPEN),
        hole_cutter("cut_vents", surf, round_vents(
            top=[(0.04, 0.03, 0.009), (0.04, -0.05, 0.009)], side=[(-0.03, 0.1, 0.009)])
            # an ear hole each side
            + [((s * 0.5, 0.0, -0.0635), (-s, 0, 0), 0.021, 0.0265) for s in (1, -1)])],
        extra=opening_lip(sh, deg(C_OPEN), 0.004, 0.005))
    plate, plate_bvh = backplate("gm_c_plate", C_PLATE, C_SLOTS)
    harness = straps("gm_c_straps", sh, plate_bvh,
                     sides=[(0.05, 0.07, 0.064), (-0.05, 0.062, -0.044)],
                     tops=[(0.032, 0.03, 0.06, 0.1), (-0.032, -0.03, 0.06, 0.1)], width=0.026)
    trim = join([plate, harness], "gm_c_trim")
    paint(trim, "GMTrim", TRIM_COL, 0.5)
    # Cage: straight bars all the way across and down, the eyes behind them.
    bars = [([(-85, y), (85, y)], 0) for y in (0.064, 0.012, -0.02, -0.046)]
    bars += [([(a, 0.11), (a, -0.09)], WIRE * 1.1 if a == 0 else 0)
             for a in (-66, -52, -38, -24, -12, 0, 12, 24, 38, 52, 66)]
    cage = cage_on("gm_c_cage", sh, C_OPEN, 0.016, bars)
    return {"shell": shell, "liner": liner, "cage": cage, "trim": trim}


# --- D: the molded mask ---------------------------------------------------------------------------
# A one-piece molded fiberglass mask of the 1970s, the kind that covers the whole face and
# runs up over the forehead and back along the sides, so it reads as a helmet: close to the
# face with a ridge down the nose to a pointed chin, a brow ridge over two eye holes, round
# vent holes over the cheeks, forehead and sides, and a strap harness to a pad on the back
# of the head. Shaped at its final size on the head.

D_SPEC = {
    "sil": [(0.095, -0.21, 0.07), (0.098, -0.165, 0.07), (0.102, -0.135, 0.075), (0.109, -0.112, 0.085),
            (0.117, -0.088, 0.095), (0.125, -0.06, 0.10), (0.132, -0.03, 0.10), (0.128, -0.005, 0.10),
            (0.118, 0.018, 0.10), (0.117, 0.045, 0.10), (0.114, 0.07, 0.10), (0.106, 0.095, 0.10),
            (0.094, 0.118, 0.095), (0.076, 0.138, 0.09), (0.05, 0.152, 0.09), (0.02, 0.159, 0.09),
            (-0.02, 0.16, 0.09), (-0.06, 0.156, 0.09), (-0.10, 0.14, 0.08), (-0.14, 0.11, 0.07),
            (-0.16, 0.06, 0.06), (-0.165, 0.0, 0.06), (-0.165, -0.10, 0.06), (-0.16, -0.20, 0.06),
            (-0.15, -0.26, 0.06), (-0.05, -0.27, 0.06), (0.05, -0.265, 0.06)],
    "width": [(-0.34, 0.026), (-0.14, 0.03), (-0.12, 0.042), (-0.09, 0.062), (-0.06, 0.077), (-0.03, 0.087),
              (0.0, 0.092), (0.26, 0.092)],
    "flare": 0.05,
    "round": [(-0.34, 1.6), (-0.10, 1.6), (-0.04, 1.8), (0.09, 1.85), (0.14, 2.0), (0.26, 2.0)],
    # Back to the crown on top; down in front of the ear; along the jaw to the chin's point.
    "rim": spline2([(-0.045, 0.25), (-0.045, 0.14), (-0.034, 0.10), (-0.012, 0.066), (0.008, 0.035),
                    (0.013, 0.0), (0.011, -0.03), (0.016, -0.056), (0.036, -0.084), (0.066, -0.11),
                    (0.1, -0.137), (0.2, -0.19)], 6, closed=False) + [(0.3, -0.19), (0.3, 0.3), (-0.045, 0.3)],
    "fit": None,
}
D_PAD = mirrored(spline2([(0.0, 0.055), (0.03, 0.05), (0.048, 0.03), (0.05, 0.0), (0.045, -0.025),
                          (0.025, -0.04), (0.0, -0.042)], 8, closed=False))


D_EYE = (0.034, 0.026, 0.026, 0.0145, 0.14)   # eye holes: center x, y, half width, half height, tilt


def d_molding(sh):
    """The face molded into it: a brow ridge over the eyes and the bulge of the nose."""
    extra = np.zeros(len(sh.r))
    for i, p in enumerate(sh.points()):
        if p[2] < 0.02:
            continue
        ax = abs(p[0])
        brow = 0.0045 * math.exp(-((p[1] - 0.052 - 0.08 * ax) / 0.0075) ** 2) * smooth(0.088, 0.06, ax)
        nose = 0.005 * math.exp(-(ax / 0.015) ** 2) * smooth(0.02, 0.0, p[1]) * smooth(-0.055, -0.03, p[1])
        extra[i] = brow + nose
    return extra


def build_d():
    sh = Shell(D_SPEC)
    shell, liner = cut_shell(sh, "gm_d", lambda surf: [
        prism_cutter("cut_eye%d" % k, ellipse(s * D_EYE[0], D_EYE[1], D_EYE[2], D_EYE[3], 28, rot=s * D_EYE[4]),
                     "z", 0.02, 0.3)
        for k, s in enumerate((1, -1))] + [
        hole_cutter("cut_vents", surf, round_vents(
            face=[(0.0, 0.118), (0.036, 0.108), (0.06, 0.08), (0.03, 0.078, 0.007),
                  (0.021, -0.012, 0.0075), (0.045, -0.018), (0.062, -0.04, 0.007),
                  (0.024, -0.044), (0.046, -0.054), (0.022, -0.076, 0.0075), (0.04, -0.086, 0.007)],
            side=[(0.045, 0.045, 0.0075), (0.04, 0.005, 0.0075), (0.012, 0.085, 0.007)],
            top=[(0.03, 0.02, 0.0075), (0.0, -0.015, 0.0075)]))],
        extra=d_molding(sh), thick=0.004)
    pad, pad_bvh = backplate("gm_d_pad", D_PAD, [])
    harness = straps("gm_d_straps", sh, pad_bvh, sides=[(0.03, 0.044, 0.056), (-0.015, 0.042, -0.036)],
                     tops=[(0.0, 0.0, 0.02, 0.05)], width=0.02)
    trim = join([pad, harness], "gm_d_trim")
    paint(trim, "GMTrim", TRIM_COL, 0.5)
    return {"shell": shell, "liner": liner, "trim": trim}


# --- B: the helmet-and-cage combo -----------------------------------------------------------------
# A skater's helmet (the classic one, tools/blender/helmet_gear.py: its exported glb, without
# the visor) with a goalie's wire cage hung from the brow down around the chin.

B_CAGE_SPEC = {
    "sil": [(0.02, -0.158, 0.07), (0.07, -0.154, 0.07), (0.105, -0.138, 0.08), (0.128, -0.112, 0.09),
            (0.142, -0.075, 0.10), (0.148, -0.035, 0.11), (0.148, 0.005, 0.11), (0.142, 0.04, 0.11),
            (0.13, 0.072, 0.11), (0.115, 0.11, 0.10), (0.09, 0.15, 0.09), (0.04, 0.18, 0.09),
            (-0.04, 0.185, 0.09), (-0.12, 0.16, 0.08), (-0.165, 0.10, 0.07), (-0.175, 0.0, 0.06),
            (-0.165, -0.10, 0.06), (-0.12, -0.15, 0.06), (-0.05, -0.16, 0.06)],
    "width": [(-0.34, 0.07), (-0.14, 0.074), (-0.10, 0.088), (-0.05, 0.1), (0.0, 0.106), (0.26, 0.106)],
    "flare": 0.0,
    "round": [(-0.34, 2.3), (0.26, 2.3)],
    "fit": None,
}
# Where the cage runs, (azimuth deg, y): from under the helmet's brim, back along its front
# edge to the ear, and down around under the chin.
B_CAGE = mirrored(spline2([(0.0, 0.056), (30.0, 0.056), (48.0, 0.042), (60.0, 0.008), (68.0, -0.036),
                           (70.0, -0.072), (62.0, -0.106), (42.0, -0.13), (18.0, -0.142), (0.0, -0.145)],
                          8, closed=False))


def import_nodes(path, names, prefix):
    """Brings a glb's nodes in as objects named prefix + node."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    out = {}
    for o in [o for o in bpy.data.objects if o not in before]:
        key = o.name.split(".")[0]
        if o.type == "MESH" and key in names:
            o.data.transform(o.matrix_world)
            o.matrix_world.identity()
            replace(prefix + key)
            o.name = prefix + key
            for c in list(o.users_collection):
                c.objects.unlink(o)
            collection().objects.link(o)
            out[key] = o
        else:
            bpy.data.objects.remove(o, do_unlink=True)
    return out


def build_b():
    parts = import_nodes(os.path.join(OUT, "helmet_b.glb"), ("shell", "trim", "dark"), "gm_b_")
    paint(parts["shell"], "GMShell", SHELL_COL, 0.3)
    paint(parts["trim"], "GMWhite", (0.9, 0.9, 0.88), 0.4)
    paint(parts["dark"], "GMLiner", LINER_COL, 0.8)
    sh = Shell(B_CAGE_SPEC)
    cage_m = deg(B_CAGE)
    top = max(q[1] for q in cage_m)
    paths = [(deg([(-80, y), (80, y)]), 0) for y in (0.012, -0.026, -0.064, -0.1)]
    paths += [(deg([(a, 0.07), (a, -0.16)]), 0.0021 if a == 0 else 0) for a in (-46, -30, -15, 0, 15, 30, 46)]
    paths += [(deg([(s * 60, 0.012), (s * 60, -0.1)]), 0) for s in (1, -1)]
    paths += [(cage_m + [cage_m[0]], 0.0027)]
    # The clips that hang it from the brim, and the J clips on the sides.
    paths += [(deg([(s * 22 - 4, top), (s * 22 + 4, top)]), 0.0042) for s in (1, -1)]
    for s in (1, -1):
        side = [q for q in cage_m if q[0] * s > 0 and -0.05 < q[1] < -0.03]
        paths.append((sorted(side, key=lambda q: q[1]), 0.0042))
    cage = cage_wires("gm_b_cage", sh.bvh(), paths, lambda q: sd2(q, cage_m) > -0.002, wire=0.0019)
    paint(cage, "GMCage", CAGE_COL, 0.35)
    return {"shell": parts["shell"], "trim": parts["trim"], "liner": parts["dark"], "cage": cage}


# --- Building, the line-up and checks -------------------------------------------------------------

BUILDERS = {"a": build_a, "b": build_b, "c": build_c, "d": build_d}
PAINTED = {"a": A_SPEC, "c": C_SPEC, "d": D_SPEC}   # the shells with a paint layout (paint_uv)
OPENINGS = {"a": A_OPEN, "c": C_OPEN}
LINE_UP = {"d": -0.42, "a": 0.0, "c": 0.42, "b": 0.84}   # where each stands (m to the side), on its own head
# The glTF nodes each is exported with, in the order of the game mesh's surfaces
# (tools/build_gear.gd MASKS, GoalieVisual.MASKS). The combo's trim is the helmet's white
# trim; the modern mask's file also carries the scalp cap.
NODES = {"a": ["shell", "liner", "cage", "trim", "scalp"], "b": ["shell", "liner", "cage", "trim"],
         "c": ["shell", "liner", "cage", "trim"], "d": ["shell", "liner", "trim"]}


def build_all(do_export=False, only="abcd"):
    """Builds the masks side by side, each on a copy of the reference head, and exports
    them to assets/equip/goalie_mask_<key>.glb."""
    _heads.clear()
    for o in list(bpy.data.objects):
        if o.name.startswith("cut_") or (o.name.startswith(("gm_", "pv_")) and o.name[3] in only):
            bpy.data.objects.remove(o, do_unlink=True)
    out = {}
    for key in only:
        parts = BUILDERS[key]()
        at = Vector((LINE_UP[key], 0.0, 0.0))
        for o in parts.values():
            o.location = g(*HEAD_CENTER) + at
        if LINE_UP[key] != 0.0:
            for n in (HEADS["male"]["obj"], HEADS["male"]["eyes"]):
                src = bpy.data.objects[n]
                dup = bpy.data.objects.new("pv_%s_%s" % (key, n), src.data)
                dup.matrix_world = src.matrix_world.copy()
                dup.location = dup.location + at
                collection().objects.link(dup)
        print(key, "tris:", {k: sum(len(p.vertices) - 2 for p in o.data.polygons) for k, o in parts.items()})
        if do_export:
            export(parts, NODES[key], "goalie_mask_%s.glb" % key, uvs=True)
        out[key] = parts
    return out


def head_overlap(parts):
    """How far the head pokes through the liner, if anywhere (mm, and where)."""
    c = Vector((0.0, 0.03, 0.0))
    bvh = head()["bvh"]
    worst, at = 0.0, None
    for v in parts["liner"].data.vertices:
        p = gv(v.co)
        d = (p - c).normalized()
        hit = cast(bvh, c + d * 0.5, -d)
        if hit is not None and hit.y > -0.115:
            over = (hit - c).length - (p - c).length
            if over > worst:
                worst, at = over, p
    print("head through the liner: %.1f mm" % (worst * 1000), "at", [round(q, 3) for q in at] if at else None)


def scalp_overlap(parts):
    """How far the scalp cap pokes through the liner, if anywhere (mm)."""
    c = Vector((0.0, 0.03, 0.0))
    o = parts["liner"]
    bvh = BVHTree.FromPolygons([gv(v.co) for v in o.data.vertices], [tuple(p.vertices) for p in o.data.polygons])
    worst = 0.0
    for v in parts["scalp"].data.vertices:
        p = gv(v.co)
        d = (p - c).normalized()
        hit = cast(bvh, c, d)
        if hit is not None:
            worst = max(worst, (p - c).length - (hit - c).length)
    print("scalp through the liner: %.1f mm" % (worst * 1000))
