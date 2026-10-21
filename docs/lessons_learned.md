# Lessons learned (read before starting work)

The full build guide is a Claude Doc: https://claude.ai/artifact/WtmrkVRtizP8oJBRwhxdWW. Add a row here whenever something goes wrong.

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
