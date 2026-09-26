#!/usr/bin/env bash
# Run only the named unit tests. Works on Linux and in Git Bash on Windows.
#
#   bash tools/dq_focused_test.sh /datum/unit_test/dq_expedition_generates_site [...]
#   bash tools/dq_focused_test.sh --full-map /datum/unit_test/...   # boot Southern Cross instead of the test map
#
# The test names go to the unit-test world as `dm-test --focus=...` (the
# test-focus world param); no source file is edited, so concurrent runs and
# other agents can't clear or add to this run's focus, and every focus set
# reuses the same compiled .dmb. Each run gets its own .dmb copy, port, log
# directory and results file (data/runs/runN), and is killed after
# DQ_FOCUS_TIMEOUT_MINUTES (default 15) with the last log lines printed.
set -euo pipefail

cd "$(dirname "$0")/.."

args=()
tests=()
for arg in "$@"; do
	case "$arg" in
		--full-map) args+=("-DCITESTING_FULL_MAP") ;;
		/datum/unit_test/*) tests+=("$arg") ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done
if [ ${#tests[@]} -eq 0 ]; then
	echo "usage: $0 [--full-map] /datum/unit_test/<name> [...]" >&2
	exit 2
fi
# Short names (no leading slash): Git Bash would rewrite "/datum/..." into a
# Windows path on its way to cmd.exe. dm-test adds the /datum/unit_test/ prefix back.
short=("${tests[@]#/datum/unit_test/}")
focus="$(IFS=,; echo "${short[*]}")"
echo "Focused on: ${tests[*]}"

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) cmd //c "tools\build\build.bat" dm-test "--focus=$focus" "${args[@]}" ;;
	*) tools/build/build.sh dm-test "--focus=$focus" "${args[@]}" ;;
esac
