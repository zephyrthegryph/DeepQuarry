#!/usr/bin/env bash
# Self-test of the lite re-proof rules (tools/dq_lane_check.js --lite, tools/dq_proof_cache.sh inherits) in a scratch repository:
# a lane whose stamp is valid against a moved master gets boot gate + its own tests + the tests of the lanes that landed since;
# a master that touched the lane's files, or did not move, gets no lite verdict; a proof that inherits master's proof covers the
# selectors master's proof ran, but only while master's proof is clean.
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
mkdir -p tools/ci lane other
cp "$here/tools/dq_lane_check.js" "$here/tools/dq_proof_cache.sh" tools/
: >tools/ci/lane_ready_global.txt
echo base >lane/base.txt; echo base >other/base.txt
git add -A; git commit -q -m b0; git branch -M master; git push -q origin master 2>/dev/null
b0="$(git rev-parse HEAD)"
note() { # <commit> <master> <branch> <tests-json>
	git notes --ref=lane-ready add -f -m "{\"version\":1,\"branch\":\"$3\",\"branch_commit\":\"$1\",\"master_commit\":\"$2\",\"tests\":$4,\"covers\":[],\"ok\":true,\"passed\":3,\"failed\":0,\"new_failed\":0}" "$1"
}
git switch -q -c lane-a master
echo change >lane/a.txt; git add -A; git commit -q -m "lane a"
note "$(git rev-parse HEAD)" "$b0" lane-a '["t_lane"]'
# master moves by another lane's landing (a different directory), which carries its own stamp
git switch -q master
echo y >other/y.txt; git add -A; git commit -q -m "lane b landed"
note "$(git rev-parse HEAD)" "$b0" lane-b '["t_other","t_other2"]'
git push -q origin master 2>/dev/null; git fetch -q origin

out="$(node tools/dq_lane_check.js --lite lane-a)"
check "a valid stamp on a moved master is lite" 'echo "$out" | grep -q "^LITE "'
check "the lite list is boot gate + the lane's tests + the tests of what landed" 'echo "$out" | grep -q "tests=dq_boot_gate,t_lane,t_other,t_other2$"'

# master touches the lane's directory: not lite
git switch -q master
echo z >lane/z.txt; git add -A; git commit -q -m "touches the lane directory"
git push -q origin master 2>/dev/null; git fetch -q origin
out="$(node tools/dq_lane_check.js --lite lane-a)"; rc=$?
check "master changing the lane's directory is no lite verdict" '[ "$rc" = 1 ] && echo "$out" | grep -q "^NOLITE .*INVALID"'

# an unmoved master: nothing to re-prove
git switch -q -c lane-c origin/master
echo c >lane/c.txt; git add -A; git commit -q -m "lane c"
note "$(git rev-parse HEAD)" "$(git rev-parse origin/master)" lane-c '["t_c"]'
out="$(node tools/dq_lane_check.js --lite lane-c)"; rc=$?
check "a stamp on the current master needs no re-proof" '[ "$rc" = 1 ] && echo "$out" | grep -q "base is current"'

# proofs that inherit
export DQ_PROOF_DIR="$tmp/proofs"
. tools/dq_proof_cache.sh
proof_store master_tree m "smoke_a smoke_b" 2 0 0 0 0 ""
proof_store lane_tree m "t_lane" 1 0 0 0 0 "" master_tree
check "a proof that inherits covers master's selectors" 'proof_find lane_tree 0 0 smoke_a t_lane smoke_b >/dev/null'
check "...but not a selector neither ran" '! proof_find lane_tree 0 0 smoke_c >/dev/null'
proof_store dirty_master m "smoke_a" 1 1 1 0 0 ""
proof_store lane2 m "t_lane" 1 0 0 0 0 "" dirty_master
check "a proof inheriting a failed master proof gets nothing from it" '! proof_find lane2 0 0 smoke_a >/dev/null'
proof_store lane3 m "t_lane" 1 0 0 0 0 "" no_such_tree
check "a missing inherited proof gets nothing" '! proof_find lane3 0 0 smoke_a >/dev/null'

[ "$fail" -eq 0 ] && echo "test_lane_lite: all passed" || { echo "test_lane_lite: FAILED"; exit 1; }
