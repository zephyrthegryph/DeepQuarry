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
#   bash tools/dq_focused_test.sh --split-slow dq_look_tree_pin dq_boot_gate  # slow pins in a second world, at the same time
#   bash tools/dq_focused_test.sh --detach <tests>                         # start in the background; prints a run id
#   bash tools/dq_focused_test.sh --status <runid>                         # poll a detached run (exit 0 passed, 1 failed, 3 running)
#
# Every run ends with one line: "FOCUSED RESULT: N passed, M failed (json: path)". A merge agent keeps that line and the
# exit code; it must not hand back while a run is going: start with --detach and poll --status (agent_workflow.md section 9).
#
# --split-slow runs the slow pins (DQ_SLOW_TESTS, default dq_look_state_pin and dq_look_tree_pin) in a second world beside
# the rest, from the same compiled .dmb (second dm-test = run2: its own run slot, port, log dir, spritesheet dir). The
# summaries merge into one data/test-runs/<id>_focused.json and one exit code. It is on by default when the selection holds
# both a slow pin and some other test; --no-split-slow (or DQ_FOCUS_SPLIT=0) turns it off. It is never used with --bless or
# --repeat. Pins that must share a world with another test should be run with --no-split-slow.
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

RUN_DIR="data/focused-runs"

# --status <runid> prints a detached run's status file and exits 0 (passed), 1 (failed), 3 (still running), 2 (unknown).
# With no id it lists the newest runs. The status file is plain key=value text (state, started, finished, json, ...).
status_cmd() {
	local id="${1:-}" f state
	if [ -z "$id" ]; then
		for f in $(ls -t "$RUN_DIR"/*.status 2>/dev/null | head -10 || true); do
			echo "$(basename "$f" .status): $(sed -n 's/^state=//p' "$f") $(sed -n 's/^result=//p' "$f")"
		done
		exit 0
	fi
	f="$RUN_DIR/$id.status"
	[ -f "$f" ] || { echo "no such focused run: $id (looked for $f)" >&2; exit 2; }
	cat "$f"
	state="$(sed -n 's/^state=//p' "$f")"
	if [ "$state" = "running" ]; then
		echo "elapsed_s=$(( $(date +%s) - $(sed -n 's/^started_epoch=//p' "$f") ))"
		echo "--- last log lines ($RUN_DIR/$id.log)"
		tail -n 8 "$RUN_DIR/$id.log" 2>/dev/null || true
	fi
	case "$state" in passed) exit 0 ;; failed) exit 1 ;; running) exit 3 ;; *) exit 2 ;; esac
}

prev=""
detach=0
passthrough=()
for arg in "$@"; do
	if [ "$prev" = "--status" ]; then status_cmd "$arg"; fi
	case "$arg" in
		--status) prev="--status"; continue ;;
		--status=*) status_cmd "${arg#--status=}" ;;
		--detach) detach=1; continue ;;
	esac
	prev=""
	passthrough+=("$arg")
done
[ "$prev" = "--status" ] && status_cmd ""

# --detach: rerun this script in the background with the same arguments, return at once with a run id. The child writes
# data/focused-runs/<id>.status (state=running, then passed/failed) and .log. A caller polls --status instead of holding
# a monitor open or handing back mid-run.
if [ "$detach" -eq 1 ] && [ -z "${DQ_FOCUSED_RUN_ID:-}" ]; then
	mkdir -p "$RUN_DIR"
	DQ_FOCUSED_RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
	export DQ_FOCUSED_RUN_ID
	nohup bash "$0" ${passthrough[@]+"${passthrough[@]}"} >"$RUN_DIR/$DQ_FOCUSED_RUN_ID.log" 2>&1 </dev/null &
	child=$!
	disown "$child" 2>/dev/null || true
	# Written here so --status works at once; the child rewrites it as it goes.
	{ echo state=running; echo run_id=$DQ_FOCUSED_RUN_ID; echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "started_epoch=$(date +%s)"; echo "log=$RUN_DIR/$DQ_FOCUSED_RUN_ID.log"; } >"$RUN_DIR/$DQ_FOCUSED_RUN_ID.status"
	echo "FOCUSED RUN STARTED: $DQ_FOCUSED_RUN_ID (pid $child)"
	echo "poll with: bash tools/dq_focused_test.sh --status $DQ_FOCUSED_RUN_ID   (exit 0 passed, 1 failed, 3 running)"
	echo "log: $RUN_DIR/$DQ_FOCUSED_RUN_ID.log"
	exit 0
fi
set -- ${passthrough[@]+"${passthrough[@]}"}

# A detached child records its state; a foreground run (no DQ_FOCUSED_RUN_ID) writes nothing.
status_write() { # state [key=value ...]
	[ -n "${DQ_FOCUSED_RUN_ID:-}" ] || return 0
	mkdir -p "$RUN_DIR"
	local state="$1"
	shift
	{
		echo "state=$state"
		echo "run_id=$DQ_FOCUSED_RUN_ID"
		echo "started=$FOCUS_STARTED"
		echo "started_epoch=$FOCUS_STARTED_EPOCH"
		[ "$state" = "running" ] || echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "log=$RUN_DIR/$DQ_FOCUSED_RUN_ID.log"
		printf '%s\n' "$@"
	} >"$RUN_DIR/$DQ_FOCUSED_RUN_ID.status.tmp"
	mv -f "$RUN_DIR/$DQ_FOCUSED_RUN_ID.status.tmp" "$RUN_DIR/$DQ_FOCUSED_RUN_ID.status"
}
FOCUS_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FOCUS_STARTED_EPOCH="$(date +%s)"

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
bless=0
list_only=0
all_types=""
split_mode=auto
for arg in "$@"; do
	case "$arg" in
		--full-map) args+=("-DCITESTING_FULL_MAP") ;;
		--repeat=*)
			repeat="${arg#--repeat=}"
			[[ "$repeat" =~ ^[1-9][0-9]*$ ]] || { echo "--repeat needs a positive integer, got '$repeat'" >&2; exit 2; }
			;;
		--list) list_only=1 ;;
		--split-slow) split_mode=on ;;
		--no-split-slow) split_mode=off ;;
		--boot) tests+=("dq_boot_gate") ;;
		--bless) export DQ_SNAPSHOT_BLESS=1; bless=1 ;;
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


# Slow tests that go to a second world under --split-slow (and by default when the selection also holds other tests).
# Exact short names, space separated; DQ_SLOW_TESTS replaces the list.
slow_tests=" ${DQ_SLOW_TESTS:-dq_look_state_pin dq_look_tree_pin} "

# focus_arg <label> <tests...>: the --focus= value for a group; a long list goes through a file (--focus=@file): a
# Windows command line stops at 8191 characters. Sets FOCUS_ARG.
focus_files=()
focus_arg() {
	local label="$1" f joined
	shift
	joined="$(IFS=,; echo "$*")"
	FOCUS_ARG="$joined"
	if [ ${#joined} -gt 1500 ]; then
		mkdir -p data/focus-lists
		f="data/focus-lists/focus.$$.$label.txt"
		printf '%s\n' "$@" >"$f"
		focus_files+=("$f")
		FOCUS_ARG="@$f"
	fi
}
cleanup_files() {
	if [ ${#focus_files[@]} -gt 0 ]; then rm -f "${focus_files[@]}"; fi
}
trap cleanup_files EXIT

# Short names (no leading slash): Git Bash would rewrite "/datum/..." into a
# Windows path on its way to cmd.exe. dm-test adds the /datum/unit_test/ prefix back.
focus="$(IFS=,; echo "${tests[*]}")"
if [ ${#tests[@]} -gt 20 ]; then
	echo "Focused on (${#tests[@]}): ${tests[*]:0:20} ..."
else
	echo "Focused on (${#tests[@]}): $focus"
fi
focus_arg all "${tests[@]}"
focus="$FOCUS_ARG"

# Decide whether to split the slow pins into their own world.
fast_group=()
slow_group=()
for t in "${tests[@]}"; do
	if [[ "$slow_tests" == *" $t "* ]]; then slow_group+=("$t"); else fast_group+=("$t"); fi
done
do_split=0
case "$split_mode" in
	on) do_split=1 ;;
	auto) if [ ${#fast_group[@]} -gt 0 ] && [ ${#slow_group[@]} -gt 0 ]; then do_split=1; fi ;;
esac
if [ "${DQ_FOCUS_SPLIT:-}" = "0" ] && [ "$split_mode" = "auto" ]; then do_split=0; fi
if [ "$do_split" -eq 1 ] && { [ "$bless" -eq 1 ] || [ "$repeat" -gt 1 ]; }; then
	if [ "$split_mode" = "on" ]; then echo "--split-slow ignored: it is not used with --bless or --repeat" >&2; fi
	do_split=0
fi
if [ "$do_split" -eq 1 ] && [ ${#fast_group[@]} -eq 0 ]; then
	# Only slow pins: deal them alternately into the two worlds.
	if [ ${#slow_group[@]} -lt 2 ]; then
		do_split=0
	else
		slow_a=()
		slow_b=()
		for ((i = 0; i < ${#slow_group[@]}; i++)); do
			if [ $((i % 2)) -eq 0 ]; then slow_a+=("${slow_group[$i]}"); else slow_b+=("${slow_group[$i]}"); fi
		done
		fast_group=("${slow_a[@]}")
		slow_group=("${slow_b[@]}")
	fi
fi
if [ "$do_split" -eq 1 ] && [ ${#fast_group[@]} -eq 0 -o ${#slow_group[@]} -eq 0 ]; then do_split=0; fi # --split-slow with nothing to split

status_write running "tests=${#tests[@]}" "split=$do_split"

# The one-line verdict every run ends with, parsed from dm-test's "Unit-test summary: N passed, M failed, K skipped ...
# (saved data/test-runs/X.json)" line(s). $1 = the combined log; $2 = exit code; $3 = json (split runs pass their merged one).
print_result() {
	local log="$1" rc="$2" json="${3:-}" line passed failed skipped note="" tail_note="" st=passed
	line="$(grep -h 'Unit-test summary: [0-9]* passed' "$log" 2>/dev/null | tail -n 1 || true)"
	if [ -z "$json" ]; then
		json="$(sed -n 's/.*(saved \(data\/test-runs\/[^)]*\.json\)).*/\1/p' "$log" 2>/dev/null | tail -n 1)"
	fi
	if [ -n "$json" ] && [ -f "$json" ]; then
		read -r passed failed skipped < <(node -e '
			const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
			console.log(r.counts.passed, r.counts.failed, r.counts.skipped);' "$json")
	elif [ -n "$line" ]; then
		passed="$(sed -n 's/.*summary: \([0-9]*\) passed.*/\1/p' <<<"$line")"
		failed="$(sed -n 's/.*passed, \([0-9]*\) failed.*/\1/p' <<<"$line")"
		skipped="$(sed -n 's/.*failed, \([0-9]*\) skipped.*/\1/p' <<<"$line")"
	else
		echo "FOCUSED RESULT: no results (exit code $rc; the world died or the build failed)"
		status_write failed "result=no results" "exit_code=$rc"
		return 0
	fi
	if [ "${skipped:-0}" -gt 0 ]; then note=", $skipped skipped"; fi
	if [ "$rc" -ne 0 ] && [ "${failed:-0}" -eq 0 ]; then tail_note=" [exit $rc: the world was not clean: boot gate, watchdog or crash]"; fi
	echo "FOCUSED RESULT: $passed passed, $failed failed$note (json: ${json:-none})$tail_note"
	if [ "$rc" -ne 0 ]; then st=failed; fi
	status_write "$st" "result=$passed passed, $failed failed$note" "passed=$passed" "failed=$failed" "json=${json:-}" "exit_code=$rc"
	if [ "${failed:-0}" -gt 0 ] && [ -n "$json" ] && [ -f tools/dq_known_failures.sh ]; then
		bash tools/dq_known_failures.sh --check "$json" || true
	fi
	return 0
}

mkdir -p data/focused-runs
combined_log="data/focused-runs/last.$$.log"

run_once() {
	# Git Bash can use the same worktree-pinned entry point and system Bun as
	# the POSIX runner; avoid the batch bootstrap's separate tool download.
	tools/build/build.sh dm-test "--focus=$focus" ${args[@]+"${args[@]}"}
}

# Two worlds from one compiled .dmb. World 1 (the rest) compiles; once it has launched its world, world 2 (the slow pins)
# starts, hits the compile-hash cache (same defines, same tree) and boots as run2: own run slot, port, log dir,
# spritesheet dir and results file. DQ_KEEP_DERIVED_DME=1 keeps the derived .dme world 1 would delete at its end.
# Shared mutable files: none beyond what a sharded dm-test already shares (data/ is per worktree; tests write only
# under their run slot); snapshot rewrites (--bless) are why --bless never splits.
run_split() {
	local began logA logB pidA pidB rcA rcB waited=0 focusA focusB jA jB
	began="$(date +%s)"
	logA="data/focused-runs/split.$$.main.log"
	logB="data/focused-runs/split.$$.slow.log"
	focus_arg main "${fast_group[@]}"
	focusA="$FOCUS_ARG"
	focus_arg slow "${slow_group[@]}"
	focusB="$FOCUS_ARG"
	echo "== split: world 1 (${#fast_group[@]}): ${fast_group[*]:0:10}"
	echo "== split: world 2 (${#slow_group[@]}): ${slow_group[*]:0:10}"
	export DQ_KEEP_DERIVED_DME=1
	tools/build/build.sh dm-test "--focus=$focusA" "--label=focused-main" ${args[@]+"${args[@]}"} >"$logA" 2>&1 &
	pidA=$!
	# Wait for world 1 to finish compiling (it logs "Test world runN" when it launches), or to die.
	while ! grep -q 'Test world run' "$logA" 2>/dev/null; do
		if ! kill -0 "$pidA" 2>/dev/null; then break; fi
		sleep 2
	done
	if ! grep -q 'Test world run' "$logA" 2>/dev/null; then
		wait "$pidA"
		rcA=$?
		echo "== split: world 1 ended before launching its world (exit $rcA); world 2 not started"
		cat "$logA"
		cat "$logA" >"$combined_log"
		unset DQ_KEEP_DERIVED_DME
		return "$rcA"
	fi
	if [ -z "${DQ_FOCUS_TIMEOUT_MINUTES:-}" ]; then export DQ_FOCUS_TIMEOUT_MINUTES=45; fi # the look pins run about 22 minutes
	tools/build/build.sh dm-test "--focus=$focusB" "--label=focused-slow" ${args[@]+"${args[@]}"} >"$logB" 2>&1 &
	pidB=$!
	echo "== split: both worlds running (pids $pidA, $pidB)"
	while kill -0 "$pidA" 2>/dev/null || kill -0 "$pidB" 2>/dev/null; do
		sleep 5
		waited=$((waited + 5))
		if [ $((waited % 120)) -eq 0 ]; then
			echo "== split: $(( $(date +%s) - began ))s elapsed: world 1 $(kill -0 "$pidA" 2>/dev/null && echo running || echo done), world 2 $(kill -0 "$pidB" 2>/dev/null && echo running || echo done)"
		fi
	done
	wait "$pidA"
	rcA=$?
	wait "$pidB"
	rcB=$?
	unset DQ_KEEP_DERIVED_DME
	echo "================ world 1 (the rest), exit $rcA"
	if [ "$rcA" -eq 0 ]; then tail -n 15 "$logA"; else cat "$logA"; fi
	echo "================ world 2 (slow pins), exit $rcB"
	if [ "$rcB" -eq 0 ]; then tail -n 15 "$logB"; else cat "$logB"; fi
	cat "$logA" "$logB" >"$combined_log"
	# Merge the two data/test-runs records into one.
	jA="$(sed -n 's/.*(saved \(data\/test-runs\/[^)]*\.json\)).*/\1/p' "$logA" | tail -n 1)"
	jB="$(sed -n 's/.*(saved \(data\/test-runs\/[^)]*\.json\)).*/\1/p' "$logB" | tail -n 1)"
	SPLIT_JSON="$(node tools/dq_merge_test_runs.js "$jA" "$jB")" || echo "== split: could not merge the records ($jA, $jB)" >&2
	if [ "$rcA" -ne 0 ] || [ "$rcB" -ne 0 ]; then return 1; fi
	return 0
}

SPLIT_JSON=""
set +e
if [ "$do_split" -eq 1 ]; then
	run_split
	rc=$?
	print_result "$combined_log" "$rc" "$SPLIT_JSON"
	rm -f "$combined_log" data/focused-runs/split."$$".*.log
	exit "$rc"
fi

if [ "$repeat" -eq 1 ]; then
	run_once 2>&1 | tee "$combined_log"
	rc=${PIPESTATUS[0]}
	print_result "$combined_log" "$rc"
	rm -f "$combined_log"
	exit "$rc"
fi

failures=0
results=()
for ((i = 1; i <= repeat; i++)); do
	echo "=== focused run $i/$repeat ==="
	run_once 2>&1 | tee "$combined_log"
	rc=${PIPESTATUS[0]}
	if [ "$rc" -eq 0 ]; then
		results+=("run $i: pass")
	else
		results+=("run $i: FAIL")
		failures=$((failures + 1))
	fi
	print_result "$combined_log" "$rc"
done
rm -f "$combined_log"
echo "=== focused repeat summary: $((repeat - failures))/$repeat passed ==="
printf '  %s\n' "${results[@]}"
[ "$failures" -eq 0 ]
