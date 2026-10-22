extends "res://game/debug/tuning/tuning_armor.gd"
## Tuning rows of the "Blood" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_BLOOD and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_BLOOD: Array = [
	["fountain_streams", 5.0, 1.0, 8.0, 1.0, "Blood", "Beheading fountain: jets from the neck at normal quality (low quality uses half, high a quarter more)."],
	["fountain_dur", 6.5, 1.0, 15.0, 0.1, "Blood", "Beheading fountain: seconds until the jets stop."],
	["fountain_hold", 1.6, 0.0, 8.0, 0.1, "Blood", "Beheading fountain: seconds at full strength before it tapers off."],
	["fountain_bpm", 150.0, 40.0, 240.0, 5.0, "Blood", "Beheading fountain: heartbeat pulses per minute."],
	["fountain_pulse_floor", 0.14, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: share of the flow that stays between heartbeats."],
	["fountain_rate", 1300.0, 50.0, 2000.0, 10.0, "Blood", "Beheading fountain: droplets per second per jet at full flow and normal quality."],
	["fountain_v_min", 3.2, 1.0, 12.0, 0.1, "Blood", "Beheading fountain: droplet exit speed between beats, m/s."],
	["fountain_v_max", 7.5, 3.0, 20.0, 0.1, "Blood", "Beheading fountain: droplet exit speed at the top of a beat, m/s."],
	["fountain_up_bias", 0.6, 0.0, 1.0, 0.05, "Blood", "Beheading fountain: how far the jets turn from the neck axis toward straight up (0 = along the neck, 1 = vertical)."],
	["fountain_fan", 0.5, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: radians the jets lean away from the main axis."],
	["fountain_wobble", 0.22, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: radians of swaying added to each jet."],
	["fountain_swirl", 0.9, 0.0, 4.0, 0.1, "Blood", "Beheading fountain: radians per second the jets circle around the axis."],
	["fountain_drop_scale", 3.2, 0.5, 3.0, 0.05, "Blood", "Beheading fountain: droplet size multiplier (cartoon fat drops)."],
	["fountain_gush", 1.4, 0.0, 4.0, 0.1, "Blood", "Beheading fountain: extra flow in the first moments."],
	["fountain_emit_cap", 250.0, 20.0, 400.0, 5.0, "Blood", "Beheading fountain: most droplets all jets may emit in one frame."],
	["fountain_mist", 2.0, 0.0, 6.0, 1.0, "Blood", "Beheading fountain: mist puffs per jet per heartbeat."],
	["fountain_pool", 0.9, 0.0, 4.0, 0.05, "Blood", "Beheading fountain: presentation litres per second poured onto the sand under the body."],
	["fountain_head_share", 0.35, 0.0, 1.0, 0.05, "Blood", "Beheading fountain: strength of the trail from the severed head, as a share of one neck jet."],
	["fountain_size_var", 1.0, 0.0, 2.0, 0.05, "Blood", "Beheading fountain: per-drop size and speed variance (0 = every drop alike)."],
	["fountain_gout", 0.05, 0.0, 0.3, 0.01, "Blood", "Beheading fountain: chance that a drop is a big fast gout."],
	["fountain_drift", 1.0, 0.0, 3.0, 0.1, "Blood", "Beheading fountain: spray drift and wobble of the jets and the scatter of single drops."],
	["fountain_fine_mist", 14.0, 0.0, 60.0, 1.0, "Blood", "Beheading fountain: fine mist puffs per second per jet at full flow."],
	["fountain_headroom", 0.35, 0.05, 1.0, 0.05, "Blood", "Beheading fountain: the jets taper off as free droplet slots drop below this share of the pool."],
	["gore_spawn_frames", 3.0, 1.0, 6.0, 1.0, "Blood", "Gore moments: frames a burst or ground splash of droplets is spread over (same total, smoother frame time)."],
	["gut_ropes", 4.0, 0.0, 8.0, 1.0, "Blood", "Gut spill: intestine strings that slide out of a gutting or run-through at normal quality."],
	["gut_segs", 9.0, 4.0, 14.0, 1.0, "Blood", "Gut spill: points per intestine string at normal quality (low uses a third fewer)."],
	["gut_seg_len", 0.15, 0.03, 0.4, 0.005, "Blood", "Gut spill: length of one intestine link when fully paid out, m."],
	["gut_radius", 0.038, 0.01, 0.12, 0.002, "Blood", "Gut spill: thickness (radius) of the intestine sausage, m."],
	["gut_pay_time", 0.9, 0.1, 3.0, 0.05, "Blood", "Gut spill: seconds for a string to slide fully out of the wound."],
	["gut_eject", 3.4, 0.0, 8.0, 0.1, "Blood", "Gut spill: speed the guts are flung out of the wound, m/s."],
	["gut_push", 12.0, 0.0, 30.0, 0.5, "Blood", "Gut spill: acceleration that shoves the guts out while they pay out, m/s^2."],
	["gut_sway", 4.0, 0.0, 12.0, 0.5, "Blood", "Gut spill: sideways acceleration that fans neighbouring strings apart while they hang, m/s^2."],
	["gut_damp", 0.99, 0.9, 1.0, 0.005, "Blood", "Gut spill: air damping per 60th of a second on the strings and chunks."],
	["gut_friction", 0.8, 0.3, 1.0, 0.01, "Blood", "Gut spill: sideways grip on the sand per 60th of a second (lower = stops sooner)."],
	["gut_sleep_speed", 0.06, 0.01, 0.5, 0.01, "Blood", "Gut spill: a string slower than this, m/s, counts as calm."],
	["gut_sleep_time", 0.6, 0.1, 3.0, 0.1, "Blood", "Gut spill: seconds of calm before a string freezes on the sand."],
	["gut_bounce", 0.3, 0.0, 0.8, 0.05, "Blood", "Gut spill: how much an organ chunk bounces off the sand."],
	["gut_blobs", 4.0, 0.0, 10.0, 1.0, "Blood", "Gut spill: organ chunks flung out per spill at normal quality."],
	["gut_blob_radius", 0.06, 0.02, 0.15, 0.005, "Blood", "Gut spill: organ chunk size (radius), m."],
	["gut_max_ropes", 14.0, 1.0, 40.0, 1.0, "Blood", "Gut spill: most intestine strings alive at normal quality (low is half, high is double)."],
	["gut_max_blobs", 28.0, 0.0, 80.0, 1.0, "Blood", "Gut spill: most organ chunks alive at normal quality (low is half, high is double)."],
	["gut_smear", 0.12, 0.0, 0.6, 0.01, "Blood", "Gut spill: presentation litres smeared on the sand where a string or chunk first lands."],
	["gut_drip", 16.0, 0.0, 60.0, 1.0, "Blood", "Gut spill: droplets per second dripping off each hanging string tip."],
	["gut_drip_time", 5.0, 0.0, 20.0, 0.5, "Blood", "Gut spill: seconds the strings keep dripping."],
	["gut_streams", 3.0, 1.0, 8.0, 1.0, "Blood", "Gut spill: blood jets from the wound at normal quality (low uses half, high a quarter more)."],
	["gut_dur", 4.2, 1.0, 15.0, 0.1, "Blood", "Gut spill: seconds until the gush stops."],
	["gut_hold", 1.0, 0.0, 8.0, 0.1, "Blood", "Gut spill: seconds at full strength before the gush tapers."],
	["gut_rate", 1100.0, 50.0, 2000.0, 10.0, "Blood", "Gut spill: droplets per second per jet at full flow and normal quality."],
	["gut_v_scale", 0.7, 0.2, 2.0, 0.05, "Blood", "Gut spill: exit speed of the gush as a share of the beheading fountain's."],
	["gut_up_bias", 0.12, 0.0, 1.0, 0.05, "Blood", "Gut spill: how far the gush turns from the wound normal toward straight up."],
	["gut_pool", 2.2, 0.0, 6.0, 0.05, "Blood", "Gut spill: presentation litres per second poured onto the sand under the wound."],
	["gut_exit_depth", 0.3, 0.1, 0.6, 0.02, "Blood", "Run-through: how far behind the entry wound the exit wound is, m."],
	["gut_exit_streams", 3.0, 0.0, 8.0, 1.0, "Blood", "Run-through: jets from the exit wound at normal quality."],
	["gut_exit_v_scale", 1.3, 0.2, 3.0, 0.05, "Blood", "Run-through: exit-wound gush speed relative to the entry gush."],
	["gut_cluster_size", 0.13, 0.0, 0.4, 0.01, "Blood", "Gut spill: half width of the tangle of guts bulging out of the wound, m."],
	["gut_organ_points", 40.0, 0.0, 200.0, 1.0, "Blood", "Gut spill: cut or pierce points of a gutting at which whole organs fall out (a run-through always)."],
	["gut_organs", 2.0, 0.0, 2.0, 1.0, "Blood", "Gut spill: organs (liver, stomach) that fall out of a big gut wound at normal quality."],
	["gut_max_organs", 6.0, 0.0, 20.0, 1.0, "Blood", "Gut spill: most organs on the sand at normal quality (low is half, high is double)."],
	["gut_organ_eject", 1.5, 0.0, 6.0, 0.1, "Blood", "Gut spill: speed an organ slides out of the wound, m/s."],
	["gut_organ_friction", 0.92, 0.5, 1.0, 0.01, "Blood", "Gut spill: an organ's grip on the sand per 60th of a second (higher slides further)."],
	["gut_organ_smear_step", 0.12, 0.03, 1.0, 0.01, "Blood", "Gut spill: an organ sliding on the sand leaves a smear every this many metres."],
	["wound_core_scale", 1.6, 1.0, 3.0, 0.05, "Blood", "Wound marks: width multiplier on a gash's open slit and a puncture's hole, so fresh cuts read at fight-camera distance."],
	["wound_rim_glow", 0.9, 0.0, 3.0, 0.05, "Blood", "Wound marks: emission of a fresh gash's or puncture's wet rim (0 = none)."],
	["wound_rim_glow_s", 4.0, 0.0, 20.0, 0.5, "Blood", "Wound marks: seconds the rim glow takes to fade as the wound dries."],
	["wound_drop_rate", 12.0, 0.0, 60.0, 1.0, "Blood", "Body stains: blood drops landing on one fighter that leave a smear, per second (the rest merge or are lost)."],
	["wound_drop_size", 6.0, 2.0, 14.0, 0.5, "Blood", "Body stains: radius of a landed drop's smear per metre of drop radius."],
	["wound_soak_min", 2.0, 0.0, 20.0, 0.5, "Blood", "Body stains: blood points (cut + pierce + 0.3 blunt) of a bleeding hit with no gash or hole that soak a smear in."],
	["wound_stump_sev", 1.0, 0.0, 1.0, 0.05, "Blood", "Body stains: strength of the blood collar on both sides of a severed limb or neck (0 = none)."],
]

var fountain_streams: float
var fountain_dur: float
var fountain_hold: float
var fountain_bpm: float
var fountain_pulse_floor: float
var fountain_rate: float
var fountain_v_min: float
var fountain_v_max: float
var fountain_up_bias: float
var fountain_fan: float
var fountain_wobble: float
var fountain_swirl: float
var fountain_drop_scale: float
var fountain_gush: float
var fountain_emit_cap: float
var fountain_mist: float
var fountain_pool: float
var fountain_head_share: float
var fountain_size_var: float
var fountain_gout: float
var fountain_drift: float
var fountain_fine_mist: float
var fountain_headroom: float
var gore_spawn_frames: float
var gut_ropes: float
var gut_segs: float
var gut_seg_len: float
var gut_radius: float
var gut_pay_time: float
var gut_eject: float
var gut_push: float
var gut_sway: float
var gut_damp: float
var gut_friction: float
var gut_sleep_speed: float
var gut_sleep_time: float
var gut_bounce: float
var gut_blobs: float
var gut_blob_radius: float
var gut_max_ropes: float
var gut_max_blobs: float
var gut_smear: float
var gut_drip: float
var gut_drip_time: float
var gut_streams: float
var gut_dur: float
var gut_hold: float
var gut_rate: float
var gut_v_scale: float
var gut_up_bias: float
var gut_pool: float
var gut_exit_depth: float
var gut_exit_streams: float
var gut_exit_v_scale: float
var gut_cluster_size: float
var gut_organ_points: float
var gut_organs: float
var gut_max_organs: float
var gut_organ_eject: float
var gut_organ_friction: float
var gut_organ_smear_step: float
var wound_core_scale: float
var wound_rim_glow: float
var wound_rim_glow_s: float
var wound_drop_rate: float
var wound_drop_size: float
var wound_soak_min: float
var wound_stump_sev: float
