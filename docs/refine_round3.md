# Bot vs bot refinement round 3

Baseline: round 2 result (seeds 5000 and 9000, `tools/bot_match.sh --matches=24 --shards=3 --seed=S`).
Round 3 fixes the fighter-side problems the bots exposed, then re-checks every round 1 and 2 target.

| item | baseline | round 3 target |
| --- | --- | --- |
| re-arms after a real disarm | 3-5 / 31 | at least half, by reaching or kneeling to the ground (GRAB while crouched), not a huge radius |
| stamina stuck at 0 (fighter holding a heavy weapon at rest) | seeds 5007, 9008, 9019 | stamina recovers at rest with any weapon; no fighter spends over 10 s at 0 |
| fighter can't get up (seed 5007, side 0, ticks ~800-3300) | yes | getting up succeeds within 3 tries on full legs |
| disarm stat | counts crippled-arm drops | `disarms` (knocked out of hand) and `arm_drops` (arm too hurt) counted apart |
| all round 1 and 2 targets | met | still met on both seeds |

## Result (round 3 closed, grab_radius 0.4)

Seed 5000: re-arms 8 of 12 disarms, arm drops 14 counted apart, longest time at 0 stamina 0.0 s, get-up fails 0,
time-outs 1, finishers 4 (behead, run through, skull crush x2), disarms 12, armor off 14, self hits 5, stuck 0,
explosions 0, 125.9 hits per minute, 1.93 ms per tick. Seed 9000 (worker run, radius 0.4): re-arms 11 of 18,
self hits 11, 80.8 hits per minute, every target met.

Open for the next rounds: hits per minute sits just over 120 on seed 5000 with 9 KOs in 24 (matches average 23 s;
possibly head dazes too strong at health_head_ko 0.1); spear matches cause most self hits; fresh-process runs of the
same seed can still differ slightly (disarms 14 vs 12).
