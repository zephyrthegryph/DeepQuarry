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
# 4. Refuses unless HEAD, or each parent of the merge, carries a passing lane-ready / merge-gates test stamp
#    (tools/dq_push_stamp.sh; tools/dq_lane_ready.sh and tools/dq_merge_gates.sh write them).
#    Checks HEAD and the tree did not change meanwhile, then `git push origin HEAD:master` (never forced). If
#    master moved, it merges again and rechecks (up to 3 rounds).
#
# 5. After the push, fetches and fails loudly unless origin/master contains the pushed commit and every expected lane tip. Nothing is
#    committed after a push (the known_failures auto-refresh is gone; a still-failing known test is printed by tools/dq_merge_gates.sh).
#
# Expected lane tips: `--expect "ref ref"` / DQ_PUSH_EXPECT, plus lane_tips= from data/merge-gates/<HEAD>.ok (tools/dq_merge_gates.sh --lanes).
# Each must be in HEAD before the push and in origin/master after it. A push that would change nothing ("Everything up-to-date")
# is refused (DQ_PUSH_ALLOW_NOOP=1 allows it). On the merge worktree branch (rewrite/integ-current, or DQ_PUSH_STRICT=1) a push is
# also refused when origin/master is not the base_master= the gates recorded: master moved since the gates started, re-run them.
#
# DQ_PUSH_DRY_RUN=1 runs every step and stops where it would push (to prove a stamp or a merge flow without touching master).
# Logs: data/push-check/<sha>.{dm,ratchets,analyze}.log. It never runs checkout, reset, restore, stash or cherry-pick.
# tools/hooks/pre-push refuses a push to master that did not come from here (install: tools/hooks/install_pre_push.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
# The analyzer is the local dev-fast build unless DQ_ANALYZE_PROFILE says otherwise: release and dev-fast are the same source
# (the findings are identical; CI builds release), and a release build is a 2-4 minute non-incremental compile.

die() { echo "dq_push_master: REFUSED: $*" >&2; exit 1; }

# In the shared merge worktree only the batch that holds the merge lock (tools/dq_merge_worktree.sh) may push; a landed push (or a HEAD
# already in origin/master) ends the batch and frees the lock.
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"
merge_lock_require || exit 1
merge_lock_busy begin
trap 'merge_lock_busy end' EXIT
# The batch ends with the push wherever it ran from: a lane that restamps and pushes from its own worktree after a refused push still frees
# the lock it holds (the old check only released from inside the merge worktree, which leaked the lock on that path).
release_batch() { merge_lock_busy end; if merge_lock_holder_check 2>/dev/null; then merge_lock_release; fi; }

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

expected_tips=()
add_expect() { # <ref-or-sha>...
	local r t
	for r in "$@"; do
		[ -n "$r" ] || continue
		t="$(git rev-parse -q --verify "$r^{commit}" 2>/dev/null || git rev-parse -q --verify "origin/$r^{commit}" 2>/dev/null)" || die "--expect '$r' does not resolve to a commit"
		case " ${expected_tips[*]-} " in *" $t "*) ;; *) expected_tips+=("$t") ;; esac
	done
}
while [ $# -gt 0 ]; do
	case "$1" in
		--expect) shift; read -r -a more <<<"${1:-}"; add_expect "${more[@]}" ;;
		-h|--help) sed -n '2,24p' "$0"; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done
if [ -n "${DQ_PUSH_EXPECT:-}" ]; then read -r -a more <<<"$DQ_PUSH_EXPECT"; add_expect "${more[@]}"; fi

# The gates' record for the HEAD we start on: lane tips to land, and the origin/master they started from.
gate_record() { # <key>: value from data/merge-gates/<HEAD>.ok of the starting HEAD
	local h f
	h="$(git rev-parse HEAD)"
	f="data/merge-gates/${h:0:12}.ok"
	[ -f "$f" ] && sed -n "s/^$1=//p" "$f" | tail -n 1
}
start_lane_tips="$(gate_record lane_tips)"
start_base="$(gate_record base_master)"
if [ -n "$start_lane_tips" ]; then
	IFS=, read -r -a more <<<"$start_lane_tips"
	add_expect "${more[@]}"
fi
strict=0
if [ "${DQ_PUSH_STRICT:-}" = "1" ] || { [ "${DQ_PUSH_STRICT:-}" != "0" ] && [ "$(git rev-parse --abbrev-ref HEAD)" = "rewrite/integ-current" ]; }; then strict=1; fi
if [ "$strict" -eq 1 ] && [ -n "$start_base" ]; then
	git fetch -q origin || die "git fetch failed"
	now_master="$(git rev-parse origin/master)"
	[ "$now_master" = "$start_base" ] || die "origin/master moved since the gates started (${start_base:0:12} -> ${now_master:0:12}): re-run tools/dq_merge_worktree.sh, the merges and tools/dq_merge_gates.sh, then push again"
fi

# After a push: origin/master must contain what was pushed and every expected lane tip. A no-op push exits 0 in git; this does not.
verify_landed() { # <sha>
	local t miss=()
	git fetch -q origin || die "git fetch failed after the push; cannot confirm it landed"
	git merge-base --is-ancestor "$1" origin/master || die "after the push origin/master ($(git rev-parse --short=12 origin/master)) does not contain ${1:0:12}"
	for t in "${expected_tips[@]-}"; do
		[ -n "$t" ] || continue
		git merge-base --is-ancestor "$t" origin/master || miss+=("${t:0:12}")
	done
	[ ${#miss[@]} -eq 0 ] || die "after the push origin/master does not contain expected lane tip(s): ${miss[*]}"
}

mkdir -p data/push-check
for round in 1 2 3; do
	if why="$(dirty)"; then die "$why: commit (or remove) them first"; fi
	echo "== dq_push_master: round $round: merging origin/master"
	bash tools/dq_merge_master.sh || die "the merge did not complete (resolve, commit, rerun)"
	if why="$(dirty)"; then die "the merge left $why"; fi
	bash tools/ci/check_look_keys_format.sh --commit || die "look_keys.txt normalization failed"
	sha="$(git rev-parse HEAD)"
	log="data/push-check/${sha:0:12}"

	# Re-proof: the lane's (or batch's) stamp went stale only because master moved while it was being gated, and its own commits are
	# unchanged (a stamp on exactly its tip). Instead of refusing and sending it round another 30 minute lap that master can outrun
	# again, the gates run its full stamped test list on this merged tree; that run is the fresh stamp, and it records reproof_of.
	if ! pre_stamp="$(bash tools/dq_push_stamp.sh "$sha" 2>&1)" && [ "${DQ_PUSH_NO_REPROOF:-0}" != "1" ] && bash tools/dq_reproof_source.sh "$sha" >/dev/null 2>&1; then
		echo "== re-proof: ${pre_stamp:0:300}"
		echo "== re-proof: running the stamped test list on the merged tree ${sha:0:12} (tools/dq_merge_gates.sh --reproof)"
		reproof_lanes="${expected_tips[*]-}"
		bash tools/dq_merge_gates.sh --reproof ${reproof_lanes:+--lanes "$reproof_lanes"} || die "the re-proof gates failed on ${sha:0:12}; fix the failure (or rerun tools/dq_lane_ready.sh on the lane)"
		sha="$(git rev-parse HEAD)"
		log="data/push-check/${sha:0:12}"
		echo "== re-proof passed: HEAD is now ${sha:0:12} and carries the fresh stamp"
	fi

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
	# The tests: HEAD (or each parent of a merge, docs/data-only commits on top excepted) must carry a passing lane-ready or
	# merge-gates stamp (tools/dq_push_stamp.sh, agent_workflow.md section 14). The pre-push hook checks the same.
	stamp_verdict="$(bash tools/dq_push_stamp.sh "$sha")" || die "$stamp_verdict"
	echo "== test stamp: $stamp_verdict"

	for t in "${expected_tips[@]-}"; do
		[ -n "$t" ] || continue
		git merge-base --is-ancestor "$t" "$sha" || die "expected lane tip ${t:0:12} is not in HEAD ${sha:0:12}: the merge worktree was moved or the lane was not merged; re-merge it and rerun the gates"
	done
	if git merge-base --is-ancestor "$sha" origin/master && [ "${DQ_PUSH_ALLOW_NOOP:-0}" != "1" ]; then
		release_batch
		die "HEAD ${sha:0:12} is already in origin/master: pushing would change nothing (the lane's work is not in this HEAD, or it already landed)"
	fi

	if [ "${DQ_PUSH_DRY_RUN:-0}" = "1" ]; then
		echo "dq_push_master: DRY RUN: ${sha:0:12} passed every check (dm, DreamChecker, ratchets, analyze); not pushing"
		exit 0
	fi
	echo "== pushing ${sha:0:12} to origin/master"
	if DQ_PUSH_VERIFIED="$sha" git push origin "$sha:refs/heads/master"; then
		verify_landed "$sha"
		release_batch
		echo "dq_push_master: pushed ${sha:0:12} (checked: dm, DreamChecker, ratchets, analyze); origin/master contains it${expected_tips[*]:+ and ${#expected_tips[@]} expected lane tip(s)}"
		exit 0
	fi
	echo "dq_push_master: push rejected (master moved?); merging again"
	git fetch -q origin || die "git fetch failed"
done
die "master kept moving; rerun"
