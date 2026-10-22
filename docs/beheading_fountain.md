# Beheading fountain

A beheading is now a deliberately over-the-top fountain (presentation only). `BloodFx.on_gore` for kind `behead`
starts a `"behead"` spurt in fountain mode (`_BfSpurt.fountain`, `BloodFx._emit_fountain`) plus a small
`"fountain_head"` trail anchored to the severed head.

- Jets: `fountain_streams` (5) jets leave the neck stump, anchored to the torso so they follow the staggering body. Each
  is the neck axis turned `fountain_up_bias` toward world up, leaning `fountain_fan` with `fountain_wobble` sway, the
  bunch circling at `fountain_swirl` (`BloodMath.fountain_dir`).
- Pulse: `fountain_bpm` heartbeat (`BloodMath.fountain_pulse`, floor `fountain_pulse_floor`); exit speed
  `fountain_v_min..fountain_v_max` follows the beat; a first-second gush (`fountain_gush`). Strength is
  `BloodMath.fountain_envelope`: full for `fountain_hold` s, then tapers to zero at `fountain_dur`.
- Mess: fat droplets (`fountain_drop_scale`), mist puffs per beat (`fountain_mist`), a pool poured under the body
  (`fountain_pool` presentation litres/s into the decals, and a sand stain every 0.25 s with the fighter's palette slot).
  The existing behead burst and ground splash are unchanged. The head trails a single jet for half the duration.
- Gameplay: it never reads the fighter's blood (a normal spurt stops at `blood <= blood_death`, which a beheaded fighter
  is usually at) and never writes anything. Droplets carry the fighter's palette slot, so the alien bleeds ichor and the
  sand owner byte is the same one the other spurts use.
- Budgets: one spurt slot (of `MAX_SPURTS`), at most `fountain_emit_cap` droplets per frame, rate times
  `BloodMath.rate_mult(quality)`, jet count times `FOUNTAIN_STREAMS[quality]` (3 / 5 / 6 jets at quality 0 / 1 / 2), and emission falls to zero as free droplet slots drop under `fountain_headroom` of the pool
  (`BloodMath.fountain_headroom`).

All numbers are in `Tuning` (group "Blood", `fountain_*`). Unit tests: `test_blood_math.gd` (envelope, pulse, streams,
headroom, direction) and `test_blood_fx.gd` (runs with blood below the death line, quality scaling, palette slot).
