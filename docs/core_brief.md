# Core brief: step 1 (fighter core, damage model, input, arena, tuning panel)

Read `CLAUDE.md`, `docs/agent_brief.md` and `docs/lessons_learned.md` first. This file is the contract every worker
in step 1 codes against. Do not change a signature here; if one is wrong, say so in your report.

## The game in one paragraph
Gladiator (working title) is an M-rated, physics-driven 1v1 melee fighter in a small sand arena, in the spirit of
**Half Sword**: fighters are active ragdolls, the player steers the weapon hand directly with the mouse or right stick,
and damage comes from where and how hard the weapon actually connects (speed, mass, edge vs flat vs point, armor).
Weapons run from fists, rakes and bats up to swords, spears and shields; armor is per body part. Gore is in scope:
blood spray, bleeding, severed limbs, gutting and beheading, all driven by the damage model's results.

## Units, axes, layers
- Metres, kilograms, seconds. Y up, fighter forward is -Z of its pelvis basis. Physics 60 Hz, engine Jolt Physics.
- Collision layers: 1 = arena (static), 2 = fighter bodies, 3 = weapons and shields. A fighter's own parts and its own
  weapon never collide with each other (collision exceptions), everything else does.
- Arena: flat sand floor at y = 0, circular wall of radius `Tuning.arena_radius` (default 11 m) centred at the origin.
  Spawns at (0, 0, ±4) facing the centre.

## FighterInput (pure, `game/logic/fighter_input.gd`, owner: input worker)
`class_name FighterInput extends RefCounted`. All values are ints so they record, hash and network exactly.
- `move_x, move_y: int` in -1000..1000 (strafe right, forward), relative to the fighter's facing.
- `aim_x, aim_y: int` in -1000..1000: weapon-hand target in the fighter's guard plane (right, up). 0,0 = guard centre.
  Mouse motion accumulates into this and is clamped; a stick maps directly.
- `buttons: int` bitmask, constants on the class: `SWING = 1` (right hand drives hard: full arm strength),
  `OFFHAND = 2` (left hand/shield up), `HALF_SWORD = 4` (alternate grip: left hand on the blade, short powerful
  thrusts), `THRUST = 8` (push hand target forward to full reach), `SPRINT = 16`, `CROUCH = 32`, `GRAB = 64`
  (pick up / grab), `TURN_LOCK = 128` (hold facing; otherwise the body turns toward the opponent).
- `func to_array() -> Array` returns `[move_x, move_y, aim_x, aim_y, buttons]`; `static func from_array(a: Array) -> FighterInput`.
- `func move() -> Vector2` and `func aim() -> Vector2` return the values scaled to -1..1. `func has(b: int) -> bool`.

## Fighter (`game/fighter/`, owner: fighter-core worker)
`class_name Fighter extends Node3D`. Built entirely in code, no .tscn needed.
- Body parts (RigidBody3D each, capsule/box shapes, realistic masses totalling about 75 kg):
  `pelvis, torso, head, upper_arm_l, upper_arm_r, forearm_l, forearm_r, thigh_l, thigh_r, shin_l, shin_r`.
  Hands are part of the forearms, feet part of the shins. Joints are `Generic6DOFJoint3D` with angular limits.
- Active ragdoll: per-joint PD torques drive the parts toward a target pose; a balance controller keeps the pelvis
  upright over the feet and steps the legs for locomotion. Strength scales with `stamina` and consciousness: a
  knocked-out fighter goes limp.
- Weapon hand: the right forearm is driven (PD force at the hand) toward the target from `aim` in the guard plane,
  with `THRUST` pushing it forward. Arm strength is capped (`Tuning.arm_force`), so heavy weapons are slower to
  accelerate and keep momentum. That is the core Half Sword feel: swings come from moving the mouse.
- Weapons and shields: `class_name Weapon extends RigidBody3D` in `game/fighter/weapon.gd`, built from a weapon def
  (see CombatData). Held by a joint to the hand; `HALF_SWORD` moves the left hand onto the blade.
- API:
  - `func setup(loadout: Dictionary, side: int, tuning: Tuning) -> void`; loadout =
    `{"weapon": "sword", "offhand": "shield_round" or "", "armor": {"head": "helm_iron", "torso": "mail", ...}}`.
  - `var opponent: Fighter`
  - `func apply_input(inp: FighterInput) -> void` (call every physics tick before the step).
  - `var health: FighterHealth` (from the damage worker).
  - `signal hit(event: Dictionary)`: emitted once per resolved weapon contact; the event dict is DamageModel's input
    merged with its result plus `"attacker"` and `"target"` side ints and `"point": Vector3`.
  - `signal gore(event: Dictionary)`: `{"kind": "sever"|"gut"|"behead"|"bleed", "part": String, "point": Vector3,
    "normal": Vector3, "amount": float}`. Presentation (blood fx, detached meshes) listens to this.
  - `signal died`.
  - `func snapshot() -> Dictionary` and `func restore(d: Dictionary) -> void`: every body's transform, linear and
    angular velocity, joint/controller state, health, severed parts, held weapon. Restoring then stepping the same
    inputs must reproduce the run (measure the divergence; target under 1 cm over 10 s on the same machine).
  - `func state_hash() -> int`.
  - `func debug_frame() -> Dictionary`, keys (all present every tick):
    `tick, side, pelvis_pos, pelvis_vel, facing_yaw, balance (0..1, 1 = fully upright), stamina, consciousness,
    hand_target (Vector3 world), hand_pos (Vector3), tip_pos (Vector3), tip_speed (m/s), weapon_id, grip
    ("normal"|"half"), parts: {name: {"pos": Vector3, "hp": float, "severed": bool}}, contacts: Array of the
    tick's hit events, state ("standing"|"stumbling"|"down"|"getting_up"|"ko"|"dead")`.

## DamageModel, FighterHealth, CombatData (pure, `game/logic/`, owner: damage worker)
- `class_name CombatData extends RefCounted`: `static func weapon(id: String) -> Dictionary`,
  `static func armor(id: String) -> Dictionary`, `static func weapon_ids() -> PackedStringArray`,
  `static func armor_ids() -> PackedStringArray`, loaded once from `data/weapons.json` and `data/armor.json`.
  - Weapon def keys: `id, name, tier (0 fists .. 4), mass, length, grip_offset, balance_point (m from grip),
    shape ("fist"|"rake"|"bat"|"club"|"sword"|"axe"|"spear"|"shield"), edge_len (m of sharp edge, 0 = none),
    point (bool), blunt_factor, cut_factor, pierce_factor, two_handed (bool), half_sword (bool), color`.
  - Armor def keys: `id, name, part (one of the body part names, or "torso" for mail covering torso+pelvis),
    covers (Array of part names), mass, kind ("cloth"|"leather"|"mail"|"plate"), cut_resist, pierce_resist,
    blunt_resist (0..1 fraction removed), durability`.
  - v1 weapons: fists, rake, bat, club, gladius, longsword, axe, spear, shield_round. v1 armor: leather and iron
    pieces for head, torso, arms, legs, plus mail.
- `class_name DamageModel extends RefCounted`, static, deterministic, no RNG:
  `static func resolve(hit: Dictionary, tuning: Tuning) -> Dictionary`.
  - Input keys: `part, weapon_id, contact ("edge"|"point"|"flat"|"blunt"), rel_vel (Vector3, weapon point velocity
    minus target velocity), normal (Vector3, surface normal into the target), edge_alignment (0..1, how well the
    edge is lined up with the motion), effective_mass (kg), armor_ids (Array of armor ids covering that part),
    armor_wear (Dictionary armor id -> 0..1 worn)`.
  - Output keys: `energy (J), blunt, cut, pierce (damage points after armor), total, bleed (per-second bleed added),
    sever (bool), gut (bool), behead (bool), knockback (Vector3 impulse N·s), stagger (0..1), armor_wear
    (Dictionary of new wear values), glanced (bool)`.
  - Rules of thumb: below `Tuning.damage_min_speed` (about 3 m/s) nothing happens. Damage grows with kinetic energy.
    Edges cut, points pierce, flats and blunt weapons bruise and stagger. Plate nearly stops cuts but transmits blunt;
    mail stops cuts, not thrusts. Severing needs an edged hit on a limb or neck with enough cut after armor, with the
    part already hurt or the hit very strong; a beheading is a sever of `head`. Gutting is a strong cut or pierce to
    an unarmored torso or pelvis.
- `class_name FighterHealth extends RefCounted`: per-part hp (dict), `blood` (litres, starts 5.0, death below
  `Tuning.blood_death`), `bleed_rate`, `consciousness` (0..1), `stamina` (0..1), `severed: PackedStringArray`,
  `dead: bool`. `func apply(result: Dictionary, part: String) -> Array` returns gore event dicts (shape as `Fighter.gore`
  minus point/normal, which the fighter adds). `func tick(delta: float, exertion: float) -> void` bleeds, recovers
  stamina and consciousness. `func to_dict()/from_dict(d)` for snapshots.

## Tuning (lead-owned file `game/debug/tuning.gd`)
Workers do not edit it. Report the rows you need, in the `FIELDS` format
`[field, default, min, max, step, group, doc]`, in your final report; the lead adds them. Until then read with
`Tuning.shared().get("field")` guarded by a local fallback constant, or add rows the lead has already listed here:
`arena_radius 11`, `gravity 9.8`, `arm_force`, `damage_min_speed 3.0`, `blood_death 2.5` (see the file).

## Input keys already taken
F1 overlay, F2 slow-mo, F3 freeze, `.` single-step, F4 hide UI, F5 reserved, F6-F9 render toggles, F10 frame stamp,
F11 reserved, F12 save flight recording, backquote tuning panel, Escape pause.
Player 1: WASD move, mouse aim, LMB SWING, RMB OFFHAND, Q HALF_SWORD, Space THRUST, Shift SPRINT, Ctrl CROUCH,
E GRAB, Alt TURN_LOCK. Gamepads: left stick move, right stick aim, RT SWING, LT OFFHAND, RB THRUST, LB HALF_SWORD,
left stick click SPRINT, B CROUCH, A GRAB, right stick click TURN_LOCK. Player 2 local: second gamepad.
Touch (phones and tablets): a floating virtual thumbstick on the left half of the screen moves; a drag on the right
half sets aim directly (finger offset from where the drag started, mapped to -1000..1000, springs back to centre on
release); while the right finger is down SWING is held. On-screen buttons: OFFHAND, THRUST, HALF_SWORD, SPRINT, GRAB.
All three schemes (mouse, stick, touch) produce the same FighterInput, so nothing downstream knows the device.

## Files and owners (step 1)
| Worker | Model | Owns |
| --- | --- | --- |
| fighter-core | Opus | `game/fighter/*`, `tests/unit/test_fighter_*.gd`, `tests/sim/sim_fighter_*.gd` |
| damage | Sonnet | `game/logic/damage_model.gd`, `fighter_health.gd`, `combat_data.gd`, `data/weapons.json`, `data/armor.json`, `tests/unit/test_damage_model.gd`, `test_fighter_health.gd`, `test_combat_data.gd` |
| input | Haiku | `game/logic/fighter_input.gd`, `game/autoload/controls.gd`, `game/input/*`, `tests/unit/test_fighter_input.gd`, `tests/unit/test_input_reader.gd` |
| arena | Sonnet | `game/arena/*`, `game/camera/*`, `tests/unit/test_arena.gd` |
| tuning-panel | Haiku | `game/debug/tuning_panel.gd`, `tests/unit/test_tuning_panel.gd` |
Lead: `game/main.gd`, `game/main.tscn`, `project.godot`, `game/debug/tuning.gd`, `tests/sim/sim_suite.gd`, docs, git.
Report lines for lead-owned files (for example a sim name for `SIM_FILES`) in your final message.

## Sand and blood (the title is Sandblood: these are headline features)
Both are presentation: never part of `snapshot()` or the state hash, and they never change fight outcomes.

`class_name SandSurface extends Node3D` (`game/sand/`, owner: sand worker). Owns the arena floor's visual mesh and
material (the arena builds only the flat collider at y = 0 and calls `SandSurface.new()` / `setup(radius)`).
- A deformation heightmap plus a wetness/blood map covering the arena disc (about 2 to 3 cm per texel), applied in
  the floor shader (vertex displacement on a dense-enough mesh, normals from the map, darker damp sand where wet,
  red-brown blood that soaks in and darkens over time).
- `func stamp(pos: Vector3, radius: float, depth: float, push: Vector3 = Vector3.ZERO) -> void`: press a footprint,
  knee, fallen body or weapon tip into the sand, pushing a small rim up (and sideways along `push`).
- `func drag(from: Vector3, to: Vector3, radius: float, depth: float) -> void`: a furrow (dragged foot, sliding body,
  weapon tip dragged through the sand).
- `func add_blood(pos: Vector3, radius: float, litres: float) -> void`: soak blood in; pools spread a little.
- `func spray(pos: Vector3, vel: Vector3, amount: float) -> void`: kick up a sand puff (particles plus grains).
- `func height_at(pos: Vector3) -> float`: visual height offset in metres at a point (for decals and feet).
- `static` helpers for the pure map math so it is unit-testable.

`class_name BloodFx extends Node3D` (`game/fx/blood/`, owner: blood worker). Listens to `Fighter.hit` and
`Fighter.gore` (connect with `func track(f: Fighter) -> void`).
- Ballistic droplets (own lightweight particle sim on the CPU, pooled, budgeted for mobile) with spray direction
  from the hit normal and weapon velocity, arterial pulsing for severs and guts (spurts timed like a heartbeat that
  weaken as `health.blood` drops), drips from wounds and from bloodied weapons, streaks along the weapon edge.
- Droplets that land call `SandSurface.add_blood` (small clumps darken the sand), droplets that hit a body or
  weapon leave a stain (a per-fighter blood mask or decals).
- `var sand: SandSurface`, `func set_quality(level: int) -> void` (0 mobile .. 2 desktop high).

## Active damage and the blood meter (Curtis, 2026-10-21)
- Damage is active for both fighters, the player included: every wound shows on the body (cuts, bruises, stains,
  missing limbs) and changes how that fighter works. A hurt arm loses strength in proportion to its hp (slower,
  weaker swings, may drop the weapon when it is badly hurt or severed); a hurt leg slows walking, makes the fighter
  limp and stumble, and a severed leg drops them to the ground; head blows blur and slow (consciousness); blood loss
  weakens everything. The fighter reads `health.hp_frac(part)` every tick to scale per-limb strength.
- Your own weapon can hurt you (a wild swing into your own leg). Self-collision between a fighter's weapon and its
  own body is ON for parts other than the holding hand and forearm, and it goes through the same DamageModel.
- There is no health bar. The HUD shows a blood meter per fighter (litres left out of 5, draining live with the
  bleed rate, pulsing faster as it drops), plus stamina. Death and KO come from the health model, not a bar.

## Disarms and knocked-off armor (Curtis, 2026-10-21)
- A weapon can be knocked out of a hand: when a hit lands on the held weapon (weapon-on-weapon or shield) or on the
  holding forearm, compare the impulse at the grip with grip strength (arm hp, stamina, two hands on it). Above it the
  hand lets go and the weapon flies as a free RigidBody3D prop. Anyone can pick up a prop on the ground with GRAB
  (hand near the handle). Fists are always available.
- Armor pieces are real objects: each worn piece has a strap integrity (from its durability and wear). A strong hit
  on it, especially blunt or upward, can tear it off: the piece detaches as a free prop (a helmet flies and rolls in
  the sand), and the part is unarmored from then on. Props can be picked up but not re-equipped in v1.
- DamageModel output gains `dislodge` (bool, the armor piece hit comes off) and `disarm_impulse` (N·s at the grip,
  the fighter decides with its grip strength). New keys only; nothing existing changes.

## Finishing blows (Curtis, 2026-10-21)
- When the target's blood meter is low (`health.blood_frac()` = (blood - blood_death) / (5.0 - blood_death), under `Tuning.finisher_blood_frac`, default 0.4, about 3.5 L), a good enough
  hit becomes a killing blow chosen by weapon and contact: a thrust with a point to the torso or pelvis runs the target
  through (the weapon stays lodged, impaled), a strong edged cut across the torso guts them, a strong edged hit to the
  head or neck beheads, and a heavy blunt hit to the head crushes the skull. Any of these kills.
- The lower the blood, the less force a finisher needs (scaled from the normal sever/gut thresholds down to about a
  third near `blood_death`).
- DamageModel input gains the optional key `blood_frac` (0..1, default 1, from `health.blood_frac()`). Output gains `finisher` (String:
  "", "run_through", "gut", "behead", "skull_crush"). `FighterHealth.apply` emits a gore event with that kind and sets
  `dead`. Presentation (slow motion, camera, crowd roar, HUD announce) keys on `finisher != ""`.

## Sound (Curtis, 2026-10-21; music later)
`class_name SfxDirector extends Node` (`game/audio/`, owner: audio worker), sounds in `assets/audio/` (CC0 or
otherwise free-for-commercial-use only, every file credited in `docs/audio_credits.md`).
- `func track(f: Fighter) -> void` listens to `hit`, `gore`, `died` and polls `debug_frame()` for swing whooshes
  (pitch and volume from `tip_speed`), footsteps and body falls in sand, and armor rattle.
- Impacts by material pair: steel on steel (clang, ring), steel on wood/shield (thunk), wood/aluminium bat on body
  (crack, thud; the bat rings "tink" when aluminium), blade into flesh (wet cut), pierce, bone crack, armor (iron
  clank, mail jingle, leather slap), helmet knocked off (clang plus tumble), dropped weapon in sand.
- Gore: sever, behead, gut and run-through stingers; arterial spurt hiss; blood spatter on sand.
- Voices: effort grunts, pain cries scaled by damage, death gurgle (non-verbal only).
- Crowd: a looping arena ambience that swells with action; reactions (gasp, cheer, roar, boo) keyed on hit size,
  disarm, armor knocked off, KO, and a huge roar plus chant on a finisher. `func crowd_excitement() -> float`.
- Spatial 3D players (`AudioStreamPlayer3D`), pooled, random pitch/variant per play, a bus layout of Master > SFX,
  Crowd, Voice (Music reserved).
