#!/usr/bin/env bash
# Checks that the permanent test-server worktree cannot be removed by cleanup: `dq_worktree.sh gc` names it in its built-in keep list,
# and no pool or cache script deletes anything under a non-pool worktree. Also checks the launcher refuses a dirty tree and never uses
# a destructive git form.
#   bash tools/ci/test_test_server_folder.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
grep -qE 'case " play merge-base train-base test-server ' "$ROOT/tools/dq_worktree.sh" && ok "gc keeps test-server by default" || fail "gc does not name test-server in its default keep list"
grep -qE 'pool-\[0-9\]\*\) continue' "$ROOT/tools/dq_worktree.sh" && ok "gc skips pool slots itself" || fail "gc pool-slot skip missing"
if grep -nE 'test-server' "$ROOT/tools/dq_lane_pool.sh" "$ROOT/tools/dq_cache_prune.sh" | grep -vE '^[^:]*:[0-9]+:\s*#' | grep -E 'rm |remove|clean'; then fail "a pool or prune script handles test-server destructively"; else ok "pool and prune scripts never delete test-server"; fi
if grep -nE 'git[^#]* (reset|checkout|stash|restore|clean|cherry-pick)\b|rm -rf' "$ROOT/tools/dq_test_server.sh" | grep -vE '^[0-9]+:\s*#'; then fail "dq_test_server.sh uses a destructive form"; else ok "launcher uses no destructive git form"; fi
grep -q 'merge --ff-only origin/master' "$ROOT/tools/dq_test_server.sh" && ok "launcher fast-forwards only" || fail "launcher does not fast-forward only"
# Dirty refusal, against a scratch repo that stands in for the worktree (no server is started: the refusal comes first).
T="$(cygpath -m "$(mktemp -d)")"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q && git -C "$T" -c user.email=a@b -c user.name=t commit -q --allow-empty -m x && echo dirty > "$T/f"
out="$(cd "$ROOT" && DQ_TEST_SERVER_DIR="$T" bash tools/dq_test_server.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "uncommitted changes" && ok "launcher refuses a dirty worktree" || fail "launcher did not refuse a dirty worktree (rc=$rc)"
[ "$fails" -eq 0 ] && { echo "test_test_server_folder: ok"; exit 0; }
echo "test_test_server_folder: $fails FAILED"; exit 1
