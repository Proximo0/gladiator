class_name OnlineService
extends Node
## Backend-agnostic online service: who you are, finding an opponent, reporting the result, the leaderboard.
## The menus only talk to this class; a backend subclasses it (ServiceLocal for LAN/dev, ServiceStub for tests, later
## ServiceEos / ServiceSteam / ServiceServer). Everything is asynchronous: call, then wait for the signal. Nothing
## here knows about ENet: a match hands NetSession either an address and port (direct) or a ready MultiplayerPeer
## (relay). Mapping to EOS, Steam and a custom server: docs/online_service.md.
##
## Typical flow: login() -> logged_in; quick_match(loadout) -> matched(info) (or match_failed); the game runs the
## fight over NetSession; both clients report_result(match_id, report) -> result_recorded(summary);
## request_leaderboard() -> leaderboard_ready(data).

signal logged_in(profile: Dictionary)  ## profile: {id, name, rating, games, wins, losses, provisional, tier}
signal login_failed(reason: String)
signal status_changed(text: String)  ## short progress text for the search screen
signal matched(info: Dictionary)  ## see match_info()
signal match_failed(reason: String)  ## search ended without a match (not for a cancel)
signal result_recorded(summary: Dictionary)  ## see result_summary()
signal leaderboard_ready(data: Dictionary)  ## {top: [row], around: [row], me: row or {}, total: int, source: String}

const ROLE_HOST: String = "host"
const ROLE_CLIENT: String = "client"

var build_id: String = ""  ## only players with the same build id are matched (NetSession.content_hash())
var profile: Dictionary = {}


## Short name of the backend for the UI footer and logs ("LAN", "EOS", ...).
func backend_name() -> String:
	return "none"


## What the backend can do, so the UI can hide what is missing: "lan_only", "relay", "global_leaderboard".
func features() -> PackedStringArray:
	return PackedStringArray()


func is_logged_in() -> bool:
	return str(profile.get("id", "")) != ""


## Anonymous sign-in with a per-device identity (EOS Connect device ID, a stored GUID, ...). `display_name` is the
## name opponents see. Emits logged_in or login_failed.
func login(_display_name: String) -> void:
	login_failed.emit("This backend has no login")


func logout() -> void:
	cancel()
	profile = {}


## Start looking for an opponent with `loadout` (a LoadoutRules dictionary). Emits matched or match_failed; status
## text arrives on status_changed meanwhile. Calling it while searching restarts the search.
func quick_match(_loadout: Dictionary) -> void:
	match_failed.emit("This backend has no matchmaking")


func is_searching() -> bool:
	return false


## Stop looking (or leave the lobby / queue). No signal: the caller already knows.
func cancel() -> void:
	pass


## Send this player's report of a match (build it with Rating.make_report, sign it with Rating.sign_report and the
## match key from `info`). Emits result_recorded once the backend has a verdict (immediately, or when the other
## player's report arrives, or after a timeout). A second report for the same match is ignored.
func report_result(_match_id: String, _report: Dictionary, _signature: String) -> void:
	result_recorded.emit(result_summary("", "voided", "", 0, 0, "This backend does not rate matches"))


## Ask for the leaderboard: the best `top_n` and `around_me` rows either side of the player. Emits leaderboard_ready.
func request_leaderboard(_top_n: int = 20, _around_me: int = 3) -> void:
	leaderboard_ready.emit({"top": [], "around": [], "me": {}, "total": 0, "source": backend_name()})


## {rating, games, wins, losses, provisional, tier} of the signed-in player (the cached copy; updated by results).
func my_rating() -> Dictionary:
	var r: int = int(profile.get("rating", Rating.START_RATING))
	var g: int = int(profile.get("games", 0))
	return {"rating": r, "games": g, "wins": int(profile.get("wins", 0)), "losses": int(profile.get("losses", 0)),
		"provisional": Rating.is_provisional(g), "tier": Rating.tier(r)}


## The one shape every backend uses for `matched`.
##   role:      "host" or "client" (the host simulates the fight, see docs/online_brief.md)
##   address, port: where the client connects (direct play); host: the port to listen on
##   peer:      a ready MultiplayerPeer for relay backends (null for direct); NetSession.adopt_peer(peer, role)
##   match_id:  the backend's id for this match; match_key: shared secret for signing reports
##   opponent:  {id, name, rating, games}
static func match_info(role: String, address: String, port: int, peer: Object, match_id: String, match_key: String,
		opponent: Dictionary) -> Dictionary:
	return {"role": role, "address": address, "port": port, "peer": peer, "match_id": match_id, "match_key": match_key,
		"opponent": opponent}


## The one shape for `result_recorded`. `status` is a Rating.reconcile status; before/after are this player's ratings.
static func result_summary(match_id: String, status: String, winner_id: String, before: int, after: int, why: String) -> Dictionary:
	return {"match_id": match_id, "status": status, "winner": winner_id, "before": before, "after": after,
		"delta": after - before, "why": why, "rated": status == "agree" or status == "single" or status == "forfeit"}
