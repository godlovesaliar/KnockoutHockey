"""The goal: our own net, built here from nothing.

Run it in the live Blender (it works in its own scene, "NetLab", and leaves the others be):

    ns = {"__name__": "net", "__file__": r"<project>\\tools\\blender\\net.py"}
    exec(open(ns["__file__"]).read(), ns); ns["main"]()

It writes assets/net/net.glb, in meters, the goal line along x through the origin, the mouth
toward Blender's -Y (the game's +Z), the ice at z = 0:
    net_frame   the red pipes (NetFrame) and the white padding and lacing cord (NetPad)
    net_mesh    the netting (NetMesh), its UVs in meters along the threads

The file carries only the materials' names; the game puts its own on (Net._build_model).

The goal: 6 ft by 4 ft between the pipes, 40 in deep at the ice and 22 in at the top shelf
(RinkSpec's numbers; keep them the same here). The sides run straight back from the posts and
both the top shelf and the base turn round corners at the back (TOP_CORNER, BASE_CORNER, which
RinkSpec.NET_TOP_CORNER / NET_BASE_CORNER repeat for the colliders). A spine runs back along
the middle of the top shelf and a support comes down from it to the base. The base is wrapped
in a white bumper, the top shelf's pipes are padded on the inside and laced, and the netting
hangs between them with a little slack.
"""

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "net")
SCENE = "NetLab"
MATS = ["NetFrame", "NetPad", "NetMesh"]
FRAME, PAD, MESH = range(3)
Z = Vector((0.0, 0.0, 1.0))

# --- The goal's measures (m) ------------------------------------------------------------

IN = 0.0254
W = 72.0 * IN                # between the posts
H = 48.0 * IN                # under the crossbar
D = 40.0 * IN                # deep at the ice
T = 22.0 * IN                # deep at the top shelf
R = 1.1875 * IN              # the posts' and the crossbar's radius
HX = W * 0.5 + R             # the posts' center lines, and the netting's sides
ZT = H + R                   # the crossbar's center line, and the top shelf's
RF = 0.021                   # the pipes behind the mouth are thinner
TOP_CORNER = 0.20            # the top shelf's back corners
BASE_CORNER = 0.36           # the base's
ZN = ZT - 0.012              # the netting's top panel
ZB = 0.05                    # where the netting goes into the bumper
Y0 = 0.02                    # the netting starts this far behind the pipes' center lines
SLACK = 0.03                 # how far the netting hangs in from a straight line
TOP_SLACK = 0.022            # and the top panel down
NS, NC, NB = 4, 8, 6         # steps along a side, round a corner, along half the back
NV = 10                      # and down the netting
PAD_R = 0.026                # the padding inside the top shelf's pipes
LACE_R = 0.0032              # the lacing cord
LACE_PITCH = 0.06
# The bumper round the base, as (in from the netting's line, up from the ice).
BUMPER = [(-0.034, 0.0), (-0.036, 0.04), (-0.028, 0.075), (-0.008, 0.095), (0.02, 0.1),
          (0.045, 0.09), (0.058, 0.065), (0.062, 0.03), (0.062, 0.0)]


# --- Building ---------------------------------------------------------------------------

class Build:
    def __init__(self):
        self.v, self.f, self.uv, self.mat = [], [], [], []

    def vert(self, p):
        self.v.append(Vector(p))
        return len(self.v) - 1

    def face(self, ids, mat, uvs=None):
        self.f.append(list(ids))
        self.uv.append(list(uvs) if uvs else [(0.0, 0.0)] * len(ids))
        self.mat.append(mat)

    def mesh(self, name):
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
        me.update()
        return me


def circle(r, sides):
    return [(r * math.cos(2.0 * math.pi * k / sides), r * math.sin(2.0 * math.pi * k / sides)) for k in range(sides)]


def sweep(b, pts, profile, mat, planar=False, sharp=(), caps=(False, False), hint=Z):
    """`profile` (a closed loop of offsets along the path's normal and binormal) carried along
    `pts`. Bends are mitred. `planar`: the path lies flat, so the normal is the side its
    inside is on (to the right of the way it runs, seen from above) and the binormal is up.
    `sharp`: points where the surface creases (a welded corner)."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    dirs = [(pts[i + 1] - pts[i]).normalized() for i in range(n - 1)]
    rings = []
    prev = None
    for i in range(n):
        din, dout = dirs[max(i - 1, 0)], dirs[min(i, n - 2)]
        t = (din + dout).normalized()
        if planar:
            nn, bn = t.cross(Z).normalized(), Z
        else:
            nn = (hint if prev is None else prev)
            nn = nn - t * nn.dot(t)
            if nn.length < 1e-6:
                nn = Vector((1.0, 0.0, 0.0)) - t * t.x
            nn.normalize()
            bn = t.cross(nn)
            prev = nn
        m = dout - din
        s = 1.0
        if m.length > 1e-6:
            m.normalize()
            s = 1.0 / max(math.cos(math.acos(max(-1.0, min(1.0, din.dot(dout)))) * 0.5), 0.3)
        ring = []
        for a, c in profile:
            off = nn * a + bn * c
            if s != 1.0:
                off += m * off.dot(m) * (s - 1.0)
            ring.append(pts[i] + off)
        rings.append(ring)
    k = len(profile)
    # Which way round the faces go: the first one should look away from the path.
    q = [rings[0][0], rings[0][1], rings[1][1], rings[1][0]]
    nrm = (q[1] - q[0]).cross(q[3] - q[0])
    mid = (q[0] + q[1] + q[2] + q[3]) * 0.25 - (pts[0] + pts[1]) * 0.5
    flip = nrm.dot(mid) < 0.0
    ids = [[b.vert(p) for p in rings[0]]]
    for i in range(1, n):
        cur = [b.vert(p) for p in rings[i]]
        last = ids[-1]
        for j in range(k):
            f = [last[j], last[(j + 1) % k], cur[(j + 1) % k], cur[j]]
            b.face(reversed(f) if flip else f, mat)
        ids.append([b.vert(p) for p in rings[i]] if i in sharp else cur)
    for end, ring in ((0, rings[0]), (1, rings[-1])):
        if caps[end]:
            f = [b.vert(p) for p in ring]
            if (end == 0) != flip:
                f.reverse()
            b.face(f, mat)


def half_outline(depth, rad, y0):
    """From the left post back along the side, round the corner and along the back to the middle."""
    pts = [(-HX, y0 + (depth - rad - y0) * i / NS) for i in range(NS + 1)]
    cx, cy = -HX + rad, depth - rad
    for i in range(1, NC + 1):
        a = math.radians(90.0 * i / NC)
        pts.append((cx - rad * math.cos(a), cy + rad * math.sin(a)))
    for i in range(1, NB + 1):
        pts.append((cx * (1.0 - i / NB), depth))
    return pts


def outline(depth, rad, y0=0.0):
    left = half_outline(depth, rad, y0)
    return left + [(-x, y) for x, y in reversed(left[:-1])]


def inward(path):
    """Unit vectors into the goal at each point of a flat path."""
    out = []
    for i in range(len(path)):
        a, c = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        t = Vector((c[0] - a[0], c[1] - a[1], 0.0)).normalized()
        out.append(t.cross(Z))
    return out


def lengths(pts):
    out = [0.0]
    for i in range(1, len(pts)):
        out.append(out[-1] + (Vector(pts[i]) - Vector(pts[i - 1])).length)
    return out


# --- The parts --------------------------------------------------------------------------

def pipes(b):
    # Posts and crossbar: one pipe, welded at the corners.
    sweep(b, [(-HX, 0, -0.01), (-HX, 0, ZT), (HX, 0, ZT), (HX, 0, -0.01)], circle(R, 16), FRAME,
          sharp=(1, 2), hint=Vector((0, -1, 0)))
    # The top shelf, its spine and the support down the back.
    sweep(b, [(x, y, ZT) for x, y in outline(T, TOP_CORNER)], circle(RF, 10), FRAME)
    sweep(b, [(0, 0, ZT), (0, T, ZT)], circle(RF, 10), FRAME, hint=Vector((1, 0, 0)))
    sweep(b, [(0, T, ZT), (0, D, RF)], circle(RF, 10), FRAME, hint=Vector((1, 0, 0)))


def padding(b):
    # The bumper round the base, from the back of one post to the back of the other.
    sweep(b, [(x, y, 0.0) for x, y in outline(D, BASE_CORNER, R * 0.9)], BUMPER, PAD, planar=True, caps=(True, True))
    # Padding inside the top shelf's pipes: in and down from them.
    top = outline(T, TOP_CORNER, R + PAD_R)
    sweep(b, [Vector((x, y, ZT - 0.02)) + n * 0.022 for (x, y), n in zip(top, inward(top))], circle(PAD_R, 10), PAD,
          caps=(True, True))
    sweep(b, [(0, R + PAD_R, ZT - 0.026), (0, T - 0.03, ZT - 0.026)], circle(PAD_R, 10), PAD,
          caps=(True, True), hint=Vector((1, 0, 0)))
    # And under the support: toward the mouth and down.
    run = Vector((0.0, D - T, RF - ZT))
    into = Vector((0.0, run.z, -run.y)).normalized()
    a, c = Vector((0, T, ZT)) + run * 0.06, Vector((0, T, ZT)) + run * 0.93
    sweep(b, [a + into * 0.026, c + into * 0.026], circle(PAD_R, 10), PAD, caps=(True, True), hint=Vector((1, 0, 0)))


def lace(b, pts, wrap):
    """A cord wound round a pipe of radius `wrap` that follows `pts`."""
    pts = [Vector(p) for p in pts]
    s = lengths(pts)
    step = LACE_PITCH / 8.0
    count = int(s[-1] / step)
    out = []
    prev = None
    j = 0
    for i in range(count + 1):
        d = i * step
        while j < len(pts) - 2 and s[j + 1] < d:
            j += 1
        p = pts[j].lerp(pts[j + 1], (d - s[j]) / (s[j + 1] - s[j]))
        t = (pts[j + 1] - pts[j]).normalized()
        nn = (Z if prev is None else prev)
        nn = nn - t * nn.dot(t)
        if nn.length < 1e-6:
            nn = Vector((1.0, 0.0, 0.0))
        nn.normalize()
        prev = nn
        a = 2.0 * math.pi * d / LACE_PITCH
        out.append(p + (nn * math.cos(a) + t.cross(nn) * math.sin(a)) * (wrap + LACE_R * 0.6))
    sweep(b, out, circle(LACE_R, 3), PAD)


def lacing(b):
    lace(b, [(x, y, ZT) for x, y in outline(T, TOP_CORNER, R + 0.01)], RF)
    lace(b, [(0, R + 0.01, ZT), (0, T - RF, ZT)], RF)
    run = Vector((0.0, D - T, RF - ZT))
    lace(b, [Vector((0, T, ZT)) + run * 0.04, Vector((0, T, ZT)) + run * 0.93], RF)


def near_support(s, total):
    """0 at a post and at the middle of the back (where the netting is tied), 1 away from both."""
    d = min(s, total - s) / 0.22
    d = max(0.0, min(1.0, d))
    return d * d * (3.0 - 2.0 * d)


def netting(b):
    # The wall: from the top shelf's line down to the base's, a half at a time. The threads
    # run parallel to each half's post, so the two halves meet behind the support.
    top, base = half_outline(T, TOP_CORNER, Y0), half_outline(D, BASE_CORNER, Y0)
    st, sb = lengths(top), lengths(base)
    into = inward(base)
    for side in (1.0, -1.0):
        grid = []
        for j in range(len(top)):
            pt, pb = Vector((top[j][0], top[j][1], ZN)), Vector((base[j][0], base[j][1], ZB))
            fall = (pb - pt).length
            col = []
            for k in range(NV + 1):
                v = k / NV
                hang = math.sin(math.pi * v) * near_support(st[j] + (sb[j] - st[j]) * v, st[-1] + (sb[-1] - st[-1]) * v)
                p = pt.lerp(pb, v) + into[j] * SLACK * hang - Z * SLACK * 0.4 * hang
                p.x *= side
                col.append((b.vert(p), (st[j] + (sb[j] - st[j]) * v, fall * v)))
            grid.append(col)
        for j in range(len(grid) - 1):
            for k in range(NV):
                q = [grid[j][k], grid[j + 1][k], grid[j + 1][k + 1], grid[j][k + 1]]
                if side < 0.0:
                    q.reverse()
                b.face([i for i, _ in q], MESH, [uv for _, uv in q])
    # The top panel: rows from the crossbar back, each as wide as the shelf is there.
    rows = [y for x, y in top if x <= -HX + TOP_CORNER + 1e-9]
    nx = 16
    grid = []
    for y in rows:
        back = y - (T - TOP_CORNER)
        half = HX if back <= 0.0 else HX - TOP_CORNER + math.sqrt(max(TOP_CORNER ** 2 - back ** 2, 0.0))
        row = []
        for i in range(nx + 1):
            s = -1.0 + 2.0 * i / nx
            hang = math.sin(math.pi * abs(s)) * math.sin(math.pi * (y - Y0) / (T - Y0)) ** 0.7
            row.append((b.vert((s * half, y, ZN - TOP_SLACK * hang)), (s * half, y)))
        grid.append(row)
    for r in range(len(grid) - 1):
        for i in range(nx):
            q = [grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]]
            b.face([i for i, _ in q], MESH, [uv for _, uv in q])


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
    """Stand-ins to look at in Blender (the game has its own)."""
    out = []
    for name in MATS:
        old = bpy.data.materials.get(name)
        if old:
            bpy.data.materials.remove(old)
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        if name == "NetFrame":
            bsdf.inputs["Base Color"].default_value = (0.62, 0.012, 0.012, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.35
        else:
            bsdf.inputs["Base Color"].default_value = (0.86, 0.86, 0.86, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.85
        if name == "NetMesh":
            # Threads every 5 cm, see-through between them.
            uv = nt.nodes.new("ShaderNodeUVMap")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(uv.outputs["UV"], sep.inputs[0])
            lines = []
            for axis in ("X", "Y"):
                mul = nt.nodes.new("ShaderNodeMath")
                mul.operation = 'MULTIPLY'
                mul.inputs[1].default_value = 20.0
                nt.links.new(sep.outputs[axis], mul.inputs[0])
                fr = nt.nodes.new("ShaderNodeMath")
                fr.operation = 'FRACT'
                nt.links.new(mul.outputs[0], fr.inputs[0])
                lt = nt.nodes.new("ShaderNodeMath")
                lt.operation = 'LESS_THAN'
                lt.inputs[1].default_value = 0.12
                nt.links.new(fr.outputs[0], lt.inputs[0])
                lines.append(lt)
            mx = nt.nodes.new("ShaderNodeMath")
            mx.operation = 'MAXIMUM'
            nt.links.new(lines[0].outputs[0], mx.inputs[0])
            nt.links.new(lines[1].outputs[0], mx.inputs[1])
            nt.links.new(mx.outputs[0], bsdf.inputs["Alpha"])
            m.use_backface_culling = False
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = 'DITHERED'
        out.append(m)
    return out


def export(sc, objects):
    for o in sc.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    # No pictures in the file: the game puts its own materials on by name.
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "net.glb"), use_selection=True, use_active_scene=True,
                              export_image_format='NONE', export_apply=True, export_extras=False,
                              export_animations=False)


def main(write=True):
    sc = setup()
    mats = materials()
    frame = Build()
    pipes(frame)
    padding(frame)
    lacing(frame)
    mesh = Build()
    netting(mesh)
    parts = []
    for name, b in (("net_frame", frame), ("net_mesh", mesh)):
        drop(name)
        ob = bpy.data.objects.new(name, b.mesh(name))
        for m in mats:
            ob.data.materials.append(m)
        sc.collection.objects.link(ob)
        parts.append(ob)
        print(name + ":", sum(len(p.vertices) - 2 for p in ob.data.polygons), "triangles,", len(ob.data.vertices), "vertices")
    if write:
        export(sc, parts)
    return parts
