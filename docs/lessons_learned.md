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
| A knocked-off armor prop had a layer the fighters scan but a mask that ignored them; Godot made it an immovable block that pinned a fallen fighter's thigh for 40 s (seed 5007) | Give dynamic props symmetric masks, or no layer at all; never one-sided |
| Owner saw "green blood": shadows on orange sand read olive/teal because the only fill light was a blue sky ambient, and damp sand darkened the warm part | Use a warm colour ambient in a sand arena and sample shadow pixel colours (hue) in renders before blaming the blood shaders |
| Round 4 started from round 3's numbers (126 hits/min), but the arena-footwork brain change had already moved them to 95 | Re-measure the baseline on the current tree before tuning; numbers go stale after any brain or physics change |
| Closing the ENet peer from inside its own `poll()` (a disconnect signal handler) crashed with signal 11 | Never close a MultiplayerPeer from its own signal; defer the close to the next idle frame |
| ENet's packet throttle silently dropped about half the unreliable snapshots after a frame hitch | Switch the ENet throttle off on connect (deceleration 0) for snapshot streams |
| A shader-hidden crowd twin (`VERTEX *= 0`) still cost its vertices, and Godot's primitive counter ignores MultiMesh instances, so the crowd looked cheap | Cut instances with `visible_instance_count`; count MultiMesh triangles yourself and time script cost separately |
| EOSG's create-user login path fires no Connect login callback, so the runtime never learned the local user | Log in a second time after creating the device user; mock a plugin's native singleton to run its real GDScript without the binaries |
| A reliable events packet could exceed the EOS relay's 1164-byte limit and be silently dropped | Split network packets by bytes, not by record count (`NetEvents.encode_chunks`) |
| A bot run hung for 15 min and wrote a 334 MB log: another worker's half-saved `fighter_brain.gd` failed to parse at launch, so every tick errored | Watch a long bot run's log size or error lines, not just its exit; re-run balance after a shared script stops changing |
| Spear AI aimed open-loop and thrust from walking speed, so its "thrusts" were sub-3 m/s shaft touches (0 wins of 10) | For long weapons, steer on the measured blade line and check speed against damage_min_speed; reach comes from footwork, not arm extension |
| Two fighters with the same weapon shared one cached glb `Mesh`; per-instance override materials on a shared mesh gave `Parameter "material" is null` at teardown | Duplicate an instanced glb's mesh before setting surface override materials |
| Fist fights could never be won: no bleeding, and the time-out judge only compared blood | Every win rule needs a fallback for its zero case (level blood falls back to body hp) |
| Container restarts killed running workers three times | Workers leave WIP in the tree; relaunch a worker on that WIP with the prior findings, never from scratch |
| Houdini 22's glTF ROP exports every material as `alphaMode BLEND` | Force imported art opaque (or set it in the ROP); `hipFile.save` needs its folder made first; run Houdini builds with `--only=<ids>` |
