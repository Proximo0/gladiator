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

## Result (round 2 closed)

| metric | 5000 | 9000 | target | met |
| --- | --- | --- | --- | --- |
| time-outs | 1 | 1 | at most 3 | yes |
| finishers | 5 (behead 2, gut 1, skull crush 2) | 8 (4 kinds) | at least 5, 3 kinds | yes |
| disarms | 17 | 14 | 8 to 24 | yes (includes crippled-arm drops) |
| re-arms | 3 / 31 | 5 / 31 | half | no: hand can't reach ground props (lowest 0.82 m vs radius 0.6) |
| armor off | 11 | 14 | 5 to 20 | yes |
| self hits | 8 | 6 | under 12 | yes |
| stuck_s | 4.1 | 0 | under 10 | yes |
| hits per minute | 104 | 84 | 50 to 120 | yes |

Carried to round 3 (fighter side): ground reach for pickups, stamina stuck at 0 while holding a heavy weapon,
a fighter that can't get up (seed 5007), split disarms from crippled-arm drops in the stats.
