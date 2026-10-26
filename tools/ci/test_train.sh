#!/usr/bin/env bash
# Self-test of tools/dq_train.sh (the batch train) in a scratch repository: the real dq_train.sh, dq_train_estimate.js and
# dq_merge_batch.sh run against stub gates / stub push / stub light batch, so no compiler, test world or master is touched.
# Cases: light lane lands through the light path; a heavy batch lands the good lanes and bounces the bad one with a report; a lane whose
# branch moved after enqueue is bounced; a conflicting lane is bounced; a capped test phase halves the batch and every lane still lands;
# a refused push keeps the lanes queued (nobody is bounced); the lock refuses a second live integrator and replaces a dead one; enqueue
# refuses a dirty tree and a heavy --light lane; dequeue; the estimator; the gate's fixed test cap and its no-retry-on-cap rule; the batch
# driver's deadline (deferral) and its cap handling.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
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

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
cd "$tmp/repo"
git config user.email t@t; git config user.name t
mkdir -p tools/ci lanes docs
cp "$here/tools/dq_train.sh" "$here/tools/dq_train_estimate.js" "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_proof_cache.sh" "$here/tools/dq_light_paths.sh" "$here/tools/dq_gate_retry.sh" "$here/tools/dq_declared_tests.sh" tools/
echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
printf '#!/usr/bin/env bash\nexit 0\n' >tools/dq_disk_budget.sh  # stub: the integrator runs the disk gate from its SELF_DIR
echo '# manifest' >tools/ci/disk_budget.toml
cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
# stub gates: BAD in a lane file fails; with DQ_STUB_CAP_ABOVE=N a batch of more than N lane files looks like a killed test phase
if grep -rq BAD lanes 2>/dev/null; then echo "stub gates: BAD present"; exit 1; fi
n="$(git diff --name-only origin/master HEAD -- lanes | wc -l)"
if [ -n "${DQ_STUB_CAP_ABOVE:-}" ] && [ "$n" -gt "$DQ_STUB_CAP_ABOVE" ]; then echo "FOCUSED RUN CAPPED: the 10 minute wall-clock cap was hit"; exit 1; fi
echo "$*" >>"${DQ_STUB_ARGS_LOG:-/dev/null}"
echo "dc=${DQ_GATE_DREAMCHECKER:-}" >>"${DQ_STUB_DC_LOG:-/dev/null}"
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
	echo "$3" >"$2"
	[ -z "${4:-}" ] || echo "$4" >shared.txt
	git add -A; git commit -q -m "$1"
}
back() { git switch -q --detach origin/master; }
train() { bash tools/dq_train.sh "$@"; }
in_master() { git fetch -q origin; git merge-base --is-ancestor "$1" origin/master; }
status_has() { local o; o="$(train status 2>&1)"; grep -q -- "$1" <<<"$o"; } # not `status | grep -q`: grep exits early and pipefail fails the pipe

# ---- enqueue guards -------------------------------------------------------------------------------------------------------------
mk lane/heavy-light lanes/hl.txt fine
out="$(train enqueue --light 2>&1)"; rc=$?
check "enqueue --light accepts a lane that touches no heavy path" '[ "$rc" = 0 ]'  # lanes/ is not a heavy path
mkdir -p code; echo x >code/a.dm; git add -A; git commit -q -m "touches code"
out="$(train enqueue --light 2>&1)"; rc=$?
check "enqueue --light refuses a heavy path" '[ "$rc" != 0 ] && grep -q "may not touch" <<<"$out"'
echo dirty >lanes/dirty.txt
out="$(train enqueue --tests t1 2>&1)"; rc=$?
check "enqueue refuses a dirty tree" '[ "$rc" != 0 ] && grep -q "not clean" <<<"$out"'
rm -f lanes/dirty.txt
train dequeue lane/heavy-light >/dev/null
back

# ---- a light lane lands through the light path ---------------------------------------------------------------------------------------
mk lane/doc docs/new.txt "a doc"
train enqueue --light >/dev/null 2>&1
check "an enqueued lane is listed in the queue" 'status_has "lane/doc"'
back
out="$(train run 2>&1)"; rc=$?
check "the integrator lands a light lane" '[ "$rc" = 0 ] && in_master lane/doc && grep -q "LANDED lane/doc" <<<"$out"'
check "status lists it as landed and the queue is empty" 'status_has "landed (latest" && status_has "  (empty)" && ! status_has "tests: "'

# ---- enqueue validates --tests names against the tree being enqueued ------------------------------------------------------------
git fetch -q origin; git switch -q -c lane/names origin/master
mkdir -p code/modules/unit_tests
cat >code/modules/unit_tests/names.dm <<'DM'
/datum/unit_test/solo_leaf/Run()
	return

/datum/unit_test/parent_only
/datum/unit_test/parent_only/kid_one/Run()
	return
/datum/unit_test/parent_only/kid_two/Run()
	return
DM
git add -A; git commit -q -m names
out="$(train enqueue --tests "solo_leaf" 2>&1)"; rc=$?
check "enqueue accepts a declared runnable leaf" '[ "$rc" = 0 ] && grep -q "is queued" <<<"$out"'
out="$(train enqueue --tests "solo_leef" 2>&1)"; rc=$?
check "enqueue refuses an unknown test and lists the nearest" '[ "$rc" != 0 ] && grep -q "not declared" <<<"$out" && grep -q "unit_test/solo_leaf" <<<"$out"'
out="$(train enqueue --tests "parent_only" 2>&1)"; rc=$?
check "enqueue refuses an abstract parent and lists its subtests" '[ "$rc" != 0 ] && grep -q "abstract parent" <<<"$out" && grep -q "parent_only/kid_one" <<<"$out" && grep -q "parent_only/kid_two" <<<"$out"'
out="$(train enqueue --tests "parent_only/kid_one /datum/unit_test/solo_leaf" 2>&1)"; rc=$?
check "enqueue accepts leaf names given as paths or under a parent" '[ "$rc" = 0 ]'
train dequeue lane/names >/dev/null 2>&1 || rm -f "$DQ_TRAIN_STATE"/queue/lane_names.q 2>/dev/null
back

# ---- a heavy batch: good, bad, good, a lane that moves after enqueue, two lanes that conflict -----------------------------------------
mk lane/a lanes/a.txt fine; train enqueue --tests "ta1 ta2" >/dev/null 2>&1; back
mk lane/b lanes/b.txt BAD; train enqueue --tests "tb1" >/dev/null 2>&1; back
mk lane/c lanes/c.txt fine; train enqueue --tests "tc1" >/dev/null 2>&1; back
mk lane/d lanes/d.txt fine; train enqueue --tests td >/dev/null 2>&1
echo more >lanes/d2.txt; git add -A; git commit -q -m "d moved"; back
mk lane/e lanes/e.txt fine "shared-e"; train enqueue --tests te >/dev/null 2>&1; back
mk lane/f lanes/f.txt fine "shared-f"; train enqueue --tests tf >/dev/null 2>&1; back
out="$(train run 2>&1)"; rc=$?
check "a heavy batch lands the good lanes" 'in_master lane/a && in_master lane/c'
check "the bad lane is not landed and is bounced alone" '! in_master lane/b && grep -q "BOUNCED lane/b" <<<"$out" && ! grep -q "BOUNCED lane/a" <<<"$out" && ! grep -q "BOUNCED lane/c" <<<"$out"'
check "the bounce has a readable report with the reason and the next step" '[ -f "$DQ_TRAIN_STATE/reports/lane_b.md" ] && grep -q "was bounced" "$DQ_TRAIN_STATE/reports/lane_b.md" && grep -q "enqueue" "$DQ_TRAIN_STATE/reports/lane_b.md" && grep -q "BAD present" "$DQ_TRAIN_STATE/reports/lane_b.md"'
check "status shows the bounced lane with its report" 'status_has "lane/b: " && status_has "report: "'
check "the report command prints it" 'train report lane/b | grep -q "lane/b"'
check "the gate gets only the tests of the lanes it merged (the bounced lane's tests are dropped)" 'grep -h "stub gates: ok" "$DQ_TRAIN_STATE"/log/cycle-*.log | grep "tests: " | grep -q "ta1 ta2 tc1" && ! grep -h "stub gates: ok" "$DQ_TRAIN_STATE"/log/cycle-*.log | grep -q "tb1"'
check "the decisions are logged" 'grep -q "heavy cycle: 5 lane" "$DQ_TRAIN_STATE/log/train.log" && grep -q "merge_batch rc=1 good=" "$DQ_TRAIN_STATE/log/train.log"'
check "a lane whose branch moved after enqueue is bounced" 'grep -q "BOUNCED lane/d: the branch moved" <<<"$out" && ! in_master lane/d'
check "of two conflicting lanes one lands and one is bounced" '{ in_master lane/e && ! in_master lane/f && grep -q "BOUNCED lane/f" <<<"$out"; } || { in_master lane/f && ! in_master lane/e && grep -q "BOUNCED lane/e" <<<"$out"; }'
check "the integrator released its lock" '[ ! -d "$DQ_TRAIN_STATE/run.lock" ]'

# ---- heavy cycles skip the duplicate production compile ----------------------------------------------------------------------------------
export DQ_STUB_ARGS_LOG="$tmp/gate-args.log"; : >"$DQ_STUB_ARGS_LOG"
export DQ_STUB_DC_LOG="$tmp/gate-dc.log"; : >"$DQ_STUB_DC_LOG"
export DQ_TRAIN_STALL_BACKOFF_SEC=0

# ---- a capped test phase halves the batch; every lane still lands ----------------------------------------------------------------------
mk lane/g lanes/g.txt fine; train enqueue --tests tg >/dev/null 2>&1; back
mk lane/h lanes/h.txt fine; train enqueue --tests th >/dev/null 2>&1; back
mk lane/i lanes/i.txt fine; train enqueue --tests ti >/dev/null 2>&1; back
rm -f "$DQ_TRAIN_STATE/batch_limit"
# the stub calls a batch of more than one lane file a killed test phase
out="$(DQ_STUB_CAP_ABOVE=1 train run 2>&1)"
check "a capped test phase halves the batch limit" 'grep -q "hit its 10 min cap with 3 lane" <<<"$out"'
check "and every lane lands in later, smaller cycles" 'in_master lane/g && in_master lane/h && in_master lane/i && ! grep -q "BOUNCED lane/[ghi]" <<<"$out"'
check "every heavy cycle passes --no-dm to the gates (no duplicate compile)" '[ -s "$DQ_STUB_ARGS_LOG" ] && ! grep -qv -- "--no-dm" "$DQ_STUB_ARGS_LOG"'

# ---- the size budget defers a lane to the next cycle ------------------------------------------------------------------------------------
rm -f "$DQ_TRAIN_STATE/batch_limit"
mk lane/j lanes/j.txt fine; train enqueue --tests "tj1 tj2" >/dev/null 2>&1; back
mk lane/k lanes/k.txt fine; train enqueue --tests "tk1 tk2" >/dev/null 2>&1; back
out="$(DQ_TRAIN_TEST_BUDGET_SEC=80 train run 2>&1)"
check "a lane that would push the test estimate over the budget waits for the next cycle" 'grep -q "deferred lane/k to a later cycle" <<<"$out" && in_master lane/j && in_master lane/k'

# ---- a refused push keeps the lanes queued, bounces nobody -------------------------------------------------------------------------------
mk lane/l lanes/l.txt fine; train enqueue --tests tl >/dev/null 2>&1; back
out="$(DQ_STUB_PUSH_FAIL=1 DQ_TRAIN_STALL_CYCLES=2 DQ_TRAIN_STALL_EXIT_AFTER=2 train run 2>&1)"; rc=$?
check "a push refused because master moved leaves the lane queued and not bounced" '[ "$rc" = 1 ] && grep -q "push FAILED" <<<"$out" && grep -q "STALLED" <<<"$out" && status_has "lane/l  tip" && ! grep -q "BOUNCED lane/l" <<<"$out"'
check "a stall backs off and the integrator keeps running (it only stops at the test hook's second stall)" '[ "$(grep -c "STALLED" <<<"$out")" = 2 ] && grep -q "keeps running" <<<"$out"'
out="$(train run 2>&1)"
check "the next integrator lands it" 'in_master lane/l'
check "every heavy gate ran with DQ_GATE_DREAMCHECKER=1 (DreamChecker is a gate job)" '[ -s "$DQ_STUB_DC_LOG" ] && ! grep -qv "dc=1" "$DQ_STUB_DC_LOG"'

# ---- a refusal that is not "master moved" bounces the lane after 2 attempts, with the refusal line as the reason --------------------------
mk lane/stallpush lanes/stallpush.txt fine; train enqueue --tests tsp >/dev/null 2>&1; back
out="$(DQ_STUB_PUSH_FAIL=1 DQ_STUB_PUSH_MSG="the test stamp is missing on this HEAD" DQ_TRAIN_STALL_CYCLES=5 DQ_TRAIN_ONCE=1 train run 2>&1)"
check "the first non-master-moved refusal keeps the lane queued" 'grep -q "push refusal 1 of 2 for lane/stallpush" <<<"$out" && status_has "lane/stallpush  tip" && ! grep -q "BOUNCED lane/stallpush" <<<"$out"'
out="$(DQ_STUB_PUSH_FAIL=1 DQ_STUB_PUSH_MSG="the test stamp is missing on this HEAD" DQ_TRAIN_STALL_CYCLES=5 DQ_TRAIN_ONCE=1 train run 2>&1)"
check "the second one bounces it with the refusal line as the reason" 'grep -q "BOUNCED lane/stallpush" <<<"$out" && grep -q "test stamp is missing" "$DQ_TRAIN_STATE/reports/lane_stallpush.md" && ! status_has "lane/stallpush  tip"'

# ---- the watchdog: ensure is a no-op with an empty queue ---------------------------------------------------------------------------------
out="$(train ensure 2>&1)"; rc=$?
check "ensure with nothing queued starts nothing" '[ "$rc" = 0 ] && ! status_has "integrator: RUNNING"'
check "dq_lane_pool.sh calls the train's ensure after lease and release" 'grep -q "train_watchdog; exit" "$here/tools/dq_lane_pool.sh" && grep -q "dq_train.sh\" ensure" "$here/tools/dq_lane_pool.sh"'
check "the push trusts the gate's DreamChecker only with the gate's stamp on the exact HEAD" 'grep -q "stamped ratchets && stamped dreamchecker && gate_sha_ok" "$here/tools/dq_push_master.sh"'
check "the gates run a dreamchecker job in --no-dm mode and fail on its verdict" 'grep -q "names+=(dreamchecker)" "$here/tools/dq_merge_gates.sh" && grep -q "failed+=(dreamchecker)" "$here/tools/dq_merge_gates.sh" && grep -q "dreamchecker.ok" "$here/tools/dq_merge_gates.sh"'

# ---- the lock ----------------------------------------------------------------------------------------------------------------------------
sleep 60 & holder=$!
mkdir -p "$DQ_TRAIN_STATE/run.lock"
printf 'pid=%s\nwinpid=\nsince=now\n' "$holder" >"$DQ_TRAIN_STATE/run.lock/owner"
mk lane/m lanes/m.txt fine; train enqueue --tests tm >/dev/null 2>&1; back
out="$(train run 2>&1)"; rc=$?
check "a second integrator refuses to run beside a live one" '[ "$rc" = 0 ] && grep -q "already running" <<<"$out" && ! in_master lane/m'
check "status names the running integrator" 'status_has "integrator: RUNNING pid $holder"'
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
out="$(train run 2>&1)"
check "a dead integrator's lock is replaced" 'grep -q "replacing the lock of a dead integrator" <<<"$out" && in_master lane/m'

# ---- a bisect spans cycles: one attempt per cycle, the bad lane is bounced, the rest land, a newcomer waits --------------------------------
rm -f "$DQ_TRAIN_STATE/batch_limit" "$DQ_TRAIN_STATE/bisect.lanes" "$DQ_TRAIN_STATE/bisect.cache"
for n in 1 2 3 4 5 6; do
	if [ "$n" = 4 ]; then mk "lane/bs$n" "lanes/bs$n.txt" BAD; else mk "lane/bs$n" "lanes/bs$n.txt" fine; fi
	train enqueue --tests "tbs$n" >/dev/null 2>&1; back
done
bsout=""; late=0
for c in 1 2 3 4 5 6 7 8 9 10 11 12; do
	o="$(DQ_TRAIN_CYCLE_MAX_MIN=0 DQ_TRAIN_ONCE=1 train run 2>&1)"; bsout="$bsout$o"
	if [ "$c" = 1 ]; then mk lane/bslate lanes/bslate.txt fine; train enqueue --tests tbsl >/dev/null 2>&1; back; fi
	status_has "lane/bs4  tip" || [ -n "$(ls "$DQ_TRAIN_STATE"/bounced 2>/dev/null | grep bs4)" ] && [ ! -s "$DQ_TRAIN_STATE/bisect.lanes" ] && break
done
check "an unfinished bisect is recorded and resumed, not restarted" 'grep -q "bisect unfinished" <<<"$bsout" && grep -q "resuming the bisect" "$DQ_TRAIN_STATE"/log/cycle-*.log'
check "the bad lane is bounced, never deferred forever" 'grep -q "BOUNCED lane/bs4" <<<"$bsout" || grep -q "bounced lane/bs4\|lane/bs4" "$DQ_TRAIN_STATE/log/train.log"; ! in_master lane/bs4'
check "the other five land" 'for n in 1 2 3 5 6; do in_master "lane/bs$n" || exit 1; done'
check "a lane enqueued during the bisect waited for it" 'grep -q "the other queued lanes wait" "$DQ_TRAIN_STATE/log/train.log"'
check "a failed batch halves the next one" 'grep -q "failed (bounced" "$DQ_TRAIN_STATE/log/train.log"'
train run >/dev/null 2>&1

# ---- dry run -----------------------------------------------------------------------------------------------------------------------------
mk lane/n lanes/n.txt fine; train enqueue --tests tn >/dev/null 2>&1; back
out="$(DQ_TRAIN_DRY_RUN=1 DQ_TRAIN_ONCE=1 train run 2>&1)"
check "a dry run passes the gate but pushes nothing and keeps the lane queued" 'grep -q "DRY RUN" <<<"$out" && ! in_master lane/n && status_has "lane/n  tip"'
train dequeue lane/n >/dev/null
check "dequeue withdraws a lane" '! status_has "lane/n  tip"'

# ---- the estimator -----------------------------------------------------------------------------------------------------------------------
mkdir -p "$tmp/runs"
echo '{"tests":{"/datum/unit_test/aa":{"duration_ds":100},"/datum/unit_test/gp/x":{"duration_ds":50},"/datum/unit_test/gp/y":{"duration_ds":30}}}' >"$tmp/runs/1.json"
echo '{"tests":{"/datum/unit_test/aa":{"duration_ds":300}}}' >"$tmp/runs/2.json"
est="$(node tools/dq_train_estimate.js --runs "$tmp/runs" --base 10 --unknown 7 aa 'gp/*' zz)"
check "the estimator sums mean per-test times, a prefix glob and the unknown default" '[ "$est" = 45 ]'   # base 10 + aa mean(10,30)=20 + gp/* (5+3)=8 + zz unknown 7

# ---- the gate: a fixed test cap, and no retry of a run killed at the cap ---------------------------------------------------------------
. tools/dq_gate_retry.sh
check "the gate's test cap never exceeds 10 minutes" '[ "$(gate_cap_minutes 50)" = 10 ] && [ "$(gate_cap_minutes 2)" -le 10 ]'
cat >"$tmp/focused_cap.sh" <<'STUB'
#!/usr/bin/env bash
echo run >>"$DQ_STUB_COUNT"
echo "FOCUSED RUN CAPPED: the 10 minute wall-clock cap was hit; the run's worlds were killed"
exit 1
STUB
: >"$tmp/count"
DQ_STUB_COUNT="$tmp/count" DQ_FOCUSED_TEST_CMD="bash $tmp/focused_cap.sh" gate_tests_with_retry t1 t2 >/dev/null 2>&1; rc=$?
check "a run killed at the cap fails once, with no retry" '[ "$rc" = 1 ] && [ "$(wc -l <"$tmp/count")" = 1 ]'

# ---- the batch driver: deadline and cap -----------------------------------------------------------------------------------------------
git fetch -q origin; git switch -q --detach origin/master
git switch -q -c lane/p origin/master; echo ok >lanes/p.txt; git add -A; git commit -q -m p; git switch -q --detach origin/master
git switch -q -c lane/q origin/master; echo ok >lanes/q.txt; git add -A; git commit -q -m q; git switch -q --detach origin/master
git switch -q -c lane/pd origin/master; echo ok >lanes/pd.txt; git add -A; git commit -q -m pd; git switch -q --detach origin/master
git switch -q -c lane/rd origin/master; echo ok >lanes/rd.txt; git add -A; git commit -q -m rd; git switch -q --detach origin/master
git switch -q -c lane/qd origin/master; echo BAD >lanes/qd.txt; git add -A; git commit -q -m qd; git switch -q --detach origin/master
out="$(DQ_BATCH_DEADLINE=1 bash tools/dq_merge_batch.sh --lanes "lane/pd,lane/rd,lane/qd" 2>&1)"
check "past the deadline only the first attempt runs; the rest of the bisect is deferred, not bounced" 'grep -q "^BATCH_DEFERRED: lane/pd lane/rd lane/qd" <<<"$out" && grep -q "^BATCH_GOOD: $" <<<"$out" && ! grep -q "^BATCH_BOUNCED" <<<"$out"'
out="$(DQ_STUB_CAP_ABOVE=1 bash tools/dq_merge_batch.sh --lanes "lane/p,lane/q" 2>&1)"
check "a capped attempt on two lanes defers them and reports the batch capped" 'grep -q "^BATCH_CAPPED: 1" <<<"$out" && grep -q "^BATCH_DEFERRED: lane/p lane/q" <<<"$out" && ! grep -q "^BATCH_BOUNCED" <<<"$out"'
out="$(DQ_STUB_CAP_ABOVE=0 bash tools/dq_merge_batch.sh --lanes "lane/p" 2>&1)"
check "a lane capped alone is bounced with the attempt log named" 'grep -q "^BATCH_BOUNCED: lane/p|its tests do not fit" <<<"$out" && grep -q "^BATCH_BOUNCED: lane/p|.*|data/merge-batch/.*attempt1.log" <<<"$out"'
out="$(bash tools/dq_merge_batch.sh --lanes "lane/p,lane/q" 2>&1)"
check "a clean batch reports its lanes as good" 'grep -q "^BATCH_GOOD: lane/p lane/q" <<<"$out" && grep -q "^BATCH_CAPPED: $" <<<"$out"'

# ---- the integrator updates itself from origin/master between cycles ---------------------------------------------------------------------
# It runs from a snapshot ($STATE/self). Cases: a change to a snapshot script on master re-execs it (same pid, same lock, the new code runs,
# the snapshot equals master's blobs, the queued lane still lands); a master whose dq_train.sh does not parse is refused loudly and the
# old copy keeps running. And every "$SELF_DIR/<file>" the cycle uses is in SNAP_FILES.
snapfiles="$(sed -n 's/^SNAP_FILES=(\(.*\))$/\1/p' tools/dq_train.sh)"
refs="$(sed '/^cmd_enqueue() {/,/^}/d' tools/dq_train.sh | grep -o '\$SELF_DIR/[A-Za-z0-9_][A-Za-z0-9_./-]*' | sed 's|^\$SELF_DIR/||' | sort -u)"
missing=""; for r in $refs; do case " $snapfiles " in *" $r "*) ;; *) missing="$missing $r" ;; esac; done
check "every file the cycle runs from SELF_DIR is in SNAP_FILES (missing:${missing:- none})" '[ -z "$missing" ] && [ -n "$snapfiles" ]'
git fetch -q origin; git switch -q --detach origin/master
su="$tmp/su-state"; mkdir -p "$su/self/ci"
for f in $snapfiles; do cp -f "tools/$f" "$su/self/$f"; done
export DQ_TRAIN_ORIGIN_REPO="$tmp/repo"
sulog() { cat "$su/log/train.log" 2>/dev/null; }
suenq() { mk "$1" "lanes/$2.txt" fine; DQ_TRAIN_STATE="$su" train enqueue --light >/dev/null 2>&1; back; }
sumaster() { # <file> <sed-expr>: a commit on origin/master changing tools/<file>
	git fetch -q origin; git switch -q --detach origin/master
	sed -i "$2" "tools/$1"; git add -A; git commit -q -m "master changes $1"; git push -q origin HEAD:refs/heads/master
}
suenq lane/su1 su1
sumaster dq_train.sh '/^	trap .lock_release; phase "idle". EXIT$/a\
	tlog "v2 marker: the new dq_train.sh runs"'
sumaster dq_train_estimate.js '$a// v2'
want_est="$(git show origin/master:tools/dq_train_estimate.js | git hash-object --stdin)"
out="$(DQ_TRAIN_STATE="$su" DQ_TRAIN_ONCE=1 bash "$su/self/dq_train.sh" run 2>&1)"; rc=$?
check "a changed snapshot script is logged and the integrator re-execs" '[ "$rc" = 0 ] && grep -q "self-update: dq_train.sh dq_train_estimate.js changed on master; re-exec" <<<"$out"'
check "the new dq_train.sh ran after the exec" 'grep -q "v2 marker" <<<"$out"'
check "the snapshot now equals origin/master's copies" '[ "$(git hash-object --no-filters "$su/self/dq_train_estimate.js")" = "$want_est" ] && git show origin/master:tools/dq_train.sh | cmp -s - "$su/self/dq_train.sh"'
pids="$(sed -n 's/.*train\[\([0-9]*\)\]: integrator started (pid .*/\1/p' <<<"$out" | sort -u | wc -l)"
check "the exec keeps the integrator's pid and its lock (no second integrator)" '[ "$pids" = 1 ] && ! grep -q "already running" <<<"$out" && in_master lane/su1 && [ ! -d "$su/run.lock" ]'
suenq lane/su2 su2
sumaster dq_train.sh '$aif then echo "unterminated'
cp -f "$su/self/dq_train.sh" "$tmp/su-before.sh"
out="$(DQ_TRAIN_STATE="$su" DQ_TRAIN_ONCE=1 bash "$su/self/dq_train.sh" run 2>&1)"; rc=$?
check "a master whose dq_train.sh does not parse is refused loudly" 'grep -q "SELF-UPDATE REFUSED" <<<"$out" && ! grep -q "changed on master; re-exec" <<<"$out"'
check "the old copy keeps running, is not replaced, and still lands the lane" '[ "$rc" = 0 ] && cmp -s "$tmp/su-before.sh" "$su/self/dq_train.sh" && in_master lane/su2'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
