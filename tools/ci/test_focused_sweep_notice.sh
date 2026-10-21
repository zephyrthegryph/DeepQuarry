#!/usr/bin/env bash
# Test for sweep_notice() in tools/dq_focused_test.sh: a clamped sweep run says how many shards it got, why each slice is longer, and the watchdog.
#   bash tools/ci/test_focused_sweep_notice.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
eval "$(sed -n '/^sweep_notice() {/,/^}/p' "$ROOT/tools/dq_focused_test.sh")"
out="$(sweep_notice dq_loot_roll_pin 4 2 2 45)"
grep -q "2 shard world" <<<"$out" && grep -q "4 were asked for" <<<"$out" && grep -q "2 test-world slot" <<<"$out" && grep -q "4/2 times longer" <<<"$out" && grep -q "watchdog 45 min" <<<"$out" \
	&& ok "a clamped run explains itself" || fail "clamped notice: $out"
out="$(sweep_notice dq_loot_roll_pin 4 4 8 45)"
grep -q "asked for" <<<"$out" && fail "an unclamped run should not mention a clamp: $out" || ok "an unclamped run is one plain line"
grep -q 'sweep_notice "' "$ROOT/tools/dq_focused_test.sh" && ok "the run prints it" || fail "sweep_notice is never called"
[ "$fails" -eq 0 ] && echo "test_focused_sweep_notice: all passed" || { echo "test_focused_sweep_notice: FAILED"; exit 1; }
