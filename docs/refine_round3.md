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
