#!/usr/bin/env bash
# A tool self-test that fails inside check_ratchets.sh must fail the whole run (exit 1, named in the summary), never "All ratchet lints passed".
# Runs the real check_ratchets.sh once with the disk-budget self-test replaced by a failing script (DQ_RATCHETS_DISK_TEST).
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here" || exit 1
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\necho "FAIL a deliberately failing self-test"\nexit 1\n' >"$tmp/bad.sh"
out="$(DQ_RATCHETS_SELFTESTS=all DQ_RATCHETS_DISK_TEST="$tmp/bad.sh" bash tools/ci/check_ratchets.sh 2>&1)"; rc=$?
fail=0
[ "$rc" -ne 0 ] && echo "PASS: check_ratchets exits non-zero when a tool self-test fails" || { echo "FAIL: exit $rc with a failing self-test"; fail=1; }
grep -q "Ratchet lints failed:.*test_disk_budget" <<<"$out" && echo "PASS: the failing self-test is named in the summary" || { echo "FAIL: not named"; fail=1; }
grep -qx "All ratchet lints passed\." <<<"$out" && { echo "FAIL: reported an overall pass"; fail=1; }
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
