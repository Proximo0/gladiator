# Online security and anti-cheat review

Review of `game/net/*` and `game/store/*` (October 2026, branch `claude/project-thread-l9rbe3`): what a modded client
or a hostile host can do to the other machine, the match and the ratings. The fight is host-authoritative
(`docs/online_brief.md`): the host simulates both fighters, the client sends only inputs. Results and ratings follow
`docs/online_service.md` (Tier 0 on EOS: no server, each player rates itself).

Severity: **Critical** = one packet takes down the other machine; **High** = a cheat that changes ratings or
purchases without effort; **Medium** = crash, script error or unbounded growth from crafted data; **Low** = noise
or a bounded nuisance.

## Findings

| # | Severity | Issue | Status |
| --- | --- | --- | --- |
| 1 | Critical | **Host freeze from one input packet.** `NetInputBuffer.pop()` skipped a too-deep buffer by walking every tick from the next one to the newest. A client packet with tick 4 294 967 000 made the host loop ~4 billion times in one physics tick (measured 80 ms per million ticks, so ~340 s per packet, repeatable). | Fixed: a tick may jump at most `MAX_AHEAD` = 600 past the newest held, at most `MAX_HELD` = 256 wait, and skipping walks the held keys. Worst pop on a hostile stream now under 1 ms (`test_net_fuzz`). |
| 2 | High | **Drop-to-win on Tier 0.** A losing player blocks the game's traffic (a firewall rule, no modding) and leaves the EOS lobby. On its own device only its own `dropped` report exists, and `Rating.reconcile` made a lone `dropped` a forfeit **win for the reporter**. Also a `dropped` report beat the other side's real `result` when it came first. | Fixed: a `dropped` report names who was ahead on points when the link died (`MatchJudge.leader`, the time-limit rule) as its winner, and a lone `dropped` forfeits only to a reporter that was ahead after `MIN_RATED_TICKS`; otherwise void. A `result` report beats a `dropped` one on both devices. |
| 3 | High | **The host decides the result.** The client reports what the host's OVER says, so a modded host (any Quick Match lobby owner) can send itself as the winner and both reports agree. | Accepted risk for v1. Next step: the client cross-checks OVER against the snapshots it saw (claimed loser dead or KO'd, blood order for a time decision) and reports "disputed" on a mismatch; then a Tier 1 verifier. |
| 4 | High | **Self-written stats.** On Tier 0 each client ingests its own `sb_rating` (a "Latest" stat), games, wins and losses. A modded client can write any rating and top the leaderboard. | Accepted risk until a server exists. Fix: the client policy loses Stats ingest; a small verifier (both signed reports in, `Rating.reconcile`, ingest with server credentials) writes the stats. Shadow-flag ratings that move more than K per game in the meantime. |
| 5 | High | **Premium and earned items are not verified online.** The host sanitizes the client's loadout with `owned = null` (`LoadoutRules.sanitize`), so a modded client can fight with `dai_katana` / `laser_sword` and wear the premium outfits without buying them; earned weapons live in a local file. `StoreLocal` grants for free (dev only, never in release, `StoreFactory`). | Accepted risk: needs proof of ownership. The client sends a store receipt with HELLO (an Epic Ecom ownership token is a JWT signed by Epic that the host can check offline against Epic's public keys; a Google Play purchase token needs a server call) and the host falls back to `PREMIUM_FALLBACK` without one. Ranked Quick Match could also allow only starter weapons until then. |
| 6 | Medium | **Lobby messages with wrong-typed fields raised script errors** and aborted the handler: a non-numeric `v` ("Nonexistent 'int' constructor"), a `loadout` or `armor` that is not a dictionary, a body that decodes as a typed dictionary (refuses the `_type` key), a non-bool `accepted`, NaN or huge `time_limit_s`. | Fixed: `NetLobby.dict_of` / `int_of` / `float_of` for every decoded field, typed dictionaries refused, `LoadoutRules.sanitize` takes any armor value, START's time limit capped at 3600 s, `NetClientDriver.on_over` typed. |
| 7 | Medium | **No flood limit.** The session handled every packet it received each tick; an input packet could claim 255 rows; reliable control messages had no rate limit. | Fixed: at most `MAX_PACKETS_PER_TICK` = 64 handled per tick (legit traffic is 1-3, a 1 s hitch ~60), none over 4 KB, input packets must be exactly 1-16 rows with no tick below 0, control messages at most 20 per second. The rest are drained and counted in `NetSession.dropped_packets`. ENet still receives and reassembles a large packet before we drop it (its own limit, engine side). |
| 8 | Medium | **Repeated HELLO** after joining renamed the player and swapped its loadout (and fired `lobby_changed`) at any time, also mid-match. | Fixed: one HELLO per connection. LOADOUT still works in the lobby; mid-match it only changes the rematch pick (the fighter's loadout is fixed at setup, checked by `sim_net_cheat`). |
| 9 | Medium | **Event decoder (client side, hostile host).** Truncated packets read past the end (engine errors, zeros), half floats could be NaN or infinite, mask bits outside the key table were ignored, any record count was read, non-ASCII strings printed a UTF-8 error each, and the client's event queue had no bound (events stamped far in the future stayed for ever and were scanned every tick). | Fixed: every read is checked first, masks outside `KEYS` and more than 32 records refuse the packet, non-finite halves read 0, sides clamp to -1..1, strings must be printable ASCII, the client queue keeps the newest 512. |
| 10 | Medium | **Report decoding.** `ServiceEos.decode_report` raised a script error on a non-numeric `ticks`; an empty match key made HMAC log an engine error. | Fixed: `int_of` for ticks; `Rating.sign_report` / `verify_report` refuse an empty key. |
| 11 | Medium | **Self-declared opponent rating.** The rating used for the Elo update comes from the opponent's lobby attribute (clamped 100..9999 in `ServiceBoard.note_opponent`). Announcing 100 makes a win against the cheater worth nothing and a loss cost a full K. | Accepted risk (Tier 1 reads the opponent's stats server side). |
| 12 | Medium | **Quitting by killing the app** writes no report on the quitter's device, so Tier 0 never records its loss. | Accepted risk; with the rule in #2 the opponent still gets the forfeit if it was ahead. Count drops per player once a server exists. |
| 13 | Low | `bytes_to_var` prints engine errors for a garbled body and has no quiet mode, so a peer could fill the log. | Accepted: bounded by the 20/s control-message limit. A JSON body (silent parse) would remove it but changes the wire (protocol bump). |
| 14 | Low | **Input rate and range.** Axes are clamped to ±1000 (`FighterInput.from_array`); unknown button bits are ignored by the fighter; the hand goal chases the aim at `swing_hand_speed` (30 m/s); move speed comes from Tuning. A macro can flip the aim corner to corner every tick, which a hand cannot. | Accepted: measured in `sim_net_cheat`, the macro's hand goal tops out at the same 30 m/s as legal mashing, its pelvis speed stays inside the legal baseline, and its hit rate is about the same (see below). |
| 15 | Low | **EOS credentials.** Never logged: `EosConfig` errors name missing fields only, `describe()` hides the secret (tested), the file is git-ignored and was never committed (`git log --all -- config/`). The client id and secret ship inside every EOS build by design (EOS client credentials are not secret on a client), and the export scripts copy the file next to the exe. | Accepted. Keep the client policy minimal (GameClient: Connect, Lobbies, P2P, Leaderboards read; drop Stats ingest once #4 is fixed), keep build zips private, rotate the secret if a build leaks. |
| 16 | Low | **Hostile host to client.** Snapshots are parsed with bounds already (2 fighters, 32 bodies, 8 props, state clamped, a time scale under 0.05 ignored). A host can pose the fighters anywhere, but it owns the fight anyway. | No change. Fuzzed (`test_net_fuzz`) and attacked live (`sim_net_cheat`): no errors, poses stay finite. |
| 17 | Low | **The match key is readable** by both members (a lobby attribute), so the HMAC only ties a report to its match and player, it does not stop a cheating client signing what it likes. | Accepted, as documented in `online_service.md`; the verifier fixes it. |

**Protocol version:** not bumped by this work. The wire format is unchanged; the stricter parsing accepts every
packet a legit build sends (exact-size input packets of 1-16 rows, plain dictionaries, ASCII ids in events).

## Tests

- `tests/unit/test_net_fuzz.gd`: seeded mutation fuzzing, 3000 rounds per case (byte overwrite, extreme bytes,
  truncation, appends, inserts, repeated slices, 10% pure noise; the type byte survives 80% so parsers go deep)
  plus structured mutation (valid `var_to_bytes` bodies whose fields hold any Variant: NaN, huge ints, arrays,
  typed and nested dictionaries, StringNames, colours). Cases: input packets into a live jitter buffer, hostile tick
  patterns (a tick near 2^32, ticks walking ahead, scattered 16-row packets), snapshots (decode, blend,
  extrapolate), events, the NaN half, lobby messages through both roles' handlers, HELLO once, signed reports,
  a 5000-packet flood plus a 64 KB packet through `NetSession`. A `Logger` counts every engine and script error; only
  the engine's own unmarshal complaints for garbled `var_to_bytes` bodies are counted apart (#13).
- `tests/sim/sim_net_cheat.gd` (in the suite): host and client over real ENet on localhost. 6 s honest bot, 6 s legal
  max-effort mashing (sprint at the foe, swing held, roll at 6 Hz, aim swept), then 10 s of a modded client (aim
  flipped between opposite corners every tick, random 16-bit buttons, plus raw abuse: ticks near 2^32, 16-row
  packets of random rows, every message type mutated, START/OVER/SNAP/EVENTS sent the wrong way, a 500-packet
  flood, a 64 KB packet, HELLO and LOADOUT with wrong types and a premium weapon, a tick walk past `MAX_AHEAD`),
  then 2 s of a hostile host sending mutated snapshots and far-future events.
- `tests/unit/test_rating.gd`: the drop rule (#2); `test_match_judge.gd`: `MatchJudge.leader`.

## Numbers

| Measure | Before | After |
| --- | --- | --- |
| One pop after the stream jumps 1 000 000 ticks | 79 ms (one packet) | 0.33 ms (the walk in 600-tick steps, 256 held, the rest refused) |
| One pop after a tick near 2^32 (one packet) | ~340 s (extrapolated, 80 ms per million) | 2 µs (the packet is refused) |
| Packets handled per tick from a flooding peer | unbounded | 64 (`sim_net_cheat`: 334 of a 500-packet burst dropped, both sessions stayed open, snapshots kept flowing) |
| Script and engine errors from fuzzed lobby / report / event data | 6 kinds (#6, #9, #10) | 0 in 3000 rounds per case |
| Hand goal speed, modded client | n/a | 30.0 m/s (the Tuning cap; legal mashing reaches the same 30.0) |
| Peak pelvis speed, modded client | n/a | 5.2 m/s (legal mashing 5.9, bot 2.4) |
| Side-1 hits per second (INFO; varies run to run with Jolt) | n/a | modded 1.7, legal mashing 1.5, bot 0.8 (a second run: 0.0, 2.3, 0.5) |
| Rated outcome of "block traffic while losing, leave the lobby" | a win on the cheater's device | void |

## Next defects

1. The host can declare itself the winner (#3): client-side cross-check of OVER against snapshots, then the verifier.
2. Stats are client-written (#4): a Tier 1 verifier with server credentials; Stats ingest off in the client policy.
3. Ownership of premium weapons and outfits is not proven online (#5): a store receipt in HELLO, checked by the host.
