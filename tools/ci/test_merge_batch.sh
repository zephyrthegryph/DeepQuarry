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
cp "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_proof_cache.sh" tools/
echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
if grep -rq BAD lanes 2>/dev/null; then echo "stub gates: BAD present"; exit 1; fi
echo "stub gates: ok"
STUB
mkdir lanes; echo base >lanes/base.txt; echo x >shared.txt
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
rc="$(run "lb")"
check "a lone bad lane leaves the branch at origin/master" '[ "$rc" = 1 ] && [ "$(git rev-parse rewrite/integ-current)" = "$(git rev-parse origin/master)" ]'
rc="$(run "ld,le,la")"
check "a conflicting lane is bounced, the rest merge" '[ "$rc" = 1 ] && grep -q "BOUNCED: le" "$tmp/out.log" && git merge-base --is-ancestor ld rewrite/integ-current && git merge-base --is-ancestor la rewrite/integ-current'

# the proof cache
. tools/dq_proof_cache.sh
export DQ_PROOF_DIR="$tmp/proofs"
proof_store T1 m1 "dq_boot_gate dq_a dq_b" 3 0 0 0 0 ""
check "a proof covers a subset of its tests" '[ -n "$(proof_find T1 0 0 dq_a dq_boot_gate)" ]'
check "a proof does not cover a test it did not run" '! proof_find T1 0 0 dq_a dq_zzz >/dev/null'
check "a proof without tgui does not cover a tgui batch" '! proof_find T1 1 0 dq_a >/dev/null'
proof_alias T1 T2
check "an alias covers the second tree" '[ -n "$(proof_find T2 0 0 dq_b)" ]'

# docs/tools-only diffs skip the look pins
git switch -q --detach origin/master; mkdir -p doc tools/ci code; echo d >doc/x.md; echo t >tools/ci/y.sh; git add -A; git commit -q -m docs
check "a docs/tools-only diff touches no DM" '! dq_diff_touches_dm'
echo 'x' >code/z.dm; git add -A; git commit -q -m code
check "a diff with a .dm file touches DM" 'dq_diff_touches_dm'

[ "$fail" -eq 0 ] && echo "test_merge_batch: all passed" || echo "test_merge_batch: FAILED"
exit "$fail"
