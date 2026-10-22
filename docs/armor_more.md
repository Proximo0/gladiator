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
| `retiarius_arm` Galerus and manicae | arms | left arm, right forearm | plate | 0.95 / 0.9 / 0.4 | 240 / 280 | Win 2 fights |
| `spaulders` Spaulders and manicae | arms | both arms | plate | 0.88 / 0.8 / 0.45 | 220 / 280 | Play 2 fights |
| `fasciae` Fasciae wraps | legs | both thighs | leather | 0.4 / 0.3 / 0.3 | 80 / 140 | Play 1 fight |

The helmets trade against the galea: the murmillo's wide brim takes blunt blows best but is the easiest to knock off,
the thraex is the most blade-proof and the weakest to blunt, the secutor's smooth egg stays on best but its eye holes
let points in. Side-grade rule (tested): no piece is at once no heavier, covering at least as much and at least as
good in every resistance, durability and strap as another piece of its slot.

Armor mass now costs mobility and stamina (`ArmorLoad`), and plate has gaps at the joints (`ArmorGaps`); see
"Weight and plate gaps" below. The ragdoll's body masses still ignore it (knocked-off props weigh it).

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

### Shields: gladius + shield vs longsword (leather armor both sides)
Wins of the shield side out of 24. Round 1 was measured before batch 10's weapon balance landed, so only round 2
and later compare.

| Shield | Round 1 | Round 2 | Round 3 (final data) | Mean length (round 2/3) |
| --- | --- | --- | --- | --- |
| shield_round (starter) | 6 | 11 | - | 22.0 s |
| scutum | 14 | 15 | - | 23.2 s |
| buckler | 9 | 4 | 8 (bash 1.35) | 20.9 s |
| parma | 5 | 7 | 7 (bash 0.8) | 22.1 s |
| pelta | 5 | 10 | - | 23.4 s |
| kite_shield | 12 | 13 | - | 24.3 s |
| aspis | 10 | 17 | 9 (bash 0.45) | 21.6 s |
| tower_shield | 17 (8 kg) | 20 (10 kg) | 14 (bash 0.35) | 25.7 s |

The big shields won on their bash: a heavier tower shield won more, a softer bash brought it from 83% to 58%. The
small shields stay around 30% (just under the 35% line, within the +/- 2 of 24 noise): they cover little, and a
harder boss punch barely moved them.

### Armor: one piece swapped into the iron set, gladius vs gladius
Side 0 wears the iron set (galea, iron cuirass, iron arm plate, bronze greaves) with one slot replaced; wins of that
side out of 24 (iron set vs itself: 11/24, mean 35.9 s).

| Piece | Round 1 | Round 2 (final data) | Mean length (round 2) |
| --- | --- | --- | --- |
| helm_murmillo | 9 | 16 | 39.6 s |
| helm_thraex | 12 | 12 | 37.6 s |
| helm_secutor | 12 | 11 | 42.3 s |
| lorica_segmentata | 12 | 10 | 39.4 s |
| lorica_squamata | 15 | 7 | 39.2 s |
| balteus | 9 | 9 | 33.8 s |
| retiarius_arm | 3 (left arm only) | 16 (adds the right manica) | 38.3 s |
| spaulders | 4 (upper arms only) | 10 (adds both manicae) | 41.6 s |
| fasciae | 9 | 12 | 36.9 s |

Every piece lands within 29-67% and the fights stay 34-42 s (iron set 36 s); the same piece moves by 4-8 wins
between rounds, so these are noise-level differences, not tiers.

## Weight and plate gaps
**Weight** (`game/logic/armor_load.gd`, Tuning group "Armor"). Load = worn armor mass / `armor_load_ref` (19 kg;
the iron set is 19.3 kg, so about 1), capped at 1.5. Pieces knocked off drop out at once. At a full load:

| Cost | Tuning row | Full load |
| --- | --- | --- |
| Walk and sprint speed | `armor_speed_loss` | -20% |
| Walking acceleration cap (starts, stops, turns) | `armor_accel_loss` | -25% |
| Stamina per step | `armor_step_stamina` | 0.03 |
| Stamina per swing or thrust started | `armor_swing_stamina` | 0.06 |
| Get-up time | `armor_getup_slow` | +60% (1.4 s to 2.2 s) |
| Hand force cap, per arm, from that arm's armor (`armor_arm_ref` 2 kg = full) | `armor_arm_force_loss` | -15% |

Body masses, physics and the net snapshot are unchanged: only the drives (speed, acceleration, hand cap, get-up)
and stamina read the load. Measured by `tests/sim/sim_armor_weight.gd` (gladius, flat floor, 4 s from standing):

| | Naked | Iron set | Before (both) |
| --- | --- | --- | --- |
| Walk | 2.39 m/s | 1.89 m/s | 2.39 m/s |
| Sprint | 4.32 m/s | 3.44 m/s | 4.32 m/s |
| 10 m dash from standing | 2.63 s | 3.25 s | 2.63 s |
| Stamina after a 4 s sprint | 0.48 | 0.07 | 0.48 |

**Plate gaps** (`game/logic/armor_gaps.gd`). Weight alone could not balance plate: a gladius cut passes 8% of
iron plate, every cut on bare skin bleeds, so the naked side lost on blood even when it landed more hits. Now a cut
or thrust that lands within `armor_gap_len` (7 cm) of a limb's end (elbow, wrist, knee, ankle, shoulder, hip), in
the top band of the torso (neck, armpits) or in a helmet's face opening skips `armor_gap_pass` (80%) of a plate
piece's cut and pierce resistance. Plate faces still glance; blunt force, mail and leather are unchanged.

**Iron set v naked, gladius v gladius** (`tools/bot_match.sh --w0=gladius --w1=gladius --a0=<iron set> --a1=` and
swapped, 60 s limit). Wins of the iron side:

| Version | Seeds 2000-2023 (48) | Seeds 3000-3023 (48) | Mean length |
| --- | --- | --- | --- |
| Before (seeds 2000-2011, 24) | 22 of 24 (92%) | - | 17.5 s |
| Weight only, first values | 42 (88%) | - | 26.4 s |
| Weight only, harsh (speed -30%, step 0.08, swing 0.2, hand -50%) | 43 (90%) | - | 30.4 s |
| Gaps only (weight off) | 36 (75%) | - | 22.1 s |
| **Final: weight + gaps** | **29 (60%)** | **31 (65%)** | 30.1 s |

Final over 96 fights: 60 (62.5%), inside the 35-65% band. The same settings move by about 3 wins of 48 between
seed sets, so differences under that are noise. Weight is worth about 12 points on top of the gaps.

## Bots read the armor
`game/logic/armor_read.gd` (`ArmorRead`, tests in `test_armor_read.gd`) gives the CPU brain a read of the foe's armor
from what a player can see: which parts wear plate, the gap points (neck band, face opening, elbows, knees: the
`ArmorGaps` bands, aimed at from the foe's part positions), and each side's armor load. `FighterBrain` uses it three
ways, scaled by the difficulty knob `armor_read` (easy 0.15, normal 0.6, hard 1.0) and drawing from its own random
stream, so fights with no plate and no load gap play exactly as before (the shield rows below did not move):

- A point weapon that picked a plated part thrusts at a gap instead (`GAP_THRUST_CHANCE` 0.65, weighted neck 1.4,
  face 1.0, weapon elbow 0.6, knees 0.3, off elbow 0.25). A spear over a plate cuirass aims at the neck band.
- Head targeting follows the helmet: on plate, blunt weapons hit the head 1.8 times as often (the blow carries
  through), edged swings 0.45 times (they glance).
- A fighter carrying 0.4 load less than its foe (about 8 kg) kites while the foe has stamina over 0.45: it keeps
  0.9 m outside the longer reach (sprinting when inside the foe's reach), for at most 2.5 s, then goes in with a
  committed burst; it goes in at once when the foe whiffs or tires. 2.5 s cooldown between stints.

Tried and dropped: a 7 s kiting stint (the plate fighter walked, not chased, and recovered stamina: 0.6 to 0.8 while
kited) and hit and run (sprint out after every blow: naked side lost more, iron v naked 73-75%, it took ripostes
with no guard up).

**Gap hits** (bot `--hitlog`, hits on plate that found a gap): 63% before, 61% after, iron v naked over 48 fights.
The bands already cover so much of the plate (about 40% of each limb) that aiming at them changes little; the gap
read is a behaviour players can see, not a balance lever.

### Re-measured tables (round 4, seeds 2000-2011 both sides, 24 fights per row)
Before = main (ed9e027 brain, the bot never reads armor); after = the armor-reading brain. `tools/armor_tables.py`
runs every row (`--table=shields|armor|naked`, `--hitlog` for gap hits). Iron v naked is 48 fights (seeds 2000-2023);
the merge of main b4af3cd (arena dressing) gave the same 29/48 before.

| Shield (gladius + shield v longsword, leather) | Before | After | Length after |
| --- | --- | --- | --- |
| shield_round | 8 (33%) OUT | 9 (38%) | 24.5 s |
| scutum | 16 (67%) OUT | 16 (67%) OUT | 26.0 s |
| buckler | 6 (25%) OUT | 6 (25%) OUT | 23.6 s |
| parma | 12 (50%) | 12 (50%) | 23.3 s |
| pelta | 8 (33%) OUT | 8 (33%) OUT | 20.9 s |
| kite_shield | 14 (58%) | 14 (58%) | 23.5 s |
| aspis | 7 (29%) OUT | 7 (29%) OUT | 26.2 s |
| tower_shield | 17 (71%) OUT | 17 (71%) OUT | 25.8 s |

| Piece swapped into the iron set (gladius v gladius) | Before | After | Length before / after |
| --- | --- | --- | --- |
| (iron set v itself) | 12 (50%) | 12 (50%) | 34.1 / 44.8 s |
| helm_murmillo | 13 (54%) | 13 (54%) | 38.4 / 42.3 s |
| helm_thraex | 11 (46%) | 14 (58%) | 42.6 / 41.4 s |
| helm_secutor | 12 (50%) | 13 (54%) | 40.2 / 42.5 s |
| lorica_segmentata | 12 (50%) | 14 (58%) | 40.6 / 40.4 s |
| lorica_squamata | 11 (46%) | 11 (46%) | 34.6 / 40.7 s |
| balteus | 10 (42%) | 7 (29%) OUT | 32.5 / 34.7 s |
| retiarius_arm | 12 (50%) | 9 (38%) | 31.8 / 37.7 s |
| spaulders | 11 (46%) | 12 (50%) | 34.9 / 41.4 s |
| fasciae | 13 (54%) | 13 (54%) | 36.8 / 40.9 s |
| **Iron set v naked (48)** | **29 (60%)** | **30 (62.5%)** | 30.6 / 30.8 s |

Out of the 35-65% band after: scutum 67%, tower shield 71%, buckler 25%, pelta 33%, aspis 29% (all unchanged: these
fights have no plate, so the new brain plays them as before; they need data or shield handling, not armor reads)
and balteus 29% (was 42%: the balteus leaves the chest bare, and the foe's thrusts now go to the open chest rather
than the plate gaps; within about 3 wins of noise, re-check in the next matrix). Plate v plate fights got longer
(iron set mirror 34 s to 45 s) as both sides thrust at gaps instead of swinging.

## Next
- Gaps are bands on the part's own axis, not per-piece art: a piece that covers only the middle of a limb (or the
  galerus set's one arm) has the same gaps as full plate.
- The small shields (buckler, pelta, aspis) sit near 30% and the big ones (scutum, tower) near 70% against the
  longsword; the bots do not use a small shield's speed or the big shields' cover differently.
- Covers text says "both arms" for the galerus set (left arm and right forearm).
- Light fighters still lose on blood to plate (62.5%): a kite does not tire a plate bot that walks instead of
  chasing. A brain that waits out a heavy foe at range (or breaks off when it sprints) would need the plate side to
  chase.
