"""Build Sandblood Roman arena decor meshes procedurally and export them as .glb.

Run:  hython scripts/build_decor.py [--only=column,stump] [--no-preview]

Conventions: meters, Y up, origin = centre of the footprint on the ground, front faces +Z.
Reuses the geometry library (B, lathe, box, loft) from build_weapons.py so both scripts build alike.
Phone-friendly: every piece stays under 3000 triangles.
"""
import math
import os
import re
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "decor.hip")
EXPORT = os.path.join(ROOT, "export", "decor")
PREVIEW = os.path.join(ROOT, "preview", "decor")
MAX_TRIS = 3000

# The weapons script's embedded geometry library and glb reader, so the two never drift apart.
_WEAPONS_SRC = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_weapons.py"), encoding="utf-8").read()
LIB_BASE = re.search(r"LIB = r'''(.*?)'''", _WEAPONS_SRC, re.S).group(1)
_reader = re.search(r"(def read_glb\(path\):.*?)\n\n\n", _WEAPONS_SRC, re.S).group(1)
exec("import json, struct\n" + _reader)

# id: (top height, footprint half-width limit, lowest point: 0 = stands on the ground; the banner hangs on a wall)
SPECS = {
    "column": (4.2, 0.5, 0.0),
    "column_stump": (1.6, 0.5, 0.0),
    "brazier": (1.1, 0.4, 0.0),
    "statue_plinth": (2.9, 0.6, 0.0),
    "banner": (3.0, 0.8, 0.3),
}
ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
if ONLY:
    SPECS = {k: v for k, v in SPECS.items() if k in ONLY[0].split(",")}

# name: (base colour, roughness, metallic[, emission colour, emission intensity])
MATERIALS = {
    "marble": ((0.86, 0.83, 0.77), 0.55, 0.0),
    "stone": ((0.66, 0.6, 0.5), 0.85, 0.0),
    "bronze": ((0.5, 0.33, 0.17), 0.45, 1.0),
    "verdigris": ((0.34, 0.5, 0.42), 0.7, 0.3),
    "iron": ((0.28, 0.28, 0.30), 0.55, 1.0),
    "wood": ((0.42, 0.27, 0.14), 0.75, 0.0),
    "cloth": ((0.55, 0.06, 0.05), 0.9, 0.0),
    "trim": ((0.75, 0.58, 0.2), 0.5, 0.6),
    # Glowing coals: modest intensity so the preview on white doesn't blow out to white (see the laser sword).
    "ember": ((0.35, 0.08, 0.02), 0.9, 0.0, (1.0, 0.35, 0.05), 1.5),
}

LIB = LIB_BASE + r'''
def hashn(a, b):
    # Smooth deterministic weathering noise in about -1..1.
    return 0.6 * math.sin(3.1 * a + 7.3 * b) + 0.4 * math.sin(5.7 * a - 4.1 * b + 1.7)

def bar(b, p0, p1, r, mat, segs=6):
    # Prism of radius r from p0 to p1 (legs, struts, arms).
    d = [p1[i] - p0[i] for i in range(3)]
    L = math.sqrt(sum(x * x for x in d)) or 1.0
    d = [x / L for x in d]
    up = [0, 1, 0] if abs(d[1]) < 0.9 else [1, 0, 0]
    u = [d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0]]
    ul = math.sqrt(sum(x * x for x in u)); u = [x / ul for x in u]
    v = [d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0]]
    rings = []
    for p in (p0, p1):
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ring.append(tuple(p[i] + r * (math.cos(a) * u[i] + math.sin(a) * v[i]) for i in range(3)))
        rings.append(ring)
    b.loft(rings, mat)

def fluted(a, h):
    # 16 shallow flutes plus weathering chips.
    return 1.0 - 0.07 * abs(math.sin(8 * a)) + 0.012 * hashn(a, h * 3.0)

def column_base(b):
    box(b, (-0.45, 0.0, -0.45), (0.45, 0.22, 0.45), "stone")
    lathe(b, [(0.42, 0.22), (0.42, 0.28), (0.38, 0.32), (0.36, 0.36), (0.39, 0.4), (0.34, 0.44)], 24, "stone")

def build_column(b):
    column_base(b)
    hs = [0.44 + k * 0.3 for k in range(12)]  # shaft 0.44 .. 3.74
    prof = [(0.33 - 0.04 * (h - 0.44) / 3.3, h) for h in hs]
    lathe(b, prof, 48, "stone", rfn=fluted)
    # Capital: neck ring, echinus flare, square abacus.
    lathe(b, [(0.3, 3.74), (0.32, 3.77), (0.3, 3.8), (0.33, 3.86), (0.42, 3.94), (0.46, 3.98)], 24, "stone")
    box(b, (-0.5, 3.98, -0.5), (0.5, 4.2, 0.5), "stone")

def build_column_stump(b):
    column_base(b)
    segs = 48
    hs = [0.44, 0.74, 1.04]
    rings = [circ(0.33 - 0.012 * k, h, segs, rfn=fluted) for k, h in enumerate(hs)]
    # Broken top: a jagged ring whose height and radius wander, then a rough cap.
    top = []
    for j in range(segs):
        a = 2 * math.pi * j / segs
        h = 1.32 + 0.16 * math.sin(a + 0.6) + 0.07 * hashn(a * 2.0, 1.0)
        r = 0.31 * fluted(a, h) * (0.96 + 0.03 * hashn(a, 2.0))
        top.append((r * math.cos(a), h, r * math.sin(a)))
    rings.append(top)
    b.loft(rings, "stone")
    # A fallen chunk at the foot.
    lathe(b, [(0.0, 0.0), (0.22, 0.0), (0.22, 0.18), (0.0, 0.2)], 12, "stone", axis="z", c=(0.66, 0.22, 0.12))

def build_brazier(b):
    # Tripod of iron legs, a bronze bowl on top, glowing coals in it.
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        foot = (0.32 * math.cos(a), 0.0, 0.32 * math.sin(a))
        top = (0.16 * math.cos(a), 0.78, 0.16 * math.sin(a))
        bar(b, foot, top, 0.022, "iron")
        lathe(b, [(0.0, 0.0), (0.045, 0.0), (0.045, 0.025), (0.0, 0.03)], 8, "iron", c=foot)
    lathe(b, [(0.02, 0.36), (0.19, 0.36), (0.19, 0.38), (0.02, 0.38)], 16, "iron")  # leg ring
    lathe(b, [(0.06, 0.74), (0.12, 0.76), (0.24, 0.84), (0.32, 0.95), (0.35, 1.04), (0.37, 1.06),
              (0.37, 1.08), (0.33, 1.08), (0.3, 1.0), (0.2, 0.9), (0.06, 0.86)], 28, ["bronze"] * 4 + ["verdigris"] * 6)
    coal = lambda a, h: 1.0 + 0.12 * max(0.0, hashn(a * 3.0, h * 40.0))
    lathe(b, [(0.29, 0.98), (0.24, 1.02), (0.14, 1.05), (0.02, 1.06)], 18, "ember", rfn=coal)

def build_statue_plinth(b):
    # Marble plinth with mouldings, then a simple bronze gladiator: gladius raised, round shield.
    box(b, (-0.55, 0.0, -0.55), (0.55, 0.12, 0.55), "marble")
    box(b, (-0.48, 0.12, -0.48), (0.48, 1.0, 0.48), "marble")
    box(b, (-0.53, 1.0, -0.53), (0.53, 1.1, 0.53), "marble")
    m = "bronze"
    box(b, (-0.3, 1.1, -0.25), (0.3, 1.16, 0.25), m)  # base slab
    # Legs (stance), hips, torso, head with crested helmet.
    bar(b, (-0.11, 1.16, 0.08), (-0.1, 1.62, 0.0), 0.055, m)
    bar(b, (0.12, 1.16, -0.12), (0.1, 1.62, 0.0), 0.055, m)
    lathe(b, [(0.1, 1.6), (0.15, 1.64), (0.16, 1.74)], 10, m, sz=0.7)
    lathe(b, [(0.16, 1.74), (0.15, 1.9), (0.19, 2.06), (0.2, 2.12), (0.12, 2.16)], 12, m, sz=0.65)
    lathe(b, [(0.05, 2.16), (0.055, 2.22)], 8, m)
    lathe(b, sphere_prof(0.1, 2.31, 8), 12, m)
    box(b, (-0.012, 2.36, -0.13), (0.012, 2.46, 0.11), "trim")  # crest
    # Sword arm raised high, gladius pointing up and forward.
    bar(b, (0.19, 2.08, 0.0), (0.3, 2.3, 0.05), 0.045, m)
    bar(b, (0.3, 2.3, 0.05), (0.33, 2.52, 0.12), 0.04, m)
    bar(b, (0.33, 2.52, 0.12), (0.34, 2.62, 0.14), 0.012, "trim", segs=4)
    bar(b, (0.34, 2.62, 0.14), (0.37, 2.86, 0.2), 0.02, "iron", segs=4)
    # Shield arm forward, round shield on it.
    bar(b, (-0.19, 2.08, 0.0), (-0.24, 1.88, 0.12), 0.045, m)
    lathe(b, [(0.0, 0.0), (0.2, 0.005), (0.24, 0.02), (0.24, 0.04), (0.2, 0.05), (0.0, 0.055)], 18, "verdigris",
          axis="z", c=(-0.27, 1.9, 0.16))

def build_banner(b):
    # Swallow-tailed cloth slab hanging from a wooden pole with bronze finials. Front faces +Z.
    W, H, T = 0.6, 2.6, 0.006
    top = 2.9
    lathe(b, [(0.03, -0.75), (0.03, 0.75)], 10, "wood", axis="x", c=(0, top + 0.03, 0))
    for sx in (-1, 1):
        lathe(b, sphere_prof(0.05, sx * 0.8, 6), 10, "trim", axis="x", c=(0, top + 0.03, 0))
    nx, ny = 10, 12
    xs = [-W + 2 * W * i / nx for i in range(nx + 1)]
    rings = []
    for k in range(ny + 1):
        v = k / ny
        front, back = [], []
        for x in xs:
            length = H - 0.45 * (1.0 - abs(x) / W)  # the centre is cut up into a V: swallow tail
            y = top - v * length
            z = 0.05 * math.sin(3.0 * x + 2.0 * v) * v + 0.03 * v * v
            front.append((x, y, z + T))
            back.append((x, y, z - T))
        rings.append(front + back[::-1])
    b.loft(rings, ["trim"] + ["cloth"] * (ny - 2) + ["trim"])
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
    obj = hou.node("/obj").createNode("geo", pid)
    obj.parmTuple("t").set((x_offset, 0, 0))
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild_%s(B(hou.pwd().geometry()))\n" % pid)
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, py)
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, div)
    nrm.parm("cuspangle").set(40)
    out = obj.createNode("null", "OUT")
    out.setInput(0, nrm)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    rop = hou.node("/out").createNode("gltf", "export_" + pid)
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    rop.parm("outputfile").set("$HIP/../export/decor/%s.glb" % pid)
    rop.parm("exportmaterials").set(1)
    return obj, out, rop


def render_previews(objs):
    cam = hou.node("/obj").createNode("cam", "preview_cam")
    cam.parm("projection").set("ortho")
    key = hou.node("/obj").createNode("hlight", "key")
    key.parmTuple("t").set((4, 8, 8))
    fill = hou.node("/obj").createNode("hlight", "fill")
    fill.parmTuple("t").set((-6, 3, 4))
    fill.parm("light_intensity").set(0.5)
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(0.6)
    rop = hou.node("/out").createNode("karma", "preview")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)
    for pid, (obj, out) in objs.items():
        bb = out.geometry().boundingBox()
        c = bb.center() + hou.Vector3(obj.parmTuple("t").eval())
        size = bb.sizevec()
        r = hou.hmath.buildRotate((-12, 30, 0), "xyz")
        cam.setWorldTransform(r * hou.hmath.buildTranslate(hou.Vector3(c) + hou.Vector3(0, 0, 20) * r))
        cam.parm("resx").set(512); cam.parm("resy").set(512)
        rop.parm("resolutionx").set(512); rop.parm("resolutiony").set(512)
        cam.parm("orthowidth").set(max(size[0], size[1], size[2]) * 1.15)
        rop.parm("candobjects").set(obj.name())
        rop.parm("picture").set(os.path.join(PREVIEW, pid + ".png"))
        rop.render()


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    for d in (EXPORT, PREVIEW, os.path.dirname(HIP)):
        os.makedirs(d, exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    objs, rops = {}, {}
    x = 0.0
    for pid in SPECS:
        obj, out, rop = make_piece(pid, x)
        objs[pid] = (obj, out)
        rops[pid] = rop
        x += max(out.geometry().boundingBox().sizevec()[0], 0.5) + 1.0
    hou.hipFile.save(HIP)

    ok = True
    for pid, (height, half, floor) in SPECS.items():
        rops[pid].render()
        path = os.path.join(EXPORT, pid + ".glb")
        tris, lo, hi, vol, mnames = read_glb(path)
        good = abs(lo[1] - floor) <= 0.01 and hi[1] <= height + 0.01 and hi[1] >= height * 0.8
        good = good and max(abs(lo[0]), abs(hi[0]), abs(lo[2]), abs(hi[2])) <= half + 0.4
        good = good and tris <= MAX_TRIS and vol > 0
        ok = ok and good
        print("%-14s %s tris=%5d size=%6.1f KB bbox=(%.2f %.2f %.2f)..(%.2f %.2f %.2f) vol=%.4f mats=%s" % (
            pid, "OK  " if good else "FAIL", tris, os.path.getsize(path) / 1024.0, *lo, *hi, vol, ",".join(mnames)))

    if "--no-preview" not in sys.argv:
        try:
            render_previews(objs)
        except hou.Error as e:
            print("preview render failed:", e)
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
