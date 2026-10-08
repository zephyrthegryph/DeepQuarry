#!/usr/bin/env bash
# Tests that fail on master itself, so a merge agent need not build a throwaway worktree to prove a failure is old.
# The list is tools/ci/known_failures.txt: one test per line, TAB separated: test spec, reason, master sha (10 chars)
# last seen failing. `#` lines are comments. A spec is a /datum/unit_test/ name (prefix optional) or `parent/*`.
#
#   bash tools/dq_known_failures.sh --check data/test-runs/<run>.json     # prints NEW vs KNOWN failures; exit 1 if any NEW
#   bash tools/dq_known_failures.sh --refresh data/test-runs/<run>.json   # drop known tests that pass in the run, bump sha of
#                                                                         # those still failing (never adds a test)
#   bash tools/dq_known_failures.sh --adopt data/test-runs/<run>.json --reason "why"   # add the run's NEW failures
#   bash tools/dq_known_failures.sh --refresh-for-head <sha>              # --refresh from the data/test-runs records of that
#                                                                         # commit (newest result per test); exit 10 if changed
#
# dq_focused_test.sh calls --check after a run that has failures. dq_push_master.sh calls --refresh-for-head after a push,
# only when a focused run JSON for the pushed head exists (it runs no tests); it commits a changed list on top and pushes.
# Adding a test to the list is a decision (--adopt, with a reason); nothing adds one automatically.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { sed -n '2,15p' "$0" >&2; exit 2; }
mode="${1#--}"
shift
exec node tools/dq_known_failures.js "$mode" "$@"
