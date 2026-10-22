# Gut spill

A gutting (`gut`) or run-through (`run_through`) is now a deliberately over-the-top spill (presentation only), in the
spirit of the beheading fountain (`docs/beheading_fountain.md`). It is all driven by `BloodFx.on_gore`, so it also
plays online: the host sends gore events and the client re-emits them on the fighters (`net_client_driver.gd`), where
`BloodFx` is connected exactly as offline. Nothing is added to the wire or the fighter state.

- Gush: kind `gut` runs the fountain machinery (`_emit_fountain`) with its own numbers: `gut_streams` jets leaving along
  the wound normal (`gut_up_bias` toward up), heartbeat pulse and gush from `fountain_*`, speed scaled by `gut_v_scale`,
  `gut_rate` droplets/s/jet, `gut_hold` s at full then a taper to `gut_dur`, and a pool poured under the wound
  (`gut_pool`) plus sand stains. Like the fountain it never reads or writes the fighter's blood.
- Run-through: the entry gets the same gush, the exit (`gut_exit_depth` behind it, along `-normal`, kind `gut_exit`) gets
  `gut_exit_streams` faster jets and a smaller pool, both sides get a big burst and ground splash, strings spill from
  the front and a few organ chunks are flung out of the back.
- Guts: `GutRope` (pure) is a chain pinned at the wound: position based constraints, gravity, damping, sand collision
  (via `BloodFx._height_fn`), a pay-out phase (`gut_pay_time`) where it grows from a stub and is shoved out
  (`gut_eject`, `gut_push`), sand friction, and sleep when calm (`gut_sleep_*`); it wakes if the body it hangs from moves.
  The wound end is a point on the torso node, so strings swing with the staggering body and trail after it when it falls.
  `GutSim` (pure) owns the strings and the organ chunks (ballistic, bounce `gut_bounce`, sleep), caps them
  (`gut_max_ropes`, `gut_max_blobs`, oldest dropped) and writes a MultiMesh buffer (one fat ellipsoid per link, links
  alternate in thickness so they read as sausages; the first links are blood coated).
- Mess: when a string or chunk first lands, `BloodFx._update_guts` adds a decal pool, a sand stain (palette slot as the
  owner byte) and a few droplets (`gut_smear`); hanging tips drip for `gut_drip_time` s (`gut_drip`/s).
- Colour: `BloodPalette.gut_color` (flesh washed toward pink) and `organ_color` (flesh darkened, purple lean), so the alien
  gets ichor-tinted guts. Colours per palette slot are cached in `BloodFx._gut_rope_cols/_gut_blob_cols`.
- Budgets: strings per spill `gut_ropes` x `BloodMath.gut_mult` (0.67 / 1 / 1.34), points per string `gut_segs` x
  (0.67 / 1 / 1.2), caps x (0.5 / 1 / 2). Jets scale like the fountain. Sleeping strings cost nothing per frame and the
  buffer is re-uploaded only when something moved.

All numbers are in `Tuning` (group "Blood", `gut_*`). Unit tests: `test_blood_gut_rope.gd`, `test_blood_gut_sim.gd`,
`test_blood_fx.gd` (gush, run-through, quality, slot), `test_blood_math.gd`.
