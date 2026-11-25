# Builds the hats in Blender and exports them to assets/equip/; tools/build_gear.gd
# (only=hat) turns them into assets/characters/*.res. Hats are head gear worn in place of
# the helmet (SkaterVisual.HATS): set on the crown as a helmet is, and they come off in a
# fight as a helmet does.
#
# Run in Blender:  exec(open(r"<project>/tools/blender/hat_gear.py").read()); build_all(True)
# with the male head in the scene as tools/blender/helmet_gear.py wants it (HEAD_OBJ),
# which this is built on (its Shape, patches, solidify, export); the head is only used for
# the fit check (clearance()).
#
#   cap      Florida Man's ball cap, worn backwards: a soft six-panel crown close to the
#            head, the bill out over the nape, the strap and its half-moon opening on the
#            forehead, a button on top. hat_cap.glb: crown (team color), accent (bill,
#            button, seams, strap)
#   shades   his wraparound sunglasses: one mirrored blade of a lens across both eyes with
#            a notch for the nose, a heavy brow bar and arms back over the ears.
#            hat_shades.glb: frame, lens. The game sets them on the eyes (the masks' frame,
#            SkaterVisual.MASK_EYE) and hangs them on the cap.
#   stunt    the Stuntmen's helmet: an open-face daredevil's helmet, a deep round shell down
#            over the ears and the nape with the face left open, a short snap-on peak
#            over the brow, a rolled edge and a chin strap. hat_stunt.glb: shell (the game
#            paints flames on it: scenes/actors/flame_paint.gdshader), trim (the peak and
#            its snaps), dark (the edge, the liner, the strap)
#   watch    the Whalers' knit fisherman's watch cap: a close ribbed crown and a deep cuff
#            folded back up round it, worn over the tops of the ears. hat_watch.glb: knit
#            (team color; the crown, the cuff, a plain lining), stripe (a band round the cuff)
#   beanie   a winter knit beanie for anyone: a tall ribbed crown with two stripes round it,
#            a deep cuff down over the tops of the ears, a pom on top. hat_beanie.glb: knit
#            (team color), accent (the stripes and the pom)
#   leather  an old leather helmet, as football players wore: a round crown, a padded band
#            round the head with straps from it over the top, a flap down over each ear
#            with holes punched in it, a chin strap. hat_leather.glb: leather, straps (the
#            padding, the binding round the edge, the chin strap), dark (the ear holes)
#   guard    a leather head guard, the hockey one: a broad band of stiff leather round the
#            head with a short tab down over each ear, lined and padded with felt; a cross
#            of padded leather straps over the top of the head, open between them (the game
#            shows the hair through it); a thin chin strap. hat_guard.glb: leather (the
#            band, the straps), felt (the lining, the padding inside the band's top, the
#            roll under its lower edge, the stitching), dark (the chin strap, rivets)
#   golf     the Sweet Tea's golf visor: a band round the head, a tall stiff panel in front
#            narrowing to a strap behind, a see-through tinted bill, the top of the head
#            left open (the hair shows out of it). hat_golf.glb: band (team color), brim
#            (the see-through bill), trim (piping round the edges, the tab at the back)
#   cowboy   a cowboy hat for anyone: a tall crown creased down the middle and pinched at
#            the front, a wide brim rolled up at the sides and dipped front and back, a
#            band round the crown. hat_cowboy.glb: felt, band (team color)
#
# Frame (game coordinates, meters): the helmets', the origin CROWN below the top of the male
# head, +Y up, +Z the face. In it the bare skull is about 0.077 wide to each side, 0.099
# deep in front and 0.120 behind at brow level, the crown at 0.1446, the eyes at
# (+-0.031, 0.0255, 0.0747), the bridge of the nose 0.0965 out.

import math
import os

import bmesh
import bpy
from mathutils import Vector

_here = os.path.dirname(os.path.abspath(globals().get(
    "__file__", r"C:\Users\Booker\Desktop\Knockout Hockey\tools\blender\hat_gear.py")))
_hm = {"__file__": os.path.join(_here, "helmet_gear.py"), "__name__": "helmet_gear"}
with open(_hm["__file__"]) as _f:
    exec(compile(_f.read(), _hm["__file__"], "exec"), _hm)
for _k, _v in _hm.items():
    if not _k.startswith("__"):
        globals()[_k] = _v
_hm["COLLECTION"] = "HatGear"     # (helmet_gear's new_object looks its collection up there)


def ring_grid(bm, rings, closed=True):
    """Quads between consecutive rings of game points (each ring a loop when `closed`)."""
    vs = [[bm.verts.new(g(*q)) for q in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.smooth = True
    return vs


def paint(o, name, color, rough=0.6, alpha=1.0):
    o.data.materials.append(material(name, color, rough, alpha))
    return o


# --- The backwards cap ------------------------------------------------------------------------

CAP_SHAPE = Shape(ax=0.089, cf=0.114, cb=0.128, cy=0.05, b=0.107, p=2.2, pv=2.3, tuck=0.05, zc=-0.004)
# Its edge (deg from the front: y). Worn backwards, the cap's back is on the forehead: the
# half-moon opening over the strap in the middle, then round and down to the nape, where
# the bill is.
CAP_RIM = [(0, 0.101), (13, 0.099), (23, 0.083), (40, 0.076), (70, 0.064), (100, 0.054), (140, 0.045), (180, 0.041)]
CAP_STRAP = (26.0, 0.081)        # the strap across the opening: how far round it reaches, its height
CAP_BILL = (62.0, 0.078, 0.2)    # the bill: how far round its root reaches from the back, its length, its droop
CAP_SEAMS = (0.0, 60.0, 120.0, 180.0, 240.0, 300.0)


def _cap_rim(a):
    return keyed(CAP_RIM, a)


def build_cap(offset=Vector()):
    sh = CAP_SHAPE
    crown = new_object("hat_cap_crown", lambda bm: shell_patch(bm, sh, _cap_rim, None, nu=72, nv=22), offset)
    solidify(crown, 0.003, bevel=0.0009)
    apply_all(crown)
    paint(crown, "CapCrown", (0.1, 0.6, 0.6))

    def accent(bm):
        # The bill: a stiff plate out from the edge at the back, straight back and a little
        # down, its outline a blunt curve, bowed across (the middle higher than the corners).
        half, length, droop = CAP_BILL
        nu, nv = 28, 8
        rows = []
        for i in range(nu + 1):
            u = -1.0 + 2.0 * i / nu
            a = 180.0 + half * u
            root, n = surf_pt(sh, a, _cap_rim(a) + 0.003)
            reach = length * (1.0 - abs(u) ** 2.6) ** (1.0 / 2.6)
            bow = 0.011 * (1.0 - u * u)
            rows.append([root - n * 0.001 + Vector((0.0, -droop * reach * v + bow * v * (1.0 - 0.35 * v), -reach * v))
                         for v in (j / nv for j in range(nv + 1))])
        grid(bm, rows)
    bill = new_object("hat_cap_bill", accent, offset)
    solidify(bill, 0.004, bevel=0.0012)
    apply_all(bill)

    def details(bm):
        # The button on top, the six seams down from it, the strap across the opening.
        top = sh.profile(0.0, 0.1, 30)[-1]
        rounded_box(bm, top + Vector((0, 0.0025, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0)),
                    0.008, 0.008, 0.0035, segs=16, rings=6, p=2.2)
        for a in CAP_SEAMS:
            prof = sh.profile(a, _cap_rim(a) + 0.002, 22, 0.0006)
            wire(bm, prof, 0.0011, sides=4)
        half, y = CAP_STRAP
        pts, nrms = [], []
        for i in range(17):
            a = -half + 2 * half * i / 16
            q, n = surf_pt(sh, a, y, 0.0008)
            pts.append(q)
            nrms.append(n)
        strap_along(bm, pts, nrms, 0.013, 0.0022)
    det = new_object("hat_cap_details", details, offset)
    acc = join("hat_cap_accent", [bill, det])
    paint(acc, "CapAccent", (0.95, 0.4, 0.6))
    return {"crown": crown, "accent": acc}


# --- The shades ----------------------------------------------------------------------------------
#
# One surface wrapped round the front of the face: in plan a superellipse about the head's
# axis, SHADE_W wide and SHADE_F deep. The lens is a band of it across both eyes.

SHADE_W, SHADE_F, SHADE_P = 0.08, 0.1045, 2.6   # (5 to 8 mm off the brow and the bridge of the nose)
SHADE_A = 61.0                     # the lens reaches this far round to each side
SHADE_EAR = (0.0835, 0.03, -0.012)   # where an arm reaches the top of the ear, then hooks down behind it


def _shade_pt(a, y, out=0.0):
    s, c = math.sin(math.radians(a)), math.cos(math.radians(a))
    r = 1.0 / ((abs(s) / SHADE_W) ** SHADE_P + (abs(c) / SHADE_F) ** SHADE_P) ** (1.0 / SHADE_P) + out
    return Vector((s * r, y, c * r))


def _shade_top(a):
    return 0.047 - 0.009 * (abs(a) / SHADE_A) ** 2


def _shade_bottom(a):
    # (up over the nose in the middle, and up again toward the ends)
    return 0.007 + 0.017 * math.exp(-(a / 8.5) ** 2) + 0.012 * (abs(a) / SHADE_A) ** 3


def build_shades(offset=Vector()):
    def lens(bm):
        nu, nv = 44, 7
        rows = []
        for i in range(nu + 1):
            a = -SHADE_A + 2 * SHADE_A * i / nu
            y1, y0 = _shade_top(a) - 0.002, _shade_bottom(a)
            rows.append([_shade_pt(a, _lerp(y1, y0, j / nv)) for j in range(nv + 1)])
        grid(bm, rows)
    ln = new_object("hat_shades_lens", lens, offset)
    solidify(ln, 0.0022, bevel=0.0006)
    apply_all(ln)
    paint(ln, "ShadesLens", (0.1, 0.5, 0.6), 0.1)

    def frame(bm):
        # The brow bar along the top of the lens, and a thin rim under it.
        top = [_shade_pt(a, _shade_top(a), 0.0008) for a in (-SHADE_A + 2 * SHADE_A * i / 40 for i in range(41))]
        rings = []
        for i, q in enumerate(top):
            t = (top[min(i + 1, 40)] - top[max(i - 1, 0)]).normalized()
            n = Vector((q.x, 0.0, q.z)).normalized()
            rings.append(ring_pts(q, n, Vector((0, 1, 0)), 0.0032, 0.0036, 8, 2.6))
        tube(bm, rings)
        bot = [_shade_pt(a, _shade_bottom(a), 0.0006) for a in (-SHADE_A + 2 * SHADE_A * i / 40 for i in range(41))]
        wire(bm, bot, 0.0013, sides=5)
        # The arms: from each end of the bar back to the ear, then hooked down behind it.
        for s in (1.0, -1.0):
            end = _shade_pt(s * SHADE_A, _shade_top(SHADE_A) - 0.006, 0.0008)
            ear = Vector((s * SHADE_EAR[0], SHADE_EAR[1], SHADE_EAR[2]))
            ctrl = [end, end.lerp(ear, 0.5) + Vector((s * 0.002, 0.001, 0)), ear, ear + Vector((-s * 0.002, -0.014, -0.02))]
            pts = spline(ctrl, 18)
            rings = []
            for i, q in enumerate(pts):
                t = (pts[min(i + 1, 17)] - pts[max(i - 1, 0)]).normalized()
                side = Vector((s, 0, 0)) - t * t.x * s
                side.normalize()
                k = 1.0 - 0.45 * i / 17          # (heavy at the hinge, slim over the ear)
                rings.append(ring_pts(q, side, t.cross(side), 0.0016, 0.0052 * k, 8, 2.6))
            tube(bm, rings)
            # the end of the lens, closed off by the frame
            wire(bm, [_shade_pt(s * SHADE_A, _lerp(_shade_top(SHADE_A), _shade_bottom(SHADE_A), j / 4), 0.0006) for j in range(5)],
                 0.0022, sides=6)
    fr = new_object("hat_shades_frame", frame, offset)
    paint(fr, "ShadesFrame", (0.04, 0.04, 0.045), 0.35)
    return {"frame": fr, "lens": ln}


# --- The cowboy hat ------------------------------------------------------------------------------

COW_Y0 = 0.071                     # where the crown meets the brim (on the forehead, over the ears)
COW_H = 0.108                      # the crown's sides, up to where the top rounds over
COW_PLAN = (0.087, 0.111, 0.124, 2.2, -0.004)   # the crown's foot: half width, front and back depth, exponent, axis z
COW_TAPER = 0.15                   # how much narrower the crown is at the top
COW_BRIM = (0.093, 0.084)          # the brim's width front and back / at the sides
COW_ROLL = 0.052                   # how far the brim's sides roll up at their edge
COW_DIP = 0.017                    # how far its front and back dip
COW_BAND = 0.021


def _cow_r(a):
    ax, cf, cb, p, _zc = COW_PLAN
    s, c = math.sin(math.radians(a)), math.cos(math.radians(a))
    cz = cf if c >= 0 else cb
    return 1.0 / ((abs(s) / ax) ** p + (abs(c) / cz) ** p) ** (1.0 / p)


def _cow_pt(a, r, y):
    return Vector((math.sin(math.radians(a)) * r, y, COW_PLAN[4] + math.cos(math.radians(a)) * r))


def _cow_crease(q):
    """The top of the crown pushed in: one crease down the middle from front to back,
    deepest toward the front, and a pinch either side of it at the front."""
    w = _smooth(COW_Y0 + COW_H * 0.72, COW_Y0 + COW_H + 0.012, q.y)
    if w <= 0.0:
        return q
    out = Vector(q)
    fr = _smooth(-0.06, 0.07, q.z)                               # toward the front
    out.y -= w * (0.02 + 0.016 * fr) * math.exp(-(q.x / 0.03) ** 2)
    pinch = w * _smooth(0.0, 0.08, q.z)
    out.x *= 1.0 - 0.2 * pinch
    out.y -= 0.012 * pinch * math.exp(-((abs(q.x) - 0.042) / 0.02) ** 2)
    return out


def build_cowboy(offset=Vector()):
    nu = 72
    az = [360.0 * i / nu - 180.0 for i in range(nu)]

    def crown(bm):
        # The profile: straight tapering sides, a rounded shoulder, a flat top (creased after).
        prof = [(1.0 - COW_TAPER * t, COW_Y0 + COW_H * t) for t in (k / 10 for k in range(11))]
        for k in range(1, 7):
            e = math.radians(90.0 * k / 6)
            prof.append((1.0 - COW_TAPER - 0.17 * (1 - math.cos(e)), COW_Y0 + COW_H + 0.017 * math.sin(e)))
        for k in range(1, 6):
            prof.append(((1.0 - COW_TAPER - 0.17) * (1 - k / 5.5), COW_Y0 + COW_H + 0.017))
        rings = [[_cow_crease(_cow_pt(a, _cow_r(a) * rs, y)) for a in az] for rs, y in prof]
        vs = ring_grid(bm, rings)
        top = bm.verts.new(g(*_cow_crease(_cow_pt(0.0, 0.0, prof[-1][1]))))
        for k in range(nu):
            f = bm.faces.new((vs[-1][k], vs[-1][(k + 1) % nu], top))
            f.smooth = True
    cr = new_object("hat_cowboy_crown", crown, offset)
    solidify(cr, 0.003, bevel=0.0)
    apply_all(cr)

    def brim(bm):
        nv = 12
        rings = []
        for j in range(nv + 1):
            t = j / nv
            ring = []
            for a in az:
                s, c = abs(math.sin(math.radians(a))), abs(math.cos(math.radians(a)))
                w = _lerp(COW_BRIM[1], COW_BRIM[0], c ** 2)
                y = COW_Y0 + COW_ROLL * s ** 2.4 * t ** 1.9 - COW_DIP * c ** 3 * t
                # (the rolled sides come in a little as they come up)
                ring.append(_cow_pt(a, _cow_r(a) - 0.002 + w * t * (1.0 - 0.1 * s ** 2.4 * t), y))
            rings.append(ring)
        ring_grid(bm, rings)
    br = new_object("hat_cowboy_brim", brim, offset)
    solidify(br, 0.0036, bevel=0.0012)
    apply_all(br)
    felt = join("hat_cowboy_felt", [cr, br])
    paint(felt, "CowboyFelt", (0.72, 0.6, 0.42), 0.85)

    def band(bm):
        rings = []
        for k in range(5):
            y = COW_Y0 + 0.003 + COW_BAND * k / 4
            rs = 1.0 - COW_TAPER * (y - COW_Y0) / COW_H
            rings.append([_cow_pt(a, _cow_r(a) * rs + 0.0016, y) for a in az])
        ring_grid(bm, rings)
        # its buckle, on the left side
        q = _cow_pt(84.0, _cow_r(84.0) * (1.0 - COW_TAPER * 0.12) + 0.003, COW_Y0 + 0.003 + COW_BAND * 0.5)
        n = Vector((q.x, 0.0, q.z - COW_PLAN[4])).normalized()
        rounded_box(bm, q, n.cross(Vector((0, 1, 0))).normalized(), Vector((0, 1, 0)), n, 0.011, 0.0125, 0.0022, segs=14, rings=5)
    bd = new_object("hat_cowboy_band", band, offset)
    solidify(bd, 0.0016, bevel=0.0)
    apply_all(bd)
    paint(bd, "CowboyBand", (0.1, 0.25, 0.7), 0.6)
    return {"felt": felt, "band": bd}


# --- The stunt helmet ----------------------------------------------------------------------------

STUNT_SHAPE = Shape(ax=0.113, cf=0.129, cb=0.147, cy=0.06, b=0.107, p=2.1, pv=2.3, tuck=0.15, zc=-0.004,
                    tuck_back=0.08, tuck_y=0.03, pv_fb=2.1)
# Its edge (deg from the front: y): across the brow, down the side of the face in front of
# the ear to the jaw, then round under the ear and the back of the skull.
STUNT_RIM = [(0, 0.064), (30, 0.062), (43, 0.054), (50, 0.03), (54, -0.014), (58, -0.05), (66, -0.064), (95, -0.068),
             (135, -0.074), (180, -0.08)]
STUNT_PEAK = (40.0, 0.046, 0.3)    # the peak: how far round its root reaches, its length, its droop
STUNT_SNAPS = (-30.0, 0.0, 30.0)


def _stunt_rim(a):
    return keyed(STUNT_RIM, a)


def build_stunt(offset=Vector()):
    sh = STUNT_SHAPE
    shell = new_object("hat_stunt_shell", lambda bm: shell_patch(bm, sh, _stunt_rim, None, nu=96, nv=28), offset)
    solidify(shell, 0.004, bevel=0.0012)
    apply_all(shell)
    paint(shell, "StuntShell", (0.08, 0.08, 0.09), 0.25)

    def peak(bm):
        # The peak: a short stiff plate snapped on across the brow, out and a little down.
        half, length, droop = STUNT_PEAK
        nu, nv = 24, 6
        rows = []
        for i in range(nu + 1):
            u = -1.0 + 2.0 * i / nu
            a = half * u
            root, n = surf_pt(sh, a, _stunt_rim(a) + 0.012, 0.001)
            reach = length * (1.0 - abs(u) ** 2.4) ** (1.0 / 2.4)
            rows.append([root + Vector((0.0, -droop * reach * v + 0.006 * (1.0 - u * u) * v, reach * v)) for v in (j / nv for j in range(nv + 1))])
        grid(bm, rows)
    pk = new_object("hat_stunt_peak", peak, offset)
    solidify(pk, 0.0036, bevel=0.0012)
    apply_all(pk)

    def snaps(bm):
        for a in STUNT_SNAPS:
            q, n = surf_pt(sh, a, _stunt_rim(a) + 0.02, 0.001)
            screw(bm, q + n * 0.0012, n, r=0.0048, h=0.002)
        # ... and a band across the root of the peak, where it lies on the shell.
        half = STUNT_PEAK[0]
        pts, nrms = [], []
        for i in range(21):
            a = -half + 2 * half * i / 20
            q, n = surf_pt(sh, a, _stunt_rim(a) + 0.014, 0.0012)
            pts.append(q)
            nrms.append(n)
        strap_along(bm, pts, nrms, 0.016, 0.0024)
    sn = new_object("hat_stunt_snaps", snaps, offset)
    trim = join("hat_stunt_trim", [pk, sn])
    paint(trim, "StuntTrim", (0.92, 0.92, 0.9), 0.4)

    lin = new_object("hat_stunt_liner", lambda bm: shell_patch(
        bm, sh, lambda a: _stunt_rim(a) + 0.004, None, nu=64, nv=14, grow=-0.0042), offset)
    solidify(lin, 0.011, bevel=0.0)
    apply_all(lin)

    def dark(bm):
        # The rolled rubber edge all the way round, and the strap under the chin.
        rim, k = [], 128
        for i in range(k):
            a = 360.0 * i / k - 180.0
            q, nr = surf_pt(sh, a, _stunt_rim(a) + 0.001)
            rim.append((q - nr * 0.002, nr))
        rings = []
        for i, (q, nr) in enumerate(rim):
            t = (rim[(i + 1) % k][0] - rim[i - 1][0]).normalized()
            rings.append(ring_pts(q, nr, t.cross(nr).normalized(), 0.0034, 0.0036, 8))
        tube(bm, rings, closed=True)
        f, _ = side_pt(sh, 0.03, -0.05)
        f -= Vector((0.012, 0, 0))
        b, _ = side_pt(sh, -0.05, -0.06)
        b -= Vector((0.012, 0, 0))
        chin_strap(bm, f, b, Vector((0.09, -0.082, -0.004)),
                   [Vector((0.074, -0.1, 0.024)), Vector((0.046, -0.114, 0.05)), Vector((0.018, -0.116, 0.062))])
        chin_cup(bm, Vector((0.0, -0.112, 0.064)), size=(0.03, 0.02, 0.005))
    dk = join("hat_stunt_dark", [new_object("hat_stunt_edge", dark, offset), lin])
    paint(dk, "StuntDark", (0.05, 0.05, 0.06), 0.6)
    return {"shell": shell, "trim": trim, "dark": dk}


# --- The watch cap -------------------------------------------------------------------------------

WATCH_SHAPE = Shape(ax=0.086, cf=0.1085, cb=0.127, cy=0.054, b=0.099, p=2.4, pv=2.3, tuck=0.04, zc=-0.004)
# Its edge, the fold of the cuff: a level line tipped back, across the forehead, over the
# tops of the ears and lower round the back of the skull (its height at z = 0, its rise per
# meter toward the face: a plane, so the game can cut the hair along it, SkaterVisual.HATS).
WATCH_RIM = (0.048, 0.14)
WATCH_RIBS = 40                    # ribs round the cap
WATCH_RIB = 0.0025                 # how far a rib stands out of the knit
WATCH_CUFF = (0.04, 0.0056)        # the cuff: its height, how far its face stands off the crown
WATCH_STRIPE = (0.0135, 0.0265)    # the stripe round the cuff: from and to, above the fold


def _watch_rim(a):
    sh = WATCH_SHAPE
    return WATCH_RIM[0] + WATCH_RIM[1] * (sh.zc + math.cos(math.radians(a)) * sh.rho(a))


def _profile_normals(prof, zc):
    """Outward normals along a Shape.profile (each in the profile's own vertical plane)."""
    out = []
    for i, q in enumerate(prof):
        tng = (prof[min(len(prof) - 1, i + 1)] - prof[max(0, i - 1)]).normalized()
        hor = Vector((q.x, 0.0, q.z - zc))
        hor = hor.normalized() if hor.length > 1e-6 else Vector((0, 0, 0))
        n = hor * tng.y - Vector((0, 1, 0)) * (tng.x * hor.x + tng.z * hor.z)
        out.append(n.normalized() if n.length > 1e-6 else Vector((0, 1, 0)))
    return out


def _profile_at(prof, nrm, y):
    """(point, normal) at height y on a profile (rising)."""
    for i in range(len(prof) - 1):
        if prof[i + 1].y >= y or i == len(prof) - 2:
            t = 0.0 if prof[i + 1].y == prof[i].y else (y - prof[i].y) / (prof[i + 1].y - prof[i].y)
            t = max(0.0, min(1.0, t))
            return prof[i].lerp(prof[i + 1], t), nrm[i].lerp(nrm[i + 1], t).normalized()
    return prof[-1], nrm[-1]


def _watch_rib(a):
    """A rib's height at azimuth a (0..1): round ridges, narrow grooves between them."""
    return abs(math.cos(math.radians(a) * WATCH_RIBS * 0.5)) ** 0.8


def flip(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def build_watch(offset=Vector()):
    sh = WATCH_SHAPE
    nu = WATCH_RIBS * 6
    az = [360.0 * i / nu - 180.0 for i in range(nu)]

    def crown(bm):
        # The knit: ribs from the cuff up over the crown, running out where they meet on top.
        nv = 20
        cols = []
        for a in az:
            prof = sh.profile(a, _watch_rim(a) + 0.002, nv)
            nrm = _profile_normals(prof, sh.zc)
            rib = _watch_rib(a)
            cols.append([prof[j] + nrm[j] * (WATCH_RIB * rib * _smooth(0.0, 0.3, 1.0 - j / nv)) for j in range(nv)])
        vs = ring_grid(bm, [[c[j] for c in cols] for j in range(nv)])
        top = bm.verts.new(g(*sh.profile(0.0, _watch_rim(0.0), nv)[-1]))
        for k in range(nu):
            f = bm.faces.new((vs[-1][k], vs[-1][(k + 1) % nu], top))
            f.smooth = True
    cr = new_object("hat_watch_crown", crown, offset)

    # The cuff, the knit folded back up on itself: round the fold at the bottom from the
    # inside, up its ribbed face, and in over its free edge to the crown.
    height, off = WATCH_CUFF
    s0, s1 = WATCH_STRIPE
    sec = [(-0.002, 0.003), (-0.0012, 0.0), (0.0006, -0.0016), (0.003, -0.002), (0.0048, -0.0008), (off, 0.002),
           (off, 0.006), (off, s0), (off, (s0 + s1) * 0.5), (off, s1), (off, height - 0.006),
           (off - 0.0002, height - 0.0025), (off - 0.0012, height - 0.0007), (off - 0.0028, height),
           (off - 0.0048, height - 0.0004), (-0.0006, height - 0.001)]
    rows = [[] for _ in sec]
    for a in az:
        yr = _watch_rim(a)
        prof = sh.profile(a, yr - 0.006, 70)
        nrm = _profile_normals(prof, sh.zc)
        rib = _watch_rib(a)
        for k, (grow, dy) in enumerate(sec):
            q, n = _profile_at(prof, nrm, yr + dy)
            rows[k].append(q + n * (grow + WATCH_RIB * rib * _smooth(0.003, off - 0.0004, grow)))
    lo, hi = 7, 9      # (the stripe's rows in `sec`)
    cuff = new_object("hat_watch_cuff", lambda bm: (ring_grid(bm, rows[:lo + 1]), ring_grid(bm, rows[hi:])), offset)
    stripe = new_object("hat_watch_stripe", lambda bm: ring_grid(bm, rows[lo:hi + 1]), offset)

    # The inside, plain, for when the cap lies on the ice.
    lin = flip(new_object("hat_watch_lining", lambda bm: shell_patch(
        bm, sh, lambda a: _watch_rim(a) + 0.003, None, nu=48, nv=10, grow=-0.002), offset))
    knit = join("hat_watch_knit", [cr, cuff, lin])
    paint(knit, "WatchKnit", (0.76, 0.09, 0.13), 0.95)
    paint(stripe, "WatchStripe", (0.95, 0.95, 0.93), 0.95)
    return {"knit": knit, "stripe": stripe}


def build_watch_only(do_export=False):
    """The watch cap alone, on a head beyond the cowboy hat."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_watch"):
            bpy.data.objects.remove(o, do_unlink=True)
    watch = build_watch(head_offset() + g(1.0, 0.0, 0.0))
    print("clearance over the head (mm): watch cap %s" % clearance(watch["knit"], above=0.07))
    if do_export:
        export(watch, "hat_watch.glb", WATCH_ROLES)
    return watch


# --- The pom beanie --------------------------------------------------------------------------------

BEANIE_SHAPE = Shape(ax=0.088, cf=0.1095, cb=0.128, cy=0.05, b=0.116, p=2.4, pv=1.95, tuck=0.1, zc=-0.004,
                     tuck_back=0.45)
BEANIE_RIM = (0.024, 0.27)         # its edge, a plane as the watch cap's: lower, down over the ears
BEANIE_RIBS = 48
BEANIE_RIB = 0.002
BEANIE_CUFF = (0.046, 0.006)       # the cuff: its height, how far its face stands off the crown
BEANIE_ROWS = 26                   # rows of the crown from the edge to the top ...
BEANIE_STRIPES = ((8, 10), (12, 14))   # ... and the rows the two stripes round it lie between
BEANIE_EAR = (0.026, -0.026, 0.0085)   # the knit pushed out over each ear: its height, its z, how far
BEANIE_POM = (0.031, 0.02)         # the pom: its radius, how far its center stands over the top


def _beanie_rim(a):
    sh = BEANIE_SHAPE
    return BEANIE_RIM[0] + BEANIE_RIM[1] * (sh.zc + math.cos(math.radians(a)) * sh.rho(a))


def _beanie_ear(q):
    """How far the knit is pushed out at q by the ear under it."""
    y0, z0, out = BEANIE_EAR
    side = _smooth(0.03, 0.07, abs(q.x))
    return out * side * math.exp(-((q.y - y0) / 0.024) ** 2) * math.exp(-((q.z - z0) / 0.03) ** 2)


def _rib(a, ribs):
    return abs(math.cos(math.radians(a) * ribs * 0.5)) ** 0.8


def _hash(*k):
    """A steady pseudo-random number in 0..1 from a few numbers."""
    x = math.sin(sum((i + 1) * 12.9898 * v for i, v in enumerate(k))) * 43758.5453
    return x - math.floor(x)


def build_beanie(offset=Vector()):
    sh = BEANIE_SHAPE
    nu = BEANIE_RIBS * 4
    nv = BEANIE_ROWS
    az = [360.0 * i / nu - 180.0 for i in range(nu)]

    # The crown: taller than the head, ribbed, coming to a soft top under the pom.
    cols = []
    for a in az:
        prof = sh.profile(a, _beanie_rim(a) + 0.002, nv)
        nrm = _profile_normals(prof, sh.zc)
        rib = _rib(a, BEANIE_RIBS)
        cols.append([prof[j] + nrm[j] * (BEANIE_RIB * rib * _smooth(0.0, 0.3, 1.0 - j / nv) + _beanie_ear(prof[j]))
                     for j in range(nv)])
    rings = [[c[j] for c in cols] for j in range(nv)]
    top = sh.profile(0.0, _beanie_rim(0.0), nv)[-1]
    (s0, s1), (s2, s3) = BEANIE_STRIPES

    def crown(bm):
        ring_grid(bm, rings[:s0 + 1])
        ring_grid(bm, rings[s1:s2 + 1])
        vs = ring_grid(bm, rings[s3:])
        pole = bm.verts.new(g(*top))
        for k in range(nu):
            f = bm.faces.new((vs[-1][k], vs[-1][(k + 1) % nu], pole))
            f.smooth = True
    cr = new_object("hat_beanie_crown", crown, offset)
    stripes = new_object("hat_beanie_stripes", lambda bm: (ring_grid(bm, rings[s0:s1 + 1]), ring_grid(bm, rings[s2:s3 + 1])), offset)

    # The cuff, folded back up as the watch cap's is.
    height, off = BEANIE_CUFF
    sec = [(-0.002, 0.003), (-0.0012, 0.0), (0.0006, -0.0016), (0.003, -0.002), (0.0052, -0.0008), (off, 0.002),
           (off, 0.008), (off, height * 0.35), (off, height * 0.65), (off, height - 0.007),
           (off - 0.0002, height - 0.003), (off - 0.0012, height - 0.0008), (off - 0.003, height),
           (off - 0.005, height - 0.0004), (-0.0006, height - 0.001)]
    rows = [[] for _ in sec]
    for a in az:
        yr = _beanie_rim(a)
        prof = sh.profile(a, yr - 0.006, 70)
        nrm = _profile_normals(prof, sh.zc)
        rib = _rib(a, BEANIE_RIBS)
        for k, (grow, dy) in enumerate(sec):
            q, n = _profile_at(prof, nrm, yr + dy)
            rows[k].append(q + n * (grow + BEANIE_RIB * rib * _smooth(0.003, off - 0.0004, grow) + _beanie_ear(q)))
    cuff = new_object("hat_beanie_cuff", lambda bm: ring_grid(bm, rows), offset)

    # The pom: a ball of yarn ends, each tuft a little longer or shorter than the next.
    def pom(bm):
        r, up = BEANIE_POM
        c = top + Vector((0.0, up, 0.0))
        made = bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
        for v in made["verts"]:
            d = Vector((v.co.x, v.co.z, -v.co.y)).normalized()      # (a game direction)
            k = 0.86 + 0.2 * _hash(round(d.x * 7.0), round(d.y * 7.0), round(d.z * 7.0)) + 0.06 * _hash(d.x, d.y, d.z)
            v.co = g(*(c + d * (r * k)))
        for f in bm.faces:
            f.smooth = True
    pm = new_object("hat_beanie_pom", pom, offset)

    lin = flip(new_object("hat_beanie_lining", lambda bm: shell_patch(
        bm, sh, lambda a: _beanie_rim(a) + 0.003, None, nu=48, nv=10, grow=-0.002), offset))
    knit = join("hat_beanie_knit", [cr, cuff, lin])
    paint(knit, "BeanieKnit", (0.1, 0.25, 0.6), 0.95)
    accent = join("hat_beanie_accent", [stripes, pm])
    paint(accent, "BeanieAccent", (0.95, 0.8, 0.2), 0.95)
    return {"knit": knit, "accent": accent}


def build_beanie_only(do_export=False):
    """The pom beanie alone, on a head beyond the watch cap's."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_beanie"):
            bpy.data.objects.remove(o, do_unlink=True)
    beanie = build_beanie(head_offset() + g(1.5, 0.0, 0.0))
    print("clearance over the head (mm): beanie %s" % clearance(beanie["knit"], above=0.07))
    if do_export:
        export(beanie, "hat_beanie.glb", BEANIE_ROLES)
    return beanie


# --- The leather helmet ----------------------------------------------------------------------------

LEATHER_SHAPE = Shape(ax=0.103, cf=0.119, cb=0.138, cy=0.055, b=0.103, p=2.2, pv=2.15, tuck=0.5, zc=-0.004,
                      tuck_back=0.5, tuck_y=0.03)
# Its edge (deg from the front: y): across the brow, down in front of the ear, the flap's
# round bottom under the ear, up again behind it and level round the back of the skull, well above the flaps.
LEATHER_RIM = [(0, 0.07), (35, 0.068), (47, 0.058), (54, 0.02), (60, -0.03), (70, -0.056), (88, -0.062),
               (106, -0.056), (119, -0.032), (131, -0.002), (150, 0.005), (180, 0.003)]
# The padded band round the head (deg: its lower edge), and its height.
LEATHER_BAND = ([(0, 0.07), (47, 0.066), (70, 0.058), (120, 0.048), (180, 0.044)], 0.026)
LEATHER_STRAPS = (0.0, 60.0, 120.0, 180.0, -120.0, -60.0)   # the padded straps over the crown
LEATHER_EAR = (90.0, -0.012, 0.0115)   # the ear holes on a flap: where (deg, y), how far apart


def _leather_rim(a):
    return keyed(LEATHER_RIM, a)


def _leather_band(a):
    return keyed(LEATHER_BAND[0], a)


def build_leather(offset=Vector()):
    sh = LEATHER_SHAPE
    shell = new_object("hat_leather_shell", lambda bm: shell_patch(bm, sh, _leather_rim, None, nu=96, nv=24), offset)
    solidify(shell, 0.0045, bevel=0.0012)
    apply_all(shell)
    paint(shell, "LeatherShell", (0.5, 0.32, 0.17), 0.55)

    # The padding, in a darker hide: a band round the head, straps from it up over the
    # crown to a round patch on top.
    band = new_object("hat_leather_band", lambda bm: band_patch(
        bm, sh, -180.0, 180.0, _leather_band, lambda a: _leather_band(a) + LEATHER_BAND[1], nu=96, nv=4, grow=0.004), offset)
    solidify(band, 0.0045, bevel=0.0014)
    apply_all(band)

    def straps(bm):
        for a in LEATHER_STRAPS:
            prof = sh.profile(a, _leather_band(a) + LEATHER_BAND[1] - 0.004, 20, 0.0022)
            nrm = _profile_normals(prof, sh.zc)
            strap_along(bm, prof[:-1], nrm[:-1], 0.023, 0.0056, segs=8)
        top = sh.profile(0.0, 0.1, 30)[-1]
        rounded_box(bm, top + Vector((0, 0.002, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0)),
                    0.027, 0.03, 0.0052, segs=24, rings=6, p=2.0)
        # The binding round the edge.
        rim, k = [], 108
        for i in range(k):
            a = 360.0 * i / k - 180.0
            q, nr = surf_pt(sh, a, _leather_rim(a) + 0.001)
            rim.append((q - nr * 0.0022, nr))
        rings = []
        for i, (q, nr) in enumerate(rim):
            t = (rim[(i + 1) % k][0] - rim[i - 1][0]).normalized()
            rings.append(ring_pts(q, nr, t.cross(nr).normalized(), 0.0034, 0.0034, 6))
        tube(bm, rings, closed=True)
        # The chin strap, buckled on the left: from the flaps down under the chin.
        f, _ = side_pt(sh, 0.012, -0.056)
        f -= Vector((0.006, 0, 0))
        b, _ = side_pt(sh, -0.026, -0.056)
        b -= Vector((0.006, 0, 0))
        chin_strap(bm, f, b, Vector((0.078, -0.082, 0.002)),
                   [Vector((0.066, -0.1, 0.026)), Vector((0.044, -0.114, 0.05)), Vector((0.018, -0.118, 0.062))], width=0.013)
    st = new_object("hat_leather_straps", straps, offset)
    trim = join("hat_leather_trim", [band, st])
    paint(trim, "LeatherStraps", (0.3, 0.18, 0.09), 0.5)

    def dark(bm):
        # The ear holes: five punched in each flap, one in the middle and four round it.
        a0, y0, gap = LEATHER_EAR
        for s in (1.0, -1.0):
            for da, dy in ((0.0, 0.0), (1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)):
                q, n = surf_pt(sh, s * (a0 + da * math.degrees(gap / sh.rho(a0))), y0 + dy * gap, 0.0003)
                screw(bm, q, n, r=0.0038, h=0.0008)
    dk = new_object("hat_leather_dark", dark, offset)
    paint(dk, "LeatherDark", (0.05, 0.035, 0.03), 0.7)
    return {"leather": shell, "straps": trim, "dark": dk}


def build_leather_only(do_export=False):
    """The leather helmet alone, on a head beyond the beanie's."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_leather"):
            bpy.data.objects.remove(o, do_unlink=True)
    leather = build_leather(head_offset() + g(2.0, 0.0, 0.0))
    print("clearance over the head (mm): leather helmet %s" % clearance(leather["leather"], above=-0.01))
    if do_export:
        export(leather, "hat_leather.glb", LEATHER_ROLES)
    return leather


# --- The leather head guard (the hockey one) -------------------------------------------------------

GUARD_SHAPE = Shape(ax=0.09, cf=0.111, cb=0.13, cy=0.05, b=0.1, p=2.3, pv=2.2, tuck=0.12, zc=-0.004,
                    tuck_y=0.03)
# The band's lower edge: a plane (its height at z = 0, its rise per meter toward the face),
# across the brow and well up the back of the skull, so the game can cut the hair along it
# and leave it showing below (SkaterVisual.HATS `edge`); the band's height above it.
GUARD_RIM = (0.052, 0.12)
GUARD_BAND = 0.046
GUARD_STAND = 0.35                 # how far the band stands straighter than the skull (0 on it, 1 a plain hoop)
# The tab down over each ear: where (deg), how far round it reaches to each side, how deep.
GUARD_TAB = (93.0, 23.0, 0.062)
GUARD_TAB_OUT = 0.008              # how far a tab stands out over the ear
GUARD_STRAPS = (0.0, 90.0, 180.0, -90.0)   # the cross of straps over the crown
GUARD_STRAP_W = 0.036
GUARD_STRAP_UP = 0.0075            # how far the straps' middle stands off the shape: room for the hair under them


def _guard_plane(a):
    sh = GUARD_SHAPE
    return GUARD_RIM[0] + GUARD_RIM[1] * (sh.zc + math.cos(math.radians(a)) * sh.rho(a))


def _guard_tab(a):
    """0..1: how far the ear tab hangs toward azimuth a (a round-bottomed flap)."""
    at, half, _ = GUARD_TAB
    t = abs(abs(wrap_deg(a)) - at) / half
    return (1.0 - t ** 2.2) ** (1.0 / 1.5) if t < 1.0 else 0.0


def _guard_rim(a):
    return _guard_plane(a) - GUARD_TAB[2] * _guard_tab(a)


def _guard_col(a, nv, grow):
    """A column of the band toward azimuth a, from its lower edge (the tab's, by an ear) to
    its upper: on the skull up to the plane of its edge, then straighter than the skull,
    so its top stands off the crown as a hoop of stiff leather does."""
    sh = GUARD_SHAPE
    lo, y0 = _guard_rim(a), _guard_plane(a)
    prof = sh.profile(a, lo, nv, grow, y0 + GUARD_BAND)
    d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
    hoop = Vector((surf_pt(sh, a, y0, grow)[0].x, 0.0, surf_pt(sh, a, y0, grow)[0].z - sh.zc)).length
    out = []
    for q in prof:
        h = Vector((q.x, 0.0, q.z - sh.zc)).length
        if q.y > y0:
            h += (hoop - h) * GUARD_STAND
        # (the tab stands out over the ear, which came through it lying on the skull)
        h += GUARD_TAB_OUT * _guard_tab(a) * (1.0 - _smooth(y0 - 0.012, y0 + 0.02, q.y))
        out.append(Vector((d.x * h, q.y, sh.zc + d.z * h)))
    return out


def build_guard(offset=Vector()):
    """A leather head guard as hockey players wore: a broad band of stiff leather round the
    head with a tab down over each ear, lined and padded with felt, a cross of padded
    leather straps over the top of the head, open between them (the hair shows through),
    and a thin chin strap."""
    sh = GUARD_SHAPE
    nu, nv = 96, 9
    az = [360.0 * i / nu - 180.0 for i in range(nu)]
    cols = [_guard_col(a, nv, 0.004) for a in az]
    rows = [[c[j] for c in cols] for j in range(nv + 1)]
    band = new_object("hat_guard_band", lambda bm: ring_grid(bm, rows), offset)
    solidify(band, 0.005, bevel=0.0014)
    apply_all(band)

    # The padding inside the band's top: a roll of felt from the leather in to the head, so
    # the band sits on the head all round and nothing shows down between them.
    lining = [_guard_col(a, nv, -0.0012) for a in az]
    pad = []
    for a, col in zip(az, lining):
        d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
        outer = col[-1]
        inner = on_head(outer - d * 0.03, 0.0015)[0] if head_bvh() is not None else outer - d * 0.008
        inner = Vector((inner.x, outer.y, inner.z))
        gap = max((outer - inner).dot(d), 0.004)
        pad.append((outer - d * (gap * 0.5) + Vector((0.0, -0.0035, 0.0)), d, gap * 0.5 + 0.0015))

    def straps(bm):
        for a in GUARD_STRAPS:
            # Each strap stands on the padding inside the band's top and comes in onto the
            # line of the skull over its first few points. (Run down behind the band
            # instead, it came through the band's face at the sides and the back.)
            k = az.index(min(az, key=lambda q: abs(wrap_deg(q - a))))
            foot = pad[k][0] + Vector((0.0, 0.0045, 0.0))
            prof = sh.profile(a, foot.y, 26, GUARD_STRAP_UP)
            nrm = _profile_normals(prof, sh.zc)
            d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
            out = (foot - prof[0]).dot(d)
            pts = [q + d * (out * (1.0 - _smooth(0.0, 7.0, i))) for i, q in enumerate(prof)]
            strap_along(bm, pts[:-1], nrm[:-1], GUARD_STRAP_W, 0.0085, segs=10)
        top = sh.profile(0.0, 0.1, 30)[-1]
        rounded_box(bm, top + Vector((0, GUARD_STRAP_UP + 0.0005, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0)),
                    0.031, 0.031, 0.0065, segs=24, rings=6, p=3.0)
    st = new_object("hat_guard_straps", straps, offset)
    leather = join("hat_guard_leather", [band, st])
    paint(leather, "GuardLeather", (0.44, 0.23, 0.13), 0.55)

    # The felt: the band's lining, the padding inside its top, a roll of it under the
    # band's lower edge, and the stitching along both edges.
    lrows = [[c[j] for c in lining] for j in range(nv + 1)]
    liner = new_object("hat_guard_liner", lambda bm: ring_grid(bm, lrows), offset)
    solidify(liner, 0.002, bevel=0.0)
    apply_all(liner)

    def felt(bm):
        def loop(pts, ru, rv, segs=6):
            rings = []
            for i, (q, out) in enumerate(pts):
                t = (pts[(i + 1) % len(pts)][0] - pts[i - 1][0]).normalized()
                rings.append(ring_pts(q, out, t.cross(out).normalized(), ru, rv, segs))
            tube(bm, rings, closed=True)
        low, seams = [], [[], []]
        for a, col in zip(az, cols):
            q, nr = surf_pt(sh, a, _guard_rim(a) - 0.0008, 0.0012)
            low.append((q, nr))
            # (the stitching a set distance inside each edge: taken at a row of the band,
            # it jogged where the tabs make the columns longer)
            for k, y in enumerate((_guard_rim(a) + 0.0065, col[-1].y - 0.0065)):
                j = next((i for i in range(nv) if col[i + 1].y >= y), nv - 1)
                q = col[j].lerp(col[j + 1], max(0.0, min(1.0, (y - col[j].y) / max(col[j + 1].y - col[j].y, 1e-9))))
                nr2 = (q - Vector((0.0, q.y, sh.zc))).normalized()
                seams[k].append((q + nr2 * 0.0004, nr2))
        rings = []
        for i, (q, d, r) in enumerate(pad):
            t = (pad[(i + 1) % nu][0] - pad[i - 1][0]).normalized()
            rings.append(ring_pts(q, d, t.cross(d).normalized(), r, 0.0055, 8))
        tube(bm, rings, closed=True)
        loop(low, 0.003, 0.003)
        for s in seams:
            loop(s, 0.0011, 0.0011, 4)
    ft = new_object("hat_guard_felt_trim", felt, offset)
    felt_obj = join("hat_guard_felt", [liner, ft])
    paint(felt_obj, "GuardFelt", (0.85, 0.79, 0.64), 0.95)

    def dark(bm):
        # A rivet in each tab, and the chin strap from the tabs, buckled on the left.
        at, _, deep = GUARD_TAB
        for s in (1.0, -1.0):
            col = _guard_col(s * at, 40, 0.0044)   # (on the tab's own face, which stands off the shape)
            q = min(col, key=lambda c: abs(c.y - (_guard_plane(at) - deep + 0.02)))
            screw(bm, q, Vector((q.x, 0.0, q.z - sh.zc)).normalized(), r=0.0036, h=0.0012)
        y = _guard_plane(at) - deep + 0.008
        f, _ = side_pt(sh, 0.006, y)
        f -= Vector((0.004, 0, 0))
        b, _ = side_pt(sh, -0.018, y)
        b -= Vector((0.004, 0, 0))
        chin_strap(bm, f, b, Vector((0.078, -0.07, 0.0)),
                   [Vector((0.066, -0.098, 0.026)), Vector((0.044, -0.114, 0.05)), Vector((0.018, -0.118, 0.062))], width=0.011)
    dk = new_object("hat_guard_dark", dark, offset)
    paint(dk, "GuardDark", (0.2, 0.12, 0.07), 0.55)
    return {"leather": leather, "felt": felt_obj, "dark": dk}


def build_guard_only(do_export=False):
    """The head guard alone, on a head beyond the golf visor's."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_guard"):
            bpy.data.objects.remove(o, do_unlink=True)
    guard = build_guard(head_offset() + g(3.0, 0.0, 0.0))
    print("clearance over the head (mm): head guard %s" % clearance(guard["leather"], above=0.07))
    if do_export:
        export(guard, "hat_guard.glb", GUARD_ROLES)
    return guard


# --- The golf visor --------------------------------------------------------------------------------

GOLF_SHAPE = Shape(ax=0.086, cf=0.1085, cb=0.127, cy=0.054, b=0.099, p=2.4, pv=2.3, tuck=0.04, zc=-0.004)
# The band's two edges, each a plane as the watch cap's edge is (its height at z = 0, its
# rise per meter toward the face), so the game can cut the hair out between them and leave
# it above (SkaterVisual.HATS `edge` and `open`): the lower across the forehead and over the
# tops of the ears, the upper steeper, so the band is a tall panel in front and a strap behind.
GOLF_RIM = (0.055, 0.12)
GOLF_TOP = (0.092, 0.238)
GOLF_STAND = 0.007                # how far the top of the front panel stands off the forehead
GOLF_BILL = (60.0, 0.074, 0.38)   # the bill: how far round its root reaches, its length, its droop
GOLF_TAB = (24.0, 0.0125)         # the closing tab at the back: how far round it reaches, its width


def _golf_edge(plane, a, out=0.0):
    """The height at which a plane (GOLF_RIM, GOLF_TOP) meets the band toward azimuth a,
    the band standing `out` off the shape there."""
    sh = GOLF_SHAPE
    c = math.cos(math.radians(a))
    y = plane[0] + plane[1] * (sh.zc + c * sh.rho(a))
    for _ in range(4):
        q, _n = surf_pt(sh, a, y)
        y = plane[0] + plane[1] * (q.z + c * out)
    return y


def _golf_stiff(a):
    """1 across the stiffened front panel, 0 round the sides and the back."""
    return 1.0 - _smooth(35.0, 80.0, abs(wrap_deg(a)))


def _golf_col(a, nv, grow):
    """A column of the band toward azimuth a, from its lower edge to its upper: on the
    head round the sides and back, standing straighter than the forehead in front."""
    sh = GOLF_SHAPE
    d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
    stand = GOLF_STAND * _golf_stiff(a)
    lo = _golf_edge(GOLF_RIM, a, grow)
    hi = _golf_edge(GOLF_TOP, a, grow + stand)
    prof = sh.profile(a, lo, nv, grow, hi)
    return [q + d * (stand * (j / nv) ** 1.6) for j, q in enumerate(prof)]


def build_golf(offset=Vector()):
    sh = GOLF_SHAPE
    nu, nv = 96, 5
    az = [360.0 * i / nu - 180.0 for i in range(nu)]
    cols = [_golf_col(a, nv, 0.003) for a in az]
    rows = [[c[j] for c in cols] for j in range(nv + 1)]
    band = new_object("hat_golf_band", lambda bm: ring_grid(bm, rows), offset)
    solidify(band, 0.003, bevel=0.0008)
    apply_all(band)
    paint(band, "GolfBand", (0.42, 0.67, 0.87), 0.85)

    # The bill: a stiff see-through plate out from the foot of the front panel, forward and
    # a little down, its outline a blunt curve, bowed across (the middle higher than the corners).
    half, length, droop = GOLF_BILL
    bu, bv = 32, 8
    plate = []
    for i in range(bu + 1):
        u = -1.0 + 2.0 * i / bu
        a = half * u
        root = _golf_col(a, nv, 0.003)[0] + Vector((0.0, 0.004, 0.0))
        reach = length * (1.0 - abs(u) ** 2.4) ** (1.0 / 2.4)
        bow = 0.012 * (1.0 - u * u)
        plate.append([root + Vector((0.0, -droop * reach * v + bow * v * (1.0 - 0.4 * v), reach * v))
                      for v in (j / bv for j in range(bv + 1))])
    bill = new_object("hat_golf_brim", lambda bm: grid(bm, plate), offset)
    solidify(bill, 0.0026, bevel=0.0008)
    apply_all(bill)
    paint(bill, "GolfBrim", (0.72, 0.45, 0.12), 0.15, 0.6)

    def trim(bm):
        # Piping round the band's two edges and a binding round the bill's.
        for row in (rows[0], rows[-1]):
            rings = []
            for i, q in enumerate(row):
                t = (row[(i + 1) % nu] - row[i - 1]).normalized()
                out = Vector((q.x, 0.0, q.z - sh.zc)).normalized()
                rings.append(ring_pts(q - out * 0.0012, out, t.cross(out).normalized(), 0.0019, 0.0019, 6))
            tube(bm, rings, closed=True)
        edge = [r[-1] + Vector((0.0, -0.0013, 0.0)) for r in plate]
        rings = []
        for i, q in enumerate(edge):
            t = (edge[min(i + 1, bu)] - edge[max(i - 1, 0)]).normalized()
            up = Vector((0.0, 1.0, 0.0))
            rings.append(ring_pts(q, up, t.cross(up).normalized(), 0.0021, 0.0021, 6))
        tube(bm, rings)
        # The closing tab over the strap at the back.
        half_t, width = GOLF_TAB
        pts, nrms = [], []
        for i in range(13):
            a = 180.0 - half_t * 0.4 + half_t * 1.4 * i / 12
            col = _golf_col(a, nv, 0.0036)
            q = col[0].lerp(col[-1], 0.5)
            pts.append(q)
            nrms.append(Vector((q.x, 0.0, q.z - sh.zc)).normalized())
        strap_along(bm, pts, nrms, width, 0.0022, segs=8)
    tr = new_object("hat_golf_trim", trim, offset)
    paint(tr, "GolfTrim", (0.72, 0.45, 0.12), 0.7)
    return {"band": band, "brim": bill, "trim": tr}


def build_golf_only(do_export=False):
    """The golf visor alone, on a head beyond the leather helmet's."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_golf"):
            bpy.data.objects.remove(o, do_unlink=True)
    golf = build_golf(head_offset() + g(2.5, 0.0, 0.0))
    print("clearance over the head (mm): golf visor %s" % clearance(golf["band"], above=0.03))
    if do_export:
        export(golf, "hat_golf.glb", GOLF_ROLES)
    return golf


# --- Checks and export -----------------------------------------------------------------------------

def clearance(obj, above=0.03):
    """How close the head comes to a hat's inside, and whether it comes through (mm): the
    least distance from the head's surface (above `above` in the frame) out to the hat."""
    bvh = head_bvh()
    if bvh is None:
        return None
    hat = BVHTree.FromPolygons([gv(obj.matrix_world @ v.co - obj.location) for v in obj.data.vertices],
                               [tuple(p.vertices) for p in obj.data.polygons])
    c = Vector((0.0, 0.04, -0.004))
    worst = 1e9
    for i in range(0, 360, 6):
        for el in range(0, 90, 6):
            d = Vector((math.sin(math.radians(i)) * math.cos(math.radians(el)), math.sin(math.radians(el)),
                        math.cos(math.radians(i)) * math.cos(math.radians(el))))
            h = bvh.ray_cast(c + d * 0.5, -d, 0.6)
            t = hat.ray_cast(c, d, 0.6)
            if h[0] is None or t[0] is None or h[0].y < above:
                continue
            worst = min(worst, (t[0] - c).length - (h[0] - c).length)
    return round(worst * 1000, 1)


CAP_ROLES = ["crown", "accent"]
SHADES_ROLES = ["frame", "lens"]
COWBOY_ROLES = ["felt", "band"]
STUNT_ROLES = ["shell", "trim", "dark"]
WATCH_ROLES = ["knit", "stripe"]
BEANIE_ROLES = ["knit", "accent"]
LEATHER_ROLES = ["leather", "straps", "dark"]
GOLF_ROLES = ["band", "brim", "trim"]
GUARD_ROLES = ["leather", "felt", "dark"]


def build_all(do_export=False):
    """The cap with its shades on the head where it stands, the cowboy hat on a head beside it."""
    for o in list(bpy.data.objects):
        if o.name.startswith(("cut_", "hat_")):
            bpy.data.objects.remove(o, do_unlink=True)
    cap = build_cap(head_offset())
    shades = build_shades(head_offset())
    cowboy = build_cowboy(head_offset() + g(0.5, 0.0, 0.0))
    print("clearance over the head (mm): cap %s, cowboy %s" % (clearance(cap["crown"]), clearance(cowboy["felt"])))
    if do_export:
        export(cap, "hat_cap.glb", CAP_ROLES)
        export(shades, "hat_shades.glb", SHADES_ROLES)
        export(cowboy, "hat_cowboy.glb", COWBOY_ROLES)
    stunt = build_stunt_only(do_export)
    watch = build_watch_only(do_export)
    beanie = build_beanie_only(do_export)
    leather = build_leather_only(do_export)
    golf = build_golf_only(do_export)
    guard = build_guard_only(do_export)
    return cap, shades, cowboy, stunt, watch, beanie, leather, golf, guard


def build_stunt_only(do_export=False):
    """The stunt helmet alone, on the head on the other side of the cap."""
    for o in list(bpy.data.objects):
        if o.name.startswith("hat_stunt"):
            bpy.data.objects.remove(o, do_unlink=True)
    stunt = build_stunt(head_offset() + g(-0.5, 0.0, 0.0))
    print("clearance over the head (mm): stunt %s" % clearance(stunt["dark"], above=-0.04))
    if do_export:
        export(stunt, "hat_stunt.glb", STUNT_ROLES)
    return stunt
