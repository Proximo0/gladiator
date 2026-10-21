# Bot vs bot refinement round 2

Baseline: round 1 result (`tools/bot_match.sh --matches=24 --shards=3 --seed=5000` at the round 1 close commit).

| metric | baseline | round 2 target |
| --- | --- | --- |
| time-outs | 6 / 24 | at most 3 |
| finishers | 5 (gut 4, run through 1) | at least 5, with at least 3 kinds (behead and skull crush seen) |
| disarms | 57 | 8 to 24 |
| weapons picked back up | not measured | measured; at least half of disarmed bots re-arm |
| armor knocked off | 4 | 5 to 20 |
| self hits | 7 | under 12 |
| stuck_s total | 3.4 | under 10 |
| hits per minute | 75.5 | 50 to 120 |
| explosions | 0 | 0 |

Same rules as round 1. Runs are chaotic (any brain RNG change reshuffles all matches): judge on two seeds
(5000 and 9000) before claiming a target.
