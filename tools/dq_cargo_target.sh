#!/usr/bin/env bash
# Prints the cargo target directory a gate, push, prebuild or equivalence run must build into instead of <worktree>/tools/*/target:
#   export CARGO_TARGET_DIR="$(bash tools/dq_cargo_target.sh <name>)"
# It lives under the disposable cache root (E:/dq-cache/cargo-targets/<worktree>/<name>, else ~/.cache/dq/cargo-targets), one per worktree and
# name (cargo's fingerprints are path-relative, so two checkouts must not share one), and tools/dq_cache_prune.sh caps it
# (DQ_CARGO_TARGET_MAX_GB, default 12 per directory; incremental state always goes). Nothing is created here.
set -u
name="${1:?usage: dq_cargo_target.sh <name>}"
if [ -n "${DQ_CARGO_TARGETS:-}" ]; then root="$DQ_CARGO_TARGETS"
elif [ -d E:/dq-cache ]; then root="E:/dq-cache/cargo-targets"
else root="$HOME/.cache/dq/cargo-targets"; fi
wt="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
echo "$root/$wt/$name"
