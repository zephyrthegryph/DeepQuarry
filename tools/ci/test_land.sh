#!/usr/bin/env bash
# Self-test of tools/dq_land.sh in a scratch repository with stub merge tools (no compiler, no world, no machine slots):
#   1. master unmoved: one proof outside the lock, the lock held only for the merge + gates + push, the lane lands;
#   2. master moves while the lane is proved: the lock is NOT taken for the stale proof, the lane is proved again, then lands;
#   3. master moves while the lock is queued: the lock is given back at once, the lane is proved again, then lands;
#   4. master keeps moving: the last round lands under the lock with the gates (no starvation);
#   5. an already proved merge is landed with no proof run at all.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

export DQ_PROOF_DIR="$tmp/proofs" DQ_MERGE_SESSION=lane-x DQ_LANE_NOTES_PUSH=0
git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
cd "$tmp/repo"
git config user.email t@t; git config user.name t
mkdir -p tools/ci lanes
cp "$here/tools/dq_land.sh" "$here/tools/dq_run_lock.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_proof_cache.sh" tools/
echo "smoke_one" >tools/ci/smoke_tests.txt
echo base >lanes/base.txt
# stubs ---------------------------------------------------------------------------------------------------------------------------------
cat >tools/dq_machine_slots.sh <<'STUB'
merge_lock_holder_check() { [ -f "$STATE/lock" ]; }
merge_lock_release() { rm -f "$STATE/lock"; echo release >>"$STATE/events"; }
STUB
cat >tools/dq_merge_worktree.sh <<'STUB'
#!/usr/bin/env bash
# --lanes X: take the lock, move the second clone to origin/master, print its path. --release: free the lock.
if [ "$1" = "--release" ]; then rm -f "$STATE/lock"; echo release >>"$STATE/events"; exit 0; fi
echo "lock" >>"$STATE/events"; : >"$STATE/lock"
[ -z "${MOVE_DURING_QUEUE:-}" ] || { [ -f "$STATE/moved_q" ] || { touch "$STATE/moved_q"; bash "$STATE/advance_master.sh"; }; }
git -C "$WTDIR" fetch -q origin; git -C "$WTDIR" switch -q -C rewrite/integ-current origin/master
echo "$WTDIR"
STUB
cat >tools/dq_lane_ready.sh <<'STUB'
#!/usr/bin/env bash
# merges origin/master into the lane, "proves" it (stores the proof under the tree), optionally moves master meanwhile
echo prove >>"$STATE/events"
git fetch -q origin; git merge -q --no-edit origin/master >/dev/null 2>&1
. tools/dq_proof_cache.sh
proof_store "$(proof_tree HEAD)" "$(git rev-parse origin/master)" "smoke_one" 1 0 0 0 0 ""
n=$(grep -c '^prove$' "$STATE/events")
if [ -n "${MOVE_DURING_PROOF:-}" ] && [ "$n" -le "$MOVE_DURING_PROOF" ]; then bash "$STATE/advance_master.sh"; fi
exit 0
STUB
cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
. tools/dq_proof_cache.sh
if proof_find "$(proof_tree HEAD)" 0 0 smoke_one >/dev/null; then echo gates-reuse >>"$STATE/events"; else echo gates-FULL >>"$STATE/events"; fi
exit 0
STUB
cat >tools/dq_push_master.sh <<'STUB'
#!/usr/bin/env bash
echo push >>"$STATE/events"
if [ -n "${DQ_PUSH_DRY_RUN:-}" ]; then exit 0; fi
git push -q origin HEAD:refs/heads/master && rm -f "$STATE/lock"
STUB
git add -A; git commit -q -m init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
git worktree add -q -b rewrite/integ-current "$tmp/wt" origin/master 2>/dev/null
# a second clone that moves master
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null; (cd "$tmp/other" && git config user.email t@t && git config user.name t)
export STATE="$tmp/state" WTDIR="$tmp/wt"
mkdir -p "$STATE"
cat >"$STATE/advance_master.sh" <<STUB
cd "$tmp/other" && git pull -q origin master 2>/dev/null; echo "\$RANDOM\$RANDOM" >lanes/m_\$RANDOM.txt; git add -A; git commit -q -m "master moves"; git push -q origin HEAD:master
STUB

lane() { # fresh lane branch from the current origin/master with one commit
	git fetch -q origin
	git switch -q -C lane-x origin/master
	echo "$RANDOM$RANDOM" >"lanes/lane_$RANDOM.txt"; git add -A; git commit -q -m "lane work"
}
run() { rm -rf "$STATE/events" "$STATE/lock" "$STATE/moved_q"; : >"$STATE/events"; bash tools/dq_land.sh "$@" >"$tmp/out.log" 2>&1; echo $?; }
ev() { tr '\n' ' ' <"$STATE/events"; }

lane
rc="$(run)"
check "unmoved master: prove, lock, merge gates reuse, push" '[ "$rc" = 0 ] && [ "$(ev)" = "prove lock gates-reuse push " ] && git merge-base --is-ancestor lane-x origin/master'

lane
rc="$(MOVE_DURING_PROOF=1 run)"
check "master moves during the proof: no lock for the stale proof, proved again, then lands" '[ "$rc" = 0 ] && [ "$(ev)" = "prove prove lock gates-reuse push " ]'

lane
rc="$(MOVE_DURING_QUEUE=1 run)"
check "master moves while the lock is queued: lock given back, proved again, then lands" '[ "$rc" = 0 ] && [ "$(ev)" = "prove lock release prove lock gates-reuse push " ]'

lane
rc="$(MOVE_DURING_PROOF=9 run --rounds 2)"
check "master keeps moving: the last round lands under the lock with the gates" '[ "$rc" = 0 ] && [ "$(ev)" = "prove prove lock gates-FULL push " ] && grep -q "last round" "$tmp/out.log"'

lane
bash tools/dq_lane_ready.sh >/dev/null 2>&1
rc="$(run)"
check "an already proved merge lands with no proof run" '[ "$rc" = 0 ] && [ "$(ev)" = "lock gates-reuse push " ]'

lane
rc="$(run --dry-run)"
check "dry run pushes nothing and frees the lock" '[ "$rc" = 0 ] && ! git merge-base --is-ancestor lane-x origin/master && [ ! -f "$STATE/lock" ]'

lane
rc="$(DQ_MERGE_SESSION= run)"
check "DQ_MERGE_SESSION unset: defaults to the branch and lands" '[ "$rc" = 0 ] && git merge-base --is-ancestor lane-x origin/master'

lane
git switch -q --detach
rc="$(DQ_MERGE_SESSION= run)"
check "a detached HEAD is still refused" '[ "$rc" = 2 ] && grep -q "detached HEAD" "$tmp/out.log"'

# disjoint accept (stub tools/dq_land_disjoint.sh: merges master into the lane and stores the proof, like the real one on success)
cat >tools/dq_land_disjoint.sh <<'STUB'
#!/usr/bin/env bash
[ -z "${DISJOINT_NO:-}" ] || { echo "== land-disjoint: NOT accepted: stub"; exit 1; }
echo disjoint >>"$STATE/events"
git fetch -q origin; git merge -q --no-edit origin/master >/dev/null 2>&1
. tools/dq_proof_cache.sh
proof_store "$(proof_tree HEAD)" "$(git rev-parse origin/master)" "smoke_one" 1 0 0 0 0 ""
git notes --ref=lane-ready add -f -m '{"ok":true}' HEAD
exit 0
STUB
lane
rc="$(MOVE_DURING_QUEUE=1 run)"
check "master moved while queued but the lane qualifies: accepted twice without a proof run, the queue move not counted" '[ "$rc" = 0 ] && [ "$(ev)" = "disjoint lock release disjoint lock push " ] && ! grep -q "^prove$" "$STATE/events"'
lane
rc="$(DISJOINT_NO=1 run)"
check "a lane that does not qualify is proved as before" '[ "$rc" = 0 ] && [ "$(ev)" = "prove lock gates-reuse push " ]'

[ "$fail" -eq 0 ] && echo "test_land: all passed" || { echo "test_land: FAILED"; exit 1; }
