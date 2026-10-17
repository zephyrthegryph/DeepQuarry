#!/usr/bin/env bash
# The machine's flake ledger: what the merge gates retried and passed (tools/dq_gate_retry.sh).
#
#   bash tools/dq_flake_log.sh [N]      # the last N rows (default 30): time, kind (flake | infra), gate sha, lanes, tests, first error
#   bash tools/dq_flake_log.sh --count  # tests that flaked, with how often, most frequent first (the fix-lane list)
#
# A flake is a test that failed in a gate and passed alone right after; an infra row is a world that never produced a result
# (compiler daemon, watchdog, shared binary). Every test in the --count list needs a fix lane; nothing here edits the tree.
set -uo pipefail
cd "$(dirname "$0")/.."
. tools/dq_gate_retry.sh
ledger="$(flake_ledger)"
[ -f "$ledger" ] || { echo "no flakes recorded ($ledger)"; exit 0; }
if [ "${1:-}" = "--count" ]; then
	awk -F'\t' '$2 == "flake" { n = split($5, a, " "); for (i = 1; i <= n; i++) c[a[i]]++ } END { for (t in c) printf "%d\t%s\n", c[t], t }' "$ledger" | sort -rn
	exit 0
fi
tail -n "${1:-30}" "$ledger"
