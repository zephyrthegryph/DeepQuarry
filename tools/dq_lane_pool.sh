#!/usr/bin/env bash
# The lane worktree pool: lanes lease a worktree from a fixed pool instead of creating and deleting one per lane.
#
#   bash tools/dq_lane_pool.sh lease <branch> [--base REF]   # prints the worktree path; one per lane
#   bash tools/dq_lane_pool.sh release [<branch>|--path P] [--force] [--keep-outputs]
#   bash tools/dq_lane_pool.sh status                          # who holds which slot, how big each worktree is
#   bash tools/dq_lane_pool.sh path <branch>                   # the leased path of a branch (exit 1 if none)
#
# Why: a fresh worktree is a 24k-file checkout (minutes), cold caches (analyzer, icons, node_modules, compile cache) and about 1.5 GB
# of build output that nobody deletes. The pool is DQ_LANE_POOL_SIZE worktrees (default 3) under E:/projects/dq-wt/pool-N, created
# once and reused for the life of the machine. At most DQ_LANE_POOL_SIZE lanes run at once: a 4th lease is refused.
#
# lease <branch>
#   - Refuses when every slot is held ("pool full", with the holders). A lease whose lane is finished (clean worktree, branch tip already
#     in origin/master) is reclaimed first, so a lane that forgot `release` never blocks the pool.
#   - Takes a free slot whose worktree is clean (a dirty one is skipped and named; nothing is ever cleaned for you), fetches, and starts
#     the lane on origin/master: `git switch -c <branch> origin/master`. A branch that already exists and holds commits origin/master
#     lacks is resumed (`git switch <branch>`, nothing moves); one fully merged is restarted (`git switch -C`, which loses nothing
#     because every commit of it is in origin/master). Leasing a branch that already holds a slot returns that slot's path again.
#   - Never runs checkout, reset, restore, stash or cherry-pick, and passes no discard flag to switch: git refuses rather than lose work.
#   - The first lease of a slot creates the worktree (a one-time checkout); every later one is a switch of a few seconds, with
#     icons/gen, node_modules, the analyzer binary and data/analyze-cache still in place.
# release
#   - Refuses a dirty worktree (commit or finish first; --force records the release but leaves the tree and its slot dirty).
#   - Retires the worktree's dmbc daemon (about 8 GB of RAM), deletes its build outputs (the test/production .dmb/.rsc, compiler logs,
#     .dmbc, data/ except analyze-cache) and moves it to a detached origin/master. icons/gen, node_modules links, tools/analyze/target and
#     data/analyze-cache stay: they are the warm part of the pool. --keep-outputs skips the deletion.
#   - Deletes the lane branch only when it is fully merged into origin/master (`git branch -d`); an unmerged branch is kept and named.
#
# State: DQ_LANE_POOL_STATE (default E:/dq-cache/lane-pool): one <slot>.lease file per held slot and a lock directory. Override
# DQ_LANE_POOL_DIR (where pool-N lives) and DQ_LANE_POOL_REPO (the repository) for tests. tools/ci/test_lane_pool.sh runs this in a scratch repo.
# Exit status: 0 ok, 1 error, 3 pool full.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"

POOL_SIZE="${DQ_LANE_POOL_SIZE:-3}"
POOL_DIR="${DQ_LANE_POOL_DIR:-E:/projects/dq-wt}"
STATE_DIR="${DQ_LANE_POOL_STATE:-E:/dq-cache/lane-pool}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${DQ_LANE_POOL_REPO:-$here}"
case "$POOL_SIZE" in ''|*[!0-9]*) echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2 ;; esac
[ "$POOL_SIZE" -ge 1 ] || { echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2; }

die() { echo "dq_lane_pool: $*" >&2; exit "${DIE_CODE:-1}"; }
say() { echo "dq_lane_pool: $*" >&2; }

slot_path() { echo "$POOL_DIR/pool-$1"; }
lease_file() { echo "$STATE_DIR/pool-$1.lease"; }
lease_get() { sed -n "s/^$2=//p" "$(lease_file "$1")" 2>/dev/null | head -n 1; }

LOCK="$STATE_DIR/pool.lock"
lock_take() {
	mkdir -p "$STATE_DIR"
	local i=0
	while ! mkdir "$LOCK" 2>/dev/null; do
		# A lock older than two minutes belongs to a crashed caller (the critical sections below take seconds, except the
		# one-time worktree creation, which refreshes the lock's mtime when it starts).
		if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null; continue; fi
		i=$((i + 1))
		[ "$i" -le 600 ] || die "could not take the pool lock ($LOCK) in 60 s"
		sleep 0.1
	done
	trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}
lock_drop() { rmdir "$LOCK" 2>/dev/null; trap - EXIT; }

wt_clean() { # <path>: no tracked change, no untracked non-ignored file, no merge/rebase/cherry-pick in progress
	local wt="$1" gd m
	git -C "$wt" update-index -q --refresh >/dev/null 2>&1
	gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
	for m in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do [ -e "$gd/$m" ] && return 1; done
	[ -z "$(git -C "$wt" status --porcelain --untracked-files=normal 2>/dev/null | head -n 1)" ]
}

merged_into_master() { # <repo-or-wt> <ref>: every commit of ref is in origin/master
	git -C "$1" merge-base --is-ancestor "$2" origin/master 2>/dev/null
}

# ---- build outputs and the daemon -----------------------------------------------------------------------------------------------
retire_daemon() { # <wt>: ask the dmbc daemon registered for this worktree to retire (tools/build/lib/dmbc_daemons.ts keeps the registry)
	local wt="$1" reg exe
	reg="${DQ_DMBC_DAEMON_DIR:-E:/dq-cache/dmb-daemon/ns}"
	[ -d "$reg" ] || return 0
	for exe in "${DQ_DMBC_EXE:-}" "$wt/tools/dmb/target/release/dmbc.exe" "$wt/tools/dmb/target/release/dmbc" \
		"E:/dq-cache/dmb-target/release/dmbc.exe" "E:/dq-cache/dmb-target/release/dmbc"; do
		[ -n "$exe" ] && [ -x "$exe" ] && break
		exe=""
	done
	WT="$wt" REG="$reg" EXE="$exe" node -e '
		const fs = require("fs"), path = require("path"), cp = require("child_process");
		const norm = (p) => path.resolve(p).replace(/\\/g, "/").toLowerCase().replace(/\/+$/, "");
		const wt = norm(process.env.WT), reg = process.env.REG, exe = process.env.EXE;
		for (const name of fs.readdirSync(reg)) {
			if (!name.endsWith(".json")) continue;
			let e; try { e = JSON.parse(fs.readFileSync(path.join(reg, name), "utf8")); } catch { continue; }
			if (!e.root || norm(e.root) !== wt) continue;
			let out = "no dmbc executable found; registry entry dropped";
			if (exe) {
				const r = cp.spawnSync(exe, ["--daemon-retire"], { env: { ...process.env, DMB_DAEMON_NAMESPACE: e.namespace, DMB_DAEMON_AUTOSTART: "0" }, encoding: "utf8", timeout: 20000, windowsHide: true });
				out = r.status === 0 ? (r.stdout.trim() || "retiring") : "retire failed (" + (r.stderr || r.error?.message || "status " + r.status).trim() + ")";
			}
			console.error("dq_lane_pool: dmbc daemon " + e.namespace + ": " + out);
			try { fs.unlinkSync(path.join(reg, name)); } catch {}
		}' 2>&1 | sed 's/^/  /' >&2 || true
}

drop_outputs() { # <wt>: build outputs only; icons/gen, node_modules, tools/analyze/target and data/analyze-cache stay
	local wt="$1" f d n=0
	for f in "$wt"/deepquarry.*; do
		[ -e "$f" ] || continue
		case "$f" in *.dme|*.dm|*.md) continue ;; esac
		# only files git ignores: never a tracked file
		git -C "$wt" check-ignore -q -- "${f#"$wt"/}" 2>/dev/null || continue
		rm -rf "$f" && n=$((n + 1))
	done
	for f in "$wt"/.dmbc "$wt"/tools/dmb/target "$wt"/verdigris/target "$wt"/data/*; do
		[ -e "$f" ] || continue
		case "$f" in "$wt"/data/analyze-cache) continue ;; esac
		git -C "$wt" check-ignore -q -- "${f#"$wt"/}" 2>/dev/null || continue
		rm -rf "$f" && n=$((n + 1))
	done
	say "dropped $n build output path(s) in $wt"
}

size_of() { du -sk "$1" 2>/dev/null | cut -f1; }

# ---- release ----------------------------------------------------------------------------------------------------------------------
release_slot() { # <slot> <force> <keep_outputs>
	local i="$1" force="$2" keep="$3" wt branch
	wt="$(slot_path "$i")"
	branch="$(lease_get "$i" branch)"
	if [ -d "$wt" ]; then
		if ! wt_clean "$wt"; then
			if [ "$force" -eq 1 ]; then
				say "WARNING: $wt is not clean; --force records the release and leaves the tree as it is (the slot stays unusable until it is cleaned by hand)"
				rm -f "$(lease_file "$i")"
				return 0
			fi
			git -C "$wt" status --short | head -n 8 >&2
			die "$wt is not clean (above): commit or finish it, then release (--force records the release only)"
		fi
		retire_daemon "$wt"
		[ "$keep" -eq 1 ] || drop_outputs "$wt"
		git -C "$wt" fetch -q origin 2>/dev/null
		git -C "$wt" switch -q --detach origin/master || die "could not move $wt to a detached origin/master"
	fi
	rm -f "$(lease_file "$i")"
	if [ -n "$branch" ] && git -C "$REPO" show-ref -q --verify "refs/heads/$branch"; then
		if merged_into_master "$REPO" "$branch"; then
			git -C "$REPO" branch -q -d "$branch" 2>/dev/null && say "deleted merged branch $branch"
		else
			say "branch $branch holds commits origin/master lacks; kept (it is not lost: git log origin/master..$branch)"
		fi
	fi
	say "released pool-$i${branch:+ ($branch)}"
}

reclaim_finished() { # called under the lock: drop leases whose lane is done
	local i wt branch
	for i in $(seq 1 "$POOL_SIZE"); do
		[ -f "$(lease_file "$i")" ] || continue
		wt="$(slot_path "$i")"
		branch="$(lease_get "$i" branch)"
		if [ ! -d "$wt" ]; then rm -f "$(lease_file "$i")"; say "reclaimed pool-$i (worktree gone)"; continue; fi
		wt_clean "$wt" || continue
		if ! git -C "$REPO" show-ref -q --verify "refs/heads/$branch"; then
			release_slot "$i" 0 0; say "reclaimed pool-$i (branch $branch is gone)"; continue
		fi
		if merged_into_master "$REPO" "$branch" && [ "$(git -C "$REPO" rev-parse "refs/heads/$branch")" != "$(lease_get "$i" start)" ]; then
			# the lane committed (tip moved off its start) and all of it is in origin/master: finished. A lane that has not committed yet
			# also sits on a master ancestor, which is why the start commit is recorded.
			release_slot "$i" 0 0; say "reclaimed pool-$i (lane $branch is merged into origin/master)"
		fi
	done
}

# ---- lease ------------------------------------------------------------------------------------------------------------------------
cmd_lease() {
	local branch="" base="origin/master" i wt held=0 free="" skipped=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--base) shift; base="${1:?--base needs a ref}" ;;
			-*) die "unknown argument: $1" ;;
			*) [ -z "$branch" ] || die "one branch per lease"; branch="$1" ;;
		esac
		shift
	done
	[ -n "$branch" ] || die "usage: dq_lane_pool.sh lease <branch>"
	git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name"
	case "$branch" in master|main|rewrite/integ-current) die "'$branch' is not a lane branch" ;; esac

	git -C "$REPO" fetch -q origin || say "warning: git fetch failed; using the last fetched origin/master"
	git -C "$REPO" rev-parse -q --verify "$base" >/dev/null || die "no such base: $base"
	lock_take
	# A lane that already holds a slot gets it back.
	for i in $(seq 1 "$POOL_SIZE"); do
		if [ -f "$(lease_file "$i")" ] && [ "$(lease_get "$i" branch)" = "$branch" ]; then
			wt="$(slot_path "$i")"
			if [ -d "$wt" ] && [ "$(git -C "$wt" symbolic-ref -q --short HEAD)" = "$branch" ]; then
				lock_drop; say "$branch already holds pool-$i"; echo "$wt"; return 0
			fi
			rm -f "$(lease_file "$i")"  # a stale record: the worktree moved on
		fi
	done
	reclaim_finished
	for i in $(seq 1 "$POOL_SIZE"); do [ -f "$(lease_file "$i")" ] && held=$((held + 1)); done
	if [ "$held" -ge "$POOL_SIZE" ]; then
		echo "dq_lane_pool: POOL FULL: $held of $POOL_SIZE lane worktrees are in use; at most $POOL_SIZE lanes run at once (DQ_LANE_POOL_SIZE)." >&2
		for i in $(seq 1 "$POOL_SIZE"); do
			echo "  pool-$i: $(lease_get "$i" branch) since $(lease_get "$i" since) ($(lease_get "$i" owner))" >&2
		done
		echo "  Finish one lane (dq_lane_ready.sh, merge, then 'bash tools/dq_lane_pool.sh release <branch>') and ask again, or wait." >&2
		lock_drop
		return 3
	fi
	for i in $(seq 1 "$POOL_SIZE"); do
		[ -f "$(lease_file "$i")" ] && continue
		wt="$(slot_path "$i")"
		if [ -d "$wt" ] && ! wt_clean "$wt"; then skipped="$skipped pool-$i"; continue; fi
		free="$i"; break
	done
	if [ -z "$free" ]; then
		lock_drop
		die "no usable slot: every free worktree is dirty or mid-merge ($skipped); clean or finish it by hand (nothing is cleaned for you)"
	fi
	i="$free"; wt="$(slot_path "$i")"
	if [ ! -e "$wt/.git" ]; then
		[ -z "$(ls -A "$wt" 2>/dev/null)" ] || { lock_drop; die "$wt exists and is not a worktree; move it away"; }
		say "creating $wt (one-time checkout; later leases are a switch)"
		mkdir -p "$POOL_DIR"
		touch "$LOCK"
		git -C "$REPO" worktree add --detach "$wt" "$base" >&2 || { lock_drop; die "git worktree add failed"; }
	fi
	git -C "$wt" fetch -q origin 2>/dev/null
	if git -C "$REPO" show-ref -q --verify "refs/heads/$branch"; then
		if merged_into_master "$REPO" "$branch"; then
			git -C "$wt" switch -q -C "$branch" "$base" || { lock_drop; die "git switch -C $branch failed in $wt"; }
			say "restarted merged branch $branch on $base"
		else
			git -C "$wt" switch -q "$branch" || { lock_drop; die "git switch $branch failed in $wt (is it checked out in another worktree?)"; }
			say "resumed $branch (it holds commits $base lacks); merge master with: bash tools/dq_merge_master.sh"
		fi
	else
		git -C "$wt" switch -q -c "$branch" "$base" || { lock_drop; die "git switch -c $branch failed in $wt"; }
	fi
	{
		echo "branch=$branch"
		echo "since=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "owner=${DQ_LANE_OWNER:-${USERNAME:-${USER:-unknown}}}"
		echo "base=$base"
		echo "start=$(git -C "$wt" rev-parse HEAD)"
	} >"$(lease_file "$i")"
	lock_drop
	say "leased pool-$i to $branch ($(git -C "$wt" rev-parse --short HEAD) = $base); release with: bash tools/dq_lane_pool.sh release $branch"
	echo "$wt"
}

cmd_release() {
	local target="" force=0 keep=0 i found=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--force) force=1 ;;
			--keep-outputs) keep=1 ;;
			--path) shift; target="$(cd "${1:?--path needs a dir}" 2>/dev/null && pwd -W 2>/dev/null || echo "$1")" ;;
			-*) die "unknown argument: $1" ;;
			*) target="$1" ;;
		esac
		shift
	done
	if [ -z "$target" ]; then
		target="$(git rev-parse --show-toplevel 2>/dev/null)" || die "usage: dq_lane_pool.sh release [<branch>|--path P]"
	fi
	lock_take
	for i in $(seq 1 "$POOL_SIZE"); do
		[ -f "$(lease_file "$i")" ] || continue
		if [ "$(lease_get "$i" branch)" = "$target" ] || [ "$(slot_path "$i")" = "$target" ] || [ "$(cd "$(slot_path "$i")" 2>/dev/null && pwd)" = "$(cd "$target" 2>/dev/null && pwd)" ]; then found="$i"; break; fi
	done
	[ -n "$found" ] || { lock_drop; die "no lease for '$target' (dq_lane_pool.sh status)"; }
	release_slot "$found" "$force" "$keep"
	local rc=$?
	lock_drop
	return "$rc"
}

cmd_status() {
	local i wt held=0
	echo "lane pool: $POOL_SIZE slot(s) under $POOL_DIR (state $STATE_DIR)"
	for i in $(seq 1 "$POOL_SIZE"); do
		wt="$(slot_path "$i")"
		if [ -f "$(lease_file "$i")" ]; then
			held=$((held + 1))
			echo "  pool-$i  LEASED  $(lease_get "$i" branch)  since $(lease_get "$i" since)  ($(lease_get "$i" owner))  $([ -d "$wt" ] && echo "$(( $(size_of "$wt") / 1024 )) MB")"
		elif [ -d "$wt" ]; then
			echo "  pool-$i  free    $(wt_clean "$wt" && echo clean || echo DIRTY)  $(( $(size_of "$wt") / 1024 )) MB"
		else
			echo "  pool-$i  free    (not created yet: the first lease checks it out)"
		fi
	done
	echo "  $held of $POOL_SIZE leased"
}

cmd_path() {
	local i
	for i in $(seq 1 "$POOL_SIZE"); do
		if [ -f "$(lease_file "$i")" ] && [ "$(lease_get "$i" branch)" = "${1:-}" ]; then slot_path "$i"; return 0; fi
	done
	return 1
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
	lease) cmd_lease "$@" ;;
	release) cmd_release "$@" ;;
	status) cmd_status ;;
	path) cmd_path "$@" ;;
	-h|--help|help|"") sed -n '2,37p' "$0"; [ -n "$cmd" ] || exit 2 ;;
	*) echo "dq_lane_pool: unknown command '$cmd' (lease, release, status, path)" >&2; exit 2 ;;
esac
