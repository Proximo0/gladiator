What happened: perf.sh averaged Performance.TIME_PROCESS per frame and reported 36 ms on low; that monitor updates about once a second with the slowest frame, and the first run included shader compiles (real: 5.2 ms)
Rule: Time real frames (ticks between frames, p50/p95/max) after a warm-up; never average a once-per-second monitor
