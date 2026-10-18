#!/usr/bin/env bash
# Prunes the content-addressed caches under E:/dq-cache that only ever grew (each entry is rebuilt on a miss, so pruning is always safe):
#
#   bash tools/dq_cache_prune.sh [--dry-run]
#
#   analyze-bin/<source hash>/analyze.exe   keep the newest DQ_ANALYZE_KEEP (default 12) and every key a live worktree's binary was built from
#                                            (a 15 MB binary per analyzer source change had grown to 6.3 GB)
#   tree-proofs/<tree>.proof                keep the newest DQ_PROOF_KEEP (default 200); tools/dq_merge_gates.sh prunes them too
#   look-manifest/<digest>.tsv              keep the newest DQ_LOOK_MANIFEST_KEEP (default 6)
#   dmb-bin/v/<id>/                        compiler versions: keep `current` and the newest DQ_DMB_VERSION_KEEP (default 1) other; a version a running
#                                            daemon or compile holds cannot be deleted on Windows and stays until the next run
#   dmbd/cache (per-file dmbc caches)       `dmbc --cache-gc`: size cap DMB_CACHE_BUDGET_GB (default 16), age cap DMB_CACHE_MAX_AGE_DAYS (default 14),
#                                            least recently used first (a dmbc daemon runs the same pass every 6 hours by itself)
#   dmb-dev/<hash>/                        private compiler-development builds untouched for DQ_DMB_DEV_DAYS (default 14)
# Run by hand or from the pool's release; nothing here touches a worktree, .git or a lock.
set -uo pipefail
dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
CACHE="${DQ_CACHE_ROOT:-E:/dq-cache}"
WT_ROOT="${DQ_WT_ROOT:-E:/projects/dq-wt}"
rm_path() { if [ "$dry" -eq 1 ]; then echo "would remove $1"; else rm -rf "$1"; fi; }

ab="${DQ_ANALYZE_CACHE:-$CACHE/analyze-bin}"
if [ -d "$ab" ]; then
	keep="${DQ_ANALYZE_KEEP:-12}"
	live="$(ls "$WT_ROOT"/*/tools/analyze/target/*/analyze*.key "$WT_ROOT"/../CHOMPStation2/tools/analyze/target/*/analyze*.key 2>/dev/null | xargs -r cat 2>/dev/null | tr -d '\r' | sort -u)"
	before="$(du -sk "$ab" 2>/dev/null | cut -f1)"
	n=0
	while IFS= read -r d; do
		k="$(basename "$d")"
		n=$((n + 1))
		[ "$n" -le "$keep" ] && continue
		grep -qx "$k" <<<"$live" && continue
		rm_path "$d"
	done < <(ls -dt "$ab"/*/ 2>/dev/null | sed 's#/$##')
	echo "analyze-bin: $(ls -d "$ab"/*/ 2>/dev/null | wc -l) entries kept; $(( before / 1024 )) MB before, $(( $(du -sk "$ab" | cut -f1) / 1024 )) MB after$([ "$dry" -eq 1 ] && echo ' (dry run: nothing removed)')"
fi
prune_newest() { # <dir> <glob> <keep>
	[ -d "$1" ] || return 0
	ls -t "$1"/$2 2>/dev/null | tail -n +"$(( $3 + 1 ))" | while read -r f; do rm_path "$f"; [ "$dry" -eq 1 ] || rm -f "${f%.proof}.tests.json"; done
}
prune_newest "${DQ_PROOF_DIR:-$CACHE/tree-proofs}" '*.proof' "${DQ_PROOF_KEEP:-200}"
prune_newest "${DQ_LOOK_MANIFEST_DIR:-$CACHE/look-manifest}" '*.tsv' "${DQ_LOOK_MANIFEST_KEEP:-6}"

# Compiler versions: one latest compiler for everyone, so only `current` and the version just superseded are worth keeping.
bin="${DQ_DMBC_BIN_DIR:-$CACHE/dmb-bin}"
if [ -d "$bin/v" ]; then
	cur="$(cat "$bin/current" 2>/dev/null | tr -d '\r\n ')"
	keep="${DQ_DMB_VERSION_KEEP:-1}"
	before="$(du -sk "$bin" 2>/dev/null | cut -f1)"
	n=0
	while IFS= read -r d; do
		id="$(basename "$d")"
		[ "$id" = "$cur" ] && continue
		case "$id" in .tmp-*) [ -n "$(find "$d" -maxdepth 0 -mmin +10 2>/dev/null)" ] && rm_path "$d"; continue ;; esac
		n=$((n + 1))
		[ "$n" -le "$keep" ] && continue
		rm_path "$d" 2>/dev/null || true
	done < <(ls -dt "$bin"/v/*/ 2>/dev/null | sed 's#/$##')
	rm_path "$bin/by-key"; rm_path "$bin/by-tree"
	echo "dmb-bin: $(ls -d "$bin"/v/*/ 2>/dev/null | wc -l) versions (current $cur); $(( before / 1024 )) MB before, $(( $(du -sk "$bin" | cut -f1) / 1024 )) MB after$([ "$dry" -eq 1 ] && echo ' (dry run: nothing removed)')"
fi
# Per-file dmbc caches: size and age caps by recency of use (the compiler does the work; nothing here reads a cache file).
if [ "$dry" -eq 0 ] && [ -f "$bin/current" ]; then
	exe="$bin/v/$(cat "$bin/current" | tr -d '\r\n ')/dmbc.exe"
	[ -f "$exe" ] || exe="$bin/v/$(cat "$bin/current" | tr -d '\r\n ')/dmbc"
	[ -f "$exe" ] && "$exe" --cache-gc 2>&1 | tail -1
fi
dd="${DQ_DMB_DEV_ROOT:-$CACHE/dmb-dev}"
if [ -d "$dd" ]; then
	find "$dd" -mindepth 1 -maxdepth 1 -type d -mtime +"${DQ_DMB_DEV_DAYS:-14}" 2>/dev/null | while read -r d; do rm_path "$d"; done
fi
