#!/usr/bin/env bash
# Self-test of tools/dq_merge_batch.sh in a scratch repository, with a stub dq_merge_gates.sh that fails when the merged tree holds a
# file containing BAD (so no compiler or DM world runs). Cases: a clean batch of three merges and the branch holds all three; a batch
# with one bad lane bounces only that lane (bisect) and the branch holds the others; a conflicting lane is bounced at once; a lone bad
# lane leaves the branch at origin/master. Also checks tools/dq_proof_cache.sh: a proof covers a superset-or-equal test list only.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
cd "$tmp/repo"
git config user.email t@t; git config user.name t
mkdir -p tools
cp "$here/tools/dq_gate_retry.sh" tools/
cp "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_proof_cache.sh" tools/
echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
# like the real gates' in-job baseline shrink: a tracked edit that is left behind when the gate fails afterwards
echo "$*" >>"${DQ_STUB_ARGS:-/dev/null}"
echo shrunk >>tools/ci/x_baseline.txt
if [ -n "${DQ_STUB_USAGE_FAIL:-}" ] && grep -rq USAGEFAIL lanes 2>/dev/null; then . tools/dq_gate_retry.sh; echo x >"$DQ_STUB_ARGS.l"; gate_ensure_result "$DQ_STUB_ARGS.l" 2; exit 1; fi
if grep -rq BAD lanes 2>/dev/null; then echo "stub gates: BAD present"; exit 1; fi
git show HEAD:tools/ci/x_baseline.txt >tools/ci/x_baseline.txt
echo "stub gates: ok"
STUB
mkdir -p tools/ci lanes; echo base >tools/ci/x_baseline.txt; echo base >lanes/base.txt; echo x >shared.txt
git add -A; git commit -q -m init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
mk() { # <branch> <file> <content> [shared-line]
	git switch -q -c "$1" origin/master
	echo "$3" >"lanes/$2"
	[ -z "${4:-}" ] || echo "$4" >shared.txt
	git add -A; git commit -q -m "$1"
	git switch -q --detach origin/master
}
git switch -q --detach origin/master
mk la a.txt fine; mk lb b.txt BAD; mk lc c.txt fine; mk ld d.txt fine "shared-d"; mk le e.txt fine "shared-e"

run() { bash tools/dq_merge_batch.sh --lanes "$1" >"$tmp/out.log" 2>&1; echo $?; }
rc="$(run "la,lc")"
check "a clean batch merges every lane" '[ "$rc" = 0 ] && git merge-base --is-ancestor la rewrite/integ-current && git merge-base --is-ancestor lc rewrite/integ-current'
rc="$(run "la,lb,lc")"
check "one bad lane is bounced alone" '[ "$rc" = 1 ] && grep -q "BOUNCED: lb" "$tmp/out.log" && git merge-base --is-ancestor la rewrite/integ-current && git merge-base --is-ancestor lc rewrite/integ-current && ! git merge-base --is-ancestor lb rewrite/integ-current'
check "a failed attempt's tracked edit never reaches the next attempt" '! grep -q REFUSED "$tmp/out.log" && grep -q "failed gate left a tracked edit: tools/ci/x_baseline.txt restored" "$tmp/out.log" && [ -z "$(git status --porcelain --untracked-files=no)" ]'
# a dirty tree at the start of a batch is logged and cleaned, not refused
echo stray >>tools/ci/x_baseline.txt
rc="$(run "la")"
check "a dirty start is cleaned, not refused" '[ "$rc" = 0 ] && grep -q "start dirty: tools/ci/x_baseline.txt restored" "$tmp/out.log" && [ -z "$(git status --porcelain --untracked-files=no)" ]'
rc="$(run "lb")"
check "a lone bad lane leaves the branch at origin/master" '[ "$rc" = 1 ] && [ "$(git rev-parse rewrite/integ-current)" = "$(git rev-parse origin/master)" ]'
rc="$(run "ld,le,la")"
check "a conflicting lane is bounced, the rest merge" '[ "$rc" = 1 ] && grep -q "BOUNCED: le" "$tmp/out.log" && git merge-base --is-ancestor ld rewrite/integ-current && git merge-base --is-ancestor la rewrite/integ-current'

# a test-phase failure that is not a cap (here: an unknown test name, exit 2, no result line) must not be read as a cap, and the
# tests of a lane that is not in the attempt must not reach the gate (the train bounced healthy lanes both ways)
mk lu u.txt USAGEFAIL
export DQ_STUB_ARGS="$tmp/stub.args" DQ_STUB_USAGE_FAIL=1
: >"$DQ_STUB_ARGS"
rc="$(bash tools/dq_merge_batch.sh --lanes "lu" --lane-tests "lu=dq_t_u" >"$tmp/out.log" 2>&1; echo $?)"
check "an exit-2 test failure is a gate failure, not a cap" '[ "$rc" = 1 ] && ! grep -q "hit its wall-clock cap" "$tmp/out.log" && ! grep -q "do not fit" "$tmp/out.log" && grep -q "gates failed alone" "$tmp/out.log" && grep -q "^BATCH_CAPPED: $" "$tmp/out.log"'
check "the fallback result line does not contain the cap marker" '! grep -q "FOCUSED RUN CAPPED" "$tmp/out.log"'
unset DQ_STUB_USAGE_FAIL
: >"$DQ_STUB_ARGS"
rc="$(bash tools/dq_merge_batch.sh --lanes "ld,le,la" --lane-tests "ld=dq_t_d" --lane-tests "le=dq_t_e" --lane-tests "la=dq_t_a" >"$tmp/out.log" 2>&1; echo $?)"
check "a bounced lane's tests are not sent to the gate" '[ "$rc" = 1 ] && grep -q "dq_t_d" "$DQ_STUB_ARGS" && grep -q "dq_t_a" "$DQ_STUB_ARGS" && ! grep -q dq_t_e "$DQ_STUB_ARGS"'
unset DQ_STUB_ARGS

# A bisect that only gets one attempt per cycle (the deadline is already past; the first real attempt of a run is still allowed) is
# resumed from the saved verdicts: over successive cycles the bad lane of six is bounced and the other five land.
for n in 1 2 3 4 5 6; do if [ "$n" = 4 ]; then mk "m$n" "m$n.txt" BAD; else mk "m$n" "m$n.txt" fine; fi; done
export DQ_BATCH_CACHE="$tmp/bisect.cache" DQ_BATCH_DEADLINE=1
set_lanes="m1 m2 m3 m4 m5 m6"; cycles=0; bounced_all=""; deferred_bad=0
while [ -n "$set_lanes" ] && [ "$cycles" -lt 12 ]; do
	cycles=$((cycles + 1))
	bash tools/dq_merge_batch.sh --lanes "${set_lanes// /,}" >"$tmp/cyc$cycles.log" 2>&1
	good="$(sed -n 's/^BATCH_GOOD: //p' "$tmp/cyc$cycles.log" | tail -n 1)"
	bounced_all="$bounced_all $(sed -n 's/^BATCH_BOUNCED: \([^|]*\)|.*/\1/p' "$tmp/cyc$cycles.log" | tr '\n' ' ')"
	set_lanes="$(sed -n 's/^BATCH_DEFERRED: //p' "$tmp/cyc$cycles.log" | tail -n 1)"
	case " $set_lanes " in *" m4 "*) if grep -q '^BATCH_BOUNCED: m4|' "$tmp/cyc$cycles.log"; then deferred_bad=1; fi ;; esac
	if [ -n "$good" ]; then git push -q origin rewrite/integ-current:master 2>/dev/null; git fetch -q origin; fi
done
unset DQ_BATCH_CACHE DQ_BATCH_DEADLINE
check "a bisect cut to one attempt per cycle still ends" '[ -z "$set_lanes" ] && [ "$cycles" -lt 12 ]'
check "the bad lane is bounced, never deferred" 'case " $bounced_all " in *" m4 "*) true ;; *) false ;; esac && [ "$deferred_bad" = 0 ]'
check "the five good lanes landed over the cycles" 'for n in 1 2 3 5 6; do git merge-base --is-ancestor "m$n" origin/master || exit 1; done; ! git merge-base --is-ancestor m4 origin/master'
check "a later cycle resumed from saved verdicts" 'grep -q "resuming the bisect" "$tmp/cyc2.log"'

# the proof cache
. tools/dq_proof_cache.sh
export DQ_PROOF_DIR="$tmp/proofs"
proof_store T1 m1 "dq_boot_gate dq_a dq_b" 3 0 0 0 0 ""
check "a proof covers a subset of its tests" '[ -n "$(proof_find T1 0 0 dq_a dq_boot_gate)" ]'
check "a proof does not cover a test it did not run" '! proof_find T1 0 0 dq_a dq_zzz >/dev/null'
check "a proof without tgui does not cover a tgui batch" '! proof_find T1 1 0 dq_a >/dev/null'
proof_alias T1 T2
check "an alias covers the second tree" '[ -n "$(proof_find T2 0 0 dq_b)" ]'

[ "$fail" -eq 0 ] && echo "test_merge_batch: all passed" || echo "test_merge_batch: FAILED"
exit "$fail"
