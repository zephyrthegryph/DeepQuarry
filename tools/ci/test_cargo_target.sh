#!/usr/bin/env bash
# The gate/prebuild cargo targets live under the cache root, per worktree and name, never inside the checkout.
set -u
cd "$(git rev-parse --show-toplevel)"
t="$(DQ_CARGO_TARGETS=/cache-root bash tools/dq_cargo_target.sh analyze)"
[ "$t" = "/cache-root/$(basename "$PWD")/analyze" ] || { echo "FAIL: $t"; exit 1; }
case "$(bash tools/dq_cargo_target.sh x)" in "$PWD"/*) echo "FAIL: target inside the worktree"; exit 1 ;; esac
for f in tools/dq_light_checks.sh tools/dq_merge_gates.sh tools/dq_push_master.sh tools/dq_prebuild_tools.sh tools/ci/dm_equiv.sh tools/ci/move_equiv.sh; do
	grep -q dq_cargo_target.sh "$f" || { echo "FAIL: $f builds into the worktree's target"; exit 1; }
done
echo "ok"
