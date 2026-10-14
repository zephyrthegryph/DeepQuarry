#!/usr/bin/env bash
# Is this merge commit a lane (or batch) that proved itself, merged into a master that has since moved? If so, prints what to prove again.
#
#   bash tools/dq_reproof_source.sh <merge-commit>      # stdout: line 1 the stamped parent L, line 2 its stamped test list (space separated)
#                                                        # exit 1 and the reason on stderr when there is nothing to re-prove
#
# Used by tools/dq_push_master.sh and tools/dq_merge_gates.sh --reproof-from (doc/rewrite/agent_workflow.md "Re-proof"). A stamp goes stale
# when master changes a global path or a file the lane depends on while the lane's own 25-40 minute run is in flight, and the retry races
# the same way again. The merged tree is the thing that has to be proved, so the gates run the stamped test list on it and the result is
# the fresh stamp. That is allowed only when the lane's own commits are unchanged since the stamp:
#   - HEAD is a merge of exactly two parents: one already in origin/master and one L that is not;
#   - L carries a passing stamp on exactly that commit (a lane-ready note with branch_commit == L, or a merge-gates note with commit == L)
#     and the stamp names its tests. A lane with commits after its stamp has no note on its tip and is refused: it needs tools/dq_lane_ready.sh.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
target="${1:-}"
[ -n "$target" ] || { echo "usage: dq_reproof_source.sh <merge-commit>" >&2; exit 2; }
target="$(git rev-parse --verify -q "$target^{commit}")" || { echo "$1 is not a commit" >&2; exit 1; }
master="$(git rev-parse --verify -q refs/remotes/origin/master 2>/dev/null || true)"
[ -n "$master" ] || { echo "no origin/master" >&2; exit 1; }

read -r -a parents <<<"$(git rev-list --parents -n 1 "$target" | cut -d' ' -f2-)"
[ "${#parents[@]}" -eq 2 ] || { echo "${target:0:10} is not a two-parent merge" >&2; exit 1; }
lane=""
mp=""
for p in "${parents[@]}"; do
	if git merge-base --is-ancestor "$p" "$master" 2>/dev/null; then mp="$p"; else lane="$p"; fi
done
[ -n "$lane" ] && [ -n "$mp" ] || { echo "${target:0:10} does not merge master into one unpushed parent" >&2; exit 1; }

tests=""
note="$(git notes --ref=lane-ready show "$lane" 2>/dev/null || true)"
if [ -n "$note" ] && grep -q '"ok":true' <<<"$note" && grep -q "\"branch_commit\":\"$lane\"" <<<"$note"; then
	tests="$(MSYS2_ARG_CONV_EXCL='*' node -e 'const s = JSON.parse(process.argv[1]); console.log((s.tests || []).map((t) => t.replace(/^\/datum\/unit_test\//, "")).join(" "));' "$note")"
else
	note="$(git notes --ref=merge-gates show "$lane" 2>/dev/null || true)"
	if [ -n "$note" ] && grep -q '"ok":true' <<<"$note" && grep -q "\"commit\":\"$lane\"" <<<"$note"; then
		tests="$(MSYS2_ARG_CONV_EXCL='*' node -e 'const s = JSON.parse(process.argv[1]); console.log((s.tests || []).join(" "));' "$note")"
		if [ -z "$tests" ]; then # an older merge-gates note does not carry its list: the local gate record does
			tests="$(sed -n 's/^tests=//p' "data/merge-gates/${lane:0:12}.ok" 2>/dev/null | head -n 1)"
		fi
	else
		echo "parent ${lane:0:10} has no passing stamp on exactly that commit (its own commits changed since the stamp, or it was never stamped): it needs tools/dq_lane_ready.sh" >&2
		exit 1
	fi
fi
[ -n "$tests" ] || { echo "the stamp on ${lane:0:10} names no tests to re-run" >&2; exit 1; }
echo "$lane"
echo "$tests"
