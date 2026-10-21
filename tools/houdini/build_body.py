"""Build the Sandblood fighter body (segmented ragdoll parts) procedurally and export .glb files.

Run:  hython scripts/build_body.py [--no-preview] [--detail]   (re-runnable; rebuilds hip, exports, previews)

Conventions: metres, Y up, -Z forward (face/chest/toes toward -Z). Each part is modelled in its
own local frame with the origin at the part centre, posed in the standing rest pose.
Right-side parts are built natively (outward = +X); left parts are mirrored copies.
Cap meshes: flat disc, normal +Y, centred at the origin.
"""
import json
import math
import os
import struct
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "body.hip")
EXPORT = os.path.join(ROOT, "export", "body")
PREVIEW = os.path.join(ROOT, "preview")

# name: (rest-pose world centre, builder call, mirror x, physics bbox lo, physics bbox hi)
SHIN_LO, SHIN_HI = (-0.05, -0.27, -0.185), (0.05, 0.21, 0.065)  # capsule + foot box
PARTS = {
    "pelvis": ((0, 0.98, 0), "build_pelvis(b)", 1, (-0.16, -0.10, -0.10), (0.16, 0.10, 0.10)),
    "torso": ((0, 1.33, 0), "build_torso(b)", 1, (-0.18, -0.24, -0.11), (0.18, 0.24, 0.11)),
    "head": ((0, 1.70, 0), "build_head(b, False)", 1, (-0.11,) * 3, (0.11,) * 3),
    "head_b": ((0, 1.70, 0), "build_head(b, True)", 1, (-0.11,) * 3, (0.11,) * 3),
    "upper_arm_l": ((-0.23, 1.39, 0), "build_upper_arm(b)", -1, (-0.05, -0.15, -0.05), (0.05, 0.15, 0.05)),
    "upper_arm_r": ((0.23, 1.39, 0), "build_upper_arm(b)", 1, (-0.05, -0.15, -0.05), (0.05, 0.15, 0.05)),
    "forearm_l": ((-0.23, 1.08, 0), "build_forearm(b)", -1, (-0.045, -0.17, -0.045), (0.045, 0.17, 0.045)),
    "forearm_r": ((0.23, 1.08, 0), "build_forearm(b)", 1, (-0.045, -0.17, -0.045), (0.045, 0.17, 0.045)),
    "thigh_l": ((-0.10, 0.68, 0), "build_thigh(b)", -1, (-0.07, -0.22, -0.07), (0.07, 0.22, 0.07)),
    "thigh_r": ((0.10, 0.68, 0), "build_thigh(b)", 1, (-0.07, -0.22, -0.07), (0.07, 0.22, 0.07)),
    "shin_l": ((-0.10, 0.27, 0), "build_shin(b)", -1, SHIN_LO, SHIN_HI),
    "shin_r": ((0.10, 0.27, 0), "build_shin(b)", 1, SHIN_LO, SHIN_HI),
}
# cap name: (outer radius, bones [(x, z, r)])
CAPS = {
    "cap_neck": (0.058, [(0.0, 0.018, 0.012)]),
    "cap_shoulder": (0.052, [(0.0, 0.0, 0.014)]),
    "cap_elbow": (0.045, [(0.012, 0.0, 0.009), (-0.013, 0.004, 0.008)]),
    "cap_hip": (0.078, [(0.0, 0.0, 0.017)]),
    "cap_knee": (0.052, [(0.0, -0.008, 0.016), (0.03, 0.01, 0.007)]),
}

# name: (base color (linear), roughness, metallic)
MATERIALS = {
    "skin": ((0.56, 0.31, 0.19), 0.55, 0.0),
    "cloth": ((0.85, 0.84, 0.80), 0.9, 0.0),
    "leather": ((0.20, 0.10, 0.045), 0.7, 0.0),
    "hair": ((0.045, 0.03, 0.02), 0.8, 0.0),
    "flesh": ((0.75, 0.04, 0.04), 0.4, 0.0),
    "bone": ((0.85, 0.82, 0.70), 0.5, 0.0),
    "fat": ((0.90, 0.80, 0.40), 0.5, 0.0),
}

# Geometry library, embedded in each Python SOP so the .hip is self-contained.
LIB = r'''
import math

def interp(s, table):
    if s <= table[0][0]:
        return table[0][1]
    for (s0, v0), (s1, v1) in zip(table, table[1:]):
        if s <= s1:
            return v0 + (v1 - v0) * (s - s0) / (s1 - s0)
    return table[-1][1]

def rowinterp(y, rows):
    """Catmull-Rom through rows [(y, v...)] sorted by y; returns the tuple of values."""
    n = len(rows)
    if y <= rows[0][0]:
        return rows[0][1:]
    if y >= rows[-1][0]:
        return rows[-1][1:]
    i = 0
    while y > rows[i + 1][0]:
        i += 1
    t = (y - rows[i][0]) / (rows[i + 1][0] - rows[i][0])
    p0, p1, p2, p3 = rows[max(i - 1, 0)][1:], rows[i][1:], rows[i + 1][1:], rows[min(i + 2, n - 1)][1:]
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                 for a, b, c, d in zip(p0, p1, p2, p3))

def gauss(dx, dy):
    return math.exp(-(dx * dx + dy * dy))

def newell(cs):
    n = [0.0, 0.0, 0.0]
    for i in range(len(cs)):
        a = cs[i]; b = cs[(i + 1) % len(cs)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n

def centroid(cs):
    k = len(cs)
    return [sum(c[i] for c in cs) / k for i in range(3)]

def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

def sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

def norm(a):
    l = math.sqrt(dot(a, a)) or 1.0
    return [a[0] / l, a[1] / l, a[2] / l]

class B:
    def __init__(self, geo, mx=1.0):
        self.geo = geo
        self.mx = mx
        geo.addAttrib(hou.attribType.Vertex, "uv", (0.0, 0.0, 0.0))
        geo.addAttrib(hou.attribType.Prim, "shop_materialpath", "")
        # Houdini's polygon winding relative to Newell (right-hand) order.
        pts = [geo.createPoint() for _ in range(3)]
        for p, c in zip(pts, [(0, 0, 0), (1, 0, 0), (0, 1, 0)]):
            p.setPosition(c)
        t = geo.createPolygon()
        for p in pts:
            t.addVertex(p)
        self.sign = 1.0 if t.normal()[2] > 0 else -1.0
        geo.deletePrims([t])
        geo.deletePoints(pts)

    def pts(self, coords):
        out = []
        for c in coords:
            p = self.geo.createPoint()
            p.setPosition(c)
            out.append(p)
        return out

    def poly(self, pts, uvs, mat):
        p = self.geo.createPolygon()
        for pt, uv in zip(pts, uvs):
            v = p.addVertex(pt)
            v.setAttribValue("uv", (uv[0], uv[1], 0.0))
        p.setAttribValue("shop_materialpath", "/mat/" + mat)

    def facing(self, cs, out):
        return self.sign * dot(newell(cs), out) >= 0

    def face(self, cs, mat, out):
        """Single flat polygon oriented toward `out`, planar UVs."""
        if not self.facing(cs, out):
            cs = cs[::-1]
        self.poly(self.pts(cs), [(c[0] * 5 + 0.5, c[2] * 5 + 0.5) for c in cs], mat)

    def loft(self, rings, mat, cap0=True, cap1=True, wrap=False, closed=True):
        if self.mx < 0:
            rings = [[(-c[0], c[1], c[2]) for c in r] for r in rings]
        if not closed:
            cap0 = cap1 = False
        n = len(rings[0])
        P = [self.pts(r) for r in rings]
        cs = [centroid(r) for r in rings]
        d = [0.0]
        for a, b in zip(cs, cs[1:]):
            d.append(d[-1] + math.dist(a, b))
        if wrap:
            d.append(d[-1] + math.dist(cs[-1], cs[0]))
        tot = d[-1] or 1.0
        bands = len(rings) if wrap else len(rings) - 1
        cols = n if closed else n - 1
        quads = []
        votes = 0.0
        for k in range(bands):
            k2 = (k + 1) % len(rings)
            axis = centroid([cs[k], cs[k2]])
            for j in range(cols):
                j2 = (j + 1) % n
                q = [(k, j), (k, j2), (k2, j2), (k2, j)]
                c = [rings[a][b] for a, b in q]
                votes += self.sign * dot(newell(c), sub(centroid(c), axis))
                uv = [(j / cols, d[k] / tot), ((j + 1) / cols, d[k] / tot),
                      ((j + 1) / cols, d[k + 1] / tot), (j / cols, d[k + 1] / tot)]
                m = mat[k] if isinstance(mat, (list, tuple)) else mat
                quads.append((q, uv, m))
        for q, uv, m in quads:
            if votes < 0:
                q = q[::-1]; uv = uv[::-1]
            self.poly([P[a][b] for a, b in q], uv, m)
        if wrap:
            return
        for idx, nb, use in ((0, 1, cap0), (len(rings) - 1, len(rings) - 2, cap1)):
            if not use:
                continue
            m = mat[0 if idx == 0 else -1] if isinstance(mat, (list, tuple)) else mat
            ring = rings[idx]
            order = list(range(n))
            if not self.facing(ring, sub(cs[idx], cs[nb])):
                order = order[::-1]
            uv = [(0.5 + 0.5 * math.cos(2 * math.pi * j / n), 0.5 + 0.5 * math.sin(2 * math.pi * j / n)) for j in order]
            self.poly([P[idx][j] for j in order], uv, m)

def xring(y, rxo, rxi, rzf, rzb, segs, cx=0.0, cz=0.0, bump=None, p=2.0):
    """Horizontal ring: outward(+X)/inward x radii, front(-Z)/back z radii, superellipse exponent p.
    bump(x, y, c, s) returns a radial offset."""
    out = []
    e = 2.0 / p
    for j in range(segs):
        a = 2 * math.pi * j / segs
        c, s = math.cos(a), math.sin(a)
        rx = max(rxo if c > 0 else rxi, 0.001)
        rz = max(rzb if s > 0 else rzf, 0.001)
        x = cx + rx * math.copysign(abs(c) ** e, c)
        z = cz + rz * math.copysign(abs(s) ** e, s)
        if bump:
            k = bump(x, y, c, s)
            x += k * c; z += k * s
        out.append((x, y, z))
    return out

def limb(b, rows, segs, mat, bump=None, ys=None, p=2.0, bulk=None):
    """rows: [(y, rxo, rxi, rzf, rzb[, cz])] sorted by y. ys: resample heights (default: the rows).
    bulk(y): radius multiplier."""
    srt = sorted(rows)
    if bulk:
        srt = [(r[0],) + tuple(v * bulk(r[0]) for v in r[1:5]) + tuple(r[5:]) for r in srt]
    if ys is None:
        ys = [r[0] for r in srt]
    rings = []
    for y in ys:
        v = rowinterp(y, srt)
        cz = v[4] if len(v) > 4 else 0.0
        rings.append(xring(y, v[0], v[1], v[2], v[3], segs, 0.0, cz, bump, p))
    b.loft(rings, mat)

def ellipsoid(b, c, rx, ry, rz, segs, rings, mat):
    rs = []
    for k in range(rings + 1):
        phi = math.pi * k / rings
        sr = max(math.sin(phi), 0.05)
        rs.append(xring(c[1] - ry * math.cos(phi), rx * sr, rx * sr, rz * sr, rz * sr, segs, c[0], c[2]))
    b.loft(rs, mat)

def tube(b, path, radii, segs, mat):
    """Swept tube with rounded ends (parallel-transport frames)."""
    t0 = norm(sub(path[1], path[0])); t1 = norm(sub(path[-1], path[-2]))
    r0, r1 = radii[0], radii[-1]
    path = ([[path[0][k] - t0[k] * r0 * f for k in range(3)] for f in (0.85, 0.5)] + [list(p) for p in path]
            + [[path[-1][k] + t1[k] * r1 * f for k in range(3)] for f in (0.5, 0.85)])
    radii = [r0 * 0.5, r0 * 0.85] + list(radii) + [r1 * 0.85, r1 * 0.5]
    ref = [0, 1, 0] if abs(t0[1]) < 0.9 else [1, 0, 0]
    nrm = norm(cross(t0, ref))
    rings = []
    n = len(path)
    for i in range(n):
        t = norm(sub(path[min(i + 1, n - 1)], path[max(i - 1, 0)]))
        nrm = norm(sub(nrm, [t[k] * dot(nrm, t) for k in range(3)]))
        bi = cross(t, nrm)
        r = radii[i]
        rings.append([tuple(path[i][k] + r * (math.cos(2 * math.pi * j / segs) * nrm[k]
                                              + math.sin(2 * math.pi * j / segs) * bi[k]) for k in range(3))
                      for j in range(segs)])
    b.loft(rings, mat)

# ---------------------------------------------------------------- arms

UPPER_ARM = [
    (0.172, 0.014, 0.014, 0.014, 0.014),
    (0.16, 0.033, 0.031, 0.033, 0.033),
    (0.14, 0.046, 0.043, 0.046, 0.047),
    (0.11, 0.053, 0.047, 0.051, 0.053),
    (0.07, 0.056, 0.048, 0.054, 0.058),
    (0.03, 0.056, 0.048, 0.060, 0.055),
    (-0.01, 0.054, 0.047, 0.061, 0.052),
    (-0.05, 0.051, 0.046, 0.056, 0.048),
    (-0.09, 0.047, 0.045, 0.047, 0.045),
    (-0.12, 0.047, 0.046, 0.042, 0.044),
    (-0.145, 0.042, 0.040, 0.036, 0.040),
    (-0.16, 0.032, 0.030, 0.028, 0.033),
    (-0.172, 0.015, 0.015, 0.015, 0.015),
]

def build_upper_arm(b):
    def bump(x, y, c, s):
        return 0.005 * gauss((y - 0.0) / 0.05, (c + 0.2) / 0.5) * max(-s, 0.0)  # biceps peak
    limb(b, UPPER_ARM, 16, "skin", bump, bulk=lambda y: 1.0 + 0.17 * gauss(y / 0.1, 0.0))

FOREARM = [
    (-0.105, 0.012, 0.011, 0.016, 0.015),
    (-0.095, 0.020, 0.018, 0.026, 0.024),
    (-0.08, 0.022, 0.020, 0.028, 0.026),
    (-0.05, 0.031, 0.028, 0.031, 0.027),
    (-0.01, 0.039, 0.034, 0.036, 0.032),
    (0.04, 0.046, 0.040, 0.042, 0.038),
    (0.09, 0.050, 0.043, 0.046, 0.043),
    (0.13, 0.048, 0.044, 0.043, 0.046),
    (0.16, 0.039, 0.038, 0.036, 0.042),
    (0.18, 0.026, 0.026, 0.026, 0.028),
    (0.19, 0.012, 0.012, 0.012, 0.013),
]

def build_hand(b, cy=-0.14):
    """Fist around a bar along Z through (0, cy, 0). Right hand: back of hand outward (+X),
    palm facing inward, thumb forward (-Z)."""
    plate = [
        (-0.083, 0.020, 0.018, 0.026, 0.024, 0.0),
        (-0.10, 0.020, 0.016, 0.036, 0.034, 0.0),
        (-0.12, 0.016, 0.014, 0.043, 0.041, 0.0),
        (-0.145, 0.015, 0.014, 0.045, 0.043, 0.0),
        (-0.165, 0.014, 0.012, 0.043, 0.041, 0.0),
        (-0.172, 0.009, 0.008, 0.035, 0.033, 0.0),
    ]
    # plate centre drifts outward from the wrist to sit behind the bar
    srt = sorted(plate)
    rings = []
    for y in [r[0] for r in srt]:
        v = rowinterp(y, srt)
        cx = interp(-y, [(0.083, 0.0), (0.12, 0.022), (0.145, 0.032), (0.172, 0.03)])
        rings.append(xring(y, v[0], v[1], v[2], v[3], 14, cx, 0.0, None, 2.6))
    b.loft(rings, "skin")
    # fingers: index at front (-Z) to little finger at back
    for z, r, R in ((-0.031, 0.0098, 0.0272), (-0.010, 0.0100, 0.0274), (0.011, 0.0095, 0.0270), (0.030, 0.0085, 0.0262)):
        a0, a1 = math.radians(-35), math.radians(-232)
        n = 8
        path = [(R * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + R * math.sin(a0 + (a1 - a0) * i / (n - 1)), z)
                for i in range(n)]
        path[0] = (path[0][0] + 0.004, path[0][1], z)  # knuckle sits into the hand
        tube(b, path, [r * (1.08 if i == 1 else 1.0 - 0.15 * i / (n - 1)) for i in range(n)], 8, "skin")
    # thumb wraps over the front of the bar
    tube(b, [(0.004, -0.098, -0.03), (-0.008, -0.11, -0.046), (-0.022, -0.121, -0.046),
             (-0.03, -0.128, -0.033), (-0.032, -0.132, -0.021)],
         [0.0125, 0.0115, 0.0105, 0.0095, 0.0088], 8, "skin")

def build_forearm(b):
    limb(b, FOREARM, 16, "skin", bulk=lambda y: 1.0 + 0.14 * gauss((y - 0.08) / 0.07, 0.0))
    build_hand(b)

# ---------------------------------------------------------------- legs

THIGH = [
    (0.252, 0.016, 0.016, 0.016, 0.016),
    (0.24, 0.045, 0.040, 0.045, 0.050),
    (0.22, 0.070, 0.062, 0.068, 0.075),
    (0.18, 0.082, 0.070, 0.075, 0.082),
    (0.12, 0.083, 0.072, 0.080, 0.076),
    (0.05, 0.078, 0.068, 0.081, 0.071),
    (-0.03, 0.070, 0.064, 0.076, 0.065),
    (-0.10, 0.063, 0.059, 0.067, 0.058),
    (-0.15, 0.059, 0.056, 0.061, 0.055),
    (-0.19, 0.059, 0.057, 0.063, 0.053),
    (-0.22, 0.050, 0.048, 0.050, 0.046),
    (-0.24, 0.035, 0.034, 0.034, 0.033),
    (-0.252, 0.015, 0.015, 0.015, 0.015),
]

def build_thigh(b):
    def bump(x, y, c, s):
        f = max(-s, 0.0)
        return (0.008 * gauss((y + 0.185) / 0.025, x / 0.03) * f        # kneecap
                + 0.006 * gauss((y - 0.05) / 0.08, (x + 0.01) / 0.04) * f  # rectus femoris
                + 0.005 * gauss((y + 0.14) / 0.03, (x + 0.045) / 0.025) * f)  # vastus medialis teardrop
    ys = [r[0] for r in sorted(THIGH)]
    ys = sorted(set(ys + [-0.205, -0.17, -0.125, 0.0]))
    limb(b, THIGH, 16, "skin", bump, ys, bulk=lambda y: 1.0 + 0.1 * gauss((y - 0.08) / 0.12, 0.0))

SHIN = [
    (-0.205, 0.012, 0.012, 0.014, 0.014),
    (-0.19, 0.033, 0.032, 0.034, 0.038),
    (-0.16, 0.028, 0.027, 0.030, 0.030),
    (-0.11, 0.031, 0.030, 0.032, 0.033),
    (-0.05, 0.038, 0.036, 0.036, 0.042),
    (0.02, 0.045, 0.042, 0.040, 0.055),
    (0.08, 0.050, 0.046, 0.042, 0.062),
    (0.15, 0.052, 0.048, 0.046, 0.058),
    (0.20, 0.050, 0.048, 0.047, 0.050),
    (0.225, 0.035, 0.033, 0.036, 0.036),
    (0.236, 0.015, 0.015, 0.015, 0.015),
]

# foot sections along Z: (z, half width out, half width in, y bottom, y top, x centre)
FOOT = [
    (0.068, 0.018, 0.018, -0.256, -0.228, 0.0),
    (0.058, 0.032, 0.032, -0.258, -0.206, 0.0),
    (0.035, 0.036, 0.035, -0.258, -0.186, 0.0),
    (0.0, 0.038, 0.037, -0.258, -0.178, 0.0),
    (-0.04, 0.043, 0.041, -0.258, -0.193, -0.001),
    (-0.08, 0.046, 0.046, -0.258, -0.211, -0.002),
    (-0.115, 0.048, 0.049, -0.258, -0.226, -0.003),
    (-0.14, 0.046, 0.048, -0.258, -0.233, -0.004),
    (-0.155, 0.040, 0.044, -0.258, -0.236, -0.004),
    (-0.163, 0.022, 0.026, -0.256, -0.240, -0.004),
]

def fsec(z, grow=0.0, segs=14):
    v = rowinterp(z, sorted(FOOT))
    xo, xi, yb, yt, cx = v
    ym, hh = (yb + yt) / 2, (yt - yb) / 2 + grow
    out = []
    for j in range(segs):
        a = 2 * math.pi * j / segs
        c, s = math.cos(a), math.sin(a)
        w = (xo if c > 0 else xi) + grow
        out.append((cx + w * math.copysign(abs(c) ** 0.75, c), ym + hh * math.copysign(abs(s) ** 0.75, s), z))
    return out

def build_foot(b):
    b.loft([fsec(r[0]) for r in FOOT], "skin")
    # toes, big toe on the inward side (-X)
    for x, rx, ry, rz, z in ((-0.030, 0.013, 0.011, 0.018, -0.167), (-0.008, 0.0085, 0.0085, 0.013, -0.164),
                             (0.008, 0.0078, 0.0080, 0.012, -0.159), (0.022, 0.0072, 0.0075, 0.011, -0.152),
                             (0.035, 0.0066, 0.0070, 0.010, -0.143)):
        ellipsoid(b, (x, -0.258 + ry, z), rx, ry, rz, 8, 5, "skin")
    # sandal: sole, ankle strap, forefoot strap, instep and side straps
    sole = [(0.075, 0.026), (0.062, 0.040), (0.03, 0.044), (-0.03, 0.048), (-0.09, 0.053),
            (-0.13, 0.055), (-0.165, 0.052), (-0.183, 0.042), (-0.191, 0.022)]
    rings = []
    for z, w in sole:
        cx = interp(-z, [(-0.075, 0.0), (0.04, -0.001), (0.12, -0.004)])
        ring = []
        for j in range(12):
            c, s = math.cos(2 * math.pi * j / 12), math.sin(2 * math.pi * j / 12)
            ring.append((cx + w * math.copysign(abs(c) ** 0.4, c), -0.264 + 0.006 * math.copysign(abs(s) ** 0.4, s), z))
        rings.append(ring)
    b.loft(rings, "leather")
    b.loft([fsec(-0.084, 0.0035), fsec(-0.099, 0.0035)], "leather")
    srt = sorted(SHIN)
    rings = []
    for y in (-0.152, -0.136):
        v = rowinterp(y, srt)
        rings.append(xring(y, v[0] + 0.004, v[1] + 0.004, v[2] + 0.004, v[3] + 0.004, 14))
    b.loft(rings, "leather")
    tube(b, [(0.0, -0.148, -0.034), (0.0, -0.172, -0.042), (0.0, -0.192, -0.062), (0.0, -0.208, -0.088)],
         [0.0045] * 4, 6, "leather")
    for sx in (0.041, -0.040):
        tube(b, [(sx, -0.259, 0.026), (sx * 0.9, -0.22, 0.022), (sx * 0.8, -0.18, 0.014), (sx * 0.78, -0.146, 0.006)],
             [0.004] * 4, 6, "leather")

def build_shin(b):
    def bump(x, y, c, s):
        f = max(s, 0.0)
        return (0.006 * gauss((y - 0.09) / 0.05, (x + 0.02) / 0.025) * f   # inner calf head
                + 0.004 * gauss((y - 0.07) / 0.05, (x - 0.025) / 0.025) * f)  # outer calf head
    limb(b, SHIN, 16, "skin", bump, bulk=lambda y: 1.0 + 0.12 * gauss((y - 0.09) / 0.07, 0.0))
    build_foot(b)

# ---------------------------------------------------------------- pelvis

PELVIS = [  # (y, half width, front depth, back depth)
    (-0.125, 0.100, 0.060, 0.070),
    (-0.115, 0.130, 0.080, 0.090),
    (-0.095, 0.150, 0.090, 0.098),
    (-0.06, 0.163, 0.096, 0.103),
    (-0.02, 0.166, 0.098, 0.104),
    (0.02, 0.163, 0.098, 0.099),
    (0.06, 0.156, 0.097, 0.095),
    (0.10, 0.150, 0.096, 0.093),
    (0.13, 0.145, 0.093, 0.090),
]

def pelvis_bump(x, y, c, s):
    if s <= 0:
        return 0.004 * gauss(x / 0.06, (y - 0.08) / 0.04) * -s  # lower abdomen
    ax = abs(x)
    return (0.012 * gauss((ax - 0.062) / 0.05, (y + 0.055) / 0.045)
            - 0.007 * gauss(x / 0.012, 0.0) * (1.0 if y < 0.0 else 0.0)) * s

def pring(y, push=0.0, segs=28):
    v = rowinterp(y, PELVIS)
    a, df, db = v[0] + push, v[1] + push, v[2] + push
    return xring(y, a, a, df, db, segs, 0.0, 0.0, pelvis_bump, 2.5)

def flap(b, ys, wtab, side):
    """Thin loincloth panel hanging at the front (side=-1) or back (+1), just outside the surface."""
    rings = []
    for y in ys:
        w = interp(-y, wtab)
        push = 0.006 if 0.025 <= y <= 0.08 else 0.0
        zs = [p[2] for p in pring(y, push, 56) if abs(p[0]) < w and p[2] * side > 0]
        z = (max(zs) if side > 0 else min(zs)) + side * 0.004
        t = 0.005
        rings.append([(-w, y, z), (0.0, y, z + side * 0.006), (w, y, z),
                      (w, y, z - side * t), (0.0, y, z + side * (0.006 - t)), (-w, y, z - side * t)])
    # hang straight below the lowest surface point
    zmax = max(r[1][2] * side for r in rings)
    for r in rings:
        dz = zmax - r[1][2] * side
        if r[0][1] < -0.06:
            for i in range(6):
                r[i] = (r[i][0], r[i][1], r[i][2] + side * dz)
    b.loft(rings, "cloth")

def build_pelvis(b):
    ys = [-0.125, -0.115, -0.105, -0.095] + [-0.08 + 0.015 * i for i in range(14)] + [0.13]
    ys = sorted(set(round(y, 4) for y in ys if y <= 0.13))
    rings = [pring(y) for y in ys]
    mats = ["cloth" if 0.5 * (y0 + y1) < 0.05 else "skin" for y0, y1 in zip(ys, ys[1:])]
    b.loft(rings, mats)
    b.loft([pring(0.026, 0.006), pring(0.05, 0.0075), pring(0.074, 0.006)], "leather")
    flap(b, [0.07, 0.03, -0.01, -0.05, -0.09, -0.13], [(-0.07, 0.065), (0.13, 0.05)], -1)
    flap(b, [0.07, 0.03, -0.01, -0.05, -0.09, -0.125], [(-0.07, 0.07), (0.13, 0.06)], 1)

# ---------------------------------------------------------------- torso

TORSO = [  # (y, half width, front depth, back depth)
    (-0.27, 0.130, 0.085, 0.085),
    (-0.24, 0.145, 0.095, 0.090),
    (-0.20, 0.148, 0.100, 0.092),
    (-0.14, 0.150, 0.100, 0.094),
    (-0.08, 0.155, 0.101, 0.096),
    (-0.02, 0.164, 0.104, 0.099),
    (0.04, 0.180, 0.108, 0.104),
    (0.09, 0.190, 0.110, 0.105),
    (0.13, 0.192, 0.108, 0.105),
    (0.165, 0.185, 0.098, 0.100),
    (0.19, 0.163, 0.084, 0.090),
    (0.215, 0.128, 0.068, 0.076),
    (0.235, 0.090, 0.056, 0.063),
    (0.25, 0.060, 0.046, 0.052),
]

def torso_bump(x, y, c, s):
    ax = abs(x)
    if s < 0:
        f = -s
        sy = 0.05 if y > 0.105 else 0.024
        d = 0.019 * gauss((ax - 0.072) / 0.05, (y - 0.105) / sy)                        # pecs
        if y < 0.065:
            d -= 0.007 * gauss(x / 0.011, 0.0)                                          # linea alba
            for yk in (0.025, -0.035, -0.095):
                d -= 0.0045 * gauss((y - yk) / 0.011, 0.0) * math.exp(-(x / 0.06) ** 4)  # ab rows
            d += 0.005 * gauss((ax - 0.13) / 0.025, (y + 0.03) / 0.06)                  # serratus/obliques
        d -= 0.004 * gauss(x / 0.02, (y - 0.19) / 0.02)                                 # sternal notch
        return d * f
    f = s
    return (-0.006 * gauss(x / 0.014, 0.0)
            + 0.008 * gauss((ax - 0.075) / 0.045, (y - 0.11) / 0.05)
            + 0.006 * gauss((ax - 0.13) / 0.04, (y - 0.02) / 0.07)) * f

def build_torso(b):
    ys = [-0.27 + 0.018 * i for i in range(28)] + [0.25]
    ys = sorted(set(round(min(y, 0.25), 4) for y in ys))
    rings = []
    for y in ys:
        a, df, db = rowinterp(y, TORSO)
        rings.append(xring(y, a, a, df, db, 28, 0.0, 0.0, torso_bump, 2.4))
    b.loft(rings, "skin")
    # neck stump
    limb(b, [(0.12, 0.062, 0.062, 0.058, 0.062, 0.008), (0.2, 0.060, 0.060, 0.054, 0.060, 0.008),
             (0.25, 0.057, 0.057, 0.051, 0.057, 0.01), (0.262, 0.053, 0.053, 0.048, 0.053, 0.01),
             (0.27, 0.04, 0.04, 0.036, 0.04, 0.01)], 14, "skin")
    # deltoid caps around the shoulder pivots (x = +/-0.23, y = +0.20)
    for sx in (1, -1):
        rs = []
        for k in range(10):
            phi = math.pi * k / 9
            sr = max(math.sin(phi), 0.05)
            y = 0.172 - 0.068 * math.cos(phi)
            w = 0.058 * sr * (0.85 + 0.15 * (y - 0.104) / 0.136)
            rs.append(xring(y, w, w, 0.064 * sr, 0.064 * sr, 14, sx * 0.21, 0.0))
        b.loft(rs, "skin")

# ---------------------------------------------------------------- head

HEAD = [  # (y, half width, front depth, back depth)
    (-0.128, 0.030, 0.056, 0.030),
    (-0.12, 0.034, 0.068, 0.036),
    (-0.105, 0.046, 0.082, 0.046),
    (-0.09, 0.056, 0.086, 0.056),
    (-0.07, 0.062, 0.090, 0.068),
    (-0.05, 0.068, 0.092, 0.082),
    (-0.025, 0.074, 0.094, 0.093),
    (0.0, 0.078, 0.093, 0.099),
    (0.02, 0.079, 0.095, 0.100),
    (0.045, 0.077, 0.093, 0.099),
    (0.07, 0.070, 0.085, 0.092),
    (0.09, 0.058, 0.070, 0.078),
    (0.105, 0.036, 0.045, 0.050),
    (0.112, 0.012, 0.014, 0.016),
]
HEAD_YS = [-0.128, -0.122, -0.114, -0.106, -0.098, -0.09, -0.083, -0.076, -0.069, -0.062, -0.055, -0.047,
           -0.037, -0.026, -0.014, -0.002, 0.006, 0.014, 0.022, 0.03, 0.04, 0.052, 0.066, 0.08,
           0.092, 0.104, 0.112]
HEAD_PHI = ([-math.pi / 2 + math.pi * i / 18 for i in range(18)]
            + [math.pi / 2 + math.pi * i / 10 for i in range(10)])

def face_feat(x, y):
    ax = abs(x)
    d = 0.007 * math.exp(-((y - 0.026) / 0.011) ** 2) * math.exp(-(x / 0.055) ** 4)  # brow ridge
    d -= 0.013 * gauss((ax - 0.032) / 0.017, (y - 0.003) / 0.013)                    # eye sockets
    d += 0.006 * gauss((ax - 0.052) / 0.02, (y + 0.022) / 0.014)                     # cheekbones
    d -= 0.004 * gauss((ax - 0.045) / 0.018, (y + 0.058) / 0.014)                    # cheek hollows
    d += 0.004 * gauss(x / 0.022, (y + 0.062) / 0.007)                               # upper lip
    d += 0.004 * gauss(x / 0.02, (y + 0.079) / 0.007)                                # lower lip
    d += 0.007 * gauss(x / 0.02, (y + 0.106) / 0.012)                                # chin
    return d

def head_pt(phi, y, push=0.0):
    W, F, K = rowinterp(y, HEAD)
    s, c = math.sin(phi), math.cos(phi)
    e = 2.0 / 2.3
    x = W * math.copysign(abs(s) ** e, s)
    z = -(F if c > 0 else K) * math.copysign(abs(c) ** e, c)
    d = push
    if c > 0:
        d += face_feat(x, y) * min(1.0, c * 1.5)
    return (x + d * s, y, z - d * c)

def face_z(x, y):
    lo, hi = 0.0, math.pi / 2
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if head_pt(mid, y)[0] < x:
            lo = mid
        else:
            hi = mid
    return head_pt(lo, y)[2]

def build_head(b, beard):
    b.loft([[head_pt(phi, y) for phi in HEAD_PHI] for y in HEAD_YS], "skin")
    # upper neck, tucks into the torso's neck stump
    limb(b, [(-0.14, 0.05, 0.05, 0.046, 0.05, 0.012), (-0.1, 0.05, 0.05, 0.046, 0.05, 0.012),
             (-0.06, 0.048, 0.048, 0.044, 0.048, 0.016)], 12, "skin")
    # nose
    rings = []
    for y, w, pr in ((0.014, 0.007, 0.002), (0.0, 0.008, 0.007), (-0.015, 0.0095, 0.014), (-0.03, 0.012, 0.021),
                     (-0.04, 0.015, 0.025), (-0.047, 0.017, 0.022), (-0.052, 0.014, 0.011)):
        z0 = face_z(0.0, y) + 0.004
        rings.append([(w, y, z0 + 0.004), (w * 0.8, y, z0 - pr * 0.5), (w * 0.4, y, z0 - pr * 0.93), (0.0, y, z0 - pr),
                      (-w * 0.4, y, z0 - pr * 0.93), (-w * 0.8, y, z0 - pr * 0.5), (-w, y, z0 + 0.004), (0.0, y, z0 + 0.01)])
    b.loft(rings, "skin")
    # eyes and ears
    for sx in (1, -1):
        ellipsoid(b, (sx * 0.032, 0.003, face_z(0.032, 0.003) + 0.005), 0.0115, 0.0115, 0.0115, 8, 5, "hair")
        W = rowinterp(-0.012, HEAD)[0]
        ellipsoid(b, (sx * (W + 0.002), -0.012, 0.012), 0.009, 0.028, 0.017, 8, 6, "skin")
    # short cropped hair: shell from the hairline to the crown
    hl = [(0.0, 0.068), (0.6, 0.064), (1.1, 0.040), (1.57, 0.028), (2.1, 0.0), (2.6, -0.04), (math.pi, -0.055)]
    rings = []
    for t in (0.0, 0.25, 0.5, 0.72, 0.88, 1.0):
        ring = []
        for phi in HEAD_PHI:
            h = interp(abs(phi), hl)
            y = h + (0.112 - h) * t
            x, _, z = head_pt(phi, y, 0.0055)
            ring.append((x, y + 0.006 * t * t, z))
        rings.append(ring)
    b.loft(rings, "hair", cap0=False)
    if not beard:
        return
    cols = [-1.4 + 2.8 * i / 14 for i in range(15)]
    ybot = [(0.0, -0.124), (0.6, -0.118), (1.0, -0.10), (1.4, -0.07)]
    ytop = [(0.0, -0.081), (0.35, -0.076), (0.55, -0.05), (0.9, -0.02), (1.2, 0.01), (1.4, 0.03)]
    rows = []
    for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
        row = []
        for phi in cols:
            a = abs(phi)
            y = interp(a, ybot) + (interp(a, ytop) - interp(a, ybot)) * t
            th = 0.004 + 0.009 * (1.0 - t) * max(0.0, 1.0 - a / 1.6)
            x, _, z = head_pt(phi, max(y, -0.127), th)
            drop = 0.016 * (1.0 - t) ** 2 * math.exp(-(phi / 0.6) ** 2)
            row.append((x, y - drop, z - 0.5 * drop))
        rows.append(row)
    b.loft(rows, "hair", closed=False)
    cols = [-0.55 + 1.1 * i / 8 for i in range(9)]
    rows = []
    for y in (-0.061, -0.0565, -0.052):
        rows.append([(lambda p: (p[0], y - 0.006 * (abs(phi) / 0.55) ** 2, p[2]))(head_pt(phi, y, 0.0045)) for phi in cols])
    b.loft(rows, "hair", closed=False)

# ---------------------------------------------------------------- dismemberment caps

def circle(r, y, n, cx=0.0, cz=0.0):
    return [(cx + r * math.cos(2 * math.pi * j / n), y, cz + r * math.sin(2 * math.pi * j / n)) for j in range(n)]

def annulus(b, inner, outer, mat, out):
    n = len(inner)
    for j in range(n):
        j2 = (j + 1) % n
        q = [inner[j], inner[j2], outer[j2], outer[j]]
        o = out if out else sub(centroid(q), [0.0, centroid(q)[1], 0.0])
        b.face(q, mat, o)

def build_cap(b, R, bones, n=20):
    rf = R - 0.006
    up = [0.0, 1.0, 0.0]
    rings = [circle(rf * k, 0.0025 * (1 - k * k) + 0.0005 * math.sin(7 * k), n) for k in (0.35, 0.7, 1.0)]
    b.face(rings[0], "flesh", up)
    annulus(b, rings[0], rings[1], "flesh", up)
    annulus(b, rings[1], rings[2], "flesh", up)
    fat = circle(R, -0.0005, n)
    annulus(b, rings[2], fat, "fat", up)
    bottom = circle(R, -0.012, n)
    annulus(b, fat, bottom, "skin", None)
    b.face(bottom, "skin", [0.0, -1.0, 0.0])
    for x, z, r in bones:
        top = circle(r, 0.0045, 12, x, z)
        b.face(top, "bone", up)
        annulus(b, top, circle(r, -0.003, 12, x, z), "bone", None)
'''


def make_materials():
    mat = hou.node("/mat")
    for name, (col, rough, metal) in MATERIALS.items():
        m = mat.createNode("principledshader::2.0", name)
        m.parmTuple("basecolor").set(col)
        m.parm("rough").set(rough)
        m.parm("metallic").set(metal)


def make_part(name, pos, call, mx):
    obj = hou.node("/obj").createNode("geo", name)
    obj.parmTuple("t").set(pos)
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nb = B(hou.pwd().geometry(), %r)\n%s\n" % (float(mx), call))
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, py)
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, div)
    nrm.parm("cuspangle").set(50)
    out = obj.createNode("null", "OUT")
    out.setInput(0, nrm)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    rop = hou.node("/out").createNode("gltf", "export_" + name)
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    rop.parm("outputfile").set("$HIP/../export/body/%s.glb" % name)
    rop.parm("exportmaterials").set(1)
    return obj, out, rop


def read_glb(path):
    """Return (triangles, bbox min, bbox max, signed volume, material names) from a .glb file."""
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    bin_off = 20 + jlen + 8
    comp = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}

    def acc(i):
        a = doc["accessors"][i]
        bv = doc["bufferViews"][a["bufferView"]]
        fmt, size = comp[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        start = bin_off + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", size * ncomp)
        return [struct.unpack_from("<%d%s" % (ncomp, fmt), data, start + k * stride) for k in range(a["count"])]

    tris, vol = 0, 0.0
    lo, hi = [1e9] * 3, [-1e9] * 3
    attrs = set()
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            attrs |= set(prim["attributes"])
            pos = acc(prim["attributes"]["POSITION"])
            idx = [i[0] for i in acc(prim["indices"])] if "indices" in prim else list(range(len(pos)))
            for p in pos:
                for k in range(3):
                    lo[k] = min(lo[k], p[k]); hi[k] = max(hi[k], p[k])
            for t in range(0, len(idx), 3):
                a, b, c = pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]]
                vol += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0])
                        + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
                tris += 1
    return tris, lo, hi, vol, [m["name"] for m in doc.get("materials", [])], attrs


def render_previews(objs, detail):
    cam = hou.node("/obj").createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    for name, t, inten in (("key", (4, 4.5, -3), 1.2), ("fill", (-4, 1, -3), 0.3), ("rim", (-1, 3, 6), 0.6)):
        l = hou.node("/obj").createNode("hlight", name)
        l.parmTuple("t").set(t)
        l.parm("light_intensity").set(inten)
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(0.35)
    rop = hou.node("/out").createNode("karma", "preview")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)

    def shoot(path, center, width, rot, res, vis):
        cam.parm("resx").set(res[0]); cam.parm("resy").set(res[1])
        rop.parm("resolutionx").set(res[0]); rop.parm("resolutiony").set(res[1])
        r = hou.hmath.buildRotate(rot, "xyz")
        pos = hou.Vector3(center) + hou.Vector3(0, 0, 10) * r
        cam.setWorldTransform(r * hou.hmath.buildTranslate(pos))
        cam.parm("orthowidth").set(width)
        rop.parm("candobjects").set(vis)
        rop.parm("picture").set(path)
        rop.render()

    body = " ".join(n for n in PARTS if n != "head_b")
    shoot(os.path.join(PREVIEW, "body_front.png"), (0.15, 0.93, 0), 2.1, (0, 180, 0), (1024, 1024), body + " head_b")
    shoot(os.path.join(PREVIEW, "body_side.png"), (0, 0.93, 0), 2.1, (0, 90, 0), (1024, 1024), body)
    caps = " ".join(CAPS)
    shoot(os.path.join(PREVIEW, "body_caps.png"), (0.4, 3.0, 0), 1.0, (-55, 180, 0), (1024, 512), caps)
    if detail:
        shoot(os.path.join(PREVIEW, "body_detail_head.png"), (0.35, 1.70, 0), 0.9, (-5, 200, 0), (1024, 512), "head head_b")
        shoot(os.path.join(PREVIEW, "body_detail_head_side.png"), (0, 1.70, 0), 0.4, (0, 90, 0), (512, 512), "head")
        shoot(os.path.join(PREVIEW, "body_detail_hand.png"), (0.23, 0.95, 0), 0.25, (-20, 120, 0), (512, 512), "forearm_r")
        shoot(os.path.join(PREVIEW, "body_detail_foot.png"), (0.10, 0.08, -0.04), 0.35, (-25, 150, 0), (512, 512), "shin_r")
        shoot(os.path.join(PREVIEW, "body_detail_34.png"), (0, 0.93, 0), 2.1, (-8, 215, 0), (1024, 1024), body)


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    os.makedirs(EXPORT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    objs, rops = {}, {}
    for name, (pos, call, mx, _, _) in PARTS.items():
        if name == "head_b":
            pos = (0.55, pos[1], pos[2])  # shown beside the body in the front preview
        obj, out, rop = make_part(name, pos, call, mx)
        objs[name] = (obj, out)
        rops[name] = rop
    for i, (name, (R, bones)) in enumerate(CAPS.items()):
        obj, out, rop = make_part(name, (i * 0.2, 3.0, 0), "build_cap(b, %r, %r)" % (R, bones), 1)
        objs[name] = (obj, out)
        rops[name] = rop
    hou.hipFile.save(HIP)

    ok = True
    total = 0
    tol, slack = 0.03, 0.005
    for name in list(PARTS) + list(CAPS):
        rops[name].render()
        tris, lo, hi, vol, mnames, attrs = read_glb(os.path.join(EXPORT, name + ".glb"))
        if name != "head_b":
            total += tris
        notes = []
        good = tris <= 2500 and vol > 0 and {"NORMAL", "TEXCOORD_0"} <= attrs
        if name in PARTS:
            plo, phi = PARTS[name][3], PARTS[name][4]
            for k, ax in enumerate("xyz"):
                if lo[k] > plo[k] + slack or hi[k] < phi[k] - slack:
                    notes.append("%s under by %.3f" % (ax, max(lo[k] - plo[k], phi[k] - hi[k])))
                if lo[k] < plo[k] - tol - slack or hi[k] > phi[k] + tol + slack:
                    notes.append("%s over by %.3f" % (ax, max(plo[k] - lo[k], hi[k] - phi[k])))
        print("%-13s tris=%5d bbox=(%+.3f %+.3f %+.3f)..(%+.3f %+.3f %+.3f) vol=%.5f mats=%s %s%s" % (
            name, tris, *lo, *hi, vol, ",".join(mnames), "OK" if good and not notes else "CHECK",
            (" [" + "; ".join(notes) + "]") if notes else ""))
        ok = ok and good
    print("total tris (body with plain head + caps): %d" % total)

    if "--no-preview" not in sys.argv:
        try:
            render_previews(objs, "--detail" in sys.argv)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
