#!/usr/bin/env bash
# Run only the named unit tests. Works on Linux and in Git Bash on Windows.
#
#   bash tools/dq_focused_test.sh /datum/unit_test/dq_expedition_generates_site [...]
#   bash tools/dq_focused_test.sh --full-map /datum/unit_test/...   # boot Southern Cross instead of the test map
#
# The script adds TEST_FOCUS(...) lines to code/modules/unit_tests/dq_focus.dm,
# runs the normal unit-test build (the dm-test target), and restores the focus
# file afterwards, even if the run fails. CI refuses a committed focus line.
set -euo pipefail

cd "$(dirname "$0")/.."
FOCUS_FILE="code/modules/unit_tests/dq_focus.dm"

defines=()
tests=()
for arg in "$@"; do
	case "$arg" in
		--full-map) defines+=("-DCITESTING_FULL_MAP") ;;
		/datum/unit_test/*) tests+=("$arg") ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done
if [ ${#tests[@]} -eq 0 ]; then
	echo "usage: $0 [--full-map] /datum/unit_test/<name> [...]" >&2
	exit 2
fi

backup="$(mktemp)"
cp "$FOCUS_FILE" "$backup"
restore() { cp "$backup" "$FOCUS_FILE"; rm -f "$backup"; }
trap restore EXIT

for t in "${tests[@]}"; do
	echo "TEST_FOCUS($t)" >> "$FOCUS_FILE"
done
echo "Focused on: ${tests[*]}"

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) cmd //c "tools\build\build.bat" dm-test "${defines[@]}" ;;
	*) tools/build/build.sh dm-test "${defines[@]}" ;;
esac
