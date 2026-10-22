# Balance round 6 (after the new gait and dodge roll)

Method: `tools/bot_match.sh --matches=10 --shards=1 --w0=<id> --w1=longsword` and the mirrored side, seeds 6000 (and 7000
for checks); 20 fights per weapon. Win % is the weapon's. n=20 has about +-20 points of noise; read results in bands.

| Weapon | Before | After | Change |
| --- | --- | --- | --- |
| fists | 0/20 | not retuned (joke weapon, never won: no bleeding) | none |
| rake | 25% | 25% | none |
| bat | 30% | 30% | none |
| club | 20% | 20-35% (25-30% mean, noise) | none (see below) |
| gladius | 5% | 30% (both seeds) | length 0.6 to 0.7, cut 0.9 to 1.0 |
| axe | 35% | 35% | none |
| spear | 45% | 45% | none |
| machete | 25% | 25% | none |
| sledgehammer | 30% | 35% | blunt 1.5 to 1.65 |
| mace | 30% | 45% | blunt 1.5 to 1.65 |
| falchion | 55% | 55% | none |
| warhammer | 30% | 30% | none |
| halberd | 45% | 45% | none |
| dai_katana | 55% | 65% (26/40) | cut 1.55 to 2.0 |
| laser_sword | 75% / 50% (two seeds) | not retuned | none |

Gait AI check: about 2 dodge rolls per fight (both fighters), 1.3 to 3.0 per weapon. With AI rolling switched off,
win rates and self hits did not improve (rake 20%, 7 self hits; club 25%, 9), so rolls are not the cause of the
rake/club self hits (pommel/butt clips). No stuck or exploding fights, no log errors beyond the missing EOS extension.

Club: raising blunt (1.3 to 1.5) lifted it to 35% but broke sim `fighter_heavy_hit` (more forearm damage, less
stagger) and the unit test "mace out-crushes a club"; raising mass also broke the sim. Club left unchanged.

Bot stats now count dodge rolls (`rolls`, both fighters) in `match_stats.gd` and the `bot_match.sh` table.
