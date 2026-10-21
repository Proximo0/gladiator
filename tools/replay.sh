#!/usr/bin/env bash
# Replay a flight recording from tick 0 with the recorded inputs and compare it with the original.
# Usage: tools/replay.sh <recording.json> [--tune=preset.json] [--render]
#   --tune=preset.json  what-if: a Tuning preset ({field: value}) applied on top of the recorded tuning
#   --render            arena visuals under xvfb (software GL: about 0.8 s per tick on this box), PNG frames in out/replay/<seed>/
#                       (--render_every=<ticks>, default 30)
# Prints `REPLAY ticks=N divergence=<m> result_match=yes|no ...`. Exit 1 when an untuned replay diverges.
set -uo pipefail
GODOT="${GODOT:-godot}"
file=""; extra=(); render=0
for a in "$@"; do
  case "$a" in
    --tune=*) extra+=("--tune=$(realpath "${a#--tune=}")") ;;
    --render) render=1; extra+=("--render") ;;
    --render_every=*) extra+=("$a") ;;
    --*) extra+=("$a") ;;
    *) file="$(realpath "$a")" ;;
  esac
done
[[ -f "$file" ]] || { echo "usage: tools/replay.sh <recording.json> [--tune=preset.json] [--render]"; exit 2; }
cd "$(dirname "$0")/.."
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
FILTER='^(Godot Engine v|$|WARNING: .*audio|   at: )'
if (( render )); then
  timeout 3000 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 \
    --fixed-fps 60 res://tests/replay/replay.tscn -- --scripted "--file=$file" "${extra[@]}" 2>&1 | grep -vE "$FILTER"
else
  timeout 600 "$GODOT" --headless --fixed-fps 60 --path . res://tests/replay/replay.tscn -- "--file=$file" "${extra[@]}" 2>&1 | grep -vE "$FILTER"
fi
exit "${PIPESTATUS[0]}"
