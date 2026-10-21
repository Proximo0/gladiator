# Combat feel

Every effect is presentation only (MatchPresenter, FightCamera, HitFx); none touches physics or state hashes. Hit stop is
deliberately not done: the existing finisher slow motion (`match_slowmo_*`, Engine.time_scale in Match) is the only time warp.

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

## Switches
- `feel_shake_scale` (Tuning): 0 turns camera kick, shake and zoom off.
- `FeelOptions.reduced_motion` forces camera motion off; `FeelOptions.rumble_enabled` gates rumble and vibration; `feel_rumble_scale` scales them.
- MenuSettings has no reduced-motion or rumble option yet: the options screen must set these two statics (and save them).

## Checking
`tests/unit/test_feel_logic.gd`, `test_camera_shake.gd`, `test_fight_camera.gd`. Frames: run a seeded bot match, find the first big hit and finisher tick headless, then render with rendering enabled only around those ticks.
