class_name Rating
extends RefCounted
## Skill rating for quick matches: Elo with a provisional K (new players move fast, veterans slowly), a repeat-pair
## damper, a widening matchmaking window, tier names, and the rules that turn two clients' signed result reports into
## one verdict (the anti-cheat core: see docs/online_service.md). Pure: no clock, no random, no engine nodes.
## These are ranking numbers, not combat numbers, so they live here as constants.

const START_RATING: int = 1000
const MIN_RATING: int = 100
const SCALE: float = 400.0  ## 400 points = 10:1 expected odds
const PROVISIONAL_GAMES: int = 10  ## rating shown with a "?" until this many rated games
const ESTABLISHED_GAMES: int = 40
const K_PROVISIONAL: float = 40.0
const K_NORMAL: float = 24.0
const K_ESTABLISHED: float = 16.0
const MIN_RATED_TICKS: int = 600  ## a "result" shorter than this (10 s at 60 Hz) is voided, never rated
const WINDOW_START: int = 100  ## matchmaking: accept opponents within this many points at first ...
const WINDOW_PER_S: int = 25  ## ... and widen by this much per second searched
const PAIR_WEIGHTS: Array[float] = [1.0, 1.0, 0.5, 0.25, 0.1]  ## k multiplier for the n-th recent game vs the same opponent
## Roman ladder, low to high: [below this rating, name]. Tiro (recruit), Gladiator, Veteranus (survived bouts),
## Primus Palus (first of his school), Rudiarius (freed with the wooden sword, fights by choice), Summa Rudis.
const TIERS: Array = [[1000, "Tiro"], [1200, "Gladiator"], [1400, "Veteranus"], [1600, "Primus Palus"], [1800, "Rudiarius"]]
const TOP_TIER: String = "Summa Rudis"

const KIND_RESULT: String = "result"  ## "the fight ended and this is who won" (winner id, "" = draw)
const KIND_LEFT: String = "left"  ## "I left the match" (menu Leave, window closed): I lose
const KIND_DROPPED: String = "dropped"  ## "the connection died": nobody is blamed on this alone


static func expected(rating: float, opponent: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (opponent - rating) / SCALE))


static func is_provisional(games: int) -> bool:
	return games < PROVISIONAL_GAMES


static func k_factor(games: int) -> float:
	if games < PROVISIONAL_GAMES:
		return K_PROVISIONAL
	return K_NORMAL if games < ESTABLISHED_GAMES else K_ESTABLISHED


## New rating after one game. `score` 1 win, 0.5 draw, 0 loss. `weight` scales k (see pair_weight).
static func updated(rating: int, games: int, opponent: int, score: float, weight: float = 1.0) -> int:
	var delta: float = k_factor(games) * weight * (score - expected(float(rating), float(opponent)))
	return maxi(MIN_RATING, rating + roundi(delta))


## `recent_vs_same` = rated games already played against this opponent lately.
static func pair_weight(recent_vs_same: int) -> float:
	return PAIR_WEIGHTS[clampi(recent_vs_same, 0, PAIR_WEIGHTS.size() - 1)]


## Both players' new ratings. a and b are {rating, games}; score_a is 1 / 0.5 / 0.
static func apply_match(a: Dictionary, b: Dictionary, score_a: float, weight: float = 1.0) -> Dictionary:
	var ra: int = int(a.get("rating", START_RATING))
	var rb: int = int(b.get("rating", START_RATING))
	var na: int = updated(ra, int(a.get("games", 0)), rb, score_a, weight)
	var nb: int = updated(rb, int(b.get("games", 0)), ra, 1.0 - score_a, weight)
	return {"a_rating": na, "b_rating": nb, "a_delta": na - ra, "b_delta": nb - rb}


## How far apart two searching players may be after `seconds` of searching.
static func search_window(seconds: float) -> int:
	return WINDOW_START + int(float(WINDOW_PER_S) * maxf(seconds, 0.0))


static func in_window(a: int, b: int, seconds: float) -> bool:
	return absi(a - b) <= search_window(seconds)


static func tier(rating: int) -> String:
	for t: Array in TIERS:
		if rating < int(t[0]):
			return str(t[1])
	return TOP_TIER


## 0 for the lowest tier .. TIERS.size() for the top one.
static func tier_index(rating: int) -> int:
	for i: int in TIERS.size():
		if rating < int(TIERS[i][0]):
			return i
	return TIERS.size()


## Every tier name, lowest first.
static func tier_names() -> PackedStringArray:
	var out := PackedStringArray()
	for t: Array in TIERS:
		out.append(str(t[1]))
	out.append(TOP_TIER)
	return out


## {name, at, need} of the next tier up ({} at the top): "need" points from `rating` to reach it.
static func next_tier(rating: int) -> Dictionary:
	var i: int = tier_index(rating)
	if i >= TIERS.size():
		return {}
	var at: int = int(TIERS[i][0])
	return {"name": tier_names()[i + 1], "at": at, "need": at - rating}


## "1016" or "1000?" while provisional.
static func rating_text(rating: int, games: int) -> String:
	return "%d%s" % [rating, "?" if is_provisional(games) else ""]


# --- result reports ----------------------------------------------------------------------------------------------

static func make_report(match_id: String, player_id: String, kind: String, winner_id: String, reason: String, ticks: int) -> Dictionary:
	return {"match_id": match_id, "player": player_id, "kind": kind, "winner": winner_id, "reason": reason, "ticks": ticks}


static func _canon(r: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%d" % [str(r.get("match_id", "")), str(r.get("player", "")), str(r.get("kind", "")),
		str(r.get("winner", "")), str(r.get("reason", "")), int(r.get("ticks", 0))]


## HMAC-SHA256 (hex) of a report under the per-match key the service handed both players.
static func sign_report(key: String, r: Dictionary) -> String:
	if key == "":
		return ""
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key.to_utf8_buffer(), _canon(r).to_utf8_buffer()).hex_encode()


static func verify_report(key: String, r: Dictionary, signature: String) -> bool:
	return key != "" and signature != "" and sign_report(key, r) == signature  # (an empty HMAC key is an engine error)


## One verdict from the two players' reports (`a_rep` / `b_rep`, or {} when that player sent none).
## Returns {status, winner, score_a, rated, why}:
##   status "agree" | "forfeit" | "single" | "disputed" | "voided" | "pending"
##   winner = a player id, or "" for a draw; score_a = 1 / 0.5 / 0; rated = apply it to the ratings.
## `final` = the grace period for the missing report is over (until then one lone report is "pending").
static func reconcile(a_id: String, a_rep: Dictionary, b_id: String, b_rep: Dictionary, final: bool) -> Dictionary:
	var ak: String = str(a_rep.get("kind", ""))
	var bk: String = str(b_rep.get("kind", ""))
	if ak == "" and bk == "":
		return _verdict("pending" if not final else "voided", "", a_id, false, "no reports")
	# Leaving costs the game, at any time, whatever the other report says.
	if ak == KIND_LEFT and bk == KIND_LEFT:
		return _verdict("voided", "", a_id, false, "both left")
	if ak == KIND_LEFT:
		return _verdict("forfeit", b_id, a_id, true, "%s left" % a_id)
	if bk == KIND_LEFT:
		return _verdict("forfeit", a_id, a_id, true, "%s left" % b_id)
	if ak == KIND_RESULT and bk == KIND_RESULT:
		var wa: String = str(a_rep.get("winner", ""))
		var wb: String = str(b_rep.get("winner", ""))
		if wa != wb:
			return _verdict("disputed", "", a_id, false, "reports disagree")
		if not _plausible_winner(wa, a_id, b_id):
			return _verdict("disputed", "", a_id, false, "winner is not in the match")
		if mini(int(a_rep.get("ticks", 0)), int(b_rep.get("ticks", 0))) < MIN_RATED_TICKS:
			return _verdict("voided", "", a_id, false, "match too short")
		return _verdict("agree", wa, a_id, true, "both agree")
	if ak == KIND_DROPPED and bk == KIND_DROPPED:
		return _verdict("voided", "", a_id, false, "both dropped")
	# One side is missing or only says "dropped". A real result beats a "dropped" (the side that saw the end decides).
	var take_a: bool = ak != "" and (ak == KIND_RESULT or bk != KIND_RESULT)
	var lone: Dictionary = a_rep if take_a else b_rep
	var lone_id: String = a_id if take_a else b_id
	var other_id: String = b_id if take_a else a_id
	var lone_kind: String = str(lone.get("kind", ""))
	var other_kind: String = bk if take_a else ak
	if lone_kind == KIND_DROPPED:
		# Only "the connection died" and nothing from the other side. Without a server this runs on the reporter's own
		# device, which cannot tell a silent opponent from one it cut off itself (block the game's traffic when losing,
		# leave the lobby). So the silent side forfeits only to a reporter that was ahead when the link died (its
		# report's winner is itself, MatchJudge.leader) and the fight had run MIN_RATED_TICKS; anything else is void.
		if not final:
			return _verdict("pending", "", a_id, false, "waiting for %s" % other_id)
		if str(lone.get("winner", "")) == lone_id and int(lone.get("ticks", 0)) >= MIN_RATED_TICKS:
			return _verdict("forfeit", lone_id, a_id, true, "%s silent" % other_id)
		return _verdict("voided", "", a_id, false, "connection lost")
	if not final and other_kind == "":
		return _verdict("pending", "", a_id, false, "waiting for %s" % other_id)
	var w: String = str(lone.get("winner", ""))
	if not _plausible_winner(w, a_id, b_id) or int(lone.get("ticks", 0)) < MIN_RATED_TICKS:
		return _verdict("voided", "", a_id, false, "lone report not rated")
	return _verdict("single", w, a_id, true, "only %s reported" % lone_id)


static func _plausible_winner(w: String, a_id: String, b_id: String) -> bool:
	return w == "" or w == a_id or w == b_id


static func _verdict(status: String, winner: String, a_id: String, rated: bool, why: String) -> Dictionary:
	var score: float = 0.5 if winner == "" else (1.0 if winner == a_id else 0.0)
	return {"status": status, "winner": winner, "score_a": score, "rated": rated, "why": why}
