@echo off
rem Second EOS identity on this PC: run after starting Sandblood.exe (docs/eos_setup.md, section 5).
start "" "%~dp0Sandblood.exe" -- --eos-profile=p2
