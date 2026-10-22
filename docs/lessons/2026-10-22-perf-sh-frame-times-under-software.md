What happened: perf.sh frame times under software GL moved 7 ms between two runs of nearly the same tree (the "after" was faster), so a sub-millisecond shader cost could not be read from them
Rule: Measure a small shader change in one process with the feature toggled in alternating blocks over a fixed scene (`tests/perf/contact_bench.tscn`); compare off and on, never two separate runs
