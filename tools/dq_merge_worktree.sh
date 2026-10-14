#!/usr/bin/env bash
# One long-lived worktree for merge batches: E:/projects/dq-wt/merge-base on branch rewrite/integ-current.
#
#   bash tools/dq_merge_worktree.sh --lanes "a b"  # take the merge lock (waits, printing who holds it), create the worktree once,
#                                                  # or move it to origin/master; stdout is its path
#   bash tools/dq_merge_worktree.sh --join "c"     # the lock holder adds lanes to its batch (no switch, prints the path)
#   bash tools/dq_merge_worktree.sh --adopt --lanes "a b"   # the owner of an unpushed batch already merged in the worktree takes the lock
#                                                  # for its current HEAD: no switch, no re-merge, no discard (every lane named must be in HEAD)
#   bash tools/dq_merge_worktree.sh --release      # end an abandoned batch and free the lock (--release --force: someone else's)
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
# The merge lock (tools/dq_machine_slots.sh, class merge_base, one slot) makes "only one batch" true: a call takes it before the
# clear check, so two agents cannot both pass the check and merge into the same index. It is held by a detached holder process with a
# heartbeat, across dq_merge_gates.sh, until dq_push_master.sh lands the batch (or the tree is level with origin/master), or --release.
# dq_merge_gates.sh and dq_push_master.sh refuse to run in the merge worktree without it. A crashed holder is reclaimed like a dead
# machine slot. The caller's identity is DQ_MERGE_SESSION, which must be set (the lane branch name); it is never inferred, and the merge tools refuse without it.
# Only one merge batch uses the worktree at a time. Run the batch inside the printed path:
#   cd "$(bash tools/dq_merge_worktree.sh)" && git merge --no-ff <branch> ... && bash tools/dq_merge_gates.sh
# Nothing here runs checkout, reset, restore, stash or cherry-pick, or deletes any lock file.
set -uo pipefail

WT="${DQ_MERGE_WT:-E:/projects/dq-wt/merge-base}"
BRANCH="rewrite/integ-current"

got_lock=0
die() {
	echo "dq_merge_worktree: ABORT: $*" >&2
	# A batch that never got the worktree must not keep the lock.
	if [ "$got_lock" -eq 1 ]; then merge_lock_release >&2; fi
	exit 1
}

warm=0
discard=0
lanes=""
mode="take"
force=""
mode_next=""
for arg in "$@"; do
	if [ -n "$mode_next" ]; then lanes="$arg"; mode_next=""; continue; fi
	case "$arg" in
		--print-path) echo "$WT"; exit 0 ;;
		--warm) warm=1 ;;
		--discard-previous) discard=1 ;;
		--lanes) mode_next=lanes ;;
		--join) mode="join"; mode_next=lanes ;;
		--adopt) mode="adopt" ;;
		--release) mode="release" ;;
		--force) force="--force" ;;
		-h|--help) sed -n '2,36p' "$0"; exit 0 ;;
		*) die "unknown argument: $arg" ;;
	esac
done

[ -z "$mode_next" ] || die "--lanes / --join need a value (the lane branch names, one quoted string)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
# shellcheck source=dq_machine_slots.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
case "$mode" in
	release) merge_lock_release $force; exit $? ;;
	join) [ -n "$lanes" ] || die "--join needs the lanes to add"; merge_lock_join $lanes || exit 1; echo "$WT"; exit 0 ;;
esac
[ -n "$lanes" ] || lanes="unnamed batch"
[ "$mode" != "adopt" ] || [ "$lanes" != "unnamed batch" ] || die "--adopt needs --lanes (the lane branches of your batch that are already merged in the worktree)"

here="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run this inside a DeepQuarry checkout"
merge_lock_acquire $lanes || { rc=$?; { [ "$rc" -eq 3 ] || [ "$rc" -eq 4 ]; } && exit 1; die "could not take the merge lock"; }
got_lock=1

# The lock first: the fetch, the target and the clear check below must all be seen by the batch that owns the worktree.
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

if [ "$mode" = "adopt" ]; then
	[ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "--adopt: $WT is not on $BRANCH"
	[ "$(git -C "$WT" rev-list --count "origin/master..HEAD")" -gt 0 ] || die "--adopt: $BRANCH holds nothing origin/master lacks; there is no batch to adopt (take the worktree normally with --lanes)"
	for lane in $lanes; do
		tip="$(git -C "$WT" rev-parse -q --verify "$lane^{commit}" 2>/dev/null || git -C "$WT" rev-parse -q --verify "origin/$lane^{commit}" 2>/dev/null)" || die "--adopt: lane '$lane' does not resolve to a commit"
		git -C "$WT" merge-base --is-ancestor "$tip" HEAD || die "--adopt: lane '$lane' (${tip:0:12}) is not in the worktree's HEAD; only the owner of a batch merged there can adopt it (merge it normally, or wait for the lock)"
		! git -C "$WT" merge-base --is-ancestor "$tip" origin/master || die "--adopt: lane '$lane' (${tip:0:12}) is already in origin/master, so it is not an unpushed batch in the worktree (nothing to adopt for it)"
	done
	merge_lock_mark_base "$(git -C "$WT" merge-base HEAD origin/master)"
	echo >&2 "MERGE WORKTREE ADOPTED: $WT ($BRANCH at $(git -C "$WT" rev-parse --short=12 HEAD), $(git -C "$WT" rev-list --count "origin/master..HEAD") unpushed commit(s), lanes: $lanes)"
	echo "$WT"
	exit 0
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
merge_lock_mark_base "$(git -C "$WT" rev-parse HEAD)"
echo >&2 "MERGE WORKTREE READY: $WT ($BRANCH at ${target:0:12})"
echo "$WT"
