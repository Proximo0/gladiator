# Lessons learned (read before starting work)

Sandblood build guide: https://claude.ai/artifact/LBNp22258n18mRFtk2ke4i (Skate Park playbook: https://claude.ai/artifact/WtmrkVRtizP8oJBRwhxdWW).

**Read them:** `python3 tools/lessons_index.py` prints every lesson as one table (or `cat docs/lessons/*.md`).

**Add one** whenever something goes wrong: a new file `docs/lessons/<YYYY-MM-DD>-<short-slug>.md` with two lines,

```
What happened: <what went wrong, with the numbers you measured>
Rule: <what to do from now on>
```

One file per lesson, and no committed table, so two branches that each add a lesson never touch the same file and
GitHub can merge both. `tools/lint.sh` checks every file's name and format (rule `lessons`).
