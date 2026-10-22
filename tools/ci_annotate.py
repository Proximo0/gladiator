#!/usr/bin/env python3
"""Turn failure lines in a check's log into GitHub annotations and step-summary lines.

Usage: python3 tools/ci_annotate.py <job name> <log file>
Reads FAIL lines from tools/run_tests.sh, tools/lint.sh, tools/run_sims.sh and the bot scene. Prints one
`::error` workflow command per failure (shown on the run page and in the checks API without downloading logs)
and appends a short table to $GITHUB_STEP_SUMMARY when it is set. Prints nothing when there are no failures.
"""
import os
import re
import sys

MAX_ANNOTATIONS = 50  # GitHub keeps at most 50 error annotations per job
PATTERNS = [
    # unit: "FAIL test_x::case  message" and "LOAD FAIL tests/unit/test_x.gd"
    (re.compile(r"^(?:LOAD )?FAIL (\S+)\s*(.*)$"), None),
    # sims and bot: "SIM name FAIL detail", "BOT ... FAIL detail"
    (re.compile(r"^SIM (\S+) FAIL (.*)$"), None),
    (re.compile(r"^BOT (.*?) FAIL (.*)$"), None),
    # sims runner fallback when the scene dies: "SIM sim_suite FAIL ..." is covered above
    # lint: "path/file.gd:12 rule message"
    (re.compile(r"^([\w./-]+\.(?:gd|py|sh|tscn|json)):(\d+) (.*)$"), "file"),
    # Godot script errors that end a run early
    (re.compile(r"^(SCRIPT ERROR): (.*)$"), None),
]


def _escape(text: str, prop: bool = False) -> str:
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if prop:
        text = text.replace(":", "%3A").replace(",", "%2C")
    return text


def _failures(lines: list) -> list:
    out = []
    for line in lines:
        line = line.rstrip("\n")
        for rx, kind in PATTERNS:
            m = rx.match(line)
            if not m:
                continue
            if kind == "file":
                out.append({"title": m.group(3).split(" ", 1)[0], "file": m.group(1), "line": m.group(2), "text": m.group(3)})
            else:
                out.append({"title": m.group(1), "text": m.group(2) or line})
            break
    return out


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: ci_annotate.py <job name> <log file>", file=sys.stderr)
        return 2
    job, path = sys.argv[1], sys.argv[2]
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError as e:
        print("::error title=%s::log missing (%s)" % (_escape(job, True), _escape(str(e))))
        return 0
    fails = _failures(lines)
    for f in fails[:MAX_ANNOTATIONS]:
        props = "title=%s" % _escape("%s: %s" % (job, f["title"]), True)
        if "file" in f:
            props = "file=%s,line=%s,%s" % (_escape(f["file"], True), f["line"], props)
        print("::error %s::%s" % (props, _escape(f["text"][:900])))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and fails:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("### %s: %d failure(s)\n\n" % (job, len(fails)))
            for f in fails[:200]:
                where = " (%s:%s)" % (f["file"], f["line"]) if "file" in f else ""
                fh.write("- **%s**%s %s\n" % (f["title"], where, f["text"][:300].replace("|", "\\|")))
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
