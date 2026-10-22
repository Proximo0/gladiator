#!/usr/bin/env bash
# Sim isolation check: runs every sim file of the suite (sim_suite.tscn -- --list) alone (one process each), then the whole suite in
# one process, and compares each file's SIM rows. Usage: tools/sim_isolation.sh [sim_name ...]
# Prints the rows that differ, then "ISOLATION same=N differ=M files=T". Exit 1 if any file differs.
# Wall-clock numbers are masked before comparing (ms_per_tick, rtt, us/tick and us/frame costs, the audio voice-steal
# counts and pool use, which follow the audio clock). Physics results also shift when the box is busy (Jolt's contact order follows
# thread timing), so run it on an idle machine. SUITE_ARGS=--no-reset measures the suite without the per-file reset.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
if [[ $# -gt 0 ]]; then files=("$@"); else
  mapfile -t files < <("$GODOT" --headless --path . res://tests/sim/sim_suite.tscn -- --list 2>/dev/null | grep '^sim_')
fi
mask() {
  sed -E -e 's/ms_per_tick=[0-9.]+/ms_per_tick=#/g; s/rtt=[0-9]+ms/rtt=#ms/g; s/(stolen|mean_players)=[0-9.]+/\1=#/g' \
    -e 's/peak_use=\{[^}]*\}/peak_use=#/g' \
    -e '/us\/(tick|frame)/s/[0-9]+/#/g'
}
run() {  # run <out> <sim names...>
  local out=$1; shift
  timeout 900 "$GODOT" --headless --fixed-fps 60 --path . res://tests/sim/sim_suite.tscn -- "$@" ${SUITE_ARGS:-} 2>&1 | grep -E '^(SIM|SIMFILE) ' | mask > "$out"
}
for f in "${files[@]}"; do run "$dir/alone_$f" "$f"; done
run "$dir/suite" "${files[@]}"
same=0; differ=0
for f in "${files[@]}"; do
  # the suite's rows for file f: the lines after its SIMFILE header, up to the next header
  awk -v f="$f" '/^SIMFILE /{on = ($2 == f); next} on' "$dir/suite" > "$dir/suite_$f"
  grep -v '^SIMFILE ' "$dir/alone_$f" > "$dir/alone_rows_$f"
  if cmp -s "$dir/alone_rows_$f" "$dir/suite_$f"; then same=$((same + 1)); else
    differ=$((differ + 1))
    echo "DIFF $f (< alone, > in the suite)"
    diff "$dir/alone_rows_$f" "$dir/suite_$f" | grep '^[<>]' | cut -c1-220
  fi
done
echo "ISOLATION same=$same differ=$differ files=${#files[@]}"
(( differ > 0 )) && exit 1
exit 0
