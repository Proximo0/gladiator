# Balance: bat

Tool: `tools/bot_match.sh --matches=20 --shards=2 --hitlog`, 20 fights per side order (bat as side 0 with seed 5000, bat as side 1 with seed 6000), so each cell is 40 fights (noise about +-10 points). Hit counts and damage per hit come from the `hitlog` sums.

## Trace (before, bat blunt_factor 1.0)
- Bat vs longsword: 12/40 bat wins (30%). Bat lands 379 hits at 5.5 damage per hit; longsword lands 499 at 4.7-5.3. So damage per hit is not the gap: the longsword (length 1.05 vs 0.85) lands about 30% more hits.
- Mace lands 8.0 damage per hit against the bat's 5.2, with mace 16/40 for the bat (40%).
- The bat (mass 1.0, blunt 1.0) is the weakest tier-1 blunt weapon: club blunt 1.55, mace 1.65. Reach and AI were left alone (round 7 showed the longsword edge is reach and footwork, not the longsword stats; AI has no bat-specific branch).

## Change
`data/weapons.json` bat `blunt_factor` 1.0 to 1.2.

| Bat wins (of 40) | before (1.0) | 1.3 | 1.2 (kept) |
| --- | --- | --- | --- |
| vs longsword | 12 (30%) | 20 (50%) | 15 (38%) |
| vs mace | 16 (40%) | 17 (42%) | 16 (40%) |
| vs axe | 23 (57%) | 23 (57%) | 23 (57%) |

Bat damage per hit at 1.2 is about 5.1-6.4 (was 4.8-5.5). 1.3 sat on the top edge of the band against the longsword, so 1.2 was kept. Mace and axe cells did not move beyond noise, so the bat does not dominate.
