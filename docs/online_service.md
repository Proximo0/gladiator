# Online service layer (quick match, ratings, leaderboard)

Sandblood is mainly a multiplayer game: Quick Match, a rating and a leaderboard. The fight itself is the host-authoritative
ENet model in `docs/online_brief.md`; this layer decides **who you play, who hosts, how the result is judged and what the
leaderboard shows**. The menus talk only to `OnlineService`; a backend is a subclass. **Chosen backend: Epic Online
Services (EOS)**, as `ServiceEos` (written against EOSG 2.3.1; install and test plan in `docs/eos_setup.md`). Without
the plugin binaries or the credentials file the game uses `ServiceLocal` (Quick Match on a LAN), and `ServiceStub` is
the test double.

## Files

| File | What |
| --- | --- |
| `game/net/online_service.gd` | `OnlineService` (Node): the interface, signals, and the two dictionary shapes (`match_info`, `result_summary`). |
| `game/net/service_eos.gd` | EOS backend (EOSG plugin, loaded only when its classes and autoloads exist): Connect device-id login, lobby Quick Match, P2P relay peer, stats and leaderboard. |
| `game/net/eos_config.gd` | Reads the git-ignored `config/eos_credentials.cfg` (product, sandbox, deployment, client id and secret). |
| `game/net/service_local.gd` | LAN / dev backend: UDP broadcast matchmaking, ratings kept on this device. |
| `game/net/service_stub.gd` | Scriptable fake for tests; also models the server rules (two reports, `Rating.reconcile`). |
| `game/net/service_board.gd` | Pure rating table + leaderboard views (used by Local and Stub; a custom server could reuse it). |
| `game/logic/rating.gd` | Pure Elo with provisional K, matchmaking window, tiers, report signing and `reconcile`. |
| `game/ui/menu/online_screen.gd` | Direct-IP lobby, and Quick Match mode (`open_quick`): search, found, loadout confirm, connect, report; the online part of the result panel (rating change, rematch). |
| `game/logic/quick_match_flow.gd` | `QuickMatchFlow`: the Quick Match screen's phases and clocks (search timer, usual wait, confirm countdown, ready notes, join timeout). |
| `game/logic/rematch_handshake.gd` | `RematchHandshake`: both players must ask; answer window, words for the panel. |
| `game/logic/online_text.gd` | `OnlineText`: raw network / service reasons in plain words, clock and wait lines. |
| `game/ui/menu/rating_change_view.gd` | `RatingChangeView`: the rating counting to its new value, tier promotion, bar to the next tier. |
| `game/ui/menu/leaderboard_screen.gd` | The ranking screen: top 100 in pages of 20, your row highlighted and pinned, tiers, W - L, streak, loading and offline states. |
| `game/ui/menu/online_capture.gd` (+ `.tscn`) | Dev capture of every online screen state against the stub (`--resolution 720x1280` for a phone). |
| `tests/unit/test_rating.gd`, `test_online_service_board.gd`, `test_online_service_stub.gd` | Unit tests. |
| `tests/unit/test_net_service_eos.gd`, `test_eos_config.gd`, `test_net_session_adopt.gd` | EOS helpers without the plugin, the credentials parser, NetSession over a relay peer. |
| `tests/sim/sim_net_quick.gd` (+ `_peer`, `_peer_node`) | Two engine processes quick-match over loopback, play, report; plus the menu against the stub. |

## The interface

```
login(display_name)            -> logged_in(profile) | login_failed(reason)
quick_match(loadout)           -> status_changed(text)..., matched(info) | match_failed(reason)
cancel()                       (no signal)
report_result(match_id, report, signature) -> result_recorded(summary)
request_leaderboard(top_n, around_me, offset) -> leaderboard_ready({top, around, me, total, offset, source, error?})
my_rating()                    -> {rating, games, wins, losses, streak, provisional, tier}
expected_wait_s()              usual search time for the "usual wait" line (-1: unknown, the screen learns it)
rematch_info(info, n)          the n-th rematch's info (derived match id and key: rated), or {} (a friendly rematch)
is_logged_in() / is_searching() / backend_name() / features() / logout()
build_id                       only equal build ids are matched (the UI sets NetSession.content_hash())
```

`profile` = `{id, name, rating, games, wins, losses, streak}` (streak: +n wins / -n losses in a row); `id` is the backend's stable player id (EOS ProductUserId, SteamID,
server GUID, LAN device id).

`matched(info)` (built by `OnlineService.match_info`):

| Key | Meaning |
| --- | --- |
| `role` | `"host"` or `"client"`. The host simulates both fighters (online_brief). Backends pick it deterministically (LAN: smaller id; EOS: lobby owner). |
| `address`, `port` | Direct play: the client connects here; the host listens on `port`. |
| `peer` | Relay play: a ready `MultiplayerPeer` (EOS P2P, Steam). `null` for direct play. |
| `match_id`, `match_key` | Backend id of the match; secret that signs result reports. |
| `opponent` | `{id, name, rating, games}`. |

`result_recorded(summary)`: `{match_id, status, winner, before, after, delta, why, rated}`; `status` is a
`Rating.reconcile` status (`agree`, `single`, `forfeit`, `disputed`, `voided`, `pending`). A `report` is
`Rating.make_report(match_id, player_id, kind, winner_id, reason, ticks)` with `kind` `result`, `left` or `dropped`, signed
with `Rating.sign_report(match_key, report)` (HMAC-SHA256).

### Running NetSession over the peer the service gives

`OnlineScreen` does `session.host(port)` / `session.join(address, port)` for a direct match and
`session.adopt_peer(info.peer, info.role)` for a relay match. NetSession only uses the `MultiplayerPeer` packet API
(`put_packet`, `get_packet`, transfer modes, `peer_connected`). What `adopt_peer` does (done):

1. `_peer` is typed `MultiplayerPeer`; `host()`/`join()` still create `ENetMultiplayerPeer`.
2. `adopt_peer(p, as_role)`: `_reset()`, `_peer = p`, `role = as_role`, connect `peer_connected` / `peer_disconnected`; a
   client talks to peer id 1 (EOSG's server id too) and times out like a direct join; a client peer that is already
   connected is greeted at once. The service must not `poll()` the peer before the hand-over.
3. ENet-only bits run only on `ENetMultiplayerPeer`: `_put`'s `host.flush()`, `rtt_ms()` (0 on a relay), `_no_throttle()`.
4. Unreliable traffic goes `TRANSFER_MODE_UNRELIABLE` on a relay peer: EOSG has no "unreliable ordered" and turns it into
   **reliable** (with a warning), which would queue every snapshot behind a lost one. Snapshots and inputs carry ticks,
   and `NetInterpBuffer` / `NetInputBuffer` drop old and duplicate ones, so reordering is harmless.
5. EOS P2P packets are at most 1170 bytes, 6 of them EOSG's header: NetSession warns once about a packet over 1164
   (a worst-case snapshot is about 1114). A relay peer is closed 0.3 s after `leave()` so the LEAVE gets out first.
6. Relayed links add latency; the interpolation buffer already adapts (`NetInterpBuffer`).

## Rating (`Rating`)

Elo, 400-point scale, start 1000, floor 100. K = 40 for the first 10 rated games (shown with "?"), 24 until 40 games, then 16.
A repeat-pair damper multiplies K by 1, 1, 0.5, 0.25, 0.1 for the n-th game against the same opponent within the last 12
games (stops farming one friend). Matchmaking window: 100 points, widening 25 per second searched; either player's
waiting time counts. Tiers (Roman): Tiro < 1000, Gladiator < 1200, Veteranus < 1400, Primus Palus < 1600, Rudiarius < 1800,
Summa Rudis.
Glicko-2 would model uncertainty better, but Elo with provisional K is enough for one mode and trivial to run on a server or
inside an EOS stat.

## The Quick Match flow (what the player sees)

1. **Search**: a spinning comet with the search time inside, "Usual wait about 0:20" (this session's last searches, else
   `expected_wait_s()`, else 30 s; past it: "Longer than usual. Widening the search..."), the rating range being
   searched (`Rating.search_window`), the player's tier, rating, W - L and streak. Cancel, big.
2. **Found -> confirm**: "Opponent found!" with their name, tier and rating for `QuickMatchFlow.FOUND_S`, then "Ready
   your arms": the loadout stays editable, a READY button counts down `CONFIRM_S` (10 s) and readies by itself. Each
   side sends a NetSession **NOTE** `{t: "ready"}` (`NetConfig.MSG_NOTE`) once ready and connected; the host starts
   when both are ready, or `READY_GRACE_S` after its own ready (an older build without notes still plays). The
   client's LOADOUT goes out before its ready note, so the host fights the arms the client confirmed.
3. **Before the fight** a failure that is about that opponent (left, dropped, no answer within `JOIN_TIMEOUT_S`,
   refused) puts the player straight back in the search with one line ("Verus left the arena. Back in the queue.");
   a version mismatch, an offline service or a blocked port stops with a plain explanation and Search again.
4. **Result panel** (MenuFlow's, built from `OnlineScreen.result_body()` / `result_entries()` / `make_result_view()`):
   the rating counts to its new value (promotion flash, bar and points to the next tier, streak), or why the fight
   was not rated. **Rematch**: either side asks (`{t: "rematch"}` note), the other sees "Verus wants a rematch!" and
   Accept; the host starts once both asked; the question lapses after 30 s; leaving gives "Verus left. No rematch."
   The rematch is rated when the backend derives a match id and key for it (`rematch_info`: Local and Stub do,
   `<match id>-r<n>`; the pair damper keeps repeats cheap), else it is a friendly ("Friendly rematch: not rated").
   "Find another opponent" goes back to the queue on a fresh connection.

## Resisting cheating

The fight is host-authoritative, so **the host can lie about the result**; the other client only sees what the host sends.
The rules below are in `Rating.reconcile` and are what any backend's result handler must apply (a server runs it; without a
server each client runs it on the two reports it can read).

| Threat | Rule |
| --- | --- |
| Host reports a win it did not get | Each client reports from its own view (the client from the host's OVER message). Reports that disagree are `disputed`: **nobody is rated**, and the pair is counted for review. |
| Forged or replayed report | Every report is HMAC-signed with the per-match key and carries match id and player id; a bad signature is `voided`. A second report for a match is ignored. |
| Leaving (menu Leave, window closed, killing the app) before the end | `left` report: **leaver loses**, at any time, whatever the other report says (`forfeit`). Both left: `voided`. |
| Pulling the plug when losing | A `dropped` report alone is not rated; after the grace period the silent side is treated as forfeit. Count drops per player; a high drop rate is shadow-flagged (EOS/server side). |
| Instant "wins" / collusion by quitting | Results shorter than 10 s (`MIN_RATED_TICKS`) are `voided`. |
| Win-trading with a friend | Repeat-pair damper; optionally require a minimum number of distinct opponents for the visible leaderboard. |
| Fake winner id | A winner that is neither player is `disputed`. |
| Rating inflation by editing the client | Needs a server-side verdict (see "tiers" below); a client-written stat can always be forged. |
| Sandbagging / smurfing | Provisional K and the widening window; leaderboard rows list `games` and the "?" mark until 10 games. |

`ServiceLocal` is **trust-based** (each device rates its own games from its own report) because a LAN has no referee. It does
apply the signature, duplicate and leave rules.

## EOS (primary): what `ServiceEos` maps to

`ServiceEos` uses the **EOSG GDExtension 2.3.1** (github.com/3ddelano/epic-online-services-godot, EOS SDK wrapper with a
`MultiplayerPeer` over EOS P2P). The plugin is not in the repo (its binaries are installed on the owner's PC,
`docs/eos_setup.md`), so the script never names a plugin class: it reaches the `IEOS` singleton, the `eos.gd` option
classes (`load()`), the `HPlatform` / `HAuth` / `HLobbies` autoloads and `ClassDB.instantiate("EOSGMultiplayerPeer")`
at run time, and parses and lints without them. `MenuFlow` builds it only when `ServiceEos.create_for()` finds the
plugin and complete credentials (`--online-service=auto|eos|local|stub`; auto never picks EOS in scripted runs).

EOSG calls used: `HPlatform.setup_eos_async(HCredentials)` (cache folder per `--eos-profile`),
`IEOS.p2p_interface_set_relay_control(AllowRelays)`, `IEOS.connect_interface_create_device_id` (+ `_callback`; an
existing id answers `DuplicateNotAllowed`), `HAuth.login_game_services_async(Connect.LoginOptions{DeviceidAccessToken,
UserLoginInfo.display_name})` (creates the user on `InvalidUser`; a first login is then repeated, because EOSG's
`create_user` path fires no connect-login callback and `EOSGRuntime` / the P2P mediator would not know the user),
`IEOS.stats_interface_query_stats` / `copy_stat_by_name` / `ingest_stat`, `IEOS.lobby_interface_create_lobby_search`
+ `EOSGLobbySearch.set_parameter` + `HLobbies.search_async`, `HLobbies.create_lobby_async` / `join_async`,
`HLobby.add_attribute` / `add_current_member_attribute` / `update_async` / `leave_async` / `destroy_async`,
`EOSGMultiplayerPeer.create_server(socket)` / `create_client(socket, owner_puid)`,
`IEOS.leaderboards_interface_query_leaderboard_ranks` / `get_leaderboard_record_count` / `copy_leaderboard_record_by_index`
/ `query_leaderboard_user_scores` / `copy_leaderboard_user_score_by_user_id`. Every SDK wait has a timeout (15 s).

As built (differences from the plan below): the bucket is `sb_quick:<first 16 of build_id>`; the search adds
`minslotsavailable >= 1` and sorts by `rating` distance, and the window is applied on the results; the socket id is
`"sb" + lobby id` (letters and digits, 32 at most); the lobby is created with presence, invites and join-by-id off and
host migration off, and is set **invite-only** once full; while waiting in its own lobby a player still searches and
gives its lobby up only for one whose owner id is smaller (the larger id joins); the match key is a random
16-byte hex lobby attribute. Results are Tier 0: report in member attribute `rep`, wait up to 20 s for the other's,
`Rating.reconcile(final)`, `ServiceBoard.apply` for the new rating (repeat-pair memory in `user://eos_profile*.json`),
ingest `sb_rating` (new value) + `sb_games` 1 + `sb_wins` or `sb_losses` 1, stay 3 s so the other can read ours, then
leave (the owner destroys the lobby). The leaderboard shows `user_display_name` (the Connect display name) and fetches
games / wins / losses only for the rows on screen.

| `OnlineService` | EOS |
| --- | --- |
| `login(name)` | **Connect**: `EOS_Connect_CreateDeviceId` (once per install; device model string), then `EOS_Connect_Login` with credential type `EOS_ECT_DEVICEID_ACCESS_TOKEN` and `UserLoginInfo.DisplayName` = the name. First time the result is `EOS_InvalidUser`: `EOS_Connect_CreateUser` with the continuance token, then login again. The **ProductUserId** is `profile.id`. No Epic account needed; the id is lost if the device id is deleted (offer linking an Epic/Steam account later with `EOS_Connect_LinkAccount`). |
| `quick_match(loadout)` | **Lobbies**: search with `EOS_Lobby_CreateLobbySearch` on bucket `sandblood-quick-<build_id>` (the build id keeps incompatible builds apart), parameter `rating` with `EOS_CO_DISTANCE` around my rating (re-search with a wider window every few seconds = `Rating.search_window`), max 2 members. Found: `JoinLobby`, `role = "client"`. Nothing found: `CreateLobby` (bucket, 2 slots, `bPresenceEnabled` false, public) with attributes `rating`, `build`, and wait; owner = `role "host"`. A lobby with 2 members is the match; `match_id` = the lobby id. Set `AllowInvites false` and lock the lobby when full. |
| `matched.peer` | **P2P with relay**: `EOS_P2P_SetRelayControl(ALLOW_RELAYS)`, socket id = lobby id. EOSG's multiplayer peer hosts on the lobby owner and the other member joins it; `NetSession.adopt_peer(peer, role)`. Relays are Epic's, free, and cover symmetric/carrier NAT (mobile). |
| `cancel()` | `EOS_Lobby_DestroyLobby` (owner) / `LeaveLobby`, stop the search. |
| `report_result(...)` | Tier 0 (no server): write the signed report as a lobby **member attribute** (`rep`, ~120 bytes); both members read the other's, run `Rating.reconcile`, then each client **ingests its own stats** (below). Tier 1 (recommended): post the two reports to a tiny verifier (see "tiers") that runs `reconcile` and ingests stats with server credentials. `match_key`: generated by the lobby owner into a lobby attribute (members can read it; it only ties a report to its match, it is not a secret against a cheating client). |
| `request_leaderboard(top, around)` | **Leaderboards**: `EOS_Leaderboards_QueryLeaderboardRanks` for the top; around me with `EOS_Leaderboards_QueryLeaderboardUserScores` for my score plus `QueryLeaderboardRanks` offset around my rank (or just show top N plus "you: #rank" from the user score). Rows: ProductUserId, rank, score; resolve names with `EOS_Connect_QueryProductUserIdMappings`/ display names published as stats or stored in the lobby attributes (see "display names" below). |
| `my_rating()` | `EOS_Stats_QueryStats` for the signed-in user (`sb_rating`, `sb_games`, `sb_wins`, `sb_losses`), cached in `profile`. |
| `build_id` | Lobby bucket suffix and attribute. |
| `features()` | `relay`, `global_leaderboard`. |

### Values the owner must give (from dev.epicgames.com/portal)

Create an organisation, then a **Product** (Sandblood) and put these in a config file the game reads (`ServiceEos` takes
them as constructor arguments; the **client secret is not secret on a client** and must not be treated as one):

| Value | Where in the portal | Notes |
| --- | --- | --- |
| **Product ID** | Product Settings > SDK Download / Credentials | One per product. |
| **Sandbox ID** | Product Settings > Sandboxes | One per environment (dev / stage / live). Start with the dev sandbox. |
| **Deployment ID** | Product Settings > Sandboxes > Deployments | One per sandbox; the build selects the deployment (dev build -> dev deployment, store build -> live). |
| **Client ID** and **Client Secret** | Product Settings > Clients > Add New Client | One client per role. The game client gets one with a **client policy** (below). A server/verifier later gets a separate client with a "Server" policy and its secret kept on the server only. |
| **Client policy** | Product Settings > Clients > Client Policies | For the game client choose "Peer-to-Peer" or a custom policy with only these features enabled: Connect (Device ID), Lobbies / Sessions, P2P, Stats, Leaderboards. Leave Auth/Epic account, Ecom, Anti-cheat, Friends, Presence and Player Data Storage off. For Tier 0 tick the Stats policy that lets a client **ingest** stats; for Tier 1 leave client ingest **off** (only the server client ingests). |
| Encryption key (optional) | Clients > Client | 64 hex characters, only needed for Player Data / Title Storage (not used now). |
| Product name, brand, privacy policy, age rating | Product Settings > Brand / Permissions | Required before the live sandbox; Connect device-id users need no Epic permissions prompt. M-rating: answer the content questionnaire honestly. |
| Platform setup | Product Settings > Platforms | Windows, macOS, Linux and Android entries (Android needs the app package name and signing certificate hash). |

The Connect device-id flow needs **no** Epic login and no store presence; shipping outside the Epic store is fine (a Product
with a live deployment is enough).

### Stats and leaderboards to create in the portal (Game Services > Stats / Leaderboards)

Names are fixed by the code, all 32-bit integers:

| Stat | Aggregation | Meaning |
| --- | --- | --- |
| `sb_rating` | **Latest** | Current Elo (set on every rated game; it goes down as well as up, so not Max). |
| `sb_games` | **Sum** | Rated games played (ingest 1 per game). |
| `sb_wins` | **Sum** | Wins (ingest 1 or 0). |
| `sb_losses` | **Sum** | Losses. |

| Leaderboard | Stat | Aggregation / period |
| --- | --- | --- |
| `sb_rating_all` | `sb_rating` | Latest value, order **descending**, no time period (all-time). |
| `sb_rating_week` (optional, later) | `sb_rating` | Latest, descending, weekly reset, for a "this week" tab. |

Leaderboard rows give only the ProductUserId and score. **Display names**: either ingest nothing and store the name in a
second stat-free place (a tiny server table, Tier 1) or keep the last 8 characters of a hash as a fallback label. With
Tier 0 the simplest working choice is a `sb_name` **lobby attribute** seen at match time (names of players you met) and
"Player ####" for everyone else.

### Tiers (how much authority EOS gives us)

EOS has no game logic: stats sent by a client are as honest as the client. Tier 0 above works for a soft launch and
friends; any serious leaderboard needs a verifier: a small web service (a serverless function or the VPS below) that holds
the **server client credentials**, takes both players' signed reports, runs `Rating.reconcile` and `ServiceBoard.apply`
(the same GDScript logic can be ported, it is 150 lines of arithmetic), and calls the EOS Stats Web API
(`POST /stats/v1/{deploymentId}/ingest/{accountId}`) with a server access token. That also lets it keep display names.
Cost: one small VPS or a free-tier function.

## Steam (alternative `ServiceSteam`)

| `OnlineService` | Steamworks (via GodotSteam) |
| --- | --- |
| `login` | The Steam user is the identity (`profile.id` = SteamID64, name = persona name); no anonymous device id, so Steam builds only. A session ticket (`GetAuthSessionTicket`) is what a verifier checks. |
| `quick_match` | Steam Lobbies: `RequestLobbyList` with `AddRequestLobbyListNumericalFilter("rating", ...)` / `AddRequestLobbyListNearValueFilter`, else `CreateLobby` (public, 2 members). Owner = host. |
| `matched.peer` | **Steam Networking Sockets** relay (SDR) through GodotSteam's `SteamMultiplayerPeer`; no ports, NAT-proof. |
| reports | Same tiers: lobby member data for Tier 0; a verifier checking tickets for Tier 1. |
| leaderboard | `FindOrCreateLeaderboard("sb_rating_all", descending)`, `UploadLeaderboardScore` (keep best/latest with `k_ELeaderboardUploadScoreMethodForceUpdate`), `DownloadLeaderboardEntries` (global top, **around user**, friends). Mark it trusted-writes-only in the partner site once a verifier exists. |
| Owner provides | Steamworks partner account and app fee, an AppID (480 for tests), the SDK / GodotSteam build, the leaderboard definition, depot / build upload. |

## Custom server (alternative `ServiceServer`)

A small HTTPS + UDP service (any language; SQLite or Postgres):

| Endpoint | Maps to |
| --- | --- |
| `POST /login {device_id, name}` -> `{token, profile}` | `login` (the device id is a random GUID the client keeps; the server signs a token). |
| `POST /queue {loadout, build, rating}` then long-poll `GET /queue/poll` | `quick_match` -> `matched` with `role`, and either the other player's public address (after UDP hole punching, see online_brief "NAT traversal") or a **relay**: `address` = the server, `port` = a per-match UDP forwarder, `match_key` secret per match. Relay cost: ~23 KB/s each way per match, about 165 MB per match-hour. |
| `DELETE /queue` | `cancel` |
| `POST /result {match_id, report, signature}` | `report_result`; the server holds both reports and runs `Rating.reconcile` with a timeout, and the key is a real secret only the server and two players know. |
| `GET /leaderboard?top=&around=` | `request_leaderboard` |

Owner provides: a VPS (1 vCPU is plenty for hundreds of players), a domain and TLS certificate, a decision on relay vs
direct only, a privacy policy (device id + display name stored), and someone to keep it patched. Best accuracy and
the only option with real anti-cheat authority and names on the board; the most ongoing work.

## ServiceLocal (LAN) details

Search: `quick_match` binds UDP `discovery_port` (17780, first free of 8) and broadcasts a `seek` (id, name, rating, games,
search age, game port, protocol, `build_id`) every 0.4 s to 255.255.255.255 and to 127.0.0.1 (so two instances on one
machine find each other). Players with another protocol or build id are ignored. Every player keeps the fresh seeks it hears. The
player with the **smaller device id hosts**: it picks the closest-rated fresh candidate with a larger id inside the window
and sends an `offer` (match id = hash(host, client, counter)); the candidate (if it has no offer out) answers `accept` three
times and becomes the client; on the first accept the host becomes the host. An unanswered offer times out after 1.5 s and
the candidate is skipped for a second. After 120 s without a match it gives up. The UI then shows the opponent for 1.6 s, the host listens at once and the
client joins after the beat, and the host starts the fight when the client is in. Ratings and everyone met live in
`user://online_local.json` (not in scripted runs: headless, `--capture`, `--scripted`). Dev flags: `--device-id=<id>` fixes
the identity (two instances on one machine need different ids; they get different random ones anyway),
`--online-service=stub` shows the menus against `ServiceStub` with fake players, `--online-service=local` forces the LAN
backend when EOS is installed, and `--eos-profile=<name>` gives a second EOS identity on one PC (`docs/eos_setup.md`). Broadcast does not cross routers or most
guest Wi-Fi networks; that is what the real backend is for.

## Tests

- `tools/run_tests.sh test_rating`, `test_online_service_board`, `test_online_service_stub`: Elo maths, K and window,
  signing, every `reconcile` rule, the board, the stub as a server, Local never writing in scripted runs.
- `tools/run_sims.sh` -> `sim_net_quick`: two real engine processes (headless, real time, ~35 s) quick match by UDP over
  loopback, take opposite roles, play a match over ENet and report; both must name the same winner and the ratings must move
  by exactly +/-20. Then the Quick Match menu against the stub: search, found + host listening, cancel, result line,
  leaving mid-fight loses.
- `test_online_text`, `test_quick_match_flow`, `test_rematch_handshake`, `test_rating_change_view`: the plain-language
  reasons, the screen's phases and clocks, the rematch handshake, the count-up and the leaderboard page helpers.
- `sim_net_quick_flow`: two MenuFlows in one process, each with a ServiceStub, over a localhost ENet port: search,
  found -> confirm (the client changes arms and readies, the host waits for its own ready) -> fight -> result with the
  rating change -> rated rematch by handshake -> the client walks out and the host reads "Bo left the arena" -> back
  to the queue; a confirm the other side abandons and a client that never connects both requeue with a plain line.
