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
#   bash tools/dq_focused_test.sh --rerun-failed [data/test-runs/X.json]   # run only what failed in the last run (or in that record)
#   bash tools/dq_focused_test.sh --force <tests>                          # run a list again that the guard below refuses
#
# The rerun guard ("diagnose before re-running"): the same list of arguments on the same tree (HEAD, tracked changes and untracked
# sources identical) is not run twice within DQ_FOCUS_RERUN_WINDOW_MIN (default 120) minutes. A list that passed is not rerun and
# reports the earlier result (exit 0); a list that failed is refused (exit 4) with a pointer to the log, because the same tests on
# the same code fail the same way: read the log and the code first. --rerun-failed runs only the failures of the last run (the
# way to check a flake), --force runs the list anyway, and any edit to the tree lets a run through by itself. --bless, --repeat=N and
# --list are never guarded. The record is data/focused-runs/ledger.tsv.
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
# Look pins (dq_look_state_pin, dq_look_tree_pin) run as DQ_LOOK_SHARDS (default 4; --look-shards=N) parallel worlds, each probing a
# slice of the types, and only the types whose analyzer key changed since code/modules/unit_tests/snapshots/look_keys.txt;
# --full probes every type. --look-order=reverse|shuffle:N reorders the types (the determinism proof) and --look-dump=DIR writes the
# produced rows sorted under DIR/merged for `diff -r`. At most two look-pin runs execute at once on the machine (the look_state_pin class of tools/dq_machine_slots.sh;
# the merge worktree goes first; DQ_SLOTS_LOOK_STATE_PIN=0 turns the cap off). --bless runs them unsharded and full.
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

# ---- The rerun guard ---------------------------------------------------------------------------------------------------------
LEDGER="$RUN_DIR/ledger.tsv"

# A digest of the tree a run tests: HEAD, the tracked changes and the untracked sources. Any edit moves it.
tree_digest() {
	{ git rev-parse HEAD; git diff HEAD; git ls-files -o --exclude-standard -- code tools tgui/packages; } 2>/dev/null | sha1sum | cut -c1-16
}

# One ledger row per finished run: epoch, key, exit code, failed count, result json, head, the arguments.
ledger_add() { # rc failed json
	[ -n "${FOCUS_KEY:-}" ] || return 0
	mkdir -p "$RUN_DIR"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$FOCUS_KEY" "$1" "$2" "${3:-}" "$(git rev-parse --short=10 HEAD 2>/dev/null)" "${FOCUS_ARGS_TEXT:-}" >>"$LEDGER" 2>/dev/null || true
}

# The failed test names (short, without /datum/unit_test/) of a result json, one per line.
failed_names_of() {
	node -e '
		const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
		for (const t of r.failed || []) console.log(t.replace(/^\/datum\/unit_test\//, ""));' "$1"
}

if [ -z "${DQ_FOCUS_GUARD_DONE:-}" ]; then
	force=0
	rerun=0
	rerun_json=""
	exempt=0
	clean=()
	for arg in ${passthrough[@]+"${passthrough[@]}"}; do
		case "$arg" in
			--force) force=1 ;;
			--rerun-failed) rerun=1 ;;
			--rerun-failed=*) rerun=1; rerun_json="${arg#--rerun-failed=}" ;;
			--bless|--list|--repeat=*|-h|--help) exempt=1; clean+=("$arg") ;;
			*) clean+=("$arg") ;;
		esac
	done
	passthrough=(${clean[@]+"${clean[@]}"})
	if [ "$rerun" -eq 1 ]; then
		# Only what failed in the last recorded run (or in the named record), plus this call's own flags.
		if [ -z "$rerun_json" ] && [ -f "$LEDGER" ]; then rerun_json="$(awk -F'\t' '$4 > 0 && $5 != "" { j = $5 } END { print j }' "$LEDGER")"; fi
		if [ -z "$rerun_json" ] || [ ! -f "$rerun_json" ]; then
			echo "dq_focused_test: --rerun-failed: no failed focused run on record in this worktree ($LEDGER); name the tests, or pass the record: --rerun-failed=data/test-runs/X.json" >&2
			exit 2
		fi
		mapfile -t failed_list < <(failed_names_of "$rerun_json")
		if [ ${#failed_list[@]} -eq 0 ]; then
			echo "dq_focused_test: --rerun-failed: $rerun_json lists no failed test" >&2
			exit 2
		fi
		echo "== rerunning the ${#failed_list[@]} test(s) that failed in $rerun_json: ${failed_list[*]:0:8}$([ ${#failed_list[@]} -gt 8 ] && echo ' ...')"
		keep=()
		for arg in ${passthrough[@]+"${passthrough[@]}"}; do
			case "$arg" in -*) keep+=("$arg") ;; esac
		done
		passthrough=(${keep[@]+"${keep[@]}"} "${failed_list[@]}")
	fi
	FOCUS_ARGS_TEXT="$(printf '%s ' ${passthrough[@]+"${passthrough[@]}"} | cut -c1-300)"
	FOCUS_KEY="$({ tree_digest; printf '%s\n' ${passthrough[@]+"${passthrough[@]}"} | sort; } | sha1sum | cut -c1-16)"
	export FOCUS_KEY FOCUS_ARGS_TEXT
	if [ "$force" -eq 0 ] && [ "$rerun" -eq 0 ] && [ "$exempt" -eq 0 ] && [ -f "$LEDGER" ]; then
		window=$(( ${DQ_FOCUS_RERUN_WINDOW_MIN:-120} * 60 ))
		prior="$(awk -F'\t' -v k="$FOCUS_KEY" -v now="$(date +%s)" -v win="$window" '$2 == k && now - $1 <= win { line = $0 } END { print line }' "$LEDGER")"
		if [ -n "$prior" ]; then
			IFS=$'\t' read -r p_epoch _ p_rc p_failed p_json p_head _ <<<"$prior"
			p_age=$(( ($(date +%s) - p_epoch) / 60 ))
			if [ "$p_rc" -eq 0 ]; then
				echo "FOCUSED RESULT: (not rerun) this exact list already passed on this exact tree $p_age min ago (json: ${p_json:-none}); --force runs it again"
				if [ "$detach" -eq 1 ]; then
					DQ_FOCUSED_RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
					mkdir -p "$RUN_DIR"
					{ echo state=passed; echo "run_id=$DQ_FOCUSED_RUN_ID"; echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "result=not rerun: passed $p_age min ago"; echo "json=${p_json:-}"; echo "exit_code=0"; } >"$RUN_DIR/$DQ_FOCUSED_RUN_ID.status"
					echo "FOCUSED RUN STARTED: $DQ_FOCUSED_RUN_ID (already passed; nothing to wait for)"
				fi
				exit 0
			fi
			{
				if [ "${p_failed:-0}" -gt 0 ]; then
					echo "dq_focused_test: REFUSED: this exact list already ran on this exact tree $p_age min ago (HEAD $p_head) and FAILED ($p_failed failed; result ${p_json:-none})."
					echo "  Read the log and the code first: the same tests on the same code fail the same way, unless the failure is order- or seed-dependent (the log says so:"
					echo "  'rng seed ... reruns this test alone', STATE LEAK lines). The failures are in $p_json (\"tests\"), the world log is data/logs/runN/tests.log, and"
					echo "  the last runs' output is under data/focused-runs/."
					echo "  - run only what failed (a flake check):   bash tools/dq_focused_test.sh --rerun-failed"
				else
					echo "dq_focused_test: REFUSED: this exact list already ran on this exact tree $p_age min ago (HEAD $p_head) and ended unclean (exit $p_rc) with no failed test (result ${p_json:-none})."
					echo "  Read the log and the code first: a world that died, was killed by the watchdog, tripped the boot gate or logged a runtime ends this way; the reason is in"
					echo "  data/logs/runN/tests.log and runtime-errors.log and in the last output under data/focused-runs/. If it was a machine hiccup (a daemon that did not exit, a"
					echo "  loaded machine), say so and run it again with --force."
				fi
				echo "  - run this list again regardless:          bash tools/dq_focused_test.sh --force <the same arguments>"
				echo "  - after any edit to the tree the guard lets the run through by itself."
			} >&2
			exit 4
		fi
	fi
	export DQ_FOCUS_GUARD_DONE=1
fi

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

# The one EXIT trap. It releases what the run holds (the temp focus lists, a look-pin slot) and, for a detached child, makes the
# status file say how the run ended when nothing else did: a script that exits before it reaches print_result (a bad test name, a
# usage error, a signal) must not leave `state=running` behind for --status to report forever.
focus_on_exit() {
	local rc=$?
	trap - EXIT
	if [ "$(type -t slots_group_release)" = "function" ]; then slots_group_release; fi
	if [ "$(type -t look_lock_release)" = "function" ]; then look_lock_release; fi
	if [ "$(type -t cleanup_files)" = "function" ]; then cleanup_files; fi
	if [ -n "${DQ_FOCUSED_RUN_ID:-}" ] && [ "$(sed -n 's/^state=//p' "$RUN_DIR/$DQ_FOCUSED_RUN_ID.status" 2>/dev/null)" = "running" ]; then
		local why
		why="$(grep -v '^[[:space:]]*$' "$RUN_DIR/$DQ_FOCUSED_RUN_ID.log" 2>/dev/null | tail -n 1 | cut -c1-300)"
		status_write failed "result=exited before a result (exit $rc)" "exit_code=$rc" "reason=${why:-no output}"
	fi
	exit "$rc"
}
trap focus_on_exit EXIT
trap 'exit 130' INT TERM

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
look_shards="${DQ_LOOK_SHARDS:-4}"
look_full=0
look_order=""
look_dump=""
for arg in "$@"; do
	case "$arg" in
		--full-map) args+=("-DCITESTING_FULL_MAP") ;;
		--repeat=*)
			repeat="${arg#--repeat=}"
			[[ "$repeat" =~ ^[1-9][0-9]*$ ]] || { echo "--repeat needs a positive integer, got '$repeat'" >&2; exit 2; }
			;;
		--list) list_only=1 ;;
		--split-slow) split_mode=on ;;
		--look-shards=*)
			look_shards="${arg#--look-shards=}"
			[[ "$look_shards" =~ ^[1-9][0-9]*$ ]] || { echo "--look-shards needs a positive integer, got '$look_shards'" >&2; exit 2; }
			;;
		--full) look_full=1 ;;
		--look-order=*) look_order="${arg#--look-order=}" ;;
		--look-dump=*) look_dump="${arg#--look-dump=}" ;;
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

# ---- worlds ----
# The selection becomes up to three kinds of world, all from one compiled .dmb (each a dm-test of its own: run slot, port, log dir,
# spritesheet dir, results file):
#   main   the tests that are not slow pins
#   slow   slow tests that are not look pins (DQ_SLOW_TESTS names more), together in one world
#   look   dq_look_state_pin / dq_look_tree_pin: DQ_LOOK_SHARDS (default 4, --look-shards=N) worlds, each probing its slice of the
#          types (DQ_FOCUS_SHARD=i/N; the sweep tests ask sweep_owns()), so the pins finish in about a quarter of the time. Both
#          pins ride in every look world, so each type is made once for both. Not used with --bless or --repeat; a new pin (an
#          empty snapshot file) is recorded by an unsharded full run: --look-shards=1 --full (tools/dq_pin.sh passes both).
# Look runs are incremental unless --full: `analyze look-keys` hashes everything that can change a type's rows, and only the types whose
# key differs from code/modules/unit_tests/snapshots/look_keys.txt are probed. A passing run that covered both pins rewrites that file.
# --full probes every type (the merge worktree and the nightly use it).
look_pins=" dq_look_state_pin dq_look_tree_pin "
main_group=()
slow_group=()
look_group=()
for t in "${tests[@]}"; do
	if [[ "$look_pins" == *" $t "* ]]; then look_group+=("$t")
	elif [[ "$slow_tests" == *" $t "* ]]; then slow_group+=("$t")
	else main_group+=("$t"); fi
done
do_split=0
case "$split_mode" in
	on) do_split=1 ;;
	auto) if [ ${#main_group[@]} -gt 0 ] && [ $(( ${#slow_group[@]} + ${#look_group[@]} )) -gt 0 ]; then do_split=1; fi ;;
esac
if [ "${DQ_FOCUS_SPLIT:-}" = "0" ] && [ "$split_mode" = "auto" ]; then do_split=0; fi
if [ "$bless" -eq 1 ] || [ "$repeat" -gt 1 ]; then
	if [ "$split_mode" = "on" ]; then echo "--split-slow ignored: it is not used with --bless or --repeat" >&2; fi
	do_split=0
fi
# A look run: the pins are worlds of their own (sharded) unless bless, repeat or an empty snapshot file makes them run as before.
look_world=0
if [ ${#look_group[@]} -gt 0 ] && [ "$bless" -eq 0 ] && [ "$repeat" -eq 1 ] && [ "$split_mode" != "off" ] && [ "${DQ_FOCUS_SPLIT:-}" != "0" ]; then
	look_world=1
	do_split=1
fi
# The cap on look-pin runs across the machine (tools/dq_look_lock.sh): any run that holds a look pin waits for a slot first.
if [ ${#look_group[@]} -gt 0 ]; then
	# shellcheck source=tools/dq_look_lock.sh
	. tools/dq_look_lock.sh
	DQ_LOOK_LOCK_LABEL="focused ${look_group[*]:0:2}" look_lock_acquire
fi

LOOK_PARAMS=""
LOOK_PLAN_FILE=""
LOOK_STALE_COUNT=-1
look_prepare() {
	# The analyzer's plan: a key and a probe list per type. Without it (no engine, an old one) the pins run full and unnarrowed.
	local bin plan keys stale universe
	plan="data/look-plan.tsv"
	keys="code/modules/unit_tests/snapshots/look_keys.txt"
	if bin="$(bash tools/ci/analyze.sh 2>/dev/null)" && "$bin" look-keys --out "$plan" >/dev/null 2>&1 && [ -s "$plan" ]; then
		LOOK_PLAN_FILE="$plan"
		LOOK_PARAMS="look-plan=$plan"
		universe="$(wc -l <"$plan" | tr -d ' ')"
		if [ "$look_full" -eq 0 ] && [ -f "$keys" ]; then
			stale="data/look-types.$$.txt"
			focus_files+=("$stale")
			awk -F'\t' 'NR == FNR { have[$1] = $2; next } have[$1] != $2 { print $1 }' "$keys" "$plan" >"$stale"
			LOOK_STALE_COUNT="$(wc -l <"$stale" | tr -d ' ')"
			echo "== look pins: $LOOK_STALE_COUNT of $universe types changed since the recorded keys (--full probes all)"
			LOOK_PARAMS="$LOOK_PARAMS&look-types=$stale"
		else
			echo "== look pins: full run over $universe types"
		fi
	else
		echo "== look pins: no analyzer plan (analyze look-keys unavailable): full, unnarrowed run"
		look_full=1
	fi
	if [ -n "$look_order" ]; then LOOK_PARAMS="${LOOK_PARAMS:+$LOOK_PARAMS&}look-order=$look_order"; fi
	if [ -n "$look_dump" ]; then LOOK_PARAMS="${LOOK_PARAMS:+$LOOK_PARAMS&}look-dump=$look_dump"; fi
}
if [ "$look_world" -eq 1 ]; then look_prepare; fi

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
		# Not recorded: a run with no result says nothing about the tests, so a rerun is not a repeat of it.
		status_write failed "result=no results" "exit_code=$rc"
		return 0
	fi
	if [ "${skipped:-0}" -gt 0 ]; then note=", $skipped skipped"; fi
	if [ "$rc" -ne 0 ] && [ "${failed:-0}" -eq 0 ]; then tail_note=" [exit $rc: the world was not clean: boot gate, watchdog or crash]"; fi
	echo "FOCUSED RESULT: $passed passed, $failed failed$note (json: ${json:-none})$tail_note"
	ledger_add "$rc" "${failed:-0}" "${json:-}"
	if [ "$rc" -ne 0 ]; then st=failed; fi
	status_write "$st" "result=$passed passed, $failed failed$note" "passed=$passed" "failed=$failed" "json=${json:-}" "exit_code=$rc"
	if [ "${failed:-0}" -gt 0 ] && [ -n "$json" ] && [ -f "$json" ] && [ -f tools/dq_known_failures.sh ]; then
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

# Several worlds from one compiled .dmb. The first world compiles; once it has launched its world ("Test world runN"), the rest start,
# hit the compile-hash cache (same defines, same tree) and boot as run2, run3, ...: own run slot, port, log dir, spritesheet dir and
# results file. DQ_KEEP_DERIVED_DME=1 keeps the derived .dme the first world would delete at its end. Shared mutable files: none beyond
# what a sharded dm-test already shares (data/ is per worktree; tests write only under their run slot); snapshot rewrites (--bless)
# are why --bless never splits.
W_LABEL=()
W_FOCUS=()
W_SHARD=()
W_PARAMS=()
W_LOG=()
W_PID=()
W_RC=()
add_world() { # label shard params tests...
	local label="$1" shard="$2" params="$3"
	shift 3
	focus_arg "w${#W_LABEL[@]}" "$@"
	W_LABEL+=("$label")
	W_FOCUS+=("$FOCUS_ARG")
	W_SHARD+=("$shard")
	W_PARAMS+=("$params")
}
start_world() { # index
	local i="$1" log="data/focused-runs/split.$$.$1.log"
	W_LOG[$i]="$log"
	(
		if [ -n "${W_SHARD[$i]}" ]; then export DQ_FOCUS_SHARD="${W_SHARD[$i]}"; fi
		if [ -n "${W_PARAMS[$i]}" ]; then export DQ_WORLD_PARAMS="${W_PARAMS[$i]}"; fi
		exec tools/build/build.sh dm-test "--focus=${W_FOCUS[$i]}" "--label=focused-${W_LABEL[$i]}" ${args[@]+"${args[@]}"}
	) >"$log" 2>&1 &
	W_PID[$i]=$!
}
run_worlds() {
	local began n i waited=0 running jsons=() rc=0 j shard W_DONE
	began="$(date +%s)"
	W_LABEL=(); W_FOCUS=(); W_SHARD=(); W_PARAMS=()
	if [ ${#main_group[@]} -gt 0 ]; then add_world main "" "" "${main_group[@]}"; fi
	if [ ${#slow_group[@]} -gt 0 ]; then add_world slow "" "" "${slow_group[@]}"; fi
	if [ "$look_world" -eq 1 ] && [ "$LOOK_STALE_COUNT" -ne 0 ]; then
		n="$look_shards"
		if [ "$LOOK_STALE_COUNT" -ge 0 ] && [ "$n" -gt 1 ]; then
			# Little to probe: fewer worlds (a world costs a boot, about 30 seconds, for about 50 types).
			n=$(( (LOOK_STALE_COUNT + 49) / 50 ))
			[ "$n" -lt 1 ] && n=1
			[ "$n" -gt "$look_shards" ] && n="$look_shards"
		fi
		for ((i = 0; i < n; i++)); do
			shard=""
			if [ "$n" -gt 1 ]; then shard="$i/$n"; fi
			add_world "look$i" "$shard" "$LOOK_PARAMS" "${look_group[@]}"
		done
	elif [ ${#look_group[@]} -gt 0 ]; then
		add_world look "" "" "${look_group[@]}"
	fi
	for ((i = 0; i < ${#W_LABEL[@]}; i++)); do echo "== worlds: ${W_LABEL[$i]}${W_SHARD[$i]:+ (slice ${W_SHARD[$i]})}"; done
	export DQ_KEEP_DERIVED_DME=1
	if [ ${#look_group[@]} -gt 0 ] || [ ${#slow_group[@]} -gt 0 ]; then
		if [ -z "${DQ_FOCUS_TIMEOUT_MINUTES:-}" ]; then export DQ_FOCUS_TIMEOUT_MINUTES=45; fi
	fi
	start_world 0
	# Wait for world 0 to finish compiling (it logs "Test world runN" when it launches), or to die.
	while ! grep -q 'Test world run' "${W_LOG[0]}" 2>/dev/null; do
		if ! kill -0 "${W_PID[0]}" 2>/dev/null; then break; fi
		sleep 2
	done
	if ! grep -q 'Test world run' "${W_LOG[0]}" 2>/dev/null; then
		wait "${W_PID[0]}"
		rc=$?
		echo "== worlds: world 0 ended before launching its world (exit $rc); the others were not started"
		cat "${W_LOG[0]}"
		cat "${W_LOG[0]}" >"$combined_log"
		unset DQ_KEEP_DERIVED_DME
		return "$rc"
	fi
	# The other worlds' test_world slots are taken together, in one queue entry (slots_group_acquire): a world never waits for a slot
	# while a sibling holds one, and two sharded runs cannot each hold part of the budget. The group is clamped to the machine's
	# capacity; the worlds beyond it start as earlier ones end, each handing its slot back the moment its world exits. World 0 took
	# its own slot (it queues alone, after its compile) and waits for nothing else.
	local rest=$(( ${#W_LABEL[@]} - 1 )) next=1 gsize=0 limited=0 started_n=0 reaped=0
	if [ "$rest" -gt 0 ]; then
		. tools/dq_machine_slots.sh
		gsize="$(slots_group_size test_world "$rest")"
		if [ "$(slots_capacity test_world)" -gt 0 ]; then
			limited=1
			[ "$gsize" -lt "$rest" ] && echo "== worlds: $rest more worlds, but at most $gsize test worlds run at once on this machine: the rest start as slots come back"
			slots_group_acquire test_world "$gsize" "focused ${#W_LABEL[@]} worlds"
		fi
	fi
	echo "== worlds: ${#W_LABEL[@]} total"
	W_DONE=()
	for ((i = 0; i < ${#W_LABEL[@]}; i++)); do W_DONE[$i]=0; done
	while true; do
		running=0
		for ((i = 0; i < next; i++)); do
			[ "${W_DONE[$i]}" -eq 1 ] && continue
			if kill -0 "${W_PID[$i]}" 2>/dev/null; then
				running=$((running + 1))
			else
				W_DONE[$i]=1
				# World 0 holds its own slot; every other world used one of the group's.
				if [ "$i" -gt 0 ] && [ "$limited" -eq 1 ]; then slots_group_release_one; fi
			fi
		done
		# Start the worlds still waiting for a hand-off slot: one per slot the group holds that no running world uses.
		while [ "$next" -lt "${#W_LABEL[@]}" ]; do
			if [ "$limited" -eq 1 ]; then
				local in_use=0 k
				for ((k = 1; k < next; k++)); do [ "${W_DONE[$k]}" -eq 0 ] && in_use=$((in_use + 1)); done
				[ "$in_use" -ge "$gsize" ] && break
			fi
			if [ "$limited" -eq 1 ]; then export DQ_SLOTS_PREHELD=test_world; fi
			start_world "$next"
			unset DQ_SLOTS_PREHELD
			next=$((next + 1))
			running=$((running + 1))
		done
		[ "$running" -eq 0 ] && [ "$next" -ge "${#W_LABEL[@]}" ] && break
		sleep 5
		waited=$((waited + 5))
		if [ $((waited % 120)) -eq 0 ]; then echo "== worlds: $(( $(date +%s) - began ))s elapsed, $running of ${#W_LABEL[@]} still running"; fi
	done
	slots_group_release 2>/dev/null || true
	unset DQ_KEEP_DERIVED_DME
	: >"$combined_log"
	for ((i = 0; i < ${#W_LABEL[@]}; i++)); do
		wait "${W_PID[$i]}"
		W_RC[$i]=$?
		echo "================ world ${W_LABEL[$i]}, exit ${W_RC[$i]}"
		if [ "${W_RC[$i]}" -eq 0 ]; then tail -n 6 "${W_LOG[$i]}"; else cat "${W_LOG[$i]}"; rc=1; fi
		cat "${W_LOG[$i]}" >>"$combined_log"
		j="$(sed -n 's/.*(saved \(data\/test-runs\/[^)]*\.json\)).*/\1/p' "${W_LOG[$i]}" | tail -n 1)"
		jsons+=("$j")
	done
	SPLIT_JSON="$(node tools/dq_merge_test_runs.js "${jsons[@]}")" || echo "== worlds: could not merge the records (${jsons[*]})" >&2
	echo "== worlds: all done in $(( $(date +%s) - began ))s"
	return "$rc"
}

# The dumps of a look run (look-dump=DIR): each world wrote DIR/shardN/<pin>/<root>.txt; the shard files of a root are joined and
# sorted into DIR/merged/<pin>/<root>.txt, so two runs (in different orders or shard counts) compare with `diff -r`.
look_dump_merge() {
	if [ -z "$look_dump" ] || [ ! -d "$look_dump" ]; then return 0; fi
	local f rel
	rm -rf "$look_dump/merged"
	for f in "$look_dump"/shard*/*/*.txt; do
		[ -f "$f" ] || continue
		rel="${f#"$look_dump"/}"
		rel="${rel#*/}"
		mkdir -p "$look_dump/merged/$(dirname "$rel")"
		cat "$f" >>"$look_dump/merged/$rel"
	done
	while IFS= read -r f; do LC_ALL=C sort -o "$f" "$f"; done < <(find "$look_dump/merged" -name '*.txt' 2>/dev/null)
	echo "== look dump merged under $look_dump/merged ($(find "$look_dump/merged" -name '*.txt' | wc -l | tr -d ' ') files)"
}

# A passing run that covered both pins records the plan's keys: those types' rows are what the snapshots say.
look_keys_record() {
	if [ "$look_world" -ne 1 ] || [ -z "$LOOK_PLAN_FILE" ] || [ ! -f "$LOOK_PLAN_FILE" ] || [ -n "$look_order" ]; then return 0; fi
	if [[ " ${look_group[*]} " != *" dq_look_state_pin "* || " ${look_group[*]} " != *" dq_look_tree_pin "* ]]; then return 0; fi
	# One writer format: the analyzer's plan verbatim (type, key, probes), byte-identical to `analyze look-keys` output.
	cp "$LOOK_PLAN_FILE" code/modules/unit_tests/snapshots/look_keys.txt
	if ! cmp -s "$LOOK_PLAN_FILE" code/modules/unit_tests/snapshots/look_keys.txt; then
		echo "== look pins: FAIL: recorded look_keys.txt differs from the analyzer plan"
		return 1
	fi
	echo "== look pins: recorded $(wc -l <code/modules/unit_tests/snapshots/look_keys.txt | tr -d ' ') type keys in code/modules/unit_tests/snapshots/look_keys.txt (commit it with the snapshots)"
}

# A look run with no stale type and nothing else to run needs no world at all.
if [ "$look_world" -eq 1 ] && [ "$LOOK_STALE_COUNT" -eq 0 ] && [ ${#main_group[@]} -eq 0 ] && [ ${#slow_group[@]} -eq 0 ]; then
	echo "FOCUSED RESULT: 0 passed, 0 failed (look pins: no type changed since the recorded keys, nothing probed; --full probes all)"
	status_write passed "result=look pins: nothing stale" "passed=0" "failed=0" "exit_code=0"
	ledger_add 0 0 ""
	exit 0
fi

SPLIT_JSON=""
set +e
if [ "$do_split" -eq 1 ]; then
	run_worlds
	rc=$?
	look_dump_merge
	if [ "$rc" -eq 0 ]; then look_keys_record; fi
	print_result "$combined_log" "$rc" "$SPLIT_JSON"
	rm -f "$combined_log" data/focused-runs/split."$$".*.log
	exit "$rc"
fi

if [ "$repeat" -eq 1 ]; then
	run_once 2>&1 | tee "$combined_log"
	rc=${PIPESTATUS[0]}
	if [ "$rc" -eq 0 ] && [ "$bless" -eq 1 ] && [ ${#look_group[@]} -gt 0 ]; then
		# A blessed (unsharded, full, unnarrowed) run rewrote every look row: the keys now describe them.
		look_world=1
		if bin="$(bash tools/ci/analyze.sh 2>/dev/null)" && "$bin" look-keys --out data/look-plan.tsv >/dev/null 2>&1 && [ -s data/look-plan.tsv ]; then
			LOOK_PLAN_FILE=data/look-plan.tsv
			look_keys_record
		fi
	fi
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
