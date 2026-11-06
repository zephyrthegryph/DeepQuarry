#!/usr/bin/env bash
# The permanent local test server (AGENTS.md section 4; doc/rewrite/agent_workflow.md "The test-server folder").
#   bash tools/dq_test_server.sh [--no-update] [server args, e.g. --port=1337]
# Runs from the dedicated worktree E:/projects/dq-wt/test-server (outside the lane pool; pool release never touches it and
# `dq_worktree.sh gc` never removes it). It fast-forwards that worktree to origin/master, then starts bin\server.cmd, which
# serves config/example on port 1337. Saves live in that worktree's data/player_saves (gitignored), which a fast-forward leaves alone.
# Refuses when the worktree has uncommitted changes. Never uses reset, checkout, stash or clean. Agents never run or touch it.
set -uo pipefail
TS="${DQ_TEST_SERVER_DIR:-E:/projects/dq-wt/test-server}"
die() { echo "dq_test_server: $*" >&2; exit 1; }
SELF_MAIN="$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"

if [ ! -d "$TS/.git" ] && [ ! -f "$TS/.git" ]; then
	echo "dq_test_server: creating the test-server worktree at $TS (detached at origin/master)"
	git -C "$SELF_MAIN" fetch -q origin || die "git fetch failed"
	git -C "$SELF_MAIN" worktree add --detach "$TS" origin/master || die "could not create the worktree"
	mkdir -p "$TS/data/player_saves"
fi

update=1
args=()
for a in "$@"; do case "$a" in --no-update) update=0 ;; *) args+=("$a") ;; esac; done

dirty="$(git -C "$TS" status --porcelain --untracked-files=normal 2>/dev/null)"
if [ -n "$dirty" ]; then
	echo "$dirty" | head -10 >&2
	die "the test-server worktree $TS has uncommitted changes (above): commit or discard them by hand, then run this again. Nothing was updated or started."
fi

if [ "$update" = 1 ]; then
	git -C "$TS" fetch -q origin || die "git fetch failed; nothing started (use --no-update to start the current tree)"
	before="$(git -C "$TS" rev-parse --short HEAD)"
	git -C "$TS" merge --ff-only origin/master || die "cannot fast-forward $TS to origin/master (it has diverged); nothing started"
	echo "dq_test_server: $before -> $(git -C "$TS" rev-parse --short HEAD)"
fi

echo "dq_test_server: starting bin\\server.cmd in $TS (config/example, port 1337); saves in $TS/data/player_saves"
cd "$TS" || die "cannot enter $TS"
exec cmd //c "bin\\server.cmd" "${args[@]}"
