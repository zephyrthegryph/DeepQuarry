#!/usr/bin/env bash
# Self-test of tools/dq_lane_pool.sh in a scratch repository (no network, no DM, no daemon).
#
#   bash tools/ci/test_lane_pool.sh      # prints PASS/FAIL per case, exit 1 on any failure
#
# Cases: lease creates pool-1 and a branch on origin/master; a second lane gets pool-2; a third is refused (exit 3, "POOL FULL");
# leasing a held branch returns its slot; release refuses a dirty tree; release keeps icons/gen, data/analyze-cache and node_modules,
# deletes build outputs, detaches at origin/master and keeps an unmerged branch; a finished (merged) lane is reclaimed by the next
# lease; a dirty free slot is skipped, not cleaned.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
g() { git -C "$tmp/repo" "$@"; }
g config user.email t@t; g config user.name t
mkdir -p "$tmp/repo/tools"
cp "$here/tools/dq_lane_pool.sh" "$here/tools/dq_git_safe.sh" "$tmp/repo/tools/"
printf 'deepquarry.dmb\ndeepquarry.rsc\n/data/**/*\n/data\nicons/gen/\nnode_modules\n' >"$tmp/repo/.gitignore"
echo a >"$tmp/repo/a.txt"; echo m >"$tmp/repo/deepquarry.dme"
g add -A && g commit -q -m init && g branch -M master && g push -q origin master 2>/dev/null
g fetch -q origin

export DQ_LANE_POOL_DIR="$tmp/pool" DQ_LANE_POOL_STATE="$tmp/state" DQ_LANE_POOL_SIZE=2 DQ_LANE_POOL_REPO="$tmp/repo" DQ_DMBC_DAEMON_DIR="$tmp/none"
export DQ_LANE_POOL_NO_UPDATE=1
export DQ_LANE_POOL_PROCS_CMD="echo no processes"   # never spawn powershell (seconds per call) in the fixtures
pool() { bash "$tmp/repo/tools/dq_lane_pool.sh" "$@"; }

p1="$(pool lease lane/a 2>/dev/null)"
check "lease 1 creates pool-1 on a new branch at origin/master" '[ "$p1" = "$tmp/pool/pool-1" ] && [ "$(git -C "$p1" symbolic-ref --short HEAD)" = lane/a ] && [ "$(git -C "$p1" rev-parse HEAD)" = "$(g rev-parse origin/master)" ]'
p2="$(pool lease lane/b 2>/dev/null)"
check "lease 2 uses pool-2" '[ "$p2" = "$tmp/pool/pool-2" ]'
out="$(pool lease lane/c 2>&1)"; rc=$?
check "third lane refused with exit 3 and a clear message" '[ "$rc" -eq 3 ] && grep -q "POOL FULL" <<<"$out" && grep -q "lane/a" <<<"$out"'
check "no third worktree was created" '[ ! -e "$tmp/pool/pool-3" ]'
again="$(pool lease lane/a 2>/dev/null)"
check "leasing a held branch returns its slot" '[ "$again" = "$p1" ]'

mkdir -p "$p1/icons/gen" "$p1/data/analyze-cache" "$p1/data/logs" "$p1/node_modules"
echo i >"$p1/icons/gen/x.dmi"; echo c >"$p1/data/analyze-cache/c"; echo l >"$p1/data/logs/l"; echo b >"$p1/deepquarry.dmb"; echo r >"$p1/deepquarry.rsc"
echo dirty >>"$p1/a.txt"
out="$(pool release lane/a 2>&1)"; rc=$?
check "release refuses a dirty tree" '[ "$rc" -ne 0 ] && grep -q "not clean" <<<"$out"'
echo a >"$p1/a.txt"
echo work >"$p1/work.txt"; git -C "$p1" add work.txt; git -C "$p1" commit -q -m work
pool release lane/a >/dev/null 2>&1
check "release detaches at origin/master" '[ -z "$(git -C "$p1" symbolic-ref -q --short HEAD)" ] && [ "$(git -C "$p1" rev-parse HEAD)" = "$(g rev-parse origin/master)" ]'
check "release keeps icons/gen, data/analyze-cache and node_modules" '[ -f "$p1/icons/gen/x.dmi" ] && [ -f "$p1/data/analyze-cache/c" ] && [ -d "$p1/node_modules" ]'
check "release deletes build outputs" '[ ! -e "$p1/deepquarry.dmb" ] && [ ! -e "$p1/deepquarry.rsc" ] && [ ! -e "$p1/data/logs" ]'
check "release keeps an unmerged branch" 'g show-ref -q --verify refs/heads/lane/a'
check "the slot is free again" '[ "$(pool status | grep -c LEASED)" -eq 1 ]'

git -C "$p2" commit -q --allow-empty -m "lane work"
g push -q origin "lane/b:master" 2>/dev/null; g fetch -q origin
held="$(DQ_LANE_POOL_RECLAIM_IDLE_MIN=180 pool lease lane/x 2>&1)"
check "a merged lane still working (recently touched) keeps its slot" '! grep -q "reclaimed" <<<"$held" && git -C "$p2" symbolic-ref -q --short HEAD | grep -qx lane/b'
pool release lane/x >/dev/null 2>&1
p3="$(DQ_LANE_POOL_RECLAIM_IDLE_MIN=0 pool lease lane/c 2>/dev/null)"
check "a merged lane's slot is reclaimed for a new lease" '[ -n "$p3" ] && [ "$(git -C "$p3" symbolic-ref --short HEAD)" = lane/c ]'
check "the merged branch was deleted" '! g show-ref -q --verify refs/heads/lane/b'

pool release lane/c >/dev/null 2>&1
echo junk >"$p1/untracked.txt"
p4="$(pool lease lane/d 2>/dev/null)"
check "a dirty free slot is skipped" '[ "$p4" != "$p1" ] && [ -f "$p1/untracked.txt" ]'

rm -f "$p1/untracked.txt"
pool lease lane/e >/dev/null 2>&1
DQ_LANE_POOL_WAIT_POLL=1 pool lease lane/f --wait --timeout 2 >"$tmp/wait.out" 2>"$tmp/wait.err" &
waiter=$!
sleep 8
check "a waiter queues instead of failing on a full pool" 'kill -0 "$waiter" 2>/dev/null && st="$(pool status)" && grep -q "queue 1: lane/f" <<<"$st"'
pool release lane/e >/dev/null 2>&1
wait "$waiter"; wrc=$?
check "the waiter gets the freed slot and exits 0" '[ "$wrc" -eq 0 ] && [ -n "$(cat "$tmp/wait.out")" ] && [ "$(git -C "$(cat "$tmp/wait.out")" symbolic-ref --short HEAD)" = lane/f ]'
check "the queue is empty afterwards" '! pool status | grep -q "queue "'

# ---- lane classes: compiler (reserved pool-c1/c2, ahead of general), light (one shared slot, own queue) ----------------------------
export DQ_LANE_POOL_DIR="$tmp/pool2" DQ_LANE_POOL_STATE="$tmp/state2" DQ_LANE_POOL_SIZE=1 DQ_LANE_POOL_COMPILER=2
g1="$(pool lease lane/g1 2>/dev/null)"
check "a general lane takes pool-1" '[ "$g1" = "$tmp/pool2/pool-1" ]'
out="$(pool lease lane/g2 2>&1)"; rc=$?
check "general lanes never take the reserved compiler slots" '[ "$rc" -eq 3 ] && [ ! -e "$tmp/pool2/pool-c1" ]'
c1="$(pool lease tools/dmb-fix 2>/dev/null)"
check "a tools/dmb* branch is a compiler lane on pool-c1" '[ "$c1" = "$tmp/pool2/pool-c1" ]'
c2="$(pool lease lane/zz --class compiler 2>/dev/null)"
check "--class compiler takes pool-c2" '[ "$c2" = "$tmp/pool2/pool-c2" ]'
c3="$(pool lease tools/dmb-third 2>&1)"; rc=$?
check "a third compiler lane finds the general slot held too: pool full" '[ "$rc" -eq 3 ]'
pool release lane/g1 >/dev/null 2>&1
c3="$(pool lease tools/dmb-third 2>/dev/null)"
check "a compiler lane overflows into a free general slot" '[ "$c3" = "$tmp/pool2/pool-1" ]'
l1="$(pool lease docs/one --class light 2>/dev/null)"
check "a light lane takes the one shared pool-light" '[ "$l1" = "$tmp/pool2/pool-light" ]'
out="$(pool lease docs/two --class light 2>&1)"; rc=$?
check "a second light lane waits (pool full) instead of taking a game slot" '[ "$rc" -eq 3 ] && grep -q "light" <<<"$out"'
pool release docs/one >/dev/null 2>&1
check "the light slot is free after release" '[ -n "$(pool lease docs/two --class light 2>/dev/null)" ]'
pool release docs/two >/dev/null 2>&1
DQ_LANE_POOL_WAIT_POLL=1 pool lease lane/gw --wait --timeout 2 >"$tmp/gw.out" 2>/dev/null &
gw=$!
sleep 2
DQ_LANE_POOL_WAIT_POLL=1 pool lease tools/dmb-late --class compiler --wait --timeout 2 >"$tmp/late.out" 2>/dev/null &
late=$!
sleep 2
check "a compiler waiter sorts ahead of a general waiter" '[ "$(pool status | grep "queue [0-9]" | head -n 1 | grep -c dmb-late)" -eq 1 ]'
kill "$gw" "$late" 2>/dev/null; wait 2>/dev/null

# status never waits for `du` (a built worktree takes a minute on Windows): a slow du is refreshed in the background
mkdir -p "$tmp/slowbin"; printf '#!/bin/sh
sleep 25
echo 1024 "$2"
' >"$tmp/slowbin/du"; chmod +x "$tmp/slowbin/du"
rm -rf "$tmp/state/sizes"
t0=$(date +%s); PATH="$tmp/slowbin:$PATH" pool status >/dev/null 2>&1; t1=$(date +%s)
check "status returns promptly even when du is slow" '[ $((t1 - t0)) -lt 12 ]'

# ---- stuck leases, cancel, suite cap (fresh pool and state; the earlier cases' leases are not involved) ----
cp "$here/tools/dq_machine_slots.sh" "$tmp/repo/tools/"
export DQ_LANE_POOL_DIR="$tmp/pool4" DQ_LANE_POOL_STATE="$tmp/state4" DQ_LANE_POOL_SIZE=2 DQ_SLOTS_DIR="$tmp/slots2" DQ_LANE_POOL_PROCS_CMD="echo nothing relevant"
export DQ_LANE_POOL_STUCK_MIN=30 DQ_LANE_POOL_RECLAIM_IDLE_MIN=60
sa="$(pool lease stuck/a 2>"$tmp/sa.err")"; sb="$(pool lease stuck/b 2>>"$tmp/sa.err")"; cat "$tmp/sa.err" >&2
echo unsaved >>"$sa/a.txt"
old() { # <slot dir> <slot name>: make every sign of activity two hours old
	local gd; gd="$(git -C "$1" rev-parse --absolute-git-dir)"
	touch -d "2 hours ago" "$DQ_LANE_POOL_STATE/pool-$2.lease" "$gd/HEAD" "$gd/logs/HEAD" "$1/a.txt"
}
pool status >/dev/null 2>&1
old "$sa" 1; old "$sb" 2
out="$(pool stuck 2>&1)"; rc=$?
check "stuck lists a dirty and a clean idle lease and exits 1" '[ "$rc" -eq 1 ] && grep -q "STUCK pool-1 stuck/a.*dirty=1.*report-only" <<<"$out" && grep -q "STUCK pool-2 stuck/b.*dirty=0.*reclaimable" <<<"$out"'
check "a notice file is written for a stuck lease" '[ -f "$DQ_LANE_POOL_STATE/notices/pool-1.stuck" ] && grep -q "dirty=1" "$DQ_LANE_POOL_STATE/notices/pool-1.stuck"'
pool status >"$tmp/status.out" 2>&1
check "status flags STUCK with the idle time" 'grep -q "pool-1  LEASED.*STUCK: no live process, idle 2h.*DIRTY" "$tmp/status.out" || { cat "$tmp/status.out" >&2; false; }'
pool lease stuck/c >"$tmp/c.out" 2>"$tmp/c.err"; crc=$?
check "the clean stuck lease is reclaimed, the dirty one is never wiped" '[ "$crc" -eq 0 ] && grep -q "reclaimed pool-2 (stuck" "$tmp/c.err" && [ "$(cat "$tmp/c.out")" = "$sb" ] && grep -q unsaved "$sa/a.txt" && [ "$(pool path stuck/a)" = "$sa" ]'
DQ_LANE_POOL_PROCS_CMD="echo node run $sa/x" pool stuck >/dev/null 2>&1; lrc=$?
check "a live process using the worktree makes it not stuck" '[ "$lrc" -eq 0 ]'
check "the notice goes away once the lease is not stuck" '[ ! -f "$DQ_LANE_POOL_STATE/notices/pool-1.stuck" ]'

DQ_LANE_POOL_WAIT_POLL=1 pool lease stuck/w --wait --timeout 3 >"$tmp/w.out" 2>"$tmp/w.err" &
cw=$!
sleep 4
check "a queued lease shows in status" 'kill -0 "$cw" 2>/dev/null && pool status 2>&1 | grep -q "queue 1: stuck/w"'
pool cancel stuck/w >/dev/null 2>&1
wait "$cw"; cwrc=$?
check "cancel makes the waiter exit 4 with a cancelled message, nothing killed" '[ "$cwrc" -eq 4 ] && grep -q cancelled "$tmp/w.err" && ! pool status 2>&1 | grep -q "stuck/w"'
out="$(pool cancel stuck/nobody 2>&1)"; nrc=$?
check "cancel of an unknown branch is an error" '[ "$nrc" -ne 0 ] && grep -q "no queued lease" <<<"$out"'

capsize() { ( export DQ_SLOTS_DIR="$tmp/slots3" DQ_SLOTS_TEST_WORLD=2 DQ_SLOTS_MERGE_RESERVE=0 DQ_SLOT_WORKTREE=/x/pool-9 DQ_SLOT_PRIORITY="${PRIO:-1}"; . "$tmp/repo/tools/dq_machine_slots.sh"; slots_group_size test_world 2 ); }
check "suite cap: no cap while nobody waits" '[ "$(capsize)" = 2 ]'
mkdir -p "$tmp/slots3/test_world/queue"
printf 'kind=bash\npid=%s\nworktree=/x/other\nlabel=f\nqueued=%s\n' "$$" "$(date +%s)" >"$tmp/slots3/test_world/queue/1-0000000000001-$$"
check "suite cap: 1 world while another run waits, priority 0 exempt" '[ "$(capsize)" = 1 ] && [ "$(PRIO=0 capsize)" = 2 ]'
check "suite cap: DQ_SLOTS_SUITE_MAX_WORLDS=2 always allows 2, =1 always caps" '[ "$(DQ_SLOTS_SUITE_MAX_WORLDS=2 capsize)" = 2 ] && [ "$(DQ_SLOTS_SUITE_MAX_WORLDS=1 capsize)" = 1 ]'

[ "$fail" -eq 0 ] && echo "test_lane_pool: all passed" || echo "test_lane_pool: FAILED"
exit "$fail"
