"""Build Sandblood weapon visual meshes procedurally and export them as .glb.

Run:  hython scripts/build_weapons.py   (re-runnable; rebuilds hip, exports, previews)

Conventions: meters, Y up, long axis +Y, origin = grip point.
Blades lie in XY (edges face +/-X), axe head toward +X, rake tines toward +Z,
shield disc in XY facing +Z with its centre at z = 0.05.
"""
import json
import math
import os
import struct
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "weapons.hip")
EXPORT = os.path.join(ROOT, "export", "weapons")
PREVIEW = os.path.join(ROOT, "preview")

# id: (length, grip, edge length or None, materials)
SPECS = {
    "rake": (1.6, 0.2, None, ["wood", "steel"]),
    "bat": (0.85, 0.1, None, ["aluminium", "grip"]),
    "club": (0.75, 0.1, None, ["wood"]),
    "gladius": (0.6, 0.08, 0.45, ["steel", "wood"]),
    "longsword": (1.2, 0.1, 0.9, ["steel", "grip"]),
    "axe": (0.85, 0.1, 0.18, ["wood", "steel"]),
    "spear": (2.2, 0.3, 0.15, ["wood", "steel"]),
    "shield_round": (0.6, 0.0, None, ["wood", "iron"]),
    # Premium (outfit-bundled) weapons: docs/weapons_premium.md. Run only these with --only=dai_katana,laser_sword
    "dai_katana": (1.25, 0.1, 0.9, ["steel", "cord", "wrap", "brass", "iron"]),
    "laser_sword": (1.25, 0.12, 1.05, ["hilt", "brass", "energy"]),
}
ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
if ONLY:
    SPECS = {k: v for k, v in SPECS.items() if k in ONLY[0].split(",")}

# name: (base color, roughness, metallic)
MATERIALS = {
    "wood": ((0.42, 0.27, 0.14), 0.75, 0.0),
    "steel": ((0.62, 0.63, 0.66), 0.3, 1.0),
    "iron": ((0.28, 0.28, 0.30), 0.55, 1.0),
    "grip": ((0.16, 0.10, 0.07), 0.85, 0.0),
    "aluminium": ((0.78, 0.79, 0.82), 0.25, 1.0),
    "cord": ((0.07, 0.09, 0.17), 0.9, 0.0),
    "wrap": ((0.62, 0.52, 0.3), 0.85, 0.0),
    "brass": ((0.55, 0.42, 0.16), 0.4, 1.0),
    "hilt": ((0.2, 0.21, 0.24), 0.35, 1.0),
    # name: (base colour, rough, metal, emission colour, emission intensity): the laser blade glows on its own
    "energy": ((0.85, 1.0, 0.95), 0.2, 0.0, (0.2, 1.0, 0.8), 6.0),
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

class B:
    def __init__(self, geo):
        self.geo = geo
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

    def loft(self, rings, mat, cap0=True, cap1=True, wrap=False):
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
        quads = []
        votes = 0.0
        for k in range(bands):
            k2 = (k + 1) % len(rings)
            axis = centroid([cs[k], cs[k2]])
            for j in range(n):
                j2 = (j + 1) % n
                q = [(k, j), (k, j2), (k2, j2), (k2, j)]
                c = [rings[a][b] for a, b in q]
                votes += self.sign * dot(newell(c), sub(centroid(c), axis))
                uv = [(j / n, d[k] / tot), ((j + 1) / n, d[k] / tot),
                      ((j + 1) / n, d[k + 1] / tot), (j / n, d[k + 1] / tot)]
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
            c = cs[idx]
            uv = [(0.5 + 0.5 * math.cos(2 * math.pi * j / n), 0.5 + 0.5 * math.sin(2 * math.pi * j / n)) for j in order]
            self.poly([P[idx][j] for j in order], uv, m)

def circ(r, h, segs, axis="y", c=(0, 0, 0), sx=1.0, sz=1.0, rfn=None):
    out = []
    for j in range(segs):
        a = 2 * math.pi * j / segs
        rr = r * (rfn(a, h) if rfn else 1.0)
        u = rr * math.cos(a) * sx
        v = rr * math.sin(a) * sz
        if axis == "y":
            out.append((c[0] + u, c[1] + h, c[2] + v))
        elif axis == "z":
            out.append((c[0] + u, c[1] + v, c[2] + h))
        else:
            out.append((c[0] + h, c[1] + u, c[2] + v))
    return out

def lathe(b, prof, segs, mat, axis="y", c=(0, 0, 0), sx=1.0, sz=1.0, rfn=None):
    b.loft([circ(r, h, segs, axis, c, sx, sz, rfn) for r, h in prof], mat)

def box(b, lo, hi, mat):
    x0, y0, z0 = lo; x1, y1, z1 = hi
    b.loft([[(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]], mat)

def sphere_prof(r, cy, steps=8):
    out = []
    for k in range(steps + 1):
        phi = math.pi * k / steps
        out.append((max(r * math.sin(phi), 0.0008), cy - r * math.cos(phi)))
    return out

def blade(b, y0, y1, wt, tt, mat, fuller=0.0, nseg=16):
    rings = []
    for i in range(nseg + 1):
        s = i / nseg
        y = y0 + (y1 - y0) * s
        w = max(interp(s, wt), 0.0006)
        t = max(interp(s, tt), 0.0004)
        if fuller > 0:
            f = fuller * max(0.0, 1.0 - s / 0.8)
            ring = [(w, y, 0), (0.5 * w, y, t), (0.2 * w, y, t), (0, y, t * (1 - f)),
                    (-0.2 * w, y, t), (-0.5 * w, y, t), (-w, y, 0), (-0.5 * w, y, -t),
                    (-0.2 * w, y, -t), (0, y, -t * (1 - f)), (0.2 * w, y, -t), (0.5 * w, y, -t)]
        else:
            ring = [(w, y, 0), (0.45 * w, y, t), (0, y, t), (-0.45 * w, y, t),
                    (-w, y, 0), (-0.45 * w, y, -t), (0, y, -t), (0.45 * w, y, -t)]
        rings.append(ring)
    b.loft(rings, mat)

def build_rake(b):
    lathe(b, [(0.014, -0.2), (0.015, -0.19), (0.015, 1.30)], 12, "wood")
    lathe(b, [(0.017, 1.28), (0.017, 1.33), (0.012, 1.37)], 12, "steel")
    box(b, (-0.18, 1.37, -0.012), (0.18, 1.4, 0.012), "steel")
    for i in range(12):
        x = -0.165 + i * 0.03
        lathe(b, [(0.0045, 0.0), (0.0045, 0.06), (0.0015, 0.09)], 6, "steel", axis="z", c=(x, 1.385, 0))

def build_bat(b):
    prof = [(0.020, -0.1), (0.027, -0.097), (0.027, -0.088), (0.016, -0.082), (0.0135, -0.075),
            (0.0135, 0.18), (0.014, 0.2), (0.02, 0.35), (0.028, 0.48), (0.033, 0.58),
            (0.033, 0.70), (0.031, 0.735), (0.024, 0.748), (0.012, 0.75)]
    mats = ["aluminium"] * (len(prof) - 1)
    mats[4] = "grip"
    lathe(b, prof, 20, mats)

def build_club(b):
    knots = [(0.8, 0.25), (3.0, 0.42), (5.1, 0.33), (1.9, 0.55), (4.2, 0.12)]
    def rfn(a, h):
        r = 1.0 + 0.07 * math.sin(3 * a + 11 * h) + 0.05 * math.sin(5 * a - 17 * h + 1.3)
        for a0, h0 in knots:
            da = math.atan2(math.sin(a - a0), math.cos(a - a0))
            r += 0.28 * math.exp(-(da * da) / 0.06 - (h - h0) ** 2 / 0.0005)
        return r
    tab = [(-0.1, 0.022), (-0.085, 0.019), (0.15, 0.018), (0.35, 0.034), (0.5, 0.045),
           (0.58, 0.05), (0.62, 0.042), (0.64, 0.03), (0.65, 0.012)]
    hs = [-0.1, -0.085] + [-0.06 + 0.04 * i for i in range(17)] + [0.6, 0.62, 0.635, 0.645, 0.65]
    prof = [(interp(h, tab), h) for h in hs]
    lathe(b, prof, 18, "wood", rfn=rfn)

def build_gladius(b):
    lathe(b, sphere_prof(0.025, -0.055), 14, "wood")
    lathe(b, [(0.0125, -0.035), (0.0145, -0.025), (0.0125, -0.012), (0.0145, 0.0),
              (0.0125, 0.012), (0.0145, 0.025), (0.0125, 0.035)], 12, "wood", sz=0.8)
    lathe(b, [(0.032, 0.035), (0.04, 0.045), (0.04, 0.062), (0.03, 0.07)], 16, "wood", sz=0.55)
    blade(b, 0.07, 0.52, [(0, 0.024), (0.35, 0.021), (0.68, 0.025), (0.82, 0.02), (0.93, 0.01), (1.0, 0.0)],
          [(0, 0.0045), (0.8, 0.0035), (1.0, 0.0006)], "steel", nseg=18)

def build_longsword(b):
    lathe(b, [(0.016, -0.012), (0.022, -0.008), (0.022, 0.008), (0.016, 0.012)], 16, "steel",
          axis="z", c=(0, -0.078, 0))
    lathe(b, [(0.013, -0.058), (0.0145, -0.04), (0.016, 0.05), (0.0145, 0.15), (0.013, 0.165)],
          12, "grip", sz=0.8)
    rings = []
    for x in (-0.1, -0.09, -0.05, 0.0, 0.05, 0.09, 0.1):
        f = abs(x) / 0.1
        hh = 0.0175 * (1.0 - 0.35 * f) if f < 0.95 else 0.0175 * 0.9
        ht = 0.012 * (1.0 - 0.3 * f)
        cy = 0.1825
        rings.append([(x, cy - hh, -ht), (x, cy + hh, -ht), (x, cy + hh, ht), (x, cy - hh, ht)])
    b.loft(rings, "steel")
    blade(b, 0.2, 1.1, [(0, 0.026), (0.75, 0.019), (0.9, 0.012), (1.0, 0.0)],
          [(0, 0.005), (1.0, 0.0012)], "steel", fuller=0.45, nseg=20)

def build_axe(b):
    lathe(b, [(0.017, -0.1), (0.016, -0.09), (0.014, 0.0), (0.016, 0.6), (0.017, 0.74), (0.012, 0.75)],
          12, "wood")
    head = [(-0.035, 0.70, 0.025, 0.018), (-0.02, 0.70, 0.03, 0.021), (0.025, 0.70, 0.03, 0.021),
            (0.06, 0.695, 0.035, 0.01), (0.10, 0.68, 0.055, 0.006), (0.14, 0.665, 0.08, 0.003),
            (0.16, 0.66, 0.09, 0.0008)]
    b.loft([[(x, cy - hh, -ht), (x, cy + hh, -ht), (x, cy + hh, ht), (x, cy - hh, ht)]
            for x, cy, hh, ht in head], "steel")

def build_spear(b):
    lathe(b, [(0.012, -0.3), (0.0165, -0.29), (0.0165, -0.27)], 10, "steel")
    lathe(b, [(0.0165, -0.27), (0.016, 1.0), (0.0145, 1.67)], 10, "wood")
    lathe(b, [(0.017, 1.64), (0.0165, 1.70), (0.011, 1.75)], 10, "steel")
    blade(b, 1.75, 1.9, [(0, 0.01), (0.3, 0.03), (0.55, 0.026), (1.0, 0.0)],
          [(0, 0.008), (0.5, 0.005), (1.0, 0.001)], "steel", nseg=12)

def build_shield_round(b):
    R = 0.29
    n = 6
    w = 2 * R / n
    for i in range(n):
        xa = -R + i * w + (0.001 if i else 0.0001)
        xb = -R + (i + 1) * w - (0.001 if i < n - 1 else 0.0001)
        xs = [xa + (xb - xa) * k / 6 for k in range(7)]
        top = [(x, math.sqrt(max(R * R - x * x, 1e-8))) for x in xs]
        outline = top + [(x, -y) for x, y in reversed(top)]
        b.loft([[(x, y, 0.04) for x, y in outline], [(x, y, 0.06) for x, y in outline]], "wood")
    sect = [(0.284, 0.035), (0.3, 0.035), (0.3, 0.066), (0.284, 0.066)]
    rings = []
    for k in range(32):
        a = 2 * math.pi * k / 32
        rings.append([(rr * math.cos(a), rr * math.sin(a), zz) for rr, zz in sect])
    b.loft(rings, "iron", wrap=True)
    lathe(b, [(0.08, 0.058), (0.08, 0.064), (0.06, 0.066), (0.058, 0.085), (0.045, 0.1),
              (0.025, 0.11), (0.003, 0.114)], 18, "iron", axis="z")
    box(b, (-0.012, -0.06, -0.012), (0.012, 0.06, 0.012), "wood")
    box(b, (-0.012, -0.075, -0.012), (0.012, -0.06, 0.04), "iron")
    box(b, (-0.012, 0.06, -0.012), (0.012, 0.075, 0.04), "iron")

def curved_blade(b, y0, y1, curve, wt, tt, mat, nseg=24):
    # Single-edged curved blade: edge toward +X, thick spine toward -X, the tip bends toward the edge (x = curve * s^2).
    rings = []
    for i in range(nseg + 1):
        s = i / nseg
        y = y0 + (y1 - y0) * s
        dx = curve * s * s
        w = max(interp(s, wt), 0.0006)
        t = max(interp(s, tt), 0.0004)
        rings.append([(w + dx, y, 0), (0.35 * w + dx, y, t), (-0.85 * w + dx, y, 0.95 * t),
                      (-w + dx, y, 0.55 * t), (-w + dx, y, -0.55 * t), (-0.85 * w + dx, y, -0.95 * t),
                      (0.35 * w + dx, y, -t)])
    b.loft(rings, mat)

def build_dai_katana(b):
    # +Y long axis, origin 0.1 m above the pommel: kashira -0.1, wrapped tsuka to 0.215, fuchi, tsuba 0.235, blade 0.275..1.15.
    lathe(b, [(0.012, -0.1), (0.018, -0.094), (0.018, -0.078), (0.0155, -0.072)], 14, "brass", sz=0.75)
    lathe(b, [(0.0155, -0.072), (0.0165, -0.03), (0.0172, 0.07), (0.0165, 0.17), (0.0155, 0.215)], 14, "cord", sz=0.75)
    for k in range(9):
        y = -0.062 + k * 0.0165
        lathe(b, [(0.0168, y), (0.0178, y + 0.003), (0.0178, y + 0.009), (0.0168, y + 0.012)], 14, "wrap", sz=0.75)
    lathe(b, [(0.0155, 0.215), (0.021, 0.218), (0.021, 0.232), (0.0155, 0.235)], 16, "brass", sz=0.8)
    lathe(b, [(0.02, 0.235), (0.05, 0.235), (0.052, 0.239), (0.05, 0.243), (0.02, 0.243)], 28, "iron")
    lathe(b, [(0.019, 0.243), (0.021, 0.26), (0.019, 0.275)], 14, "brass", sz=0.4)
    curved_blade(b, 0.275, 1.15, 0.04,
                 [(0, 0.0175), (0.7, 0.016), (0.88, 0.0135), (1.0, 0.0)],
                 [(0, 0.0045), (0.85, 0.0035), (1.0, 0.0008)], "steel")

def build_laser_sword(b):
    # Hilt from the pommel (-0.12) to the emitter (0.06); the 1.07 m blade is a capsule core of the "energy" material.
    # The game adds its own translucent halo, light, trail and hum around it (game/fighter/weapon.gd, game/fx/blade_glow.gd).
    lathe(b, [(0.012, -0.12), (0.021, -0.113), (0.021, -0.098), (0.0155, -0.09)], 16, "brass")
    lathe(b, [(0.0155, -0.09), (0.0165, -0.06), (0.0155, -0.03), (0.0165, 0.0), (0.0155, 0.03), (0.0165, 0.04)], 16, "hilt")
    for k in range(5):
        y = -0.08 + k * 0.025
        lathe(b, [(0.0155, y), (0.0185, y + 0.002), (0.0185, y + 0.006), (0.0155, y + 0.008)], 16, "brass")
    lathe(b, [(0.0165, 0.04), (0.03, 0.045), (0.034, 0.055), (0.03, 0.062), (0.014, 0.064)], 20, "hilt")
    box(b, (-0.06, 0.036, -0.009), (0.06, 0.046, 0.009), "hilt")
    lathe(b, [(0.0035, 0.064), (0.011, 0.07), (0.011, 1.10), (0.0085, 1.12), (0.004, 1.128), (0.0008, 1.132)], 14, "energy")
'''


def make_materials():
    mat = hou.node("/mat")
    for name, spec in MATERIALS.items():
        col, rough, metal = spec[:3]
        m = mat.createNode("principledshader::2.0", name)
        m.parmTuple("basecolor").set(col)
        m.parm("rough").set(rough)
        m.parm("metallic").set(metal)
        if len(spec) > 3:  # emissive: exports as glTF emissiveFactor (Godot: emission on)
            m.parm("emitint").set(spec[4])
            m.parmTuple("emitcolor").set(spec[3])


def make_weapon(wid, x_offset):
    obj = hou.node("/obj").createNode("geo", wid)
    obj.parmTuple("t").set((x_offset, 0, 0))
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild_%s(B(hou.pwd().geometry()))\n" % wid)
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, py)
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, div)
    nrm.parm("cuspangle").set(45)
    out = obj.createNode("null", "OUT")
    out.setInput(0, nrm)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    rop = hou.node("/out").createNode("gltf", "export_" + wid)
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    rop.parm("outputfile").set("$HIP/../export/weapons/%s.glb" % wid)
    rop.parm("exportmaterials").set(1)
    return obj, out, rop


def read_glb(path):
    """Return (triangles, bbox min, bbox max, signed volume) from a .glb file."""
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
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
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
    return tris, lo, hi, vol, [m["name"] for m in doc.get("materials", [])]


def render_previews(objs):
    cam = hou.node("/obj").createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    cam.parm("resx").set(512)
    cam.parm("resy").set(512)
    key = hou.node("/obj").createNode("hlight", "key")
    key.parmTuple("t").set((3, 4, 6))
    fill = hou.node("/obj").createNode("hlight", "fill")
    fill.parmTuple("t").set((-4, 1, 3))
    fill.parm("light_intensity").set(0.5)
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(0.6)
    rop = hou.node("/out").createNode("karma", "preview")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)

    def shoot(path, center, width, rot, res=(512, 512), vis="*"):
        cam.parm("resx").set(res[0]); cam.parm("resy").set(res[1])
        rop.parm("resolutionx").set(res[0]); rop.parm("resolutiony").set(res[1])
        r = hou.hmath.buildRotate(rot, "xyz")
        pos = hou.Vector3(center) + hou.Vector3(0, 0, 10) * r
        cam.setWorldTransform(r * hou.hmath.buildTranslate(pos))
        cam.parm("orthowidth").set(width)
        rop.parm("candobjects").set(vis)
        rop.parm("picture").set(path)
        rop.render()

    for wid, (obj, out) in objs.items():
        bb = out.geometry().boundingBox()
        c = bb.center() + hou.Vector3(obj.parmTuple("t").eval())
        size = bb.sizevec()
        diag = max(size[0], size[1], size[2])
        shoot(os.path.join(PREVIEW, wid + ".png"), c, diag * 0.85 if wid != "shield_round" else diag * 1.2,
              (-15, 25, 0 if wid == "shield_round" else 45), vis=obj.name())
    xs = [o.parmTuple("t").eval()[0] for o, _ in objs.values()]
    shoot(os.path.join(PREVIEW, "all.png"), ((min(xs) + max(xs)) / 2, 0.8, 0), max((max(xs) - min(xs)) + 0.8, 5.0),
          (-5, 0, 0), res=(1536, 768), vis=" ".join(o.name() for o, _ in objs.values()))


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    os.makedirs(EXPORT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    objs, rops = {}, {}
    x = 0.0
    for wid in SPECS:
        obj, out, rop = make_weapon(wid, x)
        objs[wid] = (obj, out)
        rops[wid] = rop
        bb = out.geometry().boundingBox()
        x += max(bb.sizevec()[0], 0.1) + 0.25
    hou.hipFile.save(HIP)

    ok = True
    for wid, (length, grip, edge, mats) in SPECS.items():
        rops[wid].render()
        path = os.path.join(EXPORT, wid + ".glb")
        tris, lo, hi, vol, mnames = read_glb(path)
        if wid == "shield_round":
            want = [(-0.3, 0.3), (-0.3, 0.3)]
            got = [(lo[0], hi[0]), (lo[1], hi[1])]
        else:
            want = [(-grip, length - grip)]
            got = [(lo[1], hi[1])]
        good = all(abs(a - c) <= 0.01 and abs(b - d) <= 0.01 for (a, b), (c, d) in zip(want, got))
        good = good and tris <= 3000 and vol > 0
        ok = ok and good
        print("%-13s %s tris=%5d bbox=(%.3f %.3f %.3f)..(%.3f %.3f %.3f) vol=%.6f mats=%s" % (
            wid, "OK  " if good else "FAIL", tris, *lo, *hi, vol, ",".join(mnames)))

    if "--no-preview" not in sys.argv:
        try:
            render_previews(objs)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
