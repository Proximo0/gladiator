What happened: A render capture keyed on frame counts looked hung for 5 min at load 45: wall-clock frames crawled and the intro timer ran on real time
Rule: Run captures with `--fixed-fps 60` so frames, timers and physics advance together, and print a line per saved shot
