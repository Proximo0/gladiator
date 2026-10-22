What happened: A global `flock` around every Godot run deadlocked agents
Rule: Only `godot --import` takes /tmp/<project>_import.lock. Never wrap tools/*.sh in flock.
