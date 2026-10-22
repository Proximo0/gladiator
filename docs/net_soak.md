# Online soak (2026-10-22)

`tools/net_soak.sh [--matches=N] [--time_limit=S] [--profiles="60:0.02 150:0.03 250:0.05"] [--no-drill]` runs bot-vs-bot host and
client over real ENet on 127.0.0.1 in one headless process per profile, with `NetLinkSim` (latency, jitter, loss both ways).
Logs go to `out/net_soak/<rtt>ms.log`; the tool prints a table per profile and `NET_SOAK profiles=<n> problems=<n>`.
`tests/sim/sim_net_soak.gd` does the measuring; `tests/sim/sim_net_drop.gd` (in the sim suite) covers leave, vanish, stall and
the protocol 1 vs 2 refusal.

## Results (3 matches per profile, protocol 2, roll bit 256)

| | 60 ms / 2% | 150 ms / 3% | 250 ms / 5% |
| --- | --- | --- | --- |
| snapshots received | 29.4 Hz (worst 1-s window 27/30) | 29.0 (26) | 28.5 (24) |
| interp delay / extrapolated run | 45 ms / 3 ticks | 45 ms / 3 | 55 ms / 3 |
| resyncs | 0 | 0 | 0 |
| pelvis err mean / p95 / max | 1.8 / 4.5 / 10 cm | 1.8 / 4.2 / 9 | 1.8 / 4.7 / 9 |
| hand err | 3.0 / 6.6 / 18 | 3.3 / 7.2 / 17 | 3.1 / 7.0 / 16 |
| weapon tip err | 5.9 / 15.8 / 39 | 7.0 / 17.5 / 55 | 6.1 / 17.0 / 55 |
| input to screen | 139 ms | 239 ms | 375 ms |
| rolls play on client | yes, pelvis err max 10 cm | yes, 9 cm | yes, 9 cm |
| gore events host/client | all equal | all equal | all equal |
| largest snapshot / events / input | 522 / 331 / 46 B | 522 / 250 / 46 | 522 / 449 / 46 (budget 1100) |
| bandwidth host->client avg / peak | 16.6 / 18.7 KB/s | 16.5 / 18.5 | 16.1 / 18.5 |
| bandwidth client->host | 5.3 KB/s | 5.2 | 5.1 |
| same result both ends | 4/4 | 4/4 | 4/4 |

`zemitted` and `zspurts_peak` are particle counters, not events; they differ by design (particles are local) and are ignored.

## Defects found and fixed

1. A press-once button (roll, grab) on a client tick the host skipped (lost for good, late, or dropped when the buffer shrinks)
   never played. `NetInputBuffer` now carries those bits onto the next tick played (`carried`).
2. With the client's packets gone, the host kept repeating the last input forever (fighter 1 kept walking and swinging for the
   5 s until "Connection lost"). After `NetConfig.INPUT_STALE_TICKS` (12) quiet pops, movement and buttons go neutral, the aim stays.

## Next net defects

1. Input to screen is RTT plus 78 ms (host buffer + interpolation + 2-tick snapshot cadence); a client-side predicted own roll/dodge would hide it.
2. Weapon-tip error peaks at 55 cm under 3-5% loss (extrapolation of a fast swing across two missed snapshots); snapshot hand/tip velocity hints or a 3-tick cadence on swings would cut it.
3. Particle effects (blood) are local and not covered by any parity check; a visual desync of gore volume is possible and untested.
