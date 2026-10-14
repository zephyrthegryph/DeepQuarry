#!/usr/bin/env bash
# Builds a scratch repo with a lane-ready stamp and drives tools/dq_lane_check.js through the master moves that must keep it and the
# ones that must invalidate it: a changelog-only or doc-only move (kept, files named), a data/bench output move (kept), a code move in
# a directory the branch changed or a global path (invalidated, files named), and a doc a tool reads (invalidated).
#
#   bash tools/ci/test_lane_check_docs.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d "$ROOT/data/lane-check-test.XXXXXX" 2>/dev/null || { mkdir -p "$ROOT/data"; mktemp -d "$ROOT/data/lane-check-test.XXXXXX"; })"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

R="$T/r"
git init -q -b master "$R"
cd "$R" || exit 1
mkdir -p tools/ci code/game html/changelogs doc/rewrite data/bench
cp "$ROOT/tools/dq_lane_check.js" tools/
cp "$ROOT/tools/ci/lane_ready_doc_reads.txt" tools/ci/
printf 'tools/analyze/\n' >tools/ci/lane_ready_global.txt
echo a >code/game/a.dm
echo a >code/game/b.dm
echo d >doc/rewrite/reads_closure_newly_visible.md
echo d >doc/rewrite/guide.md
git add -A && git commit -qm base
base="$(git rev-parse HEAD)"
git switch -q -c lane
echo lane >>code/game/a.dm && git commit -qam "lane work"
tip="$(git rev-parse HEAD)"
git notes --ref=refs/notes/lane-ready add -m "{\"ok\":true,\"failed\":0,\"master_commit\":\"$base\",\"tests\":[\"dq_nothing\"],\"branch\":\"lane\"}" "$tip"
git switch -q master

check() { # description expected-verdict expected-text
	local out
	out="$(node tools/dq_lane_check.js --master master lane 2>&1)"
	if echo "$out" | grep -q "LANE lane $2" && echo "$out" | grep -q -- "$3"; then ok "$1"; else fail "$1: $out"; fi
}
move() { git add -A && git commit -qm "$1"; }

echo c >html/changelogs/x.yml; echo g >doc/rewrite/guide.md; move "changelog and doc"
check "a changelog and doc-only master move keeps the stamp, naming the files" VALID "2 changelog/doc/data file(s) ignored (doc/rewrite/guide.md, html/changelogs/x.yml"

echo o >data/bench/run.json; echo r >README.md; move "bench output and root markdown"
check "bench output and root markdown are ignored too" VALID "4 changelog/doc/data file(s) ignored"

echo x >code/game/c.dm; move "code in a directory the branch changed"
check "a code move in a directory the branch changed invalidates, naming the file" INVALID "code/game/c.dm (a directory the branch changed)"

# back to the doc-only state on a second scratch master
git branch -q m2 "$base"
git switch -q m2
echo r2 >>doc/rewrite/reads_closure_newly_visible.md; move "a doc a tool reads"
out="$(node tools/dq_lane_check.js --master m2 lane 2>&1)"
echo "$out" | grep -q "INVALID.*reads_closure_newly_visible.md (a doc a tool reads" && ok "a doc a tool reads invalidates" || fail "read doc: $out"

git switch -q -c m3 "$base"
mkdir -p tools/analyze && echo g >tools/analyze/x.rs; move "global path"
out="$(node tools/dq_lane_check.js --master m3 lane 2>&1)"
echo "$out" | grep -q "INVALID.*tools/analyze/x.rs (a global path" && ok "a global path invalidates" || fail "global: $out"

[ "$fails" -eq 0 ] && { echo "test_lane_check_docs: ok"; exit 0; }
echo "test_lane_check_docs: $fails FAILED"
exit 1
