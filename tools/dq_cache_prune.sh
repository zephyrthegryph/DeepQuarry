#!/usr/bin/env bash
# Prunes the content-addressed caches under E:/dq-cache that only ever grew (each entry is rebuilt on a miss, so pruning is always safe):
#
#   bash tools/dq_cache_prune.sh [--dry-run]
#
#   analyze-bin/<source hash>/analyze.exe   keep the newest DQ_ANALYZE_KEEP (default 12) and every key a live worktree's binary was built from
#                                            (a 15 MB binary per analyzer source change had grown to 6.3 GB)
#   analyze-cache/<stamp>/                  the analyzer's shared per-file results: newest DQ_ANALYZE_SHARED_KEEP (4) directories, DQ_ANALYZE_SHARED_MAX_MB (4096) MB
#   tree-proofs/<tree>.proof                keep the newest DQ_PROOF_KEEP (default 200); tools/dq_merge_gates.sh prunes them too
#   look-manifest/<digest>.tsv              keep the newest DQ_LOOK_MANIFEST_KEEP (default 6)
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
# analyze-cache/<stamp key>/  the per-file results every worktree's analyzer shares (tools/analyze/src/shared.rs): keep the DQ_ANALYZE_SHARED_KEEP
# (default 4) most recently used stamp directories and at most DQ_ANALYZE_SHARED_MAX_MB (default 4096) MB, never the newest one; leftover scratch
# files an interrupted copy made go too. "Used" is the mtime of each directory's .used file (touched by every seed and publish).
sc="${DQ_ANALYZE_SHARED_CACHE:-$CACHE/analyze-cache}"
if [ -d "$sc" ]; then
	skeep="${DQ_ANALYZE_SHARED_KEEP:-4}"
	smax_kb=$(( ${DQ_ANALYZE_SHARED_MAX_MB:-4096} * 1024 ))
	n=0; total_kb=0
	while IFS= read -r d; do
		d="${d%/}"
		case "$(basename "$d")" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;; *) continue ;; esac
		[ "$dry" -eq 1 ] || find "$d" -name '*.tmp*' -mmin +60 -delete 2>/dev/null
		n=$((n + 1))
		kb="$(du -sk "$d" 2>/dev/null | cut -f1)"
		total_kb=$((total_kb + ${kb:-0}))
		# The newest directory (n = 1) is always kept.
		if [ "$n" -gt 1 ] && { [ "$n" -gt "$skeep" ] || [ "$total_kb" -gt "$smax_kb" ]; }; then
			total_kb=$((total_kb - ${kb:-0}))
			rm_path "$d"
		fi
	done < <(ls -dt "$sc"/*/ 2>/dev/null | while read -r x; do echo "$(stat -c %Y "$x/.used" 2>/dev/null || stat -c %Y "$x") $x"; done | sort -rn | cut -d' ' -f2-)
	echo "analyze-cache: $(ls -d "$sc"/*/ 2>/dev/null | wc -l) stamp dirs kept, $(( $(du -sk "$sc" | cut -f1) / 1024 )) MB$([ "$dry" -eq 1 ] && echo ' (dry run: nothing removed)')"
fi
prune_newest() { # <dir> <glob> <keep>
	[ -d "$1" ] || return 0
	ls -t "$1"/$2 2>/dev/null | tail -n +"$(( $3 + 1 ))" | while read -r f; do rm_path "$f"; [ "$dry" -eq 1 ] || rm -f "${f%.proof}.tests.json"; done
}
prune_newest "${DQ_PROOF_DIR:-$CACHE/tree-proofs}" '*.proof' "${DQ_PROOF_KEEP:-200}"
prune_newest "${DQ_LOOK_MANIFEST_DIR:-$CACHE/look-manifest}" '*.tsv' "${DQ_LOOK_MANIFEST_KEEP:-6}"
