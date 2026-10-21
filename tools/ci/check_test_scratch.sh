#!/usr/bin/env bash
# Rust tests under tools/dmb must not build scratch directories under E:/dq-cache by hand: they take them from the shared per-process root in
# tools/dmb/shared/test_scratch.rs (`crate::test_scratch::root()` / `dir(label)`), which deletes itself when the test process exits.
# Fixed paths that are only compared as strings, and the daemon's own default roots, are listed here.
set -uo pipefail
cd "$(dirname "$0")/../.."
allow='dmb-bin|session-output-fixture|worktree-specific-cache|unused-resident-map-fixture|dmbd/cache|dmbd/publication-leases|dmb-daemon|dmb-native-v2\)|^[^:]*:[0-9]+:\s*//'
hits="$(grep -rnE 'E:/dq-cache' tools/dmb/crates tools/dmb/src --include=*.rs 2>/dev/null | grep -vE "$allow" | grep -vE 'daemon/resident\.rs' || true)"
if [ -n "$hits" ]; then
	echo "check_test_scratch: scratch under E:/dq-cache outside the shared guard (use crate::test_scratch::root() or dir()):"
	echo "$hits"
	exit 1
fi
echo "check_test_scratch: ok"
