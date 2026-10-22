extends "res://game/debug/tuning/tuning_replay.gd"
## Tuning rows of the "Feel" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_FEEL and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_FEEL: Array = [
	["feel_shake_scale", 1.0, 0.0, 2.0, 0.05, "Feel", "Master scale of camera kick, shake and zoom punch. 0 turns them all off (reduced motion forces 0)."],
	["feel_impact_energy_ref", 90.0, 10.0, 400.0, 5.0, "Feel", "Hit energy (J) at which the impact reads about 63 percent."],
	["feel_impact_total_ref", 25.0, 5.0, 100.0, 1.0, "Feel", "Damage points at which the impact reads about 63 percent."],
	["feel_shake_min", 0.15, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does no camera kick or shake."],
	["feel_kick_m", 0.14, 0.0, 0.6, 0.01, "Feel", "Camera kick distance at full impact, m (toward the blow)."],
	["feel_kick_freq", 16.0, 6.0, 40.0, 0.5, "Feel", "Spring stiffness of the camera kick, rad/s."],
	["feel_shake_m", 0.035, 0.0, 0.2, 0.005, "Feel", "High-frequency shake amplitude at full impact, m."],
	["feel_shake_roll_deg", 1.6, 0.0, 6.0, 0.1, "Feel", "Camera roll shake at full impact, degrees."],
	["feel_shake_decay", 7.0, 1.0, 20.0, 0.5, "Feel", "How fast shake dies away, 1/s."],
	["feel_zoom_deg", 7.0, 0.0, 20.0, 0.5, "Feel", "Field-of-view punch-in on a finisher, degrees."],
	["feel_zoom_hit_deg", 1.2, 0.0, 6.0, 0.1, "Feel", "Field-of-view punch-in on a full-impact ordinary hit, degrees."],
	["feel_zoom_decay", 5.0, 1.0, 20.0, 0.5, "Feel", "How fast the zoom punch relaxes, 1/s."],
	["feel_flash_s", 0.08, 0.0, 0.4, 0.01, "Feel", "Hit-flash length on the struck part, s (real time)."],
	["feel_flash_min", 0.08, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does not flash."],
	["feel_spark_max", 26.0, 0.0, 80.0, 1.0, "Feel", "Sparks per metal-on-metal hit at full impact."],
	["feel_spark_min", 0.1, 0.0, 0.8, 0.01, "Feel", "Impact below which metal hits make no sparks."],
	["feel_rumble_scale", 1.0, 0.0, 1.0, 0.05, "Feel", "Gamepad rumble and phone vibration strength (the options toggle also gates it)."],
	["feel_rumble_s", 0.3, 0.0, 1.0, 0.02, "Feel", "Rumble length at full impact, s."],
	["feel_rumble_min", 0.2, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does not rumble."],
	["feel_hitstop_min", 0.2, 0.0, 0.9, 0.01, "Feel", "Impact below which a hit has no hit-stop (presentation only; physics never pauses)."],
	["feel_hitstop_light_s", 0.035, 0.0, 0.2, 0.005, "Feel", "Hit-stop of a hit just over the floor, real s."],
	["feel_hitstop_heavy_s", 0.095, 0.0, 0.3, 0.005, "Feel", "Hit-stop of a full-impact hit, real s."],
	["feel_hitstop_sever_s", 0.12, 0.0, 0.3, 0.005, "Feel", "Least hit-stop of a blow that severs or guts, real s."],
	["feel_hitstop_finisher_s", 0.16, 0.0, 0.4, 0.005, "Feel", "Hit-stop of a finisher (behead, gut, run through, skull crush), real s."],
	["feel_hitstop_clash_mult", 0.7, 0.0, 1.5, 0.05, "Feel", "Hit-stop share for weapon on weapon (a crisp clang, not a stall)."],
	["feel_hitstop_rate", 0.06, 0.0, 0.5, 0.01, "Feel", "Presentation speed while a hit-stop holds (0 = frozen)."],
	["feel_hitstop_catchup", 1.6, 0.3, 6.0, 0.1, "Feel", "Extra presentation speed while it catches back up to physics after a hold (1.6 = 2.6x)."],
	["feel_hitstop_lag_max", 0.15, 0.02, 0.4, 0.01, "Feel", "Most the shown pose may trail physics, s: the hard cap against stacked stalls."],
	["feel_hitstop_budget_s", 0.3, 0.05, 1.5, 0.01, "Feel", "Hit-stop debt at which further stops shrink to nothing (a flurry does not stall)."],
	["feel_hitstop_budget_tau", 0.8, 0.1, 4.0, 0.05, "Feel", "Time constant over which hit-stop debt drains, s."],
	["feel_punch_min", 0.45, 0.0, 1.0, 0.01, "Feel", "Impact below which a hit does no screen punch (radial blur, colour split, flash)."],
	["feel_punch_s", 0.16, 0.02, 0.6, 0.01, "Feel", "Length of a screen punch, real s."],
	["feel_punch_blur", 0.045, 0.0, 0.15, 0.005, "Feel", "Radial blur reach of a full screen punch (share of the distance to the impact point)."],
	["feel_punch_chroma", 0.006, 0.0, 0.03, 0.001, "Feel", "Colour split of a full screen punch (share of the distance to the impact point)."],
	["feel_punch_flash", 0.22, 0.0, 0.8, 0.01, "Feel", "Screen flash alpha of a full screen punch."],
	["feel_cine_scale", 0.2, 0.05, 1.0, 0.01, "Feel", "Time scale of the finisher slow motion on a behead, gut or run through."],
	["feel_cine_hold_s", 0.9, 0.0, 3.0, 0.05, "Feel", "How long that slow motion holds, real s."],
	["feel_cine_ramp_s", 0.7, 0.05, 3.0, 0.05, "Feel", "Ease back to full speed after the hold, real s (the crowd roars as it starts)."],
	["feel_cine_lpf_hz", 900.0, 200.0, 8000.0, 50.0, "Feel", "Low-pass cutoff on crowd and effects during the finisher slow motion, Hz."],
	["feel_cine_bass_db", -2.0, -30.0, 6.0, 0.5, "Feel", "Gain of the finisher bass hit, dB."],
	["feel_bass_min", 0.6, 0.0, 1.0, 0.01, "Feel", "Impact above which an ordinary heavy hit gets a short sub-bass thump."],
	["aim_trail_s", 0.3, 0.05, 1.0, 0.05, "Feel", "Length of the player's own weapon-tip trail (aim aid), s."],
	["aim_alpha", 0.8, 0.1, 1.0, 0.05, "Feel", "Opacity of the aim aid (tip marker, trail, hand reticle)."],
	["aim_lost_delay_s", 0.4, 0.0, 3.0, 0.1, "Feel", "Disarmed for this long before the weapon-lost prompt shows, s."],
	["feel_frame_pull_max", 5.0, 0.0, 12.0, 0.5, "Feel", "Most the follow camera pulls back to keep both fighters on screen, m."],
	["feel_frame_margin", 0.82, 0.4, 1.0, 0.01, "Feel", "Share of the half field of view both fighters must stay inside."],
	["feel_close_shoulder", 1.1, 0.0, 2.5, 0.05, "Feel", "Extra sideways shift of the follow camera at melee range, so the opponent is not hidden behind your back, m."],
	["feel_close_height", 0.7, 0.0, 2.0, 0.05, "Feel", "Extra height of the follow camera at melee range, m."],
	["feel_close_near", 1.7, 0.5, 4.0, 0.1, "Feel", "Fighter separation at or under which the full close-range camera shift applies, m."],
	["feel_cam_lead_rate", 24.0, 2.0, 30.0, 1.0, "Feel", "How fast the follow camera's motion lead picks up the wanted pose's velocity, per s. Low and a dodge roll near the foe leaves the camera 0.8 m behind."],
	["feel_cam_lead_max", 18.0, 3.0, 30.0, 1.0, "Feel", "Cap on the follow camera's motion lead, m/s. The wanted pose moves faster than the fighter at melee range (shoulder and close-range swing)."],
	["feel_cam_cut_m", 0.3, 0.1, 1.0, 0.05, "Feel", "A wanted-pose jump over this in one frame is a cut (framing change), not motion to lead, m."],
	["feel_finale_hold_s", 3.0, 0.5, 8.0, 0.1, "Feel", "How long the finisher / death camera holds its framing, s."],
	["feel_finale_ease_s", 0.6, 0.1, 2.0, 0.05, "Feel", "Ease-in of the finisher camera, s."],
	["feel_finale_release_s", 1.5, 0.2, 4.0, 0.1, "Feel", "Ease-out back to the normal camera after the hold, s."],
	["feel_finale_dist", 3.6, 1.5, 7.0, 0.1, "Feel", "Distance of the finisher camera from the held point, m."],
	["feel_finale_height", 1.1, 0.3, 3.0, 0.1, "Feel", "Height of the finisher camera above the held point, m."],
	["feel_finale_look_y", 0.8, 0.3, 1.5, 0.05, "Feel", "Height of the held finisher look point, m."],
	["feel_finale_head_bias0", 0.2, 0.0, 1.0, 0.05, "Feel", "Share of the beheading look point on the severed head at first (the rest stays on the body's fountain)."],
	["feel_finale_head_bias1", 0.65, 0.0, 1.0, 0.05, "Feel", "Share of the beheading look point on the head once it has rolled."],
	["feel_finale_head_s", 2.0, 0.2, 5.0, 0.1, "Feel", "Seconds over which the beheading shot shifts from the fountain to the head, s."],
	["feel_finale_head_reach", 5.0, 1.5, 10.0, 0.1, "Feel", "Furthest the beheading shot follows the head from the body, m."],
	["feel_finale_dist_max", 7.5, 3.0, 12.0, 0.1, "Feel", "Most the finisher camera backs off to keep body and head in frame, m."],
	["feel_finale_high", 3.2, 1.5, 6.0, 0.1, "Feel", "Camera height of the high 3/4 finisher fallback when no side-on angle fits inside the wall, m."],
	["feel_prime_ticks", 1.0, 0.0, 10.0, 1.0, "Feel", "Physics ticks the camera waits after a restart before it primes, so ragdolls settle."],
	["feel_close_far", 3.6, 1.0, 8.0, 0.1, "Feel", "Fighter separation at or over which the close-range camera shift is gone, m."],
]

var feel_shake_scale: float
var feel_impact_energy_ref: float
var feel_impact_total_ref: float
var feel_shake_min: float
var feel_kick_m: float
var feel_kick_freq: float
var feel_shake_m: float
var feel_shake_roll_deg: float
var feel_shake_decay: float
var feel_zoom_deg: float
var feel_zoom_hit_deg: float
var feel_zoom_decay: float
var feel_flash_s: float
var feel_flash_min: float
var feel_spark_max: float
var feel_spark_min: float
var feel_rumble_scale: float
var feel_rumble_s: float
var feel_rumble_min: float
var feel_hitstop_min: float
var feel_hitstop_light_s: float
var feel_hitstop_heavy_s: float
var feel_hitstop_sever_s: float
var feel_hitstop_finisher_s: float
var feel_hitstop_clash_mult: float
var feel_hitstop_rate: float
var feel_hitstop_catchup: float
var feel_hitstop_lag_max: float
var feel_hitstop_budget_s: float
var feel_hitstop_budget_tau: float
var feel_punch_min: float
var feel_punch_s: float
var feel_punch_blur: float
var feel_punch_chroma: float
var feel_punch_flash: float
var feel_cine_scale: float
var feel_cine_hold_s: float
var feel_cine_ramp_s: float
var feel_cine_lpf_hz: float
var feel_cine_bass_db: float
var feel_bass_min: float
var aim_trail_s: float
var aim_alpha: float
var aim_lost_delay_s: float
var feel_frame_pull_max: float
var feel_frame_margin: float
var feel_close_shoulder: float
var feel_close_height: float
var feel_close_near: float
var feel_cam_lead_rate: float
var feel_cam_lead_max: float
var feel_cam_cut_m: float
var feel_finale_hold_s: float
var feel_finale_ease_s: float
var feel_finale_release_s: float
var feel_finale_dist: float
var feel_finale_height: float
var feel_finale_look_y: float
var feel_finale_head_bias0: float
var feel_finale_head_bias1: float
var feel_finale_head_s: float
var feel_finale_head_reach: float
var feel_finale_dist_max: float
var feel_finale_high: float
var feel_prime_ticks: float
var feel_close_far: float
