# Bot vs bot refinement round 4

Baseline: the tree after the Houdini art and blood commits (9b206b3), `tools/bot_match.sh --matches=12 --shards=3
--seed=S` for seeds 5000 and 9000, plus one 48-match sample (seed 7000, one process) for the rarer events. The round 3
numbers (126 hits/min, 9 KOs in 24) predate the arena-footwork brain (35547c3): on this tree seed 5000 already sat at
95 hits/min, but KOs were still common and finishers had dropped to 0 in 24.

| item | baseline | round 4 target |
| --- | --- | --- |
| head collider | 0.11 m sphere, 2.3 cm per side wider than the drawn head | matches the art |
| hits per minute | 95.0 / 45.9 | roughly 90-120 |
| KOs | 2 + 4 in 24 (15 in 48) | rarer; more blood loss and finisher endings |
| finishers | 0 + 0 in 24 (6 in 48) | at least 3 per 12 |
| self hits | 4 + 2 in 24 (21 in 48, 14 of them spear) | at most 2 per 12 |

## What was traced

- **Head.** The art AABB (`assets/body/head.glb`, `head_b.glb`, part frame) is x ±0.0874, y -0.14..0.118,
  z -0.114..0.105; below y -0.10 it is the neck stub inside the torso. The sphere reached x ±0.11.
- **KOs.** `health_head_ko` 0.1 per blunt point: one club blow of 10-18 blunt (common at 8-11 m/s) emptied consciousness
  from full, so blunt fights ended as a KO before anyone was in the finisher window (a skull crush needs the foe
  bled or dazed *before* the blow).
- **Finishers.** Logging every hit on a foe inside the window: most land on the guarding forearms; the head and torso
  hits that did land came at 4-9 m/s and fell just short (club head 6.2 blunt vs 7.5 needed, axe gut 9.1 vs 12.6,
  gladius thrust 8.3 vs 11.6).
- **Self hits.** Logged part, contact point along the weapon (`ly`, metres from the grip) and pose for each one. 14 of 21
  were the spear's butt (`ly` -0.27..-0.33: the 0.3 m behind the hand) striking the holder's own upper arms at 6-7 m/s
  while standing and swinging or half-gripping; 3 more were longsword/bat/axe pommels (`ly` -0.13..-0.17) on the
  own upper arm. The rest were real blade hits (falling on the own blade, a low axe swing into the own shin).

## Changes

- `game/fighter/fighter.gd`: the head collider is a convex hull of nine measured rings (`HEAD_PROFILE`, the larger of
  the two head models, so the cosmetic pick never changes physics). The head keeps the old sphere's inertia and a
  centred centre of mass, so joints and drives are unchanged (sims and replays pass as before).
- `game/fighter/fighter.gd`: a two-handed pole (spear, rake) no longer collides with the holder's upper arms (it already
  skipped the forearms); contacts behind the grip (handle, pommel, butt) on the own body are not counted as hits.
- `game/debug/tuning.gd`: `health_head_ko` 0.1 -> 0.04 (a solid club blow dazes into the finisher window; only a huge
  one knocks out). `dmg_finisher_min_scale` 0.25 -> 0.15 and `dmg_finisher_top_scale` 0.5 -> 0.4 (also the
  `DamageModel.DEFAULTS`).
- `tests/unit/test_damage_model.gd`: the finisher threshold test uses 3.5 m/s at the window edge; the plate test now
  checks that a 6 m/s thrust that runs an unarmored dying foe through is stopped by an iron cuirass (an 8 m/s one now
  goes through, intended with the lower scale).

## Result

| seed 5000 (12) | before | after |
| --- | --- | --- |
| outcomes | blood_loss 10, ko 2 | blood_loss 6, ko 3, gut 1, run_through 1, time 1 |
| hits per minute | 95.0 | 101.0 |
| finishers | 0 | 2 |
| self hits | 4 | 1 |
| disarms / rearms | 10 / 6 | 9 / 8 |
| knockdowns, getup fails | 12, 0 | 4, 0 |
| stuck, explosions | 0, 0 | 0, 0 |
| mean match length | 28.3 s | 28.5 s |

| seed 9000 (12) | before | after |
| --- | --- | --- |
| outcomes | blood_loss 7, ko 4, time 1 | blood_loss 7, gut 1, run_through 1, skull_crush 1, time 2 |
| hits per minute | 45.9 | 89.8 |
| finishers | 0 | 3 |
| self hits | 2 | 2 |
| disarms / rearms | 5 / 2 | 7 / 4 |
| knockdowns, getup fails | 2, 0 | 15, 0 |
| stuck, explosions | 0, 0 | 0, 0 |
| mean match length | 23.2 s | 29.1 s |

| seed 7000 (48, one process) | before | head_ko only | after |
| --- | --- | --- | --- |
| KOs | 15 | 8 | 7 |
| finishers | 6 (behead 1, gut 5) | 9 | 14 (behead 5, skull crush 4, gut 4, run through 1) |
| time-outs | 9 | 11 | 11 |
| self hits | 21 (14 spear) | - | 5 (0 spear) |
| hits per minute | 70.2 | - | 67.5 |

Over all 72 matches: KOs 21 -> 10, finishers 6 -> 19 (3.2 per 12), self hits 27 -> 8 (1.3 per 12).

## Open

- Seed 5000 still shows 3 KOs, and one of them (5001) is a fighter fainting from blood loss: consciousness is capped by
  blood and drops under 0.2 at about 2.7 L, so a slow bleeder sits in "ko" for the 2.5 s hold before reaching the
  2.5 L death line. The judge calls that `ko`; it is really blood loss (`FighterHealth.knocked_out` / `MatchJudge`).
- The remaining self hits are real blade hits: a fighter falling or getting up onto its own blade, and a low right-side
  axe swing (aim about 750, -450) into the own shin (47 damage, seed 7000 sample). A brain limit on low swings for
  short heavy weapons would be the next step.
- Helmets are drawn from `FighterArt.ARMOR_FIT` (head sphere r 0.112) and now sit about 2.5 cm outside the head
  collider at the sides; a blow that clips only the drawn helmet rim does not land.
- Finishers per 12 vary 2-4 between 12-match samples; the 48-match sample is the steadier number.
