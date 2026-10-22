#!/usr/bin/env python3
"""Print the lessons table from docs/lessons/, one file per lesson. Standard library only.

Usage: python3 tools/lessons_index.py [--check] [--out FILE]

Each lesson is docs/lessons/<YYYY-MM-DD>-<slug>.md holding two lines:
    What happened: <what went wrong>
    Rule: <what to do from now on>
One file per lesson means two branches that each add one never touch the same file, so GitHub's merge button (which
ignores custom merge drivers) never sees a conflict. The table is not committed for the same reason: it is printed.
Rows are in file-name order (date, then slug). --out writes the table to FILE instead of stdout.
--check prints one "path:line lessons <problem>" per bad file and "LESSONS files=<n> problems=<m>"; exit 1 on problems.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LESSONS_DIR = "docs/lessons"
NAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$")
FIELDS = ("What happened: ", "Rule: ")


def lesson_files(root: str = ROOT) -> list:
    folder = os.path.join(root, LESSONS_DIR)
    if not os.path.isdir(folder):
        return []
    return sorted(fn for fn in os.listdir(folder) if fn.endswith(".md") and fn != "README.md")


def parse_lesson(text: str) -> tuple:
    """Returns ((what, rule), problem); problem is "" for a good file."""
    lines = [line for line in text.split("\n") if line.strip()]
    if len(lines) != 2:
        return None, "needs exactly two lines, '%s...' and '%s...'" % (FIELDS[0].strip(), FIELDS[1].strip())
    for line, field in zip(lines, FIELDS):
        if not line.startswith(field) or not line[len(field):].strip():
            return None, "line must start with '%s' and say something" % field.strip()
    return (lines[0][len(FIELDS[0]):].strip(), lines[1][len(FIELDS[1]):].strip()), ""


def check(root: str = ROOT) -> list:
    problems = []
    for fn in lesson_files(root):
        rel = "%s/%s" % (LESSONS_DIR, fn)
        if not NAME_RE.match(fn):
            problems.append((rel, 1, "name must be <YYYY-MM-DD>-<lowercase-slug>.md"))
        with open(os.path.join(root, LESSONS_DIR, fn), encoding="utf-8") as fh:
            _, problem = parse_lesson(fh.read())
        if problem:
            problems.append((rel, 1, problem))
    return problems


def table(root: str = ROOT) -> str:
    out = ["| What happened | Rule |", "| --- | --- |"]
    for fn in lesson_files(root):
        with open(os.path.join(root, LESSONS_DIR, fn), encoding="utf-8") as fh:
            lesson, _ = parse_lesson(fh.read())
        if lesson:
            out.append("| %s | %s |" % tuple(cell.replace("|", "\\|") for cell in lesson))
    return "\n".join(out) + "\n"


def main() -> int:
    args = sys.argv[1:]
    if "--check" in args:
        problems = check()
        for rel, lineno, message in problems:
            print("%s:%d lessons %s" % (rel, lineno, message))
        print("LESSONS files=%d problems=%d" % (len(lesson_files()), len(problems)))
        return 1 if problems else 0
    text = table()
    if "--out" in args:
        with open(args[args.index("--out") + 1], "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
