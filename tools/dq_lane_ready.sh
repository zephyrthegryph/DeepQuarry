#!/usr/bin/env bash
# A lane runs this when it is finished. It proves the lane on its merge with the current master, once, and stamps the proof, so the
# merge agent does not prove it again (doc/rewrite/agent_workflow.md section 10).
#
#   bash tools/dq_lane_ready.sh --tests "dq_foo dq_bar/*" [--covers 'code/game/machinery/**'] [--no-merge]
#
#   1. refuses a dirty tree, master and a detached HEAD
#   2. merges current origin/master (tools/dq_merge_master.sh: settles the generated files, regenerates)
#   3. runs tools/dq_merge_gates.sh on that merge: gen, the test world with the cross-branch smoke set, your --tests, the gameplay
#      scenarios (tools/ci/gameplay_tests.txt, always), the production compile + DreamChecker, the ratchets
#      and the analyzer, in parallel (tgui lint when the lane touches tgui/). There are no look pins (deleted 2026-10-17)
#   4. if the gates re-recorded snapshot files (tools/dq_pin.sh families), commits them; any other tracked change the gates
#      made is an error
#   5. writes the stamp: a git note on HEAD in refs/notes/lane-ready (JSON: branch, the commit, the master commit merged and
#      tested against, the tests, --covers, the results), a copy in data/lane-ready/, and pushes the notes ref (best effort;
#      DQ_LANE_NOTES_PUSH=0 keeps it local, which is enough for worktrees of this clone)
#
# --lite re-proves cheaply when master moved under a stamped lane (tools/dq_land.sh passes it): if the lane's previous stamp is VALID against
# the new master (master changed none of what the stamp depends on: tools/dq_lane_check.js --lite) and origin/master's own tree carries a
# passing proof of the smoke set, the gates run the boot gate, the lane's stamped tests, your --tests, the gameplay scenarios and the tests of
# the lanes that landed on master since (their stamps), not the rest of the smoke set; the proof records `inherits=<master's tree>` so a
# later merge of this lane counts master's proof for the smoke selectors. Compile, DreamChecker and the ratchets still run on the merged tree.
# --reuse-gates completes stamping from existing successful evidence for the unchanged
# current commit; every requested selector must already occur in that proof. It does
# not merge, compile or run tests. Use it only after diagnosing a wrapper failure.
# --tests names the lane's own tests (names or globs as dq_focused_test.sh takes them). --covers adds globs the stamp depends on
# beyond the files the lane changed and their directories: if master later changes a file under them, the stamp is stale and the
# merge reruns the lane's tests. Commit nothing after this except changelogs and docs; a later code commit makes the stamp stale.
# The merge agent's side: tools/dq_lane_check.sh <branch>, tools/dq_merge_gates.sh --lanes "<branches>".
# Exit status: 0 stamped, 1 a gate failed (nothing stamped), 2 a usage problem.
set -uo pipefail
# The gates keep the full end-of-test staleness sweep (dq_focused_test.sh would otherwise bound it).
export DQ_STALENESS=full
cd "$(git rev-parse --show-toplevel)"
# The merge below can bring in a newer copy of this very script (a fix lands on master, the lane only gets it by merging). The running
# bash would keep executing the old text, so remember the script and its hash now and re-run the new copy after the merge.
self_path="tools/dq_lane_ready.sh"
self_sum="$(git hash-object "$self_path" 2>/dev/null || true)"
orig_args=("$@")
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_run_lock.sh"
run_lock_take "dq_lane_ready.sh $(git symbolic-ref -q --short HEAD)" || exit 1
trap run_lock_release EXIT
. "$(dirname "${BASH_SOURCE[0]}")/dq_proof_cache.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_declared_tests.sh"

tests=()
covers=()
merge=1
reuse_gates=0
lite=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tests) shift; read -r -a more <<<"${1:-}"; tests+=("${more[@]}") ;;
		--tests-file) shift; while IFS= read -r l; do l="${l%%#*}"; l="$(echo "$l" | tr -d '\r' | xargs)"; [ -n "$l" ] && tests+=("$l"); done <"${1:?--tests-file needs a file}" ;;
		--covers) shift; covers+=("${1:?--covers needs a glob}") ;;
		--no-pins) echo "dq_lane_ready: --no-pins is deprecated and does nothing: there are no look pins" >&2 ;;
		--no-merge) merge=0 ;;
		--reuse-gates) reuse_gates=1 ;;
		--lite) lite=1 ;;
		-h|--help) sed -n '2,28p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

die() { echo "dq_lane_ready: $1" >&2; exit "${2:-1}"; }

branch="$(git symbolic-ref -q --short HEAD)" || die "REFUSED: a detached HEAD; check out the lane's branch" 2
case "$branch" in master|rewrite/integ-current) die "REFUSED: $branch is not a lane branch" 2 ;; esac
# Lanes live in the worktree pool (tools/dq_lane_pool.sh): a fixed set of leased worktrees, not one created and deleted per lane.
case "$(git rev-parse --show-toplevel)" in
	*/dq-wt/pool-[0-9]*|*/dq-wt/merge-base) ;;
	*) if [ "${DQ_LANE_POOL_STRICT:-0}" = 1 ]; then die "REFUSED: $(git rev-parse --show-toplevel) is not a pool worktree; lease one: bash tools/dq_lane_pool.sh lease <branch>" 2
	   else echo "dq_lane_ready: WARNING: this is not a pool worktree; lanes get worktrees only from the pool (bash tools/dq_lane_pool.sh lease <branch>)" >&2; fi ;;
esac
git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then die "REFUSED: uncommitted changes to tracked files; commit the lane first (the stamp names an exact commit)" 2; fi
if git ls-files --others --exclude-standard -- 'code/*.dm' deepquarry.dme | grep -q .; then die "REFUSED: untracked .dm files under code/; add and commit them" 2; fi

# Check every --tests name and glob against the declared test types now, before the merge, the gen and any compile: a typo or a missing
# dir prefix (dq_eg2/) used to surface after a 30 minute run. --list expands without compiling and prints close matches for a miss.
if [ ${#tests[@]} -gt 0 ]; then
	bash tools/dq_focused_test.sh --list "${tests[@]}" >/dev/null || die "REFUSED: --tests names a test that does not exist (close matches above); nothing was merged or compiled" 2
fi

t_start=$(date +%s)
# The lite decision is made before master is merged in: the lane's stamp sits on the pre-merge tip.
lite_tests=()
lite_master=""
lite_tree=""
if [ "$lite" -eq 1 ] && [ "$reuse_gates" -eq 0 ] && [ "$merge" -eq 1 ]; then
	git fetch -q origin 2>/dev/null
	git fetch -q origin +refs/notes/lane-ready:refs/notes/lane-ready 2>/dev/null
	lite_line="$(node tools/dq_lane_check.js --lite "$branch" 2>/dev/null)"
	case "$lite_line" in
		LITE*)
			lite_master="$(git rev-parse origin/master)"
			lite_tree="$(git rev-parse "$lite_master^{tree}")"
			mapfile -t smoke_sel < <(proof_smoke_tests)
			if proof_find "$lite_tree" 0 0 "${smoke_sel[@]}" >/dev/null; then
				IFS=, read -r -a lite_tests <<<"${lite_line##* tests=}"
				echo "== lane-ready: lite re-proof: ${lite_line%% tests=*}"
				echo "   master ${lite_master:0:10} carries a proof of the smoke set; running ${#lite_tests[@]} test(s): ${lite_tests[*]:0:8}$([ ${#lite_tests[@]} -gt 8 ] && echo ' ...')"
			else
				echo "== lane-ready: lite re-proof not used: origin/master's tree ${lite_tree:0:10} has no covering proof; running the full list"
				lite_tree=""
			fi
			;;
		*) echo "== lane-ready: lite re-proof not used: ${lite_line:-no verdict}" ;;
	esac
fi
if [ "$reuse_gates" -eq 1 ]; then
	echo "== lane-ready: reusing completed gates for the unchanged current commit"
elif [ "$merge" -eq 1 ]; then
	echo "== lane-ready: merging origin/master into $branch"
	bash tools/dq_merge_master.sh || die "the merge with origin/master did not complete (resolve, commit, rerun)"; if [ -z "${DQ_LANE_READY_REEXEC:-}" ] && [ -n "$self_sum" ] && [ "$(git hash-object "$self_path" 2>/dev/null)" != "$self_sum" ]; then echo "== lane-ready: the merge changed $self_path; re-running the merged copy"; DQ_LANE_READY_REEXEC=1 exec bash "$self_path" ${orig_args[@]+"${orig_args[@]}"}; fi
else
	git fetch -q origin || die "git fetch failed"
	git merge-base --is-ancestor origin/master HEAD || die "REFUSED: --no-merge, but origin/master has commits $branch does not; rerun without --no-merge" 2
fi
if [ "$reuse_gates" -eq 1 ]; then
	master="$(git merge-base origin/master HEAD)"
else
	master="$(git rev-parse origin/master)"
fi
git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then die "the merge left uncommitted changes"; fi

list=(${tests[@]+"${tests[@]}"})
gate_extra=()
if [ -n "$lite_tree" ] && [ "$master" = "$lite_master" ] && [ ${#lite_tests[@]} -gt 0 ]; then
	mapfile -t lite_tests < <(filter_declared_tests "lite re-proof list" "${lite_tests[@]}")
	for l in ${lite_tests[@]+"${lite_tests[@]}"}; do case " ${list[*]-} " in *" $l "*) ;; *) list+=("$l") ;; esac; done
	gate_extra=(--no-smoke)
	export DQ_PROOF_INHERITS="$lite_tree"
elif [ -n "$lite_tree" ]; then
	echo "== lane-ready: master moved again while merging (${lite_master:0:10} -> ${master:0:10}); the lite re-proof is dropped, running the full list"
fi
# The gameplay scenarios run on every landing, whatever the lane (tools/ci/gameplay_tests.txt, doc/testing.md "Gameplay scenarios").
gameplay_file="tools/ci/gameplay_tests.txt"
if [ -f "$gameplay_file" ]; then
	while IFS= read -r l; do
		l="${l%%#*}"; l="$(echo "$l" | tr -d '\r' | xargs)"
		[ -n "$l" ] || continue
		case " ${list[*]-} " in *" $l "*) ;; *) list+=("$l") ;; esac
	done <"$gameplay_file"
fi
if [ ${#list[@]} -eq 0 ]; then echo "dq_lane_ready: no --tests given: proving the smoke set only" >&2; fi

tested="$(git rev-parse HEAD)"
evidence_alt=""
echo "== lane-ready: gates on ${tested:0:10} (master ${master:0:10}): ${list[*]:-the smoke set}"
gate_args=(--snapshot-output ${gate_extra[@]+"${gate_extra[@]}"})
if [ ${#list[@]} -gt 0 ]; then gate_args+=(--tests "${list[*]}"); fi
if [ "$reuse_gates" -eq 0 ]; then
	bash tools/dq_merge_gates.sh ${gate_args[@]+"${gate_args[@]}"} || die "the gates failed; nothing was stamped (logs under data/merge-gates/${tested:0:12}.*.log)"
fi

# The gates may move HEAD before they record it: they shrink ratchet baselines into an unpushed merge commit
# (amend) and record snapshots, and the evidence is named by the HEAD they ended on. Follow HEAD when it moved, provided the
# old commit is an ancestor or was amended in place (same tree plus the gates' own files), so the proof always matches what is stamped.
if [ "$reuse_gates" -eq 0 ]; then
	after="$(git rev-parse HEAD)"
	if [ "$after" != "$tested" ]; then
		echo "== lane-ready: the gates moved HEAD ${tested:0:10} -> ${after:0:10}; proof is read for the new HEAD"
		# The gates run the tests on the commit they started from, then shrink ratchet baselines into the merge commit. When
		# tools/ci/*_baseline.txt files are the whole difference, the run recorded against the old commit is evidence for the new one.
		shrink_other="$(git diff --name-only "$tested" "$after" 2>/dev/null | grep -v -E '^tools/ci/[^/]*_baseline\.txt$' || true)"
		if [ -z "$shrink_other" ]; then
			evidence_alt="$tested"
			echo "== lane-ready: only tools/ci/*_baseline.txt (or nothing) differ between ${tested:0:10} (tested) and ${after:0:10}; test evidence for ${tested:0:10} is accepted for ${after:0:10}"
		fi
		tested="$after"
	fi
fi
# An interrupted gate can return without evidence; absence is never a passing result.
ok_file="data/merge-gates/${tested:0:12}.ok"
if ! { [ -s "$ok_file" ] && grep -Fxq "sha=$tested" "$ok_file"; }; then
	found="$(sed -n 's/^sha=//p' "$ok_file" 2>/dev/null)"
	die "the gates produced no matching result; nothing was stamped
  expected: $ok_file containing sha=$tested
  found:    ${found:-no such file or no sha line} (HEAD now $(git rev-parse HEAD); other proofs: $(ls data/merge-gates/*.ok 2>/dev/null | tail -n 3 | tr '
' ' '))
  if the gates passed on another commit, rerun; do not hand-edit the evidence"
fi
if [ "$reuse_gates" -eq 1 ]; then
	completed_tests=" $(sed -n 's/^tests=//p' "$ok_file") "
	for selector in "${list[@]}"; do
		case "$completed_tests" in
			*" $selector "*) ;;
			*) die "reused proof does not contain requested selector: $selector" ;;
		esac
	done
fi
for marker in dm ratchets analyze; do
	[ "$(cat "data/merge-gates/${tested:0:12}.${marker}.ok" 2>/dev/null)" = "$tested" ] || die "missing $marker evidence; nothing was stamped"
done

# A pass may re-record snapshot files; anything else the gates changed is a mistake.
git update-index -q --refresh >/dev/null 2>&1
changed="$(git status --porcelain --untracked-files=no)"
if [ -n "$changed" ]; then
	other="$(printf '%s\n' "$changed" | grep -v ' code/modules/unit_tests/snapshots/' || true)"
	[ -z "$other" ] || die "the gates changed tracked files that are not snapshots (not stamping):
$other"
	git add -u code/modules/unit_tests/snapshots
	git add -- code/modules/unit_tests/snapshots/op_bases 2>/dev/null || true
	git commit -q -m "Record snapshots after the lane-ready run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" || die "could not commit the recorded snapshots"
	echo "== lane-ready: committed the recorded snapshots"
fi
head_sha="$(git rev-parse HEAD)"
# The commit above (snapshots re-recorded) changes the tree the gates proved, by exactly what the proving run wrote: the proof
# covers that tree too, so merging this lane into an unmoved master needs no second proof (tools/dq_proof_cache.sh).
proof_alias "$(proof_tree "$tested")" "$(proof_tree HEAD)"

ok_file="data/merge-gates/${tested:0:12}.ok"
passed="$(sed -n 's/^passed=//p' "$ok_file")"
failed="$(sed -n 's/^failed=//p' "$ok_file")"
# Failures tools/ci/known_failures.txt lists do not fail the gates; the stamp is ok when nothing else failed (an old .ok: every failure).
new_failed="$(sed -n 's/^new_failed=//p' "$ok_file")"
new_failed="${new_failed:-${failed:-0}}"
tests_json="$(sed -n 's/^tests_json=//p' "$ok_file")"
MSYS2_ARG_CONV_EXCL='*' node -e '
	const fs = require("fs");
	const [file, passed, failed, newFailed, tested, alt] = process.argv.slice(1);
	if (![passed, failed, newFailed].every(x => /^[0-9]+$/.test(x)) || Number(passed) < 1 || Number(newFailed) !== 0) process.exit(1);
	let result;
	try { result = JSON.parse(fs.readFileSync(file, "utf8")); } catch { process.exit(1); }
	// A run JSON names its commit abbreviated (10 hex digits, as in its file name): match it as a prefix of the tested sha.
	const c = String(result.commit || "");
	if (c.length < 10 || !(tested.startsWith(c) || (alt && alt.startsWith(c))) || result.counts?.passed !== Number(passed) || result.counts?.failed !== Number(failed)) process.exit(1);
' "$tests_json" "$passed" "$failed" "$new_failed" "$tested" "$evidence_alt" || die "missing or inconsistent test evidence; nothing was stamped"
mkdir -p data/lane-ready
stamp_json="$(MSYS2_ARG_CONV_EXCL='*' node -e '
	const fs = require("fs");
	const [branch, head, tested, master, testsCsv, coversCsv, passed, failed, testsJson, timingsFile, started, newFailed] = process.argv.slice(1);
	const timings = {};
	try { for (const l of fs.readFileSync(timingsFile, "utf8").split(/\r?\n/)) { const m = /^(\S+) (\d+)s/.exec(l); if (m) timings[m[1]] = Number(m[2]); } } catch {}
	console.log(JSON.stringify({
		version: 1, branch, branch_commit: head, tested_commit: tested, master_commit: master,
		tests: testsCsv ? testsCsv.split(",") : [], covers: coversCsv ? coversCsv.split(",") : [],
		ok: Number(newFailed) === 0, passed: Number(passed), failed: Number(failed), new_failed: Number(newFailed), tests_json: testsJson,
		gate_seconds: timings, created: new Date().toISOString(), host: require("os").hostname(),
	}));' "$branch" "$head_sha" "$tested" "$master" "$(IFS=,; echo "${list[*]-}")" "$(IFS=,; echo "${covers[*]-}")" "${passed:-0}" "${failed:-0}" "$tests_json" "data/merge-gates/${tested:0:12}.timings" "$t_start" "$new_failed")" || die "could not build the stamp"
printf '%s\n' "$stamp_json" >"data/lane-ready/${branch//\//_}.json"
git notes --ref=lane-ready add -f -m "$stamp_json" HEAD || die "could not write the stamp note"

if [ "${DQ_LANE_NOTES_PUSH:-1}" != "0" ]; then
	pushed=0
	for attempt in 1 2 3; do
		if git push -q origin refs/notes/lane-ready:refs/notes/lane-ready 2>/dev/null; then pushed=1; break; fi
		# Another lane pushed its note first: take theirs (notes on different commits never conflict) and try again.
		git fetch -q origin +refs/notes/lane-ready:refs/notes/lane-ready-remote 2>/dev/null && git notes --ref=lane-ready merge -s cat_sort_uniq refs/notes/lane-ready-remote >/dev/null 2>&1
	done
	if [ "$pushed" -eq 1 ]; then echo "== lane-ready: pushed refs/notes/lane-ready"; else echo "== lane-ready: could not push refs/notes/lane-ready (the stamp is in this clone; push the notes ref by hand)" >&2; fi
fi
echo "LANE READY: $branch ${head_sha:0:10} on master ${master:0:10}: ${passed:-0} passed, ${failed:-0} failed in $(( $(date +%s) - t_start ))s (stamp: git notes --ref=lane-ready show HEAD)"
echo "Push the branch ($branch); do not commit code after this, or the stamp goes stale."
