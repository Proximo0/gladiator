# Bot vs bot refinement round 1

Baseline: `tools/bot_match.sh --matches=24 --shards=3 --seed=5000` at db6bd30.

| metric | baseline | round 1 target |
| --- | --- | --- |
| time-outs | 10 / 24 (8 draws) | at most 3 / 24 |
| zero-hit matches | 1 (seed 5016) | 0 |
| finishers | 0 / 24 | at least 4 / 24 (behead, gut, run through, skull crush seen) |
| disarms | 0 | at least 3 / 24 |
| armor knocked off | 10 | keep 5 to 20 |
| self hits | 32 | under 12 |
| stuck_s total | 42.4 | under 10 |
| explosions | 0 | 0 |
| hits per minute | 45.9 | 50 to 120 |
| ms per tick | 1.80 | under 2.5 |

Rules: measure with the same command (seed 5000) before and after; every claim backed by a bot line or a replay.
Recordings for any FAIL are in out/bot/<seed>.rec.json; `tools/replay.sh <rec> [--tune '{...}']` gives what-ifs.

## Result (round 1 closed)

| metric | baseline | after round 1 | target | met |
| --- | --- | --- | --- | --- |
| time-outs | 10 | 6 (3 draws) | at most 3 | no, carried to round 2 |
| zero-hit matches | 1 | 0 | 0 | yes |
| finishers | 0 | 5 (gut 4, run through 1) | at least 4 | yes |
| disarms | 0 (miscounted) | 57 | at least 3 | yes, now too many: round 2 |
| armor knocked off | 10 | 4 | 5 to 20 | just under: round 2 |
| self hits | 32 | 7 | under 12 | yes |
| stuck_s total | 42.4 | 3.4 | under 10 | yes |
| explosions | 0 | 0 | 0 | yes |
| hits per minute | 45.9 | 75.5 | 50 to 120 | yes |
| ms per tick | 1.80 | 2.08 | under 2.5 | yes |

Changes: bots commit to attacks, seek weapon-specific finishers and aim disarms; finisher window 0.6 with less force
needed at its edge; dazed or downed fighters can be finished; self hits off for 0.5 s after spawn; grab radius 0.6;
blunt head hits daze harder (health_head_ko 0.1); disarms on weapon hits now counted.
