#!/usr/bin/env bash
# Publish the compiler (tools/dmb) and the lint engine (tools/analyze) after a push that changed them, so no later gate or focused
# run builds either on its critical path. Usage: bash tools/dq_prebuild_tools.sh <old-sha> <new-sha>   (run from a clean checkout of <new-sha>)
# Detached: returns at once. Both builds go through the build tool's own targets (build.sh dmbc / analyze-build), which publish into the
# shared content-addressed caches (E:/dq-cache/dmb-bin/v/<id>, E:/dq-cache/analyze-bin) under the machine-wide cargo slot, so a second
# builder (a gate that started meanwhile) queues on the slot, finds the shared cargo target current and publishes the same id in seconds
# instead of rebuilding. DQ_PREBUILD_TOOLS=0 disables it. Log: data/prebuild-tools/<sha>.log.
set -u
old="${1:?old sha}"; new="${2:?new sha}"
[ "${DQ_PREBUILD_TOOLS:-1}" = "0" ] && exit 0
cd "$(git rev-parse --show-toplevel)" || exit 1
changed="$(git diff --name-only "$old" "$new" -- tools/dmb tools/analyze 2>/dev/null)"
[ -n "$changed" ] || { echo "dq_prebuild_tools: neither tools/dmb nor tools/analyze changed; nothing to publish"; exit 0; }
want=()
grep -q '^tools/dmb/' <<<"$changed" && want+=(dmbc)
grep -q '^tools/analyze/' <<<"$changed" && want+=(analyze-build)
mkdir -p data/prebuild-tools
log="data/prebuild-tools/${new:0:12}.log"
echo "dq_prebuild_tools: publishing ${want[*]} for ${new:0:12} in the background; log $log"
# The analyzer builds in a cache-root target (tools/dq_cargo_target.sh), never in this checkout's tools/analyze/target, so the merge
# worktree keeps no multi-GB build directory; dmbc already builds in the shared dmb-build target. Pruned by tools/dq_cache_prune.sh.
export DQ_ANALYZE_TARGET="${DQ_ANALYZE_TARGET:-$(bash tools/dq_cargo_target.sh analyze)}"
( nohup bash -c 'for t in "$@"; do echo "== build.sh $t $(date -u +%FT%TZ)"; bash tools/build/build.sh "$t" || echo "prebuild $t failed rc=$?"; done; echo "== done $(date -u +%FT%TZ)"' _ "${want[@]}" >"$log" 2>&1 & ) 
exit 0
