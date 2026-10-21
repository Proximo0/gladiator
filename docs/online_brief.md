# Online 1v1 brief

Contract for v1 online play: one host, one client, direct IP and port over ENet (UDP), on Windows, Mac, Linux and
Android in any combination. Code in `game/net/`, the lobby in `game/ui/menu/online_screen.gd`, tests in
`tests/unit/test_net_*.gd` and `tests/sim/sim_net_*.gd`.

## Model: host-authoritative, client renders

Jolt is not deterministic across machines (and not even run to run: see lessons_learned), so lockstep and rollback
are out. The **host simulates both fighters** exactly as offline: its own side 0 from its devices, side 1 from the
client's input stream. The **client simulates nothing**: it builds the same Match from the same seed and loadouts
(so it has the same bodies, art, armor and weapons), switches the simulation off, and poses the bodies from the
host's snapshots, a little in the past, interpolated. Hits, gore and the result come from the host as events.

The only thing the client predicts is its **weapon-hand cursor**: `NetCursor` runs the fighter's own guard-target
maths (`FighterMath.guard_target`) on the interpolated torso and facing with the *local* aim, the same tick the
mouse or stick moves, and draws a small marker there. The arm itself follows one round trip plus the
interpolation delay later. Predicting the ragdoll would mean simulating it on the client and correcting it from
the host, which Jolt's divergence makes jittery; a cursor gives aim feel without that.

## Messages

Every packet starts with a type byte (`NetConfig.MSG_*`). One ENet channel; unreliable ordered or reliable by
transfer mode. Max one client per host.

| Type | Dir | Mode | Rate | Payload |
| --- | --- | --- | --- | --- |
| HELLO (1) | C→H | reliable | once | `var_to_bytes({v, name, loadout})` |
| LOBBY (2) | H→C | reliable | on change | `{v, name, loadout, accepted, reason}` |
| LOADOUT (9) | C→H | reliable | on change | `{loadout}` |
| START (3) | H→C | reliable | per match | `{seed, loadouts[2], time_limit_s, names[2]}` |
| INPUT (4) | C→H | unreliable ordered | 60 Hz | newest tick u32, count u8, then count × (move_x, move_y, aim_x, aim_y i16, buttons u8), newest first |
| SNAP (5) | H→C | unreliable ordered | 30 Hz | see below |
| EVENTS (6) | H→C | reliable | when hits happen | count u8, then per event: tick u32, fighter u8, kind u8 (hit/gore), key mask u32, present values |
| OVER (7) | H→C | reliable | once | `{winner, reason, ticks, seed}` |
| LEAVE (8) | both | reliable | once | `{reason}` |

Lobby messages are `var_to_bytes` dictionaries (objects refused by `bytes_to_var`, 4 KB cap). The protocol version
is checked on HELLO; a mismatch is refused with a reason.

**INPUT** carries the last `INPUT_REDUNDANCY` = 4 ticks, so any packet that arrives fills the gap of up to 3 lost
before it. The host's `NetInputBuffer` plays the client's ticks in order, `INPUT_BUFFER_TARGET` = 2 ticks behind the
newest received; a missing tick repeats the last input (and is skipped once newer ticks are in), a buffer deeper
than `INPUT_BUFFER_MAX` = 10 skips back to the target (client clock running fast, or a burst).

**SNAP** (`NetSnapshot`): header 12 bytes (type, host tick u32, last applied client input tick u32, flags, engine
time scale u8, fighter count), then per fighter (`NetFighterSnap`) 31 bytes of meta and 16 bytes per body:

- meta: state u8, flags (dead, gutted), blood u16 (0.1 ml), bleed rate u16, stamina u8, consciousness u8, severed
  mask u16 (FighterRig order), armor-worn mask u8 (the loadout's armor order), 11 × part hp fraction u8, facing yaw
  u16, hand target 3 × i16.
- bodies: the 11 parts in `FighterRig.PARTS` order, then the fighter's weapons in creation order (right fist, left
  fist, main weapon, off hand; dropped weapons stay in the list, so props are covered). Each body: position 3 × i16
  at 1 mm (±32.7 m), rotation 32-bit smallest-three (≤0.25° error), linear velocity 3 × i16 at 1 cm/s.
  Angular velocity is not sent (the client never integrates rotation).

The engine time scale rides along so the client follows the host's knockout slow motion with its own physics clock.

**EVENTS** (`NetEvents`): a fixed key table (attacker, target, part, weapon_id, contact, point, normal, rel_vel,
cut, pierce, blunt, total, bleed, energy, stagger, glanced, hit_on_weapon, disarmed, arm_drop, sever, behead, gut,
finisher, armor_ids, kind, amount, dislodge, edge_alignment, knockback). Booleans live in the mask, zeros and
empty strings are left out, floats are halves, points 1 mm i16, normals 3 × i8. A typical hit is 40-60 bytes. The
client queues each event by tick and re-emits it on the fighter's `hit` / `gore` signal when its render clock
reaches that tick, so blood, sound, sand and the announcer fire in step with the picture.

## Rates and byte budget (per direction, target under 30 KB/s)

Overhead is counted at 42 bytes per packet (IPv4 20 + UDP 8 + ENet ≈ 14).

| Stream | Payload | Rate | Bytes/s |
| --- | --- | --- | --- |
| SNAP, typical (14 bodies each) | 12 + 2 × (31 + 14 × 16) = 522 | 30 Hz | 16.9 KB/s |
| SNAP, worst (15 bodies each) | 554 | 30 Hz | 17.9 KB/s |
| EVENTS | ~50 per hit, bursts of 1-5 | a few/s | < 1 KB/s |
| **Host → client total** | | | **~18-19 KB/s** |
| INPUT (4 ticks) | 6 + 4 × 9 = 42 | 60 Hz | 5.0 KB/s |
| **Client → host total** | | | **~5 KB/s** |

Measured (sims below): host→client 17.1 KB/s average, 18.4 KB/s peak 1 s window; client→host 5.0 KB/s.
Headroom: snapshots could go to 40 Hz (`SNAP_EVERY_TICKS` can't express that at 60 Hz; 60 Hz would be 34 KB/s), or
the budget can be cut in half with delta compression against the last acked snapshot if mobile data matters.

## Latency handling

- Client render clock (`NetInterpBuffer`) runs in host ticks, `delay` behind the host's newest tick:
  one snapshot interval + 1 + 2 × measured arrival jitter, clamped 3..24 ticks (50..400 ms). It eases at up to
  ±10% speed toward its target, jumps on a 30-tick error, never runs backwards. The host-minus-local offset tracks
  the late edge of the stream (falls fast on a late packet, rises slowly).
- Past the newest snapshot it extrapolates by velocity for up to 6 ticks (100 ms), then holds.
- Input to screen (client presses, sees the host's answer): round trip + input buffer (2 ticks) + half a snapshot
  interval + interpolation delay. Measured 8.5 ticks (142 ms) on a clean localhost, 18.6 ticks (310 ms) with a
  fake 50-83 ms one-way link and 5% loss. The cursor is 0 ticks.
- `--net-lag=<ms> --net-jitter=<ms> --net-loss=<0..1>` fake a bad link on what this machine sends (NetLinkSim).
- 5 s without a packet during a match, or 10 s without reaching the host, closes the session with a reason.

## Pure logic vs nodes

Pure `RefCounted` (no Node, no clock, no global random; unit tested): `NetConfig`, `NetQuant`, `NetFighterSnap`,
`NetSnapshot`, `NetInputPacker`, `NetInputBuffer`, `NetInterpBuffer`, `NetEvents`, `NetLobby`, `NetBandwidth`,
`NetLinkSim`, `NetCursor`. `NetRemoteBrain` (a `FighterBrain` that pops the input buffer) is pure too.

Nodes and engine glue: `NetSession` (ENet peer, polling at physics priority -20, lobby, routing, byte counting),
`NetHostDriver` (child of the host's Match, priority 20: snapshots, events, result), `NetClientDriver` (child of
the client's Match, priority -10: reads the device, sends inputs, interpolates, poses, replays events, HUD and
camera on side 1, cursor), `NetWorld` (reads a Fighter into a snapshot; makes a Fighter a kinematic puppet and
poses it), `OnlineScreen` (lobby UI).

## Integration points

- **Menu**: Title → "Online 1v1" → `OnlineScreen` (name, Host on a port with this machine's LAN addresses shown,
  or Join by `ip[:port]`, your loadout with the usual pickers, the opponent's shown). The host's FIGHT sends START;
  both `MenuFlow`s build the match with `NetLobby.match_config(start, true)` and call `NetSession.attach_match()`.
  Result screen: host gets Rematch / Back to lobby / Leave, the client Back to lobby / Leave. Esc in an online match
  opens a menu without pausing the tree. A dropped connection shows "Connection closed" with the reason.
- **Match** (unchanged): both sides set it up as `player_vs_cpu`. Host: `brains[1]` is replaced by a
  `NetRemoteBrain`. Client: `Match.set_physics_process(false)`; its `readers[0]` (device "auto") is the local
  input; the driver feeds `presenter.tick()`, sets `tick`, `over`, `result` and emits `match_over`.
- **Fighter** (unchanged): the client puppet uses `freeze` (kinematic) on every body, and reaches private members
  through `get`/`set`/`call`: `_weapons`, `_armor`, `_armor_meshes`, `_yaw`, `_hand_target`, `_state`, `_sever()`,
  `_die()`. Kinematic bodies moved by transform report the right `linear_velocity` under Jolt (checked by
  `sim_net_presented`), so sand and sound work unchanged.
- **Android**: `permissions/internet=true` is already in `export_presets.cfg`.

## NAT traversal and relay (later)

v1 is direct: the host must be reachable on UDP 7777 (same LAN, a forwarded port, or a VPN mesh such as Tailscale
or ZeroTier). For play across home routers:

1. A small rendezvous/matchmaking server (room codes instead of IPs) that tells each peer the other's public
   UDP endpoint, then **UDP hole punching**: both sides send to each other from the port they registered with
   (ENet can bind its local port; `ENetConnection` gives the raw host for the punch packets).
2. A **relay** fallback for symmetric NATs and carrier-grade NAT (common on mobile data): a UDP forwarder per match,
   ~23 KB/s each way per match at current rates.
3. Or a service that does both: Steam Networking Sockets (Steam builds), Epic Online Services P2P (free, all our
   platforms), or WebRTC with STUN/TURN (`WebRTCMultiplayerPeer`; needs the webrtc-native extension on desktop).
   `NetSession` only uses the `MultiplayerPeer` packet API (`put_packet`, `get_packet`, transfer modes), so any of
   these peers can replace `ENetMultiplayerPeer` behind `host()` / `join()`.

## Tests

- `tools/run_tests.sh test_net_*`: quantisation error bounds, snapshot and event round trips and sizes, input
  redundancy under 20% loss, the jitter buffer, the interpolation clock under 0-8 tick jitter, lobby messages and
  address parsing, the fake link, the byte meter, the cursor maths.
- `tests/sim/sim_net_loopback.gd`: host and client in one process (client match in a SubViewport with its own
  World3D and physics space), real ENet sockets on 127.0.0.1, fake 50 ms + 0-33 ms jitter + 5% loss each way,
  10 s match. Checks lobby, snapshots arrive, inputs reach the host and walk its fighter, budget, same result,
  client state equals host state at the same tick within quantisation, every event plays.
- `tests/sim/sim_net_presented.gd`: the same with full presentation on both sides and a clean link (kinematic
  speed for sand/sound, the cursor).
- `tests/sim/sim_net_menu.gd`: two MenuFlows, host / join by typed address / lobby pick / FIGHT / client leaves.
- Not in the suite: `tests/sim/sim_net_peer.gd` runs one side as its own process, real time
  (`--role=host|client --port=17951`), to check two separate engines; and `tests/sim/sim_net_solo.gd` runs one net
  sim outside the suite.
