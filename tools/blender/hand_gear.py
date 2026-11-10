# Builds the skater's hockey glove and bare fight fist in Blender and exports them as
# .glb files to assets/equip/. tools/build_gear.gd turns those into
# assets/characters/glove.res and fist.res.
#
# Run it in Blender's Python console or text editor:
#   exec(open(r"<project>/tools/blender/hand_gear.py").read())
#
# Both models are right hands, sized for a 1.8 m body, in game coordinates (glTF +Y up):
# the wrist at the origin, fingers up +Y and curled toward the palm (-Z), the back of
# the hand +Z, the thumb on the -X side. The game mirrors them for the left hand. The
# glove is closed around the stick, which runs along X through (0, GRIP_UP, -GRIP_IN);
# build_gear.gd and skater_visual.gd hold the same two numbers.
#
# Everything is written in game coordinates and mapped to Blender's Z-up with g(); the
# glTF exporter maps it back.

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\hand_gear.py")))))
OUT = os.path.join(PROJECT, "assets", "equip")
COLLECTION = "HandGear"

GRIP_UP = 0.065
GRIP_IN = 0.05


def g(x, y, z):
    """Game coordinates (Y up, +Z = back of the hand) to Blender (Z up)."""
    return Vector((x, -z, y))


# --- Mesh building -----------------------------------------------------------------

def _frame(along, across_hint):
    """Columns (across, along, depth) as a rotation: length runs along `along`."""
    y = along.normalized()
    x = (across_hint - y * across_hint.dot(y)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


def add_box(bm, center, size, bevel, segs=3, along=None, across=None):
    """A box of `size` (across, along, depth) with rounded edges, centered at `center`,
    its length on `along` and its width on `across` (Blender vectors). Without `along`
    the size is in Blender axes: (game x, game depth, game height)."""
    tmp = bmesh.new()
    geom = bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bev = min(bevel, min(size) * 0.49)
    bmesh.ops.bevel(tmp, geom=list(tmp.edges) + list(tmp.verts), offset=bev, offset_type="OFFSET",
                    segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    m = Matrix.Identity(3)
    if along is not None:
        m = _frame(along, across if across is not None else Vector((1, 0, 0)))
    xf = Matrix.Translation(center) @ m.to_4x4()
    bmesh.ops.transform(tmp, matrix=xf, verts=list(tmp.verts))
    _merge(bm, tmp)


def add_segment(bm, a, b, width, depth, bevel, gap=0.0, segs=3, across=Vector((1, 0, 0)), grow=0.0):
    """A rounded box from point a to point b (Blender vectors), `gap` shorter overall."""
    d = b - a
    length = d.length - gap + grow
    add_box(bm, (a + b) * 0.5, (width, length, depth), bevel, segs, along=d, across=across)


def add_tube(bm, rings, segs=28, cap_top=False, cap_bottom=False):
    """An oval tube through rings [(center (Blender), rx, ry)], each ring in its XY plane.
    Faces point outward when the rings climb +Z (inward when they descend)."""
    tmp = bmesh.new()
    loops = []
    for c, rx, ry in rings:
        loop = []
        for k in range(segs):
            a = math.tau * k / segs
            loop.append(tmp.verts.new(c + Vector((math.cos(a) * rx, math.sin(a) * ry, 0))))
        loops.append(loop)
    for i in range(len(loops) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            tmp.faces.new((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]))
    if cap_top:
        tmp.faces.new(loops[-1])
    if cap_bottom:
        tmp.faces.new(list(reversed(loops[0])))
    _merge(bm, tmp)


def add_torus(bm, center, rx, ry, minor, segs=28, minor_segs=8):
    """An oval ring in the XY plane (Blender) around `center`."""
    tmp = bmesh.new()
    loops = []
    for k in range(segs):
        a = math.tau * k / segs
        c = Vector((math.cos(a) * rx, math.sin(a) * ry, 0))
        out = Vector((math.cos(a) * ry, math.sin(a) * rx, 0)).normalized()
        loop = []
        for j in range(minor_segs):
            b = math.tau * j / minor_segs
            loop.append(tmp.verts.new(center + c + out * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor))))
        loops.append(loop)
    for k in range(segs):
        k2 = (k + 1) % segs
        for j in range(minor_segs):
            j2 = (j + 1) % minor_segs
            tmp.faces.new((loops[k][j], loops[k2][j], loops[k2][j2], loops[k][j2]))
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    _merge(bm, tmp)


def add_sphere(bm, center, radius, segs=12, rings=8, scale=(1, 1, 1)):
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=segs, v_segments=rings, radius=radius)
    for v in tmp.verts:
        v.co = center + Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    _merge(bm, tmp)


def _merge(bm, tmp):
    remap = {}
    for v in tmp.verts:
        remap[v] = bm.verts.new(v.co)
    for f in tmp.faces:
        bm.faces.new([remap[v] for v in f.verts])
    tmp.free()


def arc_point(center_y, center_z, r, th_deg, x):
    """A point on a circle around the stick (game coords): angle 0 = toward the back of
    the hand (+Z), 90 = up the fingers (+Y), 180 = the palm side (-Z)."""
    th = math.radians(th_deg)
    return g(x, center_y + r * math.sin(th), center_z + r * math.cos(th))


def collection():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def make_object(name, bm, smooth=True):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    mesh = bpy.data.meshes.get(name)
    if mesh is not None:
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    collection().objects.link(obj)
    return obj


def material(name, color):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = color
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.6
    return m


# --- The glove ---------------------------------------------------------------------
#
# Built like the jersey (build_jersey.py): overlapping volumes fused into one skin by a
# voxel remesh and smoothed, so it reads as one padded glove rather than parts; then the
# construction is carved back in as stitched grooves (backhand pad seams, the breaks
# between finger rolls, the thumb joint, the cuff's panels) and the result decimated.

# Fingers: index (thumb side, -X) to pinky, wrapped over and around the stick.
# [x, roll radius around the stick, width, depth, start height]
FINGERS = [(-0.0378, 0.0365, 0.024, 0.027, 0.097),
           (-0.0126, 0.038, 0.0245, 0.028, 0.099),
           (0.0126, 0.0368, 0.024, 0.027, 0.098),
           (0.0374, 0.0335, 0.0215, 0.025, 0.094)]
FINGER_ARC = (98.0, 226.0)      # where each finger's roll starts and ends around the stick
FINGER_BREAKS = (140.0, 186.0)  # grooves between the three rolls of a finger
THUMB = [(-0.052, 0.01, -0.01), (-0.059, 0.056, -0.044), (-0.042, 0.072, -0.098)]


def _smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def add_sweep(bm, pts, radii, segs=20, across=Vector((1, 0, 0))):
    """A closed tube along points `pts` (Blender), cross-section ellipses (half width,
    half depth) from `radii`, its width kept on `across`; round end caps."""
    tmp = bmesh.new()
    loops = []
    n = len(pts)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        x = (across - t * across.dot(t)).normalized()
        y = t.cross(x)
        rx, ry = radii[i]
        loops.append([tmp.verts.new(p + (x * math.cos(math.tau * k / segs) * rx + y * math.sin(math.tau * k / segs) * ry))
                      for k in range(segs)])
    for i in range(n - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            tmp.faces.new((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]))
    tmp.faces.new(list(reversed(loops[0])))
    tmp.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    _merge(bm, tmp)


def _ellipsoid(bm, center, frame_cols, radii, squareness=1.0):
    """An ellipsoid at `center` with axes = columns of frame_cols scaled by radii.
    squareness < 1 makes it a superellipsoid: a pillow with a flatter face and rounded
    edges (0.4: a puffy pad)."""
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=24, v_segments=16, radius=1.0)
    m = Matrix((frame_cols[0] * radii[0], frame_cols[1] * radii[1], frame_cols[2] * radii[2])).transposed()
    for v in tmp.verts:
        c = v.co
        if squareness != 1.0:
            c = Vector([math.copysign(abs(a) ** squareness, a) for a in c])
        v.co = center + m @ c
    _merge(bm, tmp)


PAD = 0.45   # squareness of the padded pillows


def _tube(bm, pts, radii, across=Vector((1, 0, 0)), segs=20):
    """Swept tube with ellipsoid end caps (Blender coords)."""
    add_sweep(bm, pts, radii, segs=segs, across=across)
    n = len(pts)
    for i, d in ((0, -1.0), (n - 1, 1.0)):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() * d
        x = (across - t * across.dot(t)).normalized()
        y = t.cross(x)
        rx, ry = radii[i]
        _ellipsoid(bm, pts[i], (x, y, t), (rx, ry, min(rx, ry) * 0.9))


def _finger_path(x, r, y0, steps=18):
    """Game-coordinate points: up from the knuckle, then around the stick."""
    sy, sz = GRIP_UP, -GRIP_IN
    a0, a1 = FINGER_ARC
    start = Vector((x, y0, 0.006))
    first = Vector((x, sy + r * math.sin(math.radians(a0)), sz + r * math.cos(math.radians(a0))))
    pts = [start.lerp(first, k / 3.0) for k in range(3)]
    for k in range(steps + 1):
        th = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append(Vector((x, sy + r * math.sin(th), sz + r * math.cos(th))))
    return pts


def _gv(v):
    return g(v.x, v.y, v.z)


def _fuse(obj, voxel, smooth_iters, smooth_factor=0.6):
    rm = obj.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.use_smooth_shade = True
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = smooth_factor
    sm.iterations = smooth_iters
    _apply_all(obj)


def _carve(obj, depth_fn):
    """Push vertices in along their normals by depth_fn(game point, game normal) (m)."""
    me = obj.data
    me.update()
    # Normals first: moving vertices one by one makes Blender recompute the rest from the
    # half-moved surface, which turned a deep dish (the catcher's pocket) into noise.
    normals = [v.normal.copy() for v in me.vertices]
    moves = []
    for v, nb in zip(me.vertices, normals):
        d = depth_fn(Vector((v.co.x, v.co.z, -v.co.y)), Vector((nb.x, nb.z, -nb.y)))
        moves.append(nb * d if d else None)
    for v, m in zip(me.vertices, moves):
        if m is not None:
            v.co -= m
    me.update()


def _decimate(obj, tris):
    faces = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = min(1.0, tris / max(1, faces))
    _apply_all(obj)
    obj.data.shade_smooth()


def _bake_colors(obj, palm_fn=None, seam_fn=None, trim_fn=None, rays=40, reach=0.03):
    """Vertex colors for the glove shader (scenes/actors/glove.gdshader):
    R = how open the surface is (1) or tucked into a crease / between fingers (toward 0),
        from rays cast over the hemisphere around each normal;
    G = palm leather, palm_fn(game point, game normal) 0..1;
    B = stitched seam lines: the groove function the shape was carved with, evaluated
        again on the final mesh (1 at a seam's center);
    A = trim color (the cuff's strap band and rim), trim_fn 0..1."""
    from mathutils.bvhtree import BVHTree
    me = obj.data
    me.update()
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])
    # fixed directions on the unit hemisphere around +Z (golden spiral, cosine-weighted)
    dirs = []
    for k in range(rays):
        u = (k + 0.5) / rays
        r = math.sqrt(u)
        a = k * 2.399963
        dirs.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1 - u)))))
    open_ = []
    for v in me.vertices:
        n = v.normal
        rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix()
        o = v.co + n * 0.0006
        occ = 0.0
        for d in dirs:
            hit = bvh.ray_cast(o, rot @ d, reach)
            if hit[0] is not None:
                occ += 1.0 - hit[3] / reach
        open_.append(1.0 - occ / rays)
    # soften over neighbors
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    for _ in range(2):
        open_ = [(open_[i] * 2 + sum(open_[j] for j in nbr[i])) / (2 + len(nbr[i])) for i in range(len(open_))]
    col = me.color_attributes.get("glove") or me.color_attributes.new("glove", "FLOAT_COLOR", "POINT")
    seams = []
    for v in me.vertices:
        p = Vector((v.co.x, v.co.z, -v.co.y))
        n = Vector((v.normal.x, v.normal.z, -v.normal.y))
        seams.append(min(1.0, seam_fn(p, n) / 0.0008) if seam_fn else 0.0)
    for i, v in enumerate(me.vertices):
        p = Vector((v.co.x, v.co.z, -v.co.y))
        n = Vector((v.normal.x, v.normal.z, -v.normal.y))
        palm = palm_fn(p, n) if palm_fn else 0.0
        trim = trim_fn(p, n) if trim_fn else 0.0
        col.data[i].color = (open_[i], palm, seams[i], 1.0 - trim)
    me.color_attributes.active_color = col


def _palm(p, n):
    """Palm leather: the palm under the backhand, and the inside of the fingers and thumb
    where they wrap the stick."""
    sy, sz = GRIP_UP, -GRIP_IN
    # the palm itself: facing the stick, between the palm and the stick (the fingertips
    # curl back to face the same way but sit in front of the stick, and stay padding)
    palm = (_smoothstep(-0.25, -0.6, n.z) * (1.0 - _smoothstep(0.07, 0.085, p.y))
            * (1.0 - _smoothstep(-0.005, 0.01, p.z)) * _smoothstep(-0.05, -0.04, p.z))
    if abs(p.x) < 0.052 and (p.y > 0.08 or p.z < -0.025):
        r = Vector((0.0, p.y - sy, p.z - sz))
        if r.length > 1e-6:
            palm = max(palm, _smoothstep(0.15, 0.55, n.dot(-r.normalized())))
    # inside of the thumb (facing the index finger / the stick)
    t1, t2 = Vector(THUMB[1]), Vector(THUMB[2])
    if (p - t1).length < 0.04 or (p - t2).length < 0.03:
        toward = (Vector((0.0, sy, sz)) - p)
        toward.x = 0.04
        palm = max(palm, _smoothstep(0.2, 0.6, n.dot(toward.normalized())))
    return palm


def _groove(dist, width, depth):
    """Profile of a sewn groove: `depth` at its line, 0 beyond `width`."""
    return depth * math.exp(-(dist / width) ** 2 * 2.5)


def build_glove_cuff(voxel=0.0016, tris=3200):
    """The cuff, a separate piece: the game hangs it on the forearm so it stays on the
    arm while the hand part turns at the wrist. One profile spun around the wrist (an
    oval): inner wall, a padded roll tucked up under the glove at the top, the outer wall
    with a raised strap band, a rolled rim flaring at the open end."""
    cz = -0.002
    # profile (radius scale, game y): goes up the inside, over the top, down the outside
    prof = []
    for k in range(6):                        # inner wall, bottom to top
        t = k / 5.0
        prof.append((0.050 - 0.004 * (1 - t), -0.074 + t * 0.074))
    for k in range(1, 8):                     # top roll, tucked up under the glove
        a = math.pi * k / 8.0
        prof.append((0.05375 - 0.00375 * math.cos(a), 0.009 * math.sin(a)))
    for k in range(17):                       # outer wall, top to bottom
        t = k / 16.0
        y = 0.0 - t * 0.072
        f = t ** 2                            # flare toward the open end
        r = 0.0575 + 0.009 * f
        band = math.exp(-((y + 0.036) / 0.011) ** 4) * 0.0035   # raised strap band
        prof.append((r + band, y))
    for k in range(1, 8):                     # rolled rim at the open end, back inside
        a = math.pi * k / 8.0
        prof.append((0.05625 + 0.01025 * math.cos(a), -0.073 - 0.007 * math.sin(a)))
    bm = bmesh.new()
    segs = 48
    rows = []
    for r, y in prof:
        row = []
        for s in range(segs):
            a = math.tau * s / segs
            row.append(bm.verts.new(g(math.cos(a) * r, y, cz + math.sin(a) * r * 0.875)))
        rows.append(row)
    for i in range(len(rows)):
        a, b = rows[i], rows[(i + 1) % len(rows)]
        for s in range(segs):
            s2 = (s + 1) % segs
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    obj = make_object("GloveCuff", bm)
    _fuse(obj, voxel, 6, 0.5)

    def cuff_grooves(p, n):
        out = n.dot(Vector((p.x, 0, p.z - cz)).normalized()) > 0.3
        if not out:
            return 0.0
        d = 0.0
        # stitching along both edges of the strap band and above the rim roll
        for y in (-0.0255, -0.0465, -0.066):
            d += _groove(abs(p.y - y), 0.0012, 0.0008)
        # a few vertical panel seams below the band (sides and back only)
        ang = math.atan2(p.z - cz, p.x)
        for a in (0.0, math.pi, math.pi * 0.5, -math.pi * 0.5):
            da = abs((ang - a + math.pi) % math.tau - math.pi) * 0.058
            if -0.064 < p.y < -0.047:
                d += _groove(da, 0.0012, 0.0007)
        return d
    def cuff_trim(p, n):
        # the strap band and the rolled rim at the open end, in the trim color
        band = _smoothstep(-0.0475, -0.0455, p.y) * (1.0 - _smoothstep(-0.0265, -0.0245, p.y))
        rim = 1.0 - _smoothstep(-0.0675, -0.0655, p.y)
        return max(band, rim)

    _carve(obj, cuff_grooves)
    _decimate(obj, tris)
    _bake_colors(obj, None, cuff_grooves, cuff_trim)
    obj.data.materials.append(material("GloveMat", (0.55, 0.08, 0.1, 1.0)))
    return obj


def build_glove(voxel=0.0013, tris=6000):
    """The hand part of the glove (the cuff is build_glove_cuff)."""
    bm = bmesh.new()
    X = Vector((1, 0, 0))
    G = (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0)))   # game x, y, z in Blender
    # Hand core (palm and backhand).
    add_box(bm, g(0, 0.048, -0.004), (0.1, 0.06, 0.092), 0.026)
    # Backhand pads: puffy pillows that fuse with soft valleys between them; a split lower
    # row and three across the middle.
    for xc in (-0.0255, 0.0255):
        _ellipsoid(bm, g(xc, 0.026, 0.02), G, (0.0265, 0.0185, 0.017), PAD)
    for xc in (-0.0338, 0.0, 0.0338):
        _ellipsoid(bm, g(xc, 0.0595, 0.021), G, (0.0178, 0.0165, 0.017), PAD)
    # Knuckle roll: a fat roll across the top of the hand.
    _tube(bm, [_gv(Vector((xx, 0.088, 0.017))) for xx in (-0.05, -0.025, 0.0, 0.025, 0.05)],
          [(0.0175, 0.016)] * 5, across=g(0, -0.2, 1.0) - g(0, 0, 0))
    # Side padding down the pinky side, and the thumb-side lock pad.
    _ellipsoid(bm, g(0.05, 0.05, -0.006), G, (0.011, 0.044, 0.04), PAD)
    _ellipsoid(bm, g(-0.051, 0.032, -0.004), G, (0.0105, 0.028, 0.028), PAD)
    # Fingers: one continuous padded roll each, touching their neighbors.
    for x, r, w, d, y0 in FINGERS:
        pts = _finger_path(x, r, y0)
        n = len(pts)
        radii = [((w * 0.5 + 0.0012) * (1 - 0.06 * k / n), (d * 0.5) * (1 - 0.1 * k / n)) for k in range(n)]
        _tube(bm, [_gv(p) for p in pts], radii, across=X)
    # Thumb: up the side and around the front of the shaft.
    tp = [Vector(p) for p in THUMB]
    pts = [tp[0].lerp(tp[1], k / 6.0) for k in range(6)] + [tp[1].lerp(tp[2], k / 6.0) for k in range(7)]
    _tube(bm, [_gv(p) for p in pts], [(0.0195 - 0.003 * k / 12, 0.019 - 0.003 * k / 12) for k in range(13)],
          across=g(0, 0, 1) - g(0, 0, 0))
    obj = make_object("Glove", bm)
    _fuse(obj, voxel, 10, 0.6)

    sy, sz = GRIP_UP, -GRIP_IN

    def glove_grooves(p, n):
        d = 0.0
        on_back = n.z > 0.35 and p.y < 0.08
        if on_back:
            # stitching along the valleys between the backhand pillows
            if p.y < 0.043:
                d += _groove(abs(p.x), 0.0012, 0.0008)
            elif p.y < 0.075:
                for xc in (-0.0168, 0.0168):
                    d += _groove(abs(p.x - xc), 0.0012, 0.0008)
            d += _groove(abs(p.y - 0.043), 0.0012, 0.0008)
            d += _groove(abs(p.y - 0.0755), 0.0014, 0.001)     # under the knuckle roll
        # finger rolls: rings where one roll ends and the next begins, and the knuckle line
        if p.y > 0.085 or p.z < -0.02:
            fx = min(FINGERS, key=lambda f: abs(f[0] - p.x))
            if abs(p.x - fx[0]) < fx[2] * 0.62:
                th = math.degrees(math.atan2(p.y - sy, p.z - sz))     # 0 = back, 90 = up
                th = th % 360.0
                arc_r = math.hypot(p.y - sy, p.z - sz)
                for b in FINGER_BREAKS:
                    d += _groove(abs(th - b) * math.pi / 180 * arc_r, 0.0018, 0.0022)
                if n.z > 0.2:
                    d += _groove(abs(p.y - (fx[4] + 0.004)), 0.0018, 0.0016)
        # thumb joint
        t1 = Vector(THUMB[1])
        q = p - t1
        tdir = (Vector(THUMB[2]) - Vector(THUMB[0])).normalized()
        if abs(q.dot(tdir)) < 0.003 and (q - tdir * q.dot(tdir)).length < 0.022:
            d += _groove(abs(q.dot(tdir)), 0.0016, 0.0016)
        return d
    _carve(obj, glove_grooves)
    _decimate(obj, tris)
    _bake_colors(obj, _palm, glove_grooves)
    obj.data.materials.append(material("GloveMat", (0.55, 0.08, 0.1, 1.0)))
    return obj


# --- The bare fist -----------------------------------------------------------------

def build_fist(voxel=0.002, tris=3200, scale=1.15):
    """The bare fight fist (right hand). Soft masses, not boxes: a thick wrist that
    flares out of the sleeve, a domed back of the hand, fingers wide enough to touch so
    they fuse with shallow grooves (not separate bony segments), a fleshy thumb.
    Built at a 1.8 m body's real size, then scaled up by `scale` (game bodies read
    better with chunky hands)."""
    bm = bmesh.new()
    X, Y, Z = g(1, 0, 0) - g(0, 0, 0), g(0, 1, 0) - g(0, 0, 0), g(0, 0, 1) - g(0, 0, 0)
    # Wrist: from deep in the sleeve, slightly flattened, flaring into the hand.
    # It runs on up inside the hand, so the two blend with no step.
    # The part up the sleeve tapers away, so it never pokes through the jersey.
    wrist = [(-0.075, 0.022, 0.017), (-0.05, 0.028, 0.021), (-0.028, 0.033, 0.025), (-0.01, 0.034, 0.025),
             (0.012, 0.037, 0.026), (0.03, 0.041, 0.026), (0.05, 0.038, 0.022)]
    add_sweep(bm, [g(0, y, -0.008) for y, _, _ in wrist], [(rx, rz) for _, rx, rz in wrist], segs=28, across=X)
    # Back of the hand and palm: one domed pillow, a little wider at the knuckles.
    _ellipsoid(bm, g(0, 0.05, -0.008), (X, Y, Z), (0.044, 0.038, 0.027), squareness=0.7)
    _ellipsoid(bm, g(0.001, 0.072, -0.01), (X, Y, Z), (0.047, 0.018, 0.026), squareness=0.65)
    # Heel of the palm and the thumb's mound (fleshy).
    _ellipsoid(bm, g(0.012, 0.03, -0.018), (X, Y, Z), (0.027, 0.024, 0.022))
    _ellipsoid(bm, g(-0.024, 0.032, -0.02), (X, Y, Z), (0.02, 0.024, 0.024))
    # The curled fingers sit on a solid core, so there's no gap between them and the palm.
    _ellipsoid(bm, g(0.0, 0.066, -0.04), (X, Y, Z), (0.042, 0.026, 0.026), squareness=0.6)
    # ...and the curled fingertips press into the palm: fill the fold under them, so only
    # a soft crease is left there (a deep one reads as a hole).
    _ellipsoid(bm, g(0.006, 0.044, -0.034), (X, Y, Z), (0.036, 0.013, 0.014))
    _ellipsoid(bm, g(0.006, 0.042, -0.048), (X, Y, Z), (0.037, 0.014, 0.015))
    # Fingers: wide enough to touch their neighbours; only shallow grooves survive the fuse.
    # [x, width, length scale, knuckle height]
    fingers = [(-0.0305, 0.0235, 1.0, 0.086), (-0.0102, 0.024, 1.05, 0.088),
               (0.0104, 0.0232, 1.0, 0.087), (0.0300, 0.021, 0.88, 0.083)]
    for x, w, s, ky in fingers:
        k = g(x, ky, -0.002)
        a = g(x, ky + 0.004 * s, -0.042 * s)
        b = g(x, ky - 0.026 * s, -0.052 * s)
        c = g(x, ky - 0.042 * s, -0.034 * s)
        add_segment(bm, k, a, w, w * 0.95, 0.0095, segs=2, grow=0.012)
        add_segment(bm, a, b, w * 0.98, w * 0.92, 0.009, segs=2, grow=0.012)
        add_segment(bm, b, c, w * 0.94, w * 0.88, 0.0085, segs=2, grow=0.01)
    # Thumb: thick at the base, up the side, then across the front of the index and middle.
    t0 = g(-0.034, 0.024, -0.014)
    t1 = g(-0.044, 0.05, -0.046)
    t2 = g(-0.014, 0.059, -0.066)
    add_segment(bm, t0, t1, 0.029, 0.026, 0.011, segs=2, across=Z)
    add_segment(bm, t1, t2, 0.025, 0.022, 0.01, segs=2, across=Z, grow=0.006)

    obj = make_object("Fist", bm)
    obj.data.materials.append(material("SkinMat", (0.8, 0.58, 0.45, 1.0)))
    # Fuse into one skin, smooth enough that the joins read as flesh, then decimate.
    _fuse(obj, voxel, smooth_iters=10, smooth_factor=0.7)
    obj.data.transform(Matrix.Scale(scale, 4))
    obj.data.update()
    _decimate(obj, tris)
    return obj


def _apply_all(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    mesh = bpy.data.meshes.new_from_object(ev)
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    bpy.data.meshes.remove(old)
    mesh.name = obj.name


# --- Export ------------------------------------------------------------------------

def export(obj, filename):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, filename)
    kw = dict(filepath=path, export_format="GLB", use_selection=True,
              export_yup=True, export_apply=True, export_normals=True,
              export_texcoords=False, export_materials="NONE")
    if obj.data.color_attributes:                 # the glove shader's baked colors
        props = bpy.ops.export_scene.gltf.get_rna_type().properties
        if "export_vertex_color" in props:
            kw["export_vertex_color"] = "ACTIVE"
        elif "export_colors" in props:
            kw["export_colors"] = True
    bpy.ops.export_scene.gltf(**kw)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("exported %s: %d tris, size %s" % (path, tris, tuple(round(v, 3) for v in obj.dimensions)))


def build_all(do_export=False):
    glove = build_glove()
    cuff = build_glove_cuff()
    fist = build_fist()
    fist.location = Vector((0.2, 0, 0))
    if do_export:
        fist.location = Vector((0, 0, 0))
        export(glove, "hockey_glove.glb")
        export(cuff, "hockey_glove_cuff.glb")
        export(fist, "fist.glb")
        fist.location = Vector((0.2, 0, 0))
    return glove, cuff, fist
