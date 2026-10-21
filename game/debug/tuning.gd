class_name Tuning
extends RefCounted
## Template for live-tunable gameplay numbers (pattern from the skate project's PhysicsTuning).
## Game code reads `Tuning.shared().<field>` every tick instead of hard-coding numbers, so a tuning panel,
## replays, sims and presets can change the feel without touching code.
## Add a row to FIELDS and a matching `var` below; nothing else is needed.
## Presets are JSON dictionaries of {field: value}; unknown keys are ignored.

signal changed(field: String, value: float)

## [field, default, min, max, step, group, doc]. The order here is the order a tuning panel shows.
const FIELDS: Array = [
	["gravity", 9.8, 5.0, 30.0, 0.1, "World", "Gravity, m/s². Real is 9.8."],
	["arena_radius", 11.0, 6.0, 20.0, 0.5, "World", "Radius of the arena wall, m."],
	["move_speed", 2.5, 0.5, 8.0, 0.1, "Movement", "Walk speed on sand, m/s."],
	["sprint_speed", 4.5, 1.0, 10.0, 0.1, "Movement", "Sprint speed on sand, m/s."],
	["arm_force", 900.0, 100.0, 4000.0, 25.0, "Arms", "Max force the weapon hand can apply toward its target, N."],
	["damage_min_speed", 3.0, 0.0, 10.0, 0.1, "Damage", "Weapon-to-target speed below which a contact does no damage, m/s."],
	["blood_death", 2.5, 0.5, 5.0, 0.1, "Damage", "Blood volume (litres) below which a fighter dies."],
	["dmg_cut_scale", 0.25, 0.05, 1.0, 0.01, "Damage", "Cut damage points per joule of edged energy (before armor and weapon cut_factor)."],
	["dmg_pierce_scale", 0.9, 0.1, 3.0, 0.05, "Damage", "Pierce damage points per joule of point energy."],
	["dmg_blunt_scale", 0.1, 0.02, 0.5, 0.01, "Damage", "Blunt damage points per joule (before armor and weapon blunt_factor)."],
	["dmg_sever_cut", 40.0, 10.0, 120.0, 1.0, "Damage", "Cut points (after armor) that sever a forearm at full hp; other parts scale from this."],
	["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut or pierce points (after armor) on torso/pelvis that gut."],
	["dmg_stagger_ref", 150.0, 30.0, 600.0, 5.0, "Damage", "Blunt energy (J, after armor) that gives full stagger."],
	["dmg_knock_scale", 0.3, 0.0, 2.0, 0.05, "Damage", "Knockback impulse per N·s of hit momentum."],
	["dmg_bleed_cut", 0.004, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per cut point."],
	["dmg_bleed_pierce", 0.003, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per pierce point."],
	["dmg_bleed_sever", 0.4, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a severed limb."],
	["dmg_bleed_gut", 0.35, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a gutting."],
	["dmg_wear_loss", 0.6, 0.0, 1.0, 0.05, "Damage", "Fraction of an armor piece's resistance lost at full wear."],
	["dmg_glance_frac", 0.15, 0.0, 1.0, 0.01, "Damage", "A sharp hit is a glance when armor leaves less than this fraction of its cut+pierce."],
	["dmg_strap_wear", 0.7, 0.0, 1.0, 0.05, "Damage", "Fraction of an armor piece's strap strength lost at full wear."],
	["dmg_dislodge_up", 1.0, 0.0, 4.0, 0.1, "Damage", "Dislodge bonus for upward blows (doubled on the head)."],
	["dmg_dislodge_glance", 0.5, 0.0, 4.0, 0.1, "Damage", "Dislodge bonus for glancing blows."],
	["dmg_dislodge_sharp", 0.3, 0.0, 2.0, 0.05, "Damage", "How much cutting or piercing energy counts toward tearing a strap, relative to blunt."],
	["dmg_disarm_scale", 1.0, 0.1, 5.0, 0.1, "Damage", "Disarm impulse per N·s of hit momentum."],
	["dmg_disarm_forearm", 0.5, 0.0, 1.0, 0.05, "Damage", "Share of the disarm impulse that a hit on the holding forearm (not the weapon) delivers."],
	["dmg_grip_base", 18.0, 4.0, 60.0, 0.5, "Damage", "One-handed grip strength at full arm hp and stamina, N·s."],
	["dmg_grip_two_hands", 1.6, 1.0, 3.0, 0.05, "Damage", "Grip strength multiplier with two hands on the weapon."],
	["finisher_blood_frac", 0.6, 0.0, 1.0, 0.05, "Damage", "Blood fraction (0 = blood_death, 1 = full) below which a hit can be a killing blow."],
	["dmg_finisher_min_scale", 0.25, 0.1, 1.0, 0.01, "Damage", "Share of the normal sever/gut/crush force a finisher needs when blood is at blood_death."],
	["dmg_finisher_top_scale", 0.5, 0.2, 1.0, 0.01, "Damage", "Share of the normal sever/gut/crush force a finisher needs at the top edge of the finisher window."],
	["dmg_skull_crush", 20.0, 5.0, 80.0, 1.0, "Damage", "Blunt points (after armor, head multiplier included) a heavy blunt hit needs to crush the skull."],
	["stand_height", 0.95, 0.7, 1.1, 0.01, "Fighter", "Pelvis height held when standing, m."],
	["crouch_height", 0.74, 0.5, 0.95, 0.01, "Fighter", "Pelvis height held when crouching, m."],
	["support_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the pelvis height support, rad/s."],
	["support_max", 2.2, 0.5, 4.0, 0.1, "Fighter", "Max support force as a multiple of body weight."],
	["balance_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the upright and yaw controller, rad/s."],
	["balance_torque", 450.0, 50.0, 2000.0, 10.0, "Fighter", "Max upright torque on the pelvis, N·m."],
	["torso_assist", 0.35, 0.0, 1.0, 0.05, "Fighter", "Share of the upright torque also put on the torso."],
	["move_accel", 9.0, 1.0, 30.0, 0.5, "Movement", "Max horizontal acceleration while moving, m/s²."],
	["move_response", 7.0, 1.0, 20.0, 0.5, "Movement", "How fast the body velocity follows the move input, 1/s."],
	["turn_rate", 6.0, 1.0, 20.0, 0.5, "Movement", "Max turn rate toward the opponent, rad/s."],
	["joint_strength", 1.0, 0.0, 3.0, 0.05, "Fighter", "Multiplier on every joint's PD torque cap."],
	["joint_damping", 1.0, 0.2, 2.0, 0.05, "Fighter", "Damping ratio of joint PD drives."],
	["arm_freq", 22.0, 5.0, 40.0, 0.5, "Arms", "Stiffness of the hand position drive, rad/s."],
	["arm_damping", 0.3, 0.05, 1.5, 0.05, "Arms", "Damping ratio of the hand position drive."],
	["arm_drive_mass", 3.5, 0.5, 10.0, 0.1, "Arms", "Mass the hand drive gains are computed for, kg."],
	["guard_force_frac", 0.45, 0.1, 1.0, 0.05, "Arms", "Share of arm_force used when not swinging or thrusting."],
	["offhand_force_frac", 0.6, 0.1, 1.0, 0.05, "Arms", "Share of arm_force for the left hand."],
	["arm_reaction", 0.4, 0.0, 1.0, 0.05, "Arms", "Share of the hand force pushed back on the torso at the shoulder."],
	["wrist_torque", 140.0, 10.0, 400.0, 5.0, "Arms", "Max wrist torque on the weapon, N·m."],
	["wrist_freq", 16.0, 4.0, 40.0, 0.5, "Arms", "Stiffness of the weapon orientation drive, rad/s."],
	["wrist_limit", 1.2, 0.2, 2.0, 0.05, "Arms", "Wrist joint swing limit, rad."],
	["wrist_roll", 0.3, 0.0, 1.0, 0.05, "Arms", "Strength of the wrist roll drive relative to swing."],
	["wrist_reach", 0.9, 0.2, 1.6, 0.05, "Arms", "Max wrist target angle from the natural grip direction, rad."],
	["wrist_lead", 0.15, 0.0, 0.5, 0.01, "Arms", "Blade lead along hand velocity (whip), s."],
	["blade_up_guard", 0.75, 0.0, 1.0, 0.05, "Arms", "How upright the blade is held in guard."],
	["blade_up_swing", 0.25, 0.0, 1.0, 0.05, "Arms", "How upright the blade is held while swinging."],
	["blade_pivot_back", 0.45, 0.0, 1.0, 0.05, "Arms", "How far the blade points back along the swing path, wind-up."],
	["guard_width", 0.7, 0.2, 1.2, 0.05, "Arms", "Half width of the guard plane, m."],
	["guard_height", 0.5, 0.2, 1.0, 0.05, "Arms", "Half height of the guard plane, m."],
	["guard_forward", 0.42, 0.2, 0.8, 0.01, "Arms", "Guard plane distance in front of the chest, m."],
	["thrust_reach", 0.45, 0.0, 1.0, 0.05, "Arms", "Extra forward reach when thrusting, m."],
	["swing_reach", 0.35, 0.0, 1.0, 0.05, "Arms", "Extra forward reach while swinging, m."],
	["half_sword_thrust", 1.6, 1.0, 3.0, 0.1, "Arms", "Thrust force multiplier in the half-sword grip."],
	["torso_twist", 0.7, 0.0, 1.5, 0.05, "Arms", "Torso yaw following horizontal aim, rad at full aim."],
	["stumble_tilt", 0.35, 0.1, 1.0, 0.01, "Balance", "Tilt where standing turns to stumbling, rad."],
	["fall_tilt", 1.0, 0.4, 1.5, 0.05, "Balance", "Tilt where the fighter goes down, rad."],
	["stagger_down", 0.85, 0.2, 1.5, 0.05, "Balance", "Stagger level that knocks the fighter down."],
	["stagger_recover", 0.8, 0.1, 3.0, 0.05, "Balance", "Stagger recovered per second."],
	["down_time", 1.5, 0.2, 5.0, 0.1, "Balance", "Time spent down before getting up, s."],
	["getup_time", 1.4, 0.3, 4.0, 0.1, "Balance", "Duration of getting up, s."],
	["down_strength", 0.3, 0.0, 1.0, 0.05, "Balance", "Joint strength while down."],
	["limp_strength", 0.04, 0.0, 0.3, 0.01, "Balance", "Joint strength when KO or dead."],
	["stamina_floor", 0.45, 0.0, 1.0, 0.05, "Fighter", "Strength left at zero stamina."],
	["limb_floor", 0.25, 0.0, 1.0, 0.05, "Fighter", "Limb drive left at zero limb hp."],
	["weapon_drop_hp", 0.15, 0.0, 0.5, 0.01, "Fighter", "Arm hp fraction below which the weapon is dropped."],
	["stride_base", 0.15, 0.0, 0.4, 0.01, "Movement", "Half stride at walking start, m."],
	["stride_per_speed", 0.08, 0.0, 0.3, 0.01, "Movement", "Half stride added per m/s, m."],
	["stride_max", 0.45, 0.1, 0.8, 0.01, "Movement", "Max half stride, m."],
	["foot_lift", 0.13, 0.0, 0.3, 0.01, "Movement", "Swing foot lift height, m."],
	["pelvis_inertia", 2.0, 1.0, 5.0, 0.1, "Stability", "Pelvis inertia boost for stable PD."],
	["torso_inertia", 2.5, 1.0, 5.0, 0.1, "Stability", "Torso inertia boost for stable PD."],
	["balance_inertia", 3.0, 0.5, 8.0, 0.1, "Stability", "Inertia the upright controller gains assume, kg·m²."],
	["leg_reaction", 0.25, 0.0, 1.0, 0.05, "Stability", "Share of leg joint reaction put on the pelvis."],
	["pd_margin", 0.5, 0.1, 1.5, 0.05, "Stability", "Damping-rate margin for explicit PD (below 2 is stable)."],
	["self_hit_min_speed", 6.0, 0.0, 15.0, 0.5, "Damage", "Min speed for a fighter's own weapon to hurt them, m/s."],
	["self_hit_grace_s", 0.5, 0.0, 3.0, 0.1, "Damage", "No self hits for this long after spawn, while the weapon settles in the hand, s."],
	["finisher_consc", 0.35, 0.0, 1.0, 0.05, "Damage", "A dazed (consciousness below this) or downed fighter can be finished at any blood level."],
	["hold_freq", 2.0, 0.0, 6.0, 0.1, "Movement", "Idle position hold stiffness (stops drift), rad/s."],
	["guard_hand_speed", 2.5, 0.5, 10.0, 0.1, "Arms", "Max speed of the hand goal in guard, m/s."],
	["swing_hand_speed", 30.0, 5.0, 60.0, 1.0, "Arms", "Max speed of the hand goal while swinging or thrusting, m/s."],
	["offhand_hand_speed", 5.0, 0.5, 15.0, 0.5, "Arms", "Max speed of the left hand goal, m/s."],
	["hit_debounce", 0.25, 0.05, 1.0, 0.05, "Damage", "Min time between hits by the same weapon on the same part, s."],
	["grab_radius", 0.6, 0.1, 1.0, 0.05, "Arms", "GRAB pickup radius from the hand, m."],
	["knockback_scale", 1.0, 0.0, 3.0, 0.05, "Damage", "Multiplier on hit knockback impulses."],
	["match_pause_s", 4.0, 1.0, 15.0, 0.5, "Match", "Pause after a match before the next bot match starts, s."],
	["match_slowmo_scale", 0.4, 0.1, 1.0, 0.05, "Match", "Time scale during the finisher slow motion."],
	["match_slowmo_s", 1.0, 0.0, 5.0, 0.1, "Match", "Length of the finisher slow motion, game seconds."],
	["blood_faint", 3.5, 2.6, 5.0, 0.1, "Health", "Blood (L) below which consciousness is capped; zero at blood_death."],
	["health_head_ko", 0.1, 0.0, 0.2, 0.005, "Health", "Consciousness lost per blunt point on the head."],
	["health_stagger_ko", 0.05, 0.0, 0.5, 0.01, "Health", "Consciousness lost per unit of stagger on any part."],
	["health_clot", 0.02, 0.0, 0.5, 0.005, "Health", "Bleed rate decay per second (clotting)."],
	["health_consc_recover", 0.03, 0.0, 0.5, 0.005, "Health", "Consciousness recovery per second."],
	["health_stamina_recover", 0.2, 0.0, 1.0, 0.01, "Health", "Stamina recovered per second at rest."],
	["health_stamina_drain", 0.3, 0.0, 1.0, 0.01, "Health", "Stamina drained per second at full exertion."],
]

static var _shared: Tuning = null

var gravity: float
var arena_radius: float
var move_speed: float
var sprint_speed: float
var arm_force: float
var damage_min_speed: float
var blood_death: float
var dmg_cut_scale: float
var dmg_pierce_scale: float
var dmg_blunt_scale: float
var dmg_sever_cut: float
var dmg_gut: float
var dmg_stagger_ref: float
var dmg_knock_scale: float
var dmg_bleed_cut: float
var dmg_bleed_pierce: float
var dmg_bleed_sever: float
var dmg_bleed_gut: float
var dmg_wear_loss: float
var dmg_glance_frac: float
var dmg_strap_wear: float
var dmg_dislodge_up: float
var dmg_dislodge_glance: float
var dmg_dislodge_sharp: float
var dmg_disarm_scale: float
var dmg_disarm_forearm: float
var dmg_grip_base: float
var dmg_grip_two_hands: float
var finisher_blood_frac: float
var dmg_finisher_min_scale: float
var dmg_finisher_top_scale: float
var dmg_skull_crush: float
var stand_height: float
var crouch_height: float
var support_freq: float
var support_max: float
var balance_freq: float
var balance_torque: float
var torso_assist: float
var move_accel: float
var move_response: float
var turn_rate: float
var joint_strength: float
var joint_damping: float
var arm_freq: float
var arm_damping: float
var arm_drive_mass: float
var guard_force_frac: float
var offhand_force_frac: float
var arm_reaction: float
var wrist_torque: float
var wrist_freq: float
var wrist_limit: float
var wrist_roll: float
var wrist_reach: float
var wrist_lead: float
var blade_up_guard: float
var blade_up_swing: float
var blade_pivot_back: float
var guard_width: float
var guard_height: float
var guard_forward: float
var thrust_reach: float
var swing_reach: float
var half_sword_thrust: float
var torso_twist: float
var stumble_tilt: float
var fall_tilt: float
var stagger_down: float
var stagger_recover: float
var down_time: float
var getup_time: float
var down_strength: float
var limp_strength: float
var stamina_floor: float
var limb_floor: float
var weapon_drop_hp: float
var stride_base: float
var stride_per_speed: float
var stride_max: float
var foot_lift: float
var pelvis_inertia: float
var torso_inertia: float
var balance_inertia: float
var leg_reaction: float
var pd_margin: float
var self_hit_min_speed: float
var self_hit_grace_s: float
var finisher_consc: float
var hold_freq: float
var guard_hand_speed: float
var swing_hand_speed: float
var offhand_hand_speed: float
var hit_debounce: float
var grab_radius: float
var knockback_scale: float
var match_pause_s: float
var match_slowmo_scale: float
var match_slowmo_s: float
var blood_faint: float
var health_head_ko: float
var health_stagger_ko: float
var health_clot: float
var health_consc_recover: float
var health_stamina_recover: float
var health_stamina_drain: float


func _init() -> void:
	reset()


## The tuning the game uses unless it is given its own. A tuning panel edits this one.
static func shared() -> Tuning:
	if _shared == null:
		_shared = Tuning.new()
	return _shared


static func field_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in FIELDS:
		out.append(f[0])
	return out


static func field_info(field: String) -> Dictionary:
	for f: Array in FIELDS:
		if f[0] == field:
			return {"name": f[0], "default": f[1], "min": f[2], "max": f[3], "step": f[4], "group": f[5], "doc": f[6]}
	return {}


func reset() -> void:
	for f: Array in FIELDS:
		set(f[0], float(f[1]))


## Sets one field, clamped to its range. Returns false for an unknown field.
func set_value(field: String, value: float) -> bool:
	var info: Dictionary = field_info(field)
	if info.is_empty():
		return false
	var v: float = clampf(value, float(info["min"]), float(info["max"]))
	set(field, v)
	changed.emit(field, v)
	return true


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		d[f[0]] = get(f[0])
	return d


## Applies known keys from `d` (others are ignored). Returns the number of fields applied.
func apply_dict(d: Dictionary) -> int:
	var n: int = 0
	for key: Variant in d:
		if set_value(str(key), float(d[key])):
			n += 1
	return n


## Only the fields that differ from the defaults: what a preset needs to store.
func diff_from_defaults() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		if not is_equal_approx(float(get(f[0])), float(f[1])):
			d[f[0]] = get(f[0])
	return d


func copy_from(other: Tuning) -> void:
	apply_dict(other.to_dict())


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	return OK


## Loads a preset file over the current values. Returns false if the file is missing or not a JSON object.
func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	apply_dict(parsed)
	return true
