# Builds the team masks in Blender and exports them to assets/equip/; tools/build_gear.gd
# (only=team_mask) turns them into assets/characters/*.res.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/mask_gear.py").read()); build_all(True)
# Needs both heads in the scene: dump them with
#   godot --headless --path . -s res://tools/dump_heads.gd -- out=<dir>
# and import <dir>/head_male.obj, then <dir>/head_female.obj (forward -Z, up Y), so the
# objects named in HEADS exist.
#
#   lucha_a  luchador hood: a stretch-fabric hood over the whole head, eye and mouth holes
#   lucha_b  the same, open below the nose (mouth and chin bare)
#   lucha_c  the same as A with a padded crest over the top of the head
#            Each also as lucha_<x>_female, fitted to the female head (in the same frame:
#            the game fits it as the male one, so it is fitted through that same fit).
#            Surfaces: 0 hood (UV mapped: the pattern texture, see build_patterns),
#            1 extras (the crest; trim color). All three share one UV layout, so every
#            pattern fits every hood: u runs around the head (0.5 = the nose, seam at the
#            back), v up from the neck (0) to the crown (1).
#   vintage  an old-school fiberglass goalie face mask: a rigid shell over the face with
#            breathing holes, three chevron marks and elastic straps around the head.
#            Surfaces: 0 shell, 1 marks, 2 straps.
#
# Frame (game coordinates, meters) as tools/blender/helmet_gear.py: the male body's head box
# center at the origin, +Y up, +Z the face, +X the head's left. The game fits every body
# the way it fits helmets (SkaterVisual.HELMET_CROWN / HELMET_HEAD_W).

import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\mask_gear.py")))))
OUT = os.path.join(PROJECT, "assets", "equip")
TEX_OUT = os.path.join(PROJECT, "assets", "characters", "masks")
COLLECTION = "MaskGear"

HEAD_CENTER = (0.0, 1.6953, 0.0003)
# The dumped heads (tools/dump_heads.gd; the female one imported after the male, so its eyes
# object got the ".001"), and each body's head box (skeleton space, from the dump's
# printout) for fitting them as the game does.
HEADS = {
    "male": {"obj": "male_muscle_13290Mesh_s0", "eyes": "Eyes_s0",
             "box": ((-0.096931, 1.550604, -0.119257), (0.193861, 0.289396, 0.239142))},
    "female": {"obj": "female_genericMesh_s0", "eyes": "Eyes_s0.001",
               "box": ((-0.093388, 1.494648, -0.121553), (0.186776, 0.255352, 0.23085))},
}
# SkaterVisual's fitting constants: HELMET_CROWN, HELMET_HEAD_W, MASK_EYE.
CROWN = 0.1447
HEAD_W = 0.1939
MASK_EYE = Vector((0.0, 0.0255, 0.0747))
BODY = "male"   # the head the hood is fitted to (build_lucha builds one per body)

# Hood grid: NU columns around the head, NV rows from the neck hem up to the crown.
NU = 104
NV = 60
HEM_Y = -0.135      # bottom of the hood (under the jersey collar)
HOOD_OFF = 0.0035   # fabric over the skin
TEX_W, TEX_H = 1024, 512


def g(x, y, z):
    """Game coordinates (Y up, +Z front) to Blender (Z up); the glTF exporter maps back."""
    return Vector((x, -z, y))


def gv(v):
    return Vector((v.x, v.z, -v.y))


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# --- The reference heads ---------------------------------------------------------------------

_heads = {}


def body_fit(body):
    """(at, scale): where the game puts the masks' frame on this body (skeleton space), as
    SkaterVisual._build_team_mask does: on the eyes, scaled by eyes-to-crown height and
    across by head width."""
    h = HEADS[body]
    eo = bpy.data.objects[h["eyes"]]
    ev = [gv(eo.matrix_world @ v.co) for v in eo.data.vertices]
    lo = Vector([min(q[i] for q in ev) for i in range(3)])
    hi = Vector([max(q[i] for q in ev) for i in range(3)])
    e = (lo + hi) * 0.5
    pos, size = Vector(h["box"][0]), Vector(h["box"][1])
    sy = (pos.y + size.y - e.y) / (CROWN - MASK_EYE.y)
    sc = Vector((size.x / HEAD_W, sy, sy))
    at = Vector((pos.x + size.x * 0.5, e.y - MASK_EYE.y * sy, e.z - MASK_EYE.z * sy))
    return at, sc


def to_frame(body, p):
    at, sc = body_fit(body) if body not in _heads else _heads[body]["fit"]
    q = p - at
    return Vector((q.x / sc.x, q.y / sc.y, q.z / sc.z))


def head(body=None):
    """{bvh, eyes: [left, right] centers, points} of a body's head in the masks' frame."""
    body = body or BODY
    if body in _heads:
        return _heads[body]
    fit = body_fit(body)
    _heads[body] = {"fit": fit}
    verts, polys = [], []
    for name in (HEADS[body]["obj"], HEADS[body]["eyes"]):
        o = bpy.data.objects[name]
        base = len(verts)
        vs = [to_frame(body, gv(o.matrix_world @ v.co)) for v in o.data.vertices]
        verts += vs
        for p in o.data.polygons:
            pts = [vs[i] for i in p.vertices]
            # The head only: not the shoulders the dump also carries.
            if all(q.y > -0.2 and abs(q.x) < 0.13 for q in pts):
                polys.append(tuple(base + i for i in p.vertices))
        if name == HEADS[body]["obj"]:
            # (no eyes: they show through the eye holes)
            points = [q for q in vs if q.y > HEM_Y + 0.01 and abs(q.x) < 0.13]
    eo = bpy.data.objects[HEADS[body]["eyes"]]
    ev = [to_frame(body, gv(eo.matrix_world @ v.co)) for v in eo.data.vertices]
    left = [q for q in ev if q.x > 0]
    right = [q for q in ev if q.x < 0]
    eyes = [sum(left, Vector()) / len(left), sum(right, Vector()) / len(right)]
    _heads[body].update({"bvh": BVHTree.FromPolygons(verts, polys), "eyes": eyes, "points": points})
    return _heads[body]


def head_points():
    """The head's vertices above the hem."""
    return head()["points"]


def nearest(p):
    """(point, outward normal, distance signed: < 0 inside the head)."""
    loc, nrm, _, d = head()["bvh"].find_nearest(p)
    side = (p - loc).dot(nrm)
    return loc, nrm, d if side >= 0 else -d


def first_hit(origin, d):
    loc, nrm, _, _ = head()["bvh"].ray_cast(origin, d)
    if loc is None:
        return None, None
    if nrm.dot(d) > 0:
        nrm = -nrm
    return loc, nrm


# --- Scene helpers ---------------------------------------------------------------------------

def collection():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def replace(name):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    if bpy.data.meshes.get(name) is not None:
        bpy.data.meshes.remove(bpy.data.meshes[name])


def to_object(name, bm, offset=Vector()):
    replace(name)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection().objects.link(obj)
    obj.location = offset
    return obj


def apply_all(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    bpy.data.meshes.remove(old)
    mesh.name = obj.name


def solidify(obj, thick, offset=-1.0, rim_only=False):
    """Thickens a surface; rim_only keeps just the one surface plus the band around its
    edges and holes (the game draws it two-sided), for half the triangles."""
    m = obj.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thick
    m.offset = offset
    m.use_rim = True
    m.use_rim_only = rim_only
    m.use_even_offset = False   # (even offset spikes at the crown's pole fan)
    apply_all(obj)


def cut(obj, cutters):
    """Boolean-subtracts the cutter objects (then deletes them)."""
    for c in cutters:
        c.location = obj.location
        m = obj.modifiers.new("cut", "BOOLEAN")
        m.operation = "DIFFERENCE"
        m.solver = "EXACT"
        m.object = c
        m.use_hole_tolerant = True   # open surfaces: cut before solidifying
        c.hide_set(True)
    apply_all(obj)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)


def prism_cutter(name, outline, axis, z0, z1):
    """A prism from a closed outline extruded from z0 to z1 along a game axis: axis "z"
    takes outline points as (x, y), axis "x" as (z, y)."""
    def pt(a, b, w):
        return g(a, b, w) if axis == "z" else g(w, b, a)
    bm = bmesh.new()
    lo = [bm.verts.new(pt(a, b, z0)) for a, b in outline]
    hi = [bm.verts.new(pt(a, b, z1)) for a, b in outline]
    n = len(outline)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return to_object(name, bm)


def ellipse(cx, cy, rx, ry, n=48, rot=0.0, squash_top=0.0):
    out = []
    cr, sr = math.cos(rot), math.sin(rot)
    for k in range(n):
        t = math.tau * k / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        if y > 0:
            y *= 1.0 - squash_top
        out.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return out


def material(name, color, rough=0.5):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (color[0], color[1], color[2], 1.0)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


# --- Luchador hood ---------------------------------------------------------------------------

def hood_ring(t):
    """Base shape the hood is pulled in from: (y, ring radius x, ring radius z, z center)
    for t 0 (hem) .. 1 (crown): a capsule a little larger than the head."""
    top = 0.24
    if t < 0.55:
        y = HEM_Y + (0.02 - HEM_Y) * (t / 0.55)
        return y, 0.16, 0.19, 0.0
    a = (t - 0.55) / 0.45 * math.pi * 0.5
    return 0.02 + (top - 0.02) * math.sin(a), 0.16 * math.cos(a), 0.19 * math.cos(a), 0.0


def hood_rays():
    """Each hood vertex's ray (from outside, toward the head) and where the hood starts:
    horizontal rays inward below the brow, rays aimed at the head's middle above it."""
    starts, dirs = [], []
    for j in range(NV + 1):
        t = j / NV
        y, rx, rz, zc = hood_ring(t)
        srow, drow = [], []
        for i in range(NU):
            az = math.tau * i / NU - math.pi   # i = NU/2: az 0, the face
            p0 = Vector((0.0, 0.3, 0.0)) if j == NV else Vector((rx * math.sin(az), y, zc + rz * math.cos(az)))
            aim = Vector((0.0, min(y, 0.0) if t < 0.55 else -0.01, -0.005))
            d = aim - p0
            if t < 0.55:
                d.y = 0.0
            d.normalize()
            srow.append(p0)
            drow.append(d)
        starts.append(srow)
        dirs.append(drow)
    return starts, dirs


def hood_grid():
    """The hood's vertices as an NV+1 x NU grid (masks' frame), pulled onto the male head
    from outside along hood_rays, then relaxed like stretched fabric (relax)."""
    starts, dirs = hood_rays()
    pts = []
    for j in range(NV + 1):
        row = []
        for i in range(NU):
            hit, nrm = first_hit(starts[j][i], dirs[j][i])
            row.append(hit + nrm * HOOD_OFF if hit is not None else starts[j][i])
        pts.append(row)
    return relax(pts, dirs, 40, 0.5)


def relax(pts, dirs, iters, k):
    """Laplacian smoothing (fabric spans hollows: eye sockets, behind the ears), each pass
    pushed back out HOOD_OFF off the current head (BODY); the hem row keeps its height.
    Then any head points still through (ear rims between grid lines) push the nearby
    vertices out until none are."""
    pts = [[q.copy() for q in r] for r in pts]
    for it in range(iters):
        new = [[q.copy() for q in r] for r in pts]
        for j in range(1, NV):
            for i in range(NU):
                nb = (pts[j][(i - 1) % NU] + pts[j][(i + 1) % NU] + pts[j - 1][i] + pts[j + 1][i]) * 0.25
                new[j][i] = pts[j][i].lerp(nb, k)
        for i in range(NU):
            q = pts[0][i]
            nb = (pts[0][(i - 1) % NU] + pts[0][(i + 1) % NU]) * 0.5
            new[0][i] = Vector((q.x + (nb.x - q.x) * k, q.y, q.z + (nb.z - q.z) * k))
        pts = new
        for j in range(NV):
            for i in range(NU):
                loc, nrm, d = nearest(pts[j][i])
                if d < HOOD_OFF:
                    pts[j][i] = loc + nrm * HOOD_OFF
                # Seen from outside along its ray, nothing of the head may be in front
                # of it (the ears: thin flaps the nearest-point test passes through).
                rd = dirs[j][i]
                o = pts[j][i] - rd * 0.3
                hit, _ = first_hit(o, rd)
                if hit is not None and (pts[j][i] - o).dot(rd) > (hit - o).dot(rd) - HOOD_OFF:
                    pts[j][i] = pts[j][i] - rd * ((pts[j][i] - o).dot(rd) - (hit - o).dot(rd) + HOOD_OFF)
    for it in range(10):
        flat = [q for r in pts[:NV] for q in r]
        hb = BVHTree.FromPolygons(flat, [(j * NU + i, j * NU + (i + 1) % NU, (j + 1) * NU + (i + 1) % NU, (j + 1) * NU + i)
                                         for j in range(NV - 1) for i in range(NU)])
        bad = 0
        for q in head_points():
            loc, nrm, idx, d = hb.find_nearest(q)
            if loc is None or d > 0.03:
                continue
            outward = nrm if nrm.dot(loc) > 0 else -nrm
            if (q - loc).dot(outward) > -0.0015:
                bad += 1
                j, i = divmod(idx, NU)
                for jj in (j, j + 1):
                    for ii in (i, (i + 1) % NU):
                        if jj < NV:
                            pts[jj][ii] = pts[jj][ii] + outward * 0.0015
        if bad == 0:
            break
        print("  hood (%s): %d head points through, pushing out" % (BODY, bad))
    top = Vector((0.0, max(pts[NV - 1][i].y for i in range(NU)) + 0.002, 0.0))
    loc, nrm, d = nearest(top)
    pts[NV] = [loc + nrm * HOOD_OFF] * NU
    return pts


_grids = {}


def grid():
    """The hood grid for BODY. Other bodies start from the male one and are only
    relaxed onto their head, so each grid vertex stays on the same spot of the face
    and one set of pattern textures fits every body's hood."""
    global BODY
    if BODY not in _grids:
        if BODY == "male":
            _grids[BODY] = hood_grid()
        else:
            body = BODY
            BODY = "male"
            base = grid()
            _, dirs = hood_rays()
            BODY = body
            _grids[body] = relax(base, dirs, 12, 0.25)
    return _grids[BODY]


def hood_mesh(name, offset):
    """The hood surface from the grid, UV mapped (u around: 0.5 = the face; v up)."""
    pts = grid()
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    vs = [[bm.verts.new(g(*q)) for q in pts[j]] for j in range(NV)]
    tip = bm.verts.new(g(*pts[NV][0]))
    for j in range(NV - 1):
        for i in range(NU):
            i2 = (i + 1) % NU
            f = bm.faces.new((vs[j][i], vs[j][i2], vs[j + 1][i2], vs[j + 1][i]))
            u0, u1 = i / NU, (i + 1) / NU
            for loop, (u, v) in zip(f.loops, ((u0, j / NV), (u1, j / NV), (u1, (j + 1) / NV), (u0, (j + 1) / NV))):
                loop[uv].uv = (u, v)
    for i in range(NU):
        i2 = (i + 1) % NU
        f = bm.faces.new((vs[NV - 1][i], vs[NV - 1][i2], tip))
        for loop, (u, v) in zip(f.loops, (((i) / NU, (NV - 1) / NV), ((i + 1) / NU, (NV - 1) / NV), ((i + 0.5) / NU, 1.0))):
            loop[uv].uv = (u, v)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    out = sum((f.calc_center_median() - g(0, 0, 0)).dot(f.normal) for f in bm.faces)
    if out < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    obj = to_object(name, bm, offset)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


# Holes, in the front view (game x, y; cut straight back along z).
EYE_RX, EYE_RY, EYE_TILT, EYE_UP = 0.023, 0.0145, 0.14, 0.002
MOUTH = (0.0, -0.053, 0.026, 0.0135)   # center x, y, half width, half height
OPEN_UNDER = -0.034                    # B: the hood ends here, under the nose


def eye_outline(side, grow=0.0, n=48):
    """Almond eye hole for side +1 (the head's left) / -1, tilted up toward the temple."""
    e = head("male")["eyes"][0 if side > 0 else 1]   # every body's: the patterns' piping is drawn there
    return ellipse(e.x, e.y + EYE_UP, EYE_RX + grow, EYE_RY + grow, n, rot=EYE_TILT * side)


def mouth_outline(grow=0.0, n=48):
    return ellipse(MOUTH[0], MOUTH[1], MOUTH[2] + grow, MOUTH[3] + grow, n)


def open_outline():
    """B's lower edge in the side view (z, y): under the nose, along the cheek to under
    the ear, then straight down past the hem (the back of the neck stays covered)."""
    pts = [(0.3, OPEN_UNDER), (0.06, OPEN_UNDER), (0.035, OPEN_UNDER - 0.006),
           (0.012, -0.055), (-0.004, -0.09), (-0.012, -0.2), (0.3, -0.2)]
    return pts


def crest_mesh(name, offset):
    """A padded crest down the middle of the head: from above the brow over the crown
    to the back of the head, tallest over the crown."""
    pts = grid()
    front = [pts[j][NU // 2] for j in range(NV) if pts[j][NU // 2].y > 0.075]
    back = [pts[j][0] for j in reversed(range(NV)) if pts[j][0].y > 0.0]
    path = front + [pts[NV][0]] + back
    # Even spacing.
    lens = [0.0]
    for a, b in zip(path, path[1:]):
        lens.append(lens[-1] + (b - a).length)
    total = lens[-1]
    n = 60
    even = []
    k = 0
    for s in range(n + 1):
        d = total * s / n
        while k < len(lens) - 2 and lens[k + 1] < d:
            k += 1
        t = (d - lens[k]) / max(lens[k + 1] - lens[k], 1e-9)
        even.append(path[k].lerp(path[k + 1], t))
    bm = bmesh.new()
    segs = 16
    rings = []
    for s, p in enumerate(even):
        t = s / n
        tng = (even[min(s + 1, n)] - even[max(s - 1, 0)]).normalized()
        _, nrm, _ = nearest(p)
        nrm = (nrm - tng * nrm.dot(tng)).normalized()
        side = tng.cross(nrm).normalized()
        h = 0.004 + 0.03 * math.sin(math.pi * t) ** 0.7     # height off the hood
        w = 0.004 + 0.0045 * math.sin(math.pi * t) ** 0.5   # half width
        c = p + nrm * (h * 0.5 - 0.002)
        ring = []
        for q in range(segs):
            a = math.tau * q / segs
            ring.append(bm.verts.new(g(*(c + nrm * (math.sin(a) * h * 0.5) + side * (math.cos(a) * w)))))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for q in range(segs):
            q2 = (q + 1) % segs
            bm.faces.new((r0[q], r0[q2], r1[q2], r1[q]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    obj = to_object(name, bm, offset)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build_lucha(kind, offset, body="male"):
    """kind "a" full hood, "b" open below the nose, "c" full hood with a crest, fitted to
    a body's head. Returns {hood, extras}."""
    global BODY
    BODY = body
    name = "lucha_%s%s" % (kind, "" if body == "male" else "_" + body)
    hood = hood_mesh(name + "_hood", offset)
    cutters = [prism_cutter("cut_eye_l", eye_outline(1), "z", 0.0, 0.2),
               prism_cutter("cut_eye_r", eye_outline(-1), "z", 0.0, 0.2)]
    if kind == "b":
        cutters.append(prism_cutter("cut_open", open_outline(), "x", -0.2, 0.2))
    else:
        cutters.append(prism_cutter("cut_mouth", mouth_outline(), "z", 0.0, 0.2))
    cut(hood, cutters)   # on the open surface (a closed shell's exact boolean went wrong)
    solidify(hood, 0.0016, offset=1.0, rim_only=True)   # outward: the inside stays where it was fitted
    for p in hood.data.polygons:
        p.use_smooth = True
    if kind == "c":
        extras = crest_mesh(name + "_extras", offset)
    else:
        # No extras: a speck hidden inside the head keeps the surface slot.
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.001, matrix=__import__("mathutils").Matrix.Translation(g(0, 0, 0)))
        extras = to_object(name + "_extras", bm, offset)
    hood.data.materials.append(material("LuchaHood", (0.85, 0.1, 0.5), 0.45))
    extras.data.materials.append(material("LuchaExtras", (0.9, 0.7, 0.1), 0.4))
    BODY = "male"
    return {"hood": hood, "extras": extras}


# --- Hood patterns ---------------------------------------------------------------------------
# Each pattern is a TEX_W x TEX_H PNG in the hood's UV layout. The game's mask shader
# (scenes/actors/lucha_mask.gdshader) paints the base color, then mixes in accent 1 by
# red, accent 2 by green and accent 3 by blue. New patterns can be painted by hand over
# assets/characters/masks/lucha_uv_guide.png (eye and mouth holes white, the open cut of
# hood B grey, the center line) and listed in SkaterVisual.LUCHA_PATTERNS.

AA = 0.0007   # soft edge (m)


def texel_points():
    """Each texel's point on the hood (game coords), (TEX_H, TEX_W, 3), row 0 = v 0
    (Blender stores image rows bottom-up, as UV v runs)."""
    pts = grid()
    G = np.zeros((NV + 1, NU + 1, 3))
    for j in range(NV + 1):
        for i in range(NU + 1):
            q = pts[j][i % NU]
            G[j, i] = (q.x, q.y, q.z)
    u = (np.arange(TEX_W) + 0.5) / TEX_W * NU
    v = (np.arange(TEX_H) + 0.5) / TEX_H * NV
    i0 = np.clip(np.floor(u).astype(int), 0, NU - 1)
    j0 = np.clip(np.floor(v).astype(int), 0, NV - 1)
    fu = (u - i0)[None, :, None]
    fv = (v - j0)[:, None, None]
    a = G[j0][:, i0]
    b = G[j0][:, i0 + 1]
    c = G[j0 + 1][:, i0]
    d = G[j0 + 1][:, i0 + 1]
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def fill(sdf):
    """Coverage 0..1 from a signed distance (m, < 0 inside)."""
    return np.clip(0.5 - sdf / AA, 0.0, 1.0)


def sd_ellipse(X, Y, cx, cy, rx, ry, rot=0.0):
    dx, dy = X - cx, Y - cy
    c, s = math.cos(-rot), math.sin(-rot)
    x, y = dx * c - dy * s, dx * s + dy * c
    k = np.sqrt((x / rx) ** 2 + (y / ry) ** 2)
    return (k - 1.0) * min(rx, ry)


def sd_poly(X, Y, poly):
    """Signed distance to a closed polygon [(x, y)]."""
    d = np.full(X.shape, 1e9)
    inside = np.zeros(X.shape, bool)
    n = len(poly)
    for k in range(n):
        ax, ay = poly[k]
        bx, by = poly[(k + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = X - ax, Y - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0.0, 1.0)
        d = np.minimum(d, np.hypot(wx - ex * t, wy - ey * t))
        cond = ((ay > Y) != (by > Y)) & (X < (bx - ax) * (Y - ay) / (by - ay + 1e-12) + ax)
        inside ^= cond
    return np.where(inside, -d, d)


def mirror(poly):
    return [(-x, y) for x, y in reversed(poly)]


def star(cx, cy, r_out, r_in, n=5, rot=math.pi / 2):
    out = []
    for k in range(n * 2):
        r = r_out if k % 2 == 0 else r_in
        a = rot + math.pi * k / n
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def hole_piping(X, Y, front, width):
    """Coverage of bands `width` wide around the eye and mouth holes (cut along z, so in
    the front view's x, y)."""
    out = np.zeros(X.shape)
    for side in (1, -1):
        e = head("male")["eyes"][0 if side > 0 else 1]
        s = sd_ellipse(X, Y, e.x, e.y + EYE_UP, EYE_RX, EYE_RY, EYE_TILT * side)
        out = np.maximum(out, fill(s - width) * front)
    s = sd_ellipse(X, Y, MOUTH[0], MOUTH[1], MOUTH[2], MOUTH[3])
    return np.maximum(out, fill(s - width) * front)


def outlined(r, gch, s, mask=1.0, line=0.0018):
    """Adds shape `s` (signed distance) to accent 1 and its outline to accent 2."""
    return np.maximum(r, fill(s) * mask), np.maximum(gch, fill(np.abs(s) - line) * mask)


def build_patterns(save=True):
    P = texel_points()
    X, Y, Z = P[..., 0], P[..., 1], P[..., 2]
    front = (Z > 0.03).astype(float)
    A = np.arctan2(X, Z) * 0.095   # around the head: arc length from the center line (m)
    ex = head("male")["eyes"][0]
    zero = np.zeros(X.shape)
    pats = {}

    # "clasico": big eye surrounds and a mouth surround (accent 1) outlined in accent 2,
    # a flame point up the forehead, an accent 2 stripe over the crown, accent 3 piping.
    r, gch = zero, zero
    for side in (1, -1):
        r, gch = outlined(r, gch, sd_ellipse(X, Y, ex.x * side * 1.08, ex.y + 0.004, 0.036, 0.025, 0.3 * side), front)
    r, gch = outlined(r, gch, sd_ellipse(X, Y, 0.0, MOUTH[1], MOUTH[2] + 0.013, MOUTH[3] + 0.012), front)
    flame = [(0.0, 0.035), (0.016, 0.06), (0.012, 0.085), (0.024, 0.11), (0.0, 0.16)]
    r, gch = outlined(r, gch, sd_poly(A, Y, flame + mirror(flame)[1:-1]))
    crown = ((Y > 0.12) | (Z < 0)) & (np.abs(X) < 0.02)
    gch = np.maximum(gch, fill(np.where(crown, np.abs(X) - 0.012, 1.0)))
    r = r * (1 - gch)
    b = hole_piping(X, Y, front, 0.0028)
    pats["clasico"] = (r * (1 - b), gch * (1 - b), b)

    # "alas": wings sweeping back from the eyes over the ears (accent 1 outlined in
    # accent 2), an accent 3 star on the forehead, a mouth surround, accent 2 piping.
    r, gch = zero, zero
    wing = [(0.012, 0.03), (0.03, 0.05), (0.06, 0.07), (0.1, 0.085), (0.15, 0.08),
            (0.13, 0.05), (0.16, 0.035), (0.12, 0.015), (0.14, -0.005), (0.09, -0.005),
            (0.05, -0.01), (0.02, 0.0)]
    for side in (1, -1):
        r, gch = outlined(r, gch, sd_poly(A, Y, wing if side > 0 else mirror(wing)))
    r, gch = outlined(r, gch, sd_ellipse(X, Y, 0.0, MOUTH[1] - 0.004, MOUTH[2] + 0.012, MOUTH[3] + 0.016), front)
    s = sd_poly(A, Y, star(0.0, 0.088, 0.03, 0.013))
    b = fill(s)
    gch = np.maximum(gch, fill(np.abs(s) - 0.0018))
    r = r * (1 - gch) * (1 - b)
    b = b * (1 - gch)
    pip = hole_piping(X, Y, front, 0.0028)
    pats["alas"] = (r * (1 - pip), np.maximum(gch * (1 - pip), pip), b * (1 - pip))

    # "dividido": split down the middle, the head's left half (+x) in accent 2, the eye
    # surrounds in the other half's colors, an accent 1 center stripe and piping.
    left = fill(-X)
    for side in (1, -1):
        m = fill(sd_ellipse(X, Y, ex.x * side * 1.05, ex.y + 0.002, 0.033, 0.024, 0.25 * side)) * front
        left = left * (1 - m) if side > 0 else np.maximum(left, m)
    r = fill(np.abs(X) - 0.006)
    gch = left * (1 - r)
    pip = hole_piping(X, Y, front, 0.0028)
    pats["dividido"] = (np.maximum(r * (1 - pip), pip), gch * (1 - pip), zero)

    # "rayo": a lightning bolt from between the eyes up over the crown (accent 1 edged in
    # accent 3), jagged accent 2 eye surrounds and chin patch, accent 1 piping.
    bolt = [(-0.006, 0.03), (0.012, 0.06), (0.002, 0.065), (0.02, 0.1), (0.008, 0.104),
            (0.03, 0.16), (-0.004, 0.105), (0.007, 0.1), (-0.012, 0.07), (-0.002, 0.066),
            (-0.018, 0.035)]
    # Up the forehead in the front view, then on over the crown and down the back.
    s = sd_poly(X, np.where(Z > 0.06, Y, np.where(Y > 0.04, 0.12 + (0.06 - Z) * 0.9, -1.0)), bolt)
    r = fill(s)
    b = fill(np.abs(s) - 0.002)
    gch = zero
    jag = [(0.012, 0.012), (0.035, 0.0), (0.06, 0.018), (0.075, 0.05), (0.052, 0.04),
           (0.04, 0.052), (0.028, 0.04), (0.012, 0.045)]
    for side in (1, -1):
        gch = np.maximum(gch, fill(sd_poly(X, Y, jag if side > 0 else mirror(jag))) * front)
    chin = [(-0.03, -0.035), (0.03, -0.035), (0.02, -0.075), (0.0, -0.085), (-0.02, -0.075)]
    gch = np.maximum(gch, fill(sd_poly(X, Y, chin)) * front)
    r = r * (1 - b)
    gch = gch * (1 - np.maximum(r, b))
    pip = hole_piping(X, Y, front, 0.0028)
    pats["rayo"] = (np.maximum(r * (1 - pip), pip), gch * (1 - pip), b * (1 - pip))

    # The UV guide for painting new ones: holes white, hood B's open cut grey, the center
    # line white.
    holes = np.maximum(hole_piping(X, Y, front, 0.0), fill(np.abs(X) - 0.0006))
    cutb = fill(np.where((Y < OPEN_UNDER) & (Z > 0.035), -1.0, 1.0)) * 0.4
    guide = np.maximum(holes, cutb)
    pats["uv_guide"] = (guide, guide, guide)

    if save:
        os.makedirs(TEX_OUT, exist_ok=True)
        for name, (cr, cg, cb) in pats.items():
            img_name = "lucha_" + name
            old = bpy.data.images.get(img_name)
            if old is not None:
                bpy.data.images.remove(old)
            img = bpy.data.images.new(img_name, TEX_W, TEX_H, alpha=False)
            px = np.stack([cr, cg, cb, np.ones(cr.shape)], axis=-1).astype(np.float32)
            img.pixels.foreach_set(px.ravel())
            img.filepath_raw = os.path.join(TEX_OUT, img_name + ".png")
            img.file_format = "PNG"
            img.save()
            print("saved", img.filepath_raw)
    return pats


def preview_material(pattern, base=(0.86, 0.05, 0.48), a1=(0.91, 0.71, 0.13), a2=(0.05, 0.05, 0.05), a3=(0.95, 0.95, 0.93)):
    """A Blender material showing a pattern the way the game's shader colors it."""
    name = "LuchaPreview_" + pattern
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.45
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images["lucha_" + pattern]
    tex.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], sep.inputs[0])
    col = nt.nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (*base, 1)
    last = col.outputs[0]
    for ch, c in ((2, a3), (0, a1), (1, a2)):
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(sep.outputs[ch], mix.inputs[0])
        nt.links.new(last, mix.inputs[6])
        mix.inputs[7].default_value = (*c, 1)
        last = mix.outputs[2]
    nt.links.new(last, bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m


# --- Vintage goalie face mask ----------------------------------------------------------------

V_CLEAR = 0.009      # the shell's least gap over the face (the nose tip)
V_THICK = 0.004
V_LIFT = 0.006       # straps over the hood line (hair under them)
# The outline in the front view (x, y), the right half from the top center down to the
# chin; mirrored for the left.
V_OUTLINE = [(0.0, 0.118), (0.029, 0.113), (0.048, 0.098), (0.06, 0.072), (0.066, 0.04),
             (0.066, 0.005), (0.062, -0.03), (0.054, -0.062), (0.041, -0.09), (0.022, -0.11),
             (0.0, -0.116)]
V_EYE = (0.024, 0.0175)   # eye hole half sizes (a little teardrop: wider at the outer corner)
# Breathing holes (x, y) and their radius: forehead rows, cheeks, around the mouth, chin.
V_HOLE_R = 0.0033
V_HOLES = ([(x, 0.058) for x in (-0.04, -0.024, -0.008, 0.008, 0.024, 0.04)]
           + [(x, 0.075) for x in (-0.032, -0.016, 0.0, 0.016, 0.032)]
           + [(s * x, y) for s in (1, -1) for x, y in ((0.03, -0.032), (0.045, -0.03), (0.056, -0.022),
                                                       (0.036, -0.047), (0.051, -0.045))]
           + [(x, -0.056) for x in (-0.018, -0.006, 0.006, 0.018)]
           + [(x, -0.07) for x in (-0.024, -0.012, 0.0, 0.012, 0.024)]
           + [(x, -0.086) for x in (-0.012, 0.0, 0.012)])
# Chevrons: center (x, y), turn (rad, 0 = pointing down), size.
V_MARKS = [(0.0, 0.096, 0.0, 1.25), (0.045, -0.004, 0.35, 1.1), (-0.045, -0.004, -0.35, 1.1)]


def v_outline(n=160):
    """The closed outline, evenly resampled (front view x, y)."""
    half = V_OUTLINE
    full = half + [(-x, y) for x, y in reversed(half[1:-1])]
    pts = [Vector((x, y, 0)) for x, y in full]
    # A smooth closed curve through the points (Catmull-Rom), then evenly spaced.
    dense = []
    m = len(pts)
    for k in range(m):
        p0, p1, p2, p3 = pts[k - 1], pts[k], pts[(k + 1) % m], pts[(k + 2) % m]
        for s in range(20):
            t = s / 20
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    lens = [0.0]
    for a, b in zip(dense, dense[1:] + dense[:1]):
        lens.append(lens[-1] + (b - a).length)
    out = []
    k = 0
    for s in range(n):
        d = lens[-1] * s / n
        while lens[k + 1] < d:
            k += 1
        t = (d - lens[k]) / (lens[k + 1] - lens[k])
        out.append(dense[k].lerp(dense[(k + 1) % len(dense)], t))
    return [(q.x, q.y) for q in out]


_vfield = None


def v_field():
    """The shell's front surface as z over the front view: (xs, ys, Z). Pulled in to the
    face, at least V_CLEAR off it, smoothed into a rigid shell."""
    global _vfield
    if _vfield is not None:
        return _vfield
    xs = np.linspace(-0.09, 0.09, 91)
    ys = np.linspace(-0.13, 0.135, 133)
    C = np.full((len(ys), len(xs)), -1.0)
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            hit, _ = first_hit(Vector((x, y, 0.4)), Vector((0, 0, -1)))
            if hit is not None and hit.z > 0.0:
                C[j, i] = hit.z + V_CLEAR
    F = np.where(C > 0, C, np.nan)
    F = np.where(np.isnan(F), np.nanmax(C) * 0.5, F)

    def blur(a, r=4):
        k = np.exp(-np.linspace(-2, 2, 2 * r + 1) ** 2)
        k /= k.sum()
        pad = np.pad(a, r, mode="edge")
        a = np.apply_along_axis(lambda m: np.convolve(m, k, mode="valid"), 0, pad)
        return np.apply_along_axis(lambda m: np.convolve(m, k, mode="valid"), 1, a)
    for it in range(60):
        F = np.maximum(blur(F), C)
    F = blur(F, 2)
    F = np.maximum(F, C)
    _vfield = (xs, ys, F)
    return _vfield


def v_z(x, y, lift=0.0):
    """The shell's front at (x, y), and the normal there."""
    xs, ys, F = v_field()
    fx = (x - xs[0]) / (xs[1] - xs[0])
    fy = (y - ys[0]) / (ys[1] - ys[0])
    i = int(max(0, min(len(xs) - 2, math.floor(fx))))
    j = int(max(0, min(len(ys) - 2, math.floor(fy))))
    u, v = fx - i, fy - j

    def at(a, b):
        return F[b, a]
    z = (at(i, j) * (1 - u) + at(i + 1, j) * u) * (1 - v) + (at(i, j + 1) * (1 - u) + at(i + 1, j + 1) * u) * v
    dzdx = ((at(i + 1, j) - at(i, j)) * (1 - v) + (at(i + 1, j + 1) - at(i, j + 1)) * v) / (xs[1] - xs[0])
    dzdy = ((at(i, j + 1) - at(i, j)) * (1 - u) + (at(i + 1, j + 1) - at(i + 1, j)) * u) / (ys[1] - ys[0])
    n = Vector((-dzdx, -dzdy, 1.0)).normalized()
    return Vector((x, y, z)) + n * lift, n


def v_shell(name, offset):
    """The shell surface: rings from the middle of the face out to the outline."""
    ol = v_outline(96)
    c = (0.0, 0.0)
    rings = 22
    bm = bmesh.new()
    center = bm.verts.new(g(*v_z(*c)[0]))
    vs = []
    for r in range(1, rings + 1):
        t = r / rings
        row = []
        for (x, y) in ol:
            p, _ = v_z(c[0] + (x - c[0]) * t, c[1] + (y - c[1]) * t)
            row.append(bm.verts.new(g(*p)))
        vs.append(row)
    n = len(ol)
    for k in range(n):
        bm.faces.new((center, vs[0][k], vs[0][(k + 1) % n]))
    for r in range(rings - 1):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((vs[r][k], vs[r + 1][k], vs[r + 1][k2], vs[r][k2]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if sum(f.normal.dot(g(0, 0, 1)) for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    obj = to_object(name, bm, offset)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def v_eye(side, n=40):
    """Eye hole outline: an oval, fuller toward the outer corner."""
    e = head("male")["eyes"][0 if side > 0 else 1]
    out = []
    for k in range(n):
        t = math.tau * k / n
        x, y = math.cos(t) * V_EYE[0], math.sin(t) * V_EYE[1]
        outer = (x * side) > 0
        if not outer:
            y *= 1.0 - 0.25 * (abs(x) / V_EYE[0]) ** 2
        out.append((e.x + 0.002 * side + x, e.y + 0.003 + y - 0.002 * (x * side) / V_EYE[0]))
    return out


def chevron(cx, cy, turn, size, n=8):
    """A V pointing down at turn 0: [(left edge point, right edge point)] pairs along it
    from one tip through the point to the other (front view x, y)."""
    w, h, t = 0.013 * size, 0.012 * size, 0.0045 * size
    a, b, c = Vector((-w, h * 0.5)), Vector((0.0, -h * 0.5)), Vector((w, h * 0.5))
    d1, d2 = (b - a).normalized(), (c - b).normalized()
    n1, n2 = Vector((-d1.y, d1.x)), Vector((-d2.y, d2.x))
    miter = (n1 + n2).normalized()
    miter = miter / miter.dot(n1)
    pairs = []
    for k in range(n + 1):
        s = k / n
        pairs.append((a.lerp(b, s), n1 if k < n else miter))
    for k in range(1, n + 1):
        s = k / n
        pairs.append((b.lerp(c, s), n2))
    cr, sr = math.cos(turn), math.sin(turn)

    def rot(q):
        return (cx + q.x * cr - q.y * sr, cy + q.x * sr + q.y * cr)
    return [(rot(p + m * t * 0.5), rot(p - m * t * 0.5)) for p, m in pairs]


def v_marks(name, offset):
    """The chevron decals, laid on the shell's front, a hair above it."""
    bm = bmesh.new()
    for cx, cy, turn, size in V_MARKS:
        strip = chevron(cx, cy, turn, size)
        rows = []
        for l, r in strip:
            row = []
            for k in range(4):
                q = Vector(l).lerp(Vector(r), k / 3)
                p, _ = v_z(q.x, q.y, 0.0007)
                row.append(bm.verts.new(g(*p)))
            rows.append(row)
        for r0, r1 in zip(rows, rows[1:]):
            for k in range(3):
                bm.faces.new((r0[k], r1[k], r1[k + 1], r0[k + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if sum(f.normal.dot(g(0, 0, 1)) for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    obj = to_object(name, bm, offset)
    solidify(obj, 0.0006)
    return obj


def ribbon(bm, pts, nrms, width, thick):
    """A flat strap along pts, lying on the surface with normals nrms."""
    rings = []
    for k, (p, n) in enumerate(zip(pts, nrms)):
        tng = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        n = (n - tng * n.dot(tng)).normalized()
        side = tng.cross(n).normalized()
        ring = [p + side * width * 0.5, p + side * width * 0.5 + n * thick,
                p - side * width * 0.5 + n * thick, p - side * width * 0.5]
        rings.append([bm.verts.new(g(*q)) for q in ring])
    for r0, r1 in zip(rings, rings[1:]):
        for q in range(4):
            q2 = (q + 1) % 4
            bm.faces.new((r0[q], r0[q2], r1[q2], r1[q]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def hood_row(y):
    """Grid row index closest to height y (at the sides)."""
    pts = grid()
    return min(range(NV), key=lambda j: abs(pts[j][NU // 4].y - y))


def strap_path(row, x_end):
    """From the shell's edge at its side (x = +-x_end) around the back of the head along
    hood row `row`, lifted V_LIFT: [(point, normal)]."""
    pts = grid()
    out = []
    # Columns from the left side around the back to the right: i runs 0 (back) .. NU/2
    # (front); the left (+x) side is i > NU/2.
    cols = [i for i in range(NU // 2, NU)] + [i for i in range(0, NU // 2)]
    ring = [pts[row][i] for i in cols]
    keep = [q for q in ring if q.z < 0.0 or abs(q.x) > x_end + 0.004]
    # Split: the left run (x > 0, from the front edge back), then the right.
    left = [q for q in ring[:NU // 2] if q in keep]
    right = [q for q in ring[NU // 2:] if q in keep]
    path = left + right
    for q in path:
        _, n, _ = nearest(q)
        out.append((q + n * V_LIFT, n))
    return out


def v_straps(name, offset):
    bm = bmesh.new()
    # Upper strap above the ears, lower one just under them (lower, it stood off the neck
    # where the hood spans the hollow behind the jaw).
    for y_edge, y_back in ((0.05, 0.06), (-0.035, -0.042)):
        # Edge anchor: on the shell's side, just inside the outline.
        xs = max(x for x, y in v_outline() if abs(y - y_edge) < 0.01) - 0.006
        row = hood_row(y_back)
        # Riveted on the outside of the shell's sides, then straight back to the head.
        a_l, _ = v_z(xs, y_edge, 0.0012)
        a_r, _ = v_z(-xs, y_edge, 0.0012)
        path = [(p, n) for p, n in strap_path(row, xs) if p.z < a_l.z - 0.03]
        pts = [a_l] + [p for p, n in path] + [a_r]
        # The anchors lie as the strap does where it leaves them.
        nrms = [path[0][1]] + [n for p, n in path] + [path[-1][1]]
        ribbon(bm, pts, nrms, 0.013, 0.0022)
    # Over the top: from the shell's top to the upper strap at the back.
    pts = grid()
    top = []
    for j in range(NV):
        q = pts[j][NU // 2]
        if q.y > 0.112:
            top.append(q)
    back = [pts[j][0] for j in reversed(range(NV)) if pts[j][0].y > 0.055]
    path = top + [pts[NV][0]] + back
    ps, ns = [], []
    for q in path:
        _, n, _ = nearest(q)
        ps.append(q + n * V_LIFT)
        ns.append(n)
    a, n = v_z(0.0, 0.106, -V_THICK * 0.5)
    ribbon(bm, [a] + ps, [ns[0]] + ns, 0.016, 0.0022)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    obj = to_object(name, bm, offset)
    return obj


def build_vintage(offset):
    shell = v_shell("vintage_shell", offset)
    cutters = [prism_cutter("cut_veye_l", v_eye(1), "z", 0.0, 0.25),
               prism_cutter("cut_veye_r", v_eye(-1), "z", 0.0, 0.25)]
    holes = bmesh.new()
    for x, y in V_HOLES:
        ol = ellipse(x, y, V_HOLE_R, V_HOLE_R, 10)
        lo = [holes.verts.new(g(a, b, 0.0)) for a, b in ol]
        hi = [holes.verts.new(g(a, b, 0.25)) for a, b in ol]
        for k in range(len(ol)):
            k2 = (k + 1) % len(ol)
            holes.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
        holes.faces.new(list(reversed(lo)))
        holes.faces.new(hi)
    bmesh.ops.recalc_face_normals(holes, faces=list(holes.faces))
    cutters.append(to_object("cut_vholes", holes))
    cut(shell, cutters)
    solidify(shell, V_THICK, rim_only=True)
    b = shell.modifiers.new("bevel", "BEVEL")
    b.width = 0.0012
    b.segments = 1
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(50)
    apply_all(shell)
    for p in shell.data.polygons:
        p.use_smooth = True
    marks = v_marks("vintage_marks", offset)
    straps = v_straps("vintage_straps", offset)
    shell.data.materials.append(material("VintageShell", (0.9, 0.88, 0.8), 0.35))
    marks.data.materials.append(material("VintageMarks", (0.7, 0.1, 0.08), 0.4))
    straps.data.materials.append(material("VintageStraps", (0.06, 0.06, 0.06), 0.6))
    return {"shell": shell, "marks": marks, "straps": straps}


# --- Export ----------------------------------------------------------------------------------

def export(parts, roles, filename, uvs=False):
    """Exports one mask, its parts named by role (the glTF node names build_gear.gd
    reads), at the origin."""
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
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_normals=True,
                              export_texcoords=uvs, export_materials="NONE")
    for o, name, loc in keep:
        o.name = name
        o.location = loc
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print("exported %s: %d tris" % (path, tris))


def build_all(do_export=False):
    global _vfield, BODY
    _vfield = None
    _grids.clear()
    _heads.clear()
    BODY = "male"
    for o in list(bpy.data.objects):
        if o.name.startswith(("cut_", "lucha_", "vintage_", "pv_")):
            bpy.data.objects.remove(o, do_unlink=True)
    if do_export:
        build_patterns(True)
    out = {}
    for b, body in enumerate(("male", "female")):
        for k, kind in enumerate("abc"):
            key = kind + ("" if body == "male" else "_" + body)
            out[key] = build_lucha(kind, g(*HEAD_CENTER) + g(0.3 * (k + 1), 0.0, -0.4 * b), body)
            if do_export:
                export(out[key], ["hood", "extras"], "lucha_%s.glb" % key, uvs=True)
    out["vintage"] = build_vintage(g(*HEAD_CENTER))
    if do_export:
        export(out["vintage"], ["shell", "marks", "straps"], "vintage_mask.glb")
    return out
