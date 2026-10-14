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

if [ "$fails" -eq 0 ]; then echo "test_merge_lock: ok"; exit 0; fi
echo "test_merge_lock: $fails FAILED"
exit 1
