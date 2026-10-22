What happened: Agent calls with isolation "remote" ran as local background subagents on the same 4-core box (load 70, branches barely landed) and some checked out branches in the shared main tree
Rule: Verify where an agent runs (cwd, list_sessions) before claiming extra machines; real scale-out is separate cloud sessions or the Actions matrix; keep local workers to the core count's budget
