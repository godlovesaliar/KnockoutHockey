# Generates the game's bodies with MPFB (the MakeHuman extension for Blender; its output is
# CC0). They took the place of the two downloaded bodies the game began with ("the first
# male / female" below): the head, rig layout and rest pose were matched to those, because
# the helmets, masks, hair, jerseys and clips had all been fitted to them.
#
# Run in Blender (MPFB enabled):
#   exec(open(r"<project>/tools/blender/mpfb_body.py").read()); make("male")     (or "female")
# Writes assets/player/mpfb_<body>.glb: the body mesh ("mpfb_<body>"), the eyes
# ("mpfb_<body>_eyes", as tools/build_characters.gd looks for them) and the rig.
# tools/build_characters.gd builds them as bodies "male" and "female" (-- body=male).
# paint_eyes() writes the eye picture (assets/player/own_eyes.png). The skin picture is
# painted by tools/blender/skin_paint.py from the body this writes.
#
# What comes from where:
#   * the body: MPFB's base mesh shaped by the macro settings in BODIES (gender, age,
#     muscle, weight, proportions), its helper geometry removed, then the head brought to
#     the first body's head size (HEAD_FIT: the helmets, masks and hair are all fitted to
#     that head), feet on the floor
#   * the rig and skin weights: the MPFB rig laid out like the first body's, re-rested to
#     the first body's rest pose, so the joints sit where the jersey cut, the gear and the
#     uniform's stripes expect them. The male: "cmu_mb" (the hips joint level with the hip
#     joints, the collarbones starting at the spine), the collarbones level and the arms
#     straight out (REST). MPFB's own rest has the shoulders dropped and the arms at 45
#     degrees; the game's clips hold the collarbones level, which lifted the shoulders 7 cm
#     off where the jersey was modelled. The female: "mixamo" (the hips joint above the hip
#     joints, the collarbones starting out at the shoulders, as the first female's rig has
#     them), resting as the first female does: the collarbones dropped 23 degrees, the
#     arms down at her sides. That is where the game's clips hold a Mixamo-style collarbone
#     (measured in the game: level in the rest pose, they came down 5 cm in play and the
#     jersey's collar stood up to her jaw), and her jersey's cut is drawn for arms that hang
#     (on straight-out arms the cloth over the shoulder swings out like a wing when they
#     drop).
#   * the skin picture (assets/player/mpfb_<body>_skin.png): our own, painted by
#     tools/blender/skin_paint.py over the body's shape. bake_skin() here is the plain one
#     it replaced (MPFB's procedural "v2" skin, baked; it writes the same file). The game
#     tints the picture to each player's skin tone.
#   * the eyes: our own. Two balls built here (eyeballs()), one in each eye socket (a ball
#     fitted to MPFB's helper eye, which marks where an eye goes), and our own painted
#     picture (paint_eyes()). The picture is laid out the way scenes/actors/eye.gdshader
#     expects (EYE): one iris per eye at fixed spots, the ball unrolled around it evenly, so
#     the shader can slide the iris across the ball to where the player looks.
#
# Works in its own "BodyLab" scene. The female stands at x = -0.9 once exported.

import math
import os

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\mpfb_body.py")))))
LAB = "BodyLab"
BODIES = {
    "male": {
        "macro": {"gender": 1.0, "age": 0.5, "muscle": 0.9, "weight": 0.42, "proportions": 0.45, "height": 0.5,
                  "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
        # MPFB's own shape targets on top of the macro shape ("<folder>/<target>": weight).
        "targets": {"neck/neck-scale-horiz-incr": 0.5},
        "height": 1.84,
        # The first body's head (m at `height`): ear to ear, crown to the bottom of the
        # chin, nose tip to the back of the skull. The new head is scaled to it.
        # (Measured with head_size() below on it.)
        "head": (0.1922, 0.234, 0.2385),
    },
    "female": {
        # (the first female is MakeHuman's plain "female_generic": every setting near the
        # middle. Tuned against her widths and joint heights in the game: MPFB's own female
        # comes out with wider shoulders, narrower hips and shorter thighs.)
        "macro": {"gender": 0.0, "age": 0.5, "muscle": 0.35, "weight": 0.57, "proportions": 0.5, "height": 0.5,
                  "cupsize": 0.45, "firmness": 0.6, "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
        "targets": {"torso/measure-shoulder-dist-decr": 1.0, "legs/measure-upperleg-height-incr": 0.3,
                    "hip/hip-scale-horiz-incr": 0.15, "legs/measure-knee-circ-incr": 0.25},
        "height": 1.75,
        # The first female's head, measured on the game's copy of it (tools/dump_heads.gd).
        "head": (0.1868, 0.23, 0.2308),
        # Her rig is a Mixamo one, resting as the first female's does (measured on it).
        "rig": "mixamo", "prefix": "mixamorig:",
        "rest": [("Shoulder", "Arm", (0.9219, 0.0131, -0.3871)), ("Arm", "ForeArm", (0.3088, -0.0337, -0.9505)),
                 ("ForeArm", "Hand", (0.2492, -0.0232, -0.9682)), ("UpLeg", "Leg", (0.0208, 0.0428, -0.9989)),
                 ("Leg", "Foot", (0.038, 0.0742, -0.9965))],
        "lab_x": -0.9,
    },
}
HEAD_BONE = "Head"
RIG = "cmu_mb"
# The rest pose: where each of these bones points (toward its child; Blender axes, the left
# side: +X the body's left, -Y its front, +Z up), measured on the first male's rig.
REST = [("Shoulder", "Arm", (1.0, 0.03, 0.03)), ("Arm", "ForeArm", (1.0, 0.04, -0.04)),
        ("ForeArm", "Hand", (1.0, -0.07, 0.05)), ("UpLeg", "Leg", (0.03, -0.09, -1.0)),
        ("Leg", "Foot", (0.04, 0.04, -1.0))]
# The eyes. Each ball covers `reach` degrees from straight ahead (a little past half: the
# game measures the ball by its width). The picture: (u, v) from the top left, as the game
# reads it. An eye's straight-ahead point is its `centers` entry (where eye.gdshader has its
# iris: iris_r / iris_l), and a point `t` radians off straight ahead lies `per_rad * t` from
# it, in the direction it lies on the ball (up is up). That holds out to `linear` radians
# (the game fits the gaze over the front 57 degrees); past it the rest of the ball is
# squeezed in before `max_r`, half way to the other eye's centre, where the shader hands
# over to the other eye. `iris` and `pupil` are the shader's iris_radius and pupil_radius.
EYE = dict(rings=12, segs=32, reach=100.0, per_rad=0.24, linear=1.0, max_r=0.288,
           centers={"r": (0.290, 0.288), "l": (0.706, 0.700)}, iris=0.118, pupil=0.038,
           picture="assets/player/own_eyes.png")


def lab():
    sc = bpy.data.scenes.get(LAB) or bpy.data.scenes.new(LAB)
    bpy.context.window.scene = sc
    return sc


def world_points(ob):
    """An object's vertices as posed and placed (armature applied)."""
    dg = bpy.context.evaluated_depsgraph_get()
    e = ob.evaluated_get(dg)
    me = e.to_mesh()
    pts = [e.matrix_world @ v.co for v in me.vertices]
    e.to_mesh_clear()
    return pts


def box(pts):
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def group_verts(ob, name):
    gi = ob.vertex_groups[name].index
    return [v.index for v in ob.data.vertices if any(g.group == gi for g in v.groups)]


def head_weight(ob, bone):
    """Per vertex: how much of it rides the head bone (0..1)."""
    ids = [ob.vertex_groups[n].index for n in (bone,) if n in ob.vertex_groups]
    out = []
    for v in ob.data.vertices:
        out.append(sum(g.weight for g in v.groups if g.group in ids))
    return out


def head_size(me, k):
    """(ear to ear, crown to chin, nose to the back of the skull, crown z, back y) of a
    body mesh standing in Blender axes (face toward -Y), in meters at scale `k`."""
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    top = max(v.co.z for v in me.vertices)
    front = []   # the face's profile down the middle: (z, y of the first hit from the front)
    step = 0.004 / k
    for i in range(1, 90):
        z = top - i * step
        loc, _, _, _ = bvh.ray_cast(Vector((0.0, -1.0, z)), Vector((0.0, 1.0, 0.0)))
        if loc is not None:
            front.append((z, loc.y))
    nose = min(front, key=lambda f: f[1])
    # The chin: going down from the nose, where the profile first runs back under the jaw
    # (1 cm back in one 4 mm step).
    chin = front[-1][0]
    below = [f for f in front if f[0] < nose[0] - 0.03 / k]
    for a, b in zip(below, below[1:]):
        if (b[1] - a[1]) * k > 0.01:
            chin = (a[0] + b[0]) * 0.5
            break
    head = [v.co for v in me.vertices if v.co.z > chin and abs(v.co.x) < 0.16 / k]
    back = max(p.y for p in head if p.z > nose[0])
    width = max(p.x for p in head) - min(p.x for p in head)
    return width * k, (top - chin) * k, (back - nose[1]) * k, top, chin, nose[1], back


def ball_fit(pts):
    """The ball through a cloud of points: (center, radius), least squares."""
    import numpy as np

    a = np.array([[p.x, p.y, p.z, 1.0] for p in pts])
    b = np.array([p.length_squared for p in pts])
    x = np.linalg.lstsq(a, b, rcond=None)[0]
    c = Vector(x[:3] * 0.5)
    return c, math.sqrt(x[3] + c.length_squared)


def eye_uv_r(t):
    """How far from an eye's centre in the picture a point `t` radians off straight ahead lies."""
    a, t0 = EYE["per_rad"], EYE["linear"]
    if t <= t0:
        return a * t
    x = min(1.0, (t - t0) / (math.radians(EYE["reach"]) - t0))
    return a * t0 + (EYE["max_r"] - a * t0) * (1.0 - (1.0 - x) ** 2)


def eyeballs(balls, rig, name, bone):
    """Our own eyes: one object `name`, a ball per socket (`balls`: {"l" / "r": (center,
    radius)}; the body faces -Y, its left is +X), riding the head bone."""
    verts, faces, uvs = [], [], []
    rings, segs = EYE["rings"], EYE["segs"]
    for side in ("r", "l"):
        c, r = balls[side]
        cu, cv = EYE["centers"][side]
        base = len(verts)
        verts.append(c + Vector((0.0, -r, 0.0)))
        uvs.append((cu, 1.0 - cv))
        for i in range(1, rings + 1):
            t = math.radians(EYE["reach"]) * i / rings
            ur = eye_uv_r(t)
            for j in range(segs):
                a = math.tau * j / segs
                verts.append(c + Vector((math.sin(t) * math.cos(a), -math.cos(t), math.sin(t) * math.sin(a))) * r)
                # (the picture's v runs down, Blender's up)
                uvs.append((cu + ur * math.cos(a), 1.0 - (cv - ur * math.sin(a))))
        for j in range(segs):
            faces.append((base, base + 1 + j, base + 1 + (j + 1) % segs))
        for i in range(rings - 1):
            a0, a1 = base + 1 + i * segs, base + 1 + (i + 1) * segs
            for j in range(segs):
                k2 = (j + 1) % segs
                faces.append((a0 + j, a1 + j, a1 + k2, a0 + k2))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in verts], [], faces)
    me.update()
    # Every face looking out of its ball.
    flip = 0
    for side, n in (("r", 0), ("l", 1)):
        c = balls[side][0]
        per = len(me.polygons) // 2
        for poly in me.polygons[n * per:(n + 1) * per]:
            if poly.normal.dot(poly.center - c) < 0:
                poly.flip()
                flip += 1
    if flip:
        print("  eyes: %d faces turned outward" % flip)
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    for poly in me.polygons:
        poly.use_smooth = True
    me.update()
    ob = bpy.data.objects.new(name, me)
    lab().collection.objects.link(ob)
    ob.parent = rig
    g = ob.vertex_groups.new(name=bone)
    g.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return ob


def re_rest(rig, meshes, rest, prefix):
    """Poses the rig to `rest` (as REST), bakes that pose into the meshes and makes it the
    rest pose."""
    from mathutils import Matrix

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for bone, child, want in rest:
        for side, sgn in (("Left", 1.0), ("Right", -1.0)):
            pb = rig.pose.bones[prefix + side + bone]
            head = pb.head.copy()
            have = (rig.pose.bones[prefix + side + child].head - head).normalized()
            rot = have.rotation_difference(Vector((want[0] * sgn, want[1], want[2])).normalized())
            pb.matrix = Matrix.Translation(head) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
            bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    for ob in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        for m in [m for m in ob.modifiers if m.type == "ARMATURE"]:
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for ob in meshes:
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = rig


def make(body="male", export=True):
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService

    spec = BODIES[body]
    sc = lab()
    name = "mpfb_" + body
    prefix = spec.get("prefix", "")
    for o in list(sc.objects):
        if o.name.startswith(name):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    bm_ob = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                      feet_on_ground=True, scale=0.1, macro_detail_dict=dict(spec["macro"]))
    bm_ob.name = name
    bpy.context.view_layer.objects.active = bm_ob
    if spec.get("targets"):
        from bl_ext.blender_org.mpfb.services.targetservice import TargetService

        mpfb = os.path.dirname(__import__("bl_ext.blender_org.mpfb", fromlist=["x"]).__file__)
        for target, weight in spec["targets"].items():
            TargetService.load_target(bm_ob, os.path.join(mpfb, "data", "targets", *target.split("/")) + ".target.gz",
                                      weight=weight, name=target.split("/")[-1])
    rig = HumanService.add_builtin_rig(bm_ob, spec.get("rig", RIG), import_weights=True)
    rig.name = name + "_rig"

    # The shape keys (macro targets) baked into the mesh.
    bpy.ops.object.select_all(action="DESELECT")
    bm_ob.select_set(True)
    bpy.context.view_layer.objects.active = bm_ob
    if bm_ob.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)

    # Where the eye sockets are (the ball each of MPFB's helper eyes lies on), before the
    # helpers go.
    me = bm_ob.data
    sockets = {}
    for side in ("l", "r"):
        pts = [me.vertices[i].co.copy() for i in group_verts(bm_ob, "helper-%s-eye" % side)]
        sockets[side] = ball_fit(pts)
        c, r = sockets[side]
        lo, hi = box(pts)
        print("  helper eye %s: %d points, box %s, ball r %.4f, off the ball by up to %.4f" % (
            side, len(pts), [round(x, 4) for x in hi - lo], r, max(abs((p - c).length - r) for p in pts)))

    # The body only: helper geometry and joint cubes removed.
    keep = set(group_verts(bm_ob, "body"))
    for m in list(bm_ob.modifiers):
        if m.type == "MASK":
            bm_ob.modifiers.remove(m)
    b = bmesh.new()
    b.from_mesh(me)
    bmesh.ops.delete(b, geom=[v for v in b.verts if v.index not in keep], context="VERTS")
    b.to_mesh(me)
    b.free()
    me.update()

    # The head brought to the first head's size: scaled about the top of the neck, by
    # how much each vertex rides the head bone (so the neck blends).
    hw = head_weight(bm_ob, prefix + HEAD_BONE)
    k = spec["height"] / (max(v.co.z for v in me.vertices) - min(v.co.z for v in me.vertices))
    w, h, d, top, chin, nose_y, back_y = head_size(me, k)
    s = Vector((spec["head"][0] / w, spec["head"][2] / d, spec["head"][1] / h))
    pivot = Vector((0.0, (nose_y + back_y) * 0.5, chin))
    print("head %.4f wide, %.4f crown to chin, %.4f deep -> scale %s" % (w, h, d, [round(x, 3) for x in s]))

    def fit(p, wgt):
        q = p - pivot
        return p.lerp(pivot + Vector((q.x * s.x, q.y * s.y, q.z * s.z)), wgt)

    for v, wgt in zip(me.vertices, hw):
        if wgt > 0.0:
            v.co = fit(v.co, wgt)
    me.update()
    print("  after: %s" % [round(x, 4) for x in head_size(me, spec["height"] / (max(v.co.z for v in me.vertices) - min(v.co.z for v in me.vertices)))[:3]])

    # Eyes: our own balls, one in each socket (moved and sized with the head; the head's
    # fit is a few percent uneven, a ball takes the middle of it).
    grow = (s.x * s.y * s.z) ** (1.0 / 3.0)
    balls = {side: (fit(c, 1.0), r * grow) for side, (c, r) in sockets.items()}
    eyes = eyeballs(balls, rig, name + "_eyes", prefix + HEAD_BONE)
    for side in ("r", "l"):
        print("  eye %s: center %s, radius %.4f" % (side, [round(x, 4) for x in balls[side][0]], balls[side][1]))

    re_rest(rig, [bm_ob, eyes], spec.get("rest", REST), prefix)
    # (Raising the arms lifts nothing off the floor, but keep the feet at 0.)
    low = min(v.co.z for v in me.vertices)
    if abs(low) > 1e-4:
        print("  feet at %.4f after the re-rest" % low)
    for p in me.polygons:
        p.use_smooth = True
    lo, hi = box([v.co for v in me.vertices])
    print("%s: %d verts, %d polys, %.3f m tall, %d bones" % (name, len(me.vertices), len(me.polygons), hi.z - lo.z, len(rig.data.bones)))
    if export:
        out = os.path.join(PROJECT, "assets", "player", name + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        for o in (rig, bm_ob, eyes):
            o.hide_set(False)
            o.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, use_active_scene=True,
                                  export_yup=True, export_apply=False, export_skins=True, export_animations=False,
                                  export_morph=False, export_materials="NONE", export_normals=True, export_texcoords=True)
        print("wrote", out, round(os.path.getsize(out) / 1e6, 2), "MB")
    rig.location.x = spec.get("lab_x", 0.0)     # (beside the others in the lab, once exported)
    return bm_ob, rig, eyes


def bake_skin(body="male", size=2048, lips=(0.78, 0.45, 0.43), lip_mix=0.55):
    """Bakes MPFB's procedural skin on the body made by make() to a picture, and tints the
    lips (MPFB's lip mask, in the same texture layout). Replaced by skin_paint.py, which
    writes the same file: run this only to get the plain skin back."""
    import numpy as np

    sc = lab()
    ob = bpy.data.objects["mpfb_" + body]
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.mpfb.create_v2_skin()
    mat = ob.data.materials[0]
    img = bpy.data.images.new("mpfb_skin_bake", size, size, alpha=False)
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    was = sc.render.engine
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 4
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    sc.render.bake.margin = 16
    bpy.ops.object.bake(type="DIFFUSE")
    sc.render.engine = was
    px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
    mpfb = os.path.dirname(__import__("bl_ext.blender_org.mpfb", fromlist=["x"]).__file__)
    mask_img = bpy.data.images.load(os.path.join(mpfb, "data", "textures", "mpfb_lips.jpg"))
    mw, mh = mask_img.size
    mask = np.array(mask_img.pixels[:], dtype=np.float32).reshape(mh, mw, 4)[:, :, 0]
    bpy.data.images.remove(mask_img)
    if (mh, mw) != (size, size):
        yi = (np.arange(size) * mh // size)
        xi = (np.arange(size) * mw // size)
        mask = mask[yi][:, xi]
    for c in range(3):
        px[:, :, c] = px[:, :, c] * (1.0 - mask * lip_mix) + lips[c] * mask * lip_mix
    # Outside the body's texture islands the bake is black: filled with the skin's own mean,
    # so the picture's average (which the game's skin shader divides by) is the skin's.
    bare = px[:, :, :3].sum(axis=2) < 0.03
    for c in range(3):
        px[:, :, c][bare] = px[:, :, c][~bare].mean()
    px[:, :, 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    out = os.path.join(PROJECT, "assets", "player", "mpfb_%s_skin.png" % body)
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    print("wrote", out, "mean color", [round(float(px[:, :, c].mean()), 3) for c in range(3)], "lip mask max", float(mask.max()))
    return out


def paint_eyes(size=1024, seed=11):
    """Paints the eye picture (EYE["picture"]): for each eye the white of the eye around its
    centre, veined and pinker toward the back, and the iris: fibers running out from the
    pupil, a paler ring round it, darker toward the rim. The game takes only the iris's
    light and dark from here and colors it per player (eye.gdshader); the brown is for
    anything that shows the picture as it is."""
    import numpy as np

    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    u = (xx + 0.5) / size
    v = (yy + 0.5) / size     # row 0 is the top of the picture
    R, P, MAX = EYE["iris"], EYE["pupil"], EYE["max_r"]
    # The white, in the picture's own (sRGB) values: about what the eye shader was tuned on.
    WHITE = np.array([0.665, 0.65, 0.63])
    BACK = np.array([0.6, 0.545, 0.515])

    def smooth(a, b, x):
        t = np.clip((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    def ring_noise(n, ang):
        """Noise round a circle: `n` random values, read smoothly at angle `ang`."""
        tab = rng.random(n)
        x = (ang / math.tau) % 1.0 * n
        i = np.floor(x).astype(int) % n
        f = x - np.floor(x)
        f = f * f * (3.0 - 2.0 * f)
        return tab[i] * (1.0 - f) + tab[(i + 1) % n] * f

    def to_srgb(x):
        return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.maximum(x, 1e-9) ** (1 / 2.4) - 0.055)

    img = np.empty((size, size, 3))
    img[:] = BACK
    cs = EYE["centers"]
    for side, other in (("r", "l"), ("l", "r")):
        cu, cv = cs[side]
        du, dv = u - cu, v - cv
        d = np.hypot(du, dv)
        ang = np.arctan2(dv, du)
        mine = d <= np.hypot(u - cs[other][0], v - cs[other][1])

        # The white: paler round the iris, pinker and darker toward the back, a little uneven.
        back = smooth(0.19, MAX, d)
        blotch = (ring_noise(7, ang + d * 6.0) - 0.5) * (1.0 - back)
        white = WHITE[None, None, :] * (1.0 - back[..., None]) + BACK[None, None, :] * back[..., None]
        white = white * (1.0 + 0.03 * blotch[..., None])

        # Veins: wandering in from the back toward the iris, branching, thinning as they go.
        veins = np.zeros((size, size))
        stack = [(rng.uniform(0, math.tau), MAX * rng.uniform(0.8, 1.05), rng.uniform(0.35, 1.0), 0) for _ in range(46)]
        while stack:
            a, r, strength, depth = stack.pop()
            heading = a + math.pi + rng.uniform(-0.5, 0.5)     # (inward, roughly)
            x, y = cu + r * math.cos(a), cv + r * math.sin(a)
            stop = rng.uniform(R * 1.25, R * 2.1)
            for step in range(400):
                rr = math.hypot(x - cu, y - cv)
                if rr < stop or strength < 0.08:
                    break
                heading += rng.normal(0.0, 0.22)
                # (pulled back toward the iris, so it wanders without turning round)
                want = math.atan2(cv - y, cu - x)
                heading += 0.08 * math.sin(want - heading)
                x += math.cos(heading) * 0.0016
                y += math.sin(heading) * 0.0016
                strength *= 0.994
                if depth < 2 and rng.random() < 0.012:
                    stack.append((math.atan2(y - cv, x - cu), rr, strength * 0.7, depth + 1))
                px_, py_ = x * size, y * size
                w = (0.4 + 0.5 * strength) * size / 1024.0     # (pixels)
                x0, y0 = int(px_) - 3, int(py_) - 3
                if x0 < 0 or y0 < 0 or x0 + 7 > size or y0 + 7 > size:
                    continue
                gy, gx = np.mgrid[y0:y0 + 7, x0:x0 + 7]
                g = strength * np.exp(-((gx + 0.5 - px_) ** 2 + (gy + 0.5 - py_) ** 2) / (2.0 * w * w))
                patch = veins[y0:y0 + 7, x0:x0 + 7]
                np.maximum(patch, g, out=patch)
        veins *= smooth(R * 1.2, R * 2.3, d) * 0.42
        white = white * (1.0 - veins[..., None]) + np.array([0.6, 0.33, 0.31])[None, None, :] * veins[..., None]
        # The soft grey shadow where the white meets the iris.
        white = white * (0.8 + 0.2 * smooth(R, R * 1.3, d))[..., None]

        # The iris, as light and dark (linear, about 0.035 on average: eye.gdshader shows
        # 0.12 as the player's eye color at full strength and nothing darker than a quarter
        # of it; the look was tuned on a picture that sat at that floor).
        rn = d / R
        wave = (ring_noise(9, ang) - 0.5) * 0.12 * rn        # (fibers don't run dead straight)
        fine = ring_noise(260, ang + wave) * 0.55 + ring_noise(120, ang + wave * 1.4) * 0.45
        coarse = ring_noise(46, ang - wave)
        inner = ring_noise(150, ang + 1.0)
        fibers = np.where(rn < 0.43, inner, fine * 0.6 + coarse * 0.4)
        fibers = fibers * smooth(0.28, 0.36, rn) + 0.5 * (1.0 - smooth(0.28, 0.36, rn))
        collar = np.exp(-((rn - (0.43 + 0.05 * (ring_noise(14, ang) - 0.5))) / 0.07) ** 2)
        pits = smooth(0.6, 0.85, ring_noise(30, ang + wave)) * smooth(0.48, 0.6, rn) * (1.0 - smooth(0.62, 0.9, rn))
        lum = 0.022 + 0.04 * fibers ** 1.6 + 0.022 * collar - 0.01 * pits
        lum *= 1.0 - 0.35 * smooth(0.8, 1.0, rn)
        lum = np.clip(lum, 0.008, 0.11)
        lum = lum * smooth(P * 0.9, P * 1.15, d)             # the pupil
        hue = np.array([2.2, 0.75, 0.3])
        hue = hue / hue.dot([0.3, 0.59, 0.11])
        iris = to_srgb(np.clip(lum[..., None] * hue[None, None, :], 0.0, 1.0))

        edge = smooth(R * 0.97, R * 1.05, d)
        eye = iris * (1.0 - edge[..., None]) + white * edge[..., None]
        img[mine] = eye[mine]

    img = np.clip(img, 0.0, 1.0)
    out = os.path.join(PROJECT, *EYE["picture"].split("/"))
    pic = bpy.data.images.new("own_eyes", size, size, alpha=False)
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = img[::-1]     # (Blender's rows run bottom up)
    pic.pixels.foreach_set(rgba.ravel())
    pic.filepath_raw = out
    pic.file_format = "PNG"
    pic.save()
    bpy.data.images.remove(pic)
    print("wrote", out)
    return out
