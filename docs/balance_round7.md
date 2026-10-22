# Balance round 7

Method as round 6: `tools/bot_match.sh --matches=10 --shards=1 --seed=6000`, both sides, 20 fights per weapon. n=20 is about
+-15 points of noise, and a rerun after an unrelated data change moved gladius 5/20 to 6/20, so same-seed reruns are not exact.

Sanity check vs axe: rake 25, bat 40, club 30, spear 30, mace 60, falchion 75, sledgehammer 75; longsword 65. The field is
not uniformly weak. Against the longsword: mean of the starters/unlockables is 36%.

Vs longsword (before): rake 25, bat 30, club 20, gladius 25, axe 35, spear 45, machete 30, sledgehammer 35, mace 40,
falchion 55, warhammer 35, halberd 45, dai_katana 50, laser_sword 75 (shield_round 0, not a weapon).
Longsword experiments (club/bat/gladius/axe, dai): length 1.0: 25/30/10/25, dai 75. cut 0.8: 35/25/25/10, dai 70. cut 1.25: axe 25,
gladius 20. mass 1.1: 15/15/20/20. mass 1.8: 10/30/20/25. pierce 0.4: 20/25/30/25. balance 0.4: 40/30/15/20. A crippled sword
(cut 0.4, pierce 0.3): 25/35/45/30. No longsword stat moves the field beyond noise, so the longsword was left unchanged: its edge is
reach/footwork with the bot's half-sword thrusts, not damage numbers.

Club blunt 1.1 to 1.55: 20% to 45%. `fighter_heavy_hit` now also checks a fixed 8 m/s club torso blow on a fresh dummy.
Still out of band: bat 30, gladius 25-30, machete 30 (just under 35); dai_katana 50 (below 65-75; 75 only appeared with a shorter longsword).
Flaky `test_wear_weakens_strap`: club 8 m/s blow (51 J x blunt) sat next to the helm strap (70), so club blunt above about 1.37
flipped the "fresh" half; now 6.5 m/s.
