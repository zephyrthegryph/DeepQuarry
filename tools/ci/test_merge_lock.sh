#!/usr/bin/env bash
# Shell test for the merge worktree lock (tools/dq_machine_slots.sh merge_lock_*, tools/dq_merge_worktree.sh,
# tools/dq_merge_gates.sh, tools/dq_push_master.sh). Everything runs in a scratch git repo and worktree under this
# checkout's data/ directory with its own slot directory; the live merge-base worktree and slots are never touched.
#
#   bash tools/ci/test_merge_lock.sh
#
# Proves: a second contender waits (and says who holds the lock) until the first releases; the clear check and the merge happen
# inside the lock; gates and push refuse in the merge worktree without the lock; only the holder joins lanes or releases; a failed
# clear check frees the lock; a holder that dies is reclaimed; a push in the merge worktree frees the lock.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d "$ROOT/data/merge-lock-test.XXXXXX" 2>/dev/null || { mkdir -p "$ROOT/data"; mktemp -d "$ROOT/data/merge-lock-test.XXXXXX"; })"
fails=0
cleanup() {
	DQ_SLOTS_DIR="$T/slots" DQ_MERGE_WT="$T/mb" bash "$ROOT/tools/dq_machine_slots.sh" merge-lock release --force >/dev/null 2>&1
	sleep 2
	rm -rf "$T"
}
trap cleanup EXIT

export DQ_SLOTS_DIR="$T/slots" DQ_MERGE_WT="$T/mb" DQ_SLOTS_POLL_SEC=1 DQ_SLOTS_HEARTBEAT_SEC=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset DQ_MERGE_SESSION
export CLAUDE_CODE_SESSION_ID=shared-by-every-lane # must never decide who holds the lock
MW="$ROOT/tools/dq_merge_worktree.sh"
SL="$ROOT/tools/dq_machine_slots.sh"

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
check() { # description command...
	local d="$1"
	shift
	if "$@"; then ok "$d"; else fail "$d"; fi
}

# ---- scratch repo: origin (bare), main clone (where the scripts are run from), mb (the stand-in merge worktree) ----
git init -q --bare -b master "$T/origin.git"
git clone -q "$T/origin.git" "$T/main" 2>/dev/null
(
	cd "$T/main" && git switch -q -c master 2>/dev/null; echo base >f.txt && git add f.txt && git commit -qm base && git push -q origin master
	git branch -q -u origin/master master 2>/dev/null
	git worktree add -q -b rewrite/integ-current "$T/mb" origin/master
) >/dev/null 2>&1
[ -d "$T/mb" ] || { echo "FAIL: scratch repo setup"; exit 1; }
cd "$T/main" || exit 1
git fetch -q origin

run_as() { # session args...: dq_merge_worktree.sh as that session
	local s="$1"
	shift
	DQ_MERGE_SESSION="$s" bash "$MW" "$@"
}

# ---- 0. no explicit session, no lock (and the shared agent session id is no substitute) ----
bash "$MW" --lanes laneX >"$T/n.out" 2>"$T/n.err" && rc=0 || rc=$?
check "a merge call without DQ_MERGE_SESSION is refused" bash -c "[ $rc -ne 0 ] && grep -q 'DQ_MERGE_SESSION is not set' '$T/n.err'"
check "and took no lock" bash -c "bash '$SL' merge-lock status | grep -q nobody"

# ---- 1. A takes the lock; B, started while A holds it, waits ----
out="$(run_as A --lanes "laneA" 2>"$T/a.err")"
check "A took the lock and got the worktree path" test "$out" = "$T/mb"
check "status names A's lanes" bash -c "bash '$SL' merge-lock status | grep -q \"lanes 'laneA'\""
check "slots status shows the merge lock holder" bash -c "bash '$SL' status merge_base | grep -q \"lanes 'laneA'\""
DQ_MERGE_SESSION=B bash "$MW" --lanes "laneB" >"$T/b.out" 2>"$T/b.err" &
bpid=$!
for _ in $(seq 1 60); do grep -q "waiting" "$T/b.err" 2>/dev/null && break; sleep 1; done
sleep 3
check "B is still waiting while A holds the lock" bash -c "kill -0 $bpid 2>/dev/null && [ ! -s '$T/b.out' ]"
check "B printed who holds the lock" grep -q "laneA" "$T/b.err"
check "B has not touched the worktree" test "$(git -C "$T/mb" rev-parse HEAD)" = "$(git -C "$T/main" rev-parse origin/master)"

# A merges its lane inside the lock (the half-applied merge the race used to cause)
echo a >"$T/mb/a.txt"
git -C "$T/mb" add a.txt && git -C "$T/mb" commit -qm "A's batch"
sleep 3
check "B still waits while A has unpushed work in the worktree" bash -c "kill -0 $bpid 2>/dev/null && [ ! -s '$T/b.out' ]"

# ---- 2. unlocked callers are refused; the holder is not ----
check "gates refuse in the merge worktree without the lock (cwd outside is the scratch worktree)" bash -c "cd '$T/mb' && DQ_MERGE_SESSION=B bash '$ROOT/tools/dq_merge_gates.sh' --no-tests 2>&1 | grep -q 'do not hold its lock'"
check "push refuses in the merge worktree without the lock" bash -c "cd '$T/mb' && DQ_MERGE_SESSION=B bash '$ROOT/tools/dq_push_master.sh' 2>&1 | grep -q 'do not hold its lock'"
check "the lock check passes for the holder" bash -c "cd '$T/mb' && . '$SL' && DQ_MERGE_SESSION=A merge_lock_require"
check "the lock check refuses the shared agent session id without DQ_MERGE_SESSION" bash -c "cd '$T/mb' && . '$SL' && ! merge_lock_require 2>/dev/null"
check "the lock check ignores other worktrees" bash -c "cd '$T/main' && . '$SL' && DQ_MERGE_SESSION=B merge_lock_require"
check "a second --lanes from the holder is refused (use --join)" bash -c "DQ_MERGE_SESSION=A bash '$MW' --lanes again 2>&1 | grep -q 'already hold'"

check "merge_master refuses in the merge worktree without the lock" bash -c "cd '$T/mb' && DQ_MERGE_SESSION=B bash '$ROOT/tools/dq_merge_master.sh' 2>&1 | grep -q 'do not hold its lock'"
echo staged >"$T/mb/staged.txt" && git -C "$T/mb" add staged.txt
check "merge_master refuses to start on staged files, even for the holder" bash -c "cd '$T/mb' && DQ_MERGE_SESSION=A bash '$ROOT/tools/dq_merge_master.sh' 2>&1 | grep -q 'staged or modified tracked files'"
check "the staged file was left alone" test "$(git -C "$T/mb" diff --cached --name-only)" = "staged.txt"
git -C "$T/mb" rm -q --cached -f staged.txt && rm -f "$T/mb/staged.txt"
check "no automatic stashing is configured for the tools" bash -c ". '$ROOT/tools/dq_git_safe.sh' && [ \"\$(git config --get merge.autoStash)\" = false ] && [ \"\$(git config --get rebase.autoStash)\" = false ]"

# ---- 3. only the holder joins and releases ----
check "a non-holder cannot --join" bash -c "! DQ_MERGE_SESSION=B bash '$MW' --join laneX >/dev/null 2>&1"
check "the holder can --join" bash -c "DQ_MERGE_SESSION=A bash '$MW' --join laneA2 >/dev/null 2>&1"
check "the joined lanes show in status" bash -c "bash '$SL' merge-lock status | grep -q 'laneA laneA2'"
check "a non-holder cannot --release" bash -c "! DQ_MERGE_SESSION=B bash '$MW' --release >/dev/null 2>&1"

# ---- 4. A pushes (as dq_push_master does) and the lock frees B ----
git -C "$T/mb" push -q origin HEAD:master
check "A's release frees the lock" run_as A --release
for _ in $(seq 1 30); do [ -s "$T/b.out" ] && break; sleep 1; done
check "B got the worktree once A released" test "$(cat "$T/b.out" 2>/dev/null)" = "$T/mb"
check "B's clear check ran after A's push: worktree is at origin/master" test "$(git -C "$T/mb" rev-parse HEAD)" = "$(git -C "$T/main" rev-parse origin/master)"
check "B is now the holder" bash -c "bash '$SL' merge-lock status | grep -q \"lanes 'laneB'\""
wait "$bpid" 2>/dev/null
run_as B --release >/dev/null

# ---- 5. a failed clear check frees the lock ----
echo dirty >"$T/mb/dirty.txt"
run_as C --lanes laneC >/dev/null 2>"$T/c.err" && rc=0 || rc=$?
check "a dirty worktree aborts the batch" test "$rc" -ne 0
check "the aborted batch released the lock" bash -c "bash '$SL' merge-lock status | grep -q 'nobody'"
rm -f "$T/mb/dirty.txt"

# ---- 6. a crashed holder is reclaimed ----
run_as D --lanes laneD >/dev/null 2>&1
dpid="$(sed -n 's/^pid=//p' "$T/slots/merge_base/slot.1/owner")"
kill -9 "$dpid" 2>/dev/null
sleep 1
out="$(run_as E --lanes laneE 2>"$T/e.err")"
check "a killed holder's lock is reclaimed by the next batch" test "$out" = "$T/mb"
check "the reclaim was announced" grep -q "reclaiming a dead slot" "$T/e.err"
run_as E --release >/dev/null

# ---- 7. a landed push frees the lock (the release_batch path of dq_push_master.sh) ----
run_as F --lanes laneF >/dev/null 2>&1
check "push script frees the lock when the batch has landed" bash -c "cd '$T/mb' && . '$SL' && DQ_MERGE_SESSION=F merge_lock_release >/dev/null && bash '$SL' merge-lock status | grep -q nobody"

# ---- 8. the holder process ends with the lock ----
run_as G --lanes laneG >/dev/null 2>&1
gpid="$(sed -n 's/^pid=//p' "$T/slots/merge_base/slot.1/owner")"
run_as G --release >/dev/null
sleep 3
check "the holder process exited after release" bash -c "! kill -0 $gpid 2>/dev/null"

# ---- 9. the push releases the lock wherever it ran from (a lane that restamps and pushes from its own worktree) ----
export DQ_MERGE_LOCK_CHECK_SEC=2
git -C "$T/main" worktree add -q -b lane-p "$T/lane-p" origin/master 2>/dev/null
(cd "$T/lane-p" && run_as P --lanes laneP >/dev/null 2>&1)
check "P holds the lock" bash -c "bash '$SL' merge-lock status | grep -q \"lanes 'laneP'\""
rb="$(sed -n '/^release_batch() {/p' "$ROOT/tools/dq_push_master.sh")"
check "release_batch is a single definition in the push script" test -n "$rb"
check "release_batch from the lane worktree frees the holder's lock" bash -c "cd '$T/lane-p' && . '$SL' && $rb; DQ_MERGE_SESSION=P release_batch >/dev/null 2>&1; bash '$SL' merge-lock status | grep -q nobody"
check "release_batch does not touch another batch's lock" bash -c "cd '$T/lane-p' && DQ_MERGE_SESSION=Q bash '$MW' --lanes laneQ >/dev/null 2>&1 && . '$SL' && $rb; DQ_MERGE_SESSION=R release_batch >/dev/null 2>&1; bash '$SL' merge-lock status | grep -q \"lanes 'laneQ'\""
run_as Q --release >/dev/null

# ---- 10. a holder whose lane worktree is gone releases itself, heartbeat or not ----
(cd "$T/lane-p" && run_as S --lanes laneS >/dev/null 2>&1)
spid="$(sed -n 's/^pid=//p' "$T/slots/merge_base/slot.1/owner")"
git -C "$T/main" worktree remove --force "$T/lane-p"
for _ in $(seq 1 40); do [ -d "$T/slots/merge_base/slot.1" ] || break; sleep 1; done
check "the lock was released after the lane worktree vanished" test ! -d "$T/slots/merge_base/slot.1"
sleep 2
check "and the holder process ended" bash -c "! kill -0 $spid 2>/dev/null"

# ---- 11. a holder whose batch HEAD already landed releases itself, but not under a running gate or push ----
run_as H --lanes laneH >/dev/null 2>&1
echo h >"$T/mb/h.txt" && git -C "$T/mb" add h.txt && git -C "$T/mb" commit -qm "H's batch"
sleep 6
check "unpushed batch work keeps the lock" test -d "$T/slots/merge_base/slot.1"
sleep 30 & busy=$!
echo "$busy" >"$T/slots/merge_base/slot.1/busy"
git -C "$T/mb" push -q origin HEAD:master
sleep 8
check "a running gate or push (busy marker) keeps the lock after the push landed" test -d "$T/slots/merge_base/slot.1"
kill "$busy" 2>/dev/null; wait "$busy" 2>/dev/null
for _ in $(seq 1 40); do [ -d "$T/slots/merge_base/slot.1" ] || break; sleep 1; done
check "once nothing runs, the landed batch's lock is released by its holder" test ! -d "$T/slots/merge_base/slot.1"

# ---- 12. the same session and worktree never queue twice ----
run_as U --lanes laneU >/dev/null 2>&1
DQ_MERGE_SESSION=V bash "$MW" --lanes laneV >/dev/null 2>"$T/v1.err" &
v1=$!
for _ in $(seq 1 30); do grep -q waiting "$T/v1.err" 2>/dev/null && break; sleep 1; done
DQ_MERGE_SESSION=V bash "$MW" --lanes laneV >/dev/null 2>"$T/v2.err" && rc=0 || rc=$?
check "a second queue entry from the same session and worktree is refused" bash -c "[ $rc -ne 0 ] && grep -q 'not queueing twice' '$T/v2.err'"
check "only one entry waits" test "$(ls "$T/slots/merge_base/queue" | wc -l)" -eq 1
run_as U --release >/dev/null
for _ in $(seq 1 40); do bash "$SL" merge-lock status | grep -q "lanes 'laneV'" && break; sleep 1; done
wait "$v1" 2>/dev/null
run_as V --release >/dev/null

# ---- 13. no mode changes the merge worktree without the lock; an unpushed batch already there is adopted, not re-merged or discarded ----
echo z >"$T/mb/z.txt" && git -C "$T/mb" add z.txt && git -C "$T/mb" commit -qm "Z's batch, merged without the lock"
git -C "$T/mb" branch laneZ HEAD
zhead="$(git -C "$T/mb" rev-parse HEAD)"
run_as Y >/dev/null 2>"$T/y.err" && rc=0 || rc=$?
check "a plain call (no --lanes) on a worktree holding an unpushed batch is refused" test "$rc" -ne 0
check "and left the lock free and the worktree alone" bash -c "bash '$SL' merge-lock status | grep -q nobody && [ \"\$(git -C '$T/mb' rev-parse HEAD)\" = $zhead ]"
run_as Y --warm --lanes laneY >/dev/null 2>&1 && rc=0 || rc=$?
check "--warm does not bypass the lock or the check" bash -c "[ $rc -ne 0 ] && [ \"\$(git -C '$T/mb' rev-parse HEAD)\" = $zhead ] && bash '$SL' merge-lock status | grep -q nobody"
run_as Y --adopt >/dev/null 2>&1 && rc=0 || rc=$?
check "--adopt without --lanes is refused" test "$rc" -ne 0
git -C "$T/main" branch -q laneOther "$(git -C "$T/main" commit-tree -p origin/master -m other "origin/master^{tree}")"
run_as Y --adopt --lanes laneOther >/dev/null 2>"$T/y2.err" && rc=0 || rc=$?
check "--adopt of a lane that is not in HEAD is refused (not the owner)" bash -c "[ $rc -ne 0 ] && grep -q 'is not in the worktree' '$T/y2.err' && bash '$SL' merge-lock status | grep -q nobody"
git -C "$T/main" branch -q laneOld origin/master
run_as Y --adopt --lanes laneOld >/dev/null 2>"$T/y3.err" && rc=0 || rc=$?
check "--adopt of a lane already in origin/master is refused" bash -c "[ $rc -ne 0 ] && grep -q 'already in origin/master' '$T/y3.err' && bash '$SL' merge-lock status | grep -q nobody"
out="$(run_as Z --adopt --lanes laneZ 2>"$T/z.err")" && rc=0 || rc=$?
check "the owner adopts its batch: path printed" bash -c "[ $rc -eq 0 ] && [ '$out' = '$T/mb' ]"
check "adopting changed nothing: same HEAD, no discard branch" bash -c "[ \"\$(git -C '$T/mb' rev-parse HEAD)\" = $zhead ] && [ -z \"\$(git -C '$T/mb' branch --list 'rewrite/integ-prev-*')\" ]"
check "the lock is held for the batch" bash -c "bash '$SL' merge-lock status | grep -q \"lanes 'laneZ'\""
check "a second batch cannot stack on it" bash -c "! DQ_SLOTS_POLL_SEC=1 timeout 5 env DQ_MERGE_SESSION=W bash '$MW' --lanes laneW >/dev/null 2>&1"
git -C "$T/mb" push -q origin HEAD:master
for _ in $(seq 1 40); do [ -d "$T/slots/merge_base/slot.1" ] || break; sleep 1; done
check "the adopted batch's lock self-releases once it landed" test ! -d "$T/slots/merge_base/slot.1"

# ---- 14. the reference-transaction guard refuses a raw merge/commit in the merge worktree without the lock ----
cp "$ROOT/tools/hooks/reference-transaction" "$T/main/.git/hooks/reference-transaction" && chmod +x "$T/main/.git/hooks/reference-transaction"
export DQ_MERGE_LOCK_LIB="$SL"
git -C "$T/mb" commit -q --allow-empty -m "raw commit without the lock" 2>"$T/h.err" && rc=0 || rc=$?
check "a raw commit in the merge worktree without the lock is refused by the hook" bash -c "[ $rc -ne 0 ] && grep -q 'do not hold its lock' '$T/h.err'"
git -C "$T/main" commit -q --allow-empty -m "main checkout is not guarded" 2>/dev/null && ok "other checkouts are not guarded" || fail "the hook blocked a non-merge worktree"
run_as K --lanes laneK >/dev/null 2>&1
DQ_MERGE_SESSION=K git -C "$T/mb" commit -q --allow-empty -m "holder commit" && ok "the lock holder may commit in the merge worktree" || fail "holder blocked by the hook"
git -C "$T/mb" push -q origin HEAD:master
run_as K --release >/dev/null
rm -f "$T/main/.git/hooks/reference-transaction"
unset DQ_MERGE_LOCK_LIB

if [ "$fails" -eq 0 ]; then echo "test_merge_lock: ok"; exit 0; fi
echo "test_merge_lock: $fails FAILED"
exit 1
