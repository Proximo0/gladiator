What happened: Adding a weapon (scutum) mid-round shifted every pair's seed index, so before/after runs were no longer paired
Rule: Seed from the weapons' own indices (i * 64 + j), stable while weapons are only appended; measure "before" on the same seeds
