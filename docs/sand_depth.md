# Sand depth and particles

Owner feedback: "much deeper sand and much more sand particles." Presentation only: the physics floor stays flat at
y = 0, nothing here is in a state hash.

## Depth
- Every press goes through `SandSurface._visual_depth`: `SandMap.deepen(depth, sand_depth_scale, sand_deep_from,
  sand_deep_gain, sand_max_depth)`. A foot (0.018 requested) digs about 4 cm, a hard fall (0.062) about 17 cm. A hollow is
  never deeper than ~0.85 of its half-width (`DEPTH_PER_WIDTH`), steeper walls than sand holds read as spikes.
- `SandMap.H_MIN` is -0.30 and `H_MAX` 0.25. The bowl wall is wider (smoothstep 0.35..1) and the berm gets
  `sand_rim_gain` (1.3) of the displaced volume.
- `stamp_capsule(from, to, radius, depth, push)` / `SandMap.apply_capsule`: one-pass body-shaped crater with a berm all
  round it (stamping a line of round presses buried each stamp's rim in the next bowl).
- `sand_lift` (3 cm): the visual surface sits above the collider (faded out under the wall), so planted feet (sole at
  y = 0) stand in the sand and prints reach the floor instead of hovering above a pit. `height_at()` includes the lift
  (blood decals follow it). Set it to 0 for the old flat look.
- Shader: hollows are darker and damper (`sand_hollow_dark`), berm crests lighter and drier (`sand_rim_light`). The vertex
  height is box-filtered over one mesh cell (`vtx_cell`) so narrow hollows do not alias into saw teeth; the fragment
  normals still come from the full-resolution map.

## Particles
- `SandFxPlan` (pure) turns an event into grain and dust counts: `step` (every foot-down), `slide` (sprint, rolls, dodges,
  dragged feet, bodies and weapon tips), `fall` (body presses by impact), `strike` (`spray`). Quality share:
  `GfxQuality.SAND_FX_MULT`.
- Grains: `SandFx` MultiMesh, capacity `GfxQuality.SAND_GRAINS` (450 / 900 / 1800), cubes now 6-17 mm.
- Dust: new `SandDust` (pure) drawn as a billboard MultiMesh (`GfxQuality.SAND_DUST` 110 / 260 / 560 sprites); drifts, rises
  slightly and lingers `sand_dust_life` seconds. The old CPUParticles puffs remain for the big events.
- All numbers: Tuning group "Sand" (`sand_*`).

## Perf (tools/perf.sh --quality=all, seed 1002, xvfb software GL; fx_ms is the trustworthy column)

| | low before / after | medium | high |
| --- | --- | --- | --- |
| fx_ms | 0.87 / 0.97 | 1.22 / 1.51 | 1.91 / 2.24 |
| of which grains | 0.08 / 0.22 | 0.10 / 0.42 | 0.14 / 0.72 |
| draw calls | 293 / 293 | 434 / 420 | 477 / 458 |
| peak grains | 200 / 450 | 360 / 900 | 520 / 1800 |

Calls are unchanged (one more MultiMesh). The pools fill to their caps in the bot match at every level.

## Renders
`tests/render/sand_render.tscn` (xvfb window, `-- --out=<dir>/ --quality=N`): footprints, fall crater, sprint spray,
strike spray. Saved in /mnt/project-files/renders/sand/.

## Hooks wanted in match_presenter.gd (not owned here)
- `_bodies`, on touch-down (line ~241): use `sand.call("stamp_capsule", a_flat, b_flat, r * 1.3, 0.012 + 0.05 * impact, push)`
  with `a` and `b` the part's two ends (e.g. torso top and bottom) for a body-shaped crater; `stamp` still works (round).
- Sprint/roll dust works from the existing `stamp_ellipse` and `drag` calls; no other hook is needed.
