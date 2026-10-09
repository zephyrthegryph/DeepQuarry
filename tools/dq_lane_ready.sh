#!/usr/bin/env bash
# A lane runs this when it is finished. It proves the lane on its merge with the current master, once, and stamps the proof, so the
# merge agent does not prove it again (doc/rewrite/agent_workflow.md section 10).
#
#   bash tools/dq_lane_ready.sh --tests "dq_foo dq_bar/*" [--covers 'code/game/machinery/**'] [--no-pins] [--no-merge]
#
#   1. refuses a dirty tree, master and a detached HEAD
#   2. merges current origin/master (tools/dq_merge_master.sh: settles the generated files, regenerates)
#   3. runs tools/dq_merge_gates.sh on that merge: gen, the test world with the cross-branch smoke set, your --tests and the
#      incremental look pins (dq_look_state_pin, dq_look_tree_pin: only the types whose analyzer key moved are probed, so a lane
#      that did not touch a look costs nothing; --no-pins leaves them out), the production compile + DreamChecker, the ratchets
#      and the analyzer, in parallel (tgui lint when the lane touches tgui/)
#   4. if the pins re-recorded the look keys or snapshots, commits them ("Record look keys"); any other tracked change the gates
#      made is an error
#   5. writes the stamp: a git note on HEAD in refs/notes/lane-ready (JSON: branch, the commit, the master commit merged and
#      tested against, the tests, --covers, the results), a copy in data/lane-ready/, and pushes the notes ref (best effort;
#      DQ_LANE_NOTES_PUSH=0 keeps it local, which is enough for worktrees of this clone)
#
# --tests names the lane's own tests (names or globs as dq_focused_test.sh takes them). --covers adds globs the stamp depends on
# beyond the files the lane changed and their directories: if master later changes a file under them, the stamp is stale and the
# merge reruns the lane's tests. Commit nothing after this except changelogs and docs; a later code commit makes the stamp stale.
# The merge agent's side: tools/dq_lane_check.sh <branch>, tools/dq_merge_gates.sh --lanes "<branches>".
# Exit status: 0 stamped, 1 a gate failed (nothing stamped), 2 a usage problem.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

tests=()
covers=()
pins=1
merge=1
while [ $# -gt 0 ]; do
	case "$1" in
		--tests) shift; read -r -a more <<<"${1:-}"; tests+=("${more[@]}") ;;
		--tests-file) shift; while IFS= read -r l; do l="${l%%#*}"; l="$(echo "$l" | tr -d '\r' | xargs)"; [ -n "$l" ] && tests+=("$l"); done <"${1:?--tests-file needs a file}" ;;
		--covers) shift; covers+=("${1:?--covers needs a glob}") ;;
		--no-pins) pins=0 ;;
		--no-merge) merge=0 ;;
		-h|--help) sed -n '2,28p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

die() { echo "dq_lane_ready: $1" >&2; exit "${2:-1}"; }

branch="$(git symbolic-ref -q --short HEAD)" || die "REFUSED: a detached HEAD; check out the lane's branch" 2
case "$branch" in master|rewrite/integ-current) die "REFUSED: $branch is not a lane branch" 2 ;; esac
git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then die "REFUSED: uncommitted changes to tracked files; commit the lane first (the stamp names an exact commit)" 2; fi
if git ls-files --others --exclude-standard -- 'code/*.dm' deepquarry.dme | grep -q .; then die "REFUSED: untracked .dm files under code/; add and commit them" 2; fi

t_start=$(date +%s)
if [ "$merge" -eq 1 ]; then
	echo "== lane-ready: merging origin/master into $branch"
	bash tools/dq_merge_master.sh || die "the merge with origin/master did not complete (resolve, commit, rerun)"
else
	git fetch -q origin || die "git fetch failed"
	git merge-base --is-ancestor origin/master HEAD || die "REFUSED: --no-merge, but origin/master has commits $branch does not; rerun without --no-merge" 2
fi
master="$(git rev-parse origin/master)"
git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then die "the merge left uncommitted changes"; fi

list=(${tests[@]+"${tests[@]}"})
if [ "$pins" -eq 1 ] && [ -f code/modules/unit_tests/dq_look_pins.dm ]; then list+=(dq_look_state_pin dq_look_tree_pin); fi
if [ ${#list[@]} -eq 0 ]; then echo "dq_lane_ready: no --tests given: proving the smoke set only" >&2; fi

tested="$(git rev-parse HEAD)"
echo "== lane-ready: gates on ${tested:0:10} (master ${master:0:10}): ${list[*]:-the smoke set}"
gate_args=()
if [ ${#list[@]} -gt 0 ]; then gate_args+=(--tests "${list[*]}"); fi
bash tools/dq_merge_gates.sh ${gate_args[@]+"${gate_args[@]}"} || die "the gates failed; nothing was stamped (logs under data/merge-gates/${tested:0:12}.*.log)"

# The pins re-record look_keys.txt and the look snapshots after a pass; anything else the gates changed is a mistake.
git update-index -q --refresh >/dev/null 2>&1
changed="$(git status --porcelain --untracked-files=no)"
if [ -n "$changed" ]; then
	other="$(printf '%s\n' "$changed" | grep -v ' code/modules/unit_tests/snapshots/' || true)"
	[ -z "$other" ] || die "the gates changed tracked files that are not look snapshots (not stamping):
$other"
	git add -u code/modules/unit_tests/snapshots
	git commit -q -m "Record look keys after the lane-ready run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" || die "could not commit the recorded look keys"
	echo "== lane-ready: committed the recorded look keys/snapshots"
fi
head_sha="$(git rev-parse HEAD)"

ok_file="data/merge-gates/${tested:0:12}.ok"
passed="$(sed -n 's/^passed=//p' "$ok_file")"
failed="$(sed -n 's/^failed=//p' "$ok_file")"
tests_json="$(sed -n 's/^tests_json=//p' "$ok_file")"
mkdir -p data/lane-ready
stamp_json="$(node -e '
	const fs = require("fs");
	const [branch, head, tested, master, testsCsv, coversCsv, passed, failed, testsJson, timingsFile, started] = process.argv.slice(1);
	const timings = {};
	try { for (const l of fs.readFileSync(timingsFile, "utf8").split(/\r?\n/)) { const m = /^(\S+) (\d+)s/.exec(l); if (m) timings[m[1]] = Number(m[2]); } } catch {}
	console.log(JSON.stringify({
		version: 1, branch, branch_commit: head, tested_commit: tested, master_commit: master,
		tests: testsCsv ? testsCsv.split(",") : [], covers: coversCsv ? coversCsv.split(",") : [],
		ok: Number(failed) === 0, passed: Number(passed), failed: Number(failed), tests_json: testsJson,
		gate_seconds: timings, created: new Date().toISOString(), host: require("os").hostname(),
	}));' "$branch" "$head_sha" "$tested" "$master" "$(IFS=,; echo "${list[*]-}")" "$(IFS=,; echo "${covers[*]-}")" "${passed:-0}" "${failed:-0}" "$tests_json" "data/merge-gates/${tested:0:12}.timings" "$t_start")" || die "could not build the stamp"
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
