#!/usr/bin/env bash
# Sourced by the merge tooling (dq_merge_master.sh, dq_merge_worktree.sh, dq_merge_gates.sh, dq_push_master.sh, dq_lane_ready.sh).
# Turns git's automatic stashing off for every git command the script runs, whatever a repository, worktree or user config says
# (merge --autostash / merge.autoStash, rebase.autoStash, pull.autoStash). Stashing is forbidden in these checkouts, and on a dirty
# or half-merged tree an automatic one fails halfway and leaves a stale index. Nothing in the tools passes --autostash.
_dq_n="${GIT_CONFIG_COUNT:-0}"
for _dq_k in merge.autoStash rebase.autoStash pull.autoStash; do
	export "GIT_CONFIG_KEY_$_dq_n=$_dq_k" "GIT_CONFIG_VALUE_$_dq_n=false"
	_dq_n=$((_dq_n + 1))
done
# The merge driver for tools/ci/*_baseline.txt (.gitattributes merge=dq-baseline; tools/ci/baseline_merge_driver.sh), supplied per command
# like the lines above so a clean worktree needs no `git config`. A branch whose tree lacks the script gets a normal conflict.
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-baseline.driver" "GIT_CONFIG_VALUE_$_dq_n=bash tools/ci/baseline_merge_driver.sh %O %A %B %P"
_dq_n=$((_dq_n + 1))
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-baseline.name" "GIT_CONFIG_VALUE_$_dq_n=shrink-only baseline merge"
_dq_n=$((_dq_n + 1))
# The merge driver for deepquarry.dme (.gitattributes merge=dq-dme; tools/build/dme_merge_driver.sh): the generated manifest merges by
# its include sets, never by text. A branch whose tree lacks the script gets the driver's failure, and git a normal conflict.
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-dme.driver" "GIT_CONFIG_VALUE_$_dq_n=bash tools/build/dme_merge_driver.sh %O %A %B %P"
_dq_n=$((_dq_n + 1))
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-dme.name" "GIT_CONFIG_VALUE_$_dq_n=generated deepquarry.dme: merge the include sets"
_dq_n=$((_dq_n + 1))
export GIT_CONFIG_COUNT="$_dq_n"
unset _dq_n _dq_k

# dq_clean_tracked <label>: put every tracked file (working tree and index) back to HEAD's content, without checkout, reset, restore or
# stash. A gate attempt leaves tracked edits behind when it fails (the in-job baseline shrink of dq_merge_gates.sh, a formatter, a
# half-finished merge); `git switch --detach` then carries them into the next attempt, whose gates refuse a dirty tree, or the switch
# itself fails ("local changes would be overwritten"). Logs each dirty path to stderr and returns 0; the count is in DQ_CLEANED_N.
dq_clean_tracked() {
	local label="${1:-tree}" f n=0
	DQ_CLEANED_N=0
	[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ] && { echo "$label: unfinished merge found; aborting it" >&2; git merge --abort >/dev/null 2>&1; }
	git update-index -q --refresh >/dev/null 2>&1
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		n=$((n + 1))
		if git cat-file -e "HEAD:$f" 2>/dev/null; then
			git show "HEAD:$f" >"$f" && git add -- "$f"
		else
			git rm -q -f --cached -- "$f" >/dev/null 2>&1
			rm -f -- "$f"
		fi
		echo "$label: $f restored to HEAD" >&2
	done < <(git diff --name-only HEAD 2>/dev/null)
	DQ_CLEANED_N=$n
	return 0
}
