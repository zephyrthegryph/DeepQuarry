#!/usr/bin/env bash
# Batched landing for light lanes (docs, lane/tooling scripts, Rust/compiler-only work; tools/dq_lane_pool.sh --class light).
#
#   bash tools/dq_land.sh --light                 # from the light lane's worktree: queue this branch and run the batch (same as submit --run)
#   bash tools/dq_land_batch.sh submit [--run]    # push this branch and put it in the light queue; --run also runs the batch
#   bash tools/dq_land_batch.sh run               # merge every pushed light branch waiting in the queue in ONE merge and push master once
#   bash tools/dq_land_batch.sh status            # what waits
#
# A light lane edits, commits, `dq_land.sh --light` (which pushes the branch and queues it), then releases its slot: the lane is done in
# minutes. Whoever runs the batch next lands every queued branch together, so ten docs lanes cost one merge-lock hold, not ten.
#
# What a batch does (merge lock held, in the merge worktree, the lock part is short because nothing here compiles):
#   1. drops queue entries already in origin/master and REFUSES (and dequeues) a branch that touches a heavy path: .dm .dme .dmm .dmi, maps/,
#      icons/, code/, interface/, sound/, tgui/ (tools/dq_light_paths.sh): those need a general lane and the full gates;
#   2. merges each remaining branch with --no-ff; a branch that conflicts is skipped and stays queued, the rest still land;
#   3. runs the cheap checks for what changed (tools/dq_light_checks.sh: bash -n/shellcheck, doc links, cargo test for touched crates,
#      ratchets only when .dm files or the lints changed);
#   4. stamps the merge commit (refs/notes/light-batch; tools/dq_push_stamp.sh accepts it only when the whole change since origin/master is
#      light) and pushes with tools/dq_push_master.sh --light (no DM build; refuses when master moved: run the batch again).
# Queue state: <DQ_LANE_POOL_STATE>/light-queue/<branch>.q (default E:/dq-cache/lane-pool/light-queue). Nothing here runs checkout, reset,
# restore, stash or cherry-pick, or deletes a lock file.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
here="$(pwd)"
. "$here/tools/dq_git_safe.sh"
. "$here/tools/dq_light_paths.sh"
STATE="${DQ_LANE_POOL_STATE:-E:/dq-cache/lane-pool}"
Q="$STATE/light-queue"

die() { echo "dq_land_batch: $*" >&2; exit 1; }
log() { echo "== dq_land_batch: $*"; }
qfile() { echo "$Q/$(printf '%s' "$1" | tr '/' '_').q"; }
qget() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }
queued_branches() { local f; for f in "$Q"/*.q; do [ -e "$f" ] && qget "$f" branch; done; }

cmd_status() {
	local b any=0
	for b in $(queued_branches); do any=1; echo "  waiting: $b ($(git rev-parse --short "origin/$b" 2>/dev/null || echo 'not on origin')) since $(qget "$(qfile "$b")" since)"; done
	[ "$any" -eq 1 ] || echo "  the light queue is empty"
}

cmd_submit() {
	local run=0 branch heavy ahead
	[ "${1:-}" = "--run" ] && run=1
	branch="$(git symbolic-ref -q --short HEAD)" || die "a detached HEAD; run it on the light lane's branch"
	case "$branch" in master|main|rewrite/integ-current) die "$branch is not a lane branch" ;; esac
	git update-index -q --refresh >/dev/null 2>&1
	[ -z "$(git status --porcelain --untracked-files=normal | head -n 1)" ] || die "the tree is not clean: commit your change first"
	git fetch -q origin || die "git fetch failed"
	heavy="$(light_heavy_in origin/master HEAD)"
	if [ -n "$heavy" ]; then
		echo "$heavy" | head -8 >&2
		die "REFUSED: a light branch may not touch .dm/.dme/maps/icons/code/interface/sound/tgui (listed above). Move this work to a general lane (bash tools/dq_lane_pool.sh lease <branch>) and land it with tools/dq_land.sh."
	fi
	ahead="$(git rev-list --count origin/master..HEAD)"
	[ "$ahead" -gt 0 ] || die "$branch holds nothing origin/master lacks; there is nothing to land"
	git push -q origin "HEAD:refs/heads/$branch" || die "could not push $branch to origin (never forced)"
	mkdir -p "$Q"
	{ echo "branch=$branch"; echo "tip=$(git rev-parse HEAD)"; echo "owner=${DQ_LANE_OWNER:-${USERNAME:-${USER:-unknown}}}"; echo "since=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } >"$(qfile "$branch")"
	log "queued $branch ($ahead commit(s), pushed). It is safe to release the light slot: bash tools/dq_lane_pool.sh release $branch"
	[ "$run" -eq 1 ] || return 0
	cmd_run
}

cmd_run() {
	local b tip f heavy lanes=() wt rc merged=() skipped=() sha tips
	git fetch -q origin || die "git fetch failed"
	# 1. what is waiting and valid
	for b in $(queued_branches); do
		f="$(qfile "$b")"
		if ! git rev-parse -q --verify "origin/$b" >/dev/null; then echo "dq_land_batch: $b is not on origin; dropped from the queue" >&2; rm -f "$f"; continue; fi
		if git merge-base --is-ancestor "origin/$b" origin/master; then log "$b is already in origin/master; dequeued"; rm -f "$f"; continue; fi
		heavy="$(light_heavy_in origin/master "origin/$b")"
		if [ -n "$heavy" ]; then echo "dq_land_batch: REFUSED $b: it touches heavy paths ($(echo "$heavy" | head -3 | tr '\n' ' ')); dequeued. Land it from a general lane (tools/dq_land.sh)." >&2; rm -f "$f"; continue; fi
		lanes+=("$b")
	done
	[ ${#lanes[@]} -gt 0 ] || { log "nothing is waiting in the light queue"; return 0; }
	log "batch of ${#lanes[@]}: ${lanes[*]}"
	export DQ_MERGE_SESSION="light-batch-$$"
	. "$here/tools/dq_machine_slots.sh"
	wt="$(bash "$here/tools/dq_merge_worktree.sh" --lanes "${lanes[*]}")" || die "could not take the merge lock / worktree"
	rc=0
	(
		cd "$wt" || exit 1
		merged=(); skipped=()
		for b in "${lanes[@]}"; do
			if git merge-base --is-ancestor "origin/$b" origin/master; then continue; fi   # landed by another batch while we queued for the lock
			if git merge --no-ff --no-edit -q -m "Merge $b (light batch)" "origin/$b"; then merged+=("$b"); else git merge --abort >/dev/null 2>&1; skipped+=("$b"); echo "dq_land_batch: $b conflicts with master/the batch: skipped, stays queued (rebase it: bash tools/dq_merge_master.sh)" >&2; fi
		done
		[ ${#merged[@]} -gt 0 ] || { echo "dq_land_batch: nothing to merge" >&2; exit 3; }
		sha="$(git rev-parse HEAD)"
		if [ -n "${DQ_LIGHT_TRUST:-}" ]; then
			# the batch train prechecked every lane with these same checks and master changed nothing they read since (dq_train.sh light_trust)
			echo "== light checks: not repeated: $DQ_LIGHT_TRUST"
		else
			bash tools/dq_light_checks.sh origin/master HEAD || { echo "dq_land_batch: the cheap checks failed; nothing was pushed" >&2; exit 1; }
		fi
		git notes --ref=light-batch add -f -m "{\"ok\":true,\"commit\":\"$sha\",\"branches\":\"${merged[*]}\"}" "$sha" || exit 1
		tips=""; for b in "${merged[@]}"; do tips="$tips origin/$b"; done
		bash tools/dq_push_master.sh --light --expect "$tips" || exit 1
		printf '%s\n' "${merged[@]}" >"$STATE/light-queue.landed.$$"
		exit 0
	)
	rc=$?
	if [ "$rc" -eq 0 ]; then
		while IFS= read -r b; do rm -f "$(qfile "$b")"; done <"$STATE/light-queue.landed.$$"
		rm -f "$STATE/light-queue.landed.$$"
		log "landed the light batch (${lanes[*]})"
		merge_lock_holder_check 2>/dev/null && merge_lock_release >/dev/null 2>&1
		return 0
	fi
	# a failed batch gives the merge worktree and the lock back
	if merge_lock_holder_check 2>/dev/null; then
		git -C "$wt" merge --abort >/dev/null 2>&1
		git -C "$wt" switch -q -C rewrite/integ-current origin/master 2>/dev/null
		merge_lock_release >/dev/null 2>&1
	fi
	[ "$rc" -eq 3 ] && return 0
	return 1
}

case "${1:-}" in
	submit) shift; cmd_submit "$@" ;;
	run) cmd_run ;;
	status) cmd_status ;;
	*) sed -n '2,12p' "$0"; exit 2 ;;
esac
