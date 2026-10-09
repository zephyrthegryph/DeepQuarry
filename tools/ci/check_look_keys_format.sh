#!/usr/bin/env bash
# look_keys.txt has one format: the analyzer's plan, three tab-separated columns (type, key, probes) per line, and it is a pure
# function of the tree: `analyze look-keys` output, byte for byte. This guards both.
#
#   bash tools/ci/check_look_keys_format.sh            # format + currency check (fails when the committed file is stale)
#   bash tools/ci/check_look_keys_format.sh --regen    # rewrite the committed file from the tree (needs `analyze gen` output)
#   bash tools/ci/check_look_keys_format.sh --commit   # --regen, then commit the file if it changed (merge scripts use this)
#
# dq_focused_test.sh copies the plan verbatim after a passing run; a merge that changes code without regenerating leaves the
# file stale, so the next lane would rewrite everything. DQ_LOOK_KEYS_FILE overrides the path (tests).
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="check"
case "${1:-}" in
	--regen) mode="regen"; shift ;;
	--commit) mode="commit"; shift ;;
esac
f="${1:-${DQ_LOOK_KEYS_FILE:-code/modules/unit_tests/snapshots/look_keys.txt}}"

plan() { # <out>: write the current plan
	local bin
	bin="$(bash tools/ci/analyze.sh)" || { echo "check_look_keys_format: the analyze engine could not be built" >&2; return 1; }
	"$bin" look-keys --out "$1" >/dev/null || { echo "check_look_keys_format: analyze look-keys failed" >&2; return 1; }
	[ -s "$1" ] || { echo "check_look_keys_format: analyze look-keys wrote an empty plan" >&2; return 1; }
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [ "$mode" != "check" ]; then
	plan "$tmp" || exit 1
	if cmp -s "$tmp" "$f"; then
		echo "check_look_keys_format: $f already current"
		exit 0
	fi
	cp "$tmp" "$f"
	echo "check_look_keys_format: regenerated $f"
	if [ "$mode" = "commit" ]; then
		git add -- "$f"
		git commit -q -m "Regenerate look_keys.txt for the merged tree" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "$f"
	fi
	exit 0
fi

bad="$(awk -F'\t' 'NF != 3 { n++ } END { print n + 0 }' "$f")"
if [ "$bad" -ne 0 ]; then
	echo "check_look_keys_format: $bad line(s) in $f do not have exactly 3 tab-separated columns" >&2
	exit 1
fi
plan "$tmp" || exit 1
if ! cmp -s "$tmp" "$f"; then
	echo "check_look_keys_format: $f is stale (differs from \`analyze look-keys\`); fix: bash tools/ci/check_look_keys_format.sh --regen && git add $f" >&2
	exit 1
fi
