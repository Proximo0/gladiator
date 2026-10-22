# Wound and shadow readability (round 4, task 24)

Measured on a seeded 18 s bot fight (seed 12, gladius v club, `tests/render/wound_look_capture.tscn`), at
1280x720 high and 540x960 low. Renders: `docs/renders/wound-look/` (before_ / after_).

| What | Before | After |
| --- | --- | --- |
| Smear outline | value noise of the angle at 3x and 9x (amplitude 0.7, a seam at the back): maple-leaf stars | three whole harmonics (2, 3, 5) at `wound_smear_lobe` 0.26, a little 2D edge noise, sparser drops outside the blot: soft lobed blots (outline radius within 1.75x, at most 5 lobes; unit test) |
| Fist and weapon coat blots | fine 3D noise at 60/m, read as stars on a fist | 24/m at half the depth |
| Marks dropped from a full part in the fight | high 14, low 15 | high 0, low 2 (smears that made room for new cuts) |
| Sever ring | a lobed smear at the joint, hard to see at 2.5 m | a RING mark: a wet band (`wound_ring_band` 6 cm) all round the stump and the cut end, a dark torn line at the cut, runs off its edge, glowing for `wound_ring_glow_s` 12 s |
| Foot contact blob | round, radius 0.2 m | an oval along the foot (`sand_contact_foot_aspect` 2, same area) |
| Blob inside the sun shadow, high (arena-lit bench `tests/render/contact_sun_check.tscn`) | 3.0 luminance (plain shadow 36.9): near black | 23.3 |
| Blob in full sun, high (same bench) | 43.1 | 41.7 |
| Shadowed sand by the feet in the fight (mean luminance) | 38.8 | 54.5 |
| Fight camera draw calls / primitives, high | 282 / 236089 | 282 / 236089 |
| Fight camera draw calls / primitives, low | 197 / 126733 | 197 / 126733 |

Full-part rule (WoundMarks): a new mark drops the oldest mark ranked below it (smear < bruise < gash, puncture <
ring); when nothing ranks lower it deepens the nearest mark of its kind (by `FULL_DEEPEN` of its strength), or
leaves no mark (a smear on a part full of cuts). So marks never pop off once a part is full of wounds, at the cost
of late splashes on a full part showing as an older blot growing.

Sun fade (GfxQuality.CONTACT_SUN_FADE, high only): Compatibility draws the shadowed sun in a pass of its own, so the
sand's light() can only scale the sun's light. The blob keeps `sand_contact_sun_ambient` (0.35) of itself on the
ambient (EMISSION) and cuts the sun `sand_contact_sun_gain` (1.65) times harder, so it reads as before in full sun
and fades to a light grounding in the sun's shadow. Low and medium darken the albedo as before.
