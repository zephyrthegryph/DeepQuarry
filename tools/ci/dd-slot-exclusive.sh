#!/bin/bash
# Exclusive bench slot: acquires the machine-wide lock that dd-slot.sh waits
# on, then waits for already-running DreamDaemons (held via dd-slot.sh) to
# drain, before running "$@". This is what `bench --exclusive` uses from
# inside tools/build/build.ts (BenchTarget calls the equivalent JS in
# lib/bench.ts directly -- acquireBenchExclusiveLock() /
# waitForDreamDaemonsToDrain()); this shell copy exists so a plain shell
# script (or another agent's ad hoc DreamDaemon run) can honour the same
# protocol without going through the TS tooling.
#
# The lock self-expires after 20 minutes even if its holder is still alive,
# so a stuck or killed exclusive run can't starve every other agent's builds
# and tests forever.
#
# Usage: dd-slot-exclusive.sh <command...>

SLOT_COUNT=${DQ_DD_SLOT_COUNT:-5}
DRAIN_TIMEOUT=${DQ_BENCH_DRAIN_TIMEOUT:-300} # 5 minutes
MAX_AGE=1200 # 20 minutes

default_base_parent() {
  if [ -n "$DQ_BENCH_STORE" ]; then
    dirname -- "$DQ_BENCH_STORE"
  else
    cd "$(dirname "$0")/../.." && pwd
  fi
}

SLOT_BASE=${DQ_DD_SLOT_BASE:-"$(default_base_parent)/.dq-dd-slot-"}
EXCLUSIVE=${DQ_BENCH_EXCLUSIVE_LOCK:-"${DQ_BENCH_STORE:-$(default_base_parent)/data/bench}/.dq-bench-exclusive"}

acquire() {
  while ! mkdir "$EXCLUSIVE" 2>/dev/null; do
    local p started now
    p=$(cat "$EXCLUSIVE/pid" 2>/dev/null)
    if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf "$EXCLUSIVE"; continue; fi
    started=$(cat "$EXCLUSIVE/started" 2>/dev/null)
    now=$(date +%s)
    if [ -n "$started" ] && [ $((now - started)) -gt "$MAX_AGE" ]; then rm -rf "$EXCLUSIVE"; continue; fi
    sleep 5
  done
  echo $$ > "$EXCLUSIVE/pid"
  date +%s > "$EXCLUSIVE/started"
  trap 'rm -rf "'"$EXCLUSIVE"'"' EXIT
}

drain() {
  echo "[dd-slot-exclusive] waiting for running DreamDaemons to drain..." >&2
  local deadline
  deadline=$(( $(date +%s) + DRAIN_TIMEOUT ))
  while :; do
    local busy=0
    for i in $(seq 1 "$SLOT_COUNT"); do
      d="${SLOT_BASE}${i}"
      if [ -d "$d" ]; then
        p=$(cat "$d/pid" 2>/dev/null)
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          busy=1
        else
          rm -rf "$d"
        fi
      fi
    done
    [ "$busy" -eq 0 ] && return 0
    if [ "$(date +%s)" -gt "$deadline" ]; then
      echo "[dd-slot-exclusive] timed out after ${DRAIN_TIMEOUT}s waiting for drain; proceeding under load" >&2
      return 1
    fi
    sleep 5
  done
}

acquire
drain
echo "[dd-slot-exclusive] running exclusive benchmark" >&2
"$@"; rc=$?
exit $rc
