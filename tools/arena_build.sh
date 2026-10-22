#!/usr/bin/env bash
# Arena build time per step: tests/perf/arena_build.tscn in a real window (xvfb on a headless Linux box), each
# quality in a fresh process. Usage: tools/arena_build.sh [--quality=0|1|2|all] [--repeat=N] [--runs=N]
#   --runs  fresh processes per quality (default 3); the table shows the median of the first and of the later builds.
# Prints one row per quality and step, then one summary line.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
q=all; repeat=3; runs=3
for a in "$@"; do
  case "$a" in
    --quality=*) q="${a#*=}" ;;
    --repeat=*) repeat="${a#*=}" ;;
    --runs=*) runs="${a#*=}" ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
levels=("$q"); [[ "$q" == "all" ]] && levels=(0 1 2)
runner=()
if [[ -z "${DISPLAY:-}" && "$(uname)" == "Linux" ]]; then runner=(xvfb-run -a -s "-screen 0 640x360x24"); fi
log=$(mktemp -d)
rc=0
for l in "${levels[@]}"; do
  for r in $(seq 1 "$runs"); do
    timeout 300 "${runner[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution 640x360 \
        res://tests/perf/arena_build.tscn -- --quality="$l" --repeat="$repeat" >"$log/q${l}_r$r.log" 2>&1
    grep -q '^ARENA_BUILD {' "$log/q${l}_r$r.log" || { echo "ARENA_BUILD quality=$l run=$r FAIL (log $log/q${l}_r$r.log)"; rc=1; }
  done
done
python3 - "$log" <<'PY'
import json, os, re, statistics, sys
d = sys.argv[1]
rows = {}
for f in sorted(os.listdir(d)):
    q = int(re.match(r"q(\d)", f).group(1))
    for line in open(os.path.join(d, f)):
        if line.startswith("ARENA_BUILD {"):
            p = json.loads(line[len("ARENA_BUILD "):])
            rows.setdefault(q, {}).setdefault("first" if p["build"] == 0 else "later", []).append(p)
for q in sorted(rows):
    first, later = rows[q].get("first", []), rows[q].get("later", [])
    keys = [k for k in first[0] if k not in ("build", "quality")]
    print("quality %d  (median ms; first build n=%d, later builds n=%d)" % (q, len(first), len(later)))
    for k in keys:
        a = statistics.median(p.get(k, 0.0) for p in first)
        b = statistics.median(p.get(k, 0.0) for p in later) if later else float("nan")
        print("  %-22s %8.1f %8.1f" % (k, a, b))
PY
echo "ARENA_BUILD done levels=${#levels[@]} failed=$rc"
exit $rc
