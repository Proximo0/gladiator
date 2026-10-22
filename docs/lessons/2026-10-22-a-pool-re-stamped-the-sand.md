What happened: A pool re-stamped the sand 30x a second at an unchanged radius (25 ms at high in the worst gore case), and a per-texel loop called three sines
Rule: Time sections in a scripted worst case (`perf.sh --heavy`) before guessing; gate repeated work on a changed input, hoist per-texel trig into a table
