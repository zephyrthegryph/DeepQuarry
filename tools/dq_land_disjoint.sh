#!/usr/bin/env bash
# Accept a stamped lane onto a moved master with no compile and no test world, when the move cannot have touched what the lane proved.
#
#   bash tools/dq_land_disjoint.sh <lane-branch>      # run in the lane's worktree, on that branch (tools/dq_land.sh calls it)
#
# Exit 0: accepted. origin/master was merged into the lane (tools/dq_merge_master.sh), `analyze gen` and `check_ratchets --changed-only` passed
#         on the result, the merged tree got a proof (inheriting origin/master's own proof of the smoke set) and a lane-ready note, so
#         dq_land.sh fast-forwards it with nothing re-run. Exit 1: not eligible or a check failed; the reason is printed ("== land-disjoint:")
#         and the caller keeps the normal re-proof (dq_lane_ready.sh --lite).
# Eligible only when ALL hold:
#   1. the lane tip carries a passing lane-ready stamp and tools/dq_lane_check.js --lite says VALID (master changed none of the lane's files,
#      directories, tests, snapshots, covers or tools/ci/lane_ready_global.txt paths);
#   2. every commit master gained since the stamp's master base was itself landed through a proved gate: a lane-ready / merge-gates /
#      light-batch note on it, a merge whose merged-in parent carries one, or a docs/changelog-only commit;
#   3. the file sets are disjoint (explicit intersection), neither side touched tools/ci/land_disjoint_global.txt paths, and if both sides edited
#      deepquarry.dme neither edited a code\__defines include (load order);
#   4. git merge-tree says the merge is clean, and origin/master's own tree carries a proof covering the smoke set.
# DQ_LAND_DISJOINT=0 turns it off. A failed fast check after the merge leaves the (already merged) lane for the normal re-proof.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. tools/dq_git_safe.sh
. tools/dq_proof_cache.sh
branch="${1:-$(git symbolic-ref -q --short HEAD)}"
tmpd="${TMPDIR:-/tmp}"
say() { echo "== land-disjoint: $*"; }
no() { say "NOT accepted: $* -> the normal re-proof applies"; exit 1; }
[ "${DQ_LAND_DISJOINT:-1}" != "0" ] || no "DQ_LAND_DISJOINT=0"

git fetch -q origin 2>/dev/null
git fetch -q origin +refs/notes/lane-ready:refs/notes/lane-ready 2>/dev/null
git fetch -q origin +refs/notes/merge-gates:refs/notes/merge-gates 2>/dev/null
git fetch -q origin +refs/notes/light-batch:refs/notes/light-batch 2>/dev/null
tip="$(git rev-parse "$branch^{commit}")" || no "no such branch $branch"
mtip="$(git rev-parse origin/master)"
[ "$(git rev-parse HEAD)" = "$tip" ] || no "the worktree is not on $branch"

json_field() { # <field> reads JSON on stdin
	node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const v=JSON.parse(s)[process.argv[1]];console.log(Array.isArray(v)?v.map(t=>t.replace(/^\/datum\/unit_test\//,"")).join(" "):(v||""))})' "$1"
}

# 1. the stamp and the lane check
verdict="$(node tools/dq_lane_check.js --lite "$branch" 2>/dev/null)"
case "$verdict" in LITE*) ;; *) no "${verdict:-no lane-check verdict}" ;; esac
stamp_commit=""; stamp_json=""
for c in $(git rev-list -n 40 "$tip"); do
	if n="$(git notes --ref=lane-ready show "$c" 2>/dev/null)" && [ -n "$n" ]; then stamp_commit="$c"; stamp_json="$n"; break; fi
done
[ -n "$stamp_json" ] || no "no lane-ready stamp found"
printf '%s' "$stamp_json" | grep -q '"ok":true' || no "the stamp is not ok"
base="$(printf '%s' "$stamp_json" | json_field master_commit)"
[ -n "$base" ] && git merge-base --is-ancestor "$base" origin/master 2>/dev/null || no "the stamp's master base ${base:0:10} is not in origin/master"
say "stamp on ${stamp_commit:0:10}, master base ${base:0:10}, master now ${mtip:0:10}; ${verdict%% tests=*}"

# 2. every master commit since the base was landed through a proved gate
stamped_note() { local r; for r in lane-ready merge-gates light-batch; do git notes --ref="$r" show "$1" 2>/dev/null | grep -q '"ok":true' && return 0; done; return 1; }
docs_only() {
	local f
	while IFS= read -r f; do
		case "$f" in doc/*|html/changelogs/*|*.md|tools/ci/known_failures.txt) ;; *) return 1 ;; esac
	done < <(git diff-tree --no-commit-id --name-only -r -m --first-parent "$1")
	return 0
}
count=0
while IFS= read -r c; do
	[ -n "$c" ] || continue
	count=$((count + 1))
	stamped_note "$c" && continue
	read -r -a par <<<"$(git rev-list --parents -n 1 "$c" | cut -d' ' -f2-)"
	if [ "${#par[@]}" -ge 2 ]; then
		okp=0
		for p in "${par[@]:1}"; do stamped_note "$p" && okp=1; done
		[ "$okp" -eq 1 ] && continue
	fi
	docs_only "$c" && continue
	no "master commit ${c:0:10} ($(git log -1 --format=%s "$c" | cut -c1-60)) carries no proof stamp"
done < <(git rev-list --first-parent "$base..origin/master")
say "all $count master commit(s) since the base were landed through a proved gate"

# 3. disjoint files, global paths, deepquarry.dme
fm="$tmpd/dq_ld_m.$$"; fl="$tmpd/dq_ld_l.$$"
trap 'rm -f "$fm" "$fl"' EXIT
git diff --name-only "$base" origin/master | grep -v '^code/modules/unit_tests/snapshots/op_bases/' | sort -u >"$fm"
git diff --name-only "$base" "$tip" | grep -v '^code/modules/unit_tests/snapshots/op_bases/' | sort -u >"$fl"
both="$(comm -12 "$fm" "$fl" | grep -v '^deepquarry.dme$' | head -3 | tr '\n' ' ')"
[ -z "$both" ] || no "both sides changed: $both"
mapfile -t globals < <(grep -v '^\s*#' tools/ci/land_disjoint_global.txt | sed '/^\s*$/d')
for side in m l; do
	file="$fm"; who=master
	[ "$side" = l ] && { file="$fl"; who="the lane"; }
	while IFS= read -r f; do
		for g in "${globals[@]}"; do
			case "$f" in "$g"*) no "$who changed the global path $f" ;; esac
		done
	done <"$file"
done
if grep -qx 'deepquarry.dme' "$fm" && grep -qx 'deepquarry.dme' "$fl"; then
	if { git diff -U0 "$base" origin/master -- deepquarry.dme; git diff -U0 "$base" "$tip" -- deepquarry.dme; } | grep -E '^[+-]#include' | grep -qi '__defines'; then
		no "both sides edited deepquarry.dme and one touched a code\\__defines include (load order)"
	fi
	say "both sides edited deepquarry.dme, none of it a __defines include; the merge decides if the hunks collide"
fi
say "file sets disjoint ($(wc -l <"$fl") lane file(s), $(wc -l <"$fm") master file(s)), no global path touched"

# 4. clean merge and a proved master
proof_merge_tree origin/master "$branch" >/dev/null || no "git merge-tree: the merge conflicts"
mapfile -t smoke < <(proof_smoke_tests)
mtree="$(git rev-parse "$mtip^{tree}")"
proof_find "$mtree" 0 0 "${smoke[@]}" >/dev/null || no "origin/master's tree ${mtree:0:10} has no proof covering the smoke set"

# the fast check: merge, generate, changed-only ratchets
say "merging origin/master into $branch, then analyze gen + check_ratchets --changed-only (no compile, no test world)"
bash tools/dq_merge_master.sh || { git merge --abort >/dev/null 2>&1; no "the merge did not complete"; }
git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then no "the merge left uncommitted changes"; fi
head="$(git rev-parse HEAD)"
git merge-base --is-ancestor origin/master "$head" || no "HEAD does not contain origin/master after the merge"
tools/build/build.sh gen >/dev/null 2>&1 || no "analyze gen failed on the merged tree (HEAD ${head:0:10} is the merge)"
bash tools/ci/check_ratchets.sh --changed-only || no "check_ratchets --changed-only failed on the merged tree (HEAD ${head:0:10} is the merge)"
git update-index -q --refresh >/dev/null 2>&1
git diff --quiet || no "the checks changed tracked files"

# record: a proof for the merged tree that inherits master's proof, and a lane-ready note on the merge so the push is a fast-forward
tests="$(printf '%s' "$stamp_json" | json_field tests)"
proof_store "$(proof_tree HEAD)" "$mtip" "$tests" 0 0 0 0 0 "" "$mtree"
new_json="$(printf '%s' "$stamp_json" | HEAD_SHA="$head" MASTER="$mtip" STAMPC="$stamp_commit" node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);j.branch_commit=process.env.HEAD_SHA;j.tested_commit=process.env.HEAD_SHA;j.master_commit=process.env.MASTER;j.disjoint_accept={stamp_commit:process.env.STAMPC,created:new Date().toISOString()};console.log(JSON.stringify(j))})')"
git notes --ref=lane-ready add -f -m "$new_json" HEAD || no "could not write the lane-ready note"
if [ "${DQ_LANE_NOTES_PUSH:-1}" != "0" ]; then
	for attempt in 1 2 3; do
		git push -q origin refs/notes/lane-ready:refs/notes/lane-ready 2>/dev/null && break
		git fetch -q origin +refs/notes/lane-ready:refs/notes/lane-ready-remote 2>/dev/null && git notes --ref=lane-ready merge -s cat_sort_uniq refs/notes/lane-ready-remote >/dev/null 2>&1
	done
fi
say "ACCEPTED $branch ${head:0:10} on master ${mtip:0:10}: disjoint from $count landed master commit(s); stamp ${stamp_commit:0:10} carried, tests (${tests:-none}) not re-run"
exit 0
