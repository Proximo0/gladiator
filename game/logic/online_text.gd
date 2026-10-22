class_name OnlineText
extends RefCounted
## Plain-language words for the online screens: what a raw network or service reason means for the player
## (opponent left, timed out, different versions, nobody searching ...), clock text for the search timer, and the
## search's "usual wait" and rating-range lines. Pure: strings in, strings out.

const KIND_LEFT: String = "left"
const KIND_DROPPED: String = "dropped"
const KIND_TIMEOUT: String = "timeout"
const KIND_UNREACHABLE: String = "unreachable"
const KIND_VERSION: String = "version"
const KIND_REFUSED: String = "refused"
const KIND_NO_MATCH: String = "no_match"
const KIND_OFFLINE: String = "offline"
const KIND_BLOCKED: String = "blocked"
const KIND_OTHER: String = "other"

const GENERIC_OPPONENT: String = "The other player"


## {kind, title, body} for a raw reason from NetSession or the OnlineService. `opponent` names the other player
## when known. Order matters: the most specific patterns first.
static func plain(reason: String, opponent: String = "") -> Dictionary:
	var r: String = reason.strip_edges()
	var low: String = r.to_lower()
	var who: String = opponent if opponent != "" else _who_from(r)
	var them: String = who if who != "" else "Your opponent"  # at the start of a sentence
	var them_mid: String = who if who != "" else "your opponent"
	if low.begins_with("version mismatch") or low.contains("different game data") or low.contains("different protocol"):
		return _out(KIND_VERSION, "Different game versions",
			"%s is on another version of Sandblood. Update the game, then search again." % them)
	if low.ends_with(" left") or low == "left":
		return _out(KIND_LEFT, "%s left the arena" % them, "They walked away from the fight.")
	if low.ends_with(" disconnected"):
		return _out(KIND_DROPPED, "Lost contact with %s" % them_mid, "Their connection dropped.")
	if low == "connection lost":
		return _out(KIND_TIMEOUT, "Connection timed out", "No word from %s for a few seconds. One of the connections dropped." % them_mid)
	if low.begins_with("no answer from") or low.begins_with("could not reach") or low.contains("no relay connection"):
		return _out(KIND_UNREACHABLE, "Could not reach %s" % them_mid,
			"A network between you is blocking the fight. Try another opponent.")
	if low.begins_with("host refused") or low.begins_with("refused"):
		var why: String = r.get_slice(":", 1).strip_edges() if r.contains(":") else ""
		return _out(KIND_REFUSED, "The host turned you away", "Reason: %s." % why if why != "" else "Try another opponent.")
	if low.begins_with("nobody") or low.contains("no opponent") or low.contains("try again in a while"):
		return _out(KIND_NO_MATCH, "No opponents found", "Nobody else is searching right now. Try again in a minute.")
	if low.contains("sign in") or low.contains("sign-in") or low.contains("not signed in") or low.contains("offline") \
			or low.contains("eos") or low.contains("unavailable"):
		return _out(KIND_OFFLINE, "Can't reach the arena servers", "Check your internet connection, then try again.")
	if low.begins_with("could not listen") or low.contains("search port"):
		return _out(KIND_BLOCKED, "Online play is blocked here", "Another program may be using the port, or a firewall blocks it.")
	return _out(KIND_OTHER, "Connection closed", r if r != "" else "The fight's connection closed.")


## The name at the front of "Verus left" / "Verus disconnected" ("" for the generic wording).
static func _who_from(r: String) -> String:
	for tail: String in [" left", " disconnected"]:
		if r.ends_with(tail):
			var n: String = r.left(r.length() - tail.length()).strip_edges()
			return "" if n == GENERIC_OPPONENT or n.to_lower() == "the other player" else n
	return ""


static func _out(kind: String, title: String, body: String) -> Dictionary:
	return {"kind": kind, "title": title, "body": body}


## "0:07", "1:23", "12:05".
static func clock(seconds: float) -> String:
	var s: int = maxi(int(floor(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]


## The line under the search timer: the usual wait while we are under it, then a reassurance that the search widens.
static func wait_line(elapsed: float, estimate: float) -> String:
	if estimate <= 0.0:
		return "Searching the whole arena"
	if elapsed < estimate:
		return "Usual wait about %s" % clock(ceilf(estimate))
	return "Longer than usual. Widening the search..."


## "Rivals rated 900 to 1100": the matchmaking window after `elapsed` seconds (Rating.search_window).
static func range_line(rating: int, elapsed: float) -> String:
	var w: int = Rating.search_window(elapsed)
	return "Rivals rated %d to %d" % [maxi(rating - w, Rating.MIN_RATING), rating + w]


## "3 wins in a row" / "2 losses in a row" / "" (a streak of 0 or 1 is not news).
static func streak_line(streak: int) -> String:
	if streak >= 2:
		return "%d wins in a row" % streak
	if streak <= -2:
		return "%d losses in a row" % -streak
	return ""


## Why a fight was not rated, in plain words (`why` is Rating.reconcile's or the service's reason).
static func unrated_line(why: String) -> String:
	var w: String = why.to_lower()
	if w.contains("too short"):
		return "Not rated: the fight was too short to count"
	if w.contains("disagree") or w.contains("not in the match"):
		return "Not rated: the two sides saw different results"
	if w.contains("both left") or w.contains("both dropped") or w.contains("no reports"):
		return "Not rated: nobody finished the fight"
	if w.contains("signature"):
		return "Not rated: the result could not be checked"
	if w.contains("lone report") or w.contains("silent"):
		return "Not rated: the result never arrived"
	if w.contains("friendly"):
		return "Friendly rematch: not rated"
	return "Not rated" if why == "" else "Not rated: %s" % why
