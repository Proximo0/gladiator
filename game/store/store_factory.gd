class_name StoreFactory
extends RefCounted
## Picks the store backend for this run. A dev or debug run (or --store=local) gets StoreLocal, which sells for free;
## a release build never does: Android gets StoreGooglePlay and anything else StoreEpic. Scripted runs (tests,
## captures) get a StoreLocal that keeps its owned set in memory only.


static func create() -> Store:
	# Looked up by node path, not by the autoload's name, so a script that compiles before the autoloads still loads.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var flags: Node = tree.root.get_node_or_null("Flags") if tree != null else null
	var scripted: bool = flags == null or bool(flags.call("is_scripted_run"))
	var want: String = str(flags.call("get_arg", "store", "")) if flags != null else ""
	if want == "" and (OS.is_debug_build() or (flags != null and bool(flags.call("dev_menu")))):
		want = "local"
	if want == "" and OS.has_feature("android"):
		want = "google_play"
	match want:
		"local":
			return StoreLocal.new(not scripted)
		"google_play":
			return StoreGooglePlay.new()
		_:
			return StoreEpic.new()
