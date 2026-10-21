# Performance

Target: 60 fps on a mid PC and on mid Android phones (Compatibility / GLES3). Measure with `tools/perf.sh`.

## tools/perf.sh

`tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES] [--hide=crowd,hud,shadow,sand,blood,fighters,stands]`

Runs `tests/perf/perf.tscn`: one presented bot-vs-bot match (full arena, crowd, blood, sand FX, HUD) in a real window
(xvfb on Linux, 320x180, software GL). It fast-forwards (8x time scale) until the first state it sees from
`decals >= 60 and tick >= 600`, or the match ending, or tick 5400 (fallback), then measures 300 frames at 1x and prints one row:

| column | meaning |
| --- | --- |
| proc_ms, p95 | engine process time per frame. **Under software GL this is the renderer, not the game: do not read it.** |
| phys_ms | physics time per frame (Jolt, fighters) |
| fx_ms | script time of the blood step plus the sand `_process`, timed apart from the renderer (the number to trust for CPU) |
| calls | draw calls per frame (includes shadow passes and the HUD) |
| prims | Godot's primitive counter. **It counts a MultiMesh's mesh once per draw, not once per instance**, so it ignores the crowd and the grains; use `tris_drawn` below for the crowd |
| decals, drops, grains, mist | peak counts over the run (ground decals, blood droplets, sand grains, blood mist) |

Extra lines: per-section fx milliseconds, crowd seats / triangles in buffers / triangles drawn / MultiMesh calls,
and the heaviest geometry groups ("draw suspects"). `--hide=` switches parts off during the measured window; the
difference in calls is that part's cost (see below).

Seed 1002 is used because the presented match is deterministic per seed; it ends at tick 515 in this harness, so the
"late" point is the end of a kill with all blood present. Numbers move a little between runs (Jolt contact order).

## Quality setting

`GfxQuality.level` (`game/fx/gfx_quality.gd`): 0 low (default on `OS.has_feature("mobile")`), 1 medium, 2 high
(desktop default). Set it **before** the match (arena, sand and blood read it when built); `GfxQuality.blood_level()`
is the matching `BloodFx.set_quality` value.

| | low | medium | high |
| --- | --- | --- | --- |
| crowd spacing (x, back tiers extra x) | 1.4 (x1.6) | 1.15 (x1.25) | 1.0 |
| spectators | 368 | 487 | 623 |
| crowd mesh per tier 0..5 (-1 full, 0 ~50%, 1 ~20%, 2 ~6% of triangles) | 1 1 1 2 2 2 | 0 0 0 1 1 1 | -1 -1 0 0 0 0 |
| cheering twins | tiers 0-2 | all | all |
| crowd sectors (view culling) | 2 | 3 | 4 |
| sun shadow | 1 split, 34 m, no blur | 2 splits, 44 m, blur 1 | 2 splits, 52 m, blur 2 |
| velarium casts shadow | no | no | yes |
| MSAA 3D | off | 2x | 2x |
| forearms / shins (art, caps, armor on them) cast shadow | no | yes | yes |
| sand texels per metre / floor mesh cell | 26 / 0.22 m | 32 / 0.15 m | 40 / 0.10 m |
| sand grains / dust puffs | 200 / 4 | 360 / 7 | 520 / 10 |
| sand shader detail | 0 | 1 | 2 |
| sand pool step / GPU upload | 12 Hz / 15 Hz | 20 Hz / 20 Hz | 30 Hz / 30 Hz |
| blood droplets / mist / ground decals | 600 / 90 / 160 | 2400 / 240 / 420 | 5000 / 480 / 900 |
| blood splats turned into sand stains per frame | 12 | 24 | 48 |

Sand shader detail: 0 drops the fine grain slopes and the rake lines, 1 also keeps them but drops pebbles, speckle
and glints (2 is the full look).

## What was costing, and what was done

Measured on the same bot match (seed 1002, tick 515), before = the tree before this work at the high setting.

1. **Crowd vertices.** 623 spectators, each 550 triangles, and every standing spectator also had a hidden twin that
   was "hidden" in the vertex shader (`VERTEX *= 0`): the GPU still ran its vertices. 515k triangles went through the
   vertex stage per frame. Now `CrowdCull` sorts each MultiMesh by cheer threshold and sets `visible_instance_count`,
   so only the shown twin is submitted, and far tiers use decimated meshes (`Crowd.decimated`, ImporterMesh LODs; a
   MultiMesh cannot use engine mesh LOD). This also fixes a bug: with the old shader a standing spectator without a
   twin (the back tiers on phones) vanished when the crowd got excited.
2. **Sand floor mesh and shader.** The floor was 0.1 m cells (~88k triangles with a heavy fragment shader: ~14 texture
   fetches, three trig-heavy relief evaluations, pebbles, speckle, glints). Low uses 0.22 m cells (~20k triangles), a
   cheaper shader and 26 texels/m (the CPU maps shrink to 42%).
3. **Sand CPU.** Pools repainted every texel of every pool each frame (0.9 ms at high); now they step at a quality
   rate with the elapsed time kept. Uploads, grains and puffs are capped per quality.
4. **Blood.** Caps already existed (droplets, mist, decals, stains by quality); the per-frame splat-to-sand work
   (up to 48 `add_blood` calls) now also follows quality. The presenter must pass `GfxQuality.blood_level()`.
5. **Shadows.** One split instead of two on low, a shorter distance, no soft blur, and the velarium no longer casts.
6. **MSAA** is off on low.

## Numbers

xvfb, software GL, 320x180. `fx_ms` and `crowd tris` are meaningful; `proc_ms` is not (llvmpipe).
Before is the old tree, after is the current one at each quality.

| | before (high) | after high | after medium | after low |
| --- | --- | --- | --- | --- |
| fx_ms (blood + sand script, per frame) | 4.34 | 3.73 | 2.38 | 1.69 |
| of which sand pools / flush | n/a | 0.97 / 0.57 | 0.38 / 0.31 | 0.17 / 0.17 |
| crowd triangles through the vertex stage | 515k | 231k | 99k | 28k |
| crowd MultiMesh draw calls | 42 | 81 | 61 | 33 |
| draw calls per frame (whole scene) | 726 | 745 | 714 | 671 |
| sand floor triangles | ~88k | ~88k | ~38k | ~20k |
| peak ground decals / droplets / grains | 420 / 464 / 520 | 420 / 464 / 520 | 269 / 260 / 360 | 160 / 181 / 200 |
| physics ms | 3.1 | 3.2 | 3.4 | 4.9 (noise: same sim) |

Where the draw calls are (high, early in the fight, `--hide=`): HUD 228 of 486, fighters 147 (with their shadow
pass), crowd 81, shadow pass 59, stands and props 21, sand 6, blood 3. Triangles by the primitive counter (which skips
instancing): fighters 103k, sand 88k, shadow pass 63k. At low: crowd 32 calls, shadow pass 56 calls.

### Draw calls after the HUD and fighter pass

Same bot match (seed 1002, tick 515), `tools/perf.sh --quality=all`; `--hide=` rows are the whole scene minus that part.

| | low | medium | high |
| --- | --- | --- | --- |
| draw calls before (whole scene) | 671 | 714 | 745 |
| draw calls after | 255 | 310 | 341 |
| HUD cost after (whole scene minus `--hide=hud`) | 68 | 68 | 68 |
| fighters after (whole scene minus `--hide=fighters`) | 135 | 167 | 188 |

HUD: the meander rules were one `draw_polyline` per Greek-key cell (28 per meter, about 54 per banner rule); they are
now cached segment lists drawn with one `draw_multiline` each (`BloodMeter.meander_segments`). The dashed death line
and the flow streaks are one multiline each, and the banner is `visible = false` while idle, so it costs nothing
until `announce()`. The look is unchanged (compared before/after HUD screenshots; only the antialiasing of the rule
rows differs by about a pixel).

Fighters on low: forearms and shins (and their dismemberment caps) no longer cast into the shadow map
(`GfxQuality.SMALL_PART_SHADOWS`, `FighterArt.apply_shadow`). Armor and weapon meshes are added by `fighter.gd` and
`weapon.gd`, which must call `FighterArt.apply_shadow(part_body, part_name)` after adding them; until they do, armor
trims on forearms and shins still cast.

Draw calls on a mid phone are cheap to a point (a few hundred is fine) and the crowd and sand triangle cuts are
the GPU-side win; the CPU-side wins are the sand pools, uploads and splat caps (fx_ms 4.34 -> 1.69).

## Options menu

Options has one "Graphics: Low / Medium / High" picker (`MenuSettings.gfx_quality`, saved under `[graphics]
gfx_quality`, never in scripted runs). It replaces the old Blood picker: the same level sets everything in the table
above, blood included (`GfxQuality.blood_level()`). Old settings files migrate from `blood_quality`. The default is
`GfxQuality.default_level()` (low on mobile, high on desktop). `MenuFlow` calls `settings.apply_quality()` before
`Match.new()` for local, CPU, online host and online client matches; a `--quality=N` run argument overrides it. The
F7 MSAA toggle turns MSAA on to `GfxQuality.MSAA` for the current level, so it stays off on low.

## Rules for new effects

- Pool and cap everything per quality; never let a count grow with match length.
- A MultiMesh draws its first `visible_instance_count` instances: sort and cut instead of hiding in a shader.
- Do not hide geometry by scaling to zero in the vertex shader; the vertices are still processed.
- Time script cost on its own (see `fx_ms`); software GL frame time says nothing about a phone.
- Re-run `tools/perf.sh --quality=all` after adding an effect and put the new row in this file.
