# Paints the goalie masks' paint jobs: pattern textures for the shells built by
# tools/blender/goalie_mask_gear.py, saved to assets/characters/masks/mask_<key>_<name>.png.
#
# Run in Blender:
#   exec(open(r"<project>/tools/blender/goalie_mask_paint.py").read()); paint_all()
# sheet("a") saves a colored preview of every design on one mask (PREVIEW_COLORS).
#
# A pattern texture's channels say where each color goes over the base, as the luchador
# hoods' do (scenes/actors/mask_paint.gdshader): red accent 1, green accent 2, blue the
# detail color (outlines, teeth, stars), painted in that order.
#
# The shells share one kind of layout (paint_uv in goalie_mask_gear.py): a fisheye view of
# the mask from the front. Designs are not drawn in that image, though: for every texel the
# painter works out the point of the mask it lands on, and a design is written in terms of
# the mask itself (how far around from the center line, how high, how far from the cage
# opening or the eye holes), so the same design sits right on every mask.

import math
import os

import bpy
import numpy as np

_HERE = os.path.dirname(os.path.abspath(globals().get(
    "__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\goalie_mask_paint.py")))
_saved_file = globals().get("__file__")
globals()["__file__"] = os.path.join(_HERE, "goalie_mask_gear.py")
exec(open(os.path.join(_HERE, "goalie_mask_gear.py")).read())
if _saved_file is not None:
    globals()["__file__"] = _saved_file

TEX = 1024
ARC = 0.11   # meters of arc per radian around the head, for measuring "how far around"
PREVIEW_COLORS = ((0.93, 0.93, 0.9), (0.1, 0.25, 0.75), (0.95, 0.75, 0.1), (0.05, 0.05, 0.06))


class Fields:
    """What the painter knows about each texel of one mask's layout (arrays TEX x TEX, row 0
    at v = 0):
      X, Y, Z   the point of the mask there (m, on the head: +Y up, +Z the face)
      A         how far around it is from the center line (m of arc, + toward the head's left)
      S         the same without the sign
      QX, QY    the layout's own coordinates, scaled to about meters (for work over the crown,
                where A pinches together)
      e         how far outside the cage opening (the molded mask: the eye holes) it is (m;
                < 0 inside it)
      win       how far outside the "window" the face shows in: e on the cage masks, an
                oval around both eye holes on the molded one
      far       the same in a straight line, for designs that reach a long way from it
      rin       how far inside the shell's outer edge (m)
      cover     1 where there is shell to paint
      mpp       meters per texel there
      psi       the angle around the window (0 straight out to the head's left, + up), and
                psi_s the same mirrored (-pi/2 .. pi/2 on both sides)
    and the mask's landmarks: top, bot, half (the window's top, bottom and half width in
    A), mid (its middle height), hy (its half height), chin, crown (the shell's lowest and
    highest Y), side (how far around the rear edge is), k (the sides' size next to the
    modern mask's), key."""


def fields(key):
    spec = PAINTED[key]
    sh = Shell(spec, n=4)
    s, dz = spec["fit"] if spec["fit"] is not None else (Vector((1, 1, 1)), 0.0)
    t = (np.arange(TEX) + 0.5) / TEX * 2.0 - 1.0
    qx, qy = np.meshgrid(t, t)   # rows are v
    rho = np.hypot(qx, qy)
    th = np.minimum(rho, 1.0) * UV_SPAN
    k = np.sin(th) / np.maximum(rho, 1e-9)
    df = np.stack([qx * k, qy * k, np.cos(th)], axis=-1)        # direction on the head
    dd = df / np.array([s.x, s.y, s.z])                          # ... as the shell was shaped
    dd /= np.linalg.norm(dd, axis=-1, keepdims=True)
    c = np.array(tuple(C0))
    lo = np.full(rho.shape, 0.02)
    hi = np.full(rho.shape, 0.5)
    for _ in range(24):
        mid = (lo + hi) * 0.5
        p = c + dd * mid[..., None]
        ins = np.abs(p[..., 0]) < sample(sh.field, p[..., 2], p[..., 1])
        lo = np.where(ins, mid, lo)
        hi = np.where(ins, hi, mid)
    pd = c + dd * ((lo + hi) * 0.5)[..., None]                   # the point, as shaped
    F = Fields()
    F.key = key
    F.X, F.Y, F.Z = pd[..., 0] * s.x, pd[..., 1] * s.y, pd[..., 2] * s.z + dz
    F.A = np.arctan2(F.X, F.Z + 0.005) * ARC
    F.S = np.abs(F.A)
    F.QX, F.QY = qx * 0.3, qy * 0.3
    gy = np.gradient(np.stack([F.X, F.Y, F.Z], axis=-1), axis=0)
    gx = np.gradient(np.stack([F.X, F.Y, F.Z], axis=-1), axis=1)
    F.mpp = np.clip(0.5 * (np.linalg.norm(gx, axis=-1) + np.linalg.norm(gy, axis=-1)), 1e-4, 5e-3)
    F.rin = -sd_poly(pd[..., 2], pd[..., 1], spec["rim"]) * 0.78
    if key in OPENINGS:
        azd = np.degrees(np.arctan2(pd[..., 0], pd[..., 2] - ZC))
        F.e = np.where(pd[..., 2] > 0.0, sd_poly(azd * AZ, pd[..., 1], deg(OPENINGS[key])), 0.05) * 0.78
        F.win = F.e
    else:
        ex, ey, rx, ry, tilt = D_EYE
        e = np.minimum(sd_ellipse(F.X, F.Y, ex, ey, rx, ry, tilt), sd_ellipse(F.X, F.Y, -ex, ey, rx, ry, -tilt))
        F.e = np.where(F.Z > 0.02, e, 0.05)
        F.win = np.where(F.Z > 0.0, sd_ellipse(F.A, F.Y, 0.0, ey - 0.004, 0.07, 0.03), 0.05)
    F.cover = ((F.e > 0.0) & (F.rin > 0.0) & (rho < 1.0)).astype(float)
    inside = (F.win < 0.0) & (rho < 1.0)
    # How far from the window, for designs that reach a long way from it: the straight-line
    # distance to its edge, which stays even over the crown and around the sides (measured
    # around the head it pinches and stretches there).
    band = np.argwhere((np.abs(F.win) < 0.7 * F.mpp) & (rho < 0.98))
    band = band[::max(1, len(band) // 260)]
    far = np.full(F.Y.shape, 1e9)
    for i, j in band:
        far = np.minimum(far, (F.X - F.X[i, j]) ** 2 + (F.Y - F.Y[i, j]) ** 2 + (F.Z - F.Z[i, j]) ** 2)
    F.far = np.where(inside, -1.0, 1.0) * np.sqrt(far)
    F.top, F.bot = float(F.Y[inside].max()), float(F.Y[inside].min())
    F.half = float(F.S[inside].max())
    F.mid = 0.5 * (F.top + F.bot)
    on = F.cover > 0
    F.chin, F.crown = float(F.Y[on].min()), float(F.Y[on].max())
    F.hy = 0.5 * (F.top - F.bot)
    F.side = float(F.S[on & (np.abs(F.Y - F.mid) < 0.02) & (F.Z > -0.2)].max())   # the rear edge, in A
    F.k = (F.side - F.half) / 0.125                                                # the sides' size (modern: 1)
    # Around the window: 0 straight out to the head's left, + up, as if the window were round.
    # Measured in the layout itself, where lines out from the window stay straight over the
    # crown (around the head they pinch together there).
    qh = float(np.abs(F.QX[inside]).max())
    q0, q1 = float(F.QY[inside].min()), float(F.QY[inside].max())
    F.psi = np.arctan2((F.QY - 0.5 * (q0 + q1)) / (0.5 * (q1 - q0)), F.QX / qh)
    F.psi_s = np.arctan2((F.QY - 0.5 * (q0 + q1)) / (0.5 * (q1 - q0)), np.abs(F.QX) / qh)   # ... mirrored
    print("mask %s: window top %.3f bottom %.3f half %.3f, chin %.3f, crown %.3f" % (
        key, F.top, F.bot, F.half, F.chin, F.crown))
    return F


# --- Brushes -------------------------------------------------------------------------------------

def cov(g):
    """Coverage of {g < 0} for any smooth g, anti-aliased by its own slope."""
    gy, gx = np.gradient(g)
    return np.clip(0.5 - g / (np.sqrt(gx * gx + gy * gy) + 1e-12), 0.0, 1.0)


def edge(F, g, w):
    """A line `w` m wide along {g = 0}."""
    gy, gx = np.gradient(g)
    d = np.abs(g) / (np.sqrt(gx * gx + gy * gy) + 1e-12)   # texels from the line
    return np.clip(0.5 - (d - 0.5 * w / F.mpp), 0.0, 1.0)


def solid(F, sd):
    """Coverage of a shape from its signed distance (m, < 0 inside)."""
    return np.clip(0.5 - sd / F.mpp, 0.0, 1.0)


def outline(F, sd, w):
    return np.clip(0.5 - (np.abs(sd) - 0.5 * w) / F.mpp, 0.0, 1.0)


def tri(x):
    """A triangle wave: 0 at whole numbers, 1 halfway between."""
    return np.abs((x % 1.0) - 0.5) * 2.0


def over(under, top):
    """Layers: `top` painted over `under` (each an (r, g, b) of coverages)."""
    a = np.clip(top[0] + top[1] + top[2], 0.0, 1.0)
    return tuple(u * (1 - a) + t for u, t in zip(under, top))


def window_line(F, w=0.0022, gap=0.0045):
    """A pinstripe around the cage opening or the eye holes."""
    return outline(F, F.e - gap, w)


# --- Designs -------------------------------------------------------------------------------------
# Each returns (accent 1, accent 2, detail) coverages. DESIGNS lists them with the colors
# they are meant for (see GoalieVisual.MASK_PAINTS in game).

def p_flames(F):
    """Flames licking up from the chin and jaw, leaning back as they rise: accent 1 with a
    hotter accent 2 core, edged in the detail color."""
    def tongues(x, w):
        return 1.0 - np.abs(np.sin(np.pi * x / w)) ** 0.5
    lean = F.S - 0.5 * (F.Y - F.chin)
    base = F.bot - 0.02 + 0.045 * smooth_np(0.0, 0.12, F.S)   # higher toward the back
    top1 = base + 0.085 * (0.62 * tongues(lean, 0.04) + 0.38 * tongues(lean + 0.013, 0.024))
    top2 = base - 0.03 + 0.07 * (0.62 * tongues(lean + 0.004, 0.04) + 0.38 * tongues(lean + 0.02, 0.024))
    outer, inner = cov(F.Y - top1), cov(F.Y - top2)
    line = edge(F, F.Y - top1, 0.0024)
    return outer * (1 - inner) * (1 - line), inner * (1 - line), line


def p_beast(F):
    """A beast's face: fangs around the cage opening (the molded mask: a mouth of teeth
    across the lower face), gums in accent 2, angry eyes over the brow, stripes down the
    sides in accent 1."""
    zero = np.zeros(F.Y.shape)
    if F.key in OPENINGS:
        e = F.e
        per = 0.0125
        row = np.where(F.Y > F.mid, 1.0, 0.0)
        length = np.where(row > 0, 0.02, 0.017) * (1.0 + 0.9 * np.exp(-((F.S - F.half * 0.6) / 0.008) ** 2))
        span = smooth_np(F.half * 0.97, F.half * 0.86, F.S)   # the rows end before the corners
        teeth = cov(tri(F.A / per) * 0.5 - 0.46 * e / length) * cov(e - length) * span
        gums = cov(e - length - 0.0075) * (1 - cov(e - length)) * span
        lips = cov(e - 0.0065) * (1 - span)
        mouth_y = None
    else:
        mouth_y = F.mid - 0.07 + 5.0 * F.A ** 2          # a grin
        dy = np.abs(F.Y - mouth_y)
        length = 0.016
        span = smooth_np(0.062, 0.05, F.S)
        teeth = cov(tri(F.A / 0.0115 + 0.5 * (F.Y > mouth_y)) * 0.5 - 0.46 * dy / length) * cov(dy - length) * span
        gums = cov(dy - length - 0.007) * (1 - cov(dy - length)) * span
        lips = zero
    # Eyes over the brow (the molded mask: dark sockets around its eye holes), and a brow.
    r, g, b = zero, np.maximum(gums, lips), teeth
    for side in (1, -1):
        if F.key in OPENINGS:
            ex, ey = side * F.half * 0.47, F.top + 0.045
            eye = sd_ellipse(F.A, F.Y, ex, ey, 0.024, 0.0095, 0.42 * side)
            pupil = sd_ellipse(F.A, F.Y, ex - side * 0.003, ey - 0.001, 0.0032, 0.008, 0.42 * side)
            brow = sd_ellipse(F.A, F.Y, ex + side * 0.002, ey + 0.012, 0.03, 0.0055, 0.5 * side)
            b = np.maximum(b, solid(F, eye) * (1 - solid(F, pupil)))
            g = np.maximum(g, np.maximum(solid(F, pupil), solid(F, brow) * (1 - solid(F, eye))))
            g = np.maximum(g, outline(F, eye, 0.0022))
        else:
            ex, ey, rx, ry, tilt = D_EYE
            socket = sd_ellipse(F.X, F.Y, side * (ex + 0.004), ey + 0.006, rx + 0.016, ry + 0.012, 0.5 * side)
            g = np.maximum(g, solid(F, socket) * (F.Z > 0.02))
    # Stripes: tapering from the back edge forward, down the sides and over the crown.
    side_w = smooth_np(0.045, 0.08, np.abs(F.X)) * smooth_np(0.012, 0.035, F.win)
    wave = np.sin(F.Y * 95.0 - 38.0 * F.Z + 1.2 * np.sin(F.Z * 55.0))
    stripes = cov(0.55 + 0.4 * (1 - side_w) - wave) * (side_w > 0.02)
    r = stripes * (1 - np.clip(g + b, 0, 1))
    line = window_line(F)
    return r * (1 - line), g * (1 - line) * (1 - b), np.maximum(b, line * (1 - g))


def p_wings(F):
    """A wing each side, sweeping back from beside the window: three rows of accent 1
    feathers edged in accent 2, and a stripe over the crown."""
    zero = np.zeros(F.Y.shape)
    r, g = zero, zero
    root = (F.half + 0.004, F.mid + 0.004)
    rows = [  # (feathers, first and last angle up from straight back, first and last length, width)
        (6, -22.0, 62.0, 0.2, 0.125, 0.019),
        (5, -12.0, 66.0, 0.128, 0.09, 0.0175),
        (4, 0.0, 70.0, 0.074, 0.058, 0.016),
    ]
    for n, a0, a1, l0, l1, w in rows:
        fill_row, lines = zero, zero
        for i in range(n):
            t = i / (n - 1)
            a = math.radians(a0 + (a1 - a0) * t)
            ln = (l0 + (l1 - l0) * t) * F.k
            sd = sd_ellipse(F.S, F.Y, root[0] + math.cos(a) * ln * 0.5, root[1] + math.sin(a) * ln * 0.5,
                            ln * 0.5, w * (0.75 + 0.25 * F.k), a)
            fill_row = np.maximum(fill_row, solid(F, sd))
            lines = np.maximum(lines, outline(F, sd, 0.0026))
        r = np.maximum(r, fill_row)
        g = np.maximum(g * (1 - fill_row), lines)
    r = r * (1 - g)
    # The crown stripe: from over the window back, pinstriped.
    upper = np.maximum(smooth_np(F.top + 0.006, F.top + 0.016, F.Y), (F.Z < 0.05) * (F.Y > 0.05))
    stripe = solid(F, np.abs(F.X) - 0.013) * upper
    pins = outline(F, np.abs(F.X) - 0.019, 0.0022) * upper
    line = window_line(F)
    r = np.maximum(r, stripe)
    return r * (1 - line), g * (1 - stripe) * (1 - line), np.maximum(pins * (1 - r), line)


def p_burst(F):
    """A sunburst: long and short spikes of accent 1 around the window, each with an
    accent 2 heart, edged in the detail color."""
    n = 24
    frac = F.psi / math.tau * n
    long_ = (np.floor(frac) % 2) == 0
    length = np.where(long_, 0.09, 0.052) * (0.55 + 0.45 * F.k)
    off = 1.0 - tri(frac)                       # 0 down a spike's middle, 1 between spikes
    g1 = off - 0.92 * (1.0 - F.far / length)
    g2 = off - 0.42 * (1.0 - F.far / (0.6 * length))
    out = cov(-F.far)
    spikes, hearts = cov(g1) * out, cov(g2) * out
    lines = edge(F, g1, 0.0022) * out * (off < 0.95)   # (not the jump where long meets short)
    ring = cov(F.far - 0.007) * out
    r = spikes * (1 - hearts) * (1 - ring)
    g = np.maximum(hearts, ring)
    return r * (1 - lines), g * (1 - lines), lines


def p_stars(F):
    """Stars and bars: a field of detail-color stars on accent 1 over the brow and crown,
    accent 2 bars down the cheeks and chin."""
    bound = F.top + 0.018 - 0.3 * np.clip(F.S - F.half, 0.0, 1.0) - F.Y   # < 0 above the line
    upper = np.maximum(cov(bound), (F.Z < 0.0) * (F.Y > F.mid))
    cell = 0.038
    gy = F.QY / cell
    gx = F.QX / cell + 0.5 * (np.floor(gy) % 2)
    lx, ly = ((gx % 1.0) - 0.5) * cell, ((gy % 1.0) - 0.5) * cell
    stars = solid(F, sd_poly(lx, ly, star(0.0, 0.0, 0.0115, 0.0048))) * upper
    bars = cov(np.sin(math.tau * F.A / 0.034 + math.pi / 2)) * (1 - upper)
    line = edge(F, bound, 0.003) * (F.Z > 0.0)
    return upper * (1 - stars) * (1 - line), bars * (1 - line), np.maximum(stars, line)


def bolt(pts, w0):
    """A lightning bolt's outline from its zigzag center line (top first), tapering from w0
    wide to a point."""
    n = len(pts)
    ws = [w0 * (1.0 - i / (n - 1)) for i in range(n)]
    return [(x + w, y) for (x, y), w in zip(pts, ws)] + [(x - w, y) for (x, y), w in reversed(list(zip(pts, ws)))][1:]


def p_bolts(F):
    """A storm: an accent 2 cloud bank over the crown, accent 1 lightning striking down
    each side and down the forehead, edged in the detail color."""
    k = 0.55 + 0.45 * F.k
    cloud_y = F.crown - 0.062 - 0.011 * np.abs(np.sin(F.S * 48.0)) - 0.005 * np.abs(np.sin(F.S * 131.0 + 1.0))
    cloud = np.maximum(cov(cloud_y - F.Y), (F.Z < -0.01) * (F.Y > F.top))
    sd = np.full(F.Y.shape, 1.0)
    x0, y0 = F.half + 0.03 * k, F.crown - 0.07
    main = [(x0 + 0.03 * k, y0 + 0.01), (x0 - 0.012, y0 - 0.055), (x0 + 0.04 * k, y0 - 0.062),
            (x0 - 0.008, y0 - 0.128), (x0 + 0.038 * k, y0 - 0.136), (x0 - 0.03, F.bot - 0.05)]
    sd = np.minimum(sd, sd_poly(F.S, F.Y, bolt(main, 0.022)))
    x1 = F.half + 0.1 * k
    small = [(x1 + 0.016, y0), (x1 - 0.012, y0 - 0.05), (x1 + 0.022, y0 - 0.056), (x1 - 0.012, y0 - 0.125)]
    sd = np.minimum(sd, sd_poly(F.S, F.Y, bolt(small, 0.014)))
    mid = [(0.022, F.top + 0.088), (-0.02, F.top + 0.052), (0.022, F.top + 0.046), (-0.008, F.top + 0.008)]
    sd = np.minimum(sd, np.where(F.Z > 0.02, sd_poly(F.X, F.Y, bolt(mid, 0.02)), 1.0))
    bolts = solid(F, sd)
    lines = outline(F, sd, 0.0024)
    line = window_line(F)
    return bolts * (1 - lines), cloud * (1 - bolts) * (1 - lines), np.maximum(lines, line * (1 - bolts))


def p_sweep(F):
    """Blades sweeping around the window: three curved accent 1 blades each side with
    accent 2 echoes, and a point up the forehead and down the chin."""
    zero = np.zeros(F.Y.shape)
    reach = 0.125 * (0.55 + 0.45 * F.k)
    out = cov(-F.far)
    r, g = zero, zero
    for a0 in (-1.15, -0.35, 0.45):
        t = np.clip(F.far / reach, 0.0, 1.0)
        da = F.psi_s - a0 - 5.0 * F.far
        r = np.maximum(r, cov(np.abs(da) - 0.24 * (1.0 - t) ** 0.8))
        g = np.maximum(g, cov(np.abs(da - 0.3) - 0.075 * np.clip(1.0 - t / 0.85, 0.0, 1.0)))
    up = cov(np.abs(F.X) - 0.02 * (1.0 - (F.Y - F.top) / 0.085)) * (F.Y > F.top) * (F.Z > 0.03)
    down = cov(F.S - 0.02 * (1.0 - (F.bot - F.Y) / 0.07)) * (F.Y < F.bot)
    r = np.maximum(r * out, np.maximum(up, down))
    g = g * out * (1 - r)
    line = window_line(F)
    return r * (1 - line), g * (1 - line), line


STITCHES = [  # (around, height, angle, length), scattered like the real thing
    (-0.03, 0.108, 20.0, 0.046), (0.05, 0.118, -35.0, 0.036), (0.1, 0.085, 70.0, 0.032),
    (-0.105, 0.08, -55.0, 0.04), (-0.135, 0.03, 80.0, 0.044), (0.14, 0.012, -75.0, 0.04),
    (0.125, -0.045, 30.0, 0.036), (-0.115, -0.05, -20.0, 0.04), (-0.04, -0.074, 55.0, 0.034),
    (0.034, -0.084, -40.0, 0.03), (0.004, -0.108, 8.0, 0.028), (0.175, 0.062, 12.0, 0.032),
    (-0.18, 0.07, -15.0, 0.036), (0.07, -0.02, 85.0, 0.026), (-0.068, 0.0, -80.0, 0.024),
    (0.018, 0.092, -70.0, 0.022)]


def p_stitches(F):
    """Stitches in the detail color, one for every puck the mask stopped."""
    kx = 0.5 + 0.5 * F.k
    b = np.zeros(F.Y.shape)

    def segment(ax, ay, bx, by):
        ex, ey = bx - ax, by - ay
        t = np.clip(((F.A - ax) * ex + (F.Y - ay) * ey) / (ex * ex + ey * ey), 0.0, 1.0)
        return np.hypot(F.A - ax - ex * t, F.Y - ay - ey * t)

    for cx, cy, ang, ln in STITCHES:
        cx *= kx
        if F.key == "d":
            cy = cy * 0.8 - 0.012
        a = math.radians(ang)
        ux, uy = math.cos(a), math.sin(a)
        b = np.maximum(b, np.clip(0.5 - (segment(cx - ux * ln / 2, cy - uy * ln / 2, cx + ux * ln / 2, cy + uy * ln / 2)
                                         - 0.0011) / F.mpp, 0.0, 1.0))
        n = max(3, int(ln / 0.0075))
        for j in range(n):
            q = (j + 0.5) / n - 0.5
            px, py = cx + ux * ln * q, cy + uy * ln * q
            b = np.maximum(b, np.clip(0.5 - (segment(px - uy * 0.0055, py + ux * 0.0055, px + uy * 0.0055, py - ux * 0.0055)
                                             - 0.0009) / F.mpp, 0.0, 1.0))
    return np.zeros(F.Y.shape), np.zeros(F.Y.shape), b * (F.Z > -0.02)


DESIGNS = {"flames": p_flames, "beast": p_beast, "wings": p_wings, "burst": p_burst, "stars": p_stars,
           "bolts": p_bolts, "sweep": p_sweep, "stitches": p_stitches}


# --- Painting ------------------------------------------------------------------------------------

_fields = {}


def get_fields(key):
    if key not in _fields:
        _fields[key] = fields(key)
    return _fields[key]


def save_image(name, rgb, path):
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    h, w = rgb[0].shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.stack([rgb[0], rgb[1], rgb[2], np.ones(rgb[0].shape)], axis=-1).astype(np.float32)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def design(key, name):
    F = get_fields(key)
    r, g, b = DESIGNS[name](F)
    return tuple(np.clip(ch, 0.0, 1.0) for ch in (r, g, b))


def paint_all(keys="acd", names=None):
    os.makedirs(TEX_OUT, exist_ok=True)
    for key in keys:
        for name in (names or DESIGNS):
            save_image("mask_%s_%s" % (key, name), design(key, name),
                       os.path.join(TEX_OUT, "mask_%s_%s.png" % (key, name)))
            print("saved mask_%s_%s.png" % (key, name))


def colored(F, rgb, colors=PREVIEW_COLORS):
    """A design as the game colors it (base, accent 1, accent 2, detail), over the shell."""
    out = np.zeros(F.Y.shape + (3,)) + np.array(colors[0])
    for ch, col in zip(rgb, colors[1:]):
        out = out * (1 - ch[..., None]) + np.array(col) * ch[..., None]
    return out * F.cover[..., None] + 0.16 * (1 - F.cover[..., None])


def sheet(key, path, names=None, colors=PREVIEW_COLORS, cell=512):
    """Saves every design on one mask's layout, side by side."""
    F = get_fields(key)
    names = list(names or DESIGNS)
    step = TEX // cell
    tiles = [colored(F, design(key, n), colors)[::step, ::step] for n in names]
    img = np.concatenate(tiles, axis=1)
    save_image("mask_sheet_" + key, (img[..., 0], img[..., 1], img[..., 2]), path)
    print("sheet:", path, names)
