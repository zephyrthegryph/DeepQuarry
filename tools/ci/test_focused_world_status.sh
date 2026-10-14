#!/usr/bin/env bash
# Reproduction/test for the "world 0 exited 127" bug in tools/dq_focused_test.sh: a world that printed every test and exited 0 was counted
# as 127 because `wait` could not find the child. world_status() now takes the world's own recorded exit status (<log>.rc) and only falls
# back to wait. This extracts the function from the script and drives it with a child bash has no record of (a pid that is not its
# child makes `wait` return 127 exactly as in the failing run).
#
#   bash tools/ci/test_focused_world_status.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

eval "$(sed -n '/^world_status() {/,/^}/p' "$ROOT/tools/dq_focused_test.sh")"
W_LABEL=(main)
W_LOG=("$T/w0.log")
: >"$T/w0.log"

# 1. not our child (wait returns 127), the world recorded exit 0: the record wins, the disagreement is printed, status 0.
sleep 1 &
foreign=$!
( sleep 0.2 ) & disown
W_PID=(99999)
echo 0 >"$T/w0.log.rc"
out="$(world_status 0 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "recorded exit 0 beats wait's 127" || fail "expected 0, got $rc"
echo "$out" | grep -q "wait returned 127 but the world recorded exit 0" && ok "the disagreement is printed" || fail "no disagreement line: $out"

# 2. the world recorded a real failure: it is reported, not masked.
echo 3 >"$T/w0.log.rc"
world_status 0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "recorded exit 3 is reported" || fail "expected 3, got $rc"

# 3. no record and no such child: counted as failed (125) with the log named, never silently 0.
rm -f "$T/w0.log.rc"
out="$(world_status 0 2>&1)"; rc=$?
[ "$rc" -eq 125 ] && echo "$out" | grep -q "left no exit record" && ok "127 without a record is an unclean world" || fail "expected 125 + message, got $rc: $out"

# 4. the normal path: a real child, record written by the same wrapper the script uses.
( ( exit 0 ); echo $? >"$T/w0.log.rc.tmp" && mv -f "$T/w0.log.rc.tmp" "$T/w0.log.rc" ) &
W_PID=($!)
world_status 0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "a normal world exits 0" || fail "expected 0, got $rc"
wait "$foreign" 2>/dev/null

[ "$fails" -eq 0 ] && { echo "test_focused_world_status: ok"; exit 0; }
echo "test_focused_world_status: $fails FAILED"
exit 1
