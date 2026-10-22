# CPU difficulty

`AiDifficulty` (`game/ai/ai_difficulty.gd`) is a table of human-like handicaps for `FighterBrain`. The personality dict
takes `"difficulty": "easy" | "normal" | "hard"` (missing or unknown means normal). Normal is the identity: it changes
nothing (`test_normal_is_the_identity`). `MenuState.cpu_difficulty` (session) feeds `to_config()`, which puts it in the
CPU's personality; the loadout screen has a Difficulty picker above Style.

## Knobs (all in the table, documented there)
Reaction delay (scale and floor), aim noise and flat aim error, hand speed cap (`aim_slew`, aim units per tick), commit
rate (aggression shift, pause between attacks, attack chance), guard reflex (skip chance, lift, hand speed), finisher
and opening notice rates, footwork (venue lean, wall pinning), stamina rest threshold, swing length, target choice
(armor weighting, vitals), riposte and punish chances. Rolls use a separate RNG so normal draws what it always drew.

## Measured (bot_match, 12 matches, seed 5000, X vs normal, X on each side in turn, 24 games)
| level | X wins | draws | X losses | hits/min | note |
| --- | --- | --- | --- | --- | --- |
| easy | 6 | 4 | 14 | 90 / 81 | slow hand (cap 0.022), long reaction, wild aim; matches run 30-45 s |
| hard | 9 | 2 | 13 | 93 / 111 | not reliably better than normal |

Findings from a larger sweep (30 matches per side): a brain's reaction time, guard, aim error and swing speed barely move
the outcome, because fights are decided by the physical hand and by loadouts. Only the hand speed cap separated
levels (easy 0.033: 18 wins in 60). Capping normal's hand (0.06-0.07) made hard win about 55-65%, but it changes
normal, so it was not kept. Open: hard has 4-5 self hits per 12 matches; a physical edge (not a brain one) is needed
for a Hard that clearly beats Normal.

Run it: `tools/bot_match.sh --matches=12 --shards=1 --seed=5000 --difficulty=hard --side=0` (`--side` is the level's side;
the other is normal).
