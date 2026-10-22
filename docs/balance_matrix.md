# Weapon balance matrix

Every main weapon against every other, bot vs bot, 40 fights per pairing (20 with each weapon on side 0, the same 20
seeds both ways so the seed-rolled armor and personalities swap sides). 16 main weapons, 120 pairings, 4800 fights per
measurement. Shields are off-hand only (`LoadoutRules.is_shield`) and are left out. No off-hand shields in these fights.

How to run it:
- `tools/balance_matrix.py run --fights=20` runs it locally (about an hour on 4 cores; `--only=a,b` / `--vs=a` for subsets).
- Pushing a change to `data/weapons.json` on a `ramp/balance-*` branch runs `.github/workflows/balance.yml`: 20 GitHub
  runners, about 5 minutes. Its `collect` job commits `docs/balance_runs/<sha>.json.gz` to the branch (add `[main]` to the
  commit message to also measure main's weapon data as `<sha>-main.json.gz`).
- `tools/balance_matrix.py report <run.json.gz> --before=<main run> --csv=docs/balance_matrix.csv` prints the tables below.

Fights are seed-deterministic across machines (local and CI cell values matched). Noise: one cell (40 fights) is about
+-8 points, one weapon's overall rate (600 fights) about +-2 points. A change on one weapon moves the cells of every other
weapon a little, so judge single cells with care.

## Targets and where they ended

| Target | Main (before) | This branch (after) |
| --- | --- | --- |
| Inside a tier no cell above ~65 or below ~35 | tier 1: sledgehammer 78-85 against bat, club, machete, bat 68 v machete; tier 4: warhammer 72 v halberd | one cell left: sledgehammer v bat 68/32 (tier 1); tiers 3, 4 and 5 inside |
| Unlocks are side-grades of the starters | sledgehammer (play 5 fights) 69%, the best weapon outside premium | sledgehammer 59, mace 56, falchion 52, halberd 49, machete 47, warhammer 60 against starters longsword 56, bat 54, club 47, axe 47 |
| Premium not pay-to-win (at most even with the best unlockables) | dai-katana 77%, laser 70%; the dai beat every weapon (sledgehammer 58 its closest) | dai 64, laser 58 against warhammer 60, sledgehammer 59. Head to head: dai v warhammer 38, v longsword 50, v mace 55, v halberd 58, v sledgehammer 68; laser v warhammer 48, v mace 48, v sledgehammer 55, v halberd 60 |
| Fists a fun KO underdog | 9%, wins by KO and pummel | 13%, wins by KO 44, pummel 27 |

The dai-katana is still the strongest weapon overall (64) because it beats the cheap weapons (65-80 against bat, club,
rake, gladius), but head to head it is even with the best unlockables: it loses to the warhammer and splits with the
longsword. Its cut went 2.0 to 1.1, the floor `tests/unit/test_premium_weapons.gd` allows (it must out-cut the longsword
and match the falchion, with a 0.9 m edge). A heavier (2.1 kg), blade-heavy (balance 0.45 m) version measured stronger,
not weaker (69 vs 64), so mass and balance are back at 1.6 kg / 0.25 m.

## Data changes (data/weapons.json)

| Weapon | Change | Why (traced) |
| --- | --- | --- |
| dai_katana | cut 2.0 -> 1.1 | 7.3 damage per hit (longsword 3.8); won 77%. Mass and balance tried and reverted |
| laser_sword | cut 2.9 -> 1.6 | 6.2 damage per hit, won 70%; at 1.5 it fell to 54, 1.7 gave 61 |
| sledgehammer | blunt 1.65 -> 1.24, mass 3.2 -> 3.0 | KO and skull-crush machine: 5.4 blunt per hit to the head (club 4.0). Blunt is what moves it; mass 2.6-3.2 measured the same. Still above the club's (test_weapon_unlocks) |
| club | blunt 1.55 -> 1.22 | 65% at baseline, 70-78 against bat, machete, rake |
| machete | cut 1.05 -> 1.4 | 43%, under the band against bat and club |
| gladius | cut 1.0 -> 1.35, pierce 0.8 -> 1.1 | 39%; the bots rarely thrust (2% point contacts), so cut does the work |
| axe | cut 1.15 -> 1.35 | 43-45% |
| halberd | cut 1.1 -> 1.6 | 43%, 28 against the warhammer |
| rake | blunt 0.28 -> 0.45 | 38%, 2.0 damage per hit; wins by KO |
| fists | blunt 1.3 -> 1.5 | 9%; a slightly harder punch keeps them an underdog with more KOs |

Round by round (overall win %, no shields; rounds 2+ on the stable seeds):

| Round | dai | laser | sledge | club | rake | machete | gladius | halberd | axe | fists |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| main | 77 | 70 | 69 | 50 | 38 | 44 | 39 | 43 | 43 | 9 |
| 2 (dai 1.15, laser 2.2, sledge 1.35/2.8 kg) | 68 | 63 | 62 | 50 | 41 | 45 | 41 | 48 | 48 | 12 |
| 3 (dai heavier, laser 1.7, sledge 1.31/2.6 kg) | 68 | 61 | 68 | 48 | 49 | 44 | 43 | 47 | 47 | 12 |
| 4 (club 1.22, sledge 1.24/3.0 kg, laser 1.5) | 69 | 54 | 61 | 47 | 50 | 46 | 42 | 50 | 47 | 12 |
| 5 (dai 1.1, laser 1.6) | 69 | 57 | 60 | 48 | 50 | 46 | 43 | 50 | 48 | 12 |
| 6 final (dai mass/balance reverted) | 64 | 58 | 59 | 47 | 50 | 47 | 42 | 49 | 47 | 13 |

## AI handling problems (for the lead; the AI was not changed)

1. **Spear pokes, it doesn't stab.** 30 hits a fight at 1.2 damage per hit, mean contact speed 4.2 m/s, 7% point contacts.
   54 of its 270 wins come on the time limit (mean fight 35 s). The thrust needs speed at the point (damage_min_speed is 3 m/s).
2. **Swords almost never thrust.** Point contacts: longsword 2%, gladius 2%, falchion 1%, machete 3%. Pierce numbers
   (gladius 1.1, halberd 0.8) barely matter, so the gladius's identity (stab) doesn't show.
3. **Long blades dominate short weapons.** The dai-katana wins 65-80% against bat, club, rake and gladius, and the
   longsword 58-68%; the CPU's spacing rarely lets a short weapon close inside the reach (a guess from the numbers,
   not traced in the brain).
4. **Rake fights drag on.** 23 hits a fight at 2.9 damage, 30 s mean, 37 of its wins on the time limit.
5. **Pole arms swing slowly.** Halberd contacts at 4.9 m/s (sword 6.0); its wins come from blood loss over time.
6. **Shield as a main weapon** (forced bot loadouts only) stalls: 130 of the scutum's wins came on the time limit (mean fight 44 s). Real loadouts
   never do this (MatchConfig keeps shields off-hand), so the matrix leaves shields out. A one-handed weapon plus
   shield matrix is not measured yet.

## Tables (after; "before" is main's weapon data on the same seeds)

fights=4800, side 0 won 49.5% of decided fights

| weapon | tier | win % | before | fights | mean len s | hits/fight | hits taken | dmg/hit | wins by |
|---|---|---|---|---|---|---|---|---|---|
| dai_katana | 5 | 64 | 77 | 600 | 20.7 | 16.4 | 12.3 | 4.1 | blood_loss 253, gut 61, behead 56, time 6 |
| warhammer | 4 | 60 | 59 | 600 | 25.5 | 16.7 | 13.5 | 4.6 | ko 212, skull_crush 64, blood_loss 30, gut 21 |
| sledgehammer | 1 | 59 | 69 | 600 | 23.6 | 14.5 | 13.8 | 5.1 | ko 224, skull_crush 102, pummel 15, time 11 |
| laser_sword | 5 | 58 | 70 | 600 | 21.2 | 15.7 | 14.9 | 3.5 | blood_loss 251, behead 41, gut 29, ko 13 |
| longsword | 4 | 56 | 55 | 600 | 21.6 | 16.9 | 14.2 | 3.8 | blood_loss 236, gut 49, behead 25, ko 13 |
| mace | 3 | 56 | 53 | 600 | 24.5 | 12.4 | 13.9 | 5.0 | ko 175, skull_crush 96, pummel 29, time 17 |
| bat | 1 | 54 | 54 | 600 | 25.3 | 14.9 | 14.9 | 4.0 | ko 166, skull_crush 103, time 24, pummel 22 |
| falchion | 3 | 52 | 51 | 600 | 21.7 | 14.7 | 14.7 | 4.0 | blood_loss 227, gut 45, behead 27, time 6 |
| rake | 1 | 50 | 38 | 600 | 29.7 | 22.5 | 13.6 | 2.9 | ko 192, blood_loss 57, time 37, run_through 6 |
| halberd | 4 | 49 | 43 | 600 | 22.2 | 16.2 | 14.5 | 3.6 | blood_loss 206, gut 45, time 13, behead 12 |
| axe | 3 | 47 | 43 | 600 | 21.4 | 13.4 | 16.9 | 4.4 | blood_loss 178, gut 43, behead 25, ko 23 |
| machete | 1 | 47 | 44 | 600 | 23.6 | 12.6 | 17.5 | 3.6 | blood_loss 207, behead 27, gut 22, ko 13 |
| club | 1 | 47 | 50 | 600 | 24.9 | 13.6 | 17.5 | 3.4 | ko 156, skull_crush 77, pummel 20, time 18 |
| spear | 3 | 45 | 43 | 600 | 34.7 | 29.8 | 13.4 | 1.2 | blood_loss 173, time 54, run_through 37, ko 4 |
| gladius | 2 | 42 | 39 | 600 | 24.3 | 14.1 | 18.2 | 3.0 | blood_loss 180, gut 24, behead 17, time 14 |
| fists | 0 | 13 | 9 | 600 | 25.0 | 8.2 | 28.6 | 8.7 | ko 44, pummel 27, time 6, blood_loss 1 |

| row vs col | fists | bat | club | machete | rake | sledge | gladius | axe | falchion | mace | spear | halberd | long | whammer | dai | laser |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fists (0) | - | 2 | 15 | 28 | 8 | 11 | 20 | 25 | 12 | 18 | 2 | 15 | 5 | 8 | 20 | 8 |
| bat (1) | 98 | - | 60 | 60 | 60 | **32** | 65 | 55 | 58 | 52 | 62 | 55 | 45 | 32 | 35 | 48 |
| club (1) | 85 | 40 | - | 58 | 52 | 38 | 38 | 62 | 45 | 40 | 35 | 55 | 42 | 38 | 25 | 48 |
| machete (1) | 72 | 40 | 42 | - | 38 | 42 | 61 | 58 | 38 | 45 | 58 | 50 | 32 | 50 | 45 | 35 |
| rake (1) | 92 | 40 | 48 | 62 | - | 40 | 75 | 55 | 58 | 48 | 52 | 40 | 32 | 48 | 30 | 25 |
| sledge (1) | 89 | **68** | 62 | 58 | 60 | - | 62 | 60 | 48 | 72 | 65 | 65 | 52 | 50 | 32 | 45 |
| gladius (2) | 80 | 35 | 62 | 39 | 25 | 38 | - | 48 | 30 | 42 | 65 | 62 | 32 | 28 | 20 | 30 |
| axe (3) | 75 | 45 | 38 | 42 | 45 | 40 | 52 | - | 48 | 35 | 60 | 75 | 35 | 45 | 28 | 45 |
| falchion (3) | 88 | 42 | 55 | 62 | 42 | 52 | 70 | 52 | - | 38 | 60 | 48 | 52 | 50 | 28 | 40 |
| mace (3) | 82 | 48 | 60 | 55 | 52 | 28 | 58 | 65 | 62 | - | 58 | 58 | 65 | 45 | 45 | 52 |
| spear (3) | 98 | 38 | 65 | 42 | 48 | 35 | 35 | 40 | 40 | 42 | - | 35 | 41 | 32 | 28 | 55 |
| halberd (4) | 85 | 45 | 45 | 50 | 60 | 35 | 38 | 25 | 52 | 42 | 65 | - | 60 | 52 | 42 | 40 |
| long (4) | 95 | 55 | 58 | 68 | 68 | 48 | 68 | 65 | 48 | 35 | 59 | 40 | - | 45 | 50 | 48 |
| whammer (4) | 92 | 68 | 62 | 50 | 52 | 50 | 72 | 55 | 50 | 55 | 68 | 48 | 55 | - | 62 | 52 |
| dai (5) | 80 | 65 | 75 | 55 | 70 | 68 | 80 | 72 | 72 | 55 | 72 | 58 | 50 | 38 | - | 55 |
| laser (5) | 92 | 52 | 52 | 65 | 75 | 55 | 70 | 55 | 60 | 48 | 45 | 60 | 52 | 48 | 45 | - |

Run files: before docs/balance_runs/f056344-main.json.gz, after docs/balance_runs/0ae1f59.json.gz. Per-pairing rows (win %, fight length, hits, damage per hit, how the wins came, side-0 win %) are in docs/balance_matrix.csv.
