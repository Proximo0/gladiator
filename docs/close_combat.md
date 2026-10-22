# Close combat: shove, front kick, grab

Half Sword-style physical moves for when the fighters are chest to chest. Pure timing and shape logic lives in
`game/logic/close_combat.gd` (`CloseCombat`, unit tests in `tests/unit/test_close_combat.gd`); the fighter turns it
into physics (`game/fighter/fighter.gd`, section "close range"). Every number is a Tuning row in the "Close" group.
Regression sims: `tests/sim/sim_close_combat.gd`.

## Controls

| Move | Bit | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- | --- |
| Shove | `SHOVE` 512 | F | D-pad up | SHOVE |
| Front kick | `KICK` 1024 | V | D-pad down | KICK |
| Grab the foe (hold to keep) | `CLINCH` 2048 | G | D-pad left | HOLD |

R, T, N, pad Y, Back and D-pad right stay with practice mode; E/A stays "pick up". The bits ride in the existing u16
buttons field of the input wire, but `NetConfig.PROTOCOL_VERSION` went 2 -> 3 on purpose: a protocol-2 host would
silently drop the new moves of a protocol-3 client, so the two must not be matched (lobby and EOS session filters
already compare the version). Touch adds a fourth column of buttons in landscape and a stack above the arc in portrait
(both inside the 42% width / 55% height budget of `test_touch_buttons_leave_the_aim_area_free`).

## How each move works

**Shove** (`shove_*` rows). On the press, standing or stumbling, not rolling or reaching down, with `shove_stamina`
to pay. The free left hand is driven out to `shove_reach` ahead of the chest at `shove_force_frac` of arm force, and
the hips drive forward at `shove_lunge`. A shield-holder shoves with the shield; with both hands on the weapon
(two-handed or half-sword grip) it is a shoulder charge. It lands in the window 20-75% of `shove_time` when the palm or
shield touches any part of the foe or the weapon in the foe's hand (real contacts), or the hand (or shoulder) comes
within `shove_contact` of the foe's torso or pelvis. A landed shove gives `shove_impulse` N·s (scaled by strength and
the arm's limb factor; 60% torso, 40% pelvis), pushes `shove_recoil` of it back on the shover and adds `shove_stagger`
stagger, plus `shove_stagger_off` when the foe is already off balance (stumbling, mid kick, balance under 0.6). That
second part is what floors a stumbling foe (0.35 + 0.55 > `stagger_down` 0.85). A shoving palm is not a punch: the
left fist's damage contacts are skipped while shoving or grabbing (a shield bash still hits). A held fighter that
shoves breaks the hold.

**Front kick** (`kick_*` rows). On the press, standing on both legs with nothing else under way. The lead (left) leg's
foot follows `CloseCombat.kick_foot`: knee up to `kick_chamber` (0-30%), drive out to `kick_reach` ahead of the hip at
`kick_height` (30-50%), held out (to 65%), drawn back down onto its spot. The foot is moved by the same PD foot force
as the gait (reaction on the pelvis), capped at `kick_force` instead of `foot_force_max`; the gait plans no new steps
and the planted leg carries the body; the hips drive in at `kick_lunge` while the leg is out. The shins report their
contacts, and in the window (30-80%) the first foe body part the foot meets takes a blunt blow through `DamageModel`
with the foot's real pre-step velocity and `kick_mass` (scaled by strength) as the effective mass (a kick never
severs or finishes), plus a `kick_push` impulse. A held shield or weapon in the way blocks it. Risks: a kick that meets
nothing leaves the kicker with `kick_miss_stagger` (stumbling), and stagger taken while on one leg is multiplied by
`kick_stagger_take` (a shove on a kicker floors them).

**Grab** (`clinch_*` rows). On the press, with a free left hand (no shield; a two-handed weapon's left hand lets go of
the shaft). The hand reaches for the foe's weapon (right) wrist, or the head when the aim is high (`aim_y` > 0.35), for
up to `clinch_time`. Within `clinch_latch` it closes: a `Generic6DOFJoint3D` between the holding forearm and the held
part, free to turn, its points kept within `clinch_slack` (a joint, not a spring: a PD spring stiff enough to hold
an arm was unstable on the 1.7 kg forearms at 60 Hz). The holding hand stays on the held point and draws it 12 cm at a
time toward `clinch_pull` ahead of the chest with its normal capped arm drive, so the holder pulls the foe in and stabs
with the weapon hand. While held, the foe's weapon arm keeps `clinch_pin` of its force (it cannot swing freely), or a
head-held foe keeps `clinch_head_balance` of its upright torque. The hand's fist stops colliding with the held part and
the hilt in that hand. The hold lasts while CLINCH is held, up to `clinch_max`, and costs the holder `clinch_stamina`
per second. It ends when the held point is pulled more than `clinch_break_dist` from the hand, when the holding arm
takes a staggering blow, when the held foe shoves, or when the held foe's struggle reaches 1: per second
`clinch_struggle` x effort (0.3 passive, up to 1 pulling away and pressing buttons) x its strength over the holder's.
`Fighter.snapshot()` / `restore()` drop a hold (the joint ties two fighters' bodies together and is not part of the
re-normalised engine state); replays run from tick 0, so they are unaffected.

## CPU use (sparingly)

`FighterBrain._maybe_close` runs after the roll check, on its own random stream (`_close_rng`), so the rest of the
brain draws exactly as before. At most one close move per `CLOSE_COOLDOWN_TICKS` (5 s), only standing with stamina
over 0.4, never while winding up, striking, finishing or fetching a weapon, and only on a standing or stumbling foe.
One draw against stacked chances per tick: shove under 1.25 m (0.6%, 5% when the foe stumbles), kick 1.0-1.3 m (0.4%),
grab under 1.2 m with a free left hand (0.5%, held 0.75-1.8 s while the brain keeps attacking). Held by the foe, the
brain pulls back and shoves now and then.

## Measurements

Bot vs bot, random loadouts, seeds 3000-3031, 60 s limit, `tools/bot_match.sh --matches=32 --seed=3000` (main at
4e36895 as baseline, run in two halves of 16; this branch in one run). Same seeds and loadouts, so the difference is
the close moves plus what they change downstream.

| | Baseline (main) | With close moves |
| --- | --- | --- |
| Mean fight length | 24.7 s | 22.3 s |
| Hits per minute | 85.2 | 88.0 |
| Knockdowns | 47 | 45 |
| Outcomes | blood loss 15, KO 8, finishers 9 | blood loss 15, KO 13, finishers 4 |
| Shoves (landed) | - | 28 (16, 57%) |
| Kicks (landed) | - | 12 (4, 33%) |
| Grabs (held, broken free) | - | 3 (2, 1) |
| Explosions, stuck | 0, 0 s | 0, 0 s |

Per fight that is about one shove, one kick every three fights and a grab every ten: sparing, as asked. Kicks land
less often than shoves because the foe moves in the 0.2 s the leg takes to come up, and a held weapon in the way
blocks them. KOs rose (8 -> 13) and finishers fell (9 -> 4): a shove or kick that floors a hurt foe gets a beating on
the ground before the finisher window opens. 32 fights is too few to call the finisher drop real; re-measure before
tuning against it.

Static land range (a scripted sweep, gladius vs gladius, the foe standing still, pelvis to pelvis): shove lands from
1.07 to 1.36 m (misses at 1.47), kick 1.06 to 1.36 m (misses at 1.46), grab 1.09 to 1.27 m (misses at 1.37). The
brain's bands sit inside those.

Sims (`sim_close_combat`): a shove pushes a standing gladius fighter 0.46 m into a stumble and floors one already
stumbling; a kick at 1.1 m lands once (foot 5.8 m/s, 16 blunt points to an unarmored thigh, foe pushed 0.78 m and
down); a kick at 3 m whiffs and leaves the kicker stumbling, not down; a grab latches in 4 ticks, holds 2.7 s and the
foe (pulling away and swinging) breaks free.

Renders (1280x720, cropped): `docs/renders/shove-kick/kick.png`, `shove.png`, `grab.png`
(`tests/render/close_capture.tscn`, keyed on distance and the move's own state).

## Known issues and next steps

1. The fighter draws no special pose for a hold or a shove beyond the hand target: a hand-on-chest palm and a
   wrapped grip would read better. The kick has no hip turn-over or lean back yet, so it reads as a knee-up push.
2. Presentation does not listen to `Fighter.close` yet: no shove grunt, kick thud on a block, or crowd reaction to a
   floor-by-shove. SfxDirector and the HUD can key on it (`kind`, `landed`).
3. The CPU never kicks a downed foe or grabs the head, and does not stab on purpose while holding (its weapon logic
   just keeps running). Practice mode has no step for the new moves.
Also: flight recordings masked buttons to 8 bits, so ROLL (256) never made it into a recording; fixed here (16 bits).
