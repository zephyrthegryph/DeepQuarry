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
#        dm         tools/build/build.sh dm (production native compile + DreamChecker); no local DreamMaker compile (CI cross-checks with DreamMaker)
#        dreamchecker  build.sh dream-checker over the whole tree (only with --no-dm and DQ_GATE_DREAMCHECKER=1: the train's heavy cycles;
#                   the native compiler accepts what DreamChecker rejects, so the train needs its verdict in the gate, where a failure bisects)
#        ratchets   tools/ci/check_ratchets.sh, then build.sh analyze
#        tgui       tools/build/build.sh tgui-lint                 (only when the batch touches tgui/, or with --tgui)
#        analyze_tests  cargo test in tools/analyze, in a cargo slot (only when the batch touches tools/analyze/ or tools/ci/lint_scopes.toml, which the fixture tests read)
#
# The test list is the cross-branch smoke set (tools/ci/smoke_tests.txt, which includes the boot gate), plus --tests, plus the
# tests of every lane in --lanes whose lane-ready stamp (tools/dq_lane_ready.sh, tools/dq_lane_check.sh) is not valid for this
# master. A lane with a valid stamp is not tested again: its tests ran on its own merge with this master (or with a master that
# changed nothing it depends on), and what remains to be proved is the combination, which the smoke set, the compile and the
# ratchets on the merged HEAD cover. A lane without a stamp needs its tests named with --tests.
#   --no-smoke   leave the smoke set out (tools/dq_lane_ready.sh runs the lane's own list)
#   --no-dm      skip the production compile + DreamChecker job (lane proofs: the test build is a superset; the integration push
#                (tools/dq_push_master.sh, no dm.ok) or the batch train runs the production compile)
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
. tools/dq_below_normal.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
# In the shared merge worktree only the batch that holds the merge lock (tools/dq_merge_worktree.sh) may gate.
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_declared_tests.sh"
merge_lock_require || exit 1
# shellcheck source=tools/dq_proof_cache.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_proof_cache.sh"
# shellcheck source=tools/dq_gate_retry.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_gate_retry.sh"
# shellcheck source=tools/dq_gate_verdicts.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_gate_verdicts.sh"
_lap_t0=$(date +%s)
lap() { echo "== gates: $1 +$(( $(date +%s) - _lap_t0 ))s"; } # where the pre-proof seconds go (the lock is held across them)
merge_lock_busy begin
trap 'merge_lock_busy end' EXIT

orig_args=("$@")
automerge=1
tests_arg=()
lanes=""
smoke_file="tools/ci/smoke_tests.txt"
smoke=1
run_tests=1
snapshot_output=0
tgui=0
serial=0
reproof=0
no_dm=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests) shift; read -r -a more <<<"${1:-}"; tests_arg+=("${more[@]}") ;;
		--lanes) shift; lanes="${1:-}"; lanes="${lanes//,/ }" ;;
		--no-auto-merge) automerge=0 ;;
		--smoke) shift; smoke_file="${1:-}" ;;
		--snapshot-output) snapshot_output=1 ;;
		--no-smoke) smoke=0 ;;
		--no-tests|--no-boot) run_tests=0 ;;
		--no-dm) no_dm=1 ;;
		--tgui) tgui=1 ;;
		--serial) serial=1 ;;
		--reproof) reproof=1 ;;
		-h|--help) sed -n '2,32p' "$0"; echo '  --lanes a,b,c   lanes not yet in HEAD are merged as a batch (tools/dq_merge_batch.sh); --no-auto-merge refuses instead'; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dq_merge_gates: REFUSED: uncommitted changes to tracked files; commit the merge first (the stamp names an exact HEAD)" >&2
	exit 1
fi
# --lanes names lanes that are not merged yet: this is a batch. The batch driver merges them (one build, one union of
# tests) and bisects by lane on a failure, calling this script again per attempt with --no-auto-merge (tools/dq_merge_batch.sh).
if [ "$automerge" -eq 1 ] && [ -n "$lanes" ]; then
	for ref in $lanes; do
		tip="$(git rev-parse -q --verify "$ref^{commit}" 2>/dev/null || git rev-parse -q --verify "origin/$ref^{commit}" 2>/dev/null || true)"
		if [ -n "$tip" ] && ! git merge-base --is-ancestor "$tip" HEAD; then exec bash "$(dirname "${BASH_SOURCE[0]}")/dq_merge_batch.sh" "${orig_args[@]}"; fi
	done
fi
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
# A tree that already carries a covering proof (tools/dq_land.sh and dq_lane_ready.sh prove it before the lock) needs none of the steps
# that exist to prepare a gate run: the generated files, the baseline shrink were all settled when the proof was
# made (the tree is byte-identical), and the lock is held across every second spent here.
early_reuse=0
if [ "$run_tests" -eq 1 ] && [ "$snapshot_output" -eq 0 ] && [ "$reproof" -eq 0 ] && [ "${DQ_PROOF_REUSE:-1}" != 0 ] && [ "${DQ_GATES_NO_EARLY:-0}" != 1 ] && [ -n "$lanes" ] && git rev-parse -q --verify origin/master >/dev/null 	&& proof_covers_tree origin/master "$(proof_tree HEAD)" ${tests_arg[@]+"${tests_arg[@]}"} >/dev/null; then
	early_reuse=1
	echo "== gates: the tree $(proof_tree HEAD | cut -c1-12) already has a covering proof; skipping gen and the baseline shrink"
fi
# The generated files must be fresh before the HEAD is stamped.
if [ "$early_reuse" -eq 0 ]; then
	tools/build/build.sh gen || { echo "dq_merge_gates: gen failed" >&2; exit 1; }
fi
lap "gen and fetch"
pre_shrink_tree="$(proof_tree HEAD)" # the tree a plain merge makes; the shrink below changes it (proof_alias_baseline_shrink)
# A baseline that only needs shrinking after the merge (a fixed site left it) is shrunk into the merge commit, instead of a separate
# repair commit. Only when HEAD is an unpushed merge commit (the merge worktree's batch): a lane-ready run or any other HEAD keeps
# its sha, which its caller already recorded. `analyze baseline --update` never adds a site or raises a ceiling.
# DQ_SHRINK_IN_RATCHETS=1 (the default) moves it into the ratchets job, where the model is already loaded, and records it after the jobs
# pass: a cold `baseline --update` here cost 120-150 s before any job started.
shrink_after=0
if [ "$early_reuse" -eq 0 ] && [ "${DQ_SHRINK_IN_RATCHETS:-1}" = 1 ] && [ "$(git rev-list --parents -n 1 HEAD | awk '{print NF-1}')" = "2" ] && ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
	shrink_after=1
elif [ "$early_reuse" -eq 0 ] && [ "$(git rev-list --parents -n 1 HEAD | awk '{print NF-1}')" = "2" ] && ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null 	&& bin="$(bash tools/ci/analyze.sh 2>/dev/null)"; then
	"$bin" baseline --update >/dev/null 2>&1 || echo "dq_merge_gates: warning: analyze baseline --update failed; baselines left as they are" >&2
	if ! git diff --quiet -- tools/ci; then
		echo "dq_merge_gates: shrank ratchet baselines into the merge commit:"
		git diff --stat -- tools/ci | tail -n 5
		git add -- tools/ci
		git commit -q --amend --no-edit
	fi
fi
lap "fetch and baseline shrink"
sha="$(git rev-parse HEAD)"
short="${sha:0:12}"
mkdir -p data/merge-gates
timings="data/merge-gates/$short.timings"
rm -f "data/merge-gates/$short".{ok,ratchets.ok,dm.ok,dreamchecker.ok,analyze.ok}
: >"$timings"
wall_start=$(date +%s)

if [ "$tgui" -eq 0 ] && git rev-parse -q --verify origin/master >/dev/null; then
	if ! git diff --quiet "$(git merge-base origin/master HEAD)" HEAD -- tgui/ ':!tgui/packages/tgui/interfaces/generated'; then tgui=1; fi
fi

analyze_tests=0
if git rev-parse -q --verify origin/master >/dev/null && ! git diff --quiet "$(git merge-base origin/master HEAD)" HEAD -- tools/analyze/ tools/ci/lint_scopes.toml; then analyze_tests=1; fi

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
		line="${line//$'\r'/}"
		read -r line <<<"$line" # trims the blanks with no fork (an xargs per line cost seconds on Windows, under the merge lock)
		[ -n "$line" ] && add_test "$line"
	done <"$smoke_file"
fi
# The gameplay scenarios (tools/ci/gameplay_tests.txt) run on every landing, with the smoke set.
if [ "$run_tests" -eq 1 ] && [ "$smoke" -eq 1 ] && [ -f tools/ci/gameplay_tests.txt ]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="${line//$'\r'/}"
		read -r line <<<"$line"
		[ -n "$line" ] && add_test "$line"
	done <tools/ci/gameplay_tests.txt
fi
add_test ${tests_arg[@]+"${tests_arg[@]}"}
lane_rows=()
unstamped=()
if [ -n "$lanes" ]; then
	lap "test list (smoke and gameplay)"
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
				# A lane stamped before master deleted or renamed a test still lists it: leave out the exact names no longer declared.
				mapfile -t kept_lt < <(filter_declared_tests "stamp of ${row%% *}" ${lt[@]+"${lt[@]}"})
				add_test ${kept_lt[@]+"${kept_lt[@]}"}
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
	# The stamped list may name tests master has since deleted (a look pin): the same rule as a lane's stale stamp drops them.
	mapfile -t rp_tests < <(filter_declared_tests "re-proof list" ${rp_tests[@]+"${rp_tests[@]}"})
	reproof_reason="$(bash tools/dq_lane_check.sh "$reproof_of" 2>&1 | sed 's/ tests=.*//' | head -n 1 | tr -d '"\\' | head -c 300)"
	echo "== re-proof: the stamp on ${reproof_of:0:12} is stale because master moved; running its full stamped list (${#rp_tests[@]} test(s)) on the merged tree ${sha:0:12}"
	echo "   why: ${reproof_reason:-master moved}"
	add_test "${rp_tests[@]}"
fi
if [ "$run_tests" -eq 1 ] && [ ${#tests[@]} -eq 0 ]; then tests=(dq_boot_gate); fi

# ---- a proof for this exact tree ------------------------------------------------------------------------------------------------
# dq_lane_ready.sh proves a lane on its merge with master and stores the proof under the TREE hash (tools/dq_proof_cache.sh). If master
# has not moved, merging the lane gives that very tree: nothing to rebuild or retest, the stamps for this commit are written from the
# proof. A tree nobody proved (master moved, a batch of several lanes) runs the gates below. DQ_PROOF_REUSE=0 forces them.
lap "test list"
tree="$(proof_tree HEAD)"
proof_file=""
if [ "$run_tests" -eq 1 ] && [ "${DQ_PROOF_REUSE:-1}" != 0 ] && [ -z "$reproof_of" ]; then
	proof_file="$(proof_find "$tree" "$tgui" "$analyze_tests" "${tests[@]}")" || proof_file=""
fi
reused=0
if [ "$early_reuse" -eq 1 ] && [ -z "$proof_file" ]; then
	# The early check named no lane-specific selector (an invalid stamp adds its lane's tests): the steps it skipped are needed after all.
	echo "== gates: the early proof check did not hold for the full test list; starting over without it"
	DQ_GATES_NO_EARLY=1 exec bash "$0" "${orig_args[@]}"
fi
if [ -n "$proof_file" ]; then
	reused=1
	echo "== proof reused: tree ${tree:0:12} was proved on master $(sed -n 's/^master=//p' "$proof_file" | cut -c1-10) ($(sed -n 's/^passed=//p' "$proof_file") test(s) passed); no compile, no test world, no ratchet run"
fi

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

names=()
failed=()
dm_ok=0
dc_ok=0
declare -A pid start
if [ "$reused" -eq 0 ]; then
gate gen tools/build/build.sh gen
# The compiler and the lint engine come from the shared caches (published after the push that changed them, tools/dq_prebuild_tools.sh).
# When one is still missing, build it HERE, once, overlapped with prepare, and before the parallel jobs start: the jobs then all hit the
# cache instead of queueing separate cargo builds (dm and tests each ran the dmbc target). DQ_GATE_PREBUILD_TOOLS=0 turns it off.
tools_pid=""
if [ "${DQ_GATE_PREBUILD_TOOLS:-1}" = "1" ] && [ "$no_dm" -eq 0 -o "$run_tests" -eq 1 ]; then
	( t0=$(date +%s); tools/build/build.sh dmbc; rc=$?; echo "prebuild-compiler $(( $(date +%s) - t0 ))s rc=$rc" | tee -a "$timings"; exit $rc ) &
	tools_pid=$!
fi
gate prepare tools/build/build.sh icon-repack validate-dme verdigris-bindings-check verdigris map-bounds
if [ -n "$tools_pid" ]; then wait "$tools_pid" || echo "dq_merge_gates: warning: compiler prebuild failed; the jobs build it themselves"; fi

job_tests() { gate_tests_with_retry "${tests[@]}"; } # one isolated retry tells a flake from a failure (tools/dq_gate_retry.sh)
job_dm() {
	# Never "up to date": DreamChecker runs inside the dm target and the push script's checks read this log.
	rm -f deepquarry.dmb
	DQ_DREAMCHECKER=1 DQ_DREAMCHECKER_AFTER=1 tools/build/build.sh dm || return 1 # the verdict the push requires; local builds skip it
}
job_dreamchecker() {
	# DQ_DREAMCHECKER=1 makes a missing DreamChecker an error the verdict below catches (no 'dream-checker: passed' line), never a silent pass.
	DQ_DREAMCHECKER=1 tools/build/build.sh dream-checker
}
job_ratchets() {
	# The analyze caches are content-addressed and stamped with the engine's own source hash and lint_scopes.toml (tools/analyze/README.md,
	# "Caches and truth"; tests/cache_truth.rs holds the property), so a warm run answers as a cold one does. The gate still audits that
	# claim: it runs COLD (private cache, no shared seed, no gen store; ~4 min) when the last passing cold run is older than
	# DQ_GATE_COLD_EVERY_MIN (720), when the batch changed tools/analyze or lint_scopes.toml, or when DQ_GATE_COLD=1; otherwise warm.
	local cold_stamp="${DQ_ANALYZE_COLD_STAMP:-E:/dq-cache/analyze-cold-audit.stamp}" want_cold=0 why=""
	if [ "${DQ_GATE_COLD:-0}" = "1" ]; then want_cold=1; why="DQ_GATE_COLD=1"
	elif [ ! -f "$cold_stamp" ] || [ -n "$(find "$cold_stamp" -mmin +"${DQ_GATE_COLD_EVERY_MIN:-720}" 2>/dev/null)" ]; then want_cold=1; why="no cold audit in the last ${DQ_GATE_COLD_EVERY_MIN:-720} min"
	elif [ -n "$(git diff --name-only origin/master HEAD -- tools/analyze tools/ci/lint_scopes.toml 2>/dev/null | head -1)" ]; then want_cold=1; why="the analyzer or its scopes changed"
	fi
	if [ "$want_cold" -eq 1 ]; then
		echo "dq_merge_gates: ratchets run COLD ($why)"
		DQ_ANALYZE_COLD=1 bash tools/ci/check_ratchets.sh || return 1
		mkdir -p "$(dirname "$cold_stamp")" 2>/dev/null; date -u +%FT%TZ >"$cold_stamp" 2>/dev/null || true
	else
		echo "dq_merge_gates: ratchets run WARM (content-keyed caches; the last cold audit is recent: $cold_stamp)"
		bash tools/ci/check_ratchets.sh || return 1
	fi
	# (a second `build.sh analyze` ran here: the same `analyze check` over the same tree that check_ratchets.sh just ran, ~1 min per gate)
	if [ "$shrink_after" -eq 1 ]; then
		local abin
		abin="$(bash tools/ci/analyze.sh 2>/dev/null)" && "$abin" baseline --update >/dev/null 2>&1 || echo "dq_merge_gates: warning: analyze baseline --update failed; baselines left as they are"
	fi
}
job_tgui() { tools/build/build.sh tgui-lint; }
job_analyze_tests() { # the analyzer's own cargo tests: a change under tools/analyze must leave them green (all targets, every failure listed)
	# Compiled harnesses are cached by source hash (tools/build/lib/analyze_test_cache.md); every harness still runs.
	CARGO_TARGET_DIR="$(bash tools/dq_cargo_target.sh analyze-test)" tools/build/build.sh analyze-test
}

[ "$run_tests" -eq 1 ] && names+=(tests)
[ "$no_dm" -eq 1 ] && names+=(ratchets) || names+=(dm ratchets)
dc_key=""
if [ "$no_dm" -eq 1 ] && [ "${DQ_GATE_DREAMCHECKER:-0}" = 1 ]; then
	# DreamChecker has no incremental mode; its verdict is reused when every file it reads is identical to a tree that passed it
	# (tools/dq_gate_verdicts.sh: a lane that changed no DM, or a bisect attempt on a tree already checked). Any DM change runs it.
	dc_key="$(gate_dc_key 2>/dev/null)" || dc_key=""
	if [ -n "$dc_key" ] && dc_prev="$(gate_verdict_has dreamchecker "$dc_key")"; then
		dc_ok=1
		echo "dreamchecker reused 0s" >>"$timings"
		echo "== gates: dreamchecker reused: its inputs (key ${dc_key:0:12}) are identical to a tree that passed it ($dc_prev)"
	else
		names+=(dreamchecker)
	fi
fi
[ "$tgui" -eq 1 ] && names+=(tgui)
[ "$analyze_tests" -eq 1 ] && names+=(analyze_tests)
echo "== gates in parallel: ${names[*]}$([ "$run_tests" -eq 1 ] && echo " (${#tests[@]} test(s): ${tests[*]:0:6}$([ ${#tests[@]} -gt 6 ] && echo ' ...'))")"
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

# The DreamChecker and compiler verdicts, read the way dq_push_master.sh reads them.
if printf '%s\n' "${names[@]}" | grep -qx dm && [[ " ${failed[*]-} " != *" dm "* ]]; then
	dm_log="data/merge-gates/$short.dm.log"
	if grep -q "dream-checker: passed" "$dm_log" && grep -q "Found 0 diagnostics" "$dm_log" && grep -qE "deepquarry\.dmb - 0 errors" "$dm_log"; then
		dm_ok=1
	else
		echo "dq_merge_gates: the production build ran but DreamChecker/the compiler did not report a clean result; see $dm_log" >&2
		failed+=(dm)
	fi
fi

# The standalone DreamChecker job (the train's gate): a clean result needs its own pass line and zero diagnostics.
if printf '%s\n' "${names[@]}" | grep -qx dreamchecker && [[ " ${failed[*]-} " != *" dreamchecker "* ]]; then
	dc_log="data/merge-gates/$short.dreamchecker.log"
	if grep -q "dream-checker: passed" "$dc_log" && grep -q "Found 0 diagnostics" "$dc_log"; then
		dc_ok=1
		gate_verdict_put dreamchecker "$dc_key" "$sha"
	else
		echo "dq_merge_gates: DreamChecker ran but did not report a clean result (or did not run); see $dc_log" >&2
		failed+=(dreamchecker)
	fi
fi

if [ ${#failed[@]} -gt 0 ]; then
	for n in "${failed[@]}"; do
		echo "---- $n: last lines of data/merge-gates/$short.$n.log" >&2
		tail -n 40 "data/merge-gates/$short.$n.log" >&2
		grep -h '^FOCUSED RESULT:\|^FOCUSED RUN CAPPED\|^dq_focused_test: REFUSED' "data/merge-gates/$short.$n.log" >&2 || true
	done
	echo "dq_merge_gates: FAILED: ${failed[*]} (logs data/merge-gates/$short.<job>.log); fix it, recommit, rerun" >&2
	exit 1
fi
else
	dm_ok="$(sed -n 's/^dm=//p' "$proof_file" 2>/dev/null)" # a lane proof (dm=0) leaves the production compile to the push
	[ "$dm_ok" = 1 ] || dm_ok=0
	# The push trusts the train's gate only with a DreamChecker stamp on the exact HEAD: a proof reuse has none unless DreamChecker's
	# inputs match a tree that passed it (tools/dq_gate_verdicts.sh). Without the stamp the push runs the full production build itself.
	if [ "$no_dm" -eq 1 ] && [ "${DQ_GATE_DREAMCHECKER:-0}" = 1 ] && dc_key="$(gate_dc_key 2>/dev/null)" && dc_prev="$(gate_verdict_has dreamchecker "$dc_key")"; then
		dc_ok=1
		echo "== gates: dreamchecker reused with the proof: its inputs (key ${dc_key:0:12}) passed before ($dc_prev)"
	fi
	echo "proof-reused 0s" >>"$timings"
fi

git update-index -q --refresh >/dev/null 2>&1
# A shrunk baseline (shrink_after) is recorded the same way: it only drops fixed sites, so the ratchet verdict cannot change.
record_paths=()
[ "$shrink_after" -eq 1 ] && record_paths+=(tools/ci)
if [ ${#record_paths[@]} -gt 0 ] && [ "$(git rev-parse HEAD)" = "$sha" ] && ! git diff --quiet -- "${record_paths[@]}" 	&& [ -z "$(git diff --name-only -- . "${record_paths[@]/#/:!}")" ] && git diff --cached --quiet; then
	if [ "$shrink_after" -eq 1 ] && ! git diff --quiet -- tools/ci; then
		echo "dq_merge_gates: shrank ratchet baselines into the merge commit:"
		git diff --stat -- tools/ci | tail -n 5
	fi
	git add -- "${record_paths[@]}"
	if [ "$(git rev-list --parents -n 1 HEAD | awk '{print NF-1}')" = "2" ] && ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
		git commit -q --amend --no-edit
	else
		git commit -q -m "Shrink ratchet baselines" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
	fi
	new_sha="$(git rev-parse HEAD)"
	for f in data/merge-gates/"$short".*; do [ -e "$f" ] && cp -f "$f" "data/merge-gates/${new_sha:0:12}${f#data/merge-gates/$short}"; done
	echo "dq_merge_gates: recorded the shrunk baselines into HEAD (${short} -> ${new_sha:0:12})"
	sha="$new_sha"
	short="${sha:0:12}"
	timings="data/merge-gates/$short.timings"
	tree="$(proof_tree HEAD)"
fi
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
if [ "$dc_ok" -eq 1 ]; then echo "$sha" >"data/merge-gates/$short.dreamchecker.ok"; fi
tests_json=""
passed=0
nfailed=0
if [ "$reused" -eq 1 ]; then
	passed="$(sed -n 's/^passed=//p' "$proof_file")"
	nfailed="$(sed -n 's/^failed=//p' "$proof_file")"
	tests_json="$(sed -n 's/^tests_json=//p' "$proof_file")"
elif [ "$run_tests" -eq 1 ]; then
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
	echo "proof_reused=$([ "$reused" -eq 1 ] && echo "$tree")"
	echo "flakes=$(grep -h '^GATE FLAKE: ' "data/merge-gates/$short.tests.log" 2>/dev/null | sed 's/^GATE FLAKE: \(.*\) failed once.*/\1/' | tr '\n' ' ')"
} >"data/merge-gates/$short.ok"
# The proof for this tree (tools/dq_proof_cache.sh): what lets the merge of an unmoved-master lane skip every gate above.
if [ "$reused" -eq 0 ] && [ "$run_tests" -eq 1 ] && { [ "$dm_ok" -eq 1 ] || [ "$no_dm" -eq 1 ]; } && [ "${new_failed:-0}" = "0" ] && [ "${passed:-0}" -gt 0 ]; then
	DQ_PROOF_DM=$((1 - no_dm)) proof_store "$tree" "$base_master" "${tests[*]-}" "${passed:-0}" "${nfailed:-0}" 0 "$tgui" "$analyze_tests" "$tests_json" "${DQ_PROOF_INHERITS:-}"
	proof_alias_baseline_shrink "$pre_shrink_tree" "$tree"
	proof_prune
fi
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
