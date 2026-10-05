#!/usr/bin/env bash
# Run only the named unit tests. Works on Linux and in Git Bash on Windows.
#
#   bash tools/dq_focused_test.sh dq_expedition_generates_site [...]      # bare name
#   bash tools/dq_focused_test.sh /datum/unit_test/dq_expedition_generates_site
#   bash tools/dq_focused_test.sh 'dq_expedition_*'                        # glob over the test types (quote it)
#   bash tools/dq_focused_test.sh --repeat=5 belly_damage                  # run it 5 times, report each
#   bash tools/dq_focused_test.sh --full-map /datum/unit_test/...          # boot Southern Cross instead of the test map
#   bash tools/dq_focused_test.sh --some-flag=x name                       # any other --flag goes to dm-test
#   bash tools/dq_focused_test.sh --profile-tests name                     # per-test proc profile (data/logs/runN/profile/)
#   bash tools/dq_focused_test.sh --boot                                   # boot only: fails on any boot runtime or warning
#   bash tools/dq_focused_test.sh --bless dq_conversion_pin                # snapshot tests rewrite their recorded rows (doc/rewrite/snapshot_pins.md)
#
# Every run fails when the world logged a runtime or a warning before its first test (the boot gate,
# doc/rewrite/boot_gate.md); the build prints "BOOT GATE" with the first warnings when it trips.
#
# A named test runs whatever its tier: an exhaustive sweep (tier =
# TEST_TIER_EXHAUSTIVE, normally only in CI via dm-test --tier=all) runs here
# by name like any other test.
#
# A name without a leading slash gets /datum/unit_test/ prepended. A name
# containing * ? or [ is matched against every /datum/unit_test type defined
# under code/ and expands to all matches (it fails if nothing matches).
#
# --list prints the expansion (one /datum/unit_test name per line) and exits
# without compiling or running; use it to check a glob.
#
# The test names go to the unit-test world as `dm-test --focus=...` (the
# test-focus world param); no source file is edited, so concurrent runs and
# other agents can't clear or add to this run's focus, and every focus set
# reuses the same compiled .dmb. Each run gets its own .dmb copy, port, log
# directory and results file (data/runs/runN), and is killed after
# DQ_FOCUS_TIMEOUT_MINUTES (default 15) with the last log lines printed.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
	echo "usage: $0 [--full-map] [--repeat=N] [--<dm-test flag>...] <test name | /datum/unit_test/path | 'glob*'> [...]" >&2
	exit 2
}

# Every /datum/unit_test type defined in code/, without the prefix (one per line).
test_types() {
	# git grep reads the worktree in-process (about 0.5 s); a recursive grep over
	# code/ takes minutes on Windows. --untracked picks up new files. One awk
	# pass strips the prefix and dedupes.
	{
		git grep -h -o -E --untracked '^/datum/unit_test/[A-Za-z0-9_/]+[[:space:]]*$' -- 'code/*.dm' 2>/dev/null \
			|| grep -rhoE '^/datum/unit_test/[A-Za-z0-9_/]+[[:space:]]*$' code --include='*.dm'
	} | awk '{ sub(/^\/datum\/unit_test\//, ""); sub(/[[:space:]]+$/, ""); if (!seen[$0]++) print }'
}

args=()
tests=()
repeat=1
list_only=0
all_types=""
for arg in "$@"; do
	case "$arg" in
		--full-map) args+=("-DCITESTING_FULL_MAP") ;;
		--repeat=*)
			repeat="${arg#--repeat=}"
			[[ "$repeat" =~ ^[1-9][0-9]*$ ]] || { echo "--repeat needs a positive integer, got '$repeat'" >&2; exit 2; }
			;;
		--list) list_only=1 ;;
		--boot) tests+=("dq_boot_gate") ;;
		--bless) export DQ_SNAPSHOT_BLESS=1 ;;
		-h|--help) usage ;;
		--*) args+=("$arg") ;;
		-*) echo "unknown argument: $arg" >&2; usage ;;
		*)
			name="${arg#/datum/unit_test/}"
			if [[ "$name" == /* ]]; then
				echo "not a unit test path: $arg" >&2
				exit 2
			fi
			if [[ "$name" == *[*?[]* ]]; then
				[ -n "$all_types" ] || all_types="$(test_types)"
				matched=0
				while IFS= read -r type; do
					# shellcheck disable=SC2053  # $name is deliberately a glob
					if [[ -n "$type" && "$type" == $name ]]; then
						tests+=("$type")
						matched=1
					fi
				done <<<"$all_types"
				if [ "$matched" -eq 0 ]; then
					echo "no /datum/unit_test type matches '$arg'" >&2
					exit 2
				fi
			else
				tests+=("$name")
			fi
			;;
	esac
done
[ ${#tests[@]} -gt 0 ] || usage
if [ "$list_only" -eq 1 ]; then
	printf '%s
' "${tests[@]}"
	exit 0
fi

# Short names (no leading slash): Git Bash would rewrite "/datum/..." into a
# Windows path on its way to cmd.exe. dm-test adds the /datum/unit_test/ prefix back.
focus="$(IFS=,; echo "${tests[*]}")"
if [ ${#tests[@]} -gt 20 ]; then
	echo "Focused on (${#tests[@]}): ${tests[*]:0:20} ..."
else
	echo "Focused on (${#tests[@]}): $focus"
fi
# A long list goes through a file (--focus=@file): a Windows command line stops at 8191 characters.
if [ ${#focus} -gt 1500 ]; then
	mkdir -p data/focus-lists
	focus_file="data/focus-lists/focus.$$.txt"
	printf '%s\n' "${tests[@]}" >"$focus_file"
	trap 'rm -f "$focus_file"' EXIT
	focus="@$focus_file"
fi

run_once() {
	case "$(uname -s)" in
		MINGW*|MSYS*|CYGWIN*) cmd //c "tools\build\build.bat" dm-test "--focus=$focus" ${args[@]+"${args[@]}"} ;;
		*) tools/build/build.sh dm-test "--focus=$focus" ${args[@]+"${args[@]}"} ;;
	esac
}

if [ "$repeat" -eq 1 ]; then
	run_once
	exit $?
fi

failures=0
results=()
for ((i = 1; i <= repeat; i++)); do
	echo "=== focused run $i/$repeat ==="
	if run_once; then
		results+=("run $i: pass")
	else
		results+=("run $i: FAIL")
		failures=$((failures + 1))
	fi
done
echo "=== focused repeat summary: $((repeat - failures))/$repeat passed ==="
printf '  %s\n' "${results[@]}"
[ "$failures" -eq 0 ]
