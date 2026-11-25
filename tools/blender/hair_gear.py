# Builds every hairstyle and all the facial hair in Blender, on the game's own heads, and
# exports them to assets/equip/hair.glb; tools/build_hair.gd turns that into
# assets/characters/hair/<id>.res. Nothing here comes from an outside model.
#
# Run in Blender (with the reference heads loaded, see tools/blender/mask_gear.py):
#   exec(open(r"<project>/tools/blender/hair_gear.py").read()); build_all(True)
# build_all stands every style in a row in its own "HairLab" scene, each on a copy of the
# head (men in front, women behind them, the under-helmet versions behind those);
# only=["flow"] builds some; build_all(True) also writes the glb and the strand texture.
#
# How hair is made:
#   * each head is measured once: rays from a point inside it out through the skin, on a
#     grid (around the head, down from the crown). Two such charts per head: the scalp
#     (from the middle of the skull, ears taken off) and the face (from the middle of the
#     jaw, as it is)
#   * a style is a thickness over a chart (the hair's volume), an edge (where it ends: the
#     hairline, or lower where it hangs over the forehead, ears and neck; for facial hair
#     an outline made of zones) and fields of locks
#   * the volume is a shell, cut clean along the edge, darker than the locks: it is what
#     shows in the gaps between them
#   * a lock is a tapered ribbon with a shallow arch, grown from a root along the style's
#     flow (away from the whorl, combed back, off a part...), riding on the volume. Where
#     it runs off the bottom of the skull it hangs free, kept off the neck; it can also
#     curl, or flip out at its end
#   * tails, braids and buns are swept tubes
# Hairstyles are built for each body ("<id>" male, "<id>_female"), and again pressed under
# a helmet ("<id>_helm", "<id>_female_helm"): the thin volume alone above the helmet's rim,
# as grown below it. Facial hair is built on the male head only.
#
# Space: "head space", as the game places hair (SkaterVisual._add_hair): the origin on top
# of the head box (centered), +Y up, +Z the face, +X the head's left. Meters here; the
# exported meshes are in head widths (meters / the head box's width).
# Vertex colors shade the hair (dark volume, lighter locks, lighter toward the tips); UVs
# run along each lock (v) for the strand grain (strands.png, made here too).

import math
import os
import random

import bpy
import numpy as np
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\hair_gear.py")))))
OUT_GLB = os.path.join(PROJECT, "assets", "equip", "hair.glb")
TEX_OUT = os.path.join(PROJECT, "assets", "characters", "hair", "strands.png")
LAB = "HairLab"

# The dumped heads (tools/dump_heads.gd, imported and named as mask_gear.py says) and each
# body's head box (skeleton space, from the dump's printout).
# "lift": the hairlines, the facial hair's zones and the styles themselves were laid out on
# the downloaded bodies the game began with. Our own heads are the same below the brow
# (eyes, ears, jaw, nape all within a millimeter or two), but the top of the skull is lower:
# measured down from the crown, everything sits this much higher (m). The charts' centers
# are raised by it, so every angle still lands on the same part of the face.
HEADS = {
    "male": {"obj": "head_male", "eyes": "eyes_male", "lift": 0.0063,
             "box": ((-0.095738, 1.553988, -0.049997), (0.191476, 0.286012, 0.237688))},
    "female": {"obj": "head_female", "eyes": "eyes_female", "lift": 0.0032,
               "box": ((-0.092633, 1.49781, -0.054504), (0.185266, 0.25219, 0.228945))},
}
SKULL = Vector((0.0, -0.095, -0.01))   # the scalp chart's rays start here (plus the lift)
JAW = Vector((0.0, -0.15, -0.02))      # ...and the face chart's
DP = 3.0                           # chart step around the head (degrees)
DT = 3.0                           # ...and down from the crown
TH_MAX = 156.0                     # the scalp chart's last row (the chin)
TH_BACK = 141.0                    # ...and the last one that is still skull behind the ears:
                                   # below it the rays graze the neck, hair hangs free
TH_FACE = 168.0                    # the face chart's last row (the throat)
SHELL_STEP = 6.0                   # the volume's own grid on the scalp (degrees)
FACE_STEP = 3.0                    # ...and on the face
# Triangle budget: lock fields are written at full density; the scalp's are thinned by
# these (rows and columns of roots spread out, each lock widened to keep the cover).
THIN_ROW = 1.3
THIN_COL = 1.45
THIN_W = 1.4
THIN_FACE = 1.3                    # the same for facial hair (both ways, and the width)
DEG = 0.0016                       # about a degree of chart on the skin (m)
MIN_T = 0.0007                     # the thinnest the volume gets (m off the skin)
# Under a helmet: above RIM (head widths below the top of the head, where the old build
# step had it) the volume is pressed to HELM_T off the scalp and there are no locks. The
# game also wears a skin-tight cap in the hair's color under head gear (scalp_cap.res),
# which is what shows wherever a snug mask squeezes this in under the skin.
RIM = -0.62
HELM_T = 0.002                     # the volume's thickness under the helmet (m)
HELM_SHADE = 0.75                  # ...and its shade there (the cap's)
TEX_V = 0.07                       # meters of lock per strand texture repeat (along)
TEX_U = 0.05                       # ...and across


def g(p):
    """Head space / game axes (Y up, +Z front) to Blender (Z up); glTF export maps back."""
    return Vector((p[0], -p[2], p[1]))


def gv(v):
    return Vector((v.x, v.z, -v.y))


def smooth(e0, e1, x):
    if e0 == e1:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def wrap(phi):
    return ((phi + 180.0) % 360.0) - 180.0


def dirv(phi, theta):
    """Unit vector: `theta` degrees down from straight up, `phi` around (0 the face, 90 the
    head's left)."""
    a, b = math.radians(phi), math.radians(theta)
    return Vector((math.sin(b) * math.sin(a), math.cos(b), math.sin(b) * math.cos(a)))


def rot(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis) @ v


def curve(points, x):
    """Smooth interpolation through (x, y) points sorted by x, flat past the ends."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return lerp(y0, y1, smooth(x0, x1, x))
    return points[-1][1]


# --- The head ------------------------------------------------------------------------------

# Where hair grows: the lowest it reaches (degrees down from the crown, scalp chart) by the
# angle around from the face (0 the middle of the forehead ... 180 the nape), the same on
# both sides. Forehead, the temple's corner, down the sideburn in front of the ear, over
# the ear, down behind it, across the nape.
HAIRLINE = {
    "male": [(0, 60), (24, 59), (40, 55), (50, 60), (58, 82), (64, 102), (70, 110), (77, 109),
             (83, 98), (96, 95), (108, 99), (116, 120), (128, 131), (150, 136), (180, 136)],
    "female": [(0, 60), (24, 59), (40, 56), (50, 61), (58, 82), (64, 98), (70, 104), (77, 103),
               (83, 97), (96, 95), (108, 99), (116, 120), (128, 131), (150, 135), (180, 135)],
}

_heads = {}


class Chart:
    """The skin's distance from `center` on a (theta, phi) grid of rays, and the surface
    that makes. `opened`: ears (and anything else narrow that sticks out) taken off, by an
    opening around the head (lowest, then highest, over a window). `back`: the last row
    that can be followed behind the ears."""

    def __init__(self, hd, center, th_max, opened, back=None):
        self.head, self.c, self.th_max, self.back = hd, center, th_max, back
        self.width = hd.width
        self.np = int(round(360 / DP))
        self.nt = int(round(th_max / DT)) + 1
        r = np.zeros((self.nt, self.np))
        for j in range(self.nt):
            for i in range(self.np):
                d = dirv(-180 + i * DP, j * DT)
                loc, _, _, dist = hd.bvh.ray_cast(center + d * 0.42, -d, 0.42)
                r[j, i] = 0.42 - dist if loc is not None else np.nan
        for j in range(1, self.nt):   # misses (out through the neck): the row above
            bad = np.isnan(r[j])
            r[j, bad] = r[j - 1, bad]
        if opened:
            k = 4
            lo = np.min([np.roll(r, s, axis=1) for s in range(-k, k + 1)], axis=0)
            op = np.max([np.roll(lo, s, axis=1) for s in range(-k, k + 1)], axis=0)
            op = (np.roll(op, 1, axis=1) + 2 * op + np.roll(op, -1, axis=1)) / 4
            # ...around the ears only; everywhere else the skin as measured.
            for j in range(self.nt):
                for i in range(self.np):
                    a = abs(-180 + i * DP)
                    w = smooth(58.0, 72.0, a) * (1.0 - smooth(118.0, 132.0, a)) * smooth(78.0, 90.0, j * DT)
                    r[j, i] = lerp(r[j, i], op[j, i], w)
        if back is not None:
            # Below `back` the rays hit the neck and shoulders: hold the last good row
            # (nothing follows the chart down there, see limit()).
            jb = int(back / DT)
            for i in range(self.np):
                if abs(-180 + i * DP) > 95:
                    r[jb + 1:, i] = r[jb, i]
        self.r = r

    def R(self, phi, theta):
        x = ((phi + 180.0) / DP) % self.np
        y = max(0.0, min(self.nt - 1.001, theta / DT))
        i0, j0 = int(x), int(y)
        fx, fy = x - i0, y - j0
        i1 = (i0 + 1) % self.np
        r = self.r
        return lerp(lerp(r[j0, i0], r[j0, i1], fx), lerp(r[j0 + 1, i0], r[j0 + 1, i1], fx), fy)

    def S(self, phi, theta, h=0.0):
        """The point `h` off the skin at (phi, theta)."""
        return self.c + dirv(phi, theta) * (self.R(phi, theta) + h)

    def param(self, p):
        q = p - self.c
        return math.degrees(math.atan2(q.x, q.z)), math.degrees(math.acos(max(-1.0, min(1.0, q.y / q.length))))

    def limit(self, phi):
        """The lowest the chart can be followed at `phi` (degrees down from the crown)."""
        if self.back is None:
            return self.th_max - 2.0
        return lerp(self.th_max - 2.0, self.back, smooth(85.0, 100.0, abs(wrap(phi))))

    def frame(self, phi, theta):
        """(d/dphi, d/dtheta, outward normal) of the surface, per degree."""
        e = 1.0
        su = (self.S(phi + e, theta) - self.S(phi - e, theta)) / (2 * e)
        sv = (self.S(phi, theta + e) - self.S(phi, max(0.0, theta - e))) / (e + min(e, theta))
        n = su.cross(sv)
        d = dirv(phi, theta)
        if n.length < 1e-9 or theta < 2.0:
            return su, sv, d
        n.normalize()
        if n.dot(d) < 0:
            n = -n
        return su, sv, n.lerp(d, 0.35).normalized()

    def step(self, phi, theta, move):
        """(phi, theta) after moving `move` (meters, any direction) along the surface."""
        if theta < 6.0:
            return self.param(self.S(phi, theta) + move)
        su, sv, _ = self.frame(phi, theta)
        a, b, c = su.dot(su), su.dot(sv), sv.dot(sv)
        det = a * c - b * b
        if det < 1e-16:
            return self.param(self.S(phi, theta) + move)
        x, y = su.dot(move), sv.dot(move)
        return phi + (c * x - b * y) / det, theta + (a * y - b * x) / det


class Head:
    def __init__(self, body):
        h = HEADS[body]
        pos, size = Vector(h["box"][0]), Vector(h["box"][1])
        self.body = body
        self.top = Vector((pos.x + size.x * 0.5, pos.y + size.y, pos.z + size.z * 0.5))
        self.width = size.x
        o = bpy.data.objects[h["obj"]]
        vs = [gv(o.matrix_world @ v.co) - self.top for v in o.data.vertices]
        polys = [tuple(p.vertices) for p in o.data.polygons
                 if all(vs[i].y > -0.34 and abs(vs[i].x) < 0.14 for i in p.vertices)]
        self.bvh = BVHTree.FromPolygons(vs, polys)
        self.line = HAIRLINE[body]
        lift = Vector((0.0, h.get("lift", 0.0), 0.0))
        self.scalp = Chart(self, SKULL + lift, TH_MAX, True, TH_BACK)
        self.face = Chart(self, JAW + lift, TH_FACE, False)

    def hairline(self, phi):
        return curve(self.line, abs(wrap(phi)))

    def nearest(self, p):
        """(point on the skin, the way out from it, distance signed: < 0 inside the head)."""
        loc, nrm, _, d = self.bvh.find_nearest(p)
        out = p - loc
        if out.dot(nrm) < 0:
            return loc, nrm, -d
        return loc, (out.normalized() if d > 1e-6 else nrm), d


def head(body):
    if body not in _heads:
        _heads[body] = Head(body)
    return _heads[body]


# --- Geometry --------------------------------------------------------------------------------

class Geo:
    """Triangles with a position, UV and shade per vertex."""

    def __init__(self):
        self.v, self.uv, self.col, self.f = [], [], [], []

    def add(self, p, uv, shade):
        self.v.append(Vector(p))
        self.uv.append(uv)
        self.col.append(shade)
        return len(self.v) - 1

    def tri(self, a, b, c):
        self.f.append((a, b, c))

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))


def clip(geo, verts, tris, m):
    """Adds the part of a triangle soup where the field `m` (per vertex) is >= 0 to `geo`,
    cut straight along m = 0. `verts`: (position, uv, shade)."""
    made, cuts = {}, {}

    def put(i):
        if i not in made:
            made[i] = geo.add(*verts[i])
        return made[i]

    def cut(a, b):
        key = (a, b) if a < b else (b, a)
        if key not in cuts:
            t = m[a] / (m[a] - m[b])
            (pa, ua, ca), (pb, ub, cb) = verts[a], verts[b]
            cuts[key] = geo.add(pa.lerp(pb, t), (lerp(ua[0], ub[0], t), lerp(ua[1], ub[1], t)), lerp(ca, cb, t))
        return cuts[key]

    for t in tris:
        inside = [m[i] >= 0 for i in t]
        if all(inside):
            geo.tri(put(t[0]), put(t[1]), put(t[2]))
            continue
        if not any(inside):
            continue
        poly = []
        for k in range(3):
            a, b = t[k], t[(k + 1) % 3]
            if m[a] >= 0:
                poly.append(put(a))
            if (m[a] >= 0) != (m[b] >= 0):
                poly.append(cut(a, b))
        for k in range(1, len(poly) - 1):
            geo.tri(poly[0], poly[k], poly[k + 1])


def ribbon(geo, pts, nrms, width, rng, shade=(0.84, 1.0), arch=0.2, taper=0.45, root=0.6, tip=0.15):
    """A lock along `pts` (with the outward direction at each): `width` at its widest,
    narrowed to `root` of that where it starts and tapered to `tip` over its last
    (1 - `taper`); its edges dipped by `arch` of the width (a shallow arch). Shade runs
    root to tip."""
    n = len(pts)
    if n < 2:
        return
    lens = [0.0]
    for i in range(1, n):
        lens.append(lens[-1] + (pts[i] - pts[i - 1]).length)
    total = lens[-1] or 1e-6
    u0 = rng.random()
    tone = rng.uniform(-0.05, 0.05)
    du = width / TEX_U
    prev = None
    side = None
    for i in range(n):
        t = lens[i] / total
        tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        b = nrms[i].cross(tan)
        if b.length < 1e-5:
            b = side or Vector((1, 0, 0))
        b.normalize()
        if side is not None and b.dot(side) < 0:
            b = -b
        side = b
        up = tan.cross(b).normalized()
        if up.dot(nrms[i]) < 0:
            up = -up
        w = width * lerp(root, 1.0, smooth(0.0, 0.3, t)) * lerp(1.0, tip, smooth(taper, 1.0, t))
        sh = lerp(shade[0], shade[1], t) + tone
        v = lens[i] / TEX_V
        row = [geo.add(pts[i] + b * (j * w * 0.5) - up * (arch * w * j * j), (u0 + du * (j + 1) * 0.5, v),
                       sh * (1.0 if j == 0 else 0.94)) for j in (-1, 0, 1)]
        if prev is not None:
            for k in range(2):
                geo.quad(prev[k], prev[k + 1], row[k + 1], row[k])
        prev = row


def tube(geo, pts, radius, rng, sides=7, shade=(0.8, 1.0), flat=1.0, up=None, cap=True):
    """A round (or with `flat` < 1 flattened) tube along `pts`; `radius`: one, or f(t)."""
    n = len(pts)
    lens = [0.0]
    for i in range(1, n):
        lens.append(lens[-1] + (pts[i] - pts[i - 1]).length)
    total = lens[-1] or 1e-6
    u0 = rng.random()
    a = up or Vector((0, 0, -1))
    prev = None
    for i in range(n):
        t = lens[i] / total
        tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        b = a.cross(tan)
        if b.length < 1e-5:
            b = tan.orthogonal()
        b.normalize()
        a = tan.cross(b).normalized()
        r = radius(t) if callable(radius) else radius
        sh = lerp(shade[0], shade[1], t)
        row = []
        for k in range(sides + 1):
            ang = 2 * math.pi * k / sides
            off = b * (math.cos(ang) * r) + a * (math.sin(ang) * r * flat)
            row.append(geo.add(pts[i] + off, (u0 + k / sides * (2 * math.pi * r / TEX_U), lens[i] / TEX_V),
                               sh * (0.9 + 0.1 * math.sin(ang * 3 + i))))
        if prev is not None:
            for k in range(sides):
                geo.quad(prev[k], prev[k + 1], row[k + 1], row[k])
        elif cap:
            c = geo.add(pts[i], (u0, 0.0), sh)
            for k in range(sides):
                geo.tri(c, row[k + 1], row[k])
        prev = row
    if cap:
        c = geo.add(pts[-1], (u0, lens[-1] / TEX_V), shade[1])
        for k in range(sides):
            geo.tri(c, prev[k], prev[k + 1])


def blob(geo, center, radii, rng, shade=(0.75, 1.0), bump=0.06, axes=None, rows=9, cols=14):
    """A lumpy ball (a bun): `radii` along `axes` (three unit vectors; default x, y, z)."""
    ax = axes or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    seed = rng.random() * 50
    grid = []
    for j in range(rows + 1):
        th = math.pi * j / rows
        row = []
        for i in range(cols + 1):
            ph = 2 * math.pi * i / cols
            d = Vector((math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)))
            k = 1.0 + bump * noise.noise(d * 2.2 + Vector((seed, 0, 0)))
            p = center + ax[0] * (d.x * radii[0] * k) + ax[1] * (d.y * radii[1] * k) + ax[2] * (d.z * radii[2] * k)
            # The grain winds around the bun.
            row.append(geo.add(p, (i / cols * 3.0 + j * 0.35, j / rows * 1.5), lerp(shade[0], shade[1], 0.5 + 0.5 * d.y)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            geo.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])


# --- Styles ----------------------------------------------------------------------------------

def sph(phi, theta):
    """(side, up, front) of a chart direction: handy for saying where on the head."""
    d = dirv(phi, theta)
    return d.x, d.y, d.z


class Style:
    """A hairstyle or a piece of facial hair.
      thick(phi, theta)  the volume (m off the skin)
      fields             lock fields (see grow)
      cover(a)           how far down past the hairline the hair reaches (degrees), by the
                         angle around from the face (0..180); None = ends at the hairline
      mask(phi, theta)   more to cut away from where it grows (> 0 keeps; degrees)
      hairline(a)        degrees added to the body's hairline (negative = higher)
      zone(K, phi, theta)  facial hair: its outline instead of the hairline (> 0 inside; degrees)
      edge               degrees over which the volume thins out to nothing at its edge
      shade              the volume's shade (locks are lighter)
      extra(K, geo, rng, helm)  builds anything else (tails, buns)
      base               another style built first (its volume and locks), e.g. buzzed sides
      chart              "scalp" or "face"; women / men: who it is built for
      helm               False = no under-helmet version (facial hair)"""

    def __init__(self, thick, fields=(), cover=None, mask=None, edge=7.0, shade=0.6, hairline=None, zone=None,
                 extra=None, base=None, chart="scalp", women=True, men=True, helm=True, step=None):
        self.thick, self.fields, self.cover, self.mask = thick, list(fields), cover, mask
        self.edge, self.shade, self.hairline, self.zone, self.extra = edge, shade, hairline, zone, extra
        self.base, self.chart, self.women, self.men, self.helm = base, chart, women, men, helm
        self.step = step or (SHELL_STEP if chart == "scalp" else FACE_STEP)

    def grows(self, K, phi, theta):
        """Degrees inside where the hair grows (< 0 outside)."""
        if self.zone:
            return self.zone(K, phi, theta)
        line = K.head.hairline(phi)
        if self.hairline:
            line += self.hairline(abs(wrap(phi)))
        m = line - theta
        if self.mask:
            m = min(m, self.mask(phi, theta))
        return m

    def covered(self, K, phi, theta):
        """Degrees inside the hair's edge."""
        m = self.grows(K, phi, theta)
        if self.cover:
            c = self.cover(abs(wrap(phi)))
            m2 = K.head.hairline(phi) + c - theta
            if self.mask:
                m2 = min(m2, self.mask(phi, theta) + c)
            m = max(m, m2)
        return m

    def height(self, K, phi, theta, helm):
        t = self.thick(phi, theta)
        if helm:
            y = K.S(phi, theta).y / K.width
            t = lerp(t, min(t, HELM_T), smooth(RIM - 0.06, RIM + 0.1, y))
        return t


def add_shell(K, geo, st, helm):
    step = st.step
    cols = int(round(360 / step)) + 1
    rows = int(K.th_max / step) + 1
    verts, m = [], []
    for j in range(rows):
        th = j * step
        for i in range(cols):
            ph = -180 + i * step
            mm = st.covered(K, ph, th)
            if th > K.limit(ph):
                mm = min(mm, -1.0)
            t = st.height(K, ph, th, helm) * smooth(0.0, st.edge, mm)
            p = K.S(ph, th, max(MIN_T, t))
            shade = st.shade
            if helm:
                shade = lerp(shade, HELM_SHADE, smooth(RIM - 0.06, RIM + 0.1, p.y / K.width))
            verts.append((p, ((ph + 180.0) / 360.0 * 12.0, th / 180.0 * 4.0), shade))
            m.append(mm)
    tris = []
    for j in range(rows - 1):
        for i in range(cols - 1):
            if max(m[j * cols + i], m[j * cols + i + 1], m[(j + 1) * cols + i], m[(j + 1) * cols + i + 1]) < 0:
                continue
            a, b = j * cols + i, j * cols + i + 1
            c, d = (j + 1) * cols + i + 1, (j + 1) * cols + i
            if j > 0:
                tris.append((a, d, b))
            tris.append((b, d, c))
    clip(geo, verts, tris, m)


def scatter(K, st, fld, rng):
    """Roots (phi, theta) for a lock field: rows down from the crown `row` meters apart,
    `col` apart along each, jittered, where hair grows (and `where` says so)."""
    roots = []
    face = st.chart == "face"
    row = fld["row"] * (THIN_FACE if face else THIN_ROW)
    col = fld["col"] * (THIN_FACE if face else THIN_COL)
    th = fld.get("th0", 5.0)
    dth = math.degrees(row / 0.095)
    while th < K.th_max:
        circ = 2 * math.pi * 0.095 * max(0.05, math.sin(math.radians(th)))
        n = max(1, int(circ / col))
        off = rng.random()
        for k in range(n):
            ph = wrap(-180 + (k + off + rng.uniform(-0.3, 0.3)) * 360.0 / n)
            tj = th + rng.uniform(-0.35, 0.35) * dth
            if st.grows(K, ph, tj) < fld.get("inset", 2.0):
                continue
            if "where" in fld and not fld["where"](ph, tj):
                continue
            roots.append((ph, tj))
        th += dth
    return roots


def grow(K, geo, st, fld, ph, th, rng, helm):
    """One lock from a root. Field keys:
      len (m, or f(phi, theta)), len_j (share it varies by), w (width), segs
      flow(K, p, n, phi, theta, t) -> the way the hair wants to go (any length)
      wob (degrees each lock is turned off the flow), bend (degrees it curves over its
      length), curl (degrees it swings side to side) and turns (how many times)
      over (degrees past the hair's edge a lock may reach), lift (m: how far it stands off
      the volume at its middle), tip_h (m off the volume at its tip), sink (m under the
      volume's surface at its root), ride (share of the volume's height it rides at)
      Where a lock runs off the bottom of the skull (behind the ears) the rest of it hangs
      free (hang=False: it ends there; hang_max: at most this much, m); `free` adds a free
      end to every lock that reaches the hair's edge:
      free: {len, flip (degrees it curls out and up), down (pull toward straight down, 0..1),
             back (pull backward), out (m: least distance kept from the skin), segs}
      shade, arch, taper, tip, root: see ribbon."""
    L = fld["len"](ph, th) if callable(fld["len"]) else fld["len"]
    L *= 1.0 + rng.uniform(-1, 1) * fld.get("len_j", 0.2)
    fine = 16
    ds = L / fine
    wob = math.radians(rng.uniform(-1, 1) * fld.get("wob", 10.0))
    bend = math.radians(rng.uniform(-1, 1) * fld.get("bend", 0.0))
    curl = math.radians(fld.get("curl", 0.0)) * rng.choice((-1, 1))
    turns = fld.get("turns", 1.0) * rng.uniform(0.8, 1.2)
    phase = rng.uniform(0, 2 * math.pi)
    over = fld.get("over", 3.0)
    path = [(ph, th)]
    left = 0.0
    edge = False
    for i in range(fine):
        t = i / fine
        _, _, n = K.frame(ph, th)
        p = K.S(ph, th)
        want = fld["flow"](K, p, n, ph, th, t)
        d = want - n * want.dot(n)
        if d.length < 1e-6:
            d = n.orthogonal()
        d = rot(d.normalized(), n, wob + bend * t + curl * math.cos(2 * math.pi * turns * t + phase))
        ph2, th2 = K.step(ph, th, d * ds)
        if th2 > K.limit(ph2):
            left = min(L - i * ds, fld.get("hang_max", 1.0))
            break
        if st.covered(K, ph2, th2) < -over:
            edge = True
            break
        ph, th = ph2, th2
        path.append((ph, th))
    # A free end only where the lock got to the hair's edge (not one lying on the head).
    fr = fld.get("free") if (left > 0.0 or edge) else None
    tail = (left > 0.0 and fld.get("hang", True)) or fr is not None
    if len(path) < 3 and not tail:
        return
    segs = min(fld.get("segs", 4), 4)
    n_hug = segs if not tail else max(1, int(round(segs * (len(path) - 1) / fine)))
    pts, nrms = [], []
    lift, tip_h, sink, ride = fld.get("lift", 0.003), fld.get("tip_h", 0.0015), fld.get("sink", 0.002), fld.get("ride", 1.0)
    for k in range(n_hug + 1):
        t = k / n_hug
        x = t * (len(path) - 1)
        i0 = min(int(x), max(0, len(path) - 2))
        f = x - i0
        a, b = path[i0], path[min(i0 + 1, len(path) - 1)]
        pph, pth = a[0] + wrap(b[0] - a[0]) * f, lerp(a[1], b[1], f)
        base = st.height(K, pph, pth, helm) * ride * smooth(0.0, st.edge, st.covered(K, pph, pth) + 0.3)
        squash = 1.0
        if helm:
            squash = lerp(1.0, 0.25, smooth(RIM - 0.06, RIM + 0.1, K.S(pph, pth).y / K.width))
        if tail:
            h = base + lift * smooth(0.0, 0.5, t) * squash - sink * (1 - t) ** 2
        else:
            h = base + (lift * math.sin(math.pi * t ** 0.8) + tip_h * t) * squash - sink * (1 - t) ** 2
        pts.append(K.S(pph, pth, max(MIN_T, h)))
        nrms.append(K.frame(pph, pth)[2])
    if tail:
        fr = fr or {}
        more = left + fr.get("len", 0.0) * (1.0 + rng.uniform(-1, 1) * fld.get("len_j", 0.2))
        n_free = min(max(2, int(round(more / (L / segs)))), fr.get("segs", 8), 5)
        fs = more / n_free
        out, down, back = fr.get("out", 0.007), fr.get("down", 0.35), fr.get("back", 0.0)
        d = (pts[-1] - pts[-2]).normalized() if len(pts) > 1 else Vector((0, -1, 0))
        nr = nrms[-1]
        p = pts[-1]
        for k in range(n_free):
            side = nr.cross(d)
            if side.length > 1e-5 and fr.get("flip"):
                d = rot(d, side.normalized(), -math.radians(fr["flip"]) * smooth(0.0, 1.0, (k + 1) / n_free) * 2.0 / n_free)
            d = (d + Vector((0, -down, -back))).normalized()
            p = p + d * fs
            loc, nn, sd = K.head.nearest(p)
            if sd < out:
                p = loc + nn * out
                nr = nr.lerp(nn, 0.5).normalized()
            pts.append(p)
            nrms.append(nr)
    if len(pts) < 3:
        return
    kw = {k: fld[k] for k in ("shade", "arch", "taper", "tip", "root") if k in fld}
    wide = THIN_FACE if st.chart == "face" else THIN_W
    ribbon(geo, pts, nrms, fld["w"] * wide * (1.0 + rng.uniform(-0.2, 0.2)), rng, **kw)


def build_style(name, body, helm=False, geo=None, rng=None):
    st = STYLES[name]
    hd = head(body)
    K = getattr(hd, st.chart)
    geo = geo or Geo()
    rng = rng or random.Random(sum(ord(c) * (k + 1) for k, c in enumerate(name + body)))
    if st.base:
        build_style(st.base, body, helm, geo, rng)
    add_shell(K, geo, st, helm)
    for fld in st.fields:
        for ph, th in scatter(K, st, fld, rng):
            # Under the helmet's shell only the volume shows (in the vents): no locks up there.
            if helm and K.S(ph, th).y / K.width > RIM + fld.get("helm_keep", 0.12):
                continue
            grow(K, geo, st, fld, ph, th, rng, helm)
    if st.extra:
        st.extra(K, geo, rng, helm)
    return geo


# --- Flows -----------------------------------------------------------------------------------

def f_whorl(wphi=170.0, wtheta=24.0):
    """Away from the whorl, at the back of the crown."""
    def f(K, p, n, ph, th, t):
        return p - K.S(wphi, wtheta)
    return f


def f_toward(tphi, ttheta):
    """Toward a point on the head (where a tail or bun is gathered)."""
    def f(K, p, n, ph, th, t):
        return K.S(tphi, ttheta) - p
    return f


def f_comb(v):
    """One way everywhere (head space)."""
    v = Vector(v)
    return lambda K, p, n, ph, th, t: v


def f_back(drop=0.25, side=0.0):
    """Combed back: over the top toward the back of the head, then down it (one fixed
    direction would run every lock into the spot on the back of the head that faces it)."""
    def f(K, p, n, ph, th, t):
        return Vector((side, -drop, -1.0)).lerp(Vector((0.0, -1.0, -0.1)), smooth(-0.1, 0.55, -n.z))
    return f


def f_part(x0=0.03, back=0.35, down=0.5):
    """Off a part line running front to back at x = x0."""
    def f(K, p, n, ph, th, t):
        return Vector((1.0 if p.x > x0 else -1.0, -down, -back))
    return f


def f_mix(a, b, k):
    def f(K, p, n, ph, th, t):
        kk = k(ph, th, t) if callable(k) else k
        return a(K, p, n, ph, th, t).normalized().lerp(b(K, p, n, ph, th, t).normalized(), kk)
    return f


# --- The hairstyles --------------------------------------------------------------------------

def top_of(phi, theta, lo=0.25, hi=0.8):
    return smooth(lo, hi, sph(phi, theta)[1])


def front_of(phi, theta, lo=0.1, hi=0.7):
    return smooth(lo, hi, sph(phi, theta)[2])


def back_of(phi, theta, lo=0.1, hi=0.7):
    return smooth(lo, hi, -sph(phi, theta)[2])


def side_of(phi, theta, lo=0.5, hi=0.9):
    return smooth(lo, hi, abs(sph(phi, theta)[0]))


def tail_path(K, at, length, start=20.0, hang=64.0, steps=14):
    """A tail's center line from `at` on the back of the head: leaving `start` degrees below
    straight back, bending down to `hang` below it (not straight down: a skater leans
    forward, so straight down in head space runs into the back)."""
    pts = [Vector(at)]
    for k in range(steps):
        a = math.radians(lerp(start, hang, smooth(0.0, 0.35, (k + 0.5) / steps)))
        p = pts[-1] + Vector((0.0, -math.sin(a), -math.cos(a))) * (length / steps)
        loc, nn, sd = K.head.nearest(p)
        if sd < 0.016:
            p = loc + nn * 0.016
        pts.append(p)
    return pts


def band(geo, pts, k, radius, rng):
    """The tie around a tail at point `k` of its path."""
    tube(geo, [pts[k], pts[k] + (pts[k + 1] - pts[k]).normalized() * 0.008], radius, rng, sides=8,
         shade=(0.3, 0.3), cap=False)


def ponytail(gather=(180.0, 100.0), helm_gather=(180.0, 118.0), length=0.2, radius=0.017, braided=False):
    def extra(K, geo, rng, helm):
        gp = helm_gather if helm else gather
        at = K.S(gp[0], gp[1], 0.004)
        pts = tail_path(K, at, length * (0.85 if helm else 1.0), start=25.0 if not helm else 55.0, steps=30 if braided else 14)
        if not braided:
            tube(geo, pts, lambda t: radius * lerp(0.7, 1.15, smooth(0.0, 0.22, t)) * lerp(1.0, 0.1, smooth(0.6, 1.0, t) ** 1.5),
                 rng, sides=8, flat=0.8)
            band(geo, pts, 1, radius * 0.95, rng)
            return
        # Three strands, each weaving side to side and over and under the others.
        n = len(pts)
        twists = 6.5
        strands = [[] for _ in range(3)]
        up = Vector((0, 0, -1))
        for i in range(n):
            t = i / (n - 1)
            tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            b = up.cross(tan).normalized()
            a = tan.cross(b).normalized()
            amp = radius * 0.62 * lerp(1.0, 0.55, t)
            for s in range(3):
                w = 2 * math.pi * (twists * t + s / 3.0)
                strands[s].append(pts[i] + b * (math.sin(w) * amp) + a * (math.sin(2 * w) * amp * 0.5))
        for s in range(3):
            tube(geo, strands[s], lambda t: radius * 0.52 * lerp(1.0, 0.5, t) * (1.0 - 0.75 * smooth(0.93, 1.0, t)), rng,
                 sides=5, shade=(0.82, 1.0))
        band(geo, pts, 1, radius * 1.05, rng)
        band(geo, pts, n - 4, radius * 0.6, rng)
    return extra


def bun(at=(180.0, 62.0), size=0.032, helm_ok=False):
    def extra(K, geo, rng, helm):
        if helm and not helm_ok:
            return
        d = dirv(*at)
        c = K.S(at[0], at[1], size * 0.75)
        side = Vector((1, 0, 0))
        fwd = d.cross(side).normalized()
        blob(geo, c, (size, size * 0.8, size), rng, axes=(side, d, fwd))
        tube(geo, [K.S(at[0], at[1], 0.004), K.S(at[0], at[1], 0.012)], size * 0.55, rng, sides=8, shade=(0.3, 0.3), cap=False)
    return extra


STYLES = {}
HAIR = []      # hairstyle ids, in the order the game lists them
FACIAL = []    # facial hair ids


def hair(name, *a, **kw):
    STYLES[name] = Style(*a, **kw)
    HAIR.append(name)


def _hairstyles():
    whorl = f_whorl()

    # Buzz cut: the volume alone, close to the scalp.
    hair("buzz", lambda ph, th: 0.0028, edge=5.0, shade=0.92)

    # Short textured crop, pushed up a little at the front.
    hair("messy",
         lambda ph, th: 0.006 + 0.012 * top_of(ph, th) + 0.008 * top_of(ph, th) * front_of(ph, th),
         fields=[dict(row=0.011, col=0.0095, len=0.05, len_j=0.3, w=0.013, wob=24, bend=30, segs=3,
                      flow=f_mix(whorl, f_comb((0.3, 0.0, 1.0)), lambda ph, th, t: 0.6 * top_of(ph, th, 0.5, 0.9)),
                      lift=0.005, tip_h=0.003, tip=0.2)],
         edge=6.0)

    # Quiff: the front swept up and back, short at the sides.
    def quiff_t(ph, th):
        x, y, z = sph(ph, th)
        return 0.005 + 0.012 * smooth(0.3, 0.8, y) + 0.026 * smooth(0.45, 0.9, y) * smooth(-0.1, 0.6, z)
    hair("quiff", quiff_t,
         fields=[dict(row=0.014, col=0.011, len=0.075, len_j=0.15, w=0.017, wob=7, bend=10, over=2, segs=5,
                      where=lambda ph, th: sph(ph, th)[1] > 0.55,
                      flow=f_back(0.0, 0.25), lift=0.005, tip_h=0.002),
                 dict(row=0.012, col=0.011, len=0.04, len_j=0.2, w=0.014, wob=10, segs=3,
                      where=lambda ph, th: sph(ph, th)[1] <= 0.55,
                      flow=f_back(0.75), lift=0.003)])

    # Shaggy: medium length, loose, half over the ears, onto the neck.
    hair("shaggy",
         lambda ph, th: 0.012 + 0.008 * top_of(ph, th),
         cover=lambda a: curve([(0, 14), (40, 16), (62, 10), (80, 12), (100, 16), (120, 8), (180, 5)], a),
         fields=[dict(row=0.014, col=0.011, len=0.085, len_j=0.3, w=0.016, wob=20, bend=35, over=3, segs=5,
                      flow=f_mix(f_whorl(170.0, 18.0), f_comb((0.6, -0.3, 0.3)), lambda ph, th, t: 0.5 * front_of(ph, th) * top_of(ph, th)),
                      lift=0.005, tip_h=0.003, taper=0.5,
                      free=dict(len=0.012, flip=35, down=0.25, out=0.009, segs=3))],
         edge=4.0)

    # Mop: long all over, a heavy fringe to the brows, over the ears.
    hair("mop",
         lambda ph, th: 0.016 + 0.008 * top_of(ph, th),
         cover=lambda a: curve([(0, 26), (45, 28), (65, 24), (80, 26), (100, 30), (120, 10), (180, 5)], a),
         fields=[dict(row=0.018, col=0.012, len=0.1, len_j=0.15, w=0.02, wob=9, bend=14, over=3, segs=6,
                      flow=f_whorl(175.0, 14.0), lift=0.004, tip_h=0.001, taper=0.6)],
         edge=4.0)

    # Flow: hockey hair. Combed back off the forehead, long, turning out over the ears and
    # flipping up at the neck (what sticks out under a helmet).
    def flow_field(back, free):
        return dict(row=0.015, col=0.011, len=0.11, len_j=0.15, w=0.017, wob=8, bend=12, over=2, segs=6, hang_max=0.03,
                    where=lambda ph, th: (abs(wrap(ph)) > 112) == back,
                    flow=f_mix(f_back(0.25), f_comb((0.0, -1.0, -0.5)), lambda ph, th, t: side_of(ph, th, 0.6, 0.95)),
                    lift=0.004, tip_h=0.002, taper=0.55, free=free)
    hair("flow",
         lambda ph, th: 0.011 + 0.007 * top_of(ph, th) + 0.004 * back_of(ph, th),
         cover=lambda a: curve([(0, 0), (50, 0), (62, 6), (80, 10), (100, 18), (120, 10), (180, 5)], a),
         fields=[flow_field(False, dict(len=0.02, flip=30, down=0.25, back=0.3, out=0.012, segs=3)),
                 flow_field(True, dict(len=0.045, flip=65, down=0.15, out=0.012, segs=5))],
         edge=4.0)

    # Mullet: a short crop on top and at the sides, long down the back of the neck.
    hair("mullet",
         lambda ph, th: 0.006 + 0.011 * top_of(ph, th) + 0.008 * back_of(ph, th, 0.3, 0.8),
         cover=lambda a: curve([(0, 0), (110, 0), (125, 5), (180, 5)], a),
         fields=[dict(row=0.011, col=0.0095, len=0.045, len_j=0.3, w=0.013, wob=22, bend=25, segs=3,
                      where=lambda ph, th: back_of(ph, th, 0.25, 0.6) * (1 - top_of(ph, th, 0.5, 0.8)) < 0.5,
                      flow=f_mix(whorl, f_comb((0.2, 0.0, 1.0)), lambda ph, th, t: 0.6 * top_of(ph, th, 0.5, 0.9)),
                      lift=0.005, tip_h=0.003, tip=0.2, hang=False),
                 dict(row=0.013, col=0.01, len=0.07, len_j=0.2, w=0.016, wob=8, bend=14, over=2, segs=4,
                      where=lambda ph, th: back_of(ph, th, 0.25, 0.6) * (1 - top_of(ph, th, 0.5, 0.8)) >= 0.5,
                      flow=f_comb((0.0, -1.0, -0.2)), lift=0.004, taper=0.6,
                      free=dict(len=0.075, down=0.3, back=0.35, flip=25, out=0.01, segs=5))],
         edge=5.0)

    # Slicked back: close to the head, combed straight back.
    hair("slick",
         lambda ph, th: 0.005 + 0.005 * top_of(ph, th),
         fields=[dict(row=0.016, col=0.0095, len=0.1, len_j=0.1, w=0.014, wob=4, bend=6, over=1, segs=6,
                      flow=f_mix(f_back(0.15), f_back(0.8), lambda ph, th, t: side_of(ph, th, 0.5, 0.95)),
                      lift=0.002, tip_h=0.001, arch=0.12, taper=0.7, hang=False, shade=(0.9, 1.0))],
         edge=5.0, shade=0.72)

    # Side part: neat, combed across from a part on the left.
    hair("part",
         lambda ph, th: 0.006 + 0.011 * top_of(ph, th),
         fields=[dict(row=0.014, col=0.01, len=0.07, len_j=0.15, w=0.015, wob=6, bend=12, over=2, segs=5,
                      flow=f_part(0.036, 0.45, 0.35), lift=0.004, tip_h=0.002, hang=False)],
         edge=6.0)

    # Curls: short, tight, all over.
    hair("curly",
         lambda ph, th: 0.013 + 0.012 * top_of(ph, th) + 0.003 * noise.noise(Vector(sph(ph, th)) * 9.0),
         cover=lambda a: curve([(0, 5), (60, 3), (100, 5), (180, 3)], a),
         fields=[dict(row=0.0105, col=0.0095, len=0.04, len_j=0.3, w=0.012, wob=180, bend=150, curl=70, turns=1.5, segs=5,
                      flow=whorl, lift=0.007, tip_h=0.004, over=4, tip=0.3, taper=0.6, hang=False)],
         edge=4.0, shade=0.55)

    # Afro: a round mass.
    def afro_t(ph, th):
        return 0.034 + 0.014 * top_of(ph, th, 0.0, 0.8) + 0.004 * noise.noise(Vector(sph(ph, th)) * 7.0)
    hair("afro", afro_t,
         cover=lambda a: curve([(0, 4), (60, 6), (100, 10), (180, 4)], a),
         fields=[dict(row=0.013, col=0.012, len=0.035, len_j=0.3, w=0.014, wob=180, bend=160, curl=80, turns=1.5, segs=4,
                      flow=whorl, lift=0.006, tip_h=0.004, over=5, tip=0.35, taper=0.6, hang=False)],
         edge=3.0, shade=0.52, step=4.0)

    # High fade: skin at the sides, a short flat crop on top.
    hair("fade",
         lambda ph, th: 0.002 + 0.011 * top_of(ph, th, 0.45, 0.85),
         hairline=lambda a: curve([(0, 0), (40, 0), (55, -8), (70, -32), (100, -22), (125, -34), (180, -30)], a),
         fields=[dict(row=0.01, col=0.009, len=0.03, len_j=0.25, w=0.012, wob=20, bend=20, segs=3,
                      where=lambda ph, th: sph(ph, th)[1] > 0.5,
                      flow=f_mix(whorl, f_comb((0.0, 0.0, 1.0)), 0.5), lift=0.004, tip_h=0.003, tip=0.25, over=1)],
         edge=16.0, shade=0.8)

    # Mohawk: a crest standing up down the middle, the sides buzzed.
    def strip(ph, th):
        return (0.02 - abs(dirv(ph, th).x) * 0.095) / DEG
    hair("mohawk",
         lambda ph, th: 0.03 + 0.022 * top_of(ph, th, 0.1, 0.9),
         mask=strip, base="buzz", edge=7.0, shade=0.7, step=2.5,
         hairline=lambda a: curve([(0, -4), (30, -4), (150, -14), (180, -14)], a),
         fields=[dict(row=0.008, col=0.007, len=0.026, len_j=0.3, w=0.012, wob=22, bend=10, segs=3,
                      flow=lambda K, p, n, ph, th, t: Vector((-1.0 if p.x > 0 else 1.0, 0.0, -0.45)),
                      lift=0.003, tip_h=0.014, over=1, tip=0.12, taper=0.3, hang=False, inset=0.5)])

    # Balding: gone on top, a short ring around the sides and back.
    hair("balding",
         lambda ph, th: 0.0045,
         mask=lambda ph, th: th - curve([(0, 200), (38, 200), (52, 74), (90, 66), (180, 70)], abs(wrap(ph))),
         fields=[dict(row=0.011, col=0.0095, len=0.03, len_j=0.25, w=0.012, wob=12, segs=3,
                      flow=f_comb((0.0, -1.0, -0.5)), lift=0.003, tip_h=0.002, over=1, hang=False)],
         edge=9.0, shade=0.8, women=False)

    # Tied back: what a ponytail, a braid and a bun are gathered from.
    def tied(name, gather, extra, **kw):
        hair(name,
             lambda ph, th: 0.006 + 0.004 * top_of(ph, th),
             fields=[dict(row=0.016, col=0.0095, len=0.12, len_j=0.1, w=0.014, wob=4, bend=6, over=1, segs=6,
                          flow=f_toward(*gather), lift=0.002, tip_h=0.001, arch=0.12, taper=0.75, hang=False,
                          shade=(0.9, 1.0))],
             edge=5.0, shade=0.72, extra=extra, **kw)
    tied("ponytail", (180.0, 100.0), ponytail())
    tied("braid", (180.0, 104.0), ponytail(gather=(180.0, 104.0), length=0.24, radius=0.018, braided=True), men=False)
    tied("topknot", (180.0, 58.0), bun())

    # Long: straight, parted in the middle, down past the shoulders at the back.
    def long_flow(K, p, n, ph, th, t):
        k = smooth(0.0, 0.5, -n.z)
        return Vector((1.0 if p.x > 0 else -1.0, -1.0, -0.55)).lerp(Vector((0.0, -1.0, 0.0)), k)
    hair("long",
         lambda ph, th: 0.011 + 0.006 * top_of(ph, th),
         cover=lambda a: curve([(0, 0), (40, 4), (62, 16), (80, 24), (100, 34), (120, 14), (180, 5)], a),
         fields=[dict(row=0.016, col=0.011, len=0.13, len_j=0.1, w=0.018, wob=5, bend=8, over=2, segs=6,
                      flow=long_flow, lift=0.003, taper=0.7,
                      free=dict(len=0.11, down=0.4, back=0.22, out=0.012, segs=7))],
         edge=4.0, men=False)

    # Bob: one length to the jaw all the way round, over the ears, swept off the forehead.
    hair("bob",
         lambda ph, th: 0.014 + 0.007 * top_of(ph, th),
         cover=lambda a: curve([(0, 2), (30, 8), (48, 30), (64, 30), (80, 36), (100, 42), (120, 16), (180, 5)], a),
         fields=[dict(row=0.017, col=0.011, len=0.125, len_j=0.06, w=0.02, wob=4, bend=6, over=2, segs=6,
                      flow=f_mix(f_whorl(178.0, 12.0), f_comb((1.0, -0.6, 0.2)), lambda ph, th, t: 0.75 * front_of(ph, th, 0.2, 0.7) * top_of(ph, th, 0.3, 0.7)),
                      lift=0.003, taper=0.8, tip=0.3, hang_max=0.012,
                      free=dict(len=0.012, down=0.6, out=0.012, segs=3))],
         edge=4.0, men=False)


_hairstyles()

# --- Facial hair -----------------------------------------------------------------------------
# On the face chart (rays from the middle of the jaw) rows run level across the face: the
# base of the nose is about 100 degrees down, the lips' seam 111, the bottom of the lower lip
# 117, the chin 124-132, the jaw's edge 130 from the chin round to its corner (60-70 degrees
# around from the middle), the ear 80 and beyond. Zones are written in those terms: `a` is
# the angle around from the middle of the face, either side.

CHEEK = [(0, 100.8), (14, 103.0), (22, 108.0), (34, 108.5), (48, 103.0), (58, 94.0), (66, 85.0), (74, 78.0)]
NECK = [(0, 150.0), (30, 147.0), (50, 143.0), (65, 139.0), (80, 132.0)]


def z_box(a, th, a0, a1, t0, t1):
    return min(a - a0, a1 - a, th - t0, t1 - th)


def z_must(a, th, w=17.0, droop=3.5):
    """The moustache: under the nose, out past the corners of the mouth, ends turned down."""
    top = 100.8 + 2.6 * (a / w) ** 2
    bot = 107.3 + droop * smooth(7.0, w, a)
    return min(th - top, bot - th, w - a)


def z_mouth(a, th):
    """> 0 outside the lips."""
    return max(a - 14.0, 107.3 - th, th - 117.6)


def z_rear(a, th):
    """The beard's back edge: in front of the ear, round the corner of the jaw under it."""
    return lerp(75.0, 81.0, smooth(100.0, 116.0, th)) - a


def z_full(a, th, neck=0.0):
    return min(th - curve(CHEEK, a), curve(NECK, a) + neck - th, z_rear(a, th), z_mouth(a, th))


def z_bars(a, th, lo=132.0):
    """Down past each corner of the mouth."""
    return z_box(a, th, 13.6, 20.5, 104.5, lo)


def z_chin(a, th, w=18.0):
    return min(w * lerp(1.0, 0.8, smooth(128.0, 148.0, th)) - a, th - 118.2, 148.0 - th)


def z_strap(a, th):
    """A band along the jaw's edge from ear to ear."""
    band = min(th - lerp(125.0, 122.0, smooth(20.0, 60.0, a)), curve(NECK, a) - 6.0 - th, z_rear(a, th))
    up = min(a - 66.0, z_rear(a, th), th - curve(CHEEK, a), 126.0 - th)
    return max(band, up)


def z_chops(a, th):
    """Mutton chops: the sideburns carried down the cheeks to the jaw, the chin bare."""
    front = lerp(40.0, 24.0, smooth(104.0, 128.0, th))
    return min(th - curve(CHEEK, a), curve(NECK, a) - 5.0 - th, z_rear(a, th), a - front)


def zone(fn, **kw):
    return lambda K, ph, th: fn(abs(wrap(ph)), th, **kw)


def f_beard(K, p, n, ph, th, t):
    """Down the face; back along the underside of the jaw."""
    return Vector((0.0, -1.0, 0.12)).lerp(Vector((0.0, -0.25, -1.0)), smooth(0.35, 0.8, -n.y))


def f_must(K, p, n, ph, th, t):
    """Out from the middle of the lip, turning down."""
    return Vector((1.0 if p.x > 0 else -1.0, -0.35 - 0.5 * smooth(8.0, 17.0, abs(wrap(ph))), 0.0))


def facial(name, thick, zone_fn, fields, **kw):
    kw.setdefault("edge", 2.5)
    STYLES[name] = Style(thick, fields=fields, zone=zone_fn, chart="face", women=False, helm=False, **kw)
    FACIAL.append(name)


def beard_locks(length=0.02, w=0.008, sp=0.0065, lift=0.002, **kw):
    d = dict(row=sp, col=sp, len=length, len_j=0.3, w=w, wob=16, bend=20, segs=3, inset=0.6, over=1.5,
             flow=f_beard, lift=lift, tip_h=0.002, tip=0.25, hang=False, th0=70.0)
    d.update(kw)
    return d


def must_locks(**kw):
    d = dict(row=0.0032, col=0.0036, len=0.017, len_j=0.2, w=0.0055, wob=8, bend=10, segs=3, inset=0.3, over=1.2,
             flow=f_must, lift=0.0015, tip_h=0.001, tip=0.25, hang=False, th0=96.0)
    d.update(kw)
    return d


def handlebars(K, geo, rng, helm):
    """The moustache's ends twisted out and curled up."""
    for sgn in (1.0, -1.0):
        at = K.S(sgn * 17.5, 108.6, 0.004)
        pts = [at]
        d = Vector((sgn * 0.85, -0.25, -0.3)).normalized()
        for k in range(9):
            d = rot(d, Vector((0.0, 0.0, 1.0)), sgn * math.radians(26.0))
            pts.append(pts[-1] + d * 0.0042)
        tube(geo, pts, lambda t: 0.0028 * lerp(1.0, 0.25, t), rng, sides=5, shade=(0.9, 1.0))


def _facial():
    def chin_heavy(base, chin, cheek=0.0):
        """Thickness: `base` everywhere, up to `chin` more on the chin, `cheek` more on the jaw."""
        def f(ph, th):
            a = abs(wrap(ph))
            return base + chin * smooth(114.0, 130.0, th) * (1.0 - smooth(18.0, 45.0, a)) + cheek * smooth(108.0, 128.0, th)
        return f

    over_lip = lambda ph, th: th <= 108.5 and abs(wrap(ph)) < 14.5
    not_lip = lambda ph, th: not over_lip(ph, th)
    facial("beard", chin_heavy(0.0045, 0.006, 0.002), zone(z_full),
           [beard_locks(where=not_lip), must_locks(where=over_lip)])
    facial("playoff", chin_heavy(0.008, 0.02, 0.008), zone(z_full, neck=5.0),
           [beard_locks(length=0.034, w=0.011, sp=0.0075, lift=0.004, wob=24, bend=30, over=4, segs=4, where=not_lip,
                        free=dict(len=0.012, down=0.5, out=0.01, segs=2)),
            must_locks(where=over_lip, len=0.02, w=0.007, lift=0.003)], edge=3.5)
    facial("chinstrap", chin_heavy(0.004, 0.002), zone(z_strap), [beard_locks(length=0.014, sp=0.006)])
    facial("chops", chin_heavy(0.005, 0.0, 0.003), zone(z_chops), [beard_locks(length=0.018)])
    facial("goatee", chin_heavy(0.0045, 0.006),
           lambda K, ph, th: max(z_must(abs(wrap(ph)), th), z_bars(abs(wrap(ph)), th, 126.0), z_chin(abs(wrap(ph)), th)),
           [beard_locks(length=0.016, sp=0.0055, where=lambda ph, th: th > 109.0),
            must_locks(where=lambda ph, th: th <= 109.0 and abs(wrap(ph)) < 13.0)], step=1.6, edge=2.0)
    facial("moustache", lambda ph, th: 0.0042, zone(z_must), [must_locks()], step=1.25, edge=1.6)
    facial("horseshoe", lambda ph, th: 0.004,
           lambda K, ph, th: max(z_must(abs(wrap(ph)), th), z_bars(abs(wrap(ph)), th, 134.0)),
           [must_locks(where=lambda ph, th: th <= 108.5 and abs(wrap(ph)) < 13.0),
            beard_locks(length=0.014, sp=0.0048, w=0.006, where=lambda ph, th: abs(wrap(ph)) >= 13.0)], step=1.25, edge=1.6)
    facial("handlebar", lambda ph, th: 0.0045, zone(z_must, w=18.0, droop=1.5), [must_locks(len=0.02)],
           step=1.25, edge=1.6, extra=handlebars)
    facial("soulpatch", lambda ph, th: 0.0035, zone(z_box, a0=-1.0, a1=5.5, t0=117.8, t1=124.0),
           [beard_locks(length=0.01, sp=0.004, w=0.005)], step=1.25, edge=1.6)


_facial()


# --- Blender ---------------------------------------------------------------------------------

def lab_scene():
    return bpy.data.scenes.get(LAB) or bpy.data.scenes.new(LAB)


def material():
    m = bpy.data.materials.get("HairLabMat")
    if m:
        return m
    m = bpy.data.materials.new("HairLabMat")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[2].default_value = (0.26, 0.15, 0.08, 1.0)
    nt.links.new(col.outputs["Color"], mix.inputs[1])
    nt.links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    m.use_backface_culling = False
    return m


def skin_material():
    m = bpy.data.materials.get("HairLabSkin")
    if m:
        return m
    m = bpy.data.materials.new("HairLabSkin")
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.78, 0.56, 0.44, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    return m


def to_object(name, geo, hd, at):
    """A mesh object in head widths, standing at `at` (Blender) at the head's size."""
    sc = lab_scene()
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(g(p / hd.width)) for p in geo.v], [], geo.f)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        uv.data[lp.index].uv = geo.uv[lp.vertex_index]
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, s in enumerate(geo.col):
        s = max(0.0, min(1.0, s))
        ca.data[i].color = (s, s, s, 1.0)
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(material())
    ob = bpy.data.objects.new(name, me)
    ob.location = g(hd.top) + at
    ob.scale = (hd.width,) * 3
    sc.collection.objects.link(ob)
    return ob


def lab_head(body, key):
    """The lab's own copy of a head mesh (head and neck only, skin colored), made once."""
    name = "lab_%s_%s" % (body, key)
    me = bpy.data.meshes.get(name)
    if me:
        return me
    src = bpy.data.objects[HEADS[body][key]]
    top = head(body).top
    vs = [src.matrix_world @ v.co for v in src.data.vertices]
    keep = [p.vertices[:] for p in src.data.polygons
            if all(gv(vs[i]).y - top.y > -0.34 and abs(vs[i].x) < 0.14 for i in p.vertices)]
    used = sorted({i for f in keep for i in f})
    at = {i: k for k, i in enumerate(used)}
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(vs[i]) for i in used], [], [tuple(at[i] for i in f) for f in keep])
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    if key == "obj":
        me.materials.append(skin_material())
    return me


def stand_head(body, at, tag):
    """A copy of the body's head in the lab at `at`."""
    sc = lab_scene()
    for key in ("obj", "eyes"):
        name = "head_%s_%s" % (tag, key)
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        ob = bpy.data.objects.new(name, lab_head(body, key))
        ob.location = at
        sc.collection.objects.link(ob)


def variants(name):
    """(body, helm) pairs a style is built for."""
    st = STYLES[name]
    out = []
    for body in ("male", "female"):
        if (body == "male" and not st.men) or (body == "female" and (not st.women or st.chart == "face")):
            continue
        out.append((body, False))
        if st.helm and st.chart == "scalp":
            out.append((body, True))
    return out


def build_all(export=False, only=None, bodies=("male", "female"), helm=True, gap=0.34):
    names = [n for n in HAIR + FACIAL if only is None or n in only]
    made = []
    for k, name in enumerate(names):
        for body, hm in variants(name):
            if body not in bodies or (hm and not helm):
                continue
            at = Vector((k * gap, (0.5 if body == "female" else 0.0) + (1.0 if hm else 0.0), 0.0))
            tag = "%s%s%s" % (name, "" if body == "male" else "_" + body, "_helm" if hm else "")
            geo = build_style(name, body, hm)
            stand_head(body, at, tag)
            made.append(to_object(tag, geo, head(body), at))
            print("%s: %d tris" % (tag, len(geo.f)))
    if export:
        export_glb(made)
        write_strands()
    return made


def export_glb(objects):
    sc = lab_scene()
    win = bpy.context.window
    was = win.scene
    win.scene = sc
    keep = [(o, o.location.copy(), o.scale.copy()) for o in objects]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.location = (0, 0, 0)
        o.scale = (1, 1, 1)
        o.select_set(True)
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, use_active_scene=True,
                              export_apply=True, export_yup=True, export_materials="NONE",
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_normals=True, export_texcoords=True)
    for o, loc, scl in keep:
        o.location, o.scale = loc, scl
    win.scene = was
    print("wrote", OUT_GLB)


def write_strands(w=256, h=512, seed=7):
    """The strand grain: light streaks running along v, tiling both ways. White strands on
    black, as the game expects (it squeezes them into a narrow band)."""
    rs = np.random.RandomState(seed)
    img = np.zeros((h, w))
    for octave, (cells, amp) in enumerate(((16, 0.5), (48, 0.35), (128, 0.25))):
        base = rs.rand(cells)
        x = np.arange(w) / w * cells
        i0 = np.floor(x).astype(int) % cells
        f = x - np.floor(x)
        f = f * f * (3 - 2 * f)
        line = base[i0] * (1 - f) + base[(i0 + 1) % cells] * f
        # Each strand wanders a little along its length.
        for y in range(h):
            shift = int(round(math.sin(2 * math.pi * (y / h) * (octave + 1) + octave) * w * 0.012))
            img[y] += np.roll(line, shift) * amp
    img += rs.rand(h, w) * 0.06
    img = (img - img.min()) / (img.max() - img.min())
    px = np.ones((h, w, 4), dtype=np.float32)
    for c in range(3):
        px[:, :, c] = img
    im = bpy.data.images.new("hair_strands", w, h, alpha=False)
    im.pixels.foreach_set(px.ravel())
    os.makedirs(os.path.dirname(TEX_OUT), exist_ok=True)
    im.filepath_raw = TEX_OUT
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("wrote", TEX_OUT)


def contact_sheet(names, path, views=((0.5, -1.0, 0.12), (1.0, 0.0, 0.05), (-0.55, 1.0, 0.2)), size=340, span=0.36,
                  body="male", suffix=""):
    """Renders each named style (as it stands in the lab) from `views` into one picture:
    a row per style."""
    sc = lab_scene()
    win = bpy.context.window
    was = win.scene
    win.scene = sc
    cam = bpy.data.objects.get("HairLabCam")
    if cam is None:
        cam = bpy.data.objects.new("HairLabCam", bpy.data.cameras.new("HairLabCam"))
        sc.collection.objects.link(cam)
        sun = bpy.data.objects.new("HairLabSun", bpy.data.lights.new("HairLabSun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), 0.0, math.radians(25))
        sc.collection.objects.link(sun)
        sc.world = bpy.data.worlds.new("HairLabWorld")
        sc.world.use_nodes = True
        sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.33, 0.35, 0.4, 1.0)
        sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    sc.camera = cam
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sheet = np.zeros((size * len(names), size * len(views), 4), dtype=np.float32)
    tmp = os.path.join(bpy.app.tempdir, "hairlab_tile.png")
    for r, name in enumerate(names):
        tag = name + ("" if body == "male" else "_" + body) + suffix
        show = {tag, "head_%s_obj" % tag, "head_%s_eyes" % tag, "HairLabSun"}
        for o in sc.objects:
            o.hide_render = o.name not in show
        ob = bpy.data.objects[tag]
        mid = ob.location + Vector((0.0, 0.0, -0.11))
        for c, v in enumerate(views):
            d = Vector(v).normalized()
            cam.location = mid + d * 2.0
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            im = bpy.data.images.load(tmp)
            px = np.array(im.pixels[:], dtype=np.float32).reshape(size, size, 4)
            bpy.data.images.remove(im)
            y0 = size * (len(names) - 1 - r)
            sheet[y0:y0 + size, c * size:(c + 1) * size] = px
    out = bpy.data.images.new("hairlab_sheet", size * len(views), size * len(names))
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    for o in sc.objects:
        o.hide_render = False
    win.scene = was
    return path
