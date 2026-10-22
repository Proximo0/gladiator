# Earned shields and armor (second Houdini set)

Six shields and nine armor pieces from `tools/houdini/build_armor_more.py` (branch decor-assets, d8babff), all earned
by playing. Starters stay free (round shield, leather and iron pieces, galea, mail); the scutum stays as it was.

## Shields (data/weapons.json)
Grip at the origin, face toward +Z, like the round shield. `look` picks the collider: `shield` is a disc of diameter
`length`, `board` (and the scutum's own `scutum`) a box of `width` by `length`. `center` [x, y] puts the face off the
grip (the kite hangs 10 cm low, the aspis bowl sits 25 cm to the holder's left). `art_roll` and `art_offset` fit a mesh
built another way round.

| Shield | Face | Mass | Bash (blunt) | Unlock |
| --- | --- | --- | --- | --- |
| `buckler` Buckler | disc 0.31 m | 1.5 kg | 0.85 | Play 1 fight |
| `parma` Parma | disc 0.47 m | 2.5 kg | 0.65 | Play 3 fights |
| `pelta` Pelta | crescent board 0.61 x 0.41 m | 2.2 kg | 0.5 | Win 3 fights |
| `kite_shield` Kite shield | board 0.58 x 1.0 m, 10 cm low | 4.5 kg | 0.6 | Win 5 fights |
| `aspis` Aspis | disc 0.9 m, 25 cm to the left | 6.5 kg | 0.75 | Win 6 fights |
| `tower_shield` Tower shield | board 0.7 x 1.3 m | 8.0 kg | 0.7 | Win 2 ranked Quick Matches |
| (`shield_round` Round shield) | disc 0.6 m | 3.5 kg | 0.6 | starter |
| (`scutum` Scutum) | board 0.68 x 1.08 m | 6.0 kg | 0.7 | Win 2 fights |

Side-grade rule (tested in `test_armor_more.gd`): no shield is at once no heavier, no smaller and no softer-bashing than
another. Small shields are light and hit hard with the boss; big ones cover more and drag the off hand.

**Aspis orientation.** The mesh has its arm band toward -X. `Fighter._wrist` holds a shield with local +X toward the
holder's left, and a hoplite's forearm runs through the band at the centre with the hand at the rim, so the bowl
belongs on the holder's left of the hand: the art is rolled 180 degrees about its face normal (`art_roll`) and the
collider centre is +0.25 m. The bowl sits 3-6 cm off the grip, so the left fist poked through it in the first renders;
`art_offset` moves the mesh 4.5 cm forward.

## Armor (data/armor.json)
Each piece fills one loadout slot (`part`) and protects every part in `covers`; `art` maps each covered part to its
mesh in `assets/armor/` (built in that part's frame, so it attaches directly). The torso pieces also draw the pelvis
piece: the segmentata with the balteus, the squamata with the subligaculum.

| Piece | Slot | Covers | Kind | Cut / pierce / blunt | Durability / strap | Unlock |
| --- | --- | --- | --- | --- | --- | --- |
| `helm_murmillo` Murmillo helmet | head | head | plate | 0.9 / 0.8 / 0.55 | 240 / 60 | Win 7 fights |
| `helm_thraex` Thraex helmet | head | head | plate | 0.95 / 0.9 / 0.3 | 180 / 75 | Win 3 fights |
| `helm_secutor` Secutor helmet | head | head | plate | 0.93 / 0.7 / 0.45 | 220 / 110 | Win 1 fight |
| `lorica_segmentata` Lorica segmentata | torso | chest, belly | plate | 0.9 / 0.75 / 0.35 | 220 / 400 | Win 5 fights |
| `lorica_squamata` Lorica squamata | torso | chest, belly | mail | 0.8 / 0.5 / 0.2 | 180 / 550 | Play 6 fights |
| `balteus` Balteus belt | torso | belly | plate | 0.9 / 0.8 / 0.35 | 160 / 300 | Play 3 fights |
| `retiarius_arm` Galerus and manica | arms | left arm | plate | 0.95 / 0.9 / 0.4 | 240 / 280 | Win 2 fights |
| `spaulders` Bronze spaulders | arms | both upper arms | plate | 0.92 / 0.85 / 0.35 | 200 / 260 | Play 2 fights |
| `fasciae` Fasciae wraps | legs | both thighs | leather | 0.4 / 0.3 / 0.3 | 80 / 140 | Play 1 fight |

The helmets trade against the galea: the murmillo's wide brim takes blunt blows best but is the easiest to knock off,
the thraex is the most blade-proof and the weakest to blunt, the secutor's smooth egg stays on best but its eye holes
let points in. Side-grade rule (tested): no piece is at once no heavier, covering at least as much and at least as
good in every resistance, durability and strap as another piece of its slot.

Armor mass is shown and used by the random loadouts, but the fighter's physics ignores it (only knocked-off props
weigh it), so today armor has no movement cost; see "Next" below.

## Unlocks and the loadout
`WeaponUnlocks` gates armor the same way as weapons and shields: weapon and armor ids share one id space, an armor def
with `unlock` is earned by the same counters, `unlockable_ids()` lists weapons and shields then armor, and the
"Unlocked: Secutor helmet! Pick it in your loadout." line works unchanged. `LoadoutRules.sanitize(loadout, owned)`
turns a locked armor piece into the slot's default (`DEFAULT_ARMOR`: leather cap and jerkin, nothing for arms and legs),
like a locked shield becomes the round shield. The loadout screen lists every piece, greys locked ones with a padlock,
shows the milestone on the stat card ("Locked: Win 3 fights (1/3)"), and the 3D preview shows the browsed piece or
shield so a player can see what they are playing for. The stat card line now names what a piece covers
("2.4 kg | plate | left arm"). `--unlock-all` opens them; ranked Quick Match ignores it, as for weapons.

## Renders
`tests/render/armor_more_capture.tscn` (see its header for the command) saves two armored gladiators and each one's front
and back. Three sets cover every new helmet, torso piece, arm piece and shield, at 1280x720 (`land_*`) and 540x960
(`port_*`) in `docs/renders/armor_more_game/`.

## Balance
`tools/bot_match.sh` takes `--o0/--o1=<shield>` and `--a0/--a1=<armor ids>`. See the tables below (seeds 2000-2011 on
both sides, 24 fights per row, 60 s limit).
