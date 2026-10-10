#!/usr/bin/env bash
# Merge origin/master (or the named ref) into the current branch and settle the generated files.
#
#   bash tools/dq_merge_master.sh              # git fetch origin, then merge origin/master
#   bash tools/dq_merge_master.sh some/ref     # merge another ref (no fetch)
#
# The `analyze gen` output (code/engine/_generated/, code/_generated/reads.dm and
# tgui/packages/tgui/interfaces/generated/) is no longer committed: every build regenerates it
# (doc/rewrite/agent_workflow.md). A branch that still tracks those files gets a modify/delete
# conflict on them when it merges master. This script resolves exactly those conflicts as deleted
# (`git rm --cached`: the file stays on disk), untracks any generated file the branch still tracks,
# commits, and regenerates. Any other conflict is left for you, listed at the end; resolve it and
# commit as usual (the generated paths are already settled).
#
# It never runs checkout, reset, restore, stash or cherry-pick.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GEN_RE='^(code/engine/_generated/|code/_generated/reads\.dm$|tgui/packages/tgui/interfaces/generated/)'
GEN_PATHS=(code/engine/_generated code/_generated/reads.dm tgui/packages/tgui/interfaces/generated)

LOOK_KEYS=code/modules/unit_tests/snapshots/look_keys.txt
ref="${1:-}"
if [ -z "$ref" ]; then
	git fetch -q origin || { echo "dq_merge_master: git fetch failed" >&2; exit 1; }
	ref="origin/master"
fi

merge_rc=0
git merge --no-edit "$ref" || merge_rc=$?

if [ "$merge_rc" -ne 0 ]; then
	mapfile -t conflicted < <(git diff --name-only --diff-filter=U)
	if [ ${#conflicted[@]} -eq 0 ]; then
		echo "dq_merge_master: git merge failed without conflicts (see above)" >&2
		exit "$merge_rc"
	fi
	if printf '%s
' "${conflicted[@]}" | grep -qxF "$LOOK_KEYS"; then
		echo "dq_merge_master: $LOOK_KEYS conflicted; taking our side for now, regenerating it after the merge"
		git show ":2:$LOOK_KEYS" >"$LOOK_KEYS" && git add -- "$LOOK_KEYS"
		mapfile -t conflicted < <(printf '%s
' "${conflicted[@]}" | grep -vxF "$LOOK_KEYS")
	fi
	gen=()
	for f in "${conflicted[@]}"; do
		if [[ "$f" =~ $GEN_RE ]]; then gen+=("$f"); fi
	done
	if [ ${#gen[@]} -gt 0 ]; then
		echo "dq_merge_master: resolving ${#gen[@]} generated file(s) as untracked (the build regenerates them)"
		git rm -q --cached -- "${gen[@]}"
	fi
fi

# Generated files the branch still tracks (it added one, or the merge kept them): untrack them too.
mapfile -t tracked < <(git ls-files -- "${GEN_PATHS[@]}")
if [ ${#tracked[@]} -gt 0 ]; then
	echo "dq_merge_master: untracking ${#tracked[@]} generated file(s)"
	git rm -r -q --cached -- "${GEN_PATHS[@]}"
fi

mapfile -t remaining < <(git diff --name-only --diff-filter=U)
if [ ${#remaining[@]} -gt 0 ]; then
	echo
	echo "dq_merge_master: these conflicts still need you (the generated files are settled):"
	printf '  %s\n' "${remaining[@]}"
	echo "Resolve them, \`git add\` them and \`git commit --no-edit\`, then run tools/build/build.sh gen."
	exit 1
fi

if [ -f .git/MERGE_HEAD ] || git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
	git commit -q --no-edit || { echo "dq_merge_master: commit failed" >&2; exit 1; }
elif [ ${#tracked[@]} -gt 0 ]; then
	git commit -q -m "Untrack the generated analyze output (the build regenerates it)" || exit 1
fi

echo "dq_merge_master: merged $ref; regenerating"
tools/build/build.sh gen || exit 1
# look_keys.txt is a pure function of the tree: never hand-merged, always regenerated after the merge.
bash tools/ci/check_look_keys_format.sh --commit
