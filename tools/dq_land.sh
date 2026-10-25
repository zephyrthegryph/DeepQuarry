#!/usr/bin/env bash
# Retired 2026-10-24: the batch train (tools/dq_train.sh) is the only path to master. Per-lane proofs re-ran on every master move,
# queued for the one DM compile slot and took lanes 2-3 h to land. A lane runs its focused tests, enqueues and releases its slot.
if [ "${DQ_LEGACY_LAND:-0}" != 1 ]; then
	echo "dq_land: retired; land with: bash tools/dq_train.sh enqueue --tests \"<your tests>\" (or --light), then release your slot" >&2
	exit 2
fi
# Land a lane on master with the merge lock held only for the cheap part: prove OUTSIDE the lock, lock only to merge and push.
#
#   export DQ_MERGE_SESSION=<the lane branch>   # optional: defaults to the current branch
#   bash tools/dq_land.sh --light                     # a LIGHT lane (docs/tooling/Rust only): queue it, land the batch (tools/dq_land_batch.sh)
#   bash tools/dq_land.sh [--tests "a b"] [--covers GLOB] [--rounds N] [--dry-run]     # from the lane's pool worktree
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
#   Disjoint accept (tools/dq_land_disjoint.sh): in step 1, when master moved since the lane's valid stamp, every master commit gained since
#   was itself landed through a proved gate, and the lane's files are disjoint from master's changes (and neither side touched a global path,
#   tools/ci/land_disjoint_global.txt), the lane is merged with master and only `analyze gen` + `check_ratchets --changed-only` run: no
#   compile, no test world. Otherwise (or on the last round) step 1 proves as before. A move while the lock was queued no longer counts as
#   a round: the lock is given back and step 1 runs again (at most DQ_LAND_FREE_ROUNDS, default 8, uncounted rounds).
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
. "$here/tools/dq_run_lock.sh"

echo "dq_land: NOTICE: the batch train is the default way to land a lane now: 'bash tools/dq_train.sh enqueue --tests \"<tests>\"' (add --light for docs/tooling/Rust-only work), then release your slot. One detached integrator gates every waiting lane together. dq_land.sh still works, but it re-proves on every master move; see doc/rewrite/agent_workflow.md section 29." >&2
# A light lane (docs, tooling scripts, Rust/compiler-only; pool-light) lands in a batch: no DM proof, no per-lane lock hold.
if [ "${1:-}" = "--light" ]; then shift; exec bash "$here/tools/dq_land_batch.sh" submit --run "$@"; fi

ready_args=()
rounds="${DQ_LAND_ROUNDS:-3}"
dry=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests|--covers|--tests-file) ready_args+=("$1" "${2:?$1 needs a value}"); shift ;;
		--no-pins) echo "dq_land: --no-pins is deprecated and does nothing: there are no look pins" >&2 ;;
		--rounds) shift; rounds="${1:?--rounds needs a number}" ;;
		--dry-run) dry=1 ;;
		-h|--help) sed -n '2,40p' "$0"; exit 0 ;;
		*) echo "dq_land: unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done
case "$rounds" in ''|*[!0-9]*|0) echo "dq_land: --rounds must be a positive number" >&2; exit 2 ;; esac
branch="$(git symbolic-ref -q --short HEAD)" || { echo "dq_land: a detached HEAD; run it on the lane's branch" >&2; exit 2; }
# The merge tools need a session name; default it to the lane branch (an explicit DQ_MERGE_SESSION wins).
[ -n "${DQ_MERGE_SESSION:-}" ] || export DQ_MERGE_SESSION="$branch"
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
run_lock_take "dq_land.sh $(git symbolic-ref -q --short HEAD)" || exit 1
trap 'release_lock; run_lock_release' EXIT

merge_ref="$branch"
free_rounds=0
for ((round = 1; round <= rounds; round++)); do
	last=0
	[ "$round" -eq "$rounds" ] && last=1
	git fetch -q origin || { echo "dq_land: git fetch failed" >&2; exit 1; }
	# 1. Prove outside the lock (skipped when the proof for exactly this merge already exists).
	if tree="$(proof_covers_merge origin/master "$merge_ref")"; then
		log "round $round: the merge of $branch into origin/master (${tree:0:10}) is already proved; no gate run needed"
	elif [ "$last" -eq 0 ] && bash "$here/tools/dq_land_disjoint.sh" "$branch"; then
		# Master moved, but only through proved landings that touch none of the lane's files: the lane was merged with it and passed the
		# fast checks (dq_land_disjoint.sh); no compile, no test world. Logged above by the script.
		git fetch -q origin || exit 1
		if ! tree="$(proof_covers_merge origin/master "$merge_ref")"; then
			log "master moved again while the fast check ran; trying again (not counted as a round)"
			free_rounds=$((free_rounds + 1))
			if [ "$free_rounds" -le "${DQ_LAND_FREE_ROUNDS:-8}" ]; then round=$((round - 1)); fi
			continue
		fi
		log "round $round: accepted without a re-proof (disjoint from the master commits landed since the stamp)"
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
		log "master moved while the lock was queued; giving the lock back and checking again"
		release_lock
		# Waiting for the lock is not a reason to re-prove: the next round tries dq_land_disjoint.sh first, and the round is not counted
		# against --rounds while the lane keeps qualifying (bounded by DQ_LAND_FREE_ROUNDS so a busy master cannot loop it forever).
		free_rounds=$((free_rounds + 1))
		if [ "$free_rounds" -le "${DQ_LAND_FREE_ROUNDS:-8}" ] && [ "$last" -eq 0 ]; then round=$((round - 1)); fi
		continue
	fi
	(
		cd "$WT" || exit 1
		_t=$(date +%s); lap() { echo "== dq_land: $1 $(( $(date +%s) - _t ))s"; _t=$(date +%s); }
		# A lane that already contains origin/master merges as a fast-forward: same commit, so its stamp (and its gates) stand with zero re-runs.
		if git merge-base --is-ancestor origin/master "$merge_ref" && git notes --ref=lane-ready show "$(git rev-parse "$merge_ref")" 2>/dev/null | grep -q '"ok":true'; then
			git merge --ff-only -q "$merge_ref" || { echo "dq_land: fast-forward failed" >&2; exit 1; }
			lap "fast-forward (stamped, nothing re-run)"
			if [ "$dry" -eq 1 ]; then DQ_PUSH_DRY_RUN=1 bash tools/dq_push_master.sh --expect "$branch"; else bash tools/dq_push_master.sh --expect "$branch"; fi
			rc=$?; lap "push"; exit "$rc"
		fi
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
