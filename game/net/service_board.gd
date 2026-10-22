class_name ServiceBoard
extends RefCounted
## The rating table behind ServiceLocal and ServiceStub: players by id with rating and record, the repeat-pair
## counter, result application and the leaderboard views. Pure data in, pure data out (to_dict / from_dict for the
## file); the owner decides when to save, and never in scripted runs.

const MAX_PLAYERS: int = 500
const PAIR_MEMORY: int = 12  ## remembered recent opponents for the repeat-pair damper

var players: Dictionary = {}  ## id -> {name, rating, games, wins, losses}
var recent: Dictionary = {}  ## id -> Array of the last PAIR_MEMORY opponent ids


func ensure(id: String, player_name: String) -> Dictionary:
	if not players.has(id):
		if players.size() >= MAX_PLAYERS:
			_evict()
		players[id] = {"name": NetLobby.clean_name(player_name), "rating": Rating.START_RATING, "games": 0, "wins": 0, "losses": 0}
	elif player_name != "":
		(players[id] as Dictionary)["name"] = NetLobby.clean_name(player_name)
	return players[id]


## Remember an opponent seen in matchmaking (name and the rating/record they announced) without touching anything
## we computed ourselves: the larger game count wins.
func note_opponent(id: String, player_name: String, rating: int, games: int) -> void:
	var e: Dictionary = ensure(id, player_name)
	if games >= int(e["games"]):
		e["rating"] = clampi(rating, Rating.MIN_RATING, 9999)
		e["games"] = clampi(games, 0, 99999)


func entry(id: String) -> Dictionary:
	return players.get(id, {})


## Apply one verdict: `score_a` 1 / 0.5 / 0 for player a. Returns {a_before, a_after, b_before, b_after}.
func apply(a_id: String, b_id: String, score_a: float) -> Dictionary:
	var a: Dictionary = ensure(a_id, "")
	var b: Dictionary = ensure(b_id, "")
	var weight: float = Rating.pair_weight(_count_recent(a_id, b_id))
	var res: Dictionary = Rating.apply_match(a, b, score_a, weight)
	var out: Dictionary = {"a_before": int(a["rating"]), "a_after": int(res["a_rating"]), "b_before": int(b["rating"]),
		"b_after": int(res["b_rating"])}
	a["rating"] = res["a_rating"]
	b["rating"] = res["b_rating"]
	a["games"] = int(a["games"]) + 1
	b["games"] = int(b["games"]) + 1
	if score_a > 0.5:
		a["wins"] = int(a["wins"]) + 1
		b["losses"] = int(b["losses"]) + 1
	elif score_a < 0.5:
		b["wins"] = int(b["wins"]) + 1
		a["losses"] = int(a["losses"]) + 1
	_remember(a_id, b_id)
	_remember(b_id, a_id)
	return out


func _count_recent(a_id: String, b_id: String) -> int:
	var n: int = 0
	for o: Variant in recent.get(a_id, []):
		if str(o) == b_id:
			n += 1
	return n


func _remember(id: String, opp: String) -> void:
	var l: Array = recent.get(id, [])
	l.append(opp)
	while l.size() > PAIR_MEMORY:
		l.pop_front()
	recent[id] = l


func _evict() -> void:
	var worst: String = ""
	for id: String in players:
		if worst == "" or int(players[id]["games"]) < int(players[worst]["games"]):
			worst = id
	players.erase(worst)
	recent.erase(worst)


## Rows best first: {rank, id, name, rating, games, wins, losses, provisional, tier}.
func rows() -> Array:
	var out: Array = []
	for id: String in players:
		var e: Dictionary = players[id]
		if int(e["games"]) == 0:
			continue
		out.append({"id": id, "name": str(e["name"]), "rating": int(e["rating"]), "games": int(e["games"]),
			"wins": int(e["wins"]), "losses": int(e["losses"]), "provisional": Rating.is_provisional(int(e["games"])),
			"tier": Rating.tier(int(e["rating"]))})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["rating"] != y["rating"]:
			return int(x["rating"]) > int(y["rating"])
		if x["games"] != y["games"]:
			return int(x["games"]) > int(y["games"])
		return str(x["id"]) < str(y["id"]))
	for i: int in out.size():
		(out[i] as Dictionary)["rank"] = i + 1
	return out


## {top, around, me, total}: `around` is the window of `around_me` rows either side of `my_id` and is empty when the
## player is already inside the top list; `me` is {} for a player with no rated game yet.
func leaderboard(my_id: String, top_n: int, around_me: int) -> Dictionary:
	var all: Array = rows()
	var top: Array = all.slice(0, maxi(top_n, 0))
	var me: Dictionary = {}
	var my_i: int = -1
	for i: int in all.size():
		if str(all[i]["id"]) == my_id:
			me = all[i]
			my_i = i
	var around: Array = []
	if my_i >= top.size():
		around = all.slice(maxi(my_i - around_me, top.size()), mini(my_i + around_me + 1, all.size()))
	return {"top": top, "around": around, "me": me, "total": all.size()}


func to_dict() -> Dictionary:
	return {"players": players.duplicate(true), "recent": recent.duplicate(true)}


## Loads what to_dict wrote; anything malformed is skipped so a damaged file cannot break the game.
func from_dict(d: Dictionary) -> void:
	players.clear()
	recent.clear()
	var p: Variant = d.get("players", {})
	if p is Dictionary:
		for id: Variant in p:
			var e: Variant = (p as Dictionary)[id]
			if e is Dictionary and players.size() < MAX_PLAYERS:
				var ed: Dictionary = e
				players[str(id)] = {"name": NetLobby.clean_name(str(ed.get("name", ""))),
					"rating": clampi(int(ed.get("rating", Rating.START_RATING)), Rating.MIN_RATING, 9999),
					"games": maxi(int(ed.get("games", 0)), 0), "wins": maxi(int(ed.get("wins", 0)), 0),
					"losses": maxi(int(ed.get("losses", 0)), 0)}
	var r: Variant = d.get("recent", {})
	if r is Dictionary:
		for id: Variant in r:
			var l: Variant = (r as Dictionary)[id]
			if l is Array:
				var cleaned: Array = []
				for o: Variant in (l as Array).slice(-PAIR_MEMORY):
					cleaned.append(str(o))
				recent[str(id)] = cleaned
