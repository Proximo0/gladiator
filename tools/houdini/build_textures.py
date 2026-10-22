"""Give the flat-coloured Sandblood props tileable procedural textures and re-export textured .glb copies.

Run:  hython scripts/build_textures.py [--only=column,axe or a group name] [--no-preview] [--skip-tex] [--embed=png]

1. Textures: scripts/tex_gen.py writes seamless 512x512 maps per material family to export/textures/
   (<family>_albedo.png sRGB, <family>_orm.png linear R=occlusion G=roughness B=metal, <family>_normal.png),
   plus JPEG twins in export/textures/embed/ (what goes inside the glbs by default; --embed=png ships the PNGs).
2. Re-export: each untextured glb is loaded with a File SOP and unpacked. Geometry, normals and triangles stay as
   they are; a Python SOP only rescales the loft UVs per part so texel density is roughly even (TILES_PER_M), keeping
   wrap-around seams on whole tiles. Every material gets a Principled shader with the textures (the glb's own colour /
   roughness / metalness become baseColorFactor / roughnessFactor / metallicFactor over the shared maps), opaque blend.
   The glTF ROP writes export/<group>_tex/<name>.glb; a pure-Python pass then swaps the ROP's re-encoded images for
   our own files, de-duplicates them (the ROP embeds a copy per material and per slot), adds a repeat sampler, and
   copies over named empties (weapon-rack slots) from the source.
3. Checks: same triangle count as the source, images/textures present, image bytes per glb, alphaMode, then a
   Karma CPU preview per model in preview/<group>_tex/ and a contact sheet per group (_sheet.png).
"""
import json
import math
import os
import struct
import sys
import time

import hou

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPTS)
sys.path.insert(0, SCRIPTS)
import tex_gen  # noqa: E402

TEX = os.path.join(ROOT, "export", "textures")
EMBED_DIR = os.path.join(TEX, "embed")
GROUPS = {
    "decor": None,
    "dressing": None,
    "armor": None,
    "gore": None,
    # laser_sword is skipped: its blade is emissive and should stay a clean glow.
    "weapons": ["rake", "bat", "club", "gladius", "longsword", "axe", "spear", "shield_round", "dai_katana",
                "machete", "sledgehammer", "mace", "falchion", "warhammer", "halberd"],
}
TILES_PER_M = 0.75  # 512 px tiles -> 384 texels per metre target (woven cloth x2, DMUL in UV_SOP)
EMBED = "png" if "--embed=png" in sys.argv else "jpeg"
ONLY = [a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")]
ONLY = ONLY[0] if ONLY else None
PREVIEW_RES = 384
PREVIEW_SPP = 8

# ------------------------------------------------------------------------------------------------ glb I/O

COMP = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}


def glb_read(path):
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    binc = b""
    off = 20 + jlen
    if off < len(data):
        blen = struct.unpack_from("<I", data, off)[0]
        binc = data[off + 8:off + 8 + blen]
    return doc, binc


def glb_write(path, doc, binc):
    j = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    j += b" " * ((4 - len(j) % 4) % 4)
    binc += b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(j) + 8 + len(binc)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<I4s", len(j), b"JSON") + j)
        f.write(struct.pack("<I4s", len(binc), b"BIN\0") + binc)


def glb_tris(doc):
    n = 0
    for m in doc.get("meshes", []):
        for p in m["primitives"]:
            if "indices" in p:
                n += doc["accessors"][p["indices"]]["count"] // 3
            else:
                n += doc["accessors"][p["attributes"]["POSITION"]]["count"] // 3
    return n


def src_materials(doc):
    out = {}
    for m in doc.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        ext = m.get("extensions", {}).get("KHR_materials_emissive_strength", {})
        out[m["name"]] = dict(
            color=tuple(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3]),
            rough=pbr.get("roughnessFactor", 1.0),
            metal=pbr.get("metallicFactor", 1.0),
            emit=tuple(m.get("emissiveFactor", [0, 0, 0])),
            emit_int=ext.get("emissiveStrength", 1.0 if "emissiveFactor" in m else 0.0),
        )
    return out


def postprocess(path, src_doc, tex_files):
    """Swap embedded images for our files, de-dupe, add sampler, copy empties, check alphaMode."""
    doc, binc = glb_read(path)
    views = doc["bufferViews"]
    old_img_views = {im["bufferView"] for im in doc.get("images", [])}
    # Which of our files each material slot should carry.
    slot_file = {}
    for m in doc.get("materials", []):
        files = tex_files.get(m["name"])
        if not files:
            continue
        pbr = m.get("pbrMetallicRoughness", {})
        for key, holder, kind in (("baseColorTexture", pbr, "albedo"), ("metallicRoughnessTexture", pbr, "orm"),
                                  ("occlusionTexture", m, "orm"), ("normalTexture", m, "normal")):
            if key in holder and files.get(kind):
                slot_file[(m["name"], key)] = files[kind]
            elif key in holder:
                del holder[key]
    # Rebuild the binary chunk without the old image views.
    new_views, remap, chunks, pos = [], {}, [], 0
    for i, v in enumerate(views):
        if i in old_img_views:
            continue
        piece = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        pad = (4 - pos % 4) % 4
        chunks.append(b"\0" * pad)
        pos += pad
        nv = dict(v)
        nv["byteOffset"] = pos
        remap[i] = len(new_views)
        new_views.append(nv)
        chunks.append(piece)
        pos += len(piece)
    for a in doc.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    images, textures, img_index = [], [], {}
    for fpath in sorted(set(slot_file.values())):
        with open(fpath, "rb") as f:
            payload = f.read()
        pad = (4 - pos % 4) % 4
        chunks.append(b"\0" * pad)
        pos += pad
        new_views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(payload)})
        chunks.append(payload)
        pos += len(payload)
        img_index[fpath] = len(images)
        images.append({"name": os.path.splitext(os.path.basename(fpath))[0], "bufferView": len(new_views) - 1,
                       "mimeType": "image/jpeg" if fpath.lower().endswith(".jpg") else "image/png"})
        textures.append({"source": len(images) - 1, "sampler": 0})
    for m in doc.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for key, holder in (("baseColorTexture", pbr), ("metallicRoughnessTexture", pbr),
                            ("occlusionTexture", m), ("normalTexture", m)):
            if (m["name"], key) in slot_file:
                holder[key]["index"] = img_index[slot_file[(m["name"], key)]]
    binc = b"".join(chunks)
    doc["bufferViews"] = new_views
    doc["buffers"] = [{"byteLength": len(binc)}]
    for k in ("images", "textures", "samplers"):
        doc.pop(k, None)
    if images:
        doc["images"] = images
        doc["textures"] = textures
        doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    # Keep the source's mesh-node name and its named empties (weapon_rack slot_1..6).
    src_nodes = src_doc.get("nodes", [])
    src_mesh = next((n for n in src_nodes if "mesh" in n), None)
    out_mesh = next((n for n in doc.get("nodes", []) if "mesh" in n), None)
    if src_mesh and out_mesh:
        out_mesh["name"] = src_mesh["name"]
        if "matrix" in src_mesh and src_mesh["matrix"] != [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]:
            out_mesh["matrix"] = src_mesh["matrix"]
        # Named empties: the mesh node's children, plus orphan empties (the source weapon_rack's slot_1..6 are
        # listed in "nodes" but no scene or parent references them); both become children of the mesh node.
        in_scene = {i for s in src_doc.get("scenes", []) for i in s.get("nodes", [])}
        parented = {k for n in src_nodes for k in n.get("children", [])}
        orphans = [i for i, n in enumerate(src_nodes) if i not in in_scene and i not in parented and "mesh" not in n]
        kids = []
        for ci in list(src_mesh.get("children", [])) + orphans:
            c = src_nodes[ci]
            if "mesh" in c or "children" in c:
                continue
            nn = {k: c[k] for k in ("name", "matrix", "translation", "rotation", "scale", "extras") if k in c}
            doc["nodes"].append(nn)
            kids.append(len(doc["nodes"]) - 1)
        if kids:
            out_mesh["children"] = out_mesh.get("children", []) + kids
    glb_write(path, doc, binc)
    return doc


# ------------------------------------------------------------------------------------------------ Houdini side

UV_SOP = r'''
import hou, math
import numpy as np
geo = hou.pwd().geometry()
D = %(D)r
GRAIN = ("wood", "wood_wet")
DMUL = %(DMUL)r
# Unpacking the source's empty nodes leaves stray points: drop points no polygon uses.
geo.deletePoints([p for p in geo.points() if not p.prims()])
P = np.array(geo.pointFloatAttribValues("P")).reshape(-1, 3)
UV = np.array(geo.pointFloatAttribValues("uv")).reshape(-1, 3)
prims = geo.prims()
mats = geo.primStringAttribValues("gltf_material_name")
tri = np.array([[v.point().number() for v in p.vertices()] for p in prims])
npt = len(P)
parent = list(range(npt))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a
def union(a, b):
    a, b = find(a), find(b)
    if a != b:
        parent[b] = a
ptmat = [""] * npt
for t, m in zip(tri, mats):
    for p in t:
        ptmat[p] = m
    union(t[0], t[1]); union(t[0], t[2])
key = [(ptmat[i],) + tuple(np.round(P[i] / 1e-5).astype(np.int64)) for i in range(npt)]
first = {}
for i, k in enumerate(key):
    if k in first:
        union(first[k], i)
    else:
        first[k] = i
root = np.array([find(i) for i in range(npt)])
# Loft end caps carry a disc mapping (uv on the circle |uv - 0.5| = 0.5, see B.loft), which squashes boxes and
# planks into diamonds. They are flat, so they get a planar projection below at the part's own density.
onc = np.abs(np.hypot(UV[:, 0] - 0.5, UV[:, 1] - 0.5) - 0.5) < 1e-4
cap = onc[tri].all(axis=1)
capPt = np.zeros(npt, bool)
capPt[tri[cap].reshape(-1)] = True
# Per-triangle UV Jacobian: metres per UV unit along u and along v.
a, b, c = P[tri[:, 0]], P[tri[:, 1]], P[tri[:, 2]]
e1, e2 = b - a, c - a
d1 = UV[tri[:, 1], :2] - UV[tri[:, 0], :2]
d2 = UV[tri[:, 2], :2] - UV[tri[:, 0], :2]
det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
ok = (np.abs(det) > 1e-12) & ~cap
sdet = np.where(np.abs(det) > 1e-12, det, 1.0)[:, None]
dpdu = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / sdet
dpdv = (-e1 * d2[:, 0:1] + e2 * d1[:, 0:1]) / sdet
Lu_t = np.linalg.norm(dpdu, axis=1)
Lv_t = np.linalg.norm(dpdv, axis=1)
cr = np.cross(e1, e2)
area = 0.5 * np.linalg.norm(cr, axis=1)
troot = root[tri[:, 0]]
def wmedian(x, w):
    o = np.argsort(x); cw = np.cumsum(w[o])
    return float(x[o][np.searchsorted(cw, cw[-1] * 0.5)])
newuv = UV.copy()
dens, dens_w = [], []
Dof = {}
nrot = 0
for r in np.unique(troot):
    sel = (troot == r) & ok & (area > 0)
    pts = np.nonzero((root == r) & ~capPt)[0]
    if not sel.any():
        continue
    Lu = max(wmedian(Lu_t[sel], area[sel]), 1e-5)
    Lv = max(wmedian(Lv_t[sel], area[sel]), 1e-5)
    u, v = UV[pts, 0], UV[pts, 1]
    kz = lambda m: {key[i][1:] for i in pts[m]}
    wrap_u = bool(kz(u < 1e-4) & kz(u > 1 - 1e-4))
    wrap_v = bool(kz(v < 1e-4) & kz(v > 1 - 1e-4))
    Deff = D * DMUL.get(ptmat[pts[0]], 1.0)  # woven cloth at double density: finer threads
    for wr, L in ((wrap_u, Lu), (wrap_v, Lv)):
        if wr and L * Deff < 1.0:
            Deff = max(Deff, 1.0 / L)
    su = max(1, round(Lu * Deff)) if wrap_u else Lu * Deff
    sv = max(1, round(Lv * Deff)) if wrap_v else Lv * Deff
    Dof[r] = su / Lu
    # Wood grain runs along v (the loft axis). On boards lofted across their short side (a box rail lying
    # flat: v = its height, u = around its long faces) turn the map a quarter so the grain follows the board.
    if ptmat[pts[0]] in GRAIN and wrap_u and Lu / 2.5 > Lv:
        newuv[pts, 0] = v * sv
        newuv[pts, 1] = u * su
        nrot += 1
    else:
        newuv[pts, 0] = u * su
        newuv[pts, 1] = v * sv
    w = float(area[sel].sum())
    dens += [512.0 * su / Lu, 512.0 * sv / Lv]
    dens_w += [w, w]
# Planar caps: axis 1 = world up projected into the cap plane (world X if the cap faces up/down).
for t in np.nonzero(cap)[0]:
    n = cr[t] / (np.linalg.norm(cr[t]) or 1.0)
    up = np.array([0.0, 1.0, 0.0]) if abs(n[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    t1 = up - n * np.dot(up, n); t1 /= np.linalg.norm(t1)
    t2 = np.cross(n, t1)
    Dc = Dof.get(troot[t], D)
    for p in tri[t]:
        newuv[p, 0] = np.dot(P[p], t2) * Dc
        newuv[p, 1] = np.dot(P[p], t1) * Dc
# Flat rings inside a lathe (a disc band such as a tsuba face or the fallen chunk's faces) get the loft's polar
# mapping, which pinches the texture toward the centre. Find each straight loft's axis (u runs around it, so it is
# the direction every dP/du is perpendicular to) and project the bands that face along that axis flat instead.
# These bands share their rim with the side wall, so UVs become per-vertex there (the exporter splits those points).
VT = newuv[tri].copy()
nflat = 0
for r in np.unique(troot):
    sel = (troot == r) & ok & (area > 0)
    if sel.sum() < 4:
        continue
    g = dpdu[sel] / np.maximum(Lu_t[sel], 1e-9)[:, None]
    M = (g * area[sel][:, None]).T @ g
    w_, V_ = np.linalg.eigh(M)
    if w_[0] > 0.03 * w_[2]:
        continue  # curved tube or free-form part: no single axis
    A = V_[:, 0]
    nt = cr / np.maximum(np.linalg.norm(cr, axis=1), 1e-12)[:, None]
    flat = (troot == r) & ~cap & (np.abs(nt @ A) > 0.97) & (area > 0)
    if not flat.any():
        continue
    up = np.array([0.0, 1.0, 0.0]) if abs(A[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    t1 = up - A * np.dot(up, A); t1 /= np.linalg.norm(t1)
    t2 = np.cross(A, t1)
    Dc = Dof.get(r, D)
    for t in np.nonzero(flat)[0]:
        Pt = P[tri[t]]
        VT[t, :, 0] = Pt @ t2 * Dc
        VT[t, :, 1] = Pt @ t1 * Dc
    nflat += int(flat.sum())
geo.findPointAttrib("uv").destroy()
geo.addAttrib(hou.attribType.Vertex, "uv", (0.0, 0.0, 0.0))
geo.setVertexFloatAttribValues("uv", VT.reshape(-1).tolist())
dens = np.array(dens); dens_w = np.array(dens_w)
geo.addAttrib(hou.attribType.Global, "tex_density", "")
geo.setGlobalAttribValue("tex_density", "%%.0f %%.0f %%.0f caps=%%d rotated=%%d flat=%%d" %% (
    wmedian(dens, dens_w), dens.min(), dens.max(), int(cap.sum()), nrot, nflat))# Material paths for the Principled shaders, then drop the importer's bookkeeping attributes.
if geo.findPrimAttrib("shop_materialpath") is None:
    geo.addAttrib(hou.attribType.Prim, "shop_materialpath", "")
geo.setPrimStringAttribValues("shop_materialpath", tuple("/mat/" + m for m in mats))
for name in ("material_override", "gltf_material_name", "gltf_node_name", "gltf_mesh_name", "name", "path"):
    at = geo.findPrimAttrib(name)
    if at is not None:
        at.destroy()
at = geo.findVertexAttrib("tangentu")
if at is not None:
    at.destroy()
at = geo.findGlobalAttrib("gltf_scene_name")
if at is not None:
    at.destroy()
''' % {"D": TILES_PER_M, "DMUL": {m: 2.0 for m, t in tex_gen.MATERIAL_TEX.items() if t[0] == "cloth"}}


def tex_paths(name, kind, embed):
    if embed:
        return os.path.join(EMBED_DIR, "%s_%s.%s" % (name, kind, "jpg" if EMBED == "jpeg" else "png"))
    return os.path.join(TEX, "%s_%s.png" % (name, kind))


def make_material(name, spec, means):
    m = hou.node("/mat").createNode("principledshader::2.0", name)
    m.parm("alphablendmode").set("opaque")
    m.parm("metallic").set(spec["metal"])
    files = None
    if name in tex_gen.MATERIAL_TEX:
        alb, orm, nrm = tex_gen.MATERIAL_TEX[name]
        mean = means[alb]
        tint = [spec["color"][i] / mean[i] for i in range(3)]
        if max(tint) > 1.01:
            print("    note: %s tint %s > 1, clamped" % (name, ["%.2f" % t for t in tint]))
        tint = [min(1.0, t) for t in tint]
        m.parmTuple("basecolor").set(tint)
        m.parm("basecolor_useTexture").set(1)
        m.parm("basecolor_texture").set(tex_paths(alb, "albedo", False))
        m.parm("rough").set(min(1.0, spec["rough"] / means[orm + "_orm"]))
        m.parm("rough_useTexture").set(1)
        m.parm("rough_texture").set(tex_paths(orm, "orm", False))
        m.parm("rough_monoChannel").set(2)  # green
        m.parm("occlusion_useTexture").set(1)
        m.parm("occlusion_texture").set(tex_paths(orm, "orm", False))
        files = {"albedo": tex_paths(alb, "albedo", True), "orm": tex_paths(orm, "orm", True)}
        if nrm:
            m.parm("baseBumpAndNormal_enable").set(1)
            m.parm("baseBumpAndNormal_type").set("normal")
            m.parm("baseNormal_useTexture").set(1)
            m.parm("baseNormal_texture").set(tex_paths(nrm, "normal", False))
            files["normal"] = tex_paths(nrm, "normal", True)
    else:
        m.parmTuple("basecolor").set(spec["color"])
        m.parm("rough").set(spec["rough"])
    m.parmTuple("emitcolor").set(spec["emit"])
    m.parm("emitint").set(spec["emit_int"])
    return files


def preview_setup():
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
    rop.parm("samplesperpixel").set(PREVIEW_SPP)
    return cam, rop


def render_preview(group, mid, obj, out, path):
    cam, rop = preview_setup()
    bb = out.geometry().boundingBox()
    size = bb.sizevec()
    diag = max(size[0], size[1], size[2])
    if group == "weapons":
        rot, width = ((-15, 25, 0), diag * 1.2) if mid == "shield_round" else ((-15, 25, 45), diag * 0.85)
        dist = 10
    else:
        rot, width, dist = (-12, 30, 0), diag * 1.15, 20
    r = hou.hmath.buildRotate(rot, "xyz")
    cam.setWorldTransform(r * hou.hmath.buildTranslate(hou.Vector3(bb.center()) + hou.Vector3(0, 0, dist) * r))
    for p in (cam.parm("resx"), cam.parm("resy"), rop.parm("resolutionx"), rop.parm("resolutiony")):
        p.set(PREVIEW_RES)
    cam.parm("orthowidth").set(width)
    rop.parm("candobjects").set(obj.name())
    rop.parm("picture").set(path)
    rop.render()
    if not os.path.exists(path):
        print("    preview missing:", path, rop.errors(), rop.warnings())


def process(group, mid, means, previews):
    src = os.path.join(ROOT, "export", group, mid + ".glb")
    dst_dir = os.path.join(ROOT, "export", group + "_tex")
    dst = os.path.join(dst_dir, mid + ".glb")
    os.makedirs(dst_dir, exist_ok=True)
    src_doc, _ = glb_read(src)
    hou.hipFile.clear(suppress_save_prompt=True)
    files = {}
    for name, spec in src_materials(src_doc).items():
        f = make_material(name, spec, means)
        if f:
            files[name] = f
    obj = hou.node("/obj").createNode("geo", mid)
    fsop = obj.createNode("file", "load")
    fsop.parm("file").set(src)
    unp = obj.createNode("unpack", "unpack")
    unp.setInput(0, fsop)
    unp.parm("transfer_attributes").set("*")
    py = obj.createNode("python", "uv_density")
    py.setInput(0, unp)
    py.parm("python").set(UV_SOP)
    out = obj.createNode("null", "OUT")
    out.setInput(0, py)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    geo = out.geometry()
    density = geo.attribValue("tex_density")
    rop = hou.node("/out").createNode("gltf", "export")
    rop.parm("usesoppath").set(1)
    rop.parm("soppath").set(out.path())
    rop.parm("outputfile").set(dst)
    rop.parm("exportmaterials").set(1)
    rop.parm("imageformat").set("jpeg")  # replaced by our own files below
    rop.render()
    doc = postprocess(dst, src_doc, files)
    # Checks
    tris_src, tris_dst = glb_tris(src_doc), glb_tris(doc)
    img_bytes = sum(doc["bufferViews"][im["bufferView"]]["byteLength"] for im in doc.get("images", []))
    alpha = sorted({m.get("alphaMode", "OPAQUE") for m in doc.get("materials", [])})
    untex = [m["name"] for m in doc.get("materials", []) if "baseColorTexture" not in m.get("pbrMetallicRoughness", {})]
    want_untex = [n for n in src_materials(src_doc) if n not in files]
    attrs = sorted({k for me in doc["meshes"] for p in me["primitives"] for k in p["attributes"]})
    names = [n.get("name") for n in doc.get("nodes", [])]
    good = (tris_src == tris_dst and len(doc.get("images", [])) > 0 and sorted(untex) == sorted(want_untex)
            and alpha == ["OPAQUE"] and img_bytes < 1024 * 1024 and "TEXCOORD_0" in attrs)
    row = dict(group=group, id=mid, tris_src=tris_src, tris_dst=tris_dst, glb_kb=os.path.getsize(dst) / 1024.0,
               src_kb=os.path.getsize(src) / 1024.0, img_kb=img_bytes / 1024.0, images=len(doc.get("images", [])),
               alpha=",".join(alpha), untextured=",".join(untex), density=density, ok=good, attrs=",".join(attrs),
               nodes=",".join(n for n in names if n))
    print("%-9s %-14s %s tris %4d -> %4d  glb %6.1f KB (src %5.1f)  images %d = %6.1f KB  alpha=%s  texel/m med,min,max=%s%s" % (
        group, mid, "OK  " if good else "FAIL", tris_src, tris_dst, row["glb_kb"], row["src_kb"], row["images"],
        row["img_kb"], row["alpha"], density, ("  untextured=" + row["untextured"]) if untex else ""))
    if previews:
        pdir = os.path.join(ROOT, "preview", group + "_tex")
        os.makedirs(pdir, exist_ok=True)
        try:
            render_preview(group, mid, obj, out, os.path.join(pdir, mid + ".png"))
        except hou.Error as e:
            print("    preview failed:", e)
    return row


def contact_sheet(group, ids):
    from PIL import Image, ImageDraw
    pdir = os.path.join(ROOT, "preview", group + "_tex")
    ims = [(i, os.path.join(pdir, i + ".png")) for i in ids if os.path.exists(os.path.join(pdir, i + ".png"))]
    if not ims:
        return
    cols = min(5, len(ims))
    s = 256
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * s, rows * (s + 14)), "white")
    d = ImageDraw.Draw(sheet)
    for k, (i, p) in enumerate(ims):
        im = Image.open(p).convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        bg.alpha_composite(im)
        x, y = (k % cols) * s, (k // cols) * (s + 14)
        sheet.paste(bg.convert("RGB").resize((s, s), Image.LANCZOS), (x, y + 14))
        d.text((x + 3, y + 1), i, fill="black")
    sheet.save(os.path.join(pdir, "_sheet.png"))


def main():
    t0 = time.time()
    meta = os.path.join(TEX, "texture_means.json")
    if "--skip-tex" in sys.argv and os.path.exists(meta):
        with open(meta) as f:
            means = json.load(f)
    else:
        print("building textures ->", TEX)
        means = tex_gen.build_all(TEX)
        os.makedirs(EMBED_DIR, exist_ok=True)
        from PIL import Image
        for fn in sorted(os.listdir(TEX)):
            if not fn.endswith(".png"):
                continue
            im = Image.open(os.path.join(TEX, fn)).convert("RGB")
            stem = os.path.splitext(fn)[0]
            if "albedo" in stem:
                im.save(os.path.join(EMBED_DIR, stem + ".jpg"), quality=88, subsampling=2, optimize=True)
            else:  # normal / ORM channels are independent data: no chroma subsampling
                im.save(os.path.join(EMBED_DIR, stem + ".jpg"), quality=90, subsampling=0, optimize=True)
        with open(meta, "w") as f:
            json.dump(means, f, indent=1)
        for fn in sorted(os.listdir(TEX)):
            p = os.path.join(TEX, fn)
            if os.path.isfile(p) and fn.endswith(".png"):
                j = os.path.join(EMBED_DIR, fn[:-4] + ".jpg")
                print("  %-22s %6.1f KB png  %6.1f KB jpg" % (fn, os.path.getsize(p) / 1024.0, os.path.getsize(j) / 1024.0))
    previews = "--no-preview" not in sys.argv
    rows = []
    for group, ids in GROUPS.items():
        if ids is None:
            ids = sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, "export", group)) if f.endswith(".glb"))
        if ONLY and group not in ONLY:
            ids = [i for i in ids if i in ONLY]
        done = []
        for mid in ids:
            rows.append(process(group, mid, means, previews))
            done.append(mid)
        if previews and done:
            contact_sheet(group, sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, "preview", group + "_tex"))
                                        if f.endswith(".png") and not f.startswith("_")))
    hou.hipFile.clear(suppress_save_prompt=True)
    bad = [r["id"] for r in rows if not r["ok"]]
    print("%d models, %.0f s. %s" % (len(rows), time.time() - t0, "ALL OK" if not bad else "FAILED: " + ", ".join(bad)))


main()
