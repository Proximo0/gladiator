#!/usr/bin/env bash
# Clean gameplay clip: a bot-vs-bot presented match with the player's aim aid and prompts off, rendered with --write-movie.
# Usage: tools/record_fight.sh [--seed=S] [--scan=N] [--min=SECONDS] [--max=SECONDS] [--tail=SECONDS] [--quality=0|1|2]
#                              [--name=NAME] [--shards=K] [--render_seed=S]
#   --seed/--scan   scan N seeds from S (headless, fast) for a fight that ends in a kill with a finisher (default 1000, 60)
#   --min/--max     the fight must last this many game seconds (default 14 to 40; the longest one wins; the clip adds --tail)
#   --tail          seconds rolling after the kill, for the finale and the banner (default 8)
#   --quality       graphics quality of the render (default 1)
#   --name          output base name in out/video/ (default fight_<seed>)
#   --shards        parallel Godot processes for the scan (default 2)
#   --render_seed   skip the scan and render this seed
# The scan runs the presented match headless (about 3x real time), so --scan seeds cost seconds each.
# Writes out/video/NAME_1080p60.mp4 (1280x720, 60 fps, H.264 yuv420p + AAC, faststart) and NAME_720p30.mp4 (under 15 MB).
# The render itself runs near 2 fps on a 4-core cloud box: run this as a tracked background job. Prints one line per step.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
seed=1000; scan=60; min=14; max=40; tail=8; q=1; name=""; shards=2; rseed=""
for a in "$@"; do
  case "$a" in
    --seed=*) seed="${a#*=}" ;;
    --scan=*) scan="${a#*=}" ;;
    --min=*) min="${a#*=}" ;;
    --max=*) max="${a#*=}" ;;
    --tail=*) tail="${a#*=}" ;;
    --quality=*) q="${a#*=}" ;;
    --name=*) name="${a#*=}" ;;
    --shards=*) shards="${a#*=}" ;;
    --render_seed=*) rseed="${a#*=}"; render_seed_given=1 ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
command -v ffmpeg >/dev/null || { echo "record_fight: ffmpeg not found"; exit 1; }
mkdir -p out/video
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }

# The presented match is not bit-exact from run to run (one run in six drifts around tick 1200), so a scan result is only
# a candidate: each is run headless twice more and must repeat the same ending, and a render that misses the kill is retried.
scan_one() {  # seed -> the CAPTURE result line (a hang is a line with reason=hang)
  timeout 300 "$GODOT" --headless --fixed-fps 60 --path . res://tests/capture/capture.tscn -- --seed="$1" --scan \
      --max_ticks=$((max * 60 + 600)) 2>&1 | grep '^CAPTURE result' || echo "CAPTURE result seed=$1 reason=hang"
}
export -f scan_one 2>/dev/null
if [[ -n "$rseed" ]]; then
  cands=("$rseed")
  echo "[1/4] scan skipped, seed $rseed"
else
  echo "[1/4] scan: $scan seeds from $seed for a kill with a finisher lasting $min to $max s"
  : >/tmp/record_scan.log
  for ((i = 0; i < scan; i++)); do
    echo $((seed + i))
  done | xargs -P "$shards" -I{} sh -c "timeout 300 '$GODOT' --headless --fixed-fps 60 --path . res://tests/capture/capture.tscn -- --seed={} --scan --max_ticks=$((max * 60 + 600)) 2>&1 | grep '^CAPTURE result' || echo 'CAPTURE result seed={} reason=hang'" >/tmp/record_scan.log
  mapfile -t cands < <(python3 - "$min" "$max" /tmp/record_scan.log <<'PY'
import re, sys
lo, hi = float(sys.argv[1]), float(sys.argv[2])
found = []
for line in open(sys.argv[3]):
    m = re.search(r"seed=(\d+) winner=\S+ reason=(\w+) finisher=(\w*) ticks=\d+ fight_s=([\d.]+)", line)
    if m and m.group(2) != "time" and m.group(3) and lo <= float(m.group(4)) <= hi:
        found.append((float(m.group(4)), int(m.group(1))))
for secs, s in sorted(found, reverse=True):
    print(s)
PY
)
  (( ${#cands[@]} > 0 )) || { echo "[1/4] no seed in $seed..$((seed + scan - 1)) ends in a finisher between $min and $max s; widen --scan or --min/--max"; exit 1; }
  echo "[1/4] ${#cands[@]} candidates, longest fight first: ${cands[*]:0:6}"
fi

runner=()
if [[ -z "${DISPLAY:-}" && "$(uname)" == "Linux" ]]; then runner=(xvfb-run -a -s "-screen 0 1280x720x24"); fi
rseed=""
tried=0
for c in "${cands[@]}"; do
  (( tried >= 3 )) && break
  if [[ -z "${render_seed_given:-}" ]]; then
    ref=$(grep "seed=$c " /tmp/record_scan.log | head -1 | sed 's/.*reason=/reason=/')
    ok=1
    for r in 1 2; do
      [[ "$(scan_one "$c" | sed 's/.*reason=/reason=/')" == "$ref" ]] || { ok=0; break; }
    done
    (( ok )) || { echo "[1/4] seed $c is not repeatable headless, next"; continue; }
  fi
  tried=$((tried + 1))
  name_c="${name:-fight_$c}"
  avi="out/video/$name_c.avi"
  echo "[2/4] render: seed $c at 1280x720, 60 fps, quality $q (about 2 fps on a 4-core box)"
  rm -f "$avi"
  "${runner[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --disable-vsync \
      --write-movie "$avi" res://tests/capture/capture.tscn -- --seed="$c" --quality="$q" --tail="$tail" >/tmp/record_render.log 2>&1
  grep '^CAPTURE' /tmp/record_render.log
  if [[ -s "$avi" ]] && grep -q 'CAPTURE result.*finisher=[a-z_]' /tmp/record_render.log && grep -q 'CAPTURE done' /tmp/record_render.log; then
    rseed="$c"; break
  fi
  echo "[2/4] seed $c did not end in a finisher in the render, next"
  rm -f "$avi"
done
[[ -n "$rseed" ]] || { echo "[2/4] no candidate rendered a finisher"; tail -5 /tmp/record_render.log; exit 1; }
name="${name:-fight_$rseed}"
avi="out/video/$name.avi"; full="out/video/${name}_1080p60.mp4"; small="out/video/${name}_720p30.mp4"
echo "[3/4] encode: H.264 yuv420p + AAC, faststart"
ffmpeg -v error -y -i "$avi" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 60 -c:a aac -b:a 160k -movflags +faststart "$full" || exit 1
echo "[4/4] 720p30 copy under 15 MB"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$full")
# Video bitrate from the size budget (14 MB total, 128 kb/s audio), one retry at 80% if it still comes out over 15 MB.
vb=$(python3 -c "print(int((14*8*1024 - 128*$dur) / $dur))")
for attempt in 1 2; do
  ffmpeg -v error -y -i "$full" -vf scale=1280:720,fps=30 -c:v libx264 -preset slow -b:v "${vb}k" -maxrate "$((vb * 3 / 2))k" -bufsize "$((vb * 2))k" \
      -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$small" || exit 1
  (( $(stat -c %s "$small") < 15000000 )) && break
  vb=$((vb * 8 / 10))
done
rm -f "$avi"
echo "OUT $full ($(du -h "$full" | cut -f1)) $small ($(du -h "$small" | cut -f1)) duration ${dur}s seed $rseed"
