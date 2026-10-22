extends SceneTree
## One side of the Quick Match sim (see sim_net_quick.gd): a separate process that signs in to ServiceLocal, quick
## matches over the LAN (UDP on loopback), plays the match over NetSession in the role the service gave it, reports
## the result and prints one "QPEER ..." line. Run by sim_net_quick.gd, not by hand and not part of the suite list.
##   godot --headless --path . -s res://tests/sim/sim_net_quick_peer.gd -- --id=aaaa --name=Ann --gport=17961 --dport=17790


func _initialize() -> void:
	_start.call_deferred()


## Game classes compile only once the autoloads exist, so the work lives in a script loaded here.
func _start() -> void:
	var scr: GDScript = load("res://tests/sim/sim_net_quick_peer_node.gd") as GDScript
	root.add_child(scr.new() as Node)
