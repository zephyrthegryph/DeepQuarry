#!/usr/bin/env bash
# Self-test of tools/dq_declared_tests.sh (filter_declared_tests): a stamped list that names a deleted test (a removed look pin)
# loses exactly that name, each drop is logged, globs and declared names stay, and a /datum/unit_test/ prefix is accepted.
# Also checks by grep that every path that replays a stamped list (lane stamps, the re-proof list, the lite re-proof list) uses it.
#
#   bash tools/ci/test_declared_tests.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mkdir -p "$tmp/code"
cat >"$tmp/code/t.dm" <<'DM'
/datum/unit_test/dq_alive
/datum/unit_test/dq_group
/datum/unit_test/dq_group/child
DM
export DQ_DECLARED_TESTS_ROOT="$tmp/code"
. "$here/tools/dq_declared_tests.sh"

kept="$(filter_declared_tests "stamp of lane-x" dq_alive dq_look_pin 'dq_group/*' /datum/unit_test/dq_group/child dq_gone/sub dq_group/other 2>"$tmp/err" | tr '\n' ' ')"
[ "$kept" = "dq_alive dq_group/* dq_group/child dq_group/other " ] && ok "declared names, globs and prefixed names are kept" || bad "kept: '$kept'"
grep -q "dropped (no longer declared, stamp of lane-x): dq_look_pin" "$tmp/err" && ok "the deleted name is dropped and logged with its origin" || bad "no drop line: $(cat "$tmp/err")"
grep -q "dq_gone/sub" "$tmp/err" && ok "a deleted nested name is dropped and logged" || bad "nested drop missing"
[ "$(grep -c dropped "$tmp/err")" -eq 2 ] && ok "only the stale names are reported" || bad "drop count: $(cat "$tmp/err")"
[ -z "$(filter_declared_tests x 2>&1)" ] && ok "an empty list stays empty" || bad "empty list"

# every replay of a stamped list goes through the filter
grep -q 'filter_declared_tests "stamp of' "$here/tools/dq_merge_gates.sh" && ok "merge gates filter the lane stamp lists" || bad "merge gates: lane stamps unfiltered"
grep -q 'filter_declared_tests "re-proof list"' "$here/tools/dq_merge_gates.sh" && ok "merge gates filter the re-proof list" || bad "merge gates: re-proof unfiltered"
grep -q 'filter_declared_tests "lite re-proof list"' "$here/tools/dq_lane_ready.sh" && ok "lane-ready filters the lite re-proof list" || bad "lane-ready: lite list unfiltered"
exit "$fail"
