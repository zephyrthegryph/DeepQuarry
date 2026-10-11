#!/usr/bin/env bash
# Does a commit carry a passing test stamp? The push gate of tools/dq_push_master.sh and tools/hooks/pre-push
# (doc/rewrite/agent_workflow.md section 14).
#
#   bash tools/dq_push_stamp.sh <commit>      # exit 0 and "STAMPED: ..." when it does, exit 1 and "UNSTAMPED: ..." when not
#
# A commit passes when:
#   - it carries a passing stamp: a lane-ready note (refs/notes/lane-ready, written by tools/dq_lane_ready.sh) or a merge-gates
#     note (refs/notes/merge-gates, written by tools/dq_merge_gates.sh when its test world passed) whose commit is this one and
#     whose result is ok; or
#   - it is already in origin/master; or
#   - it is a merge and every parent passes (the push script's merge of origin/master into a stamped lane, a merge batch of
#     stamped lanes); or
#   - it has one parent that passes and changes only docs, changelogs, tools/ci/known_failures.txt or the look keys (what
#     dq_lane_ready.sh allows after the stamp, and the data-only commits dq_push_master.sh itself adds).
# A merge-gates run with --no-tests stamps nothing here: a stamp means tests ran and passed.
set -uo pipefail

target="${1:-}"
[ -n "$target" ] || { echo "usage: dq_push_stamp.sh <commit>" >&2; exit 2; }
target="$(git rev-parse --verify -q "$target^{commit}")" || { echo "UNSTAMPED: $1 is not a commit"; exit 1; }
master="$(git rev-parse --verify -q refs/remotes/origin/master 2>/dev/null || true)"

# Paths a commit on top of a stamped one may touch without a new stamp.
exempt_path() {
	case "$1" in
		doc/*|html/changelogs/*|*.md|tools/ci/known_failures.txt|code/modules/unit_tests/snapshots/look_keys.txt) return 0 ;;
	esac
	return 1
}

note_ok() { # <ref> <sha> <commit field>: a passing note of that kind on exactly this commit
	local body
	body="$(git notes --ref="$1" show "$2" 2>/dev/null)" || return 1
	grep -q '"ok":true' <<<"$body" && grep -q "\"$3\":\"$2\"" <<<"$body"
}

declare -A seen=()
why=""
passes() { # <sha> <depth>
	local sha="$1" depth="$2" p parents n f
	if [ -n "${seen[$sha]:-}" ]; then [ "${seen[$sha]}" = 1 ]; return; fi
	seen[$sha]=0
	if note_ok lane-ready "$sha" branch_commit; then why="${why}${sha:0:10} lane-ready; "; seen[$sha]=1; return 0; fi
	if note_ok merge-gates "$sha" commit; then why="${why}${sha:0:10} merge-gates; "; seen[$sha]=1; return 0; fi
	if [ -n "$master" ] && git merge-base --is-ancestor "$sha" "$master" 2>/dev/null; then seen[$sha]=1; return 0; fi
	[ "$depth" -gt 0 ] || { why="${why}${sha:0:10} too deep; "; return 1; }
	read -r -a parents <<<"$(git rev-list --parents -n 1 "$sha" | cut -d' ' -f2-)"
	n=${#parents[@]}
	if [ "$n" -ge 2 ]; then
		for p in "${parents[@]}"; do
			passes "$p" $((depth - 1)) || { why="${why}merge ${sha:0:10}: parent ${p:0:10} unstamped; "; return 1; }
		done
		seen[$sha]=1
		return 0
	fi
	[ "$n" -eq 1 ] || { why="${why}${sha:0:10} is a root; "; return 1; }
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		exempt_path "$f" || { why="${why}${sha:0:10} has no stamp and changes $f; "; return 1; }
	done < <(git diff-tree --no-commit-id --name-only -r "$sha")
	passes "${parents[0]}" $((depth - 1)) || return 1
	why="${why}${sha:0:10} docs/data only; "
	seen[$sha]=1
	return 0
}

if passes "$target" 40; then
	echo "STAMPED: ${target:0:12} (${why:-already in origin/master})"
	exit 0
fi
echo "UNSTAMPED: ${target:0:12}: ${why}run bash tools/dq_lane_ready.sh --tests \"...\" on the lane (or tools/dq_merge_gates.sh on a merge batch) first"
exit 1
