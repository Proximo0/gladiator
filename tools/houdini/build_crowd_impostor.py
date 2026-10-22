"""Build octahedral impostor atlases for every Sandblood crowd spectator variant.

Run:  hython scripts/build_crowd_impostor.py [--only=stand_idle,sit_idle] [--grid=8] [--res=1024] [--full] [--spp=6]

SideFX Labs (labs::impostor_texture) is not installed in this Houdini 22.0.466, so this writes the capture itself,
in ONE Karma render per pass: every atlas cell gets its own copy of the figure, rotated so that the cell's view
direction points at a single orthographic camera looking down -Z, and moved to the cell's spot on a grid. With an
orthographic camera that is pixel-identical to one camera per cell, but costs one render instead of grid*grid.

Layout (also written to <variant>_impostor.json for the game shader):
  * grid x grid cells, square atlas of res px. Cell (col i from the LEFT, row j from the BOTTOM of the image) has
    oct coordinate e = ((i + 0.5) / grid * 2 - 1, (j + 0.5) / grid * 2 - 1).
  * hemi-octahedral (default, upper hemisphere, for figures seen from level or above):
        p = ((e.x + e.y) / 2, (e.x - e.y) / 2);  d = normalize(p.x, 1 - |p.x| - |p.y|, p.y)
    full octahedral (--full):  d = (e.x, 1 - |e.x| - |e.y|, e.y); if d.y < 0: d.xz = (1 - |d.zx|) * sign(d.xz)
  * d is the world direction from the figure's pivot TOWARD the viewer (+Y up, figure faces -Z, so the front view
    d = (0, 0, -1) is a hemi corner cell; its index is "front_cell" in the json).
  * cell camera basis: forward = d, right = normalize(cross(+Y, d)) (fallback +X at the pole), up = cross(d, right).
  * each cell spans cell_size metres, centred on the pivot (bbox centre of the figure, in figure space).
Passes (PNG, RGBA, transparent background):
  <v>_impostor_color.png   unlit vertex colour: the region masks (red = clothing, green = skin, blue = hair)
  <v>_impostor_normal.png  view-space normal * 0.5 + 0.5 (x right, y up, z toward the viewer)
  <v>_impostor_depth.png   grey = 0.5 + z_view / cell_size (1 = nearest the viewer, 0.5 = pivot plane)
Output: export/crowd_impostor/, preview/crowd_impostor/<v>.png (colour + normal over grey, side by side).
"""
import json
import math
import os
import re
import sys
import time

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "crowd_impostor.hip")
EXPORT = os.path.join(ROOT, "export", "crowd_impostor")
PREVIEW = os.path.join(ROOT, "preview", "crowd_impostor")

_CROWD_SRC = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_crowd.py"), encoding="utf-8").read()
LIB = re.search(r"LIB = r'''(.*?)'''", _CROWD_SRC, re.S).group(1)
VARIANTS = eval(re.search(r"VARIANTS = (\[.*?\])", _CROWD_SRC, re.S).group(1))


def _arg(key, default):
    for a in sys.argv:
        if a.startswith("--%s=" % key):
            return a.split("=", 1)[1]
    return default


ONLY = _arg("only", "")
if ONLY:
    VARIANTS = [v for v in VARIANTS if v in ONLY.split(",")]
GRID = int(_arg("grid", 8))
RES = int(_arg("res", 1024))
SPP = int(_arg("spp", 6))
FULL = "--full" in sys.argv
PASSES = ("color", "normal", "depth")


def oct_dir(i, j):
    ex, ey = (i + 0.5) / GRID * 2 - 1, (j + 0.5) / GRID * 2 - 1
    if FULL:
        x, z = ex, ey
        y = 1 - abs(x) - abs(z)
        if y < 0:
            x, z = (1 - abs(ey)) * math.copysign(1, ex), (1 - abs(ex)) * math.copysign(1, ey)
    else:
        x, z = (ex + ey) / 2, (ex - ey) / 2
        y = 1 - abs(x) - abs(z)
    n = math.sqrt(x * x + y * y + z * z)
    return (x / n, y / n, z / n)


def basis(d):
    r = (d[2], 0.0, -d[0])  # cross(+Y, d)
    n = math.hypot(r[0], r[2])
    r = (1.0, 0.0, 0.0) if n < 1e-6 else (r[0] / n, 0.0, r[2] / n)
    u = (d[1] * r[2] - d[2] * r[1], d[2] * r[0] - d[0] * r[2], d[0] * r[1] - d[1] * r[0])
    return r, u


def make_figure(name):
    """The plain figure (normals, Cd as point/vertex attrib), used to measure the pivot and bounding sphere."""
    obj = hou.node("/obj").createNode("geo", "src_" + name)
    obj.setDisplayFlag(False)
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild(B(hou.pwd().geometry()), %r)\n" % name)
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, py)
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, div)
    nrm.parm("type").set(0)  # point normals: we rotate them per cell, and smooth shading suits the normal pass
    nrm.parm("cuspangle").set(50)
    return obj, nrm


def make_atlas(src_sop, pivot, cell):
    """One geo object holding all cell copies; a wrangle picks Cd for the pass from the 'impass' detail int."""
    obj = hou.node("/obj").createNode("geo", "atlas")
    obj.addSpareParmTuple(hou.IntParmTemplate("impass", "Impostor pass", 1))
    om = obj.createNode("object_merge", "src")
    om.parm("objpath1").set(src_sop.path())
    py = obj.createNode("python", "cells")
    code = [
        "import math",
        "GRID, FULL, CELL, PIV = %d, %r, %r, %r" % (GRID, FULL, cell, tuple(pivot)),
        "geo = hou.pwd().geometry()",
        "src = hou.pwd().inputs()[0].geometry()",
        "geo.clear()",
    ]
    py.parm("python").set("\n".join(code) + "\n" + _CELLS_BODY)
    py.setInput(0, om)
    wr = obj.createNode("attribwrangle", "pass_colour")
    wr.setInput(0, py)
    wr.parm("class").set(3)  # vertices
    wr.parm("snippet").set(
        'int ip = chi("../impass");\n'
        'if (ip == 1) { vector n = normalize(point(0, "N", @ptnum)); v@Cd = n * 0.5 + 0.5; }\n'
        'else if (ip == 2) { float z = point(0, "vz", @ptnum); v@Cd = set(1, 1, 1) * clamp(0.5 + z / %r, 0, 1); }\n'
        'if (ip > 0) v@Cd = pow(v@Cd, 2.2);  // pre-undo the sRGB encode of the PNG so data lands linear\n'
        % cell)
    mat = obj.createNode("attribwrangle", "material")
    mat.setInput(0, wr)
    mat.parm("class").set(1)
    mat.parm("snippet").set('s@shop_materialpath = "/mat/unlit";')
    out = obj.createNode("null", "OUT")
    out.setInput(0, mat)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    return obj, out


_CELLS_BODY = r'''
def oct_dir(i, j):
    ex, ey = (i + 0.5) / GRID * 2 - 1, (j + 0.5) / GRID * 2 - 1
    if FULL:
        x, z = ex, ey
        y = 1 - abs(x) - abs(z)
        if y < 0:
            x, z = (1 - abs(ey)) * math.copysign(1, ex), (1 - abs(ex)) * math.copysign(1, ey)
    else:
        x, z = (ex + ey) / 2, (ex - ey) / 2
        y = 1 - abs(x) - abs(z)
    n = math.sqrt(x * x + y * y + z * z)
    return (x / n, y / n, z / n)

def basis(d):
    r = (d[2], 0.0, -d[0])
    n = math.hypot(r[0], r[2])
    r = (1.0, 0.0, 0.0) if n < 1e-6 else (r[0] / n, 0.0, r[2] / n)
    u = (d[1] * r[2] - d[2] * r[1], d[2] * r[0] - d[0] * r[2], d[0] * r[1] - d[1] * r[0])
    return r, u

for j in range(GRID):
    for i in range(GRID):
        d = oct_dir(i, j)
        r, u = basis(d)
        # p * M (row vectors): columns of the 3x3 are right, up, forward -> view-space x, y, z.
        rot = hou.Matrix4(((r[0], u[0], d[0], 0), (r[1], u[1], d[1], 0), (r[2], u[2], d[2], 0), (0, 0, 0, 1)))
        m = hou.hmath.buildTranslate(-PIV[0], -PIV[1], -PIV[2]) * rot
        g = hou.Geometry()
        g.merge(src)
        g.transform(m)  # rotates P and the N attribute (typed as normal)
        g.addAttrib(hou.attribType.Point, 'vz', 0.0)
        g.setPointFloatAttribValues('vz', [p.position()[2] for p in g.points()])
        g.transform(hou.hmath.buildTranslate((i + 0.5 - GRID / 2.0) * CELL, (j + 0.5 - GRID / 2.0) * CELL, 0))
        geo.merge(g)
'''


def setup_scene():
    m = hou.node("/mat").createNode("principledshader::2.0", "unlit")
    m.parmTuple("basecolor").set((0, 0, 0))
    m.parm("basecolor_usePointColor").set(0)
    m.parm("reflect").set(0)
    m.parm("specularlevel").set(0) if m.parm("specularlevel") else None
    m.parm("emitint").set(1.0)
    m.parmTuple("emitcolor").set((1, 1, 1))
    m.parm("emitcolor_usePointColor").set(1)
    cam = hou.node("/obj").createNode("cam", "cam")
    cam.parm("projection").set("ortho")
    cam.parm("resx").set(RES)
    cam.parm("resy").set(RES)
    rop = hou.node("/out").createNode("karma", "render")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(SPP)
    rop.parm("resolutionx").set(RES)
    rop.parm("resolutiony").set(RES)
    for p in ("diffuselimit", "reflectionlimit", "refractionlimit"):
        rop.parm(p).set(0)
    rop.parm("pixelfilter").set("box")  # no blur between neighbouring cells
    return cam, rop


def main():
    t0 = time.time()
    hou.hipFile.clear(suppress_save_prompt=True)
    for d in (EXPORT, PREVIEW, os.path.dirname(HIP)):
        os.makedirs(d, exist_ok=True)
    hou.hipFile.save(HIP)
    cam, rop = setup_scene()
    results = []
    for name in VARIANTS:
        tv = time.time()
        src, sop = make_figure(name)
        g = sop.geometry()
        bb = g.boundingBox()
        piv = bb.center()
        rad = max((p.position() - piv).length() for p in g.points())
        cell = 2 * rad * 1.04  # 2% margin each side
        atlas, out = make_atlas(sop, piv, cell)
        span = GRID * cell
        cam.setWorldTransform(hou.hmath.buildTranslate(0, 0, rad * 4 + 10))
        cam.parm("orthowidth").set(span)
        rop.parm("candobjects").set(atlas.name())
        rop.parm("excludeobjects").set("") if rop.parm("excludeobjects") else None
        paths = {}
        for k, ps in enumerate(PASSES):
            atlas.parm("impass").set(k)
            path = os.path.join(EXPORT, "%s_impostor_%s.png" % (name, ps))
            rop.parm("picture").set(path)
            rop.render()
            paths[ps] = path
        # Which cell is the straight-on front view (d = (0, 0, -1))? Report the nearest.
        best = min(((i, j) for i in range(GRID) for j in range(GRID)),
                   key=lambda c: -sum(a * b for a, b in zip(oct_dir(*c), (0, 0, -1))))
        meta = {
            "variant": name, "mapping": "octahedral" if FULL else "hemi_octahedral", "grid": GRID,
            "resolution": RES, "cell_px": RES // GRID, "cell_size_m": cell, "pivot_m": list(piv),
            "bounding_radius_m": rad, "front_cell": list(best),
            "cell_order": "col i from left, row j from bottom of image; e = ((i+0.5)/grid*2-1, (j+0.5)/grid*2-1)",
            "view_basis": "forward d toward viewer, right = norm(cross(+Y, d)) (pole: +X), up = cross(d, right)",
            "passes": {ps: os.path.basename(p) for ps, p in paths.items()},
            "normal_encoding": "view space n*0.5+0.5 (x right, y up, z toward viewer)",
            "depth_encoding": "0.5 + z_view / cell_size_m (1 = nearest viewer)",
        }
        with open(os.path.join(EXPORT, "%s_impostor.json" % name), "w") as f:
            json.dump(meta, f, indent=1)
        stats = check(paths["color"], name)
        preview(paths, os.path.join(PREVIEW, name + ".png"))
        sizes = "/".join("%.0f" % (os.path.getsize(p) / 1024.0) for p in paths.values())
        print("%-22s %s cells_filled=%d/%d clipped=%d  KB(color/normal/depth)=%s  %.1fs" % (
            name, "OK  " if stats[0] == GRID * GRID and stats[1] == 0 else "FAIL", stats[0], GRID * GRID, stats[1],
            sizes, time.time() - tv), flush=True)
        results.append(stats)
        atlas.destroy()
        src.destroy()
    hou.hipFile.save(HIP)
    print("total %.1fs" % (time.time() - t0))


def check(path, name):
    """Count cells with figure pixels, and cells whose border ring carries alpha (= figure clipped)."""
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A").load()
    c = RES // GRID
    filled = clipped = 0
    for j in range(GRID):
        for i in range(GRID):
            x0, y0 = i * c, j * c
            ys = range(y0, y0 + c, 2)
            if any(a[x, y] > 8 for y in ys for x in range(x0 + 2, x0 + c - 2, 2)):
                filled += 1
            ring = [(x0, y) for y in range(y0, y0 + c)] + [(x0 + c - 1, y) for y in range(y0, y0 + c)] + \
                   [(x, y0) for x in range(x0, x0 + c)] + [(x, y0 + c - 1) for x in range(x0, x0 + c)]
            if any(a[p] > 8 for p in ring):
                clipped += 1
    return filled, clipped


def preview(paths, out):
    from PIL import Image
    ims = [Image.open(paths[k]).convert("RGBA") for k in ("color", "normal")]
    w, h = ims[0].size
    sheet = Image.new("RGBA", (w * 2, h), (70, 70, 70, 255))
    c = w // GRID
    for k, im in enumerate(ims):
        bg = Image.new("RGBA", (w, h), (70, 70, 70, 255))
        for n in range(1, GRID):  # faint cell grid
            for t in range(h):
                bg.putpixel((n * c, t), (90, 90, 90, 255))
                bg.putpixel((t, n * c), (90, 90, 90, 255))
        sheet.paste(Image.alpha_composite(bg, im), (k * w, 0))
    sheet.convert("RGB").save(out)


main()
