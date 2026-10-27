#!/usr/bin/env bash
# Fast unit checks (a few seconds) of the train's proof-landing decisions, without a scratch repository: the functions are extracted from
# tools/dq_train.sh and tools/dq_merge_batch.sh and called directly. tools/ci/test_train.sh drives the whole train end to end.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# smoke_due: the smoke/gameplay sets run every DQ_TRAIN_SMOKE_EVERY proof landings, and on a batch of DQ_TRAIN_SMOKE_AT_LANES lanes
eval "$(sed -n '/^smoke_due() {/,/^}/p' "$here/tools/dq_train.sh")"
STATE="$tmp"
rm -f "$STATE/smoke_skipped"
check "smoke not due on the first proof landing of one lane" '! DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'
echo 3 >"$STATE/smoke_skipped"
check "smoke due after every-1 skipped proof landings" 'DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'
echo 0 >"$STATE/smoke_skipped"
check "smoke due on a batch of many lanes" 'DQ_TRAIN_SMOKE_AT_LANES=5 smoke_due 5'
echo junk >"$STATE/smoke_skipped"
check "a corrupt counter counts as zero" '! DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'

# dq_merge_batch: a run with no result is a cap (93), never a failure
re="$(grep -o "grep -qE '[^']*FOCUSED RESULT: CAPPED[^']*'" "$here/tools/dq_merge_batch.sh" | head -n 1 | sed "s/^grep -qE '//; s/'\$//")"
check "merge_batch classifies a no-result run as capped" '[ -n "$re" ] && echo "FOCUSED RESULT: CAPPED or killed before a result (exit 0)" | grep -qE "$re" && echo "FOCUSED RUN CAPPED: x" | grep -qE "$re" && ! echo "FOCUSED RESULT: 3 FAILED" | grep -qE "$re"'
check "merge_batch retries a no-result lane once with only its own tests, then defers it" 'grep -q "pass+=(--no-smoke)" "$here/tools/dq_merge_batch.sh" && grep -q "BATCH_NORESULT" "$here/tools/dq_merge_batch.sh"'

# the gates honour the train's analyze_tests trust
check "dq_merge_gates skips analyze_tests on DQ_GATE_ANALYZE_TRUSTED and logs why" 'grep -q "analyze_tests trusted (not run)" "$here/tools/dq_merge_gates.sh"'

[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
