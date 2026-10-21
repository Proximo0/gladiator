extends SceneTree
## One side of a two-process online check (real time, separate engines), not part of the suite:
##   godot --headless --path . -s res://tests/sim/sim_net_peer.gd -- --role=host --port=17951 &
##   godot --headless --path . -s res://tests/sim/sim_net_peer.gd -- --role=client --port=17951
## The host's side 0 is a CPU brain, the client's side 1 walks then swings. 8 s time limit. Each prints
## "NETPEER <role> winner=.. reason=.. ticks=.. ..." and exits 0, or "NETPEER <role> FAIL ..." and exits 1.



func _initialize() -> void:
	_start.call_deferred()


## Game classes compile only once the autoloads exist, so the work lives in a script loaded here.
func _start() -> void:
	var scr: GDScript = load("res://tests/sim/sim_net_peer_node.gd") as GDScript
	root.add_child(scr.new() as Node)
