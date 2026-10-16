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
#        dm         tools/build/build.sh dm                        (production native compile (DreamMaker with DQ_COMPILER=dreammaker) without UNIT_TESTS + DreamChecker)
#        ratchets   tools/ci/check_ratchets.sh, then build.sh analyze
#        tgui       tools/build/build.sh tgui-lint                 (only when the batch touches tgui/, or with --tgui)
#        analyze_tests  cargo test in tools/analyze, in a cargo slot (only when the batch touches tools/analyze/)
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
# The gates keep the full end-of-test staleness sweep (dq_focused_test.sh would otherwise bound it).
export DQ_STALENESS=full
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
# In the shared merge worktree only the batch that holds the merge lock (tools/dq_merge_worktree.sh) may gate.
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
merge_lock_require || exit 1
merge_lock_busy begin
trap 'merge_lock_busy end' EXIT

tests_arg=()
lanes=""
smoke_file="tools/ci/smoke_tests.txt"
smoke=1
run_tests=1
snapshot_output=0
tgui=0
serial=0
reproof=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests) shift; read -r -a more <<<"${1:-}"; tests_arg+=("${more[@]}") ;;
		--lanes) shift; lanes="${1:-}" ;;
		--smoke) shift; smoke_file="${1:-}" ;;
		--snapshot-output) snapshot_output=1 ;;
		--no-smoke) smoke=0 ;;
		--no-tests|--no-boot) run_tests=0 ;;
		--tgui) tgui=1 ;;
		--serial) serial=1 ;;
		--reproof) reproof=1 ;;
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
# The generated files must be fresh before the HEAD is stamped.
tools/build/build.sh gen || { echo "dq_merge_gates: gen failed" >&2; exit 1; }
# What this batch is meant to land, recorded for tools/dq_push_master.sh: origin/master as the gates start (a push after it moved
# is refused on the merge worktree) and the tip of every lane in --lanes (the push fails unless each is in HEAD and then in origin/master).
git fetch -q origin 2>/dev/null || echo "dq_merge_gates: warning: git fetch failed; base_master is the last fetched origin/master" >&2
base_master="$(git rev-parse -q --verify origin/master 2>/dev/null || true)"
lane_tips=""
for ref in $lanes; do
	tip="$(git rev-parse -q --verify "$ref^{commit}" 2>/dev/null || git rev-parse -q --verify "origin/$ref^{commit}" 2>/dev/null || true)"
	if [ -z "$tip" ]; then echo "dq_merge_gates: REFUSED: lane '$ref' does not resolve to a commit" >&2; exit 2; fi
	if ! git merge-base --is-ancestor "$tip" HEAD; then
		echo "dq_merge_gates: REFUSED: lane '$ref' (${tip:0:12}) is not in HEAD; merge it into this branch first (git merge --no-ff $ref)" >&2
		exit 1
	fi
	lane_tips="$lane_tips${lane_tips:+,}$tip"
done
# A baseline that only needs shrinking after the merge (a fixed site left it) is shrunk into the merge commit, instead of a separate
# repair commit. Only when HEAD is an unpushed merge commit (the merge worktree's batch): a lane-ready run or any other HEAD keeps
# its sha, which its caller already recorded. `analyze baseline --update` never adds a site or raises a ceiling.
if [ "$(git rev-list --parents -n 1 HEAD | awk '{print NF-1}')" = "2" ] && ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null 	&& bin="$(bash tools/ci/analyze.sh 2>/dev/null)"; then
	"$bin" baseline --update >/dev/null 2>&1 || echo "dq_merge_gates: warning: analyze baseline --update failed; baselines left as they are" >&2
	if ! git diff --quiet -- tools/ci; then
		echo "dq_merge_gates: shrank ratchet baselines into the merge commit:"
		git diff --stat -- tools/ci | tail -n 5
		git add -- tools/ci
		git commit -q --amend --no-edit
	fi
fi
# look_keys.txt records VERIFIED keys only. The union merge may have left it non-canonical (normalize drops rows, never writes a key).
bash tools/ci/check_look_keys_format.sh --commit || { echo "dq_merge_gates: look_keys normalization failed" >&2; exit 1; }
# Every type whose current look key has no recorded row (its look changed in a lane or in the merge) is probed here, and only here are
# its keys recorded, into the merge commit. A lane-ready run (--snapshot-output) probes its own and records them itself.
if [ "$run_tests" -eq 1 ] && [ "$snapshot_output" -eq 0 ] && [ -f code/modules/unit_tests/dq_look_pins.dm ]; then
	unverified_line="$(bash tools/ci/check_look_keys_format.sh --unverified)" || { echo "dq_merge_gates: could not compute the unverified look types" >&2; exit 1; }
	unverified_n="${unverified_line%% *}"
	echo "== look pins: $unverified_line"
	if [ "${unverified_n:-0}" -gt 0 ]; then
		bash tools/dq_focused_test.sh dq_look_state_pin dq_look_tree_pin || { echo "dq_merge_gates: FAILED: the look pins over the unverified types; fix them (or bless explicitly), recommit, rerun" >&2; exit 1; }
		if ! git diff --quiet -- code/modules/unit_tests/snapshots/look_keys.txt; then
			git add -- code/modules/unit_tests/snapshots/look_keys.txt
			if [ "$(git rev-list --parents -n 1 HEAD | awk '{print NF-1}')" = "2" ] && ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
				git commit -q --amend --no-edit
			else
				git commit -q -m "Record look keys for the types the merge gates probed" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
			fi
			echo "dq_merge_gates: recorded the probed look keys into HEAD"
		fi
	fi
fi
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

analyze_tests=0
if git rev-parse -q --verify origin/master >/dev/null && ! git diff --quiet "$(git merge-base origin/master HEAD)" HEAD -- tools/analyze/; then analyze_tests=1; fi

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
# The gameplay scenarios (tools/ci/gameplay_tests.txt) run on every landing, with the smoke set.
if [ "$run_tests" -eq 1 ] && [ "$smoke" -eq 1 ] && [ -f tools/ci/gameplay_tests.txt ]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="$(echo "$line" | tr -d '
' | xargs)"
		[ -n "$line" ] && add_test "$line"
	done <tools/ci/gameplay_tests.txt
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
# Re-proof (tools/dq_reproof_source.sh, agent_workflow.md "Re-proof"): HEAD merges master into a lane or batch whose stamp is on exactly its tip but
# went stale because master moved. Its full stamped test list runs on this merged tree, and this run is the fresh stamp (recorded in the note and the log).
reproof_of=""
reproof_reason=""
if [ "$reproof" -eq 1 ]; then
	[ "$run_tests" -eq 1 ] || { echo "dq_merge_gates: REFUSED: --reproof needs the test world (not --no-tests)" >&2; exit 2; }
	rp="$(bash tools/dq_reproof_source.sh HEAD)" || { echo "dq_merge_gates: REFUSED: nothing to re-prove on HEAD: $(bash tools/dq_reproof_source.sh HEAD 2>&1 >/dev/null | head -n 1)" >&2; exit 1; }
	reproof_of="$(sed -n 1p <<<"$rp")"
	read -r -a rp_tests <<<"$(sed -n 2p <<<"$rp")"
	reproof_reason="$(bash tools/dq_lane_check.sh "$reproof_of" 2>&1 | sed 's/ tests=.*//' | head -n 1 | tr -d '"\\' | head -c 300)"
	echo "== re-proof: the stamp on ${reproof_of:0:12} is stale because master moved; running its full stamped list (${#rp_tests[@]} test(s)) on the merged tree ${sha:0:12}"
	echo "   why: ${reproof_reason:-master moved}"
	add_test "${rp_tests[@]}"
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
job_analyze_tests() { # the analyzer's own cargo tests: a change under tools/analyze must leave them green (all targets, every failure listed)
	bash tools/dq_machine_slots.sh run cargo --label analyze-tests -- bash -c 'cd tools/analyze && cargo test --no-fail-fast'
}

names=()
[ "$run_tests" -eq 1 ] && names+=(tests)
names+=(dm ratchets)
[ "$tgui" -eq 1 ] && names+=(tgui)
[ "$analyze_tests" -eq 1 ] && names+=(analyze_tests)
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
		echo "################################################################################"
		echo "# KNOWN FAILURE STILL PRESENT - fix required (listed above; nothing is committed for them)"
		echo "################################################################################"
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
gate_diff_args=()
if [ "$snapshot_output" -eq 1 ]; then
	# Lane-ready commits successful pin output itself; every other tracked edit remains forbidden.
	gate_diff_args=(-- . ":!code/modules/unit_tests/snapshots/")
fi
if [ "$(git rev-parse HEAD)" != "$sha" ] || ! git diff --quiet "${gate_diff_args[@]}" || ! git diff --cached --quiet; then
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
# The failures tools/ci/known_failures.txt does not list (the gates passed, so a failure here is a KNOWN one; 0 without a check line).
new_failed=0
known_line="$(grep -h '^KNOWN FAILURES CHECK:' "data/merge-gates/$short.tests.log" 2>/dev/null | tail -n 1)"
if [ -n "$known_line" ]; then
	new_failed="$(sed -n 's/^KNOWN FAILURES CHECK: \([0-9]*\) NEW.*/\1/p' <<<"$known_line")"
fi
{
	echo "sha=$sha"
	echo "tests=${tests[*]-}"
	echo "tests_json=$tests_json"
	echo "passed=${passed:-0}"
	echo "failed=${nfailed:-0}"
	echo "new_failed=${new_failed:-0}"
	echo "tgui=$tgui"
	echo "dm=$dm_ok"
	echo "lanes=$lanes"
	echo "lane_tips=$lane_tips"
	echo "base_master=$base_master"
	echo "reproof_of=$reproof_of"
	echo "reproof_reason=$reproof_reason"
} >"data/merge-gates/$short.ok"
# The test stamp the push gate reads (tools/dq_push_stamp.sh): a note on this exact commit, only when a test world ran and nothing failed
# that tools/ci/known_failures.txt does not list. A lane-ready run gets its own note from dq_lane_ready.sh; a merge batch pushes on this one.
if [ "$run_tests" -eq 1 ] && [ "${new_failed:-0}" = "0" ] && [ "${passed:-0}" -gt 0 ]; then
	tests_arr="$(printf '"%s",' "${tests[@]}" | sed 's/,$//')"
	gate_note="$(printf '{"version":1,"kind":"merge-gates","commit":"%s","ok":true,"passed":%s,"failed":%s,"new_failed":0,"lanes":"%s","tests":[%s],"reproof_of":"%s","reproof_reason":"%s","tests_json":"%s","created":"%s"}' \
		"$sha" "$passed" "${nfailed:-0}" "$lanes" "$tests_arr" "$reproof_of" "$reproof_reason" "$tests_json" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
	[ -z "$reproof_of" ] || echo "dq_merge_gates: re-proof of ${reproof_of:0:12} recorded in the stamp on ${short} (reproof_of, reproof_reason)"
	if git notes --ref=merge-gates add -f -m "$gate_note" "$sha"; then
		echo "dq_merge_gates: stamped ${short} (git notes --ref=merge-gates show $short)"
		if [ "${DQ_LANE_NOTES_PUSH:-1}" != "0" ]; then
			for attempt in 1 2 3; do
				git push -q origin refs/notes/merge-gates:refs/notes/merge-gates 2>/dev/null && break
				git fetch -q origin +refs/notes/merge-gates:refs/notes/merge-gates-remote 2>/dev/null && git notes --ref=merge-gates merge -s cat_sort_uniq refs/notes/merge-gates-remote >/dev/null 2>&1
			done
		fi
	else
		echo "dq_merge_gates: could not write the merge-gates note; dq_push_master.sh will refuse this HEAD" >&2
	fi
fi
echo "dq_merge_gates: all gates passed on $short (timings: $timings)"
