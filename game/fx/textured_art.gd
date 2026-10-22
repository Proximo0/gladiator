class_name TexturedArt
extends RefCounted
## Picks the textured copy of a Houdini model when one exists: res://assets/<group>/<name>.glb becomes
## res://assets/textured/<group>/<name>.glb (tools/houdini/build_textures.py: same triangles, alphaMode OPAQUE, UVs and
## the library's albedo/ORM/normal maps; tools/textured_import.py points its materials at the shared, VRAM-compressed
## textures in res://assets/textures/). Every art loader goes through `path`, so a model without a textured copy, or
## one in KEEP_PLAIN, keeps its untextured file. Presentation only.

const ASSETS: String = "res://assets/"
const DIR: String = "res://assets/textured/"
const LIBRARY: String = "res://assets/textures/"
## Models that stay untextured: the laser sword's blade is an emissive core, not a surface.
const KEEP_PLAIN: PackedStringArray = ["laser_sword"]

## Off: every loader keeps the untextured files (before/after captures, a fallback switch).
static var enabled: bool = true


## The file to load for art at `untextured` (a res://assets/... glb path).
static func path(untextured: String) -> String:
	if not enabled or not untextured.begins_with(ASSETS) or untextured.begins_with(DIR):
		return untextured
	if KEEP_PLAIN.has(untextured.get_file().get_basename()):
		return untextured
	var t: String = DIR + untextured.trim_prefix(ASSETS)
	return t if ResourceLoader.exists(t) else untextured


## A library texture by name ("organic_normal"), or null when it is missing or textured art is off.
static func library(tex_name: String) -> Texture2D:
	var p: String = LIBRARY + tex_name + ".png"
	if not enabled or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D
