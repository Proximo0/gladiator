"""Build a 4-level LOD set of every Sandblood crowd spectator variant and export them as .glb.

Run:  hython scripts/build_crowd_lod.py [--only=stand_idle,sit_idle] [--no-preview]

LOD0 = the build_crowd.py mesh as is, LOD1 = 50% and LOD2 = 20% of its triangles (PolyReduce, keeping the vertex-
colour region masks: red = clothing, green = skin, blue = hair), LOD3 = an impostor card: one quad facing -Z with the
LOD0 figure rendered front-on into a PNG (same RGB masks, transparent background), origin at the feet like the rest.
Output: export/crowd_lod/<variant>_lod<n>.glb, export/crowd_lod/<variant>_impostor.png, preview/crowd_lod/<variant>.png.
"""
import os
import re
import sys

import hou

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIP = os.path.join(ROOT, "hip", "crowd_lod.hip")
EXPORT = os.path.join(ROOT, "export", "crowd_lod")
PREVIEW = os.path.join(ROOT, "preview", "crowd_lod")
IMPOSTOR_RES = 128

_CROWD_SRC = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_crowd.py"), encoding="utf-8").read()
LIB = re.search(r"LIB = r'''(.*?)'''", _CROWD_SRC, re.S).group(1)
VARIANTS = eval(re.search(r"VARIANTS = (\[.*?\])", _CROWD_SRC, re.S).group(1))
_reader = re.search(r"(def read_glb\(path\):.*?)\n\n\n", _CROWD_SRC, re.S).group(1)
exec("import json, struct\n" + _reader)
ONLY = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
if ONLY:
    VARIANTS = [v for v in VARIANTS if v in ONLY[0].split(",")]
# LOD2 is 30%, not 20%: at 20% PolyReduce thins the limbs to slivers (seen in the lineup preview).
LEVELS = [(0, 100.0), (1, 50.0), (2, 30.0)]


def make_materials():
    m = hou.node("/mat").createNode("principledshader::2.0", "crowd")
    m.parmTuple("basecolor").set((1, 1, 1))
    m.parm("rough").set(0.8)
    card = hou.node("/mat").createNode("principledshader::2.0", "crowd_card")
    card.parmTuple("basecolor").set((1, 1, 1))
    card.parm("rough").set(1.0)
    return card


def make_variant(name, x):
    obj = hou.node("/obj").createNode("geo", name)
    obj.parmTuple("t").set((x, 0, 0))
    py = obj.createNode("python", "build")
    py.parm("python").set(LIB + "\nbuild(B(hou.pwd().geometry()), %r)\n" % name)
    div = obj.createNode("divide", "triangulate")
    div.setInput(0, py)
    outs = {}
    for lod, pct in LEVELS:
        src = div
        if pct < 100.0:
            # Reduce each body piece (limb, head, torso shell) on its own: one global pass at 20% spends the budget on
            # the big torso and collapses thin limbs to slivers or deletes them.
            conn = obj.createNode("connectivity", "pieces_%d" % lod)
            conn.setInput(0, div)
            conn.parm("connecttype").set(1)  # primitives
            conn.parm("attribname").set("piece")
            begin = obj.createNode("block_begin", "each_piece_%d" % lod)
            begin.setInput(0, conn)
            begin.parm("method").set(1)  # extract piece
            red = obj.createNode("polyreduce::2.0", "reduce_%d" % lod)
            red.setInput(0, begin)
            red.parm("percentage").set(pct)
            red.parm("vattribseamweight").set(0.0)  # uv seams are per-ring: weighting them starves the limbs
            red.parm("equalizelengths").set(0.5)
            end = obj.createNode("block_end", "each_piece_end_%d" % lod)
            end.setInput(0, red)
            end.parm("itermethod").set(1)  # by pieces
            end.parm("method").set(1)  # merge each iteration
            end.parm("class").set(0)  # primitives
            end.parm("useattrib").set(1)
            end.parm("attrib").set("piece")
            end.parm("blockpath").set(end.relativePathTo(begin))
            end.setInput(1, conn)  # the piece template is the second input
            begin.parm("blockpath").set(begin.relativePathTo(end))
            src = end
        nrm = obj.createNode("normal", "normals_%d" % lod)
        nrm.setInput(0, src)
        nrm.parm("cuspangle").set(50)
        mat = obj.createNode("attribwrangle", "material_%d" % lod)
        mat.setInput(0, nrm)
        mat.parm("class").set(1)  # primitives
        mat.parm("snippet").set('s@shop_materialpath = "/mat/crowd";')
        out = obj.createNode("null", "OUT_%d" % lod)
        out.setInput(0, mat)
        outs[lod] = out
    outs[0].setDisplayFlag(True)
    outs[0].setRenderFlag(True)
    obj.layoutChildren()
    return obj, outs


def export(sop, path):
    rop = hou.node("/out").createNode("gltf")
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(sop.path())
    rop.parm("outputfile").set(path)
    rop.parm("exportmaterials").set(1)
    rop.render()
    rop.destroy()


def render_rig():
    cam = hou.node("/obj").createNode("cam", "cam")
    cam.parm("projection").set("ortho")
    # Flat, even light so the region masks stay close to pure red/green/blue in the impostor texture.
    hou.node("/obj").createNode("envlight", "sky").parm("light_intensity").set(1.0)
    rop = hou.node("/out").createNode("karma", "render")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("samplesperpixel").set(16)
    return cam, rop


def shoot(cam, rop, objs, center, width, height, res, rot, path):
    cam.parm("resx").set(res[0]); cam.parm("resy").set(res[1])
    rop.parm("resolutionx").set(res[0]); rop.parm("resolutiony").set(res[1])
    r = hou.hmath.buildRotate(rot, "xyz")
    cam.setWorldTransform(r * hou.hmath.buildTranslate(hou.Vector3(center) + hou.Vector3(0, 0, 20) * r))
    cam.parm("orthowidth").set(max(width, height * res[0] / res[1]))
    rop.parm("candobjects").set(" ".join(o.name() for o in objs))
    rop.parm("picture").set(path)
    rop.render()


def make_card(name, lo, hi, tex):
    """One quad facing -Z spanning the figure's front silhouette, UVs 0..1, textured with the impostor PNG."""
    m = hou.node("/mat").createNode("principledshader::2.0", "card_" + name)
    m.parmTuple("basecolor").set((1, 1, 1))
    m.parm("rough").set(1.0)
    m.parm("basecolor_useTexture").set(1)
    m.parm("basecolor_texture").set(tex)
    obj = hou.node("/obj").createNode("geo", name + "_card")
    obj.setDisplayFlag(False)
    py = obj.createNode("python", "quad")
    py.parm("python").set(
        "geo = hou.pwd().geometry()\n"
        "geo.addAttrib(hou.attribType.Vertex, 'uv', (0.0, 0.0, 0.0))\n"
        "geo.addAttrib(hou.attribType.Prim, 'shop_materialpath', '')\n"
        "x0, x1, y0, y1, z = %r, %r, %r, %r, %r\n"
        "pts = []\n"
        "for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):\n"
        "    p = geo.createPoint(); p.setPosition((x, y, z)); pts.append(p)\n"
        "uvs = [(1, 0), (0, 0), (0, 1), (1, 1)]  # seen from -Z, +X is on the viewer's left\n"
        "for tri in ((0, 1, 2), (0, 2, 3)):\n"
        "    poly = geo.createPolygon()\n"
        "    for i in tri:\n"
        "        v = poly.addVertex(pts[i]); v.setAttribValue('uv', (uvs[i][0], uvs[i][1], 0.0))\n"
        "    poly.setAttribValue('shop_materialpath', %r)\n"
        "    if poly.normal()[2] > 0: poly.reverse()\n" % (lo[0], hi[0], 0.0, hi[1], 0.0, m.path()))
    nrm = obj.createNode("normal", "normals")
    nrm.setInput(0, py)
    out = obj.createNode("null", "OUT")
    out.setInput(0, nrm)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    return obj, out


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    for d in (EXPORT, PREVIEW, os.path.dirname(HIP)):
        os.makedirs(d, exist_ok=True)
    hou.hipFile.save(HIP)
    make_materials()
    cam, rop = render_rig()
    ok = True
    for name in VARIANTS:
        obj, outs = make_variant(name, 0.0)
        counts = []
        for lod, _ in LEVELS:
            path = os.path.join(EXPORT, "%s_lod%d.glb" % (name, lod))
            export(outs[lod], path)
            tris, lo, hi, vol, mats, attrs, _, _ = read_glb(path)
            good = vol > 0 and "COLOR_0" in attrs and mats == ["crowd"]
            ok = ok and good
            counts.append((tris, os.path.getsize(path)))
            if lod == 0:
                lo0, hi0 = lo, hi
        # Impostor: LOD0 seen front-on (from -Z), framed to the figure's bbox, square texture.
        tex = os.path.join(EXPORT, "%s_impostor.png" % name)
        w, h = hi0[0] - lo0[0], hi0[1]
        side = max(w, h)
        lo_c = ((lo0[0] + hi0[0]) / 2 - side / 2, 0.0)
        hi_c = ((lo0[0] + hi0[0]) / 2 + side / 2, side)
        shoot(cam, rop, [obj], ((lo0[0] + hi0[0]) / 2, side / 2, 0), side, side, (IMPOSTOR_RES, IMPOSTOR_RES),
              (0, 180, 0), tex)
        cobj, cout = make_card(name, lo_c, hi_c, tex)
        cpath = os.path.join(EXPORT, "%s_lod3.glb" % name)
        export(cout, cpath)
        ctris = read_glb(cpath)[0]
        ok = ok and ctris == 2
        counts.append((ctris, os.path.getsize(cpath) + os.path.getsize(tex)))
        print("%-22s %s lod0=%d lod1=%d lod2=%d lod3(card)=%d tris; KB %s" % (
            name, "OK  " if ok else "FAIL", *[c[0] for c in counts], "/".join("%.1f" % (c[1] / 1024.0) for c in counts)))
        if "--no-preview" not in sys.argv:
            # Side by side: LOD0..2 copies spread along X, then the card.
            shown = []
            for lod in (0, 1, 2):
                g = hou.node("/obj").createNode("geo", "%s_pv%d" % (name, lod))
                g.parmTuple("t").set((lod * 0.9, 0, 0))
                om = g.createNode("object_merge")
                om.parm("objpath1").set(outs[lod].path())
                om.setDisplayFlag(True); om.setRenderFlag(True)
                shown.append(g)
            cobj.parmTuple("t").set((2 * 0.9 + 0.5 + (hi_c[0] - lo_c[0]) / 2, 0, 0))  # clear of LOD2
            cobj.setDisplayFlag(True)
            shown.append(cobj)
            obj.setDisplayFlag(False)
            span = 2 * 0.9 + 0.5 + (hi_c[0] - lo_c[0])
            shoot(cam, rop, shown, (span / 2 - 0.3, 0.95, 0), span + 0.8, 2.0, (1280, 560), (-5, 180, 0),
                  os.path.join(PREVIEW, name + ".png"))
            for g in shown[:3]:
                g.destroy()
        obj.destroy()
        cobj.destroy()
    hou.hipFile.save(HIP)
    print("ALL OK" if ok else "SOME CHECKS FAILED")


main()
