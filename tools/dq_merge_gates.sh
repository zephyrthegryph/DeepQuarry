#!/usr/bin/env bash
# The gates of a merge batch (and of a lane-ready run), run once, on the merged HEAD, with the long steps overlapped:
#
#   bash tools/dq_merge_gates.sh [--lanes "branch branch"] [--tests "name name"] [--smoke FILE | --no-smoke] [--no-tests] [--tgui] [--serial]
#
#   1. gen          tools/build/build.sh gen                       (a no-op when the generated files are fresh: gen-state.bin)
#   2. prepare      icon repack, map bounds, DME check, verdigris  (the prerequisites every build target shares, done once so the
#                                                                   parallel jobs below never write the same file)
#   3. in parallel, each with its own log under data/merge-gates/<sha>.<job>.log:
#        tests      tools/dq_focused_test.sh <the test list>       (the test compile, the boot gate and the tests, one world)
#        dm         tools/build/build.sh dm                        (production DreamMaker without UNIT_TESTS + DreamChecker)
#        ratchets   tools/ci/check_ratchets.sh, then build.sh analyze
#        tgui       tools/build/build.sh tgui-lint                 (only when the batch touches tgui/, or with --tgui)
#
# The test list is the cross-branch smoke set (tools/ci/smoke_tests.txt, which includes the boot gate), plus --tests, plus the
# tests of every lane in --lanes whose lane-ready stamp (tools/dq_lane_ready.sh, tools/dq_lane_check.sh) is not valid for this
# master. A lane with a valid stamp is not tested again: its tests ran on its own merge with this master (or with a master that
# changed nothing it depends on), and what remains to be proved is the combination, which the smoke set, the compile and the
# ratchets on the merged HEAD cover. A lane without a stamp needs its tests named with --tests.
#   --no-smoke   leave the smoke set out (tools/dq_lane_ready.sh runs the lane's own list)
#   --no-tests   no test world at all (gen, dm, ratchets only)
#   --serial     run the jobs one after another (to read one job's output)
#
# On success the script stamps the exact HEAD, for tools/dq_push_master.sh, which then skips what the stamp says passed:
# data/merge-gates/<sha>.ok (the gates), .ratchets.ok, .dm.ok (production compile + DreamChecker), .analyze.ok. Timings land in
# data/merge-gates/<sha>.timings. Exit status: 0 all passed, 1 a gate failed (every job's verdict is printed), 2 a usage problem.
#
# What it still leaves to dq_push_master.sh: the second merge of origin/master, and any stamp it cannot honor (a different HEAD,
# an unclean tree). It never runs build.sh lint (DreamChecker + analyze + tgui lint, all covered above).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

tests_arg=()
lanes=""
smoke_file="tools/ci/smoke_tests.txt"
smoke=1
run_tests=1
tgui=0
serial=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests) shift; read -r -a more <<<"${1:-}"; tests_arg+=("${more[@]}") ;;
		--lanes) shift; lanes="${1:-}" ;;
		--smoke) shift; smoke_file="${1:-}" ;;
		--no-smoke) smoke=0 ;;
		--no-tests|--no-boot) run_tests=0 ;;
		--tgui) tgui=1 ;;
		--serial) serial=1 ;;
		-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dq_merge_gates: REFUSED: uncommitted changes to tracked files; commit the merge first (the stamp names an exact HEAD)" >&2
	exit 1
fi
# look_keys.txt must match the merged tree before the HEAD is stamped: regenerate it and commit it as part of the merge.
tools/build/build.sh gen || { echo "dq_merge_gates: gen failed" >&2; exit 1; }
bash tools/ci/check_look_keys_format.sh --commit || { echo "dq_merge_gates: look_keys regeneration failed" >&2; exit 1; }
sha="$(git rev-parse HEAD)"
short="${sha:0:12}"
mkdir -p data/merge-gates
timings="data/merge-gates/$short.timings"
rm -f "data/merge-gates/$short".{ok,ratchets.ok,dm.ok,analyze.ok}
: >"$timings"
wall_start=$(date +%s)

if [ "$tgui" -eq 0 ] && git rev-parse -q --verify origin/master >/dev/null; then
	if ! git diff --quiet "$(git merge-base origin/master HEAD)" HEAD -- tgui/ ':!tgui/packages/tgui/interfaces/generated'; then tgui=1; fi
fi

# ---- the test list ---------------------------------------------------------------------------------------------------------
tests=()
add_test() {
	local t
	for t in "$@"; do
		[ -n "$t" ] || continue
		case " ${tests[*]-} " in *" $t "*) ;; *) tests+=("$t") ;; esac
	done
}
if [ "$run_tests" -eq 1 ] && [ "$smoke" -eq 1 ] && [ -f "$smoke_file" ]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="$(echo "$line" | tr -d '\r' | xargs)"
		[ -n "$line" ] && add_test "$line"
	done <"$smoke_file"
fi
add_test ${tests_arg[@]+"${tests_arg[@]}"}
lane_rows=()
unstamped=()
if [ -n "$lanes" ]; then
	echo "== lanes: stamps against origin/master"
	# shellcheck disable=SC2086  # a list of refs
	mapfile -t lane_rows < <(bash tools/dq_lane_check.sh $lanes)
	for row in "${lane_rows[@]}"; do
		echo "   $row"
		verdict="$(awk '{print $3}' <<<"$row")"
		names="${row##* tests=}"
		case "$verdict" in
			VALID) echo "      -> tests skipped (valid stamp): ${names//,/ }" ;;
			INVALID)
				echo "      -> tests rerun in the combined world: ${names//,/ }"
				IFS=, read -r -a lt <<<"$names"
				add_test ${lt[@]+"${lt[@]}"}
				;;
			UNSTAMPED) unstamped+=("$(awk '{print $2}' <<<"$row")") ;;
		esac
	done
	if [ ${#unstamped[@]} -gt 0 ] && [ ${#tests_arg[@]} -eq 0 ]; then
		echo "dq_merge_gates: REFUSED: no lane-ready stamp on: ${unstamped[*]}. Run tools/dq_lane_ready.sh in the lane, or name its tests: --tests \"a b c\"" >&2
		exit 2
	fi
fi
if [ "$run_tests" -eq 1 ] && [ ${#tests[@]} -eq 0 ]; then tests=(dq_boot_gate); fi

# ---- running the gates -----------------------------------------------------------------------------------------------------
gate() { # <name> <command...>: one step in the foreground
	local name="$1" t0 rc
	shift
	echo "== gate: $name"
	t0=$(date +%s)
	"$@"
	rc=$?
	echo "$name $(( $(date +%s) - t0 ))s rc=$rc" | tee -a "$timings"
	if [ "$rc" -ne 0 ]; then
		echo "dq_merge_gates: FAILED at '$name' (exit $rc); fix it, recommit, rerun" >&2
		exit 1
	fi
}

gate gen tools/build/build.sh gen
gate prepare tools/build/build.sh icon-repack validate-dme verdigris-bindings-check verdigris map-bounds

job_tests() { bash tools/dq_focused_test.sh "${tests[@]}"; }
job_dm() {
	# Never "up to date": DreamChecker runs inside the dm target and the push script's checks read this log.
	rm -f deepquarry.dmb
	tools/build/build.sh dm || return 1
}
job_ratchets() {
	bash tools/ci/check_ratchets.sh || return 1
	tools/build/build.sh analyze || return 2
}
job_tgui() { tools/build/build.sh tgui-lint; }

names=()
[ "$run_tests" -eq 1 ] && names+=(tests)
names+=(dm ratchets)
[ "$tgui" -eq 1 ] && names+=(tgui)
echo "== gates in parallel: ${names[*]}$([ "$run_tests" -eq 1 ] && echo " (${#tests[@]} test(s): ${tests[*]:0:6}$([ ${#tests[@]} -gt 6 ] && echo ' ...'))")"
declare -A pid start
for n in "${names[@]}"; do
	log="data/merge-gates/$short.$n.log"
	start[$n]=$(date +%s)
	if [ "$serial" -eq 1 ]; then
		"job_$n" >"$log" 2>&1
		echo "$? $(date +%s)" >"$log.rc"
	else
		( "job_$n" >"$log" 2>&1; echo "$? $(date +%s)" >"$log.rc" ) &
		pid[$n]=$!
	fi
done
for n in "${names[@]}"; do
	[ "$serial" -eq 1 ] || wait "${pid[$n]}" 2>/dev/null
done

failed=()
for n in "${names[@]}"; do
	log="data/merge-gates/$short.$n.log"
	read -r rc finished <"$log.rc" 2>/dev/null || { rc=1; finished=$(date +%s); }
	rm -f "$log.rc"
	echo "$n $(( finished - start[$n] ))s rc=$rc" | tee -a "$timings"
	if [ "$rc" -ne 0 ] && [ "$n" = tests ] && grep -q '^KNOWN FAILURES CHECK: 0 NEW, [1-9]' "$log" && ! grep -q '^KNOWN FAILURES CHECK: [1-9][0-9]* NEW' "$log"; then
		# Every failure is one tools/ci/known_failures.txt lists (dq_focused_test.sh classified them): they are printed, not a gate failure.
		echo "tests: only KNOWN failures (tools/ci/known_failures.txt); not failing the gate:"
		grep -h '^  KNOWN' "$log" | sort -u
		rc=0
	fi
	if [ "$rc" -ne 0 ]; then failed+=("$n"); fi
done
echo "gates-wall $(( $(date +%s) - wall_start ))s" | tee -a "$timings"

# The DreamChecker and DreamMaker verdicts, read the way dq_push_master.sh reads them.
dm_ok=0
if printf '%s\n' "${names[@]}" | grep -qx dm && [[ " ${failed[*]-} " != *" dm "* ]]; then
	dm_log="data/merge-gates/$short.dm.log"
	if grep -q "dream-checker: passed" "$dm_log" && grep -q "Found 0 diagnostics" "$dm_log" && grep -qE "deepquarry\.dmb - 0 errors" "$dm_log"; then
		dm_ok=1
	else
		echo "dq_merge_gates: the production build ran but DreamChecker/DreamMaker did not report a clean result; see $dm_log" >&2
		failed+=(dm)
	fi
fi

if [ ${#failed[@]} -gt 0 ]; then
	for n in "${failed[@]}"; do
		echo "---- $n: last lines of data/merge-gates/$short.$n.log" >&2
		tail -n 40 "data/merge-gates/$short.$n.log" >&2
		grep -h '^FOCUSED RESULT:\|^dq_focused_test: REFUSED' "data/merge-gates/$short.$n.log" >&2 || true
	done
	echo "dq_merge_gates: FAILED: ${failed[*]} (logs data/merge-gates/$short.<job>.log); fix it, recommit, rerun" >&2
	exit 1
fi

git update-index -q --refresh >/dev/null 2>&1
if [ "$(git rev-parse HEAD)" != "$sha" ] || ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dq_merge_gates: the tree changed during the gates; not stamping" >&2
	exit 1
fi
echo "$sha" >"data/merge-gates/$short.ratchets.ok"
echo "$sha" >"data/merge-gates/$short.analyze.ok"
if [ "$dm_ok" -eq 1 ]; then echo "$sha" >"data/merge-gates/$short.dm.ok"; fi
tests_json=""
passed=0
nfailed=0
if [ "$run_tests" -eq 1 ]; then
	res_line="$(grep -h '^FOCUSED RESULT:' "data/merge-gates/$short.tests.log" | tail -n 1)"
	tests_json="$(sed -n 's/.*(json: \([^)]*\)).*/\1/p' <<<"$res_line")"
	passed="$(sed -n 's/^FOCUSED RESULT: \([0-9]*\) passed.*/\1/p' <<<"$res_line")"
	nfailed="$(sed -n 's/^FOCUSED RESULT: [0-9]* passed, \([0-9]*\) failed.*/\1/p' <<<"$res_line")"
	if [ -z "$passed" ] && [ -n "$tests_json" ] && [ -f "$tests_json" ]; then
		# "(not rerun)": the rerun guard found the same list passing on this tree; the counts are in its record.
		read -r passed nfailed < <(node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(r.counts.passed, r.counts.failed);' "$tests_json")
	fi
fi
{
	echo "sha=$sha"
	echo "tests=${tests[*]-}"
	echo "tests_json=$tests_json"
	echo "passed=${passed:-0}"
	echo "failed=${nfailed:-0}"
	echo "tgui=$tgui"
	echo "dm=$dm_ok"
	echo "lanes=$lanes"
} >"data/merge-gates/$short.ok"
echo "dq_merge_gates: all gates passed on $short (timings: $timings)"
