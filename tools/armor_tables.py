#!/usr/bin/env python3
"""Re-measure the shield and per-piece armor tables of docs/armor_more.md with seeded bot fights.

Usage: tools/armor_tables.py [--table=shields|armor|naked|all] [--seeds=2000:2012] [--shards=4] [--rows=a,b]
                             [--out=out/armor_tables.json]
Every row is fought from both sides (seeds A..B-1 each), so a row has 2 * (B - A) fights. Quiet: one line per row,
then a summary line; rows outside the 35-65% band are marked OUT.
"""
import argparse
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IRON = {"head": "helm_iron", "torso": "cuirass_iron", "arms": "bracers_iron", "legs": "greaves_iron"}
SHIELDS = ["shield_round", "scutum", "buckler", "parma", "pelta", "kite_shield", "aspis", "tower_shield"]
PIECES = ["helm_iron", "helm_murmillo", "helm_thraex", "helm_secutor", "lorica_segmentata", "lorica_squamata",
          "balteus", "retiarius_arm", "spaulders", "fasciae"]


def armor_slot(aid):
    data = json.load(open(os.path.join(ROOT, "data", "armor.json")))
    rows = data[list(data)[0]] if isinstance(data, dict) else data
    for a in rows:
        if a["id"] == aid:
            return a["part"]
    raise SystemExit("unknown armor id " + aid)


def iron_with(aid):
    s = dict(IRON)
    if aid != "helm_iron":
        s[armor_slot(aid)] = aid
    return ",".join(s.values())


def fight(args, side_a, side_b, more):
    """side_a / side_b: dicts of bot_match flags for sides 0 / 1 (keys w, o, a). Returns list of result dicts."""
    a, b = args.seeds.split(":")
    cmd = [os.path.join(ROOT, "tools", "bot_match.sh"), "--matches=%d" % (int(b) - int(a)), "--seed=" + a,
           "--shards=%d" % args.shards]
    for side, flags in ((0, side_a), (1, side_b)):
        for k, v in flags.items():
            cmd.append("--%s%d=%s" % (k, side, v))
    cmd += more + args.extra
    for f in glob.glob(os.path.join(ROOT, "out", "bot", "*.json")):
        os.remove(f)
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = []
    for s in range(int(a), int(b)):
        fn = os.path.join(ROOT, "out", "bot", "%d.json" % s)
        if not os.path.exists(fn):
            print("ERROR missing %s (rc %d)\n%s" % (fn, p.returncode, p.stdout[-2000:]))
            continue
        out.append(json.load(open(fn))["result"])
    return out


def row(args, name, mine, theirs, more=None):
    """Wins of `mine` out of both side assignments."""
    more = more or []
    recs = [(r, 0) for r in fight(args, mine, theirs, more)] + [(r, 1) for r in fight(args, theirs, mine, more)]
    wins = sum(1 for r, s in recs if int(r["winner"]) == s)
    draws = sum(1 for r, _ in recs if int(r["winner"]) < 0)
    n = len(recs)
    secs = sum(float(r["fight_ticks"]) for r, _ in recs) / 60.0 / max(n, 1)
    share = wins / max(n, 1)
    flag = "" if 0.35 <= share <= 0.65 else " OUT"
    print("ROW %-18s wins=%d/%d (%.0f%%) draws=%d len=%.1fs%s" % (name, wins, n, share * 100, draws, secs, flag))
    sys.stdout.flush()
    return {"row": name, "wins": wins, "fights": n, "draws": draws, "len_s": round(secs, 1)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", default="all")
    ap.add_argument("--seeds", default="2000:2012")
    ap.add_argument("--shards", type=int, default=4)
    ap.add_argument("--rows", default="")
    ap.add_argument("--out", default="out/armor_tables.json")
    args, args.extra = ap.parse_known_args()
    only = set(r for r in args.rows.split(",") if r)
    res = {}
    if args.table in ("shields", "all"):
        res["shields"] = [row(args, s, {"w": "gladius", "o": s}, {"w": "longsword"},
                              ["--armor=leather"])
                          for s in SHIELDS if not only or s in only]
    if args.table in ("armor", "all"):
        base = iron_with("helm_iron")
        res["armor"] = [row(args, p if p != "helm_iron" else "iron set", {"w": "gladius", "a": iron_with(p)},
                            {"w": "gladius", "a": base}) for p in PIECES if not only or p in only]
    if args.table in ("naked", "all"):
        res["naked"] = [row(args, "iron v naked", {"w": "gladius", "a": iron_with("helm_iron")},
                            {"w": "gladius", "a": ""})]
    os.makedirs(os.path.dirname(os.path.join(ROOT, args.out)), exist_ok=True)
    json.dump(res, open(os.path.join(ROOT, args.out), "w"), indent=1)
    rows = [r for t in res.values() for r in t]
    out = sum(1 for r in rows if not 0.35 <= r["wins"] / max(r["fights"], 1) <= 0.65)
    print("ARMOR_TABLES rows=%d out_of_band=%d" % (len(rows), out))


if __name__ == "__main__":
    main()
