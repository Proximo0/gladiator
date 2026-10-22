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

## Poses (close-combat polish)

The kick's foot path (`CloseCombat.kick_foot`) has four phases: chamber (0-30%: knee up, foot under it), snap
(30-45%: the leg drives out, about 1.3x the old extension rate), hold (to 60%), re-chamber (to 80%: the foot snaps back
under the raised knee) and down. `CloseCombat.kick_lean` leans the upper body back by up to `kick_lean_back` while the
leg is out, as a counterweight (sim: torso tipped back 0.23 rad; before it leaned in 0.04).

A hold no longer just draws the held point toward the chest. `CloseCombat.hold_pull_goal` hauls a weapon arm across to
the holder's free side and down (`clinch_pull_side`, `clinch_pull_down`) and a head straight down (`clinch_head_down`);
the hand leads the held point by `clinch_pull_step` with its own force share (`clinch_pull_force_frac`), and the
holder's chest turns toward the free side (`clinch_twist`) to put the body into it. Sim `close_hold_hauls_arm`: in the
second after the latch the held wrist moves 0.29 m (in 0.28, across 0.07) and the foe's chest turns 0.17 rad (before:
0.06 m and 0.07 rad). In the full suite (after other sims) the same row gave in 0.23, across 0.03, turn 0.18 rad.

## Sound and crowd

`SfxDirector.on_close` plays `SfxLogic.close_plan`: a landed shove is a body thud, a palm slap, the shover's effort
grunt and the foe's grunt; a kick is an effort grunt, plus a slow whoosh on a whiff or a thump when a shield or weapon
blocks it (`Fighter.close` events carry `blocked`); a hold is a grip slap and both fighters' grunts; a break is the
freed fighter's grunt. A landed kick's blow goes through the normal hit path (`impact_plan`) with its own "kick"
material: a body thud and a heavy thump instead of a fist punch. A held fighter grunts every 0.9 s
(`SfxLogic.STRUGGLE_GRUNT_GAP`). The crowd gets a small lift from each move (`CrowdModel.close_impulse`) and gasps when a
fighter goes down within 1.5 s of a landed shove or kick on them (`CrowdModel.floored_reaction`). Every key already
has files in `assets/audio`.

## Practice and hints

Practice mode teaches the moves after "strike": "shove" (two landed shoves), "kick" (two landed kicks) and "hold" (one
unbroken 1 s hold; "grab" stays the weapon pick-up step). Counts come from `Fighter.close` and survive bout resets.
`sim_practice` drives all eleven steps by state. The in-fight hint (`ControlsText.compact_lines`) lists the moves for
keyboard (second line: F shove, V kick, hold G), pad (D-pad shove/kick/hold) and touch (SHOVE, KICK, HOLD, the CROUCH
toggle and hold-GRAB pickup).

Render: `docs/renders/close-polish/kick_before_after.png` (top before, bottom after; kick at 25%, 45% and 70%:
chamber, out, re-chamber), from `tests/render/close_capture.tscn -- --move=kick --at=U`.

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

### After the polish (poses, sound, practice)

Same seeds, base = the merged lead lines before this work, `tools/bot_match.sh` (60 s limit).

| | Before, seeds 3000-3031 | After | Before, seeds 4000-4063 | After |
| --- | --- | --- | --- | --- |
| Mean fight length | 23.2 s | 24.3 s | 25.3 s | 25.1 s |
| Hits per minute | 81.5 | 82.1 | 76.7 | 76.5 |
| Knockdowns | 52 | 51 | 62 | 64 |
| KOs | 10 | 11 | 12 | 14 |
| Shoves (landed) | 26 (11, 42%) | 24 (9, 38%) | 56 (30, 54%) | 61 (31, 51%) |
| Kicks (landed) | 6 (2) | 8 (4) | 11 (6, 55%) | 11 (6, 55%) |
| Grabs (held, broken free) | 7 (5, 2) | 6 (4, 3) | 14 (12, 9) | 14 (13, 7) |
| Explosions, stuck | 0, 0 s | 0, 0 s | 0, 0 s | 0, 0 s (1 getup fail) |

Fight length and land rates are unchanged within noise (96 fights; the CPU kicks about once every six fights, so kick
rates need a forced-kick run to say more). A landed kick in `sim_close_combat` does 26.5 points (was 16.4) at a lower
peak foot speed (5.3 m/s, was 5.8): the snap brings the foot in on a straighter line at contact.

## Known issues and next steps

1. The shove still has no special palm pose beyond the hand target, and the kick no hip turn-over.
2. The CPU never kicks a downed foe or grabs the head, and does not stab on purpose while holding (its weapon logic
   just keeps running).
3. A reaching hand that runs into the foe's fist or blade is "hit" at the reach's own speed (contacts resolve on
   relative velocity), and a stagger over 0.2 on the holding arm breaks the hold: in one sim run a passive foe's left
   fist broke a fresh hold this way (5.1 m/s, stagger 0.29).
Also: flight recordings masked buttons to 8 bits, so ROLL (256) never made it into a recording; fixed here (16 bits).
