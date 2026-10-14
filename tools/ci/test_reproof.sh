#!/usr/bin/env bash
# Test for the re-proof rule (tools/dq_reproof_source.sh; used by tools/dq_push_master.sh and tools/dq_merge_gates.sh --reproof): a merge of
# master into a lane whose stamp is on exactly its tip is eligible, and yields the lane's full stamped test list; a lane whose own commits
# changed after the stamp, a plain commit, or a stamp with no test list is refused. The scratch repo lives under data/. The gates themselves
# (a test world) are not run here; the wiring of --reproof into the gates and the push is checked by grep.
#
#   bash tools/ci/test_reproof.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$ROOT/data"
T="$(mktemp -d "$ROOT/data/reproof-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

git init -q --bare -b master "$T/origin.git"
git clone -q "$T/origin.git" "$T/r" 2>/dev/null
cd "$T/r" || exit 1
git switch -q -c master 2>/dev/null
mkdir -p code tools/analyze
echo a >code/a.dm && git add -A && git commit -qm base && git push -q origin master
base="$(git rev-parse HEAD)"

# a lane with a lane-ready stamp on exactly its tip
git switch -q -c lane
echo l >code/lane.dm && git add -A && git commit -qm "lane"
tip="$(git rev-parse HEAD)"
git notes --ref=lane-ready add -m "{\"ok\":true,\"branch_commit\":\"$tip\",\"master_commit\":\"$base\",\"tests\":[\"dq_a\",\"/datum/unit_test/dq_b/*\"]}" "$tip"
# master moves a global path while the lane was being gated
git switch -q master
echo g >tools/analyze/x.rs && git add -A && git commit -qm "master moves a global path" && git push -q origin master
git fetch -q origin
# the merge the push would make
git switch -q -c merge1 lane
git merge -q --no-ff -m "merge master into lane" origin/master
m1="$(git rev-parse HEAD)"

out="$(bash "$ROOT/tools/dq_reproof_source.sh" "$m1" 2>"$T/e1")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sed -n 1p <<<"$out")" = "$tip" ] && ok "a stamped lane merged with a moved master is eligible and names the lane tip" || fail "eligible case: rc=$rc out=$out err=$(cat "$T/e1")"
[ "$(sed -n 2p <<<"$out")" = "dq_a dq_b/*" ] && ok "it returns the lane's full stamped test list" || fail "tests: $out"

# the lane's own commits change after the stamp: no note on its tip, refused
git switch -q -c lane2 lane
echo more >code/lane2.dm && git add -A && git commit -qm "lane commit after the stamp"
git switch -q -c merge2
git merge -q --no-ff -m "merge master into changed lane" origin/master
m2="$(git rev-parse HEAD)"
bash "$ROOT/tools/dq_reproof_source.sh" "$m2" >/dev/null 2>"$T/e2" && fail "a lane changed after its stamp must be refused" || { grep -q "own commits changed" "$T/e2" && ok "a lane whose own commits changed since the stamp is refused" || fail "wrong refusal: $(cat "$T/e2")"; }

# a plain commit
bash "$ROOT/tools/dq_reproof_source.sh" "$tip" >/dev/null 2>"$T/e3" && fail "a non-merge must be refused" || { grep -q "not a two-parent merge" "$T/e3" && ok "a plain commit is refused" || fail "wrong refusal: $(cat "$T/e3")"; }

# a failed stamp
git switch -q -c lane3 lane
echo f >code/f.dm && git add -A && git commit -qm "failed lane"
ftip="$(git rev-parse HEAD)"
git notes --ref=lane-ready add -m "{\"ok\":false,\"branch_commit\":\"$ftip\",\"tests\":[\"dq_a\"]}" "$ftip"
git switch -q -c merge3 && git merge -q --no-ff -m "merge master into failed lane" origin/master
bash "$ROOT/tools/dq_reproof_source.sh" HEAD >/dev/null 2>&1 && fail "a failed stamp must be refused" || ok "a stamp that records a failure is refused"

# a merge-gates stamped batch: the list comes from the note, an old note without one is refused
git switch -q -c batch lane
echo b >code/b.dm && git add -A && git commit -qm "batch"
btip="$(git rev-parse HEAD)"
git notes --ref=merge-gates add -m "{\"kind\":\"merge-gates\",\"commit\":\"$btip\",\"ok\":true,\"tests\":[\"dq_x\",\"dq_y\"]}" "$btip"
git switch -q -c merge4 && git merge -q --no-ff -m "merge master into batch" origin/master
out="$(bash "$ROOT/tools/dq_reproof_source.sh" HEAD 2>/dev/null)" && [ "$(sed -n 2p <<<"$out")" = "dq_x dq_y" ] && ok "a merge-gates batch stamp is re-proved from its note's list" || fail "batch: $out"
git switch -q -c batch2 lane
echo c >code/c.dm && git add -A && git commit -qm "old-style batch"
otip="$(git rev-parse HEAD)"
git notes --ref=merge-gates add -m "{\"kind\":\"merge-gates\",\"commit\":\"$otip\",\"ok\":true}" "$otip"
git switch -q -c merge5 && git merge -q --no-ff -m "merge master into old-style batch" origin/master
bash "$ROOT/tools/dq_reproof_source.sh" HEAD >/dev/null 2>"$T/e5" && fail "an old note with no list must be refused" || { grep -q "names no tests" "$T/e5" && ok "a stamp with no test list is refused" || fail "wrong refusal: $(cat "$T/e5")"; }

# wiring
grep -q -- '--reproof' "$ROOT/tools/dq_merge_gates.sh" && grep -q 'reproof_of' "$ROOT/tools/dq_merge_gates.sh" && ok "the gates take --reproof and record reproof_of in the stamp" || fail "gates wiring"
grep -q 'dq_merge_gates.sh --reproof' "$ROOT/tools/dq_push_master.sh" && grep -q 'dq_reproof_source.sh' "$ROOT/tools/dq_push_master.sh" && ok "the push runs the re-proof instead of refusing" || fail "push wiring"

[ "$fails" -eq 0 ] && { echo "test_reproof: ok"; exit 0; }
echo "test_reproof: $fails FAILED"
exit 1
