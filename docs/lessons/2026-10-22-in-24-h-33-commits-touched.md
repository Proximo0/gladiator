What happened: In 24 h, 33 commits touched lessons_learned.md and 21 touched sim_suite.gd's SIM_FILES list, so most lead merges hit conflicts in those two files
Rule: The suite finds sims by folder scan (markers `## suite: skip` / `## suite: last`). `.gitattributes` merges this file with `union`, so add rows only at the end and never rewrite another row
