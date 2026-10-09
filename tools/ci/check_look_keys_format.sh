#!/usr/bin/env bash
# look_keys.txt has one format: the analyzer's plan, three tab-separated columns (type, key, probes) per line.
# dq_focused_test.sh copies the plan verbatim after a passing run; this guards the committed file against a two-column rewrite.
set -euo pipefail
f="${1:-code/modules/unit_tests/snapshots/look_keys.txt}"
bad="$(awk -F'\t' 'NF != 3 { n++ } END { print n + 0 }' "$f")"
if [ "$bad" -ne 0 ]; then
	echo "check_look_keys_format: $bad line(s) in $f do not have exactly 3 tab-separated columns" >&2
	exit 1
fi
