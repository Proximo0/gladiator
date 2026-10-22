What happened: Same-seed bot matches split late in about 40% of fresh runs; a second match in one process always diverged
Rule: Jolt's contact order is thread-dependent: sort contacts before first-per-key debounce. Run every same-seed repeat in a fresh process
