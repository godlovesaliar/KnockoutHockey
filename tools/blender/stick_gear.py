# Builds the skater stick and the goalie stick in Blender and exports them to
# assets/equip/stick.glb and goalie_stick.glb; tools/build_gear.gd (only=stick |
# goalie_stick) turns them into assets/characters/stick.res and goalie_stick.res.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/stick_gear.py").read()); build_all(True)
#
# Real senior dimensions (the game body is 1.8 m, so no scaling):
#   skater  heel to butt 1.50 m; shaft 28 x 19 mm; blade ~32 cm long, 5.5 cm tall at the
#           heel rising to 7 cm at the toe, 10 mm thick at the heel to 6 mm at the toe;
#           lie 135 deg (shaft 45 deg off the ice); 16 mm toe curve.
#   goalie  heel to butt 1.55 m; shaft 29 x 22 mm; paddle 8.5 cm wide up to 0.70 m with a
#           short shoulder into the shaft; blade ~39 cm long and 9 cm tall; lie 120 deg.
# Both bend from the shaft into the blade around one wide heel radius, with the blade's
# bottom rocking up a little toward the toe.
#
# Game frame: the heel at the origin, where the shaft's center line meets the line of the
# blade's bottom edge (a corner the heel radius rounds off); the shaft straight up +Y; the
# blade in the YZ plane running toward +Z and dropping at the lie; faces toward +-X, the
# toe curved toward -X (the forehand face).
# Objects become glTF nodes, and build_gear.gd sorts the surfaces by node name:
#   stick         shaft (the whole stick, black), tape (a skin over the blade and a knob
#                 over the butt end)
#   goalie_stick  body (the whole stick), grip (top wrap and knob), tape (over the blade)
# The "blade" meta (heel to toe along the bottom line) and "shaft" meta (heel to butt) in
# build_gear.gd come from blade_vector() and SPEC["shaft"].

import math
import os

import bmesh
import bpy
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\stick_gear.py")))))
OUT = os.path.join(PROJECT, "assets", "equip")
COLLECTION = "StickGear"

# shaft: heel to butt · sw / st: shaft width (in the blade plane) / thickness (across the
# face) · lie: angle between shaft and blade bottom (deg) · heel_r: outer radius of the
# heel bend · blade: bottom-line length from the heel corner to the tip of the toe ·
# bh: blade height (heel, toe) · bt: blade thickness (heel, toe) · toe_r: length the toe
# rounds off over · toe_low: how far up the blade the tip is (fraction) · rocker: (length, deg) the bottom turns up over at the toe
# · hook: toe curve depth · hosel: (height above the bend where the shaft starts
# thinning, thickness it thins to at the bend).
SKATER = dict(shaft=1.50, sw=0.028, st=0.019, lie=135.0, heel_r=0.13, blade=0.335,
              bh=(0.055, 0.07), bt=(0.010, 0.006), toe_r=0.05, rocker=(0.07, 9.0),
              hook=0.016, hosel=(0.24, 0.013))
GOALIE = dict(shaft=1.55, sw=0.029, st=0.022, lie=120.0, heel_r=0.13, blade=0.40,
              bh=(0.09, 0.09), bt=(0.013, 0.009), toe_r=0.028, toe_low=0.2, rocker=(0.06, 6.0),
              hook=0.008, hosel=(0.0, 0.016),
              paddle=dict(w=0.085, top=0.70, shoulder=0.045, t=(0.016, 0.019)))


def g(x, y, z):
    """Game coordinates (Y up) to Blender (Z up); the glTF exporter maps it back."""
    return Vector((x, -z, y))


def _smooth(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _lerp(a, b, t):
    return a + (b - a) * t


# --- The outline -------------------------------------------------------------------------
#
# Everything is lofted along one path in the blade plane (2D points are (z, y)): the back
# edge of the shaft from the butt down, around the heel radius, along the blade's bottom
# edge and up the rocker to the toe. Each station has the path's inward normal (into the
# stick), a width measured along it and a thickness across the face.

def _rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def path(spec, a0):
    """[(s, point, tangent, inward normal)] along the back / bottom edge, dense where it
    turns. a0: half-width of the stick at the bottom of the shaft (the back edge's offset
    from the shaft's center line). Also returns where the heel arc starts and ends (s)."""
    lie = math.radians(spec["lie"])
    d = (math.sin(lie), math.cos(lie))           # (z, y) heel to toe along the bottom line
    turn = math.pi - lie                         # how far the edge turns at the heel
    # Corner of the back edge (z = -a0) and the bottom line (through the origin).
    t_c = -a0 / d[0]
    corner = (-a0, t_c * d[1])
    tan_len = spec["heel_r"] * math.tan(turn / 2)
    arc0 = (corner[0], corner[1] + tan_len)      # where the shaft's back edge starts bending
    out = []

    def add(s, p, t):
        out.append((s, p, t, (-t[1], t[0])))

    top = spec["shaft"]
    s = 0.0
    # Shaft: sparse while nothing changes, dense over the hosel / paddle shoulder.
    ys = sorted({top, arc0[1], *[y for y in _shaft_breaks(spec) if arc0[1] < y < top]})[::-1]
    prev = top
    for i, y in enumerate(ys):
        s += prev - y
        prev = y
        add(s, (-a0, y), (0.0, -1.0))
    # Heel arc around center (-a0 + R, arc0.y).
    cen = (-a0 + spec["heel_r"], arc0[1])
    n_arc = 16
    for i in range(1, n_arc + 1):
        a = turn * i / n_arc
        p = _rot((-spec["heel_r"], 0.0), a)
        add(s + spec["heel_r"] * a, (cen[0] + p[0], cen[1] + p[1]), _rot((0.0, -1.0), a))
    s_arc = (out[len(ys) - 1][0], out[-1][0])
    # Blade bottom: straight, then the rocker turning up toward the toe.
    p0 = out[-1][1]
    u0 = p0[0] * d[0] + p0[1] * d[1]             # where the arc left the bottom line
    rl, rdeg = spec["rocker"]
    flat = spec["blade"] - u0 - rl
    n_flat = max(2, int(flat / 0.012))
    for i in range(1, n_flat + 1):
        f = flat * i / n_flat
        add(s_arc[1] + f, (p0[0] + d[0] * f, p0[1] + d[1] * f), d)
    p1, s1 = out[-1][1], out[-1][0]
    rr = rl / math.radians(rdeg)
    n_r = 10
    for i in range(1, n_r + 1):
        a = math.radians(rdeg) * i / n_r
        # Turning toward the inward normal, like the heel.
        nz, ny = -d[1], d[0]
        dz = math.sin(a) * rr * d[0] + (1 - math.cos(a)) * rr * nz
        dy = math.sin(a) * rr * d[1] + (1 - math.cos(a)) * rr * ny
        add(s1 + rr * a, (p1[0] + dz, p1[1] + dy), _rot(d, a))
    return out, s_arc, d


def _shaft_breaks(spec):
    """Heights where the shaft's section changes, sampled densely."""
    ys = []
    hz = spec["hosel"][0]
    for i in range(9):
        ys.append(hz * i / 8)
    p = spec.get("paddle")
    if p:
        for i in range(9):
            ys.append(p["top"] + p["shoulder"] * (i / 8 - 0.15))
        for i in range(8):
            ys.append(p["top"] * i / 8)
    ys.append(spec["shaft"] - 0.12)
    return ys


def sections(spec):
    """Stations [(s, center (z, y), normal, width, thickness, exponent)] for the whole
    stick, plus the s where the blade (past the heel arc) begins."""
    p = spec.get("paddle")
    a0 = (p["w"] if p else spec["sw"]) * 0.5
    pts, (sa0, sa1), d = path(spec, a0)
    s_end = pts[-1][0]
    out = []
    for s, pt, t, n in pts:
        # u: distance along the bottom line from the heel corner (blade side only).
        u = pt[0] * d[0] + pt[1] * d[1]
        y = pt[1]
        # Width and thickness up the shaft (by height), then into the blade (by u).
        if p:
            w_sh = _lerp(spec["sw"], p["w"], 1 - _smooth(p["top"], p["top"] + p["shoulder"], y))
            t_sh = spec["st"] if y > p["top"] + p["shoulder"] else _lerp(
                p["t"][0], p["t"][1], _smooth(0.0, p["top"], y))
            if p["top"] < y < p["top"] + p["shoulder"]:
                t_sh = _lerp(p["t"][1], spec["st"], _smooth(p["top"], p["top"] + p["shoulder"], y))
        else:
            w_sh = spec["sw"]
            t_sh = _lerp(spec["hosel"][1], spec["st"], _smooth(0.0, spec["hosel"][0], y))
        f = _smooth(spec["blade"] * 0.08, spec["blade"], u)
        w_bl = _lerp(spec["bh"][0], spec["bh"][1], f)
        t_bl = _lerp(spec["bt"][0], spec["bt"][1], f)
        # Blend from shaft to blade through the heel arc (by s).
        k = _smooth(sa0 - 0.02, sa1 + 0.015, s)
        w = _lerp(w_sh, w_bl, k)
        th = _lerp(t_sh, t_bl, k)
        # The toe: over the last toe_r the top comes down and the bottom up, round, to
        # meet at the tip a third of the way up.
        bot = 0.0
        left = s_end - s
        if left < spec["toe_r"]:
            q = 1 - left / spec["toe_r"]
            e = 1 - math.sqrt(max(0.02, 1 - q * q))   # (not quite zero: a clean end cap)
            bot = w * spec.get("toe_low", 0.33) * e
            w -= w * e
            th = _lerp(th, th * 0.8, q)
        # Center: on the shaft's center line up the shaft, half the width off the bottom
        # edge along the blade.
        off = _lerp(a0, bot + w * 0.5, k)
        c = (pt[0] + n[0] * off, pt[1] + n[1] * off)
        pexp = _lerp(4.0, 3.0, k)
        out.append((s, c, n, w, th, pexp))
    return out, sa1, d


def ring(c, n, w, th, pexp, segs, grow=0.0):
    """One cross-section loop (game Vectors): `th` across the face (x), `w` along the
    in-plane normal `n`."""
    pts = []
    for k in range(segs):
        a = math.tau * k / segs
        ca, sa = math.cos(a), math.sin(a)
        u = math.copysign(abs(ca) ** (2.0 / pexp), ca) * (th * 0.5 + grow)
        v = math.copysign(abs(sa) ** (2.0 / pexp), sa) * (w * 0.5 + grow)
        pts.append(Vector((u, c[1] + n[1] * v, c[0] + n[0] * v)))
    return pts


def loft(bm, rings, caps=(True, True)):
    """Rings of equal size joined into a tube; sides smooth, end caps flat."""
    loops = [[bm.verts.new(g(p.x, p.y, p.z)) for p in r] for r in rings]
    segs = len(rings[0])
    for i in range(len(loops) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            f = bm.faces.new((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]))
            f.smooth = True
    for e, loop in ((0, loops[0]), (1, loops[-1])):
        if caps[e]:
            f = bm.faces.new(loop)
            f.smooth = False


def hook(bm, spec, d, u_start):
    """Curves the blade toward -X, from nothing at u_start to `hook` at the toe."""
    L = spec["blade"]
    for v in bm.verts:
        z, y = -v.co.y, v.co.z
        u = z * d[0] + y * d[1]
        if u > u_start:
            v.co.x -= spec["hook"] * ((u - u_start) / (L - u_start)) ** 1.8


def blade_vector(spec):
    """Heel corner to the toe end of the bottom line (the "blade" meta, game axes)."""
    lie = math.radians(spec["lie"])
    return Vector((0.0, math.cos(lie), math.sin(lie))) * spec["blade"]


# --- Objects -------------------------------------------------------------------------------

def make_object(name, build, offset=Vector()):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    if bpy.data.meshes.get(name) is not None:
        bpy.data.meshes.remove(bpy.data.meshes[name])
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    col.objects.link(obj)
    obj.location = offset
    return obj


def material(name, color, rough=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = color
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    return m


def wrap(bm, spec, y0, y1, grow, bulb, segs=24):
    """Tape or grip wound round the shaft from y0 up to the butt end at y1, `grow`
    thick, swelling `bulb` more into a knob over the top 25 mm and rounded over the end."""
    hw, ht = spec["sw"] * 0.5, spec["st"] * 0.5
    rings = []
    n = (1.0, 0.0)   # (z, y): across the shaft in the blade plane
    ys = [y0 - 0.002] + [_lerp(y0, y1, i / 12) for i in range(13)]
    for i, y in enumerate(ys):
        sgrow = grow * (0.3 if i == 0 else 1.0) + bulb * _smooth(y1 - 0.03, y1 - 0.012, y)
        if y > y1 - 0.008:
            sgrow -= (bulb + grow * 0.5) * _smooth(y1 - 0.008, y1, y)
        rings.append(ring((0.0, y), n, hw * 2, ht * 2, 4.0, segs, sgrow))
    loft(bm, rings)


def body_rings(spec, segs, grow=0.0, s_from=None):
    st, s_blade, d = sections(spec)
    rings = [ring(c, n, w, th, p, segs, grow) for s, c, n, w, th, p in st
             if s_from is None or s >= s_from]
    return rings, s_blade, d


def build_stick(offset=Vector()):
    s = SKATER
    segs = 24

    def shaft(bm):
        rings, _, d = body_rings(s, segs)
        loft(bm, rings)
        hook(bm, s, d, 0.06)
    sh = make_object("shaft", shaft, offset)

    def tape(bm):
        # The blade is taped from just past the heel bend to the toe.
        _, s_blade, d = sections(s)
        rings, _, _ = body_rings(s, segs, 0.0007, s_blade - 0.01)
        loft(bm, rings)
        hook(bm, s, d, 0.06)
        wrap(bm, s, s["shaft"] - 0.11, s["shaft"] + 0.002, 0.0012, 0.003)
    tp = make_object("tape", tape, offset)
    sh.data.materials.append(material("StickShaft", (0.05, 0.05, 0.06, 1), 0.5))
    tp.data.materials.append(material("StickTape", (0.92, 0.92, 0.9, 1), 0.8))
    return [sh, tp]


def build_goalie_stick(offset=Vector()):
    s = GOALIE
    segs = 24

    def body(bm):
        rings, _, d = body_rings(s, segs)
        loft(bm, rings)
        hook(bm, s, d, 0.08)
    bd = make_object("body", body, offset)

    def grip(bm):
        wrap(bm, s, s["shaft"] - 0.22, s["shaft"] + 0.002, 0.0015, 0.004)
    gp = make_object("grip", grip, offset)

    def tape(bm):
        _, s_blade, d = sections(s)
        rings, _, _ = body_rings(s, segs, 0.0007, s_blade - 0.01)
        loft(bm, rings)
        hook(bm, s, d, 0.08)
    tp = make_object("tape", tape, offset)
    bd.data.materials.append(material("GoalieStickBody", (0.07, 0.07, 0.08, 1), 0.45))
    gp.data.materials.append(material("GoalieStickGrip", (0.02, 0.02, 0.02, 1), 0.8))
    tp.data.materials.append(material("StickTape", (0.92, 0.92, 0.9, 1), 0.8))
    return [bd, gp, tp]


# --- Export ----------------------------------------------------------------------------------

def export(objs, filename):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    keep = [o.location.copy() for o in objs]
    for o in objs:
        o.location = Vector()
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path_ = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path_, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_normals=True,
                              export_texcoords=False, export_materials="NONE")
    for o, k in zip(objs, keep):
        o.location = k
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print("exported %s: %d tris (%s)" % (path_, tris, ", ".join(o.name for o in objs)))


def build_all(do_export=False):
    # Both sticks have a "tape" node, so the skater stick is exported under its glTF
    # names first and then renamed out of the goalie stick's way.
    for name in ("skater_shaft", "skater_tape"):
        if bpy.data.objects.get(name) is not None:
            bpy.data.meshes.remove(bpy.data.objects[name].data)
    stick = build_stick()
    if do_export:
        export(stick, "stick.glb")
    for o in stick:
        o.name = "skater_" + o.name
        o.data.name = o.name
    goalie = build_goalie_stick(Vector((0.5, 0, 0)))
    if do_export:
        export(goalie, "goalie_stick.glb")
    print("blade metas: skater %s  goalie %s" % (tuple(round(v, 4) for v in blade_vector(SKATER)),
                                                   tuple(round(v, 4) for v in blade_vector(GOALIE))))
    return stick, goalie
