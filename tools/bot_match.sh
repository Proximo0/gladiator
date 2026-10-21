#!/usr/bin/env bash
# Seeded headless bot vs bot matches with an aggregate table.
# Usage: tools/bot_match.sh [--matches=N] [--seed=S] [--time_limit=SECONDS] [--shards=K] [--keep]
#   --matches     total matches (default 6), seeds S .. S+N-1 (default S = 1000)
#   --time_limit  game seconds per match (default 60)
#   --shards      parallel Godot processes (default 1, keep it at 2 or less on a small box)
#   --keep        also save the flight recording of passing matches (out/bot/<seed>.rec.json)
# Quiet: failing match lines, then the table. Per-match stats: out/bot/<seed>.json; every FAIL also writes
# out/bot/<seed>.rec.json (replay it with tools/replay.sh). Exit 1 when any match fails.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
matches=6; seed=1000; limit=60; shards=1; keep=()
for a in "$@"; do
  case "$a" in
    --matches=*) matches="${a#*=}" ;;
    --seed=*) seed="${a#*=}" ;;
    --time_limit=*) limit="${a#*=}" ;;
    --shards=*) shards="${a#*=}" ;;
    --keep) keep=(--keep) ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
(( shards < 1 )) && shards=1
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
FILTER='^(Godot Engine v|$|WARNING: .*audio|   at: )'
log=$(mktemp -d)
pids=()
for ((i = 0; i < shards; i++)); do
  n=$(( matches / shards + (i < matches % shards ? 1 : 0) ))
  (( n == 0 )) && continue
  ( timeout 1700 "$GODOT" --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --shard=$i --nshards=$shards \
      --matches=$n --seed=$seed --time_limit=$limit "${keep[@]}" 2>&1 | grep -vE "$FILTER" >"$log/shard$i.log"
    echo "${PIPESTATUS[0]}" >"$log/shard$i.rc" ) &
  pids+=($!)
done
wait "${pids[@]}"
python3 - "$log" "$PWD/out/bot" <<'PY'
import glob, json, os, re, sys
from collections import Counter
log, out = sys.argv[1], sys.argv[2]
rows, bad, other = [], 0, []
for f in sorted(glob.glob(os.path.join(log, "shard*.log"))):
    for line in open(f):
        line = line.rstrip("\n")
        m = re.match(r"BOT match seed=(\d+) winner=(-?\d+) reason=(\w+) ticks=(\d+) hits=(\d+) stuck_s=([\d.]+) "
                     r"explosions=(\d+) ms_per_tick=([\d.]+) (PASS|FAIL)", line)
        if m:
            rows.append(m.groups())
            if m.group(9) == "FAIL":
                bad += 1
                print(line)
        elif line.startswith("BOT why") or line.startswith("BOT recording"):
            print(line)
        elif not line.startswith("BOT score="):
            other.append(line)
for line in other[:20]:
    print(line)
for f in glob.glob(os.path.join(log, "shard*.rc")):
    if open(f).read().strip() not in ("0", "1"):
        bad += 1
        print("BOT shard crashed: %s" % os.path.basename(f))
n = len(rows)
if n == 0:
    print("BOT score=0.00 matches=0 (no matches ran)")
    sys.exit(1)
stats = []
for r in rows:
    try:
        stats.append(json.load(open(os.path.join(out, r[0] + ".json"))).get("stats") or {})
    except Exception:
        stats.append({})
ticks = sum(int(r[3]) for r in rows)
mins = ticks / 3600.0
hits = sum(int(r[4]) for r in rows)
reasons = Counter(r[2] for r in rows)
winners = Counter({"-1": "draw", "0": "side 0", "1": "side 1"}[r[1]] for r in rows)
fin = Counter(s.get("finisher") or "none" for s in stats)
def tot(k):
    return sum(int(s.get(k, 0)) for s in stats)
wall = sum(float(r[7]) * int(r[3]) for r in rows) / max(ticks, 1)
passed = n - sum(1 for r in rows if r[8] == "FAIL")
print("bot matches: %d  passed: %d  failed: %d" % (n, passed, n - passed))
print("  outcomes (reason)    %s" % ", ".join("%s %d" % kv for kv in sorted(reasons.items())))
print("  outcomes (winner)    %s" % ", ".join("%s %d" % kv for kv in sorted(winners.items())))
print("  mean match length    %.1f s" % (ticks / 60.0 / n))
print("  hits per minute      %.1f" % (hits / mins if mins > 0 else 0.0))
print("  finisher kinds       %s" % ", ".join("%s %d" % kv for kv in sorted(fin.items())))
print("  disarms %d  armor off %d  self hits %d  knockdowns %d  severs %d" % (
    tot("disarms"), tot("armor_dislodged"), tot("self_hits"), tot("knockdowns"), tot("severs")))
print("  max tip speed        %.1f m/s" % max([float(s.get("max_tip_speed", 0.0)) for s in stats] + [0.0]))
print("  stuck_s total %.1f  explosions %d" % (sum(float(s.get("stuck_s", 0.0)) for s in stats), tot("explosions")))
print("  ms per tick          %.2f" % wall)
print("BOT score=%.2f matches=%d failed=%d hits=%d ms_per_tick=%.2f" % (passed / n, n, n - passed, hits, wall))
sys.exit(1 if bad else 0)
PY
rc=$?
rm -rf "$log"
exit $rc
