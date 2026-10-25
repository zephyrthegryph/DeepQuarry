#!/usr/bin/env bash
# Tests the three limits on tools/dq_focused_test.sh against a fake world (no DM compile, no real DreamDaemon):
#   1. an exhaustive-tier test is refused (exit 3) unless --allow-exhaustive, and the refusal names its /representative;
#   2. the wall-clock cap: DQ_FOCUSED_MAX_MIN is clamped to 10 without --allow-exhaustive, and a run that passes the cap has its
#      DreamDaemon killed, its slot freed and "FOCUSED RUN CAPPED" printed;
#   3. no orphans: when the run's shell is killed, the world it started dies and the test-world slot a dead holder showed is freed.
# The fixture is a scratch git repo holding copies of the tools, a tiny unit-test tree and a fake tools/build/build.sh that starts
# a "dreamdaemon" (a copy of sleep) and holds a test_world slot like the real runner does.
#
#   bash tools/ci/test_focused_caps.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
cleanup() {
	[ -f "$T/dd.pid" ] && kill -9 "$(cat "$T/dd.pid")" 2>/dev/null
	rm -rf "$T"
}
trap cleanup EXIT

R="$T/repo"
mkdir -p "$R/tools/build" "$R/code" "$R/code/modules/unit_tests" "$T/bin" "$T/slots"
export DQ_FOCUSED_NO_TOOL_PREBUILD=1 # the fake tree has a stub build.sh; the prebuild is not what this test measures
for f in dq_focused_test.sh dq_test_tiers.sh dq_run_guard.js dq_machine_slots.sh dq_below_normal.sh; do cp "$ROOT/tools/$f" "$R/tools/$f"; done
# The fake world: a process whose image name matches the guard's pattern (dreamdaemon), sleeping.
SLEEP="$(command -v sleep)"
case "$SLEEP" in *.exe) cp "$SLEEP" "$T/bin/dreamdaemon.exe" ;; *) cp "$SLEEP" "$T/bin/dreamdaemon" 2>/dev/null || cp "$(readlink -f "$SLEEP")" "$T/bin/dreamdaemon" ;; esac
[ -e "$T/bin/dreamdaemon" ] || [ -e "$T/bin/dreamdaemon.exe" ] || { cp "$(readlink -f "$SLEEP")" "$T/bin/dreamdaemon.exe"; }

cat >"$R/deepquarry.dme" <<'EOF'
#include "code\t.dm"
EOF
: >"$R/code/modules/unit_tests/_unit_tests.dm"
cat >"$R/code/t.dm" <<'EOF'
/datum/unit_test/big_sweep
	tier = TEST_TIER_EXHAUSTIVE

/datum/unit_test/big_sweep/representative
	tier = TEST_TIER_NORMAL

/datum/unit_test/lone_sweep
	tier = TEST_TIER_EXHAUSTIVE

/datum/unit_test/parent_of_sweep

/datum/unit_test/parent_of_sweep/child
	tier = TEST_TIER_EXHAUSTIVE

/datum/unit_test/quick

/datum/unit_test/hang
EOF
cat >"$R/tools/build/build.sh" <<'EOF'
#!/usr/bin/env bash
# fake dm-test: FAKE_MODE=quick finishes at once, FAKE_MODE=hang starts a fake DreamDaemon that never exits.
echo "$*" >>"$FAKE_ROOT/build.calls"
sleep "${FAKE_QUEUE_SEC:-0}" # time spent queued for a slot, before the run holds one
. tools/dq_machine_slots.sh
slots_acquire test_world "fake world" >/dev/null 2>&1
trap 'slots_release' EXIT
if [ "${FAKE_MODE:-quick}" = hang ]; then
	PATH="$FAKE_BIN:$PATH" dreamdaemon 600 &
	echo $! >"$FAKE_ROOT/dd.pid"
	# what runDreamDaemonWithWatchdog() does for a real world
	wp="$(cat /proc/$!/winpid 2>/dev/null || echo $!)"
	mkdir -p "$DQ_WORLD_REGISTRY" && echo dreamdaemon >"$DQ_WORLD_REGISTRY/$wp"
	echo $$ >"$FAKE_ROOT/build.pid"
	wait $!
	exit 1
fi
echo "Unit-test summary: 1 passed, 0 failed, 0 skipped (saved data/test-runs/fake.json)"
EOF
chmod +x "$R/tools/build/build.sh"
git -C "$R" init -q 2>/dev/null
export FAKE_ROOT="$T" FAKE_BIN="$T/bin" DQ_SLOTS_DIR="$T/slots" DQ_SLOTS_TEST_WORLD=2 DQ_SLOTS_POLL_SEC=1 DQ_SLOTS_HEARTBEAT_SEC=1 DQ_PRIORITY=normal DQ_FOCUS_SPLIT=0
focused() { (cd "$R" && bash tools/dq_focused_test.sh "$@"); }
slot_dirs() { ls -d "$T"/slots/test_world/slot.* 2>/dev/null | wc -l; }
alive() { kill -0 "$1" 2>/dev/null; }

# ---- 1. the tier refusal ----------------------------------------------------------------------------------------------------
: >"$T/build.calls"
out="$(focused big_sweep 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "an exhaustive test is refused (exit 3)" || fail "big_sweep: expected exit 3, got $rc: $out"
echo "$out" | grep -q "big_sweep/representative" && ok "the refusal names the /representative" || fail "no representative named: $out"
out="$(focused lone_sweep 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && echo "$out" | grep -q "no /representative" && ok "an exhaustive test with no representative is refused and says so" || fail "lone_sweep: $rc $out"
out="$(focused parent_of_sweep 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && echo "$out" | grep -q "parent_of_sweep/child" && ok "a test with an exhaustive subtype is refused" || fail "parent_of_sweep: $rc $out"
[ ! -s "$T/build.calls" ] && ok "a refusal compiles and starts nothing" || fail "the fake build ran: $(cat "$T/build.calls")"
out="$(FAKE_MODE=quick focused big_sweep/representative 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "FOCUSED RESULT: 1 passed" && ok "the /representative itself runs" || fail "representative: $rc $out"
out="$(FAKE_MODE=quick focused --force --allow-exhaustive lone_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--allow-exhaustive lets an exhaustive test through" || fail "--allow-exhaustive: $rc $out"
grep -q -- "allow-exhaustive" "$T/build.calls" && fail "--allow-exhaustive leaked into the dm-test arguments" || ok "--allow-exhaustive is not passed to dm-test"
out="$(FAKE_MODE=quick focused quick 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "an ordinary test runs" || fail "quick: $rc $out"

# ---- 2a. the cap setting ----------------------------------------------------------------------------------------------------
eval "$(sed -n '/^focused_cap_minutes() {/,/^}/p' "$ROOT/tools/dq_focused_test.sh")"
[ "$(unset DQ_FOCUSED_MAX_MIN; focused_cap_minutes 0 2>/dev/null)" = 10 ] && ok "the default cap is 10 minutes" || fail "default cap"
[ "$(DQ_FOCUSED_MAX_MIN=5 focused_cap_minutes 0 2>/dev/null)" = 5 ] && ok "DQ_FOCUSED_MAX_MIN lowers the cap" || fail "lowered cap"
[ "$(DQ_FOCUSED_MAX_MIN=45 focused_cap_minutes 0 2>/dev/null)" = 10 ] && ok "a cap above 10 is clamped to 10 without --allow-exhaustive" || fail "clamp"
[ "$(DQ_FOCUSED_MAX_MIN=45 focused_cap_minutes 1 2>/dev/null)" = 45 ] && ok "--allow-exhaustive lifts the clamp" || fail "unclamped"
[ "$(DQ_FOCUSED_MAX_MIN=abc focused_cap_minutes 0 2>/dev/null)" = 10 ] && ok "a bad value falls back to 10" || fail "bad value"

# The gate cap: DQ_GATE_FOCUSED_MAX_MIN replaces the agent cap and its clamp, with a firm ceiling of 10; a bad value is ignored.
[ "$(DQ_GATE_FOCUSED_MAX_MIN=7 focused_cap_minutes 0 2>/dev/null)" = 7 ] && ok "the gate cap sets its own value" || fail "gate cap 50"
[ "$(DQ_GATE_FOCUSED_MAX_MIN=90 focused_cap_minutes 0 2>/dev/null)" = 10 ] && ok "the gate cap has a ceiling of 10" || fail "gate ceiling"
[ "$(DQ_GATE_FOCUSED_MAX_MIN=x DQ_FOCUSED_MAX_MIN=45 focused_cap_minutes 0 2>/dev/null)" = 10 ] && ok "a bad gate cap is ignored" || fail "bad gate cap"
. "$ROOT/tools/dq_gate_retry.sh"
[ "$(gate_cap_minutes 0)" = 5 ] && [ "$(gate_cap_minutes 3)" = 8 ] && [ "$(gate_cap_minutes 47)" = 10 ] && [ "$(gate_cap_minutes 500)" = 10 ] && ok "gate_cap_minutes: 5 + 1 per test, ceiling 10" || fail "gate_cap_minutes"
out="$(FAKE_MODE=quick DQ_GATE_FOCUSED_MAX_MIN=9 focused --force quick 2>&1)"
echo "$out" | grep -q "hard cap 9 min" && ok "a focused run under the gate variable reports the gate cap" || fail "gate cap not applied: $out"
out="$(FAKE_MODE=quick DQ_GATE_FOCUSED_MAX_MIN=9 focused --force big_sweep 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "the gate cap does not lift the exhaustive refusal" || fail "exhaustive under gate cap: $rc"

# ---- 2b. the cap kills the world --------------------------------------------------------------------------------------------
rm -f "$T/dd.pid"
start=$(date +%s)
out="$(FAKE_MODE=hang DQ_FOCUSED_MAX_SEC=8 DQ_FOCUSED_GUARD_POLL_MS=1000 timeout 120 bash -c "cd '$R' && bash tools/dq_focused_test.sh hang" 2>&1)"; rc=$?
took=$(( $(date +%s) - start ))
dd_pid="$(cat "$T/dd.pid" 2>/dev/null)"
if [ "$rc" -ne 124 ] && [ "$rc" -ne 0 ] && [ "$took" -lt 100 ]; then ok "a run past the cap ends by itself (${took}s, exit $rc)"; else fail "the capped run did not end: rc=$rc took=${took}s: $out"; fi
echo "$out" | grep -q "FOCUSED RUN CAPPED" && ok "the cap is reported" || fail "no CAPPED line: $out"
[ -n "$dd_pid" ] && ! alive "$dd_pid" && ok "the cap killed the DreamDaemon" || fail "the fake DreamDaemon ($dd_pid) is still running"
sleep 2
[ "$(slot_dirs)" -eq 0 ] && ok "the cap freed the test_world slot" || fail "a slot is still held: $(ls "$T"/slots/test_world 2>&1)"

# ---- 2c. queue time is not run time --------------------------------------------------------------------------------------
out="$(FAKE_MODE=quick FAKE_QUEUE_SEC=14 DQ_FOCUSED_MAX_SEC=8 DQ_FOCUSED_GUARD_POLL_MS=1000 timeout 200 bash -c "cd '$R' && bash tools/dq_focused_test.sh --force quick" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a run that queued longer than the cap is not capped" || fail "queue time counted against the cap: $rc $out"
echo "$out" | grep -q "FOCUSED RUN TIME: queued" && ok "queue time is reported separately" || fail "no queued line: $out"

# ---- 3. no orphans when the shell dies --------------------------------------------------------------------------------------
rm -f "$T/dd.pid" "$T/build.pid"
cd "$R" || exit 1
FAKE_MODE=hang DQ_FOCUSED_GUARD_POLL_MS=1000 bash tools/dq_focused_test.sh hang >"$T/orphan.out" 2>&1 &
shell_pid=$!
cd "$ROOT" || exit 1
for _ in $(seq 1 60); do [ -s "$T/dd.pid" ] && [ -s "$T/build.pid" ] && break; sleep 1; done
dd_pid="$(cat "$T/dd.pid" 2>/dev/null)"
if [ -z "$dd_pid" ] || ! alive "$dd_pid"; then
	fail "the fake world did not start: $(cat "$T/orphan.out")"
else
	sleep 3 # let the guard record the world
	# What a stopped task does: the shell and the runner die at once, the world (its own process) is left behind.
	kill -9 "$(cat "$T/build.pid")" 2>/dev/null
	kill -9 "$shell_pid" 2>/dev/null
	alive "$dd_pid" && ok "setup: the world outlived its shell" || fail "setup: the world died with the shell, so the test proves nothing"
	for _ in $(seq 1 30); do alive "$dd_pid" || break; sleep 1; done
	alive "$dd_pid" && fail "the orphaned DreamDaemon is still running 30 s after its shell died" || ok "an orphaned DreamDaemon is killed when its shell dies"
	for _ in $(seq 1 15); do [ "$(slot_dirs)" -eq 0 ] && break; sleep 1; done
	[ "$(slot_dirs)" -eq 0 ] && ok "the dead run's test_world slot is freed" || fail "a dead holder's slot is still there: $(cat "$T"/slots/test_world/slot.*/owner 2>&1)"
fi

[ "$fails" -eq 0 ] && { echo "test_focused_caps: ok"; exit 0; }
echo "test_focused_caps: $fails FAILED"
exit 1
