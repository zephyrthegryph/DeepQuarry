#!/usr/bin/env bash
# Sourced by the merge tooling (dq_merge_master.sh, dq_lane_pool.sh).
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
# The merge driver for tools/ci/lint_scopes.toml (.gitattributes merge=dq-lint-scopes; tools/ci/lint_scopes_merge_driver.sh): two sides
# that lower ceilings on the same or adjacent lines merge to the lower values; anything else conflicts as a text merge would.
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-lint-scopes.driver" "GIT_CONFIG_VALUE_$_dq_n=bash tools/ci/lint_scopes_merge_driver.sh %O %A %B %P"
_dq_n=$((_dq_n + 1))
export "GIT_CONFIG_KEY_$_dq_n=merge.dq-lint-scopes.name" "GIT_CONFIG_VALUE_$_dq_n=lint_scopes.toml: the lower ceiling wins"
_dq_n=$((_dq_n + 1))
export GIT_CONFIG_COUNT="$_dq_n"
unset _dq_n _dq_k

