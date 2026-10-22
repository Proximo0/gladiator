# Gladiator (Godot 4.7.2, GDScript)

Gladiator (working title) is an M-rated, physics-driven 1v1 melee fighter in a small sand arena, in the spirit of
Half Sword: active-ragdoll fighters, the weapon hand steered directly by mouse, stick or touch, and damage from how the
weapon really connects. Fists, rakes and bats up to swords, spears and shields; per-part armor; graphic gore (blood,
dismemberment, gutting, beheading). v1: one arena, CPU opponent, local 2P, online 1v1, Windows/Mac/Linux/Android.
The current step's contract is in `docs/core_brief.md`; read it before coding.

## Commands
- `tools/run_tests.sh [test_name]`: headless unit tests (`tests/unit/test_*.gd`). Prints failures only.
- `tools/lint.sh`: parse and static checks for every script. Ends with `LINT problems=<n>`.
- `tools/run_sims.sh`: regression sims (every `tests/sim/sim_*.gd` with a `run()`, found by `tests/sim/sim_suite.gd`).
- `tools/sim_isolation.sh [sim ...]`: each sim file alone vs the whole suite in one process; prints rows that differ.
- `tools/check_all.sh`: everything at once (unit, sims, lint, plus the bot and lab if their scenes exist).
- `tools/export_windows.sh`: Windows build zip in `build/`.
- Run the game: `godot --path .` (add `-- --dev` for dev entries, `-- --stamp` to show the frame stamp).

## Layout
- `game/autoload/`: `Flags` (run flags, frame counter, state hash), `Controls` (input actions).
- `game/debug/`: frame stamp (F10), render toggles (F4, F6-F9), `Tuning` (live-tunable numbers).
- `game/<system>/`: one folder per system.
- `tests/unit/`: one `test_<module>.gd` per module, `extends TestCase`. `tests/sim/`: regression sims.
- `tools/`: shell and Python tools. Python uses the standard library only.
- `docs/`: `agent_brief.md` (contracts and subagent rules), `lessons/` (one file per lesson; format in
  `lessons_learned.md`), `new_project_checklist.md`.

## Rules
- Static typing everywhere: typed vars, params and returns. Tabs for indentation.
- Gameplay logic is pure `RefCounted` classes with `class_name`, no Node, no wall clock, no `randf()`: take `delta`
  and a seeded `RandomNumberGenerator`. Nodes are thin wrappers that feed them input. Put pure logic in
  `game/logic/` (or edit `PURE_PREFIXES` in `tools/lint.py`).
- Gameplay numbers live in `Tuning` (or data files), never as literals in logic.
- Every logic module has a unit test file. A change is done when `tools/run_tests.sh` and `tools/lint.sh` pass.
- File-local helper names must be unique across the project (one `class_name` space).
- Tools are quiet: print errors and failures, then one summary line.
- Scripted shots key on game state (an observed condition) with a time fallback, never fixed seconds alone.
- Compare state hashes only on frames where `Flags.commands == 0`.
- Captures, tests and gates never write player data (`Flags.is_scripted_run()`).
- Reproduce a bug (test, sim, bot, replay) before fixing it; fix the traced mechanism, not a guess.
- Read the lessons before starting (`python3 tools/lessons_index.py`); whenever something goes wrong, add one as a new
  file in `docs/lessons/` (format in `docs/lessons_learned.md`).
