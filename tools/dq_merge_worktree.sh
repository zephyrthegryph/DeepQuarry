#!/usr/bin/env bash
# One long-lived worktree for merge batches: E:/projects/dq-wt/merge-base on branch rewrite/integ-current.
#
#   bash tools/dq_merge_worktree.sh                # create it once, or move it to origin/master; stdout is its path
#   bash tools/dq_merge_worktree.sh --print-path   # just the path (no fetch, no changes)
#   bash tools/dq_merge_worktree.sh --warm         # also run `build.sh gen` there (analyzer + generated files)
#   bash tools/dq_merge_worktree.sh --discard-previous   # the last batch never reached master: keep its tip as a
#                                                        # rewrite/integ-prev-<stamp> branch and move on
#
# Why: a fresh worktree checks out about 24k files (up to 30 minutes on this machine) and starts with cold caches. This
# one is never removed, so icons/gen, verdigris/target (or the DLL cache), the analyze binary, data/dmb-cache and
# node_modules stay warm, and a batch starts with a fast-forward-sized checkout instead.
#
# Each call: git fetch, then verify the worktree is clean and has nothing unpushed, then `git switch -C
# rewrite/integ-current origin/master` inside it (switch is allowed; checkout/reset/restore/stash are not, and no
# discarding flag is ever passed, so a dirty or conflicted tree makes git refuse instead of losing work). It aborts,
# changing nothing, when:
#   - the worktree has tracked changes or untracked non-ignored files (a half-finished batch),
#   - a merge, rebase, cherry-pick or revert is in progress there,
#   - rewrite/integ-current holds commits that origin/master does not (the previous batch was never pushed; or another
#     agent's batch is running in it right now). Push it, or pass --discard-previous.
# Only one merge batch uses the worktree at a time. Run the batch inside the printed path:
#   cd "$(bash tools/dq_merge_worktree.sh)" && git merge --no-ff <branch> ... && bash tools/dq_merge_gates.sh
# Nothing here runs checkout, reset, restore, stash or cherry-pick, or deletes any lock file.
set -uo pipefail

WT="${DQ_MERGE_WT:-E:/projects/dq-wt/merge-base}"
BRANCH="rewrite/integ-current"

die() { echo "dq_merge_worktree: ABORT: $*" >&2; exit 1; }

warm=0
discard=0
for arg in "$@"; do
	case "$arg" in
		--print-path) echo "$WT"; exit 0 ;;
		--warm) warm=1 ;;
		--discard-previous) discard=1 ;;
		-h|--help) sed -n '2,26p' "$0"; exit 0 ;;
		*) die "unknown argument: $arg" ;;
	esac
done

here="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run this inside a DeepQuarry checkout"
git -C "$here" fetch -q origin || die "git fetch failed"
git -C "$here" rev-parse -q --verify origin/master >/dev/null || die "no origin/master"
target="$(git -C "$here" rev-parse origin/master)"

common() { (cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P); }
registered() { [ "$(common "$WT")" = "$(common "$here")" ]; }

if [ ! -d "$WT/.git" ] && [ ! -f "$WT/.git" ]; then
	[ -z "$(ls -A "$WT" 2>/dev/null)" ] || die "$WT exists and is not a worktree; move it away"
	mkdir -p "$(dirname "$WT")"
	echo >&2 "dq_merge_worktree: creating $WT (one-time checkout of the whole tree, slow)"
	if git -C "$here" show-ref -q --verify "refs/heads/$BRANCH"; then
		# The branch exists (an earlier worktree was pruned): attach it, then move it below.
		git -C "$here" worktree add --force "$WT" "$BRANCH" || die "git worktree add failed"
	else
		git -C "$here" worktree add -b "$BRANCH" "$WT" origin/master || die "git worktree add failed"
	fi
	warm=1
fi
registered || die "$WT is not a registered worktree of this repository (git worktree list)"

gd="$(git -C "$WT" rev-parse --git-dir)"
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
	[ -e "$gd/$marker" ] || [ -e "$WT/$gd/$marker" ] && die "$marker present in $WT: a merge or rebase is in progress; finish it first"
done
git -C "$WT" update-index -q --refresh >/dev/null 2>&1
dirty="$(git -C "$WT" status --porcelain --untracked-files=normal | head -10)"
if [ -n "$dirty" ]; then
	echo "$dirty" >&2
	die "$WT is not clean (listed above). A batch is unfinished there; commit and push it, or clean it by hand."
fi

cur="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
if [ "$cur" = "$BRANCH" ]; then
	ahead="$(git -C "$WT" rev-list --count "origin/master..HEAD")"
	if [ "$ahead" -gt 0 ]; then
		if [ "$discard" -ne 1 ]; then
			git -C "$WT" log --oneline -5 "origin/master..HEAD" >&2
			die "$BRANCH has $ahead commit(s) origin/master does not (listed above): the previous batch was not pushed, or a batch is running in it. Push it, or rerun with --discard-previous."
		fi
		keep="rewrite/integ-prev-$(date +%Y%m%dT%H%M%S)"
		git -C "$WT" branch "$keep" HEAD || die "could not save the previous tip as $keep"
		echo >&2 "dq_merge_worktree: previous tip kept as $keep"
	fi
fi

git -C "$WT" switch -q -C "$BRANCH" origin/master || die "git switch failed; nothing was discarded"
if [ "$warm" -eq 1 ]; then
	echo >&2 "dq_merge_worktree: warming gen (analyze binary, generated files)"
	(cd "$WT" && tools/build/build.sh gen >&2) || echo "dq_merge_worktree: warm-up gen failed (the batch's gate will report it)" >&2
fi
echo >&2 "MERGE WORKTREE READY: $WT ($BRANCH at ${target:0:12})"
echo "$WT"
