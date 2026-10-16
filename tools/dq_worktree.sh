#!/usr/bin/env bash
# Worktree hygiene (AGENTS.md section 4). Worktrees live under E:/projects/dq-wt, caches under E:/dq-cache, nothing in .git.
#   bash tools/dq_worktree.sh lease <branch>          a LANE's worktree: one of DQ_LANE_POOL_SIZE (3) pooled worktrees, E:/projects/dq-wt/pool-N
#   bash tools/dq_worktree.sh release <branch>        give it back (daemon retired, build outputs dropped; tools/dq_lane_pool.sh has the rules)
#   bash tools/dq_worktree.sh pool                    who holds which pool slot
#   bash tools/dq_worktree.sh new <name> [base-ref]   a NON-lane worktree E:/projects/dq-wt/<name> on a new branch <name> from origin/master
#   bash tools/dq_worktree.sh gc [--dry-run]          remove every worktree that is clean and merged into origin/master
#   bash tools/dq_worktree.sh status                  free space, worktree count, merged+clean per worktree
# `new` refuses when more than DQ_WT_MAX (8) worktrees exist or E: has under DQ_WT_MIN_FREE_GB (60) GB free: run `gc` first.
set -uo pipefail
# `gc` never removes the main checkout, the current worktree or a name in DQ_WT_KEEP (space separated), and never uses --force.
WT_ROOT="${DQ_WT_ROOT:-E:/projects/dq-wt}"
MAX="${DQ_WT_MAX:-8}"; MIN_FREE="${DQ_WT_MIN_FREE_GB:-60}"
die() { echo "dq_worktree: $*" >&2; exit 1; }
main="$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"
here="$(git rev-parse --show-toplevel)"
free_gb() { df -Pk "$WT_ROOT" 2>/dev/null | awk 'NR==2{printf "%d", $4/1048576}'; }
wts() { git -C "$main" worktree list --porcelain | awk -v r="$(echo "$WT_ROOT/" | tr 'A-Z' 'a-z')" '/^worktree /{p=substr($0,10); if (index(tolower(p), r)==1) print p}';  }
# Delete build targets and unlink junctions first; git must never recurse through a junction into shared data.
strip() {
	local d="$1" t
	for t in tools/dmb/target tools/analyze/target verdigris/target; do rm -rf "$d/$t"; done
	for t in "$d"/node_modules "$d"/tgui/node_modules "$d"/tgui/packages/*/node_modules; do
		[ -L "$t" ] || { [ -d "$t" ] && cmd //c "fsutil reparsepoint query \"$(cygpath -w "$t")\"" >/dev/null 2>&1 && cmd //c "rmdir \"$(cygpath -w "$t")\"" >/dev/null 2>&1; }
		[ -L "$t" ] && rm -f "$t"
	done
}
merged_clean() { # <dir>
	local d="$1" sha
	[ -z "$(git -C "$d" status --porcelain --untracked-files=normal 2>/dev/null)" ] || return 1
	sha="$(git -C "$d" rev-parse HEAD 2>/dev/null)" || return 1
	git -C "$main" merge-base --is-ancestor "$sha" origin/master
}
cmd_gc() {
	local dry=0 d n removed=0; [ "${1:-}" = "--dry-run" ] && dry=1
	git -C "$main" fetch -q origin 2>/dev/null
	while IFS= read -r d; do
		n="$(basename "$d")"
		[ "$(cd "$d" && pwd -P)" = "$(cd "$here" && pwd -P)" ] && continue
		case "$n" in pool-[0-9]*) continue ;; esac  # pool slots are permanent: tools/dq_lane_pool.sh leases and releases them
		case " ${DQ_WT_KEEP:-} " in *" $n "*) echo "keep  $n (DQ_WT_KEEP)"; continue ;; esac
		if merged_clean "$d"; then
			if [ "$dry" = 1 ]; then echo "would remove $n"; continue; fi
			strip "$d"
			if git -C "$main" worktree remove "$d" 2>/dev/null; then echo "removed $n"; removed=$((removed+1)); else echo "skip  $n (git refused; in use?)"; fi
		else echo "skip  $n (dirty or unmerged)"; fi
	done < <(wts)
	git -C "$main" worktree prune
	echo "dq_worktree: removed $removed; E: free $(free_gb) GB"
}
cmd_new() {
	local name="${1:-}" base="${2:-origin/master}" count
	[ -n "$name" ] || die "usage: new <name> [base-ref]"
	[ -n "${DQ_WT_ALLOW_LANE_NEW:-}" ] || echo "dq_worktree: note: a lane gets its worktree with 'lease <branch>' (the pool, at most 3 lanes); 'new' is for non-lane worktrees" >&2
	count="$(wts | wc -l)"
	[ "$count" -lt "$MAX" ] || die "$count worktrees already exist (cap $MAX); run: bash tools/dq_worktree.sh gc, or remove one by hand"
	[ "$(free_gb)" -ge "$MIN_FREE" ] || die "E: has $(free_gb) GB free (need $MIN_FREE); run: bash tools/dq_worktree.sh gc"
	git -C "$main" worktree add -b "$name" "$WT_ROOT/${name//\//-}" "$base"
}
cmd_status() {
	echo "E: free $(free_gb) GB; worktrees: $(wts | wc -l) (cap $MAX)"
	git -C "$main" fetch -q origin 2>/dev/null
	while IFS= read -r d; do echo "$(basename "$d") $(merged_clean "$d" && echo merged+clean || echo keep)"; done < <(wts)
}
case "${1:-}" in lease|release) c="$1"; shift; exec bash "$(dirname "${BASH_SOURCE[0]}")/dq_lane_pool.sh" "$c" "$@" ;; pool) exec bash "$(dirname "${BASH_SOURCE[0]}")/dq_lane_pool.sh" status ;; new) shift; cmd_new "$@" ;; gc) shift; cmd_gc "$@" ;; status) cmd_status ;; *) die "usage: lease|release|pool|new|gc|status" ;; esac
