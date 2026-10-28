#!/usr/bin/env bash
# The batch train: lanes enqueue and leave, ONE detached integrator lands everything that is waiting, together.
#
#   bash tools/dq_train.sh enqueue [--tests "a b"] [--light]   # from the lane's worktree, after commit: record branch + tip + tests, return
#   bash tools/dq_train.sh status [--json]                      # integrator, queue, bounced lanes (with report paths), recent landings
#   bash tools/dq_train.sh report <branch>                      # print a bounced lane's report
#   bash tools/dq_train.sh dequeue <branch>                     # withdraw a queued or bounced lane (the branch itself is untouched)
#   bash tools/dq_train.sh ensure                               # start the integrator when none is running (enqueue does this)
#   bash tools/dq_train.sh run                                  # the integrator itself (detached by `ensure`; one at a time)
#   bash tools/dq_train.sh lanes [--since T]                    # per-lane waiting / in-cycle / fixing times, mean gate phases
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
SNAP_FILES=(dq_train.sh dq_train_estimate.js dq_disk_budget.sh ci/disk_budget.toml train/lane_times.py)
STATE="${DQ_TRAIN_STATE:-E:/dq-cache/train}"
WT="${DQ_TRAIN_WT:-E:/projects/dq-wt/train-base}"
TBRANCH="${DQ_TRAIN_BRANCH:-train/integ}"
MAX_LANES="${DQ_TRAIN_MAX_LANES:-8}"
# The union of tests runs in TEST_WORLDS test worlds at once (dq_focused_test.sh splits the list: DQ_MAIN_WORLDS), so the budget for the
# union's summed seconds is the per-world budget times the worlds, less one world boot (~30 s) per extra world. Heavy lanes that a single
# 420 s world deferred to a later cycle ride the same one.
TEST_WORLDS="${DQ_TRAIN_TEST_WORLDS:-2}"
TEST_BUDGET_WORLD="${DQ_TRAIN_TEST_BUDGET_SEC:-420}"
TEST_BUDGET=$(( TEST_BUDGET_WORLD * TEST_WORLDS - 30 * (TEST_WORLDS - 1) ))
AUTO_LIGHT="${DQ_TRAIN_AUTO_LIGHT:-1}"
TEST_MAX_MIN="${DQ_TRAIN_TEST_MAX_MIN:-10}"
CYCLE_MAX_MIN="${DQ_TRAIN_CYCLE_MAX_MIN:-20}"
# Prechecks (section 29 "Prechecks"): every heavy lane is gated ALONE on current master by a separate detached process (`precheck-run`)
# in its own worktree(s), in parallel with the batch gate; a lane that fails alone is bounced at once and never joins a batch.
PRE_ON="${DQ_TRAIN_PRECHECK:-1}"
PRE_WORKERS="${DQ_TRAIN_PRECHECK_WORKERS:-2}"
PRE_WT_BASE="${DQ_TRAIN_PRE_WT:-E:/projects/dq-wt/train-pre}"   # worker N works in ${PRE_WT_BASE}N
PRE_WAIT_MIN="${DQ_TRAIN_PRECHECK_WAIT_MIN:-45}"                 # an unprechecked lane rides the old way after waiting this long
PRE_SMOKE_ARGS=(--no-smoke); [ "${DQ_TRAIN_PRECHECK_SMOKE:-0}" != 1 ] || PRE_SMOKE_ARGS=()
PRE_MIN_FREE_GB="${DQ_TRAIN_PRECHECK_MIN_FREE_GB:-12}"          # a precheck does not START below this much free RAM (the user's desktop)
MAX_LANES_PRE="${DQ_TRAIN_MAX_LANES_PRECHECKED:-20}"            # batch size when every lane is prechecked
WT2="${DQ_TRAIN_WT2:-E:/projects/dq-wt/train-bisect}"           # the second worktree of a parallel bisect
PRE="$STATE/precheck"
LIGHT_PRE="${DQ_TRAIN_LIGHT_PRECHECK:-1}"                         # light lanes are prechecked too (their cheap checks, beside the gates)
DC_BATCH="${DQ_TRAIN_DC_BATCH:-1}"                               # DreamChecker once for all queued lanes (dc_batch_run), not once per precheck
WT_DC="${DQ_TRAIN_DC_WT:-E:/projects/dq-wt/train-dc}"           # the DreamChecker batch's worktree
Q="$STATE/queue"
BOUNCED="$STATE/bounced"
LANDED="$STATE/landed"
REPORTS="$STATE/reports"
LOGS="$STATE/log"

die() { echo "dq_train: $*" >&2; exit 1; }
init_state() { mkdir -p "$Q" "$BOUNCED" "$LANDED" "$REPORTS" "$LOGS" "$STATE/self" "$PRE/v" "$PRE/running" "$PRE/probe" "$PRE/dc/v" "$PRE/dc/solo" || die "cannot create $STATE"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# Every decision goes to the log (and to stdout).
tlog() { local line; line="$(now) train[$$]: $*"; echo "$line"; echo "$line" >>"$LOGS/train.log" 2>/dev/null || true; }
fname() { printf '%s' "$1" | tr '/' '_'; }
qfile() { echo "$Q/$(fname "$1").q"; }
qget() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }
# Queue files are only ever replaced whole (write a temp file, rename it) and every change to one holds the queue lock, so a bounce that
# removes a lane's file can never race an edit into a half-written one (27 October: an append after a bounce's rm left
# perf/refresh-timer queued with no tip, tests or enqueue time). A file without seq, branch or tip is moved to malformed/ and reported.
qlock() {
	local i=0
	while ! mkdir "$STATE/queue.lock" 2>/dev/null; do
		i=$((i + 1))
		# a holder that died mid-change leaves the lock: after 2 minutes it is stale (changes take milliseconds)
		if [ "$i" -ge 100 ] && [ -n "$(find "$STATE/queue.lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then rmdir "$STATE/queue.lock" 2>/dev/null; i=0; fi
		sleep 0.1
	done
}
qunlock() { rmdir "$STATE/queue.lock" 2>/dev/null; return 0; }
q_wellformed() { [ -n "$(qget "$1" seq)" ] && [ -n "$(qget "$1" branch)" ] && [ -n "$(qget "$1" tip)" ]; }
qedit() { # <branch> <sed args...>: change a lane's queue file in place, atomically; nothing when it is gone (never re-created)
	local b="$1" f
	shift
	f="$(qfile "$b")"
	qlock
	if [ -f "$f" ] && q_wellformed "$f"; then sed "$@" "$f" >"$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"; fi
	rm -f "$f.tmp.$$"
	qunlock
}
queue_branches() { # oldest first; a malformed entry is moved aside to malformed/ and reported, never gated
	local f m
	for f in "$Q"/*.q; do
		[ -e "$f" ] || continue
		if ! q_wellformed "$f"; then
			m="$STATE/malformed/$(basename "$f").$(date +%Y%m%dT%H%M%S)"
			mkdir -p "$STATE/malformed" && mv -f "$f" "$m" 2>/dev/null && \
				tlog "WARNING: malformed queue entry $(basename "$f") (no seq, branch or tip): moved to $m and skipped; enqueue the lane again" >&2
			continue
		fi
		printf '%s %s\n' "$(qget "$f" seq)" "$(qget "$f" branch)"
	done | sort -n | awk '{print $2}'
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
wait_change() { # <max secs> <dir...>: sleep until a directory's listing changes (2 s ticks), at most <max secs>
	local max="$1" w=0 sig now_sig
	shift
	sig="$(ls -l --time-style=+%s "$@" 2>/dev/null | cksum)"
	while [ "$w" -lt "$max" ]; do
		sleep 2; w=$((w + 2))
		now_sig="$(ls -l --time-style=+%s "$@" 2>/dev/null | cksum)"
		[ "$now_sig" = "$sig" ] || return 0
	done
	return 0
}
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
	# Exclusive across concurrent ensure/enqueue starts and self-update re-execs (27 October: two integrators gated rx/readback-notices).
	# The owner file is written into a private directory first and the directory is renamed into place, so a lock never exists without its
	# owner; a dead lock is moved aside (one rename wins) and checked to still be the dead owner's before it is dropped.
	local d="$STATE/$LOCK_NAME" who="integrator" mine dead deadpid
	[ "$LOCK_NAME" = run.lock ] || who="prechecker"
	mine="$STATE/.$LOCK_NAME.new.$$"
	rm -rf "$mine"; mkdir "$mine" 2>/dev/null || return 1
	printf 'pid=%s\nwinpid=%s\nsince=%s\nscript=%s\n' "$$" "$(cat /proc/$$/winpid 2>/dev/null)" "$(now)" "$SELF" >"$mine/owner"
	if ! mv -T "$mine" "$d" 2>/dev/null; then
		if [ ! -s "$d/owner" ] && [ -n "$(find "$d" -maxdepth 0 -mmin -2 2>/dev/null)" ]; then rm -rf "$mine"; return 1; fi # an old-style lock being born
		if lockdir_alive "$LOCK_NAME"; then rm -rf "$mine"; return 1; fi
		deadpid="$(lockdir_pid "$LOCK_NAME")"
		dead="$STATE/.$LOCK_NAME.dead.$$"
		mv -T "$d" "$dead" 2>/dev/null || { rm -rf "$mine"; return 1; }
		if [ "$(sed -n 's/^pid=//p' "$dead/owner" 2>/dev/null)" != "$deadpid" ]; then
			# another process replaced the dead lock between our look and our move: put its lock back and step aside
			mv -T "$dead" "$d" 2>/dev/null || rm -rf "$dead"
			rm -rf "$mine"; return 1
		fi
		rm -rf "$dead"
		tlog "replacing the lock of a dead $who (pid ${deadpid:-none})"
		mv -T "$mine" "$d" 2>/dev/null || { rm -rf "$mine"; return 1; }
	fi
	[ "$(lockdir_pid "$LOCK_NAME")" = "$$" ] || return 1
	LOCK_HELD=1
}
lock_owned() { [ "$(lockdir_pid "$LOCK_NAME")" = "$$" ]; } # still ours (checked at every cycle: a second integrator must stop, not gate)
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
	printf 'seq=%s\nbranch=%s\ntip=%s\ntests=%s\nlight=%s\nowner=%s\nsince=%s\nattempts=0\n' "$(date +%s%N)" "$branch" "$tip" "$tests" "$light" "$owner" "$(now)" >"$f.tmp" || die "could not write $f"
	qlock; mv -f "$f.tmp" "$f"; qunlock
	rm -f "$REPORTS/$(fname "$branch").md" "$BOUNCED/$(fname "$branch").q"
	# enqueueing a tip again asks for a fresh precheck: forget this tip's verdicts and probe marks
	find "$PRE/v" "$PRE/probe" "$PRE/dc/v" -maxdepth 1 -type f -name "$(fname "$branch")@${tip:0:12}@*" -delete 2>/dev/null
	rm -f "$PRE/dc/solo/$(fname "$branch")"
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
	mkdir -p "$to/ci" "$to/train" || return 1
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
	rm -rf "$stage"; mkdir -p "$stage/ci" "$stage/train" || return 0
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
	# A running integrator only starts the prechecker between cycles: a lane enqueued during a 10-minute cycle waited for its end before its
	# precheck even began (27 October: 11 of migrate/ratchet-tail's 34 minutes in the queue). Start it now, from the integrator's snapshot.
	if integrator_alive; then tlog "integrator already running (pid $(integrator_pid)); the enqueued lane joins its next cycle"; precheck_ensure; return 0; fi
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
	qlock
	if [ -f "$f" ]; then
		{ cat "$f"; echo "bounced=$(now)"; echo "reason=$why"; echo "report=$rep"; } >"$BOUNCED/$(fname "$b").q.tmp.$$" && mv -f "$BOUNCED/$(fname "$b").q.tmp.$$" "$BOUNCED/$(fname "$b").q"
		rm -f "$f"
	fi
	qunlock
	tlog "BOUNCED $b: $why (report $rep)"
}
# A lane enqueued without --light whose change touches no DM path, compiler or build tool runs no DM world: it rides the light path
# (cheap checks only). The light batch merges origin/<branch>, so its tip is pushed there first (never forced).
promote_light() { # <branch>
	local b="$1" f tip
	f="$(qfile "$b")"
	[ "$(qget "$f" light)" = 1 ] && return 0
	tip="${TIP_OF[$b]:-$(qget "$f" tip)}"
	G diff --name-only "origin/master...$tip" 2>/dev/null | awk '
		/\.(dm|dme|dmm|dmf|dmi|dmb|rsc)$/ || /^(maps|icons|code|interface|sound|tgui)\// || /^tools\/(dmb|build)\// { heavy = 1 }
		END { exit heavy ? 0 : 1 }' && return 0
	if [ "$(G rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null)" != "$tip" ] && ! G push -q origin "$tip:refs/heads/$b" 2>/dev/null; then return 0; fi
	qedit "$b" -e "s/^light=.*/light=1/"
	tlog "$b changes no DM, compiler or build tool: it rides the light path (no DM world)"
}
adopt_tip() { # <branch> <queued tip> <current tip>: 0 = the queue now holds the current tip; 1 = bounced (a light lane that cannot be pushed)
	local b="$1" old="$2" cur="$3" f
	f="$(qfile "$b")"
	if [ "$(qget "$f" light)" = 1 ] && [ "$(G rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null)" != "$cur" ]; then
		# the light batch merges origin/<branch>: publish the new tip there (never forced)
		if ! G push -q origin "$cur:refs/heads/$b" 2>/dev/null; then
			bounce "$b" "the branch moved after it was enqueued (queued ${old:0:10}, now ${cur:0:10}) and the new tip could not be pushed to origin (not a fast-forward?): enqueue again"
			return 1
		fi
	fi
	qedit "$b" -e "s/^tip=.*/tip=$cur/" -e "s/^attempts=.*/attempts=0/"
	tlog "adopted the new tip of $b (${old:0:10} -> ${cur:0:10}): it stays queued, no bounce"
	return 0
}
mark_landed() { # <branch> <snapshot tip> <master sha>
	local b="$1" tip="$2" sha="$3" f cur
	f="$(qfile "$b")"
	printf 'branch=%s\ntip=%s\nmaster=%s\nlanded=%s\n' "$b" "$tip" "$sha" "$(now)" >"$LANDED/$(fname "$b").landed"
	# a bounce record for this tip (or an older one) is stale once the tip is in master: a racing cycle may have written it
	if [ -f "$BOUNCED/$(fname "$b").q" ] && G merge-base --is-ancestor "$(qget "$BOUNCED/$(fname "$b").q" tip)" "$sha" 2>/dev/null; then
		rm -f "$BOUNCED/$(fname "$b").q"; tlog "$b: cleared its stale bounce record (it landed)"
	fi
	# a lane that enqueued a newer tip, or committed more, while its old tip rode the train stays queued with what is not in master yet
	cur="$(G rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null || G rev-parse -q --verify "refs/remotes/origin/$b^{commit}" 2>/dev/null)"
	if [ -f "$f" ] && [ "$(qget "$f" tip)" = "$tip" ]; then
		if [ -n "$cur" ] && [ "$cur" != "$tip" ] && ! G merge-base --is-ancestor "$cur" "$sha" 2>/dev/null; then
			tlog "$b moved while its tip ${tip:0:10} rode the cycle: the new tip ${cur:0:10} is carried to the next cycle"
		else
			rm -f "$f"
		fi
	fi
	tlog "LANDED $b (tip ${tip:0:10}) in origin/master ${sha:0:10}"
}
bump_attempts() { local f n; f="$(qfile "$1")"; [ -f "$f" ] || return 0; n="$(qget "$f" attempts)"; n=$(( ${n:-0} + 1 )); qedit "$1" -e "s/^attempts=.*/attempts=$n/"; }

bump_push_refusals() { # <branch>: counts non-"master moved" push refusals in the queue file; prints the new count
	local f n; f="$(qfile "$1")"; [ -f "$f" ] || { echo 0; return 0; }
	n="$(qget "$f" push_refusals)"; n=$(( ${n:-0} + 1 ))
	# never an append: an append to a file a bounce just removed created a queue entry with nothing but this line
	if grep -q '^push_refusals=' "$f"; then qedit "$1" -e "s/^push_refusals=.*/push_refusals=$n/"; else qedit "$1" -e "\$a push_refusals=$n"; fi
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
# ---- DreamChecker for the queued lanes, in one run (27 October: one SpacemanDMM run is ~340 s and cannot check single files) --------------
# A precheck defers DreamChecker (DQ_GATE_DC_DEFER) and records "tpass" when everything else passed. The prechecker runs DreamChecker ONCE on
# origin/master plus every queued lane that has no DreamChecker verdict yet (dc_batch_run: tools/dq_merge_batch.sh --no-tests with
# DQ_GATE_ONLY_DC in WT_DC; a failure bisects to the culprit lane), and a lane that changes no DreamChecker input passes at once. A tpass
# lane with a DreamChecker pass becomes "pass" (dc_finalize); a DreamChecker failure bounces it with the log. A lane that conflicted with
# another lane of the run, or a run that broke, is checked alone next ($PRE/dc/solo). DQ_TRAIN_DC_BATCH=0: per-precheck DreamChecker.
dc_verdict_file() { find "$PRE/dc/v" -maxdepth 1 -type f -name "$(pre_key "$1" "$2")@*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-; }
dc_status() { # <branch> <tip>: pass | fail | none. A verdict older than the lane's queue entry (it was enqueued again since) is none: whatever script enqueued it, a stale DreamChecker fail never bounces the new entry
	local f w q; f="$(dc_verdict_file "$1" "$2")"
	[ -n "$f" ] || { echo none; return 0; }
	w="$(qget "$f" when)"; q="$(qget "$(qfile "$1")" since)"
	if [ -n "$w" ] && [ -n "$q" ] && [[ "$w" < "$q" ]]; then echo none; else qget "$f" verdict; fi
}
dc_record() { # <branch> <tip> <master> <verdict> <log> <why>
	local f="$PRE/dc/v/$(pre_key "$1" "$2")@${3:0:12}"
	printf 'branch=%s\ntip=%s\nmaster=%s\nverdict=%s\nlog=%s\nwhy=%s\nwhen=%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$(now)" >"$f.tmp" && mv -f "$f.tmp" "$f"
}
lane_tip_now() { G rev-parse -q --verify "refs/heads/$1^{commit}" 2>/dev/null || G rev-parse -q --verify "refs/remotes/origin/$1^{commit}" 2>/dev/null; }
dc_needs_run() { # <tip> <master>: 0 when the lane changes something DreamChecker reads
	G diff --name-only "$2...$1" 2>/dev/null | grep -qE '^tools/analyze/|^SpacemanDMM\.toml$' && return 0
	[ -n "$(dc_inputs "$2...$1")" ]
}
dc_batch_run() { # <master> <lanes...>: one DreamChecker run on master + the lanes (a background job of the prechecker)
	local master="$1" log good line lane why lg b
	shift
	ensure_wt_at "$WT_DC" || { tlog "DreamChecker batch: no worktree $WT_DC"; return 0; }
	log="$LOGS/dcbatch-$(date +%Y%m%dT%H%M%S).log"
	tlog "DreamChecker batch: [$*] on origin/master ${master:0:10} in $WT_DC; log $log"
	(
		cd "$WT_DC" || exit 99
		export DQ_MERGE_BRANCH="train/dc" DQ_MERGE_SESSION="train-dc-$$" DQ_DREAMMAKER_GATE=0 DQ_GATE_DREAMCHECKER=1 DQ_GATE_ONLY_DC=1
		unset DQ_BATCH_DEADLINE DQ_BATCH_CACHE DQ_BATCH_WT2 DQ_SLOT_PRIORITY DQ_GATE_DC_DEFER DQ_GATE_DC_DISJOINT
		bash tools/dq_merge_batch.sh --lanes "$*" --no-tests --no-dm
	) >"$log" 2>&1
	good="$(sed -n 's/^BATCH_GOOD: //p' "$log" | tail -n 1)"
	for b in $good; do dc_record "$b" "$(lane_tip_now "$b")" "$master" pass "$log" "passed with [$*]"; done
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		lane="${line%%|*}"; why="${line#*|}"; lg="${why##*|}"; why="${why%|*}"
		case "$why" in
			*"merge conflict"*) : >"$PRE/dc/solo/$(fname "$lane")" ;;
			*) if [ -f "$WT_DC/$lg" ]; then lg="$WT_DC/$lg"; else lg="$log"; fi; dc_record "$lane" "$(lane_tip_now "$lane")" "$master" fail "$lg" "DreamChecker: $why" ;;
		esac
	done < <(sed -n 's/^BATCH_BOUNCED: //p' "$log")
	for b in $(sed -n 's/^BATCH_LATER: //p' "$log" | tail -n 1); do : >"$PRE/dc/solo/$(fname "$b")"; done
	# a run that judged nobody (it broke): each lane is checked alone next; a lone lane that breaks is an error, retried later
	if [ -z "$good" ] && ! grep -q '^BATCH_BOUNCED: ' "$log"; then
		if [ $# -eq 1 ]; then dc_record "$1" "$(lane_tip_now "$1")" "$master" error "$log" "the DreamChecker run did not finish"
		else for b in "$@"; do : >"$PRE/dc/solo/$(fname "$b")"; done; fi
	fi
	tlog "DreamChecker batch done: pass=[${good:-}] (log $log)"
	return 0
}
dc_finalize() { # tpass lanes whose DreamChecker verdict arrived: pass, or bounced
	local b tip vf dv dvf
	for b in $(queue_branches); do
		tip="$(qget "$(qfile "$b")" tip)"
		[ "$(pre_status "$b" "$tip")" = tpass ] || continue
		dv="$(dc_status "$b" "$tip")"
		vf="$(pre_verdict_file "$b" "$tip")"
		dvf="$(dc_verdict_file "$b" "$tip")"
		case "$dv" in
			pass)
				sed -i 's/^verdict=tpass$/verdict=pass/' "$vf"
				tlog "PRECHECK pass: $b (tip ${tip:0:10}) on master $(qget "$vf" master | cut -c1-10) (DreamChecker: $(qget "$dvf" why))"
				;;
			fail)
				# A DreamChecker failure on an older master, or from a batch run (several lanes), is not proof against this lane today
				# (28 October: lanes bounced at 00:28 on a 22:14 batch on 8d956975f3 whose attempts all failed on a dirty tree). Such a
				# verdict is dropped and the lane is checked ALONE on current master next; only a solo failure on current master bounces.
				local cur_m; cur_m="$(G rev-parse origin/master 2>/dev/null)"
				local once="$PRE/dc/solo/$(fname "$b")@${tip:0:12}.rechecked" dm; dm="$(qget "$dvf" master)"
				if [ "$dm" != "$cur_m" ] || [ ! -f "$once" ]; then
					tlog "DreamChecker fail for $b (on master ${dm:0:10}; current ${cur_m:0:10}) is dropped: the lane is checked ALONE on current master next, and only that verdict can bounce it ($(qget "$dvf" why))"
					rm -f "$dvf"; : >"$PRE/dc/solo/$(fname "$b")"
					[ "$dm" != "$cur_m" ] || : >"$once"
					continue
				fi
				sed -i 's/^verdict=tpass$/verdict=fail/' "$vf"
				# the verdict carries the DreamChecker reason: a later bounce of this verdict (a raced re-enqueue) must not print an empty one
				{ grep -v '^why=' "$vf"; printf 'why=%s\n' "$(qget "$dvf" why)"; } >"$vf.tmp" && mv -f "$vf.tmp" "$vf"
				tlog "PRECHECK fail: $b (tip ${tip:0:10}): $(qget "$dvf" why)"
				bounce "$b" "precheck: $(qget "$dvf" why) (DreamChecker on origin/master $(qget "$dvf" master | cut -c1-10) with the queued lanes)" "$(qget "$dvf" log)"
				;;
		esac
	done
}
dc_pending() { # a queued lane waits for a DreamChecker verdict that a run can still give (tpass without a verdict)
	local b tip
	[ "$DC_BATCH" = 1 ] || return 1
	for b in $(queue_branches); do
		tip="$(qget "$(qfile "$b")" tip)"
		[ "$(pre_status "$b" "$tip")" = tpass ] && [ "$(dc_status "$b" "$tip")" = none ] && return 0
	done
	return 1
}
dc_candidates() { # <master>: the queued heavy lanes that need a DreamChecker run now (a solo one alone); records no-input passes
	local master="$1" b tip st solo=() many=()
	for b in $(queue_branches); do
		lane_is_light "$b" && continue
		listed_in "$STATE/batch.lanes" "$b" && continue
		tip="$(qget "$(qfile "$b")" tip)"
		[ "$(lane_tip_now "$b")" = "$tip" ] || continue
		case "$(pre_status "$b" "$tip")" in fail|conflict) continue ;; esac
		st="$(dc_status "$b" "$tip")"
		case "$st" in
			none) ;;
			error) [ -n "$(find "$(dc_verdict_file "$b" "$tip")" -mmin +"${DQ_TRAIN_PRECHECK_RETRY_MIN:-30}" 2>/dev/null)" ] || continue ;;
			*) continue ;;
		esac
		if ! dc_needs_run "$tip" "$master"; then dc_record "$b" "$tip" "$master" pass "" "it changes nothing DreamChecker reads"; continue; fi
		if [ -f "$PRE/dc/solo/$(fname "$b")" ]; then solo+=("$b"); else many+=("$b"); fi
	done
	if [ ${#solo[@]} -gt 0 ]; then rm -f "$PRE/dc/solo/$(fname "${solo[0]}")"; echo "${solo[0]}"; return 0; fi
	[ ${#many[@]} -gt 0 ] && printf '%s\n' "${many[@]}" | head -n "${DQ_TRAIN_DC_BATCH_MAX:-12}"
	return 0
}
# ---- light prechecks (27 October: compiler lanes ride the light path; their cargo tests made each light cycle ~10 min, ahead of every DM lane) --
# The prechecker runs a light lane's cheap checks on its merge with master (DQ_GATE_LIGHT) beside the gates. The light cycle takes a light
# lane once that passed (or when prechecks are off, or after the wait limit), and lands it without repeating the checks when master changed
# nothing in the lane's areas since (light_trust: a crate, tools/<x>, or a directory; a parent area such as tools/dmb overlaps its crates).
light_area() { awk '{ n = split($0, p, "/"); if (p[1] == "tools" && p[2] == "dmb" && p[3] == "crates" && n > 4) print p[1] "/" p[2] "/" p[3] "/" p[4]; else if (p[1] == "tools" && n > 3) print p[1] "/" p[2]; else if (p[1] == "tools" && n == 2) print $0; else if (n > 1) { sub(/\/[^\/]*$/, "", $0); print } else print "." }' | sort -u; }
light_ready() { # <branch>: a light lane may ride now
	local b="$1" tip st since_s
	[ "$PRE_ON" = 1 ] && [ "$LIGHT_PRE" = 1 ] || return 0
	tip="${TIP_OF[$b]:-$(qget "$(qfile "$b")" tip)}"
	st="$(pre_status "$b" "$tip")"
	[ "$st" = pass ] && return 0
	case "$st" in fail|conflict) return 1 ;; esac
	since_s="$(date -d "$(qget "$(qfile "$b")" since)" +%s 2>/dev/null || date +%s)"
	[ $(( $(date +%s) - since_s )) -ge $(( PRE_WAIT_MIN * 60 )) ]
}
light_trust() { # <lanes...>: 0 and LIGHT_TRUST_WHY set when every lane's light precheck still holds on current origin/master
	local b tip vf pm master la ma a m seen=""
	LIGHT_TRUST_WHY=""
	[ "$PRE_ON" = 1 ] && [ "$LIGHT_PRE" = 1 ] || return 1
	master="$(G rev-parse origin/master 2>/dev/null)" || return 1
	for b in "$@"; do
		tip="${TIP_OF[$b]:-$(qget "$(qfile "$b")" tip)}"
		vf="$(pre_verdict_file "$b" "$tip")"
		[ -n "$vf" ] && [ "$(qget "$vf" verdict)" = pass ] || return 1
		pm="$(qget "$vf" master)"
		G merge-base --is-ancestor "$pm" "$master" 2>/dev/null || return 1
		if [ "$pm" != "$master" ]; then
			la="$(G diff --name-only "$master...$tip" | light_area)"
			ma="$(G diff --name-only "$pm" "$master" | light_area)"
			for a in $la; do for m in $ma; do
				case "$a/" in "$m/"*) return 1 ;; esac
				case "$m/" in "$a/"*) return 1 ;; esac
			done; done
		fi
		seen="$seen $b@${pm:0:10}"
	done
	LIGHT_TRUST_WHY="every lane passed these checks in its light precheck (${seen# }) and master changed nothing in their areas since"
	return 0
}
lane_is_light() { [ "$(qget "$(qfile "$1")" light)" = 1 ]; }
free_ram_gb() { awk '/^MemAvailable:/ {a=$2} /^MemFree:/ {f=$2} END {print int((a ? a : f) / 1048576)}' /proc/meminfo 2>/dev/null || echo 999; } # MemAvailable counts the Windows standby cache MemFree leaves out
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
	# with the repository's merge drivers (tools/dq_git_safe.sh: shrink-only baselines, the manifest's include sets), as the real merge has them
	out="$(cd "$(repo_dir)" && { [ -f tools/dq_git_safe.sh ] && . tools/dq_git_safe.sh; GIT_OBJECT_DIRECTORY="$scratch" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common/objects" git merge-tree --write-tree --name-only --no-messages "$3" "$2"; } 2>/dev/null)" || rc=$?
	rm -rf "$scratch"
	[ "$rc" -eq 1 ] || return 0 # clean, or merge-tree could not tell (the full precheck merges for real)
	CONFLICT_FILES="$(tail -n +2 <<<"$out" | awk 'NF' | sort -u)"
	# the manifest merges by sets, shared docs by union (tools/dq_merge_batch.sh doc_union_conflict): neither is a conflict here
	# files with a merge driver or a union rule (baselines, the manifest, the unit-test list) never stop the real merge either
	f="$(grep -vE '^(deepquarry\.dme|AGENTS\.md|CLAUDE\.md|doc/.*\.md|tools/.*/doc/[^/]*\.md|tools/ci/[^/]*_baseline\.txt|tools/ci/sys_baseline/.*\.txt|code/modules/unit_tests/_unit_tests\.dm)$' <<<"$CONFLICT_FILES")"
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
	local is_light=0; lane_is_light "$b" && is_light=1
	printf 'branch=%s\ntip=%s\nworker=%s\npid=%s\nsince=%s\n' "$b" "$tip" "$n" "$BASHPID" "$(now)" >"$PRE/running/$(fname "$b")"
	ensure_wt_at "$wt" || { rm -f "$PRE/running/$(fname "$b")"; pre_record "$b" "$tip" "unknown" error 0 "" "no precheck worktree $wt"; return 0; }
	G fetch -q origin 2>/dev/null
	master="$(G rev-parse origin/master)"
	log="$LOGS/precheck-$(fname "$b")-$(date +%Y%m%dT%H%M%S).log"
	tlog "precheck: $b (tip ${tip:0:10}) on origin/master ${master:0:10} in $wt; log $log"
	(
		cd "$wt" || exit 99
		export DQ_MERGE_BRANCH="train/pre$n" DQ_MERGE_SESSION="train-pre$n-$$" DQ_DREAMMAKER_GATE=0 DQ_FOCUSED_MAX_MIN="$TEST_MAX_MIN" DQ_GATE_DREAMCHECKER=1
		[ "$DC_BATCH" = 1 ] && export DQ_GATE_DC_DEFER=1
		unset DQ_BATCH_DEADLINE DQ_BATCH_CACHE DQ_BATCH_WT2 DQ_SLOT_PRIORITY
		set -f
		if [ "$is_light" = 1 ]; then
			export DQ_GATE_LIGHT=1; unset DQ_GATE_DC_DEFER
			bash tools/dq_merge_batch.sh --lanes "$b" --no-tests --no-dm
		else
			# lane tests + boot only: the smoke and gameplay sets run once per batch in the integrator's gate (DQ_TRAIN_PRECHECK_SMOKE=1: per precheck as before)
			bash tools/dq_merge_batch.sh --lanes "$b" --lane-tests "$b=$tests" ${PRE_SMOKE_ARGS[@]+"${PRE_SMOKE_ARGS[@]}"} --no-dm
		fi
	) >"$log" 2>&1
	rc=$?
	secs=$(( $(date +%s) - t0 ))
	good="$(sed -n 's/^BATCH_GOOD: //p' "$log" | tail -n 1)"
	bl="$(sed -n 's/^BATCH_BOUNCED: //p' "$log" | tail -n 1)"
	if [[ " $good " == *" $b "* ]]; then
		verdict=pass
		# DreamChecker was deferred to the DreamChecker batch: the precheck passes once that verdict is in (dc_finalize)
		[ "$DC_BATCH" = 1 ] && [ "$is_light" = 0 ] && [ "$(dc_status "$b" "$tip")" != pass ] && verdict=tpass
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
	local i b tip f master want idle_rounds=0 ram_note=0 dcpid="" dcl=()
	while :; do
		# reap the DreamChecker batch, settle the lanes waiting for it
		if [ -n "$dcpid" ] && ! kill -0 "$dcpid" 2>/dev/null; then wait "$dcpid" 2>/dev/null; dcpid=""; fi
		[ "$DC_BATCH" = 1 ] && dc_finalize
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
			lane_is_light "$b" && [ "$LIGHT_PRE" != 1 ] && continue
			listed_in "$STATE/batch.lanes" "$b" && continue
			listed_in "$STATE/light.lanes" "$b" && continue
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
		# the DreamChecker batch: one run at a time, for every queued lane still without a verdict (beside the prechecks)
		if [ "$DC_BATCH" = 1 ] && [ -z "$dcpid" ]; then
			mapfile -t dcl < <(dc_candidates "$master")
			if [ ${#dcl[@]} -gt 0 ] && [ -n "${dcl[0]}" ] && [ "$(free_ram_gb)" -ge "$PRE_MIN_FREE_GB" ]; then dc_batch_run "$master" "${dcl[@]}" & dcpid=$!; fi
			dc_finalize
		fi
		if [ ${#want[@]} -eq 0 ] && [ ${#wpid[@]} -eq 0 ] && [ -z "$dcpid" ] && ! dc_pending; then
			idle_rounds=$((idle_rounds + 1))
			if [ "$idle_rounds" -ge "${DQ_TRAIN_PRECHECK_IDLE_ROUNDS:-2}" ]; then tlog "prechecker: nothing to precheck; exits"; exit 0; fi
		else
			idle_rounds=0
		fi
		# start workers: cheap prechecks first (a lane that changes no DM reuses DreamChecker's verdict and patches nothing in the compile),
		# then queue order; at most PRE_WORKERS at once, never below the free-RAM floor
		if [ ${#want[@]} -gt 1 ] && [ ${#wpid[@]} -le "$PRE_WORKERS" ]; then
			local cheap=() dear=()
			for b in "${want[@]}"; do
				if G diff --name-only "origin/master...$(qget "$(qfile "$b")" tip)" 2>/dev/null | grep -qE '^(code|maps|interface)/|\.dme$|\.dmm$'; then dear+=("$b"); else cheap+=("$b"); fi
			done
			want=("${cheap[@]+"${cheap[@]}"}" "${dear[@]+"${dear[@]}"}")
		fi
		for b in "${want[@]+"${want[@]}"}"; do
			# A light lane (docs, tools: cheap checks, no compile) has its own worker slot "L": it never waits behind the heavy prechecks (21 minutes on 27 October)
			# and the free-RAM floor does not apply to it. Heavy lanes use the PRE_WORKERS slots as before.
			local is_l=0 hv=${#wpid[@]}
			lane_is_light "$b" && is_l=1
			[ -z "${wpid[L]:-}" ] || hv=$((hv - 1))
			if [ "$is_l" = 1 ]; then
				[ -z "${wpid[L]:-}" ] || continue
				listed_in "$STATE/batch.lanes" "$b" && continue
				precheck_one L "$b" "$(qget "$(qfile "$b")" tip)" &
				wpid[L]=$!; wlane[L]="$b"
				continue
			fi
			[ "$hv" -lt "$PRE_WORKERS" ] || break
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
		[ "${DQ_TRAIN_ONCE:-0}" = 1 ] && [ ${#wpid[@]} -eq 0 ] && [ ${#want[@]} -eq 0 ] && [ -z "$dcpid" ] && ! dc_pending && exit 0
		if [ -n "$dcpid" ] && [ ${#wpid[@]} -eq 0 ]; then
			local w=0; while [ "$w" -lt "${DQ_TRAIN_PRECHECK_POLL_SEC:-60}" ] && kill -0 "$dcpid" 2>/dev/null; do sleep 2; w=$((w + 2)); done
		elif [ ${#wpid[@]} -gt 0 ]; then
			# wake when a worker ends, at most DQ_TRAIN_PRECHECK_POLL_SEC later (new lanes are looked at then)
			local w=0; while [ "$w" -lt "${DQ_TRAIN_PRECHECK_POLL_SEC:-60}" ]; do sleep 2; w=$((w + 2)); for i in "${!wpid[@]}"; do kill -0 "${wpid[$i]}" 2>/dev/null || break 2; done; done
		else
			wait_change "${DQ_TRAIN_PRECHECK_POLL_SEC:-60}" "$Q"   # an enqueue starts its precheck at once
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

# ---- DreamChecker for a prechecked batch (no run when the lanes' DreamChecker inputs are disjoint) ----------------------------------
# SpacemanDMM checks only the whole tree (5-11 min). Every lane of a prechecked batch passed it alone on its merge with master. When no
# two lanes, and no lane and what master changed since its precheck, change the same DreamChecker input file, and no lane touches a
# global path (train_interact_global.txt: defines, engine, controllers, maps, build) or the generator (tools/analyze/), the batch keeps
# those verdicts: the gate's dreamchecker job is skipped (DQ_GATE_DC_DISJOINT; "dreamchecker trusted" in the timings). Anything else runs it
# (its verdict is still reused per input key, tools/dq_gate_verdicts.sh). DQ_TRAIN_DC_DISJOINT=0 turns this off.
warm_train_root() { # the train compile root (merge, pre<N>) whose test build is newest; nothing when DQ_TRAIN_WARM_ROOT=0 or none is known
	[ "${DQ_TRAIN_WARM_ROOT:-1}" = 1 ] || return 0
	local roots="${DQ_DMB_ROOTS:-E:/dq-cache/dmb-roots}" r best="" bt=0 t
	for r in merge $(seq -f 'pre%g' 1 "$PRE_WORKERS"); do
		t="$(stat -c %Y "$roots/deepquarry-$r/deepquarry.test.dmb-pair.json" 2>/dev/null)" || continue
		[ "$t" -gt "$bt" ] && { bt="$t"; best="$r"; }
	done
	echo "$best"
}
dc_inputs() { # <rev range>: the DreamChecker input files it changes (what gate_dc_key hashes, less the two include lists every lane touches: deepquarry.dme and the unit tests' _unit_tests.dm)
	G diff --name-only "$1" 2>/dev/null | awk '/^(doc|tools|tgui|html\/changelogs|\.github|SQL)\// || /\.md$/ || /^deepquarry\.dme$/ || /^code\/modules\/unit_tests\/_unit_tests\.dm$/ { next } { print }' | sort -u
}
dc_disjoint() { # <lanes...>: 0 and DC_DISJOINT_WHY set when the batch may keep the lanes' DreamChecker verdicts
	local b tip vf pm seen="" files f master dvf
	DC_DISJOINT_WHY=""
	[ "${DQ_TRAIN_DC_DISJOINT:-1}" = 1 ] || return 1
	master="$(G rev-parse origin/master 2>/dev/null)" || return 1
	declare -A owner=()
	for b in "$@"; do
		tip="${TIP_OF[$b]:-$(qget "$(qfile "$b")" tip)}"
		vf="$(pre_verdict_file "$b" "$tip")"
		[ -n "$vf" ] && [ "$(qget "$vf" verdict)" = pass ] || return 1
		pm="$(qget "$vf" master)"
		# the DreamChecker verdict may come from a later master (the DreamChecker batch): what changed since THAT master matters
		dvf="$(dc_verdict_file "$b" "$tip")"; if [ -n "$dvf" ] && [ "$(qget "$dvf" verdict)" = pass ] && [ -n "$(qget "$dvf" master)" ]; then pm="$(qget "$dvf" master)"; fi
		[ -n "$pm" ] && G merge-base --is-ancestor "$pm" "$master" 2>/dev/null || return 1
		global_hit "$master...$tip" && return 1
		G diff --name-only "$master...$tip" 2>/dev/null | grep -qE '^tools/analyze/|^SpacemanDMM\.toml$' && return 1
		files="$(dc_inputs "$master...$tip")"
		# what master changed since this lane's precheck must not touch the lane's files (master's own gate checked master)
		if [ "$pm" != "$master" ] && [ -n "$files" ] && [ -n "$(comm -12 <(printf '%s\n' "$files") <(dc_inputs "$pm..$master"))" ]; then return 1; fi
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			[ -z "${owner[$f]:-}" ] || return 1
			owner[$f]="$b"
		done <<<"$files"
		seen="$seen $b@${pm:0:10}"
	done
	DC_DISJOINT_WHY="every lane passed DreamChecker in its precheck (${seen# }) and no two change the same DreamChecker input"
	return 0
}

# ---- the analyzer's cargo tests for a prechecked batch (27 October: 472-513 s in a gate whose lane had passed them in its precheck) --------
# The gate runs analyze_tests when the batch changes tools/analyze or tools/dmb. A lane that changes them passed those very tests on its
# merge with master in its precheck. When exactly one lane of the batch changes them and master changed neither since that precheck, the
# combination runs the same analyzer and compiler sources: the gate keeps that verdict (DQ_GATE_ANALYZE_TRUSTED). DQ_TRAIN_ANALYZE_TRUST=0: off.
analyze_trusted() { # <lanes...>: 0 and ANALYZE_TRUST_WHY set when the batch may skip analyze_tests
	local b tip vf pm master who="" n=0
	ANALYZE_TRUST_WHY=""
	[ "${DQ_TRAIN_ANALYZE_TRUST:-1}" = 1 ] || return 1
	master="$(G rev-parse origin/master 2>/dev/null)" || return 1
	for b in "$@"; do
		tip="${TIP_OF[$b]:-$(qget "$(qfile "$b")" tip)}"
		G diff --name-only "$master...$tip" 2>/dev/null | grep -qE '^tools/(analyze|dmb)/' || continue
		n=$((n + 1)); [ "$n" -le 1 ] || return 1
		vf="$(pre_verdict_file "$b" "$tip")"
		[ -n "$vf" ] || return 1
		case "$(qget "$vf" verdict)" in pass|tpass) ;; *) return 1 ;; esac
		pm="$(qget "$vf" master)"
		[ -n "$pm" ] && G merge-base --is-ancestor "$pm" "$master" 2>/dev/null || return 1
		if [ "$pm" != "$master" ] && G diff --name-only "$pm" "$master" 2>/dev/null | grep -qE '^tools/(analyze|dmb)/'; then return 1; fi
		who="$b@${pm:0:10}"
	done
	[ "$n" -eq 1 ] || return 1
	ANALYZE_TRUST_WHY="$who passed analyze_tests in its precheck, no other lane of the batch changes tools/analyze or tools/dmb, and master changed neither since"
	return 0
}

# Smoke and gameplay sets on a proof landing (a prechecked batch with no interaction): prechecks run each lane's own tests and the boot gate
# only, so the sets run once every DQ_TRAIN_SMOKE_EVERY proof landings (default 4) and on any batch of DQ_TRAIN_SMOKE_AT_LANES lanes or more
# (default 5): one run covers several lanes. State: smoke_skipped (proof landings since the sets last ran).
smoke_due() { # <batch size>: 0 when this proof landing runs the sets
	local every="${DQ_TRAIN_SMOKE_EVERY:-4}" at="${DQ_TRAIN_SMOKE_AT_LANES:-5}" k
	k="$(cat "$STATE/smoke_skipped" 2>/dev/null)"; case "$k" in ''|*[!0-9]*) k=0 ;; esac
	[ "$1" -ge "$at" ] || [ $((k + 1)) -ge "$every" ]
}

# ---- one cycle ------------------------------------------------------------------------------------------------------------------
LOCK_HELD=0
declare -A TIP_OF
CYCLE_PROGRESS=0
CYCLE_T0=$(date +%s)

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
	# Light lanes (docs, tools, Rust: no DM world, minutes) go first and alone, so they never ride, or wait for, a DM gate.
	if [ ! -s "$STATE/bisect.lanes" ] && [ "${DQ_TRAIN_LIGHT_FIRST:-1}" = 1 ]; then
		for b in "${VALID[@]}"; do lane_is_light "$b" && light_ready "$b" && CHOSEN+=("$b"); done
		if [ ${#CHOSEN[@]} -gt 0 ]; then BATCH_LIMIT_NOW="light first"; BATCH_EST=0; set +f; return 0; fi
	fi
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
			if lane_is_light "$b"; then light_ready "$b" && P+=("$b"); continue; fi
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
		# Gather window (e): a heavy cycle costs ~15 min whatever its size, and on 27 October every heavy cycle took ONE lane because it
		# started the moment the first precheck passed while the next ones were minutes from their verdicts. While a precheck is running and
		# the oldest ready lane passed less than DQ_TRAIN_GATHER_MIN (default 8) minutes ago, the cycle waits for it, so a batch takes every
		# prechecked lane. DQ_TRAIN_GATHER_MIN=0 turns it off; a bisect in progress never waits.
		if [ ${#P[@]} -gt 0 ] && [ ${#W[@]} -gt 0 ] && [ "${DQ_TRAIN_GATHER_MIN:-8}" -gt 0 ]; then
			local nrun=0 oldest=0 vf mt pb
			for b in "${W[@]}"; do case "$(pre_status "$b" "${TIP_OF[$b]}")" in running|tpass) nrun=$((nrun + 1)) ;; esac; done
			for pb in "${P[@]}"; do
				lane_is_light "$pb" && continue
				vf="$(pre_verdict_file "$pb" "${TIP_OF[$pb]}")"; [ -n "$vf" ] || continue
				mt="$(stat -c %Y "$vf" 2>/dev/null || echo "$nowt")"
				{ [ "$oldest" -eq 0 ] || [ "$mt" -lt "$oldest" ]; } && oldest="$mt"
			done
			if [ "$nrun" -gt 0 ] && [ "$oldest" -gt 0 ] && [ $(( nowt - oldest )) -lt $(( ${DQ_TRAIN_GATHER_MIN:-8} * 60 )) ]; then
				local gmsg="gather: ${#P[@]} lane(s) ready [${P[*]}], $nrun precheck(s) still running; the heavy cycle waits up to ${DQ_TRAIN_GATHER_MIN:-8} min from the first pass ($(( (nowt - oldest) / 60 )) min so far) to take them together"; local gkey="${P[*]}|$nrun"
				[ "$gkey" = "${GATHER_LAST:-}" ] || tlog "$gmsg"
				GATHER_LAST="$gkey"
				BATCH_LIMIT_NOW=0; BATCH_EST=0; set +f; return 0
			fi
			[ -z "${GATHER_LAST:-}" ] || tlog "gather: done waiting; the batch takes every ready lane"
			GATHER_LAST=""
		fi
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
	local trust=""
	if light_trust "${CHOSEN[@]}"; then trust="$LIGHT_TRUST_WHY"; tlog "light cycle: the cheap checks are not repeated: $trust"; fi
	printf '%s\n' "${CHOSEN[@]}" >"$STATE/light.lanes"
	( cd "$(repo_dir)" && DQ_LANE_POOL_STATE="$lstate" DQ_MERGE_SESSION="train-light-$$" DQ_LIGHT_TRUST="$trust" bash tools/dq_land_batch.sh run ) >"$out" 2>&1
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
	rm -f "$lq"/*.q "$STATE/light.lanes"
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
	# Nothing in a prechecked batch interacts (every lane's own tests skipped: no shared area with another lane or with master since its
	# precheck, no global path): each lane passed the smoke and gameplay sets on its merge with master, and master passed them on its own.
	# What is left to prove is that the combination compiles and boots (dq_boot_gate). DQ_TRAIN_LONE_SMOKE=1 keeps the sets.
	# PROOF kinds (logged on the heavy-cycle line and on LANDED): "precheck" = the lanes land on their precheck proof, the batch gate only
	# compiles and boots the combination (+ DreamChecker unless trusted, + ratchets); "precheck+smoke" = the same plus the smoke/gameplay sets
	# (smoke_due); "full" = the lanes' tests run again (an interaction, a global path, an unprechecked lane).
	local smoke_args=() proof_kind="full" smoke_ran=1
	if [ "${PRECHECKED_BATCH:-0}" = 1 ] && [ "${DQ_TRAIN_LONE_SMOKE:-0}" != 1 ] && [ "${#SKIP_TESTS[@]}" -eq "${#CHOSEN[@]}" ]; then
		tests_union="dq_boot_gate"
		case " ${lane_test_args[*]} " in *" --tests dq_boot_gate "*) ;; *) lane_test_args+=(--tests dq_boot_gate) ;; esac
		if smoke_due "${#CHOSEN[@]}"; then
			proof_kind="precheck+smoke"
			tlog "PROOF precheck+smoke: no lane interacts with another or with master since its precheck; compile + boot, and the smoke/gameplay sets are due (every ${DQ_TRAIN_SMOKE_EVERY:-4} proof landings or ${DQ_TRAIN_SMOKE_AT_LANES:-5}+ lanes)"
		else
			smoke_args=(--no-smoke); proof_kind="precheck"; smoke_ran=0
			tlog "PROOF precheck: no lane interacts with another or with master since its precheck (merge-tree clean, disjoint areas): compile and boot only; smoke/gameplay sets not due ($(cat "$STATE/smoke_skipped" 2>/dev/null || echo 0) proof landing(s) since they last ran)"
		fi
	else
		tlog "PROOF full: the batch's lane tests run again ($([ "${PRECHECKED_BATCH:-0}" = 1 ] && echo "$(( ${#CHOSEN[@]} - ${#SKIP_TESTS[@]} )) lane(s) interact" || echo "not every lane is prechecked"))"
	fi
	deadline=$(( $(date +%s) + CYCLE_MAX_MIN * 60 ))
	local wt2_use="" deadline_use="$deadline" limit_file="$STATE/batch_limit" limit_max="$MAX_LANES"
	if [ "${PRECHECKED_BATCH:-0}" = 1 ]; then
		# Every lane passed alone: a failure is an interaction, and its bisect runs to the end in this cycle (no deadline; the machine is
		# protected by the machine slots and the RAM floor instead), both halves at once in the second worktree.
		deadline_use=""; limit_file="$STATE/batch_limit_pre"; limit_max="$MAX_LANES_PRE"
		if wt_ready "$WT2"; then wt2_use="$WT2"
		else ( ensure_wt_at "$WT2" ) >/dev/null 2>&1 & disown $! 2>/dev/null || true; fi # one-time checkout in the background; used from the next cycle
	fi
	local dc_why="" warm_root
	warm_root="$(warm_train_root)"
	[ -z "$warm_root" ] || [ "$warm_root" = merge ] || tlog "compile root: the batch compiles in deepquarry-$warm_root (the train root compiled last: its daemon session is the warm one)"
	if [ "${PRECHECKED_BATCH:-0}" = 1 ] && dc_disjoint "${CHOSEN[@]}"; then dc_why="$DC_DISJOINT_WHY"; tlog "dreamchecker: $dc_why; the batch keeps those verdicts"; fi
	local an_why=""
	if [ "${PRECHECKED_BATCH:-0}" = 1 ] && analyze_trusted "${CHOSEN[@]}"; then an_why="$ANALYZE_TRUST_WHY"; tlog "analyze_tests: $an_why; the batch keeps that verdict"; fi
	phase "gate: ${CHOSEN[*]}"
	tlog "heavy cycle: ${#CHOSEN[@]} lane(s) [${CHOSEN[*]}]$([ "${PRECHECKED_BATCH:-0}" = 1 ] && echo " (all prechecked; bisect to the end$([ -n "$wt2_use" ] && echo ", halves in parallel"))"), proof $proof_kind, tests [$tests_union] ($([ ${#smoke_args[@]} -gt 0 ] && echo "no smoke set" || echo "+ smoke set"), est ~${BATCH_EST}s), test cap ${TEST_MAX_MIN} min, $([ -n "$deadline_use" ] && echo "no new attempt after $(date -u -d "@$deadline" +%H:%MZ 2>/dev/null || echo "$CYCLE_MAX_MIN min")" || echo "no cycle deadline"); log $out"
	for b in "${CHOSEN[@]}"; do bump_attempts "$b"; done
	(
		cd "$WT" || exit 99
		export DQ_MERGE_BRANCH="$TBRANCH" DQ_MERGE_SESSION="train-$$" DQ_DREAMMAKER_GATE=0 DQ_FOCUSED_MAX_MIN="$TEST_MAX_MIN"
		# the union of tests in TEST_WORLDS worlds at once (any list over 8 selectors is split)
		export DQ_MAIN_WORLDS="$TEST_WORLDS" DQ_MAIN_WORLD_TESTS="${DQ_TRAIN_WORLD_SPLIT_AT:-8}"
		export DQ_SLOT_PRIORITY=0 DQ_PUSH_STRICT=1 DQ_PUSH_NO_REPROOF=1 DQ_PUSH_TRUST_GATE_DM=1 DQ_BATCH_DEADLINE="$deadline_use" DQ_BATCH_WT2="$wt2_use"
		# DreamChecker is a gate job of its own (parallel to the tests, a failure bisects to the culprit lane): the native compiler accepts
		# undefined fields DreamChecker rejects, and the push trusts the gate only with the gate's dreamchecker stamp on the exact HEAD.
		export DQ_GATE_DREAMCHECKER=1
		[ "${PRECHECKED_BATCH:-0}" != 1 ] || export DQ_GATE_CAP_MAX_MIN="${DQ_TRAIN_PRECHECKED_CAP_MIN:-20}"
		[ -z "$dc_why" ] || export DQ_GATE_DC_DISJOINT="$dc_why"
		[ -z "$an_why" ] || export DQ_GATE_ANALYZE_TRUSTED="$an_why"
		[ -z "$warm_root" ] || export DQ_TRAIN_ROOT_KEY="$warm_root"
		export DQ_BATCH_CACHE="$STATE/bisect.cache"
		# --no-dm: the test build compile already proves the code compiles; a second full native compile run in parallel starved the test
		# build of the compile slot, memory and CPU, and the test world was killed at the cap. CI keeps the production compile cross-check.
		bash tools/dq_merge_batch.sh --lanes "${CHOSEN[*]}" "${lane_test_args[@]}" ${smoke_args[@]+"${smoke_args[@]}"} --no-dm
	) >"$out" 2>&1
	rc=$?
	good="$(sed -n 's/^BATCH_GOOD: //p' "$out" | tail -n 1)"
	deferred="$(sed -n 's/^BATCH_DEFERRED: //p' "$out" | tail -n 1)"
	capped="$(sed -n 's/^BATCH_CAPPED: //p' "$out" | tail -n 1)"
	local later noresult nr; later="$(sed -n 's/^BATCH_LATER: //p' "$out" | tail -n 1)"
	noresult="$(sed -n 's/^BATCH_NORESULT: //p' "$out" | tail -n 1)"
	# A lane whose test phase gave no result twice (capped or killed, then again with only its own tests) stays queued, never bounced;
	# after DQ_TRAIN_NORESULT_MAX (3) such cycles it is bounced so it cannot hold the train for ever.
	for b in $noresult; do
		nr="$(qget "$(qfile "$b")" noresult)"; nr=$(( ${nr:-0} + 1 ))
		if grep -q '^noresult=' "$(qfile "$b")" 2>/dev/null; then qedit "$b" -e "s/^noresult=.*/noresult=$nr/"; else qedit "$b" -e "\$a noresult=$nr"; fi
		tlog "################ NO RESULT: $b: its test phase hit the cap or died without a verdict twice (once with only its own tests); DEFERRED, still queued ($nr of ${DQ_TRAIN_NORESULT_MAX:-3}); log $out"
		if [ "$nr" -ge "${DQ_TRAIN_NORESULT_MAX:-3}" ]; then
			bounce "$b" "its test phase gave no result in $nr cycles (capped or killed, also with only its own tests): see $out" "$out"
		fi
		deferred="$(printf '%s\n' $deferred | grep -vxF "$b" | tr '\n' ' ')"
		CYCLE_PROGRESS=1
	done
	[ -z "${later// /}" ] || { tlog "conflicted with another lane of this batch only, they stay queued for the next cycle: [$later]"; CYCLE_PROGRESS=1; }
	tlog "merge_batch rc=$rc good=[${good:-}] deferred=[${deferred:-}] capped=[${capped:-}]"
	# bounces first: they are the lane's fault whatever happens to the push
	# Only a failed TEST shrinks the next batch (nfailed): a merge conflict, a moved tip or a DreamChecker/ratchet culprit says nothing
	# about how many lanes fit, and the bisect already isolated the culprit. 2026-10-26: one conflict dropped the train to 1 lane/cycle.
	local nbounced=0 nfailed=0
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		nbounced=$((nbounced + 1))
		lane="${line%%|*}"; why="${line#*|}"; lg="${why##*|}"; why="${why%|*}"
		case "$why" in *"merge conflict"*) ;; *) grep -qE '^dq_merge_gates: FAILED: .*\btests\b' "$WT/$lg" 2>/dev/null && nfailed=$((nfailed + 1)) ;; esac
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
	if [ -z "${capped:-}" ] && [ "$nfailed" -gt 0 ]; then
		local fh=$(( ${#CHOSEN[@]} / 2 )); [ "$fh" -lt 1 ] && fh=1
		echo "$fh" >"$limit_file"
		tlog "the batch of ${#CHOSEN[@]} lane(s) failed tests (bounced $nbounced, $nfailed for failed tests, deferred [${deferred:-}]): batch limit is now $fh"
	elif [ "$nbounced" -gt 0 ]; then
		tlog "bounced $nbounced lane(s), none for a failed test: the batch limit stays"
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
	if [ -z "${capped:-}" ] && [ "$nfailed" -eq 0 ]; then
		# a cycle that landed with no failed test: back to the full batch size at once (not doubled step by step)
		echo "$limit_max" >"$limit_file"
	fi
	if [ "$smoke_ran" = 1 ]; then echo 0 >"$STATE/smoke_skipped"
	else echo $(( $(cat "$STATE/smoke_skipped" 2>/dev/null || echo 0) + 1 )) >"$STATE/smoke_skipped"; fi
	tlog "pushed: origin/master ${sha:0:10} carries [$good] (proof: $proof_kind; cycle $(( $(date +%s) - CYCLE_T0 ))s; smoke/gameplay sets $([ "$smoke_ran" = 1 ] && echo ran || echo "skipped, $(cat "$STATE/smoke_skipped") proof landing(s) since they last ran"))"
}

cycle() {
	local b f tip cur all=() t0
	t0=$(date +%s); CYCLE_T0=$t0
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
		if [ "$cur" != "$tip" ]; then
			# A lane that committed more after it was enqueued is not bounced: the queue adopts the new tip (a fresh precheck follows).
			# A tip that moved while its lane rode a cycle is carried here, to the next cycle (mark_landed keeps such a lane queued).
			if adopt_tip "$b" "$tip" "$cur"; then tip="$cur"; else CYCLE_PROGRESS=1; continue; fi
		fi
		if G merge-base --is-ancestor "$tip" origin/master; then mark_landed "$b" "$tip" "$(G rev-parse origin/master)"; tlog "$b was already in origin/master"; CYCLE_PROGRESS=1; continue; fi
		TIP_OF[$b]="$tip"
		VALID+=("$b")
	done
	[ ${#VALID[@]} -gt 0 ] || return 0
	[ "$AUTO_LIGHT" = 1 ] && for b in "${VALID[@]}"; do promote_light "$b"; done
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
		# the floor is checked here; the housekeeping enforcement runs detached (synchronous it held the cycle 2-8 minutes, 27 October)
		disk_budget gate "a heavy train cycle" --throttle 10; local drc=$?
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
		if ! lock_owned; then LOCK_HELD=0; tlog "the run lock is held by pid $(integrator_pid), not this integrator: exiting without a cycle"; exit 0; fi
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
			# wake as soon as a verdict or a lane arrives (a precheck that passed is taken within seconds), at most every PRECHECK_WAIT_SEC
			wait_change "${DQ_TRAIN_PRECHECK_WAIT_SEC:-60}" "$PRE/v" "$Q"
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
cmd_status() { # reads state files only: no git, no network, and bash builtins instead of forks (an agent's status must answer in about a second)
	[ -d "$Q" ] && [ -d "$PRE/v" ] && [ -d "$BOUNCED" ] && [ -d "$LANDED" ] || init_state
	local f b n=0 now k v tphase tstamp since pst pvf pt pk pm pmaster psecs
	printf -v now '%(%s)T' -1
	local -A Fq=()
	rd_kv() { local key val; Fq=(); while IFS='=' read -r key val || [ -n "$key" ]; do Fq["$key"]="$val"; done <"$1"; }
	lk_alive() { # <lock dir name>: the owner file read with builtins; sets lk_pid
		lk_pid=""; [ -f "$STATE/$1/owner" ] || return 1
		rd_kv "$STATE/$1/owner"; lk_pid="${Fq[pid]:-}"
		alive "$lk_pid" "${Fq[winpid]:-}"
	}
	local lk_pid
	if lk_alive run.lock; then
		rd_kv "$STATE/run.lock/owner"; since="${Fq[since]:-}"
		tstamp=0; tphase=""
		[ -f "$STATE/cycle.txt" ] && IFS=$'\t' read -r tstamp tphase <"$STATE/cycle.txt"
		echo "integrator: RUNNING pid $lk_pid since $since; phase: $tphase ($(( now - ${tstamp:-0} ))s ago)"
	else
		local waiting=""
		for f in "$Q"/*.q; do [ -e "$f" ] && { waiting=1; break; }; done
		echo "integrator: not running$([ -n "$waiting" ] && echo " (lanes are waiting: bash tools/dq_train.sh ensure)")"
	fi
	if [ "$PRE_ON" = 1 ]; then
		if lk_alive precheck.lock; then
			local nowrun=""
			for f in "$PRE/running"/*; do [ -e "$f" ] || continue; rd_kv "$f"; nowrun="$nowrun${Fq[branch]:-} "; done
			echo "prechecker: RUNNING pid $lk_pid ($PRE_WORKERS worker(s); now: $nowrun)"
		else echo "prechecker: not running"; fi
	fi
	# one pass over the queue: a malformed entry is moved aside by queue_branches (the only forking path, taken only when there is one)
	local -a rows=()
	local malformed_seen=0
	for f in "$Q"/*.q; do
		[ -e "$f" ] || continue
		rd_kv "$f"
		if [ -z "${Fq[seq]:-}" ] || [ -z "${Fq[branch]:-}" ] || [ -z "${Fq[tip]:-}" ]; then malformed_seen=1; continue; fi
		rows+=("${Fq[seq]}|${Fq[branch]}|${Fq[tip]}|${Fq[light]:-}|${Fq[tests]:-}|${Fq[since]:-}|${Fq[attempts]:-}")
	done
	[ "$malformed_seen" = 0 ] || queue_branches >/dev/null 2>&1
	local mal=""
	for f in "$STATE/malformed"/*; do [ -e "$f" ] && mal="$mal$(basename "$f") "; done
	[ -z "$mal" ] || echo "malformed queue entries (moved aside, not gated; enqueue those lanes again): ${mal:0:400}"
	local bl blp
	read -r bl <"$STATE/batch_limit" 2>/dev/null || bl="$MAX_LANES (default)"
	read -r blp <"$STATE/batch_limit_pre" 2>/dev/null || blp="$MAX_LANES_PRE (default)"
	echo "batch limit: $bl lane(s) per cycle; prechecked batches: $blp"
	echo "queue:"
	local sorted
	sorted="$(printf '%s\n' ${rows[@]+"${rows[@]}"} | sort -n -t'|' -k1,1)"
	local seq br tip light tests sn att
	while IFS='|' read -r seq br tip light tests sn att; do
		[ -n "$br" ] || continue
		n=$((n + 1)); pst=""
		if [ "$PRE_ON" = 1 ] && [ "$light" != 1 ]; then
			pk="${br//\//_}@${tip:0:12}"
			pvf=""
			for f in "$PRE/v/$pk@"*; do [ -e "$f" ] || continue; if [ -z "$pvf" ] || [ "$f" -nt "$pvf" ]; then pvf="$f"; fi; done
			pst=none
			if [ -f "$PRE/running/${br//\//_}" ]; then rd_kv "$PRE/running/${br//\//_}"; [ "${Fq[tip]:-}" = "$tip" ] && pst=running; fi
			if [ "$pst" != running ] && [ -n "$pvf" ]; then
				rd_kv "$pvf"; pst="${Fq[verdict]:-none}"
				pmaster="${Fq[master]:-}"; psecs="${Fq[secs]:-}"
				pst="$pst on master ${pmaster:0:10} in ${psecs}s"
			fi
			pst="  precheck: $pst"
		fi
		echo "  $br  tip ${tip:0:10}  $([ "$light" = 1 ] && echo light || echo "tests: $tests")  enqueued $sn  gate attempts: $att$pst"
	done <<<"$sorted"
	[ "$n" -gt 0 ] || echo "  (empty)"
	n=0
	echo "bounced (fix, then enqueue again):"
	for f in "$BOUNCED"/*.q; do
		[ -e "$f" ] || continue
		n=$((n + 1)); rd_kv "$f"
		echo "  ${Fq[branch]:-}: ${Fq[reason]:-}"
		echo "      report: ${Fq[report]:-}"
	done
	[ "$n" -gt 0 ] || echo "  (none)"
	echo "landed (latest 8):"
	n=0
	local lf pm
	for lf in $(ls -t "$LANDED"/*.landed 2>/dev/null | head -n 8); do rd_kv "$lf"; pm="${Fq[master]:-}"; echo "  ${Fq[branch]:-}  ${Fq[landed]:-}  master ${pm:0:10}"; n=$((n + 1)); done
	[ "$n" -gt 0 ] || echo "  (none yet)"
	echo "log: $LOGS/train.log"
}
cmd_report() {
	local b="${1:?usage: report <branch>}" r
	r="$REPORTS/$(fname "$b").md"
	[ -f "$r" ] || { if [ -f "$(qfile "$b")" ]; then echo "$b is queued, not bounced"; elif [ -f "$LANDED/$(fname "$b").landed" ]; then echo "$b landed: $(tr '\n' ' ' <"$LANDED/$(fname "$b").landed")"; else echo "no record of $b"; fi; return 0; }
	cat "$r"
}
cmd_lanes() { # per-lane waiting / in-cycle / fixing times and the mean gate phases (tools/train/lane_times.py)
	local since="${DQ_TRAIN_LANES_SINCE:-$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)}" here
	[ "${1:-}" = "--since" ] && since="${2:?--since needs a time like 2026-10-26T14:00:00Z}"
	here="$SELF_DIR/train/lane_times.py"; [ -f "$here" ] || here="$(repo_dir)/tools/train/lane_times.py"
	"${PYTHON:-python3}" "$here" "$LOGS/train.log" --since "$since" --timings "$WT/data/merge-gates"
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
	lanes) shift; cmd_lanes "$@" ;;
	*) sed -n '2,12p' "$0"; exit 2 ;;
esac
