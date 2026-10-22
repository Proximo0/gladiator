# Play-to-unlock weapons

Earned shields (buckler, parma, pelta, kite, aspis, tower) and earned armor pieces use the same milestones and the
same gating path: see docs/armor_more.md.

Six new weapons, earned by playing. The starters stay free (fists, rake, bat, club, gladius, longsword, axe, spear,
round shield); the premium blades still come with their outfits (docs/weapons_premium.md).

## The weapons (data/weapons.json)
Every new weapon uses a physical `shape` the contact model, the AI and the sounds already know, and a `look` for its
placeholder build in `game/fighter/weapon.gd` (and its Houdini spec in `tools/houdini/build_weapons.py`).

| Weapon | Era | Shape / look | Mass | Length | Feel | Unlock |
| --- | --- | --- | --- | --- | --- | --- |
| `machete` Machete | modern | sword / machete | 0.8 kg | 0.85 m (0.55 m edge) | fast one-hand chopper: cut 1.05, pierce 0.25, blunt 0.08 | Play 2 fights |
| `sledgehammer` Sledgehammer | modern | club / sledge | 3.2 kg | 0.9 m, two-handed | slow, huge blunt 1.5, no cut | Play 5 fights |
| `mace` Flanged mace | medieval | club / mace | 1.6 kg | 0.8 m | one-hand armor crusher: blunt 1.5 (skull crush), no cut | Win 1 fight |
| `falchion` Falchion | medieval | sword / falchion | 1.1 kg | 0.92 m (0.72 m edge) | blade-heavy (balance 0.3 m) chopping sword: cut 1.1, pierce 0.45 | Win 4 fights |
| `warhammer` War hammer | medieval | axe / warhammer | 2.2 kg | 1.35 m, two-handed | hammer face blunt 0.85 plus a short beak "edge" (0.08 m, cut 0.4) | Win 8 fights |
| `halberd` Halberd | medieval | axe / halberd | 2.8 kg | 2.0 m, two-handed | reach: axe blade cut 1.1 (0.22 m), top spike pierce 0.8, half-sword grip | Win 3 ranked Quick Matches |

Shapes are chosen for what the existing code does with them: `club` gives the AI heavy swings and the skull-crush
finisher, `axe` swings with an edge zone at the head (the war hammer's 0.08 m beak stays under the AI's 0.15 m
"edged" line, so it still fights as a crusher), `sword` cuts and stabs. Not `spear`: the spear AI only thrusts and
loses to everything today (docs/balance_rake.md), so the halberd is axe-shaped with `point: true`.

`era` is informational. Gameplay numbers live in the JSON only.

## Unlock rules
A weapon def with `"unlock": {"stat": <counter>, "count": n}` unlocks once the player's counter reaches n.
Counters (`PlayerProgress`, `game/logic/player_progress.gd`), saved in `user://progress.json`:

| Counter | Counts |
| --- | --- |
| `matches` | every finished fight you were in: vs CPU, local 2P, online (direct lobby or Quick Match). Bots never count. |
| `wins` | fights you won: vs CPU (you are side 0), online (your side won). Local 2P counts as played only. |
| `ranked_matches`, `ranked_wins` | Quick Match (rated) fights and wins. On sign-in the service's own record (profile games / wins) is merged in with `max`, so a reinstall does not lose them. |

The counters are recorded in `MenuFlow._on_match_over` (`_record_progress`), once per fight. The result panel then shows
"Unlocked: Flanged mace! Pick it in your loadout." Scripted runs (tests, captures, gates, headless) never write the file:
`MenuFlow` opens the shared progress with `persist = not Flags.is_scripted_run()`.

## Gating (one path for premium and earned weapons)
`WeaponUnlocks.access(store_owned, progress_counters, unlock_all)` builds the `owned` list LoadoutRules already takes:
the store's product ids plus a token `sandblood.unlock.<weapon>` per earned weapon. So `LoadoutRules.sanitize(loadout,
owned)`, `main_weapons(owned)` and `weapon_unlocked(id, owned)` gate both kinds; a locked weapon becomes the longsword
(`PREMIUM_FALLBACK`). `owned = null` still means "trust" (bots, network loadouts the host cannot verify).

- Loadout screen: every weapon is listed; locked ones are greyed with a padlock. Browsing one shows its stats and the
  3D preview, plus a note: "Locked: Win 4 fights (1/4). Fighting with Longsword." Premium: "Locked: Comes with the
  Samurai outfit (Shop)." The loadout keeps the last usable weapon. The note wraps, so it reads at phone width.
- CPU side (custom pick): any play-to-unlock weapon (meet it before you earn it); premium only with `--dev`.
  The random CPU can roll any weapon (MatchConfig), as before.
- `MenuFlow._gate_human_weapons` re-sanitizes the human loadouts when a fight starts (a stale pick from another screen).
- Online screen: the same greyed list. **Ranked Quick Match ignores `--unlock-all`**: the loadout sent to the
  matchmaker and the session is sanitized against earned weapons only (`OnlineScreen.my_loadout / weapon_access`).
  This also fixed an older gap: the online screen used to list premium weapons whether owned or not.

**Trust gap (same as premium):** the host cannot see the client's progress, so a modified client could still send a
locked weapon. Closing it needs a server-side check (the host reads the opponent's EOS stats `sb_wins` / an unlock
stat). See "Lines for other files" in the report for the host-side plausibility hook.

## Owner bypass: `--unlock-all`
`Flags.unlock_all()` (`-- --unlock-all`) opens every play-to-unlock weapon vs CPU, in local 2P and in direct online
lobbies, without touching the saved progress. It does not open the premium blades: use it with `--store=local` (the
free test shop; buying an outfit there unlocks its weapon). Ranked Quick Match ignores it.

Windows launcher: `tools/windows/Try all weapons (unlock all).bat` runs `Sandblood.exe -- --store=local --unlock-all`.
`tools/export_windows.sh` and `tools/export_eos_windows.sh` copy every `tools/windows/*.bat` next to the exe and now
fail if this launcher or the test-shop one is missing. Elsewhere: `godot --path . -- --unlock-all --store=local`.

To reset progress, delete `user://progress.json` (Windows: `%APPDATA%\Godot\app_userdata\Sandblood\progress.json`,
or the project's custom user dir if one is set).

## Balance
Measured with `tools/bot_match.sh --matches=6 --seed=2000 --shards=1 --w0=<new> --w1=<opp>` and the swap (seeds
2000-2005 on both sides, seeded random armor, 60 s limit): wins of the new weapon out of 12. Target 35-65% vs the
longsword. For scale, the starter gladius wins 3/12 against the longsword on the same seeds.

| Weapon | vs longsword | vs other | First try (changed) |
| --- | --- | --- | --- |
| machete | 4/12 (33%) | gladius 9/12 | cut 0.85, 0.8 m, 0.7 kg: 1/12 vs longsword; now cut 1.05, 0.85 m, 0.8 kg (cut 1.1 gave 3/12 and 10/12 vs gladius) |
| mace | 5/12 (42%) | axe 5/12 | blunt 1.3, 0.7 m, 1.5 kg: 2/12, axe 3/12; now blunt 1.5, 0.8 m, 1.6 kg |
| sledgehammer | 7/12 (58%) | club 7/12 (4 draws) | unchanged |
| falchion | 5/12 (42%) | axe 8/12 | unchanged |
| war hammer | 5/12 (42%) | axe 8/12 | blunt 1.0, cut 0.5: 8/12, axe 11/12; now blunt 0.85, cut 0.4 |
| halberd | 6/12 (50%) | axe 7/12 | unchanged |

Bot results are noisy (+/- 2 of 12), and another worker was changing `fighter_brain.gd` during these runs: re-measure
after any brain or physics change. The machete is the one under target (light and short against a 1.2 m blade, like
the gladius) and already beats the gladius 9/12, so it was left there.

## Houdini
`hython tools/houdini/build_weapons.py --only=machete,sledgehammer,mace,falchion,warhammer,halberd` (add `--no-preview`
to skip the Karma render). Same conventions as the other weapons: +Y long axis, origin at the grip, edges (and the war
hammer's beak, the halberd's blade) toward +X; each spec's length / grip match data/weapons.json and the bbox check
enforces them. Drop the glbs in `assets/weapons/<id>.glb`; `Weapon._use_art_mesh` swaps them in (colliders stay).

## Tests
`tests/unit/test_weapon_unlocks.gd` (data, milestones, access list, gating, lock reasons, placeholder colliders span
grip to tip, light taps do not kill, contact kinds), `tests/unit/test_player_progress.gd` (counting, ranked sync,
save format, never writes when not persisting).
