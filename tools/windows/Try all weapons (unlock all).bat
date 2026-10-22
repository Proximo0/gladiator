@echo off
rem Owner preview: every weapon unlocked (no matches needed) plus the free test shop for the Samurai and Alien outfits
rem (buying one there also unlocks its Dai-katana / Laser sword). Ranked Quick Match still uses only what you earned.
start "" "%~dp0Sandblood.exe" -- --store=local --unlock-all
