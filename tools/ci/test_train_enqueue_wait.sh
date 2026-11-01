#!/usr/bin/env bash
# `dq_train.sh enqueue` refuses a lane that conflicts with origin/master at once (no queue entry), and `dq_train.sh wait <branch>` blocks until the
# lane landed (0) or was bounced (3, reason printed), says 4 for a lane that is not in the train and 5 on a timeout. Scratch repository and state.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
st="$tmp/state"
git init -q --bare "$tmp/origin.git"; git clone -q "$tmp/origin.git" "$tmp/w" 2>/dev/null
(
	cd "$tmp/w" || exit 1
	git config user.email t@t; git config user.name t
	mkdir -p tools doc
	cp "$here/tools/dq_train.sh" "$here/tools/dq_declared_tests.sh" "$here/tools/dq_light_paths.sh" "$here/tools/dq_git_safe.sh" tools/
	echo base >doc/a.txt; git add -A; git commit -qm base; git branch -M master; git push -q origin master 2>/dev/null
	git switch -q -c lane/conflict; echo lane >doc/a.txt; git commit -qam lane
	git switch -q master; echo master >doc/a.txt; git commit -qam master; git push -q origin master 2>/dev/null
	git switch -q -c lane/clean; echo c >doc/c.txt; git add -A; git commit -qm clean
	git switch -q lane/conflict
) >/dev/null 2>&1
run() { # <args...> in the lane's worktree
	( cd "$tmp/w" && DQ_TRAIN_STATE="$st" DQ_TRAIN_NO_START=1 DQ_TRAIN_WT="$tmp/none" DQ_TRAIN_BRANCH=train/none bash tools/dq_train.sh "$@" 2>&1 )
}
out="$(run enqueue --light)"; rc=$?
check "a conflicting lane is refused at enqueue with the fix command" '[ "$rc" -ne 0 ] && grep -q "REFUSED: lane/conflict conflicts with origin/master" <<<"$out" && grep -q "dq_merge_master.sh" <<<"$out" && grep -q "doc/a.txt" <<<"$out"'
check "a refused lane leaves no queue entry" '[ ! -e "$st/queue/lane_conflict.q" ]'
(cd "$tmp/w" && git switch -q lane/clean) >/dev/null 2>&1
out="$(run enqueue --light)"; rc=$?
check "a clean lane is queued" '[ "$rc" -eq 0 ] && [ -e "$st/queue/lane_clean.q" ]'
out="$(run wait lane/clean --timeout 0)"; rc=$?
check "wait on a queued lane times out with exit 5" '[ "$rc" -eq 5 ] && grep -q "still queued" <<<"$out"'
tip="$(git -C "$tmp/w" rev-parse lane/clean)"
mkdir -p "$st/landed"; printf 'branch=lane/clean\ntip=%s\nmaster=%s\nlanded=2026-01-01T00:00:00Z\n' "$tip" "$tip" >"$st/landed/lane_clean.landed"
rm -f "$st/queue/lane_clean.q"
out="$(run wait lane/clean --timeout 1)"; rc=$?
check "wait on a landed lane says LANDED, exit 0" '[ "$rc" -eq 0 ] && grep -q "LANDED lane/clean" <<<"$out"'
rm -f "$st/landed/lane_clean.landed"; mkdir -p "$st/bounced"
printf 'seq=1\nbranch=lane/clean\ntip=%s\nreason=precheck: gates failed alone\nreport=/x/report.md\n' "$tip" >"$st/bounced/lane_clean.q"
out="$(run wait lane/clean --timeout 1)"; rc=$?
check "wait on a bounced lane prints the reason, exit 3" '[ "$rc" -eq 3 ] && grep -q "BOUNCED lane/clean" <<<"$out" && grep -q "gates failed alone" <<<"$out" && grep -q "/x/report.md" <<<"$out"'
rm -f "$st/bounced/lane_clean.q"
out="$(run wait lane/clean --timeout 1)"; rc=$?
check "wait on a lane that is nowhere says so, exit 4" '[ "$rc" -eq 4 ] && grep -q "not in the train" <<<"$out"'
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
