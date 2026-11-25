"""The outdoor rink's warming hut: our own log cabin, built here from nothing.

Run it in the live Blender (it works in its own scene, "HutLab", and leaves the others be):

    ns = {"__name__": "hut", "__file__": r"<project>\\tools\\blender\\hut.py"}
    exec(open(ns["__file__"]).read(), ns); ns["main"]()

It writes assets/hut/:
    hut.glb     one mesh, front toward Blender's -Y, the ground at z = 0, in meters, plus two
                empties: `lamp` (the lantern by the door) and `smoke` (the chimney's mouth)
    wood.jpg    tiling wood grain, pale: the mesh's vertex colors tint it (logs, planks, paint)
    stone.jpg   tiling fieldstone, for the footing and the chimney

The file carries only the materials' names; the game puts its own on (ArenaOutdoor._hut):
    HutWood, HutStone  the pictures above times the vertex color
    HutPaint           the vertex color alone (sign letters, sticks, skates, iron)
    HutSnow            the snow on the roof and round the walls: the vertex color alone (white,
                       bluer in its hollows; the bank's rim is the ground's own color)
    HutGlow            the window panes and the lantern: lit after dark

The hut: saddle-notched log walls on a fieldstone footing, a snowed-over roof whose front
slope runs out over a plank porch, a stone chimney on one end, a red plank door, three
windows, a bench, a woodpile, sticks and skates by the door, and a sign on the porch beam.
"""

import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "hut")
SCENE = "HutLab"
MATS = ["HutWood", "HutStone", "HutPaint", "HutSnow", "HutGlow"]
WOOD, STONE, PAINT, SNOW, GLOW = range(5)
TEX = 512

# --- The hut's measures (m) -------------------------------------------------------------

HX, HY = 2.8, 1.9            # half-size of the log walls, to the logs' center lines
BASE = 0.35                  # the top of the footing, and the porch floor
LOG_R = 0.13
COURSE = 0.24                # a log's rise up the wall (they bed into each other a little)
COURSES = 11
NOTCH = 0.32                 # how far the logs run on past the corners
PLATE = 3.15                 # the roof's top surface over the front and back walls
TP = math.tan(math.radians(38.0))      # the roof's pitch
TPP = math.tan(math.radians(10.0))     # the porch roof's
PORCH = 1.8                  # the porch's depth: its posts stand at y = -HY - PORCH
POST_Y = -HY - PORCH
ROOF_X = HX + 0.42           # the roof's half-length
ROOF_T = 0.07                # its boards' thickness
BACK = HY + 0.55             # the back eave
FRONT = POST_Y - 0.25        # the porch eave
POSTS = (-2.65, -0.95, 0.95, 2.65)
DOOR = (-0.5, 0.5, BASE, 2.4)                       # along the wall from, to; z from, to
WIN_Z = (1.2, 2.2)
FRONT_WINDOWS = ((-2.1, -1.1), (1.1, 2.1))
SIDE_WINDOW = (-0.5, 0.5)                           # in the end wall away from the chimney
CHIMNEY_Y = 0.2
CHIMNEY_TOP = 5.65
SIGN = "WARMING HUT"


def srgb(r, g, b):
    """A color given as on screen, as the linear one a vertex color holds."""
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in (r, g, b))


LOG = srgb(0.78, 0.53, 0.31)
LOG_END = srgb(0.93, 0.76, 0.52)
PLANK = srgb(0.62, 0.47, 0.34)
DARK_WOOD = srgb(0.36, 0.25, 0.18)
GABLE = srgb(0.66, 0.43, 0.25)
RED = srgb(0.66, 0.13, 0.10)
FIREWOOD = srgb(0.42, 0.31, 0.22)
STONE_TINT = srgb(0.92, 0.9, 0.88)
WHITE = (1.0, 1.0, 1.0)
CREAM = srgb(0.96, 0.9, 0.74)
IRON = srgb(0.1, 0.1, 0.11)
ICE = srgb(0.82, 0.91, 1.0)
WARM = srgb(1.0, 0.78, 0.45)
HOLLOW = srgb(0.8, 0.85, 0.95)       # the snow's thin places
GROUND = srgb(0.9, 0.92, 0.96)       # the rink's lying snow (ArenaOutdoor._ground), which the drift fades into
GROUND_Z = -0.07                     # and its height, a hair over it


def roof_z(y):
    """The roof's top surface over `y`: the two slopes, and the porch roof past the front wall."""
    if y >= -HY:
        return PLATE + (HY - abs(y)) * TP
    return PLATE + (y + HY) * TPP


def wobble(x, y, seed):
    """Smooth noise, 0..1, from a few sines."""
    r = random.Random(seed)
    t = 0.0
    for k in range(4):
        a = r.uniform(0, math.tau)
        f = r.uniform(0.5, 1.8) * (1.0 + 0.6 * k)
        t += math.sin((x * math.cos(a) + y * math.sin(a)) * f + r.uniform(0, math.tau)) / (1.0 + 0.5 * k)
    return 0.5 + 0.5 * max(-1.0, min(1.0, t / 2.2))


# --- Building: faces gathered part by part, made into one mesh at the end ----------------

class Build:
    def __init__(self, seed=5):
        self.v, self.f, self.uv, self.col, self.mat = [], [], [], [], []
        self.rng = random.Random(seed)

    def tint(self, col, by=0.08):
        """`col` a little lighter or darker, so no two boards match."""
        k = 1.0 + self.rng.uniform(-by, by)
        return tuple(min(1.0, c * k) for c in col)

    def poly(self, pts, uvs, col, mat, facing=None):
        """One face, in one color or one per corner. `facing`: a direction its front should
        look (it's turned over if not)."""
        pts = [Vector(p) for p in pts]
        if facing is not None and normal(pts).dot(Vector(facing)) < 0.0:
            pts.reverse()
            uvs = list(reversed(uvs))
            if isinstance(col[0], tuple):
                col = list(reversed(col))
        i = len(self.v)
        self.v.extend(pts)
        self.f.append(list(range(i, i + len(pts))))
        self.uv.append(list(uvs))
        self.col.append(col)
        self.mat.append(mat)

    def hexa(self, p, col, mat=WOOD, grain=0, scale=(1.5, 0.75), xf=None, off=None):
        """A six-faced block from its 8 corners (4 round the bottom, the 4 above them).
        `grain`: the axis (0, 1, 2) the picture's grain runs along; `xf` moves it after;
        `off`: where in the picture it starts (its own spot, unless blocks should run on)."""
        p = [Vector(q) for q in p]
        off = off or (self.rng.random(), self.rng.random())
        out = [xf @ q for q in p] if xf is not None else p
        mid = sum(out, Vector()) / 8.0
        for ids in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            local = [p[i] for i in ids]
            n = normal(local)
            if n.length < 1e-9:
                continue
            drop_axis = max(range(3), key=lambda i: abs(n[i]))
            axes = [i for i in range(3) if i != drop_axis]
            if grain in axes:
                u, v = grain, next(i for i in axes if i != grain)
            else:
                u, v = axes
            uvs = [(q[u] / scale[0] + off[0], q[v] / scale[1] + off[1]) for q in local]
            world = [out[i] for i in ids]
            self.poly(world, uvs, col, mat, facing=sum(world, Vector()) / 4.0 - mid)

    def box(self, lo, hi, col, mat=WOOD, grain=0, scale=(1.5, 0.75), xf=None):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        self.hexa([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                   (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], col, mat, grain, scale, xf)

    def log(self, p0, p1, r, col, mat=WOOD, sides=8, cap=None, r1=None, caps=True):
        """A round timber from p0 to p1 (radius r, or r tapering to r1), capped in `cap`."""
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        length = axis.length
        axis.normalize()
        a = axis.cross(Vector((0, 0, 1)))
        if a.length < 1e-4:
            a = Vector((1, 0, 0))
        a.normalize()
        b = axis.cross(a)
        r1 = r if r1 is None else r1
        ou, ov = self.rng.random(), self.rng.random()
        ring = lambda p, rad: [p + (a * math.cos(math.tau * i / sides) + b * math.sin(math.tau * i / sides)) * rad
                               for i in range(sides)]
        q0, q1 = ring(p0, r), ring(p1, r1)
        for i in range(sides):
            j = (i + 1) % sides
            pts = [q0[i], q0[j], q1[j], q1[i]]
            uvs = [(ou, ov + i / sides), (ou, ov + (i + 1) / sides),
                   (ou + length / 1.5, ov + (i + 1) / sides), (ou + length / 1.5, ov + i / sides)]
            out = (q0[i] + q0[j]) * 0.5 - p0
            if r1 < 1e-6:
                pts, uvs = pts[:3], uvs[:3]
            self.poly(pts, uvs, col, mat, facing=out)
        if caps:
            cap = cap or col
            for q, p, rad, way in ((q0, p0, r, -axis), (q1, p1, r1, axis)):
                if rad < 1e-6:
                    continue
                uvs = [(ou + 0.5 + 0.2 * math.cos(math.tau * i / sides), ov + 0.5 + 0.2 * math.sin(math.tau * i / sides))
                       for i in range(sides)]
                self.poly(q, uvs, cap, mat, facing=way)

    def mound(self, p0, p1, width, height, col=WHITE, mat=SNOW, n=4):
        """A rounded ridge of snow lying from p0 to p1."""
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        side = axis.cross(Vector((0, 0, 1))).normalized() * (width * 0.5)
        rows = []
        for t, k in ((0.0, 0.25), (0.1, 1.0), (0.9, 1.0), (1.0, 0.25)):
            c = p0 + axis * t
            rows.append([c - side * math.cos(math.pi * j / n) * (0.6 + 0.4 * k) + Vector((0, 0, math.sin(math.pi * j / n) * height * k))
                         for j in range(n + 1)])
        for i in range(len(rows) - 1):
            for j in range(n):
                pts = [rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]]
                mid = sum(pts, Vector()) / 4.0
                self.poly(pts, [(p.x * 0.5, p.y * 0.5) for p in pts], col, mat,
                          facing=mid - (p0 + p1) * 0.5 + Vector((0, 0, height)))

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.v], [], self.f)
        uv = me.uv_layers.new(name="UVMap")
        col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
        for fi, poly in enumerate(me.polygons):
            poly.material_index = self.mat[fi]
            poly.use_smooth = True
            for k, li in enumerate(poly.loop_indices):
                uv.data[li].uv = self.uv[fi][k]
                c = self.col[fi]
                col.data[li].color = (*(c[k] if isinstance(c[0], tuple) else c), 1.0)
        # Weld the parts' own seams, then keep hard edges hard: round timbers and the snow
        # shade smooth, boards don't.
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        for e in bm.edges:
            e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(math.pi) < math.radians(50.0)
        bm.to_mesh(me)
        bm.free()
        me.update()
        return me


def normal(pts):
    """A face's normal (Newell: fine for a bent quad or one with a doubled corner)."""
    n = Vector((0.0, 0.0, 0.0))
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
    return n


## Wall-local space: x along the wall, y out from it, z up.
FRONT_WALL = Matrix(((1, 0, 0, 0), (0, -1, 0, -HY), (0, 0, 1, 0), (0, 0, 0, 1)))
END_WALL = Matrix(((0, -1, 0, -HX), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))


# --- The parts ----------------------------------------------------------------------------

def footing(b):
    """Fieldstone under the log walls, down into the ground."""
    t = 0.2
    for lo, hi in (((-HX - t, -HY - t), (HX + t, -HY + t)), ((-HX - t, HY - t), (HX + t, HY + t)),
                   ((-HX - t, -HY + t), (-HX + t, HY - t)), ((HX - t, -HY + t), (HX + t, HY - t))):
        b.box((lo[0], lo[1], -0.4), (hi[0], hi[1], BASE - 0.06), b.tint(STONE_TINT), STONE, None, (1.2, 1.2))


def wall_logs(b, along, at, z, lo, hi, cuts):
    """One course: a log along x (or y) at `at`, left out where a door or window is."""
    spans = [(lo, hi)]
    for a0, a1, z0, z1 in cuts:
        if z0 - 0.07 < z < z1 + 0.07:
            spans = [s for s0, s1 in spans for s in ((s0, min(s1, a0)), (max(s0, a1), s1)) if s[1] - s[0] > 0.05]
    for s0, s1 in spans:
        p0, p1 = ((s0, at, z), (s1, at, z)) if along == 0 else ((at, s0, z), (at, s1, z))
        b.log(p0, p1, LOG_R * b.rng.uniform(0.96, 1.04), b.tint(LOG), cap=b.tint(LOG_END, 0.05))


def walls(b):
    front = [DOOR] + [(a0, a1, *WIN_Z) for a0, a1 in FRONT_WINDOWS]
    for i in range(COURSES):
        z = BASE + COURSE * (i + 0.5)
        wall_logs(b, 0, -HY, z, -HX - NOTCH, HX + NOTCH, front)
        wall_logs(b, 0, HY, z, -HX - NOTCH, HX + NOTCH, [])
    for i in range(COURSES + 1):
        z = BASE + COURSE * i
        wall_logs(b, 1, -HX, z, -HY - NOTCH, HY + NOTCH, [(*SIDE_WINDOW, *WIN_Z)])
        wall_logs(b, 1, HX, z, -HY - NOTCH, HY + NOTCH, [])


def window(b, a0, a1, xf):
    """A four-paned window in a wall: red frame and bars, the panes one glowing sheet."""
    z0, z1 = WIN_Z
    out, back = LOG_R + 0.04, -0.06
    for lo, hi, grain in (((a0 - 0.04, back, z0), (a0 + 0.07, out, z1), 2), ((a1 - 0.07, back, z0), (a1 + 0.04, out, z1), 2),
                          ((a0 - 0.04, back, z1 - 0.07), (a1 + 0.04, out, z1 + 0.04), 0)):
        b.box(lo, hi, b.tint(RED, 0.05), WOOD, grain, xf=xf)
    b.box((a0 - 0.1, back, z0 - 0.05), (a1 + 0.1, out + 0.07, z0 + 0.04), b.tint(RED, 0.05), WOOD, 0, xf=xf)
    b.box((a0, 0.0, z0), (a1, 0.02, z1), WARM, GLOW, None, (1.0, 1.0), xf=xf)
    mid, zm = (a0 + a1) * 0.5, (z0 + z1) * 0.5
    b.box((mid - 0.02, 0.02, z0), (mid + 0.02, 0.06, z1), RED, WOOD, 2, xf=xf)
    b.box((a0, 0.02, zm - 0.02), (a1, 0.06, zm + 0.02), RED, WOOD, 0, xf=xf)


def door(b):
    a0, a1, z0, z1 = DOOR
    xf = FRONT_WALL
    out = LOG_R + 0.04
    for lo, hi, grain in (((a0 - 0.05, -0.06, z0), (a0 + 0.07, out, z1), 2), ((a1 - 0.07, -0.06, z0), (a1 + 0.05, out, z1), 2),
                          ((a0 - 0.05, -0.06, z1 - 0.07), (a1 + 0.05, out, z1 + 0.06), 0)):
        b.box(lo, hi, b.tint(DARK_WOOD), WOOD, grain, xf=xf)
    # Five upright planks, two ledges and a brace between them.
    n = 5
    w = (a1 - a0 - 0.14) / n
    for i in range(n):
        x = a0 + 0.07 + w * i
        b.box((x + 0.004, 0.0, z0), (x + w - 0.004, 0.05, z1 - 0.07), b.tint(RED, 0.1), WOOD, 2, xf=xf)
    lo_z, hi_z = z0 + 0.28, z1 - 0.42
    for z in (lo_z, hi_z):
        b.box((a0 + 0.1, 0.05, z - 0.07), (a1 - 0.1, 0.085, z + 0.07), b.tint(RED, 0.1), WOOD, 0, xf=xf)
    b.hexa([(a0 + 0.1, 0.05, lo_z + 0.07), (a0 + 0.26, 0.05, lo_z + 0.07), (a0 + 0.26, 0.085, lo_z + 0.07), (a0 + 0.1, 0.085, lo_z + 0.07),
            (a1 - 0.26, 0.05, hi_z - 0.07), (a1 - 0.1, 0.05, hi_z - 0.07), (a1 - 0.1, 0.085, hi_z - 0.07), (a1 - 0.26, 0.085, hi_z - 0.07)],
           b.tint(RED, 0.1), WOOD, 2, xf=xf)
    # An iron latch and two strap hinges.
    b.box((a1 - 0.2, 0.05, 1.32), (a1 - 0.14, 0.12, 1.5), IRON, PAINT, None, xf=xf)
    for z in (lo_z, hi_z):
        b.box((a0 + 0.07, 0.085, z - 0.02), (a0 + 0.4, 0.1, z + 0.02), IRON, PAINT, None, xf=xf)


def gables(b):
    """Upright boards closing the roof's two ends, a batten over every seam."""
    z0 = BASE + COURSE * COURSES + 0.05
    w = 0.253
    n = round(2 * HY / w)
    for side in (-1.0, 1.0):
        x = side * HX
        for i in range(n):
            y0, y1 = -HY + 2 * HY * i / n, -HY + 2 * HY * (i + 1) / n
            t0, t1 = roof_z(y0) - ROOF_T, roof_z(y1) - ROOF_T
            if max(t0, t1) - z0 < 0.04:
                continue
            b.hexa([(x - 0.03, y0, z0), (x + 0.03, y0, z0), (x + 0.03, y1, z0), (x - 0.03, y1, z0),
                    (x - 0.03, y0, max(t0, z0)), (x + 0.03, y0, max(t0, z0)), (x + 0.03, y1, max(t1, z0)), (x - 0.03, y1, max(t1, z0))],
                   b.tint(GABLE, 0.1), WOOD, 2)
            if i and t0 - z0 > 0.06:
                o = x + side * 0.03
                b.box((min(o, o + side * 0.025), y0 - 0.025, z0), (max(o, o + side * 0.025), y0 + 0.025, t0 - 0.01),
                      b.tint(DARK_WOOD, 0.1), WOOD, 2)


def roof_line():
    return [BACK, 0.0, -HY, FRONT]


def roof(b):
    """The roof's boards (the snow lies over them), its end boards, eave boards and the porch rafters."""
    ys = roof_line()
    for y0, y1 in zip(ys, ys[1:]):
        z0, z1 = roof_z(y0), roof_z(y1)
        b.hexa([(-ROOF_X, y0, z0 - ROOF_T), (ROOF_X, y0, z0 - ROOF_T), (ROOF_X, y1, z1 - ROOF_T), (-ROOF_X, y1, z1 - ROOF_T),
                (-ROOF_X, y0, z0), (ROOF_X, y0, z0), (ROOF_X, y1, z1), (-ROOF_X, y1, z1)], b.tint(DARK_WOOD), WOOD, 0)
        for side in (-1.0, 1.0):
            xa, xb = sorted((side * ROOF_X, side * (ROOF_X + 0.04)))
            b.hexa([(xa, y0, z0 - 0.19), (xb, y0, z0 - 0.19), (xb, y1, z1 - 0.19), (xa, y1, z1 - 0.19),
                    (xa, y0, z0 + 0.02), (xb, y0, z0 + 0.02), (xb, y1, z1 + 0.02), (xa, y1, z1 + 0.02)], b.tint(DARK_WOOD), WOOD, 1)
    for y, d in ((BACK, 0.04), (FRONT, -0.04)):
        ya, yb = sorted((y, y + d))
        b.box((-ROOF_X - 0.04, ya, roof_z(y) - 0.12), (ROOF_X + 0.04, yb, roof_z(y) + 0.02), b.tint(DARK_WOOD), WOOD, 0)
    # Rafters over the porch, their tails showing at the eave.
    for i in range(8):
        x = -2.66 + 5.32 * i / 7.0
        za, zb = roof_z(-HY) - ROOF_T, roof_z(FRONT + 0.02) - ROOF_T
        b.hexa([(x - 0.035, -HY, za - 0.09), (x + 0.035, -HY, za - 0.09), (x + 0.035, FRONT + 0.02, zb - 0.09), (x - 0.035, FRONT + 0.02, zb - 0.09),
                (x - 0.035, -HY, za), (x + 0.035, -HY, za), (x + 0.035, FRONT + 0.02, zb), (x - 0.035, FRONT + 0.02, zb)],
               b.tint(GABLE), WOOD, 1)


def beam_z():
    """The porch beam's center line: under the rafters at the posts."""
    return roof_z(POST_Y) - ROOF_T - 0.09 - 0.085


def porch(b):
    # The floor: planks running out from the wall, a dark skirt under them.
    y0, y1 = POST_Y - 0.15, -HY
    n = 29
    x0, x1 = -HX - 0.1, HX + 0.1
    for i in range(n):
        xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
        b.box((xa + 0.005, y0 - b.rng.uniform(0.0, 0.025), BASE - 0.05), (xb - 0.005, y1, BASE), b.tint(PLANK, 0.12), WOOD, 1)
    b.box((x0 + 0.04, y0 + 0.04, -0.4), (x1 - 0.04, y1, BASE - 0.05), tuple(c * 0.45 for c in DARK_WOOD), WOOD, 0)
    # Posts, the beam on them, a knee brace each side of every post.
    zb = beam_z()
    b.log((-HX - 0.2, POST_Y, zb), (HX + 0.2, POST_Y, zb), 0.085, b.tint(LOG), cap=LOG_END)
    for x in POSTS:
        b.log((x, POST_Y, BASE), (x, POST_Y, zb), 0.075, b.tint(LOG), caps=False)
        for way in (-1.0, 1.0):
            if abs(x + way * 0.42) < HX:
                b.log((x, POST_Y, zb - 0.5), (x + way * 0.42, POST_Y, zb - 0.06), 0.04, b.tint(LOG), sides=6, caps=False)
    # Rails: across the two outer bays and down both ends, the middle bay open to the steps.
    runs = [((POSTS[0], POST_Y), (POSTS[1], POST_Y)), ((POSTS[2], POST_Y), (POSTS[3], POST_Y)),
            ((POSTS[0], POST_Y), (POSTS[0], -HY - LOG_R)), ((POSTS[3], POST_Y), (POSTS[3], -HY - LOG_R))]
    top, low = BASE + 0.9, BASE + 0.14
    for (xa, ya), (xb, yb) in runs:
        b.log((xa, ya, top), (xb, yb, top), 0.045, b.tint(LOG), sides=6, caps=False)
        b.log((xa, ya, low), (xb, yb, low), 0.04, b.tint(LOG), sides=6, caps=False)
        b.log((xa, ya, low), (xb, yb, top), 0.03, b.tint(LOG), sides=6, caps=False)
        b.log((xa, ya, top), (xb, yb, low), 0.03, b.tint(LOG), sides=6, caps=False)
    # Two steps down to the snow.
    for k in (1, 2):
        ya = y0 - 0.3 * k
        b.box((-0.9, ya, -0.4), (0.9, ya + 0.3, BASE * (3 - k) / 3.0), b.tint(PLANK, 0.1), WOOD, 0)
        for x in (-0.82, 0.82):
            b.mound((x, ya + 0.02, BASE * (3 - k) / 3.0 - 0.01), (x, ya + 0.28, BASE * (3 - k) / 3.0 - 0.01), 0.22, 0.07)


def bench(b):
    x0, x1, y0, y1 = -2.35, -0.95, -2.5, -2.14
    seat = BASE + 0.45
    for ya, yb in ((y0, y0 + 0.17), (y0 + 0.19, y1)):
        b.box((x0, ya, seat - 0.04), (x1, yb, seat), b.tint(PLANK, 0.1), WOOD, 0)
    for x in (x0 + 0.1, x1 - 0.14):
        b.box((x, y0 + 0.03, BASE), (x + 0.04, y1 - 0.02, seat - 0.04), b.tint(DARK_WOOD), WOOD, 2)
    b.box((x0, y1 - 0.03, seat + 0.2), (x1, y1 + 0.01, seat + 0.36), b.tint(PLANK, 0.1), WOOD, 0)


def woodpile(b):
    """Split firewood stacked under the far window, cut ends to the rink."""
    r = 0.085
    y_back, y_front = -HY - LOG_R - 0.02, -HY - LOG_R - 0.44
    for row, count in enumerate((8, 7, 6)):
        z = BASE + r + row * r * 1.74
        for i in range(count):
            x = 1.08 + row * r + i * r * 2.0 + b.rng.uniform(-0.01, 0.01)
            rr = r * b.rng.uniform(0.82, 1.0)
            b.log((x, y_back, z), (x, y_front - b.rng.uniform(0.0, 0.05), z), rr, b.tint(FIREWOOD, 0.12), sides=6,
                  cap=b.tint(LOG_END, 0.1))


def sticks(b):
    """Two hockey sticks leaning by the door."""
    for x, lean, shaft, tape in ((0.68, 0.02, srgb(0.86, 0.72, 0.5), IRON), (0.86, -0.03, srgb(0.12, 0.25, 0.6), WHITE)):
        foot = Vector((x, -HY - LOG_R - 0.36, BASE + 0.03))
        top = Vector((x + lean, -HY - LOG_R - 0.03, BASE + 1.42))
        b.log(foot, top, 0.016, shaft, PAINT, sides=4, caps=True)
        knob = foot.lerp(top, 0.9)
        b.log(knob, top + (top - foot).normalized() * 0.005, 0.02, WHITE, PAINT, sides=4)
        b.box((foot.x - 0.01, foot.y - 0.008, BASE), (foot.x + 0.27, foot.y + 0.008, BASE + 0.075), tape, PAINT, None)


def skates(b):
    """A pair of skates hung by their laces on a peg by the door."""
    peg = Vector((-0.78, -HY - LOG_R, 1.62))
    b.log(peg, peg + Vector((0, -0.1, 0.02)), 0.018, DARK_WOOD, PAINT, sides=5)
    hook = peg + Vector((0, -0.08, 0.02))
    boot = srgb(0.09, 0.09, 0.1)
    for dx, drop_by, tilt, turn in ((0.05, 0.2, 38.0, -6.0), (-0.05, 0.27, 30.0, 188.0)):
        # Built toe to +x, sole down; then hung by its cuff, toe dipping, side-on to the rink.
        xf = (Matrix.Translation(hook + Vector((dx, -0.05, -drop_by))) @ Matrix.Rotation(math.radians(turn), 4, 'Z')
              @ Matrix.Rotation(math.radians(tilt), 4, 'Y') @ Matrix.Translation((0.04, 0.0, -0.2)))
        b.box((-0.1, -0.04, 0.0), (0.16, 0.04, 0.085), boot, PAINT, None, xf=xf)
        b.box((-0.1, -0.04, 0.085), (0.02, 0.04, 0.2), boot, PAINT, None, xf=xf)
        b.box((0.1, -0.042, 0.0), (0.165, 0.042, 0.06), CREAM, PAINT, None, xf=xf)
        b.box((-0.09, -0.012, -0.035), (0.15, 0.012, 0.0), WHITE, PAINT, None, xf=xf)
        b.box((-0.11, -0.004, -0.06), (0.17, 0.004, -0.035), srgb(0.7, 0.72, 0.75), PAINT, None, xf=xf)
        cuff = xf @ Vector((-0.04, 0.0, 0.2))
        b.log(hook, cuff, 0.006, WHITE, PAINT, sides=3, caps=False)


def lantern(b):
    """A lantern on an iron arm by the door. Returns where its flame is."""
    at = Vector((-0.8, -HY - LOG_R - 0.2, 2.02))
    b.box((at.x - 0.015, at.y, at.z + 0.2), (at.x + 0.015, -HY - LOG_R + 0.02, at.z + 0.23), IRON, PAINT, None)
    b.box((at.x - 0.008, at.y - 0.008, at.z + 0.13), (at.x + 0.008, at.y + 0.008, at.z + 0.2), IRON, PAINT, None)
    b.box((at.x - 0.085, at.y - 0.085, at.z + 0.1), (at.x + 0.085, at.y + 0.085, at.z + 0.13), IRON, PAINT, None)
    b.box((at.x - 0.075, at.y - 0.075, at.z - 0.12), (at.x + 0.075, at.y + 0.075, at.z - 0.1), IRON, PAINT, None)
    b.box((at.x - 0.055, at.y - 0.055, at.z - 0.1), (at.x + 0.055, at.y + 0.055, at.z + 0.1), WARM, GLOW, None)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((at.x + sx * 0.062 - 0.008, at.y + sy * 0.062 - 0.008, at.z - 0.1),
                  (at.x + sx * 0.062 + 0.008, at.y + sy * 0.062 + 0.008, at.z + 0.1), IRON, PAINT, None)
    return at


def chimney(b):
    """A fieldstone chimney up the end wall, laid in rough courses. Returns its mouth."""
    def half(z):   # half-width along the wall, and how far it stands out from it
        t = min(1.0, max(0.0, (z - 2.5) / 0.8))
        return 0.58 - 0.2 * t, 0.66 - 0.14 * t
    z = -0.4
    x_in = HX - 0.06
    while z < CHIMNEY_TOP - 0.01:
        z1 = min(CHIMNEY_TOP, z + b.rng.uniform(0.34, 0.48))
        (w0, d0), (w1, d1) = half(z), half(z1)
        j = lambda: b.rng.uniform(-0.018, 0.018)
        ja, jb, jc = j(), j(), j()
        b.hexa([(x_in, CHIMNEY_Y - w0 + ja, z), (HX + d0 + jc, CHIMNEY_Y - w0 + ja, z), (HX + d0 + jc, CHIMNEY_Y + w0 + jb, z), (x_in, CHIMNEY_Y + w0 + jb, z),
                (x_in, CHIMNEY_Y - w1 + ja, z1), (HX + d1 + jc, CHIMNEY_Y - w1 + ja, z1), (HX + d1 + jc, CHIMNEY_Y + w1 + jb, z1), (x_in, CHIMNEY_Y + w1 + jb, z1)],
               b.tint(STONE_TINT, 0.06), STONE, None, (1.2, 1.2), off=(0.37, 0.11))
        z = z1
    w, d = half(CHIMNEY_TOP)
    cx = (x_in + HX + d) * 0.5
    b.box((x_in - 0.06, CHIMNEY_Y - w - 0.06, CHIMNEY_TOP), (HX + d + 0.06, CHIMNEY_Y + w + 0.06, CHIMNEY_TOP + 0.09),
          tuple(c * 0.7 for c in STONE_TINT), STONE, None, (1.2, 1.2))
    # A clay pot for the flue, snow heaped round it on the cap.
    pot = srgb(0.62, 0.3, 0.2)
    b.log((cx, CHIMNEY_Y, CHIMNEY_TOP + 0.09), (cx, CHIMNEY_Y, CHIMNEY_TOP + 0.4), 0.15, pot, PAINT, sides=8, cap=IRON, r1=0.12)
    for dy in (-0.24, 0.24):
        b.mound((x_in - 0.02, CHIMNEY_Y + dy, CHIMNEY_TOP + 0.08), (HX + d + 0.02, CHIMNEY_Y + dy, CHIMNEY_TOP + 0.08), 0.4, 0.16)
    return Vector((cx, CHIMNEY_Y, CHIMNEY_TOP + 0.45))


def sign(b):
    """The board on the porch beam, its letters cut from Blender's own font."""
    y = POST_Y - 0.085
    zc = beam_z() - 0.06
    b.box((-1.12, y - 0.04, zc - 0.19), (1.12, y, zc + 0.19), tuple(c * 0.6 for c in DARK_WOOD), WOOD, 0)
    for z in (zc - 0.19, zc + 0.15):
        b.box((-1.15, y - 0.055, z), (1.15, y, z + 0.04), b.tint(DARK_WOOD), WOOD, 0)
    cu = bpy.data.curves.new("HutSignText", 'FONT')
    cu.body = SIGN
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.size = 0.25
    cu.space_character = 1.08
    cu.resolution_u = 2
    ob = bpy.data.objects.new("HutSignText", cu)
    bpy.data.scenes[SCENE].collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    # The text lies in the XY plane: stand it up facing -Y, just proud of the board.
    place = Matrix.Translation((0.0, y - 0.055, zc)) @ Matrix.Rotation(math.radians(90.0), 4, 'X')
    for poly in me.polygons:
        pts = [place @ me.vertices[i].co for i in poly.vertices]
        b.poly(pts, [(0.0, 0.0)] * len(pts), CREAM, PAINT, facing=(0, -1, 0))
    bpy.data.meshes.remove(me)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)


def shovel(b):
    """A snow shovel stood in the drift by the steps."""
    foot = Vector((1.55, FRONT - 0.5, 0.05))
    top = foot + Vector((0.1, 0.22, 1.25))
    b.log(foot, top, 0.018, srgb(0.8, 0.66, 0.45), PAINT, sides=5)
    xf = Matrix.Translation(foot) @ Matrix.Rotation(math.radians(-10.0), 4, 'X')
    b.box((-0.19, -0.015, -0.12), (0.19, 0.015, 0.24), RED, PAINT, None, xf=xf)


def roof_snow(b):
    """One sheet of snow over the whole roof, rounded off at the eaves and ends."""
    ys = []
    line = roof_line()
    for y0, y1 in zip(line, line[1:]):
        n = max(1, math.ceil(abs(y1 - y0) / 0.3))
        ys += [y0 + (y1 - y0) * k / n for k in range(n)]
    ys.append(line[-1])
    arc = [0.0]
    for y0, y1 in zip(ys, ys[1:]):
        arc.append(arc[-1] + math.hypot(y1 - y0, roof_z(y1) - roof_z(y0)))
    nx = 20
    x0, x1 = -ROOF_X - 0.02, ROOF_X + 0.02
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]

    def top(i, k):
        d = min(xs[i] - x0, x1 - xs[i], arc[k], arc[-1] - arc[k])
        edge = math.sqrt(1.0 - (1.0 - min(d / 0.3, 1.0)) ** 2)
        deep = 0.27 * edge * (0.75 + 0.5 * wobble(xs[i] * 1.3, arc[k] * 1.3, 11))
        return Vector((xs[i], ys[k], roof_z(ys[k]) + 0.012 + deep))

    def shade(i, k):
        w = wobble(xs[i] * 1.3, arc[k] * 1.3, 11) * 0.6 + wobble(xs[i] * 2.9, arc[k] * 2.9, 12) * 0.4
        return tuple(h + (1.0 - h) * w for h in HOLLOW)

    for k in range(len(ys) - 1):
        for i in range(nx):
            at = [(i, k), (i + 1, k), (i + 1, k + 1), (i, k + 1)]
            pts = [top(*q) for q in at]
            b.poly(pts, [(p.x * 0.5, p.y * 0.5) for p in pts], [shade(*q) for q in at], SNOW, facing=(0, 0, 1))
    # Icicles off the porch eave (short over the sign).
    for i in range(34):
        x = b.rng.uniform(-ROOF_X + 0.1, ROOF_X - 0.1)
        long = b.rng.uniform(0.07, 0.34) * (0.3 if abs(x) < 1.25 else 1.0)
        p = Vector((x, FRONT - 0.03, roof_z(FRONT) - 0.1))
        b.log(p, p - Vector((0, 0, long)), b.rng.uniform(0.014, 0.028), ICE, PAINT, sides=4, r1=0.0, caps=False)


def drift(b):
    """Snow banked up round the hut's foot (low along the porch, lower still at the steps),
    running out flat into the rink's own snow, in its color."""
    cx, cy, ax, ay, p = 0.2, -0.9, 3.25, 3.0, 5.0
    n = 56
    # Out from the hut's outline (m), how much of the bank's height is left, how much of the ground's color.
    steps = ((-0.9, 1.0, 0.0), (-0.25, 1.0, 0.0), (0.35, 0.72, 0.0), (0.9, 0.36, 0.3), (1.5, 0.1, 0.8), (2.1, 0.0, 1.0), (2.7, 0.0, 1.0))
    rings, shades = [], []
    for k in range(n):
        th = math.tau * k / n
        c, s = math.cos(th), math.sin(th)
        px = cx + ax * math.copysign(abs(c) ** (2.0 / p), c)
        py = cy + ay * math.copysign(abs(s) ** (2.0 / p), s)
        out = Vector((math.copysign(abs(c) ** (2.0 - 2.0 / p), c) / ax, math.copysign(abs(s) ** (2.0 - 2.0 / p), s) / ay, 0.0)).normalized()
        w = wobble(px, py, 23)
        h = 0.6 * (0.55 + 0.8 * w)
        if py < -HY - 0.3:
            h = min(h, 0.3)
            if abs(px) < 1.5:
                h *= 0.25 + 0.75 * min(1.0, max(0.0, (abs(px) - 0.9) / 0.6))
        rings.append([Vector((px, py, GROUND_Z)) + out * o + Vector((0, 0, h * f)) for o, f, g in steps])
        snow = tuple(q + (1.0 - q) * (0.4 + 0.6 * w) for q in HOLLOW)
        shades.append([tuple(a + (e - a) * g for a, e in zip(snow, GROUND)) for o, f, g in steps])
    for k in range(n):
        k1 = (k + 1) % n
        for j in range(len(steps) - 1):
            pts = [rings[k][j], rings[k][j + 1], rings[k1][j + 1], rings[k1][j]]
            cols = [shades[k][j], shades[k][j + 1], shades[k1][j + 1], shades[k1][j]]
            b.poly(pts, [(q.x * 0.5, q.y * 0.5) for q in pts], cols, SNOW, facing=(0, 0, 1))


# --- The two pictures: tiling, made with numpy ---------------------------------------------

def soft_noise(rx, ry, seed):
    """Noise that tiles, 0..1, blurred `rx` across and `ry` down (fractions of the picture)."""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((TEX, TEX)))
    ky = np.fft.fftfreq(TEX)[:, None] * TEX
    kx = np.fft.fftfreq(TEX)[None, :] * TEX
    f *= np.exp(-((kx * rx) ** 2 + (ky * ry) ** 2) * 10.0)
    out = np.fft.ifft2(f).real
    out -= out.min()
    return out / out.max()


def save_picture(name, rgb):
    """`rgb` (rows from the bottom, 0..1 as on screen) to assets/hut/<name>.jpg."""
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    px = np.ones((TEX, TEX, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb, 0.0, 1.0)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(OUT, name + ".jpg")
    img.file_format = 'JPEG'
    img.save()
    return img


def wood_picture():
    """Pale grain running along U: long streaks, fine lines that wander, a little fleck."""
    v = np.linspace(0.0, 1.0, TEX, endpoint=False)[:, None]
    streak = 0.6 * soft_noise(0.1, 0.006, 1) + 0.3 * soft_noise(0.03, 0.003, 2) + 0.1 * soft_noise(0.002, 0.002, 3)
    lines = 0.5 + 0.5 * np.sin(math.tau * (26.0 * v + 2.2 * soft_noise(0.12, 0.03, 4)))
    cracks = np.clip((soft_noise(0.06, 0.0025, 5) - 0.72) * 6.0, 0.0, 1.0)
    t = np.clip(0.62 * streak + 0.38 * lines, 0.0, 1.0)[..., None]
    dark, light = np.array([0.6, 0.5, 0.42]), np.array([1.0, 0.96, 0.9])
    rgb = dark + (light - dark) * t
    rgb *= (1.0 - 0.45 * cracks)[..., None]
    return save_picture("wood", rgb)


def stone_picture():
    """Fieldstone: rounded stones of a few grays and browns, dark joints between."""
    rng = np.random.default_rng(8)
    n = 46
    pts = rng.random((n, 2))
    shade = rng.uniform(0.55, 0.98, n)
    hue = rng.uniform(-1.0, 1.0, n)
    y, x = np.mgrid[0:TEX, 0:TEX] / TEX
    warp = 0.03
    x = x + warp * (soft_noise(0.05, 0.05, 31) - 0.5)
    y = y + warp * (soft_noise(0.05, 0.05, 32) - 0.5)
    dx = np.abs(x[..., None] - pts[:, 0])
    dy = np.abs(y[..., None] - pts[:, 1])
    d = np.hypot(np.minimum(dx, 1.0 - dx), np.minimum(dy, 1.0 - dy))
    order = np.argsort(d, axis=-1)[..., :2]
    d1 = np.take_along_axis(d, order[..., :1], -1)[..., 0]
    d2 = np.take_along_axis(d, order[..., 1:2], -1)[..., 0]
    cell = order[..., 0]
    joint = np.clip((d2 - d1) / 0.035, 0.0, 1.0)
    joint = joint * joint * (3.0 - 2.0 * joint)
    mottle = 0.82 + 0.3 * soft_noise(0.012, 0.012, 9) + 0.12 * (soft_noise(0.002, 0.002, 10) - 0.5)
    value = shade[cell] * mottle * (0.8 + 0.2 * joint)
    warm = np.array([1.0, 0.93, 0.84])
    cool = np.array([0.88, 0.93, 1.0])
    k = (0.5 + 0.5 * hue[cell])[..., None]
    rgb = value[..., None] * (cool + (warm - cool) * k)
    mortar = np.array([0.33, 0.31, 0.3])
    rgb = mortar + (rgb - mortar) * joint[..., None]
    return save_picture("stone", rgb)


# --- Putting it together ---------------------------------------------------------------------

def drop(name):
    ob = bpy.data.objects.get(name)
    if ob is None:
        return
    data = ob.data
    bpy.data.objects.remove(ob)
    if isinstance(data, bpy.types.Mesh) and data.users == 0:
        bpy.data.meshes.remove(data)


def setup():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    if bpy.context.window:
        bpy.context.window.scene = sc
    for o in list(sc.objects):
        drop(o.name)
    os.makedirs(OUT, exist_ok=True)
    return sc


def materials(wood, stone):
    """Stand-ins to look at in Blender (the game has its own): the pictures times the vertex color."""
    out = []
    for name in MATS:
        old = bpy.data.materials.get(name)
        if old:
            bpy.data.materials.remove(old)
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Roughness"].default_value = 0.9
        col = nt.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "Col"
        img = {"HutWood": wood, "HutStone": stone}.get(name)
        if img:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.blend_type = 'MULTIPLY'
            mix.inputs[0].default_value = 1.0
            nt.links.new(tex.outputs["Color"], mix.inputs[6])
            nt.links.new(col.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
            if name == "HutGlow":
                nt.links.new(col.outputs["Color"], bsdf.inputs["Emission Color"])
                bsdf.inputs["Emission Strength"].default_value = 3.0
        out.append(m)
    return out


def marker(sc, name, at):
    drop(name)
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.2
    ob.location = at
    sc.collection.objects.link(ob)
    return ob


def export(sc, objects):
    for o in sc.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    # No pictures in the file: the game puts its own materials on by name.
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hut.glb"), use_selection=True, use_active_scene=True,
                              export_image_format='NONE', export_apply=True, export_extras=False,
                              export_animations=False, export_vertex_color='ACTIVE', export_all_vertex_colors=False)


def main():
    sc = setup()
    wood, stone = wood_picture(), stone_picture()
    b = Build()
    footing(b)
    walls(b)
    for a0, a1 in FRONT_WINDOWS:
        window(b, a0, a1, FRONT_WALL)
    window(b, *SIDE_WINDOW, END_WALL)
    door(b)
    gables(b)
    roof(b)
    porch(b)
    bench(b)
    woodpile(b)
    sticks(b)
    skates(b)
    lamp = lantern(b)
    smoke = chimney(b)
    sign(b)
    shovel(b)
    roof_snow(b)
    drift(b)
    drop("hut")
    ob = bpy.data.objects.new("hut", b.mesh("hut"))
    for m in materials(wood, stone):
        ob.data.materials.append(m)
    sc.collection.objects.link(ob)
    parts = [ob, marker(sc, "lamp", lamp), marker(sc, "smoke", smoke)]
    export(sc, parts)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("hut:", tris, "triangles,", len(ob.data.vertices), "vertices")
    return ob
