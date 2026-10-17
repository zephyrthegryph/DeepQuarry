#!/usr/bin/env bash
# Land a lane on master with the merge lock held only for the cheap part: prove OUTSIDE the lock, lock only to merge and push.
#
#   export DQ_MERGE_SESSION=<the lane branch>
#   bash tools/dq_land.sh [--tests "a b"] [--covers GLOB] [--no-pins] [--rounds N] [--dry-run]     # from the lane's pool worktree
#
# Why: a gate run inside the merge lock takes 3-10 minutes (longer under load), and everyone queues behind it (overnight lanes
# waited up to 4.5 h). A lane that was proved on its merge with the master it lands on needs no gate run at all: the proof is stored
# under the TREE hash (tools/dq_proof_cache.sh), merging the lane into that master gives that tree, and dq_merge_gates.sh answers
# from the proof. So the proof is made first, without the lock, and the lock is taken only for what is fast:
#
#   round 1..N (N = --rounds, default 3; DQ_LAND_ROUNDS):
#     1. fetch. If merging this lane into origin/master would give a tree that already has a covering proof, go to 3.
#        Otherwise prove it: tools/dq_lane_ready.sh (merges origin/master into the lane, runs the gates in this worktree, stamps) with
#        the same --tests/--covers. No lock is held while it runs: other lanes land meanwhile.
#     2. (master may have moved while that ran: recheck, and prove again, up to N rounds)
#     3. take the merge lock (tools/dq_merge_worktree.sh; it waits its turn). Hold time is the fast path below: about a minute.
#        Inside the lock, once the worktree sits on the current origin/master: if the proof still covers the merge, merge the lane,
#        run dq_merge_gates.sh (it reuses the proof: no compile, no test world), push with dq_push_master.sh (verifies master did not
#        move and that the lane's tip landed, frees the lock). If master moved while the lock was queued, the lock is released at
#        once (the worktree reset to origin/master) and the round starts again at 1.
#   The last round does not give the lock back: whatever master did, it proves and lands inside the lock (the old behaviour), so a
#   busy master can delay a lane by N-1 proofs but never starve it.
#
# --dry-run runs everything but the push (DQ_PUSH_DRY_RUN=1) and frees the lock and the worktree. Exit 0 landed (or dry-run passed), 1 a
# gate or the push failed, 2 a usage problem. Nothing here runs checkout, reset, restore, stash or cherry-pick or deletes a lock file.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
here="$(pwd)"
. "$here/tools/dq_git_safe.sh"
. "$here/tools/dq_proof_cache.sh"
. "$here/tools/dq_machine_slots.sh"

ready_args=()
rounds="${DQ_LAND_ROUNDS:-3}"
dry=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests|--covers|--tests-file) ready_args+=("$1" "${2:?$1 needs a value}"); shift ;;
		--no-pins) ready_args+=("$1"); export DQ_NO_PINS=1 ;;
		--rounds) shift; rounds="${1:?--rounds needs a number}" ;;
		--dry-run) dry=1 ;;
		-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
		*) echo "dq_land: unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done
case "$rounds" in ''|*[!0-9]*|0) echo "dq_land: --rounds must be a positive number" >&2; exit 2 ;; esac
[ -n "${DQ_MERGE_SESSION:-}" ] || { echo "dq_land: set DQ_MERGE_SESSION=<your lane branch> (the merge tools need it)" >&2; exit 2; }
branch="$(git symbolic-ref -q --short HEAD)" || { echo "dq_land: a detached HEAD; run it on the lane's branch" >&2; exit 2; }
case "$branch" in master|rewrite/integ-current) echo "dq_land: $branch is not a lane branch" >&2; exit 2 ;; esac

log() { echo "== dq_land: $*"; }
t0=$(date +%s)
lock_held=0
WT=""
release_lock() {
	[ "$lock_held" -eq 1 ] || return 0
	lock_held=0
	# Only while this session still holds the lock (a landed push already freed it, and the next batch owns the worktree then): the
	# worktree goes back to origin/master first (a merge left in it would read as an unpushed batch to the next caller).
	merge_lock_holder_check 2>/dev/null || return 0
	if [ -n "$WT" ] && [ -d "$WT" ]; then git -C "$WT" merge --abort >/dev/null 2>&1; git -C "$WT" switch -q -C rewrite/integ-current origin/master 2>/dev/null; fi
	merge_lock_release >/dev/null 2>&1 || true
}
trap release_lock EXIT

merge_ref="$branch"
for ((round = 1; round <= rounds; round++)); do
	last=0
	[ "$round" -eq "$rounds" ] && last=1
	git fetch -q origin || { echo "dq_land: git fetch failed" >&2; exit 1; }
	# 1. Prove outside the lock (skipped when the proof for exactly this merge already exists).
	if tree="$(proof_covers_merge origin/master "$merge_ref")"; then
		log "round $round: the merge of $branch into origin/master (${tree:0:10}) is already proved; no gate run needed"
	else
		log "round $round/$rounds: proving $branch on origin/master outside the merge lock (dq_lane_ready.sh)"
		tp=$(date +%s)
		bash "$here/tools/dq_lane_ready.sh" --lite ${ready_args[@]+"${ready_args[@]}"} || { echo "dq_land: the proof failed; fix the lane (nothing was merged, no lock was taken)" >&2; exit 1; }
		log "proved in $(( $(date +%s) - tp ))s"
		git fetch -q origin || exit 1
		if ! tree="$(proof_covers_merge origin/master "$merge_ref")"; then
			if [ "$last" -eq 0 ]; then log "master moved while the lane was proved; proving again"; continue; fi
			log "master moved while the lane was proved; last round: landing under the lock with the gates"
			tree=""
		fi
	fi
	# 3. The lock, only for the fast part.
	log "taking the merge lock"
	tl=$(date +%s)
	WT="$(bash "$here/tools/dq_merge_worktree.sh" --lanes "$branch")" || { echo "dq_land: could not take the merge lock / worktree" >&2; exit 1; }
	lock_held=1
	waited=$(( $(date +%s) - tl ))
	locked_at=$(date +%s)
	log "lock held after ${waited}s in the queue; worktree $WT"
	if [ "$last" -eq 0 ] && ! proof_covers_merge origin/master "$merge_ref" >/dev/null; then
		log "master moved while the lock was queued; giving the lock back and proving again"
		release_lock
		continue
	fi
	(
		cd "$WT" || exit 1
		_t=$(date +%s); lap() { echo "== dq_land: $1 $(( $(date +%s) - _t ))s"; _t=$(date +%s); }
		git merge --no-ff --no-edit -q -m "Merge $branch" "$merge_ref" || { git merge --abort >/dev/null 2>&1; echo "dq_land: the merge of $branch conflicts with master (rebase: bash tools/dq_merge_master.sh, then run dq_land.sh again)" >&2; exit 1; }
		lap "merge"
		bash tools/dq_merge_gates.sh --lanes "$branch" --no-auto-merge || exit 1
		lap "gates (proof reuse when master did not move)"
		if [ "$dry" -eq 1 ]; then DQ_PUSH_DRY_RUN=1 bash tools/dq_push_master.sh --expect "$branch"; else bash tools/dq_push_master.sh --expect "$branch"; fi
		rc=$?
		lap "push"
		exit "$rc"
	)
	rc=$?
	held=$(( $(date +%s) - locked_at ))
	if [ "$rc" -eq 0 ]; then
		log "$([ "$dry" -eq 1 ] && echo 'dry run passed' || echo "landed $branch"): lock held ${held}s, queued ${waited}s, total $(( $(date +%s) - t0 ))s"
		release_lock # a real push already freed it; a dry run frees it here
		exit 0
	fi
	echo "dq_land: the merge, gates or push failed under the lock (held ${held}s); see the output above" >&2
	exit 1
done
echo "dq_land: master kept moving for $rounds rounds" >&2
exit 1
