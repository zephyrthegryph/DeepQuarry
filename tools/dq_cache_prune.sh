#!/usr/bin/env bash
# Prunes the content-addressed caches under E:/dq-cache that only ever grew (each entry is rebuilt on a miss, so pruning is always safe):
#
#   bash tools/dq_cache_prune.sh [--dry-run]
#
#   analyze-bin/<source hash>/analyze.exe   keep the newest DQ_ANALYZE_KEEP (default 12) and every key a live worktree's binary was built from
#                                            (a 15 MB binary per analyzer source change had grown to 6.3 GB)
#   analyze-cache/<stamp>/                  the analyzer's shared per-file results: newest DQ_ANALYZE_SHARED_KEEP (4) directories, DQ_ANALYZE_SHARED_MAX_MB (4096) MB
#   tree-proofs/<tree>.proof                keep the newest DQ_PROOF_KEEP (default 200); tools/dq_merge_gates.sh prunes them too
#   dmb-bin/v/<id>/                        compiler versions: keep `current` and the newest DQ_DMB_VERSION_KEEP (default 1) other; a version a running
#                                            daemon or compile holds cannot be deleted on Windows and stays until the next run
#   dmbd/cache (per-file dmbc caches)       `dmbc --cache-gc`: size cap DMB_CACHE_BUDGET_GB (default 16), age cap DMB_CACHE_MAX_AGE_DAYS (default 14),
#                                            least recently used first (a dmbc daemon runs the same pass every 10 minutes by itself, and every process that wrote past DMB_CACHE_PASS_WRITE_MB runs one)
#   cargo-targets/<worktree>/<name>/       the cargo targets gates, pushes and prebuilds use (tools/dq_cargo_target.sh): incremental state is always removed, and a
#                                            target over DQ_CARGO_TARGET_MAX_GB (default 12) or idle DQ_CARGO_TARGET_DAYS (default 3) days is removed whole
#   dmb-dev/<hash>/                        private compiler-development builds untouched for DQ_DMB_DEV_DAYS (default 14)
# Run by hand or from the pool's release; nothing here touches a worktree, .git or a lock.
set -uo pipefail
dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
CACHE="${DQ_CACHE_ROOT:-E:/dq-cache}"
WT_ROOT="${DQ_WT_ROOT:-E:/projects/dq-wt}"
rm_path() { if [ "$dry" -eq 1 ]; then echo "would remove $1"; else rm -rf "$1"; fi; }

ab="${DQ_ANALYZE_BIN_CACHE:-$CACHE/analyze-bin}"
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

# Compiler versions: one latest compiler for everyone, so only `current` and the version just superseded are worth keeping.
bin="${DQ_DMBC_BIN_DIR:-$CACHE/dmb-bin}"
if [ -d "$bin/v" ]; then
	cur="$(cat "$bin/current" 2>/dev/null | tr -d '\r\n')"
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
	exe="$bin/v/$(cat "$bin/current" | tr -d '\r\n')/dmbc.exe"
	[ -f "$exe" ] || exe="$bin/v/$(cat "$bin/current" | tr -d '\r\n')/dmbc"
	[ -f "$exe" ] && "$exe" --cache-gc 2>&1 | tail -1
fi
# Cargo targets of gates/pushes/prebuilds (measured by summing file sizes, never du).
ct="${DQ_CARGO_TARGETS:-$CACHE/cargo-targets}"
if [ -d "$ct" ]; then
	find "$ct" -mindepth 3 -maxdepth 5 -type d -name incremental 2>/dev/null | while read -r d; do rm_path "$d"; done
	for d in "$ct"/*/*/; do
		d="${d%/}"; [ -d "$d" ] || continue
		kb="$(find "$d" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%d", s/1024}')"
		if [ "${kb:-0}" -gt $(( ${DQ_CARGO_TARGET_MAX_GB:-12} * 1024 * 1024 )) ] || [ -n "$(find "$d" -maxdepth 0 -mtime +"${DQ_CARGO_TARGET_DAYS:-3}" 2>/dev/null)" ]; then
			echo "cargo-targets: removing $d ($(( ${kb:-0} / 1024 )) MB)"; rm_path "$d"
		fi
	done
fi
dd="${DQ_DMB_DEV_ROOT:-$CACHE/dmb-dev}"
if [ -d "$dd" ]; then
	find "$dd" -mindepth 1 -maxdepth 1 -type d -mtime +"${DQ_DMB_DEV_DAYS:-14}" 2>/dev/null | while read -r d; do rm_path "$d"; done
fi

# Abandoned test scratch. Tests put their stores under E:/dq-cache/test-scratch/run-<pid>-<ms>/ and delete that on exit (tools/dmb/shared/test_scratch.rs);
# a run that died hard, and the older per-run directories the tests used to leave in the roots below, are collected here: a child directory goes when
# nothing in it changed for DQ_TEST_SCRATCH_DAYS (default 1) days and the pid in its name (if it has one) is no longer a running process.
# Never touched: dmbc/, dmb-roots/, dmb-bin/, lane-pool/, slots/, analyze-*, gen-store/ (the daemon's real stores are capped by `dmbc --cache-gc`).
pid_table=""
live_pids() { [ -n "$pid_table" ] || pid_table="$(tasklist //NH //FO CSV 2>/dev/null | cut -d, -f2 | tr -d '"\r' | sort -u; echo end)"; echo "$pid_table"; }
scratch_idle_days="${DQ_TEST_SCRATCH_DAYS:-1}"
removed_dirs=0; removed_files=0
sweep_children() { # <root> [child-glob]
	local root="$1" glob="${2:-*}" d name pid
	[ -d "$root" ] || return 0
	while IFS= read -r d; do
		d="${d%/}"; name="$(basename "$d")"
		[ -n "$(find "$d" -mmin -$(( scratch_idle_days * 1440 )) -print -quit 2>/dev/null)" ] && continue
		pid="$(sed -n -E 's/^(run-)?(.*-)?([0-9]{2,})-[0-9]+(-.*)?$/\3/p; t; s/^(.*-)?([0-9]{2,})$/\2/p' <<<"$name" | head -1)"
		if [ -n "$pid" ] && live_pids | grep -qx "$pid"; then continue; fi
		removed_dirs=$((removed_dirs + 1))
		removed_files=$((removed_files + $(find "$d" -type f 2>/dev/null | wc -l)))
		rm_path "$d"
	done < <(ls -d "$root"/$glob/ 2>/dev/null)
}
sweep_children "$CACHE/test-scratch" 'run-*'
for r in dmb-protocol-checks dmb-abi-disk-tests dmb-disk-only-tests dmb-publication-proof-tests dmb-shadow dmb-build-integration dmbb dmbc-pool1; do
	sweep_children "$CACHE/$r"
done
for r in callable-fallback-tests variable-negative-tests contract-tests; do sweep_children "$CACHE/dmb-native-v2/$r"; done
for t in "$CACHE"/dmt-*/; do [ -d "$t" ] && sweep_children "$t"; done
# Top-level dmt-* scratch directories that are themselves idle (a codex tool's per-experiment roots) go whole once nothing under them changed.
for t in "$CACHE"/dmt-*/; do
	t="${t%/}"; [ -d "$t" ] || continue
	[ -n "$(find "$t" -mmin -$(( scratch_idle_days * 1440 )) -print -quit 2>/dev/null)" ] && continue
	removed_dirs=$((removed_dirs + 1)); removed_files=$((removed_files + $(find "$t" -type f 2>/dev/null | wc -l))); rm_path "$t"
done
echo "test scratch: $removed_dirs abandoned directories ($removed_files files)$([ "$dry" -eq 1 ] && echo ' would be removed (dry run)' || echo ' removed')"

# dqp-cache: size and age capped like the other file caches (least recently modified file first). Nothing in this repository creates it; whatever
# tool does, this keeps it bounded: DQ_DQP_CACHE_MAX_MB (default 2048) and DQ_DQP_CACHE_DAYS (default 7).
dq="${DQ_DQP_CACHE:-$CACHE/dqp-cache}"
if [ -d "$dq" ]; then
	find "$dq" -type f -mtime +"${DQ_DQP_CACHE_DAYS:-7}" 2>/dev/null | while read -r f; do rm_path "$f"; done
	max_kb=$(( ${DQ_DQP_CACHE_MAX_MB:-2048} * 1024 )); total_kb=0
	while IFS=$'\t' read -r kb f; do
		total_kb=$((total_kb + kb))
		[ "$total_kb" -gt "$max_kb" ] && rm_path "$f"
	done < <(find "$dq" -type f -printf '%T@\t%k\t%p\n' 2>/dev/null | sort -rn | awk -F'\t' '{print $2 "\t" $3}')
	echo "dqp-cache: capped at ${DQ_DQP_CACHE_MAX_MB:-2048} MB / ${DQ_DQP_CACHE_DAYS:-7} days"
fi
