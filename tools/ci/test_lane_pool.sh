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
p3="$(pool lease lane/c 2>/dev/null)"
check "a merged lane's slot is reclaimed for a new lease" '[ -n "$p3" ] && [ "$(git -C "$p3" symbolic-ref --short HEAD)" = lane/c ]'
check "the merged branch was deleted" '! g show-ref -q --verify refs/heads/lane/b'

pool release lane/c >/dev/null 2>&1
echo junk >"$p1/untracked.txt"
p4="$(pool lease lane/d 2>/dev/null)"
check "a dirty free slot is skipped" '[ "$p4" != "$p1" ] && [ -f "$p1/untracked.txt" ]'

[ "$fail" -eq 0 ] && echo "test_lane_pool: all passed" || echo "test_lane_pool: FAILED"
exit "$fail"
