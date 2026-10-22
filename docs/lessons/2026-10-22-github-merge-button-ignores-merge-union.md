What happened: Two branches that each appended a row to docs/lessons_learned.md merged cleanly with git (merge=union in .gitattributes), but GitHub marked the PR not mergeable: its merge button ignores custom merge drivers
Rule: Shared append-only lists are one file per entry (docs/lessons/, game/debug/tuning/ groups), never a single file every branch appends to
