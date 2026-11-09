"""Builds a modelled hockey jersey for one body, in Blender.

Run inside Blender (Blender MCP, or headless):
    blender -b -P tools/blender/build_jersey.py -- female
Writes assets/characters/jersey_<body>.glb: one skinned mesh, bind pose = the body's rest
pose, bones named like the body's FBX (tools/build_characters.gd maps them the same way).

How the shape is made (all in a pose with the arms raised to ~45 degrees, so the sleeves
don't fuse into the sides):
  * torso: horizontal rings ray-cast against the body (upper arms included above the
    armpit, so the shoulder line runs into the sleeves), eased out, smoothed, then draped:
    going down, a ring may only pull in slowly from the one above, so the jersey hangs
    from the shoulder blades and the chest instead of following the waist
  * sleeves: tubes along the arm bones, wide at the shoulder, tapering to a cuff that
    fits over the glove
  * union by voxel remesh, smoothing, then openings cut (hem, cuffs, neck), a collar band
    with a shallow V and laces, a turned-in hem, and fold displacement (vertical drape,
    drag lines from the armpits, bunching at the elbows and cuffs)
  * skin weights copied from the body and smoothed, then the mesh is moved back into the
    bind pose by inverting the skinning per vertex (exact for linear blend skinning)
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")) if "__file__" in globals() else r"C:\Users\Booker\Desktop\Knockout Hockey"

BODIES = {
    # `shape`: this body's overrides of P below.
    "female": dict(file="assets/player/Mujer_Base.fbx", height=1.75, prefix="mixamorig:", map={}, shape={}),
    "male": dict(file="assets/player/Hombre_Base (1).fbx", height=1.84, prefix="",
                 map={"LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2"},
                 # boxier and straighter; the thick neck needs the collar-line cut and a
                 # lower top; sleeves start further in and the shoulders are rounded off
                 # (the broad shoulders otherwise leave a pad-like shelf)
                 shape=dict(taper_fb=0.04, taper_side=0.06, top=0.05, collar_line=True,
                            sh_r=0.092, sleeve_back=0.06, shoulder_smooth=40,
                            shoulder_weight_smooth=80, flare=0.06, pin_hem=True,
                            torso_arms=False)),
    "ybot": dict(file="assets/animations/Y Bot.fbx", height=1.80, prefix="mixamorig:", map={}),
}

# Shape parameters, as fractions of the body where they scale with it.
P = dict(
    hem=0.89,          # hem height, in units of the hips joint height (1 = hips joint)
    ease=0.024,        # cloth off the body (m), over the pads
    sleeve_ease=0.022, # sleeves off the arms (m)
    gap=0.018,         # least room between the shoulders / sleeves and the body (m)
    taper_fb=0.07,     # how fast the front/back may pull in going down (m per m)
    taper_side=0.2,    # same for the sides (low = falls straight from the armpits)
    top=0.09,          # torso rings run up to this far above the neck joint (m)
    collar_line=False, # also cut away everything above a collar line around the neck
    sleeve_back=0.03,  # sleeve tubes start this far inside the shoulder joint (m)
    shoulder_smooth=0, # extra smoothing passes around the shoulder joints
    shoulder_weight_smooth=0,  # extra skin-weight smoothing passes there
    pin_hem=False,     # below the hips joint, skin to the pelvis only
    torso_arms=True,   # torso rings above the armpit also wrap the upper arms (shoulder line)
    deltoid_to_arm=0.0,  # how much cloth past the shoulder joint is moved onto the upper arm
    flare=0.045,       # extra looseness at the hem (m): it hangs over the padded pants
    flare_h=0.2,       # over how much height above the hem the flare builds up (m)
    sh_r=0.100,        # sleeve radius at the shoulder (m)
    cuff_r=0.064,      # sleeve radius at the cuff (m)
    cuff_at=0.93,      # cuff position along the forearm
    raise_deg=28.0,    # arm raise for modelling
    voxel=0.008,
)
DEFAULTS = dict(P)

CANON = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
         "RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "RightUpLeg"]


class Body:
    """The imported body: armature in meters, feet on z = 0, arms raised for modelling."""

    def __init__(self, name):
        self.name = name
        self.spec = BODIES[name]
        P.clear()
        P.update(DEFAULTS)
        P.update(self.spec.get("shape", {}))
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, self.spec["file"]))
        self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        self.mesh = max(meshes, key=lambda o: len(o.data.vertices))
        for o in meshes:
            if o != self.mesh:
                bpy.data.objects.remove(o)
        if self.arm.animation_data:
            self.arm.animation_data_clear()
        for pb in self.arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        # Stand the rig up from its own bones (the male export comes in lying down):
        # hips -> neck along +Z, toes toward -Y (Blender's front; glTF / Godot +Z).
        def head(short):
            b = next(b for b in self.arm.data.bones if b.name.split(":")[-1] == short)
            return self.arm.matrix_world @ b.head_local
        up = (head("Neck") - head("Hips")).normalized()
        fwd = head("LeftToeBase") - head("LeftFoot")
        fwd = (fwd - up * fwd.dot(up)).normalized()
        src = Matrix((fwd.cross(up), fwd, up)).transposed()      # columns: x, y, z (right-handed)
        dst = Matrix(((-1, 0, 0), (0, -1, 0), (0, 0, 1))).transposed()
        R = dst @ src.inverted()
        # exports differ by quarter turns only: snap (splayed feet would tilt the body)
        R = Matrix([[round(R[r][c]) for c in range(3)] for r in range(3)]).to_4x4()
        self.arm.matrix_world = R @ self.arm.matrix_world
        bpy.context.view_layer.update()
        self._apply_all()
        ws = [self.mesh.matrix_world @ v.co for v in self.mesh.data.vertices]
        lo = min(w.z for w in ws)
        hi = max(w.z for w in ws)
        k = self.spec["height"] / (hi - lo)
        self.arm.scale = (k, k, k)
        self.arm.location.z = -lo * k
        self._apply_all()
        for pb in self.arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        # canonical bone name -> armature bone name
        inv = {v: k2 for k2, v in self.spec["map"].items()}
        self.bones = {}
        for b in self.arm.data.bones:
            short = b.name.split(":")[-1]
            if short.startswith("mixamorig"):
                short = short.split("_", 1)[-1]
            canon = self.spec["map"].get(short, short)
            if canon not in self.bones:
                self.bones[canon] = b.name
        self.canon_of = {v: k2 for k2, v in self.bones.items()}
        bpy.context.view_layer.update()
        self.rest = {c: self.arm.matrix_world @ self.arm.data.bones[n].head_local for c, n in self.bones.items()}
        self._raise_arms()
        self._posed_copy()

    def _apply_all(self):
        bpy.ops.object.select_all(action="DESELECT")
        for o in (self.arm, self.mesh):
            o.select_set(True)
        bpy.context.view_layer.objects.active = self.arm
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    def _raise_arms(self):
        bpy.context.view_layer.objects.active = self.arm
        bpy.ops.object.mode_set(mode="POSE")
        for side, sgn in (("Left", 1), ("Right", -1)):
            pb = self.arm.pose.bones[self.bones[side + "Arm"]]
            head = pb.head.copy()
            # how far the arm already hangs from vertical, so every body ends up alike
            d = (self.arm.pose.bones[self.bones[side + "ForeArm"]].head - head).normalized()
            have = math.degrees(math.atan2(abs(d.x), -d.z))
            ang = math.radians(46.0 - have) * sgn     # raises an A-pose, lowers a T-pose
            R = Matrix.Translation(head) @ Matrix.Rotation(-ang, 4, "Y") @ Matrix.Translation(-head)
            pb.matrix = R @ pb.matrix
            bpy.context.view_layer.update()
        bpy.ops.object.mode_set(mode="OBJECT")
        bpy.context.view_layer.update()

    def _posed_copy(self):
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(self.mesh.evaluated_get(dg), depsgraph=dg)
        me.transform(self.mesh.matrix_world)
        self.posed = bpy.data.objects.new("BodyPosed", me)
        bpy.context.scene.collection.objects.link(self.posed)
        self.mesh.hide_set(True)
        gname = {g.index: g.name for g in self.mesh.vertex_groups}
        self.dom = []
        for v in self.mesh.data.vertices:
            best = max(v.groups, key=lambda g: g.weight, default=None)
            self.dom.append(self.canon_of.get(gname[best.group], "") if best else "")

    def joint(self, canon):
        return self.arm.pose.bones[self.bones[canon]].head.copy()

    def bvh(self, bones, extra=()):
        me = self.posed.data
        polys = [list(p.vertices) for p in me.polygons if sum(self.dom[i] in bones for i in p.vertices) >= 2]
        return BVHTree.FromPolygons([v.co for v in me.vertices], polys)

    def torso_center(self):
        """Middle of the torso front-to-back, from the mesh between the hips and the chest
        (bones can't say: the CMU rig's spine runs along the back)."""
        lo, hi = self.rest["Hips"].z, self.rest["Spine2"].z
        ys = [v.co.y for i, v in enumerate(self.posed.data.vertices)
              if lo < v.co.z < hi and self.dom[i] in TORSO and abs(v.co.x) < 0.08]
        return Vector((0, (min(ys) + max(ys)) * 0.5, 0))

    def smooth_bvh(self):
        """The covered body with its small detail (nipples, muscle lines) smoothed away:
        what the cloth must clear."""
        if getattr(self, "_smooth", None) is None:
            cover = TORSO | {"LeftArm", "RightArm", "LeftForeArm", "RightForeArm"}
            bm = bmesh.new()
            bm.from_mesh(self.posed.data)
            bm.verts.ensure_lookup_table()
            for _ in range(12):
                bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
            # (smoothing shrinks the body a few mm; clearance's gap allows for it)
            co = [v.co.copy() for v in bm.verts]
            bm.free()
            polys = [list(p.vertices) for p in self.posed.data.polygons if sum(self.dom[i] in cover for i in p.vertices) >= 2]
            self._smooth = BVHTree.FromPolygons(co, polys)
        return self._smooth


def _link(name, bm):
    m = bpy.data.meshes.new(name)
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.get(name)
    if o:
        bpy.data.objects.remove(o)
    o = bpy.data.objects.new(name, m)
    bpy.context.scene.collection.objects.link(o)
    return o


def _hull_ring(row):
    """Radii of a ring replaced by its convex hull: cloth bridges the spine groove and
    the cleavage instead of dipping into them."""
    NT = len(row)
    pts = [(math.sin(2 * math.pi * t / NT) * r, -math.cos(2 * math.pi * t / NT) * r) for t, r in enumerate(row) if r > 0]
    if len(pts) < 3:
        return row
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    out = []
    for t in range(NT):
        dx, dy = math.sin(2 * math.pi * t / NT), -math.cos(2 * math.pi * t / NT)
        best = row[t]
        for i in range(len(hull)):
            a, b = hull[i], hull[(i + 1) % len(hull)]
            ex, ey = b[0] - a[0], b[1] - a[1]
            den = dx * ey - dy * ex
            if abs(den) < 1e-12:
                continue
            s = (a[0] * ey - a[1] * ex) / den        # distance along the ray
            u = (a[0] * dy - a[1] * dx) / den        # position along the edge
            if s > 0 and -1e-6 <= u <= 1 + 1e-6:
                best = max(best, s)
        out.append(best)
    return out


TORSO = {"Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder", "LeftUpLeg", "RightUpLeg"}


def torso(body):
    hips = body.rest["Hips"].z
    neck = body.joint("Neck")
    pit = body.joint("LeftArm").z - 0.10 * body.spec["height"] / 1.75
    low = body.bvh(TORSO)
    high = body.bvh(TORSO | {"LeftArm", "RightArm"}) if P["torso_arms"] else low
    NT = 64
    dz = 0.012
    z0 = hips * P["hem"]
    z1 = neck.z + P["top"]
    zs = [z0 + i * dz for i in range(int((z1 - z0) / dz) + 1)]
    NZ = len(zs)
    C = body.torso_center()
    R = []
    for z in zs:
        bvh = high if z > pit + 0.03 else low
        row = []
        for t in range(NT):
            a = 2 * math.pi * t / NT
            d = Vector((math.sin(a), -math.cos(a), 0))
            h = bvh.ray_cast(Vector((C.x, C.y, z)) + d * 0.8, -d, 0.8)
            row.append((0.8 - h[3] + P["ease"]) if h[0] else 0.0)
        R.append(_hull_ring(row) if max(row) > 0 else row)
    for _ in range(10):
        R = [[(row[t - 1] + 2 * row[t] + row[(t + 1) % NT]) / 4 if row[t] > 0 else 0 for t in range(NT)] for row in R]
    for _ in range(5):
        R = [[(R[max(z - 1, 0)][t] + 2 * R[z][t] + R[min(z + 1, NZ - 1)][t]) / 4 if R[z][t] > 0 else 0
              for t in range(NT)] for z in range(NZ)]
    zp = min(range(NZ), key=lambda i: abs(zs[i] - pit))
    for z in range(NZ - 2, -1, -1):
        for t in range(NT):
            s = math.sin(2 * math.pi * t / NT) ** 2
            tp = P["taper_fb"] * (1 - s) + P["taper_side"] * s
            src = R[z + 1][t]
            if zs[z + 1] > zs[zp]:
                src = src * (1 - s) + min(src, R[zp][t]) * s
            R[z][t] = max(R[z][t], src - tp * dz)
    for z in range(NZ):
        f = smoothstep(z0 + P["flare_h"], z0, zs[z])
        R[z] = [r + P["flare"] * f for r in R[z]]
    bm = bmesh.new()
    rings = []
    top = max(i for i in range(NZ) if max(R[i]) > 0.03)
    for z in range(top + 1):
        rings.append([bm.verts.new(Vector((C.x, C.y, zs[z])) + Vector((math.sin(2 * math.pi * t / NT), -math.cos(2 * math.pi * t / NT), 0)) * max(R[z][t], 0.035))
                      for t in range(NT)])
    for z in range(top):
        for t in range(NT):
            bm.faces.new((rings[z][t], rings[z][(t + 1) % NT], rings[z + 1][(t + 1) % NT], rings[z + 1][t]))
    bm.faces.new(list(reversed(rings[0])))
    cap = bm.verts.new(Vector((C.x, C.y, zs[top] + 0.01)))
    for t in range(NT):
        bm.faces.new((rings[top][t], rings[top][(t + 1) % NT], cap))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _link("JTorso", bm)


def sleeve_path(body, side):
    A = body.joint(side + "Arm")
    E = body.joint(side + "ForeArm")
    H = body.joint(side + "Hand")
    return A, E, H


def sleeve(body, side):
    bvh = body.bvh({side + "Arm", side + "ForeArm"})
    A, E, H = sleeve_path(body, side)
    d1 = (E - A).normalized()
    d2 = (H - E).normalized()
    L1 = (E - A).length
    L2 = (H - E).length
    back = P["sleeve_back"]
    start = A - d1 * back
    total = back + L1 + L2 * P["cuff_at"]
    sE = back + L1
    NS = 48
    NT = 32
    bm = bmesh.new()
    vr = []
    for i in range(NS + 1):
        s = total * i / NS
        c = start + d1 * s if s <= sE else E + d2 * (s - sE)
        w = max(0.0, 1 - abs(s - sE) / 0.07) * 0.5
        d = (d1 * (1 - w) + d2 * w).normalized() if s < sE else (d1 * w + d2 * (1 - w)).normalized()
        x = d.cross(Vector((0, -1, 0))).normalized()
        y = d.cross(x).normalized()
        u = s / total
        r = P["sh_r"] * (1 - u) + P["cuff_r"] * u
        mx = 0.0
        for t in range(16):
            a = 2 * math.pi * t / 16
            dv = x * math.cos(a) + y * math.sin(a)
            h = bvh.ray_cast(c + dv * 0.3, -dv, 0.3)
            if h[0]:
                mx = max(mx, 0.3 - h[3])
        if s > 0.08:
            r = max(r, mx + P["sleeve_ease"])
        dome = 0.09
        if s < dome:
            r *= math.sqrt(max(0.0, 1 - ((dome - s) / dome) ** 2)) * 0.85 + 0.15
        vr.append([bm.verts.new(c + (x * math.cos(2 * math.pi * t / NT) + y * math.sin(2 * math.pi * t / NT)) * r) for t in range(NT)])
    for i in range(NS):
        for t in range(NT):
            bm.faces.new((vr[i][t], vr[i][(t + 1) % NT], vr[i + 1][(t + 1) % NT], vr[i + 1][t]))
    bm.faces.new(vr[0])
    bm.faces.new(list(reversed(vr[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _link("JSleeve" + side, bm)


def shell(body):
    parts = [torso(body), sleeve(body, "Left"), sleeve(body, "Right")]
    o = bpy.data.objects.get("Jersey")
    if o:
        bpy.data.objects.remove(o)
    cp = []
    for p in parts:
        c = p.copy()
        c.data = p.data.copy()
        bpy.context.scene.collection.objects.link(c)
        cp.append(c)
        p.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    for c in cp:
        c.select_set(True)
    bpy.context.view_layer.objects.active = cp[0]
    bpy.ops.object.join()
    j = bpy.context.active_object
    j.name = "Jersey"
    j.data.remesh_voxel_size = P["voxel"]
    bpy.ops.object.voxel_remesh()
    m = j.modifiers.new("smooth", "SMOOTH")
    m.factor = 0.8
    m.iterations = 25
    bpy.ops.object.modifier_apply(modifier="smooth")
    if P["shoulder_smooth"]:
        _round_shoulders(body, j, P["shoulder_smooth"])
    return j


def _round_shoulders(body, j, passes, radius=0.14):
    """Extra smoothing around each shoulder joint, fading out with distance, so the
    torso's top and the sleeve's start blend into one round curve."""
    bm = bmesh.new()
    bm.from_mesh(j.data)
    joints = [body.joint(s + "Arm") for s in ("Left", "Right")]
    falloff = {}
    for v in bm.verts:
        d = min((v.co - c).length for c in joints)
        if d < radius:
            falloff[v] = 1.0 - smoothstep(radius * 0.4, radius, d)
    verts = list(falloff)
    for _ in range(passes):
        avg = {v: sum((e.other_vert(v).co for e in v.link_edges), Vector()) / max(len(v.link_edges), 1) for v in verts}
        for v in verts:
            v.co = v.co.lerp(avg[v], 0.5 * falloff[v])
    bm.to_mesh(j.data)
    bm.free()


def clearance(body, j, gap=0.018, iters=3):
    """Push the cloth out wherever the body comes closer than `gap` (shoulders, bust)."""
    bvh = body.smooth_bvh()
    me = j.data
    # Only the shoulders and sleeves: the torso rings are already hull + ease, and
    # pushing there would print the body's detail (nipples) through.
    z_sh = body.joint("LeftArm").z - 0.04
    for _ in range(iters):
        me.update()
        moved = 0
        for v in me.vertices:
            if v.co.z < z_sh and part_of(body, v.co)[2] > 0.13:
                continue
            loc, nrm, _, dist = bvh.find_nearest(v.co, 0.08)
            if loc is None:
                continue
            out = v.co - loc
            side = out.dot(nrm)
            if side < gap:
                v.co = loc + nrm * gap if side < 0 else v.co + nrm * (gap - side)
                moved += 1
        m = j.modifiers.new("relax", "SMOOTH")
        m.factor = 0.5
        m.iterations = 2
        bpy.context.view_layer.objects.active = j
        bpy.ops.object.modifier_apply(modifier="relax")
    return moved


def part_of(body, p):
    """(sleeve side or None, position along the sleeve 0..1, angle around it, axis frame)."""
    best = (None, 0.0, 1e9)
    for side in ("Left", "Right"):
        A, E, H = sleeve_path(body, side)
        L1 = (E - A).length
        L2 = (H - E).length * P["cuff_at"]
        for a, b, s0, ln in ((A, E, 0.0, L1), (E, H, L1, L2)):
            d = (b - a).normalized()
            t = max(-0.05, min(ln, (p - a).dot(d)))
            dist = (p - (a + d * t)).length
            if dist < best[2]:
                best = (side, (s0 + t) / (L1 + L2), dist)
    return best


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def folds(body, j, amp=1.0):
    """Fabric folds as displacement along the normals."""
    me = j.data
    me.update()
    hips = body.rest["Hips"].z
    z_hem = hips * P["hem"]
    chest = body.joint("Spine2").z
    C = body.torso_center()
    pits = {s: body.joint(s + "Arm") + Vector((0.0, 0.0, -0.10)) for s in ("Left", "Right")}
    for v in me.vertices:
        p = v.co
        n = v.normal
        side, u, dist = part_of(body, p)
        sleeve_k = 0.0
        if side is not None:
            A = body.joint(side + "Arm")
            # how far out along the arm, measured from the shoulder joint
            along = (p - A).dot((body.joint(side + "ForeArm") - A).normalized())
            sleeve_k = smoothstep(-0.02, 0.06, along) * (1.0 - smoothstep(0.14, 0.2, dist))
        d = 0.0
        # Torso: vertical drape folds, deeper toward the hem, warped so they wander.
        ang = math.atan2(p.x - C.x, -(p.y - C.y))
        warp = noise.noise(Vector((p.x * 4, p.y * 4, p.z * 3))) * 1.2
        hang = smoothstep(chest + 0.02, z_hem, p.z)          # 0 at the chest, 1 at the hem
        drape = math.sin(ang * 11 + warp + p.z * 2.0) * 0.5 + math.sin(ang * 6 - warp * 0.7) * 0.5
        d += drape * (0.0025 + 0.006 * hang) * (1 - sleeve_k)
        # Drag lines from each armpit toward the middle of the body.
        for s, pit in pits.items():
            q = p - pit
            r = q.length
            if r < 0.2:
                sx = 1 if s == "Left" else -1
                diag = Vector((-sx * 0.6, 0, -0.8)).normalized()
                across = q - diag * q.dot(diag)
                k = (1 - smoothstep(0.05, 0.2, r)) * (1 - sleeve_k * 0.5)
                d += math.sin(across.length * 70 + noise.noise(q * 9) * 1.5) * 0.004 * k
        # Sleeves: crumple rings around the elbow, bunching at the cuff, long folds under the arm.
        if sleeve_k > 0:
            A, E, H = sleeve_path(body, side)
            ax = (E - A).normalized() if u < 0.55 else (H - E).normalized()
            # angle around the sleeve, so the folds can run diagonally (spiral) and zigzag
            x = ax.cross(Vector((0, -1, 0))).normalized()
            y = ax.cross(x)
            q = p - A
            phi = math.atan2(q.dot(y), q.dot(x))
            warp = noise.noise(Vector((p.x * 7, p.y * 7, p.z * 7))) * 2.5
            elbow = math.exp(-((u - 0.5) * 6) ** 2)
            cuff = smoothstep(0.8, 0.97, u)
            zig = math.sin(u * 48 + math.sin(phi * 2 + warp) * 1.8 + warp)
            # break the rings up: each fold only runs part way around
            patch = smoothstep(-0.1, 0.4, noise.noise(Vector((u * 9, math.cos(phi) * 1.5, math.sin(phi) * 1.5))))
            under = smoothstep(0.2, 0.8, n.dot(Vector((0, 0, -1))))
            long_f = math.sin(phi * 7 + warp) * under * (1 - smoothstep(0.15, 0.45, u))
            d += (zig * patch * (0.006 * elbow + 0.0045 * cuff + 0.0015) + long_f * 0.0045) * sleeve_k
        # A little uneven everywhere.
        d += noise.noise(Vector((p.x * 9, p.y * 9, p.z * 9))) * 0.002
        v.co = p + n * d * amp
    me.update()


def cut_openings(body, j):
    """Hem, cuffs and the neck with a shallow V in front."""
    bm = bmesh.new()
    bm.from_mesh(j.data)
    hips = body.rest["Hips"].z
    z_hem = hips * P["hem"] + 0.006
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z_hem), plane_no=(0, 0, 1), clear_inner=True)
    for side in ("Left", "Right"):
        A, E, H = sleeve_path(body, side)
        d = (H - E).normalized()
        c = E + d * ((H - E).length * P["cuff_at"] - 0.006)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=c, plane_no=d, clear_outer=True)
    # Neck: an ellipse around the neck seen from above, tilted (lower in front), with a V.
    neck = body.joint("Neck")
    head = body.joint("Head")
    k = body.spec["height"] / 1.75
    rx, ry = 0.078 * k, 0.07 * k
    cy = neck.y - 0.006
    v_depth = 0.04 * k         # how far the V drops below the front of the opening
    v_half = 0.024 * k         # half width of the V at the top
    kill = []
    for v in bm.verts:
        p = v.co
        if p.z < neck.z - 0.12:
            continue
        ex = p.x / rx
        ey = (p.y - cy) / ry
        inside = ex * ex + ey * ey < 1.0 and p.z > neck.z - 0.05
        # and anything standing up around the neck above the collar line (a thick neck
        # reaches past the ellipse): higher at the back, lower in front
        if P["collar_line"] and not inside and math.hypot(p.x, p.y - cy) < 0.17 * k:
            back = max(0.0, (p.y - cy)) / max(math.hypot(p.x, p.y - cy), 1e-6)
            front = max(0.0, -(p.y - cy)) / max(math.hypot(p.x, p.y - cy), 1e-6)
            z_line = neck.z + 0.015 * k * back - 0.02 * k * front
            inside = p.z > z_line
        front = p.y < cy - ry * 0.4
        if front and abs(p.x) < v_half:
            # top of the front edge of the opening, then the V drops below it
            z_open = neck.z - 0.02 * k
            depth = v_depth * (1 - abs(p.x) / v_half)
            if p.z > z_open - depth:
                inside = True
        if inside:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    # drop slivers left by the cuts
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(j.data)
    bm.free()


def decimate(j, ratio):
    m = j.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    bpy.context.view_layer.objects.active = j
    bpy.ops.object.modifier_apply(modifier="dec")
    # back to quads where it can, cleaner to look at and to shade
    bm = bmesh.new()
    bm.from_mesh(j.data)
    bmesh.ops.join_triangles(bm, faces=bm.faces[:], angle_face_threshold=0.5, angle_shape_threshold=0.7)
    bm.to_mesh(j.data)
    bm.free()


def _boundary_loops(bm):
    edges = {e for e in bm.edges if e.is_boundary}
    loops = []
    while edges:
        e = edges.pop()
        loop = [e.verts[0], e.verts[1]]
        while True:
            last = loop[-1]
            nxt = next((x for x in last.link_edges if x in edges), None)
            if nxt is None:
                break
            edges.discard(nxt)
            o = nxt.other_vert(last)
            if o == loop[0]:
                break
            loop.append(o)
        loops.append(loop)
    return loops


def _resample(pts, n, closed=True):
    seg = [(pts[i] - pts[(i + 1) % len(pts)]).length for i in range(len(pts) if closed else len(pts) - 1)]
    total = sum(seg)
    out = []
    i = 0
    acc = 0.0
    for k in range(n):
        target = total * k / n
        while acc + seg[i] < target and i < len(seg) - 1:
            acc += seg[i]
            i += 1
        t = (target - acc) / seg[i] if seg[i] > 0 else 0
        out.append(pts[i].lerp(pts[(i + 1) % len(pts)], t))
    return out


def _closest_on_seg(p, a, b):
    d = b - a
    ln = d.length_squared
    if ln < 1e-12:
        return a.copy()
    return a + d * max(0.0, min(1.0, (p - a).dot(d) / ln))


PART_BODY, PART_COLLAR, PART_LACE = 0.0, 0.5, 1.0   # "part" color attribute (red channel)


def thickness(j, t=0.005):
    """Cloth thickness: an inner layer and a rim at every opening, so the hem, cuffs and
    neck read as fabric edges instead of a paper-thin cut."""
    m = j.modifiers.new("thick", "SOLIDIFY")
    m.thickness = t
    m.offset = -1.0
    m.use_rim = True
    m.use_even_offset = True
    m.use_quality_normals = True
    bpy.context.view_layer.objects.active = j
    bpy.ops.object.modifier_apply(modifier="thick")
    # Even thickness can throw a vertex at a very sharp corner far out (a spike off the
    # male goalie's collar): pull anything far from its neighbors back among them.
    bm = bmesh.new()
    bm.from_mesh(j.data)
    fixed = 0
    for _ in range(3):
        for v in bm.verts:
            if not v.link_edges:
                continue
            avg = sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges)
            if (v.co - avg).length > 0.03:
                v.co = avg
                fixed += 1
    bm.to_mesh(j.data)
    bm.free()
    if fixed:
        print("  thickness: pulled in %d stray vertices" % fixed)


def collar(body, j):
    """Rib-knit collar band over the neck opening's edge (shallow V in front), plus laces
    across the V. Returns the collar object (joined into the jersey by the caller)."""
    bm = bmesh.new()
    bm.from_mesh(j.data)
    neck = body.joint("Neck")
    loops = [l for l in _boundary_loops(bm) if sum(v.co.z for v in l) / len(l) > neck.z - 0.12]
    loop = max(loops, key=len)
    pts = [v.co.copy() for v in loop]
    jb = BVHTree.FromBMesh(bm)
    N = 120
    pts = _resample(pts, N)
    # the V's point: the lowest point of the opening near the middle, in front
    front = min(range(N), key=lambda i: pts[i].z + abs(pts[i].x) * 4 if pts[i].y < neck.y else 9)
    # smooth the jagged cut, less toward the V so it stays pointed
    keep = [math.exp(-(min(abs(i - front), N - abs(i - front)) / 4.0) ** 2) for i in range(N)]
    for _ in range(10):
        pts = [pts[i].lerp(pts[i] * 0.5 + (pts[i - 1] + pts[(i + 1) % N]) * 0.25, 1 - keep[i]) for i in range(N)]
    # Snap the jersey's own cut edge onto the smoothed curve: the vertex-by-vertex cut is
    # jagged, and its teeth would stick out from under the band.
    for v in loop:
        best = min(((pts[i], pts[(i + 1) % N]) for i in range(N)),
                   key=lambda s: (v.co - _closest_on_seg(v.co, s[0], s[1])).length)
        v.co = _closest_on_seg(v.co, best[0], best[1])
    # Snapping leaves long thin triangles next to the edge, which shade as facets: relax
    # a band around the opening (the edge itself stays put), keeping it on the surface.
    edge = set(loop)
    ring = set(edge)
    for _ in range(4):
        ring |= {e.other_vert(v) for v in list(ring) for e in v.link_edges}
    band = [v for v in ring if v not in edge]
    for _ in range(12):
        co = {v: sum((e.other_vert(v).co for e in v.link_edges), Vector()) / max(len(v.link_edges), 1) for v in band}
        for v in band:
            v.co = v.co.lerp(co[v], 0.6)
            loc, _, _, _ = jb.find_nearest(v.co)
            if loc is not None:
                v.co = loc
    bm.to_mesh(j.data)
    bm.free()
    out = bmesh.new()
    k = body.spec["height"] / 1.75
    width = 0.026 * k
    thick = 0.0075 * k
    prof = []
    for a in range(12):
        t = 2 * math.pi * a / 12
        # rounded rectangle: across the band (b) and through it (n)
        cb, cn = math.cos(t), math.sin(t)
        prof.append((math.copysign(abs(cb) ** 0.4, cb) * width * 0.5, math.copysign(abs(cn) ** 0.6, cn) * thick * 0.5))
    rings = []
    cy = neck.y
    for i, p in enumerate(pts):
        tang = (pts[(i + 1) % N] - pts[i - 1]).normalized()
        loc, n, _, _ = jb.find_nearest(p)
        out_dir = Vector((p.x, p.y - cy, 0)).normalized()
        if n.dot(out_dir) < 0:
            n = -n
        b = tang.cross(n).normalized()
        if b.z < 0:
            b = -b
        # band stands up a little from the jersey toward the neck
        c = p + b * width * 0.15 + n * thick * 0.2
        rings.append([out.verts.new(c + b * pb + n * pn) for pb, pn in prof])
    for i in range(N):
        for a in range(12):
            out.faces.new((rings[i][a], rings[i][(a + 1) % 12], rings[(i + 1) % N][(a + 1) % 12], rings[(i + 1) % N][a]))
    # Laces across the V: three crossings between the two sides, tails hanging below.
    vp = pts[front]
    left = [pts[(front + d) % N] for d in range(3, 14, 4)]
    right = [pts[(front - d) % N] for d in range(3, 14, 4)]
    _, vn, _, _ = jb.find_nearest(vp)
    if vn.y > 0:
        vn = -vn
    lace_r = 0.0028 * k

    def tube(a, b, r=lace_r, seg=6):
        d = (b - a)
        ln = d.length
        if ln < 1e-5:
            return
        d.normalize()
        x = d.cross(Vector((0, 0, 1)))
        if x.length < 1e-3:
            x = d.cross(Vector((1, 0, 0)))
        x.normalize()
        y = d.cross(x)
        ra = [out.verts.new(a + (x * math.cos(2 * math.pi * s / seg) + y * math.sin(2 * math.pi * s / seg)) * r) for s in range(seg)]
        rb = [out.verts.new(b + (x * math.cos(2 * math.pi * s / seg) + y * math.sin(2 * math.pi * s / seg)) * r) for s in range(seg)]
        for s in range(seg):
            out.faces.new((ra[s], ra[(s + 1) % seg], rb[(s + 1) % seg], rb[s]))
    lift = vn * (thick * 0.9)
    L = [p + lift for p in left]     # bottom (next to the V's point) to top
    Rr = [p + lift for p in right]
    # criss-cross up the V, a bar across the top
    for i in range(len(L) - 1):
        mid = (L[i] + Rr[i + 1]) * 0.5 + vn * 0.0015      # over / under at the crossing
        tube(L[i], mid)
        tube(mid, Rr[i + 1])
        mid = (Rr[i] + L[i + 1]) * 0.5 - vn * 0.0005
        tube(Rr[i], mid)
        tube(mid, L[i + 1])
    tube(L[-1], Rr[-1])
    knot = vp + lift * 1.3 + Vector((0, 0, 0.006 * k))
    tube(L[0], knot)
    tube(Rr[0], knot)
    for sx, ln in ((-1, 0.075), (1, 0.06)):
        tail_end = knot + Vector((sx * 0.012, 0, -ln * k)) + vn * 0.012
        mid = knot.lerp(tail_end, 0.5) + vn * 0.006
        tube(knot, mid)
        tube(mid, tail_end)
    me = bpy.data.meshes.new("Collar")
    out.to_mesh(me)
    out.free()
    o = bpy.data.objects.get("Collar")
    if o:
        bpy.data.objects.remove(o)
    o = bpy.data.objects.new("Collar", me)
    bpy.context.scene.collection.objects.link(o)
    # mark collar vs laces (laces are the small tubes after the band)
    band_verts = N * 12
    col = me.color_attributes.new("part", "FLOAT_COLOR", "POINT")
    for i in range(len(me.vertices)):
        col.data[i].color = (PART_COLLAR if i < band_verts else PART_LACE, 0, 0, 1)
    return o


def _remap(canon):
    """Bones the jersey may follow: the hem must not swing with the thighs, nor the
    collar with the head, nor the cuffs with the fingers."""
    if canon.endswith("UpLeg") or canon in ("LeftLeg", "RightLeg") or canon.endswith("HipJoint"):
        return "Hips"
    if canon.startswith("Head") or canon.startswith("Neck"):
        return "Spine2"      # the collar sits on the shoulders, it doesn't turn with the head
    # Hands, fingers and thumbs (CMU: LThumb, LeftFingerBase, LeftHandFinger1): the rig
    # folds the fingers away under the gloves, and cuff vertices following them were
    # dragged out into long strips.
    if "Hand" in canon or "Finger" in canon or "Thumb" in canon:
        return ("Left" if canon.startswith("L") else "Right") + "ForeArm"
    return canon


def skin(body, j, smooth_iters=30):
    """Weights from the nearest point of the body, smoothed over the cloth."""
    cover = TORSO | {"LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Neck", "LeftHand", "RightHand"}
    me = body.posed.data
    polys = [p for p in me.polygons if sum(body.dom[i] in cover for i in p.vertices) >= 2]
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in polys])
    gname = {g.index: g.name for g in body.mesh.vertex_groups}
    src = body.mesh.data.vertices
    W = []
    for v in j.data.vertices:
        loc, _, fi, _ = bvh.find_nearest(v.co)
        w = {}
        if loc is not None:
            pv = polys[fi].vertices
            ds = [max((me.vertices[i].co - loc).length, 1e-5) for i in pv]
            for i, dd in zip(pv, ds):
                for g in src[i].groups:
                    c = _remap(body.canon_of.get(gname[g.group], "Hips"))
                    w[c] = w.get(c, 0.0) + g.weight / dd
        W.append(w)
    # smooth over the cloth's own edges
    nbr = [[] for _ in j.data.vertices]
    for e in j.data.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    for _ in range(smooth_iters):
        nxt = []
        for i, w in enumerate(W):
            acc = {k: v * 2.0 for k, v in _norm(w).items()}
            for n in nbr[i]:
                for k, v in _norm(W[n]).items():
                    acc[k] = acc.get(k, 0.0) + v
            nxt.append(acc)
        W = nxt
    # Below the hips joint the jersey rides with the pelvis: following the lower spine,
    # the hem lifted off the pants whenever the back bent.
    hz = body.joint("Hips").z
    for i, v in enumerate(j.data.vertices if P["pin_hem"] else []):
        t = smoothstep(hz + 0.02, hz - 0.06, v.co.z)
        if t > 0:
            w = {k: x * (1 - t) for k, x in _norm(W[i]).items()}
            w["Hips"] = w.get("Hips", 0.0) + t
            W[i] = w
    # Cloth past the shoulder joint follows the upper arm. Skinned to the collarbone (as
    # the body's deltoid is), it stays out when a T-pose arm drops to the side and sticks
    # out like a shoulder pad.
    if P["deltoid_to_arm"]:
        for side in ("Left", "Right"):
            A = body.joint(side + "Arm")
            d = (body.joint(side + "ForeArm") - A).normalized()
            for i, v in enumerate(j.data.vertices):
                if (v.co.x > 0) != (side == "Left"):
                    continue
                t = smoothstep(-0.05, 0.05, (v.co - A).dot(d)) * P["deltoid_to_arm"]
                if t > 0:
                    w = {k: x * (1 - t) for k, x in _norm(W[i]).items()}
                    w[side + "Arm"] = w.get(side + "Arm", 0.0) + t
                    W[i] = w
    # Extra passes around the shoulders where the arm turns a long way from the bind pose
    # (a T-pose body): the blend spreads over more cloth instead of folding into a crease.
    if P["shoulder_weight_smooth"]:
        joints = [body.joint(s + "Arm") for s in ("Left", "Right")]
        near = [i for i, v in enumerate(j.data.vertices) if min((v.co - c).length for c in joints) < 0.18]
        for _ in range(P["shoulder_weight_smooth"]):
            nxt = list(W)
            for i in near:
                acc = {k: v * 2.0 for k, v in _norm(W[i]).items()}
                for n in nbr[i]:
                    for k, v in _norm(W[n]).items():
                        acc[k] = acc.get(k, 0.0) + v
                nxt[i] = acc
            W = nxt
    # Collar and laces follow the jersey they're sewn to: on a roomy (goalie) cut they sit
    # far off the neck, and the body's nearest point could be on an arm, which swung them
    # out into spikes.
    part = j.data.color_attributes.get("part")
    if part is not None:
        from mathutils.kdtree import KDTree
        cloth = [i for i, d in enumerate(part.data) if d.color[0] < 0.25]
        kd = KDTree(len(cloth))
        for k, i in enumerate(cloth):
            kd.insert(j.data.vertices[i].co, k)
        kd.balance()
        for i, d in enumerate(part.data):
            if d.color[0] >= 0.25:
                _, k, _ = kd.find(j.data.vertices[i].co)
                W[i] = dict(W[cloth[k]])
    out = []
    for w in W:
        top = sorted(_norm(w).items(), key=lambda kv: -kv[1])[:4]
        out.append(_norm(dict(kv for kv in top if kv[1] > 0.01)))
    return out


def _norm(w):
    s = sum(w.values())
    return {k: v / s for k, v in w.items()} if s > 0 else {"Spine2": 1.0}


def to_rest(body, j, W):
    """Undo the modelling pose: v_rest = (sum w_i S_i)^-1 v_posed, exact for linear
    blend skinning. Returns a new object in the bind pose, skinned to the armature."""
    S = {}
    for c, n in body.bones.items():
        pb = body.arm.pose.bones[n]
        S[c] = pb.matrix @ body.arm.data.bones[n].matrix_local.inverted()
    me = j.data.copy()
    me.name = "JerseyRest"
    for v, w in zip(me.vertices, W):
        M = Matrix(((0,) * 4,) * 4)
        for c, x in w.items():
            M = M + S[c] * x
        v.co = M.inverted() @ v.co
    o = bpy.data.objects.get("JerseyRest")
    if o:
        bpy.data.objects.remove(o)
    o = bpy.data.objects.new("JerseyRest", me)
    bpy.context.scene.collection.objects.link(o)
    for c, n in body.bones.items():
        if any(c in w for w in W):
            o.vertex_groups.new(name=n)
    for i, w in enumerate(W):
        for c, x in w.items():
            o.vertex_groups[body.bones[c]].add([i], x, "REPLACE")
    for p in me.polygons:
        p.use_smooth = True
    o.parent = body.arm
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = body.arm
    return o


def export(body, o, path):
    for pb in body.arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.hide_set(False)
    o.select_set(True)
    body.arm.select_set(True)
    bpy.context.view_layer.objects.active = o
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
              export_animations=False, export_apply=False, export_yup=True, export_normals=True,
              export_texcoords=False, export_materials="NONE")
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    if "export_vertex_color" in props:
        kw["export_vertex_color"] = "ACTIVE"
    elif "export_colors" in props:
        kw["export_colors"] = True
    bpy.ops.export_scene.gltf(**kw)


## Goalie cut, on top of the body's shape: room for a chest protector and arm pads
## underneath (much more ease, especially down the arms), a boxy straight body and a longer
## hem. -> jersey_<body>_goalie.glb
GOALIE = dict(ease=0.07, sleeve_ease=0.055, gap=0.05, taper_fb=0.02, taper_side=0.03,
              sh_r=0.135, cuff_r=0.095, hem=0.84, flare=0.04)


def make(name, out_dir=None, goalie=False):
    body = Body(name)
    if goalie:
        P.update(GOALIE)
    j = shell(body)
    clearance(body, j, gap=P["gap"])
    folds(body, j)
    clearance(body, j, gap=P["gap"], iters=1)
    decimate(j, 0.3)
    cut_openings(body, j)
    c = collar(body, j)
    thickness(j)
    col = j.data.color_attributes.new("part", "FLOAT_COLOR", "POINT")
    for d in col.data:
        d.color = (PART_BODY, 0, 0, 1)
    bpy.ops.object.select_all(action="DESELECT")
    c.select_set(True)
    j.select_set(True)
    bpy.context.view_layer.objects.active = j
    bpy.ops.object.join()
    j.data.color_attributes.active_color = j.data.color_attributes["part"]
    W = skin(body, j)
    rest = to_rest(body, j, W)
    path = os.path.join(out_dir or os.path.join(ROOT, "assets", "characters"),
                        "jersey_%s%s.glb" % (name, "_goalie" if goalie else ""))
    export(body, rest, path)
    print("jersey %s%s: %d verts -> %s" % (name, " (goalie)" if goalie else "", len(rest.data.vertices), path))
    return body, rest


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for which in (argv or ["female", "male"]):    # (ybot is only a fallback body)
        make(which)
        make(which, goalie=True)
