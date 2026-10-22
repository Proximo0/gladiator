# Blood stains on bodies (round 3, task 17)

Blood on a fighter's body is now drawn only by WoundFx (game/fx/wounds): every mark wraps the real skin, outfit or armor
surface in the part's frame. BloodFx keeps its flat stain quads for weapons and anything that is not a tracked
fighter's body part.

## What changed
- `BloodFx.body_marks` (set by MatchPresenter to its WoundFx). With it set:
  - the soak of a bleeding blow (`_hit_stains`) becomes one WoundFx smear (`add_stain`, strength `BloodFx.soak_sev`),
    and only when WoundFx draws no gash or hole for that blow (those carry their own blood halo and trickle) and the
    blow has at least `wound_soak_min` blood points. Pummel and skull-crush finishers soak a full-strength smear.
  - a blood drop landing on a fighter's part (`_process_rays`) becomes a WoundFx smear (`add_drop`): sized from the
    drop's radius (`wound_drop_size`), streaked along its landing speed (WoundMarks smear `stretch`, up to 3:1, same
    area), merging into bigger smears where drops pile up, at most `wound_drop_rate` per fighter per second. Smears are
    evicted first when a part is full, so gashes and holes stay.
- Fresh gashes and punctures read at fight-camera distance: the open slit / hole is `wound_core_scale` wider and the
  wet rim glows (`wound_rim_glow`) for about `wound_rim_glow_s` seconds as it dries.
- A sever or beheading (fighter `gore` signal) puts a blood collar (`wound_stump_sev`) on both cut ends: the stump at
  the joint and the cut end of the part that came off (`WoundFx.stump_ends`).

## Numbers (low quality, tools/perf.sh, software GL: read calls and primitives, not ms)
| run | body stain quads | draw calls mean (max) | primitives mean | fx ms |
|---|---|---|---|---|
| seed 7, bloody point tick 1410, before | (most of 78 loose MeshInstances) | 330.9 (337) | 109,702 | 1.50 |
| seed 7, bloody point tick 1410, after | 0 (30 loose MeshInstances) | 284.6 (290) | 109,589 | 1.52 |
| seed 1002 (match over at tick 421), before | 69 loose MeshInstances | 239.7 (299) | 124,683 | 1.81 |
| seed 1002, after | 42 loose MeshInstances | 223.0 (273) | 128,818 | 1.84 |

Bot fight at 18 s (tests/render/wound_capture.gd, seed 7, `--secs=18`): body stain quads 24 + 84 = 108 before, 0
after; WoundFx shells 15 to 23 (one extra draw per marked mesh); marks 14 to 57 (most are landed-drop smears).

## Renders (docs/renders/body_stains/)
before/after at 1280x720 and 540x960 from the fight camera (`*_cam`, `*_cam_zoom`) and a close-up of the bloodied
fighter (`*_close`); `after_sever_stump.png` (gore_capture `--kind=sever`).
