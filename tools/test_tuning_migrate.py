#!/usr/bin/env python3
"""Tests for tools/tuning_migrate.py on a fake two-group tree and a fake old-style diff.

Run: python3 tools/test_tuning_migrate.py   (prints failures, then "TUNING_MIGRATE_TESTS passed=N failed=M")
"""
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tuning_migrate  # noqa: E402

DAMAGE = '''extends RefCounted
## Tuning rows of the "Damage" group.

const ROWS_DAMAGE: Array = [
\t["dmg_cut_scale", 0.25, 0.05, 1.0, 0.01, "Damage", "Cut damage points per joule."],
\t["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut points that gut."],
]

var dmg_cut_scale: float
var dmg_gut: float
'''

SAND = '''extends "res://game/debug/tuning/tuning_damage.gd"
## Tuning rows of the "Sand" group.

const ROWS_SAND: Array = [
\t["sand_dust_life", 3.5, 0.5, 10.0, 0.1, "Sand", "Seconds fine dust lingers."],
]

var sand_dust_life: float
'''

# What a branch made before the split: a new Damage row, a new Sand row (the last row, so no trailing comma
# change shows), a changed default, a row moved from Damage to Sand, and their vars.
DIFF = '''diff --git a/game/debug/tuning.gd b/game/debug/tuning.gd
--- a/game/debug/tuning.gd
+++ b/game/debug/tuning.gd
@@ -12,6 +12,8 @@ const FIELDS: Array = [
 \t["dmg_cut_scale", 0.25, 0.05, 1.0, 0.01, "Damage", "Cut damage points per joule."],
-\t["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut points that gut."],
+\t["dmg_gut", 26.0, 10.0, 100.0, 1.0, "Damage", "Cut points that gut."],
+\t["dmg_armor_weight", 1.2, 0.5, 3.0, 0.05, "Damage", "Stamina cost multiplier per kg of armor."],
 \t["sand_dust_life", 3.5, 0.5, 10.0, 0.1, "Sand", "Seconds fine dust lingers."],
+\t["sand_shadow_soft", 0.4, 0.0, 1.0, 0.05, "Sand", "Softness of grounding shadows on sand."]
 ]
@@ -400,3 +402,5 @@ var dmg_gut: float
 var sand_dust_life: float
+var dmg_armor_weight: float
+var sand_shadow_soft: float
'''


class TuningMigrateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, tuning_migrate.GROUP_DIR)
        os.makedirs(self.dir)
        for name, text in (("tuning_damage.gd", DAMAGE), ("tuning_sand.gd", SAND)):
            with open(os.path.join(self.dir, name), "w", encoding="utf-8") as fh:
                fh.write(text)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def read(self, name: str) -> str:
        with open(os.path.join(self.dir, name), encoding="utf-8") as fh:
            return fh.read()

    def test_adds_changes_and_is_idempotent(self) -> None:
        log, counts, errors = tuning_migrate.migrate(DIFF, self.tmp.name)
        self.assertEqual(errors, [])
        self.assertEqual(counts, {"added": 2, "changed": 1, "removed": 0, "unchanged": 0}, log)
        damage = self.read("tuning_damage.gd")
        sand = self.read("tuning_sand.gd")
        # the new Damage row is the last row of ROWS_DAMAGE, its var after the last var
        rows = damage.split("const ROWS_DAMAGE: Array = [\n")[1].split("\n]\n")[0].split("\n")
        self.assertTrue(rows[-1].startswith('\t["dmg_armor_weight", 1.2,'), rows)
        self.assertTrue(damage.rstrip("\n").endswith("var dmg_armor_weight: float"), damage)
        # the changed default replaced the row in place (still second)
        self.assertTrue(rows[1].startswith('\t["dmg_gut", 26.0,'), rows)
        self.assertEqual(damage.count('"dmg_gut"'), 1)
        # the Sand row got its trailing comma and its var
        self.assertIn('\t["sand_shadow_soft", 0.4, 0.0, 1.0, 0.05, "Sand", "Softness of grounding shadows on sand."],', sand)
        self.assertIn("var sand_shadow_soft: float", sand)
        self.assertNotIn("sand_shadow_soft", damage)
        # a second run changes nothing
        before = (damage, sand)
        _, counts2, _ = tuning_migrate.migrate(DIFF, self.tmp.name)
        self.assertEqual(counts2, {"added": 0, "changed": 0, "removed": 0, "unchanged": 3})
        self.assertEqual(before, (self.read("tuning_damage.gd"), self.read("tuning_sand.gd")))

    def test_moves_a_row_to_its_new_group_and_removes(self) -> None:
        diff = ('-\t["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut points that gut."],\n'
                '+\t["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Sand", "Cut points that gut."],\n'
                '-\t["sand_dust_life", 3.5, 0.5, 10.0, 0.1, "Sand", "Seconds fine dust lingers."],\n')
        _, counts, errors = tuning_migrate.migrate(diff, self.tmp.name)
        self.assertEqual(errors, [])
        self.assertEqual(counts["changed"], 1)
        self.assertEqual(counts["removed"], 1)
        damage = self.read("tuning_damage.gd")
        sand = self.read("tuning_sand.gd")
        self.assertNotIn("dmg_gut", damage)
        self.assertIn('"dmg_gut", 30.0, 10.0, 100.0, 1.0, "Sand"', sand)
        self.assertIn("var dmg_gut: float", sand)
        self.assertNotIn("sand_dust_life", sand)

    def test_unknown_group_writes_nothing(self) -> None:
        diff = '+\t["x_new", 1.0, 0.0, 2.0, 0.1, "Mounts", "A group with no file."],\n' + DIFF
        _, _, errors = tuning_migrate.migrate(diff, self.tmp.name)
        self.assertEqual(len(errors), 1)
        self.assertEqual(self.read("tuning_damage.gd"), DAMAGE)
        self.assertEqual(self.read("tuning_sand.gd"), SAND)

    def test_check_only_writes_nothing(self) -> None:
        _, counts, _ = tuning_migrate.migrate(DIFF, self.tmp.name, write=False)
        self.assertEqual(counts["added"], 2)
        self.assertEqual(self.read("tuning_damage.gd"), DAMAGE)


if __name__ == "__main__":
    out = io.StringIO()
    result = unittest.TextTestRunner(stream=out, verbosity=0).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(TuningMigrateTest))
    failed = len(result.failures) + len(result.errors)
    if failed:
        print(out.getvalue())
    print("TUNING_MIGRATE_TESTS passed=%d failed=%d" % (result.testsRun - failed, failed))
    sys.exit(1 if failed else 0)
