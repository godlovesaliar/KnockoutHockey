# A posable skater in Blender for working out the stick stance: the game's male body
# (scaled to 1.8 m), the hockey gloves and cuffs fitted to its hands the same way
# SkaterVisual fits them, and a stick that runs from the top glove's grip toward a blade
# handle on the ice.
#
# Run hand_gear.py's build_all() first (the glove meshes come from its HandGear
# collection), then in Blender:
#   exec(open(r"<project>/tools/blender/pose_rig.py").read())
#
# Handles (empties) to drag:
#   IK_TopHand / IK_BottomHand  - where each wrist goes (two-bone IK on the arm)
#   Blade                       - where the blade sits on the ice (the stick aims at it)
#   IK_LeftFoot / IK_RightFoot  - the skates; move the Hips bone down to crouch
# Rotate the hand bones (pose mode) to turn the gloves. Pose the spine, hips and legs as
# usual. read_pose() prints what the game rig needs to match the pose.

import math

import bpy
from mathutils import Matrix, Vector

BODY = r"C:\Users\Booker\Desktop\Knockout Hockey\assets\player\male_character_base_-_rigged.glb"
COLLECTION = "PoseRig"
HEIGHT = 1.8
SHOT = "left"          # left shot: blade on the character's left, right hand on top
GRIP = (0.0, 0.065, -0.05)   # the stick through the glove's fist (game coords), GRIP_UP / GRIP_IN
SHAFT = 1.45           # heel to butt end (m)
LIE = math.radians(48)  # angle between the shaft and the ice when the blade lies flat

# The game's build renames the CMU spine (tools/build_characters.gd CMU_MAP).
CMU_MAP = {"LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2"}

# Game coordinates (Y up, +Z forward for the body, +X = the character's left) to Blender.
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def to_game(v):
    return Vector((v.x, v.z, -v.y))


def to_blender(v):
    return C @ Vector(v)


def _col():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def _link(obj):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    _col().objects.link(obj)


def _bone(arm, name):
    return next(b for b in arm.pose.bones if b.name == name or b.name.startswith(name + "_"))


def _empty(name, loc, size=0.06, shape="SPHERE"):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = shape
    e.empty_display_size = size
    e.location = loc
    _col().objects.link(e)
    return e


def clear():
    col = bpy.data.collections.get(COLLECTION)
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)


def import_body():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BODY)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        _link(o)
    root = next(o for o in new if o.parent is None and o.type == "EMPTY")
    for o in new:
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            o.hide_set(True)   # a stray display sphere in the source file
    bpy.context.view_layer.update()
    body = max((o for o in new if o.type == "MESH"), key=lambda o: len(o.data.polygons))
    root.scale = root.scale * (HEIGHT / body.dimensions.z)
    root.name = "Skater"
    arm = next(o for o in new if o.type == "ARMATURE")
    arm.name = "SkaterArmature"
    body.name = "SkaterBody"
    bpy.context.view_layer.update()
    return arm


def hide_fingers(arm):
    """Folds the body's own fingers away under the gloves, as SkaterRig.hide_fingers does."""
    for side in ("Left", "Right"):
        hand = _bone(arm, side + "Hand")
        for b in hand.children:
            b.scale = (0.001, 0.001, 0.001)


def glove_basis(arm, side):
    """SkaterVisual's glove basis (game coords): fingers along the forearm, palm down in
    the T-pose, thumb forward; the left glove is the right one mirrored."""
    mw = arm.matrix_world
    fore = to_game(mw @ _bone(arm, side + "ForeArm").head)
    hand = to_game(mw @ _bone(arm, side + "Hand").head)
    y = (hand - fore).normalized()
    z = (Vector((0, 0, 1)) - y * y.z).normalized()
    x = y.cross(z)
    cols = (-z, y, x) if side == "Right" else (-z, y, -x)
    gb = Matrix((cols[0], cols[1], cols[2])).transposed()
    return hand + y * 0.01, gb


def place_gloves(arm):
    glove_mesh = bpy.data.objects["Glove"].data
    cuff_mesh = bpy.data.objects["GloveCuff"].data
    out = {}
    for side in ("Left", "Right"):
        at, gb = glove_basis(arm, side)
        m = Matrix.Translation(to_blender(at)) @ (C @ gb @ C.inverted()).to_4x4()
        for kind, mesh, bone in (("Glove", glove_mesh, side + "Hand"), ("Cuff", cuff_mesh, side + "ForeArm")):
            name = side + kind
            old = bpy.data.objects.get(name)
            if old:
                bpy.data.objects.remove(old, do_unlink=True)
            o = bpy.data.objects.new(name, mesh)
            _col().objects.link(o)
            o.parent = arm
            o.parent_type = "BONE"
            o.parent_bone = _bone(arm, bone).name
            bpy.context.view_layer.update()
            o.matrix_world = m
            out[name] = o
        grip = _empty(side + "Grip", Vector((0, 0, 0)), 0.03, "PLAIN_AXES")
        grip.parent = out[side + "Glove"]
        grip.location = to_blender(GRIP)
    return out


def build_stick(top_grip, blade):
    """A stick from the top grip toward the Blade handle: the butt end a little above
    the grip, the shaft SHAFT long, the blade flat at its heel."""
    import bmesh
    for n in ("Stick",):
        old = bpy.data.objects.get(n)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    bm = bmesh.new()
    # Built along -Z from the origin (the grip): butt 0.08 m above, heel SHAFT below that.
    shaft = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    for v in shaft:
        v.co = Vector((v.co.x * 0.03, v.co.y * 0.02, (v.co.z - 0.5) * SHAFT + 0.08))
    # The blade: off the heel, turned up by the lie angle so it lies flat on the ice
    # while the shaft slopes at about that angle (local +Y is kept toward world up).
    blade_v = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    heel = Vector((0, 0, -SHAFT + 0.08))
    rot = Matrix.Rotation(LIE, 3, "X")
    for v in blade_v:
        local = Vector((v.co.x * 0.012, v.co.y * 0.075 + 0.035, (v.co.z + 0.5) * -0.3))
        v.co = heel + rot @ local
    mesh = bpy.data.meshes.new("Stick")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("Stick", mesh)
    _col().objects.link(o)
    mat = bpy.data.materials.get("StickMat") or bpy.data.materials.new("StickMat")
    mat.diffuse_color = (0.05, 0.05, 0.06, 1)
    mesh.materials.append(mat)
    c = o.constraints.new("COPY_LOCATION")
    c.target = top_grip
    t = o.constraints.new("TRACK_TO")
    t.target = blade
    t.track_axis = "TRACK_NEGATIVE_Z"
    t.up_axis = "UP_Y"
    return o


def add_ik(arm, side, target):
    pb = _bone(arm, side + "ForeArm")
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    ik = pb.constraints.new("IK")
    ik.target = target
    ik.chain_count = 2
    ik.use_rotation = False
    # The elbow bends outward and back.
    pole = _empty("Pole_" + side, arm.matrix_world @ _bone(arm, side + "ForeArm").head
                  + Vector((0.4 if side == "Left" else -0.4, 0.4, 0.0)), 0.04, "CUBE")
    ik.pole_target = pole
    ik.pole_angle = 0.0
    return ik


def add_leg_ik(arm, side):
    """Feet stay planted on handles; drag the Hips bone down to crouch."""
    mw = arm.matrix_world
    foot = _empty("IK_" + side + "Foot", mw @ _bone(arm, side + "Foot").head, 0.07, "CUBE")
    pb = _bone(arm, side + "Leg")
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    ik = pb.constraints.new("IK")
    ik.target = foot
    ik.chain_count = 2
    knee = mw @ _bone(arm, side + "Leg").head
    ik.pole_target = _empty("Pole_" + side + "Knee", knee + Vector((0, -0.5, 0)), 0.04, "CUBE")
    ik.pole_angle = -math.pi / 2
    return ik


def build():
    clear()
    arm = import_body()
    hide_fingers(arm)
    gloves = place_gloves(arm)
    top = "Right" if SHOT == "left" else "Left"
    bot = "Left" if top == "Right" else "Right"
    mw = arm.matrix_world
    ik_top = _empty("IK_TopHand", mw @ _bone(arm, top + "Hand").head, 0.08)
    ik_bot = _empty("IK_BottomHand", mw @ _bone(arm, bot + "Hand").head, 0.08)
    for side, t in ((top, ik_top), (bot, ik_bot)):
        add_ik(arm, side, t)
    for side in ("Left", "Right"):
        add_leg_ik(arm, side)
    side_x = 0.38 if SHOT == "left" else -0.38
    blade = _empty("Blade", to_blender((side_x, 0.0, 1.0)), 0.1, "CIRCLE")
    build_stick(bpy.data.objects[top + "Grip"], blade)
    bpy.context.view_layer.objects.active = arm
    return arm


def read_pose():
    """Prints the pose in the game's body frame (meters, +X left, +Y up, +Z forward)."""
    arm = bpy.data.objects["SkaterArmature"]
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    pts = {}
    for n in ("Hips", "Spine1", "Neck", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm",
              "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"):
        pts[n] = to_game(mw @ _bone(arm, n).head)
    for n in ("LeftGrip", "RightGrip"):
        pts[n] = to_game(bpy.data.objects[n].matrix_world.translation)
    pts["Blade"] = to_game(bpy.data.objects["Blade"].matrix_world.translation)
    for k, v in pts.items():
        print("%-13s (% .3f, % .3f, % .3f)" % (k, v.x, v.y, v.z))
    for side in ("Left", "Right"):
        g = bpy.data.objects[side + "Glove"].matrix_world.to_3x3()
        cols = [to_game(g.col[i]).normalized() for i in range(3)]
        print("%s glove: knuckle +X %s  fingers +Y %s  back %s" % (side, tuple(round(c, 2) for c in cols[0]),
              tuple(round(c, 2) for c in cols[1]), tuple(round(c, 2) for c in (cols[2] if side == "Right" else -cols[2]))))
    return pts


# --- Copying a pose from the game -------------------------------------------------

def _rotate_world(arm, pbone, r_world):
    """Turns a pose bone about its head by a world-space rotation."""
    a = arm.matrix_world.to_3x3().normalized()
    r = a.inverted() @ r_world @ a
    m = pbone.matrix.copy()
    loc = m.translation.copy()
    nm = (r @ m.to_3x3()).to_4x4()
    nm.translation = loc
    pbone.matrix = nm
    bpy.context.view_layer.update()


def _best_rotation(src, dst):
    """The rotation taking the vectors in src as close as it can onto dst (Kabsch; a single
    pair gives the shortest swing)."""
    if len(src) == 1:
        return src[0].rotation_difference(dst[0]).to_matrix()
    import numpy as np
    h = sum((np.outer(np.array(s), np.array(d)) for s, d in zip(src, dst)), np.zeros((3, 3)))
    u, _, vt = np.linalg.svd(h)
    d = np.sign(np.linalg.det(vt.T @ u.T))
    r = vt.T @ np.diag([1.0, 1.0, d]) @ u.T
    return Matrix(r.tolist())


def apply_dump(path):
    """Poses the rig from a CharacterViewer `posedump=` file: every joint aimed at its
    place in the game frame, the hands turned to the gloves' angles, the blade and the IK
    handles moved to match (IK stays on, so you can carry on from there)."""
    import json
    data = json.load(open(path))
    arm = bpy.data.objects["SkaterArmature"]
    mw = arm.matrix_world
    s = HEIGHT / data.get("height", HEIGHT)
    bones = data["bones"]
    feet_y = (bones["LeftFoot"][1] + bones["RightFoot"][1]) * 0.5 * s
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        for c in pb.constraints:
            c.mute = True
    hide_fingers(arm)
    bpy.context.view_layer.update()
    rest_feet = sum((mw @ _bone(arm, n).head).z for n in ("LeftFoot", "RightFoot")) * 0.5

    def target(name):
        p = bones[name]
        return to_blender((p[0] * s, p[1] * s - feet_y + rest_feet, p[2] * s))

    def key(pb):
        n = pb.name.rsplit("_", 1)[0] if pb.name.rsplit("_", 1)[-1].isdigit() else pb.name
        return CMU_MAP.get(n, n)

    hips = _bone(arm, "Hips")
    m = hips.matrix.copy()
    m.translation = mw.inverted() @ target("Hips")
    hips.matrix = m
    bpy.context.view_layer.update()
    order = []
    def walk(pb):
        order.append(pb)
        for c in pb.children:
            walk(c)
    walk(next(pb for pb in arm.pose.bones if pb.parent is None))
    for pb in order:
        if key(pb) in ("LeftHand", "RightHand"):
            continue
        kids = [c for c in pb.children if key(c) in bones and (mw @ c.head - mw @ pb.head).length > 1e-4]
        if not kids or key(pb) not in bones:
            continue
        head = mw @ pb.head
        src = [(mw @ c.head - head).normalized() for c in kids]
        dst = [(target(key(c)) - target(key(pb))).normalized() for c in kids]
        _rotate_world(arm, pb, _best_rotation(src, dst))
    # Hands: the glove frame (each glove rides its hand bone).
    for side in ("Left", "Right"):
        g = data["gloves"][side]
        want = Matrix([to_blender(g["x"]), to_blender(g["y"]), to_blender(g["z"])]).transposed()
        have = bpy.data.objects[side + "Glove"].matrix_world.to_3x3()
        have = Matrix([have.col[i].normalized() for i in range(3)]).transposed()
        _rotate_world(arm, _bone(arm, side + "Hand"), (want @ have.inverted()).normalized())
    # Handles where the pose put things, then IK back on.
    top = "Right" if SHOT == "left" else "Left"
    bot = "Left" if top == "Right" else "Right"
    bpy.data.objects["IK_TopHand"].location = mw @ _bone(arm, top + "Hand").head
    bpy.data.objects["IK_BottomHand"].location = mw @ _bone(arm, bot + "Hand").head
    for side in ("Left", "Right"):
        bpy.data.objects["IK_" + side + "Foot"].location = mw @ _bone(arm, side + "Foot").head
    b = data["blade"]
    bpy.data.objects["Blade"].location = to_blender((b[0] * s, 0.0, b[2] * s))
    fit_poles(arm)
    report = []
    for n in ("Head", "LeftHand", "RightHand", "LeftFoot", "LeftLeg", "LeftForeArm"):
        report.append("%s off %.3f m" % (n, ((mw @ _bone(arm, n).head) - target(n)).length))
    print("; ".join(report))
    return arm


def ik_on(on=True):
    arm = bpy.data.objects["SkaterArmature"]
    for pb in arm.pose.bones:
        for c in pb.constraints:
            c.mute = not on
    bpy.context.view_layer.update()


def fit_poles(arm):
    """Moves each elbow and knee pole out from where that joint is now and picks the pole
    angle that keeps it there, then turns IK back on: the pose holds, and dragging the
    handles carries on from it."""
    mw = arm.matrix_world
    specs = [("LeftForeArm", "LeftArm", "LeftHand", "Pole_Left"), ("RightForeArm", "RightArm", "RightHand", "Pole_Right"),
             ("LeftLeg", "LeftUpLeg", "LeftFoot", "Pole_LeftKnee"), ("RightLeg", "RightUpLeg", "RightFoot", "Pole_RightKnee")]
    ik_on(False)
    want = {}
    for mid, root, end, pole in specs:
        e = (mw @ _bone(arm, mid).head).copy()
        out = (e - ((mw @ _bone(arm, root).head) + (mw @ _bone(arm, end).head)) * 0.5).normalized()
        bpy.data.objects[pole].location = e + out * 0.4
        want[mid] = e
    ik_on(True)
    for mid, root, end, pole in specs:
        c = _bone(arm, mid).constraints[0]
        best = None
        for deg in range(-180, 180, 5):
            c.pole_angle = math.radians(deg)
            bpy.context.view_layer.update()
            d = ((mw @ _bone(arm, mid).head) - want[mid]).length
            if best is None or d < best[1]:
                best = (deg, d)
        c.pole_angle = math.radians(best[0])
    bpy.context.view_layer.update()
