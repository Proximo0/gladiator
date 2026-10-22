#!/usr/bin/env python3
"""Tests for tools/lessons_index.py on a fake docs/lessons/ folder.

Run: python3 tools/test_lessons_index.py   (prints failures, then "LESSONS_INDEX_TESTS passed=N failed=M")
"""
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lessons_index  # noqa: E402


class LessonsIndexTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, lessons_index.LESSONS_DIR)
        os.makedirs(self.dir)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, name: str, text: str) -> None:
        with open(os.path.join(self.dir, name), "w", encoding="utf-8") as fh:
            fh.write(text)

    def test_table_in_name_order_with_pipes_escaped(self) -> None:
        self.write("2026-10-22-later.md", "What happened: `yes | sdkmanager` died\nRule: set +o pipefail\n")
        self.write("2026-10-21-earlier.md", "What happened: A\n\nRule: B\n")
        self.write("README.md", "not a lesson")
        self.assertEqual(lessons_index.table(self.tmp.name),
                         "| What happened | Rule |\n| --- | --- |\n| A | B |\n"
                         "| `yes \\| sdkmanager` died | set +o pipefail |\n")
        self.assertEqual(lessons_index.check(self.tmp.name), [])

    def test_check_flags_bad_names_and_formats(self) -> None:
        self.write("2026-10-22-ok.md", "What happened: A\nRule: B\n")
        self.write("no-date.md", "What happened: A\nRule: B\n")
        self.write("2026-10-22-one-line.md", "What happened: A\n")
        self.write("2026-10-22-empty-rule.md", "What happened: A\nRule: \n")
        bad = sorted(rel.split("/")[-1] for rel, _, _ in lessons_index.check(self.tmp.name))
        self.assertEqual(bad, ["2026-10-22-empty-rule.md", "2026-10-22-one-line.md", "no-date.md"])
        # a bad file stays out of the table instead of breaking it
        self.assertEqual(lessons_index.table(self.tmp.name).count("\n"), 4)


if __name__ == "__main__":
    out = io.StringIO()
    result = unittest.TextTestRunner(stream=out, verbosity=0).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LessonsIndexTest))
    failed = len(result.failures) + len(result.errors)
    if failed:
        print(out.getvalue())
    print("LESSONS_INDEX_TESTS passed=%d failed=%d" % (result.testsRun - failed, failed))
    sys.exit(1 if failed else 0)
