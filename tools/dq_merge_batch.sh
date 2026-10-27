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
#   3c. DQ_BATCH_CACHE=<file> (the batch train sets it): the verdict of every attempt (pass, merge conflict, gate failure) is saved there,
#      keyed to origin/master and the lanes' tips, and read back by the next run on the same batch. The bisect is deterministic, so a
#      run that was cut off by the deadline is RESUMED by the next one: it replays the saved verdicts at once and spends its time on the
#      next untried attempt instead of the full batch again. A cut-off or capped verdict is never saved. The first real attempt of a run
#      and any single-lane attempt (the decisive step of a bisect) ignore the deadline, so every run makes progress and a lane is never
#      deferred instead of judged,
#   3d. DQ_BATCH_WT2=<a second worktree of this repository> (the train sets it for a batch of prechecked lanes): the bisect gates BOTH
#      halves at once, good+L here and good+R there (attempt_pair); L failing narrows to L, L passing grows the proved set by L and narrows
#      to R. One attempt at a time when free RAM is under DQ_BATCH_PARALLEL_MIN_FREE_GB (16) or DQ_BATCH_PARALLEL=0.
#   3e. deepquarry.dme: a merge that stops on the manifest alone is resolved by merging the include sets, and an include the union merge
#      brought back for a file one side deleted is dropped (tools/dq_dme_resolve.sh; both verified against the files on disk).
# Machine-readable result lines at the end (tools/dq_train.sh reads them): BATCH_GOOD: <lanes>, BATCH_DEFERRED: <lanes>, BATCH_CAPPED: 1|,
# BATCH_LATER: <lanes> (they conflicted with another lane of the batch only: neither judged nor bounced, they stay queued),
# and one BATCH_BOUNCED: <lane>|<reason>|<attempt log> per bounced lane.
# Attempts run on a detached HEAD, so the branch only ever moves to a proved tip, with `git switch -C` from a clean tree (the previous
# value of the branch is origin/master, nothing is lost). Nothing here runs checkout, reset, restore, stash or cherry-pick.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_dme_resolve.sh"
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
real_attempts=0
CACHE="${DQ_BATCH_CACHE:-}"
cache_ctx=""

ref_of() { git rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1 && echo "$1" || echo "origin/$1"; }

# The verdict cache (3c): a context line (origin/master + every lane's tip, in order) then "<rc> <lanes>" lines. A different context is discarded.
cache_load() {
	[ -n "$CACHE" ] || return 0
	local l
	cache_ctx="$(git rev-parse origin/master)"
	for l in "${lanes[@]}"; do cache_ctx="$cache_ctx $(git rev-parse "$(ref_of "$l")^{commit}")"; done
	if [ -f "$CACHE" ] && [ "$(head -n 1 "$CACHE")" = "ctx $cache_ctx" ]; then
		local rc key
		while read -r rc key; do
			[ -n "$key" ] && tried_rc[$key]="$rc"
		done < <(tail -n +2 "$CACHE")
		echo "== resuming the bisect: ${#tried_rc[@]} attempt verdict(s) saved from an earlier run on this batch"
	else
		printf 'ctx %s\n' "$cache_ctx" >"$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE"
	fi
}
cache_save() { # <rc> <key>
	[ -n "$CACHE" ] || return 0
	case "$1" in 90|92|93) return 0 ;; esac
	printf '%s %s\n' "$1" "$2" >>"$CACHE"
}
cache_load

# attempt_run <dir> <log> <lane...>: in <dir> (this worktree, or the second one of a parallel bisect), detached origin/master + the merges +
# the gates; exits with the gates' status (90 setup, 91 a merge conflict: the lane is written to <log>.conflict, 93 capped). It runs in a
# subshell so two attempts can run at once (each in its own worktree); the bookkeeping is the caller's (attempt, attempt_pair).
attempt_run() {
	local dir="$1" log="$2"
	shift 2
	(
		cd "$dir" || exit 90
		# Each attempt starts from a clean tree: the previous failed attempt may have left a baseline shrink behind.
		dq_clean_tracked "dq_merge_batch: attempt started dirty" 2>&1 | tee -a "$log" >&2
		git switch -q --detach origin/master >>"$log" 2>&1 || exit 90
		for l in "$@"; do
			if ! git merge --no-ff --no-edit -q -m "Merge $l" "$(ref_of "$l")" >>"$log" 2>&1 && ! dme_resolve_conflict >>"$log" 2>&1 && ! doc_union_conflict >>"$log" 2>&1; then
				git merge --abort >/dev/null 2>&1
				echo "$l" >"$log.conflict"
				echo "   $l conflicts with the batch; see $log" >&2
				exit 91
			fi
			# the union merge of deepquarry.dme can bring back an include one side deleted: drop it (tools/dq_dme_resolve.sh)
			dme_repair_after_merge >>"$log" 2>&1
		done
		# One gen/build/test pass for the whole combination: dq_merge_gates.sh does it on this HEAD.
		# --lane-tests LANE="names": only the tests of the lanes merged in THIS attempt go to the gate. A lane bounced for a conflict (or cut by
		# the bisect) is not in the tree, and its test names would be "unknown" to the test build and fail every attempt that follows.
		lt=""
		for l in "$@"; do lt="$lt ${lane_tests[$l]:-}"; done
		lt="$(printf '%s\n' $lt | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
		bash tools/dq_merge_gates.sh --lanes "$*" --no-auto-merge ${lt:+--tests "$lt"} ${pass[@]+"${pass[@]}"} >>"$log" 2>&1
		rc=$?
		# A killed test phase is a verdict on the size of the batch, not on a lane.
		if [ "$rc" -ne 0 ] && grep -q '^FOCUSED RUN CAPPED' "$log"; then rc=93; fi
		# A failed gate leaves its in-job baseline shrink uncommitted: discard it now, so nothing leaks into the next attempt or cycle.
		if [ "$rc" -ne 0 ]; then dq_clean_tracked "dq_merge_batch: failed gate left a tracked edit" 2>&1 | tee -a "$log" >&2; fi
		exit "$rc"
	)
}

attempt_start() { # <lane...>: 0 = run it, else the cached verdict or 92 (the deadline passed)
	local key="$*"
	if [ -z "${NOCACHE:-}" ] && [ -n "${tried_rc[$key]+x}" ]; then return "${tried_rc[$key]}"; fi
	if [ -z "${NOCACHE:-}" ] && [ -n "$DEADLINE" ] && [ "$real_attempts" -gt 0 ] && [ "$#" -gt 1 ] && [ "$(date +%s)" -gt "$DEADLINE" ]; then
		echo "== batch attempt not started ($key): the cycle deadline passed; the lanes not yet judged are deferred"
		return 92
	fi
	return 0
}
attempt_new_log() { # <lane...>: numbers a new attempt; ATT_LOG is its log (relative to this worktree)
	n_attempts=$((n_attempts + 1))
	real_attempts=$((real_attempts + 1))
	ATT_LOG="data/merge-batch/$stamp.attempt$n_attempts.log"
	attempt_log["$*"]="$ATT_LOG"
	: >"$ATT_LOG"
	rm -f "$ATT_LOG.conflict"
	echo "== batch attempt $n_attempts: $* (log $ATT_LOG)"
}
attempt_done() { # <rc> <log> <lane...>: records the verdict, names a conflicting lane in CONFLICT
	local rc="$1" log="$2"
	shift 2
	CONFLICT=""
	if [ "$rc" -eq 91 ]; then CONFLICT="$(cat "$log.conflict" 2>/dev/null)"; rm -f "$log.conflict"; fi
	tail -n 3 "$log" | sed 's/^/   /'
	[ "$rc" -eq 93 ] && echo "   the test phase hit its wall-clock cap (the batch is too big for it)"
	tried_rc["$*"]=$rc
	[ -n "${NOCACHE:-}" ] || cache_save "$rc" "$*"
}

# attempt <lane...>: one attempt in this worktree. Returns the gates' status; a merge conflict names the lane in $CONFLICT.
CONFLICT=""
current_key=""
attempt() {
	local rc
	attempt_start "$@" || return $?
	current_key="$*"
	attempt_new_log "$@"
	attempt_run "$PWD" "$ATT_LOG" "$@"; rc=$?
	attempt_done "$rc" "$ATT_LOG" "$@"
	return "$rc"
}

# attempt_pair "<lanes A>" "<lanes B>": both attempts at once, A in this worktree and B in the second one (DQ_BATCH_WT2). Sets RC_A and RC_B
# (CONFLICT_A, CONFLICT_B). A verdict already known is not run again; with only one left to run it runs here, alone.
attempt_pair() {
	local a b log_a log_b pid_a pid_b
	read -r -a a <<<"$1"; read -r -a b <<<"$2"
	attempt_start "${a[@]}"; RC_A=$?
	attempt_start "${b[@]}"; RC_B=$?
	CONFLICT_A=""; CONFLICT_B=""
	if [ "$RC_A" -eq 0 ] && [ "$RC_B" -eq 0 ]; then
		echo "== parallel bisect: [${a[*]}] here and [${b[*]}] in $WT2, at the same time"
		current_key="${a[*]}"
		attempt_new_log "${a[@]}"; log_a="$ATT_LOG"
		attempt_new_log "${b[@]}"; log_b="$ATT_LOG"
		attempt_run "$PWD" "$log_a" "${a[@]}" & pid_a=$!
		attempt_run "$WT2" "$PWD/$log_b" "${b[@]}" & pid_b=$!
		wait "$pid_a"; RC_A=$?
		wait "$pid_b"; RC_B=$?
		attempt_done "$RC_A" "$log_a" "${a[@]}"; CONFLICT_A="$CONFLICT"
		attempt_done "$RC_B" "$log_b" "${b[@]}"; CONFLICT_B="$CONFLICT"
		return 0
	fi
	if [ "$RC_A" -eq 0 ]; then attempt "${a[@]}"; RC_A=$?; CONFLICT_A="$CONFLICT"; fi
	if [ "$RC_B" -eq 0 ]; then attempt "${b[@]}"; RC_B=$?; CONFLICT_B="$CONFLICT"; fi
	return 0
}

# Parallel halves need a second worktree of this repository and the memory for a second compile session.
WT2="${DQ_BATCH_WT2:-}"
parallel_ok() {
	[ -n "$WT2" ] && [ -e "$WT2/.git" ] && [ "${DQ_BATCH_PARALLEL:-1}" != 0 ] || return 1
	local free_kb min_gb="${DQ_BATCH_PARALLEL_MIN_FREE_GB:-16}"
	free_kb="$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
	if [ -n "$free_kb" ] && [ "$free_kb" -lt $((min_gb * 1048576)) ]; then
		echo "== the bisect runs one attempt at a time: $((free_kb / 1048576)) GB of RAM free (< ${min_gb} GB for a second compile session)"
		return 1
	fi
	return 0
}

# A conflict confined to shared, append-mostly docs (AGENTS.md, doc/**/*.md, tools/**/doc/*.md) is not a reason to bounce a lane: both
# sides are kept (git merge-file --union, per file, from the index stages) and the merge is committed; the gates then judge the result
# like any other tree. DQ_BATCH_DOC_UNION=0 turns it off. 2026-10-27: 5 of a batch of 8 bounced on AGENTS.md / incremental_core.md.
doc_union_conflict() {
	[ "${DQ_BATCH_DOC_UNION:-1}" = 1 ] || return 1
	local u f tmp
	u="$(git diff --name-only --diff-filter=U 2>/dev/null)"
	[ -n "$u" ] || return 1
	while IFS= read -r f; do
		case "$f" in AGENTS.md|CLAUDE.md|doc/*.md|tools/*/doc/*.md) ;; *) return 1 ;; esac
	done <<<"$u"
	tmp="$(mktemp -d)" || return 1
	while IFS= read -r f; do
		git show ":1:$f" >"$tmp/base" 2>/dev/null || : >"$tmp/base"
		git show ":2:$f" >"$tmp/ours" 2>/dev/null || { rm -rf "$tmp"; return 1; }
		git show ":3:$f" >"$tmp/theirs" 2>/dev/null || { rm -rf "$tmp"; return 1; }
		git merge-file --union -L ours -L base -L theirs "$tmp/ours" "$tmp/base" "$tmp/theirs"
		cat "$tmp/ours" >"$f" && git add -- "$f" || { rm -rf "$tmp"; return 1; }
	done <<<"$u"
	rm -rf "$tmp"
	git commit -q --no-edit >/dev/null 2>&1 || return 1
	echo "doc union: kept both sides of a conflict confined to shared docs: $(tr '\n' ' ' <<<"$u")"
	return 0
}

# A lane that conflicts with another lane of the batch, but merges cleanly with origin/master alone, is not at fault: it waits for the
# next cycle (BATCH_LATER), where it merges onto the new master. Only a conflict with master itself bounces.
merges_with_master() { # <lane>
	local scratch common rc=0
	common="$(git rev-parse --path-format=absolute --git-common-dir)"
	scratch="$(mktemp -d "${TMPDIR:-/tmp}/dq-batchprobe.XXXXXX")"
	GIT_OBJECT_DIRECTORY="$scratch" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common/objects" git merge-tree --write-tree --name-only --no-messages origin/master "$(ref_of "$1")" >/dev/null 2>&1 || rc=$?
	rm -rf "$scratch"
	[ "$rc" -eq 0 ]
}
later=()

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
		# a lane that cannot even merge: with master alone it merges -> it waits for the next cycle; with master it conflicts -> bounced
		if merges_with_master "$CONFLICT"; then
			later+=("$CONFLICT")
			echo "== $CONFLICT conflicts with another lane of this batch only (it merges with origin/master): it waits for the next cycle"
		else
			bounce "$CONFLICT" "merge conflict with master (rebase it: bash tools/dq_merge_master.sh in the lane, then enqueue again)" "${attempt_log[$current_key]:-}"
		fi
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
	if parallel_ok; then
		# Parallel bisect: good+remaining fails. Split remaining into halves L and R and gate good+L and good+R AT ONCE (two worktrees).
		# L fails: the culprit is in L (R waits in `rest`). L passes: good grows by L, and the culprit is in R (R failed on its own, or
		# only together with L: either way good+R now fails). One halving per gate wall time instead of one per attempt.
		sub=("${remaining[@]}"); rest=(); fail_key="${set[*]}"; prc=0
		while [ ${#sub[@]} -gt 1 ]; do
			mid=$(( ${#sub[@]} / 2 ))
			L=("${sub[@]:0:mid}"); R=("${sub[@]:mid}")
			attempt_pair "${good[*]-} ${L[*]}" "${good[*]-} ${R[*]}"
			if [ "$RC_A" -eq 92 ] || [ "$RC_A" -eq 93 ] || [ "$RC_B" -eq 92 ] || [ "$RC_B" -eq 93 ]; then
				if [ "$RC_A" -eq 93 ] || [ "$RC_B" -eq 93 ]; then prc=93; else prc=92; fi
				if [ "$RC_A" -eq 0 ]; then good+=("${L[@]}"); sub=("${R[@]}"); fi
				break
			fi
			if [ "$RC_A" -ne 0 ]; then
				rest=("${R[@]}" "${rest[@]+"${rest[@]}"}"); sub=("${L[@]}"); fail_key="${good[*]-}"; fail_key="${fail_key:+$fail_key }${L[*]}"
			else
				# the log that shows R failing: good+R itself when it failed, else the earlier set (good+L+R) that did
				if [ "$RC_B" -ne 0 ]; then fail_key="${good[*]-}"; fail_key="${fail_key:+$fail_key }${R[*]}"; fi
				good+=("${L[@]}"); sub=("${R[@]}")
			fi
		done
		if [ "$prc" -ne 0 ]; then
			[ "$prc" -eq 93 ] && capped=1
			echo "== the parallel bisect stopped ($([ "$prc" -eq 93 ] && echo 'capped' || echo 'deadline')); deferring [${sub[*]} ${rest[*]-}]"
			deferred+=("${sub[@]}" "${rest[@]+"${rest[@]}"}"); remaining=()
			continue
		fi
		culprit="${sub[0]}"
		if [ "${tried_rc[$fail_key]:-1}" = 91 ] && merges_with_master "$culprit"; then
			later+=("$culprit")
			echo "== $culprit conflicts with another lane of this batch only (it merges with origin/master): it waits for the next cycle"
			remaining=("${rest[@]+"${rest[@]}"}")
			continue
		fi
		if [ "${tried_rc[$fail_key]:-1}" = 91 ]; then why="merge conflict with master (rebase it: bash tools/dq_merge_master.sh in the lane, then enqueue again)"
		else why="the batch fails once it is merged (parallel bisect; logs data/merge-batch/$stamp.attempt*.log)"; fi
		bounce "$culprit" "$why" "${attempt_log[$fail_key]:-}"
		remaining=("${rest[@]+"${rest[@]}"}")
		continue
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
echo "BATCH_LATER: ${later[*]-}"
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
