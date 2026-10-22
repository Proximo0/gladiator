What happened: A rate-per-second sim check failed when a bot fight ended in 4 s: the opening clash and finisher burst made the mean 36/s
Rule: Divide rates by a floor duration (8 s) so short fights do not inflate them; bursts belong to the max/s check
