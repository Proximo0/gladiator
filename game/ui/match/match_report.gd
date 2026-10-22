class_name MatchReport
extends RefCounted
## Pure text for the match wrapper: the intro's name plates and the results screen. Columns and plates are in screen
## order: the local player first (side 0 offline, the client's side 1 online), the opponent second.

const DRAW_LATIN: String = "AEQVO MARTE"
const SEPARATOR: String = " / "
const STYLE_NAMES: Dictionary = {"brute": "Brute", "duelist": "Duelist", "coward": "Skirmisher", "berserker": "Berserker"}


## One intro plate: {name, weapon, sub}. `sub` is the CPU style, rating or player slot line.
static func plate(fighter_name: String, loadout: Dictionary, sub: String) -> Dictionary:
	return {"name": fighter_name.to_upper(), "weapon": weapon_line(loadout), "sub": sub}


## "Gladius & Round shield", "Fists".
static func weapon_line(loadout: Dictionary) -> String:
	var w: String = LoadoutRules.display_name(str(loadout.get("weapon", "fists")))
	var off: String = str(loadout.get("offhand", ""))
	return w if off == "" else "%s & %s" % [w, LoadoutRules.display_name(off)]


## "CPU - Brute" from a brain personality ({"preset": ...}).
static func cpu_style(personality: Dictionary) -> String:
	var p: String = str(personality.get("preset", "duelist"))
	return "CPU - %s" % str(STYLE_NAMES.get(p, p.capitalize()))


## "Rating 1016 - Tiro" from a rating dict ({rating, games}); "Online" without one.
static func rating_sub(rated: Dictionary) -> String:
	if not rated.has("rating"):
		return "Online"
	var r: int = int(rated["rating"])
	return "Rating %s - %s" % [Rating.rating_text(r, int(rated.get("games", 0))), Rating.tier(r)]


## The two plates in screen order for a match. `ctx`: mode, names [2], loadouts [2], personalities [2],
## local_side, ratings [2] (online: {} for unrated).
static func plates_for(ctx: Dictionary) -> Array:
	var mode: String = str(ctx.get("mode", "player_vs_cpu"))
	var names: Array = ctx.get("names", ["", ""])
	var lo: Array = ctx.get("loadouts", [{}, {}])
	var pers: Array = ctx.get("personalities", [{}, {}])
	var ratings: Array = ctx.get("ratings", [{}, {}])
	var me: int = clampi(int(ctx.get("local_side", 0)), 0, 1)
	var out: Array = []
	for side: int in [me, 1 - me]:
		var sub: String = ""
		match mode:
			"online":
				sub = ("You - " if side == me else "") + rating_sub(ratings[side] as Dictionary)
			"local_2p":
				sub = "Player %d" % (side + 1)
			"bot_vs_bot":
				sub = cpu_style(pers[side] as Dictionary)
			_:
				sub = "You" if side == me else cpu_style(pers[side] as Dictionary)
		out.append(plate(str(names[side]), lo[side] as Dictionary, sub))
	return out


## [latin, english] headline for winner `w` seen from the local side.
static func headline(w: int, mode: String, local_side: int, names: Array) -> Array:
	if w < 0 or w >= names.size():
		return [DRAW_LATIN, "Evenly matched"]
	if mode == "local_2p" or mode == "bot_vs_bot":
		return ["VICTORIA", "%s wins" % str(names[w])]
	if w == local_side:
		return ["VICTORIA", "You won"]
	return ["MORS", "%s wins" % str(names[w])]


## [latin, english] for how it ended.
static func cause(reason: String) -> Array:
	var fin: String = MatchJudge.finisher_banner(reason)
	if fin != "":
		var at: int = fin.find(SEPARATOR)
		return [fin.substr(0, at), fin.substr(at + SEPARATOR.length())]
	match reason:
		"blood_loss":
			return ["EXSANGVIS", "Bled out"]
		"ko":
			return ["SOPITVS", "Knocked out"]
		"time":
			return ["TEMPVS", "Decided at the time limit"]
		"mutual":
			return ["MORS MVTVA", "Both fell"]
	return ["", ""]


## "1:07" from seconds.
static func clock(seconds: float) -> String:
	var s: int = maxi(roundi(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## "+22" / "-18" / "0".
static func signed(n: int) -> String:
	return ("+%d" % n) if n > 0 else str(n)


## The results screen's content. `ctx` keys: mode, names [2], local_side, winner, reason, hits [2], blood_lost [2]
## (litres), severs [2], combos [2], fight_s, rating (summary dict from the rating service, {} offline), unlocked.
## Returns {latin, english, cause_latin, cause_english, names [2], won [2] (screen order), rows [[label, a, b]],
## time, rating_text, rating_delta (int, 0 when none), has_rating, unlocked}.
static func build(ctx: Dictionary) -> Dictionary:
	var names: Array = ctx.get("names", ["", ""])
	var me: int = clampi(int(ctx.get("local_side", 0)), 0, 1)
	var order: Array[int] = [me, 1 - me]
	var w: int = int(ctx.get("winner", -1))
	var mode: String = str(ctx.get("mode", "player_vs_cpu"))
	var head: Array = headline(w, mode, me, names)
	var why: Array = cause(str(ctx.get("reason", "")))
	var hits: Array = ctx.get("hits", [0, 0])
	var lost: Array = ctx.get("blood_lost", [0.0, 0.0])
	var sev: Array = ctx.get("severs", [0, 0])
	var combos: Array = ctx.get("combos", [0, 0])
	var rows: Array = []
	rows.append(["Hits landed", str(int(hits[order[0]])), str(int(hits[order[1]]))])
	rows.append(["Blood lost", "%.1f L" % maxf(float(lost[order[0]]), 0.0), "%.1f L" % maxf(float(lost[order[1]]), 0.0)])
	rows.append(["Limbs severed", str(int(sev[order[0]])), str(int(sev[order[1]]))])
	rows.append(["Longest combo", str(int(combos[order[0]])), str(int(combos[order[1]]))])
	var rating: Dictionary = ctx.get("rating", {})
	var has_rating: bool = not rating.is_empty()
	var delta: int = 0
	var rating_text: String = ""
	if has_rating:
		match str(rating.get("status", "")):
			"agree", "single", "forfeit":
				delta = int(rating.get("delta", 0))
				rating_text = "Rating %d -> %d" % [int(rating.get("before", 0)), int(rating.get("after", 0))]
			"pending":
				rating_text = "Rating pending"
			_:
				rating_text = "Not rated: %s" % str(rating.get("why", ""))
	return {
		"latin": head[0], "english": head[1], "cause_latin": why[0], "cause_english": why[1],
		"names": [str(names[order[0]]).to_upper(), str(names[order[1]]).to_upper()],
		"won": [w == order[0], w == order[1]], "rows": rows, "time": clock(float(ctx.get("fight_s", 0.0))),
		"rating_text": rating_text, "rating_delta": delta, "has_rating": has_rating,
		"unlocked": str(ctx.get("unlocked", "")),
	}
