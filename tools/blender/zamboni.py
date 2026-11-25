"""The ice resurfacer: our own machine, built here from nothing.

Run it in the live Blender (it works in its own scene, "ZamboniLab", and leaves the others be):

    ns = {"__name__": "zamboni", "__file__": r"<project>\\tools\\blender\\zamboni.py"}
    exec(open(ns["__file__"]).read(), ns); ns["main"]()

It writes assets/zamboni/zamboni.glb, in meters, the front toward Blender's +Y (the game's -Z),
the ice at z = 0, centered on the wheelbase:
    Body        the big panels, their edges rolled (Paint, Trim, Seat, Dark)
    Fittings    everything thin: stripes, lamps, grille, rails, levers, the beacon
    WheelFL, WheelFR, WheelRL, WheelRR   each with its origin on its axle
    Steering    the steering wheel, its origin at the middle of the rim

The game uses the file's materials as they are (Zamboni.set_trim recolors Trim to the home
team): Paint, Trim, Tire, Hub, Seat, Dark, Metal, Lamp, Beacon, Panel (the plates on the
tank's sides, which Zamboni.set_logo puts the home team's crest on).

The game's numbers this has to keep (Zamboni's constants): the wheels' radius and where their
axles are, the footprint, where the driver sits (SEAT: the floor under the seat, with the seat
SEAT_H over it) and the steering wheel's axis.

The machine: a snow tank with a rounded nose over the front two thirds, the driver's stand at
the back on the left behind it, the water tank and the snow conveyor's pipe on the right, and
the conditioner (the sled that shaves and floods) dragging behind, in the home team's color.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "zamboni")
SCENE = "ZamboniLab"
MATS = ["Paint", "Trim", "Tire", "Hub", "Seat", "Dark", "Metal", "Lamp", "Beacon", "Panel"]
PAINT, TRIM, TIRE, HUB, SEAT, DARK, METAL, LAMP, BEACON, PANEL = range(10)
# name: (color, roughness, metallic, glow)
LOOKS = {
    "Paint": ((0.92, 0.92, 0.90), 0.35, 0.0, 0.0),
    "Trim": ((0.16, 0.16, 0.17), 0.5, 0.0, 0.0),
    "Tire": ((0.05, 0.05, 0.05), 0.85, 0.0, 0.0),
    "Hub": ((0.62, 0.63, 0.65), 0.35, 0.6, 0.0),
    "Seat": ((0.07, 0.07, 0.08), 0.7, 0.0, 0.0),
    "Dark": ((0.04, 0.04, 0.045), 0.8, 0.0, 0.0),
    "Metal": ((0.56, 0.57, 0.59), 0.35, 0.8, 0.0),
    "Lamp": ((1.0, 0.96, 0.82), 0.3, 0.0, 2.0),
    "Beacon": ((1.0, 0.5, 0.04), 0.3, 0.0, 3.0),
    "Panel": ((0.92, 0.92, 0.90), 0.4, 0.0, 0.0),
}

# --- The machine's measures (m): x to its right, y forward, z up -------------------------

WHEEL_R = 0.376              # Zamboni.WHEEL_R
WHEEL_W = 0.27
TRACK = 0.675                # the wheels' centers, either side
AXLE = 0.98                  # and fore and aft (Zamboni.WHEELBASE is twice this)
ARCH = 0.47                  # the wheel arches' radius
HALF = 0.80                  # the body's half width
FRONT, REAR = 1.66, -1.62    # the lower body's ends
SKIRT = 0.20                 # the bottom of the skirt (it runs up to the axles' height)
BELT = 0.98                  # the top of the lower body
TANK_REAR = -1.12            # the snow tank: from here to the nose
TANK_TOP = 1.95
TANK_HALF = 0.78
NOSE = (0.75, 1.25)          # the nose rounds down from (this y, the top) to (the front, this z)
FLOOR = 1.02                 # the driver's floor (Zamboni.SEAT.y)
SEAT_AT = (-0.36, -2.12)     # where the driver's hips are (Zamboni.SEAT)
SEAT_TOP = FLOOR + 0.5       # Rink.SEAT_H over the floor
STEER_AXIS = Vector((0.0, -0.788, 0.616))    # Zamboni._steer_axis: up the column, toward the driver
STEER_AT = Vector((-0.36, -1.46, 1.72))      # the middle of the steering wheel's rim
STEER_R = 0.19
COND = (-2.48, -1.72)        # the conditioner, back to front
COND_HALF = 0.80
BEVEL = 0.018                # how far the body panels' edges are rolled


# --- Building ---------------------------------------------------------------------------

class Build:
    def __init__(self):
        self.v, self.f, self.uv, self.mat, self.facing = [], [], [], [], []

    def add(self, verts, faces, mat, uvs=None, facing=None):
        """`facing`: the way these faces should look (for a face on its own, which has no inside)."""
        i = len(self.v)
        self.v.extend(Vector(p) for p in verts)
        for k, f in enumerate(faces):
            self.f.append([i + j for j in f])
            self.uv.append(uvs[k] if uvs else [(0.0, 0.0)] * len(f))
            self.mat.append(mat)
            self.facing.append(facing)

    def box(self, lo, hi, mat, xf=None):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        v = [Vector(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        if xf is not None:
            v = [xf @ p for p in v]
        self.add(v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat)

    def prism(self, poly, x0, x1, mat):
        """A (y, z) outline run across from x0 to x1."""
        n = len(poly)
        v = [(x0, y, z) for y, z in poly] + [(x1, y, z) for y, z in poly]
        f = [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
        f.append(list(range(n - 1, -1, -1)))
        f.append(list(range(n, 2 * n)))
        self.add(v, f, mat)

    def lathe(self, prof, at, axis, segs, mat, caps=(False, False), mats=None):
        """`prof`, a line of (along the axis, radius) points, turned round `axis` through `at`.
        `mats`: a material per stretch of the line."""
        a = Vector(axis).normalized()
        u = a.orthogonal().normalized()
        w = a.cross(u)
        at = Vector(at)
        v = []
        for t, r in prof:
            for k in range(segs):
                ang = 2.0 * math.pi * k / segs
                v.append(at + a * t + (u * math.cos(ang) + w * math.sin(ang)) * r)
        for i in range(len(prof) - 1):
            f = [[i * segs + k, i * segs + (k + 1) % segs, (i + 1) * segs + (k + 1) % segs, (i + 1) * segs + k]
                 for k in range(segs)]
            self.add(v, f, mats[i] if mats else mat)
        if caps[0]:
            self.add(v[:segs], [list(range(segs))], mats[0] if mats else mat)
        if caps[1]:
            self.add(v[-segs:], [list(range(segs))], mats[-1] if mats else mat)

    def tube(self, pts, r, mat, sides=8, caps=True):
        """A round bar along `pts`, mitred at its bends."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        dirs = [(pts[i + 1] - pts[i]).normalized() for i in range(n - 1)]
        v = []
        prev = None
        for i in range(n):
            din, dout = dirs[max(i - 1, 0)], dirs[min(i, n - 2)]
            t = (din + dout).normalized()
            nn = t.orthogonal() if prev is None else prev - t * prev.dot(t)
            nn.normalize()
            prev = nn
            bn = t.cross(nn)
            m = dout - din
            s = 1.0
            if m.length > 1e-6:
                m.normalize()
                s = 1.0 / max(math.cos(math.acos(max(-1.0, min(1.0, din.dot(dout)))) * 0.5), 0.3)
            for k in range(sides):
                ang = 2.0 * math.pi * k / sides
                off = (nn * math.cos(ang) + bn * math.sin(ang)) * r
                if s != 1.0:
                    off += m * off.dot(m) * (s - 1.0)
                v.append(pts[i] + off)
        f = []
        for i in range(n - 1):
            for k in range(sides):
                f.append([i * sides + k, i * sides + (k + 1) % sides, (i + 1) * sides + (k + 1) % sides, (i + 1) * sides + k])
        if caps:
            f.append(list(range(sides)))
            f.append(list(range((n - 1) * sides, n * sides)))
        self.add(v, f, mat)

    def mesh(self, name, sharp=40.0, weld=False):
        old = bpy.data.meshes.get(name)
        if old and old.users == 0:
            bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in self.v], [], self.f)
        uv = me.uv_layers.new(name="UVMap")
        k = 0
        for poly, uvs, mat in zip(me.polygons, self.uv, self.mat):
            poly.material_index = mat
            poly.use_smooth = True
            for q in uvs:
                uv.data[k].uv = q
                k += 1
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        fixed = [(bm.faces[i], Vector(d)) for i, d in enumerate(self.facing) if d is not None]
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for face, d in fixed:
            if face.normal.dot(d) < 0.0:
                face.normal_flip()
        lim = math.radians(sharp)
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
                e.smooth = False
        bm.to_mesh(me)
        bm.free()
        me.update()
        return me


def arc(cy, cz, ry, rz, a0, a1, steps):
    """Points (y, z) round an ellipse from angle a0 to a1 (degrees, 0 = forward, 90 = up)."""
    out = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        out.append((cy + ry * math.cos(a), cz + rz * math.sin(a)))
    return out


# --- The body ---------------------------------------------------------------------------

def lower_body(b, f):
    # From the axles' height up to the belt, with the wheel arches cut in.
    poly = [(REAR, WHEEL_R)]
    for cy in (-AXLE, AXLE):
        poly += arc(cy, WHEEL_R, ARCH, ARCH, 180.0, 0.0, 14)
    poly += [(FRONT, WHEEL_R), (FRONT, BELT), (REAR, BELT)]
    b.prism(poly, -HALF, HALF, PAINT)
    # The skirt below it, in the team's color, standing a little proud.
    for y0, y1 in ((REAR, -AXLE - ARCH), (-AXLE + ARCH, AXLE - ARCH), (AXLE + ARCH, FRONT)):
        b.box((-HALF - 0.012, y0, SKIRT), (HALF + 0.012, y1, WHEEL_R + 0.02), TRIM)
    # What's between the wheels, so nobody sees through the arches.
    f.box((-0.52, REAR + 0.02, 0.18), (0.52, FRONT - 0.02, BELT - 0.01), DARK)
    # The front bumper.
    b.box((-0.82, FRONT - 0.04, 0.26), (0.82, FRONT + 0.04, 0.46), DARK)
    # Louvres between the wheels, both sides.
    for sx in (-1.0, 1.0):
        for i in range(4):
            z = 0.56 + 0.075 * i
            f.box((sx * (HALF - 0.004), -0.32, z), (sx * (HALF + 0.006), 0.32, z + 0.035), DARK)


def tank(b, f):
    # The snow tank, with its rounded nose.
    poly = [(TANK_REAR, BELT), (FRONT - 0.02, BELT)]
    poly += arc(NOSE[0], NOSE[1], FRONT - 0.02 - NOSE[0], TANK_TOP - NOSE[1], 0.0, 90.0, 10)
    poly += [(TANK_REAR, TANK_TOP)]
    b.prism(poly, -TANK_HALF, TANK_HALF, PAINT)
    # The lid on top, and the hinge it tips on at the front.
    f.box((-0.6, -0.95, TANK_TOP - 0.005), (0.6, 0.55, TANK_TOP + 0.022), PAINT)
    f.tube([(-0.5, 0.62, TANK_TOP + 0.012), (0.5, 0.62, TANK_TOP + 0.012)], 0.02, METAL)
    # A stripe round the belt, in the team's color.
    f.box((-TANK_HALF - 0.006, TANK_REAR, BELT + 0.04), (TANK_HALF + 0.006, FRONT - 0.014, BELT + 0.12), TRIM)
    # The plates on the sides (for a logo): a frame, and the plate's face with UVs across it.
    y0, y1, z0, z1 = -0.85, 0.75, 1.2, 1.8
    for sx in (-1.0, 1.0):
        x = sx * TANK_HALF
        f.box((x - sx * 0.004, y0 - 0.02, z0 - 0.02), (x + sx * 0.008, y1 + 0.02, z1 + 0.02), METAL)
        xo = x + sx * 0.0095
        # Read from outside, left to right: on the right side that's back to front.
        ya, yb = (y0, y1) if sx > 0.0 else (y1, y0)
        # (v up the plate, u in the same units about its middle: scenes/match/logo_plate.gdshader)
        u = (y1 - y0) / (z1 - z0) * 0.5
        f.add([(xo, ya, z0), (xo, yb, z0), (xo, yb, z1), (xo, ya, z1)], [(0, 1, 2, 3)], PANEL,
              [[(0.5 - u, 0.0), (0.5 + u, 0.0), (0.5 + u, 1.0), (0.5 - u, 1.0)]], facing=(sx, 0.0, 0.0))


def front(f):
    wall = FRONT
    # Headlights: a bezel and a lens.
    for sx in (-1.0, 1.0):
        f.lathe([(0.0, 0.1), (0.03, 0.1), (0.03, 0.082), (0.022, 0.082), (0.036, 0.05), (0.04, 0.0001)],
                (sx * 0.52, wall - 0.005, 0.74), (0, 1, 0), 16, METAL, mats=[METAL, METAL, METAL, LAMP, LAMP])
    # The grille between them.
    f.box((-0.3, wall - 0.005, 0.56), (0.3, wall + 0.008, 0.9), DARK)
    for i in range(5):
        z = 0.585 + 0.066 * i
        f.box((-0.3, wall, z), (0.3, wall + 0.018, z + 0.024), METAL)


def stand(b, f):
    """The driver's stand at the back on the left, the water tank and the conveyor on the right."""
    sx, sy = SEAT_AT
    back = COND[0] + 0.04
    # The floor, the locker under it, and the wall behind the seat.
    b.box((-HALF, back, FLOOR - 0.08), (-0.04, TANK_REAR, FLOOR), DARK)
    b.box((-HALF + 0.02, back + 0.04, 0.6), (-0.06, REAR + 0.05, FLOOR - 0.08), PAINT)
    b.box((-HALF, back - 0.02, FLOOR - 0.08), (-0.04, back + 0.04, SEAT_TOP + 0.02), PAINT)
    # The seat: a pedestal, the cushion and the back.
    b.box((sx - 0.15, sy - 0.2, FLOOR), (sx + 0.15, sy + 0.14, SEAT_TOP - 0.09), DARK)
    b.box((sx - 0.24, sy - 0.26, SEAT_TOP - 0.1), (sx + 0.24, sy + 0.24, SEAT_TOP), SEAT)
    lean = Matrix.Translation((sx, sy - 0.22, SEAT_TOP)) @ Matrix.Rotation(math.radians(5.0), 4, 'X')
    b.box((-0.24, -0.09, 0.0), (0.24, 0.0, 0.52), SEAT, lean)
    # The console under the steering column, with its levers.
    b.box((-0.72, TANK_REAR - 0.2, FLOOR), (-0.08, TANK_REAR, 1.44), PAINT)
    f.box((-0.7, TANK_REAR - 0.19, 1.438), (-0.1, TANK_REAR - 0.01, 1.447), DARK)
    for i, x in enumerate((-0.64, -0.57, -0.15)):
        tip = Vector((x, TANK_REAR - 0.16 - 0.02 * i, 1.64))
        f.tube([(x, TANK_REAR - 0.1, 1.44), tip], 0.009, METAL, 6)
        f.lathe([(-0.022, 0.0001), (-0.016, 0.016), (0.0, 0.022), (0.016, 0.016), (0.022, 0.0001)], tip, (0, 0, 1), 8, SEAT)
    # The steering column.
    f.tube([STEER_AT - STEER_AXIS * 0.44, STEER_AT - STEER_AXIS * 0.03], 0.022, DARK)
    # A grab rail on the open side, and a step up.
    x = -HALF + 0.03
    f.tube([(x, -1.3, FLOOR), (x, -1.3, 1.8), (x, -1.72, 1.8), (x, -1.72, FLOOR)], 0.018, METAL)
    f.box((-HALF - 0.03, -1.62, 0.56), (-HALF + 0.02, -1.26, 0.6), METAL)
    # The water tank, on the right.
    b.box((0.42, REAR - 0.3, BELT - 0.02), (HALF - 0.02, TANK_REAR + 0.02, 1.52), PAINT)
    f.lathe([(0.0, 0.07), (0.02, 0.07), (0.02, 0.05), (0.035, 0.05)], (0.6, -1.55, 1.515), (0, 0, 1), 12, METAL, caps=(False, True))
    # The conveyor: the pipe that carries the snow up from the conditioner into the tank.
    low, high = Vector((0.2, COND[1] - 0.32, 0.3)), Vector((0.2, TANK_REAR + 0.06, TANK_TOP - 0.2))
    f.tube([low, high], 0.15, PAINT, 14)
    for t in (0.3, 0.62):
        f.lathe([(-0.025, 0.162), (0.025, 0.162)], low.lerp(high, t), high - low, 14, METAL, caps=(True, True))
    # The beacon, on a post at the tank's back corner.
    at = Vector((0.62, TANK_REAR + 0.14, TANK_TOP))
    f.tube([at, at + Vector((0, 0, 0.16))], 0.015, METAL, 6)
    f.lathe([(0.15, 0.05), (0.17, 0.05), (0.17, 0.042), (0.25, 0.042), (0.262, 0.03), (0.266, 0.0001)], at, (0, 0, 1), 12, METAL,
            mats=[METAL, METAL, BEACON, BEACON, BEACON])


def conditioner(b, f):
    y0, y1 = COND
    # The cover, in the team's color.
    b.prism([(y1, 0.06), (y1, 0.3), (y1 - 0.1, 0.36), (y0 + 0.2, 0.36), (y0 + 0.04, 0.22), (y0 + 0.04, 0.06)],
            -COND_HALF, COND_HALF, TRIM)
    # Its runners, the towel dragging behind, and the water pipe over it.
    for sx in (-1.0, 1.0):
        f.prism([(y1 + 0.03, 0.03), (y1 + 0.03, 0.34), (y1 - 0.08, 0.41), (y0 + 0.2, 0.41), (y0 - 0.02, 0.22), (y0 - 0.02, 0.0),
                 (y1, 0.0)], sx * COND_HALF, sx * (COND_HALF + 0.03), METAL)
    f.box((-COND_HALF, y0 - 0.02, 0.0), (COND_HALF, y0 + 0.04, 0.1), DARK)
    f.tube([(-COND_HALF, y0 + 0.1, 0.3), (COND_HALF, y0 + 0.1, 0.3)], 0.02, METAL)
    # The arms that carry it.
    for x in (-0.5, 0.5):
        f.tube([(x, REAR + 0.1, 0.62), (x, y1 - 0.12, 0.34)], 0.035, METAL)
    f.tube([(-0.5, REAR + 0.02, 0.5), (0.5, REAR + 0.02, 0.5)], 0.03, METAL)


# --- Wheels and the steering wheel ------------------------------------------------------

def wheel():
    b = Build()
    w, r = WHEEL_W * 0.5, WHEEL_R - 0.01
    # The tire, shoulder to shoulder, then the dished hub on each side.
    b.lathe([(-w + 0.035, 0.215), (-w, 0.24), (-w, r - 0.03), (-w + 0.03, r), (w - 0.03, r), (w, r - 0.03), (w, 0.24), (w - 0.035, 0.215)],
            (0, 0, 0), (1, 0, 0), 28, TIRE)   # (the hubs have as many steps round, so the seams weld)
    for s in (-1.0, 1.0):
        b.lathe([(s * (w - 0.035), 0.215), (s * (w - 0.05), 0.2), (s * (w - 0.065), 0.1), (s * (w - 0.045), 0.065), (s * (w - 0.045), 0.0001)],
                (0, 0, 0), (1, 0, 0), 28, HUB)
        for k in range(5):
            a = 2.0 * math.pi * k / 5
            b.lathe([(0.0, 0.016), (0.02, 0.016)], (s * (w - 0.07), 0.135 * math.cos(a), 0.135 * math.sin(a)), (s, 0, 0), 6, DARK,
                    caps=(False, True))
    # Tread blocks, staggered side to side.
    for k in range(28):
        a = 2.0 * math.pi * (k + 0.5) / 28
        side = -1.0 if k % 2 else 1.0
        xf = Matrix.Rotation(a, 4, 'X')
        b.box((side * 0.012 - 0.06, -0.022, r - 0.004), (side * 0.012 + 0.06, 0.022, WHEEL_R), TIRE, xf)
    return b


def steering():
    """The steering wheel, about its own middle, already tilted on its column."""
    b = Build()
    a = STEER_AXIS.normalized()
    u = Vector((1.0, 0.0, 0.0))
    w = a.cross(u)
    ring = []
    n, m = 24, 6
    for i in range(n):
        ang = 2.0 * math.pi * i / n
        out = u * math.cos(ang) + w * math.sin(ang)
        for j in range(m):
            t = 2.0 * math.pi * j / m
            ring.append(out * (STEER_R - 0.016 + 0.016 * math.cos(t)) + a * 0.016 * math.sin(t))
    b.add(ring, [[i * m + j, ((i + 1) % n) * m + j, ((i + 1) % n) * m + (j + 1) % m, i * m + (j + 1) % m]
                 for i in range(n) for j in range(m)], SEAT)
    for k in range(3):
        ang = math.radians(90.0 + 120.0 * k)
        out = u * math.cos(ang) + w * math.sin(ang)
        b.tube([out * 0.03 - a * 0.03, out * (STEER_R - 0.02)], 0.011, METAL, 6)
    b.lathe([(-0.05, 0.03), (-0.02, 0.045), (0.0, 0.04), (0.006, 0.0001)], (0, 0, 0), a, 12, SEAT)
    return b


# --- The scene and the file -------------------------------------------------------------

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


def materials():
    out = []
    for name in MATS:
        color, rough, metal, glow = LOOKS[name]
        m = bpy.data.materials.get(name)
        if m and m.users == 0:
            bpy.data.materials.remove(m)
            m = None
        m = m or bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if glow > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = glow
        out.append(m)
    return out


def place(sc, name, build, mats, at=(0.0, 0.0, 0.0), roll=False, weld=False):
    drop(name)
    ob = bpy.data.objects.new(name, build.mesh(name, weld=weld))
    for m in mats:
        ob.data.materials.append(m)
    ob.location = at
    sc.collection.objects.link(ob)
    if roll:
        # Roll the panels' edges, and keep their faces flat.
        bev = ob.modifiers.new("roll", 'BEVEL')
        bev.limit_method = 'ANGLE'
        bev.angle_limit = math.radians(50.0)
        bev.width = BEVEL
        bev.segments = 2
        wn = ob.modifiers.new("flat", 'WEIGHTED_NORMAL')
        wn.keep_sharp = True
    return ob


def export(sc, objects):
    for o in sc.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "zamboni.glb"), use_selection=True, use_active_scene=True,
                              export_image_format='NONE', export_apply=True, export_extras=False,
                              export_animations=False)


def main(write=True):
    sc = setup()
    mats = materials()
    body, fit = Build(), Build()
    lower_body(body, fit)
    tank(body, fit)
    front(fit)
    stand(body, fit)
    conditioner(body, fit)
    parts = [place(sc, "Body", body, mats, roll=True), place(sc, "Fittings", fit, mats)]
    for key, x, y in (("FL", -TRACK, AXLE), ("FR", TRACK, AXLE), ("RL", -TRACK, -AXLE), ("RR", TRACK, -AXLE)):
        parts.append(place(sc, "Wheel" + key, wheel(), mats, (x, y, WHEEL_R), weld=True))
    parts.append(place(sc, "Steering", steering(), mats, STEER_AT))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in parts:
        me = ob.evaluated_get(dg).data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total += tris
        print(ob.name + ":", tris, "triangles")
    print("all:", total, "triangles")
    if write:
        export(sc, parts)
    return parts
