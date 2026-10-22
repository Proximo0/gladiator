# Performance

Target: 60 fps on a mid PC and on mid Android phones (Compatibility / GLES3). Measure with `tools/perf.sh`.

## tools/perf.sh

`tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES] [--heavy] [--hide=crowd,hud,shadow,sand,blood,fighters,stands] [--warmup=N] [--res=WxH] [--sweep] [--start] [--legacy|--no_warm|--no_prebuild]`

Runs `tests/perf/perf.tscn`: one presented bot-vs-bot match (full arena, crowd, blood, sand FX, HUD) in a real window
(xvfb on Linux, 320x180, software GL). It fast-forwards (8x time scale) until the first state it sees from
`decals >= 60 and tick >= 600`, or the match ending, or tick 5400 (fallback), then measures 300 frames at 1x and prints one row:

| column | meaning |
| --- | --- |
| frame_ms, p50, p95, max | real frame time (ticks between frames, after `--warmup=N` frames, default 30). Replaces proc_ms: `Performance.TIME_PROCESS` holds the slowest frame of the last second, so a per-frame mean of it repeats spikes |
| phys_ms | real physics time per frame: the physics callbacks plus Jolt's step, timed between marks |
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
| droplet triangles at peak | <= 50k | <= 10k | <= 10k | met (impostors, second pass) |
| live droplets (cap) | 600 | 2400 | 3600 | cap, second pass |
| sand texels stamped per frame (blood) | <= 1.7k | <= 3.4k | <= 5.4k | met (budget + one stamp; second pass) |
| worst blood frame on a real PC, high | | | <= 8 ms | to re-measure (was a 40 ms spike) |
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

## Sand stamping spike, droplet impostors, droplet cap (2026-10-22, second pass)

Real GPU (owner's RTX 5050 laptop, 1920x1080, heavy case, before this pass), high: frame 40.9 avg / 86.5 p95 ms,
blood 4.5 / 8.1 ms with a 40 ms spike, flush_splats 1.3, emit 1.8, sim 0.64, flush 0.5; 2,255 droplets x 336
triangles = 758k triangles (75 percent of all instanced ones); low: frame 35.6, fx 1.5, blood 1.2.

Measured here with a headless blood bench (BloodFx at high, a stand-in sand that runs the real
`SandMap.apply_blood` at 40 texels/m, both "fighters" beheaded, gutted, severed and cut at frame 10, 300 frames).
Texel counts are exact and repeatable; milliseconds are not (the box ran at load 10-30 during this pass, so single
frames stalled 100+ ms in any section): read the texels.

| high, heavy bench | before | after |
| --- | --- | --- |
| most sand texels stamped in one frame | 80,033 | 4,685 |
| largest single sand stamp (radius) | 1.71 m | 0.18 m |
| most litres piled in one 7 cm splat cell | 52.8 | 26.8 (decal only) |
| sand texels stamped over the 300 frames | 1.13M | 0.56M |
| worst flush_splats frame (ms, loaded llvmpipe) | 93-160 | 8-24 (noise bound) |
| flush_splats mean (ms, same) | 3.7-4.9 | 1.9-2.6 |
| live droplet cap | 5000 | 3600 |
| triangles per droplet (medium / high) | 160 / 336 | 2 / 2 |
| droplet triangles at a 3,600-drop peak | 1.21M | 7.2k |

Mechanisms and fixes:

1. **The blood spike was one giant sand stamp.** Landed drops add their litres to a 7 cm cell, and each drop counts
   12x (`VOLUME_BOOST`). A fountain pouring on one spot piled up to 68 L in a cell, which `_flush_splats` stamped as
   one 1.7-2.3 m splat: 40-80k texels in a single `apply_blood` call. The old per-frame budget charged area in
   metres and always let the first splat of a frame through, so the spike went straight past it. Now the budget is
   in texels the stamp really walks (`BloodMath.splat_cost`: the square `apply_blood` loops over, plus the per-call
   edge table), a stamp carries at most `SPLAT_SAND_MAX_LITRES` (0.35 L, about 0.18 m; the ground decal still gets
   all the litres, so the pool reads as big), and a splat too big for what is left waits while smaller ones go.
2. **Two sand stamps skipped the budget.** The fountain's pool pour (every 0.25 s per fountain) and the gut-spill
   smears called `sand.add_blood` directly with any size. Both now go through the splat cells (`_add_splat`).
3. **Droplet impostors on medium and high.** Droplets are a few pixels wide; the 336-triangle teardrop only cost
   vertices. `blood_drop_quad.gdshader` lays one quad per drop along its screen-space velocity, cuts the teardrop
   out in the fragment (round head, elliptical tail) and builds the rounded normal, so the silhouette matches the
   mesh at any distance (compared side by side in renders). Low keeps the 84-triangle mesh: the impostor discards
   fragments, which tile GPUs on phones pay more for. `BloodMesh.IMPOSTOR_MIN_LEVEL` picks the switch.
4. **Live droplet cap at high 5000 -> 3600** (`BloodMath.BUDGETS`). The real-PC heavy peak was 2,255, so a normal
   fight's spray is untouched; the cap bounds the worst case's sim and upload cost.

Look change to check: the impostor's normals face the camera properly; the old mesh shader's lit normals mostly
point up (rendered as colour), so the old drops read darker (mean drop red 128 vs 195 in the same close-up render).
Low still uses the mesh shader and so looks darker than medium and high. If the darker look is wanted, lower
`blood_bright` in the palettes rather than going back to the mesh.

Not changed (outside game/fx/blood): `SandMap.apply_blood` builds its 256-entry edge table (768 `sin`) on every
call, about 160 us of a 170-290 us small splat under GDScript. Caching the table per quantized seed would cut small
stamps by 60-90 percent.

## Frame sections, gore spawn and match-start hitches (2026-10-22, third pass)

`tools/perf.sh` now prints a real-time breakdown per frame (`frame ms (real)`: physics callbacks, Jolt, process
scripts, render/swap/sync; `script sections`: every script `_process` by file, the sound director, both fighters'
steps (`f_*`, `debug_frame`), the presenter's sand tick), `gore spawn` (script ms of the injected cuts and the next
8 frames' wall ms), rigid body counts, and two modes: `--start` (three Match starts as the menu makes them, a forearm
cut at frame 60 of each: setup ms, first-10-frames and gore-10-frames wall ms) and `--sweep` (30 frames with each part
hidden: render cost per part). `--legacy` / `--no_warm` / `--no_prebuild` switch the fixes below off for A/B.

Cloud numbers (software GL, 320x180, `LP_NUM_THREADS=1`, 7 workers on 4 cores: read ratios). In the heavy case all
script is small (process scripts 7.7 ms of a 331 ms frame, physics 3.1 ms of which Jolt 1.0); the rest is llvmpipe.

| | before | after | ratio |
| --- | --- | --- | --- |
| `--heavy` gore spawn, fighter script (2 beheadings + 2 forearm cuts) | 38.6 ms | 2.1 ms | 18x |
| `--start` gore cut, script (one forearm) | 6.7-7.8 ms | 0.7-0.9 ms | ~9x |
| `--start` worst of the 10 frames after the first cut | 478-2726 ms | 225-591 ms | ~4x |
| `--start` Match.setup, 2nd and 3rd match (median of 4) | ~930 ms | ~85 ms | ~11x |
| `--start` sum of the first 10 frames, 2nd and 3rd match | 5.1-19.1 s | 1.9-5.3 s | ~4x |
| first match of the session, first 10 frames | 29.3 s | 34.9 s | warm-up paid once, here |

1. **Cut caps built in the frame of the blow** (glb cap instance and the procedural `CapMesh` face, ~10 ms per cut
   here). `FighterArt.prebuild_step` builds every possible cap ahead, one per frame from the match start (18 per
   fighter, presentation only, off headless); a cut attaches ready caps. Gore faces share one material per fighter.
2. **First-use shader compiles** (first beheading, a weapon or outfit not seen before). `FighterWarmup` (started by
   `MatchPresenter.build`, once per session) draws every outfit, armor kind, weapon and gore cap plus a BloodFx
   beheading/gut/cut/wound for 8 frames in a 64 px off-screen SubViewport with its own world, and keeps the drawn
   materials alive (a StandardMaterial3D shader variant dies with its last material).
3. **Per-match rebuilds.** The tuning panel (~1,500 Controls) is built on its first toggle. The Arena (stands,
   crowd, sand) outlives its Match: the presenter keeps it out of the tree on exit and the next Match at the same
   quality takes it back with the sand cleared (`MatchPresenter._spare_arena`, not in headless runs).

Not changed: physics. Measured in real time it is 3.1 ms per frame here (Jolt 1.0 ms with 30 bodies, 1 asleep);
the "8-11 ms" figure came from the per-second-max monitor. Dead fighters keep their limp PD torques, so their parts
never sleep; letting them sleep would change post-death physics and the state hashes.

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

## Arena look pass (2026-10-22, software GL, seed 1002, CPU contended)

| | before | after |
|---|---|---|
| Low: draw calls | 255 | 215 |
| Low: crowd triangles drawn | 28k | 39.7k (Houdini lod1/lod2 plus 2-triangle impostor cards) |
| Low `--heavy`: calls / MultiMesh triangles / fx_ms (budget 250 / 100k / 8) | 216 / 77k / 7.54 | 227 / 95.9k / 5.11 |
| High: draw calls | 341 | 317 |
| High: crowd triangles drawn | 231k | 231.7k |
| High: MultiMesh triangles / VRAM | - | 289k / 26.2 MB |

`CROWD_TIER_LOD` level 1 now means Houdini lod2 (about 30% of the triangles, heads kept) and level 2 a 2-triangle
impostor card. Dressing (`ArenaDressing`) costs about 20 draw calls on high and 12 on low; on low the standards and
braziers fall back to merged code meshes and statues and the trophy are skipped (`LOW_CODE_PROPS`).

## Arena build time and weapon racks (2026-10-22)

`tools/arena_build.sh [--quality=0|1|2|all] [--runs=N]` builds the presented Arena in a real window (xvfb, software
GL, 4-core box), 3 builds per fresh process, and prints the median ms per step: the first build in a process and the
later ones (a match after the menu). `godot ... -- --arena_profile` prints the same `ARENA_BUILD {json}` line from any
run. Steps are Arena's `_build_*` calls; `sand.<step>` are SandSurface.setup's own laps.

The sand's static tables (256 px noise image, base relief grid and its RGBAH image, the subdivided disc's arrays) were
GDScript loops rebuilt on every arena: 110-180 ms. They now live in `SandTables`, a process cache whose builders run on
a WorkerThreadPool task started at the top of `Arena._ready` (`prewarm`, `is_ready` is the ready flag); the sand step
moved after the dressing, so on a first build the worker overlaps the walls, stands and crowd, and later builds take
the cached tables. The disc loop also tests each grid point once instead of four times per cell.

| median ms (3 processes) | low first | low later | medium first | medium later | high first | high later |
|---|---|---|---|---|---|---|
| before: total | 296 | 203 | 325 | 212 | 358 | 258 |
| before: floor (sand setup) | 229 | 128 | 228 | 144 | 291 | 193 |
| before: noise / base map + texture / disc mesh | 64 / 36 / 16 | 66 / 39 / 17 | 63 / 35 / 35 | 65 / 36 / 34 | 62 / 36 / 80 | 68 / 36 / 78 |
| after: total | 149 | 77 | 163 | 72 | 169 | 79 |
| after: sand step | 79 | 7 | 87 | 9 | 104 | 14 |
| after: crowd / wall visual (largest left) | 27 / 21 | 28 / 19 | 29 / 21 | 26 / 19 | 22 / 20 | 24 / 19 |

About 60 ms of a first build's sand step is the one-time GDScript compile of sand_surface.gd and its classes
(`sand.load_script`); in the game the title backdrop pays it once at boot, never a match start. The racked weapons
(`RackDressing`) load their art with threaded ResourceLoader requests after the build and appear once loaded; the
copy rebuild costs about 3 ms on the main thread. They are 11 copies on medium/high (7 on low: three starters per rack
plus the spares), one MultiMesh per distinct mesh, no shadows.
