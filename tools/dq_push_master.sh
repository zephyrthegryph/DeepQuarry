#!/usr/bin/env bash
# The only way to push to master (doc/rewrite/agent_workflow.md). Fails closed: it pushes HEAD to
# origin/master only when the build and the checks have just passed on that exact merged HEAD.
#
#   bash tools/dq_push_master.sh
#
# 1. Refuses a dirty tree (staged or unstaged changes to tracked files, untracked .dm under code/): what is
#    checked must be exactly what is pushed.
# 2. Merges origin/master (tools/dq_merge_master.sh: settles the generated files; any other conflict stops here).
# 3. Runs, on that HEAD: tools/build/build.sh dm (DreamChecker must run and report 0 diagnostics, DreamMaker 0
#    errors), bash tools/ci/check_ratchets.sh, tools/build/build.sh analyze. Any failure stops here. A step that
#    tools/dq_merge_gates.sh already passed on this exact HEAD (data/merge-gates/<sha>.dm.ok, .ratchets.ok, .analyze.ok; it runs
#    them alongside the test world) is not run again; DQ_PUSH_FULL=1 runs everything.
# 4. Checks HEAD and the tree did not change meanwhile, then `git push origin HEAD:master` (never forced). If
#    master moved, it merges again and rechecks (up to 3 rounds).
#
# 5. After the push, refreshes tools/ci/known_failures.txt when a focused run JSON for the pushed head exists (no tests run).
#
# DQ_PUSH_DRY_RUN=1 runs every step and stops where it would push (to prove a stamp or a merge flow without touching master).
# Logs: data/push-check/<sha>.{dm,ratchets,analyze}.log. It never runs checkout, reset, restore, stash or cherry-pick.
# tools/hooks/pre-push refuses a push to master that did not come from here (install: tools/hooks/install_pre_push.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
# The analyzer is the local dev-fast build unless DQ_ANALYZE_PROFILE says otherwise: release and dev-fast are the same source
# (the findings are identical; CI builds release), and a release build is a 2-4 minute non-incremental compile.

die() { echo "dq_push_master: REFUSED: $*" >&2; exit 1; }

dirty() {
	git update-index -q --refresh >/dev/null 2>&1
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "uncommitted changes to tracked files"
		return 0
	fi
	if git ls-files --others --exclude-standard -- 'code/*.dm' 'deepquarry.dme' | grep -q .; then
		echo "untracked .dm files under code/ ($(git ls-files --others --exclude-standard -- 'code/*.dm' | head -3 | tr '\n' ' '))"
		return 0
	fi
	return 1
}

# After a push: if a focused run for the pushed head is on disk, refresh tools/ci/known_failures.txt from it (tests that
# now pass leave the list, still-failing ones get the new sha). No tests run here. A changed list is committed on top of
# the pushed head and pushed (data only: no gate reads it; same DQ_PUSH_VERIFIED rule). Best effort: never fails the push.
# DQ_KNOWN_FAILURES_REFRESH=0 turns it off. A rejected push leaves the commit local; the next dq_push_master carries it.
refresh_known_failures() {
	[ "${DQ_KNOWN_FAILURES_REFRESH:-1}" = "0" ] && return 0
	local rc=0 new
	bash tools/dq_known_failures.sh --refresh-for-head "$1" || rc=$?
	[ "$rc" -eq 10 ] || return 0
	git add tools/ci/known_failures.txt && git commit -q -m "Refresh known failures from the run on ${1:0:10}" || { echo "dq_push_master: known_failures refresh: commit failed (ignored)"; return 0; }
	new="$(git rev-parse HEAD)"
	if DQ_PUSH_VERIFIED="$new" git push -q origin "$new:refs/heads/master"; then
		echo "dq_push_master: pushed known_failures refresh ${new:0:12}"
	else
		echo "dq_push_master: known_failures refresh committed locally (${new:0:12}); push rejected, it goes with the next push"
	fi
	return 0
}

mkdir -p data/push-check
for round in 1 2 3; do
	if why="$(dirty)"; then die "$why: commit (or remove) them first"; fi
	echo "== dq_push_master: round $round: merging origin/master"
	bash tools/dq_merge_master.sh || die "the merge did not complete (resolve, commit, rerun)"
	if why="$(dirty)"; then die "the merge left $why"; fi
	sha="$(git rev-parse HEAD)"
	log="data/push-check/${sha:0:12}"

	# tools/dq_merge_gates.sh runs the production build (DreamMaker + DreamChecker) next to the test world and stamps the exact
	# HEAD when both reported clean. Clean tree and an unmoved HEAD are checked here and below.
	stamped() { # <kind>: did the gates pass this check on exactly this HEAD?
		[ "${DQ_PUSH_FULL:-0}" != "1" ] && [ -f "data/merge-gates/${sha:0:12}.$1.ok" ] && [ "$(cat "data/merge-gates/${sha:0:12}.$1.ok")" = "$sha" ]
	}
	if stamped dm; then
		echo "== build.sh dm: passed (DreamMaker 0 errors, DreamChecker 0 diagnostics) on exactly this HEAD in tools/dq_merge_gates.sh; not repeated"
	else
		echo "== build.sh dm on ${sha:0:12} (log $log.dm.log)"
		rm -f deepquarry.dmb # never "up to date": DreamChecker runs inside the dm target
		tools/build/build.sh dm >"$log.dm.log" 2>&1 || { tail -40 "$log.dm.log"; die "build.sh dm failed"; }
		grep -q "dream-checker: passed" "$log.dm.log" || die "DreamChecker did not run (install it: tools/ci/install_spaceman_dmm.sh); see $log.dm.log"
		grep -q "Found 0 diagnostics" "$log.dm.log" || { grep -iE "error|warning" "$log.dm.log" | head -30; die "DreamChecker reported diagnostics; see $log.dm.log"; }
		grep -qE "deepquarry\.dmb - 0 errors" "$log.dm.log" || die "DreamMaker did not report 0 errors; see $log.dm.log"
	fi

	# The same check on the same commit is not run twice; a new merge commit, a different HEAD or DQ_PUSH_FULL=1 runs it here.
	if stamped ratchets; then
		echo "== check_ratchets.sh: passed on exactly this HEAD in tools/dq_merge_gates.sh; not repeated"
	else
		echo "== check_ratchets.sh (log $log.ratchets.log)"
		bash tools/ci/check_ratchets.sh >"$log.ratchets.log" 2>&1 || { tail -30 "$log.ratchets.log"; die "check_ratchets.sh failed"; }
	fi
	if stamped analyze; then
		echo "== build.sh analyze: passed on exactly this HEAD in tools/dq_merge_gates.sh; not repeated"
	else
		echo "== build.sh analyze (log $log.analyze.log)"
		tools/build/build.sh analyze >"$log.analyze.log" 2>&1 || { tail -30 "$log.analyze.log"; die "build.sh analyze failed"; }
	fi

	[ "$(git rev-parse HEAD)" = "$sha" ] || die "HEAD moved during the checks"
	if why="$(dirty)"; then die "the tree changed during the checks: $why"; fi

	if [ "${DQ_PUSH_DRY_RUN:-0}" = "1" ]; then
		echo "dq_push_master: DRY RUN: ${sha:0:12} passed every check (dm, DreamChecker, ratchets, analyze); not pushing"
		exit 0
	fi
	echo "== pushing ${sha:0:12} to origin/master"
	if DQ_PUSH_VERIFIED="$sha" git push origin "$sha:refs/heads/master"; then
		echo "dq_push_master: pushed ${sha:0:12} (checked: dm, DreamChecker, ratchets, analyze)"
		refresh_known_failures "$sha"
		exit 0
	fi
	echo "dq_push_master: push rejected (master moved?); merging again"
	git fetch -q origin || die "git fetch failed"
done
die "master kept moving; rerun"
