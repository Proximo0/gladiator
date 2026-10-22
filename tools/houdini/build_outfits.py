"""Build the Sandblood premium cosmetic outfits (full replacement part sets) and export .glb files.

Run:  hython scripts/build_outfits.py [--outfit samurai|alien|all] [--no-preview] [--detail]
      (re-runnable; rebuilds hip, exports, previews). Same folder layout as build_body.py:
      scripts/build_outfits.py, hip/outfits.hip, export/outfits/<outfit>/<part>.glb, export/outfits/preview_<outfit>.png.

Conventions (identical to build_body.py): metres, Y up, -Z forward (face/chest/toes toward -Z). Each part is
modelled in its own local frame with the origin at the part centre, posed in the standing rest pose, using the
same 12 part names and frames as the base body. Right-side parts are built natively (outward = +X); left parts are
mirrored copies. Cap meshes (alien only): flat disc, normal +Y, centred at the origin. Materials are named
principled shaders; the game maps them by name.
Vertex colour (Cd, exported as COLOR_0) is a baked ALBEDO MULTIPLIER (Godot multiplies it into the albedo), not a mask:
(1,1,1) everywhere, except alien_chitin where a slight iridescent hue shift (all channels <= 0.97) is baked in.
Outfit art stays within ~1.5 cm of the base body art bounds (heads 3 cm); the physics colliders never change.
"""
import json
import math
import os
import struct
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "outfits.hip")
EXPORT = os.path.join(ROOT, "export", "outfits")

# name: (rest-pose world centre, mirror x, base art bbox lo, base art bbox hi)
# The bboxes are the bounds of the base body art (build_body.py) computed from its profile tables.
PARTS = {
    "pelvis": ((0, 0.98, 0), 1, ((-0.168, -0.13, -0.117), (0.168, 0.13, 0.122))),
    "torso": ((0, 1.33, 0), 1, ((-0.264, -0.27, -0.124), (0.264, 0.27, 0.109))),
    "head": ((0, 1.70, 0), 1, ((-0.087, -0.14, -0.114), (0.087, 0.118, 0.106))),
    "head_b": ((0, 1.70, 0), 1, ((-0.087, -0.14, -0.114), (0.087, 0.118, 0.106))),
    "upper_arm_l": ((-0.23, 1.39, 0), -1, ((-0.065, -0.172, -0.075), (0.055, 0.172, 0.064))),
    "upper_arm_r": ((0.23, 1.39, 0), 1, ((-0.055, -0.172, -0.075), (0.065, 0.172, 0.064))),
    "forearm_l": ((-0.23, 1.08, 0), -1, ((-0.057, -0.177, -0.056), (0.049, 0.19, 0.05))),
    "forearm_r": ((0.23, 1.08, 0), 1, ((-0.049, -0.177, -0.056), (0.057, 0.19, 0.05))),
    "thigh_l": ((-0.10, 0.68, 0), -1, ((-0.09, -0.252, -0.094), (0.078, 0.252, 0.086))),
    "thigh_r": ((0.10, 0.68, 0), 1, ((-0.078, -0.252, -0.094), (0.09, 0.252, 0.086))),
    "shin_l": ((-0.10, 0.27, 0), -1, ((-0.056, -0.27, -0.191), (0.059, 0.236, 0.075))),
    "shin_r": ((0.10, 0.27, 0), 1, ((-0.059, -0.27, -0.191), (0.056, 0.236, 0.075))),
}
# builder base name per part (head_b reuses the head: both outfits cover the beard)
BUILDER = {"pelvis": "pelvis", "torso": "torso", "head": "head", "head_b": "head",
           "upper_arm_l": "upper_arm", "upper_arm_r": "upper_arm", "forearm_l": "forearm", "forearm_r": "forearm",
           "thigh_l": "thigh", "thigh_r": "thigh", "shin_l": "shin", "shin_r": "shin"}
HEAD_PARTS = ("head", "head_b")
TRI_LIMIT = 6000
TOL, TOL_HEAD = 0.015, 0.03  # how far the art may exceed the base art bounds (m)

# cap name: (outer radius, bones [(x, z, r)]). Same sizes as the base caps; exported only for outfits with cap_mats.
CAPS = {
    "cap_neck": (0.058, [(0.0, 0.018, 0.012)]),
    "cap_shoulder": (0.052, [(0.0, 0.0, 0.014)]),
    "cap_elbow": (0.045, [(0.012, 0.0, 0.009), (-0.013, 0.004, 0.008)]),
    "cap_hip": (0.078, [(0.0, 0.0, 0.017)]),
    "cap_knee": (0.052, [(0.0, -0.008, 0.016), (0.03, 0.01, 0.007)]),
}

# Placeholder colours for what comes out of an alien when it is cut. Open question for the owner (see
# docs/outfits_art.md); these defaults equal the human flesh/fat/bone so no decision is made by the art.
ICHOR_FLESH = (0.75, 0.04, 0.04)
ICHOR_FAT = (0.90, 0.80, 0.40)
ALIEN_CAP_MATS = {"flesh": "alien_flesh", "fat": "alien_fat", "skin": "alien_skin", "bone": "alien_bone"}

# name: (base color (linear), roughness, metallic)
MATERIALS = {
    # shared with the base body (the game tints skin and cloth per fighter)
    "skin": ((0.56, 0.31, 0.19), 0.55, 0.0),
    "cloth": ((0.85, 0.84, 0.80), 0.9, 0.0),
    "leather": ((0.20, 0.10, 0.045), 0.7, 0.0),
    "hair": ((0.045, 0.03, 0.02), 0.8, 0.0),
    # samurai
    "lacquer_red": ((0.32, 0.012, 0.010), 0.18, 0.0),
    "lacquer_black": ((0.010, 0.010, 0.012), 0.15, 0.0),
    "gold": ((0.85, 0.52, 0.10), 0.28, 1.0),
    "cloth_indigo": ((0.010, 0.016, 0.060), 0.92, 0.0),
    "iron": ((0.10, 0.10, 0.11), 0.40, 1.0),
    # alien
    "alien_skin": ((0.22, 0.30, 0.22), 0.50, 0.0),
    "alien_chitin": ((0.13, 0.19, 0.15), 0.28, 0.6),
    "alien_eye": ((0.004, 0.004, 0.005), 0.04, 0.0),
    "alien_mouth": ((0.035, 0.045, 0.040), 0.60, 0.0),
    "alien_flesh": (ICHOR_FLESH, 0.4, 0.0),
    "alien_fat": (ICHOR_FAT, 0.5, 0.0),
    "alien_bone": ((0.85, 0.82, 0.70), 0.5, 0.0),
}

OUTFITS = {
    "samurai": {"mats": {"skin", "cloth", "leather", "hair", "lacquer_red", "lacquer_black", "gold", "cloth_indigo", "iron"},
                "cap_mats": None},
    "alien": {"mats": {"alien_skin", "alien_chitin", "alien_eye", "alien_mouth"},
              "cap_mats": ALIEN_CAP_MATS},
}

# Geometry library shared by both outfits, embedded in each Python SOP so the .hip is self-contained.
LIB_COMMON = r'''
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

def smooth(e0, e1, x):
    """Smoothstep from 0 at e0 to 1 at e1 (e1 may be below e0)."""
    if e0 == e1:
        return 1.0 if x >= e1 else 0.0
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)

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

def rotp(p, rot):
    """Rotate p by Euler degrees (rx, ry, rz), applied in the order z, x, y."""
    x, y, z = p
    rx, ry, rz = [math.radians(a) for a in rot]
    c, s = math.cos(rz), math.sin(rz)
    x, y = x * c - y * s, x * s + y * c
    c, s = math.cos(rx), math.sin(rx)
    y, z = y * c - z * s, y * s + z * c
    c, s = math.cos(ry), math.sin(ry)
    x, z = x * c + z * s, -x * s + z * c
    return (x, y, z)

def vcol(mat, p):
    """Baked albedo multiplier at world position p. White, except a slight iridescent shift on alien chitin."""
    if mat == "alien_chitin":
        ph = p[1] * 7.0 + p[0] * 3.0 + p[2] * 4.0
        return (0.80 + 0.17 * math.cos(6.2832 * ph), 0.80 + 0.17 * math.cos(6.2832 * (ph + 0.33)),
                0.80 + 0.17 * math.cos(6.2832 * (ph + 0.67)))
    return (1.0, 1.0, 1.0)

class B:
    def __init__(self, geo, mx=1.0, origin=(0.0, 0.0, 0.0)):
        self.geo = geo
        self.mx = mx
        self.origin = origin
        geo.addAttrib(hou.attribType.Vertex, "uv", (0.0, 0.0, 0.0))
        geo.addAttrib(hou.attribType.Vertex, "Cd", (1.0, 1.0, 1.0))
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
        o = self.origin
        for pt, uv in zip(pts, uvs):
            v = p.addVertex(pt)
            v.setAttribValue("uv", (uv[0], uv[1], 0.0))
            ps = pt.position()
            v.setAttribValue("Cd", vcol(mat, (ps[0] + o[0], ps[1] + o[1], ps[2] + o[2])))
        p.setAttribValue("shop_materialpath", "/mat/" + mat)

    def facing(self, cs, out):
        return self.sign * dot(newell(cs), out) >= 0

    def face(self, cs, mat, out):
        """Single flat polygon oriented toward `out`, planar UVs."""
        if not self.facing(cs, out):
            cs = cs[::-1]
        self.poly(self.pts(cs), [(c[0] * 5 + 0.5, c[2] * 5 + 0.5) for c in cs], mat)

    def loft(self, rings, mat, cap0=True, cap1=True):
        """Closed rings of equal length, outward faces by vote, flat end caps. mat: one name or one per band."""
        if self.mx < 0:
            rings = [[(-c[0], c[1], c[2]) for c in r] for r in rings]
        n = len(rings[0])
        P = [self.pts(r) for r in rings]
        cs = [centroid(r) for r in rings]
        d = [0.0]
        for a, b in zip(cs, cs[1:]):
            d.append(d[-1] + math.dist(a, b))
        tot = d[-1] or 1.0
        quads = []
        votes = 0.0
        for k in range(len(rings) - 1):
            k2 = k + 1
            axis = centroid([cs[k], cs[k2]])
            for j in range(n):
                j2 = (j + 1) % n
                q = [(k, j), (k, j2), (k2, j2), (k2, j)]
                c = [rings[a][b] for a, b in q]
                votes += self.sign * dot(newell(c), sub(centroid(c), axis))
                uv = [(j / n, d[k] / tot), ((j + 1) / n, d[k] / tot),
                      ((j + 1) / n, d[k2] / tot), (j / n, d[k2] / tot)]
                m = mat[k] if isinstance(mat, (list, tuple)) else mat
                quads.append((q, uv, m))
        for q, uv, m in quads:
            if votes < 0:
                q = q[::-1]; uv = uv[::-1]
            self.poly([P[a][b] for a, b in q], uv, m)
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

def rings_for(rows, ys, segs, bump=None, p=2.0, bulk=None, off=0.0, sc=1.0):
    """Rings along a row table [(y, rxo, rxi, rzf, rzb[, cz])]. bulk(y): radius multiplier; off, sc: float or f(y)."""
    srt = sorted(rows)
    if bulk:
        srt = [(r[0],) + tuple(v * bulk(r[0]) for v in r[1:5]) + tuple(r[5:]) for r in srt]
    if ys is None:
        ys = [r[0] for r in srt]
    rings = []
    for y in ys:
        v = rowinterp(y, srt)
        cz = v[4] if len(v) > 4 else 0.0
        o = off(y) if callable(off) else off
        s = sc(y) if callable(sc) else sc
        rings.append(xring(y, v[0] * s + o, v[1] * s + o, v[2] * s + o, v[3] * s + o, segs, 0.0, cz, bump, p))
    return rings

def limb(b, rows, segs, mat, bump=None, ys=None, p=2.0, bulk=None, off=0.0, sc=1.0):
    b.loft(rings_for(rows, ys, segs, bump, p, bulk, off, sc), mat)

def edge_ys(ya, yb, lip, n, steps):
    lip = min(lip, (yb - ya) * 0.3)
    ys = [ya + lip * i / steps for i in range(steps)] + [ya + lip]
    ys += [ya + lip + (yb - ya - 2 * lip) * i / (n + 1) for i in range(1, n + 1)]
    ys += [yb - lip] + [yb - lip + lip * i / steps for i in range(1, steps + 1)]
    return ys

def edge_e(y, ya, yb, lip):
    """0 at the band's edges rising to 1 over `lip` with a quarter-circle bevel."""
    lip = min(lip, (yb - ya) * 0.3)
    u = max(min(min(y - ya, yb - y) / lip, 1.0), 0.0)
    return math.sqrt(max(1.0 - (1.0 - u) ** 2, 0.0))

def sector(cen, half, soft=0.3):
    """Mask f(c, s, y) for xring angles: 1 within `half` radians of angle `cen` (0 = outward +X, -pi/2 = front)."""
    def f(c, s, y):
        a = math.atan2(s, c)
        d = abs((a - cen + math.pi) % (2.0 * math.pi) - math.pi)
        return smooth(half, half - soft, d)
    return f

def pmask(cen, half, soft=0.3):
    """Same for a head angle phi (0 = front, pi = back)."""
    def f(phi):
        d = abs((phi - cen + math.pi) % (2.0 * math.pi) - math.pi)
        return smooth(half, half - soft, d)
    return f

def shell(b, rows, ya, yb, mat, off, thick, segs=20, mask=None, bury=0.03, lip=0.006, n=1, steps=2,
          bump=None, p=2.0, bulk=None, flare=0.0, sc=1.0):
    """Armour band over a limb/torso row table between heights ya..yb: sits `off` outside the surface, `thick` thick,
    bevelled edges, flared out by `flare` at the bottom. mask(c, s, y) < 1 sinks the band into the body there
    (partial plates), so every band stays a closed ring."""
    H = yb - ya
    def dfun(y):
        return off + thick * edge_e(y, ya, yb, lip) + flare * ((yb - y) / H)
    def bf(x, y, c, s):
        k = bump(x, y, c, s) if bump else 0.0
        if mask:
            k -= (1.0 - mask(c, s, y)) * (dfun(y) + bury)
        return k
    b.loft(rings_for(rows, edge_ys(ya, yb, lip, n, steps), segs, bf, p, bulk, dfun, sc), mat)

def rbox(b, c, hx, hy, hz, mat, rot=(0.0, 0.0, 0.0), nr=6, segs=12, p=2.8, e=2.8):
    """Rounded box / ellipsoid (e = 2, p = 2) with half sizes hx, hy, hz, rotated by Euler degrees, centred at c."""
    rings = []
    for k in range(nr + 1):
        t = -1.0 + 2.0 * k / nr
        s = max((1.0 - abs(t) ** e) ** (1.0 / e), 0.05)
        ring = xring(hy * t, hx * s, hx * s, hz * s, hz * s, segs, 0.0, 0.0, None, p)
        rings.append([tuple(rotp(q, rot)[i] + c[i] for i in range(3)) for q in ring])
    b.loft(rings, mat)

def ellipsoid(b, c, rx, ry, rz, segs, rings, mat):
    rs = []
    for k in range(rings + 1):
        phi = math.pi * k / rings
        sr = max(math.sin(phi), 0.05)
        rs.append(xring(c[1] - ry * math.cos(phi), rx * sr, rx * sr, rz * sr, rz * sr, segs, c[0], c[2]))
    b.loft(rs, mat)

def tube(b, path, radii, segs, mat, thick=None, ref=None):
    """Swept tube with rounded ends (parallel-transport frames). thick: second radius (elliptical section, the
    first radius lies along cross(tangent, ref))."""
    t0 = norm(sub(path[1], path[0])); t1 = norm(sub(path[-1], path[-2]))
    r0, r1 = radii[0], radii[-1]
    th = list(thick) if thick else list(radii)
    q0, q1 = th[0], th[-1]
    path = ([[path[0][k] - t0[k] * r0 * f for k in range(3)] for f in (0.85, 0.5)] + [list(p) for p in path]
            + [[path[-1][k] + t1[k] * r1 * f for k in range(3)] for f in (0.5, 0.85)])
    radii = [r0 * 0.5, r0 * 0.85] + list(radii) + [r1 * 0.85, r1 * 0.5]
    th = [q0 * 0.5, q0 * 0.85] + th + [q1 * 0.85, q1 * 0.5]
    if ref is None:
        ref = [0, 1, 0] if abs(t0[1]) < 0.9 else [1, 0, 0]
    nrm = norm(cross(t0, ref))
    rings = []
    n = len(path)
    for i in range(n):
        t = norm(sub(path[min(i + 1, n - 1)], path[max(i - 1, 0)]))
        nrm = norm(sub(nrm, [t[k] * dot(nrm, t) for k in range(3)]))
        bi = cross(t, nrm)
        r = radii[i]; q = th[i]
        rings.append([tuple(path[i][k] + r * math.cos(2 * math.pi * j / segs) * nrm[k]
                            + q * math.sin(2 * math.pi * j / segs) * bi[k] for k in range(3))
                      for j in range(segs)])
    b.loft(rings, mat)

def pleats(n, amp, y0, y1, ph=0.0):
    """Vertical cloth folds: radial bump amp * cos(n * angle), faded in/out over 3 cm at y0 (low) and y1 (high)."""
    def f(x, y, c, s):
        w = smooth(y0, y0 + 0.03, y) * smooth(y1, y1 - 0.03, y)
        return amp * w * math.cos(n * math.atan2(s, c) + ph)
    return f

# ---------------------------------------------------------------- base profile tables (from build_body.py)

UPPER_ARM = [
    (0.172, 0.014, 0.014, 0.014, 0.014), (0.16, 0.033, 0.031, 0.033, 0.033), (0.14, 0.046, 0.043, 0.046, 0.047),
    (0.11, 0.053, 0.047, 0.051, 0.053), (0.07, 0.056, 0.048, 0.054, 0.058), (0.03, 0.056, 0.048, 0.060, 0.055),
    (-0.01, 0.054, 0.047, 0.061, 0.052), (-0.05, 0.051, 0.046, 0.056, 0.048), (-0.09, 0.047, 0.045, 0.047, 0.045),
    (-0.12, 0.047, 0.046, 0.042, 0.044), (-0.145, 0.042, 0.040, 0.036, 0.040), (-0.16, 0.032, 0.030, 0.028, 0.033),
    (-0.172, 0.015, 0.015, 0.015, 0.015),
]
FOREARM = [
    (-0.105, 0.012, 0.011, 0.016, 0.015), (-0.095, 0.020, 0.018, 0.026, 0.024), (-0.08, 0.022, 0.020, 0.028, 0.026),
    (-0.05, 0.031, 0.028, 0.031, 0.027), (-0.01, 0.039, 0.034, 0.036, 0.032), (0.04, 0.046, 0.040, 0.042, 0.038),
    (0.09, 0.050, 0.043, 0.046, 0.043), (0.13, 0.048, 0.044, 0.043, 0.046), (0.16, 0.039, 0.038, 0.036, 0.042),
    (0.18, 0.026, 0.026, 0.026, 0.028), (0.19, 0.012, 0.012, 0.012, 0.013),
]
THIGH = [
    (0.252, 0.016, 0.016, 0.016, 0.016), (0.24, 0.045, 0.040, 0.045, 0.050), (0.22, 0.070, 0.062, 0.068, 0.075),
    (0.18, 0.082, 0.070, 0.075, 0.082), (0.12, 0.083, 0.072, 0.080, 0.076), (0.05, 0.078, 0.068, 0.081, 0.071),
    (-0.03, 0.070, 0.064, 0.076, 0.065), (-0.10, 0.063, 0.059, 0.067, 0.058), (-0.15, 0.059, 0.056, 0.061, 0.055),
    (-0.19, 0.059, 0.057, 0.063, 0.053), (-0.22, 0.050, 0.048, 0.050, 0.046), (-0.24, 0.035, 0.034, 0.034, 0.033),
    (-0.252, 0.015, 0.015, 0.015, 0.015),
]
SHIN = [
    (-0.205, 0.012, 0.012, 0.014, 0.014), (-0.19, 0.033, 0.032, 0.034, 0.038), (-0.16, 0.028, 0.027, 0.030, 0.030),
    (-0.11, 0.031, 0.030, 0.032, 0.033), (-0.05, 0.038, 0.036, 0.036, 0.042), (0.02, 0.045, 0.042, 0.040, 0.055),
    (0.08, 0.050, 0.046, 0.042, 0.062), (0.15, 0.052, 0.048, 0.046, 0.058), (0.20, 0.050, 0.048, 0.047, 0.050),
    (0.225, 0.035, 0.033, 0.036, 0.036), (0.236, 0.015, 0.015, 0.015, 0.015),
]
FOOT = [  # (z, half width out, half width in, y bottom, y top, x centre)
    (0.068, 0.018, 0.018, -0.256, -0.228, 0.0), (0.058, 0.032, 0.032, -0.258, -0.206, 0.0),
    (0.035, 0.036, 0.035, -0.258, -0.186, 0.0), (0.0, 0.038, 0.037, -0.258, -0.178, 0.0),
    (-0.04, 0.043, 0.041, -0.258, -0.193, -0.001), (-0.08, 0.046, 0.046, -0.258, -0.211, -0.002),
    (-0.115, 0.048, 0.049, -0.258, -0.226, -0.003), (-0.14, 0.046, 0.048, -0.258, -0.233, -0.004),
    (-0.155, 0.040, 0.044, -0.258, -0.236, -0.004), (-0.163, 0.022, 0.026, -0.256, -0.240, -0.004),
]
PELVIS4 = [  # (y, half width x2, front depth, back depth)
    (-0.125, 0.100, 0.100, 0.060, 0.070), (-0.115, 0.130, 0.130, 0.080, 0.090), (-0.095, 0.150, 0.150, 0.090, 0.098),
    (-0.06, 0.163, 0.163, 0.096, 0.103), (-0.02, 0.166, 0.166, 0.098, 0.104), (0.02, 0.163, 0.163, 0.098, 0.099),
    (0.06, 0.156, 0.156, 0.097, 0.095), (0.10, 0.150, 0.150, 0.096, 0.093), (0.13, 0.145, 0.145, 0.093, 0.090),
]
TORSO4 = [
    (-0.27, 0.130, 0.130, 0.085, 0.085), (-0.24, 0.145, 0.145, 0.095, 0.090), (-0.20, 0.148, 0.148, 0.100, 0.092),
    (-0.14, 0.150, 0.150, 0.100, 0.094), (-0.08, 0.155, 0.155, 0.101, 0.096), (-0.02, 0.164, 0.164, 0.104, 0.099),
    (0.04, 0.180, 0.180, 0.108, 0.104), (0.09, 0.190, 0.190, 0.110, 0.105), (0.13, 0.192, 0.192, 0.108, 0.105),
    (0.165, 0.185, 0.185, 0.098, 0.100), (0.19, 0.163, 0.163, 0.084, 0.090), (0.215, 0.128, 0.128, 0.068, 0.076),
    (0.235, 0.090, 0.090, 0.056, 0.063), (0.25, 0.060, 0.060, 0.046, 0.052),
]
NECK_STUMP = [(0.12, 0.062, 0.062, 0.058, 0.062, 0.008), (0.2, 0.060, 0.060, 0.054, 0.060, 0.008),
              (0.25, 0.057, 0.057, 0.051, 0.057, 0.01), (0.262, 0.053, 0.053, 0.048, 0.053, 0.01),
              (0.27, 0.04, 0.04, 0.036, 0.04, 0.01)]
NECK_HEAD = [(-0.14, 0.05, 0.05, 0.046, 0.05, 0.012), (-0.1, 0.05, 0.05, 0.046, 0.05, 0.012),
             (-0.06, 0.048, 0.048, 0.044, 0.048, 0.016)]
HEAD = [  # (y, half width, front depth, back depth)
    (-0.128, 0.030, 0.056, 0.030), (-0.12, 0.034, 0.068, 0.036), (-0.105, 0.046, 0.082, 0.046),
    (-0.09, 0.056, 0.086, 0.056), (-0.07, 0.062, 0.090, 0.068), (-0.05, 0.068, 0.092, 0.082),
    (-0.025, 0.074, 0.094, 0.093), (0.0, 0.078, 0.093, 0.099), (0.02, 0.079, 0.095, 0.100),
    (0.045, 0.077, 0.093, 0.099), (0.07, 0.070, 0.085, 0.092), (0.09, 0.058, 0.070, 0.078),
    (0.105, 0.036, 0.045, 0.050), (0.112, 0.012, 0.014, 0.016),
]
HEAD_PHI = ([-math.pi / 2 + math.pi * i / 18 for i in range(18)]
            + [math.pi / 2 + math.pi * i / 10 for i in range(10)])

def uphi(n):
    """n head angles evenly around, symmetric about the front (phi = 0)."""
    return [-math.pi + 2.0 * math.pi * i / n for i in range(n)]

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

def head_pt(phi, y, push=0.0, rows=None, feat=True):
    """Point on the head surface at angle phi (0 = front, -Z) and height y, pushed out by `push`."""
    W, F, K = rowinterp(y, rows or HEAD)
    s, c = math.sin(phi), math.cos(phi)
    e = 2.0 / 2.3
    x = W * math.copysign(abs(s) ** e, s)
    z = -(F if c > 0 else K) * math.copysign(abs(c) ** e, c)
    d = push
    if feat and c > 0:
        d += face_feat(x, y) * min(1.0, c * 1.5)
    return (x + d * s, y, z - d * c)

def face_zr(x, y, rows=None):
    lo, hi = 0.0, math.pi / 2
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if head_pt(mid, y, 0.0, rows, False)[0] < x:
            lo = mid
        else:
            hi = mid
    return head_pt(lo, y, 0.0, rows, False)[2]

def hlame(b, ya, yb, mat, off, thick, flare, phis, maskf=None, lip=0.005, n=0, steps=1, extra=None, rows=None):
    """Armour band around the head between heights ya..yb (see shell); maskf(phi) < 1 sinks it into the head."""
    H = yb - ya
    rings = []
    for y in edge_ys(ya, yb, lip, n, steps):
        d = off + thick * edge_e(y, ya, yb, lip) + flare * ((yb - y) / H)
        ring = []
        for phi in phis:
            dd = d + (extra(phi, y) if extra else 0.0)
            if maskf:
                dd -= (1.0 - maskf(phi)) * (dd + 0.03)
            ring.append(head_pt(phi, y, dd, rows, False))
        rings.append(ring)
    b.loft(rings, mat)

def ua_bulk(y):
    return 1.0 + 0.17 * gauss(y / 0.1, 0.0)

def fa_bulk(y):
    return 1.0 + 0.14 * gauss((y - 0.08) / 0.07, 0.0)

def th_bulk(y):
    return 1.0 + 0.1 * gauss((y - 0.08) / 0.12, 0.0)

def sh_bulk(y):
    return 1.0 + 0.12 * gauss((y - 0.09) / 0.07, 0.0)

def shin_bump(x, y, c, s):
    f = max(s, 0.0)
    return (0.006 * gauss((y - 0.09) / 0.05, (x + 0.02) / 0.025) * f
            + 0.004 * gauss((y - 0.07) / 0.05, (x - 0.025) / 0.025) * f)

def build_hand(b, mat="skin", z4=(-0.031, -0.010, 0.011, 0.030), fr=(0.0098, 0.0100, 0.0095, 0.0085),
               fR=(0.0272, 0.0274, 0.0270, 0.0262), sweep=-232, plate_w=1.0, cy=-0.14):
    """Fist around a bar along Z through (0, cy, 0). Right hand: back of hand outward (+X), palm inward, thumb forward."""
    plate = [
        (-0.083, 0.020, 0.018, 0.026 * plate_w, 0.024 * plate_w), (-0.10, 0.020, 0.016, 0.036 * plate_w, 0.034 * plate_w),
        (-0.12, 0.016, 0.014, 0.043 * plate_w, 0.041 * plate_w), (-0.145, 0.015, 0.014, 0.045 * plate_w, 0.043 * plate_w),
        (-0.165, 0.014, 0.012, 0.043 * plate_w, 0.041 * plate_w), (-0.172, 0.009, 0.008, 0.035 * plate_w, 0.033 * plate_w),
    ]
    srt = sorted(plate)
    rings = []
    for y in [r[0] for r in srt]:
        v = rowinterp(y, srt)
        cx = interp(-y, [(0.083, 0.0), (0.12, 0.022), (0.145, 0.032), (0.172, 0.03)])
        rings.append(xring(y, v[0], v[1], v[2], v[3], 14, cx, 0.0, None, 2.6))
    b.loft(rings, mat)
    for z, r, R in zip(z4, fr, fR):
        a0, a1 = math.radians(-35), math.radians(sweep)
        n = 8 if sweep > -240 else 10
        path = [(R * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + R * math.sin(a0 + (a1 - a0) * i / (n - 1)), z)
                for i in range(n)]
        path[0] = (path[0][0] + 0.004, path[0][1], z)  # knuckle sits into the hand
        tube(b, path, [r * (1.08 if i == 1 else 1.0 - 0.15 * i / (n - 1)) for i in range(n)], 8, mat)

def build_foot_base(b):
    """The base body's foot (skin foot, toes and leather sandal), unchanged."""
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
    b.loft([fsec(r[0]) for r in FOOT], "skin")
    for x, rx, ry, rz, z in ((-0.030, 0.013, 0.011, 0.018, -0.167), (-0.008, 0.0085, 0.0085, 0.013, -0.164),
                             (0.008, 0.0078, 0.0080, 0.012, -0.159), (0.022, 0.0072, 0.0075, 0.011, -0.152),
                             (0.035, 0.0066, 0.0070, 0.010, -0.143)):
        ellipsoid(b, (x, -0.258 + ry, z), rx, ry, rz, 8, 5, "skin")
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

def build_cap(b, R, bones, n=20, mats=None):
    m = mats or {"flesh": "flesh", "fat": "fat", "skin": "skin", "bone": "bone"}
    rf = R - 0.006
    up = [0.0, 1.0, 0.0]
    rings = [circle(rf * k, 0.0025 * (1 - k * k) + 0.0005 * math.sin(7 * k), n) for k in (0.35, 0.7, 1.0)]
    b.face(rings[0], m["flesh"], up)
    annulus(b, rings[0], rings[1], m["flesh"], up)
    annulus(b, rings[1], rings[2], m["flesh"], up)
    fat = circle(R, -0.0005, n)
    annulus(b, rings[2], fat, m["fat"], up)
    bottom = circle(R, -0.012, n)
    annulus(b, fat, bottom, m["skin"], None)
    b.face(bottom, m["skin"], [0.0, -1.0, 0.0])
    for x, z, r in bones:
        top = circle(r, 0.0045, 12, x, z)
        b.face(top, m["bone"], up)
        annulus(b, top, circle(r, -0.003, 12, x, z), m["bone"], None)
'''

LIB_SAMURAI = r'''
# ---------------------------------------------------------------- samurai
# Red lacquer do and sode, black lacquer kabuto, haidate, suneate and kusazuri, gold trim, dark indigo cloth,
# team-coloured ("cloth") obi sash, collar and leg ties, tinted "skin" for the face, wrists, hands and feet.

def build_upper_arm_samurai(b):
    limb(b, UPPER_ARM, 16, "cloth_indigo", None, None, 2.0, ua_bulk, 0.002)  # kimono sleeve
    mask = sector(0.0, 1.9, 0.5)  # the outer half of the arm
    for i in range(5):  # sode: five overlapping lames hanging from the shoulder
        yb = 0.150 - 0.044 * i
        ya = yb - 0.052
        off = 0.002 + 0.001 * i
        fl = 0.003 + 0.0005 * i
        shell(b, UPPER_ARM, ya, yb, "lacquer_black" if i == 0 else "lacquer_red", off, 0.005, 14, mask, 0.03,
              0.005, 1, 2, None, 2.0, ua_bulk, fl)
        shell(b, UPPER_ARM, ya, ya + 0.007, "gold", off + 0.0015, 0.0025, 14, mask, 0.03, 0.002, 0, 2, None, 2.0,
              ua_bulk, fl)

def build_forearm_samurai(b):
    limb(b, FOREARM, 16, "skin", None, None, 2.0, fa_bulk)  # bare wrist and forearm under the kote
    shell(b, FOREARM, -0.07, 0.15, "cloth_indigo", 0.002, 0.004, 16, None, 0.03, 0.01, 4, 2, None, 2.0, fa_bulk)
    for cen in (-0.45, 0.2, 0.85):  # iron splints on the outer back of the forearm
        shell(b, FOREARM, -0.035, 0.115, "iron", 0.005, 0.005, 16, sector(cen, 0.27, 0.12), 0.03, 0.006, 2, 2, None,
              2.0, fa_bulk)
    shell(b, FOREARM, 0.07, 0.15, "lacquer_black", 0.007, 0.006, 16, sector(0.4, 1.5, 0.45), 0.03, 0.008, 1, 2, None,
          2.0, fa_bulk, 0.003)  # elbow cup
    shell(b, FOREARM, 0.14, 0.152, "gold", 0.009, 0.002, 16, sector(0.4, 1.5, 0.45), 0.03, 0.003, 0, 2, None,
          2.0, fa_bulk)
    shell(b, FOREARM, -0.075, -0.06, "gold", 0.004, 0.003, 16, None, 0.03, 0.004, 0, 2, None, 2.0, fa_bulk)  # cuff
    build_hand(b)
    rbox(b, (0.045, -0.125, 0.0), 0.005, 0.030, 0.030, "iron", (0.0, 0.0, 12.0))  # tekko plate on the back of the hand
    rbox(b, (0.0505, -0.125, 0.0), 0.003, 0.010, 0.010, "gold", (0.0, 0.0, 12.0), 4, 10, 2.0, 2.0)

def build_pelvis_samurai(b):
    ys = [-0.125, -0.115, -0.10, -0.08, -0.06, -0.035, -0.01, 0.015, 0.04, 0.065, 0.09, 0.11, 0.13]
    flare = lambda y: 0.004 + 0.006 * smooth(0.0, -0.12, y)
    limb(b, PELVIS4, 28, "cloth_indigo", pleats(11, 0.0035, -0.12, 0.03), ys, 2.5, None, flare)  # hakama
    shell(b, PELVIS4, 0.04, 0.12, "cloth", 0.010, 0.006, 28, None, 0.03, 0.008, 2, 2, None, 2.5)  # obi
    for sx in (1, -1):  # bow at the back
        rbox(b, (sx * 0.032, 0.078, 0.110), 0.03, 0.02, 0.0075, "cloth", (0.0, 0.0, -sx * 22.0))
        rbox(b, (sx * 0.012, 0.045, 0.112), 0.008, 0.03, 0.005, "cloth", (0.0, 0.0, sx * 8.0))
    rbox(b, (0.0, 0.078, 0.113), 0.011, 0.013, 0.009, "cloth")
    shell(b, PELVIS4, 0.036, 0.042, "gold", 0.0125, 0.002, 28, None, 0.03, 0.002, 0, 1, None, 2.5)  # obi edge

def build_thigh_samurai(b):
    ys = [r[0] for r in sorted(THIGH)] + [0.0]
    limb(b, THIGH, 16, "cloth_indigo", pleats(9, 0.0028, -0.20, 0.20), sorted(ys), 2.0, th_bulk, 0.0045)  # hakama
    mask = sector(-math.pi / 2, 1.25, 0.45)  # the front of the thigh
    for i in range(4):  # haidate: four plates
        yb = 0.115 - 0.058 * i
        ya = yb - 0.072
        off = 0.0085 + 0.0007 * i
        shell(b, THIGH, ya, yb, "lacquer_black", off, 0.003, 14, mask, 0.03, 0.005, 1, 2, None, 2.0, th_bulk, 0.002)
        shell(b, THIGH, ya, ya + 0.006, "gold", off + 0.0015, 0.002, 14, mask, 0.03, 0.002, 0, 2, None, 2.0, th_bulk,
              0.002)

def build_shin_samurai(b):
    ys = sorted(set([r[0] for r in SHIN] + [-0.13, -0.12, 0.05]))
    mats = ["skin" if 0.5 * (y0 + y1) < -0.125 else "cloth_indigo" for y0, y1 in zip(ys, ys[1:])]
    b.loft(rings_for(SHIN, ys, 16, shin_bump, 2.0, sh_bulk, 0.002), mats)  # leg wraps over the ankle
    build_foot_base(b)
    mask = sector(-math.pi / 2, 1.35, 0.45)  # suneate: plate over the front of the shin
    shell(b, SHIN, -0.14, 0.185, "lacquer_black", 0.004, 0.007, 16, mask, 0.03, 0.01, 3, 2, shin_bump, 2.0, sh_bulk,
          0.003)
    for k in (-0.5, 0.0, 0.5):
        shell(b, SHIN, -0.12, 0.17, "lacquer_red", 0.0085, 0.003, 16, sector(-math.pi / 2 + k, 0.15, 0.07), 0.03,
              0.004, 2, 2, shin_bump, 2.0, sh_bulk)
    shell(b, SHIN, 0.172, 0.186, "gold", 0.008, 0.003, 16, mask, 0.03, 0.003, 0, 2, shin_bump, 2.0, sh_bulk)
    shell(b, SHIN, -0.14, -0.132, "gold", 0.008, 0.003, 16, mask, 0.03, 0.003, 0, 2, shin_bump, 2.0, sh_bulk)
    shell(b, SHIN, -0.105, -0.09, "cloth", 0.0045, 0.003, 14, None, 0.03, 0.004, 0, 2, None, 2.0, sh_bulk)  # ties
    shell(b, SHIN, 0.13, 0.145, "cloth", 0.0045, 0.003, 14, None, 0.03, 0.004, 0, 2, None, 2.0, sh_bulk)

def do_bump(x, y, c, s):
    if s < 0:
        return (0.007 * gauss((abs(x) - 0.075) / 0.05, (y - 0.095) / 0.05) + 0.004 * math.exp(-(x / 0.012) ** 2)) * -s
    return 0.0

def build_torso_samurai(b):
    ys = [-0.27, -0.24, -0.20, -0.16, -0.12, -0.08, -0.04, 0.0, 0.04, 0.08, 0.12, 0.16, 0.19, 0.215, 0.235, 0.25]
    limb(b, TORSO4, 24, "cloth_indigo", None, ys, 2.4, None, -0.002)  # kimono
    limb(b, NECK_STUMP, 14, "skin")
    shell(b, NECK_STUMP, 0.19, 0.25, "cloth", 0.004, 0.007, 14, None, 0.03, 0.008, 1, 2)  # collar
    for sx in (1, -1):  # kimono shoulders
        rs = []
        for k in range(9):
            phi = math.pi * k / 8
            sr = max(math.sin(phi), 0.05)
            y = 0.172 - 0.068 * math.cos(phi)
            w = 0.056 * sr * (0.85 + 0.15 * (y - 0.104) / 0.136)
            rs.append(xring(y, w, w, 0.062 * sr, 0.062 * sr, 14, sx * 0.21, 0.0))
        b.loft(rs, "cloth_indigo")
    shell(b, TORSO4, -0.035, 0.158, "lacquer_red", 0.006, 0.008, 28, None, 0.03, 0.012, 4, 2, do_bump, 2.4)  # do
    shell(b, TORSO4, 0.142, 0.158, "gold", 0.011, 0.004, 28, None, 0.03, 0.004, 0, 1, do_bump, 2.4)
    shell(b, TORSO4, -0.035, -0.022, "gold", 0.011, 0.004, 28, None, 0.03, 0.004, 0, 1, do_bump, 2.4)
    zf = rowinterp(0.10, TORSO4)[2] + 0.0185
    rbox(b, (0.0, 0.10, -zf), 0.020, 0.0035, 0.020, "gold", (90.0, 0.0, 0.0), 4, 16, 2.0, 2.0)  # mon on the chest
    for j in range(6):  # kusazuri: lames hanging from the do, upper over lower
        yb = -0.026 - 0.037 * j
        ya = yb - 0.052
        off = 0.008 + 0.0012 * (5 - j)
        fl = 0.006 + 0.002 * j
        shell(b, TORSO4, ya, yb, "lacquer_black", off, 0.005, 20, None, 0.03, 0.006, 0, 1, None, 2.4, None, fl)
        shell(b, TORSO4, ya, ya + 0.006, "gold", off + 0.0015, 0.0025, 20, None, 0.03, 0.002, 0, 1, None, 2.4, None,
              fl)

SAM_FACE_YS = [-0.128, -0.11, -0.09, -0.07, -0.05, -0.04, -0.03, -0.02, -0.01, 0.0, 0.01, 0.02, 0.03, 0.045, 0.07, 0.1,
               0.112]

def menpo_push(phi, y):
    f = max(math.cos(phi), 0.0)
    d = 0.0065
    d += 0.014 * f ** 6 * gauss(0.0, (y + 0.058) / 0.028)           # nose
    d += 0.006 * gauss((abs(phi) - 0.75) / 0.25, (y + 0.07) / 0.03)  # cheeks
    d += 0.008 * gauss(phi / 0.35, (y + 0.125) / 0.012)             # chin
    d += 0.003 * gauss(phi / 0.5, (y + 0.092) / 0.006)              # moustache ridge
    m = pmask(0.0, 1.25, 0.5)(phi)
    return d - (1.0 - m) * (d + 0.03)

def bowl_push(phi, y):
    d = 0.006
    d += 0.0028 * (0.5 + 0.5 * math.cos(12.0 * phi)) * smooth(0.03, 0.07, y)   # ribs
    d += 0.028 * max(math.cos(phi), 0.0) ** 3 * smooth(0.040, 0.026, y)        # mabizashi peak
    return d

def build_head_samurai(b):
    b.loft([[head_pt(phi, y) for phi in HEAD_PHI] for y in SAM_FACE_YS], "skin")
    limb(b, NECK_HEAD, 12, "skin")
    for sx in (1, -1):
        ellipsoid(b, (sx * 0.032, 0.003, face_zr(0.032, 0.003) + 0.005), 0.0115, 0.0115, 0.0115, 8, 5, "hair")
    phis = uphi(24)
    # menpo: lacquer half mask over the nose, cheeks, mouth and chin, gold rim along its top
    b.loft([[head_pt(phi, y, menpo_push(phi, y), None, False) for phi in phis]
            for y in (-0.126, -0.12, -0.11, -0.10, -0.09, -0.08, -0.07, -0.06, -0.05, -0.04, -0.034, -0.03)],
           "lacquer_red")
    b.loft([[head_pt(phi, y, menpo_push(phi, y) + 0.0022, None, False) for phi in phis]
            for y in (-0.040, -0.037, -0.033, -0.030)], "gold")
    rbox(b, (0.0, -0.083, face_zr(0.0, -0.083) - 0.0035), 0.024, 0.0035, 0.004, "lacquer_black")  # mouth slot
    # kabuto: ribbed bowl with a brow peak, gold band and finial
    ys = (0.022, 0.027, 0.034, 0.044, 0.056, 0.068, 0.080, 0.090, 0.100, 0.108, 0.112)
    b.loft([[head_pt(phi, y, bowl_push(phi, y), None, False) for phi in phis] for y in ys], "lacquer_black")
    b.loft([[head_pt(phi, y, bowl_push(phi, y) + 0.0022, None, False) for phi in phis]
            for y in (0.022, 0.026, 0.032, 0.036)], "gold")
    ellipsoid(b, (0.0, 0.119, 0.0), 0.014, 0.008, 0.014, 10, 4, "gold")
    # shikoro: neck guard of five lames over the sides and back
    mk = pmask(math.pi, 1.75, 0.35)
    ph20 = uphi(20)
    for k in range(5):
        yb = 0.030 - 0.030 * k
        hlame(b, yb - 0.042, yb, "lacquer_black" if k % 2 == 0 else "lacquer_red", 0.011 + 0.0085 * k, 0.004,
              0.004, ph20, mk)
    hlame(b, -0.132, -0.126, "gold", 0.0505, 0.002, 0.0, ph20, mk, 0.002)
    # tare: throat lames under the chin
    for k in range(2):
        shell(b, NECK_HEAD, -0.138 + 0.012 * k, -0.110 + 0.012 * k, "lacquer_red", 0.004 + 0.004 * (1 - k), 0.004, 14,
              sector(-math.pi / 2, 1.4, 0.4), 0.03, 0.004, 0, 1, None, 2.0, None, 0.002)
    # fukigaeshi: turned-back wings at the temples
    for sx in (1, -1):
        rbox(b, (sx * 0.093, 0.028, -0.040), 0.005, 0.030, 0.030, "lacquer_black", (0.0, sx * 25.0, 0.0))
        rbox(b, (sx * 0.0975, 0.028, -0.042), 0.002, 0.020, 0.020, "gold", (0.0, sx * 25.0, 0.0), 4, 10, 2.0, 2.0)
    # maedate: gold crescent on the front, tips swept back
    R = 0.07
    path = []
    wid = []
    for i in range(11):
        t = math.radians(-75.0 + 15.0 * i)
        path.append((R * math.sin(t), 0.080 + R * (1.0 - math.cos(t)), -0.094 + 0.07 * math.sin(t) ** 2))
        wid.append(0.002 + 0.010 * math.cos(t * 1.15) ** 2)
    tube(b, path, wid, 8, "gold", [0.0035] * 11, [0.0, 0.0, 1.0])
    ellipsoid(b, (0.0, 0.083, -0.087), 0.014, 0.016, 0.008, 10, 5, "gold")
'''

LIB_ALIEN = r'''
# ---------------------------------------------------------------- alien
# Tall lean grey-green humanoid. Limbs are slimmer than the base body (the colliders are unchanged), plates are
# alien_chitin (iridescent via baked vertex colour), the shin is shaped like a digitigrade leg.

def a_ua(y):
    return 0.72 + 0.04 * gauss(y / 0.1, 0.0)

def a_fa(y):
    return 0.74 + 0.05 * gauss((y - 0.08) / 0.07, 0.0)

def a_th(y):
    return 0.70 + 0.04 * gauss((y - 0.08) / 0.12, 0.0)

TORS_A = [(r[0], r[1] * 0.84, r[2] * 0.84, r[3] * 0.82, r[4] * 0.82) for r in TORSO4]
PELV_A = [(r[0], r[1] * 0.86, r[2] * 0.86, r[3] * 0.85, r[4] * 0.85) for r in PELVIS4]
NECK_A = [(0.12, 0.042, 0.042, 0.04, 0.042, 0.008), (0.2, 0.040, 0.040, 0.037, 0.040, 0.008),
          (0.25, 0.038, 0.038, 0.035, 0.038, 0.01), (0.262, 0.035, 0.035, 0.032, 0.035, 0.01),
          (0.27, 0.027, 0.027, 0.025, 0.027, 0.01)]
NECK_HA = [(-0.14, 0.034, 0.034, 0.032, 0.034, 0.012), (-0.1, 0.032, 0.032, 0.030, 0.032, 0.012),
           (-0.06, 0.033, 0.033, 0.031, 0.033, 0.016)]
SHIN_A = [  # (y, rxo, rxi, rzf, rzb, cz): the hock bulges backward, the long lower leg slopes forward to the foot
    (-0.215, 0.011, 0.011, 0.012, 0.012, -0.062), (-0.19, 0.0155, 0.0155, 0.0155, 0.0155, -0.045),
    (-0.15, 0.014, 0.014, 0.0135, 0.0135, -0.022), (-0.10, 0.0165, 0.0165, 0.015, 0.0155, 0.0),
    (-0.05, 0.021, 0.021, 0.019, 0.021, 0.016), (0.0, 0.029, 0.028, 0.026, 0.030, 0.030),
    (0.03, 0.030, 0.028, 0.027, 0.032, 0.032), (0.07, 0.036, 0.034, 0.033, 0.040, 0.026),
    (0.12, 0.043, 0.040, 0.037, 0.046, 0.014), (0.17, 0.046, 0.043, 0.040, 0.046, 0.004),
    (0.21, 0.042, 0.040, 0.038, 0.042, 0.0), (0.228, 0.033, 0.032, 0.032, 0.033, 0.0),
    (0.236, 0.015, 0.015, 0.015, 0.015, 0.0),
]
HEAD_A = [  # (y, half width, front depth, back depth): bulbous cranium, narrow jaw
    (-0.128, 0.022, 0.036, 0.024), (-0.118, 0.030, 0.050, 0.032), (-0.10, 0.040, 0.060, 0.044),
    (-0.07, 0.054, 0.070, 0.062), (-0.04, 0.068, 0.082, 0.082), (-0.01, 0.082, 0.092, 0.100),
    (0.02, 0.095, 0.098, 0.116), (0.05, 0.105, 0.100, 0.126), (0.08, 0.108, 0.098, 0.128),
    (0.11, 0.100, 0.088, 0.122), (0.128, 0.080, 0.068, 0.100), (0.139, 0.045, 0.040, 0.066),
    (0.1425, 0.010, 0.010, 0.014),
]
ALIEN_HEAD_YS = [-0.128, -0.12, -0.108, -0.092, -0.075, -0.058, -0.04, -0.022, -0.005, 0.012, 0.03, 0.048, 0.066,
                 0.084, 0.1, 0.114, 0.127, 0.137, 0.1425]

def a_face(phi, y):
    return -0.004 * gauss((abs(phi) - 0.6) / 0.3, (y + 0.06) / 0.03)  # sunken cheeks

def build_hand3(b):
    """Three long thin fingers curled round the grip bar, narrow palm."""
    build_hand(b, "alien_skin", (-0.024, 0.0, 0.024), (0.0078, 0.0080, 0.0078), (0.0252, 0.0254, 0.0252), -250, 0.72)

def build_upper_arm_alien(b):
    limb(b, UPPER_ARM, 14, "alien_skin", None, None, 2.0, a_ua)
    shell(b, UPPER_ARM, 0.06, 0.15, "alien_chitin", 0.004, 0.007, 14, sector(0.2, 2.0, 0.5), 0.03, 0.006, 1, 2, None,
          2.0, a_ua, 0.004)
    shell(b, UPPER_ARM, -0.03, 0.05, "alien_chitin", 0.003, 0.006, 14, sector(0.2, 1.7, 0.5), 0.03, 0.006, 0, 2, None,
          2.0, a_ua, 0.003)

def build_forearm_alien(b):
    limb(b, FOREARM, 14, "alien_skin", None, None, 2.0, a_fa)
    for i in range(5):  # chitin segments, upper over lower, along the outer back of the forearm
        yb = 0.135 - 0.04 * i
        shell(b, FOREARM, yb - 0.05, yb, "alien_chitin", 0.003 + 0.0006 * (4 - i), 0.0055, 14, sector(0.3, 2.1, 0.5),
              0.03, 0.005, 0, 1, None, 2.0, a_fa, 0.003)
    build_hand3(b)

def build_pelvis_alien(b):
    limb(b, PELV_A, 24, "alien_skin", None, None, 2.5)
    shell(b, PELV_A, 0.02, 0.09, "alien_chitin", 0.004, 0.006, 24, None, 0.03, 0.008, 1, 2, None, 2.5)
    for k in range(3):  # hip plates down the front
        yb = 0.015 - 0.045 * k
        shell(b, PELV_A, yb - 0.055, yb, "alien_chitin", 0.003 + 0.0006 * (2 - k), 0.006, 20,
              sector(-math.pi / 2, 0.75 - 0.1 * k, 0.3), 0.03, 0.006, 0, 1, None, 2.5, None, 0.003)

def build_thigh_alien(b):
    ys = [r[0] for r in sorted(THIGH)] + [0.0]
    limb(b, THIGH, 14, "alien_skin", None, sorted(ys), 2.0, a_th)
    for k in range(3):  # armoured ridge along the outer thigh
        yb = 0.12 - 0.08 * k
        shell(b, THIGH, yb - 0.095, yb, "alien_chitin", 0.003 + 0.0006 * (2 - k), 0.005, 14, sector(0.0, 0.8, 0.35),
              0.03, 0.006, 0, 1, None, 2.0, a_th, 0.002)

def build_shin_alien(b):
    limb(b, SHIN_A, 14, "alien_skin", None, None, 2.0)
    tube(b, [(0.0, 0.03, 0.05), (0.0, 0.016, 0.066), (0.0, 0.008, 0.078)], [0.012, 0.007, 0.0015], 8, "alien_chitin")  # hock spur
    shell(b, SHIN_A, 0.1, 0.2, "alien_chitin", 0.003, 0.005, 14, sector(-math.pi / 2, 0.8, 0.3), 0.03, 0.006, 0, 1)
    # foot: metatarsal, pad, three long toes with claws, heel talon (visual only, the sole stays at -0.258)
    tube(b, [(0.0, -0.19, -0.045), (0.0, -0.22, -0.062), (0.0, -0.243, -0.085)], [0.0155, 0.0135, 0.012], 8, "alien_skin")
    ellipsoid(b, (0.0, -0.245, -0.085), 0.026, 0.013, 0.05, 12, 6, "alien_skin")
    for x0, x1 in ((-0.022, -0.036), (0.0, 0.0), (0.022, 0.036)):
        tube(b, [(x0, -0.246, -0.100), ((x0 + x1) * 0.5, -0.248, -0.140), (x1, -0.250, -0.172)],
             [0.0085, 0.0070, 0.0050], 8, "alien_skin")
        tube(b, [(x1, -0.250, -0.172), (x1 * 1.05, -0.2515, -0.181)], [0.0048, 0.0012], 6, "alien_chitin")
    tube(b, [(0.0, -0.245, -0.02), (0.0, -0.243, 0.03), (0.0, -0.236, 0.062)], [0.008, 0.006, 0.002], 6, "alien_chitin")

def build_torso_alien(b):
    def ribs(x, y, c, s):
        return 0.0022 * math.sin(y * 150.0) * smooth(-0.02, 0.0, y) * smooth(0.18, 0.15, y) * max(-s, 0.0)
    ys = [-0.27, -0.24, -0.20, -0.16, -0.12, -0.08, -0.04, 0.0, 0.04, 0.08, 0.12, 0.16, 0.19, 0.215, 0.235, 0.25]
    limb(b, TORS_A, 24, "alien_skin", ribs, ys, 2.4)
    limb(b, NECK_A, 12, "alien_skin")
    for sx in (1, -1):  # shoulder joint nodules bridging the narrow chest to the arm sockets
        rbox(b, (sx * 0.215, 0.168, 0.0), 0.046, 0.040, 0.044, "alien_chitin", (0.0, 0.0, sx * -12.0), 6, 14, 2.4, 2.0)
    for k in range(7):  # front chitin segments, upper over lower
        yb = 0.17 - 0.052 * k
        shell(b, TORS_A, yb - 0.062, yb, "alien_chitin", 0.003 + 0.0008 * (6 - k), 0.007, 20,
              sector(-math.pi / 2, 1.15 - 0.07 * k, 0.35), 0.03, 0.007, 0, 2, None, 2.4, None, 0.004)
    for k in range(6):  # dorsal plates and spines
        yb = 0.19 - 0.06 * k
        shell(b, TORS_A, yb - 0.07, yb, "alien_chitin", 0.003 + 0.0008 * (5 - k), 0.01, 18,
              sector(math.pi / 2, 0.62 - 0.03 * k, 0.3), 0.03, 0.008, 0, 1, None, 2.4, None, 0.004)
        zb = rowinterp(yb - 0.035, TORS_A)[3] + 0.012
        tube(b, [(0.0, yb - 0.035, zb), (0.0, yb - 0.028, zb + 0.02)], [0.0075, 0.0012], 6, "alien_chitin")

def build_head_alien(b):
    rows = HEAD_A
    b.loft([[head_pt(phi, y, a_face(phi, y), rows, False) for phi in HEAD_PHI] for y in ALIEN_HEAD_YS], "alien_skin")
    limb(b, NECK_HA, 10, "alien_skin")
    xc, yc, hx = 0.047, 0.008, 0.034
    tilt = 24.0
    xi, xo = xc - hx * math.cos(math.radians(tilt)), xc + hx * math.cos(math.radians(tilt))
    yaw = math.degrees(math.atan2(face_zr(xi, yc, rows) - face_zr(xo, yc, rows), xo - xi))
    for sx in (1, -1):  # large black almond eyes, outer corners raised, wrapped round the cranium
        rbox(b, (sx * xc, yc, face_zr(xc, yc, rows) + 0.002), hx, 0.019, 0.009, "alien_eye",
             (0.0, -sx * yaw, sx * tilt), 8, 16, 2.0, 2.0)
        rbox(b, (sx * 0.007, -0.04, face_zr(0.007, -0.04, rows) + 0.0005), 0.0018, 0.0045, 0.002, "alien_mouth",
             (0.0, 0.0, sx * 20.0), 3, 6, 2.0, 2.0)
    rbox(b, (0.0, -0.088, face_zr(0.0, -0.088, rows) + 0.0005), 0.016, 0.0014, 0.003, "alien_mouth", (0, 0, 0), 3, 8,
         2.0, 2.0)
'''

SAMPLE_CALL = "build_%s_%s(b)"


def make_materials():
    mat = hou.node("/mat")
    for name, (col, rough, metal) in MATERIALS.items():
        m = mat.createNode("principledshader::2.0", name)
        m.parmTuple("basecolor").set(col)
        m.parm("rough").set(rough)
        m.parm("metallic").set(metal)


def make_node(name, pos, code, outdir, fname, mx=1, origin=(0.0, 0.0, 0.0), lib=""):
    obj = hou.node("/obj").createNode("geo", name)
    obj.parmTuple("t").set(pos)
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB_COMMON + lib + "\nb = B(hou.pwd().geometry(), %r, %r)\n%s\n" % (float(mx), tuple(origin), code))
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
    rop.parm("outputfile").set("$HIP/../export/outfits/%s/%s.glb" % (outdir, fname))
    rop.parm("exportmaterials").set(1)
    return obj, out, rop


def read_glb(path):
    """Return (triangles, bbox min, bbox max, signed volume, material names, attribute names) from a .glb file."""
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


def render_previews(outfit, detail):
    """One image per outfit: the figure from the front (left) and in 3/4 view (right), assembled from the part objects."""
    objn = hou.node("/obj")
    for old in ("preview_cam", "key", "fill", "rim", "sky"):
        if objn.node(old):
            objn.node(old).destroy()
    cam = objn.createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    for name, t, inten in (("key", (4, 4.5, -3), 1.2), ("fill", (-4, 1, -3), 0.3), ("rim", (-1, 3, 6), 0.6)):
        l = objn.createNode("hlight", name)
        l.parmTuple("t").set(t)
        l.parm("light_intensity").set(inten)
    objn.createNode("envlight", "sky").parm("light_intensity").set(0.35)
    rop = hou.node("/out").createNode("karma", "preview_" + outfit)
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

    names = []
    for fig, (x0, yaw) in enumerate(((-0.55, 0.0), (0.55, -38.0))):
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        for part, (pos, mx, _) in PARTS.items():
            if part == "head_b":
                continue
            src = objn.node("%s_%s" % (outfit, part))
            x, y, z = pos
            pv = objn.createNode("geo", "pv%d_%s_%s" % (fig, outfit, part))
            pv.parmTuple("t").set((x0 + x * cy + z * sy, y, -x * sy + z * cy))
            pv.parmTuple("r").set((0, yaw, 0))
            om = pv.createNode("object_merge", "src")
            om.parm("objpath1").set(src.node("OUT").path())
            om.parm("numobj").set(1)
            om.setDisplayFlag(True)
            names.append(pv.name())
    shoot(os.path.join(EXPORT, "preview_%s.png" % outfit), (0, 0.95, 0), 2.8, (0, 180, 0), (1280, 960), " ".join(names))
    if detail:
        heads = [n for n in names if n.endswith("_head") and n.startswith("pv0")]
        shoot(os.path.join(EXPORT, "preview_%s_head.png" % outfit), (-0.55, 1.70, 0), 0.45, (-5, 200, 0), (768, 768),
              " ".join(heads))


def selected_outfits():
    for i, a in enumerate(sys.argv):
        val = None
        if a == "--outfit" and i + 1 < len(sys.argv):
            val = sys.argv[i + 1]
        elif a.startswith("--outfit="):
            val = a.split("=", 1)[1]
        if val and val != "all":
            return [v for v in val.split(",") if v in OUTFITS]
    return list(OUTFITS)


def main():
    outfits = selected_outfits()
    hou.hipFile.clear(suppress_save_prompt=True)
    for o in outfits:
        os.makedirs(os.path.join(EXPORT, o), exist_ok=True)
    os.makedirs(os.path.dirname(HIP), exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    libs = {"samurai": LIB_SAMURAI, "alien": LIB_ALIEN}
    rops = {}
    for o in outfits:
        for part, (pos, mx, _) in PARTS.items():
            name = "%s_%s" % (o, part)
            code = SAMPLE_CALL % (BUILDER[part], o)
            _, _, rop = make_node(name, pos, code, o, part, mx, pos, libs[o])
            rops[(o, part)] = rop
        if OUTFITS[o]["cap_mats"]:
            for i, (cname, (R, bones)) in enumerate(CAPS.items()):
                code = "build_cap(b, %r, %r, 20, %r)" % (R, bones, OUTFITS[o]["cap_mats"])
                _, _, rop = make_node("%s_%s" % (o, cname), (i * 0.2, 3.0, 0), code, o, cname, 1, (0.0, 0.0, 0.0), libs[o])
                rops[(o, cname)] = rop
    hou.hipFile.save(HIP)

    ok = True
    for o in outfits:
        total = 0
        print("== %s" % o)
        for key in [k for k in rops if k[0] == o]:
            name = key[1]
            rops[key].render()
            tris, lo, hi, vol, mnames, attrs = read_glb(os.path.join(EXPORT, o, name + ".glb"))
            notes = []
            good = tris <= TRI_LIMIT and vol > 0 and {"NORMAL", "TEXCOORD_0", "COLOR_0"} <= attrs
            if tris > TRI_LIMIT:
                notes.append("over %d tris" % TRI_LIMIT)
            if not set(mnames) <= OUTFITS[o]["mats"] | (set(OUTFITS[o]["cap_mats"].values()) if OUTFITS[o]["cap_mats"] else set()):
                notes.append("unexpected materials")
                good = False
            if name in PARTS:
                if name != "head_b":
                    total += tris
                blo, bhi = PARTS[name][2]
                tol = TOL_HEAD if name in HEAD_PARTS else TOL
                for k, ax in enumerate("xyz"):
                    if lo[k] < blo[k] - tol - 0.003 or hi[k] > bhi[k] + tol + 0.003:
                        notes.append("%s over by %.3f" % (ax, max(blo[k] - lo[k], hi[k] - bhi[k]) - tol))
                    if ax == "y" and (lo[k] > blo[k] + 0.015 or hi[k] < bhi[k] - 0.015):
                        notes.append("y ends short by %.3f (joint overlap / cut cap fit)" % max(lo[k] - blo[k], bhi[k] - hi[k]))
            print("%-13s tris=%5d bbox=(%+.3f %+.3f %+.3f)..(%+.3f %+.3f %+.3f) vol=%.5f mats=%s %s%s" % (
                name, tris, *lo, *hi, vol, ",".join(mnames), "OK" if good and not notes else "CHECK",
                (" [" + "; ".join(notes) + "]") if notes else ""))
            ok = ok and good
        print("total tris (12 parts without head_b): %d" % total)

    if "--no-preview" not in sys.argv:
        for o in outfits:
            try:
                render_previews(o, "--detail" in sys.argv)
            except hou.Error as e:
                print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
