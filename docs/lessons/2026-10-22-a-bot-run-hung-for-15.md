What happened: A bot run hung for 15 min and wrote a 334 MB log: another worker's half-saved `fighter_brain.gd` failed to parse at launch, so every tick errored
Rule: Watch a long bot run's log size or error lines, not just its exit; re-run balance after a shared script stops changing
