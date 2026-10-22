What happened: check_all.sh logged to a shared /tmp/check, so two runs overwrote each other's logs, and it ended on a table with no single verdict
Rule: Each run logs to its own mktemp dir; the last line is `CHECK_ALL PASS` or `CHECK_ALL FAIL`, and the exit code matches
