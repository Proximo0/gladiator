What happened: A "concurrency flake" (Identifier "FighterWarmup" not declared, sims after it fail) was really another worker editing the same working tree while a suite ran; a second worker also committed with `git add -A` into the shared tree
Rule: Run a long suite in your own clone, not a tree others edit; stage named files, never `git add -A` in a shared checkout
