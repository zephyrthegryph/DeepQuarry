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


check "a gen failure is shown, retried, then an infra exit that merge_batch treats as a setup error" 'grep -q "exit 95" "$here/tools/dq_merge_gates.sh" && grep -q "\"\$rc\" -eq 95" "$here/tools/dq_merge_batch.sh"'

check "test worlds run below normal (not idle) and log it; ratchets cap rayon beside a world" 'grep -q "PRIORITY_BELOW_NORMAL" "$here/tools/build/lib/byond.ts" && grep -q "world priority:" "$here/tools/build/lib/byond.ts" && grep -q "RAYON_NUM_THREADS=" "$here/tools/dq_merge_gates.sh"'

check "the gates stop sibling jobs when the test build fails to compile" 'grep -q "FAIL FAST: the test build does not compile" "$here/tools/dq_merge_gates.sh"'

# dq_merge_batch: one real conflict between two lanes must not poison the attempts after it (27 October, train-dc: 0 of 12 lanes passed).
# A scratch repository, stub gates; lanes c1 and c2 conflict with each other only, g1 and g2 are clean: c2 waits, the rest pass, and no
# attempt after the conflict starts dirty.
r="$tmp/mb"; git init -q --bare "$r/origin.git"; git clone -q "$r/origin.git" "$r/w" 2>/dev/null
(
	cd "$r/w" || exit 1
	git config user.email t@t; git config user.name t
	mkdir -p tools lanes
	cp "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_dme_resolve.sh" tools/
	echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
	cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
# DQ_STUB_NORESULT=1: two or more lane files give a test phase with no result (the 28 October 03:04 case)
if [ "${DQ_STUB_NORESULT:-0}" = 1 ] && [ "$(ls lanes 2>/dev/null | wc -l)" -gt 1 ]; then
	echo "FOCUSED RESULT: CAPPED or killed before a result (exit 0): the focused run printed no result line"
	echo "dq_merge_gates: FAILED: tests (logs data/merge-gates/x.<job>.log)" >&2; exit 1
fi
echo "stub gates: ok"
STUB
	echo base >shared.txt; printf 'data/\n' >.gitignore
	git add -A; git commit -q -m init; git branch -M master; git push -q origin master; git fetch -q origin
	for l in g1 c1 c2 g2; do
		git switch -q -c "$l" origin/master
		mkdir -p lanes; case "$l" in c*) echo "$l" >shared.txt ;; *) echo "$l" >"lanes/$l.txt" ;; esac
		if [ "$l" = g1 ]; then mkdir -p code/modules/unit_tests; echo x >code/modules/unit_tests/here.dm; printf '#include "here.dm"\n#include "gone.dm"\n' >code/modules/unit_tests/_unit_tests.dm; fi
		git add -A; git commit -q -m "$l"; git push -q origin "$l"
	done
	git switch -q --detach origin/master
	bash tools/dq_merge_batch.sh --lanes "g1 c1 c2 g2" >"$r/out.txt" 2>&1
	git switch -q --detach origin/master
	DQ_STUB_NORESULT=1 bash tools/dq_merge_batch.sh --lanes "g1 g2" >"$r/noresult.txt" 2>&1
) >/dev/null 2>&1
mb_good="$(sed -n 's/^BATCH_GOOD: //p' "$r/out.txt" | tail -n 1)"
mb_later="$(sed -n 's/^BATCH_LATER: //p' "$r/out.txt" | tail -n 1)"
check "a lane-vs-lane conflict holds back only that lane; the clean lanes and the first of the pair pass" '[[ " $mb_good " == *" g1 "* && " $mb_good " == *" g2 "* && " $mb_good " == *" c1 "* ]] && [ "$(echo $mb_later)" = c2 ] && ! grep -q "started dirty" "$r/out.txt"'
check "a merged include of a file that no longer exists is dropped and reported" 'grep -q "STALE INCLUDE dropped .*gone.dm" "$r/out.txt"'
check "a 2-lane attempt with no test result defers both lanes and bisects nobody (03:04: move/effects-wave was blamed)" '! grep -q "^BATCH_BOUNCED: ." "$r/noresult.txt" && grep -q "^BATCH_DEFERRED: .*g1" "$r/noresult.txt" && grep -q "^BATCH_DEFERRED: .*g2" "$r/noresult.txt"'
[ "$fail" -eq 0 ] || { echo "---- merge_batch output:"; tail -n 30 "$r/out.txt"; }

[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
