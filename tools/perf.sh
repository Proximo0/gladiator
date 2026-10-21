#!/usr/bin/env bash
# Performance report: a presented bot-vs-bot match (full arena, crowd, blood, sand FX) in a real window, measured at a
# late, bloody point. Usage: tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES]
#   --quality  graphics quality (0 low = Android, 1 medium, 2 high); `all` runs the three (default: 2)
# Linux without a display uses xvfb. Software GL makes GPU time meaningless there: read draw calls, primitives, CPU
# process/physics ms and peak counts. One godot process at a time. Prints one table row per run; exit 1 on a failed run.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
q=2; seed=1002; extra=()
for a in "$@"; do
  case "$a" in
    --quality=*) q="${a#*=}" ;;
    --seed=*) seed="${a#*=}" ;;
    --measure=*|--bloody=*|--max_ticks=*|--late_tick=*|--hide=*|--ff=*) extra+=("$a") ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
levels=("$q"); [[ "$q" == "all" ]] && levels=(0 1 2)
runner=()
if [[ -z "${DISPLAY:-}" && "$(uname)" == "Linux" ]]; then runner=(xvfb-run -a -s "-screen 0 320x180x24"); fi
rc=0
printf '%-4s %-16s %7s %7s %7s %7s %6s %9s %7s %7s %7s %7s\n' q reached proc_ms p95 phys_ms fx_ms calls prims decals drops grains mist
for l in "${levels[@]}"; do
  line=$(timeout 900 "${runner[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution 320x180 --fixed-fps 60 \
      --disable-vsync res://tests/perf/perf.tscn -- --seed="$seed" --quality="$l" "${extra[@]}" 2>&1 | tee /tmp/perf_$l.log | grep '^PERF {' | tail -1)
  if [[ -z "$line" ]]; then echo "PERF quality=$l FAIL no result line"; rc=1; continue; fi
  echo "${line#PERF }" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read()); pk = d["peak"]
print("%-4s %-16s %7.2f %7.2f %7.2f %7.2f %6.0f %9.0f %7d %7d %7d %7d" % (d["quality"], d["reached"], d["process_ms"]["mean"],
  d["process_ms"]["p95"], d["physics_ms"]["mean"], d["fx_ms"]["mean"], d["draw_calls"]["mean"], d["primitives"]["mean"], pk.get("decals", 0),
  pk.get("drops", 0), pk.get("grains", 0), pk.get("mist", 0)))
print("     fx sections ms: " + " ".join("%s=%.2f" % kv for kv in d["sections_ms"].items()))
print("     objects %.0f  nodes %d  vram %.1f MB  tick %d  wall %.1fs" % (d["objects"]["mean"], d["nodes"], d["video_mem_mb"], d["tick"], d["wall_s"]))
print("     crowd seats %d tris_in_buffers %d tris_drawn %d mm_calls %d" % (d["crowd"]["seats"], d["crowd"]["tris"], d["crowd"]["shown_tris"], d["crowd"]["calls"]))
print("     draw suspects: " + "; ".join(d["census"]))'
done
echo "PERF done runs=${#levels[@]} failed=$rc"
exit $rc
