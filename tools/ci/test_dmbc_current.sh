#!/usr/bin/env bash
# Self-test of the shared compiler pointer rule (tools/build/lib/dmbc_cache.ts mayAdvanceCurrent / publishableCommit): the normal
# case, a current behind master, a dead current (on no branch), and a current ahead on an unmerged branch. The cases are the
# 'current stays on master' and 'current moves forward only' groups of tools/build/lib/dmbc_cache.test.ts, run on scratch repos.
#
#   bash tools/ci/test_dmbc_current.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here/tools/build" || exit 1
bun test lib/dmbc_cache.test.ts lib/dmbc_prewarm.test.ts || { echo "test_dmbc_current: FAILED"; exit 1; }
echo "test_dmbc_current: ok"
