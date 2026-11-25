# Builds the outdoor rink's woods: assets/trees/trees.glb and the textures beside it.
#
# The bare hardwoods are grown with the Easy Tree extension (Jacob Johnston, GPL-3.0; its
# node groups and CC0 ambientCG bark come from the extension's assets.blend): its tree
# skeleton and bark mesher, leaves off, cut down to game weight. Easy Tree only grows
# forked trees, so the evergreens are built here: a trunk with whorls of drooping bough
# cards. The bough texture, and the flat cut-outs the game uses for far trees, are
# rendered from these same trees.
#
# Run in Blender 5.2 with Easy Tree installed (Preferences > Get Extensions), either
#   blender -b -P tools/blender/trees.py
# or in a running Blender:
#   ns = {"__name__": "trees", "__file__": r"<this file>"}; exec(open(ns["__file__"]).read(), ns); ns["main"]()
# It works in its own scene ("TreeLab") and leaves the others alone.
#
# Out (Y-up, metres, each tree's base at the origin, 1 m tall: the game scales them):
#   trees.glb     objects <kind>: surfaces "KH Bark" (limbs, trunks) and "Boughs" (cards)
#   bough.png     a snowy spruce bough (alpha), for the evergreens' cards
#   cards.png     every kind seen from the side (alpha), one cell each, and
#   cards.json    each kind's cell in it and its width / height
#   treeline.png  a long strip of woods (alpha) for the far ring
import bpy, bmesh, math, os, json, random
from mathutils import Vector, Matrix, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "trees")
SCENE = "TreeLab"
GEN = "Simple Tree Generator"

# Easy Tree's modifier inputs (Simple Tree Generator).
S = dict(n="Socket_25", trunk="Socket_40", treetop="Socket_26", levels="Socket_27", blen="Socket_28",
         angle="Socket_29", jitter="Socket_30", gravity="Socket_31", thick="Socket_32", bark="Socket_8",
         seed="Socket_16", leaves="Socket_19")


def easy_tree_blend():
    import addon_utils
    for m in addon_utils.modules():
        if m.__name__.endswith(".easy_tree") or m.__name__ == "easy_tree":
            return os.path.join(os.path.dirname(m.__file__), "assets", "assets.blend")
    raise RuntimeError("Easy Tree isn't installed (Preferences > Get Extensions > Easy Tree)")


def drop(name):
    """Removes the object `name` and its mesh, if nothing else uses it."""
    ob = bpy.data.objects.get(name)
    if ob is None:
        return
    data = ob.data
    bpy.data.objects.remove(ob)
    if isinstance(data, bpy.types.Mesh) and data.users == 0:
        bpy.data.meshes.remove(data)


def setup():
    """The work scene, Easy Tree's node groups, and its mesher turned down to game weight."""
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    if bpy.context.window:
        bpy.context.window.scene = sc
    for o in list(sc.objects):
        drop(o.name)
    if GEN not in bpy.data.node_groups:
        with bpy.data.libraries.load(easy_tree_blend(), link=False) as (src, dst):
            dst.node_groups = [GEN]
    mesher = bpy.data.node_groups["Tree to Mesh"]
    # Five-sided tubes and no subdivision: the limbs are a tenth of the stock weight.
    next(n for n in mesher.nodes if n.bl_idname == "GeometryNodeCurvePrimitiveCircle").inputs["Resolution"].default_value = 5
    next(n for n in mesher.nodes if n.bl_idname == "GeometryNodeSubdivisionSurface").inputs["Level"].default_value = 0
    os.makedirs(OUT, exist_ok=True)
    return sc


def scene():
    return bpy.data.scenes[SCENE]


def grow(name, **kw):
    """An Easy Tree object (its generator as a modifier), bare unless told otherwise."""
    drop(name)
    ob = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    scene().collection.objects.link(ob)
    mod = ob.modifiers.new("Tree Generator", 'NODES')
    mod.node_group = bpy.data.node_groups[GEN]
    kw.setdefault("leaves", False)
    for k, v in kw.items():
        getattr(mod.properties.inputs, S[k]).value = v
    return ob


def baked(ob):
    """`ob`'s evaluated mesh as a new mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    return bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)


# --- Rendering cut-outs ------------------------------------------------------------------

def render_setup(sc):
    """Flat, even light and a clear background: the pictures are colour maps, lit in game."""
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    w = bpy.data.worlds.get("TreeLabWorld") or bpy.data.worlds.new("TreeLabWorld")
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 0.85
    sc.world = w
    cam = bpy.data.objects.get("TreeLabCam")
    if cam is None:
        cam = bpy.data.objects.new("TreeLabCam", bpy.data.cameras.new("TreeLabCam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.clip_end = 2000.0
    sc.camera = cam
    sun = bpy.data.objects.get("TreeLabSun")
    if sun is None:
        sun = bpy.data.objects.new("TreeLabSun", bpy.data.lights.new("TreeLabSun", 'SUN'))
    if sun.name not in sc.collection.objects:
        sc.collection.objects.link(sun)
    sun.data.energy = 1.6
    sun.rotation_euler = Euler((math.radians(35), 0, math.radians(20)))
    return cam


def shoot(sc, path, center, width, height, px_w, px_h, view="front", only=None, sun=(58, 25)):
    """An orthographic picture `width` x `height` metres about `center`, from the front (-Y) or above."""
    cam = render_setup(sc)
    if view == "front":
        cam.location = Vector(center) + Vector((0, -500, 0))
        cam.rotation_euler = Euler((math.radians(90), 0, 0))
    else:
        cam.location = Vector(center) + Vector((0, 0, 500))
        cam.rotation_euler = Euler((0, 0, 0))
    cam.data.ortho_scale = max(width, height)
    # The sun: `sun[0]` degrees over from straight down toward the picture, `sun[1]` round.
    bpy.data.objects["TreeLabSun"].rotation_euler = Euler((math.radians(sun[0]), 0, math.radians(sun[1])))
    sc.render.resolution_x = px_w
    sc.render.resolution_y = px_h
    sc.render.resolution_percentage = 100
    hidden = []
    if only is not None:
        for o in sc.objects:
            if o.type in ('MESH', 'CURVE') and o not in only and not o.hide_render:
                o.hide_render = True
                hidden.append(o)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    for o in hidden:
        o.hide_render = False


def bounds(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    pts = [ev.matrix_world @ Vector(c) for c in ev.bound_box]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def cutout_material(name, png):
    """A picture with its alpha, seen from both sides."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None) or nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(png, check_existing=True)
    img.reload()
    tex.image = img
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 1.0
    m.use_backface_culling = False
    return m


def card(name, mat, width=1.0, length=1.0, bend=0.0, cuts=1):
    """A card standing on its origin: `width` along X, `length` up Z, the picture's bottom at
    the origin. `bend` droops its far end toward -Y (for boughs), in `cuts` steps."""
    drop(name)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rows = []
    for i in range(cuts + 1):
        f = i / cuts
        y = -bend * f * f
        rows.append((bm.verts.new((-width / 2, y, length * f)), bm.verts.new((width / 2, y, length * f)), f))
    for a, b in zip(rows, rows[1:]):
        face = bm.faces.new((a[0], a[1], b[1], b[0]))
        for loop, st in zip(face.loops, ((0, a[2]), (1, a[2]), (1, b[2]), (0, b[2]))):
            loop[uv].uv = st
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    scene().collection.objects.link(ob)
    return ob


BARK_TINT = (0.42, 0.38, 0.36)      # Easy Tree's bark is a warm tan: winter wood is darker and greyer


def snowy_bark():
    """Easy Tree's bark, darkened, with snow lying on whatever faces up ("KH Bark"). The
    game does the same in its shader; this one is for the pictures rendered here."""
    m = bpy.data.materials.get("KH Bark")
    if m:
        return m
    m = bpy.data.materials["Bark"].copy()
    m.name = "KH Bark"
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    base = b.inputs["Base Color"]
    src = base.links[0].from_socket if base.links else None
    tint = nt.nodes.new("ShaderNodeMix")
    tint.data_type = 'RGBA'
    tint.blend_type = 'MULTIPLY'
    tint.inputs["Factor"].default_value = 1.0
    if src:
        nt.links.new(src, tint.inputs["A"])
    tint.inputs["B"].default_value = (*BARK_TINT, 1.0)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.45
    ramp.inputs["From Max"].default_value = 0.85
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(tint.outputs["Result"], mix.inputs["A"])
    mix.inputs["B"].default_value = (0.9, 0.92, 0.96, 1.0)
    nt.links.new(mix.outputs["Result"], base)
    return m


def bark_texture():
    """bark.jpg: Easy Tree's bark colour (ambientCG Bark001, CC0) at game size."""
    src = next(n.image for n in bpy.data.materials["Bark"].node_tree.nodes
               if n.type == "TEX_IMAGE" and n.image and "Color" in n.image.name)
    img = src.copy()
    img.scale(512, 512)
    img.filepath_raw = os.path.join(OUT, "bark.jpg")
    img.file_format = 'JPEG'
    img.save()
    bpy.data.images.remove(img)


def finish(name, me, real_height=None):
    """`me` as object `name`, scaled to 1 m tall with its base at the origin."""
    drop(name)
    zs = [v.co.z for v in me.vertices]
    h = real_height or max(zs)
    me.transform(Matrix.Scale(1.0 / h, 4))
    for a in list(me.attributes):
        if a.name in ("tip", "startHeight", "forward", "basePos", "height"):
            me.attributes.remove(a)
    me.name = name
    ob = bpy.data.objects.new(name, me)
    ob["real_height"] = h
    scene().collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


# --- Hardwoods (Easy Tree) ---------------------------------------------------------------

# Per kind: Easy Tree's shape inputs, and the triangles its limbs are cut down to (stock,
# they run to tens of thousands).
HARDWOODS = {
    "hw_broad": dict(shape=dict(trunk=2, treetop=2, levels=6, blen=8, angle=0.488, thick=2.9, seed=14), tris=6000),
    "hw_tall": dict(shape=dict(trunk=6, treetop=2, levels=6, blen=7, angle=0.6, thick=2.8, seed=12), tris=5600),
    "hw_slim": dict(shape=dict(trunk=3, treetop=5, levels=5, blen=6, angle=0.42, thick=1.8, seed=13), tris=4200),
    "hw_gnarled": dict(shape=dict(n="Three Branches", trunk=1, levels=4, blen=10, angle=0.41, jitter=0.25,
                                  gravity=1.7, thick=2.0, seed=15), tris=5200),
}


def hardwood(name, spec):
    limbs = grow(name + "_limbs", bark=snowy_bark(), **spec["shape"])
    raw = baked(limbs)
    count = sum(len(p.vertices) - 2 for p in raw.polygons)
    bpy.data.meshes.remove(raw)
    limbs.modifiers.new("dec", 'DECIMATE').ratio = min(1.0, spec["tris"] / count)
    me = baked(limbs)
    drop(limbs.name)
    return finish(name, me)


# --- Evergreens --------------------------------------------------------------------------

def flat_material(name, attr="Col", rough=1.0):
    """Colour straight from a corner attribute."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    a = next((n for n in nt.nodes if n.type == "ATTRIBUTE"), None) or nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = attr
    nt.links.new(a.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    return m


BOUGH_W = 0.75          # the bough picture's width over its length


def bough_texture(snow=0.58, seed=7):
    """bough.png: a spruce bough seen from above, its stem at the bottom: a stem, side twigs
    and their twigs, needles down every one, and snow lying along the middle of each."""
    sc = scene()
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")

    def strip(p0, p1, w0, w1, y, color):
        d = (p1 - p0).normalized()
        n = Vector((d.z, 0.0, -d.x))
        vs = [bm.verts.new((p.x + s * n.x * w, y, p.z + s * n.z * w)) for p, w, s in
              ((p0, w0, -1), (p0, w0, 1), (p1, w1, 1), (p1, w1, -1))]
        f = bm.faces.new(vs)
        for loop in f.loops:
            loop[col] = (*color, 1.0)

    def rot(d, ang):
        c, s = math.cos(ang), math.sin(ang)
        return Vector((d.x * c + d.z * s, 0.0, -d.x * s + d.z * c))

    twigs = []      # (start, direction, length, width)
    blobs = []      # (center, radius)

    def twig(p, d, length, width, level):
        twigs.append((p, d, length, width))
        # Snow on the inner two thirds, heavier on the bigger twigs.
        s = 0.0
        while s < length * 0.62:
            r = (0.03 if level == 0 else 0.02 if level == 1 else 0.011) * rng.uniform(0.75, 1.3) * snow
            if rng.random() < 0.85 and r > 0.004:
                blobs.append((p + d * s + Vector((rng.uniform(-r, r) * 0.4, 0, 0)), r))
            s += max(r, 0.004) * 0.9
        if level >= 2 or length < 0.07:
            return
        step = 0.034 if level == 0 else 0.045
        s = 0.07 if level == 0 else step
        side = 1
        while s < length * 0.96:
            f = s / length
            if level == 0:
                sub = 0.4 * (1.0 - f) ** 0.85 * min(1.0, f / 0.12 + 0.45)
                ang = math.radians(58 - 20 * f)
            else:
                sub = length * 0.42 * (1.0 - f)
                ang = math.radians(42)
            sub *= rng.uniform(0.8, 1.15)
            twig(p + d * s, rot(d, side * (ang + math.radians(rng.uniform(-7, 7)))), sub, width * 0.6, level + 1)
            side = -side
            s += step * rng.uniform(0.8, 1.2)

    twig(Vector((0, 0, 0)), Vector((0, 0, 1)), 1.0, 0.011, 0)
    for p, d, length, width in twigs:
        strip(p, p + d * length, width, width * 0.3, 0.0, (0.1, 0.065, 0.04))
        s = 0.0
        while s < length:
            for side in (-1, 1):
                g = rng.uniform(0.6, 1.5)
                green = (0.028 * g, 0.074 * g, 0.03 * g * rng.uniform(0.8, 1.5))
                nd = rot(d, side * math.radians(rng.uniform(40, 75)))
                a = p + d * (s + rng.uniform(0, 0.004))
                nl = rng.uniform(0.02, 0.031)
                strip(a, a + nd * nl, 0.0026, 0.0008, rng.uniform(0.001, 0.004), green)
            s += 0.0045
        # Needles off the tip.
        for k in range(5):
            g = rng.uniform(0.7, 1.4)
            a = p + d * length
            strip(a, a + rot(d, math.radians(rng.uniform(-35, 35))) * rng.uniform(0.02, 0.03), 0.0026, 0.0008, 0.002,
                  (0.028 * g, 0.074 * g, 0.036 * g))
    me = bpy.data.meshes.new("BoughSrc")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(flat_material("KH Needles"))
    ob = bpy.data.objects.new("BoughSrc", me)
    sc.collection.objects.link(ob)
    # The snow: soft lumps, toward the camera (-Y).
    bm = bmesh.new()
    for c, r in blobs:
        mat = Matrix.Translation((c.x, -0.004 - r * 0.35, c.z)) @ Matrix.Diagonal((r, r * 0.45, r * rng.uniform(1.0, 1.5), 1.0))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=mat)
    sme = bpy.data.meshes.new("BoughSnow")
    bm.to_mesh(sme)
    bm.free()
    for poly in sme.polygons:
        poly.use_smooth = True
    sm = bpy.data.materials.get("KH Snow") or bpy.data.materials.new("KH Snow")
    sm.use_nodes = True
    b = next(n for n in sm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.62, 0.645, 0.69, 1.0)
    b.inputs["Roughness"].default_value = 1.0
    sme.materials.append(sm)
    sob = bpy.data.objects.new("BoughSnow", sme)
    sc.collection.objects.link(sob)
    path = os.path.join(OUT, "bough.png")
    shoot(sc, path, (0, 0, 0.5), BOUGH_W, 1.0, int(768 * BOUGH_W), 768, only=[ob, sob], sun=(78, 18))
    drop(ob.name)
    drop(sob.name)
    return path


# Per kind: height (m), where the boughs start (share of the height), the lowest boughs'
# reach (m), tiers of boughs, boughs in the lowest tier, and how far the low ones sag (deg).
EVERGREENS = {
    "ev_spruce": dict(height=15.0, base=0.1, reach=2.8, tiers=21, per=9, sag=24, seed=3),
    "ev_fir": dict(height=11.0, base=0.07, reach=3.0, tiers=16, per=9, sag=14, seed=5),
    "ev_narrow": dict(height=13.0, base=0.16, reach=1.8, tiers=19, per=7, sag=32, seed=9),
}


def evergreen(name, spec, bough_mat):
    rng = random.Random(spec["seed"])
    H = spec["height"]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    # The trunk: a tapered six-sided tube.
    rings = []
    n_rings = 7
    for i in range(n_rings + 1):
        f = i / n_rings
        r = (0.05 + H * 0.013) * (1.0 - f) ** 0.8 + 0.012
        rings.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, H * 0.99 * f))
                      for a in (math.tau * k / 6 for k in range(6))])
    for i in range(n_rings):
        for k in range(6):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % 6], rings[i + 1][(k + 1) % 6], rings[i + 1][k]))
            for loop, st in zip(f.loops, ((k / 6, i), (k / 6 + 1 / 6, i), (k / 6 + 1 / 6, i + 1), (k / 6, i + 1))):
                loop[uv].uv = (st[0], st[1] * H / n_rings * 0.25)
            f.material_index = 0

    def bough(origin, out, pitch, length, width, sag, hang=True):
        """A bough card from `origin` along `out` (flat, unit), starting `pitch` above level
        and sagging `sag` metres by its tip; `hang` adds a fin of twigs hanging under it."""
        side = Vector((-out.y, out.x, 0.0))
        cuts = 3
        path = []
        for i in range(cuts + 1):
            f = i / cuts
            path.append(origin + out * (length * f * math.cos(pitch))
                        + Vector((0, 0, length * f * math.sin(pitch) - sag * f * f)))
        rows = [(bm.verts.new(p - side * width / 2), bm.verts.new(p + side * width / 2)) for p in path]
        for i in range(cuts):
            f = bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
            for loop, st in zip(f.loops, ((0, i / cuts), (1, i / cuts), (1, (i + 1) / cuts), (0, (i + 1) / cuts))):
                loop[uv].uv = st
            f.material_index = 1
        if hang:
            drop = width * 0.42
            rows = []
            for i, p in enumerate(path):
                d = (path[min(i + 1, cuts)] - path[max(i - 1, 0)]).normalized()
                down = d.cross(side).normalized()
                if down.z > 0:
                    down = -down
                rows.append((bm.verts.new(p + down * drop * 0.1), bm.verts.new(p + down * drop)))
            for i in range(cuts):
                f = bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
                for loop, st in zip(f.loops, ((0.5, i / cuts), (1, i / cuts), (1, (i + 1) / cuts), (0.5, (i + 1) / cuts))):
                    loop[uv].uv = st
                f.material_index = 1

    tiers = spec["tiers"]
    z0 = H * spec["base"]
    for k in range(tiers):
        t = k / (tiers - 1)
        z = z0 + (H * 0.95 - z0) * t ** 0.92
        reach = spec["reach"] * (1.0 - t) ** 0.8 + 0.35
        n = max(3, round(spec["per"] * (1.0 - 0.6 * t)))
        pitch = math.radians(-spec["sag"] * 0.35 + (38 + spec["sag"] * 0.35) * t ** 1.3)
        for j in range(n):
            yaw = math.tau * (j + rng.uniform(-0.25, 0.25) + k * 0.41) / n
            length = reach * rng.uniform(0.82, 1.12)
            bough(Vector((0, 0, z + rng.uniform(-0.12, 0.12))), Vector((math.cos(yaw), math.sin(yaw), 0)),
                  pitch + math.radians(rng.uniform(-7, 7)), length, min(length * BOUGH_W, 2.2),
                  length * math.sin(math.radians(spec["sag"])) * (1.0 - 0.6 * t), hang=t < 0.8)
        # Shorter boughs between those, a little higher, to fill in round the trunk.
        if t < 0.85:
            for j in range(max(3, n // 2)):
                yaw = math.tau * (j + 0.5 + rng.uniform(-0.2, 0.2) + k * 0.41) / max(3, n // 2)
                length = reach * rng.uniform(0.5, 0.65)
                bough(Vector((0, 0, z + rng.uniform(0.15, 0.4))), Vector((math.cos(yaw), math.sin(yaw), 0)),
                      pitch + math.radians(rng.uniform(8, 20)), length, length * BOUGH_W,
                      length * math.sin(math.radians(spec["sag"])) * 0.5, hang=False)
    # The leader: two boughs straight up, crossed.
    top = H * 0.1
    for yaw in (0.4, 0.4 + math.pi / 2):
        bough(Vector((0, 0, H - top)), Vector((math.cos(yaw), math.sin(yaw), 0)), math.radians(89.9), top, top * 0.4, 0.0, hang=False)
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index == 0])
    bm.to_mesh(me)
    bm.free()
    me.materials.append(snowy_bark())
    me.materials.append(bough_mat)
    ob = finish(name, me)
    # The cards stay flat-shaded; the trunk is smooth.
    for p in ob.data.polygons:
        p.use_smooth = p.material_index == 0
    return ob


# --- The far trees' cut-outs -------------------------------------------------------------

CELL = 512              # pixels a side, each kind's cell in cards.png
COLS = 4

SHRUB = dict(shape=dict(n="Three Branches", trunk=1, treetop=1, levels=5, blen=4, angle=0.75, jitter=0.3,
                        gravity=0.4, thick=1.3, seed=21), tris=20000)


SHRUB_SUNK = 0.2        # of its height


def cut_outs(kinds):
    """cards.png: every kind seen from the side, a cell each. Returns per kind the card
    objects (`<kind>_card`: two crossed quads, 1 m tall trees on them, mapped to the cell)."""
    sc = scene()
    rows = math.ceil(len(kinds) / COLS)
    w, h = CELL * COLS, CELL * rows
    import numpy as np
    sheet = np.zeros((h, w, 4), dtype=np.float32)
    info = {}
    tmp = os.path.join(OUT, "_cell.png")
    for i, ob in enumerate(kinds):
        ob.location = (0, 0, 0)
        ob.scale = (1, 1, 1)
        lo, hi = bounds(ob)
        size = max(hi.z, 2 * max(-lo.x, hi.x, -lo.y, hi.y)) * 1.04
        shoot(sc, tmp, (0, 0, size / 2), size, size, CELL, CELL, only=[ob])
        img = bpy.data.images.load(tmp)
        px = np.empty(CELL * CELL * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        bpy.data.images.remove(img)
        cx, cy = i % COLS, i // COLS
        y0 = h - (cy + 1) * CELL        # image rows run bottom-up
        sheet[y0:y0 + CELL, cx * CELL:(cx + 1) * CELL] = px.reshape(CELL, CELL, 4)
        info[ob.name] = (size, cx / COLS, 1.0 - (cy + 1) / rows, (cx + 1) / COLS, 1.0 - cy / rows)
    os.remove(tmp)
    out = bpy.data.images.new("cards", w, h, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(OUT, "cards.png")
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    mat = cutout_material("Cards", os.path.join(OUT, "cards.png"))
    cards = []
    for name, (size, u0, v0, u1, v1) in info.items():
        cname = name + "_card"
        drop(cname)
        me = bpy.data.meshes.new(cname)
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        for ax in (Vector((1, 0, 0)), Vector((0, 1, 0))):
            a, b = -ax * size / 2, ax * size / 2
            up = Vector((0, 0, size))
            f = bm.faces.new([bm.verts.new(p) for p in (a, b, b + up, a + up)])
            for loop, st in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                loop[uv].uv = st
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        c = bpy.data.objects.new(cname, me)
        sc.collection.objects.link(c)
        cards.append(c)
    return cards


TREELINE = (128.0, 32.0)    # metres of woods in the strip, and its height


def treeline(kinds):
    """treeline.png: a deep stand of the same trees, and the strip it goes on (`treeline`:
    one quad, 1 m tall, facing -Y in Blender)."""
    sc = scene()
    rng = random.Random(44)
    W, Hh = TREELINE
    stand = []
    ever = [o for o in kinds if o.name.startswith("ev_")]
    hard = [o for o in kinds if o.name.startswith("hw_")]
    for row, (y, count) in enumerate(((0.0, 30), (7.0, 34), (14.0, 38), (22.0, 40))):
        for i in range(count):
            src = rng.choice(ever) if rng.random() < 0.6 else rng.choice(hard)
            o = src.copy()
            sc.collection.objects.link(o)
            height = rng.uniform(15.0, 27.0) if src in ever else rng.uniform(13.0, 21.0)
            o.scale = (height,) * 3
            o.location = ((i + rng.uniform(0.1, 0.9)) / count * (W + 12.0) - (W + 12.0) / 2, y, 0)
            o.rotation_euler = Euler((0, 0, rng.uniform(0, math.tau)))
            stand.append(o)
    shoot(sc, os.path.join(OUT, "treeline.png"), (0, 0, Hh / 2), W, Hh, 2048, int(2048 * Hh / W), only=stand)
    for o in stand:
        drop(o.name)
    mat = cutout_material("Treeline", os.path.join(OUT, "treeline.png"))
    old = bpy.data.objects.get("treeline")
    if old:
        drop(old.name)
    strip = card("treeline", mat, width=W / Hh, length=1.0)
    return strip


def export(objects):
    sc = scene()
    for o in sc.objects:
        o.select_set(False)
    for o in objects:
        o.location = (0, 0, 0)
        o.scale = (1, 1, 1)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    # No pictures in the file: the game puts its own materials on by name.
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "trees.glb"), use_selection=True, use_active_scene=True,
                              export_image_format='NONE', export_apply=True, export_extras=False,
                              export_animations=False)


def main(lay_out=True):
    sc = setup()
    render_setup(sc)
    bark_texture()
    bough_mat = cutout_material("Boughs", bough_texture())
    kinds = [hardwood(name, spec) for name, spec in HARDWOODS.items()]
    kinds += [evergreen(name, spec, bough_mat) for name, spec in EVERGREENS.items()]
    shrub = hardwood("shrub", SHRUB)
    # A shrub has no trunk to speak of: sink it to its first fork.
    shrub.data.transform(Matrix.Scale(1.0 / (1.0 - SHRUB_SUNK), 4) @ Matrix.Translation((0, 0, -SHRUB_SUNK)))
    cards = cut_outs(kinds + [shrub])
    strip = treeline(kinds)
    drop(shrub.name)
    export(kinds + cards + [strip])
    if lay_out:
        # Left life-size in a row to look at.
        x = 0.0
        for o in kinds:
            o.scale = (o["real_height"],) * 3
            o.location = (x, 0, 0)
            x += 14.0
        for i, c in enumerate(cards):
            c.location = (i * 2.0, -8.0, 0)
        strip.location = (0, -14.0, 0)
    print("trees:", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in kinds})


if __name__ == "__main__":
    main(lay_out=False)
