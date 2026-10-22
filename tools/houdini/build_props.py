"""Build Sandblood gore pieces, arena dressing and armor procedurally and export them as .glb.

Run:  hython scripts/build_props.py [--only=gore|dressing|armor|<piece id>,...] [--no-preview]

Conventions (meters, Y up):
- gore/: origin at the piece centre, glossy wet materials.
- dressing/: origin at the footprint centre on the ground, front faces +Z (like decor/).
- armor/: in the fighter part's local frame from build_body.py (origin = part centre, front = -Z), so a piece can be
  parented straight to its body part: galea -> head, manica -> forearm_r (manica_l mirrored), greave -> shin_r/l.
  The scutum follows the shield convention of build_weapons.py: grip at the origin, shield face toward +Z.
Reuses the geometry library and glb reader from build_weapons.py.
"""
import math
import os
import re
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "props.hip")
PREVIEW_ROOT = os.path.join(ROOT, "preview")

_WEAPONS_SRC = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_weapons.py"), encoding="utf-8").read()
LIB_BASE = re.search(r"LIB = r'''(.*?)'''", _WEAPONS_SRC, re.S).group(1)
_reader = re.search(r"(def read_glb\(path\):.*?)\n\n\n", _WEAPONS_SRC, re.S).group(1)
exec("import json, struct\n" + _reader)

# Body part physics boxes from build_body.py (part-local), for the armor fit check: (lo, hi).
BODY = {
    "head": ((-0.11, -0.11, -0.11), (0.11, 0.11, 0.11)),
    "forearm": ((-0.045, -0.17, -0.045), (0.045, 0.17, 0.045)),
    "shin": ((-0.05, -0.27, -0.185), (0.05, 0.21, 0.065)),
}

# id: (group, max tris, closed (volume check), preview yaw, body part for the fit check or None)
PIECES = {
    "gut_rope": ("gore", 600, False, 30, None),
    "gut_coil": ("gore", 600, True, 30, None),
    "gut_torn": ("gore", 600, True, 30, None),
    "gut_cluster": ("gore", 600, True, 30, None),
    "liver": ("gore", 600, True, 30, None),
    "stomach": ("gore", 600, True, 30, None),
    "heart": ("gore", 600, True, 30, None),
    "portcullis": ("dressing", 3000, True, 25, None),
    "weapon_rack": ("dressing", 3000, True, 30, None),
    "barrier": ("dressing", 3000, True, 30, None),
    "laurel_trophy": ("dressing", 3000, True, 25, None),
    "galea": ("armor", 2500, True, 210, "head"),
    "manica_r": ("armor", 2500, True, 210, "forearm"),
    "manica_l": ("armor", 2500, True, 150, "forearm"),
    "greave_r": ("armor", 2500, True, 210, "shin"),
    "greave_l": ("armor", 2500, True, 150, "shin"),
    "scutum": ("armor", 2500, True, 25, None),
}
ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
if ONLY:
    want = ONLY[0].split(",")
    PIECES = {k: v for k, v in PIECES.items() if k in want or v[0] in want}
MIRROR = {"manica_l": "manica_r", "greave_l": "greave_r"}  # built from the right piece, mirrored in X
RACK_SLOTS = 6

# name: (base colour, roughness, metallic[, emission colour, emission intensity])
MATERIALS = {
    "intestine": ((0.72, 0.3, 0.3), 0.18, 0.0),
    "gut_dark": ((0.45, 0.08, 0.09), 0.2, 0.0),
    "liver": ((0.32, 0.05, 0.05), 0.15, 0.0),
    "stomach": ((0.7, 0.36, 0.34), 0.2, 0.0),
    "heart": ((0.55, 0.06, 0.07), 0.16, 0.0),
    "fat": ((0.88, 0.76, 0.42), 0.3, 0.0),
    "vessel": ((0.35, 0.12, 0.25), 0.2, 0.0),
    "stone": ((0.66, 0.6, 0.5), 0.85, 0.0),
    "iron": ((0.28, 0.28, 0.30), 0.55, 1.0),
    "wood": ((0.42, 0.27, 0.14), 0.75, 0.0),
    "wood_wet": ((0.24, 0.15, 0.08), 0.6, 0.0),
    "sand": ((0.76, 0.6, 0.38), 0.95, 0.0),
    "gold": ((0.83, 0.62, 0.22), 0.3, 1.0),
    "laurel": ((0.3, 0.42, 0.16), 0.6, 0.0),
    "marble": ((0.86, 0.83, 0.77), 0.55, 0.0),
    "bronze": ((0.55, 0.37, 0.18), 0.4, 1.0),
    "crest": ((0.6, 0.05, 0.04), 0.85, 0.0),
    "leather": ((0.2, 0.1, 0.045), 0.7, 0.0),
    "scutum_red": ((0.5, 0.06, 0.04), 0.6, 0.0),
}

LIB = LIB_BASE + r'''
def vnorm(a):
    l = math.sqrt(dot(a, a)) or 1.0
    return [a[0] / l, a[1] / l, a[2] / l]

def vcross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

def hashn(a, b):
    return 0.6 * math.sin(3.1 * a + 7.3 * b) + 0.4 * math.sin(5.7 * a - 4.1 * b + 1.7)

def sweep_rings(path, rfn, segs):
    # Rings of `segs` points around a polyline with parallel-transport frames; rfn(i, s, a) -> radius.
    n = len(path)
    rings = []
    tan = [vnorm(sub(path[min(i + 1, n - 1)], path[max(i - 1, 0)])) for i in range(n)]
    ref = [0.0, 1.0, 0.0] if abs(tan[0][1]) < 0.9 else [1.0, 0.0, 0.0]
    u = vnorm(vcross(tan[0], ref))
    for i in range(n):
        u = vnorm(sub(u, [tan[i][k] * dot(u, tan[i]) for k in range(3)]))
        v = vcross(tan[i], u)
        s = i / (n - 1)
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            r = rfn(i, s, a)
            ring.append(tuple(path[i][k] + r * (math.cos(a) * u[k] + math.sin(a) * v[k]) for k in range(3)))
        rings.append(ring)
    return rings

def sweep(b, path, rfn, segs, mat, cap0=True, cap1=True):
    b.loft(sweep_rings(path, rfn, segs), mat, cap0, cap1)

def bar(b, p0, p1, r, mat, segs=6):
    sweep(b, [p0, p1], lambda i, s, a: r, segs, mat)

def blob(b, c, rx, ry, rz, mat, segs=10, steps=6, rough=0.0, seed=0.0):
    prof = sphere_prof(1.0, 0.0, steps)
    rings = []
    for r, h in prof:
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            k = 1.0 + rough * hashn(a + seed, h * 2.0 + seed)
            ring.append((c[0] + rx * r * k * math.cos(a), c[1] + ry * h, c[2] + rz * r * k * math.sin(a)))
        rings.append(ring)
    b.loft(rings, mat)

def bulge(i, s, a, r0=0.025, waves=3.0):
    return r0 * (1.0 + 0.15 * math.sin(2 * math.pi * waves * s) ** 2 + 0.04 * math.cos(3 * a))

# ---------------- gore ----------------
def build_gut_rope(b):
    # Tileable 0.3 m section along +Y: open ends with identical rings, three peristaltic bulges.
    path = [(0.0, -0.15 + 0.3 * k / 18, 0.0) for k in range(19)]
    sweep(b, path, lambda i, s, a: bulge(i, s, a), 12, "intestine", cap0=False, cap1=False)

def build_gut_coil(b):
    path = []
    for k in range(34):
        t = k / 33
        ang = t * 2.0 * 2 * math.pi
        rad = 0.11 - 0.05 * t
        path.append((rad * math.cos(ang), 0.02 * math.sin(ang * 1.5) + 0.04 * t - 0.02, rad * math.sin(ang)))
    sweep(b, path, lambda i, s, a: bulge(i, s, a, 0.022, 7.0), 8, "intestine")

def build_gut_torn(b):
    path = [(0.0, -0.1 + 0.2 * k / 10, 0.015 * math.sin(k * 0.6)) for k in range(11)]
    rings = sweep_rings(path, lambda i, s, a: bulge(i, s, a, 0.026, 1.5), 12)
    # Torn end: a ragged, flared lip, then a dark, sunken inner wound.
    c = path[-1]
    lip = []
    for j, p in enumerate(rings[-1]):
        a = 2 * math.pi * j / 12
        f = 1.25 + 0.2 * hashn(a * 2, 1.0)
        lip.append((c[0] + (p[0] - c[0]) * f, p[1] + 0.03 * (0.5 + 0.5 * math.sin(3 * a + 1)), c[2] + (p[2] - c[2]) * f))
    inner = [(c[0] + (p[0] - c[0]) * 0.6, p[1] - 0.004, c[2] + (p[2] - c[2]) * 0.6) for p in rings[-1]]
    b.loft(rings + [lip], ["intestine"] * (len(rings)), cap1=False)
    b.loft([lip, inner], "gut_dark", cap0=False)

def build_gut_cluster(b):
    for k, (cx, cy, cz, ph) in enumerate([(0.0, 0.0, 0.0, 0.0), (0.06, 0.035, -0.03, 1.7), (-0.05, 0.04, 0.04, 3.1)]):
        path = []
        for m in range(13):
            t = m / 12
            ang = t * 1.6 * 2 * math.pi + ph
            path.append((cx + 0.07 * math.cos(ang), cy + 0.015 * math.sin(3 * ang), cz + 0.06 * math.sin(ang)))
        sweep(b, path, lambda i, s, a: bulge(i, s, a, 0.023, 4.0), 6, "intestine")
    blob(b, (0.0, -0.015, 0.0), 0.08, 0.03, 0.07, "fat", segs=8, steps=4, rough=0.15)

def build_liver(b):
    # Two-lobed wedge: big right lobe, smaller left lobe, flat-ish underside.
    blob(b, (0.035, 0.0, 0.0), 0.1, 0.045, 0.07, "liver", segs=14, steps=8, rough=0.06)
    blob(b, (-0.07, 0.008, 0.01), 0.06, 0.03, 0.05, "liver", segs=12, steps=6, rough=0.06, seed=2.0)

def build_stomach(b):
    # J-shaped bag: wide fundus tapering through the body to the pylorus.
    path = []
    for k in range(13):
        t = k / 12
        ang = math.pi * (0.15 + 0.85 * t)
        path.append((0.08 * math.cos(ang), 0.07 * math.sin(ang) - 0.02, 0.0))
    def rfn(i, s, a):
        return (0.055 * (1 - s) + 0.018 * s) * (1.0 + 0.05 * hashn(a, s * 4.0)) * (0.85 if math.sin(a) > 0 else 1.0)
    sweep(b, path, rfn, 14, "stomach")

def build_heart(b):
    def rfn(a, h):
        return 1.0 + 0.08 * math.cos(a - 0.6) + 0.05 * hashn(a, h * 6.0)
    prof = [(0.004, -0.06), (0.022, -0.052), (0.038, -0.035), (0.05, -0.012), (0.056, 0.01), (0.054, 0.03),
            (0.044, 0.048), (0.026, 0.06), (0.004, 0.066)]
    lathe(b, prof, 14, "heart", sx=1.0, sz=0.85, rfn=rfn)
    # Aorta arch and two vessel stubs.
    sweep(b, [(0.005, 0.05, 0.0), (0.008, 0.085, -0.004), (-0.012, 0.1, -0.006), (-0.03, 0.092, -0.004)],
          lambda i, s, a: 0.013, 8, "vessel")
    bar(b, (-0.02, 0.05, 0.015), (-0.03, 0.082, 0.02), 0.009, "vessel")
    bar(b, (0.025, 0.045, 0.012), (0.04, 0.072, 0.016), 0.008, "vessel")

# ---------------- arena dressing ----------------
def build_portcullis(b):
    # Stone arch frame (opening 2.4 m wide, 3.2 m to the crown) with an iron grate let down into it.
    W, H, D = 1.2, 2.0, 0.35  # half opening, spring height, wall depth
    for sx in (-1, 1):
        box(b, (sx * W if sx > 0 else -W - 0.5, 0.0, -D), (sx * W + 0.5 if sx > 0 else -W, H, D), "stone")
    rings = []
    n = 16
    for k in range(n + 1):
        a = math.pi * k / n
        ci, co = (W * math.cos(a), H + W * math.sin(a)), ((W + 0.5) * math.cos(a), H + (W + 0.5) * math.sin(a))
        rings.append([(ci[0], ci[1], -D), (co[0], co[1], -D), (co[0], co[1], D), (ci[0], ci[1], D)])
    b.loft(rings, "stone")
    box(b, (-W - 0.6, H + W + 0.4, -D - 0.02), (W + 0.6, H + W + 0.7, D + 0.02), "stone")  # lintel course
    # Grate: verticals with spiked feet, crossbars; the arch top is cut by a stepped skyline.
    for i in range(9):
        x = -W + 0.12 + i * (2 * W - 0.24) / 8
        top = H + math.sqrt(max(W * W - x * x, 0.0)) - 0.05
        bar(b, (x, 0.15, 0.0), (x, top, 0.0), 0.022, "iron", segs=4)
        lathe(b, [(0.03, 0.15), (0.002, 0.0)], 4, "iron", c=(x, 0.0, 0.0))
    for y in (0.6, 1.3, 2.0, 2.7):
        half = min(W, math.sqrt(max(W * W - (y - H) ** 2, 0.0)) if y > H else W) - 0.04
        box(b, (-half, y - 0.03, -0.035), (half, y + 0.03, 0.035), "iron")

def build_weapon_rack(b):
    # Wooden rack: two uprights on feet, a top bar with six notches and a bottom butt rail. Slot empties are
    # separate null objects (slot_1..slot_6) placed where each weapon's grip sits.
    for sx in (-0.75, 0.75):
        box(b, (sx - 0.04, 0.0, -0.04), (sx + 0.04, 1.5, 0.04), "wood")
        box(b, (sx - 0.05, 0.0, -0.3), (sx + 0.05, 0.08, 0.3), "wood")
    box(b, (-0.8, 1.32, -0.06), (0.8, 1.42, 0.06), "wood")
    box(b, (-0.8, 0.18, -0.12), (0.8, 0.26, 0.0), "wood")
    for i in range(6):
        x = -0.55 + i * 0.22
        box(b, (x - 0.045, 1.42, -0.07), (x - 0.03, 1.5, 0.07), "wood")  # notch pegs
        box(b, (x + 0.03, 1.42, -0.07), (x + 0.045, 1.5, 0.07), "wood")
        box(b, (x - 0.06, 0.26, -0.11), (x + 0.06, 0.29, -0.01), "iron")  # butt cup

def build_barrier(b):
    # 2 m section: two posts, four horizontal planks; the lower planks are sand-soaked (dark), a sand berm at the foot.
    for sx in (-0.95, 0.95):
        box(b, (sx - 0.06, 0.0, -0.06), (sx + 0.06, 1.15, 0.06), "wood_wet")
        lathe(b, [(0.06, 1.15), (0.04, 1.2), (0.0, 1.21)], 6, "wood", c=(sx, 0.0, 0.0))
    for k, y in enumerate((0.12, 0.38, 0.64, 0.9)):
        mat = "wood_wet" if k < 2 else "wood"
        tilt = 0.012 * hashn(k, 0.3)
        box(b, (-1.0, y + tilt, 0.06), (1.0, y + 0.22 - tilt, 0.1), mat)
    rings = []
    for k in range(13):
        x = -1.05 + 2.1 * k / 12
        h = 0.12 + 0.05 * hashn(x * 3, 1.0)
        rings.append([(x, 0.0, 0.32), (x, h * 0.6, 0.22), (x, h, 0.12), (x, h * 0.8, 0.03), (x, 0.0, -0.02)])
    b.loft(rings, "sand")

def build_laurel_trophy(b):
    # Marble plinth, gold post and a gold-bound laurel wreath standing upright, facing +Z.
    box(b, (-0.22, 0.0, -0.16), (0.22, 0.08, 0.16), "marble")
    box(b, (-0.18, 0.08, -0.12), (0.18, 0.42, 0.12), "marble")
    box(b, (-0.2, 0.42, -0.14), (0.2, 0.46, 0.14), "marble")
    lathe(b, [(0.03, 0.46), (0.02, 0.5), (0.015, 0.62), (0.025, 0.66)], 10, "gold")
    cy, R = 0.86, 0.2
    ring_path = [(R * math.sin(2 * math.pi * k / 30 + 0.45), cy - R * math.cos(2 * math.pi * k / 30 + 0.45), 0.0)
                 for k in range(25)]
    sweep(b, ring_path, lambda i, s, a: 0.012, 6, "gold")
    for k in range(44):
        t = k / 43
        ang = 0.45 + t * (2 * math.pi * 24 / 30)
        side = 1 if k % 2 else -1
        c = (R * math.sin(ang), cy - R * math.cos(ang), 0.0)
        out = (math.sin(ang), -math.cos(ang), 0.0)
        tan = (math.cos(ang), math.sin(ang), 0.0)
        tip = [c[m] + 0.055 * tan[m] + side * 0.03 * out[m] for m in range(3)]
        mid = [c[m] + 0.03 * tan[m] + side * 0.02 * out[m] for m in range(3)]
        w = [-side * 0.012 * out[m] for m in range(3)]
        th = 0.004
        leaf = [[(c[0], c[1], c[2] - th), (c[0], c[1], c[2] + th)],
                [(mid[0] + w[0], mid[1] + w[1], mid[2] - th), (mid[0] + w[0], mid[1] + w[1], mid[2] + th)],
                [(tip[0], tip[1], tip[2] - th), (tip[0], tip[1], tip[2] + th)],
                [(mid[0] - w[0], mid[1] - w[1], mid[2] + th), (mid[0] - w[0], mid[1] - w[1], mid[2] - th)]]
        rings_l = [[leaf[0][0], leaf[1][0], leaf[2][0], leaf[3][1]], [leaf[0][1], leaf[1][1], leaf[2][1], leaf[3][0]]]
        b.loft(rings_l, "laurel")
    box(b, (-0.04, cy - R - 0.03, -0.015), (0.04, cy - R + 0.03, 0.015), "gold")  # binding knot

# ---------------- armor (part-local, front = -Z) ----------------
def build_galea(b):
    # Head centre at the origin, skull radius 0.11. Bowl clears it by about 1.5 cm.
    def bowl(a, h):
        return 1.0 + 0.04 * max(0.0, -math.sin(a))  # slightly deeper toward the back (+Z)
    lathe(b, [(0.128, -0.02), (0.13, 0.03), (0.122, 0.08), (0.1, 0.12), (0.06, 0.145), (0.004, 0.152)], 20, "bronze",
          sz=1.08, rfn=bowl)
    lathe(b, [(0.132, -0.025), (0.14, -0.02), (0.14, -0.005), (0.131, 0.0)], 20, "bronze", sz=1.08)  # brow band
    # Brow peak at the front (-Z) and a flared neck guard at the back (+Z).
    b.loft([[(-0.1, -0.005, -0.12), (0.1, -0.005, -0.12), (0.1, 0.005, -0.12), (-0.1, 0.005, -0.12)],
            [(-0.09, -0.0, -0.165), (0.09, -0.0, -0.165), (0.09, 0.006, -0.165), (-0.09, 0.006, -0.165)]], "bronze")
    rings = []
    for k in range(9):
        a = math.pi * (0.2 + 0.6 * k / 8)
        x, z = 0.14 * math.cos(a), 0.14 * 1.08 * math.sin(a)
        rings.append([(x, -0.02, z), (x * 1.0, -0.085, z * 1.0 + 0.05), (x * 1.0, -0.08, z * 1.0 + 0.06),
                      (x, -0.012, z + 0.012)])
    b.loft(rings, "bronze")
    # Cheek guards hinged at the temples.
    for sx in (-1, 1):
        b.loft([[(sx * 0.122, -0.01, -0.07), (sx * 0.13, -0.01, -0.07), (sx * 0.13, -0.01, 0.02), (sx * 0.122, -0.01, 0.02)],
                [(sx * 0.112, -0.1, -0.08), (sx * 0.12, -0.1, -0.08), (sx * 0.12, -0.1, 0.0), (sx * 0.112, -0.1, 0.0)],
                [(sx * 0.098, -0.145, -0.05), (sx * 0.106, -0.145, -0.05), (sx * 0.106, -0.145, -0.02),
                 (sx * 0.098, -0.145, -0.02)]], "bronze")
    # Crest: front-to-back arc of red horsehair on a bronze holder.
    path = [(0.0, 0.15 + 0.035 * math.sin(math.pi * k / 12), -0.12 + 0.26 * k / 12) for k in range(13)]
    for k in range(13):
        z = -0.13 + 0.27 * k / 12
        base = 0.152 * math.sqrt(max(0.0, 1 - (z / 0.15) ** 2)) + 0.004
        path[k] = (0.0, base, z)
    rings = []
    for k, (x, y, z) in enumerate(path):
        hgt = 0.09 * math.sin(math.pi * (0.1 + 0.8 * k / 12))
        rings.append([(-0.006, y, z), (0.006, y, z), (0.018, y + hgt * 0.6, z + 0.01), (0.0, y + hgt, z + 0.02),
                      (-0.018, y + hgt * 0.6, z + 0.01)])
    b.loft(rings, "crest")

def build_manica_r(b):
    # Right forearm: centre at the origin, 0.34 m long, radius 0.045. Seven overlapping lames from wrist to elbow,
    # each a short cone, on a leather liner.
    lathe(b, [(0.049, -0.16), (0.05, 0.16)], 14, "leather")
    for k in range(7):
        y0 = -0.15 + k * 0.045
        r0 = 0.054 + 0.0015 * k
        lathe(b, [(r0, y0), (r0 + 0.006, y0 + 0.004), (r0 + 0.008, y0 + 0.05), (r0 + 0.002, y0 + 0.054)], 16, "iron")

def build_greave_r(b):
    # Right shin: centre at the origin, capsule radius 0.05 from y -0.27 (ankle) to 0.21 (knee). The greave wraps the
    # front (-Z) 220 degrees with a 7 mm shell, a rolled rim and a knee boss.
    def shell(y, r_in, r_out, arc=math.radians(220)):
        pts_o, pts_i = [], []
        for j in range(9):
            a = -math.pi / 2 - arc / 2 + arc * j / 8  # centred on -Z
            pts_o.append((r_out * math.cos(a), y, r_out * math.sin(a) * 1.1))
            pts_i.append((r_in * math.cos(a), y, r_in * math.sin(a) * 1.1))
        return pts_o + pts_i[::-1]
    prof = [(-0.2, 0.052), (-0.14, 0.058), (-0.04, 0.066), (0.06, 0.064), (0.13, 0.06), (0.17, 0.062)]
    b.loft([shell(y, r, r + 0.007) for y, r in prof], "bronze")
    lathe(b, sphere_prof(0.035, 0.0, 6)[:4], 12, "bronze", axis="z", c=(0.0, 0.18, -0.058))  # knee boss, domed to -Z
    for y in (-0.2, 0.17):
        b.loft([shell(y - 0.006, 0.055, 0.068), shell(y + 0.006, 0.055, 0.068)], "bronze")

def build_scutum(b):
    # 0.66 x 1.06 m, curved (radius 0.55) so the convex face points +Z; grip at the origin; iron boss; brass rim.
    W, H, R, T = 0.33, 0.53, 0.55, 0.012
    def zc(x):
        return 0.06 + (math.sqrt(R * R - x * x) - R)
    rows = []
    for k in range(9):
        y = -H + 2 * H * k / 8
        front = [(x, y, zc(x) + T) for x in [-W + 2 * W * i / 12 for i in range(13)]]
        back = [(x, y, zc(x)) for x in [W - 2 * W * i / 12 for i in range(13)]]
        rows.append(front + back)
    b.loft(rows, "scutum_red")
    for sy in (-1, 1):  # top and bottom rim
        rim = []
        for k in range(13):
            x = -W + 2 * W * k / 12
            rim.append([(x, sy * H - 0.012, zc(x) - 0.004), (x, sy * H + 0.012, zc(x) - 0.004),
                        (x, sy * H + 0.012, zc(x) + T + 0.004), (x, sy * H - 0.012, zc(x) + T + 0.004)])
        b.loft(rim, "bronze")
    for sx in (-1, 1):  # side rims
        box(b, (sx * W - 0.012, -H, zc(W) - 0.004), (sx * W + 0.012, H, zc(W) + T + 0.004), "bronze")
    lathe(b, [(0.12, 0.0), (0.12, 0.004), (0.09, 0.02), (0.05, 0.045), (0.004, 0.055)], 16, "iron", axis="z",
          c=(0.0, 0.0, 0.06 + T))
    box(b, (-0.012, -0.1, -0.03), (0.012, 0.1, 0.0), "wood")  # vertical hand grip behind the boss
    box(b, (-0.015, -0.12, 0.0), (0.015, -0.1, 0.06), "wood")
    box(b, (-0.015, 0.1, 0.0), (0.015, 0.12, 0.06), "wood")
'''


def make_materials():
    mat = hou.node("/mat")
    for name, spec in MATERIALS.items():
        col, rough, metal = spec[:3]
        m = mat.createNode("principledshader::2.0", name)
        m.parmTuple("basecolor").set(col)
        m.parm("rough").set(rough)
        m.parm("metallic").set(metal)
        if len(spec) > 3:
            m.parm("emitint").set(spec[4])
            m.parmTuple("emitcolor").set(spec[3])


def make_piece(pid, x_offset):
    group = PIECES[pid][0]
    obj = hou.node("/obj").createNode("geo", pid)
    obj.parmTuple("t").set((x_offset, 0, 0))
    py = obj.createNode("python", "build")
    src = MIRROR.get(pid, pid)
    py.parm("python").set(LIB + "\nbuild_%s(B(hou.pwd().geometry()))\n" % src)
    last = py
    if pid in MIRROR:
        xf = obj.createNode("xform", "mirror")
        xf.setInput(0, py)
        xf.parm("sx").set(-1)
        rev = obj.createNode("reverse", "rewind")  # a negative scale flips the winding back
        rev.setInput(0, xf)
        last = rev
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, last)
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, div)
    nrm.parm("cuspangle").set(40)
    out = obj.createNode("null", "OUT")
    out.setInput(0, nrm)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    rop = hou.node("/out").createNode("gltf", "export_" + pid)
    rop.parm("outputfile").set("$HIP/../export/%s/%s.glb" % (group, pid))
    rop.parm("exportmaterials").set(1)
    if pid == "weapon_rack":
        # Object mode so the slot nulls export as named empty nodes under the rack.
        names = [pid]
        for i in range(RACK_SLOTS):
            n = hou.node("/obj").createNode("null", "slot_%d" % (i + 1))
            n.setFirstInput(obj)
            n.parmTuple("t").set((-0.55 + i * 0.22, 0.27, -0.06))
            names.append(n.name())
        rop.parm("usesoppath").set(0)
        rop.parm("objpath").set("/obj")
        rop.parm("objects").set(" ".join(names))
        rop.parm("exportcameras").set(0)
        rop.parm("exportlights").set(0)
    else:
        rop.parm("usesoppath").set(1)
        rop.parm("soppath").set(out.path())
    return obj, out, rop


def render_previews(objs):
    cam = hou.node("/obj").createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    key = hou.node("/obj").createNode("hlight", "key")
    key.parmTuple("t").set((4, 8, 8))
    back = hou.node("/obj").createNode("hlight", "back")
    back.parmTuple("t").set((-4, 6, -8))
    back.parm("light_intensity").set(0.6)
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(0.6)
    rop = hou.node("/out").createNode("karma", "preview")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)
    cam.parm("resx").set(512); cam.parm("resy").set(512)
    rop.parm("resolutionx").set(512); rop.parm("resolutiony").set(512)
    for pid, (obj, out) in objs.items():
        group, _, _, yaw, _ = PIECES[pid]
        bb = out.geometry().boundingBox()
        c = bb.center() + hou.Vector3(obj.parmTuple("t").eval())
        size = bb.sizevec()
        r = hou.hmath.buildRotate((-15, yaw, 0), "xyz")
        cam.setWorldTransform(r * hou.hmath.buildTranslate(hou.Vector3(c) + hou.Vector3(0, 0, 20) * r))
        cam.parm("orthowidth").set(max(size[0], size[1], size[2]) * 1.2)
        rop.parm("candobjects").set(obj.name())
        os.makedirs(os.path.join(PREVIEW_ROOT, group), exist_ok=True)
        rop.parm("picture").set(os.path.join(PREVIEW_ROOT, group, pid + ".png"))
        rop.render()


# part: (axis radius or None for a sphere, y range checked, z stretch of the body section)
FIT = {"head": (None, (-0.03, 0.2), 1.0), "forearm": (0.045, (-0.17, 0.17), 1.0), "shin": (0.05, (-0.2, 0.17), 1.0)}


def fit(part, geo):
    """Smallest clearance (m) between the armor's inner surface and the body part (head sphere r 0.11, limb capsules
    around +Y): over every armor point in the part's span. Negative = the armor cuts into the body."""
    radius, (y0, y1), _ = FIT[part]
    best = 1e9
    for p in geo.points():
        x, y, z = p.position()
        if not (y0 <= y <= y1):
            continue
        d = math.sqrt(x * x + y * y + z * z) - 0.11 if radius is None else math.sqrt(x * x + z * z) - radius
        best = min(best, d)
    return best


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    os.makedirs(os.path.dirname(HIP), exist_ok=True)
    for g in set(v[0] for v in PIECES.values()):
        os.makedirs(os.path.join(ROOT, "export", g), exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    objs, rops = {}, {}
    x = 0.0
    for pid in PIECES:
        obj, out, rop = make_piece(pid, x)
        objs[pid] = (obj, out)
        rops[pid] = rop
        x += max(out.geometry().boundingBox().sizevec()[0], 0.3) + 1.0
    hou.hipFile.save(HIP)

    ok = True
    for pid, (group, max_tris, closed, _, part) in PIECES.items():
        if pid == "weapon_rack":
            objs[pid][0].parmTuple("t").set((0, 0, 0))
        rops[pid].render()
        path = os.path.join(ROOT, "export", group, pid + ".glb")
        tris, lo, hi, vol, mnames = read_glb(path)
        good = tris <= max_tris and (vol > 0 or not closed)
        extra = ""
        if part:
            gap = fit(part, objs[pid][1].geometry())
            good = good and gap >= 0.0
            extra = " clearance=%+.3f" % gap
        if pid == "weapon_rack":
            doc_nodes = _node_names(path)
            slots = [n for n in doc_nodes if n.startswith("slot_")]
            good = good and len(slots) == RACK_SLOTS
            extra = " empties=%s" % ",".join(slots)
        ok = ok and good
        print("%-14s %-8s %s tris=%5d size=%6.1f KB bbox=(%.3f %.3f %.3f)..(%.3f %.3f %.3f)%s mats=%s" % (
            pid, group, "OK  " if good else "FAIL", tris, os.path.getsize(path) / 1024.0, *lo, *hi, extra,
            ",".join(mnames)))

    if "--no-preview" not in sys.argv:
        try:
            render_previews(objs)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


def _node_names(path):
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    return [n.get("name", "") for n in json.loads(data[20:20 + jlen]).get("nodes", [])]


main()
