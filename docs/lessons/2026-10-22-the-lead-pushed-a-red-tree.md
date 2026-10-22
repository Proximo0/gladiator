What happened: The lead pushed a red tree: `(lint; tests; sims) && git commit` only checks the last command of the subshell
Rule: Gate commits on the summary lines (`failed=0`, `problems=0`), not on a subshell exit code
