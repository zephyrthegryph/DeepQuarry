#!/usr/bin/env bash
# The batch train: lanes enqueue and leave, ONE detached integrator lands everything that is waiting, together.
#
#   bash tools/dq_train.sh enqueue [--tests "a b"] [--light]   # from the lane's worktree, after commit: record branch + tip + tests, return
#   bash tools/dq_train.sh status [--json]                      # integrator, queue, bounced lanes (with report paths), recent landings
#   bash tools/dq_train.sh report <branch>                      # print a bounced lane's report
#   bash tools/dq_train.sh dequeue <branch>                     # withdraw a queued or bounced lane (the branch itself is untouched)
#   bash tools/dq_train.sh ensure                               # start the integrator when none is running (enqueue does this)
#   bash tools/dq_train.sh run                                  # the integrator itself (detached by `ensure`; one at a time)
#
# Lane flow (doc/rewrite/agent_workflow.md section 29):
#   1. focused tests green, `bash tools/ci/check_ratchets.sh --changed-only` clean, everything committed;
#   2. `bash tools/dq_train.sh enqueue --tests "<the lane's tests>"` (add --light for docs/tooling/Rust-only work); it returns at once;
#   3. `bash tools/dq_lane_pool.sh release <branch>`: the branch ref stays in the shared repository, the slot is free;
#   4. later: `bash tools/dq_train.sh status`. A lane that is not listed under queue/bounced has landed. A bounced lane has a report
#      (`dq_train.sh report <branch>`): lease a slot, fix, commit, enqueue again.
#
# The integrator (a detached process: `ensure` starts it through PowerShell Start-Process so that a shell that is killed after 30
# minutes does not take it along; guarded by a lock directory plus pid liveness, one at a time) repeats CYCLES until the queue is empty:
#   - takes the queued lanes in order, up to a size that fits the test budget (DQ_TRAIN_MAX_LANES, estimated test seconds <=
#     DQ_TRAIN_TEST_BUDGET_SEC from the recorded per-test times, tools/dq_train_estimate.js); the rest wait for the next cycle;
#   - a lane whose branch moved since it was enqueued, or that is gone, is bounced (re-enqueue it);
#   - all light lanes: tools/dq_land_batch.sh (cheap checks, no DM build); otherwise ONE gate on the combined tree in its own worktree
#     (DQ_TRAIN_WT, branch train/integ), through tools/dq_merge_batch.sh: merge every lane onto current origin/master in order (a lane that
#     conflicts is bounced), analyze gen + ratchets, one native compile of the production dme (no DreamMaker; CI keeps that cross-check),
#     one native test compile, the union of the lanes' tests + the smoke set with the test phase capped at 10 minutes (the gate's cap, DQ_TRAIN_TEST_MAX_MIN),
#     and on a failure a bisect that names the culprit lane(s), which are bounced; the rest is proved and pushed. A test that fails and
#     then passes alone is a flake (the gate's retry ledgers it in tools/dq_flake_log.sh) and bounces nobody;
#   - a test phase that hits the cap halves the batch (state: batch_limit) and the lanes wait for the next cycle; a single lane whose own
#     tests exceed the cap is bounced;
#   - pushes master with tools/dq_push_master.sh (the batch's merge-gates stamp is what the pre-push hook checks) and records the lanes
#     as landed. Master moving under the gate is not the lanes' fault: they stay queued and the next cycle repeats.
# Nothing here holds the merge lock: the train works in its own worktree and takes no lock for the gate. Nothing runs checkout, reset,
# restore, stash or cherry-pick, or deletes a lock file (the integrator's own lock directory is replaced only when its pid is dead).
#
# State (disposable, under DQ_TRAIN_STATE, default E:/dq-cache/train): queue/*.q, bounced/*.q, landed/*.landed, reports/*.md,
# log/train.log (every decision), log/cycle-*.log (a cycle's gate output), run.lock/, cycle.txt (phase now), batch_limit.
# Environment: DQ_TRAIN_WT, DQ_TRAIN_BRANCH, DQ_TRAIN_MAX_LANES (8), DQ_TRAIN_TEST_BUDGET_SEC (420), DQ_TRAIN_TEST_MAX_MIN (10),
# DQ_TRAIN_CYCLE_MAX_MIN (20: no new gate attempt starts after it), DQ_TRAIN_NO_START=1 (enqueue does not start the integrator),
# DQ_TRAIN_ONCE=1 (run one cycle), DQ_TRAIN_DRY_RUN=1 (everything but the push; lanes stay queued).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"
STATE="${DQ_TRAIN_STATE:-E:/dq-cache/train}"
WT="${DQ_TRAIN_WT:-E:/projects/dq-wt/train-base}"
TBRANCH="${DQ_TRAIN_BRANCH:-train/integ}"
MAX_LANES="${DQ_TRAIN_MAX_LANES:-8}"
TEST_BUDGET="${DQ_TRAIN_TEST_BUDGET_SEC:-420}"
TEST_MAX_MIN="${DQ_TRAIN_TEST_MAX_MIN:-10}"
CYCLE_MAX_MIN="${DQ_TRAIN_CYCLE_MAX_MIN:-20}"
Q="$STATE/queue"
BOUNCED="$STATE/bounced"
LANDED="$STATE/landed"
REPORTS="$STATE/reports"
LOGS="$STATE/log"

die() { echo "dq_train: $*" >&2; exit 1; }
init_state() { mkdir -p "$Q" "$BOUNCED" "$LANDED" "$REPORTS" "$LOGS" "$STATE/self" || die "cannot create $STATE"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# Every decision goes to the log (and to stdout).
tlog() { local line; line="$(now) train[$$]: $*"; echo "$line"; echo "$line" >>"$LOGS/train.log" 2>/dev/null || true; }
fname() { printf '%s' "$1" | tr '/' '_'; }
qfile() { echo "$Q/$(fname "$1").q"; }
qget() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }
queue_branches() { # oldest first
	local f
	for f in "$Q"/*.q; do [ -e "$f" ] && printf '%s %s\n' "$(qget "$f" seq)" "$(qget "$f" branch)"; done | sort -n | awk '{print $2}'
}
alive() { # <msys pid> [winpid]
	[ -n "${1:-}" ] || return 1
	kill -0 "$1" 2>/dev/null && return 0
	[ -n "${2:-}" ] && command -v tasklist >/dev/null 2>&1 && tasklist //FI "PID eq $2" //NH 2>/dev/null | grep -qw "$2"
}
repo_dir() { # the checkout the cycle reads and runs light batches from: the train's worktree, else the lane's (a pool slot persists), else the main checkout
	local o="${DQ_TRAIN_ORIGIN_REPO:-}"
	if [ -e "$WT/.git" ]; then echo "$WT"
	elif [ -n "$o" ] && [ -e "$o/.git" ]; then echo "$o"
	else echo "${DQ_TRAIN_MAIN_REPO:-E:/projects/CHOMPStation2}"; fi
}
G() { git -C "$(repo_dir)" "$@"; }
phase() { printf '%s\t%s\n' "$(date +%s)" "$*" >"$STATE/cycle.txt" 2>/dev/null || true; }
read_list() { # a tools/ci test list: names without comments
	[ -f "$1" ] || return 0
	sed -e 's/#.*//' -e 's/\r//' "$1" | awk 'NF {print $1}'
}

# ---- the integrator lock ----------------------------------------------------------------------------------------------------
integrator_pid() { sed -n 's/^pid=//p' "$STATE/run.lock/owner" 2>/dev/null; }
integrator_alive() { alive "$(integrator_pid)" "$(sed -n 's/^winpid=//p' "$STATE/run.lock/owner" 2>/dev/null)"; }
lock_take() {
	local d="$STATE/run.lock"
	if ! mkdir "$d" 2>/dev/null; then
		if integrator_alive; then return 1; fi
		tlog "replacing the lock of a dead integrator (pid $(integrator_pid))"
		rm -rf "$d"
		mkdir "$d" 2>/dev/null || return 1
	fi
	printf 'pid=%s\nwinpid=%s\nsince=%s\nscript=%s\n' "$$" "$(cat /proc/$$/winpid 2>/dev/null)" "$(now)" "$SELF" >"$d/owner"
	LOCK_HELD=1
}
lock_release() { [ "${LOCK_HELD:-0}" = 1 ] && [ "$(integrator_pid)" = "$$" ] && rm -rf "$STATE/run.lock"; LOCK_HELD=0; return 0; }

# ---- enqueue ----------------------------------------------------------------------------------------------------------------
cmd_enqueue() {
	local tests="" light=0 branch tip ahead heavy f owner
	while [ $# -gt 0 ]; do
		case "$1" in
			--tests) tests="${2:?--tests needs a value}"; shift ;;
			--light) light=1 ;;
			*) die "enqueue: unknown argument: $1" ;;
		esac
		shift
	done
	tests="${tests//,/ }"
	init_state
	cd "$(git rev-parse --show-toplevel)" || die "run enqueue inside the lane's worktree"
	branch="$(git symbolic-ref -q --short HEAD)" || die "a detached HEAD; run enqueue on the lane's branch"
	case "$branch" in master|main|rewrite/integ-current|"$TBRANCH") die "$branch is not a lane branch" ;; esac
	git update-index -q --refresh >/dev/null 2>&1
	[ -z "$(git status --porcelain --untracked-files=normal | head -n 1)" ] || die "the tree is not clean: commit your change first (the train takes the commit, nothing else)"
	git fetch -q origin || die "git fetch failed"
	ahead="$(git rev-list --count origin/master..HEAD)"
	[ "$ahead" -gt 0 ] || die "$branch holds nothing origin/master lacks: there is nothing to land"
	tip="$(git rev-parse HEAD)"
	if [ -n "$tests" ]; then
		. "$SELF_DIR/dq_declared_tests.sh"
		# shellcheck disable=SC2086
		validate_enqueue_tests HEAD $tests || die "REFUSED: fix the --tests list above (names must be declared runnable /datum/unit_test leaves in this tree)"
	fi
	if [ "$light" -eq 1 ]; then
		. "$SELF_DIR/dq_light_paths.sh"
		heavy="$(light_heavy_in origin/master HEAD)"
		if [ -n "$heavy" ]; then
			echo "$heavy" | head -8 >&2
			die "REFUSED: --light may not touch .dm/.dme/maps/icons/code/interface/sound/tgui (listed above): enqueue without --light"
		fi
		# the light batch merges origin/<branch>
		git push -q origin "HEAD:refs/heads/$branch" || die "could not push $branch to origin (never forced)"
	elif [ -z "$tests" ]; then
		echo "dq_train: note: no --tests: this lane is gated with the smoke set only (its own tests will not run on the train)" >&2
	fi
	owner="${DQ_LANE_OWNER:-${USERNAME:-${USER:-unknown}}}"
	f="$(qfile "$branch")"
	printf 'seq=%s\nbranch=%s\ntip=%s\ntests=%s\nlight=%s\nowner=%s\nsince=%s\nattempts=0\n' "$(date +%s%N)" "$branch" "$tip" "$tests" "$light" "$owner" "$(now)" >"$f.tmp" && mv -f "$f.tmp" "$f" || die "could not write $f"
	rm -f "$REPORTS/$(fname "$branch").md" "$BOUNCED/$(fname "$branch").q"
	tlog "enqueued $branch tip ${tip:0:10} light=$light tests=[${tests:-none}] owner=$owner ($ahead commit(s) ahead of origin/master)"
	if [ "${DQ_TRAIN_NO_START:-0}" != 1 ]; then DQ_TRAIN_ORIGIN_REPO="$(pwd)" cmd_ensure; fi
	echo "dq_train: $branch is queued. Release the slot now: bash tools/dq_lane_pool.sh release $branch   (the branch stays in the repository). Follow it: bash tools/dq_train.sh status"
}

# ---- starting the integrator -------------------------------------------------------------------------------------------------
start_detached() { # <script> <log>: a process outside this shell's process group, so a shell killed after 30 minutes leaves it alone
	local self="$1" log="$2"
	if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		DQ_TS_BASH="$(cygpath -w "$(command -v bash)")" DQ_TS_SELF="$(cygpath -w "$self")" DQ_TS_LOG="$(cygpath -w "$log")" \
			powershell.exe -NoProfile -NonInteractive -Command '$a = @($env:DQ_TS_SELF, "run"); Start-Process -WindowStyle Hidden -FilePath $env:DQ_TS_BASH -ArgumentList $a -RedirectStandardOutput $env:DQ_TS_LOG -RedirectStandardError ($env:DQ_TS_LOG + ".err")' >/dev/null 2>&1 && return 0
		tlog "Start-Process failed; falling back to nohup (the integrator then ends with a killed shell)"
	fi
	nohup bash "$self" run >>"$log" 2>&1 &
	disown $! 2>/dev/null || true
}
cmd_ensure() {
	init_state
	if integrator_alive; then tlog "integrator already running (pid $(integrator_pid)); the enqueued lane joins its next cycle"; return 0; fi
	# The watchdog callers (dq_lane_pool.sh lease and release) ask on every call: with nothing queued there is nothing to run.
	[ -n "$(queue_branches)" ] || return 0
	# The integrator runs from a snapshot (the lane's worktree is released and reset while it works); the helpers are read from its worktree.
	if [ "$SELF_DIR" != "$STATE/self" ]; then
		cp -f "$SELF" "$STATE/self/dq_train.sh" && cp -f "$SELF_DIR/dq_train_estimate.js" "$STATE/self/dq_train_estimate.js" || die "cannot snapshot the integrator into $STATE/self"
	fi
	export DQ_TRAIN_ORIGIN_REPO="${DQ_TRAIN_ORIGIN_REPO:-$(git rev-parse --show-toplevel)}"
	start_detached "$STATE/self/dq_train.sh" "$LOGS/integrator.out"
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		integrator_alive && { tlog "integrator started (pid $(integrator_pid))"; return 0; }
		sleep 2
	done
	tlog "WARNING: the integrator did not take its lock within 20 s; see $LOGS/integrator.out(.err); run: bash tools/dq_train.sh run"
	return 0
}

# ---- bounce and landed records ----------------------------------------------------------------------------------------------------
bounce() { # <branch> <reason> [<logfile>]
	local b="$1" why="$2" lg="${3:-}" f rep tip tests
	f="$(qfile "$b")"
	rep="$REPORTS/$(fname "$b").md"
	tip="$(qget "$f" tip)"; tests="$(qget "$f" tests)"
	{
		echo "# Train: $b was bounced"
		echo
		echo "- when: $(now)"
		echo "- tip: ${tip:-unknown}"
		echo "- tests it asked for: ${tests:-none}"
		echo "- why: $why"
		echo
		if [ -n "$lg" ] && [ -f "$lg" ]; then
			echo "## What the gate printed (last 70 lines of $lg)"
			echo
			echo '```'
			grep -hE '^FOCUSED RESULT:|^KNOWN FAILURES CHECK:|^FOCUSED RUN CAPPED|FAIL' "$lg" 2>/dev/null | sort -u | head -n 25
			echo '...'
			tail -n 70 "$lg"
			echo '```'
			echo
		fi
		echo "## Next"
		echo
		echo "Nothing was merged to master for this lane. Lease a slot (\`bash tools/dq_lane_pool.sh lease $b\`), fix the cause, run the lane's tests"
		echo "and \`bash tools/ci/check_ratchets.sh --changed-only\`, commit, and \`bash tools/dq_train.sh enqueue --tests \"...\"\` again."
		echo "A conflict: \`bash tools/dq_merge_master.sh\` in the lane first. The cycle's full log: $LOGS/ (cycle-*.log); decisions: $LOGS/train.log."
	} >"$rep"
	if [ -f "$f" ]; then
		{ cat "$f"; echo "bounced=$(now)"; echo "reason=$why"; echo "report=$rep"; } >"$BOUNCED/$(fname "$b").q"
		rm -f "$f"
	fi
	tlog "BOUNCED $b: $why (report $rep)"
}
mark_landed() { # <branch> <snapshot tip> <master sha>
	local b="$1" tip="$2" sha="$3" f
	f="$(qfile "$b")"
	printf 'branch=%s\ntip=%s\nmaster=%s\nlanded=%s\n' "$b" "$tip" "$sha" "$(now)" >"$LANDED/$(fname "$b").landed"
	# a lane that enqueued a newer tip while its old one rode the train stays queued
	if [ -f "$f" ] && [ "$(qget "$f" tip)" = "$tip" ]; then rm -f "$f"; fi
	tlog "LANDED $b (tip ${tip:0:10}) in origin/master ${sha:0:10}"
}
bump_attempts() { local f n; f="$(qfile "$1")"; [ -f "$f" ] || return 0; n="$(qget "$f" attempts)"; n=$(( ${n:-0} + 1 )); sed -i "s/^attempts=.*/attempts=$n/" "$f"; }

bump_push_refusals() { # <branch>: counts non-"master moved" push refusals in the queue file; prints the new count
	local f n; f="$(qfile "$1")"; [ -f "$f" ] || { echo 0; return 0; }
	n="$(qget "$f" push_refusals)"; n=$(( ${n:-0} + 1 ))
	if grep -q '^push_refusals=' "$f"; then sed -i "s/^push_refusals=.*/push_refusals=$n/" "$f"; else echo "push_refusals=$n" >>"$f"; fi
	echo "$n"
}

est_secs() { # test names...
	local dirs=() d runs
	runs="${DQ_TRAIN_RUNS_DIRS:-$(repo_dir)/data/test-runs E:/projects/dq-wt/merge-base/data/test-runs}"
	for d in $runs; do dirs+=(--runs "$d"); done
	node "$SELF_DIR/dq_train_estimate.js" "${dirs[@]}" "$@" 2>/dev/null || echo 9999
}

# ---- one cycle ------------------------------------------------------------------------------------------------------------------
LOCK_HELD=0
declare -A TIP_OF
CYCLE_PROGRESS=0

ensure_wt() {
	[ -e "$WT/.git" ] && return 0
	local origin free
	origin="$(repo_dir)"
	free="$(df -Pk "$(dirname "$WT")" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
	if [ -n "$free" ] && [ "$free" -lt "${DQ_TRAIN_MIN_FREE_GB:-60}" ] && [ -z "${DQ_TRAIN_NO_DISK_CHECK:-}" ]; then tlog "ERROR: only ${free} GB free for the train worktree"; return 1; fi
	phase "creating the train worktree (a one-time full checkout, slow)"
	tlog "creating the train worktree $WT (branch $TBRANCH on origin/master; a one-time full checkout, slow)"
	mkdir -p "$(dirname "$WT")"
	if git -C "$origin" show-ref -q --verify "refs/heads/$TBRANCH"; then
		git -C "$origin" worktree add --force "$WT" "$TBRANCH" >>"$LOGS/train.log" 2>&1 || return 1
	else
		git -C "$origin" worktree add -b "$TBRANCH" "$WT" origin/master >>"$LOGS/train.log" 2>&1 || return 1
	fi
	tlog "train worktree created; warming it (analyzer binary, generated files)"
	(cd "$WT" && tools/build/build.sh gen) >>"$LOGS/train.log" 2>&1 || tlog "warning: the warm-up gen failed (the gate will report it)"
	tlog "train worktree ready"
}

select_batch() { # fills CHOSEN from VALID, sized to the test budget
	set -f # test names such as dq_gameplay/* are patterns for the estimator, never for the shell
	CHOSEN=()
	local limit b union est lane_tests
	limit="$(cat "$STATE/batch_limit" 2>/dev/null)"
	case "$limit" in ''|*[!0-9]*|0) limit="$MAX_LANES" ;; esac
	[ "$limit" -gt "$MAX_LANES" ] && limit="$MAX_LANES"
	union="$(printf '%s\n' $(read_list "$(repo_dir)/tools/ci/smoke_tests.txt") $(read_list "$(repo_dir)/tools/ci/gameplay_tests.txt"))"
	for b in "${VALID[@]}"; do
		[ ${#CHOSEN[@]} -ge "$limit" ] && break
		lane_tests="$(qget "$(qfile "$b")" tests)"
		est="$(est_secs $union $lane_tests)"
		if [ ${#CHOSEN[@]} -gt 0 ] && [ "${est:-9999}" -gt "$TEST_BUDGET" ]; then
			tlog "deferred $b to a later cycle: the union of tests would be ~${est}s (> ${TEST_BUDGET}s budget)"
			continue
		fi
		CHOSEN+=("$b")
		union="$union $lane_tests"
		[ "${est:-0}" -gt "$TEST_BUDGET" ] && tlog "note: $b alone is estimated at ~${est}s of tests (> ${TEST_BUDGET}s); it rides alone"
	done
	BATCH_LIMIT_NOW="$limit"
	BATCH_EST="$(est_secs $union)"
	set +f
}

settle_shrink_leftovers() {
	# A gate whose tests fail leaves its in-job baseline shrink (dq_merge_gates.sh, shrink_after) uncommitted in the train worktree,
	# and dq_merge_batch.sh then refuses every later cycle ("uncommitted tracked changes"). That shrink is the gate's own output, never
	# a lane's work: put such files back to HEAD's content. Any other tracked change still stops the cycle as before.
	[ -d "$WT" ] || return 0
	local f dirty
	dirty="$(git -C "$WT" diff --name-only HEAD 2>/dev/null)"
	[ -n "$dirty" ] || return 0
	if printf '%s\n' "$dirty" | grep -qv -E '^tools/ci/([a-z_]+_baseline\.txt|sys_baseline/[A-Za-z0-9_.-]+)$'; then return 0; fi
	while IFS= read -r f; do
		git -C "$WT" show "HEAD:$f" >"$WT/$f" && tlog "reset a gate's leftover baseline shrink in the train worktree: $f"
	done <<<"$dirty"
}

light_cycle() { # CHOSEN are all light
	local b out lq lstate rc unlanded=() sha lg
	lstate="$STATE/light-state"
	lq="$lstate/light-queue"
	out="$LOGS/cycle-$(date +%Y%m%dT%H%M%S)-light.log"
	phase "light batch: ${CHOSEN[*]}"
	tlog "light cycle: ${CHOSEN[*]} (tools/dq_land_batch.sh; no DM build, cheap checks only); log $out"
	mkdir -p "$lq"
	for b in "${CHOSEN[@]}"; do
		printf 'branch=%s\ntip=%s\nowner=train\nsince=%s\n' "$b" "${TIP_OF[$b]}" "$(now)" >"$lq/$(fname "$b").q"
	done
	( cd "$(repo_dir)" && DQ_LANE_POOL_STATE="$lstate" DQ_MERGE_SESSION="train-light-$$" bash tools/dq_land_batch.sh run ) >"$out" 2>&1
	rc=$?
	G fetch -q origin
	for b in "${CHOSEN[@]}"; do
		if G merge-base --is-ancestor "${TIP_OF[$b]}" origin/master; then :; else unlanded+=("$b"); fi
	done
	if [ ${#unlanded[@]} -gt 1 ]; then
		# several lanes did not land and the batch cannot say which is at fault (a conflict skips one lane, but cheap checks fail for the
		# whole merge): one lane at a time, the checks are cheap
		local again=("${unlanded[@]}") one
		unlanded=()
		rm -f "$lq"/*.q
		for one in "${again[@]}"; do
			printf 'branch=%s\ntip=%s\nowner=train\nsince=%s\n' "$one" "${TIP_OF[$one]}" "$(now)" >"$lq/$(fname "$one").q"
			tlog "light lane $one retried alone"
			( cd "$(repo_dir)" && DQ_LANE_POOL_STATE="$lstate" DQ_MERGE_SESSION="train-light-$$" bash tools/dq_land_batch.sh run ) >"$out.$(fname "$one")" 2>&1
			G fetch -q origin
			G merge-base --is-ancestor "${TIP_OF[$one]}" origin/master || unlanded+=("$one")
			rm -f "$lq"/*.q
		done
	fi
	rm -f "$lq"/*.q
	sha="$(G rev-parse origin/master)"
	for b in "${CHOSEN[@]}"; do
		if [[ " ${unlanded[*]-} " == *" $b "* ]]; then
			lg="$out"; [ -f "$out.$(fname "$b")" ] && lg="$out.$(fname "$b")"
			bounce "$b" "the light batch did not land it (a conflict with master or the batch, or its cheap checks failed)" "$lg"
			CYCLE_PROGRESS=1
		else
			mark_landed "$b" "${TIP_OF[$b]}" "$sha"; CYCLE_PROGRESS=1
		fi
	done
}

heavy_cycle() {
	local b out rc stamp good bounced_lines deferred capped line lane why lg pushlog prc tests_union lane_test_args lane_tests sha deadline
	ensure_wt || { tlog "ERROR: no train worktree; the cycle is skipped"; return 20; }
	stamp="$(date +%Y%m%dT%H%M%S)"
	out="$LOGS/cycle-$stamp.log"
	tests_union=""; lane_test_args=()
	for b in "${CHOSEN[@]}"; do
		lane_tests="$(qget "$(qfile "$b")" tests)"
		tests_union="$tests_union $lane_tests"
		lane_test_args+=(--lane-tests "$b=$lane_tests")
	done
	set -f
	tests_union="$(printf '%s\n' $tests_union | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
	set +f
	if [ -z "${tests_union// /}" ]; then tests_union="dq_boot_gate"; lane_test_args+=(--tests dq_boot_gate); fi
	deadline=$(( $(date +%s) + CYCLE_MAX_MIN * 60 ))
	phase "gate: ${CHOSEN[*]}"
	tlog "heavy cycle: ${#CHOSEN[@]} lane(s) [${CHOSEN[*]}], tests [$tests_union] (+ smoke set, est ~${BATCH_EST}s), test cap ${TEST_MAX_MIN} min, no new attempt after $(date -u -d "@$deadline" +%H:%MZ 2>/dev/null || echo "$CYCLE_MAX_MIN min"); log $out"
	for b in "${CHOSEN[@]}"; do bump_attempts "$b"; done
	(
		cd "$WT" || exit 99
		export DQ_MERGE_BRANCH="$TBRANCH" DQ_MERGE_SESSION="train-$$" DQ_DREAMMAKER_GATE=0 DQ_FOCUSED_MAX_MIN="$TEST_MAX_MIN"
		export DQ_SLOT_PRIORITY=0 DQ_PUSH_STRICT=1 DQ_PUSH_NO_REPROOF=1 DQ_PUSH_TRUST_GATE_DM=1 DQ_BATCH_DEADLINE="$deadline"
		# DreamChecker is a gate job of its own (parallel to the tests, a failure bisects to the culprit lane): the native compiler accepts
		# undefined fields DreamChecker rejects, and the push trusts the gate only with the gate's dreamchecker stamp on the exact HEAD.
		export DQ_GATE_DREAMCHECKER=1
		# --no-dm: the test build compile already proves the code compiles; a second full native compile run in parallel starved the test
		# build of the compile slot, memory and CPU, and the test world was killed at the cap. CI keeps the production compile cross-check.
		bash tools/dq_merge_batch.sh --lanes "${CHOSEN[*]}" "${lane_test_args[@]}" --no-dm
	) >"$out" 2>&1
	rc=$?
	good="$(sed -n 's/^BATCH_GOOD: //p' "$out" | tail -n 1)"
	deferred="$(sed -n 's/^BATCH_DEFERRED: //p' "$out" | tail -n 1)"
	capped="$(sed -n 's/^BATCH_CAPPED: //p' "$out" | tail -n 1)"
	tlog "merge_batch rc=$rc good=[${good:-}] deferred=[${deferred:-}] capped=[${capped:-}]"
	# bounces first: they are the lane's fault whatever happens to the push
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		lane="${line%%|*}"; why="${line#*|}"; lg="${why##*|}"; why="${why%|*}"
		[ -n "$lane" ] || continue
		bounce "$lane" "$why" "$WT/$lg"
		CYCLE_PROGRESS=1
	done < <(sed -n 's/^BATCH_BOUNCED: //p' "$out")
	if [ -n "${capped:-}" ]; then
		local half=$(( ${#CHOSEN[@]} / 2 )); [ "$half" -lt 1 ] && half=1
		echo "$half" >"$STATE/batch_limit"
		tlog "the test phase hit its ${TEST_MAX_MIN} min cap with ${#CHOSEN[@]} lane(s): batch limit is now $half; the deferred lanes [${deferred:-}] ride a smaller batch"
		CYCLE_PROGRESS=1
	fi
	if [ -z "${good:-}" ]; then
		tlog "nothing passed in this cycle"
		return 0
	fi
	phase "push: $good"
	pushlog="$LOGS/cycle-$stamp.push.log"
	(
		cd "$WT" || exit 99
		export DQ_MERGE_SESSION="train-$$" DQ_DREAMMAKER_GATE=0 DQ_PUSH_STRICT=1 DQ_PUSH_NO_REPROOF=1 DQ_PUSH_TRUST_GATE_DM=1
		[ "${DQ_TRAIN_DRY_RUN:-0}" = 1 ] && export DQ_PUSH_DRY_RUN=1
		bash tools/dq_push_master.sh --expect "$good"
	) >"$pushlog" 2>&1
	prc=$?
	if [ "$prc" -ne 0 ]; then
		local refusal
		refusal="$(grep -m1 -E 'REFUSED|rejected' "$pushlog" | head -c 300)"
		[ -n "$refusal" ] || refusal="$(tail -n 1 "$pushlog" | head -c 300)"
		tlog "push FAILED (rc=$prc): the lanes [$good]; see $pushlog: $refusal"
		if grep -qE 'origin/master moved|master moved|push rejected|origin/master is not' <<<"$refusal"; then
			tlog "push refused because master moved: the lanes [$good] stay queued for the next cycle"
			return 0
		fi
		# Any other refusal (a stamp, a hook, a missing check) repeats on the same tree: after 2 attempts the lanes are bounced with the
		# refusal line as the reason, so a lane never sits queued behind a refusal nobody sees.
		for b in $good; do
			local n; n="$(bump_push_refusals "$b")"
			if [ "${n:-0}" -ge 2 ]; then
				bounce "$b" "the gate passed but the push was refused $n times for a reason other than master moving: $refusal" "$pushlog"
				CYCLE_PROGRESS=1
			else
				tlog "push refusal $n of 2 for $b; it stays queued for one more attempt"
			fi
		done
		return 0
	fi
	if [ "${DQ_TRAIN_DRY_RUN:-0}" = 1 ]; then tlog "DRY RUN: [$good] passed the gate and every push check; nothing pushed, the lanes stay queued"; return 0; fi
	G fetch -q origin
	sha="$(G rev-parse origin/master)"
	for b in $good; do mark_landed "$b" "${TIP_OF[$b]}" "$sha"; done
	CYCLE_PROGRESS=1
	if [ -z "${capped:-}" ]; then
		local lim; lim="$(cat "$STATE/batch_limit" 2>/dev/null)"; lim="${lim:-$MAX_LANES}"
		lim=$(( lim * 2 )); [ "$lim" -gt "$MAX_LANES" ] && lim="$MAX_LANES"
		echo "$lim" >"$STATE/batch_limit"
	fi
	tlog "pushed: origin/master ${sha:0:10} carries [$good]"
}

cycle() {
	local b f tip cur all=() t0
	t0=$(date +%s)
	CYCLE_PROGRESS=0
	phase "fetch"
	G fetch -q origin 2>/dev/null || tlog "warning: git fetch failed"
	settle_shrink_leftovers
	mapfile -t all < <(queue_branches)
	[ ${#all[@]} -gt 0 ] || return 10
	VALID=()
	TIP_OF=()
	for b in "${all[@]}"; do
		f="$(qfile "$b")"
		tip="$(qget "$f" tip)"
		cur="$(G rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null || G rev-parse -q --verify "refs/remotes/origin/$b^{commit}" 2>/dev/null || true)"
		if [ -z "$cur" ]; then bounce "$b" "the branch no longer exists in the repository (deleted or renamed after enqueue)"; CYCLE_PROGRESS=1; continue; fi
		if [ "$cur" != "$tip" ]; then bounce "$b" "the branch moved after it was enqueued (queued ${tip:0:10}, now ${cur:0:10}); the train lands exactly what was enqueued: enqueue the new tip"; CYCLE_PROGRESS=1; continue; fi
		if G merge-base --is-ancestor "$tip" origin/master; then mark_landed "$b" "$tip" "$(G rev-parse origin/master)"; tlog "$b was already in origin/master"; CYCLE_PROGRESS=1; continue; fi
		TIP_OF[$b]="$tip"
		VALID+=("$b")
	done
	[ ${#VALID[@]} -gt 0 ] || return 0
	select_batch
	local all_light=1
	for b in "${CHOSEN[@]}"; do [ "$(qget "$(qfile "$b")" light)" = 1 ] || all_light=0; done
	tlog "cycle: queue=[${all[*]}] valid=[${VALID[*]}] chosen=[${CHOSEN[*]}] (limit $BATCH_LIMIT_NOW, est ~${BATCH_EST}s of tests) all_light=$all_light"
	# Disk budget (tools/dq_disk_budget.sh): enforce the caps at every cycle start; below the floor a heavy cycle is not started (the lanes stay queued).
	if [ "$all_light" -eq 1 ]; then
		bash "$SELF_DIR/dq_disk_budget.sh" enforce --quiet --throttle 10 >>"$LOGS/train.log" 2>&1 || true
		light_cycle
	else
		if ! bash "$SELF_DIR/dq_disk_budget.sh" gate "a heavy train cycle" --sync --throttle 10 >>"$LOGS/train.log" 2>&1; then
			tlog "disk floor: the cycle is skipped, the lanes stay queued; free space (see the REFUSED message above in this log), then the next cycle runs"
			return 0
		fi
		heavy_cycle
	fi
	local rc=$?
	tlog "cycle done in $(( $(date +%s) - t0 ))s (rc=$rc, progress=$CYCLE_PROGRESS)"
	return "$rc"
}

cmd_run() {
	init_state
	# the lane's checkout that started us (ensure exports it); a hand-started run uses the checkout it runs in
	export DQ_TRAIN_ORIGIN_REPO="${DQ_TRAIN_ORIGIN_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
	lock_take || { echo "dq_train: an integrator is already running (pid $(integrator_pid))"; exit 0; }
	trap 'lock_release; phase "idle"' EXIT
	tlog "integrator started (pid $$, script $SELF, state $STATE, worktree $WT)"
	local idle=0 rc stalls=0
	while :; do
		cycle
		rc=$?
		if [ "$rc" -eq 10 ]; then
			# the queue is empty: leave the lock, then look once more (a lane may have enqueued after the last look)
			lock_release
			[ -n "$(queue_branches)" ] && lock_take && continue
			tlog "queue empty; integrator exits"
			exit 0
		fi
		[ "${DQ_TRAIN_ONCE:-0}" = 1 ] && { tlog "DQ_TRAIN_ONCE: stopping after one cycle"; exit 0; }
		if [ "$CYCLE_PROGRESS" -eq 0 ]; then
			idle=$((idle + 1))
			if [ "$idle" -ge "${DQ_TRAIN_STALL_CYCLES:-3}" ]; then
				# Never exit on a stall (an exited integrator sat idle for 3 hours with lanes queued): back off and keep running.
				stalls=$((stalls + 1))
				tlog "STALLED: $idle cycles without a landing or a bounce (master keeps moving, or the push is refused); lanes stay queued; backing off ${DQ_TRAIN_STALL_BACKOFF_SEC:-300}s, the integrator keeps running. See $LOGS/"
				if [ -n "${DQ_TRAIN_STALL_EXIT_AFTER:-}" ] && [ "$stalls" -ge "$DQ_TRAIN_STALL_EXIT_AFTER" ]; then tlog "DQ_TRAIN_STALL_EXIT_AFTER: stopping after $stalls stall(s)"; exit 1; fi
				idle=0
				sleep "${DQ_TRAIN_STALL_BACKOFF_SEC:-300}"
				continue
			fi
			sleep "${DQ_TRAIN_RETRY_SEC:-60}"
		else
			idle=0
		fi
	done
}

# ---- status, report, dequeue ----------------------------------------------------------------------------------------------------
cmd_status() {
	init_state
	local f b age n=0
	if integrator_alive; then
		echo "integrator: RUNNING pid $(integrator_pid) since $(sed -n 's/^since=//p' "$STATE/run.lock/owner"); phase: $(cut -f2 "$STATE/cycle.txt" 2>/dev/null) ($(( $(date +%s) - $(cut -f1 "$STATE/cycle.txt" 2>/dev/null || echo 0) ))s ago)"
	else
		echo "integrator: not running$([ -n "$(queue_branches)" ] && echo " (lanes are waiting: bash tools/dq_train.sh ensure)")"
	fi
	echo "batch limit: $(cat "$STATE/batch_limit" 2>/dev/null || echo "$MAX_LANES (default)") lane(s) per cycle"
	echo "queue:"
	for b in $(queue_branches); do
		f="$(qfile "$b")"; n=$((n + 1))
		echo "  $b  tip $(qget "$f" tip | cut -c1-10)  $([ "$(qget "$f" light)" = 1 ] && echo light || echo "tests: $(qget "$f" tests)")  enqueued $(qget "$f" since)  gate attempts: $(qget "$f" attempts)"
	done
	[ "$n" -gt 0 ] || echo "  (empty)"
	n=0
	echo "bounced (fix, then enqueue again):"
	for f in "$BOUNCED"/*.q; do
		[ -e "$f" ] || continue
		n=$((n + 1))
		echo "  $(qget "$f" branch): $(qget "$f" reason)"
		echo "      report: $(qget "$f" report)"
	done
	[ "$n" -gt 0 ] || echo "  (none)"
	echo "landed (latest 8):"
	n=0
	for f in $(ls -t "$LANDED"/*.landed 2>/dev/null | head -n 8); do echo "  $(qget "$f" branch)  $(qget "$f" landed)  master $(qget "$f" master | cut -c1-10)"; n=$((n + 1)); done
	[ "$n" -gt 0 ] || echo "  (none yet)"
	echo "log: $LOGS/train.log"
}
cmd_report() {
	local b="${1:?usage: report <branch>}" r
	r="$REPORTS/$(fname "$b").md"
	[ -f "$r" ] || { if [ -f "$(qfile "$b")" ]; then echo "$b is queued, not bounced"; elif [ -f "$LANDED/$(fname "$b").landed" ]; then echo "$b landed: $(tr '\n' ' ' <"$LANDED/$(fname "$b").landed")"; else echo "no record of $b"; fi; return 0; }
	cat "$r"
}
cmd_dequeue() {
	local b="${1:?usage: dequeue <branch>}"
	rm -f "$(qfile "$b")" "$BOUNCED/$(fname "$b").q"
	tlog "dequeued $b (by hand)"
}

case "${1:-}" in
	enqueue) shift; cmd_enqueue "$@" ;;
	status) shift; cmd_status "$@" ;;
	report) shift; cmd_report "$@" ;;
	dequeue) shift; cmd_dequeue "$@" ;;
	ensure) cmd_ensure ;;
	run) cmd_run ;;
	*) sed -n '2,12p' "$0"; exit 2 ;;
esac
