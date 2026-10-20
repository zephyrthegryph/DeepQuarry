#!/usr/bin/env bash
# Sourced by dq_land.sh and dq_lane_ready.sh: one land or lane-ready per worktree at a time. Two overlapping runs change the tree under
# each other ("the tree changed during the gates; not stamping") and waste both. The lock is a directory in the worktree's lease scratch
# dir (E:/dq-cache/lanes/<pool-slot>/run.lock, DQ_LANE_POOL_LANES), with the holder's pid; a dead holder's lock is replaced. dq_land.sh
# runs dq_lane_ready.sh itself: the child sees DQ_RUN_LOCK_OWNER (the land's pid, alive) and does not queue behind its parent.
#   run_lock_take <what>     refuses (exit 1, naming the holder) when another live run holds this worktree
_rl_dir() {
	local top name
	top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
	name="$(basename "$top")"
	case "$name" in pool-*) ;; *) name="wt-$(printf '%s' "$top" | cksum | cut -d' ' -f1)" ;; esac
	echo "${DQ_LANE_POOL_LANES:-E:/dq-cache/lanes}/$name/run.lock"
}
_rl_alive() { kill -0 "$1" 2>/dev/null || { command -v tasklist >/dev/null 2>&1 && tasklist //FI "PID eq $1" //NH 2>/dev/null | grep -qw "$1"; }; }
run_lock_take() {
	local d pid
	d="$(_rl_dir)"
	mkdir -p "$(dirname "$d")" 2>/dev/null || return 0
	if [ -n "${DQ_RUN_LOCK_OWNER:-}" ] && _rl_alive "$DQ_RUN_LOCK_OWNER" && [ -f "$d/owner" ] && [ "$(sed -n 's/^pid=//p' "$d/owner")" = "$DQ_RUN_LOCK_OWNER" ]; then return 0; fi
	if ! mkdir "$d" 2>/dev/null; then
		pid="$(sed -n 's/^pid=//p' "$d/owner" 2>/dev/null)"
		if [ -n "$pid" ] && _rl_alive "$pid"; then
			echo "REFUSED: another run is already active in this worktree: $(sed -n 's/^what=//p' "$d/owner") (pid $pid, since $(sed -n 's/^since=//p' "$d/owner")). Two overlapping runs change the tree under each other; wait for it, or stop it (kill $pid)." >&2
			return 1
		fi
		rm -rf "$d"; mkdir "$d" 2>/dev/null || return 0
	fi
	printf 'pid=%s\nwhat=%s\nsince=%s\nworktree=%s\n' "$$" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(pwd)" >"$d/owner"
	export DQ_RUN_LOCK_OWNER="$$"
	_RL_HELD="$d"
}
run_lock_release() { [ -n "${_RL_HELD:-}" ] && [ "$(sed -n 's/^pid=//p' "$_RL_HELD/owner" 2>/dev/null)" = "$$" ] && rm -rf "$_RL_HELD"; _RL_HELD=""; return 0; }
