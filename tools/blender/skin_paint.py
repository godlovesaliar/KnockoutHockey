# Paints the skin pictures of our own bodies (the ones mpfb_body.py makes):
#
#     blender -b -P tools/blender/skin_paint.py -- male female
#
# writes assets/player/mpfb_<body>_skin.png, in the body's own texture layout. Run it
# headless: it empties the open file. Then re-import and rebuild the bodies
# (build_characters.gd -- body=male / female: the game keeps the picture's average).
#
# Nothing here is a photograph or anyone else's painting. The picture is built from the
# body itself:
#   * the body's shape, baked into the texture layout (where each point of the skin is, which
#     way it faces, how hemmed in it is by the skin around it, how sharply it folds). That
#     gives the soft shade in the hollows (eye sockets, round the nostrils, under the lip and
#     the chin, inside the ears, the armpits) and the creases.
#   * the colors of a face, laid on by place: the paler forehead, the red of the cheeks, nose,
#     ears and chin, the darker rosier skin round the eyes (which is what the eyelids the game
#     draws are colored like), the lips, and for men the shadow of a shaved beard.
#   * the grain of skin: blotches a few centimeters across, mottling, pores. All of it is a
#     function of the place on the body, not of the picture, so nothing shows at the seams.
#   * MPFB's own masks for the parts with a hard outline (lips, ears, nails, the inside of
#     the mouth), which come with the body and share its texture layout.
#
# The game does not show the picture's colors: skin.gdshader divides the picture by its own
# average and multiplies by the player's skin tone. So what counts is every part's color
# *relative to the average*; BODIES' "gain" sets how the plain skin of the face compares to
# it (the earlier bodies' faces were a good deal paler than their pictures' average, and the
# rosters' skin tones were chosen on those).

import math
import os
import sys

import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

BODIES = {
    "male": dict(
        gain=(1.12, 1.16, 1.16),       # plain face skin against the picture's average
        blush=0.7,                     # red of the cheeks, nose, ears, chin
        lips=((0.88, 0.63, 0.62), 0.8),  # color of the lips against the skin, and how much of it
        stubble=1.0,                   # the shadow of a shaved beard
        shade=1.0,                     # shade in the hollows
        grain=1.0,
    ),
    "female": dict(
        gain=(1.17, 1.22, 1.24),
        blush=1.1,
        lips=((0.9, 0.55, 0.57), 0.9),
        stubble=0.0,
        shade=0.85,
        grain=0.8,
    ),
}

BASE = (0.80, 0.63, 0.54)              # the picture's average (sRGB); the game divides it out


def to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(x):
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.maximum(x, 1e-9) ** (1 / 2.4) - 0.055)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(a, sigma, weight=None):
    """Gaussian blur of a picture; with `weight`, only over the pixels it marks."""
    if weight is not None:
        return blur(a * weight, sigma) / np.maximum(blur(weight, sigma), 1e-6)
    r = max(1, int(sigma * 2.5))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        out = np.zeros_like(a)
        for i, w in enumerate(k):
            out += w * np.roll(a, i - r, axis=axis)
        a = out
    return a


def vnoise(p, seed):
    """Smooth noise over space, 0..1: random values on a grid one unit apart."""
    p = p + 1000.0
    i = np.floor(p)
    f = p - i
    i = i.astype(np.uint64)
    f = f * f * (3.0 - 2.0 * f)

    def h(dx, dy, dz):
        n = ((i[:, 0] + np.uint64(dx)) * np.uint64(374761393) + (i[:, 1] + np.uint64(dy)) * np.uint64(668265263)
             + (i[:, 2] + np.uint64(dz)) * np.uint64(2147483647) + np.uint64(seed * 7919 + 13))
        n = (n ^ (n >> np.uint64(13))) * np.uint64(1274126177)
        n = n ^ (n >> np.uint64(16))
        return (n & np.uint64(0xFFFF)).astype(np.float64) / 65535.0

    x0 = h(0, 0, 0) * (1 - f[:, 0]) + h(1, 0, 0) * f[:, 0]
    x1 = h(0, 1, 0) * (1 - f[:, 0]) + h(1, 1, 0) * f[:, 0]
    x2 = h(0, 0, 1) * (1 - f[:, 0]) + h(1, 0, 1) * f[:, 0]
    x3 = h(0, 1, 1) * (1 - f[:, 0]) + h(1, 1, 1) * f[:, 0]
    y0 = x0 * (1 - f[:, 1]) + x1 * f[:, 1]
    y1 = x2 * (1 - f[:, 1]) + x3 * f[:, 1]
    return y0 * (1 - f[:, 2]) + y1 * f[:, 2]


def fbm(p, per_m, octaves, seed):
    """Layered noise, -1..1; the coarsest layer has `per_m` cells to the meter."""
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * (vnoise(p * (per_m * 2 ** o), seed + o * 31) - 0.5)
        norm += amp * 0.5
        amp *= 0.5
    return total / norm


# --- Blender side: the body, and its shape baked into the texture layout -----------------

def load_body(body):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT, "assets", "player", "mpfb_%s.glb" % body))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    skin = max(meshes, key=lambda o: len(o.data.vertices))
    eyes = next(o for o in meshes if o is not skin and "eyes" in o.name.lower())
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    return skin, eyes, rig


def joint(rig, name):
    for b in rig.data.bones:
        if b.name.split(":")[-1] == name:
            return np.array(rig.matrix_world @ b.head_local)
    raise KeyError(name)


def bake(ob, size, build, samples):
    """Bakes what `build(nodes, links)` returns (a color socket) over the skin, unlit."""
    sc = bpy.context.scene
    mat = bpy.data.materials.new("bake")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    nt.links.new(build(nt.nodes, nt.links), em.inputs[0])
    img = bpy.data.images.new("bake", size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 16
    bpy.ops.object.bake(type="EMIT")
    px = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    bpy.data.materials.remove(mat)
    return px.reshape(size, size, 4)[:, :, :3].astype(np.float64)


def _place(nodes, links):
    geo = nodes.new("ShaderNodeNewGeometry")
    add = nodes.new("ShaderNodeVectorMath")
    add.operation = "ADD"
    add.inputs[1].default_value = (4.0, 4.0, 4.0)      # (kept above zero: light can't be negative)
    links.new(geo.outputs["Position"], add.inputs[0])
    return add.outputs[0]


def _facing(nodes, links):
    geo = nodes.new("ShaderNodeNewGeometry")
    mul = nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY_ADD"
    mul.inputs[1].default_value = (0.5, 0.5, 0.5)
    mul.inputs[2].default_value = (0.5, 0.5, 0.5)
    links.new(geo.outputs["Normal"], mul.inputs[0])
    return mul.outputs[0]


def _hollows(nodes, links):
    """Red: how open the skin is to the air within 9 cm; green: within 1.2 cm (creases);
    blue: how sharply the surface folds there (above 0.5: a ridge, below: a groove)."""
    geo = nodes.new("ShaderNodeNewGeometry")
    comb = nodes.new("ShaderNodeCombineColor")
    for k, dist in enumerate((0.09, 0.012)):
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 8
        ao.inputs["Distance"].default_value = dist
        links.new(ao.outputs["AO"], comb.inputs[k])
    links.new(geo.outputs["Pointiness"], comb.inputs[2])
    return comb.outputs[0]


def mpfb_mask(name, size):
    try:
        base = os.path.dirname(__import__("bl_ext.blender_org.mpfb", fromlist=["x"]).__file__)
    except Exception:
        base = os.path.join(bpy.utils.user_resource("EXTENSIONS"), "blender_org", "mpfb")
    img = bpy.data.images.load(os.path.join(base, "data", "textures", "mpfb_%s.jpg" % name))
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    m = px.reshape(h, w, 4)[:, :, 0].astype(np.float64)
    if (h, w) != (size, size):
        m = m[np.arange(size) * h // size][:, np.arange(size) * w // size]
    return m


# --- the painting -------------------------------------------------------------------------

def paint(body, size=2048, debug=None, cache=None):
    spec = BODIES[body]
    skin, eyes, rig = load_body(body)
    kept = os.path.join(cache, "skin_bake_%s_%d.npz" % (body, size)) if cache else None
    if kept and os.path.exists(kept):            # (the bakes of an earlier run: for trying colors)
        place, facing, hollows = (np.load(kept)[k].astype(np.float64) for k in ("place", "facing", "hollows"))
    else:
        place = bake(skin, size, _place, 1) - 4.0
        facing = bake(skin, size, _facing, 1) * 2.0 - 1.0
        hollows = bake(skin, size, _hollows, 8)
        if kept:
            np.savez(kept, place=place.astype(np.float32), facing=facing.astype(np.float32), hollows=hollows.astype(np.float32))
    cov = place.sum(axis=2) > -11.0              # (pixels the bake reached, margin included)
    print("  baked: %d%% of the picture is skin" % round(100.0 * cov.mean()))
    wgt = cov.astype(np.float64)
    open_wide = np.clip(blur(hollows[:, :, 0], 3.0, wgt), 0.0, 1.0)
    open_tight = np.clip(blur(hollows[:, :, 1], 1.2, wgt), 0.0, 1.0)
    fold = blur(hollows[:, :, 2], 1.5, wgt)
    masks = {k: blur(mpfb_mask(k, size), 1.0) for k in ("lips", "ears", "fingernails", "toenails", "aureolae", "inside-mouth")}

    idx = np.nonzero(cov)
    P = place[idx]
    N = facing[idx]
    N /= np.maximum(np.linalg.norm(N, axis=1), 1e-6)[:, None]
    ev = np.array([eyes.matrix_world @ v.co for v in eyes.data.vertices])
    head_j, neck_j = joint(rig, "Head"), joint(rig, "Neck")
    # Which way she faces: the eyes are in front of the head joint.
    fs = 1.0 if ev[:, 1].mean() > head_j[1] else -1.0
    x = P[:, 0] - ev[:, 0].mean()
    ax = np.abs(x)
    f = P[:, 1] * fs
    z = P[:, 2]
    nf = N[:, 1] * fs
    nz = N[:, 2]
    eye_x = np.abs(ev[:, 0] - ev[:, 0].mean()).mean()
    eye_z = ev[:, 2].mean()
    lip = masks["lips"][idx]
    on_lip = lip > 0.5
    mouth_z = z[on_lip].mean()
    mouth_f = f[on_lip].max()
    mouth_w = ax[on_lip].max()
    U = eye_z - mouth_z                           # the face's own measure: eyes to mouth
    mid = ax < 0.008
    s = mid & (z < eye_z - 0.2 * U) & (z > mouth_z + 0.2 * U)
    i = np.argmax(np.where(s, f, -1e9))
    nose = np.array([0.0, f[i], z[i]])
    s = mid & (z < mouth_z - 0.2 * U) & (z > mouth_z - 0.75 * U) & (nf > 0.3)
    i = np.argmax(np.where(s, f, -1e9))
    chin = np.array([0.0, f[i], z[i]])
    ear = masks["ears"][idx]
    on_ear = ear > 0.5
    ear_f, ear_z, lobe_z = f[on_ear].mean(), z[on_ear].mean(), z[on_ear].min()
    print("  face: eyes %.3f up, %.1f cm apart; mouth %.3f, %.1f cm wide; nose tip %.3f; chin %.3f; ears %.3f; eyes to mouth %.1f cm"
          % (eye_z, eye_x * 200, mouth_z, mouth_w * 200, nose[2], chin[2], ear_z, U * 100))

    Q = np.stack([x, f, z], axis=1)
    head = smooth(neck_j[2] - 0.03, neck_j[2] + 0.03, z)
    front = smooth(-0.1, 0.4, nf) * head
    D = np.ones((len(z), 3))

    def tint(m, col, k=1.0):
        D[:] *= 1.0 + (np.clip(m * k, 0.0, 1.0))[:, None] * (np.array(col) - 1.0)[None, :]

    def blob(c, r):
        return np.exp(-((Q - c[None, :]) ** 2).sum(axis=1) / (2.0 * r * r))

    # Shade: hollows are darker and warmer (light that reaches them has been through skin),
    # creases more so; skin facing the ground gets a little less light than skin facing up.
    # (Below the neck the wide shade is mostly the arms' against the sides, as the body
    # happens to be modelled: kept faint there.)
    k = spec["shade"]
    ow, ot = open_wide[idx], open_tight[idx]
    upper = smooth(neck_j[2] - 0.14, neck_j[2] - 0.05, z)
    tint(1.0 - ow, (0.62, 0.47, 0.43), 0.8 * k * (0.3 + 0.7 * upper))
    tint(1.0 - ot, (0.45, 0.26, 0.24), 0.95 * k)
    fo = (fold[idx] - 0.5) * 2.0
    tint(smooth(0.0, 0.07, -fo), (0.84, 0.74, 0.72), 0.9 * k)
    tint(smooth(0.0, 0.07, fo), (1.06, 1.055, 1.05), 0.8)
    tint(smooth(0.1, -0.9, nz), (0.86, 0.82, 0.81), 0.8 * k)
    tint(smooth(0.55, 1.0, np.abs(N[:, 0])) * head, (0.93, 0.9, 0.895), 0.8 * k)

    # The colors of a face.
    b = spec["blush"]
    cheek = np.exp(-(((ax - 1.45 * eye_x) / (0.36 * U)) ** 2 + ((z - (eye_z - 0.56 * U)) / (0.3 * U)) ** 2) * 0.5) * front
    tint(cheek, (1.06, 0.86, 0.86), b)
    tint(blob(nose, 0.2 * U), (1.06, 0.86, 0.86), 0.9 * b)
    tint(blob(nose + np.array([0.0, -0.1 * U, 0.02 * U]), 0.36 * U), (1.03, 0.94, 0.94), 0.7 * b)
    tint(ear * ear, (1.05, 0.88, 0.88), 0.7 * b)
    tint(blob(chin, 0.24 * U), (1.03, 0.94, 0.94), 0.7 * b)
    brow = smooth(eye_z + 0.4 * U, eye_z + 0.85 * U, z) * front
    tint(brow, (1.03, 1.02, 0.97), 0.8)
    # Round the eyes: darker and rosier toward the opening, where the game's own eyelids
    # (eyelid.gdshader: the tone times 0.84, 0.74, 0.7) meet the face.
    g = np.array(spec["gain"])
    socket = np.exp(-(((ax - eye_x) / (0.38 * U)) ** 2 + ((z - eye_z - 0.02 * U) / (0.2 * U)) ** 2) * 0.9) * front
    tint(socket, np.array((0.97, 0.87, 0.84)) / g, 0.6)
    under = np.exp(-(((ax - eye_x) / (0.3 * U)) ** 2 + ((z - (eye_z - 0.24 * U)) / (0.1 * U)) ** 2) * 0.5) * front
    tint(under, (0.96, 0.94, 0.97), 0.4)
    # The neck: in the jaw's shade, most just under it, fading out toward the collarbones.
    throat = smooth(chin[2] - 0.05 * U, chin[2] - 0.55 * U, z) * smooth(neck_j[2] - 0.2, neck_j[2] - 0.07, z)
    tint(throat * (0.6 + 0.4 * smooth(-0.6, 0.3, nf)), (0.87, 0.82, 0.81), spec["shade"])

    # Lips: their color, lines running down them, a paler middle to the lower one.
    col, k = spec["lips"]
    lines = vnoise(np.stack([x * 1500.0, f * 40.0, z * 60.0], axis=1), 5) - 0.5
    tint(lip, col, k)
    # (the line where they meet: MPFB's mask of the mouth's inside starts just behind it)
    seam = np.clip(blur(masks["inside-mouth"], 5.0 * size / 2048.0) * 2.5, 0.0, 1.0)[idx]
    tint(seam, (0.7, 0.5, 0.5), 0.9)
    tint(lip, (0.9, 0.86, 0.86), np.clip(lines * 1.6, 0.0, 1.0))
    tint(lip * np.exp(-((x / (0.45 * mouth_w)) ** 2 + ((z - (mouth_z - 0.07 * U)) / (0.05 * U)) ** 2)), (1.07, 1.09, 1.09))
    tint(masks["inside-mouth"][idx], (0.5, 0.22, 0.22))

    # A shaved beard's shadow: from the sideburns down the jaw, round the mouth and under
    # the chin, as a cooler darker cast with the hairs' dots in it.
    if spec["stubble"]:
        back = (mouth_f - f) / (mouth_f - ear_f)          # 0 at the lips, 1 at the ears
        cheek_line = mouth_z + 0.22 * U + (ear_z - 0.1 * U - mouth_z - 0.22 * U) * smooth(0.12, 1.0, back)
        lip_line = nose[2] - 0.2 * U
        mid_w = 1.0 - smooth(mouth_w * 0.8, mouth_w * 1.3, ax)
        top = cheek_line + (np.maximum(cheek_line, lip_line) - cheek_line) * mid_w
        low = chin[2] - 0.75 * U + (lobe_z - 0.45 * U - chin[2] + 0.75 * U) * np.clip(back, 0.0, 1.0)
        beard = ((1.0 - smooth(top - 0.12 * U, top + 0.06 * U, z)) * smooth(low - 0.3 * U, low + 0.15 * U, z)
                 * (1.0 - smooth(0.82, 1.0, back)) * smooth(-0.6, 0.0, back + 0.6) * (1.0 - np.clip(lip * 1.5, 0.0, 1.0))
                 * (1.0 - np.clip(ear * 2.0, 0.0, 1.0)))
        dots = smooth(0.5, 0.78, vnoise(Q * 1300.0, 9))
        patchy = 0.8 + 0.2 * fbm(Q, 60.0, 2, 17)
        tint(beard * patchy, (0.87, 0.885, 0.915), spec["stubble"] * 0.75)
        tint(beard * dots, (0.86, 0.87, 0.9), spec["stubble"] * 0.7)

    # The body: nails, and the redder skin over elbows and knees.
    tint(masks["aureolae"][idx], (0.93, 0.72, 0.7), 0.75)
    tint(np.maximum(masks["fingernails"][idx], masks["toenails"][idx]), (1.08, 0.97, 0.95), 0.8)
    for side in ("Left", "Right"):
        for name, r in (("ForeArm", 0.04), ("Leg", 0.05)):
            c = joint(rig, side + name)
            c = np.array([c[0] - ev[:, 0].mean(), c[1] * fs, c[2]])
            tint(blob(c, r), (1.04, 0.92, 0.91), 0.8)

    # The grain of skin: wide blotches that lean red or yellow, mottling, pores.
    k = spec["grain"]
    wide = fbm(Q, 14.0, 3, 1)
    D *= 1.0 + 0.022 * k * wide[:, None] * np.array((0.3, -0.8, -1.0))[None, :]
    D *= 1.0 + 0.03 * k * fbm(Q, 110.0, 3, 2)[:, None] * np.array((0.6, 1.0, 1.0))[None, :]
    pores = vnoise(Q * 900.0, 3) * 0.6 + vnoise(Q * 1900.0, 4) * 0.4 - 0.5
    D *= 1.0 + 0.06 * k * pores[:, None] * (1.0 - np.clip(lip, 0.0, 1.0) * 0.7)[:, None]

    # Into the picture. The background takes whatever color makes the whole picture's
    # average BASE, so the game shows plain face skin as the tone times "gain".
    base = to_linear(BASE)
    lin = np.clip(D * g[None, :] * base[None, :], 0.0, 1.0)
    out = np.empty((size, size, 4), dtype=np.float32)
    out[:, :, 3] = 1.0
    srgb = to_srgb(lin)
    n_all, n_cov = size * size, len(z)
    for c in range(3):
        ch = np.zeros((size, size))
        ch[idx] = srgb[:, c]
        bg = float(np.clip((BASE[c] * n_all - srgb[:, c].sum()) / (n_all - n_cov), 0.0, 1.0))
        ch[~cov] = bg
        out[:, :, c] = ch
    img = bpy.data.images.new("skin", size, size, alpha=False)
    img.pixels.foreach_set(out.ravel())
    path = os.path.join(PROJECT, "assets", "player", "mpfb_%s_skin.png" % body)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    mean = out[:, :, :3].astype(np.float64).reshape(-1, 3).mean(axis=0)
    print("skin: wrote %s (average %s; face skin against it %s)" % (path, np.round(mean, 3), np.round(np.median((lin / to_linear(mean))[head > 0.5], axis=0), 2)))
    if debug:
        # The face, as painted, at full size (the game's colors: divided by the average).
        h = int(size * 0.2)
        r, c = int(idx[0][on_lip].mean()), int(idx[1][on_lip].mean()) - h // 3
        r0, r1, c0, c1 = max(r - h, 0), min(r + h, size), max(c - h, 0), min(c + h, size)
        crop = np.clip(out[r0:r1, c0:c1, :], 0.0, 1.0)
        d = bpy.data.images.new("dbg", crop.shape[1], crop.shape[0], alpha=False)
        d.pixels.foreach_set(np.ascontiguousarray(crop).ravel())
        d.filepath_raw = os.path.join(debug, "%s_face.png" % body)
        d.file_format = "PNG"
        d.save()
        print("  debug: nf on the lips %.2f, front %.2f, cheek max %.2f, seam max %.2f, socket max %.2f" % (nf[on_lip].mean(), front[on_lip].mean(), cheek.max(), seam.max(), socket.max()))
        for name, m in (("open_wide", open_wide), ("open_tight", open_tight), ("fold", np.clip(fold, 0, 1))):
            d = bpy.data.images.new("dbg", size, size, alpha=False)
            d.pixels.foreach_set(np.dstack([m, m, m, np.ones_like(m)]).astype(np.float32).ravel())
            d.filepath_raw = os.path.join(debug, "%s_%s.png" % (body, name))
            d.file_format = "PNG"
            d.save()
    return path


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    size = next((int(a.split("=")[1]) for a in args if a.startswith("size=")), 2048)
    debug = next((a.split("=", 1)[1] for a in args if a.startswith("debug=")), None)
    cache = next((a.split("=", 1)[1] for a in args if a.startswith("cache=")), None)
    for body in [a for a in args if "=" not in a] or list(BODIES):
        print("skin:", body)
        paint(body, size, debug, cache)
