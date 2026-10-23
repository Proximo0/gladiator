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

## Round 4 (after the round-4 AI: committed thrusts, closing plan, armor reads; main 654f700)

The new brain moved the matrix a lot: the baseline on main 654f700 had 36 pairings out of the 35-65 band (fists left
out), with the spear at 67% and the bat at 39%. Four rounds of data changes on the CI runners, 4800 fights each.

| Target | Main 654f700 (before) | After (0816f76) |
| --- | --- | --- |
| Pairings outside 35-65 (no fists) | 36 | 24 |
| Inside a tier no cell above ~65 or below ~35 | 8 cells: sledgehammer v bat 86, rake v club 75, sledgehammer v club 70, falchion v axe 68, spear v axe 66, spear v mace 68, longsword v warhammer 72, dai v laser 78 | 5 cells: bat v club 78, rake v club 72, sledgehammer v club 70 (all the club), spear v mace 76, dai v laser 78. Sledgehammer v bat is 58/42 |
| Unlocks are side-grades of the starters | spear 67, falchion 59 against starters longsword 59, bat 39, club 37 | spear 58, warhammer 59, falchion 54, sledgehammer 52 against longsword 61, bat 50, club 36, axe 49 |
| Premium not pay-to-win | dai 69, laser 58 | dai 67, laser 58 (dai still above every unlockable; see below) |
| Fists a fun KO underdog | 11% | 12%, wins by KO 42, pummel 22 |

### Data changes (data/weapons.json)

| Weapon | Change | Why (traced) |
| --- | --- | --- |
| bat | blunt 1.2 -> 1.55 | 39% overall, 14 against the sledgehammer; the closing plan makes it wait outside longer reach. 1.4 gave 45, 1.55 gives 50 and sledgehammer v bat 58 |
| spear | cut 0.3 -> 0.15, pierce 1.0 -> 0.8 | 67%: the committed thrust plus edge contacts on every swing. Pierce 0.8 is the floor `test_spear_passes_mail_and_guts` allows (0.7 fails it); mass 2.3 measured the same and was reverted. 62 after pierce, 58 after the cut |
| falchion | cut 1.1 -> 0.95 | 59%, 68 against the axe; now 54 and 58 |
| warhammer | blunt 0.85 -> 1.05 | 28% against the longsword (same tier); now 35 |
| scutum (shield) | bash 0.7 -> 0.35 | shield row 70% at 96 fights; 0.5 measured 69, 0.35 gives 56 |
| tower_shield (shield) | bash 0.35 -> 0.2 | shield row 67% at 96 fights; 0.2 gives 58 (12 kg measured 78) |
| kite_shield (shield) | bash 0.6 -> 0.45 | shield row 64-67% at 96 fights; 0.45 gives 57 |

Tried and reverted (no move on the weapon's own rate, within noise): club blunt 1.22 -> 1.35 (with the sledgehammer at
1.36 to keep `test_weapon_unlocks`' out-crush rule), club mass 1.6 -> 1.9, club balance 0.5 -> 0.42 (club 36-38% in
every round); dai-katana cut 1.1 -> 0.95 and 1.02, pierce 0.7 -> 0.4 (69% each time), mass 1.6 -> 1.35 (72%).

Round by round (overall win %):

| Round | dai | spear | long | falchion | whammer | sledge | bat | club | mace | axe |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| main 654f700 | 69 | 67 | 59 | 59 | 54 | 51 | 39 | 37 | 49 | 49 |
| 1 (spear pierce 0.8, dai/falchion cut 0.95, bat 1.4, club 1.9 kg) | 69 | 62 | 61 | 55 | 53 | 51 | 45 | 38 | 48 | 51 |
| 2 (dai pierce 0.4, spear 2.3 kg, bat 1.55, club balance 0.42, whammer 0.95) | 69 | 62 | 61 | 53 | 54 | 50 | 48 | 37 | 48 | 47 |
| 3 (club 1.35 / sledge 1.36, spear cut 0.15, dai 1.35 kg, whammer 1.05) | 72 | 59 | 62 | 53 | 58 | 50 | 48 | 38 | 45 | 48 |
| 4 final (club, sledge, dai back) | 67 | 58 | 61 | 54 | 59 | 52 | 50 | 36 | 47 | 49 |

### Shields (gladius + shield v longsword, leather, seeds 2000-2047 both sides, 96 fights per row)
The bot only raised a shield whose id contained "shield" (`FighterBrain._shield_up`), so the scutum, buckler, parma,
pelta and aspis were never lifted; fixed on main (`LoadoutRules.is_shield`). With 24 fights a row moves by about 10
points between seed sets (tower 71 on seeds 2000-2011, 56 on 2000-2023), so the rows below use 96.

| Shield | Main 654f700 | After | Length after |
| --- | --- | --- | --- |
| shield_round | 42 (44%) | 40 (42%) | 23.5 s |
| scutum | 67 (70%) OUT | 55 (57%), bash 0.35 | 27.4 s |
| buckler | 36 (38%) | 37 (39%) | 22.8 s |
| parma | 35 (36%) | 35 (36%) | 24.5 s |
| pelta | 43 (45%) | 40 (42%) | 26.1 s |
| kite_shield | 61-64 (64-67%) | 55 (57%), bash 0.45 | 25.7 s |
| aspis | 51 (53%) | 49 (51%) | 25.1 s |
| tower_shield | 64 (67%) OUT | 56 (58%), bash 0.2 | 27.0 s |

Unchanged rows move by 1-3 wins of 96 between runs. The kite row read 64 then 67 with no change to its data, so its
bash went 0.6 -> 0.45 too.

### What data cannot fix (for the lead)
1. **Club** (36%, loses 22-30 to bat, rake and sledgehammer): blunt +11%, mass +19% and balance -16% each moved it by a
   point at most. It is the shortest weapon, so the closing plan (task 19) keeps it waiting outside every foe's reach;
   its fights are long (31 s) with 32 time-limit losses. Needs the closing plan tuned for short blunt weapons.
2. **Dai-katana** (67%, 78 against the laser): cut, pierce and mass do not move it; it wins on reach and two-handed
   guard (9.9 hits taken a fight, fewest of all). Its cut cannot go lower than the longsword's (test_premium_weapons)
   and its length not under 1.2 m. Options: a slower two-handed recovery for the brain, or relax the premium test.
3. **Spear v mace 76**: the mace (shortest tier-3 weapon) cannot get inside the point; same closing-plan cause.

## Tables (after; "before" is main 654f700 on the same seeds)

fights=4800, side 0 won 49.6% of decided fights

| weapon | tier | win % | before | fights | mean len s | hits/fight | hits taken | dmg/hit | wins by |
|---|---|---|---|---|---|---|---|---|---|
| dai_katana | 5 | 67 | 69 | 600 | 23.1 | 13.8 | 9.9 | 4.6 | blood_loss 305, gut 43, behead 39, run_through 8 |
| longsword | 4 | 61 | 59 | 600 | 24.6 | 15.1 | 10.9 | 4.1 | blood_loss 265, gut 54, behead 28, time 11 |
| warhammer | 4 | 59 | 54 | 600 | 29.1 | 14.0 | 11.3 | 5.2 | ko 188, skull_crush 59, blood_loss 41, time 41 |
| spear | 3 | 58 | 67 | 600 | 38.1 | 20.2 | 8.2 | 1.8 | blood_loss 187, time 90, run_through 67, pummel 1 |
| laser_sword | 5 | 58 | 58 | 600 | 24.8 | 12.1 | 11.7 | 4.2 | blood_loss 255, gut 30, behead 28, time 18 |
| halberd | 4 | 55 | 57 | 600 | 25.8 | 13.8 | 11.2 | 4.1 | blood_loss 254, gut 24, time 21, behead 13 |
| falchion | 3 | 54 | 59 | 600 | 25.3 | 12.9 | 13.2 | 4.0 | blood_loss 235, gut 33, behead 24, time 16 |
| gladius | 2 | 53 | 53 | 600 | 25.3 | 12.4 | 14.1 | 3.7 | blood_loss 230, gut 26, time 22, behead 16 |
| sledgehammer | 1 | 52 | 51 | 600 | 28.0 | 13.1 | 13.5 | 4.8 | ko 194, skull_crush 65, time 33, pummel 13 |
| bat | 1 | 50 | 39 | 600 | 28.1 | 10.9 | 12.1 | 5.0 | ko 143, skull_crush 94, time 33, pummel 17 |
| axe | 3 | 49 | 49 | 600 | 25.1 | 11.8 | 14.3 | 4.4 | blood_loss 207, gut 28, behead 25, time 21 |
| mace | 3 | 47 | 49 | 600 | 29.1 | 10.4 | 12.7 | 5.1 | ko 136, skull_crush 85, time 38, pummel 15 |
| rake | 1 | 45 | 46 | 600 | 35.8 | 20.3 | 12.0 | 2.6 | ko 111, time 87, blood_loss 57, pummel 9 |
| machete | 1 | 44 | 43 | 600 | 25.2 | 10.7 | 13.7 | 3.7 | blood_loss 206, gut 16, time 14, behead 14 |
| club | 1 | 36 | 37 | 600 | 30.7 | 11.2 | 15.7 | 3.3 | ko 117, skull_crush 45, time 32, pummel 11 |
| fists | 0 | 12 | 11 | 600 | 27.8 | 6.8 | 24.9 | 8.2 | ko 42, pummel 22, time 7 |

| row vs col | fists | bat | club | machete | rake | sledge | gladius | axe | falchion | mace | spear | halberd | long | whammer | dai | laser |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fists (0) | - | 12 | 12 | 20 | 12 | 12 | 0 | 12 | 8 | 12 | 11 | 10 | 22 | 8 | 18 | 8 |
| bat (1) | 88 | - | **78** | 58 | 58 | 42 | 50 | 52 | 55 | 42 | 46 | 35 | 32 | 32 | 35 | 52 |
| club (1) | 88 | **22** | - | 48 | **28** | **30** | 38 | 50 | 40 | 39 | 18 | 39 | 28 | 20 | 25 | 32 |
| machete (1) | 80 | 42 | 52 | - | 55 | 45 | 50 | 45 | 40 | 35 | 48 | 32 | 38 | 38 | 25 | 32 |
| rake (1) | 88 | 42 | **72** | 45 | - | 48 | 35 | 45 | 55 | 68 | 36 | 30 | 20 | 42 | 19 | 28 |
| sledge (1) | 88 | 58 | **70** | 55 | 52 | - | 50 | 55 | 45 | 55 | 48 | 42 | 38 | 40 | 38 | 40 |
| gladius (2) | 100 | 50 | 62 | 50 | 65 | 50 | - | 60 | 38 | 60 | 52 | 50 | 50 | 35 | 35 | 38 |
| axe (3) | 88 | 48 | 50 | 55 | 55 | 45 | 40 | - | 42 | 45 | 44 | 65 | 32 | 58 | 38 | 38 |
| falchion (3) | 92 | 45 | 60 | 60 | 45 | 55 | 62 | 58 | - | 58 | 52 | 65 | 35 | 30 | 38 | 48 |
| mace (3) | 88 | 58 | 61 | 65 | 32 | 45 | 40 | 55 | 42 | - | **24** | 50 | 45 | 35 | 38 | 30 |
| spear (3) | 89 | 54 | 82 | 52 | 64 | 52 | 48 | 56 | 48 | **76** | - | 42 | 42 | 50 | 40 | 75 |
| halberd (4) | 90 | 65 | 61 | 68 | 70 | 58 | 50 | 35 | 35 | 50 | 58 | - | 40 | 52 | 45 | 42 |
| long (4) | 78 | 68 | 72 | 62 | 80 | 62 | 50 | 68 | 65 | 55 | 58 | 60 | - | 65 | 38 | 38 |
| whammer (4) | 92 | 68 | 80 | 62 | 58 | 60 | 65 | 42 | 70 | 65 | 50 | 48 | 35 | - | 40 | 52 |
| dai (5) | 82 | 65 | 75 | 75 | 81 | 62 | 65 | 62 | 62 | 62 | 60 | 55 | 62 | 60 | - | **78** |
| laser (5) | 92 | 48 | 68 | 68 | 72 | 60 | 62 | 62 | 52 | 70 | 25 | 58 | 62 | 48 | **22** | - |

Run files: before docs/balance_runs/654f700.json.gz, rounds d5234a9, 5d54b46, a6ba2fc, after docs/balance_runs/0816f76.json.gz. Per-pairing rows are in docs/balance_matrix.csv.

## Earlier rounds
Round 3 (before the round-4 AI) ended with one in-tier cell out (sledgehammer v bat 68/32); its data changes (dai,
laser, sledgehammer, club, machete, gladius, axe, halberd, rake, fists) are in git history (0ae1f59).
