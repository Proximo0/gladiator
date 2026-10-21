# Lessons learned (read before starting work)

Sandblood build guide: https://claude.ai/artifact/LBNp22258n18mRFtk2ke4i (Skate Park playbook: https://claude.ai/artifact/WtmrkVRtizP8oJBRwhxdWW). Add a row here whenever something goes wrong.

| What happened | Rule |
| --- | --- |
| Subagents messaged the user directly | Never call `mcp__hearthbot__` tools. Report only to the lead. |
| A global `flock` around every Godot run deadlocked agents | Only `godot --import` takes /tmp/<project>_import.lock. Never wrap tools/*.sh in flock. |
| Sub-orchestrator agents had no Agent tool | Nested fan-out needs the Workflow tool, or the lead starts every worker. |
| 4 cloud cores cap Godot runs | Use `tools/check_all.sh` locally and the GitHub Actions matrix (`checks`) for scale. |
| A GPU glitch was blamed on a guess | Sample screenshot pixels and reproduce first. If it can't be reproduced, ship toggles. |
| Wall ends were accepted as floor (`floor_max_angle` 80°), so a fake vert launch cut speed to 15% | Measure snags with `tools/snag_sweep.sh`, then fix the traced mechanism. |
| A lab WARN almost undid a design choice (strong halfpipe pump) | Check a WARN against the player's stated wishes before tuning it away. |
| `git commit -a` pushed another worker's half-finished file | The lead stages files by name while workers are editing. |
| A z-fighting floor pad | Lift the mesh, never the collider (`PieceKit.floor_pad`). |
| A `-s` render script couldn't see autoloads | `load()` game classes inside a deferred call. |
| A fix looked plausible but the bug predated the changed code | Check git history for when a bug first appeared. |
| Feel bugs were found by the player, not by us | Build the debug layer and the bot before content: tunables, debug frame, snapshot/replay, recorder, overlay, lab, bot. |
| Ramps had knife-edge side walls under 0.3 m | Piece rule: no collision edge under the skater's radius, side walls run below ground, no coplanar floors. |
| Shader compile failed: `MODELVIEW_MATRIX` used in a fragment shader; a disc rendered culled | `MODELVIEW_MATRIX` is vertex-only (use `VIEW_MATRIX * MODEL_MATRIX` in fragment); Godot front faces wind clockwise |
| The brief said finishers start at `blood / 5.0 < 0.4`, but death is at 2.5 L, so it could never fire | Normalise between the death line and full (`health.blood_frac()`); check a new threshold against the existing ones |
| Thin poles and an awning cast hard streaks across the sand | Only fighters, walls and big shapes cast shadows; thin decorative meshes don't |
| A worker typed a parameter as `Fighter` before that class was committed; CI lint failed on the pushed tree | Code against an uncommitted contract class with duck typing (`Node3D`), and lint a clean clone before pushing when workers are mid-flight |
| Mid-fight restore of a melee diverges (0.2 m after 1 s) though idle restore and fresh starts are exact | Record matches as seed + inputs from tick 0 and replay from the start; treat mid-fight restore as approximate |
| Same-seed bot matches split late in about 40% of fresh runs; a second match in one process always diverged | Jolt's contact order is thread-dependent: sort contacts before first-per-key debounce. Run every same-seed repeat in a fresh process |
