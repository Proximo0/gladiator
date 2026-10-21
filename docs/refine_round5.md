# Bot vs bot refinement round 5

Baseline: the tree at the start of round 5 (`tools/bot_match.sh --matches=12 --shards=1 --seed=S`). Caveat: the seed 9000
baseline ran while the judge/brain edits were being made, so it may include them.

## Changes

- `game/match/match_judge.gd`: a "ko" end whose loser holds under `FAINT_BLOOD_L` (2.75 L; the blood cap puts
  consciousness under 0.2 at 2.7 L) is reported as `blood_loss`. A blow knock-out with plenty of blood stays `ko`.
- `game/fighter/fighter_art.gd`: the helmet is `helm_mesh`, a shell built from `Fighter.HEAD_PROFILE` pushed out 6 mm
  (`HELM_CLEAR`), from y -0.03 up over the crown, closed underneath. It replaces the r 0.112 ellipsoid (2.5 cm proud).
  Render: `/tmp/r5/helmets.png` (leather and iron, front and side, plus the bare head).
- `game/ai/fighter_brain.gd`: axe and club aim floor eases from -0.75 to -0.3 as aim x goes 0.35 to 0.6
  (`heavy_low_limit`), so the head does not swing through the own shin; leg attacks on a foe in front keep -0.75.
- Tests: `test_match_judge.gd` (faint is blood_loss, blow ko stays ko), `test_fighter_brain.gd` (limit, axe and club
  never aim below it).

## Result

| seed 5000 (12) | before | after |
| --- | --- | --- |
| outcomes | blood_loss 8, ko 2, run_through 1, time 1 | blood_loss 6, gut 2, ko 1, run_through 1, skull_crush 1, time 1 |
| hits per minute | 110.4 | 107.3 |
| finishers | 1 | 4 |
| self hits | 1 | 0 |
| mean match length | 27.4 s | 29.5 s |

| seed 9000 (12) | before | after |
| --- | --- | --- |
| outcomes | blood_loss 8, run_through 1, skull_crush 1, time 2 | blood_loss 6, gut 2, run_through 1, time 3 |
| hits per minute | 89.5 | 91.8 |
| finishers | 2 | 3 |
| self hits | 0 | 2 |
| mean match length | 28.8 s | 31.8 s |

Checks: 389 unit tests pass, lint problems=0, sims 15/15.

## Open

- Seed 9000 shows 2 self hits (not traced; the brain change shifts the whole match, so the samples diverge).
- The remaining seed 5000 ko is a blow knock-out or a faint above 2.75 L; not traced per match.
