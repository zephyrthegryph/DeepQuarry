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
#    errors), bash tools/ci/check_ratchets.sh, tools/build/build.sh analyze. Any failure stops here.
# 4. Checks HEAD and the tree did not change meanwhile, then `git push origin HEAD:master` (never forced). If
#    master moved, it merges again and rechecks (up to 3 rounds).
#
# Logs: data/push-check/<sha>.{dm,ratchets,analyze}.log. It never runs checkout, reset, restore, stash or cherry-pick.
# tools/hooks/pre-push refuses a push to master that did not come from here (install: tools/hooks/install_pre_push.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DQ_ANALYZE_PROFILE=release # the gate lints with the full release analyzer, not the local dev-fast one

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

mkdir -p data/push-check
for round in 1 2 3; do
	if why="$(dirty)"; then die "$why: commit (or remove) them first"; fi
	echo "== dq_push_master: round $round: merging origin/master"
	bash tools/dq_merge_master.sh || die "the merge did not complete (resolve, commit, rerun)"
	if why="$(dirty)"; then die "the merge left $why"; fi
	sha="$(git rev-parse HEAD)"
	log="data/push-check/${sha:0:12}"

	echo "== build.sh dm on ${sha:0:12} (log $log.dm.log)"
	rm -f deepquarry.dmb # never "up to date": DreamChecker runs inside the dm target
	tools/build/build.sh dm >"$log.dm.log" 2>&1 || { tail -40 "$log.dm.log"; die "build.sh dm failed"; }
	grep -q "dream-checker: passed" "$log.dm.log" || die "DreamChecker did not run (install it: tools/ci/install_spaceman_dmm.sh); see $log.dm.log"
	grep -q "Found 0 diagnostics" "$log.dm.log" || { grep -iE "error|warning" "$log.dm.log" | head -30; die "DreamChecker reported diagnostics; see $log.dm.log"; }
	grep -qE "deepquarry\.dmb - 0 errors" "$log.dm.log" || die "DreamMaker did not report 0 errors; see $log.dm.log"

	echo "== check_ratchets.sh (log $log.ratchets.log)"
	bash tools/ci/check_ratchets.sh >"$log.ratchets.log" 2>&1 || { tail -30 "$log.ratchets.log"; die "check_ratchets.sh failed"; }
	echo "== build.sh analyze (log $log.analyze.log)"
	tools/build/build.sh analyze >"$log.analyze.log" 2>&1 || { tail -30 "$log.analyze.log"; die "build.sh analyze failed"; }

	[ "$(git rev-parse HEAD)" = "$sha" ] || die "HEAD moved during the checks"
	if why="$(dirty)"; then die "the tree changed during the checks: $why"; fi

	echo "== pushing ${sha:0:12} to origin/master"
	if DQ_PUSH_VERIFIED="$sha" git push origin "$sha:refs/heads/master"; then
		echo "dq_push_master: pushed ${sha:0:12} (checked: dm, DreamChecker, ratchets, analyze)"
		exit 0
	fi
	echo "dq_push_master: push rejected (master moved?); merging again"
	git fetch -q origin || die "git fetch failed"
done
die "master kept moving; rerun"
