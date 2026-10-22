#!/usr/bin/env python3
"""Shared materials for the textured Houdini models (assets/textured/<group>/<name>.glb).

Each textured glb embeds its own 512 px copies of the library textures (assets/textures/<family>_{albedo,normal,orm}.png,
tools/houdini/build_textures.py): 203 images, 27 distinct. Imported as is, every model would load its own uncompressed
copies. This tool writes one StandardMaterial3D per distinct glb material into assets/textured/materials/ that points at the
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
ORM_G_MEAN = 0.9  # mean of every ORM map's roughness channel (tools/houdini/tex_gen.py)
# Looks set in the arena light (tests/render/material_capture.tscn), applied over the glTF factors:
# - A metal below about 0.45 effective roughness (factor x ORM_G_MEAN) mirrors the deep-blue sky top and the sun glow,
#   and the map's roughness spread turns that into light and dark patches along a blade. Polished but not mirror.
METAL_ROUGHNESS_MIN = 0.45
# - Linear base colour scale per material: steel's colour was aluminium x 0.9 (F0 ~0.8), white in the sun under ACES;
#   0.6 brings it to ~0.48, a grey that still flashes. Bronze armor (metallic capped at 0.6 by FighterArt, so part
#   diffuse) washed out to pale yellow in full sun at 1.0; 0.8 keeps it a deep warm brown-gold.
COLOR_SCALE = {"steel": 0.6, "bronze": 0.8}


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


def material_spec(j, m, look=True):
	"""The material's maps and factors; `look` applies the arena looks above (off: the glb's own, for naming)."""
	pbr = m.get("pbrMetallicRoughness", {})
	scale = COLOR_SCALE.get(m["name"], 1.0) if look else 1.0
	col = [c * scale for c in pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])[:3]]
	metallic = pbr.get("metallicFactor", 1.0)
	rough = pbr.get("roughnessFactor", 1.0)
	if look and metallic >= 0.9:
		rough = max(rough, METAL_ROUGHNESS_MIN / ORM_G_MEAN)
	return {
		"albedo": image_name(j, pbr.get("baseColorTexture")),
		"orm": image_name(j, pbr.get("metallicRoughnessTexture")),
		"normal": image_name(j, m.get("normalTexture")),
		"ao": m.get("occlusionTexture") is not None,
		"color": [round(srgb(c), 4) for c in col],
		"metallic": round(metallic, 4),
		"roughness": round(rough, 4),
	}


def tres(name, spec):
	"""A StandardMaterial3D, not an ORMMaterial3D: Godot's ORM shader takes roughness and metallic straight from the map
	and ignores both factors, so every metal was rough (G mean 0.9) and fully metallic. Here one ORM texture feeds AO (R),
	roughness (G) and metallic (B) through channel selects, and the glTF factors multiply them as glTF means."""
	ext = []
	for key in ("albedo", "orm", "normal"):
		if spec[key]:
			png = os.path.join(LIBRARY, spec[key] + ".png")
			if not os.path.exists(png):
				raise SystemExit("textured_import: missing library texture %s" % png)
			ext.append((key, "res://assets/textures/%s.png" % spec[key]))
	lines = ['[gd_resource type="StandardMaterial3D" load_steps=%d format=3]' % (len(ext) + 1), ""]
	for i, (_k, p) in enumerate(ext):
		lines.append('[ext_resource type="Texture2D" path="%s" id="%d"]' % (p, i + 1))
	lines += ["", "[resource]", 'resource_name = "%s"' % name]
	lines.append("albedo_color = Color(%g, %g, %g, 1)" % tuple(spec["color"]))
	ids = {k: i + 1 for i, (k, _p) in enumerate(ext)}
	if "albedo" in ids:
		lines.append('albedo_texture = ExtResource("%d")' % ids["albedo"])
	lines.append("metallic = %g" % spec["metallic"])
	if "orm" in ids:
		lines.append('metallic_texture = ExtResource("%d")' % ids["orm"])
		lines.append("metallic_texture_channel = 2")
	lines.append("roughness = %g" % spec["roughness"])
	if "orm" in ids:
		lines.append('roughness_texture = ExtResource("%d")' % ids["orm"])
		lines.append("roughness_texture_channel = 1")
	if "normal" in ids:
		lines.append("normal_enabled = true")
		lines.append('normal_texture = ExtResource("%d")' % ids["normal"])
	if spec["ao"] and "orm" in ids:
		lines.append("ao_enabled = true")
		lines.append('ao_texture = ExtResource("%d")' % ids["orm"])
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
	want = {"materials": subres}
	if "gltf/embedded_image_handling=0" in text and current_subresources(text) == want:
		return text  # Godot rewrites the value over several lines (and adds fallback paths): keep its file
	text = set_param(text, "gltf/embedded_image_handling", "0")
	return set_param(text, "_subresources", json.dumps(want, sort_keys=True))


def current_subresources(text):
	"""The `_subresources` value of an .import file's text, without Godot's fallback paths; None when unreadable."""
	m = re.search(r"^_subresources=(.*?)(?=^[a-z_0-9/]+=|^\[|\Z)", text, re.M | re.S)
	if not m:
		return None
	try:
		value = json.loads(m.group(1))
	except ValueError:
		return None
	for mat in value.get("materials", {}).values():
		mat.pop("use_external/fallback_path", None)
	return value


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
	raws = {}  # material file name -> spec without the looks: a variant's name hashes this, so tuning a look keeps it
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
				raw = material_spec(j, m, False)
				name = m["name"]
				if name in raws and raws[name] != raw:
					name = "%s_%s" % (name, hashlib.md5(json.dumps(raw, sort_keys=True).encode()).hexdigest()[:6])
				specs[name] = spec
				raws[name] = raw
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
