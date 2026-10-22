# Performance

Target: 60 fps on a mid PC and on mid Android phones (Compatibility / GLES3). Measure with `tools/perf.sh`.

## tools/perf.sh

`tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES] [--heavy] [--hide=crowd,hud,shadow,sand,blood,fighters,stands]`

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

`--heavy` is the worst-case scenario: when the measured window starts, both fighters get a beheading (fountain), a gut
spill (rope sim), a severed forearm and a thigh wound at once (`BloodFx.on_gore`). Extra line `live_drops` and `mm_tris`
count MultiMesh triangles per group (instances shown x mesh triangles, peak over the window).

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
| sand grains / dust sprites / puffs | 450 / 110 / 4 | 900 / 260 / 7 | 1800 / 560 / 10 |
| sand shader detail | 0 | 1 | 2 |
| sand pool step / GPU upload | 12 Hz / 15 Hz | 20 Hz / 20 Hz | 30 Hz / 30 Hz |
| blood droplets / mist / ground decals | 600 / 90 / 160 | 2400 / 240 / 420 | 5000 / 480 / 900 |
| blood splats turned into sand stains per frame (calls / area in 5 cm splats) | 12 / 8 | 24 / 18 | 48 / 36 |
| droplet mesh triangles (sides x rings) | 84 (6x8) | 160 (8x11) | 336 (12x15) |

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

## Worst case after beheading, gut spill, dust, teardrops (2026-10-22)

`tools/perf.sh --quality=all --heavy` (seed 1002, injected gore on both fighters at tick 542, 300 frames at 1x, software
GL, 320x180). Before = tree at the start of this pass; after = with the three fixes below. CPU ms are noisy under
llvmpipe (it shares the cores): read the ratios. `drops` is the peak live droplets.

| | low before | low after | med before | med after | high before | high after |
| --- | --- | --- | --- | --- | --- | --- |
| fx_ms (blood + sand script) | 8.84 | 7.54 | 18.93 | 14.16 | 67.54 | 33.73 |
| sand pools | 1.64 | 0.81 | 2.17 | 0.34 | 25.26 | 1.86 |
| splats (sand stamping) | 2.43 | 1.55 | 7.94 | 4.00 | 25.08 | 12.43 |
| emit (fountain, wounds, guts) | 2.23 | 2.21 | 4.20 | 4.07 | 6.21 | 7.01 |
| flush (sand GPU upload) | 0.80 | 0.83 | 1.29 | 1.62 | 5.96 | 5.28 |
| physics ms | 7.28 | 6.20 | 4.71 | 4.94 | 4.43 | 4.80 |
| draw calls | 220 | 216 | 276 | 287 | 328 | 339 |
| peak droplets | 525 | 524 | 2029 | 1930 | 3223 | 3898 |
| droplet triangles at peak (drops x mesh) | 176k (est.) | 38k | 682k (est.) | 157k | 1.08M (est.) | 1.25M |
| MultiMesh triangles, all groups (crowd incl.) | | 77k | | 275k | | 1.52M |
| of which guts / dust / grains / decals | | 6k / 0.2k / 4k / 0.3k | | 15k / 0.5k / 2k / 0.8k | | 23k / 1k / 15k / 1.2k |
| VRAM MB | 19.6 | 19.6 | 23.1 | 23.1 | 25.6 | 25.6 |
| nodes | 2474 | 2466 | 2540 | 2576 | 2650 | 2690 |

("est." = peak droplets x 336, the old single mesh. The primitive counter ignores all of these; `mm_tris` is ours.)

Budgets (low must stay Android-safe; numbers from this table, software GL, so treat CPU ms as 3-5x a desktop):

| budget | low | medium | high | status |
| --- | --- | --- | --- | --- |
| worst-case fx_ms (script, per frame) | <= 8 | <= 15 | <= 35 (desktop) | met |
| draw calls, whole scene | <= 250 | <= 320 | <= 400 | met |
| MultiMesh triangles incl. crowd | <= 100k | <= 300k | <= 1.6M | met |
| droplet triangles at peak | <= 50k | <= 200k | <= 1.5M | met (new) |
| VRAM | <= 32 MB | <= 48 MB | <= 64 MB | met (new) |

Fixes, each at the traced mechanism:

1. **Sand pools repainted unchanged texels (25 ms -> 1.9 ms at high).** A spreading pool re-ran `apply_blood` every
   step (up to 8 pools, 30 Hz) although its radius grows only a few texels in 2.5 s and a max-blend repaint of the
   same radius changes nothing. Now it repaints only after the edge grew `POOL_MIN_GROW` (0.6 texel).
2. **`apply_blood` per-texel cost (splats 25 -> 12 ms high, 7.9 -> 4.0 medium).** Each texel called `blood_edge` (three
   `sin`) and two `smoothstep`. Now one 256-entry edge table per call (`SandMap.EDGE_BINS`), inlined smoothsteps and
   an early skip beyond `EDGE_MAX * 1.6 * r`. Plus `BloodMath.SPLAT_AREA`: a per-frame budget in splat area, so a few
   large pool splats no longer take the whole frame (the rest merge into their cell and wait).
3. **Droplet mesh (336 triangles, 12 sides) at every quality.** `BloodMesh.for_quality` swaps the MultiMesh mesh in
   `BloodFx.set_quality`: 84 triangles on low, 160 on medium, 336 (unchanged) on high. Peak droplet triangles on
   low drop from about 176k to 38k, on medium from about 680k to 157k.

Not changed: high still draws 1.25M droplet triangles at the peak of a double gore (fine on a desktop GPU, the thing to
watch on a weak iGPU).

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
