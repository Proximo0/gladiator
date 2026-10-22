class_name BloodPalette
extends RefCounted
## What one fighter's blood looks like: fresh and dried colour, a glow strength (0 for red blood, a little for the
## alien's ichor) and the inner colours shown in a wound or a severed part (flesh, fat, bone or chitin). Data comes
## from the "blood" block of an outfit in data/outfits.json (see OutfitRules.blood_palette). Pure data and colour
## math, no nodes. The per-medium scales turn the one fresh / dried pair into the shade each surface needs (droplet,
## mist, ground decal, sand soak, body stain), so red keeps the look it always had and any other colour keeps its hue.

const K_DROP_BRIGHT: float = 1.225
const K_DROP_DARK: float = 0.65
const K_MIST: float = 1.02
const K_DECAL_FRESH: float = 0.6
const K_DECAL_DRIED: float = 0.71
const K_SAND_FRESH: float = 0.5625
const K_SAND_DRIED: float = 0.83
const ORGAN_TONES: Array[Color] = [Color(0.32, 0.05, 0.05), Color(0.7, 0.36, 0.34), Color(0.55, 0.06, 0.07)]

var fresh: Color = Color8(204, 3, 7)
var dried: Color = Color8(61, 9, 8)
var emission: float = 0.0  ## 0 for plain blood; ichor glows
var flesh: Color = Color8(191, 10, 10)
var fat: Color = Color8(230, 204, 102)
var bone: Color = Color8(217, 209, 179)


static func red() -> BloodPalette:
	return BloodPalette.new()


## From an outfit's "blood" block ({"fresh": "#rrggbb", "dried", "emission", "flesh", "fat", "bone"}). Missing or bad
## keys keep the red default, so an old outfit file never breaks.
static func from_dict(d: Dictionary) -> BloodPalette:
	var p: BloodPalette = BloodPalette.new()
	p.fresh = _col(d, "fresh", p.fresh)
	p.dried = _col(d, "dried", p.dried)
	p.flesh = _col(d, "flesh", p.flesh)
	p.fat = _col(d, "fat", p.fat)
	p.bone = _col(d, "bone", p.bone)
	p.emission = clampf(float(d.get("emission", 0.0)), 0.0, 2.0)
	return p


static func _col(d: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = str(d.get(key, ""))
	if v == "" or not v.is_valid_html_color():
		return fallback
	return Color.html(v)


## `c` times k, brightness capped at 1 with the hue kept (a bright cyan scaled up must not clip to white).
static func scaled(c: Color, k: float) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b)) * k
	var f: float = k if m <= 1.0 else k / m
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


## Colour of this blood on a body or weapon by dryness 0 fresh .. 1 dried.
func stain_color(dry: float) -> Color:
	return fresh.lerp(dried, pow(clampf(dry, 0.0, 1.0), 0.8))


func drop_bright() -> Color:
	return scaled(fresh, K_DROP_BRIGHT)


func drop_dark() -> Color:
	return scaled(fresh, K_DROP_DARK)


func mist_color() -> Color:
	return scaled(fresh, K_MIST)


func decal_fresh() -> Color:
	return scaled(fresh, K_DECAL_FRESH)


func decal_dried() -> Color:
	return scaled(dried, K_DECAL_DRIED)


func sand_fresh() -> Color:
	return scaled(fresh, K_SAND_FRESH)


func sand_dried() -> Color:
	return scaled(dried, K_SAND_DRIED)


## Inner colour by name: "flesh", "fat", "bone" (chitin for the alien); anything else gives flesh.
func inner(kind: String) -> Color:
	match kind:
		"fat":
			return fat
		"bone":
			return bone
	return flesh


## Intestine colour: the flesh tone washed out toward pink-white, `t` 0..1 picks a variant. Alien flesh keeps its hue.
func gut_color(t: float) -> Color:
	return flesh.lerp(Color(1.0, 0.62, 0.6), 0.28 + 0.2 * t).lerp(fat, 0.1 * (1.0 - t))


## Organ colour of ORGAN_TONES[i] (liver, stomach, heart: the Houdini base colours, for red blood) turned to this
## blood's hue: the red palette gives the authored colours, ichor gives organs of its own hue at the same depth.
func organ_tone(i: int) -> Color:
	var base: Color = ORGAN_TONES[clampi(i, 0, ORGAN_TONES.size() - 1)]
	var red_h: float = Color8(191, 10, 10).h
	var h: float = fposmod(base.h + flesh.h - red_h, 1.0)
	var sat: float = base.s * clampf(flesh.s / maxf(Color8(191, 10, 10).s, 0.01), 0.0, 1.0)
	return Color.from_hsv(h, sat, base.v)


## Organ chunk colour (liver, kidney): the flesh tone darkened with a purple lean.
func organ_color(t: float) -> Color:
	return flesh.darkened(0.3 + 0.2 * t).lerp(Color(0.34, 0.08, 0.22), 0.3)
