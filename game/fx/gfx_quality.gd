class_name GfxQuality
extends RefCounted
## Graphics quality: 0 low (Android, Compatibility/GLES3 on mid phones), 1 medium, 2 high (desktop default). One
## static `level` that the arena, sand and blood read when they are built, so set it before the match starts (the
## options menu writes it from the player's setting). Pure tables, no nodes: every number the quality changes lives
## here. Presentation only: nothing here touches fight state or a state hash.

const LOW: int = 0
const MEDIUM: int = 1
const HIGH: int = 2
const NAMES: PackedStringArray = ["low", "medium", "high"]

## Crowd: metres between spectators are multiplied by CROWD_SPACING_MULT (all tiers) and, from tier 3 out, by
## CROWD_BACK_SPACING as well; tiers from CROWD_CHEER_TIER up get no cheering twin; CROWD_SECTORS angular
## sectors per variant (view culling vs draw calls); CROWD_TIER_LOD gives, per tier, the decimated mesh level
## (-1 full, 0 about half the triangles, 1 about a fifth, 2 about a sixteenth).
const CROWD_SPACING_MULT: Array[float] = [1.4, 1.15, 1.0]
const CROWD_BACK_SPACING: Array[float] = [1.6, 1.25, 1.0]
const CROWD_CHEER_TIER: Array[int] = [3, 6, 6]
const CROWD_SECTORS: Array[int] = [2, 3, 4]
## Few distinct levels keep the draw calls down (one MultiMesh per variant, sector and level).
const CROWD_TIER_LOD: Array = [[1, 1, 1, 2, 2, 2], [0, 0, 0, 1, 1, 1], [-1, -1, 0, 0, 0, 0]]
## Sun shadow: 0 no cascade split (one orthographic map), 1 two splits.
const SHADOW_SPLITS: Array[int] = [1, 2, 2]
const SHADOW_DISTANCE: Array[float] = [34.0, 44.0, 52.0]
const SHADOW_BLUR: Array[float] = [0.0, 1.0, 2.0]
## Do small fighter pieces (forearms, shins and feet, armor trims on them) cast into the sun shadow map? Each caster is
## drawn a second time in the shadow pass, and from the camera a forearm's shadow is hardly seen on the sand.
const SMALL_PART_SHADOWS: Array[bool] = [false, true, true]
const MSAA: Array[int] = [0, 2, 2]  ## Viewport.MSAA_DISABLED / MSAA_2X
## Sand: heightmap texels per metre, floor mesh vertex spacing (m), thrown-grain pool, dust puffs, shader detail
## (0 cheap, 1 most, 2 full: pebbles, rake lines, sparkle).
const SAND_TEXELS_PER_M: Array[float] = [26.0, 32.0, 40.0]
const SAND_MESH_CELL: Array[float] = [0.22, 0.15, 0.1]
const SAND_GRAINS: Array[int] = [450, 900, 1800]
## Fine lingering dust sprites (one MultiMesh quad each) and the share of the per-event spray counts kept.
const SAND_DUST: Array[int] = [110, 260, 560]
const SAND_FX_MULT: Array[float] = [0.45, 0.75, 1.0]
const SAND_PUFFS: Array[int] = [4, 7, 10]
const SAND_PUFF_AMOUNT: Array[int] = [5, 7, 9]
const SAND_DETAIL: Array[int] = [0, 1, 2]
## Seconds between blood pool spreading steps on the sand (each step repaints the pool's texels).
## Seconds between uploads of the dirty sand tiles to the GPU.
const SAND_UPLOAD_S: Array[float] = [1.0 / 15.0, 1.0 / 20.0, 1.0 / 30.0]
const SAND_POOL_STEP_S: Array[float] = [1.0 / 12.0, 1.0 / 20.0, 1.0 / 30.0]

## Hit sparks (HitFx): share of the spark count kept, particles per burst pool, and the spark flash light (off on low).
const SPARK_MULT: Array[float] = [0.5, 0.8, 1.0]
const SPARK_LIGHT: Array[bool] = [false, true, true]

## Energy blades (laser sword): trail ribbon samples kept (0 = no trail), glow light energy (0 = no light), and the
## halo pulse on or off.
const BLADE_TRAIL_SAMPLES: Array[int] = [0, 10, 18]
const BLADE_LIGHT_ENERGY: Array[float] = [0.0, 0.6, 1.0]

## Arena decor (DecorLayout): engaged columns, broken column stumps and wall banners shown, the decimated mesh level
## of the Houdini decor (-1 full, 0 about half the triangles, as CROWD_TIER_LOD), and whether the big pieces
## (columns, stumps, gates, statue) cast sun shadows.
const DECOR_COLUMNS: Array[int] = [4, 8, 8]
const DECOR_STUMPS: Array[int] = [1, 2, 4]
const DECOR_BANNERS: Array[int] = [2, 4, 4]
const DECOR_LOD: Array[int] = [0, -1, -1]
const DECOR_SHADOWS: Array[bool] = [false, true, true]

static var level: int = default_level()


static func default_level() -> int:
	return LOW if OS.has_feature("mobile") else HIGH


static func set_level(l: int) -> void:
	level = clampi(l, LOW, HIGH)


static func name_of(l: int) -> String:
	return NAMES[clampi(l, LOW, HIGH)]


## Blood quality (BloodFx.set_quality) that goes with a graphics level.
static func blood_level(l: int = -1) -> int:
	return clampi(level if l < 0 else l, LOW, HIGH)


static func pick_f(table: Array[float], l: int = -1) -> float:
	return table[clampi(level if l < 0 else l, LOW, HIGH)]


static func pick_i(table: Array[int], l: int = -1) -> int:
	return table[clampi(level if l < 0 else l, LOW, HIGH)]


static func small_part_shadows(l: int = -1) -> bool:
	return SMALL_PART_SHADOWS[clampi(level if l < 0 else l, LOW, HIGH)]


static func decor_shadows(l: int = -1) -> bool:
	return DECOR_SHADOWS[clampi(level if l < 0 else l, LOW, HIGH)]


static func tier_lod(tier: int, l: int = -1) -> int:
	var row: Array = CROWD_TIER_LOD[clampi(level if l < 0 else l, LOW, HIGH)]
	return int(row[clampi(tier, 0, row.size() - 1)])
