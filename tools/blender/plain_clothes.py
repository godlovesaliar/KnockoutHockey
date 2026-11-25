"""Plain clothes for the game's bodies: a crew-neck sweatshirt, jeans and boots, for the
people who aren't players (fans in close-ups, the Zamboni's driver).

Headless only (build_jersey's Body() clears the open file):
    blender -b -P tools/blender/plain_clothes.py -- male female [debug=<dir>]
Writes assets/characters/plain_<body>.glb: the body's armature in its rest pose and three
skinned meshes in the game's space (meters, feet on 0, like the jerseys):
    Top     the sweatshirt   ("part" color: red 0 cloth, 0.5 the collar band; green: how far
                             from the end of the sleeve or the hem, 0..1 over EDGE, so the game
                             can draw the rib knit there with a clean edge)
    Pants   the jeans        (part 0.5: the waistband)
    Shoes   both boots       (part 0 upper, 1 sole); the soles reach SOLE under the feet
tools/build_fans.gd turns that into assets/characters/fan_<body>.scn (with what shows of
the body: head, neck, hands).

The sweatshirt is the jersey's own recipe (build_jersey.py: rings round the torso, sleeve
tubes, a voxel union, openings cut, folds) with a close fit and a plain round collar. The
jeans are made the same way from a ring stack round the pelvis and a tube down each leg
that follows the thigh and falls straight from the calf. The boots are lofted round each
foot and ankle.
"""
import bpy, bmesh, math, os, sys, importlib.util
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True     # (no __pycache__ beside the tools for the import below)
_spec = importlib.util.spec_from_file_location("build_jersey", os.path.join(HERE, "build_jersey.py"))
bj = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bj)
P = bj.P
smoothstep = bj.smoothstep

SOLE = 0.028           # boot sole under the foot (m): the game stands the body this much higher

# The sweatshirt, over build_jersey's own shape for the body (which keeps what the body's
# rig needs: where the neck is laid out, how the shoulders are held).
TOP = dict(hem=0.955, ease=0.017, sleeve_ease=0.015, gap=0.010, neck_ease=0.012, neck_gap=0.008,
           taper_fb=0.05, taper_side=0.10, flare=0.004, flare_h=0.12, v_depth=0.0,
           sh_r=0.070, cuff_r=0.040, cuff_at=0.975, pin_hem=True, collar_line=True,
           collar_rise=4.0)
BODY_TOP = {
    # (the male's neck: the jersey's own round cut, 16 cm across, is a wide boat neck on a
    # sweatshirt. A smaller one that takes only the neck itself, cut level just above the
    # collarbones, as the female's is.)
    "male": dict(neck_drop=0.004, neck_r=0.7, collar_r0=0.08, sh_r=0.088, shoulder_smooth=70),
    "female": dict(neck_drop=0.008, collar_r0=0.085, sh_r=0.070, cuff_r=0.036),
}
TOP_TRIS = 6500
EDGE = 0.10            # the part color's green runs 0..1 over this far from a cuff's end or the hem (m)

# The jeans.
PANTS = dict(ease=0.011, tucked=0.004, waist=0.085, hem_at=0.985, hem_r=0.070, taper_thigh=0.25,
             taper_calf=0.03, voxel=0.008, gap=0.005)
PANTS_TRIS = 5500

# The boots.
BOOT = dict(skin=0.009, collar=0.085, toe=0.06, heel=0.035, voxel=0.005, tris=1300)


def is_leg(c, side=None):
    return ("Leg" in c or "Foot" in c or "Toe" in c) and (side is None or c.startswith(side))


def other(side):
    return "Right" if side == "Left" else "Left"


def link(name, bm):
    return bj._link(name, bm)


def activate(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.hide_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.hide_set(False)
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def remesh(o, voxel, smooth=20, factor=0.8):
    activate(o)
    o.data.remesh_voxel_size = voxel
    bpy.ops.object.voxel_remesh()
    if smooth:
        m = o.modifiers.new("smooth", "SMOOTH")
        m.factor = factor
        m.iterations = smooth
        bpy.ops.object.modifier_apply(modifier="smooth")


def decimate_to(o, tris):
    have = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if have > tris:
        bj.decimate(o, tris / have)


def rim(o, depth=0.006):
    """A turned-in lip at every opening, so hems read as cloth with some thickness."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    edges = [e for e in bm.edges if e.is_boundary]
    was = {v: v.normal.copy() for e in edges for v in e.verts}
    new = bmesh.ops.extrude_edge_only(bm, edges=edges)["geom"]
    for v in new:
        if not isinstance(v, bmesh.types.BMVert):
            continue
        src = next((e.other_vert(v) for e in v.link_edges if e.other_vert(v) in was), None)
        if src is not None:
            v.co = src.co - was[src] * depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def part_attr(o, value=0.0):
    col = o.data.color_attributes.get("part") or o.data.color_attributes.new("part", "FLOAT_COLOR", "POINT")
    for d in col.data:
        d.color = (value, 1, 0, 1)
    o.data.color_attributes.active_color = col
    return col


def keep_out(o, tree, gap, reach=0.05, where=None):
    """Moves every vertex of `o` at least `gap` outside the surface in `tree`."""
    moved = 0
    for v in o.data.vertices:
        if where is not None and not where(v.co):
            continue
        loc, nrm, _, _ = tree.find_nearest(v.co, reach)
        if loc is None:
            continue
        side = (v.co - loc).dot(nrm)
        if side < gap:
            v.co = loc + nrm * gap if side < 0 else v.co + nrm * (gap - side)
            moved += 1
    o.data.update()
    return moved


def tree_of(o):
    return BVHTree.FromPolygons([v.co.copy() for v in o.data.vertices], [list(p.vertices) for p in o.data.polygons])


def round_off(o, centers, radius, passes):
    """Extra smoothing round some points, fading out with distance."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    falloff = {}
    for v in bm.verts:
        d = min((v.co - c).length for c in centers)
        if d < radius:
            falloff[v] = 1.0 - smoothstep(radius * 0.4, radius, d)
    verts = list(falloff)
    for _ in range(passes):
        avg = {v: sum((e.other_vert(v).co for e in v.link_edges), Vector()) / max(len(v.link_edges), 1) for v in verts}
        for v in verts:
            v.co = v.co.lerp(avg[v], 0.5 * falloff[v])
    bm.to_mesh(o.data)
    bm.free()


def rested(body, o, W, name):
    """build_jersey's to_rest under our own name (it reuses one object name)."""
    r = bj.to_rest(body, o, W)
    r.name = name
    r.data.name = name
    return r


# --- Sweatshirt --------------------------------------------------------------------

def top(body):
    P.update(TOP)
    P.update(BODY_TOP.get(body.name, {}))
    j = bj.shell(body)
    j.name = "TopShell"
    bj.clearance(body, j, gap=P["gap"])
    bj.folds(body, j, amp=0.8)
    bj.clearance(body, j, gap=P["gap"], iters=1)
    decimate_to(j, int(TOP_TRIS * 1.15))
    # (the jersey's cloth may sink into the shoulders: its pads are drawn over them)
    keep_out(j, body.smooth_bvh(), 0.006)
    bj.cut_openings(body, j)
    band = bj.collar(body, j)
    # (the jersey's collar comes with laces: the vertices after the band)
    bm = bmesh.new()
    bm.from_mesh(band.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index >= 120 * 12], context="VERTS")
    bm.to_mesh(band.data)
    bm.free()
    xs = [v.co.x for v in band.data.vertices]
    ys = [v.co.y for v in band.data.vertices]
    print("plain %s: collar %.1f cm across, %.1f cm front to back" % (body.name, (max(xs) - min(xs)) * 100, (max(ys) - min(ys)) * 100))
    part_attr(band, 0.5)
    rim(j)
    part_attr(j, 0.0)
    j = join([j, band], "TopShell")
    j.data.color_attributes.active_color = j.data.color_attributes["part"]
    W = bj.skin(body, j)
    # For the rib knit at the cuffs and hem: how far each vertex is from the end of its
    # sleeve, or from the hem.
    col = j.data.color_attributes["part"]
    z_hem = body.rest["Hips"].z * P["hem"]
    for v in j.data.vertices:
        side, u, dist = bj.part_of(body, v.co)
        A, E, H = bj.sleeve_path(body, side)
        arm = (E - A).length + (H - E).length * P["cuff_at"]
        d = 9.0
        if dist < 0.09:
            d = (1.0 - u) * arm
        elif dist > 0.12:
            d = v.co.z - z_hem
        col.data[v.index].color = (col.data[v.index].color[0], max(0.0, min(d / EDGE, 1.0)), 0, 1)
    return j, W


# --- Jeans -------------------------------------------------------------------------

PELVIS = {"Hips", "Spine", "Spine1", "LHipJoint", "RHipJoint", "LeftUpLeg", "RightUpLeg"}


def crotch_z(body):
    bvh = body.bvh(PELVIS)
    C = body.torso_center()
    lows = []
    for dy in (-0.04, -0.02, 0.0, 0.02, 0.04):
        zs = []
        for x in (-0.008, -0.004, 0.004, 0.008):   # (beside the body's own seam: a ray down it can slip through)
            h = bvh.ray_cast(Vector((x, C.y + dy, 0.3)), Vector((0, 0, 1)), 1.5)
            if h[0] is not None:
                zs.append(h[0].z)
        if zs:
            lows.append(sorted(zs)[len(zs) // 2])
    return min(lows)


def leg_path(body, side):
    return body.joint(side + "UpLeg"), body.joint(side + "Leg"), body.joint(side + "Foot")


def leg_at(body, p):
    """(side, meters along the leg from the hip joint, distance from its axis, angle round it)."""
    side = "Left" if p.x > 0 else "Right"
    U, K, F = leg_path(body, side)
    best = None
    for a, b, s0 in ((U, K, 0.0), (K, F, (K - U).length)):
        d = (b - a).normalized()
        t = max(-0.12, min((b - a).length, (p - a).dot(d)))
        q = p - (a + d * t)
        if best is None or q.length < best[2]:
            x = d.cross(Vector((0, -1, 0))).normalized()
            y = d.cross(x)
            best = (side, s0 + t, q.length, math.atan2(q.dot(y), q.dot(x)))
    return best


def leg(body, side):
    bvh = body.bvh({side + "UpLeg", side + "Leg"})
    U, K, F = leg_path(body, side)
    d1, d2 = (K - U).normalized(), (F - K).normalized()
    L1, L2 = (K - U).length, (F - K).length
    back = 0.10
    start = U - d1 * back
    total = back + L1 + L2 * PANTS["hem_at"]
    sK = back + L1
    NS, NT = 72, 32
    ds = total / NS
    frames, R = [], []
    for i in range(NS + 1):
        s = ds * i
        c = start + d1 * s if s <= sK else K + d2 * (s - sK)
        w = max(0.0, 1 - abs(s - sK) / 0.07) * 0.5
        d = (d1 * (1 - w) + d2 * w).normalized() if s < sK else (d1 * w + d2 * (1 - w)).normalized()
        x = d.cross(Vector((0, -1, 0))).normalized()
        y = d.cross(x).normalized()
        row = []
        for t in range(NT):
            a = 2 * math.pi * t / NT
            dv = x * math.cos(a) + y * math.sin(a)
            h = bvh.ray_cast(c + dv * 0.35, -dv, 0.35)
            row.append(0.35 - h[3] + PANTS["ease"] if h[0] is not None else 0.0)
        frames.append((c, x, y))
        R.append(row)
    # Where the leg's own skin gives out (it runs into the pelvis): carry the ring below up.
    for i in range(NS, -1, -1):
        got = [r for r in R[i] if r > 0]
        mean = sum(got) / len(got) if got else 0.0
        below = R[i + 1] if i < NS else [0.08] * NT
        R[i] = [r if r > 0 else (min(mean, below[t] * 1.1) if mean > 0 else below[t]) for t, r in enumerate(R[i])]
    for _ in range(6):
        R = [[(row[t - 1] + 2 * row[t] + row[(t + 1) % NT]) / 4 for t in range(NT)] for row in R]
    for _ in range(4):
        R = [[(R[max(i - 1, 0)][t] + 2 * R[i][t] + R[min(i + 1, NS)][t]) / 4 for t in range(NT)] for i in range(NS + 1)]
    # Denim hangs: going down, the leg may only narrow slowly (hardly at all below the knee).
    for i in range(1, NS + 1):
        tp = PANTS["taper_thigh"] if ds * i <= sK else PANTS["taper_calf"]
        R[i] = [max(R[i][t], R[i - 1][t] - tp * ds) for t in range(NT)]
    for i in range(NS + 1):
        k = smoothstep(total - 0.32, total - 0.04, ds * i)
        R[i] = [max(r, PANTS["hem_r"] * k) for r in R[i]]
    bm = bmesh.new()
    rings = []
    for i in range(NS + 1):
        c, x, y = frames[i]
        s = ds * i
        dome = 0.09
        k = math.sqrt(max(0.0, 1 - ((dome - s) / dome) ** 2)) * 0.85 + 0.15 if s < dome else 1.0
        rings.append([bm.verts.new(c + (x * math.cos(2 * math.pi * t / NT) + y * math.sin(2 * math.pi * t / NT)) * R[i][t] * k)
                      for t in range(NT)])
    for i in range(NS):
        for t in range(NT):
            bm.faces.new((rings[i][t], rings[i][(t + 1) % NT], rings[i + 1][(t + 1) % NT], rings[i + 1][t]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return link("PLeg" + side, bm)


def pelvis(body, zc, z_top):
    bvh = body.bvh(PELVIS)
    C = body.torso_center()
    NT, dz = 64, 0.012
    z0 = zc - 0.045
    z_hem = body.rest["Hips"].z * TOP["hem"]     # the sweatshirt hangs to here: closer under it
    zs = [z0 + i * dz for i in range(int((z_top + 0.04 - z0) / dz) + 1)]
    R = []
    for z in zs:
        row = []
        for t in range(NT):
            a = 2 * math.pi * t / NT
            d = Vector((math.sin(a), -math.cos(a), 0))
            h = bvh.ray_cast(Vector((C.x, C.y, z)) + d * 0.8, -d, 0.8)
            ease = PANTS["ease"] + (PANTS["tucked"] - PANTS["ease"]) * smoothstep(z_hem - 0.02, z_hem + 0.03, z)
            row.append(0.8 - h[3] + ease if h[0] is not None else 0.0)
        R.append(bj._hull_ring(row) if max(row) > 0 else row)
    for _ in range(8):
        R = [[(row[t - 1] + 2 * row[t] + row[(t + 1) % NT]) / 4 for t in range(NT)] for row in R]
    NZ = len(zs)
    for _ in range(4):
        R = [[(R[max(z - 1, 0)][t] + 2 * R[z][t] + R[min(z + 1, NZ - 1)][t]) / 4 for t in range(NT)] for z in range(NZ)]
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector((C.x, C.y, zs[z])) + Vector((math.sin(2 * math.pi * t / NT), -math.cos(2 * math.pi * t / NT), 0)) * max(R[z][t], 0.03))
              for t in range(NT)] for z in range(NZ)]
    for z in range(NZ - 1):
        for t in range(NT):
            bm.faces.new((rings[z][t], rings[z][(t + 1) % NT], rings[z + 1][(t + 1) % NT], rings[z + 1][t]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return link("PPelvis", bm)


def smooth_trees(body):
    """The lower body with its small detail smoothed away, as three trees: what a point on
    the left, in the middle and on the right has to clear (a point between the thighs must
    not be pushed off the far leg)."""
    bm = bmesh.new()
    bm.from_mesh(body.posed.data)
    for _ in range(10):
        bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    co = [v.co.copy() for v in bm.verts]
    bm.free()
    me = body.posed.data

    def tree(pred):
        polys = [list(p.vertices) for p in me.polygons if sum(pred(body.dom[i]) for i in p.vertices) >= 2]
        return BVHTree.FromPolygons(co, polys)
    mid = lambda c: c in PELVIS and not is_leg(c)
    return {"Left": tree(lambda c: mid(c) or is_leg(c, "Left")),
            "Right": tree(lambda c: mid(c) or is_leg(c, "Right")),
            "": tree(mid)}


def side_of(p):
    return "Left" if p.x > 0.012 else ("Right" if p.x < -0.012 else "")


def clear(o, trees, gap, iters=2):
    for _ in range(iters):
        o.data.update()
        for v in o.data.vertices:
            loc, nrm, _, dist = trees[side_of(v.co)].find_nearest(v.co, 0.06)
            if loc is None:
                continue
            side = (v.co - loc).dot(nrm)
            if side < gap:
                v.co = loc + nrm * gap if side < 0 else v.co + nrm * (gap - side)
        activate(o)
        m = o.modifiers.new("relax", "SMOOTH")
        m.factor = 0.5
        m.iterations = 2
        bpy.ops.object.modifier_apply(modifier="relax")


def pant_folds(body, o, zc):
    me = o.data
    me.update()
    for v in me.vertices:
        p, n = v.co, v.normal
        side, s, dist, phi = leg_at(body, p)
        U, K, F = leg_path(body, side)
        L1, L2 = (K - U).length, (F - K).length
        total = L1 + L2 * PANTS["hem_at"]
        on_leg = smoothstep(zc + 0.02, zc - 0.06, p.z)
        warp = noise.noise(Vector((p.x * 7, p.y * 7, p.z * 7))) * 2.5
        knee = math.exp(-((s - L1) / 0.085) ** 2)
        stack = smoothstep(total - 0.2, total - 0.03, s)
        zig = math.sin(s * 95 + math.sin(phi * 2 + warp) * 1.6 + warp)
        patch = smoothstep(-0.1, 0.4, noise.noise(Vector((s * 9, math.cos(phi) * 1.5, math.sin(phi) * 1.5))))
        d = zig * patch * (0.0045 * knee + 0.005 * stack + 0.0012) * on_leg
        # drag lines across the lap, from the crotch out toward each hip
        lap = smoothstep(zc - 0.02, zc + 0.03, p.z) * smoothstep(zc + 0.2, zc + 0.08, p.z) * smoothstep(0.1, -0.3, n.y)
        d += math.sin((abs(p.x) * 0.8 + p.z) * 75 + warp * 0.6) * 0.003 * lap
        d += noise.noise(Vector((p.x * 9, p.y * 9, p.z * 9))) * 0.0018
        v.co = p + n * d
    me.update()


def skin_pants(body, o, smooth_iters=24):
    """Weights from the nearest point of the body on the same side, smoothed over the cloth."""
    me = body.posed.data
    gname = {g.index: g.name for g in body.mesh.vertex_groups}
    src = body.mesh.data.vertices
    cover = lambda c: c in PELVIS or is_leg(c)
    sets = {}
    for key, pred in (("Left", lambda c: cover(c) and not is_leg(c, "Right")),
                      ("Right", lambda c: cover(c) and not is_leg(c, "Left")),
                      ("", cover)):
        polys = [p for p in me.polygons if sum(pred(body.dom[i]) for i in p.vertices) >= 2]
        sets[key] = (polys, BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in polys]))

    def canon(name, key):
        c = body.canon_of.get(name, "Hips")
        if "Foot" in c or "Toe" in c:
            c = ("Left" if c.startswith("L") else "Right") + "Leg"   # the hem hangs from the shin
        if "HipJoint" in c:
            c = "Hips"
        if key and is_leg(c, other(key)):
            c = "Hips"
        if not (c in PELVIS or is_leg(c) or c.startswith("Spine")):
            c = "Hips"
        return c
    W = []
    for v in o.data.vertices:
        key = side_of(v.co)
        polys, bvh = sets[key]
        loc, _, fi, _ = bvh.find_nearest(v.co)
        w = {}
        if loc is not None:
            pv = polys[fi].vertices
            for i in pv:
                dd = max((me.vertices[i].co - loc).length, 1e-5)
                for g in src[i].groups:
                    c = canon(gname[g.group], key)
                    w[c] = w.get(c, 0.0) + g.weight / dd
        W.append(w)
    nbr = [[] for _ in o.data.vertices]
    for e in o.data.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    for _ in range(smooth_iters):
        nxt = []
        for i, w in enumerate(W):
            acc = {k: x * 2.0 for k, x in bj._norm(w).items()}
            for n in nbr[i]:
                for k, x in bj._norm(W[n]).items():
                    acc[k] = acc.get(k, 0.0) + x
            nxt.append(acc)
        W = nxt
    out = []
    for w in W:
        best = sorted(bj._norm(w).items(), key=lambda kv: -kv[1])[:4]
        out.append(bj._norm(dict(kv for kv in best if kv[1] > 0.01)))
    return out


def pants(body):
    zc = crotch_z(body)
    k = body.spec["height"] / 1.8
    z_top = body.rest["Hips"].z + PANTS["waist"] * k
    o = join([pelvis(body, zc, z_top), leg(body, "Left"), leg(body, "Right")], "PantsShell")
    remesh(o, PANTS["voxel"])
    round_off(o, [Vector((0.0, body.torso_center().y, zc - 0.02))], 0.1, 30)
    trees = smooth_trees(body)
    clear(o, trees, PANTS["gap"])
    pant_folds(body, o, zc)
    clear(o, trees, PANTS["gap"], iters=1)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z_top), plane_no=(0, 0, 1), clear_outer=True)
    for side in ("Left", "Right"):
        U, K, F = leg_path(body, side)
        d = (F - K).normalized()
        c = K + d * ((F - K).length * PANTS["hem_at"] - 0.006)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=c, plane_no=d, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()
    decimate_to(o, PANTS_TRIS)
    rim(o)
    col = part_attr(o, 0.0)
    for v in o.data.vertices:
        if v.co.z > z_top - 0.035:
            col.data[v.index].color = (0.5, 1, 0, 1)
    return o, skin_pants(body, o), zc


# --- Boots -------------------------------------------------------------------------

def _section(c, x, y, hw, hh, n=16, power=0.6, hh_low=None, power_low=None):
    """A rounded box outline round c: half sizes hw along x and hh along y (hh_low below
    c, squarer with power_low: a boot's flat bottom under a rounder top)."""
    out = []
    for t in range(n):
        a = 2 * math.pi * t / n
        ca, sa = math.cos(a), math.sin(a)
        up = sa >= 0 or hh_low is None
        py = power if up else (power_low or power)
        out.append(c + x * math.copysign(abs(ca) ** power, ca) * hw
                   + y * math.copysign(abs(sa) ** py, sa) * (hh if up else hh_low))
    return out


def _loft(bm, rings, cap=True):
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(vr[0])
    for i in range(len(vr) - 1):
        for t in range(n):
            bm.faces.new((vr[i][t], vr[i][(t + 1) % n], vr[i + 1][(t + 1) % n], vr[i + 1][t]))
    if cap:
        bm.faces.new(vr[0])
        bm.faces.new(list(reversed(vr[-1])))
    return vr


def boot(body, side):
    A = body.joint(side + "Foot")
    T = body.joint(side + "ToeBase")
    up = Vector((0, 0, 1))
    f = T - A
    f.z = 0.0
    f.normalize()
    r = f.cross(up)
    M = BOOT["skin"]
    sgn = 1 if side == "Left" else -1
    pts = [v.co for i, v in enumerate(body.posed.data.vertices)
           if v.co.x * sgn > 0 and v.co.z < A.z + 0.14 and is_leg(body.dom[i], side)]
    loc = [((p - A).dot(f), (p - A).dot(r), p.z) for p in pts]
    foot = [l for l in loc if l[2] < A.z + 0.012]
    a0 = min(l[0] for l in foot)
    a1 = max(l[0] for l in foot)
    # The foot's own width and height along its length...
    N = 26
    raw = []
    for i in range(N + 1):
        a = a0 - M + (a1 - a0 + 2 * M) * i / N
        q = min(max(a, a0 + 0.008), a1 - 0.008)
        slab = [l for l in foot if abs(l[0] - q) < 0.014]
        raw.append([a, min(l[1] for l in slab) - M, max(l[1] for l in slab) + M, max(max(l[2] for l in slab) + M, 0.052)])
    for _ in range(3):
        raw = [[s[0]] + [(raw[max(i - 1, 0)][q] + 2 * s[q] + raw[min(i + 1, N)][q]) / 4 for q in (1, 2, 3)] for i, s in enumerate(raw)]
    # ...rounded off into a toe box and a heel counter (they don't follow the toes).
    stations = []
    for a, w0, w1, top in raw:
        tt = max(0.0, (a - (a1 + M - BOOT["toe"])) / BOOT["toe"])
        hh = max(0.0, ((a0 - M + BOOT["heel"]) - a) / BOOT["heel"])
        kw = (math.sqrt(max(0.0, 1 - tt * tt)) * 0.9 + 0.1) * (math.sqrt(max(0.0, 1 - hh * hh)) * 0.75 + 0.25)
        kh = (0.72 + 0.28 * math.sqrt(max(0.0, 1 - tt * tt))) * (0.8 + 0.2 * math.sqrt(max(0.0, 1 - hh * hh)))
        wc = (w0 + w1) * 0.5
        # (the toe box closes toward the big toe's side a little, like a shoe's last)
        wc -= sgn * 0.006 * tt * tt
        stations.append((a, wc, (w1 - w0) * 0.5 * kw, top * kh))
    bm = bmesh.new()
    rings = []
    for a, wc, hw, top in stations:
        c = Vector((A.x, A.y, 0.0)) + f * a + r * wc + up * (top * 0.42)
        rings.append(_section(c, r, up, hw, top * 0.58, power=0.8, hh_low=top * 0.42, power_low=0.5))
    _loft(bm, rings)
    # The shaft round the ankle and shin, up to the collar.
    z_col = A.z + BOOT["collar"]
    srings = []
    last = None
    for i in range(13):
        z = 0.03 + z_col * i / 12
        slab = [l for l in loc if abs(l[2] - max(z, A.z - 0.005)) < 0.012 and l[0] < a0 + (a1 - a0) * 0.42]
        if slab:
            fa0, fa1 = min(l[0] for l in slab), max(l[0] for l in slab)
            w0, w1 = min(l[1] for l in slab), max(l[1] for l in slab)
            last = ((fa0 + fa1) * 0.5, (w0 + w1) * 0.5, (fa1 - fa0) * 0.5 + M + 0.004, (w1 - w0) * 0.5 + M + 0.004)
        if last is None:
            continue
        ca, cw, ha, hwid = last
        flare = 0.004 * smoothstep(z_col - 0.03, z_col, z)
        c = Vector((A.x, A.y, z)) + f * ca + r * cw
        srings.append(_section(c, f, r, ha + flare, hwid + flare, power=0.85))
    _loft(bm, srings)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = link("BootShell" + side, bm)
    remesh(o, BOOT["voxel"], smooth=8, factor=0.6)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z_col), plane_no=(0, 0, 1), clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()
    decimate_to(o, BOOT["tris"])
    rim(o, 0.008)
    part_attr(o, 0.0)
    # The sole: the upper's outline, a little proud of it.
    lip = 0.004
    outline = [(a, wc + hw + lip) for a, wc, hw, _ in stations] + [(a, wc - hw - lip) for a, wc, hw, _ in reversed(stations)]
    for _ in range(2):
        outline = [((outline[i - 1][0] + 2 * q[0] + outline[(i + 1) % len(outline)][0]) / 4,
                    (outline[i - 1][1] + 2 * q[1] + outline[(i + 1) % len(outline)][1]) / 4) for i, q in enumerate(outline)]
    bm = bmesh.new()
    base = Vector((A.x, A.y, 0.0))
    cx = sum(q[0] for q in outline) / len(outline)
    cy = sum(q[1] for q in outline) / len(outline)
    levels = [(-SOLE, 0.95), (-SOLE + 0.006, 1.0), (0.004, 1.0), (0.011, 0.96)]
    _loft(bm, [[base + f * (cx + (q[0] - cx) * k) + r * (cy + (q[1] - cy) * k) + up * z for q in outline] for z, k in levels])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sole = link("BootSole" + side, bm)
    part_attr(sole, 1.0)
    return join([o, sole], "Boot" + side)


def shoes(body):
    o = join([boot(body, "Left"), boot(body, "Right")], "ShoesShell")
    o.data.color_attributes.active_color = o.data.color_attributes["part"]
    W = [{("Left" if v.co.x > 0 else "Right") + "Foot": 1.0} for v in o.data.vertices]
    return o, W


# --- Output ------------------------------------------------------------------------

def snap(body, objs, folder, tag):
    """Debug pictures (front, back, side) of the body and clothes in the modelling pose."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "OBJECT"
    sh.show_cavity = True
    sh.show_object_outline = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 1300
    scene.render.film_transparent = False
    for o in bpy.data.objects:
        o.hide_render = True
    body.posed.hide_render = False
    body.posed.color = (0.8, 0.6, 0.5, 1)
    for o, c in objs:
        o.hide_render = False
        o.hide_set(False)
        o.color = c
        for p in o.data.polygons:
            p.use_smooth = True
    cam = bpy.data.objects.get("SnapCam")
    if cam is None:
        cam = bpy.data.objects.new("SnapCam", bpy.data.cameras.new("SnapCam"))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scene.camera = cam
    h = body.spec["height"]
    views = {"front": ((0, -5, h * 0.5), (0, 0, h * 0.5), h * 1.08), "back": ((0, 5, h * 0.5), (0, 0, h * 0.5), h * 1.08),
             "quarter": ((3.2, -3.8, h * 0.62), (0, 0, h * 0.5), h * 1.08),
             "feet": ((1.6, -2.4, 0.9), (0, -0.05, 0.08), 0.7), "chest": ((0.6, -3, h * 0.86), (0, 0, h * 0.74), 0.8),
             "hips": ((-1.2, -3, h * 0.6), (0, 0, h * 0.5), 0.8), "behind": ((-2.5, 4, h * 0.62), (0, 0, h * 0.5), h * 1.08)}
    for name, (at, to, scale) in views.items():
        cam.location = at
        cam.rotation_euler = (Vector(to) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = scale
        scene.render.filepath = os.path.join(folder, "%s_%s_%s.png" % (body.name, tag, name))
        bpy.ops.render.render(write_still=True)


def export(body, objs, path):
    for pb in body.arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    body.arm.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
              export_animations=False, export_apply=False, export_yup=True, export_normals=True,
              export_texcoords=False, export_materials="NONE")
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    if "use_active_scene" in props:
        kw["use_active_scene"] = True
    if "export_vertex_color" in props:
        kw["export_vertex_color"] = "ACTIVE"
    elif "export_colors" in props:
        kw["export_colors"] = True
    bpy.ops.export_scene.gltf(**kw)


def make(name, debug=None, write=True):
    body = bj.Body(name)
    t, tw = top(body)
    p, pw, zc = pants(body)
    s, sw = shoes(body)
    # The sweatshirt hangs over the jeans' waist, never inside it.
    z_hem = body.rest["Hips"].z * TOP["hem"]
    keep_out(t, tree_of(p), 0.006, reach=0.04, where=lambda co: co.z < z_hem + 0.2 and abs(co.x) < 0.3)
    if debug:
        os.makedirs(debug, exist_ok=True)
        snap(body, [(t, (0.75, 0.2, 0.2, 1)), (p, (0.25, 0.35, 0.6, 1)), (s, (0.3, 0.2, 0.12, 1))], debug, "all")
    out = [rested(body, t, tw, "Top"), rested(body, p, pw, "Pants"), rested(body, s, sw, "Shoes")]
    for o in out:
        o.data.color_attributes.active_color = o.data.color_attributes["part"]
    path = os.path.join(bj.ROOT, "assets", "characters", "plain_%s.glb" % name)
    if write:
        export(body, out, path)
    for o in out:
        print("plain %s: %s %d verts, %d tris" % (name, o.name, len(o.data.vertices), sum(len(f.vertices) - 2 for f in o.data.polygons)))
    print("plain %s -> %s (crotch at %.3f m)" % (name, path, zc))
    return body, out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    dbg = next((a[6:] for a in argv if a.startswith("debug=")), None)
    for which in ([a for a in argv if "=" not in a] or ["male", "female"]):
        make(which, debug=dbg)
