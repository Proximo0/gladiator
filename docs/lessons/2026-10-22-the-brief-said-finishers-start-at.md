What happened: The brief said finishers start at `blood / 5.0 < 0.4`, but death is at 2.5 L, so it could never fire
Rule: Normalise between the death line and full (`health.blood_frac()`); check a new threshold against the existing ones
