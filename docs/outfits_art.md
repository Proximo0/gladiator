# Premium outfit art: samurai and alien

Two full replacement part sets for the fighter body, built procedurally in Houdini by `tools/houdini/build_outfits.py`
(same method and conventions as `build_body.py`). Visual only: colliders, joints and physics never change.

## Run

Copy the script next to `build_body.py` in the Houdini project (`scripts/`), then from the project folder:

```
hython scripts/build_outfits.py                      # both outfits, with previews
hython scripts/build_outfits.py --outfit samurai     # one outfit (alien, or samurai,alien)
hython scripts/build_outfits.py --no-preview         # skip the Karma render
hython scripts/build_outfits.py --detail             # also a head close-up per outfit
```

Output (relative to the Houdini project root, like `export/body`):

- `export/outfits/samurai/<part>.glb`
- `export/outfits/alien/<part>.glb` and `export/outfits/alien/cap_*.glb`
- `export/outfits/preview_samurai.png`, `export/outfits/preview_alien.png`: front view (left) and 3/4 view (right).
- `hip/outfits.hip`: the generated scene.

It prints one line per part (triangles, bbox, signed volume, materials, `OK` or `CHECK [reason]`) and ends with `ALL OK`
or `SOME CHECKS FAILED`. Checks: under 6000 triangles per part, positive volume, NORMAL, TEXCOORD_0 and COLOR_0 present,
only the outfit's own materials, and bbox within 1.5 cm (heads 3 cm) of the base body art bounds.

The geometry code was also executed outside Houdini against a mock `hou` (all 12 parts of both outfits build, every
solid has positive volume, bounds and triangle counts pass, software-rendered silhouettes checked). The glTF ROP,
the Karma preview and the material nodes were not run: first run in Houdini needs a look.

## Parts

Same names, frames, origins and mirroring as the base body (`assets/body/`): `pelvis torso head head_b upper_arm_l
upper_arm_r forearm_l forearm_r thigh_l thigh_r shin_l shin_r` (12 files; the base body has no 13th part). `head_b`
is the bearded head: both outfits cover the lower face, so `head_b.glb` is identical to `head.glb` (the game can
load `head` always for these outfits). Metres, Y up, -Z forward, origin at the part centre in the rest pose.

The first and last ~3 cm of every limb part keep the base's tapered ends (joint overlap and the `CUT_REACH` cut-cap
fit in `fighter_art.gd`), and no armour covers them, so dismemberment caps land on bare tapered meshes.

Triangles (both limbs of a pair equal): samurai pelvis 2208, torso 4612, head 4956, upper arm 2192, forearm 3192,
thigh 1868, shin 3516. Alien pelvis 1228, torso 4164, head 1832, upper arm 716, forearm 1668, thigh 712, shin 1456.

### Samurai
- head: kabuto bowl with ribs, brow peak, gold band and finial; gold crescent maedate; five-lame shikoro neck guard
  (black and red); turned-back fukigaeshi wings; red lacquer menpo mask with gold rim over the lower face; throat lames
  (tare). Eyes and brow stay visible and use the tinted `skin`.
- torso: indigo kimono, team-coloured collar, red lacquer do chest plate with gold trim and chest mon, six black
  kusazuri lames with gold edges hanging over the hips.
- pelvis: pleated dark indigo hakama, team-coloured obi sash with a back bow.
- upper arms: indigo sleeve with five-lame sode (black top, red below, gold edges) on the outer side.
- forearms: bare wrist, indigo kote sleeve, iron splints, black elbow cup, gold cuff, iron tekko plate on the back of the
  hand (the fist and grip bar are the base hand, so weapon grips are unchanged).
- thighs: pleated indigo hakama with four-plate black haidate on the front.
- shins: indigo leg wraps, black suneate front guards with red splints and gold trim, team-coloured ties, base sandals.

### Alien
- head: bulbous cranium, narrow jaw, thin neck, large black almond eyes (outer corners raised, wrapped round the face;
  tilt is `tilt = 24.0` in `build_head_alien`), nostril and mouth slits. No hair, no ears.
- torso: lean chest (84% width) with faint rib ridges, seven overlapping front chitin segments, six dorsal plates and
  spines, shoulder nodules that bridge the narrow chest to the arm sockets.
- pelvis: slim, chitin belt and three hip plates.
- arms: slim (72 to 74%), shoulder and forearm chitin segments, three-fingered hands (no thumb) curled round the same
  grip bar as the base fist.
- legs: slim thighs with chitin ridge; shin shaped as a digitigrade leg (hock bulging backward, long lower leg sloping
  forward, ankle spur) ending in a pad with three clawed toes and a heel talon. The sole stays at the base sole height.
- caps: `cap_neck cap_shoulder cap_elbow cap_hip cap_knee`, same size and shape as the base caps, with alien materials.

## Materials the game should map

Names are glTF material names, as in the base body. `skin` and `cloth` are meant to be replaced by the existing tinted
overrides in `FighterArt._tint`; everything else keeps the imported material.

| Material | Used by | Look (linear base colour, rough, metal) | Game mapping |
| --- | --- | --- | --- |
| `skin` | samurai face, neck, wrists, hands, feet | base | existing skin tint (match seed) |
| `cloth` | samurai obi, collar, shin ties | base (near white) | existing team colour tint |
| `leather`, `hair` | samurai sandals, eyes | base | keep |
| `lacquer_red` | samurai do, sode, menpo | 0.32 0.012 0.010, 0.18, 0 | keep (glossy; a clearcoat of 0.6 suits it) |
| `lacquer_black` | samurai kabuto, lames, guards | 0.010 0.010 0.012, 0.15, 0 | keep |
| `gold` | samurai trim, maedate | 0.85 0.52 0.10, 0.28, 1 | keep |
| `cloth_indigo` | samurai hakama, kimono, wraps | 0.010 0.016 0.060, 0.92, 0 | keep (not team tinted) |
| `iron` | samurai splints, tekko | 0.10 0.10 0.11, 0.40, 1 | keep |
| `alien_skin` | alien body | 0.22 0.30 0.22, 0.50, 0 | keep, or a gentle per-fighter tint |
| `alien_chitin` | alien plates, claws, spines | 0.13 0.19 0.15, 0.28, 0.6 | keep; iridescence is baked, see below |
| `alien_eye` | alien eyes | 0.004 0.004 0.005, 0.04, 0 | keep (could add a faint specular/fresnel) |
| `alien_mouth` | alien mouth and nostrils | 0.035 0.045 0.040, 0.6, 0 | keep |
| `alien_flesh`, `alien_fat`, `alien_bone` | alien caps | placeholders equal to human flesh, fat, bone | see question 1 |

Vertex colour (`COLOR_0`) is a baked albedo multiplier, not a mask. Godot switches on `vertex_color_use_as_albedo`
when it imports a mesh with COLOR_0, so it multiplies the base colour. It is white everywhere except `alien_chitin`,
which carries a slight green, violet and gold hue shift (each channel 0.63 to 0.97, cosine palette by world position, so it
is continuous across parts). No game code is needed for the effect. A tinted override material (`skin`, `cloth`) does
not use COLOR_0, which is fine because those are white there. If the owner wants a view-dependent shimmer later, add
rim/fresnel to the `alien_chitin` material in a shader; the baked colour then acts as the base.

## What the game side needs

1. An outfit selector: choose a directory (`res://assets/outfits/<outfit>/` or the base `res://assets/body/`) per fighter
   in `FighterArt.DIR`, `dress` and `_instance`. Part names match, so nothing else in `dress` changes.
2. Hair: neither outfit has any, the head meshes already contain their own head covering (kabuto, bare alien skull). Skip
   `BodyLook.bearded` for these outfits and load `head` (both files are identical anyway). Any separate hair or beard
   prop on the head slot should be hidden.
3. Armor slots: the existing `ARMOR_FIT` primitives (helmet, torso, limb sleeves) would sit on top of the outfit. The
   samurai art is already armour: hide the primitive armor visuals for parts the outfit covers, or accept double layers.
   The helmet shell uses `HELM_CLEAR` 6 mm over the head collider; the kabuto bowl is 6 mm to 28 mm (brim) off the base
   head surface, so a helmet drawn over it would clip.
4. Caps: the samurai uses the base caps (`cap_*.glb` of the body). The alien ships its own caps with `alien_*` materials;
   `BodyLook.cap_for` and `_add_cap` need the outfit directory so they pick them up.
5. Bounds: art stays within 1.5 cm of the base art (heads 3 cm). The samurai head grows to about +/-0.107 in x, down to
   -0.131 and up to +0.122 in z in the head frame; the alien head to 0.108 wide, 0.142 high, 0.128 back. Both exceed the head
   collider (0.11 box) only by the crest, shikoro flare and cranium. Hits are decided by the colliders, so a sword can pass
   through the maedate or the back of the alien skull visually; that is expected.
6. Shadows: `SMALL_SHADOW_PARTS` logic works unchanged (same part names).
7. Performance: samurai about 33k triangles per fighter, alien about 16k, versus about 15k for the base body. A samurai head has up to
   7 material surfaces. If low quality needs less, cut the shikoro and kusazuri first.

## Questions for the owner

1. Alien blood colour: green-blue ichor, or the same red as humans? The alien caps (`alien_flesh`, `alien_fat`,
   `alien_bone`) and the blood decals and particles are all shaped for human red right now. The script keeps the caps at the
   human colours until decided (`ICHOR_FLESH`, `ICHOR_FAT` at the top of the script change both the cap meshes and the
   material in one line). A different blood colour also needs the game's wound and splatter colour to depend on the
   fighter's outfit.
2. Alien gore: gutting and organs use the human flesh and fat look; should an alien show different insides (for
   example no bones, or chitin splinters)?
3. Samurai face: the face shows `skin` between brim and menpo. Should the menpo be removable on a hit (a cut that
   exposes the mouth), or is it permanent?
4. Alien eyes: slant direction (outer corners up as built, or the classic downward wrap) and eye size are a one-line
   change (`tilt`, `hx`, `hy` in `build_head_alien`).
5. Samurai obi, collar and leg ties follow the team colour; hakama and kimono are always dark indigo. Should the indigo
   also follow the team colour?

## Risks

- Not run in Houdini 22: the geometry was verified with a mock `hou`. Possible first-run differences: the glTF ROP's
  material or COLOR_0 export, `object_merge` parameter names in the preview, Karma `candobjects`. A preview failure is
  caught and printed; the exports are independent of it.
- Thin plates (shell lips, 2 to 8 mm) can shimmer at distance or z-fight where bands overlap; the shell offsets were
  chosen to keep upper plates outside lower ones, and the gold trim sits 1.5 mm proud.
- The hakama and kimono hide the underlying body; cut caps (`skin` ring, flesh, bone) land on the narrow base-style
  ends at the joints, where the cloth also tapers, but cap radius versus cloth was not checked in game.
- Normals use the same 50 degree cusp as the body, so bevelled plate edges stay crisp but a very small bevel can look
  faceted.
- Alien lean proportions (slim arms, thin ankles) are art-only; the physics body is as thick as before, so weapons
  collide with a larger volume than drawn, by up to about 2 cm on the arms and 3 cm on the thighs.

## In-game rules (implemented in `FighterArt`, `BodyLook`, `OutfitRules`)

- Loading: an outfit's part glb replaces the base part (`FighterArt._outfit_scene`); `head_b` maps to `head`, so no
  beard or hair shows. Imports need no setting changes.
- Materials on outfit art: surfaces named `skin` take the seeded skin tone (samurai face, hands, feet); `cloth` takes the
  side's team colour (`BodyLook.cloth_color`, not the palette cloth, which is only for the palette fallback); everything
  else keeps the glb material. `alien_*` surfaces never take the skin tone. Overrides, set in code and not in the glb:
  `alien_skin` is lifted to `ALIEN_SKIN_COLOR` (brighter, greener) and `alien_eye` is glossy black (clearcoat).
- Equipped armor shells: the `ARMOR_FIT` shell of a worn piece is not drawn where the outfit's art already shows armor
  (data `art_armor` list of the outfit: samurai head, torso, pelvis, both arms' upper and lower parts, thighs, shins).
  The node stays (render layers set to 0, shadow off), so wear, protection, restore and a knocked-off piece (the prop
  copies the shell mesh and falls) behave as before. The alien has no `art_armor`, so its drawn armor shows as for the
  default outfit. Armor that is knocked off the samurai shows as a prop only; the samurai art underneath is unchanged.
- Caps: `BodyLook.cap_for(part, outfit)` gives `outfits/alien/cap_*` for outfits in `BodyLook.OUTFITS_WITH_CAPS` and the
  base cap otherwise. For every outfit the cap's flesh, fat and bone surfaces (`alien_` prefix too) take
  `OutfitRules.blood_palette(outfit)` inner colours (ichor also gets a faint emission); the `skin` ring keeps the skin tone.
- Renders: `/tmp/outfits_game/` (samurai_vs_default, alien_vs_samurai, alien_severed_arm_cap).
