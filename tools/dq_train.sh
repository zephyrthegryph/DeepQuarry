#!/usr/bin/env bash
# The batch train: lanes enqueue and leave, ONE detached integrator lands everything that is waiting, together.
#
#   bash tools/dq_train.sh enqueue [--tests "a b"] [--light]   # from the lane's worktree, after commit: record branch + tip + tests, return
#   bash tools/dq_train.sh status [--json]                      # integrator, queue, bounced lanes (with report paths), recent landings
#   bash tools/dq_train.sh report <branch>                      # print a bounced lane's report
#   bash tools/dq_train.sh dequeue <branch>                     # withdraw a queued or bounced lane (the branch itself is untouched)
#   bash tools/dq_train.sh ensure                               # start the integrator when none is running (enqueue does this)
#   bash tools/dq_train.sh run                                  # the integrator itself (detached by `ensure`; one at a time)
#   bash tools/dq_train.sh precheck-run                         # the prechecker (detached by `ensure` and by every cycle; one at a time)
#
# Prechecks (October 2026, tools/train-speed; doc section 29 "Prechecks"): the prechecker gates every queued heavy lane ALONE on current
# origin/master (tools/dq_merge_batch.sh on that one lane, in its own worktree DQ_TRAIN_PRE_WT<N>, DQ_TRAIN_PRECHECK_WORKERS at once,
# none started below DQ_TRAIN_PRECHECK_MIN_FREE_GB of free RAM), after a seconds-long `git merge-tree` conflict probe. A lane that fails
# alone is bounced at once with its report; the verdict is kept per (master, tip) under $STATE/precheck/v. Batches take only lanes with a
# PASS (light lanes need none), up to DQ_TRAIN_MAX_LANES_PRECHECKED (20); such a batch runs the own tests only of lanes that share an
# area with another lane or with master's changes since their precheck, has no cycle deadline (its bisect runs to the end, both halves
# at once in DQ_TRAIN_WT2), and a failure in it is an interaction. A lane with no verdict after DQ_TRAIN_PRECHECK_WAIT_MIN rides the old
# way below. DQ_TRAIN_PRECHECK=0 turns prechecks off.
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
#   - a batch that fails is bisected ACROSS cycles (a bisect is several 20-minute attempts, a cycle allows one): dq_merge_batch.sh saves
#     every attempt verdict in $STATE/bisect.cache (DQ_BATCH_CACHE) and the deferred lanes are recorded in $STATE/bisect.lanes. While that
#     file exists the next cycle takes exactly those lanes (new lanes wait, they never join a bisect) and resumes at the next untried
#     attempt, never the full batch again; the first real attempt of a cycle and every single-lane attempt ignore the cycle deadline, so a
#     lane proven bad alone is BOUNCED, never deferred. A cycle that bounced or deferred something halves the next batch (batch_limit);
#   - a test phase that hits the cap halves the batch (state: batch_limit) and the lanes wait for the next cycle; a single lane whose own
#     tests exceed the cap is bounced;
#   - pushes master with tools/dq_push_master.sh (the batch's merge-gates stamp is what the pre-push hook checks) and records the lanes
#     as landed. Master moving under the gate is not the lanes' fault: they stay queued and the next cycle repeats.
# Self-update: the integrator runs from a snapshot of SNAP_FILES under $STATE/self. At the start of every cycle (never inside one) it
# fetches and compares the snapshot's files with origin/master's tools/ copies; on a difference it logs "self-update: <files> changed
# on master; re-exec", refreshes the snapshot with git show, checks the new scripts with bash -n and execs the new dq_train.sh with the
# same arguments, keeping the run lock and pid. A new version that does not parse is logged (SELF-UPDATE REFUSED) and not run.
# DQ_TRAIN_SELF_UPDATE=0 turns it off.
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
ORIG_ARGS=("$@")
# Every file the integrator runs from SELF_DIR (the snapshot under $STATE/self), relative to tools/. The ONE place to list them: ensure
# copies these, and the self-update compares and refreshes these. A script the cycle runs through "$SELF_DIR/..." goes here
# (tools/ci/test_train.sh fails when one is missing); dq_declared_tests.sh and dq_light_paths.sh are enqueue-only (the lane's checkout).
SNAP_FILES=(dq_train.sh dq_train_estimate.js dq_disk_budget.sh ci/disk_budget.toml)
STATE="${DQ_TRAIN_STATE:-E:/dq-cache/train}"
WT="${DQ_TRAIN_WT:-E:/projects/dq-wt/train-base}"
TBRANCH="${DQ_TRAIN_BRANCH:-train/integ}"
MAX_LANES="${DQ_TRAIN_MAX_LANES:-8}"
TEST_BUDGET="${DQ_TRAIN_TEST_BUDGET_SEC:-420}"
TEST_MAX_MIN="${DQ_TRAIN_TEST_MAX_MIN:-10}"
CYCLE_MAX_MIN="${DQ_TRAIN_CYCLE_MAX_MIN:-20}"
# Prechecks (section 29 "Prechecks"): every heavy lane is gated ALONE on current master by a separate detached process (`precheck-run`)
# in its own worktree(s), in parallel with the batch gate; a lane that fails alone is bounced at once and never joins a batch.
PRE_ON="${DQ_TRAIN_PRECHECK:-1}"
PRE_WORKERS="${DQ_TRAIN_PRECHECK_WORKERS:-2}"
PRE_WT_BASE="${DQ_TRAIN_PRE_WT:-E:/projects/dq-wt/train-pre}"   # worker N works in ${PRE_WT_BASE}N
PRE_WAIT_MIN="${DQ_TRAIN_PRECHECK_WAIT_MIN:-45}"                 # an unprechecked lane rides the old way after waiting this long
PRE_MIN_FREE_GB="${DQ_TRAIN_PRECHECK_MIN_FREE_GB:-16}"          # a precheck does not START below this much free RAM (the user's desktop)
MAX_LANES_PRE="${DQ_TRAIN_MAX_LANES_PRECHECKED:-20}"            # batch size when every lane is prechecked
WT2="${DQ_TRAIN_WT2:-E:/projects/dq-wt/train-bisect}"           # the second worktree of a parallel bisect
PRE="$STATE/precheck"
Q="$STATE/queue"
BOUNCED="$STATE/bounced"
LANDED="$STATE/landed"
REPORTS="$STATE/reports"
LOGS="$STATE/log"

die() { echo "dq_train: $*" >&2; exit 1; }
init_state() { mkdir -p "$Q" "$BOUNCED" "$LANDED" "$REPORTS" "$LOGS" "$STATE/self" "$PRE/v" "$PRE/running" "$PRE/probe" || die "cannot create $STATE"; }
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

# ---- the integrator lock (and the prechecker's: the same protocol on another directory) ---------------------------------------
# LOCK_NAME is the lock this process takes: run.lock (the integrator) or precheck.lock (the prechecker, `precheck-run`).
LOCK_NAME="run.lock"
lockdir_pid() { sed -n 's/^pid=//p' "$STATE/$1/owner" 2>/dev/null; }
lockdir_alive() { alive "$(lockdir_pid "$1")" "$(sed -n 's/^winpid=//p' "$STATE/$1/owner" 2>/dev/null)"; }
integrator_pid() { lockdir_pid run.lock; }
integrator_alive() { lockdir_alive run.lock; }
prechecker_alive() { lockdir_alive precheck.lock; }
lock_take() {
	local d="$STATE/$LOCK_NAME" who="integrator"
	[ "$LOCK_NAME" = run.lock ] || who="prechecker"
	if ! mkdir "$d" 2>/dev/null; then
		if lockdir_alive "$LOCK_NAME"; then return 1; fi
		tlog "replacing the lock of a dead $who (pid $(lockdir_pid "$LOCK_NAME"))"
		rm -rf "$d"
		mkdir "$d" 2>/dev/null || return 1
	fi
	printf 'pid=%s\nwinpid=%s\nsince=%s\nscript=%s\n' "$$" "$(cat /proc/$$/winpid 2>/dev/null)" "$(now)" "$SELF" >"$d/owner"
	LOCK_HELD=1
}
lock_release() { [ "${LOCK_HELD:-0}" = 1 ] && [ "$(lockdir_pid "$LOCK_NAME")" = "$$" ] && rm -rf "$STATE/$LOCK_NAME"; LOCK_HELD=0; return 0; }

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
	# enqueueing a tip again asks for a fresh precheck: forget this tip's verdicts and probe marks
	find "$PRE/v" "$PRE/probe" -maxdepth 1 -type f -name "$(fname "$branch")@${tip:0:12}@*" -delete 2>/dev/null
	tlog "enqueued $branch tip ${tip:0:10} light=$light tests=[${tests:-none}] owner=$owner ($ahead commit(s) ahead of origin/master)"
	if [ "${DQ_TRAIN_NO_START:-0}" != 1 ]; then DQ_TRAIN_ORIGIN_REPO="$(pwd)" cmd_ensure; fi
	echo "dq_train: $branch is queued. Release the slot now: bash tools/dq_lane_pool.sh release $branch   (the branch stays in the repository). Follow it: bash tools/dq_train.sh status"
}

# ---- starting the integrator -------------------------------------------------------------------------------------------------
start_detached() { # <script> <log> [<command>, default run]: a process outside this shell's process group, so a shell killed after 30 minutes leaves it alone
	local self="$1" log="$2" what="${3:-run}"
	if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		DQ_TS_BASH="$(cygpath -w "$(command -v bash)")" DQ_TS_SELF="$(cygpath -w "$self")" DQ_TS_LOG="$(cygpath -w "$log")" DQ_TS_WHAT="$what" \
			powershell.exe -NoProfile -NonInteractive -Command '$a = @($env:DQ_TS_SELF, $env:DQ_TS_WHAT); Start-Process -WindowStyle Hidden -FilePath $env:DQ_TS_BASH -ArgumentList $a -RedirectStandardOutput $env:DQ_TS_LOG -RedirectStandardError ($env:DQ_TS_LOG + ".err")' >/dev/null 2>&1 && return 0
		tlog "Start-Process failed; falling back to nohup (the integrator then ends with a killed shell)"
	fi
	nohup bash "$self" "$what" >>"$log" 2>&1 &
	disown $! 2>/dev/null || true
}
# ---- the snapshot and its self-update ------------------------------------------------------------------------------------------------
in_snapshot() { [ -d "$STATE/self" ] && [ "$(cd "$STATE/self" && pwd)" = "$SELF_DIR" ]; }
snapshot_install() { # <from dir> <to dir>: SNAP_FILES, plain copies (dq_train.sh last: it may be the running script)
	local f i from="$1" to="$2"
	mkdir -p "$to/ci" || return 1
	for (( i = ${#SNAP_FILES[@]} - 1; i >= 0; i-- )); do
		f="${SNAP_FILES[$i]}"
		cp -f "$from/$f" "$to/$f" || return 1
	done
}
snap_syntax_ok() { # <dir>: every script in it parses; prints the first failure
	local f
	for f in "${SNAP_FILES[@]}"; do
		case "$f" in
			*.sh) bash -n "$1/$f" 2>&1 || { echo "bash -n failed for $f"; return 1; } ;;
			*.js) if command -v node >/dev/null 2>&1; then node --check "$1/$f" 2>&1 || { echo "node --check failed for $f"; return 1; }; fi ;;
		esac
	done
	return 0
}
SELF_UPDATE_BAD=""
SELF_UPDATE_LAST="${DQ_TRAIN_REEXEC_AT:-0}"
SELF_SIG="${DQ_TRAIN_TEST_SELF_SIG:-$(git hash-object --no-filters "$SELF" 2>/dev/null)}" # the code this process runs (self_update notices a refreshed snapshot)
# Between cycles, never in one: when a script of the snapshot differs from origin/master's copy, refresh the snapshot from origin/master
# (git show, no checkout), check that it parses, and exec the new dq_train.sh with the same arguments. The run lock and the integrator's
# identity are kept (DQ_TRAIN_REEXEC=1 makes the new process adopt its own lock). A new version that does not parse is never run: the
# old copy keeps going and the refusal is logged loudly once per master version.
self_update() {
	[ "${DQ_TRAIN_SELF_UPDATE:-1}" = 1 ] || return 0
	in_snapshot || return 0
	local f cur want changed=() sig="" stage d
	G fetch -q origin 2>/dev/null || { tlog "warning: self-update: git fetch failed; keeping the current scripts"; return 0; }
	for f in "${SNAP_FILES[@]}"; do
		want="$(G rev-parse -q --verify "origin/master:tools/$f" 2>/dev/null)"
		if [ -z "$want" ]; then continue; fi # not on master (yet): nothing to refresh to
		sig="$sig $want"
		cur=""
		[ -f "$STATE/self/$f" ] && cur="$(git hash-object --no-filters "$STATE/self/$f" 2>/dev/null)"
		[ "$cur" = "$want" ] || changed+=("$f")
	done
	if [ ${#changed[@]} -eq 0 ]; then
		# The snapshot is current, but another process of the train (the integrator or the prechecker: both run it) may have refreshed it
		# after this one started: re-exec into it, or this process keeps running the old code until it exits.
		if [ -n "$SELF_SIG" ] && [ "$(git hash-object --no-filters "$SELF" 2>/dev/null)" != "$SELF_SIG" ] && [ $(( $(date +%s) - SELF_UPDATE_LAST )) -ge 30 ] \
			&& d="$(snap_syntax_ok "$STATE/self")"; then
			tlog "self-update: $SELF was refreshed by another train process; re-exec"
			export DQ_TRAIN_REEXEC=1 DQ_TRAIN_REEXEC_AT="$(date +%s)"
			exec bash "$STATE/self/dq_train.sh" "${ORIG_ARGS[@]}"
		fi
		return 0
	fi
	[ "$sig" != "$SELF_UPDATE_BAD" ] || return 0
	if [ $(( $(date +%s) - SELF_UPDATE_LAST )) -lt 30 ]; then return 0; fi # never a tight re-exec loop
	stage="$STATE/self.new"
	rm -rf "$stage"; mkdir -p "$stage/ci" || return 0
	for f in "${SNAP_FILES[@]}"; do
		G show "origin/master:tools/$f" >"$stage/$f" 2>/dev/null || { tlog "ERROR: self-update: cannot read tools/$f from origin/master; keeping the current scripts"; SELF_UPDATE_BAD="$sig"; rm -rf "$stage"; return 0; }
	done
	d="$(snap_syntax_ok "$stage")" || {
		tlog "ERROR: SELF-UPDATE REFUSED: [${changed[*]}] changed on master but the new copy does not parse ($d); the integrator keeps running the OLD copy; fix master's tools/"
		SELF_UPDATE_BAD="$sig"; rm -rf "$stage"; return 0
	}
	tlog "self-update: ${changed[*]} changed on master; re-exec"
	snapshot_install "$stage" "$STATE/self" || { tlog "ERROR: self-update: could not refresh $STATE/self; keeping the current scripts"; rm -rf "$stage"; return 0; }
	rm -rf "$stage"
	export DQ_TRAIN_REEXEC=1 DQ_TRAIN_REEXEC_AT="$(date +%s)"
	exec bash "$STATE/self/dq_train.sh" "${ORIG_ARGS[@]}"
	tlog "ERROR: self-update: exec failed"; return 0
}
# Runs tools/dq_disk_budget.sh from the integrator's snapshot, else from the worktree it was started from; missing is a warning (rc 0), never a refusal.
disk_budget() {
	local s="$SELF_DIR/dq_disk_budget.sh" rc
	[ -f "$s" ] && [ -f "$SELF_DIR/ci/disk_budget.toml" ] || s="${DQ_TRAIN_ORIGIN_REPO:-}/tools/dq_disk_budget.sh"
	if [ ! -f "$s" ]; then tlog "WARNING: no dq_disk_budget.sh next to the integrator ($SELF_DIR) or in the origin repo; the disk budget is not enforced"; return 0; fi
	bash "$s" "$@" >>"$LOGS/train.log" 2>&1; rc=$?
	return "$rc"
}
precheck_ensure() { # start the prechecker when prechecks are on, lanes are queued and none runs (the integrator calls this every cycle)
	[ "$PRE_ON" = 1 ] && [ "${DQ_TRAIN_NO_START:-0}" != 1 ] || return 0
	prechecker_alive && return 0
	[ -n "$(queue_branches)" ] || return 0
	# It runs the integrator's snapshot, never a lane's checkout: installing a snapshot here would replace the code a running integrator
	# runs (an enqueue from a lane's worktree did that once). cmd_ensure installs it before it starts both; the integrator calls this.
	[ -f "$STATE/self/dq_train.sh" ] || return 0
	start_detached "$STATE/self/dq_train.sh" "$LOGS/prechecker.out" precheck-run
	tlog "prechecker started (detached; lock $STATE/precheck.lock)"
}
cmd_ensure() {
	init_state
	# a running integrator starts the prechecker itself at its next cycle (from its own snapshot)
	if integrator_alive; then tlog "integrator already running (pid $(integrator_pid)); the enqueued lane joins its next cycle"; return 0; fi
	# The watchdog callers (dq_lane_pool.sh lease and release) ask on every call: with nothing queued there is nothing to run.
	[ -n "$(queue_branches)" ] || return 0
	# The integrator runs from a snapshot (the lane's worktree is released and reset while it works); the helpers are read from its worktree.
	if ! in_snapshot; then
		snapshot_install "$SELF_DIR" "$STATE/self" || die "cannot snapshot the integrator into $STATE/self"
	fi
	export DQ_TRAIN_ORIGIN_REPO="${DQ_TRAIN_ORIGIN_REPO:-$(git rev-parse --show-toplevel)}"
	start_detached "$STATE/self/dq_train.sh" "$LOGS/integrator.out"
	precheck_ensure
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

# ---- prechecks: every heavy lane gated ALONE on current master before it may join a batch ------------------------------------------
# The verdict is keyed by (origin/master, lane tip): $PRE/v/<lane>@<tip12>@<master12> (verdict=pass|fail|conflict|error, secs, log).
# A batch takes a lane whose tip has a PASS (on any master: the batch gate proves the combination on current master again); a lane
# that fails alone is bounced by the prechecker at once, with its report, and never costs a batch or a bisect. Light lanes need none.
pre_key() { echo "$(fname "$1")@${2:0:12}"; } # <branch> <tip>
pre_verdict_file() { # <branch> <tip>: the newest verdict file for this tip (any master), or nothing (find, not a glob: callers run under set -f)
	find "$PRE/v" -maxdepth 1 -type f -name "$(pre_key "$1" "$2")@*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-
}
pre_status() { # <branch> <tip>: pass | fail | conflict | error | running | none
	local f v
	[ -f "$PRE/running/$(fname "$1")" ] && [ "$(qget "$PRE/running/$(fname "$1")" tip)" = "$2" ] && { echo running; return 0; }
	f="$(pre_verdict_file "$1" "$2")"
	[ -n "$f" ] || { echo none; return 0; }
	v="$(qget "$f" verdict)"
	echo "${v:-none}"
}
pre_record() { # <branch> <tip> <master> <verdict> <secs> <log> [why]
	local f="$PRE/v/$(pre_key "$1" "$2")@${3:0:12}"
	printf 'branch=%s\ntip=%s\nmaster=%s\nverdict=%s\nsecs=%s\nlog=%s\nwhy=%s\nwhen=%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}" "$(now)" >"$f.tmp" && mv -f "$f.tmp" "$f"
}
lane_is_light() { [ "$(qget "$(qfile "$1")" light)" = 1 ]; }
free_ram_gb() { awk '/^MemFree:/ {print int($2 / 1048576)}' /proc/meminfo 2>/dev/null || echo 999; }
listed_in() { # <file> <branch>: the branch is a line of the file
	[ -s "$1" ] && grep -qxF -- "$2" "$1"
}

wt_creating() { # <path>: another process of the train is creating this worktree right now
	local c="$STATE/wt-creating/$(basename "$1")"
	[ -f "$c" ] && alive "$(cat "$c" 2>/dev/null)"
}
wt_ready() { [ -e "$1/.git" ] && ! wt_creating "$1"; } # <path>: checked out, gen warmed, nobody still creating it
ensure_wt_at() { # <path>: a detached worktree of the repository (the prechecker's, the parallel bisect's); one-time full checkout + gen
	local p="$1" origin free c rc=0
	wt_ready "$p" && return 0
	wt_creating "$p" && return 1
	origin="$(repo_dir)"
	free="$(df -Pk "$(dirname "$p")" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
	if [ -n "$free" ] && [ "$free" -lt "${DQ_TRAIN_MIN_FREE_GB:-60}" ] && [ -z "${DQ_TRAIN_NO_DISK_CHECK:-}" ]; then tlog "ERROR: only ${free} GB free for the worktree $p"; return 1; fi
	# the marker names the creating process: a half-made worktree is never used (wt_ready), and a dead creator's marker is ignored
	c="$STATE/wt-creating/$(basename "$p")"
	mkdir -p "$STATE/wt-creating" && echo "${BASHPID:-$$}" >"$c"
	if [ ! -e "$p/.git" ]; then
		tlog "creating the worktree $p (detached at origin/master; a one-time full checkout, slow)"
		mkdir -p "$(dirname "$p")"
		git -C "$origin" worktree add --detach "$p" origin/master >>"$LOGS/train.log" 2>&1 || rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		(cd "$p" && [ -x tools/build/build.sh ] && tools/build/build.sh gen) >>"$LOGS/train.log" 2>&1 || tlog "warning: the warm-up gen in $p failed (the gate will report it)"
		tlog "worktree $p ready"
	fi
	rm -f "$c"
	return "$rc"
}

# The cheap first stage, for every queued lane at once (seconds, no build): does the lane merge with current master? A real conflict
# bounces it now. A conflict confined to deepquarry.dme is not one (the merge resolves the include sets, tools/dq_dme_resolve.sh).
pre_probe_conflict() { # <branch> <tip> <master>: 0 = merges (or only the manifest conflicts), 1 = conflicts (CONFLICT_FILES set)
	local scratch common out rc=0 f
	CONFLICT_FILES=""
	common="$(G rev-parse --path-format=absolute --git-common-dir)"
	scratch="$(mktemp -d "${TMPDIR:-/tmp}/dq-preprobe.XXXXXX")"
	out="$(GIT_OBJECT_DIRECTORY="$scratch" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common/objects" G merge-tree --write-tree --name-only --no-messages "$3" "$2" 2>/dev/null)" || rc=$?
	rm -rf "$scratch"
	[ "$rc" -eq 1 ] || return 0 # clean, or merge-tree could not tell (the full precheck merges for real)
	CONFLICT_FILES="$(tail -n +2 <<<"$out" | awk 'NF' | sort -u)"
	f="$(grep -vxF deepquarry.dme <<<"$CONFLICT_FILES")"
	[ -n "$f" ] || return 0
	return 1
}

# One precheck: the lane merged onto current origin/master in worker worktree N, and the gates a batch would run (tools/dq_merge_batch.sh
# on that one lane: DreamChecker reused when no DM changed, analyze_tests only when the analyzer or its scopes changed, the lane's tests
# plus the smoke set). Runs as a background job of the prechecker; it records the verdict and bounces a lane that fails alone.
precheck_one() { # <worker n> <branch> <tip>
	local n="$1" b="$2" tip="$3" wt="${PRE_WT_BASE}$1" master log out t0 secs good bl why lg verdict tests rc
	t0=$(date +%s)
	tests="$(qget "$(qfile "$b")" tests)"
	printf 'branch=%s\ntip=%s\nworker=%s\npid=%s\nsince=%s\n' "$b" "$tip" "$n" "$BASHPID" "$(now)" >"$PRE/running/$(fname "$b")"
	ensure_wt_at "$wt" || { rm -f "$PRE/running/$(fname "$b")"; pre_record "$b" "$tip" "unknown" error 0 "" "no precheck worktree $wt"; return 0; }
	G fetch -q origin 2>/dev/null
	master="$(G rev-parse origin/master)"
	log="$LOGS/precheck-$(fname "$b")-$(date +%Y%m%dT%H%M%S).log"
	tlog "precheck: $b (tip ${tip:0:10}) on origin/master ${master:0:10} in $wt; log $log"
	(
		cd "$wt" || exit 99
		export DQ_MERGE_BRANCH="train/pre$n" DQ_MERGE_SESSION="train-pre$n-$$" DQ_DREAMMAKER_GATE=0 DQ_FOCUSED_MAX_MIN="$TEST_MAX_MIN" DQ_GATE_DREAMCHECKER=1
		unset DQ_BATCH_DEADLINE DQ_BATCH_CACHE DQ_BATCH_WT2 DQ_SLOT_PRIORITY
		set -f
		bash tools/dq_merge_batch.sh --lanes "$b" --lane-tests "$b=$tests" --no-dm
	) >"$log" 2>&1
	rc=$?
	secs=$(( $(date +%s) - t0 ))
	good="$(sed -n 's/^BATCH_GOOD: //p' "$log" | tail -n 1)"
	bl="$(sed -n 's/^BATCH_BOUNCED: //p' "$log" | tail -n 1)"
	if [[ " $good " == *" $b "* ]]; then
		verdict=pass
	elif [ -n "$bl" ]; then
		why="${bl#*|}"; lg="${why##*|}"; why="${why%|*}"
		case "$why" in *"merge conflict"*) verdict=conflict ;; *) verdict=fail ;; esac
	else
		verdict=error; why="the precheck did not finish (rc=$rc); see $log"
	fi
	# the lane may have moved or been withdrawn while it was checked: record the verdict, bounce only what is still queued at this tip
	pre_record "$b" "$tip" "$master" "$verdict" "$secs" "$log" "${why:-}"
	rm -f "$PRE/running/$(fname "$b")"
	tlog "PRECHECK $verdict: $b (tip ${tip:0:10}) on master ${master:0:10} in ${secs}s"
	if [ "$verdict" = fail ] || [ "$verdict" = conflict ]; then
		if [ -f "$(qfile "$b")" ] && [ "$(qget "$(qfile "$b")" tip)" = "$tip" ]; then
			[ -n "${lg:-}" ] && [ -f "$wt/$lg" ] && lg="$wt/$lg" || lg="$log"
			bounce "$b" "precheck: $why (alone on origin/master ${master:0:10}, before joining any batch)" "$lg"
		fi
	fi
	return 0
}

# The prechecker: one detached process (lock precheck.lock), up to PRE_WORKERS prechecks at a time, each in its own worktree (its own
# compile root: the dmbc daemon keeps one session per root, so a worker's next precheck is an incremental compile of master + the next
# lane). Every heavy step holds machine slots (tools/dq_machine_slots.sh) below the batch gate's priority, runs below normal priority,
# and a precheck does not START while free RAM is under PRE_MIN_FREE_GB. Exits when nothing queued needs a precheck.
cmd_precheck_run() {
	init_state
	LOCK_NAME="precheck.lock"
	export DQ_TRAIN_ORIGIN_REPO="${DQ_TRAIN_ORIGIN_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
	if [ "${DQ_TRAIN_REEXEC:-0}" = 1 ] && [ "$(lockdir_pid precheck.lock)" = "$$" ]; then
		sed -i -e "s|^winpid=.*|winpid=$(cat /proc/$$/winpid 2>/dev/null)|" -e "s|^script=.*|script=$SELF|" "$STATE/precheck.lock/owner" 2>/dev/null || true
		LOCK_HELD=1; unset DQ_TRAIN_REEXEC
	else
		lock_take || { echo "dq_train: a prechecker is already running (pid $(lockdir_pid precheck.lock))"; exit 0; }
	fi
	trap 'lock_release' EXIT
	tlog "prechecker started (pid $$, $PRE_WORKERS worker(s) under ${PRE_WT_BASE}N, script $SELF)"
	[ -s "$PRE/epoch" ] || date +%s >"$PRE/epoch"
	# old verdicts and probe marks (keyed by tips and masters long gone) are disposable
	find "$PRE/probe" "$PRE/v" -type f -mtime +"${DQ_TRAIN_PRECHECK_KEEP_DAYS:-3}" -delete 2>/dev/null
	declare -A wpid=() wlane=()
	local i b tip f master want idle_rounds=0 ram_note=0
	while :; do
		# reap finished workers
		for i in "${!wpid[@]}"; do
			if ! kill -0 "${wpid[$i]}" 2>/dev/null; then wait "${wpid[$i]}" 2>/dev/null; unset "wpid[$i]" "wlane[$i]"; fi
		done
		# a running marker whose worker is gone (a killed prechecker) is stale
		for f in "$PRE/running"/*; do
			[ -e "$f" ] || continue
			alive "$(qget "$f" pid)" || { local busy=0; for i in "${!wlane[@]}"; do [ "${wlane[$i]}" = "$(qget "$f" branch)" ] && busy=1; done; [ "$busy" = 1 ] || rm -f "$f"; }
		done
		[ ${#wpid[@]} -gt 0 ] || self_update
		G fetch -q origin 2>/dev/null
		master="$(G rev-parse origin/master 2>/dev/null)"
		want=()
		for b in $(queue_branches); do
			f="$(qfile "$b")"; tip="$(qget "$f" tip)"
			lane_is_light "$b" && continue
			listed_in "$STATE/batch.lanes" "$b" && continue
			listed_in "$STATE/bisect.lanes" "$b" && continue
			case "$(pre_status "$b" "$tip")" in
				none) ;;
				error) [ -n "$(find "$(pre_verdict_file "$b" "$tip")" -mmin +"${DQ_TRAIN_PRECHECK_RETRY_MIN:-30}" 2>/dev/null)" ] || continue ;;
				*) continue ;;
			esac
			[ "$(G rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null || G rev-parse -q --verify "refs/remotes/origin/$b^{commit}" 2>/dev/null)" = "$tip" ] || continue # moved or gone: the integrator bounces it
			# stage 1, seconds: the conflict probe against current master (once per master and tip)
			if [ ! -f "$PRE/probe/$(pre_key "$b" "$tip")@${master:0:12}" ]; then
				: >"$PRE/probe/$(pre_key "$b" "$tip")@${master:0:12}"
				if ! pre_probe_conflict "$b" "$tip" "$master"; then
					pre_record "$b" "$tip" "$master" conflict 0 "" "conflicts with origin/master in: $(tr '\n' ' ' <<<"$CONFLICT_FILES")"
					tlog "PRECHECK conflict: $b (tip ${tip:0:10}) does not merge with origin/master ${master:0:10}: $(tr '\n' ' ' <<<"$CONFLICT_FILES")"
					bounce "$b" "precheck: merge conflict with origin/master ${master:0:10} in $(tr '\n' ' ' <<<"$CONFLICT_FILES" | head -c 300)(merge master into the lane: bash tools/dq_merge_master.sh, then enqueue again)"
					continue
				fi
			fi
			local running_it=0
			for i in "${!wlane[@]}"; do [ "${wlane[$i]}" = "$b" ] && running_it=1; done
			[ "$running_it" = 1 ] || want+=("$b")
		done
		if [ ${#want[@]} -eq 0 ] && [ ${#wpid[@]} -eq 0 ]; then
			idle_rounds=$((idle_rounds + 1))
			if [ "$idle_rounds" -ge "${DQ_TRAIN_PRECHECK_IDLE_ROUNDS:-2}" ]; then tlog "prechecker: nothing to precheck; exits"; exit 0; fi
		else
			idle_rounds=0
		fi
		# start workers: cheap prechecks first (a lane that changes no DM reuses DreamChecker's verdict and patches nothing in the compile),
		# then queue order; at most PRE_WORKERS at once, never below the free-RAM floor
		if [ ${#want[@]} -gt 1 ] && [ ${#wpid[@]} -lt "$PRE_WORKERS" ]; then
			local cheap=() dear=()
			for b in "${want[@]}"; do
				if G diff --name-only "origin/master...$(qget "$(qfile "$b")" tip)" 2>/dev/null | grep -qE '^(code|maps|interface)/|\.dme$|\.dmm$'; then dear+=("$b"); else cheap+=("$b"); fi
			done
			want=("${cheap[@]+"${cheap[@]}"}" "${dear[@]+"${dear[@]}"}")
		fi
		for b in "${want[@]+"${want[@]}"}"; do
			[ ${#wpid[@]} -lt "$PRE_WORKERS" ] || break
			if [ "$(free_ram_gb)" -lt "$PRE_MIN_FREE_GB" ]; then
				[ "$ram_note" = 1 ] || tlog "prechecker: waiting: $(free_ram_gb) GB of RAM free (< $PRE_MIN_FREE_GB GB); no new precheck starts"
				ram_note=1
				break
			fi
			ram_note=0
			listed_in "$STATE/batch.lanes" "$b" && continue
			for i in $(seq 1 "$PRE_WORKERS"); do [ -n "${wpid[$i]:-}" ] || break; done
			precheck_one "$i" "$b" "$(qget "$(qfile "$b")" tip)" &
			wpid[$i]=$!; wlane[$i]="$b"
		done
		[ "${DQ_TRAIN_ONCE:-0}" = 1 ] && [ ${#wpid[@]} -eq 0 ] && [ ${#want[@]} -eq 0 ] && exit 0
		if [ ${#wpid[@]} -gt 0 ]; then
			# wake when a worker ends, at most DQ_TRAIN_PRECHECK_POLL_SEC later (new lanes are looked at then)
			local w=0; while [ "$w" -lt "${DQ_TRAIN_PRECHECK_POLL_SEC:-60}" ]; do sleep 2; w=$((w + 2)); for i in "${!wpid[@]}"; do kill -0 "${wpid[$i]}" 2>/dev/null || break 2; done; done
		else
			sleep "${DQ_TRAIN_PRECHECK_POLL_SEC:-60}"
		fi
	done
}

# ---- which lanes interact (a prechecked batch runs the tests of these only) -----------------------------------------------------------
# A prechecked lane's own tests passed on its own merge with master. In a batch they run again only when the lane can interact with
# another lane of the batch or with what master changed since its precheck: they share an "area" (a code file's first three path
# components, e.g. code/modules/mob; another file's directory), or either side touched a path in tools/ci/train_interact_global.txt.
# Test files, the manifest, baselines, docs and changelogs are not areas (every lane touches some). The smoke set always runs.
lane_areas() { # <rev range>: the areas of the files it changes, one per line
	G diff --name-only "$1" 2>/dev/null | awk '
		/^code\/modules\/unit_tests\// || /^code\/tests\// || /^deepquarry\.dme$/ || /^doc\// || /^html\/changelogs\// || /\.md$/ { next }
		/^tools\/ci\/[a-z_]+_baseline\.txt$/ || /^tools\/ci\/sys_baseline\// { next }
		{ n = split($0, p, "/"); if (n == 1) { print $0; next } k = (p[1] == "code") ? 3 : 2; if (k > n - 1) k = n - 1; a = p[1]; for (i = 2; i <= k; i++) a = a "/" p[i]; print a }' | sort -u
}
global_hit() { # <rev range>: 0 when it touches a global path
	local g f p
	g="$(read_list "$(repo_dir)/tools/ci/train_interact_global.txt")"
	[ -n "$g" ] || g="code/__defines/ code/__odlint.dm code/__pragmas.dm code/engine/ code/controllers/ maps/ tools/build/ tools/dmb/ verdigris/ SpacemanDMM.toml"
	while IFS= read -r f; do
		for p in $g; do case "$f" in "$p"*) return 0 ;; esac; done
	done < <(G diff --name-only "$1" 2>/dev/null)
	return 1
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
	CHOSEN=(); PRECHECKED_BATCH=0; SKIP_TESTS=()
	local limit b union est lane_tests
	if [ -s "$STATE/bisect.lanes" ]; then
		# a bisect in progress: exactly its lanes (the ones still queued and valid), in the recorded order; new lanes wait
		local want w v
		want="$(cat "$STATE/bisect.lanes")"
		for w in $want; do
			for v in "${VALID[@]}"; do [ "$v" = "$w" ] && CHOSEN+=("$w"); done
		done
		if [ ${#CHOSEN[@]} -gt 0 ]; then
			tlog "bisect in progress: this cycle takes only [${CHOSEN[*]}]; the other queued lanes wait until it resolves"
			BATCH_LIMIT_NOW="bisect"
			BATCH_EST="$(est_secs $(printf '%s\n' $(read_list "$(repo_dir)/tools/ci/smoke_tests.txt")))"
			set +f
			return 0
		fi
		rm -f "$STATE/bisect.lanes" "$STATE/bisect.cache"
	fi
	if [ "$PRE_ON" = 1 ]; then
		# Batches take prechecked lanes (a PASS for their tip; light lanes need none). A lane still waiting for its precheck waits, unless
		# it has waited PRE_WAIT_MIN since it was enqueued and no precheck runs for it (the prechecker is paused for RAM, or slow): then
		# it rides the old way (a small batch, the cycle deadline), alone with other such lanes, never mixed into a prechecked batch.
		local P=() U=() W=() st since_s nowt
		nowt=$(date +%s)
		for b in "${VALID[@]}"; do
			if lane_is_light "$b"; then P+=("$b"); continue; fi
			st="$(pre_status "$b" "${TIP_OF[$b]}")"
			case "$st" in
				pass) P+=("$b") ;;
				fail|conflict)
					# the prechecker bounces such a lane; one still queued at that tip (a bounce that raced a re-enqueue) is bounced here
					local pvf; pvf="$(pre_verdict_file "$b" "${TIP_OF[$b]}")"
					bounce "$b" "precheck: $(qget "$pvf" why) (alone on origin/master $(qget "$pvf" master | cut -c1-10))" "$(qget "$pvf" log)"
					CYCLE_PROGRESS=1
					;;
				*)
					since_s="$(date -d "$(qget "$(qfile "$b")" since)" +%s 2>/dev/null || echo "$nowt")"
					# the wait counts from when prechecks began on this machine (a lane queued before the switch waits like a new one)
					[ "$(cat "$PRE/epoch" 2>/dev/null || echo 0)" -gt "$since_s" ] && since_s="$(cat "$PRE/epoch")"
					if [ "$st" != running ] && [ $(( (nowt - since_s) / 60 )) -ge "$PRE_WAIT_MIN" ]; then U+=("$b"); else W+=("$b"); fi
					;;
			esac
		done
		# logged when the set changes (the integrator looks every minute while it waits)
		if [ ${#W[@]} -gt 0 ] && [ "${W[*]}" != "${WAIT_LAST:-}" ]; then tlog "waiting for prechecks: [${W[*]}]"; fi
		WAIT_LAST="${W[*]-}"
		if [ ${#P[@]} -gt 0 ]; then
			select_prechecked "${P[@]}"
			set +f
			return 0
		fi
		if [ ${#U[@]} -eq 0 ]; then BATCH_LIMIT_NOW=0; BATCH_EST=0; set +f; return 0; fi
		tlog "no precheck verdict after ${PRE_WAIT_MIN} min for [${U[*]}]: they ride unprechecked (the old way: a small batch and the cycle deadline)"
		VALID=("${U[@]}")
	fi
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

# A batch of prechecked lanes: up to MAX_LANES_PRE (state: batch_limit_pre, halved by a failed batch, doubled back by a clean one), and the
# test budget counts only the tests that can show an interaction (lane_areas, global_hit above): every lane proved its own tests alone,
# so a lane that shares no area with the rest of the batch, or with master's changes since its precheck, adds no test time. SKIP_TESTS
# names the lanes whose own tests do not run in this batch (the smoke set and gameplay set always run).
select_prechecked() { # <lanes...> in queue order
	local limit b tip range pm g any_global=0 union base est cand o
	local -A areas=() inter=() isglobal=()
	CHOSEN=(); SKIP_TESTS=(); PRECHECKED_BATCH=1
	limit="$(cat "$STATE/batch_limit_pre" 2>/dev/null)"
	case "$limit" in ''|*[!0-9]*|0) limit="$MAX_LANES_PRE" ;; esac
	[ "$limit" -gt "$MAX_LANES_PRE" ] && limit="$MAX_LANES_PRE"
	base="$(printf '%s\n' $(read_list "$(repo_dir)/tools/ci/smoke_tests.txt") $(read_list "$(repo_dir)/tools/ci/gameplay_tests.txt"))"
	union_of() { local u="$base" x; for x in "$@"; do u="$u $(qget "$(qfile "$x")" tests)"; done; echo "$u"; }
	for b in "$@"; do
		[ ${#CHOSEN[@]} -ge "$limit" ] && break
		tip="${TIP_OF[$b]}"; range="origin/master...$tip"
		areas[$b]="$(lane_areas "$range")"
		g=0; global_hit "$range" && g=1
		local new_inter=() mine=0
		[ "$g" = 1 ] || [ "$any_global" = 1 ] && mine=1
		# master moved since the lane's precheck: what it changed counts as one more lane of the batch
		pm="$(qget "$(pre_verdict_file "$b" "$tip")" master)"
		if [ -n "$pm" ] && [ "$(G rev-parse -q --verify "$pm^{commit}" 2>/dev/null)" ] && [ "$(G rev-parse origin/master)" != "$(G rev-parse "$pm^{commit}")" ]; then
			if global_hit "$pm..origin/master" || [ -n "$(comm -12 <(lane_areas "$pm..origin/master") <(printf '%s\n' "${areas[$b]}" | sort -u) | awk 'NF' | head -n 1)" ]; then mine=1; fi
		fi
		for o in "${CHOSEN[@]+"${CHOSEN[@]}"}"; do
			if [ "$g" = 1 ] || [ -n "$(comm -12 <(printf '%s\n' "${areas[$o]}" | sort -u) <(printf '%s\n' "${areas[$b]}" | sort -u) | awk 'NF' | head -n 1)" ]; then
				mine=1; [ -n "${inter[$o]:-}" ] || new_inter+=("$o")
			fi
		done
		cand=()
		for o in "${!inter[@]}"; do cand+=("$o"); done
		cand+=("${new_inter[@]+"${new_inter[@]}"}")
		[ "$mine" = 1 ] && cand+=("$b")
		est="$(est_secs $(union_of "${cand[@]+"${cand[@]}"}"))"
		if [ ${#CHOSEN[@]} -gt 0 ] && [ "${est:-9999}" -gt "$TEST_BUDGET" ]; then
			tlog "deferred $b to a later cycle: with the tests of the lanes it interacts with the union would be ~${est}s (> ${TEST_BUDGET}s budget)"
			continue
		fi
		CHOSEN+=("$b")
		[ "$g" = 1 ] && { any_global=1; isglobal[$b]=1; }
		for o in "${new_inter[@]+"${new_inter[@]}"}"; do inter[$o]=1; done
		[ "$mine" = 1 ] && inter[$b]=1
	done
	# a global lane makes every lane's tests count
	if [ "$any_global" = 1 ]; then for b in "${CHOSEN[@]}"; do inter[$b]=1; done; fi
	for b in "${CHOSEN[@]+"${CHOSEN[@]}"}"; do [ -n "${inter[$b]:-}" ] || SKIP_TESTS+=("$b"); done
	cand=(); for b in "${!inter[@]}"; do cand+=("$b"); done
	BATCH_LIMIT_NOW="$limit (prechecked)"
	BATCH_EST="$(est_secs $(union_of "${cand[@]+"${cand[@]}"}"))"
	[ ${#SKIP_TESTS[@]} -eq 0 ] || tlog "prechecked lanes whose own tests do not run in this batch (they passed alone; no shared area with the batch or master's changes since): [${SKIP_TESTS[*]}]"
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

heavy_cycle() { # the lanes being gated are listed in batch.lanes while it runs (the prechecker leaves them alone)
	local hrc
	printf '%s\n' "${CHOSEN[@]}" >"$STATE/batch.lanes"
	heavy_cycle_gate; hrc=$?
	rm -f "$STATE/batch.lanes"
	return "$hrc"
}
heavy_cycle_gate() {
	local b out rc stamp good bounced_lines deferred capped line lane why lg pushlog prc tests_union lane_test_args lane_tests sha deadline
	ensure_wt || { tlog "ERROR: no train worktree; the cycle is skipped"; return 20; }
	stamp="$(date +%Y%m%dT%H%M%S)"
	out="$LOGS/cycle-$stamp.log"
	tests_union=""; lane_test_args=()
	for b in "${CHOSEN[@]}"; do
		lane_tests="$(qget "$(qfile "$b")" tests)"
		# a prechecked lane that interacts with nothing in the batch: its own tests passed alone (select_prechecked)
		case " ${SKIP_TESTS[*]-} " in *" $b "*) lane_tests="" ;; esac
		tests_union="$tests_union $lane_tests"
		lane_test_args+=(--lane-tests "$b=$lane_tests")
	done
	set -f
	tests_union="$(printf '%s\n' $tests_union | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
	set +f
	if [ -z "${tests_union// /}" ]; then tests_union="dq_boot_gate"; lane_test_args+=(--tests dq_boot_gate); fi
	deadline=$(( $(date +%s) + CYCLE_MAX_MIN * 60 ))
	local wt2_use="" deadline_use="$deadline" limit_file="$STATE/batch_limit" limit_max="$MAX_LANES"
	if [ "${PRECHECKED_BATCH:-0}" = 1 ]; then
		# Every lane passed alone: a failure is an interaction, and its bisect runs to the end in this cycle (no deadline; the machine is
		# protected by the machine slots and the RAM floor instead), both halves at once in the second worktree.
		deadline_use=""; limit_file="$STATE/batch_limit_pre"; limit_max="$MAX_LANES_PRE"
		if wt_ready "$WT2"; then wt2_use="$WT2"
		else ( ensure_wt_at "$WT2" ) >/dev/null 2>&1 & disown $! 2>/dev/null || true; fi # one-time checkout in the background; used from the next cycle
	fi
	phase "gate: ${CHOSEN[*]}"
	tlog "heavy cycle: ${#CHOSEN[@]} lane(s) [${CHOSEN[*]}]$([ "${PRECHECKED_BATCH:-0}" = 1 ] && echo " (all prechecked; bisect to the end$([ -n "$wt2_use" ] && echo ", halves in parallel"))"), tests [$tests_union] (+ smoke set, est ~${BATCH_EST}s), test cap ${TEST_MAX_MIN} min, $([ -n "$deadline_use" ] && echo "no new attempt after $(date -u -d "@$deadline" +%H:%MZ 2>/dev/null || echo "$CYCLE_MAX_MIN min")" || echo "no cycle deadline"); log $out"
	for b in "${CHOSEN[@]}"; do bump_attempts "$b"; done
	(
		cd "$WT" || exit 99
		export DQ_MERGE_BRANCH="$TBRANCH" DQ_MERGE_SESSION="train-$$" DQ_DREAMMAKER_GATE=0 DQ_FOCUSED_MAX_MIN="$TEST_MAX_MIN"
		export DQ_SLOT_PRIORITY=0 DQ_PUSH_STRICT=1 DQ_PUSH_NO_REPROOF=1 DQ_PUSH_TRUST_GATE_DM=1 DQ_BATCH_DEADLINE="$deadline_use" DQ_BATCH_WT2="$wt2_use"
		# DreamChecker is a gate job of its own (parallel to the tests, a failure bisects to the culprit lane): the native compiler accepts
		# undefined fields DreamChecker rejects, and the push trusts the gate only with the gate's dreamchecker stamp on the exact HEAD.
		export DQ_GATE_DREAMCHECKER=1
		export DQ_BATCH_CACHE="$STATE/bisect.cache"
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
	local nbounced=0
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		nbounced=$((nbounced + 1))
		lane="${line%%|*}"; why="${line#*|}"; lg="${why##*|}"; why="${why%|*}"
		[ -n "$lane" ] || continue
		bounce "$lane" "$why" "$WT/$lg"
		CYCLE_PROGRESS=1
	done < <(sed -n 's/^BATCH_BOUNCED: //p' "$out")
	if [ -n "${capped:-}" ]; then
		local half=$(( ${#CHOSEN[@]} / 2 )); [ "$half" -lt 1 ] && half=1
		echo "$half" >"$limit_file"
		tlog "the test phase hit its ${TEST_MAX_MIN} min cap with ${#CHOSEN[@]} lane(s): batch limit is now $half; the deferred lanes [${deferred:-}] ride a smaller batch"
		CYCLE_PROGRESS=1
	fi
	# An unfinished bisect (lanes deferred by the deadline, not by a cap) resumes next cycle with exactly those lanes and the saved verdicts.
	if [ -n "${deferred:-}" ] && [ -z "${capped:-}" ]; then
		printf '%s\n' $deferred >"$STATE/bisect.lanes"
		tlog "bisect unfinished: [$deferred] resume next cycle from the saved verdicts ($STATE/bisect.cache)"
		CYCLE_PROGRESS=1
	else
		rm -f "$STATE/bisect.lanes" "$STATE/bisect.cache"
	fi
	if [ -z "${capped:-}" ] && { [ "$nbounced" -gt 0 ] || [ -n "${deferred:-}" ]; }; then
		local fh=$(( ${#CHOSEN[@]} / 2 )); [ "$fh" -lt 1 ] && fh=1
		echo "$fh" >"$limit_file"
		tlog "the batch of ${#CHOSEN[@]} lane(s) failed (bounced $nbounced, deferred [${deferred:-}]): batch limit is now $fh"
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
	if [ -z "${capped:-}" ] && [ "$nbounced" -eq 0 ] && [ -z "${deferred:-}" ]; then
		local lim; lim="$(cat "$limit_file" 2>/dev/null)"; lim="${lim:-$limit_max}"
		lim=$(( lim * 2 )); [ "$lim" -gt "$limit_max" ] && lim="$limit_max"
		echo "$lim" >"$limit_file"
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
	precheck_ensure
	[ "$PRE_ON" != 1 ] || [ -s "$PRE/epoch" ] || date +%s >"$PRE/epoch"
	select_batch
	if [ ${#CHOSEN[@]} -eq 0 ]; then
		# every valid lane is waiting for its precheck: nothing to gate yet (not a stall; the prechecker is working)
		phase "waiting for prechecks"
		return 11
	fi
	local all_light=1
	for b in "${CHOSEN[@]}"; do [ "$(qget "$(qfile "$b")" light)" = 1 ] || all_light=0; done
	tlog "cycle: queue=[${all[*]}] valid=[${VALID[*]}] chosen=[${CHOSEN[*]}] (limit $BATCH_LIMIT_NOW, est ~${BATCH_EST}s of tests) all_light=$all_light"
	# Disk budget (tools/dq_disk_budget.sh): enforce the caps at every cycle start; below the floor a heavy cycle is not started (the lanes stay queued).
	if [ "$all_light" -eq 1 ]; then
		disk_budget enforce --quiet --throttle 10 || true
		light_cycle
	else
		# only exit 4 is a real floor breach (the REFUSED message above in this log has the free GB and the floor); anything else is a warning and the cycle runs
		disk_budget gate "a heavy train cycle" --sync --throttle 10; local drc=$?
		if [ "$drc" -eq 4 ]; then
			tlog "disk floor: the cycle is skipped, the lanes stay queued; free space (see the REFUSED message above in this log), then the next cycle runs"
			return 0
		elif [ "$drc" -ne 0 ]; then
			tlog "WARNING: the disk gate failed internally (rc=$drc, not a floor breach); running the cycle"
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
	if [ "${DQ_TRAIN_REEXEC:-0}" = 1 ] && [ "$(integrator_pid)" = "$$" ]; then
		# a self-update exec: this process IS the integrator that holds the lock (same pid); keep the lock and its start time
		sed -i -e "s|^winpid=.*|winpid=$(cat /proc/$$/winpid 2>/dev/null)|" -e "s|^script=.*|script=$SELF|" "$STATE/run.lock/owner" 2>/dev/null || true
		LOCK_HELD=1
		unset DQ_TRAIN_REEXEC
	else
		lock_take || { echo "dq_train: an integrator is already running (pid $(integrator_pid))"; exit 0; }
	fi
	trap 'lock_release; phase "idle"' EXIT
	tlog "integrator started (pid $$, script $SELF, state $STATE, worktree $WT)"
	local idle=0 rc stalls=0
	while :; do
		self_update
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
		if [ "$rc" -eq 11 ]; then
			# waiting for prechecks is not a stall; look again shortly (a verdict, a new lane, or a lane past the wait limit)
			idle=0
			if [ "${DQ_TRAIN_NO_START:-0}" = 1 ] && ! prechecker_alive; then tlog "waiting for prechecks, and DQ_TRAIN_NO_START=1 starts no prechecker: the integrator exits"; exit 0; fi
			sleep "${DQ_TRAIN_PRECHECK_WAIT_SEC:-60}"
			continue
		fi
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
	if [ "$PRE_ON" = 1 ]; then
		if prechecker_alive; then echo "prechecker: RUNNING pid $(lockdir_pid precheck.lock) ($PRE_WORKERS worker(s); now: $(for f in "$PRE/running"/*; do [ -e "$f" ] && printf '%s ' "$(qget "$f" branch)"; done))"
		else echo "prechecker: not running"; fi
	fi
	echo "batch limit: $(cat "$STATE/batch_limit" 2>/dev/null || echo "$MAX_LANES (default)") lane(s) per cycle; prechecked batches: $(cat "$STATE/batch_limit_pre" 2>/dev/null || echo "$MAX_LANES_PRE (default)")"
	echo "queue:"
	local pst pvf
	for b in $(queue_branches); do
		f="$(qfile "$b")"; n=$((n + 1)); pst=""
		if [ "$PRE_ON" = 1 ] && [ "$(qget "$f" light)" != 1 ]; then
			pst="$(pre_status "$b" "$(qget "$f" tip)")"; pvf="$(pre_verdict_file "$b" "$(qget "$f" tip)")"
			[ -n "$pvf" ] && [ "$pst" != running ] && pst="$pst on master $(qget "$pvf" master | cut -c1-10) in $(qget "$pvf" secs)s"
			pst="  precheck: $pst"
		fi
		echo "  $b  tip $(qget "$f" tip | cut -c1-10)  $([ "$(qget "$f" light)" = 1 ] && echo light || echo "tests: $(qget "$f" tests)")  enqueued $(qget "$f" since)  gate attempts: $(qget "$f" attempts)$pst"
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
	precheck-run) cmd_precheck_run ;;
	*) sed -n '2,12p' "$0"; exit 2 ;;
esac
