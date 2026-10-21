#!/usr/bin/env bash
# The lane worktree pool: lanes lease a worktree from a fixed pool instead of creating and deleting one per lane.
#
#   bash tools/dq_lane_pool.sh lease <branch> [--base REF]   # prints the worktree path; one per lane
#   bash tools/dq_lane_pool.sh lease <branch> --wait [--timeout MIN]  # queue (first come first served) instead of failing when full
#   bash tools/dq_lane_pool.sh lease <branch> --class general|compiler|light   # which slots (below); a tools/dmb* branch is compiler
#   bash tools/dq_lane_pool.sh release [<branch>|--path P] [--force] [--keep-outputs]
#   bash tools/dq_lane_pool.sh status                          # who holds which slot, how big each worktree is
#   bash tools/dq_lane_pool.sh path <branch>                   # the leased path of a branch (exit 1 if none)
#
# Classes (what the lane is, not how important): general = pool-1..N (a game lane: DM compile, test worlds); compiler = pool-c1, pool-c2
# (DQ_LANE_POOL_COMPILER, default 2), reserved: general lanes never take them, and a compiler lane is served ahead of the general queue
# (it uses a free general slot too when both reserved ones are held); light = pool-light, ONE shared slot for small work that needs no
# game build (docs, lane tooling scripts, Rust/compiler-only changes): it never runs a DM compile or a test world (tools/dq_machine_slots.sh
# refuses them there), the lane edits, commits, pushes and releases within minutes, and `bash tools/dq_land.sh --light` lands every pushed
# light branch in one batched merge (tools/dq_land_batch.sh). Compiler holders also get first claim on the machine slots.
#
# Why: a fresh worktree is a 24k-file checkout (minutes), cold caches (analyzer, icons, node_modules, compile cache) and about 1.5 GB
# of build output that nobody deletes. The pool is DQ_LANE_POOL_SIZE worktrees (default 8) under E:/projects/dq-wt/pool-N, created
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
# State: DQ_LANE_POOL_STATE (default E:/dq-cache/lane-pool): one <slot>.lease file per held slot and a lock directory. Override
# DQ_LANE_POOL_DIR (where pool-N lives) and DQ_LANE_POOL_REPO (the repository) for tests. tools/ci/test_lane_pool.sh runs this in a scratch repo.
# Exit status: 0 ok, 1 error, 3 pool full.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/dq_git_safe.sh"

POOL_SIZE="${DQ_LANE_POOL_SIZE:-8}"
COMPILER_SLOTS="${DQ_LANE_POOL_COMPILER:-2}"
POOL_DIR="${DQ_LANE_POOL_DIR:-E:/projects/dq-wt}"
STATE_DIR="${DQ_LANE_POOL_STATE:-E:/dq-cache/lane-pool}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${DQ_LANE_POOL_REPO:-$here}"
case "$POOL_SIZE" in ''|*[!0-9]*) echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2 ;; esac
[ "$POOL_SIZE" -ge 1 ] || { echo "dq_lane_pool: DQ_LANE_POOL_SIZE must be a positive integer" >&2; exit 2; }

die() { echo "dq_lane_pool: $*" >&2; exit "${DIE_CODE:-1}"; }
say() { echo "dq_lane_pool: $*" >&2; }

slot_path() { echo "$POOL_DIR/pool-$1"; }
slots_general() { seq 1 "$POOL_SIZE"; }
slots_compiler() { local k; for k in $(seq 1 "$COMPILER_SLOTS"); do echo "c$k"; done; }
slots_all() { slots_general; slots_compiler; echo light; }
slots_for_class() { # the slots a class may take, in the order it tries them
	case "$1" in
		compiler) slots_compiler; slots_general ;;
		light) echo light ;;
		*) slots_general ;;
	esac
}
lane_class() { # <branch> <explicit class or empty>
	case "${2:-}" in compiler|light|general) echo "$2"; return ;; '') ;; *) die "--class must be general, compiler or light" ;; esac
	case "$1" in tools/dmb*) echo compiler ;; *) echo general ;; esac
}
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
	# a CR-only difference (autocrlf / eol phantom: the index stat is stale but the content matches modulo CR) is not dirty
	git -C "$wt" diff --quiet --ignore-cr-at-eol HEAD -- >/dev/null 2>&1 || return 1 # --quiet honors the flag; --name-only does not
	[ -z "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null | head -n 1)" ]
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

RECLAIM_IDLE_MIN="${DQ_LANE_POOL_RECLAIM_IDLE_MIN:-180}"

slot_idle_minutes() { # <slot> <worktree>: minutes since the lease, the worktree's HEAD or its index last changed
	local gd newest=0 f m
	gd="$(git -C "$2" rev-parse --absolute-git-dir 2>/dev/null)"
	for f in "$(lease_file "$1")" "$gd/index" "$gd/HEAD" "$gd/logs/HEAD"; do
		[ -e "$f" ] || continue
		m="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
		[ "$m" -gt "$newest" ] && newest="$m"
	done
	echo $(( ($(date +%s) - newest) / 60 ))
}

reclaim_finished() { # called under the lock: drop leases whose lane is done
	local i wt branch idle_limit
	for i in $(slots_all); do
		[ -f "$(lease_file "$i")" ] || continue
		wt="$(slot_path "$i")"
		branch="$(lease_get "$i" branch)"
		if [ ! -d "$wt" ]; then rm -f "$(lease_file "$i")"; say "reclaimed pool-$i (worktree gone)"; continue; fi
		wt_clean "$wt" || continue
		if ! git -C "$REPO" show-ref -q --verify "refs/heads/$branch"; then
			release_slot "$i" 0 0; say "reclaimed pool-$i (branch $branch is gone)"; continue
		fi
		# A lane that lands several merges in a row (a wave per merge) is merged and clean between merges while its agent is still
		# working in the slot, so a merged lane is reclaimed only once nothing has touched its worktree for a while (or by release).
		idle_limit="$RECLAIM_IDLE_MIN"; [ "$i" = light ] && idle_limit="${DQ_LANE_POOL_LIGHT_IDLE_MIN:-30}"   # a light lane lasts minutes
		if [ "$(slot_idle_minutes "$i" "$wt")" -lt "$idle_limit" ]; then
			continue
		fi
		if merged_into_master "$REPO" "$branch" && [ "$(git -C "$REPO" rev-parse "refs/heads/$branch")" != "$(lease_get "$i" start)" ]; then
			# the lane committed (tip moved off its start) and all of it is in origin/master: finished. A lane that has not committed yet
			# also sits on a master ancestor, which is why the start commit is recorded.
			release_slot "$i" 0 0; say "reclaimed pool-$i (lane $branch is merged into origin/master)"
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
	local t pid
	for t in "$QUEUE_DIR"/*.ticket; do
		[ -e "$t" ] || continue
		pid="$(sed -n 's/^pid=//p' "$t" | head -n 1)"
		if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -f "$t"; fi
	done
}

queue_position() { # <ticket>: 1 when it is the oldest live ticket
	local n=0 t
	for t in $(ls "$QUEUE_DIR"/*.ticket 2>/dev/null | sort); do
		n=$((n + 1))
		[ "$t" = "$1" ] && { echo "$n"; return; }
	done
	echo 0
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
	class="$(lane_class "$branch" "$class")"
	args+=(--class "$class")
	case "$class" in
		light) QUEUE_DIR="$STATE_DIR/queue-light" ;;   # its own queue: the one shared slot never waits behind game lanes, nor they behind it
		compiler) prefix="0-" ;;                         # sorts ahead of the general tickets (plain timestamps) in the same dir
	esac
	[ "$wait" -eq 1 ] || { lease_once "${args[@]}"; return; }
	mkdir -p "$QUEUE_DIR"
	ticket="$QUEUE_DIR/${prefix}$(date +%s%N)-$$.ticket"
	printf 'pid=%s
branch=%s
since=%s
' "$$" "$branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ticket"
	trap 'rm -f "${ticket:-}"' EXIT
	start=$(date +%s)
	while :; do
		queue_prune
		pos="$(queue_position "$ticket")"
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
		if [ $(( $(date +%s) - start )) -ge $(( timeout_min * 60 )) ]; then
			say "gave up after $timeout_min minutes in the queue"; return 3
		fi
		sleep "${DQ_LANE_POOL_WAIT_POLL:-20}"
	done
}

lease_once() {
	local branch="" base="origin/master" i wt held=0 free="" skipped="" class="" nslots=0
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
	git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name"
	case "$branch" in master|main|rewrite/integ-current) die "'$branch' is not a lane branch" ;; esac
	class="$(lane_class "$branch" "$class")"

	git -C "$REPO" fetch -q origin || say "warning: git fetch failed; using the last fetched origin/master"
	git -C "$REPO" rev-parse -q --verify "$base" >/dev/null || die "no such base: $base"
	lock_take
	# A lane that already holds a slot gets it back.
	for i in $(slots_all); do
		if [ -f "$(lease_file "$i")" ] && [ "$(lease_get "$i" branch)" = "$branch" ]; then
			wt="$(slot_path "$i")"
			if [ -d "$wt" ] && [ "$(git -C "$wt" symbolic-ref -q --short HEAD)" = "$branch" ]; then
				lock_drop; say "$branch already holds pool-$i"; echo "$wt"; return 0
			fi
			rm -f "$(lease_file "$i")"  # a stale record: the worktree moved on
		fi
	done
	reclaim_finished
	for i in $(slots_for_class "$class"); do nslots=$((nslots + 1)); [ -f "$(lease_file "$i")" ] && held=$((held + 1)); done
	if [ "$nslots" -eq 0 ] || [ "$held" -ge "$nslots" ]; then
		echo "dq_lane_pool: POOL FULL ($class lanes): $held of $nslots worktrees are in use; at most $POOL_SIZE general lanes run at once (DQ_LANE_POOL_SIZE)." >&2
		for i in $(slots_for_class "$class"); do
			echo "  pool-$i: $(lease_get "$i" branch) since $(lease_get "$i" since) ($(lease_get "$i" owner))" >&2
		done
		echo "  Finish one lane (dq_lane_ready.sh, merge, then 'bash tools/dq_lane_pool.sh release <branch>') and ask again, or wait." >&2
		lock_drop
		return 3
	fi
	for i in $(slots_for_class "$class"); do
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
		echo "class=$class"
		echo "base=$base"
		echo "start=$(git -C "$wt" rev-parse HEAD)"
	} >"$(lease_file "$i")"
	lock_drop
	say "leased pool-$i ($class) to $branch ($(git -C "$wt" rev-parse --short HEAD) = $base); release with: bash tools/dq_lane_pool.sh release $branch"
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
	for i in $(slots_all); do
		[ -f "$(lease_file "$i")" ] || continue
		if [ "$(lease_get "$i" branch)" = "$target" ] || [ "$(slot_path "$i")" = "$target" ] || [ "$(cd "$(slot_path "$i")" 2>/dev/null && pwd)" = "$(cd "$target" 2>/dev/null && pwd)" ]; then found="$i"; break; fi
	done
	[ -n "$found" ] || { lock_drop; die "no lease for '$target' (dq_lane_pool.sh status)"; }
	release_slot "$found" "$force" "$keep"
	local rc=$?
	lock_drop
	# Cache hygiene, at most every 6 hours, detached: caps the shared caches and removes abandoned test scratch (tools/dq_cache_prune.sh).
	if [ -z "$(find "$STATE_DIR/prune.stamp" -mmin -360 2>/dev/null)" ] && [ -f "$REPO/tools/dq_cache_prune.sh" ]; then
		: >"$STATE_DIR/prune.stamp"
		( nohup bash "$REPO/tools/dq_cache_prune.sh" >"$STATE_DIR/prune.log" 2>&1 & ) >/dev/null 2>&1
	fi
	return "$rc"
}

cmd_status() {
	local i wt held=0
	echo "lane pool: $POOL_SIZE general + $COMPILER_SLOTS compiler + light slot(s) under $POOL_DIR (state $STATE_DIR)"
	for i in $(slots_all); do
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
	echo "  $held leased"
	queue_prune
	local t n=0
	for t in $(ls "$QUEUE_DIR"/*.ticket 2>/dev/null | sort); do
		n=$((n + 1))
		echo "  queue $n: $(sed -n 's/^branch=//p' "$t") since $(sed -n 's/^since=//p' "$t")"
	done
	QUEUE_DIR="$STATE_DIR/queue-light"; queue_prune; n=0
	for t in $(ls "$QUEUE_DIR"/*.ticket 2>/dev/null | sort); do
		n=$((n + 1))
		echo "  light queue $n: $(sed -n 's/^branch=//p' "$t") since $(sed -n 's/^since=//p' "$t")"
	done
	[ -d "$STATE_DIR/light-queue" ] && for t in "$STATE_DIR"/light-queue/*.q; do [ -e "$t" ] && echo "  waiting to land (bash tools/dq_land.sh --light): $(sed -n 's/^branch=//p' "$t")"; done
	return 0
}

cmd_path() {
	local i
	for i in $(slots_all); do
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
