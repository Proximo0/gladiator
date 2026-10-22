What happened: A worker cleared its own hung Godot with `pkill godot` and killed another worker's render
Rule: Kill only your own PIDs (`kill <pid>`); never `pkill godot` while other workers run
