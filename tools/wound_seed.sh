#!/usr/bin/env bash
# Seed scan for the wound captures (tests/render/wound_look_capture.tscn): headless bot fights with the capture's
# loadouts, keeping the seeds whose fight is still on at the end of the window and has marked both fighters.
# Usage: tools/wound_seed.sh [--secs=18] [--from=1] [--count=24] [--min_hits=14] [--shards=2]
# Prints the keepers best first (most hits), then one summary line `WOUND_SEED kept=<n> best=<seed>`.
set -uo pipefail
cd "$(dirname "$0")/.."
secs=18; from=1; count=24; min_hits=14; shards=2
for a in "$@"; do
  case "$a" in
    --secs=*) secs="${a#*=}" ;;
    --from=*) from="${a#*=}" ;;
    --count=*) count="${a#*=}" ;;
    --min_hits=*) min_hits="${a#*=}" ;;
    --shards=*) shards="${a#*=}" ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
rm -f out/bot/*.json
tools/bot_match.sh --matches="$count" --seed="$from" --time_limit="$secs" --shards="$shards" --w0=gladius --w1=club \
    --a0=helm_leather --a1=cuirass_leather >/tmp/wound_seed_bot.log 2>&1
python3 - "$secs" "$min_hits" <<'P'
import glob, json, sys
secs, min_hits = int(sys.argv[1]), int(sys.argv[2])
rows = []
for f in glob.glob("out/bot/*.json"):
    d = json.load(open(f))
    r = d.get("result", {})
    s = r.get("stats", {})
    hb = s.get("hits_by_side", [0, 0])
    if r.get("reason") == "time" and r.get("fight_ticks", 0) >= secs * 60 and min(hb) >= 3 and s.get("hits", 0) >= min_hits:
        rows.append((s["hits"], r["seed"]))
rows.sort(reverse=True)
for hits, seed in rows:
    print("seed %d hits %d" % (seed, hits))
print("WOUND_SEED kept=%d best=%s" % (len(rows), rows[0][1] if rows else "none"))
sys.exit(0 if rows else 1)
P
