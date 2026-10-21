# New project checklist

From the build guide: https://claude.ai/artifact/WtmrkVRtizP8oJBRwhxdWW

Day one (before any content):
- [ ] Debug layer is in: `Flags`, frame stamp (F10), render toggles, `Tuning` for every feel number.
- [ ] CI is on: push to GitHub and confirm the `checks` workflow runs unit, lint and sims green.
- [ ] `CLAUDE.md` filled in (what the game is, layout, rules) and `docs/agent_brief.md` units and contracts written.
- [ ] Session-start hook works in a cloud session (Godot pinned to 4.7.2, project imported).

Before building systems:
- [ ] Feel targets agreed with the player in words and numbers (jump height, top speed, turn radius, timing windows),
      written into `docs/` and into `Tuning` defaults. Check a lab WARN against these before tuning it away.
- [ ] Piece collision rules written down before building pieces (minimum collision edge size, nothing coplanar,
      side walls below ground, lift visual meshes, never colliders).
- [ ] Every logic module has a unit test; every feel-critical behaviour has a sim.

While building:
- [ ] Reproduce before fixing: a test, sim, bot run, replay or screenshot sampled for pixels. If it cannot be
      reproduced, ship toggles instead of guessing.
- [ ] Fix the traced mechanism. Check git history for when a bug first appeared.
- [ ] A row goes into `docs/lessons_learned.md` whenever something goes wrong.

Once there is a level:
- [ ] A play-bot (`tests/bot/bot.tscn`, shardable with `--shard=i --nshards=n`) that plays it and flags issues;
      `tools/check_all.sh` picks it up automatically. Fan it out in `.github/workflows/checks.yml`.
- [ ] A lab/sweep scene (`tests/lab/lab.tscn`) for measuring snags and feel numbers, if the game has physics.

Shipping:
- [ ] `tools/check_all.sh` green and CI green, then `tools/export_windows.sh`.
- [ ] Lead-only git: stage by name, one commit per integrated step.
