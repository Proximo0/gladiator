# Rake balance (owner: "a little OP, I couldn't lose with it")

Measured with `tools/bot_match.sh --matches=10 --seed=2000 --w0=rake --w1=<weapon> --armor=leather --hitlog [--wide=0]`
(forced loadouts, equal leather armor, 60 s limit; `--wide=0` makes the rake side a broad horizontal sweeper, the human proxy).
Wins are rake-wins/opponent-wins out of 10 (draws on timeout counted separately).

## Traced cause
Per hit the rake did far more damage than its tier-1 peers, and it landed more hits per minute:
- Pierce share. `pierce_factor` 0.25 (a quarter of the spear's 1.0) on a 2.5 kg effective-mass swing gave 4.5 to 9 pierce
  damage per tine hit, 60 to 70 percent of all rake damage. Tine contact is generous (last 0.15 m of the tip, any upward or
  sideways motion), so 25 to 55 percent of rake hits counted as "point". A gladius cut averages 3.3 to 4.7 per hit.
- Blunt share. `blunt_factor` 0.5 (half a bat's) from a 1.3 kg pole with its balance point at 0.9 m.
- Rate. 1.6 m reach with a 0.36 m wide head: 40 to 90 hits/min against 15 to 30 for the opponent.
Before: rake 7.0 to 13 damage per hit (fists 1.6, bat 5.1, club 5.1, gladius 4.1, longsword 7.6, axe 5.3).

## Fix (data only, plus the visual head width)
| key | before | after |
| --- | --- | --- |
| blunt_factor | 0.5 | 0.28 |
| pierce_factor | 0.25 | 0.05 (a tine hit still bleeds: about 0.003 per hit) |
| mass | 1.3 | 1.7 (slower tip) |
| length | 1.6 | 1.45 |
| balance_point | 0.9 | 0.8 |
| head crossbar (weapon.gd) | 0.36 m, 5 tines | 0.26 m, 5 tines |

## Before / after (rake wins : opponent wins of 10)
| opponent | before | after | before, wide sweep | after, wide sweep |
| --- | --- | --- | --- | --- |
| fists | 10:0 | 10:0 | 10:0 | 10:0 |
| bat | 9:1 | 5:5 | 9:1 | 7:3 |
| club | 5:5 | 7:2 (1 draw) | 7:3 | 5:5 |
| gladius | 9:1 | 6:4 | - | - |
| longsword | 5:5 | 2:8 | 4:6 | 5:5 |
| axe | 8:2 | 2:8 | 6:4 | 3:7 |
| spear | 10:0 | 10:0 | 10:0 | 10:0 (v2: 10:0) |

Rake damage per hit, normal style (before / after): vs fists 7.0 / 2.1, bat 9.9 / 3.2, club 11.8 / 2.4, gladius 11.0 / 2.6,
longsword 7.9 / 3.3, axe 11.0 / 2.5, spear 12.1 / 3.3. Hits per minute (rake): 40 to 80 before, 45 to 80 after (it is
still the reach weapon). Tip speed at contact 6 to 7 m/s, effective mass 2.4 to 2.8 kg. Rake hits: about 30 to 55 percent
point, rest blunt; blood per hit 0.002 to 0.005 (was 0.02 to 0.04), so a tine hit still draws blood but no gut or sever.

## Known gap: the spear
The rake still beats the CPU spear 10:0, and that is not the rake: the spear loses to everything (spear vs club 0:6 with 4
draws, vs longsword 0:10, vs axe 0:10). Its hits average 0.4 to 0.5 damage with 0 percent point contact and 4.5 m/s tip
speed, so the CPU spear lands shaft touches, not thrusts. Fixing the spear (contact classification or thrust brain) is a
separate task; until then "rake loses to spear" cannot be reached by tuning the rake.
Gladius is a short tier-2 sword and the rake still wins 6:4; lowering it further would break bat/club parity.

## Tests
`tests/unit/test_damage_model.gd` (tines: weak pierce, still bleeds, weaker than a club), `tests/unit/test_combat_data.gd`
(new mass and length, pierce under 0.2 of the spear's).
