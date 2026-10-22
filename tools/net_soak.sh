#!/usr/bin/env bash
# Online soak: host and client (bot on both ends) over real ENet on 127.0.0.1 in one headless Godot process, with a fake
# link (latency, jitter, loss) both ways. One process per profile, run one after the other.
# Usage: tools/net_soak.sh [--matches=N] [--time_limit=S] [--profiles="60:0.02 150:0.03 250:0.05"] [--no-drill]
#   a profile is rtt_ms:loss. Prints the per-match SOAK lines to out/net_soak/<rtt>.log and a table per profile.
# Quiet: errors, then the table and one "NET_SOAK profiles=<n> problems=<n>" line. See docs/net_soak.md.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
matches=4; limit=40; profiles="60:0.02 150:0.03 250:0.05"; drill=1
for a in "$@"; do
  case "$a" in
    --matches=*) matches="${a#*=}" ;;
    --time_limit=*) limit="${a#*=}" ;;
    --profiles=*) profiles="${a#*=}" ;;
    --no-drill) drill=0 ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
mkdir -p out/net_soak
n=0; problems=0
for p in $profiles; do
  rtt=${p%%:*}; loss=${p##*:}; n=$((n + 1))
  log="out/net_soak/${rtt}ms.log"
  timeout 1500 "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/sim/sim_net_solo.gd -- sim_net_soak "$rtt" "$loss" "$matches" "$limit" 2>&1 | grep -E '^(SOAK|SCRIPT ERROR|ERROR: [^C])' | grep -v 'GDExtension\|Error loading' >"$log"
  if (( drill )); then
    timeout 600 "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/sim/sim_net_solo.gd -- sim_net_soak "$rtt" "$loss" 1 14 drill 2>&1 | grep -E '^(SOAK|SCRIPT ERROR|ERROR: [^C])' | grep -v 'GDExtension\|Error loading' | sed 's/^SOAK match=0/SOAK drill/' >>"$log"
  fi
  python3 - "$log" "$rtt" "$loss" <<'PY' || problems=$((problems + 1))
import re, sys
log, rtt, loss = sys.argv[1], sys.argv[2], sys.argv[3]
rows = open(log).read().splitlines()
bad = [r for r in rows if (r.startswith(("SCRIPT", "ERROR")) or "FAILED" in r) and "still in use at exit" not in r]
def vals(pat, cast=float, lines=None):
    return [cast(m.group(1)) for r in (lines or rows) if r.startswith("SOAK match=") and (m := re.search(pat, r))]
def mean(v): return sum(v) / len(v) if v else 0.0
def mx(v): return max(v) if v else 0.0
print(f"== {rtt} ms RTT, {float(loss)*100:.0f}% loss each way ({len(vals(r'secs=([\d.]+)'))} matches, {sum(vals(r'secs=([\d.]+)')):.0f} s) ==")
print(f"  snapshot rate received  mean {mean(vals(r'rate_hz=([\d.]+)')):.1f} Hz, worst 1-s window {min(vals(r'min_window=(\d+)', int) or [0])} of 30")
print(f"  interp delay            mean {mean(vals(r'interp_delay_ms=([\d.]+)')):.0f} ms; extrapolated ticks/match mean {mean(vals(r'extrap_ticks=(\d+)')):.0f}, longest run {mx(vals(r'extrap_max_run=(\d+)')):.0f} ticks; resyncs {sum(vals(r'resyncs=(\d+)', int))}")
for q, label in (("pelvis", "pelvis"), ("hand", "hand"), ("tip", "weapon tip")):
    m = vals(rf"{q} mean=([\d.]+)"); p = vals(rf"{q} mean=[\d.]+ p95=([\d.]+)"); x = vals(rf"{q} mean=[\d.]+ p95=[\d.]+ max=([\d.]+)")
    print(f"  {label:<10} err vs host   mean {mean(m)*100:.1f} cm, p95 {mean(p)*100:.1f} cm, max {mx(x)*100:.0f} cm")
print(f"  apparent lag (pelvis, client now vs host now) mean {mean(vals(r'pelvis_vs_host_now mean=([\d.]+)'))*100:.0f} cm")
it = vals(r"input_to_screen_ticks=([\d.]+)")
print(f"  input to screen         mean {mean(it)*1000/60:.0f} ms ({mean(it):.1f} ticks)")
print(f"  rolls host side0/side1 {sum(vals(r'host_side0=(\d+)', int))}/{sum(vals(r'host_side1=(\d+)', int))}, client presses {sum(vals(r'client_presses=(\d+)', int))}, carried presses {sum(vals(r'carried_presses=(\d+)', int))}, roll pelvis err max {mx(vals(r'roll_pelvis_err_mean=[\d.]+ max=([\d.]+)'))*100:.0f} cm")
ev = [r for r in rows if " events (host" in r]
tot = {}
for r in ev:
    for k, a, b in re.findall(r"(\w+)=(\d+)/(\d+)", r.split("played)")[1]):
        t = tot.setdefault(k, [0, 0]); t[0] += int(a); t[1] += int(b)
print("  events host/client      " + " ".join(f"{k}={a}/{b}" for k, (a, b) in sorted(tot.items())))
mism = [k for k, (a, b) in tot.items() if a != b and not k.startswith("z")]  # z* are particle counters, not events
print(f"  largest packets         snap {mx(vals(r'max_snap=(\d+)', int)):.0f} B, events {mx(vals(r'max_events=(\d+)', int)):.0f} B, input {mx(vals(r'client max_input=(\d+)', int)):.0f} B (budget 1100)")
print(f"  bandwidth               host->client avg {mean(vals(r'host_out_avg=([\d.]+)')):.1f} KB/s peak {mx(vals(r'host_out_avg=[\d.]+KB/s peak=([\d.]+)')):.1f}; client->host avg {mean(vals(r'client_out_avg=([\d.]+)')):.1f} KB/s peak {mx(vals(r'client_out_avg=[\d.]+KB/s peak=([\d.]+)')):.1f}")
same = [r for r in rows if "same_result=" in r]
print(f"  same result host/client {sum('same_result=true' in r for r in same)}/{len(same)}")
dr = [r for r in rows if r.startswith("SOAK drill")]
for r in dr:
    if " events (host" in r or " stumps " in r:
        print("  drill " + r.split("drill ", 1)[1][:200])
problems = len(bad) + len(mism) + sum('same_result=true' not in r for r in same)
for r in bad: print("  PROBLEM " + r[:200])
for k in mism: print(f"  PROBLEM event kind {k} differs host/client")
sys.exit(1 if problems else 0)
PY
done
echo "NET_SOAK profiles=$n problems=$problems"
(( problems > 0 )) && exit 1
exit 0
