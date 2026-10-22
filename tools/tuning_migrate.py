#!/usr/bin/env python3
"""Move a branch's old-style Tuning edits (rows in game/debug/tuning.gd's FIELDS plus their vars) into the group files.

Usage: python3 tools/tuning_migrate.py <diff file | -> [--root DIR] [--check]

The diff is the branch's own change to the single tuning.gd, taken BEFORE merging the split layout:
    git diff $(git merge-base HEAD origin/main) HEAD -- game/debug/tuning.gd > /tmp/tuning.diff
    git merge origin/main                                # tuning.gd conflicts
    git checkout origin/main -- game/debug/tuning.gd     # keep the split tuning.gd
    python3 tools/tuning_migrate.py /tmp/tuning.diff     # replay the branch's rows into tuning/tuning_<group>.gd
An added row goes at the end of its group's ROWS_<GROUP> with a `var <field>: float` after the group's last var; a
changed row (same field on a - and a + line) replaces the row in place (moving it if its group changed); a removed
row loses its row and var. Rows already in the group files as given are left alone, so a second run changes nothing.
--check reports what it would do without writing. Prints one line per change, then "TUNING_MIGRATE added=a changed=c
removed=r unchanged=u". Exit 1 on a row whose group has no file (a new group needs a new chain link by hand).
"""
import os
import re
import sys

ROW_RE = re.compile(r'^\t\["(\w+)", .*, "([A-Za-z ]+)", ".*"\],?$')
VAR_RE = re.compile(r"^var (\w+): float$")
GROUP_DIR = "game/debug/tuning"


def _slug(group: str) -> str:
    return group.lower().replace(" ", "_")


def parse_diff(text: str) -> tuple:
    """Returns ({field: row line} added, {field: row line} removed) from a unified diff of the old tuning.gd."""
    added = {}
    removed = {}
    for line in text.splitlines():
        if line.startswith(("+++", "---")):
            continue
        if line[:1] in ("+", "-"):
            body = line[1:].rstrip("\r")
            m = ROW_RE.match(body)
            if m:
                row = body if body.endswith(",") else body + ","
                (added if line[0] == "+" else removed)[m.group(1)] = row
    return added, removed


class GroupFile:
    def __init__(self, path: str, group: str) -> None:
        self.path = path
        self.const = "ROWS_" + _slug(group).upper()
        with open(path, encoding="utf-8") as fh:
            self.lines = fh.read().split("\n")
        self.dirty = False

    def _rows_span(self) -> tuple:
        start = self.lines.index("const %s: Array = [" % self.const)
        end = self.lines.index("]", start)
        return start, end

    def row_index(self, field: str) -> int:
        start, end = self._rows_span()
        for i in range(start + 1, end):
            m = ROW_RE.match(self.lines[i])
            if m and m.group(1) == field:
                return i
        return -1

    def var_index(self, field: str) -> int:
        for i, line in enumerate(self.lines):
            m = VAR_RE.match(line)
            if m and m.group(1) == field:
                return i
        return -1

    def add(self, field: str, row: str) -> None:
        _, end = self._rows_span()
        self.lines.insert(end, row)
        if self.var_index(field) < 0:
            last = max([i for i, line in enumerate(self.lines) if VAR_RE.match(line)], default=len(self.lines) - 1)
            self.lines.insert(last + 1, "var %s: float" % field)
        self.dirty = True

    def remove(self, field: str) -> None:
        i = self.row_index(field)
        if i >= 0:
            del self.lines[i]
        j = self.var_index(field)
        if j >= 0:
            del self.lines[j]
        self.dirty = True

    def save(self) -> None:
        with open(self.path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(self.lines))


def migrate(diff_text: str, root: str, write: bool = True) -> tuple:
    added, removed = parse_diff(diff_text)
    files = {}
    log = []
    counts = {"added": 0, "changed": 0, "removed": 0, "unchanged": 0}
    errors = []

    def group_file(group: str):
        if group not in files:
            path = os.path.join(root, GROUP_DIR, "tuning_%s.gd" % _slug(group))
            files[group] = GroupFile(path, group) if os.path.exists(path) else None
        return files[group]

    def find(field: str):
        for fn in sorted(os.listdir(os.path.join(root, GROUP_DIR))):
            m = re.match(r"tuning_(\w+)\.gd$", fn)
            if not m:
                continue
            with open(os.path.join(root, GROUP_DIR, fn), encoding="utf-8") as fh:
                for line in fh:
                    rm = ROW_RE.match(line.rstrip("\n"))
                    if rm and rm.group(1) == field:
                        return group_file(rm.group(2))
        return None

    for field, row in added.items():
        group = ROW_RE.match(row).group(2)
        target = group_file(group)
        if target is None:
            errors.append("%s: group %r has no file %s/tuning_%s.gd" % (field, group, GROUP_DIR, _slug(group)))
            continue
        current = find(field)
        if current is not None and current.row_index(field) >= 0 and current.lines[current.row_index(field)] == row:
            counts["unchanged"] += 1
            continue
        if current is target:
            target.lines[target.row_index(field)] = row
            target.dirty = True
            counts["changed"] += 1
            log.append("TUNING changed %s (%s)" % (field, group))
            continue
        if current is not None:
            current.remove(field)
            counts["changed"] += 1
            log.append("TUNING changed %s (moved to %s)" % (field, group))
        else:
            counts["added"] += 1
            log.append("TUNING added %s (%s)" % (field, group))
        target.add(field, row)
    for field in removed:
        if field in added:
            continue
        current = find(field)
        if current is None:
            counts["unchanged"] += 1
            continue
        current.remove(field)
        counts["removed"] += 1
        log.append("TUNING removed %s" % field)
    if write and not errors:
        for f in files.values():
            if f is not None and f.dirty:
                f.save()
    return log, counts, errors


def main() -> int:
    args = sys.argv[1:]
    root = "."
    write = True
    if "--root" in args:
        i = args.index("--root")
        root = args[i + 1]
        del args[i:i + 2]
    if "--check" in args:
        args.remove("--check")
        write = False
    if len(args) != 1:
        print(__doc__.strip().split("\n")[2], file=sys.stderr)
        return 2
    text = sys.stdin.read() if args[0] == "-" else open(args[0], encoding="utf-8").read()
    log, counts, errors = migrate(text, root, write)
    for line in log:
        print(line)
    for e in errors:
        print("TUNING_MIGRATE error " + e)
    print("TUNING_MIGRATE added=%d changed=%d removed=%d unchanged=%d%s" % (
        counts["added"], counts["changed"], counts["removed"], counts["unchanged"], "" if write else " (check only)"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
