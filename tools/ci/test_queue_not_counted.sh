#!/usr/bin/env bash
# Self-test: time spent queued for a machine slot after a run started does not count against its wall-clock cap
# (tools/dq_run_guard.js), and a focused run killed before it printed gets a clear CAPPED result line (tools/dq_gate_retry.sh).
#
#   bash tools/ci/test_queue_not_counted.sh      # PASS/FAIL per case, exit 1 on any failure
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

sleep 120 & sleeper=$!
wp="$(cat "/proc/$sleeper/winpid" 2>/dev/null || echo "$sleeper")"
reg="$tmp/reg"; mkdir -p "$reg"
date +%s >"$reg/.running"                 # the run started (it holds a compile slot) ...
echo "$(date +%s)" >"$reg/.waiting.$wp"   # ... and now queues for a test world
node "$here/tools/dq_run_guard.js" --root "$wp" --cap-s 3 --queue-max-s 600 --registry "$reg" --marker "$tmp/marker" --poll-ms 200 --root-grace-s 60 >"$tmp/guard.log" 2>&1 &
guard=$!
sleep 7
check "a run waiting in a queue is not capped after 7 s on a 3 s cap" '[ ! -f "$tmp/marker" ]'
rm -f "$reg/.waiting.$wp"                 # the slot was granted
sleep 6
check "once the wait ends the remaining cap applies and the run is capped" '[ -f "$tmp/marker" ] && head -n 1 "$tmp/marker" | grep -qx capped && grep -q "^paused_s=[1-9]" "$tmp/marker"'
kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null

# the queue ceiling still bounds the waiting
reg2="$tmp/reg2"; mkdir -p "$reg2"; date +%s >"$reg2/.running"; echo "$(date +%s)" >"$reg2/.waiting.$wp"
node "$here/tools/dq_run_guard.js" --root "$wp" --cap-s 600 --queue-max-s 2 --registry "$reg2" --marker "$tmp/marker2" --poll-ms 200 --root-grace-s 60 >"$tmp/guard2.log" 2>&1 &
guard=$!
sleep 6
check "queueing past --queue-max-s stops the run with a queue-ceiling marker" '[ -f "$tmp/marker2" ] && head -n 1 "$tmp/marker2" | grep -qx queue-ceiling'
kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null

# the slot library marks and clears the waiting file
out="$( export DQ_SLOTS_DIR="$tmp/slots" DQ_WORLD_REGISTRY="$tmp/reg3" DQ_SLOTS_CARGO=1 DQ_SLOT_WORKTREE=/x/pool-9 DQ_SLOTS_POLL_SEC=1 DQ_SLOTS_HEARTBEAT_SEC=1
	. "$here/tools/dq_machine_slots.sh"
	slots_acquire cargo holder >/dev/null
	( slots_acquire cargo waiter >/dev/null 2>&1; slots_release ) >/dev/null 2>&1 </dev/null &
	w=$!
	for _ in $(seq 1 40); do ls -a "$DQ_WORLD_REGISTRY" 2>/dev/null | grep -q '^\.waiting\.' && break; sleep 1; done; ls -a "$DQ_WORLD_REGISTRY" | grep -c '^\.waiting\.'; slots_release; wait "$w"; ls -a "$DQ_WORLD_REGISTRY" | grep -c '^\.waiting\.' )"
check "a queued waiter writes .waiting.<pid> and every one is gone after release" '[ "$(echo "$out" | head -n 1)" -ge 1 ] && [ "$(echo "$out" | tail -n 1)" = 0 ]'

# a result-less log gets a CAPPED line
. "$here/tools/dq_gate_retry.sh"
printf 'some output\n' >"$tmp/nolog"
line="$(gate_ensure_result "$tmp/nolog" 143)"
check "a log without a FOCUSED RESULT line gets a clear CAPPED one" 'grep -q "^FOCUSED RESULT: CAPPED" <<<"$line" && grep -q "^FOCUSED RESULT: CAPPED" "$tmp/nolog"'
printf 'FOCUSED RESULT: 3 passed, 0 failed\n' >"$tmp/oklog"
check "a log that has a result is left alone" '[ -z "$(gate_ensure_result "$tmp/oklog" 0)" ] && [ "$(wc -l <"$tmp/oklog")" -eq 1 ]'

[ "$fail" -eq 0 ] && echo "test_queue_not_counted: all passed" || echo "test_queue_not_counted: FAILED"
exit "$fail"
