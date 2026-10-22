What happened: A sim that died on a script error (net_menu, while other workers ran net sims on the same ports) printed no rows and the suite still said failed=0
Rule: Read the SIM lines, not just the totals: a sim that returns no rows is a failure
