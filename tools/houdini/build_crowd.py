"""Build Sandblood crowd spectator variants (one low-poly mesh each) and export them as .glb.

Run:  hython scripts/build_crowd.py [--no-preview]   (re-runnable; rebuilds hip, exports, lineup preview)

Conventions: metres, Y up, facing -Z (toward the arena), origin at the feet centre on the tier floor.
Seated variants sit on a 0.45 m bench. Regions are encoded in vertex colour for per-instance tinting:
red = clothing, green = skin, blue = hair. One material "crowd" with white base colour.
"""
import json
import os
import struct
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "crowd.hip")
EXPORT = os.path.join(ROOT, "export", "crowd")
PREVIEW = os.path.join(ROOT, "preview")

VARIANTS = ["stand_idle", "stand_cheer_one_arm", "stand_cheer_both_arms", "stand_fist_pump", "stand_point",
            "stand_thumbs", "sit_idle", "sit_lean", "stand_idle_f", "stand_cheer_f", "noble_sit"]

# Preview tints per variant: (cloth, skin, hair)
TINTS = [((0.55, 0.12, 0.08), (0.62, 0.38, 0.24), (0.06, 0.04, 0.03)),
         ((0.15, 0.25, 0.55), (0.45, 0.26, 0.15), (0.03, 0.03, 0.03)),
         ((0.60, 0.50, 0.20), (0.70, 0.48, 0.34), (0.20, 0.10, 0.04)),
         ((0.25, 0.45, 0.20), (0.30, 0.17, 0.10), (0.02, 0.02, 0.02)),
         ((0.40, 0.30, 0.20), (0.62, 0.38, 0.24), (0.10, 0.06, 0.03)),
         ((0.50, 0.15, 0.40), (0.55, 0.33, 0.20), (0.05, 0.04, 0.03)),
         ((0.70, 0.65, 0.55), (0.40, 0.22, 0.13), (0.03, 0.03, 0.03)),
         ((0.20, 0.35, 0.45), (0.66, 0.44, 0.30), (0.30, 0.15, 0.05)),
         ((0.55, 0.20, 0.30), (0.62, 0.40, 0.27), (0.12, 0.06, 0.03)),
         ((0.20, 0.45, 0.45), (0.38, 0.21, 0.12), (0.02, 0.02, 0.02)),
         ((0.90, 0.88, 0.82), (0.60, 0.40, 0.28), (0.25, 0.25, 0.25))]

LIB = r'''
import math

CLOTH, SKIN, HAIR = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)

def add(a, b): return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
def sub(a, b): return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
def mul(a, s): return [a[0] * s, a[1] * s, a[2] * s]
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
def norm(a):
    l = math.sqrt(dot(a, a)) or 1.0
    return [a[0] / l, a[1] / l, a[2] / l]
def lerp(a, b, t): return [a[k] + (b[k] - a[k]) * t for k in range(3)]

def newell(cs):
    n = [0.0, 0.0, 0.0]
    for i in range(len(cs)):
        a = cs[i]; b = cs[(i + 1) % len(cs)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n

def centroid(cs):
    return [sum(c[i] for c in cs) / len(cs) for i in range(3)]

class B:
    def __init__(self, geo):
        self.geo = geo
        self.shift = [0.0, 0.0, 0.0]
        geo.addAttrib(hou.attribType.Vertex, "uv", (0.0, 0.0, 0.0))
        geo.addAttrib(hou.attribType.Vertex, "Cd", (1.0, 1.0, 1.0))
        geo.addAttrib(hou.attribType.Prim, "shop_materialpath", "")
        pts = [geo.createPoint() for _ in range(3)]
        for p, c in zip(pts, [(0, 0, 0), (1, 0, 0), (0, 1, 0)]):
            p.setPosition(c)
        t = geo.createPolygon()
        for p in pts:
            t.addVertex(p)
        self.sign = 1.0 if t.normal()[2] > 0 else -1.0
        geo.deletePrims([t])
        geo.deletePoints(pts)

    def poly(self, pts, uvs, col):
        p = self.geo.createPolygon()
        for pt, uv in zip(pts, uvs):
            v = p.addVertex(pt)
            v.setAttribValue("uv", (uv[0], uv[1], 0.0))
            v.setAttribValue("Cd", col)
        p.setAttribValue("shop_materialpath", "/mat/crowd")

    def loft(self, rings, col, cap0=True, cap1=True):
        """Rings of equal length; col is one colour or one per band."""
        n = len(rings[0])
        P = []
        for r in rings:
            row = []
            for c in r:
                p = self.geo.createPoint()
                p.setPosition(add(c, self.shift))
                row.append(p)
            P.append(row)
        cs = [centroid(r) for r in rings]
        quads, votes = [], 0.0
        for k in range(len(rings) - 1):
            axis = centroid([cs[k], cs[k + 1]])
            for j in range(n):
                j2 = (j + 1) % n
                q = [(k, j), (k, j2), (k + 1, j2), (k + 1, j)]
                c = [rings[a][b] for a, b in q]
                votes += self.sign * dot(newell(c), sub(centroid(c), axis))
                uv = [(j / n, k / len(rings)), ((j + 1) / n, k / len(rings)),
                      ((j + 1) / n, (k + 1) / len(rings)), (j / n, (k + 1) / len(rings))]
                quads.append((q, uv, col[k] if isinstance(col, list) else col))
        for q, uv, cl in quads:
            if votes < 0:
                q = q[::-1]; uv = uv[::-1]
            self.poly([P[a][b] for a, b in q], uv, cl)
        for idx, nb, use in ((0, 1, cap0), (len(rings) - 1, len(rings) - 2, cap1)):
            if not use:
                continue
            cl = (col[0] if idx == 0 else col[-1]) if isinstance(col, list) else col
            order = list(range(n))
            if self.sign * dot(newell(rings[idx]), sub(cs[idx], cs[nb])) < 0:
                order = order[::-1]
            self.poly([P[idx][j] for j in order],
                      [(0.5 + 0.5 * math.cos(6.2832 * j / n), 0.5 + 0.5 * math.sin(6.2832 * j / n)) for j in order], cl)

def frame(t, side=(1.0, 0.0, 0.0)):
    """Orthonormal (x, z) perpendicular to t, x as close as possible to `side`."""
    t = norm(t)
    x = sub(side, mul(t, dot(side, t)))
    if dot(x, x) < 1e-6:
        x = sub([0.0, 0.0, 1.0], mul(t, t[2]))
    x = norm(x)
    return x, cross(x, t)

def ring(c, t, rx, rz, n, side=(1.0, 0.0, 0.0), phase=0.0):
    x, z = frame(t, side)
    return [add(c, add(mul(x, rx * math.cos(phase + 6.2832 * j / n)), mul(z, rz * math.sin(phase + 6.2832 * j / n))))
            for j in range(n)]

def seg(b, a, c, ra, rc, col, n=6, ext=0.5):
    """Tube from a to c, extended past both ends by ext * radius so joints overlap."""
    t = norm(sub(c, a))
    a2 = sub(a, mul(t, ra * ext)); c2 = add(c, mul(t, rc * ext))
    b.loft([ring(a2, t, ra, ra, n, phase=0.5), ring(c2, t, rc, rc, n, phase=0.5)], col)

def blob(b, c, rx, ry, rz, col, n=8, rings=5, up=(0.0, 1.0, 0.0), side=(1.0, 0.0, 0.0)):
    """Ellipsoid; ry along `up`."""
    up = norm(up)
    x, z = frame(up, side)
    rs = []
    for k in range(rings + 1):
        phi = math.pi * k / rings
        sr = max(math.sin(phi), 0.06)
        cc = add(c, mul(up, -ry * math.cos(phi)))
        rs.append([add(cc, add(mul(x, rx * sr * math.cos(6.2832 * j / n + 0.4)), mul(z, rz * sr * math.sin(6.2832 * j / n + 0.4))))
                   for j in range(n)])
    b.loft(rs, col)

def spine(b, pts, rx, rz, cols, n=8, front=None):
    """Torso loft through pts with elliptical rings; front[k] pushes the front (-Z side) out."""
    rings = []
    for k, p in enumerate(pts):
        t = sub(pts[min(k + 1, len(pts) - 1)], pts[max(k - 1, 0)])
        x, z = frame(t)
        r = []
        for j in range(n):
            a = 6.2832 * j / n + 0.3927
            ca, sa = math.cos(a), math.sin(a)
            dz = rz[k] + (front[k] if front and sa < 0 else 0.0)
            r.append(add(p, add(mul(x, rx[k] * ca), mul(z, dz * sa))))
        rings.append(r)
    b.loft(rings, cols)

# ---------------------------------------------------------------- skeleton

def base(seated=False):
    J = {}
    if not seated:
        J.update(pelvis=[0, 0.90, 0], waist=[0, 1.08, 0], chest=[0, 1.30, 0], shtop=[0, 1.42, 0], neck=[0, 1.49, 0],
                 head=[0, 1.575, -0.01])
        for s, sx in (("L", -1), ("R", 1)):
            J["hip" + s] = [sx * 0.09, 0.90, 0]
            J["knee" + s] = [sx * 0.10, 0.50, -0.01]
            J["ankle" + s] = [sx * 0.10, 0.09, 0.02]
            J["toe" + s] = [sx * 0.105, 0.035, -0.13]
    else:
        J.update(pelvis=[0, 0.55, 0.42], waist=[0, 0.68, 0.43], chest=[0, 0.90, 0.43], shtop=[0, 1.02, 0.42],
                 neck=[0, 1.09, 0.41], head=[0, 1.175, 0.40])
        for s, sx in (("L", -1), ("R", 1)):
            J["hip" + s] = [sx * 0.09, 0.53, 0.42]
            J["knee" + s] = [sx * 0.11, 0.53, 0.0]
            J["ankle" + s] = [sx * 0.11, 0.09, 0.03]
            J["toe" + s] = [sx * 0.115, 0.035, -0.12]
    sh = J["shtop"]
    for s, sx in (("L", -1), ("R", 1)):
        J["sh" + s] = [sx * 0.19, sh[1] - 0.01, sh[2]]
        if not seated:
            J["el" + s] = [sx * 0.23, 1.13, 0.03]
            J["wr" + s] = [sx * 0.25, 0.88, 0.0]
        else:
            J["el" + s] = [sx * 0.22, 0.76, 0.40]
            J["wr" + s] = [sx * 0.17, 0.60, 0.15]
    return J

def arm(J, s, el, wr):
    J["el" + s] = el; J["wr" + s] = wr

def pose(name):
    seated = name.startswith("sit") or name == "noble_sit"
    J = base(seated)
    extra = {}
    if name == "stand_cheer_one_arm":
        arm(J, "R", [0.25, 1.67, -0.03], [0.29, 1.93, -0.06])
        arm(J, "L", [-0.24, 1.14, -0.02], [-0.22, 0.90, -0.06])
    elif name in ("stand_cheer_both_arms", "stand_cheer_f"):
        arm(J, "R", [0.33, 1.64, -0.03], [0.42, 1.88, -0.06])
        arm(J, "L", [-0.33, 1.64, -0.03], [-0.42, 1.88, -0.06])
    elif name == "stand_fist_pump":
        arm(J, "R", [0.40, 1.36, -0.08], [0.42, 1.63, -0.12])
        J["head"] = [0.0, 1.57, -0.03]
    elif name == "stand_point":
        arm(J, "R", [0.22, 1.30, -0.26], [0.22, 1.18, -0.52])
        extra["finger"] = ("R", 0.09)
    elif name == "stand_thumbs":
        arm(J, "R", [0.22, 1.36, -0.29], [0.21, 1.36, -0.56])
        extra["thumb"] = "R"
    elif name == "sit_lean":
        J.update(waist=[0, 0.67, 0.36], chest=[0, 0.86, 0.23], shtop=[0, 0.95, 0.14], neck=[0, 1.01, 0.09],
                 head=[0, 1.08, 0.02])
        for s, sx in (("L", -1), ("R", 1)):
            J["sh" + s] = [sx * 0.19, 0.94, 0.15]
            arm(J, s, [sx * 0.13, 0.62, 0.02], [sx * 0.035, 0.74, -0.18])
        extra["clasp"] = True
    elif name == "noble_sit":
        arm(J, "R", [0.23, 0.78, 0.40], [0.20, 0.72, 0.15])
        arm(J, "L", [-0.21, 0.78, 0.44], [-0.10, 0.62, 0.22])
    return J, extra, seated

# ---------------------------------------------------------------- figure

def build(b, name):
    J, extra, seated = pose(name)
    female = name.endswith("_f")
    noble = name == "noble_sit"
    # origin at the feet centre
    fc = centroid([J["ankleL"], J["ankleR"], J["toeL"], J["toeR"]])
    b.shift = [-fc[0], 0.0, -fc[2]]

    sw = 0.165 if female else 0.19
    # torso: pelvis, waist, chest, shoulder line, neck
    pts = [J["pelvis"], J["waist"], J["chest"], J["shtop"], J["neck"]]
    pts = [lerp(pts[0], pts[1], -0.12)] + pts
    if female:
        rx = [0.15, 0.165, 0.125, 0.15, 0.15, 0.05]
        rz = [0.10, 0.105, 0.09, 0.095, 0.09, 0.05]
        front = [0, 0, 0, 0.035, 0.0, 0]
    else:
        rx = [0.14, 0.155, 0.145, 0.18, sw - 0.005, 0.06]
        rz = [0.095, 0.10, 0.10, 0.115, 0.095, 0.055]
        front = None
    spine(b, pts, rx, rz, [CLOTH, CLOTH, CLOTH, CLOTH, SKIN], 8, front)
    # head (slightly exaggerated) and hair
    h = J["head"]
    up = norm(sub(h, J["neck"]))
    blob(b, h, 0.10, 0.12, 0.11, SKIN, 8, 5, up=up)
    if name != "stand_point":
        blob(b, add(h, [0.0, 0.03, 0.025]), 0.107, 0.105 if not female else 0.11, 0.108 if not female else 0.115, HAIR, 8, 4, up=up)
    if female:
        blob(b, add(h, [0.0, -0.10, 0.07]), 0.10, 0.15, 0.06, HAIR, 6, 3, up=up)
    if name == "stand_point":  # hood instead of hair
        blob(b, add(h, [0.0, 0.015, 0.045]), 0.122, 0.14, 0.125, CLOTH, 8, 4, up=up)
    # arms
    for s in ("L", "R"):
        sh, el, wr = J["sh" + s], J["el" + s], J["wr" + s]
        sleeve = CLOTH if not noble else SKIN
        seg(b, sh, el, 0.056, 0.046, sleeve)
        seg(b, el, wr, 0.043, 0.035, SKIN)
        d = norm(sub(wr, el))
        hc = add(wr, mul(d, 0.06))
        blob(b, hc, 0.05, 0.07, 0.058, SKIN, 6, 3, up=d)
        if extra.get("finger", (None,))[0] == s:
            tip = add(hc, mul(d, 0.12))
            seg(b, add(hc, mul(d, 0.04)), tip, 0.014, 0.011, SKIN, 4)
        if extra.get("thumb") == s:
            seg(b, add(hc, [0.0, 0.02, 0.0]), add(hc, [0.0, 0.11, 0.0]), 0.017, 0.014, SKIN, 4)
    # legs
    for s in ("L", "R"):
        hip, kn, an, to = J["hip" + s], J["knee" + s], J["ankle" + s], J["toe" + s]
        if not (female or noble):
            seg(b, hip, kn, 0.075, 0.055, CLOTH if seated else SKIN)
        if not female:
            seg(b, kn, an, 0.052, 0.038, SKIN)
        else:
            seg(b, lerp(kn, an, 0.6), an, 0.042, 0.036, SKIN)
        heel = [an[0], 0.045, an[2] + 0.03]
        seg(b, heel, to, 0.045, 0.04, CLOTH, 4, 0.3)
    # clothing silhouettes
    w = J["waist"]
    if not seated and not female:  # knee-length tunic skirt
        b.loft([ring(add(w, [0, -0.06, 0]), [0, 1, 0], 0.155, 0.11, 8, phase=0.39),
                ring([w[0], 0.60, w[2] - 0.01], [0, 1, 0], 0.215, 0.16, 8, phase=0.39)], CLOTH, cap0=False)
    if female:  # long dress to the ankles
        b.loft([ring(add(w, [0, -0.04, 0]), [0, 1, 0], 0.15, 0.105, 8, phase=0.39),
                ring([w[0], 0.75, w[2] - 0.01], [0, 1, 0], 0.20, 0.15, 8, phase=0.39),
                ring([w[0], 0.11, w[2] - 0.02], [0, 1, 0], 0.25, 0.20, 8, phase=0.39)], CLOTH, cap0=False)
    if noble:  # toga: sash over the left shoulder, drape over the lap and down the shins
        seg(b, add(J["shL"], [0.03, 0.04, 0.0]), add(J["hipR"], [0.04, 0.08, -0.02]), 0.085, 0.08, CLOTH, 8, 0.6)
        lap = [[0.0, 0.54, 0.44], [0.0, 0.55, 0.20], [0.0, 0.53, -0.05], [0.0, 0.30, -0.08], [0.0, 0.12, -0.06]]
        rings = []
        for p, rx, rz in zip(lap, (0.19, 0.21, 0.22, 0.22, 0.23), (0.10, 0.09, 0.07, 0.06, 0.06)):
            rings.append(ring(p, [0, 0, -1] if p[1] > 0.5 else [0, -1, 0.2], rx, rz, 8, phase=0.39))
        b.loft(rings, CLOTH)
'''


def make_material():
    m = hou.node("/mat").createNode("principledshader::2.0", "crowd")
    m.parmTuple("basecolor").set((1, 1, 1))
    m.parm("rough").set(0.8)
    return m


def make_variant(name, x, tint):
    obj = hou.node("/obj").createNode("geo", name)
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild(B(hou.pwd().geometry()), %r)\n" % name)
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
    obj.setDisplayFlag(False)
    rop = hou.node("/out").createNode("gltf", "export_" + name)
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    rop.parm("outputfile").set("$HIP/../export/crowd/%s.glb" % name)
    rop.parm("exportmaterials").set(1)
    # preview copy: masks turned into an example tint, placed in the lineup
    pv = hou.node("/obj").createNode("geo", "pv_" + name)
    pv.parmTuple("t").set((x, 0, 0))
    om = pv.createNode("object_merge", "merge")
    om.parm("objpath1").set(out.path())
    wr = pv.createNode("attribwrangle", "tint")
    wr.setInput(0, om)
    wr.parm("class").set(3)  # vertices
    (c, s, h) = tint
    wr.parm("snippet").set("vector c = set%s; vector s = set%s; vector h = set%s;\n"
                           "v@Cd = v@Cd.x * c + v@Cd.y * s + v@Cd.z * h;\n" % (c, s, h))
    wr.setDisplayFlag(True)
    wr.setRenderFlag(True)
    pv.layoutChildren()
    return obj, out, rop, pv


def read_glb(path):
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
    nprims = 0
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            nprims += 1
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
    return tris, lo, hi, vol, [m["name"] for m in doc.get("materials", [])], attrs, len(doc["meshes"]), nprims


def render_lineup(pvs, xs):
    cam = hou.node("/obj").createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    for name, t, inten in (("key", (6, 6, -8), 1.2), ("fill", (-6, 2, -5), 0.4), ("rim", (0, 4, 8), 0.5)):
        l = hou.node("/obj").createNode("hlight", name)
        l.parmTuple("t").set(t)
        l.parm("light_intensity").set(inten)
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(0.4)
    bench = hou.node("/obj").createNode("geo", "bench")
    merge = bench.createNode("merge")
    for i, x in enumerate(xs):
        if VARIANTS[i].startswith("sit") or VARIANTS[i] == "noble_sit":
            bx = bench.createNode("box")
            bx.parmTuple("size").set((0.7, 0.45, 0.4))
            bx.parmTuple("t").set((x, 0.225, 0.62))
            merge.setNextInput(bx)
    merge.setDisplayFlag(True)
    merge.setRenderFlag(True)
    res = (2048, 640)
    rop = hou.node("/out").createNode("karma", "preview")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)
    cam.parm("resx").set(res[0]); cam.parm("resy").set(res[1])
    rop.parm("resolutionx").set(res[0]); rop.parm("resolutiony").set(res[1])
    center = hou.Vector3(((max(xs) + min(xs)) / 2, 1.0, 0))
    r = hou.hmath.buildRotate((-8, 195, 0), "xyz")
    cam.setWorldTransform(r * hou.hmath.buildTranslate(center + hou.Vector3(0, 0, 20) * r))
    cam.parm("orthowidth").set(max(xs) - min(xs) + 1.4)
    rop.parm("candobjects").set(" ".join(p.name() for p in pvs) + " bench")
    rop.parm("picture").set(os.path.join(PREVIEW, "crowd_lineup.png"))
    rop.render()


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    os.makedirs(EXPORT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    hou.hipFile.save(HIP)
    make_material()
    rops, pvs, xs = {}, [], []
    for i, name in enumerate(VARIANTS):
        x = i * 0.85
        obj, out, rop, pv = make_variant(name, x, TINTS[i])
        rops[name] = rop
        pvs.append(pv)
        xs.append(x)
    hou.hipFile.save(HIP)

    ok = True
    for name in VARIANTS:
        rops[name].render()
        tris, lo, hi, vol, mats, attrs, nmesh, nprim = read_glb(os.path.join(EXPORT, name + ".glb"))
        good = 300 <= tris <= 600 and vol > 0 and "COLOR_0" in attrs and mats == ["crowd"] and nmesh == 1
        ok = ok and good
        print("%-22s %s tris=%3d bbox=(%+.2f %+.2f %+.2f)..(%+.2f %+.2f %+.2f) mats=%s attrs=%s prims=%d" % (
            name, "OK  " if good else "FAIL", tris, *lo, *hi, mats, ",".join(sorted(attrs)), nprim))

    if "--no-preview" not in sys.argv:
        try:
            render_lineup(pvs, xs)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
