"""Build more Sandblood shields and armor procedurally and export them as .glb (export/armor_more, preview/armor_more).

Run:  hython scripts/build_armor_more.py [--only=<ids or group>,...] [--no-preview]
      groups: shield, helmet, torso, pelvis, arm, leg

Conventions (meters, Y up), same as build_props.py:
- Shields: grip at the origin (vertical, along Y), shield face toward +Z. The forearm runs along the shield's X axis
  behind the board, so the aspis arm band (porpax) sits 0.25 m from the grip toward -X.
- Armor is modelled in the fighter body part's local frame from build_body.py (origin = part centre, front = -Z).
  Right-side pieces are built natively (outward = +X); _l pieces are the right piece mirrored (sx=-1 + Reverse SOP).
  helmets -> head, lorica_* -> torso, balteus/subligaculum -> pelvis, galerus_l/spaulder_* -> upper_arm_*,
  fasciae_* -> thigh_*.
Reuses (loads, does not copy) the geometry library of build_props.py (which contains LIB_BASE from build_weapons.py
plus sweep/bar/blob/hashn), its MATERIALS, and build_weapons.py's read_glb. Torso/pelvis armor is shaped against the
body's real cross-sections (TORSO/PELVIS tables, xring and bump functions loaded from build_body.py).

Fit check: (1) the part's physics primitive from build_body.py: head sphere r 0.11, upper_arm capsule r 0.05 and thigh
capsule r 0.07 (segment = physics box half height minus radius), torso/pelvis boxes (signed distance to the box);
(2) the real body mesh: a VDB signed distance field of the body part (build_body.py's own builder) sampled at every armor
point. Gate: mesh clearance >= 0 for every part, plus primitive clearance >= 0 for head/arm/thigh. The torso and pelvis
boxes are too crude (their corners stand 3-4 cm off the rounded body), so for those the box value is reported only.
"""
import math
import os
import re
import sys

import hou

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GROUP = "armor_more"
HIP = os.path.join(ROOT, "hip", "armor_more.hip")
EXPORT = os.path.join(ROOT, "export", GROUP)
PREVIEW = os.path.join(ROOT, "preview", GROUP)


def _src(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


_WEAPONS_SRC, _PROPS_SRC, _BODY_SRC = _src("build_weapons.py"), _src("build_props.py"), _src("build_body.py")
LIB_BASE = re.search(r"LIB = r'''(.*?)'''", _WEAPONS_SRC, re.S).group(1)
LIB_PROPS = LIB_BASE + re.search(r"LIB = LIB_BASE \+ r'''(.*?)'''", _PROPS_SRC, re.S).group(1)
exec("import json, struct\n" + re.search(r"(def read_glb\(path\):.*?)\n\n\n", _WEAPONS_SRC, re.S).group(1))
MATERIALS = {}
exec(re.search(r"(MATERIALS = \{.*?\n\})", _PROPS_SRC, re.S).group(1))
BODY_LIB = re.search(r"LIB = r'''(.*?)'''", _BODY_SRC, re.S).group(1)


def grab(src, name):
    """Top-level def or table `name` from a source string."""
    lines = src.split("\n")
    for k, line in enumerate(lines):
        if line.startswith("def %s(" % name) or line.startswith("%s = " % name):
            out = [line]
            for l2 in lines[k + 1:]:
                if l2 and not l2[0].isspace() and l2[0] not in ")]}#":
                    break
                out.append(l2)
            return "\n".join(out).rstrip() + "\n\n"
    raise KeyError(name)


BODY_FUNCS = "".join(grab(BODY_LIB, n) for n in ("rowinterp", "gauss", "xring", "TORSO", "torso_bump", "PELVIS",
                                                  "pelvis_bump", "pring", "UPPER_ARM", "THIGH"))

MATERIALS.update({
    "visor_dark": ((0.025, 0.02, 0.018), 0.7, 0.0),
    "wicker": ((0.56, 0.42, 0.22), 0.9, 0.0),
    "linen": ((0.80, 0.76, 0.66), 0.9, 0.0),
    "paint_blue": ((0.07, 0.14, 0.34), 0.6, 0.0),
})
# preview-only materials for the body reference in the fit pictures (never exported with armor)
REF_MATERIALS = {"skin": ((0.56, 0.31, 0.19), 0.55, 0.0), "cloth": ((0.85, 0.84, 0.80), 0.9, 0.0),
                 "hair": ((0.045, 0.03, 0.02), 0.8, 0.0)}

# id: (group, max tris, preview yaw, body part or None)
PIECES = {
    "parma": ("shield", 2500, 25, None),
    "aspis": ("shield", 2500, 25, None),
    "buckler": ("shield", 2500, 25, None),
    "pelta": ("shield", 2500, 25, None),
    "kite": ("shield", 2500, 25, None),
    "tower": ("shield", 3000, 25, None),
    "murmillo": ("helmet", 2500, 215, "head"),
    "thraex": ("helmet", 2500, 215, "head"),
    "secutor": ("helmet", 2500, 215, "head"),
    "lorica_segmentata": ("torso", 2500, 205, "torso"),
    "lorica_squamata": ("torso", 2500, 205, "torso"),
    "balteus": ("pelvis", 2500, 205, "pelvis"),
    "subligaculum": ("pelvis", 2500, 205, "pelvis"),
    "galerus_l": ("arm", 2500, 145, "upper_arm"),
    "spaulder_r": ("arm", 2500, 215, "upper_arm"),
    "spaulder_l": ("arm", 2500, 145, "upper_arm"),
    "fasciae_r": ("leg", 2500, 215, "thigh"),
    "fasciae_l": ("leg", 2500, 145, "thigh"),
}
ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
if ONLY:
    want = ONLY[0].split(",")
    PIECES = {k: v for k, v in PIECES.items() if k in want or v[0] in want}
MIRROR = {"galerus_l": "galerus_r", "spaulder_l": "spaulder_r", "fasciae_l": "fasciae_r"}

# Body parts (build_body.py): builder call, physics primitive.
BODY_CALL = {"head": "build_head(b, True)", "torso": "build_torso(b)", "pelvis": "build_pelvis(b)",
             "upper_arm": "build_upper_arm(b)", "thigh": "build_thigh(b)"}
PRIM = {"head": ("sphere", 0.11), "upper_arm": ("capsule", 0.05, 0.10), "thigh": ("capsule", 0.07, 0.15),
        "torso": ("box", (0.18, 0.24, 0.11)), "pelvis": ("box", (0.16, 0.10, 0.10))}

LIB = LIB_PROPS + BODY_FUNCS + r'''
# ---------------- helpers ----------------
def slab(b, f, nu, nv, t0, t1, mat, wrap=False, mat_in=None, mat_edge=None):
    """Thick sheet: f(i, j, t) -> point for grid index (i, j) at thickness offset t. Outer sheet at t1, inner at t0,
    closed with edge strips. Every face is oriented explicitly (outer: toward t1, inner: toward t0)."""
    iu = nu if wrap else nu + 1
    O = [[f(i, j, t1) for i in range(iu)] for j in range(nv + 1)]
    I = [[f(i, j, t0) for i in range(iu)] for j in range(nv + 1)]
    PO = [b.pts(r) for r in O]
    PI = [b.pts(r) for r in I]
    mo = mat if callable(mat) else (lambda i, j: mat)
    mi = (lambda i, j: mat_in) if mat_in else mo
    me = mat_edge or mat_in or (mat if not callable(mat) else mo(0, 0))
    def nx(i):
        return (i + 1) % iu if wrap else i + 1
    def emit(pts, cs, uv, out, m):
        if not b.facing(cs, out):
            pts = pts[::-1]; uv = uv[::-1]
        b.poly(pts, uv, m)
    for j in range(nv):
        for i in range(nu):
            idx = [(j, i), (j, nx(i)), (j + 1, nx(i)), (j + 1, i)]
            uv = [(i / nu, j / nv), ((i + 1) / nu, j / nv), ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv)]
            co = [O[a][c] for a, c in idx]
            ci = [I[a][c] for a, c in idx]
            out = sub(centroid(co), centroid(ci))
            emit([PO[a][c] for a, c in idx], co, uv, out, mo(i, j))
            emit([PI[a][c] for a, c in idx], ci, uv, [-v for v in out], mi(i, j))
    edges = []
    for j, jn in ((0, 1), (nv, nv - 1)):
        for i in range(nu):
            edges.append(((j, i), (j, nx(i)), (jn, i), (jn, nx(i))))
    if not wrap:
        for i, inn in ((0, 1), (nu, nu - 1)):
            for j in range(nv):
                edges.append(((j, i), (j + 1, i), (j, inn), (j + 1, inn)))
    for a, c, an, cn in edges:
        cs = [O[a[0]][a[1]], O[c[0]][c[1]], I[c[0]][c[1]], I[a[0]][a[1]]]
        pts = [PO[a[0]][a[1]], PO[c[0]][c[1]], PI[c[0]][c[1]], PI[a[0]][a[1]]]
        ref = centroid([O[an[0]][an[1]], O[cn[0]][cn[1]], I[an[0]][an[1]], I[cn[0]][cn[1]]])
        emit(pts, cs, [(0, 0), (1, 0), (1, 1), (0, 1)], sub(centroid(cs), ref), me)

def tube_rings(path, sec, closed, zref=(0.0, 0.0, 1.0)):
    n = len(path)
    rings = []
    for i in range(n):
        if closed:
            t = vnorm(sub(path[(i + 1) % n], path[i - 1]))
        else:
            t = vnorm(sub(path[min(i + 1, n - 1)], path[max(i - 1, 0)]))
        u = vcross(t, zref)
        if dot(u, u) < 1e-8:
            u = vcross(t, (0.0, 1.0, 0.0))
        u = vnorm(u)
        v = vcross(t, u)
        rings.append([tuple(path[i][k] + su * u[k] + sv * v[k] for k in range(3)) for su, sv in sec])
    return rings

def circ_sec(r, segs, rz=None):
    rz = r if rz is None else rz
    return [(r * math.cos(2 * math.pi * j / segs), rz * math.sin(2 * math.pi * j / segs)) for j in range(segs)]

def ring_tube(b, path, sec, mat, closed=True, zref=(0.0, 0.0, 1.0)):
    """Tube with cross-section `sec` [(u, v)] along `path`; u is in-plane (perpendicular to zref), v ~ zref."""
    b.loft(tube_rings(path, sec, closed, zref), mat, wrap=closed)

def strap(b, path, wdir, w, th, mat):
    """Flat strap of width w along wdir and thickness th following `path`."""
    n = len(path)
    nrm = []
    for i in range(n):
        t = vnorm(sub(path[min(i + 1, n - 1)], path[max(i - 1, 0)]))
        nrm.append(vnorm(vcross(t, wdir)))
    def f(i, j, t):
        return tuple(path[i][k] + (j - 0.5) * w * wdir[k] + t * nrm[i][k] for k in range(3))
    slab(b, f, n - 1, 1, -0.5 * th, 0.5 * th, mat)

def tetra(b, cs, mat):
    P = b.pts(cs)
    c = centroid(cs)
    for f in ((0, 1, 2), (0, 1, 3), (1, 2, 3), (0, 2, 3)):
        fc = [cs[k] for k in f]
        pts = [P[k] for k in f]
        if not b.facing(fc, sub(centroid(fc), c)):
            pts = pts[::-1]
        b.poly(pts, [(0, 0), (1, 0), (0.5, 1)], mat)

def disc_board(b, R_list, nu, zfn, th, mat, mat_in, cx=0.0, cy=0.0):
    """Round board (annulus rings R_list) with surface z = zfn(r), thickness along +Z."""
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        r = R_list[j]
        return (cx + r * math.cos(a), cy + r * math.sin(a), zfn(r) + t)
    slab(b, f, nu, len(R_list) - 1, 0.0, th, mat, wrap=True, mat_in=mat_in)

def grip(b, zback, h=0.06):
    """Vertical hand grip at the origin with two iron brackets back to the board at z = zback."""
    box(b, (-0.012, -h, -0.012), (0.012, h, 0.012), "wood")
    box(b, (-0.012, -h - 0.015, -0.012), (0.012, -h, zback + 0.004), "iron")
    box(b, (-0.012, h, -0.012), (0.012, h + 0.015, zback + 0.004), "iron")

# ---------------- body envelopes (part-local) ----------------
def poly_in(ring, x, z):
    inside = False
    for k in range(len(ring)):
        x1, _, z1 = ring[k]
        x2, _, z2 = ring[k - 1]
        if (z1 > z) != (z2 > z) and x < x1 + (z - z1) * (x2 - x1) / (z2 - z1):
            inside = not inside
    return inside

_TR = {}
def torso_ring(y):
    k = int(round(y / 0.002))
    r = _TR.get(k)
    if r is None:
        yy = k * 0.002
        a, df, db = rowinterp(yy, TORSO)
        r = _TR[k] = xring(yy, a, a, df, db, 48, 0.0, 0.0, torso_bump, 2.4)
    return r

NECK = [(0.12, 0.062, 0.058, 0.062, 0.008), (0.2, 0.060, 0.054, 0.060, 0.008), (0.25, 0.057, 0.051, 0.057, 0.01),
        (0.262, 0.053, 0.048, 0.053, 0.01), (0.27, 0.04, 0.036, 0.04, 0.01)]

def torso_in(p):
    x, y, z = p
    if -0.27 <= y <= 0.25 and poly_in(torso_ring(y), x, z):
        return True
    if 0.104 <= y <= 0.24:  # deltoid caps of build_torso
        c = max(-1.0, min(1.0, (0.172 - y) / 0.068))
        sr = max(math.sqrt(1.0 - c * c), 0.05)
        w = 0.058 * sr * (0.85 + 0.15 * (y - 0.104) / 0.136)
        if ((abs(x) - 0.21) / w) ** 2 + (z / (0.064 * sr)) ** 2 <= 1.0:
            return True
    if 0.12 <= y <= 0.27:  # neck stump
        rx = interp(y, [(r[0], r[1]) for r in NECK])
        cz = interp(y, [(r[0], r[4]) for r in NECK])
        rz = interp(y, [(r[0], r[2] if z < cz else r[3]) for r in NECK])
        if (x / rx) ** 2 + ((z - cz) / rz) ** 2 <= 1.0:
            return True
    return False

_PR = {}
def pelvis_in(p):
    x, y, z = p
    flap = abs(x) < 0.08 and y <= 0.075
    if not ((-0.125 <= y <= 0.13) or (flap and y >= -0.135)):
        return False
    push = 0.0075 if 0.022 <= y <= 0.078 else 0.0  # the body's leather belt
    if flap:
        push += 0.018  # the body's front/back loincloth flaps, which hang straight below y = -0.06
        y = max(y, -0.06) if abs(z) > 0.05 else y
    k = (int(round(y / 0.002)), int(round(push * 10000)))
    r = _PR.get(k)
    if r is None:
        r = _PR[k] = pring(k[0] * 0.002, push, 48)
    return poly_in(r, x, z)

def extent(inside, o, d, tmax=0.34, step=0.004):
    """Outermost distance along ray o + t d that is inside the body (0 if none)."""
    def at(t):
        return (o[0] + d[0] * t, o[1] + d[1] * t, o[2] + d[2] * t)
    t = tmax
    while t > 0.0:
        if inside(at(t)):
            lo, hi = t, t + step
            for _ in range(7):
                m = 0.5 * (lo + hi)
                if inside(at(m)):
                    lo = m
                else:
                    hi = m
            return hi
        t -= step
    return 0.0

class Env:
    """Horizontal body radius around the Y axis on a grid of angles x heights, each the max over y +/- span."""
    def __init__(self, inside, y0, y1, ny, na, span):
        self.y0, self.y1, self.ny, self.na = y0, y1, ny, na
        raw = [[extent(inside, (0.0, y0 + (y1 - y0) * j / ny, 0.0),
                       (math.cos(2 * math.pi * i / na), 0.0, math.sin(2 * math.pi * i / na)))
                for i in range(na)] for j in range(ny + 1)]
        ks = max(1, int(round(span / ((y1 - y0) / ny))))
        self.g = [[max(raw[jj][i] for jj in range(max(0, j - ks), min(ny, j + ks) + 1)) for i in range(na)]
                  for j in range(ny + 1)]
        # also widen by the neighbouring angles (chords between samples cut inward)
        self.g = [[max(row[i - 1], row[i], row[(i + 1) % na]) for i in range(na)] for row in self.g]
    def r(self, a, y):
        fy = (min(max(y, self.y0), self.y1) - self.y0) / (self.y1 - self.y0) * self.ny
        j = min(int(fy), self.ny - 1); ty = fy - j
        fa = (a / (2 * math.pi)) % 1.0 * self.na
        i = int(fa) % self.na; ta = fa - int(fa); i2 = (i + 1) % self.na
        g = self.g
        return ((g[j][i] * (1 - ta) + g[j][i2] * ta) * (1 - ty) + (g[j + 1][i] * (1 - ta) + g[j + 1][i2] * ta) * ty)

def cyl(r, a, y):
    return (r * math.cos(a), y, r * math.sin(a))

# ---------------- shields (grip at origin, face +Z) ----------------
def build_parma(b):
    R = 0.225
    def zf(r):
        return 0.045 + 0.035 * (1 - (r / R) ** 2)
    disc_board(b, [0.05, 0.11, 0.17, R - 0.006], 24, zf, 0.012, "paint_blue", "wood")
    path = [(R * math.cos(2 * math.pi * k / 24), R * math.sin(2 * math.pi * k / 24), zf(R) + 0.006) for k in range(24)]
    ring_tube(b, path, [(-0.009, -0.012), (0.006, -0.012), (0.01, 0.0), (0.006, 0.012), (-0.009, 0.012)], "bronze")
    z0 = zf(0.0) + 0.008
    lathe(b, [(0.07, z0), (0.07, z0 + 0.005), (0.055, z0 + 0.02), (0.035, z0 + 0.038), (0.004, z0 + 0.045)],
          16, "bronze", axis="z")
    grip(b, zf(0.06))

def build_aspis(b):
    # Hoplon: deep bronze-faced bowl (r 0.40, 0.12 deep, convex toward +Z) with a flat offset rim to r 0.45 at the
    # back plane. Arm band (porpax) at the bowl centre, 0.25 m from the hand grip (antilabe) at the origin.
    R, Rb, cx, zb, D = 0.45, 0.40, -0.25, -0.02, 0.12
    def zf(r):
        return zb + D * (1 - (r / Rb) ** 2)
    disc_board(b, [0.03, 0.09, 0.16, 0.24, 0.31, 0.36, Rb], 32, zf, 0.008, "bronze", "wood", cx=cx)
    def frim(i, j, t):
        a = 2 * math.pi * i / 32
        r = (Rb - 0.006, R)[j]
        return (cx + r * math.cos(a), r * math.sin(a), zb - 0.004 + t)
    slab(b, frim, 32, 1, 0.0, 0.008, "bronze", wrap=True, mat_in="wood")
    path = [(cx + R * math.cos(2 * math.pi * k / 32), R * math.sin(2 * math.pi * k / 32), zb) for k in range(32)]
    ring_tube(b, path, circ_sec(0.008, 6), "bronze")
    # Blazon: a raised bronze ring and centre disc on the face.
    lathe(b, [(0.06, zf(0.0) + 0.004), (0.06, zf(0.0) + 0.012), (0.03, zf(0.0) + 0.018), (0.004, zf(0.0) + 0.02)],
          12, "bronze", axis="z", c=(cx, 0.0, 0.0))
    # Porpax: U-shaped bronze band hanging from the inside of the bowl around the forearm (axis along X at z ~ 0).
    zi = zf(0.07) - 0.004
    loop = [(cx, -0.065, zi), (cx, -0.065, 0.0)]
    loop += [(cx, -0.065 * math.cos(math.pi * k / 6), -0.065 * math.sin(math.pi * k / 6)) for k in range(1, 6)]
    loop += [(cx, 0.065, 0.0), (cx, 0.065, zi)]
    strap(b, loop, (1.0, 0.0, 0.0), 0.04, 0.005, "bronze")
    # Antilabe: leather-wrapped hand grip at the origin, standoffs to the bowl.
    zg = zf(0.25) - 0.003
    bar(b, (0.0, -0.07, 0.0), (0.0, 0.07, 0.0), 0.013, "leather", segs=8)
    bar(b, (0.0, -0.07, 0.0), (0.0, -0.08, zg), 0.006, "iron", segs=5)
    bar(b, (0.0, 0.07, 0.0), (0.0, 0.08, zg), 0.006, "iron", segs=5)

def build_buckler(b):
    R = 0.15
    def zf(r):
        return 0.04 + 0.03 * (1 - (r / R) ** 2)
    disc_board(b, [0.05, 0.09, 0.125, R - 0.004], 20, zf, 0.006, "iron", "iron")
    path = [(R * math.cos(2 * math.pi * k / 20), R * math.sin(2 * math.pi * k / 20), zf(R) + 0.003) for k in range(20)]
    ring_tube(b, path, circ_sec(0.0065, 6), "bronze")
    z0 = zf(0.0) + 0.002
    lathe(b, [(0.065, z0), (0.065, z0 + 0.006), (0.055, z0 + 0.016), (0.035, z0 + 0.028), (0.016, z0 + 0.036),
              (0.011, z0 + 0.05), (0.004, z0 + 0.1), (0.0008, z0 + 0.112)], 16, "bronze", axis="z")
    grip(b, zf(0.05), h=0.055)

def build_pelta(b):
    # Lunate wicker shield ~0.6 m: outer arc r 0.3 below, a crescent bite (r 0.344 arc) from the top between two horns.
    yo, Ro, ci, Ri = 0.12, 0.3, 0.42, 0.3443
    a0, a1 = math.radians(160), math.radians(380)
    p0, p1 = math.atan2(yo + 0.1026 - ci, -0.282), math.atan2(yo + 0.1026 - ci, 0.282)
    p0 += 2 * math.pi if p0 < 0 else 0.0
    p1 += 2 * math.pi if p1 < 0 else 0.0
    us = [0.035 + 0.93 * k / 24 for k in range(25)]
    def outer(u):
        a = a0 + (a1 - a0) * u
        return (Ro * math.cos(a), yo + Ro * math.sin(a))
    def inner(u):
        a = p0 + (p1 - p0) * u
        return (Ri * math.cos(a), ci + Ri * math.sin(a))
    def zf(x):
        return 0.045 + 0.05 * (1 - (x / Ro) ** 2)
    def f(i, j, t):
        (xo, yo_), (xi, yi) = outer(us[i]), inner(us[i])
        v = j / 6
        x, y = xi + (xo - xi) * v, yi + (yo_ - yi) * v
        weave = 0.003 * (1 if (i + j) % 2 else -1) * (0.0 if j in (0, 6) else 1.0)
        return (x, y, zf(x) + weave + t)
    slab(b, f, 24, 6, 0.0, 0.014, "wicker", mat_in="wicker")
    for fn in (outer, inner):
        path = [(fn(u)[0], fn(u)[1], zf(fn(u)[0]) + 0.007) for u in [0.02 + 0.96 * k / 20 for k in range(21)]]
        sweep(b, path, lambda i, s, a: 0.0095, 6, "leather")
    z0 = zf(0.0) + 0.012
    lathe(b, [(0.05, z0), (0.05, z0 + 0.005), (0.035, z0 + 0.02), (0.015, z0 + 0.03), (0.003, z0 + 0.032)],
          12, "bronze", axis="z")
    grip(b, zf(0.0))

def kite_w(y):
    if y >= 0.1:
        return math.sqrt(max(0.3 ** 2 - (y - 0.1) ** 2, 0.0))
    return 0.3 * max((y + 0.6) / 0.7, 0.0) ** 0.75

def build_kite(b):
    R = 0.55
    def zf(x):
        return 0.05 + (math.sqrt(R * R - x * x) - R)
    ys = [-0.585, -0.5, -0.38, -0.25, -0.1, 0.05, 0.15, 0.25, 0.32, 0.37, 0.394]
    def f(i, j, t):
        y = ys[j]
        x = kite_w(y) * (2 * i / 10 - 1)
        return (x, y, zf(x) + t)
    slab(b, f, 10, len(ys) - 1, 0.0, 0.014, "scutum_red", mat_in="wood")
    side = [-0.6 + k * 0.05 for k in range(1, 14)] + [0.1 + 0.3 * math.sin(math.pi / 2 * k / 6) for k in range(1, 6)]
    outline = [(0.0, -0.6)] + [(kite_w(y), y) for y in side] + [(0.0, 0.4)] + [(-kite_w(y), y) for y in reversed(side)]
    ring_tube(b, [(x, y, zf(x) + 0.007) for x, y in outline], [(-0.006, -0.011), (0.007, -0.011), (0.009, 0.0),
                                                               (0.007, 0.011), (-0.006, 0.011)], "iron")
    strap(b, [(0.0, y, zf(0.0) + 0.0155) for y in (-0.55, 0.37)], (1.0, 0.0, 0.0), 0.04, 0.003, "bronze")
    xs = [-0.27 + 0.54 * k / 10 for k in range(11)]
    strap(b, [(x, 0.0, zf(x) + 0.0155) for x in xs], (0.0, 1.0, 0.0), 0.04, 0.003, "bronze")
    z0 = zf(0.0) + 0.014
    lathe(b, [(0.07, z0), (0.07, z0 + 0.006), (0.055, z0 + 0.025), (0.03, z0 + 0.045), (0.004, z0 + 0.05)],
          16, "iron", axis="z")
    grip(b, zf(0.06))

def build_tower(b):
    # 0.7 x 1.3 m curved (r 0.5) tower shield: leather-faced board, iron edge, two bronze bands, spine and boss.
    W, H, R, T = 0.35, 0.65, 0.5, 0.016
    def zf(x):
        return 0.07 + (math.sqrt(R * R - x * x) - R)
    def f(i, j, t):
        x = -W + 2 * W * i / 14
        return (x, -H + 2 * H * j / 10, zf(x) + t)
    slab(b, f, 14, 10, 0.0, T, "leather", mat_in="wood")
    xs = [-W + 2 * W * k / 14 for k in range(15)]
    outline = ([(x, -H) for x in xs] + [(W, -H + 2 * H * k / 4) for k in range(1, 4)] + [(x, H) for x in reversed(xs)]
               + [(-W, H - 2 * H * k / 4) for k in range(1, 4)])
    ring_tube(b, [(x, y, zf(x) + T / 2) for x, y in outline], [(-0.008, -0.014), (0.012, -0.014), (0.012, 0.014),
                                                               (-0.008, 0.014)], "iron")
    for y in (-0.38, 0.38):
        strap(b, [(x, y, zf(x) + T + 0.002) for x in xs[1:-1]], (0.0, 1.0, 0.0), 0.05, 0.004, "bronze")
    strap(b, [(0.0, y, zf(0.0) + T + 0.002) for y in (-0.6, -0.1)], (1.0, 0.0, 0.0), 0.045, 0.004, "bronze")
    strap(b, [(0.0, y, zf(0.0) + T + 0.002) for y in (0.1, 0.6)], (1.0, 0.0, 0.0), 0.045, 0.004, "bronze")
    z0 = zf(0.0) + T - 0.002
    lathe(b, [(0.13, z0), (0.13, z0 + 0.006), (0.1, z0 + 0.025), (0.06, z0 + 0.05), (0.03, z0 + 0.062),
              (0.004, z0 + 0.066)], 16, "iron", axis="z")
    grip(b, zf(0.06), h=0.07)

# ---------------- helmets (head frame, face -Z) ----------------
def prof_normals(prof):
    n = len(prof)
    N = []
    for j in range(n):
        a, c = prof[max(j - 1, 0)], prof[min(j + 1, n - 1)]
        tr, ty = c[0] - a[0], c[1] - a[1]
        l = math.hypot(tr, ty) or 1.0
        N.append((ty / l, -tr / l))
    return N

def helm_pt(prof, N, a, s, t, sx, szf, szb):
    j = min(int(s), len(prof) - 2); f = s - j
    R = prof[j][0] + (prof[j + 1][0] - prof[j][0]) * f
    y = prof[j][1] + (prof[j + 1][1] - prof[j][1]) * f
    nr = N[j][0] + (N[j + 1][0] - N[j][0]) * f
    ny = N[j][1] + (N[j + 1][1] - N[j][1]) * f
    r, y = R + t * nr, y + t * ny
    sn = math.sin(a)
    return (r * sx * math.cos(a), y, r * (szf if sn < 0 else szb) * sn)

def prof_s(prof, y):
    for j in range(len(prof) - 1):
        if prof[j][1] <= y <= prof[j + 1][1]:
            return j + (y - prof[j][1]) / (prof[j + 1][1] - prof[j][1])
    return 0.0 if y < prof[0][1] else len(prof) - 1.0

def helm_shell(b, prof, nu, th, sx, szf, szb, matfn):
    N = prof_normals(prof)
    def f(i, j, t):
        return helm_pt(prof, N, 2 * math.pi * i / nu, j, t, sx, szf, szb)
    slab(b, f, nu, len(prof) - 1, 0.0, th, matfn, wrap=True, mat_in="leather")
    return N

def top_y(prof, z, sz):
    """y of the shell's outer top (x = 0) above |z| (upper profile, radius decreasing)."""
    best = prof[-1][1]
    for j in range(len(prof) - 1):
        r0, r1 = prof[j][0] * sz, prof[j + 1][0] * sz
        if r0 >= abs(z) >= r1 and prof[j + 1][1] > 0.0:
            return prof[j][1] + (prof[j + 1][1] - prof[j][1]) * (r0 - abs(z)) / ((r0 - r1) or 1.0)
    return best

def visor(b, prof, N, nu, th, sx, sz, y0, y1, half, nv_bars, nh_bars):
    """Grille over the dark face window: vertical and horizontal bars standing on the shell."""
    s0, s1 = prof_s(prof, y0), prof_s(prof, y1)
    c = 1.5 * math.pi
    for k in range(nv_bars):
        a = c - half + 2 * half * k / (nv_bars - 1)
        path = [helm_pt(prof, N, a, s0 + (s1 - s0) * m / 3, th + 0.002, sx, sz, sz) for m in range(4)]
        sweep(b, path, lambda i, s, aa: 0.0032, 4, "bronze")
    for k in range(nh_bars):
        s = s0 + (s1 - s0) * k / (nh_bars - 1)
        path = [helm_pt(prof, N, c - half + 2 * half * m / 6, s, th + 0.004, sx, sz, sz) for m in range(7)]
        sweep(b, path, lambda i, ss, aa: 0.0034, 4, "bronze")

def window_mat(prof, nu, y0, y1, half):
    def m(i, j):
        a = 2 * math.pi * (i + 0.5) / nu
        y = 0.5 * (prof[j][1] + prof[j + 1][1])
        return "visor_dark" if abs(a - 1.5 * math.pi) < half and y0 <= y <= y1 else "bronze"
    return m

def brim(b, prof, N, sx, sz, y, width_f, width_b, droop, nu=20):
    s = prof_s(prof, y)
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        x0, _, z0 = helm_pt(prof, N, a, s, 0.004, sx, sz, sz)
        r0 = math.hypot(x0 / sx, z0 / sz)
        w = width_f + (width_b - width_f) * (0.5 + 0.5 * math.sin(a))
        r = r0 + w * j
        return (r * sx * math.cos(a), y - droop * j + t, r * sz * math.sin(a))
    slab(b, f, nu, 1, -0.003, 0.003, "bronze", wrap=True)

MURMILLO = [(0.118, -0.16), (0.112, -0.13), (0.114, -0.085), (0.122, -0.04), (0.125, 0.0), (0.124, 0.04),
            (0.117, 0.075), (0.1, 0.105), (0.075, 0.128), (0.045, 0.142), (0.02, 0.148)]

def build_murmillo(b):
    P, nu, th, sx, sz = MURMILLO, 20, 0.006, 1.0, 1.08
    y0, y1, half = -0.085, 0.04, math.radians(54)
    N = helm_shell(b, P, nu, th, sx, sz, sz, window_mat(P, nu, y0, y1, half))
    visor(b, P, N, nu, th, sx, sz, y0, y1, half - 0.02, 7, 4)
    brim(b, P, N, sx, sz, 0.046, 0.04, 0.065, 0.022)
    # Tall fish-fin crest from brow to nape with a red plume along its top edge.
    zs = [-0.1 + 0.21 * k / 10 for k in range(11)]
    def h(u):
        return 0.13 * math.sin(math.pi * (0.06 + 0.88 * u)) ** 0.7 * (1.15 - 0.45 * u)
    def f(i, j, t):
        z = zs[i]
        base = top_y(P, z, sz) + th - 0.006
        return (t, base + h(i / 10) * j / 2, z + 0.03 * (j / 2) * (i / 10))
    slab(b, f, 10, 2, -0.005, 0.005, "bronze")
    plume = [f(i, 2, 0.0) for i in range(11)]
    sweep(b, plume, lambda i, s, a: 0.006 + 0.01 * math.sin(math.pi * s), 6, "crest")
    lathe(b, sphere_prof(0.03, P[-1][1] + 0.002, 4)[2:], 10, "bronze")

THRAEX = [(0.118, -0.16), (0.112, -0.13), (0.114, -0.085), (0.122, -0.04), (0.126, 0.0), (0.125, 0.04),
          (0.12, 0.08), (0.108, 0.115), (0.088, 0.143), (0.06, 0.162), (0.03, 0.172), (0.014, 0.175)]

def build_thraex(b):
    P, nu, th, sx, sz = THRAEX, 20, 0.006, 1.0, 1.08
    y0, y1, half = -0.085, 0.035, math.radians(54)
    N = helm_shell(b, P, nu, th, sx, sz, sz, window_mat(P, nu, y0, y1, half))
    visor(b, P, N, nu, th, sx, sz, y0, y1, half - 0.02, 9, 5)
    brim(b, P, N, sx, sz, 0.042, 0.06, 0.08, -0.012)
    # Griffin-head crest: a curved neck rising from the crown and sweeping forward, ending in a hooked-beak head.
    neck = [(0.0, 0.15, 0.085), (0.0, 0.19, 0.06), (0.0, 0.215, 0.02), (0.0, 0.222, -0.025), (0.0, 0.212, -0.065)]
    sweep(b, neck, lambda i, s, a: 0.016 + 0.006 * s, 8, "bronze")
    blob(b, (0.0, 0.208, -0.088), 0.022, 0.028, 0.034, "bronze", segs=10, steps=6)
    sweep(b, [(0.0, 0.215, -0.112), (0.0, 0.205, -0.135), (0.0, 0.185, -0.142), (0.0, 0.17, -0.133)],
          lambda i, s, a: 0.012 * (1 - 0.85 * s), 6, "bronze")
    for sx_ in (-1, 1):  # eyes and ear tufts of the griffin
        blob(b, (sx_ * 0.019, 0.218, -0.098), 0.006, 0.006, 0.006, "visor_dark", segs=6, steps=3)
        sweep(b, [(sx_ * 0.012, 0.225, -0.08), (sx_ * 0.02, 0.252, -0.07)], lambda i, s, a: 0.006 * (1 - 0.8 * s), 5,
              "bronze")
    # Red horsehair fall along the back of the neck.
    sweep(b, [(0.0, 0.2, 0.07), (0.0, 0.225, 0.03), (0.0, 0.235, -0.02)], lambda i, s, a: 0.012 * math.sin(math.pi * (0.15 + 0.7 * s)) + 0.004,
          6, "crest")

SECUTOR = [(0.122, -0.165), (0.116, -0.14), (0.114, -0.1), (0.12, -0.05), (0.126, 0.0), (0.126, 0.04),
           (0.12, 0.08), (0.104, 0.115), (0.08, 0.14), (0.05, 0.158), (0.022, 0.166)]

def build_secutor(b):
    P, nu, th, sx, szf, szb = SECUTOR, 20, 0.006, 1.0, 1.12, 1.05
    N = helm_shell(b, P, nu, th, sx, szf, szb, "iron")
    # Two small round eye holes: dark disc in a bronze ring.
    s = prof_s(P, 0.003)
    for ex in (-0.032, 0.032):
        lo, hi = math.pi, 2 * math.pi
        for _ in range(40):
            m = 0.5 * (lo + hi)
            if helm_pt(P, N, m, s, th, sx, szf, szb)[0] < ex:
                lo = m
            else:
                hi = m
        zs = helm_pt(P, N, lo, s, th, sx, szf, szb)[2]
        lathe(b, [(0.011, zs + 0.004), (0.011, zs - 0.0012)], 10, "visor_dark", axis="z", c=(ex, 0.003, 0.0))
        ring = [(ex + 0.0125 * math.cos(2 * math.pi * k / 10), 0.003 + 0.0125 * math.sin(2 * math.pi * k / 10),
                 zs - 0.0005) for k in range(10)]
        ring_tube(b, ring, circ_sec(0.0028, 4), "bronze")
    # Low fin crest from the brow over the crown to the nape.
    zs_ = [-0.125 + 0.235 * k / 10 for k in range(11)]
    def f(i, j, t):
        z = zs_[i]
        base = top_y(P, z, szf if z < 0 else szb) + th - 0.005
        hh = 0.036 * math.sin(math.pi * (0.04 + 0.92 * i / 10)) ** 0.5
        return (t, base + hh * j, z)
    slab(b, f, 10, 1, -0.004, 0.004, "bronze")
    lathe(b, sphere_prof(0.03, P[-1][1] + 0.002, 4)[2:], 10, "iron")
    # Rolled bottom rim.
    ring_tube(b, [helm_pt(P, N, 2 * math.pi * k / 20, 0.0, 0.003, sx, szf, szb) for k in range(20)],
              circ_sec(0.006, 4), "bronze", zref=(0.0, 1.0, 0.0))

# ---------------- torso / pelvis (conform to the body's real cross-sections) ----------------
def hoop(b, env, y0, y1, g0, g1, th, nu, mat):
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        y = (y0, y1)[j]
        return cyl(env.r(a, y) + (g0, g1)[j] + t, a, y)
    slab(b, f, nu, 1, 0.0, th, mat, wrap=True)

def build_lorica_segmentata(b):
    env = Env(torso_in, -0.27, 0.23, 25, 48, 0.03)
    for k in range(6):  # girth hoops, each lapping over the one below
        y0 = -0.235 + 0.05 * k
        hoop(b, env, y0, y0 + 0.055, 0.018, 0.011, 0.003, 24, "iron")
    # Breast and back plates up to the collar.
    for a0, a1 in ((math.radians(208), math.radians(332)), (math.radians(28), math.radians(152))):
        ys = [0.06, 0.11, 0.16, 0.205]
        def f(i, j, t, a0=a0, a1=a1, ys=ys):
            a = a0 + (a1 - a0) * i / 8
            return cyl(env.r(a, ys[j]) + 0.012 + t, a, ys[j])
        slab(b, f, 8, 3, 0.0, 0.003, "iron")
    # Shoulder guards: four curved lames arching front-to-back over each shoulder, outer ones lapping over inner.
    th_s = [math.radians(-100 + 200 * i / 8) for i in range(9)]
    for sx in (1, -1):
        for k in range(4):
            xk = sx * (0.085 + 0.036 * k)
            rr = []
            for th in th_s:
                d = (0.0, math.cos(th), math.sin(th))
                rr.append(max(extent(torso_in, (xk + dx, 0.12, 0.0), d, 0.25) for dx in (-0.024, 0.0, 0.024)))
            def f(i, j, t, xk=xk, rr=rr, k=k):
                r = rr[i] + 0.013 + 0.005 * k + t
                return (xk + (j - 0.5) * 0.046, 0.12 + r * math.cos(th_s[i]), r * math.sin(th_s[i]))
            slab(b, f, 8, 1, 0.0, 0.003, "iron")
    # Bronze lacing hinge plates on the front of each hoop.
    for k in range(6):
        y = -0.235 + 0.05 * k + 0.028
        z = -env.r(1.5 * math.pi, y) - 0.021
        box(b, (-0.012, y - 0.012, z - 0.003), (0.012, y + 0.012, z + 0.002), "bronze")

def squam_top(a):
    return 0.19 - 0.09 * math.cos(a) ** 2

def build_lorica_squamata(b):
    env = Env(torso_in, -0.27, 0.21, 24, 48, 0.03)
    nu, nv, y0, g = 24, 7, -0.255, 0.008
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        y = y0 + (squam_top(a) - y0) * j / nv
        return cyl(env.r(a, y) + g + t, a, y)
    slab(b, f, nu, nv, 0.0, 0.004, "leather", wrap=True)
    # Rows of small bronze scales, staggered, each overlapping the row below.
    ro = g + 0.004
    step = 2 * math.pi / 24
    for row in range(9):
        yt = 0.172 - 0.046 * row
        yb = yt - 0.06
        for k in range(24):
            ac = (k + 0.5 * (row % 2)) * step
            if yt > squam_top(ac) - 0.01 or yb < y0 - 0.012:
                continue
            h = 0.47 * step
            tl = cyl(env.r(ac - h, yt) + ro + 0.0008, ac - h, yt)
            tr = cyl(env.r(ac + h, yt) + ro + 0.0008, ac + h, yt)
            tip = cyl(env.r(ac, yb) + ro + 0.0065 + 0.002 * row / 8, ac, yb)
            back = cyl(env.r(ac, yb) + ro + 0.0006, ac, yb)
            tetra(b, [tl, tr, tip, back], "bronze")
    # Leather shoulder straps (humeral bands) from the front edge over the shoulders to the back.
    th_s = [math.radians(-95 + 190 * i / 6) for i in range(7)]
    for sx in (1, -1):
        xk = sx * 0.115
        rr = [max(extent(torso_in, (xk + dx, 0.11, 0.0), (0.0, math.cos(th), math.sin(th)), 0.25)
                  for dx in (-0.035, 0.0, 0.035)) for th in th_s]
        def f2(i, j, t, xk=xk, rr=rr):
            r = rr[i] + 0.012 + t
            return (xk + (j - 0.5) * 0.065, 0.11 + r * math.cos(th_s[i]), r * math.sin(th_s[i]))
        slab(b, f2, 6, 1, 0.0, 0.005, "leather")

def build_balteus(b):
    env = Env(pelvis_in, -0.04, 0.13, 17, 56, 0.0)
    nu, ys = 28, [-0.005, 0.03, 0.065, 0.1]
    rmax = [max(env.r(2 * math.pi * i / nu, y) for y in [ys[0] + 0.005 * m for m in range(22)]) for i in range(nu)]
    rmax = [max(rmax[i - 1], rmax[i], rmax[(i + 1) % nu]) + 0.007 for i in range(nu)]
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        return cyl(rmax[i] + t + 0.002 * math.sin(math.pi * j / 3), a, ys[j])
    slab(b, f, nu, 3, 0.0, 0.005, "bronze", wrap=True)
    for y in (ys[0], ys[-1]):  # rolled edges
        path = [cyl(rmax[i] + 0.0035, 2 * math.pi * i / nu, y) for i in range(nu)]
        ring_tube(b, path, circ_sec(0.0045, 4), "bronze", zref=(0.0, 1.0, 0.0))
    for i in range(0, nu, 2):  # row of domed studs
        a = 2 * math.pi * (i + 0.5) / nu
        r = 0.5 * (rmax[i] + rmax[(i + 1) % nu]) + 0.006
        c = cyl(r, a, 0.0475)
        prof = sphere_prof(0.009, 0.0, 4)[2:]
        rings = []
        for rad, hgt in prof:
            n = (math.cos(a), 0.0, math.sin(a))
            u = (-math.sin(a), 0.0, math.cos(a))
            rings.append([tuple(c[k] + hgt * n[k] + rad * (math.cos(2 * math.pi * m / 6) * u[k]
                                                            + (math.sin(2 * math.pi * m / 6) if k == 1 else 0.0))
                                for k in range(3)) for m in range(6)])
        b.loft(rings, "gold")
    # Front buckle plate.
    zf_ = -rmax[nu * 3 // 4] - 0.006
    box(b, (-0.03, 0.005, zf_ - 0.004), (0.03, 0.09, zf_ + 0.002), "gold")

def build_subligaculum(b):
    env = Env(pelvis_in, -0.13, 0.11, 24, 48, 0.012)
    nu = 24
    ys = [-0.12, -0.105, -0.08, -0.04, 0.0, 0.04, 0.075]
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        return cyl(env.r(a, ys[j]) + 0.005 + t, a, ys[j])
    slab(b, f, nu, len(ys) - 1, 0.0, 0.003, "linen", wrap=True)
    # Leather belt over the cloth.
    rb = [max(env.r(2 * math.pi * i / nu, y) for y in (0.03, 0.045, 0.06, 0.075, 0.09)) + 0.012 for i in range(nu)]
    def fb(i, j, t):
        a = 2 * math.pi * i / nu
        return cyl(rb[i] + t, a, (0.035, 0.08)[j])
    slab(b, fb, nu, 1, 0.0, 0.005, "leather", wrap=True)
    # Front and back hanging flaps: follow the body, then hang straight down below the crotch.
    for side, ylow, w0, w1 in ((-1, -0.22, 0.075, 0.05), (1, -0.19, 0.08, 0.06)):
        ys_ = [0.06, 0.02, -0.03, -0.08, -0.11, -0.16, ylow]
        zz = {}
        def fz(x, y):
            yy = max(y, -0.11)
            key = (round(x, 4), round(yy, 4))
            if key not in zz:
                zz[key] = side * (max(extent(pelvis_in, (x, yy2, 0.0), (0.0, 0.0, side), 0.2)
                                      for yy2 in (yy, yy + 0.015, yy - 0.015)) + 0.02)
            return zz[key]
        def ff(i, j, t, ys_=ys_, w0=w0, w1=w1, side=side):
            y = ys_[i]
            w = w0 + (w1 - w0) * i / (len(ys_) - 1)
            x = (j / 2 - 0.5) * 2 * w
            sway = 0.006 * math.sin(3.0 * x / w0) if y < -0.1 else 0.0
            return (x, y, max(fz(x2, y) * side for x2 in (-w, 0.0, w)) * side + side * (t + sway))
        slab(b, ff, len(ys_) - 1, 2, 0.0, 0.004, "linen")
    zk = -rb[nu * 3 // 4] - 0.005
    blob(b, (0.0, 0.058, zk - 0.01), 0.022, 0.018, 0.012, "leather", segs=8, steps=4)

# ---------------- arms (upper_arm frame, right side native, outward +X) ----------------
def dome(b, c, d, r, ph0, ph1, nu, nv, th, mat, sy=1.0):
    d = vnorm(d)
    e1 = vnorm(vcross(d, (0.0, 0.0, 1.0)))
    e2 = vcross(d, e1)
    def f(i, j, t):
        ph = ph0 + (ph1 - ph0) * j / nv
        ps = 2 * math.pi * i / nu
        v = [math.cos(ph) * d[k] + math.sin(ph) * (math.cos(ps) * e1[k] + math.sin(ps) * e2[k]) for k in range(3)]
        rr = r + t
        return (c[0] + rr * v[0], c[1] + rr * v[1] * sy, c[2] + rr * v[2])
    slab(b, f, nu, nv, 0.0, th, mat, wrap=True)

def lame(b, y0, y1, r, a_half, nu, th, mat, flare=0.004):
    def f(i, j, t):
        a = -a_half + 2 * a_half * i / nu
        rr = r + t + flare * (1 - j)
        return cyl(rr, a, (y0, y1)[j])
    slab(b, f, nu, 1, 0.0, th, mat)

def band(b, y0, y1, r, th, nu, mat, sz=1.0):
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        return ((r + t) * math.cos(a), (y0, y1)[j], (r + t) * sz * math.sin(a))
    slab(b, f, nu, 1, 0.0, th, mat, wrap=True)

def build_spaulder_r(b):
    d = (math.sin(math.radians(35)), math.cos(math.radians(35)), 0.0)
    dome(b, (0.0, 0.1, 0.0), d, 0.088, math.radians(8), math.radians(80), 16, 5, 0.005, "bronze")
    lathe(b, sphere_prof(0.014, 0.0, 4)[2:], 8, "bronze", c=(0.088 * d[0] * 0.99, 0.1 + 0.088 * d[1] * 0.99, 0.0))
    lame(b, 0.05, 0.093, 0.087, math.radians(75), 8, 0.004, "bronze")
    lame(b, 0.014, 0.058, 0.083, math.radians(70), 8, 0.004, "bronze")
    band(b, -0.008, 0.012, 0.079, 0.004, 16, "leather")

def build_galerus_r(b):
    # Tall shoulder guard: a shoulder cap and three lames on the outside, and a tall plate rising from the neck side of
    # the shoulder whose top flares away from the head (native right: neck side = -X).
    d = (math.sin(math.radians(30)), math.cos(math.radians(30)), 0.0)
    dome(b, (0.0, 0.1, 0.0), d, 0.09, math.radians(8), math.radians(84), 16, 5, 0.005, "bronze")
    lathe(b, sphere_prof(0.014, 0.0, 4)[2:], 8, "bronze", c=(0.09 * d[0] * 0.99, 0.1 + 0.09 * d[1] * 0.99, 0.0))
    for y0, r in ((0.045, 0.092), (0.01, 0.088), (-0.025, 0.084)):
        lame(b, y0, y0 + 0.045, r, math.radians(80), 8, 0.004, "bronze")
    band(b, -0.05, -0.03, 0.075, 0.004, 16, "leather")
    def fl(i, j, t):
        u, v = i / 8, j / 4
        hw = 0.075 + 0.03 * v
        z = (2 * u - 1) * hw
        x = -0.062 + 0.055 * v ** 1.6 - 0.03 * (2 * u - 1) ** 2 * (0.3 + 0.7 * v)
        y = 0.158 + 0.17 * v + 0.012 * (1 - (2 * u - 1) ** 2) * v
        return (x + t, y, z)
    slab(b, fl, 8, 4, -0.0025, 0.0025, "bronze")
    ring_tube(b, [fl(i, 4, 0.0) for i in range(9)], circ_sec(0.0055, 5), "bronze", closed=False,
              zref=(1.0, 0.0, 0.0))
    for i in (2, 6):  # two raised ribs on the plate
        sweep(b, [fl(i, j, -0.0035) for j in range(5)], lambda ii, s, a: 0.004, 4, "bronze")

# ---------------- legs (thigh frame) ----------------
def thigh_r(a, y):
    rxo, rxi, rzf, rzb = rowinterp(y, sorted(THIGH))
    k = 1.0 + 0.1 * gauss((y - 0.08) / 0.12, 0.0)
    c, s = math.cos(a), math.sin(a)
    return (rxo if c > 0 else rxi) * k, (rzb if s > 0 else rzf) * k

def build_fasciae_r(b):
    # Padded linen wraps spiralling round the thigh from above the knee to the upper thigh, tied with leather.
    nu, ys = 16, [-0.165 + 0.33 * j / 18 for j in range(19)]
    def ring_pt(a, y, off):
        rx, rz = thigh_r(a, y)
        return ((rx + off) * math.cos(a), y, (rz + off) * math.sin(a))
    def f(i, j, t):
        a = 2 * math.pi * i / nu
        y = ys[j]
        phase = (y + 0.165) / 0.055 + a / (2 * math.pi)
        pad = 0.007 * math.sin(math.pi * phase) ** 2
        return ring_pt(a, y, 0.016 + pad + t)
    slab(b, f, nu, len(ys) - 1, 0.0, 0.006, "linen", wrap=True)
    for y0 in (-0.158, 0.14):
        def ft(i, j, t, y0=y0):
            a = 2 * math.pi * i / nu
            y = y0 + 0.016 * j
            return ring_pt(a, y, 0.03 + t)
        slab(b, ft, nu, 1, 0.0, 0.004, "leather", wrap=True)
'''


def make_materials():
    mat = hou.node("/mat")
    for name, spec in list(MATERIALS.items()) + list(REF_MATERIALS.items()):
        if mat.node(name):
            continue
        col, rough, metal = spec[:3]
        m = mat.createNode("principledshader::2.0", name)
        m.parmTuple("basecolor").set(col)
        m.parm("rough").set(rough)
        m.parm("metallic").set(metal)


def make_piece(pid, x_offset):
    obj = hou.node("/obj").createNode("geo", pid)
    obj.parmTuple("t").set((x_offset, 0, 0))
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild_%s(B(hou.pwd().geometry()))\n" % MIRROR.get(pid, pid))
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
    rop.parm("outputfile").set("$HIP/../export/%s/%s.glb" % (GROUP, pid))
    rop.parm("exportmaterials").set(1)
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    return obj, out, rop


def make_body_ref(pid, part, x_offset, armor_out):
    """Body part (build_body.py's own builder, mirrored for _l pieces) next to the armor, plus its SDF sampled at
    the armor points. Returns (obj, sampled armor geometry SOP)."""
    obj = hou.node("/obj").createNode("geo", pid + "_body")
    obj.parmTuple("t").set((x_offset, 0, 0))
    py = obj.createNode("python", "build")
    mx = -1.0 if pid in MIRROR else 1.0
    py.parm("python").set(BODY_LIB + "\nb = B(hou.pwd().geometry(), %r)\n%s\n" % (mx, BODY_CALL[part]))
    py.setDisplayFlag(True)
    py.setRenderFlag(True)
    vdb = obj.createNode("vdbfrompolygons", "sdf")
    vdb.setInput(0, py)
    vdb.parm("voxelsize").set(0.002)
    vdb.parm("exteriorbandvoxels").set(30)
    vdb.parm("fillinterior").set(1)
    om = obj.createNode("object_merge", "armor")
    om.parm("objpath1").set(armor_out.path())
    om.parm("xformtype").set(0)
    wr = obj.createNode("attribwrangle", "sample")
    wr.setInput(0, om)
    wr.setInput(1, vdb)
    wr.parm("snippet").set("f@sdf = volumesample(1, 0, @P);")
    obj.layoutChildren()
    return obj, wr


def prim_clear(part, geo):
    kind = PRIM[part]
    best = 1e9
    for p in geo.points():
        x, y, z = p.position()
        if kind[0] == "sphere":
            d = math.sqrt(x * x + y * y + z * z) - kind[1]
        elif kind[0] == "capsule":
            yy = max(-kind[2], min(kind[2], y))
            d = math.sqrt(x * x + (y - yy) ** 2 + z * z) - kind[1]
        else:
            q = [abs(x) - kind[1][0], abs(y) - kind[1][1], abs(z) - kind[1][2]]
            d = math.sqrt(sum(max(v, 0.0) ** 2 for v in q)) + min(max(q), 0.0)
        best = min(best, d)
    return best


def render_previews(objs, refs):
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
    os.makedirs(os.path.join(PREVIEW, "fit"), exist_ok=True)

    def shoot(path, names, bb, t, yaw):
        c = bb.center() + hou.Vector3(t)
        size = bb.sizevec()
        r = hou.hmath.buildRotate((-15, yaw, 0), "xyz")
        cam.setWorldTransform(r * hou.hmath.buildTranslate(hou.Vector3(c) + hou.Vector3(0, 0, 20) * r))
        cam.parm("orthowidth").set(max(size[0], size[1], size[2]) * 1.2)
        rop.parm("candobjects").set(" ".join(names))
        rop.parm("picture").set(path)
        rop.render()

    for pid, (obj, out) in objs.items():
        yaw = PIECES[pid][2]
        t = obj.parmTuple("t").eval()
        bb = out.geometry().boundingBox()
        shoot(os.path.join(PREVIEW, pid + ".png"), [obj.name()], bb, t, yaw)
        if pid in refs:
            ref = refs[pid][0]
            bb2 = hou.BoundingBox(bb)
            bb2.enlargeToContain(ref.node("build").geometry().boundingBox())
            shoot(os.path.join(PREVIEW, "fit", pid + ".png"), [obj.name(), ref.name()], bb2, t, yaw)


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    for d in (os.path.dirname(HIP), EXPORT, PREVIEW):
        os.makedirs(d, exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    objs, rops, refs = {}, {}, {}
    x = 0.0
    for pid in PIECES:
        obj, out, rop = make_piece(pid, x)
        objs[pid] = (obj, out)
        rops[pid] = rop
        part = PIECES[pid][3]
        if part:
            refs[pid] = make_body_ref(pid, part, x, out)
        x += max(out.geometry().boundingBox().sizevec()[0], 0.4) + 1.0
    hou.hipFile.save(HIP)

    ok = True
    for pid, (group, max_tris, _, part) in PIECES.items():
        rops[pid].render()
        path = os.path.join(EXPORT, pid + ".glb")
        tris, lo, hi, vol, mnames = read_glb(path)
        good = tris <= max_tris and vol > 0
        extra = ""
        if part:
            prim = prim_clear(part, objs[pid][1].geometry())
            mesh, where = min((p.attribValue("sdf"), tuple(round(v, 3) for v in p.position())) for p in refs[pid][1].geometry().points())
            good = good and mesh >= 0.0 and (prim >= 0.0 or PRIM[part][0] == "box")
            extra = " part=%s prim(%s)=%+.4f mesh=%+.4f@%s" % (part, PRIM[part][0], prim, mesh, where)
        ok = ok and good
        print("%-18s %-7s %s tris=%5d size=%6.1f KB vol=%.5f bbox=(%.3f %.3f %.3f)..(%.3f %.3f %.3f)%s mats=%s" % (
            pid, group, "OK  " if good else "FAIL", tris, os.path.getsize(path) / 1024.0, vol, *lo, *hi, extra,
            ",".join(mnames)))

    if "--no-preview" not in sys.argv:
        try:
            render_previews(objs, refs)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
