#!/usr/bin/env python3
"""Weapon balance round-robin on headless bot fights.

Usage:
  tools/balance_matrix.py run [--fights=N] [--jobs=K] [--seed=S] [--only=a,b,...] [--vs=a,b,...] [--shard=i --nshards=n] [--out=FILE]
  tools/balance_matrix.py report FILE [FILE ...] [--md=docs/balance_matrix.md] [--csv=docs/balance_matrix.csv]

run: every unordered weapon pair from data/weapons.json fights N times with each weapon on side 0 and N times on
side 1 (2N per cell). Both orientations of a pair reuse the same seeds, so the seed-rolled armor and personalities
swap sides and cancel out. Seeds are fixed per pair: S + pair_index * 100 + k. --only limits the matrix to pairs
inside that list; --vs limits it to pairs with at least one weapon in that list; --shard/--nshards take every
n-th pair (CI fan-out, .github/workflows/balance.yml). Records go to out/balance/*.json.
report: merges run files (a later file replaces earlier records for the same pair) and writes the tables.
Quiet: failing fights and one summary line.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "godot")
TIME_LIMIT = 60


def weapon_table():
    with open(os.path.join(ROOT, "data", "weapons.json")) as f:
        return json.load(f)["weapons"]


def weapon_ids():
    return [w["id"] for w in weapon_table()]


def all_pairs(ids):
    out = []
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            out.append((ids[i], ids[j]))
    return out


def parse_args(argv):
    opts, pos = {}, []
    for a in argv:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            opts[k] = v
        else:
            pos.append(a)
    return opts, pos


def run_side(w0, w1, seed, n, outdir):
    """Run n fights with w0 on side 0; returns parsed records (seed order)."""
    cmd = [GODOT, "--headless", "--fixed-fps", "60", "--path", ROOT, "res://tests/bot/bot.tscn", "--",
        "--shard=0", "--nshards=1", "--matches=%d" % n, "--seed=%d" % seed, "--time_limit=%d" % TIME_LIMIT,
        "--w0=" + w0, "--w1=" + w1, "--hitlog"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
        log = p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        log = "TIMEOUT"
    recs = []
    for k in range(n):
        s = seed + k
        path = os.path.join(ROOT, "out", "bot", "%d.json" % s)
        try:
            with open(path) as f:
                d = json.load(f)
        except (OSError, ValueError):
            recs.append({"seed": s, "w0": w0, "w1": w1, "error": "missing", "log": log[-400:]})
            continue
        res = d.get("result", {})
        st = d.get("stats") or res.get("stats") or {}
        hl = st.get("hitlog", {})
        recs.append({
            "seed": s, "w0": w0, "w1": w1, "ok": d.get("ok", False), "why": d.get("why", []),
            "winner": int(res.get("winner", -1)), "reason": res.get("reason", "?"), "ticks": int(res.get("ticks", 0)),
            "finisher": st.get("finisher", ""), "hits_by_side": st.get("hits_by_side", [0, 0]),
            "blood_left": st.get("blood_left", [0, 0]), "disarms": st.get("disarms", 0), "severs": st.get("severs", 0),
            "knockdowns": st.get("knockdowns", 0), "self_hits": st.get("self_hits", 0),
            "armor": [l.get("armor", {}) for l in res.get("loadouts", [{}, {}])],
            "dmg": [float(hl.get(w0, {}).get("total", 0.0)), float(hl.get(w1, {}).get("total", 0.0))] if w0 != w1 else None,
            "hitlog": hl,
        })
    return recs


def cmd_run(opts):
    ids = weapon_ids()
    n = int(opts.get("fights", "10"))
    jobs = int(opts.get("jobs", str(max(1, (os.cpu_count() or 2) - 1))))
    base = int(opts.get("seed", "20000"))
    pairs = all_pairs(ids)
    index = {p: i for i, p in enumerate(pairs)}
    if opts.get("only"):
        keep = set(opts["only"].split(","))
        pairs = [p for p in pairs if p[0] in keep and p[1] in keep]
    if opts.get("vs"):
        keep = set(opts["vs"].split(","))
        pairs = [p for p in pairs if p[0] in keep or p[1] in keep]
    if opts.get("nshards"):
        pairs = pairs[int(opts.get("shard", "0"))::int(opts["nshards"])]
    out = opts.get("out") or os.path.join(ROOT, "out", "balance", "run.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([GODOT, "--headless", "--path", ROOT, "--import"], capture_output=True)
    lock = threading.Lock()
    records = []
    done = [0]

    def job(p):
        seed = base + index[p] * 100
        # Seeds overlap between the two orientations on purpose; run them one after the other.
        r = run_side(p[0], p[1], seed, n, None) + run_side(p[1], p[0], seed, n, None)
        with lock:
            records.extend(r)
            done[0] += 1
            for x in r:
                if x.get("error") or not x.get("ok", True):
                    print("BALANCE fight %s vs %s seed=%d %s" % (x["w0"], x["w1"], x["seed"], x.get("error") or ",".join(x.get("why", []))))
            tmp = out + ".part"
            with open(tmp, "w") as f:
                json.dump({"fights": n, "seed": base, "records": records}, f)
            os.replace(tmp, out)

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(job, pairs))
    bad = sum(1 for x in records if x.get("error"))
    print("BALANCE run pairs=%d fights=%d missing=%d out=%s" % (len(pairs), len(records), bad, os.path.relpath(out, ROOT)))
    return 1 if bad else 0


def load_records(files):
    by_pair = {}
    for fn in files:
        with open(fn) as f:
            d = json.load(f)
        fresh = defaultdict(list)
        for r in d["records"]:
            if r.get("error"):
                continue
            fresh[tuple(sorted((r["w0"], r["w1"])))].append(r)
        by_pair.update(fresh)
    return [r for rs in by_pair.values() for r in rs]


def cmd_report(opts, files):
    table = weapon_table()
    ids = [w["id"] for w in table]
    tier = {w["id"]: int(w.get("tier", 0)) for w in table}
    recs = load_records(files)
    cell = defaultdict(lambda: {"n": 0, "w": 0.0, "ticks": 0, "fin": Counter(), "hits": 0, "dmg": 0.0, "side0": 0.0})
    tot = defaultdict(lambda: {"n": 0, "w": 0.0, "ticks": 0, "fin": Counter(), "hits": 0, "hits_taken": 0, "dmg": 0.0})
    side_wins = Counter()
    for r in recs:
        w = [r["w0"], r["w1"]]
        if r["winner"] in (0, 1):
            side_wins[r["winner"]] += 1
        for s in (0, 1):
            a, b = w[s], w[1 - s]
            score = 1.0 if r["winner"] == s else (0.5 if r["winner"] == -1 else 0.0)
            c = cell[(a, b)]
            c["n"] += 1
            c["w"] += score
            c["ticks"] += r["ticks"]
            c["hits"] += int(r["hits_by_side"][s])
            c["dmg"] += float((r.get("dmg") or [0, 0])[s])
            if s == 0:
                c["side0"] += score
            kind = r["finisher"] or r["reason"]
            if r["winner"] == s:
                c["fin"][kind] += 1
            t = tot[a]
            t["n"] += 1
            t["w"] += score
            t["ticks"] += r["ticks"]
            t["hits"] += int(r["hits_by_side"][s])
            t["hits_taken"] += int(r["hits_by_side"][1 - s])
            t["dmg"] += float((r.get("dmg") or [0, 0])[s])
            if r["winner"] == s:
                t["fin"][kind] += 1

    def pct(c):
        return 100.0 * c["w"] / c["n"] if c["n"] else float("nan")

    csv_path = opts.get("csv") or os.path.join(ROOT, "docs", "balance_matrix.csv")
    with open(csv_path, "w") as f:
        f.write("weapon,opponent,tier,opp_tier,fights,win_pct,mean_len_s,hits_per_fight,dmg_per_hit,wins_by,side0_win_pct\n")
        for a in ids:
            for b in ids:
                c = cell.get((a, b))
                if not c or not c["n"]:
                    continue
                wins_by = " ".join("%s:%d" % kv for kv in sorted(c["fin"].items()))
                s0n = c["n"] / 2.0
                f.write("%s,%s,%d,%d,%d,%.1f,%.1f,%.1f,%.1f,%s,%.1f\n" % (a, b, tier[a], tier[b], c["n"], pct(c),
                    c["ticks"] / 60.0 / c["n"], c["hits"] / c["n"], c["dmg"] / max(c["hits"], 1), wins_by,
                    100.0 * c["side0"] / s0n if s0n else 0.0))

    order = sorted([i for i in ids if tot[i]["n"]], key=lambda x: (tier[x], x))
    lines = []
    lines.append("| weapon | tier | win % | fights | mean len s | hits/fight | hits taken | dmg/hit | wins by |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for a in sorted(ids, key=lambda x: -pct(tot[x])):
        t = tot[a]
        if not t["n"]:
            continue
        top = ", ".join("%s %d" % kv for kv in t["fin"].most_common(4))
        lines.append("| %s | %d | %.0f | %d | %.1f | %.1f | %.1f | %.1f | %s |" % (a, tier[a], pct(t), t["n"],
            t["ticks"] / 60.0 / t["n"], t["hits"] / t["n"], t["hits_taken"] / t["n"], t["dmg"] / max(t["hits"], 1), top))
    summary = "\n".join(lines)
    short = {i: i.replace("shield_round", "shield").replace("sledgehammer", "sledge").replace("dai_katana", "dai")
        .replace("laser_sword", "laser").replace("longsword", "long").replace("warhammer", "whammer") for i in ids}
    m = ["| row vs col | " + " | ".join(short[b] for b in order) + " |", "|---" * (len(order) + 1) + "|"]
    for a in order:
        row = []
        for b in order:
            c = cell.get((a, b))
            if a == b or not c or not c["n"]:
                row.append("-")
            else:
                v = pct(c)
                row.append(("**%.0f**" % v) if (tier[a] == tier[b] and (v > 65 or v < 35)) else "%.0f" % v)
        m.append("| %s (%d) | %s |" % (short[a], tier[a], " | ".join(row)))
    matrix = "\n".join(m)
    md = opts.get("md")
    n = len(recs)
    s = sum(side_wins.values())
    head = "fights=%d, side 0 won %.1f%% of decided fights" % (n, 100.0 * side_wins[0] / s if s else 0.0)
    if md:
        with open(md, "w") as f:
            f.write("<!-- generated by tools/balance_matrix.py report -->\n%s\n\n%s\n\n%s\n" % (head, summary, matrix))
    else:
        print(head)
        print(summary)
        print()
        print(matrix)
    print("BALANCE report fights=%d weapons=%d" % (n, len([a for a in ids if tot[a]["n"]])))
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    opts, pos = parse_args(sys.argv[2:])
    if sys.argv[1] == "run":
        return cmd_run(opts)
    if sys.argv[1] == "report":
        return cmd_report(opts, pos)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
