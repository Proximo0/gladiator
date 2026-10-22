class_name NetResultCheck
extends RefCounted
## Client side: does the host's result fit what the host's own snapshots showed? The client reports the host's
## OVER for the rating, so a modded host could name itself the winner of a fight it lost; the client checks the
## claim against the newest snapshot it holds and reports a draw instead on a clear mismatch, which makes the two
## reports disagree ("disputed", nobody rated; docs/net_security.md). Only impossible claims are flagged: a dead
## winner, a living loser of a killing blow, both alive in a "mutual", a time decision before the time limit or
## against a clear blood lead. Nothing is flagged when the snapshots do not reach the result's tick. Pure.

const KILLS: PackedStringArray = ["behead", "gut", "run_through", "skull_crush", "mutual"]
const STATE_DEAD: String = "dead"
const TIME_SLACK_TICKS: int = 2  ## the time decision may land a tick or two before the limit in ticks
const BLOOD_MARGIN_L: float = 0.5  ## a time decision against a blood lead this large (twice the judge's) is flagged


## "" when `result` ({winner, reason, ticks}) is consistent with `snap` (a snapshot at or after the result's tick),
## else why not. `time_limit_s` is the match's limit.
static func check(result: Dictionary, snap: NetSnapshot, time_limit_s: float) -> String:
	if snap == null or snap.fighters.size() < 2 or snap.tick < int(result.get("ticks", 0)):
		return ""  # unverified, not suspect
	var winner: int = int(result.get("winner", -1))
	var reason: String = str(result.get("reason", ""))
	var dead: Array = [_dead(snap.fighters[0]), _dead(snap.fighters[1])]
	if reason == "mutual":
		return "" if dead[0] and dead[1] else "mutual death but a fighter lives"
	if winner < 0 or winner > 1:
		return ""
	var loser: int = 1 - winner
	if dead[winner] and not dead[loser]:
		return "the winner is dead"
	if KILLS.has(reason) and not dead[loser]:
		return "%s but the loser lives" % reason
	if reason == "time":
		if int(result.get("ticks", 0)) < roundi(time_limit_s * float(NetConfig.TICK_HZ)) - TIME_SLACK_TICKS:
			return "time decision before the limit"
		if snap.fighters[loser].blood - snap.fighters[winner].blood > BLOOD_MARGIN_L:
			return "time decision against the blood lead"
	return ""


static func _dead(f: NetFighterSnap) -> bool:
	return f.dead or (f.state >= 0 and f.state < NetConfig.STATES.size() and NetConfig.STATES[f.state] == STATE_DEAD)
