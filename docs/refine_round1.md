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
