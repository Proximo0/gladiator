# Spear balance (CPU)

The CPU with a spear lost every fight (0 of 10 against the longsword). Its hits were shaft touches averaging 0.34
damage, with almost no point contacts.

## Mechanism (traced in a lab: spear brain against a standing dummy)
- Aim: the sword-sized aim map put the blade line 0.8 to 1.25 m off the chest (the median closest tip pass). A long
  pole turns a small hand offset into a large one at the foe, and the blade's rest pitch depends on hand height.
- Reach: in the pole stance the arms are already at full reach (`guard_target` clamps the hand to the shoulder's
  reach), so THRUST moves the hand about 5 cm. The point travels only as fast as the body steps in.
- Speed: contacts under `damage_min_speed` (3 m/s) do nothing. Walking speed is 2.5 m/s, and a fighter needs about
  20 ticks of sprinting to pass 3 m/s. Thrusts started at 2.4 m touched the chest and did nothing.
- Range: from closer than about 2.2 m (pelvis to pelvis) the levelled point is already past the foe, and only the
  shaft can touch.
- Foes stood still: against a spear, the other weapons' brains sat in guard at about 3 m (out of their own reach, so
  guard footwork never ran) and waited for the next thrust.

## Changes (`game/ai/fighter_brain.gd`)
- Pole servo (`_pole_servo`, `pole_miss`): each tick the aim moves by a share of the real blade line's miss
  (hand to tip, from the debug frame) at the foe's chest. The blade stays level (SWING held) inside 4.5 m.
- Stance band 2.9 to 3.3 m. Inside 2.3 m the spear gives ground and never thrusts.
- Thrust: from 2.75 to 3.4 m only, let go once the blade line passes within 0.18 m of the chest (or after 10 ticks).
  It is a 28-tick run-up (sprinting while stamina is above 0.2) with the servo still steering, and it stops driving
  inside 2.2 m. Recovery keeps the point in line and backs off to the band. Spears never feint. The plan's aim noise
  becomes a point offset (`SPEAR_NOISE_M`).
- Foes of a spear: while guarding out of their own reach, they close on a slant past the point instead of standing.
  This only runs when the foe holds a spear, so other matchups do not change.

## Results (bot_match, both sides, 20 matches per side per set)
| Matchup | Before | After (seeds 2000/3000) | After (seeds 4000/5000) |
| --- | --- | --- | --- |
| spear vs longsword, spear wins | 0/10 (side 0), 1/10 (side 1) | 22/40 (55%) | 18/40 (45%) |
| spear vs axe, spear wins | 0/10 | 23/40 (58%) | 18/40 (45%) |
| spear point-contact share | 0 to 3% | 8 to 9% | 7 to 9% |
| spear damage per hit | 0.34 to 1.13 | 1.48 to 1.76 | 1.22 to 1.55 |
| self hits (both sides) | 1 in 30 matches | 2 in 80 | 1 in 80 |

Longsword vs axe (seeds 2000 to 2009) is 4:6 both before and after (hit counts within Jolt's run-to-run noise).

Sensitivity: without the sprint in the run-up, the spear won 40% against the longsword and 65% against the axe. With
the sprint but no slant step for its foes, it won 50% and 72%.

## Tuning constants to promote
`SPEAR_SERVO_GAIN`, `SPEAR_ALIGN_TOL`, `SPEAR_STRIKE_MAX`, `SPEAR_THRUST_MIN`, `SPEAR_HOLD_MIN`, `SPEAR_HOLD_MAX`,
`SPEAR_MIN_RANGE`, `SPEAR_LUNGE_MIN` and `SPEAR_STRIKE_TICKS` are consts marked `# TUNING:` in fighter_brain.gd.
