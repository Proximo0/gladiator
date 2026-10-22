#!/usr/bin/env python3
"""Shared materials for the textured Houdini models (assets/textured/<group>/<name>.glb).

Each textured glb embeds its own 512 px copies of the library textures (assets/textures/<family>_{albedo,normal,orm}.png,
tools/houdini/build_textures.py): 203 images, 27 distinct. Imported as is, every model would load its own uncompressed
copies. This tool writes one ORMMaterial3D per distinct glb material into assets/textured/materials/ that points at the
library PNGs, sets each glb's import to use those materials and discard its embedded images, and sets the library PNGs
to VRAM-compressed with mipmaps (normal maps as normal maps). Run it after re-exporting the textured models, then
`godot --headless --import`. Standard library only. Usage: tools/textured_import.py
"""
import hashlib
import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXTURED = os.path.join(ROOT, "assets", "textured")
LIBRARY = os.path.join(ROOT, "assets", "textures")
MATERIALS = os.path.join(TEXTURED, "materials")


def glb_json(path):
	with open(path, "rb") as f:
		data = f.read()
	size = struct.unpack("<I", data[12:16])[0]
	return json.loads(data[20:20 + size])


def srgb(c):
	return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1.0 / 2.4)) - 0.055


def image_name(j, info):
	if info is None:
		return None
	return j["images"][j["textures"][info["index"]]["source"]]["name"]


def material_spec(j, m):
	pbr = m.get("pbrMetallicRoughness", {})
	col = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
	return {
		"albedo": image_name(j, pbr.get("baseColorTexture")),
		"orm": image_name(j, pbr.get("metallicRoughnessTexture")),
		"normal": image_name(j, m.get("normalTexture")),
		"ao": m.get("occlusionTexture") is not None,
		"color": [round(srgb(c), 4) for c in col[:3]],
		"metallic": round(pbr.get("metallicFactor", 1.0), 4),
		"roughness": round(pbr.get("roughnessFactor", 1.0), 4),
	}


def tres(name, spec):
	ext = []
	for key in ("albedo", "orm", "normal"):
		if spec[key]:
			png = os.path.join(LIBRARY, spec[key] + ".png")
			if not os.path.exists(png):
				raise SystemExit("textured_import: missing library texture %s" % png)
			ext.append((key, "res://assets/textures/%s.png" % spec[key]))
	lines = ['[gd_resource type="ORMMaterial3D" load_steps=%d format=3]' % (len(ext) + 1), ""]
	for i, (_k, p) in enumerate(ext):
		lines.append('[ext_resource type="Texture2D" path="%s" id="%d"]' % (p, i + 1))
	lines += ["", "[resource]", 'resource_name = "%s"' % name]
	lines.append("albedo_color = Color(%g, %g, %g, 1)" % tuple(spec["color"]))
	ids = {k: i + 1 for i, (k, _p) in enumerate(ext)}
	if "albedo" in ids:
		lines.append('albedo_texture = ExtResource("%d")' % ids["albedo"])
	if "orm" in ids:
		lines.append('orm_texture = ExtResource("%d")' % ids["orm"])
	lines.append("metallic = %g" % spec["metallic"])
	lines.append("roughness = %g" % spec["roughness"])
	if "normal" in ids:
		lines.append("normal_enabled = true")
		lines.append('normal_texture = ExtResource("%d")' % ids["normal"])
	if spec["ao"] and "orm" in ids:
		lines.append("ao_enabled = true")
	return "\n".join(lines) + "\n"


def set_param(text, key, value):
	"""Sets `key=value` in an .import file's text; a value Godot wrote over several lines is replaced whole."""
	out = []
	found = False
	skipping = False
	for line in text.split("\n"):
		if skipping and not re.match(r"^[a-z_0-9/]+=", line) and not line.startswith("["):
			continue
		skipping = False
		if line.startswith(key + "="):
			out.append("%s=%s" % (key, value))
			found = True
			skipping = True
			continue
		out.append(line)
	text = "\n".join(out)
	if not found:
		text = text.rstrip("\n") + "\n%s=%s\n" % (key, value)
	return text


def scene_import(path, subres):
	"""The glb's .import with external materials and discarded images. Keeps Godot's file (and uid) when present."""
	imp = path + ".import"
	if os.path.exists(imp):
		with open(imp) as f:
			text = f.read()
	else:
		text = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
	text = set_param(text, "gltf/embedded_image_handling", "0")
	return set_param(text, "_subresources", json.dumps({"materials": subres}, sort_keys=True))


def texture_import(png):
	normal = png.endswith("_normal.png")
	return "\n".join([
		"[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", "",
		"compress/mode=2", "compress/high_quality=false", "compress/lossy_quality=0.7",
		"compress/normal_map=%d" % (1 if normal else 2), "mipmaps/generate=true", "mipmaps/limit=-1",
		"roughness/mode=0", "process/fix_alpha_border=true", "process/size_limit=0", "detect_3d/compress_to=0", ""])


def main():
	writes = {}
	specs = {}  # material file name -> spec
	for group in sorted(os.listdir(TEXTURED)):
		gdir = os.path.join(TEXTURED, group)
		if group == "materials" or not os.path.isdir(gdir):
			continue
		for fn in sorted(os.listdir(gdir)):
			if not fn.endswith(".glb"):
				continue
			path = os.path.join(gdir, fn)
			j = glb_json(path)
			subres = {}
			for m in j.get("materials", []):
				spec = material_spec(j, m)
				name = m["name"]
				if name in specs and specs[name] != spec:
					name = "%s_%s" % (name, hashlib.md5(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:6])
				specs[name] = spec
				subres[m["name"]] = {"use_external/enabled": True,
						"use_external/path": "res://assets/textured/materials/%s.tres" % name}
			writes[path + ".import"] = scene_import(path, subres)
	for name, spec in specs.items():
		writes[os.path.join(MATERIALS, name + ".tres")] = tres(name, spec)
	for fn in sorted(os.listdir(LIBRARY)):
		if fn.endswith(".png"):
			p = os.path.join(LIBRARY, fn + ".import")
			old = open(p).read() if os.path.exists(p) else ""
			# Keep Godot's own file once it has imported with these params (it adds uid and remap lines).
			if "compress/mode=2" not in old or "detect_3d/compress_to=0" not in old:
				writes[p] = texture_import(fn)
	written = 0
	for p, text in writes.items():
		old = open(p).read() if os.path.exists(p) else None
		if old == text:
			continue
		written += 1
		os.makedirs(os.path.dirname(p), exist_ok=True)
		with open(p, "w") as f:
			f.write(text)
	print("TEXTURED_IMPORT materials=%d written=%d" % (len(specs), written))
	return 0


if __name__ == "__main__":
	sys.exit(main())
