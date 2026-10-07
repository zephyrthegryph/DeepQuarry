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

# The .dm files the unit-test build compiles: deepquarry.dme's includes plus code/modules/unit_tests/_unit_tests.dm's (relative to that
# folder), as repo paths, one per line. A test type in a file nothing includes is not in the .dmb: focusing it names a test the world
# doesn't have, which fails the run (and the boot gate) for no reason.
included_files() {
	{
		awk -F'"' '/^#include "code.*\.dm"/ { print $2 }' deepquarry.dme
		awk -F'"' '/^#include ".*\.dm"/ { print "code/modules/unit_tests/" $2 }' code/modules/unit_tests/_unit_tests.dm
	} | tr -d '\015' | tr '\134' '/' |
		awk '{ n = split($0, a, "/"); k = 0; for (i = 1; i <= n; i++) { if (a[i] == "..") k--; else if (a[i] != ".") b[++k] = a[i] } o = b[1]; for (i = 2; i <= k; i++) o = o "/" b[i]; print o }'
}

# Every /datum/unit_test type defined in a compiled file, without the prefix (one per line).
test_types() {
	# git grep reads the worktree in-process (about 0.5 s); a recursive grep over
	# code/ takes minutes on Windows. --untracked picks up new files. One awk
	# pass keeps the compiled files' types, strips the prefix and dedupes.
	{
		included_files | sed 's/^/INCLUDED /'
		git grep -H -o -E --untracked '^/datum/unit_test/[A-Za-z0-9_/]+(/Run\(\))?[[:space:]]*$' -- 'code/*.dm' 2>/dev/null \
			|| grep -rHoE '^/datum/unit_test/[A-Za-z0-9_/]+(/Run\(\))?[[:space:]]*$' code --include='*.dm'
	} | awk '
		/^INCLUDED / { inc[substr($0, 10)] = 1; next }
		{
			i = index($0, ":"); file = substr($0, 1, i - 1); name = substr($0, i + 1)
			if (!(file in inc)) next
			sub(/^\/datum\/unit_test\//, "", name); sub(/[[:space:]]+$/, "", name); sub(/\/Run\(\)$/, "", name) # a type may be declared only by its Run()
			if (!seen[name]++) print name
		}'
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
				# A name the build does not compile would reach the world as an unknown type and fail the run at boot: refuse it here.
				[ -n "$all_types" ] || all_types="$(test_types)"
				if ! grep -qxF -- "$name" <<<"$all_types"; then
					echo "no compiled /datum/unit_test type named '$name' (is its file included in _unit_tests.dm?)" >&2
					exit 2
				fi
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
	# Git Bash can use the same worktree-pinned entry point and system Bun as
	# the POSIX runner; avoid the batch bootstrap's separate tool download.
	tools/build/build.sh dm-test "--focus=$focus" ${args[@]+"${args[@]}"}
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
