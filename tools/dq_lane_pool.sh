#!/usr/bin/env bash
# The lane worktree pool: lanes lease a worktree from a fixed pool instead of creating and deleting one per lane.
#
#   bash tools/dq_lane_pool.sh lease <branch> [--base REF]   # prints the worktree path; one per lane
#   bash tools/dq_lane_pool.sh lease <branch> --wait [--timeout MIN]  # queue (first come first served) instead of failing when full
#   bash tools/dq_lane_pool.sh lease <branch> --class general|compiler|light   # which slots (below); a tools/dmb* branch is compiler
#   bash tools/dq_lane_pool.sh release [<branch>|--path P] [--force] [--keep-outputs]
#   bash tools/dq_lane_pool.sh status                          # who holds which slot, how big each worktree is
#   bash tools/dq_lane_pool.sh path <branch>                   # the leased path of a branch (exit 1 if none)
#   bash tools/dq_lane_pool.sh cancel <branch>                 # withdraw a queued `lease --wait` ticket; that waiter exits 4 ("cancelled"), nothing is killed
#   bash tools/dq_lane_pool.sh stuck [--quiet]                 # list STUCK leases (below); exit 1 when there are any, so a coordinator can poll
#
# Classes (what the lane is, not how important): general = pool-1..N (a game lane: DM compile, test worlds); compiler = pool-c1, pool-c2
# (DQ_LANE_POOL_COMPILER, default 2), reserved: general lanes never take them, and a compiler lane is served ahead of the general queue
# (it uses a free general slot too when both reserved ones are held); light = pool-light, ONE shared slot for small work that needs no
# game build (docs, lane tooling scripts, Rust/compiler-only changes): it never runs a DM compile or a test world (tools/dq_machine_slots.sh
# refuses them there), the lane edits, commits, pushes and releases within minutes, and `bash tools/dq_land.sh --light` lands every pushed
# light branch in one batched merge (tools/dq_land_batch.sh). Compiler holders also get first claim on the machine slots.
#
# Why: a fresh worktree is a 24k-file checkout (minutes), cold caches (analyzer, icons, node_modules, compile cache) and about 1.5 GB
# of build output that nobody deletes. The pool is DQ_LANE_POOL_SIZE worktrees (default 3: one DM compile slot serves about three lanes plus the train) under E:/projects/dq-wt/pool-N, created
# once and reused for the life of the machine. At most DQ_LANE_POOL_SIZE general lanes run at once: one more lease is refused.
#
# lease <branch>
#   - Refuses when every slot is held ("pool full", with the holders). A lease whose lane is finished (clean worktree, branch tip already
#     in origin/master) and idle for DQ_LANE_POOL_RECLAIM_IDLE_MIN minutes (default 180; nothing touched the lease, HEAD or index) is
#     reclaimed first, so a lane that forgot `release` never blocks the pool, but a lane between two of its merges keeps its slot.
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
# Stuck and idle leases (`status`, `stuck`): a lease is STUCK when no live process uses its worktree (no process command line naming the
# path, and no machine slot held or queued for it) and nothing has changed in it for DQ_LANE_POOL_STUCK_MIN minutes (default 30): the
# lease file, HEAD, index, reflog, any modified or untracked file, the data/logs and data/runs trees, or a *.log at its root. A stuck lease
# is only REPORTED, with how long it has been idle, whether its tree is dirty and whether commits are unpushed; a notice is written under
# $STATE_DIR/notices/pool-N.stuck (removed when the lease is active again or gone). Nothing is ever wiped: a dirty tree, or a branch with
# commits that are neither in origin/master nor in origin/<branch>, keeps its slot until its owner (or a human) releases it. A stuck lease
# that is clean and whose commits are all pushed or merged is reclaimed by the next lease, once idle for the reclaim limit below. Why the
# old reclaim never fired for a dead lane with uncommitted work: it skips every dirty tree (`wt_clean || continue`) and reclaims only a
# lane whose branch is merged and whose tip moved off its start, so a stopped dirty lane was invisible to it for ever. `status` also shows,
# per leased slot, a machine-slot wait (dm_compile / test_world queue entries of that worktree, from tools/dq_machine_slots.sh waiting).
#
# State: DQ_LANE_POOL_STATE (default E:/dq-cache/lane-pool): one <slot>.lease file per held slot and a lock directory. Override
# DQ_LANE_POOL_DIR (where pool-N lives) and DQ_LANE_POOL_REPO (the repository) for tests. tools/ci/test_lane_pool.sh runs this in a scratch repo.
# Exit status: 0 ok, 1 error, 3 pool full, 4 a queued lease was cancelled (stuck: 1 when any lease is stuck).
set -uo pipefail
_dq_dir="${BASH_SOURCE[0]%/*}"; [ "$_dq_dir" = "${BASH_SOURCE[0]}" ] && _dq_dir=.   # no dirname fork: a fork costs a few hundred ms on a loaded host
. "$_dq_dir/dq_git_safe.sh"

POOL_SIZE="${DQ_LANE_POOL_SIZE:-3}"
COMPILER_SLOTS="${DQ_LANE_POOL_COMPILER:-2}"
POOL_DIR="${DQ_LANE_POOL_DIR:-E:/projects/dq-wt}"
STATE_DIR="${DQ_LANE_POOL_STATE:-E:/dq-cache/lane-pool}"
_o="$PWD"; cd "$_dq_dir/.." && here="$PWD"; cd "$_o"   # builtins only: no $(...) fork
REPO="${DQ_LANE_POOL_REPO:-$here}"
case "$POOL_SIZE" in ''|*[!0-9]*) echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2 ;; esac
[ "$POOL_SIZE" -ge 1 ] || { echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2; }

die() { echo "dq_lane_pool: $*" >&2; exit "${DIE_CODE:-1}"; }
say() { echo "dq_lane_pool: $*" >&2; }

# DQ_LANE_POOL_NO_FETCH=1 skips every fetch; only tools/ci/test_lane_pool.sh sets it (its origin is a local bare repository the test pushes to itself)
fetch_origin() { [ "${DQ_LANE_POOL_NO_FETCH:-}" = 1 ] && return 0; git -C "$1" fetch -q origin; }
SLOTS_GENERAL=(); SLOTS_COMPILER=(); _k=0   # arrays built once: a seq or $(...) per call is a fork
while [ "$_k" -lt "$POOL_SIZE" ]; do _k=$((_k + 1)); SLOTS_GENERAL+=("$_k"); done
_k=0; while [ "$_k" -lt "$COMPILER_SLOTS" ]; do _k=$((_k + 1)); SLOTS_COMPILER+=("c$_k"); done
slots_for_class() { # <class>: sets CLASS_SLOTS to the slots a class may take, in the order it tries them
	case "$1" in
		compiler) CLASS_SLOTS=("${SLOTS_COMPILER[@]}" "${SLOTS_GENERAL[@]}") ;;
		light) CLASS_SLOTS=(light) ;;
		*) CLASS_SLOTS=("${SLOTS_GENERAL[@]}") ;;
	esac
}
lane_class() { # <branch> <explicit class or empty>: sets LANE_CLASS
	case "${2:-}" in compiler|light|general) LANE_CLASS="$2"; return ;; '') ;; *) die "--class must be general, compiler or light" ;; esac
	case "$1" in tools/dmb*) LANE_CLASS=compiler ;; *) LANE_CLASS=general ;; esac
}
now_utc() { TZ=UTC printf -v NOW_UTC '%(%Y-%m-%dT%H:%M:%SZ)T' -1; }
lease_load() { # <slot>: sets L_branch, L_owner, L_since, L_start with no fork
	local k v; L_branch=""; L_owner=""; L_since=""; L_start=""
	[ -f "$STATE_DIR/pool-$1.lease" ] || return 0
	while IFS='=' read -r k v; do
		case "$k" in branch) [ -z "$L_branch" ] && L_branch="$v" ;; owner) [ -z "$L_owner" ] && L_owner="$v" ;; since) [ -z "$L_since" ] && L_since="$v" ;; start) [ -z "$L_start" ] && L_start="$v" ;; esac
	done <"$STATE_DIR/pool-$1.lease"
}
lease_get() { # <slot> <key>: sets LG (the first value of that key in the lease file) with no fork
	local k v; LG=""
	[ -f "$STATE_DIR/pool-$1.lease" ] || return 0
	while IFS='=' read -r k v; do [ "$k" = "$2" ] && { LG="$v"; return 0; }; done <"$STATE_DIR/pool-$1.lease"
}

LOCK="$STATE_DIR/pool.lock"
lock_take() {
	[ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
	local i=0
	while ! mkdir "$LOCK" 2>/dev/null; do
		# A lock older than two minutes belongs to a crashed caller (the critical sections below take seconds, except the
		# one-time worktree creation, which refreshes the lock's mtime when it starts).
		if [ -d "$LOCK" ]; then mtv_of "$LOCK"; if [ "$MTV" -gt 0 ] && [ $(( EPOCHSECONDS - MTV )) -gt 120 ]; then rmdir "$LOCK" 2>/dev/null; continue; fi; fi
		i=$((i + 1))
		[ "$i" -le 600 ] || die "could not take the pool lock ($LOCK) in 60 s"
		sleep 0.1
	done
	trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}
lock_drop() { rmdir "$LOCK" 2>/dev/null; trap - EXIT; }

_wt_clean_full() { # <path>: no tracked change, no untracked non-ignored file, no merge/rebase/cherry-pick in progress
	local wt="$1" m fd o=""
	gitdir_of "$wt"   # the git dir without a fork (rev-parse --absolute-git-dir)
	[ -e "$GD/HEAD" ] || return 1
	for m in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do [ -e "$GD/$m" ] && return 1; done
	# Fast path, one git start instead of three: a status with no line at all (nothing staged, modified or untracked) is clean by every
	# definition below. Anything it does list goes on to the exact checks, which also forgive a CR-only difference.
	o="$(git --no-optional-locks -C "$wt" status --porcelain=v1 --untracked-files=normal 2>/dev/null)" && [ -z "$o" ] && return 0
	# the untracked listing runs beside the refresh and the diff (a git start costs a few hundred ms on a loaded host), and no head/$(...) forks
	exec {fd}< <(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)
	git -C "$wt" update-index -q --refresh >/dev/null 2>&1
	# a CR-only difference (autocrlf / eol phantom: the index stat is stale but the content matches modulo CR) is not dirty
	if ! git -C "$wt" diff --quiet --ignore-cr-at-eol HEAD -- >/dev/null 2>&1; then exec {fd}<&-; return 1; fi # --quiet honors the flag; --name-only does not
	read -r -u "$fd" o; exec {fd}<&-
	[ -z "$o" ]
}
wt_clean() { # full check, result cached for status
	_wt_clean_full "$1"; local rc=$?
	dirty_store "$1" "$rc" .full
	return "$rc"
}

# ---- cached dirty state ---------------------------------------------------------------------------------------------------------
# A full dirty check (git status over a 13 to 16 GB worktree) takes minutes, so status and stuck never run it. The result of every check is
# cached under $STATE_DIR/dirty keyed by the index mtime; stuck re-checks only a lease idle past the stuck limit, with tracked files only.
dirty_key() { # <wt>: sets DK to the index mtime
	gitdir_of "$1"; mtv_of "$GD/index"; DK="$MTV"
}
dirty_store() { # <wt> <0 clean|1 dirty> [.full]: the full check (wt_clean) is kept apart from the fast one, which a stuck lease must not take from it
	local f="$STATE_DIR/dirty/${1//[^A-Za-z0-9]/_}${3:-}"
	[ -d "$STATE_DIR/dirty" ] || mkdir -p "$STATE_DIR/dirty" 2>/dev/null
	gitdir_of "$1"; unset "MT[$GD/index]"   # the index may have just been refreshed: read its mtime afresh
	dirty_key "$1"
	echo "$DK $2" >"$f" 2>/dev/null
}
dirty_cached() { # <wt> <max age minutes> [.full]: sets DV to 0/1 when a cached result matches the index mtime and is young enough
	local f k v; f="$STATE_DIR/dirty/${1//[^A-Za-z0-9]/_}${3:-}"
	[ -f "$f" ] || return 1
	mtv_of "$f"; [ $(( EPOCHSECONDS - MTV )) -le $(( $2 * 60 )) ] || return 1
	read -r k v <"$f"
	dirty_key "$1"; [ "$k" = "$DK" ] || return 1
	DV="$v"
}
wt_dirty_fast() { # <wt>: 0 when dirty. Tracked changes and merge state only (no untracked walk, no index refresh), cached by index mtime for 10 minutes
	local wt="$1" m v
	if dirty_cached "$wt" 10; then [ "$DV" = 1 ]; return; fi
	gitdir_of "$wt"
	[ -e "$GD/HEAD" ] || return 0
	v=0
	for m in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do [ -e "$GD/$m" ] && v=1; done
	[ "$v" -eq 0 ] && { GIT_OPTIONAL_LOCKS=0 git -C "$wt" diff --quiet --ignore-cr-at-eol HEAD -- >/dev/null 2>&1 || v=1; }
	dirty_store "$wt" "$v"
	[ "$v" = 1 ]
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
	local wt="$1" f n=0 cand=() ign=()
	for f in "$wt"/deepquarry.*; do
		[ -e "$f" ] || continue
		case "$f" in *.dme|*.dm|*.md) continue ;; esac
		cand+=("${f#"$wt"/}")
	done
	for f in "$wt"/.dmbc "$wt"/tools/dmb/target "$wt"/verdigris/target "$wt"/data/*; do
		[ -e "$f" ] || continue
		case "$f" in "$wt"/data/analyze-cache) continue ;; esac
		cand+=("${f#"$wt"/}")
	done
	if [ "${#cand[@]}" -gt 0 ]; then
		# only paths git ignores: never a tracked file. One check-ignore for all candidates (it prints the ignored ones).
		while IFS= read -r f; do ign+=("$f"); done < <(git -C "$wt" check-ignore -- "${cand[@]}" 2>/dev/null)
		for f in ${ign[@]+"${ign[@]}"}; do rm -rf "$wt/$f" && n=$((n + 1)); done
	fi
	say "dropped $n build output path(s) in $wt"
}

size_of() { du -sk "$1" 2>/dev/null | cut -f1; }
# size_cached <path>: KB from a per-path cache under $STATE_DIR/sizes; `du` over a built worktree takes a minute on Windows, so status never waits for it:
# a missing or older-than-30-minutes entry is refreshed by a detached du and the last known value (or 0) is printed now.
size_cached() { # <path>: sets SZ (KB); a stale entry is refreshed by a detached du and the last value is used now
	local f="$STATE_DIR/sizes/${1//[^A-Za-z0-9]/_}"
	mtv_of "$f"
	if [ $(( EPOCHSECONDS - MTV )) -ge 1800 ]; then
		mtv_of "$f.busy"
		if [ $(( EPOCHSECONDS - MTV )) -ge 600 ]; then
			mkdir -p "$STATE_DIR/sizes" 2>/dev/null
			: >"$f.busy"
			( nohup bash -c 'du -sk "$1" 2>/dev/null | cut -f1 >"$2.tmp" && mv -f "$2.tmp" "$2"; rm -f "$2.busy"' _ "$1" "$f" >/dev/null 2>&1 & ) >/dev/null 2>&1
		fi
	fi
	SZ=0; [ -f "$f" ] && read -r SZ <"$f"; case "$SZ" in ''|*[!0-9]*) SZ=0 ;; esac
}

# ---- release ----------------------------------------------------------------------------------------------------------------------
release_slot() { # <slot> <force> <keep_outputs>
	local i="$1" force="$2" keep="$3" wt branch
	wt="$POOL_DIR/pool-$i"
	lease_get "$i" branch; branch="$LG"
	if [ -d "$wt" ]; then
		if ! wt_clean "$wt"; then
			if [ "$force" -eq 1 ]; then
				say "WARNING: $wt is not clean; --force records the release and leaves the tree as it is (the slot stays unusable until it is cleaned by hand)"
				rm -f "$STATE_DIR/pool-$i.lease"
				return 0
			fi
			git --no-optional-locks -C "$wt" status --short | head -n 8 >&2
			die "$wt is not clean (above): commit or finish it, then release (--force records the release only)"
		fi
		retire_daemon "$wt"
		[ "$keep" -eq 1 ] || drop_outputs "$wt"
		fetch_origin "$wt" 2>/dev/null
		git -C "$wt" switch -q --detach origin/master || die "could not move $wt to a detached origin/master"
	fi
	rm -f "$STATE_DIR/pool-$i.lease"
	if [ -n "$branch" ] && git -C "$REPO" show-ref -q --verify "refs/heads/$branch"; then
		if merged_into_master "$REPO" "$branch"; then
			git -C "$REPO" branch -q -d "$branch" 2>/dev/null && say "deleted merged branch $branch"
		else
			say "branch $branch holds commits origin/master lacks; kept (it is not lost: git log origin/master..$branch)"
		fi
	fi
	say "released pool-$i${branch:+ ($branch)}"
}

RECLAIM_IDLE_MIN="${DQ_LANE_POOL_RECLAIM_IDLE_MIN:-180}"

STUCK_MIN="${DQ_LANE_POOL_STUCK_MIN:-30}"
IDLE_FLAG_MIN="${DQ_LANE_POOL_IDLE_FLAG_MIN:-10}"
NOTICE_DIR="$STATE_DIR/notices"
SLOTS_SH="$_dq_dir/dq_machine_slots.sh"

# Status and stuck run on a loaded Windows host where every fork costs a few hundred ms, so the evaluation below is written with bash builtins
# (EPOCHSECONDS, read, [[ =~ ]]) and a single batched stat (mt_prefetch). A command substitution is a fork too: the hot paths set variables.
declare -A MT=() LOGMAX=(); MT_PREFETCHED=0
mt_prefetch() { # one stat for every slot's lease, HEAD, reflog, index, dirty-cache, size-cache and the process-snapshot cache
	local i wt f files=() line key
	MT=(); MT_PREFETCHED=1
	for i in "${ALL_SLOTS[@]}"; do
		wt="$POOL_DIR/pool-$i"; key="${wt//[^A-Za-z0-9]/_}"
		files+=("$STATE_DIR/pool-$i.lease" "$STATE_DIR/dirty/$key" "$STATE_DIR/dirty/$key.full" "$STATE_DIR/sizes/$key" "$STATE_DIR/sizes/$key.busy")
		[ -d "$wt" ] || continue
		gitdir_of "$wt"
		files+=("$GD/HEAD" "$GD/logs/HEAD" "$GD/index")
	done
	files+=("$STATE_DIR/procs.snap" "$STATE_DIR/prune.stamp")
	# a file that does not exist is recorded as 0 up front: stat prints nothing for it, and mtv_of would otherwise fork a stat of its own to find that out
	for f in "${files[@]}"; do MT["$f"]=0; done
	while IFS=' ' read -r line f; do MT["$f"]="$line"; done < <(stat -c '%Y %n' "${files[@]}" 2>/dev/null)
	# the newest file under every worktree's log and run directories, from one find for the whole pool
	LOGMAX=(); local wts=() w m logpaths=()
	for i in "${ALL_SLOTS[@]}"; do [ -d "$POOL_DIR/pool-$i" ] && wts+=("$POOL_DIR/pool-$i"); done
	for w in "${wts[@]}"; do logpaths+=("$w"/*.log "$w/data/lane-logs" "$w/data/logs" "$w/data/runs" "$w/data/focused-runs" "$w/data/test-runs"); done
	for w in "${wts[@]}"; do LOGMAX["$w"]=0; done
	while IFS=' ' read -r line f; do
		m="${line%%.*}"
		for w in "${wts[@]}"; do
			[[ "$f" == "$w"/* ]] || continue
			[ "$m" -gt "${LOGMAX[$w]}" ] && LOGMAX["$w"]="$m"
			break
		done
	done < <(find "${logpaths[@]}" -maxdepth 3 -type f -printf '%T@ %p\n' 2>/dev/null)
}
mtv_of() { # <path>: sets MTV to the mtime (0 when absent); from the prefetch when there is one
	if [ -n "${MT[$1]:-}" ]; then MTV="${MT[$1]}"
	else MTV="$(stat -c %Y "$1" 2>/dev/null || echo 0)"; fi
}
head_branch() { # <wt>: sets HB to the branch HEAD points at (empty when detached), read from the worktree's HEAD file with no git start
	local h=""; HB=""; gitdir_of "$1"
	[ -f "$GD/HEAD" ] && read -r h <"$GD/HEAD"
	[[ "$h" == "ref: refs/heads/"* ]] && HB="${h#ref: refs/heads/}"
	return 0
}
gitdir_of() { # <wt>: sets GD to the worktree's git dir without running git (a linked worktree's .git file says "gitdir: <path>")
	local k v; GD="$1/.git"
	if [ -f "$GD" ]; then read -r k v <"$GD"; [ "$k" = "gitdir:" ] && GD="$v"; fi
}
ALL_SLOTS=(); for ((_k = 1; _k <= POOL_SIZE; _k++)); do ALL_SLOTS+=("$_k"); done
for ((_k = 1; _k <= COMPILER_SLOTS; _k++)); do ALL_SLOTS+=("c$_k"); done
ALL_SLOTS+=(light)

slot_activity_set() { # <slot> <worktree>: sets ACT_V to epoch seconds of the newest change to the lease, HEAD, reflog or a lane log
	local newest=0 f m wt="$2" line
	gitdir_of "$wt"
	for f in "$STATE_DIR/pool-$1.lease" "$GD/HEAD" "$GD/logs/HEAD"; do   # not the index: wt_clean refreshes it, which would restart the idle clock
		mtv_of "$f"
		[ "$MTV" -gt "$newest" ] && newest="$MTV"
	done
	# Only cheap signals, never a walk over the worktree: the signs above plus the newest file under the lane's log and run directories (a few
	# dozen files) and a *.log at its root, looked at only when the signs are old. A tree of 13 to 16 GB is never listed here.
	if [ -d "$wt" ] && [ $(( EPOCHSECONDS - newest )) -ge $(( IDLE_FLAG_MIN * 60 )) ]; then
		if [ -n "${LOGMAX[$wt]:-}" ]; then   # from the pool-wide find of mt_prefetch
			[ "${LOGMAX[$wt]}" -gt "$newest" ] && newest="${LOGMAX[$wt]}"
		else
			while IFS= read -r line; do
				m="${line%%.*}"
				case "$m" in ''|*[!0-9]*) ;; *) [ "$m" -gt "$newest" ] && newest="$m" ;; esac
			done < <(find "$wt"/*.log "$wt/data/lane-logs" "$wt/data/logs" "$wt/data/runs" "$wt/data/focused-runs" "$wt/data/test-runs" -maxdepth 3 -type f -printf '%T@\n' 2>/dev/null)
		fi
	fi
	ACT_V="$newest"
}

slot_idle_set() { slot_activity_set "$@"; IDLE_V=$(( (EPOCHSECONDS - ACT_V) / 60 )); }

PROC_SNAP=""; PROC_SNAP_DONE=0
PROC_CACHE_OK=0   # status and stuck may use a snapshot up to 5 minutes old; the reclaim path never does
proc_collect() { # runs the process listing (powershell: seconds on a loaded host) and sets PROC_SNAP; with PROC_CACHE_OK it also stores it in the cache
	local raw="" cache="$STATE_DIR/procs.snap" f
	if [ -n "${DQ_LANE_POOL_PROCS_CMD:-}" ]; then
		raw="$(eval "$DQ_LANE_POOL_PROCS_CMD" 2>/dev/null)"
	elif command -v powershell.exe >/dev/null 2>&1; then
		raw="$(powershell.exe -NoProfile -NonInteractive -Command 'Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.Name -notmatch "^(dmbc|powershell)" } | ForEach-Object { $_.CommandLine }' 2>/dev/null | tr -d '\r')"
	elif [ -d /proc/self ]; then
		raw="$(for f in /proc/[0-9]*; do { tr '\0' ' ' <"$f/cmdline"; echo " $(readlink "$f/cwd" 2>/dev/null)"; } 2>/dev/null; done)"
	fi
	PROC_SNAP="$(printf '%s\n' "$raw" | grep -v 'dq_lane_pool' | tr 'A-Z\\' 'a-z/' | sed 's|//*|/|g')"
	if [ "$PROC_CACHE_OK" -eq 1 ] && [ -z "${DQ_LANE_POOL_PROCS_CMD:-}" ]; then
		mkdir -p "$STATE_DIR" 2>/dev/null; printf '%s\n' "$PROC_SNAP" >"$cache.tmp.$$" 2>/dev/null && mv -f "$cache.tmp.$$" "$cache"
	fi
}
proc_snapshot() { # command lines of the running processes, lowercased with / separators (once per invocation). DQ_LANE_POOL_PROCS_CMD replaces the source (tests).
	[ "$PROC_SNAP_DONE" -eq 1 ] && return 0
	PROC_SNAP_DONE=1
	local cache="$STATE_DIR/procs.snap" age
	if [ "$PROC_CACHE_OK" -eq 1 ] && [ -z "${DQ_LANE_POOL_PROCS_CMD:-}" ]; then
		# status and stuck never wait for the listing once there is one: a snapshot up to 30 minutes old is used, and one older than 5 minutes is
		# refreshed by a detached process for the next call (the listing costs seconds, status must answer in a few)
		mtv_of "$cache"; age=$(( EPOCHSECONDS - MTV ))
		if [ "$MTV" -gt 0 ] && [ "$age" -lt 1800 ]; then
			PROC_SNAP=$(<"$cache")   # $(<file) reads without a fork; read -d '' is byte by byte (0.5 s for 200 KB)
			if [ "$age" -ge 300 ]; then
				mtv_of "$cache.busy"
				if [ $(( EPOCHSECONDS - MTV )) -ge 120 ]; then
					: >"$cache.busy"
					( nohup bash "${BASH_SOURCE[0]}" _procs_refresh >/dev/null 2>&1; rm -f "$cache.busy" ) >/dev/null 2>&1 &
				fi
			fi
			return 0
		fi
	fi
	proc_collect
}

norm_path() { # <path>: sets NP to the lower-case path with / separators, no doubled or trailing /
	NP="${1,,}"; NP="${NP//\\//}"
	while [[ "$NP" == *//* ]]; do NP="${NP//\/\//\/}"; done
	NP="${NP%/}"
}
slot_live() { # <slot> <worktree>: a process uses the worktree (its path on a command line, or a machine slot held or queued for it)
	local wt="$2" a b ra rb re
	norm_path "$wt"; a="$NP"
	b="$a"; [[ "$a" =~ ^([a-z]): ]] && b="/${a:0:1}${a:2}"   # the msys spelling /e/projects/...
	proc_snapshot
	if [ -n "$PROC_SNAP" ]; then
		ra="${a//./\\.}"; rb="${b//./\\.}"
		re="(^|[^a-z0-9_/.-])($ra|$rb)([^a-z0-9_-]|\$)"
		[[ "$PROC_SNAP" =~ $re ]] && return 0
	fi
	usage_scan "$wt"
	[ "$U_ANY" -eq 1 ] && return 0
	return 1
}

SLOT_USAGE_ALL=""; USAGE_LOADED=0; USAGE_FD=""
usage_start() { # begin the machine-slot usage listing in the background (status overlaps it with the other work)
	[ -f "$SLOTS_SH" ] && exec {USAGE_FD}< <(bash "$SLOTS_SH" usage-all 2>/dev/null)
}
usage_load() { # the listing of every fresh holder and waiter, once per invocation
	[ "$USAGE_LOADED" -eq 1 ] && return 0
	USAGE_LOADED=1
	local line
	if [ -n "$USAGE_FD" ]; then
		while IFS= read -r -u "$USAGE_FD" line; do SLOT_USAGE_ALL+="$line"$'\n'; done
		exec {USAGE_FD}<&-
	elif [ -f "$SLOTS_SH" ]; then
		SLOT_USAGE_ALL="$(bash "$SLOTS_SH" usage-all 2>/dev/null)"
	fi
}
usage_scan() { # <worktree>: sets U_ANY (0/1: it holds or queues for a machine slot) and U_WAIT ("class Ns" of its first queued wait)
	local kind w cls secs label
	U_ANY=0; U_WAIT=""
	usage_load
	norm_path "$1"
	while read -r kind w cls secs label; do
		[ "$w" = "$NP" ] || continue
		U_ANY=1
		[ "$kind" = wait ] && [ -z "$U_WAIT" ] && U_WAIT="$cls ${secs}s"
	done <<<"$SLOT_USAGE_ALL"
}

slot_pushed() { # <branch>: nothing is unpushed: every commit is in origin/master or in origin/<branch> (a deleted branch holds nothing)
	git -C "$REPO" show-ref -q --verify "refs/heads/$1" || return 0
	merged_into_master "$REPO" "$1" && return 0
	git -C "$REPO" merge-base --is-ancestor "refs/heads/$1" "refs/remotes/origin/$1" 2>/dev/null
}

fmt_min_set() { # minutes -> FM, no fork
	local m="$1"
	if [ "$m" -ge 2880 ]; then printf -v FM '%dd%02dh' $((m / 1440)) $((m % 1440 / 60))
	elif [ "$m" -ge 120 ]; then printf -v FM '%dh%02dm' $((m / 60)) $((m % 60))
	else FM="${m}m"; fi
}
fmt_min() { # minutes -> 45m / 3h05m / 2d04h
	local m="$1"
	if [ "$m" -ge 2880 ]; then echo "$((m / 1440))d$(printf %02d $((m % 1440 / 60)))h"
	elif [ "$m" -ge 120 ]; then echo "$((m / 60))h$(printf %02d $((m % 60)))m"
	else echo "${m}m"; fi
}

# slot_eval <slot>: sets E_IDLE (minutes), E_LIVE (0/1), E_DIRTY (0/1), E_PUSHED (0/1), E_STUCK (0/1), E_WAIT ("class Ns" or "")
slot_eval() {
	local i="$1" wt="$POOL_DIR/pool-$1"
	lease_load "$i"
	E_IDLE=0; E_LIVE=0; E_DIRTY=0; E_PUSHED=1; E_STUCK=0; E_WAIT=""
	[ -d "$wt" ] || return 0
	slot_idle_set "$i" "$wt"; E_IDLE="$IDLE_V"
	# processes are looked at only for a lease whose cheap signals are old (a recent change means active)
	if [ "$E_IDLE" -ge "$IDLE_FLAG_MIN" ]; then slot_live "$i" "$wt" && E_LIVE=1; fi
	[ "$E_LIVE" -eq 0 ] && [ "$E_IDLE" -ge "$STUCK_MIN" ] && E_STUCK=1
	if [ "$E_STUCK" -eq 1 ]; then   # a dirty check only for a lease idle past the stuck limit, and a cheap cached one
		wt_dirty_fast "$wt" && E_DIRTY=1
		slot_pushed "$L_branch" || E_PUSHED=0
	fi
	usage_scan "$wt"
	[ -n "$U_WAIT" ] && E_WAIT="$U_WAIT"
	return 0
}

stuck_notice() { # <slot>: write or remove $STATE_DIR/notices/pool-N.stuck from the E_* of slot_eval
	local i="$1" f="$NOTICE_DIR/pool-$1.stuck"
	if [ "$E_STUCK" -eq 1 ]; then
		[ -d "$NOTICE_DIR" ] || mkdir -p "$NOTICE_DIR" 2>/dev/null
		{
			echo "slot=pool-$i"; echo "branch=$L_branch"; echo "owner=$L_owner"
			echo "idle_minutes=$E_IDLE"; echo "dirty=$E_DIRTY"; echo "unpushed=$((1 - E_PUSHED))"
			echo "path=$POOL_DIR/pool-$i"; now_utc; echo "noticed=$NOW_UTC"
			echo "action=$([ "$E_DIRTY" -eq 0 ] && [ "$E_PUSHED" -eq 1 ] && echo "reclaimable by the next lease after the reclaim idle limit" || echo "report only: dirty or unpushed work is never discarded")"
		} >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
	else
		[ -e "$f" ] && rm -f "$f" 2>/dev/null
	fi
	return 0
}

reclaim_finished() { # called under the lock: drop leases whose lane is done
	local i wt branch idle_limit start tip held=0
	for i in "${ALL_SLOTS[@]}"; do [ -f "$STATE_DIR/pool-$i.lease" ] && held=1; done
	[ "$held" -eq 1 ] || return 0
	mt_prefetch   # one stat and one find for every slot's signs of activity, instead of one per file
	local -A heads=(); local sha ref
	while read -r sha ref; do heads["${ref#refs/heads/}"]="$sha"; done < <(git -C "$REPO" for-each-ref --format='%(objectname) %(refname)' refs/heads 2>/dev/null)   # one git start for every branch tip
	for i in "${ALL_SLOTS[@]}"; do
		[ -f "$STATE_DIR/pool-$i.lease" ] || continue
		wt="$POOL_DIR/pool-$i"
		lease_get "$i" branch; branch="$LG"; lease_get "$i" start; start="$LG"
		if [ ! -d "$wt" ]; then rm -f "$STATE_DIR/pool-$i.lease"; say "reclaimed pool-$i (worktree gone)"; continue; fi
		# A lane that lands several merges in a row (a wave per merge) is merged and clean between merges while its agent is still
		# working in the slot, so a merged lane is reclaimed only once nothing has touched its worktree for a while (or by release).
		idle_limit="$RECLAIM_IDLE_MIN"; [ "$i" = light ] && idle_limit="${DQ_LANE_POOL_LIGHT_IDLE_MIN:-30}"   # a light lane lasts minutes
		slot_idle_set "$i" "$wt"
		tip="${heads[$branch]:-}"
		if [ -n "$tip" ] && [ "$IDLE_V" -lt "$idle_limit" ]; then
			continue   # a recently touched lease whose branch exists is active: no git status of a worktree that could be 15 GB
		fi
		wt_clean "$wt" || continue
		if [ -z "$tip" ]; then
			RECLAIMED=1; release_slot "$i" 0 0; say "reclaimed pool-$i (branch $branch is gone)"; continue
		fi
		if merged_into_master "$REPO" "$branch" && [ "$tip" != "$start" ]; then
			# the lane committed (tip moved off its start) and all of it is in origin/master: finished. A lane that has not committed yet
			# also sits on a master ancestor, which is why the start commit is recorded.
			RECLAIMED=1; release_slot "$i" 0 0; say "reclaimed pool-$i (lane $branch is merged into origin/master)"
		elif ! slot_live "$i" "$wt" && slot_pushed "$branch"; then
			# stuck (no process, idle past the limit), clean, and every commit pushed or merged: nothing can be lost (a lane that never committed lands here too)
			RECLAIMED=1; release_slot "$i" 0 0; say "reclaimed pool-$i (stuck: clean, no live process, idle $(fmt_min "$IDLE_V"), nothing unpushed on $branch)"
		fi
	done
}

# ---- lease ------------------------------------------------------------------------------------------------------------------------
# ---- waiting for a slot ------------------------------------------------------------------------------------------------------------
# `lease <branch> --wait [--timeout MIN]` queues instead of failing on a full pool: one waiting process per lane (run it once, in the
# background, and get told when it exits), served first come first served from $STATE_DIR/queue. A waiter whose process died drops
# out of the queue on its own. Agents never write their own retry loops around `lease`.
QUEUE_DIR="$STATE_DIR/queue"

queue_prune() { # drop tickets whose waiting process is gone
	local t pid k v
	for t in "$QUEUE_DIR"/*.ticket; do
		[ -e "$t" ] || continue
		pid=""; while IFS='=' read -r k v; do [ "$k" = pid ] && { pid="$v"; break; }; done <"$t"
		if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -f "$t"; fi
	done
}
ticket_get() { # <ticket> <key>: sets KV
	local k v; KV=""
	while IFS='=' read -r k v; do [ "$k" = "$2" ] && { KV="$v"; break; }; done <"$1"
}

queue_position() { # <ticket>: 1 when it is the oldest live ticket
	local n=0 t   # sets QPOS; the glob is already sorted, so no ls | sort forks
	QPOS=0
	for t in "$QUEUE_DIR"/*.ticket; do
		[ -e "$t" ] || continue
		n=$((n + 1))
		[ "$t" = "$1" ] && { QPOS="$n"; return; }
	done
}

cmd_lease() {
	local wait=0 timeout_min=240 args=() ticket pos last_pos="" start rc out class="" branch="" prefix="" skip=0 a
	while [ $# -gt 0 ]; do
		case "$1" in
			--wait) wait=1 ;;
			--timeout) shift; timeout_min="${1:?--timeout needs minutes}" ;;
			--class) shift; class="${1:?--class needs general, compiler or light}" ;;
			*) args+=("$1") ;;
		esac
		shift
	done
	for a in ${args[@]+"${args[@]}"}; do # the branch: the first word that is not a flag or a flag's value
		if [ "$skip" -eq 1 ]; then skip=0; continue; fi
		case "$a" in --base) skip=1 ;; -*) ;; *) [ -n "$branch" ] || branch="$a" ;; esac
	done
	lane_class "$branch" "$class"; class="$LANE_CLASS"
	args+=(--class "$class")
	case "$class" in
		light) QUEUE_DIR="$STATE_DIR/queue-light" ;;   # its own queue: the one shared slot never waits behind game lanes, nor they behind it
		compiler) prefix="0-" ;;                         # sorts ahead of the general tickets (plain timestamps) in the same dir
	esac
	[ "$wait" -eq 1 ] || { lease_once "${args[@]}"; return; }
	[ -d "$QUEUE_DIR" ] || mkdir -p "$QUEUE_DIR"
	now_utc
	ticket="$QUEUE_DIR/${prefix}${EPOCHREALTIME/./}000-$$.ticket"   # microseconds padded to the old nanosecond width: same ordering
	printf 'pid=%s
branch=%s
since=%s
' "$$" "$branch" "$NOW_UTC" >"$ticket"
	trap 'rm -f "${ticket:-}"' EXIT
	start="$EPOCHSECONDS"
	while :; do
		[ -f "$ticket" ] || { say "cancelled: the queue ticket for $branch was withdrawn (dq_lane_pool.sh cancel)"; return 4; }
		queue_prune
		queue_position "$ticket"; pos="$QPOS"
		if [ "$pos" = 1 ]; then
			out="$(lease_once "${args[@]}" 2>"$ticket.err")"; rc=$?
			if [ "$rc" -ne 3 ]; then
				cat "$ticket.err" >&2; rm -f "$ticket.err"
				[ -n "$out" ] && echo "$out"
				return "$rc"
			fi
			rm -f "$ticket.err"
		fi
		[ "$pos" != "$last_pos" ] && { say "waiting for a slot: position $pos in the queue (bash tools/dq_lane_pool.sh status)"; last_pos="$pos"; }
		if [ $(( EPOCHSECONDS - start )) -ge $(( timeout_min * 60 )) ]; then
			say "gave up after $timeout_min minutes in the queue"; return 3
		fi
		sleep "${DQ_LANE_POOL_WAIT_POLL:-20}"
	done
}

lease_once() {
	local branch="" base="origin/master" i wt held=0 free="" skipped="" class="" nslots=0 base_sha="" tip="" br_sha=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--base) shift; base="${1:?--base needs a ref}" ;;
			--class) shift; class="${1:?--class needs a value}" ;;
			-*) die "unknown argument: $1" ;;
			*) [ -z "$branch" ] || die "one branch per lease"; branch="$1" ;;
		esac
		shift
	done
	[ -n "$branch" ] || die "usage: dq_lane_pool.sh lease <branch>"
	# the usual names (letters, digits, _ - . and / between words) are valid by git's rules; anything else asks git
	if ! { [[ "$branch" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ ]] && [[ "$branch" != *..* && "$branch" != *.lock && "$branch" != *.lock/* && "$branch" != *./* && "$branch" != *. ]]; }; then
		git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name"
	fi
	case "$branch" in master|main|rewrite/integ-current) die "'$branch' is not a lane branch" ;; esac
	lane_class "$branch" "$class"; class="$LANE_CLASS"

	# the disk floor: below DQ_DISK_FLOOR_GB free (tools/ci/disk_budget.toml) no new lane starts; above it the budget is enforced in the background
	[ -f "$REPO/tools/dq_disk_budget.sh" ] && { bash "$REPO/tools/dq_disk_budget.sh" gate "a new lane lease" --throttle 10 || return 6; }
	fetch_origin "$REPO" || say "warning: git fetch failed; using the last fetched origin/master"
	lock_take
	br_sha=""
	if [ "$base" = origin/master ]; then   # the default base and the lane branch's tip in one git start
		local sha ref
		while read -r sha ref; do
			case "$ref" in refs/remotes/origin/master) base_sha="$sha" ;; "refs/heads/$branch") br_sha="$sha" ;; esac
		done < <(git -C "$REPO" for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin/master "refs/heads/$branch" 2>/dev/null)
		[ -n "$base_sha" ] || die "no such base: $base"
	else
		base_sha="$(git -C "$REPO" rev-parse -q --verify "$base")" || die "no such base: $base"
		br_sha="$(git -C "$REPO" rev-parse -q --verify "refs/heads/$branch")" || br_sha=""
	fi
	# A lane that already holds a slot gets it back.
	for i in "${ALL_SLOTS[@]}"; do
		[ -f "$STATE_DIR/pool-$i.lease" ] || continue
		lease_get "$i" branch
		if [ "$LG" = "$branch" ]; then
			wt="$POOL_DIR/pool-$i"
			head_branch "$wt"
			if [ -d "$wt" ] && [ "$HB" = "$branch" ]; then
				lock_drop; say "$branch already holds pool-$i"; echo "$wt"; return 0
			fi
			rm -f "$STATE_DIR/pool-$i.lease"  # a stale record: the worktree moved on
		fi
	done
	RECLAIMED=0; reclaim_finished
	if [ "$RECLAIMED" -eq 1 ]; then br_sha="$(git -C "$REPO" rev-parse -q --verify "refs/heads/$branch")" || br_sha=""; fi   # a reclaim may have deleted the lane branch
	slots_for_class "$class"
	for i in "${CLASS_SLOTS[@]}"; do nslots=$((nslots + 1)); [ -f "$STATE_DIR/pool-$i.lease" ] && held=$((held + 1)); done
	if [ "$nslots" -eq 0 ] || [ "$held" -ge "$nslots" ]; then
		echo "dq_lane_pool: POOL FULL ($class lanes): $held of $nslots worktrees are in use; at most $POOL_SIZE general lanes run at once (DQ_LANE_POOL_SIZE)." >&2
		for i in "${CLASS_SLOTS[@]}"; do
			lease_load "$i"
			echo "  pool-$i: $L_branch since $L_since ($L_owner)" >&2
		done
		echo "  Finish one lane (dq_lane_ready.sh, merge, then 'bash tools/dq_lane_pool.sh release <branch>') and ask again, or wait." >&2
		lock_drop
		return 3
	fi
	for i in "${CLASS_SLOTS[@]}"; do
		[ -f "$STATE_DIR/pool-$i.lease" ] && continue
		wt="$POOL_DIR/pool-$i"
		if [ -d "$wt" ] && ! wt_clean "$wt"; then skipped="$skipped pool-$i"; continue; fi
		free="$i"; break
	done
	if [ -z "$free" ]; then
		lock_drop
		die "no usable slot: every free worktree is dirty or mid-merge ($skipped); clean or finish it by hand (nothing is cleaned for you)"
	fi
	i="$free"; wt="$POOL_DIR/pool-$i"
	if [ ! -e "$wt/.git" ]; then
		[ -z "$(ls -A "$wt" 2>/dev/null)" ] || { lock_drop; die "$wt exists and is not a worktree; move it away"; }
		say "creating $wt (one-time checkout; later leases are a switch)"
		[ -d "$POOL_DIR" ] || mkdir -p "$POOL_DIR"
		touch "$LOCK"
		git -C "$REPO" worktree add --detach "$wt" "$base" >&2 || { lock_drop; die "git worktree add failed"; }
	fi
	fetch_origin "$wt" 2>/dev/null
	tip="$base_sha"   # HEAD after the switch: the base for -c and -C, the branch tip when resuming (no rev-parse afterwards)
	if [ -n "$br_sha" ]; then
		if merged_into_master "$REPO" "$branch"; then
			git -C "$wt" switch -q -C "$branch" "$base" || { lock_drop; die "git switch -C $branch failed in $wt"; }
			say "restarted merged branch $branch on $base"
		else
			git -C "$wt" switch -q "$branch" || { lock_drop; die "git switch $branch failed in $wt (is it checked out in another worktree?)"; }
			tip="$br_sha"
			say "resumed $branch (it holds commits $base lacks); merge master with: bash tools/dq_merge_master.sh"
		fi
	else
		git -C "$wt" switch -q -c "$branch" "$base" || { lock_drop; die "git switch -c $branch failed in $wt"; }
	fi
	now_utc
	{
		echo "branch=$branch"
		echo "since=$NOW_UTC"
		echo "owner=${DQ_LANE_OWNER:-${USERNAME:-${USER:-unknown}}}"
		echo "class=$class"
		echo "base=$base"
		echo "start=$tip"
	} >"$STATE_DIR/pool-$i.lease"
	lock_drop
	say "leased pool-$i ($class) to $branch (${tip:0:10} = $base); release with: bash tools/dq_lane_pool.sh release $branch"
	echo "$wt"
}

train_watchdog() { # restart the train's integrator when lanes are queued and none is running (a fast no-op otherwise); detached, never blocks
	[ "${DQ_TRAIN_NO_START:-0}" = 1 ] && return 0
	[ -f "$REPO/tools/dq_train.sh" ] || return 0
	( nohup bash "$REPO/tools/dq_train.sh" ensure >/dev/null 2>&1 & ) >/dev/null 2>&1
	return 0
}

cmd_release() {
	local target="" force=0 keep=0 i found="" tphys="" sphys="" old="$PWD"
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
	for i in "${ALL_SLOTS[@]}"; do
		[ -f "$STATE_DIR/pool-$i.lease" ] || continue
		lease_get "$i" branch
		if [ "$LG" = "$target" ] || [ "$POOL_DIR/pool-$i" = "$target" ]; then found="$i"; break; fi
		# same directory spelled differently (msys/windows paths, symlinks): compare the shell's own resolved cwd, no subshells
		if [ -z "$tphys" ]; then tphys="-"; cd "$target" 2>/dev/null && tphys="$PWD"; cd "$old"; fi
		sphys=""; cd "$POOL_DIR/pool-$i" 2>/dev/null && sphys="$PWD"; cd "$old"
		if [ -n "$sphys" ] && [ "$sphys" = "$tphys" ]; then found="$i"; break; fi
	done
	[ -n "$found" ] || { lock_drop; die "no lease for '$target' (dq_lane_pool.sh status)"; }
	release_slot "$found" "$force" "$keep"
	local rc=$?
	lock_drop
	# Disk budget (tools/dq_disk_budget.sh, tools/ci/disk_budget.toml): the released slot's cargo targets and growth dirs are now unprotected, so
	# enforce the caps at once, detached, at most once per 10 minutes.
	if [ -f "$REPO/tools/dq_disk_budget.sh" ]; then
		( nohup bash "$REPO/tools/dq_disk_budget.sh" enforce --quiet --throttle 1 >"$STATE_DIR/prune.log" 2>&1 & ) >/dev/null 2>&1
	fi
	return "$rc"
}

free_state() { # <wt>: sets FS to the cached dirty state of a free slot (a lease runs the full check); never runs one here
	if dirty_cached "$1" 600 .full || dirty_cached "$1" 600; then [ "$DV" = 1 ] && FS=DIRTY || FS=clean; else FS="unchecked"; fi
}

cmd_status() {
	local i wt held=0 nstuck=0 tag t n=0 q
	PROC_CACHE_OK=1
	usage_start; mt_prefetch
	echo "lane pool: $POOL_SIZE general + $COMPILER_SLOTS compiler + light slot(s) under $POOL_DIR (state $STATE_DIR)"
	for i in "${ALL_SLOTS[@]}"; do
		wt="$POOL_DIR/pool-$i"
		if [ -f "$STATE_DIR/pool-$i.lease" ]; then
			held=$((held + 1))
			slot_eval "$i"; stuck_notice "$i"
			tag=""; fmt_min_set "$E_IDLE"
			if [ "$E_STUCK" -eq 1 ]; then
				tag="  STUCK: no live process, idle $FM,"
				if [ "$E_DIRTY" -eq 1 ]; then tag="$tag DIRTY tree,"; else tag="$tag clean tree,"; fi
				if [ "$E_PUSHED" -eq 1 ]; then tag="$tag nothing unpushed"; else tag="$tag UNPUSHED commits"; fi
				[ "$E_DIRTY" -eq 1 ] || [ "$E_PUSHED" -eq 0 ] && tag="$tag (report only, never wiped)"
				nstuck=$((nstuck + 1))
			elif [ "$E_IDLE" -ge "$IDLE_FLAG_MIN" ]; then
				tag="  idle $FM"
				[ "$E_LIVE" -eq 1 ] && tag="$tag (a process still uses it)"
			else
				tag="  active (last change $FM ago)"
			fi
			[ -n "$E_WAIT" ] && tag="$tag  WAITING for machine slot: $E_WAIT"
			SZ=0; [ -d "$wt" ] && size_cached "$wt"
			if [ -d "$wt" ]; then echo "  pool-$i  LEASED  $L_branch  since $L_since  ($L_owner)  $(( SZ / 1024 )) MB$tag"
			else echo "  pool-$i  LEASED  $L_branch  since $L_since  ($L_owner)  $tag"; fi
		elif [ -d "$wt" ]; then
			free_state "$wt"; size_cached "$wt"
			echo "  pool-$i  free    $FS  $(( SZ / 1024 )) MB"
		else
			echo "  pool-$i  free    (not created yet: the first lease checks it out)"
		fi
	done
	if [ "$nstuck" -gt 0 ]; then echo "  $held leased, $nstuck STUCK (bash tools/dq_lane_pool.sh stuck)"; else echo "  $held leased"; fi
	for q in "queue:" "queue-light:light "; do
		QUEUE_DIR="$STATE_DIR/${q%%:*}"; queue_prune; n=0
		for t in "$QUEUE_DIR"/*.ticket; do
			[ -e "$t" ] || continue
			n=$((n + 1))
			ticket_get "$t" branch; tag="$KV"; ticket_get "$t" since
			echo "  ${q#*:}queue $n: $tag since $KV"
		done
	done
	[ -d "$STATE_DIR/light-queue" ] && for t in "$STATE_DIR"/light-queue/*.q; do [ -e "$t" ] && { ticket_get "$t" branch; echo "  waiting to land (bash tools/dq_land.sh --light): $KV"; }; done
	return 0
}

cmd_cancel() { # <branch>: remove that branch's queue tickets; the waiting process notices and exits
	local b="${1:-}" t n=0 q
	[ -n "$b" ] || die "usage: dq_lane_pool.sh cancel <branch>"
	for q in "$STATE_DIR/queue" "$STATE_DIR/queue-light"; do
		for t in "$q"/*.ticket; do
			[ -e "$t" ] || continue
			ticket_get "$t" branch
			[ "$KV" = "$b" ] && rm -f "$t" && n=$((n + 1))
		done
	done
	[ "$n" -gt 0 ] || die "no queued lease for '$b' (dq_lane_pool.sh status)"
	say "cancelled $n queued lease ticket(s) for $b; its waiting process exits on its next poll"
}

cmd_stuck() { # [--quiet]: list stuck leases; exit 1 when there are any
	local quiet=0 i n=0 wt act
	[ "${1:-}" = "--quiet" ] && quiet=1
	PROC_CACHE_OK=1
	usage_start; mt_prefetch
	for i in "${ALL_SLOTS[@]}"; do
		if [ ! -f "$STATE_DIR/pool-$i.lease" ]; then [ -e "$NOTICE_DIR/pool-$i.stuck" ] && rm -f "$NOTICE_DIR/pool-$i.stuck" 2>/dev/null; continue; fi
		wt="$POOL_DIR/pool-$i"
		slot_eval "$i"; stuck_notice "$i"
		[ "$E_STUCK" -eq 1 ] || continue
		n=$((n + 1))
		fmt_min_set "$E_IDLE"; act=report-only; [ "$E_DIRTY" -eq 0 ] && [ "$E_PUSHED" -eq 1 ] && act=reclaimable
		[ "$quiet" -eq 1 ] || echo "STUCK pool-$i $L_branch owner=$L_owner idle=$FM dirty=$E_DIRTY unpushed=$((1 - E_PUSHED)) path=$wt action=$act"
	done
	[ "$n" -eq 0 ] && { [ "$quiet" -eq 1 ] || echo "no stuck leases"; return 0; }
	return 1
}

cmd_path() {
	local i
	for i in "${ALL_SLOTS[@]}"; do
		[ -f "$STATE_DIR/pool-$i.lease" ] || continue
		lease_get "$i" branch
		if [ "$LG" = "${1:-}" ]; then echo "$POOL_DIR/pool-$i"; return 0; fi
	done
	return 1
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
	lease) cmd_lease "$@"; rc=$?; train_watchdog; exit "$rc" ;;
	release) cmd_release "$@"; rc=$?; train_watchdog; exit "$rc" ;;
	status) cmd_status ;;
	path) cmd_path "$@" ;;
	cancel) cmd_cancel "$@" ;;
	stuck) cmd_stuck "$@"; exit $? ;;
	_procs_refresh) PROC_CACHE_OK=1; proc_collect ;;   # internal: the detached refresh of the process snapshot that status and stuck start
	-h|--help|help|"") sed -n '2,55p' "$0"; [ -n "$cmd" ] || exit 2 ;;
	*) echo "dq_lane_pool: unknown command '$cmd' (lease, release, status, path, stuck, cancel)" >&2; exit 2 ;;
esac
