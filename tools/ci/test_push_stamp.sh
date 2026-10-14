#!/usr/bin/env bash
# Self-test of tools/dq_push_stamp.sh's stamp carry-over across a re-merge, in a scratch repository (no network, no worktree).
#
#   bash tools/ci/test_push_stamp.sh      # prints PASS/FAIL per case, exit 1 on any failure
#
# Cases:
#   1. lane and master both change look_keys.txt (a regenerated file) and different code files: the trial merge conflicts only in
#      look_keys.txt, so the lane's stamp carries across the merge commit that took a regenerated look_keys.txt.
#   2. lane and master change the same line of the same code file: a real conflict, refused.
#   3. lane and master change different lines of the same code file (a clean merge, but an overlap the stamp depends on): refused.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

g() { git -C "$tmp/repo" "$@"; }
commit_tree() { # <parent...> -- message on stdin: commit the current index of the scratch repo
	local tree parents=()
	tree="$(g write-tree)"
	for p in "$@"; do parents+=(-p "$p"); done
	echo "c" | g commit-tree "$tree" "${parents[@]}"
}
put() { # <commit> <path> <content>: a commit on <commit> with <path> set
	local base="$1" path="$2" content="$3"
	g read-tree "$base"
	local blob
	blob="$(printf '%s\n' "$content" | g hash-object -w --stdin)"
	g update-index --add --cacheinfo "100644,$blob,$path"
	commit_tree "$base"
}
stamp() { # <commit> <master base>
	g notes --ref=lane-ready add -f -m "{\"version\":1,\"branch\":\"t\",\"branch_commit\":\"$1\",\"tested_commit\":\"$1\",\"master_commit\":\"$2\",\"tests\":[],\"covers\":[],\"ok\":true,\"passed\":1,\"failed\":0,\"new_failed\":0}" "$1"
}
merge_with() { # <lane> <master> <path=content for the regenerated look keys>: a merge commit whose tree is the clean side plus the keys
	local lane="$1" master="$2" keys="$3" out tree
	out="$(g merge-tree --write-tree "$lane" "$master" 2>/dev/null)"
	tree="$(head -n 1 <<<"$out")"
	g read-tree "$tree"
	local blob
	blob="$(printf '%s\n' "$keys" | g hash-object -w --stdin)"
	g update-index --add --cacheinfo "100644,$blob,code/modules/unit_tests/snapshots/look_keys.txt"
	commit_tree "$lane" "$master"
}
check() { # <name> <expect: STAMPED|UNSTAMPED> <commit>
	local verdict
	verdict="$(cd "$tmp/repo" && bash tools/dq_push_stamp.sh "$3" 2>&1)"
	if [[ "$verdict" == "$2"* ]]; then
		echo "PASS $1"
	else
		echo "FAIL $1: expected $2, got: $verdict"
		fail=1
	fi
}

mkdir -p "$tmp/repo"
git init -q "$tmp/repo"
g config user.email t@t
g config user.name t
mkdir -p "$tmp/repo/tools/ci"
cp "$here/tools/dq_push_stamp.sh" "$here/tools/dq_lane_check.js" "$tmp/repo/tools/"
printf 'tools/analyze/\n' >"$tmp/repo/tools/ci/lane_ready_global.txt"
g add -A
base0="$(commit_tree)"
base="$(put "$base0" code/modules/unit_tests/snapshots/look_keys.txt "keys v0")"
base="$(put "$base" code/a/one.dm "one")"
base="$(put "$base" code/b/two.dm "two")"
g update-ref refs/heads/main "$base"

# 1. both sides touch look_keys.txt only besides disjoint code.
lane="$(put "$base" code/a/one.dm "one changed")"
lane="$(put "$lane" code/modules/unit_tests/snapshots/look_keys.txt "keys lane")"
stamp "$lane" "$base"
master="$(put "$base" code/b/two.dm "two changed")"
master="$(put "$master" code/modules/unit_tests/snapshots/look_keys.txt "keys master")"
g update-ref refs/remotes/origin/master "$master"
m="$(merge_with "$lane" "$master" "keys regenerated")"
check "regenerated-only conflict carries the stamp" STAMPED "$m"

# 2. a real conflict on the same line.
lane2="$(put "$base" code/b/two.dm "two from the lane")"
stamp "$lane2" "$base"
m2_out="$(g merge-tree --write-tree "$lane2" "$master" 2>/dev/null | head -n 1)"
g read-tree "$m2_out"
m2="$(commit_tree "$lane2" "$master")"
check "a code conflict is refused" UNSTAMPED "$m2"

# 3. clean merge but master changed the lane's own directory.
lane3="$(put "$base" code/b/three.dm "three")"
stamp "$lane3" "$base"
m3="$(merge_with "$lane3" "$master" "keys regenerated")"
check "an overlap with the lane's directory is refused" UNSTAMPED "$m3"

exit "$fail"
