# Low-tier wound cap and 18 s capture seeds (round 5, task 30)

Seed 12, gladius v club, `tests/render/wound_look_capture.tscn` at quality 0, 1280x720 and 540x960 (renders in
`docs/renders/low-wounds/`, before_ / after_). Before = main 9b6889a.

| What | Before | After |
| --- | --- | --- |
| Marks per part, low tier | 6 (const) | `wound_cap_low` Tuning row, default 10 (4 to 12); medium and high stay 8 |
| Shader mark arrays and loops | 8 | 12 (loops break at `count`, so a part with few marks costs the same) |
| Fight, marks dropped from a full part (seed 12, 17.5 s) | side 0: 1, parts full: 1 + 3 | 0 dropped, 0 full parts |
| Fight camera draw calls (low) | 197 | 197 |
| tools/perf.sh q0 draw calls / decals / drops | 213 / 115 / 342 | 213 / 115 / 342 (0.0%) |
| tools/perf.sh q0 frame p50 (software GL, noise) | 59.1 ms | 60.7 ms |
| Texture memory | unchanged: only uniform arrays grew (12 x 5 vec4 per marked part mesh) | |

Capture seeds: `tools/wound_seed.sh [--secs=18] [--from=1] [--count=24]` runs the capture's loadouts headless and
keeps seeds whose fight is still on at the end of the window with at least 14 hits and both sides hit (24 seeds: 5
kept, best 12, 7, 23, 20, 17), best first. Pass the best to the capture with `--seed=`.
