# Premium weapons: Dai-katana and Laser sword

Outfit-bundled weapons. Owning the outfit unlocks its weapon (no separate purchase).

| Weapon | Outfit | Key numbers (data/weapons.json) |
| --- | --- | --- |
| `dai_katana` | Samurai | 1.6 kg, 1.25 m, 0.9 m edge, two-handed, cut 1.55 (longsword 1.0), pierce 0.7 |
| `laser_sword` | Alien | 1.2 kg, 1.25 m, 1.05 m energy blade, one-handed, cut 2.9, pierce 1.2, `glow` colour key, material `energy` |

## Data keys
- `requires_outfit`: outfit id. `LoadoutRules.required_outfit / is_premium_weapon / weapon_unlocked`.
- `look`: placeholder build (`katana`, `laser`) when it differs from the physical `shape` (both are `sword` for contact, AI and sound).
- `glow` (laser only): blade colour. `material: "energy"` selects the crackle/sizzle sounds and cyan sparks.
- data/outfits.json `weapon`: the bundled weapon id; the shop cards show "Includes: Dai-katana / Laser sword" (`OutfitRules.includes_line`).

## Gating
- `LoadoutRules.sanitize(loadout, owned)`: a premium weapon whose outfit is not in `owned` (store product ids) becomes `longsword`.
  `main_weapons(owned)` and the loadout picker list it only when owned (`LoadoutScreen.refresh_weapon_choices`).
- CPU opponent: only in dev runs (`--dev`) or bot runs (forced loadouts); a normal run never gives the CPU one.
- `--store=local` (the "Try outfits (test shop)" bat) is the free-purchase bypass: buying an outfit there unlocks its weapon.
- **Trust issue (online):** the host cannot see a client's store, so it accepts a client's premium weapon as sent
  (`sanitize` with `owned = null`). A modified client can use them without paying. Fixing it needs a server-side
  entitlement check (EOS ownership query by the host). Cosmetic-outfit ownership has the same gap today.

## Visuals and audio
- Katana: wrapped tsuka, tsuba, six tilted blade segments curving toward the edge (placeholder until the glb).
- Laser: dark hilt, white-hot emissive core, additive cyan halo, `BladeGlow` (omni light, motion trail ribbon, hum whose
  pitch follows blade speed, see `LaserHumLogic`). Quality is gated by `GfxQuality.BLADE_TRAIL_SAMPLES / BLADE_LIGHT_ENERGY`
  (low = no trail, no light). Colliders are plain boxes, so hits register like any blade.
- Sounds are synthesised at runtime (`game/audio/laser_synth.gd`: hum, clash crackle, flesh sizzle); no samples, no licences.
  Laser on metal/armor throws cyan sparks.

## Balance (tools/bot_match.sh --shards=1 --w0=<id> --w1=longsword and swapped, seeds 2000-2005 and 2100-2105)
Target 65-75% wins vs longsword. Measured 24 matches each:

| Weapon | Wins / 24 | Rate |
| --- | --- | --- |
| dai_katana (cut 1.55) | 17 | 71% |
| laser_sword (cut 2.9) | 16 | 67% |

Bot results are noisy (+/- one match between runs of the same seed); re-measure after any physics or brain change.
Unit tests assert light taps do not kill and that the premium blades cut but shove no more than a longsword.

## Houdini
`hython tools/houdini/build_weapons.py --only=dai_katana,laser_sword` (add `--no-preview` to skip the Karma render).
Same conventions as the other weapons: +Y long axis, origin at the grip, edges along +-X. The laser glb carries an
emissive "energy" material for the core; the game keeps its own halo/light/trail around any art mesh.
