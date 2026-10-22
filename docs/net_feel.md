# Online feel for the client (2026-10-22)

Goal: the client's own input should look answered at once at 80-150 ms RTT with jitter and 1-3% loss, while the
host stays authoritative. Everything below is visual only on the client: nothing new is sent, the snapshot is the
same 522 B, and PROTOCOL_VERSION stays 2.

## How it is measured

- `tests/sim/sim_net_feel.gd` (port 17981): host and client over real ENet on 127.0.0.1 with `NetLinkSim` both
  ways. The host's side 0 stands still; the client's side 1 runs a script, one action every 90 ticks: guard aim
  step, swing aim step (SWING held 30 ticks), guard aim step, dodge roll. For each one it records, on the client's
  screen and on the host, the ticks from the press to the first visible move (hand 3 cm; pelvis 3 cm or torso
  0.1 rad for a roll), to half the move, the largest one-tick move and the largest step back against the move.
  Alone: `sim_net_solo.gd -- sim_net_feel <rtt> <loss> <secs> [nolead]`; in the suite (no arguments) 150 ms / 3%
  for 24 s with checks.
- `tools/net_soak.sh --feel` runs it after the bot soak for each profile. The soak itself now also prints hit
  feedback: physics ticks from the host's hit to the client playing it (blood, sound, camera at the event tick)
  and to the client's confirm (the tick the event packet arrives).
- One process for both ends, so ticks are shared. 1 tick = 16.7 ms. "Host" columns are the host's own fighter
  answering the same input once it arrives: what an offline player would see, plus the uplink.

## Before and after (client, ticks from press; ms in brackets)

| | 80 ms / 1% | 120 ms / 2% | 150 ms / 3% |
| --- | --- | --- | --- |
| uplink: press to host applies | 4.0 | 5.0 | 6.2 |
| own hand, guard step, first move: before / after | 11.0 (183) / 2.0 (33) | 10.7 (178) / 1.7 (28) | 9.9 (165) / 1.2 (20) |
| own hand, guard step, half the move: before / after | 22.0 / 13.5 | 22.2 / 12.3 | 23.7 / 11.6 |
| own hand, swing step, first move: before / after | 9.2 (153) / 0 | 11.2 (187) / 0 | 11.3 (188) / 0 |
| own hand, swing step, half the move: before / after | 13.2 (220) / 2.4 (40) | 15.1 (252) / 2.3 (38) | 17.1 (285) / 2.4 (40) |
| offline reference (host answer after apply): guard half / swing half | 11.8 / 3.4 | 10.6 / 3.3 | 10.4 / 3.4 |
| roll start, first visible dip: before / after | 14.3 (238) / 3.0 (50) | 16.0 (267) / 3.0 (50) | 18.4 (307) / 3.0 (50) |
| offline reference (host dip after apply) | 4.5 | 4.6 | 4.8 |
| hit feedback after the host's hit: played (before = after) | 5.0 | 6.0 | 7.0 |
| hit feedback: confirm on arrival (new) | 2.5 | 3.6 | 4.5 |
| full body pose, input to screen (unchanged, host-authoritative) | 10.4 (173) | 12.3 (205) | 14.2 (237) |
| smoothness, swing step: largest one-tick move client / host | 0.18 / 0.18 m | 0.19 / 0.18 | 0.18 / 0.18 |
| smoothness, swing step: step back client / host (before: client 0.08-0.09) | 0.12 / 0.09 m | 0.12 / 0.09 | 0.09 / 0.09 |
| bandwidth host->client avg / peak | 16.2 / 18.5 KB/s | 16.5 / 18.3 | 16.9 / 19.5 |

Same results both ends in every soak match, all events played, no resyncs. The guard "step back" is mostly the
host arm's own settle (host 0.20-0.27 m in the same windows). The swing step back is counted until SWING is let go
(the release pulls the hand in: a new command, not a correction).

## What changed

1. **Own weapon hand lead** (`NetHandLead`, `NetWorld.lead_hand`). The client runs the host's hand-goal maths
   (`NetCursor.predict`, rate-limited at guard / swing hand speed like `Fighter._arms`) on its local input every
   tick, plus a critically damped spring standing in for the arm (`HAND_LEAD_OMEGA` 40/s: fits the host arm, which
   starts one tick after the input and is half way in 3). It keeps the modelled hand per input tick. The lead is
   the modelled hand now minus the modelled hand at the input the shown snapshot had applied (ack, less
   `HAND_LEAD_ACK_LAG` = 1 tick: a snapshot's bodies are captured before that tick's physics step). It is zero
   whenever the aim has been still for a round trip, whatever the host did with the arm, so it cannot drift.
   Drawing: a two-bone reach of the right arm from the shoulder (bone lengths kept, elbow side kept), carrying what
   the hand holds; with a two-handed or half-sword grip the left arm reaches for where its grip went.
   Handover: what the modelled hand does this tick shows at once (a new command); the rest of the way to the
   target is the host catching up and is smoothed over the ack's tick steps (`HAND_LEAD_SMOOTH_S`), and the lead
   may shrink along itself only as fast as the shown hand advances that way plus a 0.2 s release. Without that
   last rule the lead was taken back before the shown arm moved, and a swing stepped back 15-17 cm (host 8-9).
2. **Roll start lead** (`NetRollLead`, `NetWorld.lead_roll`). On the ROLL press, when the shown fighter could roll
   (standing, stamina >= `roll_stamina`, off a predicted roll_time + roll_cooldown), the opening dip starts at once:
   everything from the hips up lowers and leans toward the roll (RollLogic's direction rule, dip and lean curves,
   shoulder axis); the thighs turn about the knees. Handover is a time shift: the lead is the dip at the time since
   the press minus the dip at the time since the shown snapshots started rolling, so the sum never jumps and the
   lead ends when the shown dip completes. When the shown ack passes the press by 3 ticks and no roll shows (the
   host refused it), the lead fades over 0.1 s (`cancels` counts these). Caps: 0.2 m drop, 0.45 rad lean.
   The host now sets bit 6 of each fighter's snapshot flags while it rolls (`NetFighterSnap.rolling`). Same size;
   older builds read the prop count with `& 15` from bits 2-5 and ignore it, so no protocol bump (different builds
   already refuse each other on the content hash).
3. **Hit confirm on arrival** (`NetClientDriver.hit_confirmed(ev, tick)`). A hit that this side dealt or took is
   confirmed the tick its EVENTS packet arrives, one interpolation delay (2.5 ticks, ~40 ms) before its tick plays:
   the weapon cursor pulses (size and red, `HIT_CONFIRM_FLASH_S` 0.15 s, scaled by the hit's total) and the signal
   fires; when the presenter has a `hit_confirm(ev, tick)` method the driver connects it. Blood, sound, sand and
   camera still play at the event's tick, in step with the picture.

Snap-free: both leads are drawn over the pose `NetWorld.apply` sets each tick, so they never accumulate, and both
are clamped. `NetClientDriver.leads_enabled` switches them off (the feel sim's `nolead`). The soak skips the own
fighter's error samples while a lead is drawn (`own lead share` in its table; the foe's pose is unchanged).

## Known limits

- The full body (footwork, the foe's reaction, a clash) still arrives at the host's pace: input to screen is RTT
  plus ~78 ms as before. The leads cover the own hand, weapon and roll start only.
- A hand lead runs through whatever the host's arm hits (a parry, the foe's body) for up to one round trip, then
  eases back; with constant bot aiming the lead averages 14-24 cm at 80-150 ms.
- `NetLinkSim` never loses a reliable packet, so a lost EVENTS packet's ENet retransmit (about one RTT late) is not
  in these numbers.
