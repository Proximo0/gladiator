extends Node
## Clean gameplay capture: one presented bot-vs-bot match with the player's aim aid (tip marker, trail, weapon-lost
## pointer) off, run for a movie render (tools/record_fight.sh). Args after `--`:
##   --seed=S        match seed (default 1000)
##   --tail=N        seconds to keep rolling after the match is over, for the finale and the result banner (default 4)
##   --max_ticks=N   fallback: quit after this many physics ticks (default 3600)
##   --scan          quit the moment the match is over (the seed scan runs this headless: the presented arena has
##                   walls and a crowd, so only a presented match predicts the movie)
##   --quality=0|1|2 graphics quality (default: the platform default)
## Prints `CAPTURE result seed=.. winner=.. reason=.. finisher=.. ticks=..` when the match ends and `CAPTURE done`
## when it quits. Never writes player data.

var _match: Match = null
var _tail_ticks: int = 240
var _max_ticks: int = 3600
var _over_tick: int = -1


func _ready() -> void:
	var seed_v: int = int(Flags.get_arg("seed", "1000"))
	_tail_ticks = roundi(float(Flags.get_arg("tail", "4")) * float(Engine.physics_ticks_per_second))
	_max_ticks = int(Flags.get_arg("max_ticks", "3600"))
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	FeelOptions.aim_aid = false  # the aim overlay hides itself; the weapon-lost prompt is part of it
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": seed_v, "presentation": true, "loop": false, "time_limit_s": 600.0})
	if Flags.args.has("quality") and _match.presenter != null:
		_match.presenter.blood.set_quality(GfxQuality.blood_level())  # MatchPresenter.build hard-codes 2 on desktop
	_match.match_over.connect(_on_over)


func _on_over(r: Dictionary) -> void:
	_over_tick = _match.tick
	var stats: Dictionary = r.get("stats", {}) as Dictionary
	print("CAPTURE result seed=%d winner=%s reason=%s finisher=%s ticks=%d fight_s=%.1f" % [
		int(r.get("seed", 0)), str(r.get("winner", -1)), str(r.get("reason", "")), str(stats.get("finisher", "")),
		int(r.get("ticks", 0)), float(r.get("fight_ticks", 0)) / 60.0])


func _physics_process(_delta: float) -> void:
	var t: int = _match.tick
	if (_over_tick >= 0 and (Flags.args.has("scan") or t - _over_tick >= _tail_ticks)) or t >= _max_ticks:
		print("CAPTURE done ticks=%d over=%s" % [t, str(_over_tick >= 0)])
		get_tree().quit()
