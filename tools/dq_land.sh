#!/usr/bin/env bash
# Land the lane you are in on master, in seconds. No gates, no stamps, no queue: test what you judge reasonable first.
#
#   bash tools/dq_land.sh          # from the lane's worktree, everything committed
#
# Fetches, merges origin/master, pushes to master, and on a lost race merges and pushes again.
# Refuses only: a checkout that is not a lane (the main checkout, test-server, play worktrees, master itself), a dirty tree, a merge conflict, and committing
# user save data. A conflict is left in the tree for you to resolve and commit; run this again afterwards. --light is accepted and means nothing.
set -uo pipefail
# Below normal priority, for this script and everything it starts (cargo and rustc, the analyzer, git): the machine is also the user's desktop.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dq_below_normal.sh"
die() { echo "dq_land: REFUSED: $*" >&2; exit 1; }
# The merge drivers (deepquarry.dme, baselines, lint_scopes.toml) are supplied per command; without them a plain merge conflicts on those files.
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh" || die "cannot load dq_git_safe.sh"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git checkout"
root="$(cd "$root" && pwd -W 2>/dev/null || pwd)"
lanes="${DQ_LAND_LANE_ROOT:-E:/projects/dq-wt}"
case "$root" in
	"$lanes"/test-server|"$lanes"/test-server/*|"$lanes"/play|"$lanes"/play-*|"$lanes"/merge-base|"$lanes"/train-base) die "$root is not a lane checkout" ;;
	"$lanes"/*) ;;
	*) die "$root is not under $lanes: lease a lane (bash tools/dq_lane_pool.sh lease <branch>)" ;;
esac
cd "$root" || exit 1
branch="$(git symbolic-ref -q --short HEAD)" || die "a detached HEAD: land from a lane branch"
case "$branch" in master|main) die "you are on $branch: land from a lane branch" ;; esac
git update-index -q --refresh >/dev/null 2>&1
[ -z "$(git status --porcelain --untracked-files=normal | head -n 1)" ] || { git status --short | head -8 >&2; die "the tree is not clean: commit your change first"; }
t0=$(date +%s)
for round in 1 2 3 4 5 6; do
	git fetch -q origin || die "git fetch failed"
	saves="$(git diff --name-only origin/master...HEAD -- 'data/player_saves' 'data/player_saves/*' | head -n 3 | tr '\n' ' ')"
	[ -z "$saves" ] || die "the lane commits user save data ($saves)"
	if git merge-base --is-ancestor HEAD origin/master; then echo "dq_land: $branch is already in origin/master"; exit 0; fi
	if ! git merge-base --is-ancestor origin/master HEAD; then
		git merge -q --no-edit origin/master || die "a merge conflict with master: resolve and commit it, then run this again"
	fi
	sha="$(git rev-parse HEAD)"
	if git push -q origin "$sha:refs/heads/master"; then
		git fetch -q origin
		git merge-base --is-ancestor "$sha" origin/master || die "the push returned 0 but origin/master does not hold ${sha:0:12}"
		echo "dq_land: landed $branch as ${sha:0:12} in $(( $(date +%s) - t0 )) s (round $round)"
		bash "$(dirname "${BASH_SOURCE[0]}")/dq_post_push_check.sh" start 2>/dev/null || true # report only, returns at once
		cat "${DQ_HEALTH_STATE:-E:/dq-cache/health}/MASTER_BROKEN.txt" 2>/dev/null >&2 || true
		exit 0
	fi
	echo "dq_land: lost a race for master (round $round); merging again"
done
die "master kept moving for 6 rounds; run this again"
