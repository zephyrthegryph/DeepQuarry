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

# Self-update. The server is started from the main checkout, which agents never write and nothing updates, so its copy of this script is
# old by design: after the fetch, when origin/master's copy of it differs from the one running, run that one instead (extracted with git
# show into E:/dq-cache/test-server-self, never into a checkout) so a change to the start path (the verdigris profile below) takes effect
# on the next restart. DQ_TS_SELF=1 marks the re-run; DQ_TS_NO_SELF_UPDATE=1 turns it off.
if [ -z "${DQ_TS_SELF:-}" ] && [ -z "${DQ_TS_NO_SELF_UPDATE:-}" ] && [ -d "$TS" ]; then
	git -C "$TS" fetch -q origin 2>/dev/null
	fresh="$(git -C "$TS" show origin/master:tools/dq_test_server.sh 2>/dev/null | tr -d '\r')"
	mine="$(tr -d '\r' <"${BASH_SOURCE[0]}")"
	if [ -n "$fresh" ] && [ "$fresh" != "$mine" ]; then
		SELF_DIR="${DQ_TS_SELF_DIR:-E:/dq-cache/test-server-self}"
		mkdir -p "$SELF_DIR" && printf '%s\n' "$fresh" >"$SELF_DIR/dq_test_server.sh.$$" && mv -f "$SELF_DIR/dq_test_server.sh.$$" "$SELF_DIR/dq_test_server.sh" \
			&& { echo "dq_test_server: origin/master has a newer copy of this script; running it ($SELF_DIR/dq_test_server.sh)"; DQ_TS_SELF=1 exec bash "$SELF_DIR/dq_test_server.sh" "$@"; }
	fi
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
# The server's DLL uses verdigris/Cargo.toml [profile.server] (opt-level 3, no LTO, incremental); its cargo target in $TS/verdigris/target is kept between
# restarts (nothing here cleans it; tools/ci/disk_budget.toml lists test-server as a permanent worktree), so a Rust edit rebuilds incrementally.
export DQ_VERDIGRIS_PROFILE=server
exec cmd //c "bin\\server.cmd" "${args[@]}"
