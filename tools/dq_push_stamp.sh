#!/usr/bin/env bash
# Does a commit carry a passing test stamp? The push gate of tools/dq_push_master.sh and tools/hooks/pre-push
# (doc/rewrite/agent_workflow.md section 14).
#
#   bash tools/dq_push_stamp.sh <commit>      # exit 0 and "STAMPED: ..." when it does, exit 1 and "UNSTAMPED: ..." when not
#
# A commit passes when:
#   - it carries a passing stamp: a lane-ready note (refs/notes/lane-ready, written by tools/dq_lane_ready.sh) or a merge-gates
#     note (refs/notes/merge-gates, written by tools/dq_merge_gates.sh when its test world ran) on exactly that commit, ok; or
#   - it is already in origin/master; or
#   - it is a merge of master into one stamped parent L and the stamp carries across it (a re-merge after master moved):
#       (a) the merge is clean: `git merge-tree` of L and the master parent has no conflict, and the merge commit's tree differs
#           from that clean result only in regenerated files (look_keys.txt, snapshots/op_bases/);
#       (b) what master changed since the stamp's master base is disjoint from what the stamp depends on: for a lane-ready
#           stamp, tools/dq_lane_check.js --master <master parent> L says VALID (the lane's files and directories, the files
#           defining its tests, the snapshot directories they read, its --covers globs, the global paths; regenerated files do
#           not count); for a merge-gates stamp (a merge batch), master's changes are disjoint from the batch's files and
#           directories and from tools/ci/lane_ready_global.txt;
#       (c) the compile, DreamChecker and the ratchets pass on the merged tree: tools/dq_push_master.sh runs them on exactly
#           this commit before it pushes, and the pre-push hook only lets through what that script verified.
#     Otherwise the lane needs a fresh stamp (tools/dq_lane_ready.sh);
#   - it has one parent that passes and changes only docs, changelogs, *.md, tools/ci/known_failures.txt or the look keys.
# A merge-gates run with --no-tests stamps nothing here: a stamp means tests ran and passed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

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

# Files regenerated from the tree after a merge: a difference there is not a difference.
regenerated() {
	case "$1" in
		code/modules/unit_tests/snapshots/look_keys.txt|code/modules/unit_tests/snapshots/op_bases/*) return 0 ;;
	esac
	return 1
}

note_ok() { # <ref> <sha> <commit field>: a passing note of that kind on exactly this commit
	local body
	body="$(git notes --ref="$1" show "$2" 2>/dev/null)" || return 1
	grep -q '"ok":true' <<<"$body" && grep -q "\"$3\":\"$2\"" <<<"$body"
}

in_master() { [ -n "$master" ] && git merge-base --is-ancestor "$1" "$master" 2>/dev/null; }

# (a): the merge of $1 and $2 is clean and $3's tree is that result, regenerated files aside.
clean_merge() {
	local tree f out rc=0
	# --name-only: the tree, then one line per conflicted file, then a blank line and the messages. A conflict confined to regenerated
	# files is not a conflict: dq_merge_master.sh regenerates them after the merge (look_keys.txt) and the pin factoring rewrites
	# op_bases/, so whatever the trial merge left in them is compared away below.
	out="$(git merge-tree --write-tree --name-only "$1" "$2" 2>/dev/null)" || rc=$?
	if [ "$rc" -gt 1 ] || [ -z "$out" ]; then
		why="${why}git merge-tree failed on ${1:0:10} and ${2:0:10}; "
		return 1
	fi
	tree="$(head -n 1 <<<"$out")"
	if [ "$rc" -eq 1 ]; then
		while IFS= read -r f; do
			[ -n "$f" ] || break
			regenerated "$f" && continue
			why="${why}merging ${2:0:10} into ${1:0:10} conflicts in $f; "
			return 1
		done < <(tail -n +2 <<<"$out")
	fi
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		regenerated "$f" && continue
		why="${why}${3:0:10} differs from the clean merge in $f; "
		return 1
	done < <(git diff --name-only "$tree" "$3")
	return 0
}

# (b) for a merge-gates stamp: master's changes since the batch's base touch none of its files, their directories or a global path.
batch_disjoint() { # <batch> <master parent>
	local base f d
	base="$(git merge-base "$1" "$2")" || return 1
	local -A own=() dirs=()
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		own[$f]=1
		dirs[${f%/*}/]=1
	done < <(git diff --name-only "$base" "$1")
	mapfile -t globals < <(grep -v '^\s*#' tools/ci/lane_ready_global.txt 2>/dev/null | sed '/^\s*$/d')
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		regenerated "$f" && continue
		d="${f%/*}/"
		if [ -n "${own[$f]:-}" ] || [ -n "${dirs[$d]:-}" ]; then why="${why}master changed $f, which the batch ${1:0:10} touches; "; return 1; fi
		for g in "${globals[@]}"; do
			case "$f" in "$g"*) why="${why}master changed the global path $f; "; return 1 ;; esac
		done
	done < <(git diff --name-only "$base" "$2")
	return 0
}

declare -A seen=()
why=""
passes() { # <sha> <depth>
	local sha="$1" depth="$2" p parents n f verdict
	if [ -n "${seen[$sha]:-}" ]; then [ "${seen[$sha]}" = 1 ]; return; fi
	seen[$sha]=0
	if note_ok lane-ready "$sha" branch_commit; then why="${why}${sha:0:10} lane-ready; "; seen[$sha]=1; return 0; fi
	if note_ok merge-gates "$sha" commit; then why="${why}${sha:0:10} merge-gates; "; seen[$sha]=1; return 0; fi
	if in_master "$sha"; then seen[$sha]=1; return 0; fi
	[ "$depth" -gt 0 ] || { why="${why}${sha:0:10} too deep; "; return 1; }
	read -r -a parents <<<"$(git rev-list --parents -n 1 "$sha" | cut -d' ' -f2-)"
	n=${#parents[@]}
	if [ "$n" -ge 2 ]; then
		local lane="" mp="" others=0
		for p in "${parents[@]}"; do
			if in_master "$p"; then [ -n "$mp" ] || mp="$p"; else lane="$p"; others=$((others + 1)); fi
		done
		if [ "$others" -eq 0 ]; then seen[$sha]=1; return 0; fi
		if [ "$others" -gt 1 ] || [ -z "$mp" ]; then
			why="${why}merge ${sha:0:10} joins several unstamped parents: run tools/dq_merge_gates.sh on it; "
			return 1
		fi
		clean_merge "$lane" "$mp" "$sha" || return 1
		if node tools/dq_lane_check.js --master "$mp" "$lane" >/tmp/dq_push_stamp.$$ 2>&1; then
			why="${why}${lane:0:10}'s stamp carries across the re-merge ${sha:0:10} ($(sed 's/ tests=.*//' /tmp/dq_push_stamp.$$ | cut -d' ' -f3- | head -c 160)); "
			rm -f /tmp/dq_push_stamp.$$
			seen[$sha]=1
			return 0
		fi
		verdict="$(sed 's/ tests=.*//' /tmp/dq_push_stamp.$$ | head -c 300)"
		rm -f /tmp/dq_push_stamp.$$
		if note_ok merge-gates "$lane" commit && ! note_ok lane-ready "$lane" branch_commit; then
			batch_disjoint "$lane" "$mp" || return 1
			why="${why}the batch ${lane:0:10}'s stamp carries across the re-merge ${sha:0:10}; "
			seen[$sha]=1
			return 0
		fi
		why="${why}the re-merge ${sha:0:10} needs a fresh stamp: ${verdict}; "
		return 1
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
