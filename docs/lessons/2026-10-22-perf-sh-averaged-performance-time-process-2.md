What happened: perf.sh averaged `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` per frame and blamed 24 ms on GDScript; those monitors hold the slowest frame of the last second (and include the renderer), so spikes were counted every frame
Rule: Time real frames yourself (ticks between frames, p50/p95/max) and sections with `Time.get_ticks_usec` marks; skip warm-up frames before measuring
