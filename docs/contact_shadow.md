# Contact shadows (grounding blobs)

Fighters floated on low, where the sun shadow is one coarse split. The sand shader now darkens the sand under each
planted foot and under the pelvis (`game/logic/contact_shadow.gd`, `game/sand/sand_floor.gdshader`). MatchPresenter
packs the blobs once a frame (`_contact_shadows`, end of `_process`); SandSurface.set_contacts uploads them with one
bounding circle, outside which the shader skips the blob loop. On at every quality.

- Foot blob: radius `sand_contact_foot_r` (0.2 m), darkening `sand_contact_dark` (0.6) when planted, fading out by
  `sand_contact_foot_h` (0.3 m) above `sand_contact_foot_rest`.
- Pelvis blob: radius `sand_contact_body_r` (0.5 m), darkening `sand_contact_body_dark` (0.5) at the sand, gone at
  `sand_contact_body_h` (1.6 m): a standing fighter gets a faint wide pool, a fallen one a dark bed.
- Radii grow by `sand_contact_spread` (0.8) per metre of height. Up to 8 blobs (2 fighters x 3 used).

## Cost (4-core box, software GL, 1280x720)

`tools/perf.sh --res=1280x720`, main 2de5554 vs branch (seed 1002, same window):

| quality | frame ms before | after | draw calls | presenter script ms |
|---|---|---|---|---|
| low | 124.4 | 117.1 | 240 / 240 | 0.02 / 0.07 |
| high | 428.1 | 429.1 | 349 / 349 | 0.02 / 0.07 |

Software-GL frames swing by more than the effect, so `tests/perf/contact_bench.tscn` renders the sand alone,
alternating blobs off/on in 16 blocks in one process (6 live blobs):

| quality | view | wall ms off | on | delta |
|---|---|---|---|---|
| low | top-down, bound fills the screen (worst) | 45.85 | 45.99 | +0.14 (+0.3%) |
| low | fight-camera distance | 57.34 | 57.40 | +0.06 (+0.1%) |
| high | top-down | 109.47 | 109.25 | -0.2 (noise) |
| high | fight-camera distance | 187.43 | 191.89 | +4.5 (+2.4%, noise band) |

Without the bounding circle the low top-down case cost +3.2 ms (+7%) of llvmpipe sand fill. With it the extra fill is
within noise, far under the task's 0.3 ms budget on a real GPU (llvmpipe is much slower than a phone GPU per
fragment), plus 0.05 ms of script per frame. So it stays on at low.

## Captures

`docs/renders/contact_shadow/before_after_*.jpg`: the same frozen frame with blobs off (left) and on (right),
seed 21, from `tests/render/contact_shadow_capture.tscn` (fight camera and a low close camera, 1280x720 and 540x960,
low and high).
