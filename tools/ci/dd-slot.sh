#!/bin/bash
# Machine-wide DreamDaemon limiter: holds one of a fixed number of
# directory-lock slots while running "$@". Stale slots (owner pid gone) are
# reclaimed. Waits while the exclusive bench lock (see dd-slot-exclusive.sh,
# used by `bench --exclusive`) is held, so an exclusive benchmark run gets a
# genuinely quiet machine instead of racing new DreamDaemons that start right
# after it finishes draining the existing ones.
#
# The slot/lock base directories are NOT hardcoded to any one machine: they
# follow the same env vars tools/build/lib/bench.ts derives them from
# (DQ_BENCH_STORE, DQ_DD_SLOT_BASE, DQ_BENCH_EXCLUSIVE_LOCK), so this script
# and the TypeScript bench tooling always agree on where the locks live. With
# nothing set, it falls back to a directory next to this checkout, which is
# NOT shared across worktrees -- set DQ_BENCH_STORE (e.g. to a directory
# that's a sibling of all your worktree checkouts) to make DreamDaemon
# scheduling and bench baselines actually machine-wide. See doc/testing.md.
#
# Usage: dd-slot.sh <command...>

SLOT_COUNT=${DQ_DD_SLOT_COUNT:-5}

default_base_parent() {
  if [ -n "$DQ_BENCH_STORE" ]; then
    dirname -- "$DQ_BENCH_STORE"
  else
    # No shared store configured: fall back to a directory next to this
    # script's repo root. Only reliable within a single checkout.
    cd "$(dirname "$0")/../.." && pwd
  fi
}

SLOT_BASE=${DQ_DD_SLOT_BASE:-"$(default_base_parent)/.dq-dd-slot-"}
EXCLUSIVE=${DQ_BENCH_EXCLUSIVE_LOCK:-"${DQ_BENCH_STORE:-$(default_base_parent)/data/bench}/.dq-bench-exclusive"}
EXCLUSIVE_MAX_AGE=1200 # 20 minutes; matches acquireBenchExclusiveLock()'s default in lib/bench.ts

exclusive_stale() {
  [ -d "$EXCLUSIVE" ] || return 1
  local started now
  started=$(cat "$EXCLUSIVE/started" 2>/dev/null)
  now=$(date +%s)
  [ -n "$started" ] && [ $((now - started)) -gt "$EXCLUSIVE_MAX_AGE" ]
}

while true; do
  if [ -d "$EXCLUSIVE" ]; then
    if exclusive_stale; then
      rm -rf "$EXCLUSIVE"
    else
      sleep 5
      continue
    fi
  fi
  acquired=0
  for i in $(seq 1 "$SLOT_COUNT"); do
    d="${SLOT_BASE}${i}"
    if mkdir "$d" 2>/dev/null; then
      echo $$ > "$d/pid"
      trap 'rm -rf "'"$d"'"' EXIT
      "$@"; rc=$?
      exit $rc
    fi
    p=$(cat "$d/pid" 2>/dev/null)
    if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf "$d"; fi
  done
  sleep 10
done
