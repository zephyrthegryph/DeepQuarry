#!/usr/bin/env bash
# A batch of lanes merged and proved as ONE combination, with a bisect that bounces only the bad lane.
#
#   bash tools/dq_merge_batch.sh --lanes "a,b,c" [any dq_merge_gates.sh option: --tests "..." --tgui --serial ...]
#   bash tools/dq_merge_gates.sh --lanes a,b,c      # the same thing: gates delegates here when a lane is not in HEAD yet
#
# Run it inside the merge worktree holding the merge lock (cd "$(bash tools/dq_merge_worktree.sh)"). It:
#   (--lane-tests "lane=name name", repeatable: the tests a lane asked for, sent to the gates only in attempts that merge that lane)
#   1. starts from origin/master, merges every lane in order with `git merge --no-ff` (a lane that conflicts is bounced at once),
#   2. runs dq_merge_gates.sh once on the combination: ONE gen, ONE build, ONE union of focused tests (the smoke set plus the tests of
#      every lane whose stamp is stale) and ONE look-key normalization and record, committed into the batch's last merge commit,
#      not once per lane. A lane whose stamp is valid and whose merge changes nothing master did not (master unmoved) is covered by
#      its tree proof and costs no test at all (tools/dq_proof_cache.sh),
#   3. on failure, bisects by lane: the smallest prefix of the batch that fails names the bad lane (log N attempts, and an attempt on a
#      tree already proved is answered from the proof cache in seconds), that lane is bounced (named, with its log), and the rest is
#      merged and proved again,
#   3b. DQ_BATCH_DEADLINE=<epoch seconds> (the batch train sets it): an attempt that has not started by then is not started; the lanes
#      not yet judged are DEFERRED (neither proved nor bounced) and the proved prefix still lands. A gate whose test phase was killed at its
#      wall-clock cap ("FOCUSED RUN CAPPED") says the batch is too big, not that a lane is bad: the lanes not yet judged are deferred and the
#      batch is reported CAPPED (a single lane that is capped alone is bounced: its own tests do not fit),
#   4. leaves rewrite/integ-current on the proved combination (push it with tools/dq_push_master.sh) or on origin/master when nothing
#      passed. Exit 0: every lane is in; 1: some lane was bounced (listed); 2: usage.
# Machine-readable result lines at the end (tools/dq_train.sh reads them): BATCH_GOOD: <lanes>, BATCH_DEFERRED: <lanes>, BATCH_CAPPED: 1|,
# and one BATCH_BOUNCED: <lane>|<reason>|<attempt log> per bounced lane.
# Attempts run on a detached HEAD, so the branch only ever moves to a proved tip, with `git switch -C` from a clean tree (the previous
# value of the branch is origin/master, nothing is lost). Nothing here runs checkout, reset, restore, stash or cherry-pick.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
merge_lock_require || exit 1

lanes_arg=""
pass=()
declare -A lane_tests
while [ $# -gt 0 ]; do
	case "$1" in
		--lanes) shift; lanes_arg="${1:-}" ;;
		--lane-tests) shift; lane_tests["${1%%=*}"]="${1#*=}" ;;
		-h|--help) sed -n '2,24p' "$0"; exit 0 ;;
		*) pass+=("$1") ;;
	esac
	shift
done
lanes_arg="${lanes_arg//,/ }"
read -r -a lanes <<<"$lanes_arg"
[ ${#lanes[@]} -gt 0 ] || { echo "dq_merge_batch: --lanes needs at least one branch" >&2; exit 2; }
BRANCH="${DQ_MERGE_BRANCH:-rewrite/integ-current}"

git update-index -q --refresh >/dev/null 2>&1
# A tracked edit left by an earlier batch's failed gate is the gate's own output, not a lane's work: logged and put back to HEAD.
dq_clean_tracked "dq_merge_batch: start dirty"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "dq_merge_batch: REFUSED: uncommitted tracked changes that could not be cleaned" >&2; exit 1; fi
git fetch -q origin 2>/dev/null || echo "dq_merge_batch: warning: git fetch failed" >&2
git rev-parse -q --verify origin/master >/dev/null || { echo "dq_merge_batch: no origin/master" >&2; exit 2; }
for l in "${lanes[@]}"; do
	git rev-parse -q --verify "$l^{commit}" >/dev/null 2>&1 || git rev-parse -q --verify "origin/$l^{commit}" >/dev/null 2>&1 || { echo "dq_merge_batch: lane '$l' does not resolve to a commit" >&2; exit 2; }
done
mkdir -p data/merge-batch
stamp="$(date +%Y%m%dT%H%M%S)"
declare -A tried_rc
declare -A attempt_log
DEADLINE="${DQ_BATCH_DEADLINE:-}"
bounced=()
reasons=()
blogs=()
deferred=()
capped=""
n_attempts=0

ref_of() { git rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1 && echo "$1" || echo "origin/$1"; }

# attempt <lane...>: detached origin/master + the merges + the gates. Returns the gates' status; a merge conflict names the lane in $CONFLICT.
CONFLICT=""
current_key=""
attempt() {
	local key="$*" l log
	if [ -z "${NOCACHE:-}" ] && [ -n "${tried_rc[$key]+x}" ]; then return "${tried_rc[$key]}"; fi
	if [ -z "${NOCACHE:-}" ] && [ -n "$DEADLINE" ] && [ "$(date +%s)" -gt "$DEADLINE" ]; then
		echo "== batch attempt not started ($key): the cycle deadline passed; the lanes not yet judged are deferred"
		return 92
	fi
	current_key="$key"
	n_attempts=$((n_attempts + 1))
	log="data/merge-batch/$stamp.attempt$n_attempts.log"
	attempt_log[$key]="$log"
	echo "== batch attempt $n_attempts: $key (log $log)"
	CONFLICT=""
	# Each attempt starts from a clean tree: the previous failed attempt may have left a baseline shrink behind.
	dq_clean_tracked "dq_merge_batch: attempt started dirty" 2>&1 | tee -a "$log" >&2
	git switch -q --detach origin/master || return 90
	for l in "$@"; do
		if ! git merge --no-ff --no-edit -q -m "Merge $l" "$(ref_of "$l")" >>"$log" 2>&1; then
			git merge --abort >/dev/null 2>&1
			CONFLICT="$l"
			echo "   $l conflicts with the batch; see $log" >&2
			tried_rc[$key]=91
			return 91
		fi
	done
	# One look-key normalization/record and one gen/build/test pass for the whole combination: dq_merge_gates.sh does them on this HEAD.
	# --lane-tests LANE="names": only the tests of the lanes merged in THIS attempt go to the gate. A lane bounced for a conflict (or cut by
	# the bisect) is not in the tree, and its test names would be "unknown" to the test build and fail every attempt that follows.
	local lt=""
	for l in "$@"; do lt="$lt ${lane_tests[$l]:-}"; done
	lt="$(printf '%s\n' $lt | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
	bash tools/dq_merge_gates.sh --lanes "$*" --no-auto-merge ${lt:+--tests "$lt"} ${pass[@]+"${pass[@]}"} >>"$log" 2>&1
	local rc=$?
	tail -n 3 "$log" | sed 's/^/   /'
	# A killed test phase is a verdict on the size of the batch, not on a lane.
	if [ "$rc" -ne 0 ] && grep -q '^FOCUSED RUN CAPPED' "$log"; then rc=93; echo "   the test phase hit its wall-clock cap (the batch is too big for it)"; fi
	# A failed gate leaves its in-job baseline shrink uncommitted: discard it now, so nothing leaks into the next attempt or cycle.
	if [ "$rc" -ne 0 ]; then dq_clean_tracked "dq_merge_batch: failed gate left a tracked edit" 2>&1 | tee -a "$log" >&2; fi
	tried_rc[$key]=$rc
	return "$rc"
}

bounce() { # <lane> <why> [<attempt log>]
	bounced+=("$1"); reasons+=("$2"); blogs+=("${3:-}")
	echo "== BOUNCED $1: $2"
}

good=()
remaining=("${lanes[@]}")
while [ ${#remaining[@]} -gt 0 ]; do
	set=("${good[@]+"${good[@]}"}" "${remaining[@]}")
	attempt "${set[@]}"; rc=$?
	if [ "$rc" -eq 91 ]; then
		# a lane that cannot even merge: bounce it and retry without it
		bounce "$CONFLICT" "merge conflict with the batch or master (rebase it: bash tools/dq_merge_master.sh in the lane, then enqueue again)" "${attempt_log[$current_key]:-}"
		new=()
		for l in "${remaining[@]}"; do [ "$l" = "$CONFLICT" ] || new+=("$l"); done
		remaining=("${new[@]+"${new[@]}"}")
		new=()
		for l in "${good[@]+"${good[@]}"}"; do [ "$l" = "$CONFLICT" ] || new+=("$l"); done
		good=("${new[@]+"${new[@]}"}")
		continue
	fi
	if [ "$rc" -eq 0 ]; then good=("${set[@]}"); remaining=(); break; fi
	if [ "$rc" -eq 92 ] || { [ "$rc" -eq 93 ] && [ ${#set[@]} -gt 1 ]; }; then
		[ "$rc" -eq 93 ] && capped=1
		deferred+=("${remaining[@]}"); remaining=()
		break
	fi
	if [ ${#set[@]} -eq 1 ]; then
		if [ "$rc" -eq 93 ]; then
			bounce "${set[0]}" "its tests do not fit the gate's test-phase cap alone (the run was killed at the cap): trim or split the lane's tests" "${attempt_log[${set[*]}]:-}"
		else
			bounce "${set[0]}" "gates failed alone on master (logs data/merge-batch/$stamp.attempt$n_attempts.log and data/merge-gates/)" "${attempt_log[${set[*]}]:-}"
		fi
		good=(); remaining=(); break
	fi
	# Bisect: the smallest prefix of `remaining` that fails on top of `good` names the culprit.
	lo=1; hi=${#remaining[@]}; passed=0
	while [ "$lo" -lt "$hi" ]; do
		mid=$(( (lo + hi) / 2 ))
		attempt "${good[@]+"${good[@]}"}" "${remaining[@]:0:mid}"; prc=$?
		if [ "$prc" -eq 92 ] || [ "$prc" -eq 93 ]; then abort_rc=$prc; break; fi
		if [ "$prc" -eq 0 ]; then lo=$((mid + 1)); passed=$mid; elif [ "$prc" -eq 91 ]; then hi=$mid; else hi=$mid; fi
	done
	if [ "${abort_rc:-0}" -ne 0 ]; then
		# the deadline passed, or the test phase was capped, in the middle of the bisect: what is not judged yet waits for the next cycle
		# A prefix that already passed on top of `good` is proved: keep it (it lands this cycle) instead of throwing a green gate away.
		[ "$abort_rc" -eq 93 ] && capped=1
		if [ "$passed" -gt 0 ]; then
			echo "== keeping the proved prefix (${remaining[*]:0:passed}); deferring the rest"
			good+=("${remaining[@]:0:passed}")
			remaining=("${remaining[@]:passed}")
		fi
		deferred+=("${remaining[@]+"${remaining[@]}"}"); remaining=()
		abort_rc=0
		continue
	fi
	culprit="${remaining[$((lo - 1))]}"
	pre=("${good[@]+"${good[@]}"}" "${remaining[@]:0:lo}")
	bounce "$culprit" "the batch fails once it is merged (bisected; logs data/merge-batch/$stamp.attempt*.log)" "${attempt_log[${pre[*]}]:-}"
	good+=("${remaining[@]:0:$((lo - 1))}")
	remaining=("${remaining[@]:$lo}")
	# the loop retries good+remaining; a set already tried is answered from tried_rc
done
# HEAD sits on the last attempt, which may have been a failing one: build the proved combination again. Its tree was proved, so the gates
# answer from the proof cache (tools/dq_proof_cache.sh) in seconds.
if [ ${#good[@]} -gt 0 ] && [ "$current_key" != "${good[*]}" ]; then
	NOCACHE=1 attempt "${good[@]}" || { echo "dq_merge_batch: the proved combination (${good[*]}) failed on the rebuild; not moving $BRANCH" >&2; good=(); }
fi

echo "BATCH_GOOD: ${good[*]-}"
echo "BATCH_DEFERRED: ${deferred[*]-}"
echo "BATCH_CAPPED: ${capped}"
for i in "${!bounced[@]}"; do echo "BATCH_BOUNCED: ${bounced[$i]}|${reasons[$i]}|${blogs[$i]}"; done
if [ ${#good[@]} -eq 0 ]; then
	echo "dq_merge_batch: nothing passed; $BRANCH stays at origin/master"
	git switch -q -C "$BRANCH" origin/master 2>/dev/null
else
	git switch -q -C "$BRANCH" HEAD || { echo "dq_merge_batch: could not move $BRANCH to the proved tip $(git rev-parse --short HEAD)" >&2; exit 1; }
	echo "dq_merge_batch: $BRANCH = $(git rev-parse --short HEAD): ${good[*]} proved together in $n_attempts attempt(s); push with: bash tools/dq_push_master.sh --expect \"${good[*]}\""
fi
if [ ${#bounced[@]} -gt 0 ]; then
	echo "dq_merge_batch: BOUNCED: ${bounced[*]}"
	for i in "${!bounced[@]}"; do echo "  ${bounced[$i]}: ${reasons[$i]}"; done
	exit 1
fi
exit 0
