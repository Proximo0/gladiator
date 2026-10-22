# Combat feel

Every effect is presentation only (MatchPresenter, FightCamera, HitFx, FeelDirector); none touches physics or state
hashes. Hit-stop is a presentation clock, not a physics pause; the end-of-match slow motion (Engine.time_scale in Match,
mirrored to online clients by the snapshot) is the only real time warp.

## Audit (before this step)
- Slow motion on a finisher or KO: `match_slowmo_scale` / `match_slowmo_s` (Match).
- Sound: SfxDirector layers by impact energy; steel on steel already plays clang and ring, plates clank; crowd reacts.
- Blood: BloodFx, sand sprays on low blows.
- Camera: follow / orbit / wide framing, no impact response, follow mode could lose a far opponent.

## Added
Impact (`FeelLogic.impact`) is 0..1 from the hit's energy and damage points (`feel_impact_energy_ref`, `feel_impact_total_ref`); a finisher reads at least 0.9. Each effect has a floor (`feel_*_min`) so taps stay quiet.
- Camera kick toward the blow (damped spring, `CameraShake`), shake and roll, FOV punch (`feel_zoom_deg` on finishers, small `feel_zoom_hit_deg` on hard hits). Hits on the opponent count 80 percent.
- Framing: both fighters' feet and heads must stay inside `feel_frame_margin` of the field of view. The camera pulls back along the view line (at most `feel_frame_pull_max`), slides to a side-on shot from the inner side when the wall squeezes the follow shot, and widens the lens up to 18 degrees as a last resort.
- Hit flash: additive overlay on the struck part's meshes (weapon on a weapon hit) for `feel_flash_s`.
- Sparks (CPUParticles3D pool, fixed seeds, brief light on medium and high): steel against steel or aluminium weapons, steel against plate or mail. Count `feel_spark_max` x impact x GfxQuality.SPARK_MULT. Extra ring_steel layer for steel on plate.
- Rumble: Input.start_joy_vibration for the attacker (55 percent) and the victim; Input.vibrate_handheld on Android/iOS for the human side. One pad belongs to the human side; two or more map pad i to side i. Skipped in scripted runs.

## Hit feel (ramp/hit-feel)
FeelDirector (`game/fx/feel/`, fed by `MatchPresenter._feel`) adds, per hit class (`HitStopLogic.hit_class`: light,
medium, heavy, clash, sever, finisher; taps under `feel_hitstop_min` get nothing):
- Hit-stop (HitStop + HitStopLogic): the fighters' meshes are drawn from a short pose history `lag` seconds behind
  physics. A hit holds the shown pose at `feel_hitstop_rate` for 35 to 95 ms by impact (sever 120, finisher 160,
  clash x0.7, glance x0.6), then it catches up at 2.6x. Holds take the longer of two, never add; `lag` is capped at
  `feel_hitstop_lag_max`; a debt draining over `feel_hitstop_budget_tau` shrinks a flurry's holds (finishers excepted).
  Bodies are never moved: each physics tick first puts the visual children back at rest (physics priority -1000), so
  nothing in the tick reads a lagged mesh. Inputs keep steering the real weapon during a hold (at most 150 ms behind).
- Screen punch (ScreenPunch, layer 8 under the aim aid and HUD): radial blur and colour split toward the impact and a
  flash brightest at the impact, from impact `feel_punch_min` up; finishers x1.3 and longer. One hidden full-screen rect
  costs nothing idle. Medium and high read the screen once with 5 or 8 taps (one tap for the grade alone); low and
  reduced motion use an overlay that never reads the screen (flash and vignette only, flash halved).
- Finisher cinematic (FinisherCine): behead, gut and run through dip to `feel_cine_scale` for `feel_cine_hold_s` and
  ease back over `feel_cine_ramp_s` (Match drives Engine.time_scale from the same curve; skull crush and KO keep
  `match_slowmo_*`). The crowd and effects buses are low-passed through the hold and open with the ramp, a crowd roar
  fires as time returns, a procedural bass drop (FeelTones, on Master) lands on the blow, and the screen desaturates
  everything but blood under a vignette. The finale camera is started by the presenter as before.
- Heavy hits from `feel_bass_min` get a short sub-bass thump. RumblePatterns gives each class its own rumble (light
  tick, heavy thump and roll, clash double buzz on the light motor, sever thump and wet pulses, finisher thump, silence,
  swell at the roar) and a one-motor phone version; FeelOptions.rumble_enabled and `feel_rumble_scale` gate both.
- RealClock: real seconds for a frame. Godot scales a frame's delta by the time scale in force when the frame began,
  so the first slow-motion frame must be divided by the old scale.

Measured: `tests/sim/sim_hit_feel.gd` (hold per class from bot fights, longest stall, physics-at-rest probe),
`tests/perf/feel_cost.tscn` (script cost per frame), `tests/render/feel_capture.tscn` (before/after frames,
docs/renders/ramp-hit-feel/).

## Switches
- `feel_shake_scale` (Tuning): 0 turns camera kick, shake and zoom off.
- `FeelOptions.reduced_motion` forces camera motion off; `FeelOptions.rumble_enabled` gates rumble and vibration; `feel_rumble_scale` scales them.
- MenuSettings sets `reduced_motion` and `rumble` (FeelOptions) from the options screen.

## Checking
`tests/unit/test_feel_logic.gd`, `test_camera_shake.gd`, `test_fight_camera.gd`. Frames: run a seeded bot match, find the first big hit and finisher tick headless, then render with rendering enabled only around those ticks.
