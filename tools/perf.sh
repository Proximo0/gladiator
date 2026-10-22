#!/usr/bin/env bash
# Performance report: a presented bot-vs-bot match (full arena, crowd, blood, sand FX) in a real window, measured at a
# late, bloody point. Usage: tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES]
#   --quality  graphics quality (0 low = Android, 1 medium, 2 high); `all` runs the three (default: 2)
#   --start    match-start and first-gore hitches over 3 loop starts (with --no_warm / --no_prebuild for A/B)
#   --sweep    after the window, 30 frames with each part hidden in turn (render cost per part)
#   --res=WxH  window size (default 320x180; 1920x1080 shows fill cost in render gpu, slow under software GL)
# Linux without a display uses xvfb. Software GL makes GPU time meaningless there: read draw calls, primitives, CPU
# process/physics ms and peak counts. One godot process at a time. Prints one table row per run; exit 1 on a failed run.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
q=2; seed=1002; res=320x180; extra=()
for a in "$@"; do
  case "$a" in
    --quality=*) q="${a#*=}" ;;
    --seed=*) seed="${a#*=}" ;;
    --res=*) res="${a#*=}" ;;
    --measure=*|--warmup=*|--no_prebuild|--no_warm|--legacy|--start|--bloody=*|--max_ticks=*|--late_tick=*|--hide=*|--ff=*|--heavy|--sweep) extra+=("$a") ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
levels=("$q"); [[ "$q" == "all" ]] && levels=(0 1 2)
runner=()
if [[ -z "${DISPLAY:-}" && "$(uname)" == "Linux" ]]; then runner=(xvfb-run -a -s "-screen 0 ${res}x24"); fi
rc=0
printf '%-4s %-16s %8s %8s %8s %8s %7s %7s %6s %7s %7s %7s %7s\n' q reached frame_ms p50 p95 max phys_ms fx_ms calls decals drops grains mist
for l in "${levels[@]}"; do
  if [[ " ${extra[*]} " == *" --start "* ]]; then
    line=$(timeout 900 "${runner[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution "$res" --fixed-fps 60 \
        --disable-vsync res://tests/perf/perf.tscn -- --seed="$seed" --quality="$l" "${extra[@]}" 2>&1 | tee /tmp/perf_$l.log | grep '^PERF_START {' | tail -1)
    if [[ -z "$line" ]]; then echo "PERF quality=$l FAIL no start line"; rc=1; continue; fi
    echo "${line#PERF_START }" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for i, s in enumerate(d["starts"]):
  print("%-4s start%d legacy=%d warm=%d prebuild=%d setup_ms=%.1f first10 max=%.1f sum=%.1f steady_p50=%.1f gore script=%.1f gore10 max=%.1f" % (d["quality"], i + 1, d["legacy"], d["warm"], d["prebuild"],
    s["setup_ms"], s["first10_max"], s["first10_sum"], s["steady_p50"], s["gore_script_ms"], s["gore10_max"]))
  print("       first10: %s | gore10: %s" % (" ".join("%.0f" % x for x in s["first10"]), " ".join("%.0f" % x for x in s["gore10"])))'
    continue
  fi
  line=$(timeout 900 "${runner[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution "$res" --fixed-fps 60 \
      --disable-vsync res://tests/perf/perf.tscn -- --seed="$seed" --quality="$l" "${extra[@]}" 2>&1 | tee /tmp/perf_$l.log | grep '^PERF {' | tail -1)
  if [[ -z "$line" ]]; then echo "PERF quality=$l FAIL no result line"; rc=1; continue; fi
  echo "${line#PERF }" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read()); pk = d["peak"]; fr = d["frame_ms"]
print("%-4s %-16s %8.2f %8.2f %8.2f %8.2f %7.2f %7.2f %6.0f %7d %7d %7d %7d" % (d["quality"], d["reached"], fr["mean"], fr["p50"], fr["p95"],
  fr["max"], d["physics_ms"]["mean"], d["fx_ms"]["mean"], d["draw_calls"]["mean"], pk.get("decals", 0), pk.get("drops", 0), pk.get("grains", 0), pk.get("mist", 0)))
print("     fx sections ms: " + " ".join("%s=%.2f" % kv for kv in d["sections_ms"].items()))
sm = d.get("script_ms", {})
print("     frame ms (real, mean): wall=%.2f = phys %.2f (scripts %.2f, jolt %.2f) + process scripts %.2f + render/swap/sync %.2f; render cpu=%.2f gpu=%.2f" % (sm.get("frame_wall", 0),
  d["physics_ms"]["mean"], sm.get("phys_match_etc", 0) + sm.get("phys_sfx", 0) + sm.get("phys_fighters", 0), sm.get("jolt", 0), sm.get("proc_script", 0), sm.get("render_etc", 0),
  sm.get("render_cpu", 0), sm.get("render_gpu", 0)))
ph = d["physics_ms"]
print("     physics ms per frame (real): mean %.2f p50 %.2f p95 %.2f max %.2f, steps/frame %.2f" % (ph["mean"], ph["p50"], ph["p95"], ph["max"], sm.get("phys_steps_n", 0)))
sp = d.get("spawn", {})
if sp:
  print("     gore spawn: sever %.2f ms, on_gore %.2f ms (script); next frames wall ms: %s" % (sp.get("sever_ms", 0), sp.get("on_gore_ms", 0), " ".join("%.1f" % x for x in sp.get("wall_ms", []))))
skip = {"frame_wall", "render_etc", "render_cpu", "render_gpu"}
print("     script sections ms: " + " ".join("%s=%.2f" % kv for kv in sorted(((k, v) for k, v in sm.items() if k not in skip), key=lambda kv: -kv[1])))
print("     monitors mean/peak: " + " ".join("%s=%.0f/%.0f" % (k, v[0], v[1]) for k, v in d.get("monitors", {}).items()))
print("     objects %.0f  nodes %d  vram %.1f MB  tick %d  wall %.1fs" % (d["objects"]["mean"], d["nodes"], d["video_mem_mb"], d["tick"], d["wall_s"]))
print("     crowd seats %d tris_in_buffers %d tris_drawn %d mm_calls %d" % (d["crowd"]["seats"], d["crowd"]["tris"], d["crowd"]["shown_tris"], d["crowd"]["calls"]))
print("     live_drops %d  mm_tris total %d: %s" % (d["live_drops"], d["mm_tris"].get("_total", 0), " ".join("%s=%d/%dx%d" % (k, v[2], v[0], v[1]) for k, v in d["mm_tris"].items() if k != "_total")))
print("     draw suspects: " + "; ".join(d["census"]))
for k, v in d.get("sweep", {}).items():
  print("     sweep hide=%-9s frame=%8.2f render_cpu=%8.2f render_gpu=%8.2f calls=%5.0f" % (k, v["proc"], v["render_cpu"], v["render_gpu"], v["calls"]))'
done
echo "PERF done runs=${#levels[@]} failed=$rc"
exit $rc
