#!/usr/bin/env bash
# End-to-end self-test of tools/dq_train.sh (the batch train) in one scratch repository: the real dq_train.sh, dq_merge_batch.sh and
# friends run against stub gates / stub push / stub light batch (no compiler, test world or master is touched). Every scenario drives the
# train as an operator would and checks what lands, what bounces and why. `sleep` is a stub, so waits and polls cost nothing.
# TEST_TRAIN_ONLY=<scenario[,scenario]> runs only those: enqueue light heavy push precheck dc bisect lock selfupdate stamp; "quick" = enqueue,light.
# Elapsed seconds are printed at the end; the target is under two minutes.
set -uo pipefail
# Each scenario owns a scratch repository and state, so with no TEST_TRAIN_ONLY they run side by side (TEST_TRAIN_JOBS at a time, default 1: a loaded desktop ran out of memory at 6):
# the wall time is the slowest scenario, not the sum (every git and bash spawn costs hundreds of ms on a loaded Windows machine).
if [ -z "${TEST_TRAIN_ONLY:-}" ]; then
	scen="enqueue light heavy push precheck dc bisect lock selfupdate stamp"
	outd="$(mktemp -d)"; trap 'rm -rf "$outd"' EXIT
	t_all=$(date +%s)
	printf '%s\n' $scen | xargs -P "${TEST_TRAIN_JOBS:-1}" -I{} sh -c 'TEST_TRAIN_ONLY={} bash "$0" >"$1/{}.log" 2>&1; echo $? >"$1/{}.rc"' "$0" "$outd"
	bad_n=0
	for sc in $scen; do
		echo "---- $sc (rc=$(cat "$outd/$sc.rc" 2>/dev/null || echo ?)) ----"
		grep -E '^(PASS|FAIL)' "$outd/$sc.log"
		[ "$(cat "$outd/$sc.rc" 2>/dev/null || echo 1)" = 0 ] || { bad_n=1; tail -n 5 "$outd/$sc.log"; }
	done
	echo "elapsed: $(( $(date +%s) - t_all )) s"
	[ "$bad_n" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
	exit 0
fi
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
t_start=$(date +%s)
real_sleep="$(command -v sleep)"
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexec "%s" 0.02\n' "$real_sleep" >"$tmp/bin/sleep"; chmod +x "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

export DQ_TRAIN_STATE="$tmp/state"
export DQ_TRAIN_WT="$tmp/train-wt"
export DQ_TRAIN_NO_START=1 DQ_TRAIN_NO_DISK_CHECK=1 DQ_TRAIN_RETRY_SEC=0
export DQ_TRAIN_RUNS_DIRS="$tmp/no-runs"
export DQ_FLAKE_LEDGER="$tmp/flakes.tsv"
# The prechecker (section "prechecks" below) is off for the cases written before it; its own section turns it on.
# One test world and no light promotion for the cases written before them (every scratch lane here changes no DM); their own cases turn them on.
export DQ_TRAIN_TEST_WORLDS=1 DQ_TRAIN_AUTO_LIGHT=0
export DQ_DMB_ROOTS="$tmp/no-roots"   # warm_train_root: never the machine's real compile roots
export DQ_TRAIN_DC_WT="$tmp/dc-wt"
export DQ_TRAIN_PRECHECK=0 DQ_TRAIN_PRE_WT="$tmp/pre-wt" DQ_TRAIN_WT2="$tmp/wt2" DQ_GATE_VERDICTS="$tmp/verdicts"

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
cd "$tmp/repo"
git config user.email t@t; git config user.name t
mkdir -p tools/ci lanes docs
cp "$here/tools/dq_train.sh" "$here/tools/dq_train_estimate.js" "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_proof_cache.sh" "$here/tools/dq_light_paths.sh" "$here/tools/dq_gate_retry.sh" "$here/tools/dq_declared_tests.sh" "$here/tools/dq_dme_resolve.sh" "$here/tools/dq_gate_verdicts.sh" tools/
echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
printf '#!/usr/bin/env bash\nexit 0\n' >tools/dq_disk_budget.sh  # stub: the integrator runs the disk gate from its SELF_DIR
echo '# manifest' >tools/ci/disk_budget.toml
mkdir -p tools/train; cp "$here/tools/train/lane_times.py" tools/train/
cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
# stub gates: BAD in a lane file fails; with DQ_STUB_CAP_ABOVE=N a batch of more than N lane files looks like a killed test phase
# DQ_GATE_ONLY_DC=1 (the train's DreamChecker batch): only DCFAIL fails
if [ "${DQ_GATE_ONLY_DC:-0}" = 1 ]; then
	echo "$*" >>"${DQ_STUB_DCRUN_LOG:-/dev/null}"
	if grep -rq DCFAIL lanes 2>/dev/null; then echo "stub dreamchecker: DCFAIL present"; echo "dq_merge_gates: FAILED: dreamchecker" >&2; exit 1; fi
	echo "stub dreamchecker: ok"; exit 0
fi
echo "defer=${DQ_GATE_DC_DEFER:-}" >>"${DQ_STUB_DEFER_LOG:-/dev/null}"
[ "${DQ_GATE_LIGHT:-0}" = 1 ] && { echo "light $*" >>"${DQ_STUB_LIGHT_LOG:-/dev/null}"; echo "stub light checks: ok"; exit 0; }
if grep -rq BAD lanes 2>/dev/null; then echo "stub gates: BAD present"; echo "dq_merge_gates: FAILED: tests (logs data/merge-gates/x.tests.log)" >&2; exit 1; fi
echo "worlds=${DQ_MAIN_WORLDS:-} split=${DQ_MAIN_WORLD_TESTS:-}" >>"${DQ_STUB_WORLDS_LOG:-/dev/null}"
# DQ_STUB_MOVE=<branch>: the lane commits more while its batch is being gated (once)
if [ -n "${DQ_STUB_MOVE:-}" ] && [ ! -e "$DQ_STUB_MOVE_DONE" ]; then
	: >"$DQ_STUB_MOVE_DONE"
	mv_c="$(git commit-tree "$(git rev-parse "$DQ_STUB_MOVE^{tree}")" -p "$(git rev-parse "$DQ_STUB_MOVE")" -m "moved during the gate")"
	git update-ref "refs/heads/$DQ_STUB_MOVE" "$mv_c"
fi
if grep -rq PAIR1 lanes 2>/dev/null && grep -rq PAIR2 lanes 2>/dev/null; then echo "stub gates: PAIR1 and PAIR2 together"; exit 1; fi
echo "$(pwd) $*" >>"${DQ_STUB_WHERE:-/dev/null}"
n="$(git diff --name-only origin/master HEAD -- lanes | wc -l)"
if [ -n "${DQ_STUB_CAP_ABOVE:-}" ] && [ "$n" -gt "$DQ_STUB_CAP_ABOVE" ]; then echo "FOCUSED RUN CAPPED: the 10 minute wall-clock cap was hit"; exit 1; fi
echo "$*" >>"${DQ_STUB_ARGS_LOG:-/dev/null}"
echo "dc=${DQ_GATE_DREAMCHECKER:-}" >>"${DQ_STUB_DC_LOG:-/dev/null}"
echo "dcdisjoint=${DQ_GATE_DC_DISJOINT:-} root=${DQ_TRAIN_ROOT_KEY:-}" >>"${DQ_STUB_DCD_LOG:-/dev/null}"
echo "stub gates: ok (tests: $*)"
STUB
cat >tools/dq_push_master.sh <<'STUB'
#!/usr/bin/env bash
# stub push: fails on DQ_STUB_PUSH_FAIL, checks the train's environment, then a plain fast-forward push to origin/master
[ -z "${DQ_STUB_PUSH_FAIL:-}" ] || { echo "stub push: REFUSED (${DQ_STUB_PUSH_MSG:-origin/master moved})"; exit 1; }
[ "${DQ_DREAMMAKER_GATE:-}" = 0 ] && [ "${DQ_PUSH_STRICT:-}" = 1 ] && [ -n "${DQ_MERGE_SESSION:-}" ] || { echo "stub push: the train did not set its environment"; exit 1; }
[ "${DQ_PUSH_DRY_RUN:-0}" = 1 ] && { echo "stub push: dry run"; exit 0; }
git push -q origin "HEAD:refs/heads/master" || exit 1
echo "stub push: pushed $(git rev-parse --short HEAD)"
STUB
cat >tools/dq_land_batch.sh <<'STUB'
#!/usr/bin/env bash
# stub light batch: merge every queued branch (origin/<b>) onto origin/master, skip conflicts, push
set -u
echo "trust=${DQ_LIGHT_TRUST:-}" >>"${DQ_STUB_LIGHT_LOG:-/dev/null}"
Q="${DQ_LANE_POOL_STATE:?}/light-queue"
git fetch -q origin
git switch -q --detach origin/master
for f in "$Q"/*.q; do
	[ -e "$f" ] || continue
	b="$(sed -n 's/^branch=//p' "$f")"
	git merge --no-ff --no-edit -q -m "Merge $b (light)" "origin/$b" >/dev/null 2>&1 || { git merge --abort >/dev/null 2>&1; echo "conflict: $b skipped"; }
	rm -f "$f"
done
git push -q origin "HEAD:refs/heads/master"
STUB
echo base >lanes/base.txt; echo x >shared.txt; echo doc >docs/readme.txt
printf 'ignored\n' >.gitignore; echo "data/" >>.gitignore
git add -A; git commit -q -m init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
main="$(git rev-parse --abbrev-ref HEAD)"

mk() { # <branch> <file> <content> [shared-line]: a lane branch off origin/master, left as the current branch
	git fetch -q origin
	git switch -q -c "$1" origin/master
	mkdir -p "$(dirname "$2")"
	echo "$3" >"$2"
	[ -z "${4:-}" ] || echo "$4" >shared.txt
	git add -A; git commit -q -m "$1"
}
back() { git switch -q --detach origin/master; }
train() { bash tools/dq_train.sh "$@"; }
in_master() { git fetch -q origin; git merge-base --is-ancestor "$1" origin/master; }
status_has() { local o; o="$(train status 2>&1)"; grep -q -- "$1" <<<"$o"; } # not `status | grep -q`: grep exits early and pipefail fails the pipe

# ---- enqueue guards -------------------------------------------------------------------------------------------------------------

only=",${TEST_TRAIN_ONLY:-},"
[ "$only" != ",quick," ] || only=",enqueue,light,"   # the light precheck runs this subset (about 90 s on a loaded machine; dc alone took over 10 minutes there)
want() { [ "$only" = ",," ] || [[ "$only" == *",$1,"* ]]; }
pre_on() {
	export DQ_TRAIN_PRECHECK=1 DQ_TRAIN_PRECHECK_POLL_SEC=1 DQ_TRAIN_PRECHECK_MIN_FREE_GB=0 DQ_TRAIN_PRECHECK_IDLE_ROUNDS=1 DQ_BATCH_PARALLEL_MIN_FREE_GB=0
	export DQ_TRAIN_PRECHECK_WAIT_MIN=999 DQ_TRAIN_PRECHECK_WAIT_SEC=0
}

if want enqueue; then
# ---- enqueue refuses a dirty tree and a heavy --light lane -------------------------------------------------------------------------
mk lane/guard lanes/guard.txt fine
mkdir -p code; echo x >code/a.dm; git add -A; git commit -q -m "touches code"
out="$(train enqueue --light 2>&1)"; rc=$?
check "enqueue --light refuses a heavy path" '[ "$rc" != 0 ] && grep -q "may not touch" <<<"$out"'
echo dirty >lanes/dirty.txt
out="$(train enqueue --tests t1 2>&1)"; rc=$?
check "enqueue refuses a dirty tree" '[ "$rc" != 0 ] && grep -q "not clean" <<<"$out"'
rm -f lanes/dirty.txt; back
fi

if want light; then
# ---- a light lane lands through the light path -------------------------------------------------------------------------------------
mk lane/doc docs/new.txt "a doc"; train enqueue --light >/dev/null 2>&1; back
out="$(train run 2>&1)"; rc=$?
check "a light lane is queued, lands, and leaves the queue empty" '[ "$rc" = 0 ] && in_master lane/doc && grep -q "LANDED lane/doc" <<<"$out" && status_has "  (empty)"'
fi

if want heavy; then
# ---- a heavy batch: good, bad, a lane that moves after enqueue, two lanes that conflict ----------------------------------------------
mk lane/a lanes/a.txt fine; train enqueue --tests "ta1 ta2" >/dev/null 2>&1; back
mk lane/b lanes/b.txt BAD; train enqueue --tests "tb1" >/dev/null 2>&1; back
mk lane/d lanes/d.txt fine; train enqueue --tests td >/dev/null 2>&1
echo more >lanes/d2.txt; git add -A; git commit -q -m "d moved"; back
mk lane/e lanes/e.txt fine "shared-e"; train enqueue --tests te >/dev/null 2>&1; back
mk lane/f lanes/f.txt fine "shared-f"; train enqueue --tests tf >/dev/null 2>&1; back
out="$(train run 2>&1)"
check "the good lane lands; the bad lane is bounced alone with a non-empty reason in its report" 'in_master lane/a && ! in_master lane/b && grep -q "BOUNCED lane/b" <<<"$out" && ! grep -q "BOUNCED lane/a" <<<"$out" && grep -q "^- why: ." "$DQ_TRAIN_STATE/reports/lane_b.md" && status_has "lane/b: " && train report lane/b | grep -q "lane/b"'
check "the gate gets only the tests of the lanes it merged" 'grep -h "stub gates: ok" "$DQ_TRAIN_STATE"/log/cycle-*.log | grep "tests: " | grep -q "ta1 ta2" && ! grep -h "stub gates: ok" "$DQ_TRAIN_STATE"/log/cycle-*.log | grep -q "tb1"'
check "a lane that moved after enqueue keeps its place: the new tip is adopted and lands" 'grep -q "adopted the new tip of lane/d" <<<"$out" && in_master lane/d'
check "of two conflicting lanes one lands and one is bounced" '{ in_master lane/e && ! in_master lane/f && grep -q "BOUNCED lane/f" <<<"$out"; } || { in_master lane/f && ! in_master lane/e && grep -q "BOUNCED lane/e" <<<"$out"; }'
check "the integrator released its lock" '[ ! -d "$DQ_TRAIN_STATE/run.lock" ]'
fi

if want push; then
# ---- a refused push keeps the lane queued and bounces nobody; a non-"master moved" refusal bounces after 2 attempts --------------------
mk lane/l lanes/l.txt fine; train enqueue --tests tl >/dev/null 2>&1; back
out="$(DQ_STUB_PUSH_FAIL=1 DQ_TRAIN_STALL_CYCLES=2 DQ_TRAIN_STALL_EXIT_AFTER=2 train run 2>&1)"; rc=$?
check "a push refused because master moved leaves the lane queued, not bounced" '[ "$rc" = 1 ] && grep -q "push FAILED" <<<"$out" && grep -q "STALLED" <<<"$out" && status_has "lane/l  tip" && ! grep -q "BOUNCED lane/l" <<<"$out"'
out="$(train run 2>&1)"
check "the next integrator lands it" 'in_master lane/l'
mk lane/sp lanes/sp.txt fine; train enqueue --tests tsp >/dev/null 2>&1; back
for _ in 1 2; do out="$(DQ_STUB_PUSH_FAIL=1 DQ_STUB_PUSH_MSG="the test stamp is missing on this HEAD" DQ_TRAIN_STALL_CYCLES=5 DQ_TRAIN_ONCE=1 train run 2>&1)"; done
check "a second non-master-moved refusal bounces the lane with the refusal line as the reason" 'grep -q "BOUNCED lane/sp" <<<"$out" && grep -q "test stamp is missing" "$DQ_TRAIN_STATE/reports/lane_sp.md"'
fi

if want precheck; then
# ---- prechecks: good lanes pass, a failing lane is bounced alone with a reason, a conflict is caught by the probe; a re-enqueue is fresh ---
pre_on
mk lane/pa lanes/pa/f.txt fine; train enqueue --tests "tpa" >/dev/null 2>&1; back
mk lane/pb lanes/pb/f.txt BAD; train enqueue --tests "tpb" >/dev/null 2>&1; back
mk lane/pk lanes/pk/f.txt fine "shared-pk"; train enqueue --tests "tpk" >/dev/null 2>&1; back
git fetch -q origin; git switch -q --detach origin/master; echo "master-moves-shared" >shared.txt; git add -A; git commit -q -m "master changes shared"; git push -q origin HEAD:refs/heads/master; back
out="$(DQ_TRAIN_ONCE=1 train run 2>&1)"
check "a lane without a precheck verdict waits: no batch is gated" 'grep -q "waiting for prechecks" <<<"$out" && ! in_master lane/pa'
out="$(train precheck-run 2>&1)"
check "the prechecker passes a good lane, bounces a failing one with a reason, and catches a conflict without a gate run" 'grep -q "PRECHECK pass: lane/pa " <<<"$out" && grep -q "BOUNCED lane/pb: precheck: ." <<<"$out" && grep -q "PRECHECK conflict: lane/pk " <<<"$out"'
git switch -q lane/pb; train enqueue --tests "tpb" >/dev/null 2>&1; back
check "enqueueing a bounced tip again asks for a fresh precheck" 'status_has "lane/pb  tip.*precheck: none" && [ -z "$(ls "$DQ_TRAIN_STATE/precheck/v" | grep "^lane_pb@")" ]'
train dequeue lane/pb >/dev/null 2>&1; train dequeue lane/pk >/dev/null 2>&1
out="$(DQ_TRAIN_ONCE=1 train run 2>&1)"
check "the prechecked lane lands" 'in_master lane/pa'
export DQ_TRAIN_PRECHECK=0
fi

if want dc; then
# ---- the DreamChecker batch: one run for several lanes; a fail is pinned on its lane with a reason; a re-enqueued tip is judged afresh ----
pre_on
export DQ_STUB_DCRUN_LOG="$tmp/dcrun.log" DQ_STUB_DEFER_LOG="$tmp/defer.log"; : >"$DQ_STUB_DCRUN_LOG"; : >"$DQ_STUB_DEFER_LOG"
mk lane/da lanes/da/f.txt fine; train enqueue --tests "tda" >/dev/null 2>&1; back
mk lane/db lanes/db/f.txt DCFAIL; train enqueue --tests "tdb" >/dev/null 2>&1; back
mk lane/dc lanes/dc/f.txt fine; train enqueue --tests "tdc" >/dev/null 2>&1; back
out="$(train precheck-run 2>&1)"
check "prechecks defer DreamChecker and one run covers the lanes" 'grep -q "^defer=1" "$DQ_STUB_DEFER_LOG" && grep -q -- "--lanes lane/da lane/db lane/dc" "$DQ_STUB_DCRUN_LOG"'
check "a DreamChecker failure is pinned on its lane: bounced with a DreamChecker reason; the others pass" 'grep -q "BOUNCED lane/db: precheck: DreamChecker" <<<"$out" && grep -q "PRECHECK pass: lane/da " <<<"$out" && grep -q "PRECHECK pass: lane/dc " <<<"$out"'
check "the bounce report carries the DreamChecker reason (never an empty one)" 'grep -q "^- why: precheck: DreamChecker: ." "$DQ_TRAIN_STATE/reports/lane_db.md"'
runs0="$(grep -c -- "--lanes lane/db" "$DQ_STUB_DCRUN_LOG")"
git switch -q lane/db; train enqueue --tests "tdb" >/dev/null 2>&1; back
out2="$(train precheck-run 2>&1)"
check "the same tip enqueued again gets a fresh DreamChecker run, not a bounce on the stale verdict, and still names the reason" '[ "$(grep -c -- "--lanes lane/db" "$DQ_STUB_DCRUN_LOG")" -gt "$runs0" ] && grep -q "BOUNCED lane/db: precheck: DreamChecker" <<<"$out2"'
out="$(DQ_TRAIN_ONCE=1 train run 2>&1)"
check "the DreamChecker-batched lanes land; the culprit does not" 'in_master lane/da && in_master lane/dc && ! in_master lane/db'
unset DQ_STUB_DCRUN_LOG DQ_STUB_DEFER_LOG
export DQ_TRAIN_PRECHECK=0
fi

if want bisect; then
# ---- a prechecked batch where two lanes fail only together: the bisect isolates the culprit in one cycle, the rest land ----------------
pre_on
rm -f "$DQ_TRAIN_STATE/batch_limit" "$DQ_TRAIN_STATE/batch_limit_pre" "$DQ_TRAIN_STATE/bisect.lanes" "$DQ_TRAIN_STATE/bisect.cache"
for n in 1 2 3 4 5; do
	c=fine; [ "$n" = 2 ] && c=PAIR1; [ "$n" = 4 ] && c=PAIR2
	mk "lane/q$n" "lanes/q$n/f.txt" "$c"; train enqueue --tests "tq$n" >/dev/null 2>&1; back
done
train precheck-run >/dev/null 2>&1
out="$(DQ_TRAIN_CYCLE_MAX_MIN=0 DQ_TRAIN_ONCE=1 train run 2>&1)"
check "the interacting lane is bounced and the other four land in one cycle" 'grep -q "BOUNCED lane/q4" <<<"$out" && ! grep -q "bisect unfinished" <<<"$out" && for n in 1 2 3 5; do in_master "lane/q$n" || exit 1; done && ! in_master lane/q4'
export DQ_TRAIN_PRECHECK=0
fi

if want lock; then
# ---- the lock is exclusive: a live holder is respected, a dead one replaced, eight racers yield one winner -------------------------------
"$real_sleep" 60 & holder=$!
mkdir -p "$DQ_TRAIN_STATE/run.lock"
printf 'pid=%s\nwinpid=\nsince=now\n' "$holder" >"$DQ_TRAIN_STATE/run.lock/owner"
mk lane/m lanes/m.txt fine; train enqueue --tests tm >/dev/null 2>&1; back
out="$(train run 2>&1)"; rc=$?
check "a second integrator refuses to run beside a live one" '[ "$rc" = 0 ] && grep -q "already running" <<<"$out" && ! in_master lane/m && status_has "integrator: RUNNING pid $holder"'
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
out="$(train run 2>&1)"
check "a dead integrator's lock is replaced and the lane lands" 'grep -q "replacing the lock of a dead integrator" <<<"$out" && in_master lane/m'
lk="$tmp/lockrace"; mkdir -p "$lk/log"
sed -n '/^alive() {/,/^}/p;/^now() {/p;/^tlog() {/p;/^lockdir_pid() {/p;/^lockdir_alive() {/p;/^lock_take() {/,/^}/p;/^lock_owned() {/p' tools/dq_train.sh >"$lk/fns.sh"
for i in 1 2 3 4 5 6 7 8; do
	STATE="$lk" LOGS="$lk/log" LOCK_NAME=run.lock SELF=x bash -c '. "$1"; if lock_take; then echo "$$" >>"$2/winners"; "$3" 2; fi' _ "$lk/fns.sh" "$lk" "$real_sleep" &
done
wait
check "eight integrators racing for the lock: exactly one takes it" '[ "$(wc -l <"$lk/winners")" = 1 ]'
fi

if want selfupdate; then
# ---- the integrator updates itself from master; a master whose dq_train.sh does not parse is refused and the old copy keeps running ----
snapfiles="$(sed -n 's/^SNAP_FILES=(\(.*\))$/\1/p' tools/dq_train.sh)"
git fetch -q origin; git switch -q --detach origin/master
su="$tmp/su-state"; mkdir -p "$su/self/ci" "$su/self/train"
for f in $snapfiles; do cp -f "tools/$f" "$su/self/$f"; done
export DQ_TRAIN_ORIGIN_REPO="$tmp/repo"
suenq() { mk "$1" "lanes/$2.txt" fine; DQ_TRAIN_STATE="$su" train enqueue --light >/dev/null 2>&1; back; }
sumaster() { git fetch -q origin; git switch -q --detach origin/master; sed -i "$2" "tools/$1"; git add -A; git commit -q -m "master changes $1"; git push -q origin HEAD:refs/heads/master; }
suenq lane/su1 su1
sumaster dq_train.sh '/^	trap .lock_release; phase "idle". EXIT$/a\
	tlog "v2 marker: the new dq_train.sh runs"'
out="$(DQ_TRAIN_STATE="$su" DQ_TRAIN_ONCE=1 bash "$su/self/dq_train.sh" run 2>&1)"; rc=$?
check "a changed snapshot script is re-exec'd (the new code runs) and the queued lane lands" '[ "$rc" = 0 ] && grep -q "changed on master; re-exec" <<<"$out" && grep -q "v2 marker" <<<"$out" && in_master lane/su1'
suenq lane/su2 su2
sumaster dq_train.sh '$aif then echo "unterminated'
cp -f "$su/self/dq_train.sh" "$tmp/su-before.sh"
out="$(DQ_TRAIN_STATE="$su" DQ_TRAIN_ONCE=1 bash "$su/self/dq_train.sh" run 2>&1)"; rc=$?
check "an unparsable master dq_train.sh is refused loudly; the old copy keeps running and lands the lane" '[ "$rc" = 0 ] && grep -q "SELF-UPDATE REFUSED" <<<"$out" && cmp -s "$tmp/su-before.sh" "$su/self/dq_train.sh" && in_master lane/su2'
fi

if want stamp; then
# ---- the gates' unstamped-lane refusal: a --no-tests batch (the train's DreamChecker run) passes; a test run is refused without naming the retired script ----
blk="$(sed -n '/^	if \[ \${#unstamped\[@\]} -gt 0 \]/,/^	fi$/p' "$here/tools/dq_merge_gates.sh")"
check "the refusal block was found in the gates script" '[ -n "$blk" ]'
r0="$(bash -c 'unstamped=(lane/x); tests_arg=(); run_tests=0; '"$blk"'; echo REACHED' 2>&1)"
r1="$(bash -c 'unstamped=(lane/x); tests_arg=(); run_tests=1; '"$blk"'; echo REACHED' 2>&1)"
r2="$(bash -c 'unstamped=(lane/x); tests_arg=(t1); run_tests=1; '"$blk"'; echo REACHED' 2>&1)"
check "--no-tests passes an unstamped lane" 'grep -q REACHED <<<"$r0" && ! grep -q REFUSED <<<"$r0"'
check "a test run refuses an unstamped lane with no test list, and the message does not name dq_lane_ready.sh" '! grep -q REACHED <<<"$r1" && grep -q REFUSED <<<"$r1" && ! grep -q dq_lane_ready <<<"$r1"'
check "naming the lane's tests passes it" 'grep -q REACHED <<<"$r2"'
fi

echo "elapsed: $(( $(date +%s) - t_start )) s"
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
