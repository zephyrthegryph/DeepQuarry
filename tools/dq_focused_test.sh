#!/usr/bin/env bash
# Focused unit-test run helper for the build VM.
#
# Usage (on the VM, from ~/DeepQuarry):
#   bash tools/dq_focused_test.sh /datum/unit_test/dq_expedition_generates_site [more paths...]
#   DQ_MAP=minitest bash tools/dq_focused_test.sh /datum/unit_test/...   # tiny map: boots in seconds
#
# Appends TEST_FOCUS lines to code/modules/unit_tests/dq_focus.dm (scratch
# file, empty in git), runs the normal build+test script, then empties the
# focus file again so the next sync/run is a full suite unless re-focused.
# DQ_MAP=minitest builds with -DCITESTING (virgo_minitest) instead of Southern
# Cross — use it for everything except map-specific tests; iteration is ~4x
# faster (boot seconds instead of ~3 minutes, expedition z-levels are tiny).
set -euo pipefail

FOCUS_FILE="code/modules/unit_tests/dq_focus.dm"
[ -f "$FOCUS_FILE" ] || { echo "run from the repo root (missing $FOCUS_FILE)"; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 /datum/unit_test/<name> [...]"; exit 1; }

# Slaughter any of OUR stale test daemons first — DreamDaemon routinely hangs
# after "Shutdown complete" instead of exiting, and a 90%-CPU zombie halves
# every subsequent run on this small VM. (Never touches other users' daemons.)
STALE=$(ps -u "$(id -un)" -o pid=,cmd= | awk '/deepquarry\.dmb -close/ && !/awk/ {print $1}')
if [ -n "$STALE" ]; then
    echo "Killing stale test DreamDaemon(s): $STALE"
    kill -9 $STALE || true
    sleep 1
    ps -u "$(id -un)" -o pid=,cmd= | grep "deepquarry.dmb -close" | grep -v grep && { echo "stale daemon survived kill!"; exit 1; } || true
fi

cleanup() { git checkout -- "$FOCUS_FILE" 2>/dev/null || sed -i '/^TEST_FOCUS/d' "$FOCUS_FILE"; }
trap cleanup EXIT

for t in "$@"; do
    echo "TEST_FOCUS($t)" >> "$FOCUS_FILE"
done
echo "Focused on: $*"

bash ~/dq-native.sh
